# jai-sqlite

Jai bindings for [SQLite3](https://github.com/sqlite/sqlite), automatically generated using Bindings Generator.

Windows x64, Mac x64/arm64, and Linux x64 are supported. We build our own binaries for all platforms [here](https://github.com/overlord-systems/jai-sqlite/actions).

Currently only Windows bindings and binaries are available, but it should be *very* easy to [compile](https://www.sqlite.org/howtocompile.html) and then generate bindings using `jai generate.jai`.

## Usage

You can find a simple usage example in `tests/test.jai`.

Mac and Linux are statically linked, so nothing to do on your end just import the module and run.

Windows is dynamically linked, so download the `sqlite3.dll` file from the releases page and place it next to your executable to be able to run. You can find a prebuilt `sqlite3.dll` in [releases](https://github.com/overlord-systems/jai-sqlite/releases).

## Other

We have a GitHub Actions workflow that builds binaries for all platforms, so if you want some binaries (e.g. dynamic binaries for Linux) then trigger the workflow and download the resulting artifacts.

To generate bindings run `jai generate.jai`.
