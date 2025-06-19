# jai-sqlite

[![Build SQLite3](https://github.com/overlord-systems/jai-sqlite/actions/workflows/build-sqlite.yml/badge.svg)](https://github.com/overlord-systems/jai-sqlite/actions/workflows/build-sqlite.yml)

Jai bindings for [SQLite3](https://github.com/sqlite/sqlite), automatically generated using Bindings Generator. A nice to use jai wrapper `sqlite3_exec_query` is provided for running queries along with an example of how to use it in the `Usage` section.

Windows x64, Mac x64/arm64, and Linux x64 are supported. We build our own binaries for all platforms [here](https://github.com/overlord-systems/jai-sqlite/actions).

## Usage

You can find a simple usage example in `tests/test.jai`.

Mac and Linux are statically linked, so nothing to do on your end just import the module and run.

Windows is dynamically linked, so download the `sqlite3.dll` file from the releases page and place it next to your executable to be able to run. You can find a prebuilt `sqlite3.dll` in [releases](https://github.com/overlord-systems/jai-sqlite/releases).

Here is a simple usage example showing opening/creating a database, creating a table, inserting a row, and reading rows, and error handling:
```jai
new_db: *sqlite3;

// Open db, create if it doesn't exist
sqlite3_status := sqlite3_open_v2("my_sqlite.db", *new_db, SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE, null);
if sqlite3_status != SQLITE_OK {
    log("failed to open/create sqlite db at 'my_sqlite.db' with err = %", get_sqlite_error(new_db), flags=.ERROR);

    // This must be freed on such errors
    if new_db sqlite3_free(new_db);

    return;
}

// We provide a jai wrapper procedures to make usage nice: 'sqlite3_exec_query'.
//
// One overlord is for queries that do not return rows, like insert, which returns only success and number of updated rows (check docs for 'sqlite3_changes64' for caveats).
//
// The other overload is for queries that return rows, which takes the struct type to parse rows into, and returns success and an array of those structs.
//
// This is using the first overload.
CREATE_PROJECTS_TABLE :: #string EOF
CREATE TABLE IF NOT EXISTS 'projects' (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
) STRICT;
EOF
success := sqlite3_exec_query(new_db, CREATE_PROJECTS_TABLE);
if !success {
    log("failed to create 'projects' table with err = %", get_sqlite_error(new_db), flags=.ERROR);
    return;
}

// Insert using the first overload
INSERT_PROJECT :: #string EOF
INSERT INTO 'projects' (id, name) VALUES (?, ?);
EOF

project_id := "some_id";
project_name := "My Test Project";
success = sqlite3_exec_query(new_db, INSERT_PROJECT, project_id, project_name);
if !success {
    log("failed to insert project % into 'projects' table with err = %", project_name, get_sqlite_error(new_db), flags=.ERROR);
    return;
}

// This is using the second overload, which parses rows into jai structs
Project :: struct {
    id: string;
    name: string;
}

READ_ALL_PROJECTS :: #string EOF
SELECT * FROM 'projects' LIMIT ?;
EOF
success=, rows := sqlite3_exec_query(new_db, Project, READ_ALL_PROJECTS, 100);
if !success {

    log("failed to read projects from db with err = %", get_sqlite_error(new_db), flags=.ERROR);

    // If we fail mid-way, there might be rows to free
    for rows {
        free(it.id);
        free(it.name);
    }
    array_free(rows);

    return;
}

print("my projects = %\n", rows);
```

## Other

We have a GitHub Actions workflow that builds binaries for all platforms, so if you want some binaries (e.g. dynamic binaries for Linux) then trigger the workflow and download the resulting artifacts.

To generate bindings run `jai generate.jai`. Bindings are generated using `include/sqlite3.h`, which we get from the `amalgamation` version from the [sqlite download](https://sqlite.org/download.html) page.
