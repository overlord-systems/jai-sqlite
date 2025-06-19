#import "Math";

#if OS == .WINDOWS {
    #load "windows/windows.jai";
} else #if OS == .MACOS {
    #load "macos/macos.jai";
} else #if OS == .LINUX {
    #load "linux/linux.jai";
}

// Calls sqlite3_errmsg.
//
// The returned string is owned by sqlite and only valid until the next sqlite call.
get_sqlite_error :: (db: *sqlite3) -> string {
    err := sqlite3_errmsg(db);
    if !err return "";
    return to_string(err);
}

// The caller is always responsible for freeing the returned rows, even in the case of success=false.
sqlite3_exec_query :: (
    db: *sqlite3,
    $Row_Type: Type,
    sql: string,
    params: ..Any,
    ignore_unknown_columns := false
) -> success: bool, rows : []Row_Type, sqlite_status: s32 {

    auto_release_temp();

    // Prepare statement
    stmt: *sqlite3_stmt;
    defer {
        if stmt {
            sqlite3_finalize(stmt);
        }
    }

    c_sql := temp_c_string(sql);    // Its faster if we pass a null-terminated string
    status := sqlite3_prepare_v2(db, c_sql, (sql.count+1).(s32), *stmt, null);
    if status != SQLITE_OK {
        log("failed to parse sql query with err = % and query = %", get_sqlite_error(db), sql, flags=.ERROR);
        return false, .[], status;
    }

    // Do some validations
    stmt_param_count := sqlite3_bind_parameter_count(stmt);
    if stmt_param_count != params.count {
        log("failed to execute sql query because the query requires % params but we got % params for query = %", stmt_param_count, params.count, sql, flags=.ERROR);
        return false, .[], SQLITE_ERROR;
    }

    // Bind params
    success, status= := bind_sqlite_params(db, stmt, sql, ..params);
    if !success {
        return false, .[], status;
    }

    //
    // Execute stmt and parse rows
    //

    // We need to call this at least once before trying to get column info.
    step_status := sqlite3_step(stmt);
    if step_status != SQLITE_ROW && step_status != SQLITE_DONE {
        log("failed to execute sql query with status code=% and error = % in query = %", step_status, get_sqlite_error(db), sql, flags=.ERROR);
        return false, .[], step_status;
    }

    // We process column names and column types once so we can use them for each row.
    //
    // Note: Columns are valid as long as we don't finalize the stmt or use sqlite3_column_name()
    // again on the same column.
    col_count := sqlite3_column_count(stmt);
    col_names: [..]string;
    col_names.allocator = temp;

    if step_status == SQLITE_ROW && col_count {

        array_reserve(*col_names, col_count);
        for 0..col_count-1 {

            name := sqlite3_column_name(stmt, it);
            array_add(*col_names, to_string(name));
        }
    }

    // Get rows one at a time, and for each parse into Row_Type by
    // looping over each column, finding a member in the row type struct with the same name,
    // then parsing into that field if supported, or otherwise returning early if a failure
    // happens or we have a type mismatch between column type and struct type.
    rows: [..]Row_Type;
    ti := type_info(Row_Type);
    while step_status == SQLITE_ROW {

        defer step_status = sqlite3_step(stmt);

        // In rare cases the columns returned for a row might be zero so we check
        col_count := sqlite3_data_count(stmt);
        if !col_count continue;

        array_add(*rows, .{});
        row := *rows[rows.count-1];
        row_as_bytes := row.(*u8);
        for col: col_names {

            col_index := it_index.(s32);
            col_type := sqlite3_column_type(stmt, col_index);

            if col_type == SQLITE_NULL {
                continue;
            }

            // @TODO: @PERF: cache get_field results before parsing rows
            // Find member with the same name as this column
            member, offset_in_bytes := get_field(ti, col);
            if !member {

                if !ignore_unknown_columns {
                    log("failed to parse query row into type=% because column=% doesn't exist in the type in query = %", Row_Type, col, sql, flags=.ERROR);
                    return false, rows, SQLITE_ERROR;
                }

                continue;
            }

            // Parse column value into member
            member_type := member.type.type;
            member_slot : *void = row_as_bytes + offset_in_bytes;
            if member_type == {

                case .ENUM; #through;
                case .INTEGER;

                    if col_type != SQLITE_INTEGER {
                        log("failed to parse column=% of sqlite_type=% into member=% of type=integer/enum because of type mismatch in query = %", col, col_type, member.name, sql, flags=.ERROR);
                        return false, rows, SQLITE_ERROR;
                    }

                    // @TODO: We should protect against overflows (which would crash us) similar
                    // to how we protect against them when binding.
                    col_val := sqlite3_column_int64(stmt, col_index);
                    if member.type.runtime_size == 1
                        member_slot.(*s8).* = col_val.(s8);
                    else if member.type.runtime_size == 2
                        member_slot.(*s16).* = col_val.(s16);
                    else if member.type.runtime_size == 4
                        member_slot.(*s32).* = col_val.(s32);
                    else
                        member_slot.(*s64).* = col_val;

                case .FLOAT;

                    if col_type != SQLITE_FLOAT {
                        log("failed to parse column=% of sqlite_type=% into member=% of type=float/float64 because of type mismatch in query = %", col, col_type, member.name, sql, flags=.ERROR);
                        return false, rows, SQLITE_ERROR;
                    }

                    col_val := sqlite3_column_double(stmt, col_index);
                    if member.type.runtime_size == 4
                        member_slot.(*float).* = col_val.(float);
                    else
                        member_slot.(*float64).* = col_val;

                case .STRING;

                    if col_type != SQLITE_TEXT {
                        log("failed to parse column=% of sqlite_type=% into member=% of type=string because of type mismatch in query = %", col, col_type, member.name, sql, flags=.ERROR);
                        return false, rows, SQLITE_ERROR;
                    }

                    // Count does NOT include the null terminator, but strings are always
                    // returned with null terminator, even empty ones.
                    //
                    // The string we return includes the null terminator.
                    //
                    // If null, count will be zero.
                    col_val := sqlite3_column_text(stmt, col_index);
                    count := sqlite3_column_bytes(stmt, col_index);

                    copied_string := ifx col_val copy_string(to_string(col_val, count+1)) else "";
                    if copied_string.count copied_string.count -= 1;

                    member_slot.(*string).* = copied_string;

                case .BOOL;

                    if col_type != SQLITE_INTEGER {
                        log("failed to parse column=% of sqlite_type=% into member=% of type=bool because of type mismatch in query = %", col, col_type, member.name, sql, flags=.ERROR);
                        return false, rows, SQLITE_ERROR;
                    }

                    col_val := sqlite3_column_int(stmt, col_index);
                    member_slot.(*bool).* = col_val != 0;

                case;
                    log("failed to parse column=% of sqlite_type=% into member=% of type=% because this member type isn't supported in query = %", col, col_type, member.name, member_type, sql, flags=.ERROR);
                    return false, rows, SQLITE_ERROR;
            }
        }
    }

    return step_status == SQLITE_DONE, rows, step_status;
}

