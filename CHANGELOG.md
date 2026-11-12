# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][kac], and the project follows
[Semantic Versioning][semver]. A project states the oldest version it
needs, which `tcs-helpers --require` checks.

[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html

## [0.7.0] - 2026-11-11

### Added

- `bin/html-pages` and the pre-commit hook `githooks/pre-commit`, which
  keep a project's committed HTML pages up to date: the hook rebuilds the
  page of each `.rst` or `.md` source a commit changes and adds it to the
  commit, and `html-pages check DIR...` fails, naming them, where a page
  is behind its source. A project's `make hooks` sets `core.hooksPath` to
  `githooks`.

## [0.6.0] - 2026-11-10

### Added

- `packaging/third-party-notices.py`, which writes the notices a package
  owes the Rust crates compiled into it, and the Rust standard library:
  each crate with its licence, the one it is taken under where it offers
  a choice, and the texts of the licence and notice files it ships, each
  printed once. A project's `install-files` runs it, as
  `$(THIRD_PARTY_NOTICES)`, to put `THIRD-PARTY-NOTICES` in each package
  of compiled code, since nearly every crate's licence requires its
  notices to go with every copy. `packaging/licences` holds the standard
  texts it gives a crate that ships none.

## [0.5.0] - 2026-10-31

### Changed

- The dry run of `make install` and `make uninstall` is `DRY_RUN=1`,
  where it was `SIMULATE=1`: tcspecial's own `SIMULATE` chooses which
  payloads its run targets simulate, and the one name meant two things.

## [0.4.0] - 2026-10-30

### Added

- `install` and `uninstall` in `packaging.mk`. `make install` builds the
  packages, both kinds, as whoever runs make, and installs those of the
  kind this system takes with its usual installer: `apt-get` on Debian
  and Ubuntu, `dnf`, or `yum` without it, on Fedora and Red Hat's, and
  `zypper` on SUSE's, as the `ID` and `ID_LIKE` of `/etc/os-release` say.
  `make uninstall` removes the packages with the same installer. Only the
  installer runs privileged, under `SUDO`, which is `sudo` unless make
  runs as root. `SIMULATE=1` runs the installer's no-change mode without
  `SUDO`; `PACKAGE_FORMAT=deb|rpm` and `INSTALLER=<command>` override
  the choice. Both stop, naming `install-files` and `uninstall-files`,
  when given `DESTDIR` or a `PREFIX` other than `/opt/tcs`.
- `packaging/install-packages.sh`, which chooses the kind and the
  installer and runs it for those targets, and
  `packaging/test-install-packages.sh`, which `make check` runs to test
  its choices against stand-in installers.

### Changed

- `STAGE_TARGET` defaults to `install-files`, the project's copy of its
  files into `DESTDIR`, which is what a project's `make install` was. A
  project renames its `install` and `uninstall` to `install-files` and
  `uninstall-files`, and includes `packaging.mk` only where
  `install-packages.sh` is there, so that an older checkout stops at the
  `tcs-helpers` check.
- `make deb` without `dpkg-deb` says so and builds nothing, without
  failing, as `make rpm` does without `rpmbuild`, so that `make packages`
  builds what it can.
- The RPMs are given `tcs_release`, `DEB_REVISION`, for their spec's
  `Release`, so that a .deb and its RPM have the same revision and
  `install` can name both files exactly. `lint-packages` checks those
  files alone, not every revision in `build/packages`.

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
