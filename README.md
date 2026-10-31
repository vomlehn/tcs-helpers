# tcs-helpers

One copy of what the tcs projects -- tcs-xtce, tcslog, tcslog-tools and
tcspecial -- share for building their packages, installed once and used
from where it is installed rather than copied into each project.

## Installing

```sh
make install
```

puts the commands in `~/bin`, which is on `PATH`, and the data in
`~/lib/tcs-helpers`, so nothing needs root. `PREFIX=/some/where` installs
under another prefix, and `BINDIR` and `DATADIR` set the two places
separately. `make uninstall` removes them again.

After changing anything here, run `make install` again: the projects use
whatever is installed, so an edit takes effect only once it is.

## What a project asks of it

A project that packages with tcs-helpers states the oldest version it
needs, and its packaging checks before it builds anything:

```sh
tcs-helpers --require 0.1.0
```

exits 0 when the installed version is at least that, and otherwise says
which version is installed and which is required, and exits 1. `make
install` here then brings it up to date. `tcs-helpers --version` prints
the installed version and `tcs-helpers --datadir` the directory holding
its data, which is where a project's Makefile finds what it includes.

## What is here

| Path | What it is |
|---|---|
| `bin/tcs-helpers.in` | The `tcs-helpers` command, written to `~/bin` with the version and data directory filled in |
| `lib/` | Data installed in `~/lib/tcs-helpers` as it is |
| `VERSION` | This release's version, which `--require` compares against |

The packaging pieces the projects share move here next: the package
linter, the link-making hook template, the Debian file generator and the
packaging rules their Makefiles have in common. What differs between
projects -- control files, RPM specs, copyright, rpmlint settings and
install hooks -- stays in each project.

## Checking

`make check` runs shellcheck on every script.

## License

Licensed under either of the Apache License, Version 2.0, in
`LICENSE-APACHE`, or the MIT license, in `LICENSE-MIT`, at your option.
