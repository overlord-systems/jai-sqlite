# jai-sqlite

Jai bindings for [SQLite3](https://github.com/sqlite/sqlite).

Currently only Windows bindings and binaries are available, but it should be *very* easy to [compile](https://www.sqlite.org/howtocompile.html) and then generate bindings using `jai generate.jai`.

## Usage

You can find a simple usage example in `tests/test.jai`. Make sure to place the relevant shared library (i.e. `sqlite3.dll`/`sqlite3.so`/`sqlite3.dylib`) next to your executable or in your system path.

You can find some prebuilt shared libraries in [releases](https://github.com/overlord-systems/jai-sqlite/releases).

If you want to generate bindings simply run `jai generate.jai`.
