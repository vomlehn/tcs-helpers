# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][kac], and the project follows
[Semantic Versioning][semver]. A project states the oldest version it
needs, which `tcs-helpers --require` checks.

[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html

## [0.3.0] - 2026-10-30

### Added

- `packaging/packaging.mk`, the make rules for `stage`, `deb`, `rpm`,
  `packages`, `lint-packages`, `links` and `unlinks` that the TCS projects
  each had, for a project's Makefile to include. A project gives it its
  `PACKAGES`, and, as it needs them, `RPM_DEFINES`, `LINT_SCRIPTS`,
  `STAGE_TARGET`, `STAGE_VARS` and `TCS_SOURCE`.
- `packaging/build-deb.sh`, which builds a package's .deb from its stage
  for `packaging.mk`, as tcs-xtce's and tcspecial's copies did. It takes
  the control file and maintainer scripts from the project's
  `packaging/deb/<package>/DEBIAN`, replaces `@SHLIBS@` in the control file
  with what `dpkg-shlibdeps` finds, makes every file under `/etc` a
  conffile and writes a `shlibs` entry for each shared library.

## [0.2.0] - 2026-10-30

### Added

- `packaging/lint-packages.sh`, `packaging/debian-files.sh` and
  `packaging/links.sh.in`, the packaging scripts the TCS projects each
  carried a copy of. `debian-files.sh` takes the project's `packaging/deb`
  directory as its first argument, where it found it beside itself before.

### Changed

- tcs-helpers is used from its checkout, `../tcs-helpers` beside a
  project or wherever `TCS_HELPERS` says, and is no longer installed:
  `make install` is gone, and `tcs-helpers --datadir` with it.
- `make uninstall` removes what 0.1.0's `make install` put in `~/bin` and
  `~/lib`.

## [0.1.0] - 2026-10-30

### Added

- `make install`, `make uninstall` and `make check`, installing into
  `~/bin` and `~/lib/tcs-helpers` by default.
- `tcs-helpers --version`, `--datadir` and `--require VERSION`.