sqlite3_exec_query :: (db: *sqlite3, sql: string, params: ..Any) -> success: bool, updated_rows := 0, sqlite_status: s32 {

    auto_release_temp();

    // Prepare statement
    stmt: *sqlite3_stmt;
    defer {
        if stmt {
            sqlite3_finalize(stmt);
        }
    }

    c_sql := temp_c_string(sql);    // Its faster if we pass a null-terminated string
    status := sqlite3_prepare_v2(db, c_sql, (sql.count+1).(s32), *stmt, null);
    if status != SQLITE_OK {
        log("failed to parse sql query with err = % and query = %", get_sqlite_error(db), sql, flags=.ERROR);
        return false, sqlite_status=status;
    }

    // Do some validations
    stmt_param_count := sqlite3_bind_parameter_count(stmt);
    if stmt_param_count != params.count {
        log("failed to execute sql query because the query requires % params but we got % params for query = %", stmt_param_count, params.count, sql, flags=.ERROR);
        return false, sqlite_status=SQLITE_ERROR;
    }

    // Bind params
    success, status= := bind_sqlite_params(db, stmt, sql, ..params);
    if !success {
        return false, sqlite_status=status;
    }

    // Reach done or error state
    step_status := sqlite3_step(stmt);
    while step_status == SQLITE_ROW {
        step_status = sqlite3_step(stmt);
    }

    rows_changed := sqlite3_changes64(db);
    return step_status == SQLITE_DONE, rows_changed, step_status;
}

bind_sqlite_params :: (db: *sqlite3, stmt: *sqlite3_stmt, sql: string, params: ..Any) -> success: bool, sqlite_status: s32 {

    for param: params {

        // Param indices start at 1
        param_index := it_index.(s32) + 1;

        status: s32;
        if param.type.type == {

            case .ENUM; #through;
            case .INTEGER;

                info := ifx param.type.type == .ENUM then param.type.(*Type_Info_Enum).internal_type else param.type.(*Type_Info_Integer);

                val: s64;
                if param.type.runtime_size == 1
                    val = param.value_pointer.(*s8).*;
                else if param.type.runtime_size == 2
                    val = param.value_pointer.(*s16).*;
                else if param.type.runtime_size == 4
                    val = param.value_pointer.(*s32).*;
                else {

                    if !info.signed && param.value_pointer.(*u64).* > S64_MAX.(u64) {
                        log("failed to bind sql param at index=% because sqlite only supports s64, but the provided parameter is u64 with a value larger than S64_MAX in query = %", param_index-1, sql, flags=.ERROR);
                        return false, SQLITE_ERROR;
                    }

                    val = param.value_pointer.(*s64).*;
                }

                status = sqlite3_bind_int64(stmt, param_index, val);

            case .FLOAT;
                if param.type.runtime_size <= 4
                    status = sqlite3_bind_double(stmt, param_index, param.value_pointer.(*float32).*);
                else
                    status = sqlite3_bind_double(stmt, param_index, param.value_pointer.(*float64).*);

            case .STRING;
                str := param.value_pointer.(*string).*;
                status = sqlite3_bind_text(stmt, param_index, str.data, str.count.(s32), null);

            case .BOOL;
                status = sqlite3_bind_int64(stmt, param_index, ifx param.value_pointer.(*bool).* then 1 else 0);

            case;
                log("failed to bind sql param at index=% because its type=% is not supported in query = %", param_index-1, param.type.type, sql, flags=.ERROR);
                return false, SQLITE_ERROR;
        }

        if status != SQLITE_OK {
            log("failed to bind sql param at index=% and type=% with error = % for sql = %", param_index-1, param.type.type, get_sqlite_error(db), sql, flags=.ERROR);
            return false, status;
        }
    }

    return true, SQLITE_OK;
}
