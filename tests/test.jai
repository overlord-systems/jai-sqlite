#import "Basic";
#import,file "../module.jai";

main :: () {

    test_db: *sqlite3;
    status := sqlite3_open("test_db.sqlite", *test_db);
    defer sqlite3_close(test_db);
    assert(status == SQLITE_OK, "failed to open/create test_db.sqlite");
}
