#run build();

build :: () {

    set_build_options_dc(.{do_output=false});

    options := get_build_options();

    if !generate_bindings() {
        compiler_set_workspace_status(.FAILED);
        return;
    }
}

// We use 'sqlite3_lib' as the library name, eventhough the real name is 'sqlite3', because
// there is a struct called `sqlite3` and so having the library be the same name will cause a conflict.
//
// On windows the user must have 'sqlite3.dll' (I didn't find a way to statically compile sqlite3 for windows)
// but on mac/linux we do static linking.
generate_bindings :: () -> bool {

    output_filename: string;
    opts: Generate_Bindings_Options;

    {
        opts.header = HEADER;

        #if OS == .WINDOWS {

            output_filename = "windows/windows.jai";

            FOOTER :: #string EOF
#if CPU == .X64 {
    sqlite3_lib :: #library,no_dll "bin/x64/sqlite3_lib";
} else #if CPU == .ARM64 {
    #assert false "Windows ARM64 is not supported, but you might be able to compile for that!";
}
EOF
            opts.footer = FOOTER;
            opts.generate_library_declarations = false;

            #if CPU == .X64 {
                array_add(*opts.libpaths, "windows/bin/x64");
            } else {
                assert(false, "the CPU % is currently unsupported. You might be able to add support for it though!", CPU);
            }

            array_add(*opts.libnames, "sqlite3_lib");

        } else #if OS == .MACOS {

            output_filename = "macos/macos.jai";
            opts.generate_library_declarations = false;

            FOOTER :: #string EOF
#if CPU == .X64 {
    sqlite3_lib :: #library,no_dll "bin/x64/sqlite3_lib";
} else #if CPU == .ARM64 {
    sqlite3_lib :: #library,no_dll "bin/arm64/sqlite3_lib";
}
EOF;
            #if CPU == .X64 {
                array_add(*opts.libpaths, "macos/bin/x64");
            } else #if CPU == .ARM64 {
                array_add(*opts.libpaths, "macos/bin/arm64");
            } else {
                assert(false, "the CPU % is currently unsupported. You might be able to add support for it though!", CPU);
            }

            opts.footer = FOOTER;

            array_add(*opts.libnames, "sqlite3_lib");

        } else #if OS == .LINUX {

            output_filename = "linux/linux.jai";
            opts.generate_library_declarations = false;

            FOOTER :: #string EOF
#if CPU == .X64 {
    sqlite3_lib :: #library,no_dll "bin/x64/sqlite3_lib";
} else {
    #assert false "Only Linux x64 is supported, but you might be able to compile for your architecture!";
}
EOF;
            opts.footer = FOOTER;
            opts.generate_library_declarations = false;

            array_add(*opts.libnames, "sqlite3_lib");

        } else {
            assert(false, "the OS % is currently unsupported. You might be able to add support for it though!", OS);
        }

        array_add(*opts.include_paths, "include");
        array_add(*opts.source_files, "include/sqlite3.h");

        opts.visitor = sqlite_visitor;
        opts.generate_compile_time_struct_checks = false;
    }

    success := generate_bindings(opts, output_filename);
    if !success return false;

    return success;
}

sqlite_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {

    if array_find(DECLARATIONS_TO_OMIT, decl.name) {
        decl.decl_flags |= .OMIT_FROM_OUTPUT;
        return .STOP;
    }

    return .RECURSE;
}

#scope_file

#import "Basic";
#import "Compiler";
#import "BuildCpp";
#import "Check";
#import "Bindings_Generator";
#import "File";
#import "String";

DECLARATIONS_TO_OMIT :: string.[
];

HEADER :: #string EOF
EOF
