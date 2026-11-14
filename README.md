# tcs-helpers

tcs-helpers holds the one copy of what the TCS projects -- tcs-xtce, tcslog,
tcslog-tools and tcspecial -- share for building their packages: the make
rules and the scripts they run. Each project used to carry its own copy of
these, and the copies drifted apart; now there is one, and the projects use
it from where it is.

It is not installed. A project uses it from a checkout of this repository,
by default the one beside the project, `../tcs-helpers`, so that cloning it
next to the projects is all it takes, and nothing is put in `~/bin`, `/usr`
or `/opt`.

## Getting it

Clone it beside the TCS projects:

```sh
cd ~/working        # the directory that holds tcs-xtce, tcslog and so on
git clone git@github.com:vomlehn/tcs-helpers.git
```

A project finds it there as `../tcs-helpers`. To keep it somewhere else,
set `TCS_HELPERS` to its path, on the make command line or in the
environment:

```sh
make packages TCS_HELPERS=/path/to/tcs-helpers
```

## Using it from a project

A project's packaging -- `make install`, `make uninstall`, `make
install-files`, `make uninstall-files`, `make stage`, `make deb`, `make
rpm`, `make packages`, `make lint-packages`, `make links` and `make
unlinks` -- runs what it needs from the checkout. All but `make
install-files` and `make uninstall-files`, which copy the project's own
files into place, are the rules in `packaging/packaging.mk`, which the
project's Makefile includes after saying what its packages are:

```make
TCS_HELPERS ?= $(abspath $(CURDIR)/../tcs-helpers)
TCS_HELPERS_REQUIRED := 0.4.0
PACKAGES := tcslog
ifneq ($(wildcard $(TCS_HELPERS)/packaging/install-packages.sh),)
include $(TCS_HELPERS)/packaging/packaging.mk
else
.PHONY: install
install: tcs-helpers
.PHONY: uninstall
uninstall: tcs-helpers
.PHONY: stage
stage: tcs-helpers
.PHONY: deb
deb: tcs-helpers
.PHONY: rpm
rpm: tcs-helpers
.PHONY: packages
packages: tcs-helpers
.PHONY: lint-packages
lint-packages: tcs-helpers
.PHONY: links
links: tcs-helpers
.PHONY: unlinks
unlinks: tcs-helpers
endif
```

The `else` is for a checkout that is missing or older than 0.4.0, the
first with `install-packages.sh`, when there is nothing to include that
has every target: the targets then stop as the project's `tcs-helpers`
target says. The comment at the top of `packaging.mk` lists
what else a project gives it, such as `RPM_DEFINES` for its RPM spec, and
what it must have in its own `packaging` directory.

Before any of them runs, the project checks that the checkout is there and
new enough, and stops with a message saying what to do if not: where to
clone it from, or to update it.

The check is the `tcs-helpers` command, which a project runs from the
checkout:

```sh
../tcs-helpers/bin/tcs-helpers --version         # this checkout's version
../tcs-helpers/bin/tcs-helpers --require 0.4.0   # exit 1 if it is older
```

What the projects use from it, all in `packaging/`:

| File | What it does |
|---|---|
| `packaging.mk` | The make rules for `install`, `uninstall`, `stage`, `deb`, `rpm`, `packages`, `lint-packages`, `links` and `unlinks`, which a project's Makefile includes |
| `install-packages.sh` | Installs the packages `make packages` built, or removes them, with this system's installer, for `make install` and `make uninstall` |
| `build-deb.sh` | Builds a package's .deb from its stage, for `make deb`, from the control file and maintainer scripts in the project's `packaging/deb/<package>/DEBIAN` |
| `lint-packages.sh` | Runs lintian, rpmlint and shellcheck on what `make packages` built, for `make lint-packages` |
| `debian-files.sh` | Adds to a .deb the files Debian expects outside `/opt/tcs`: the copyright, `changelog.Debian.gz`, lintian overrides, the ldconfig trigger and `DEBIAN/md5sums`. It is given the project's `packaging/deb` directory, which holds what differs between projects |
| `third-party-notices.py` | Writes `THIRD-PARTY-NOTICES`, the notices a package owes the Rust crates compiled into it: see below |
| `release.sh` | Publishes the packages as a GitHub release, for `make publish-release`: see below |
| `attribution/` | The attributions a licence asks to be shown where packages are downloaded, which `make publish-release` adds to a release's notes |
| `links.sh.in` | The template of each package's `<package>-links` script, which links its programs into `/usr/local/bin` |

What differs between projects -- their `make install-files`, Debian control files
and maintainer scripts, RPM specs, `copyright.in`, rpmlint settings and
install hooks -- stays in each project.

## HTML pages

A project commits each HTML page beside the reStructuredText or Markdown
it is built from, so that it can be read without building it. Two things
keep those pages up to date, both from `bin/html-pages`:

- The pre-commit hook, `githooks/pre-commit`, which also checks the names
  first: see [Production names](#production-names). For each `.rst` or `.md`
  file a commit changes whose directory's Makefile has a rule for its
  page, it rebuilds the page and adds it to the commit. It refuses a
  commit whose staged source also has changes that are not staged, since
  the page would be built from text the commit does not hold. A
  project's `make hooks` points git's `core.hooksPath` at this checkout's
  `githooks`.
- `html-pages check DIR...`, which a project's `make html-check` runs. It
  rebuilds every page in each directory and fails, naming them, where any
  was behind its source, which catches a commit made without the hook.
  The pages it found behind are already rebuilt, and need only
  committing.

## Production names

TCS code is of two kinds. Production code is code a mission depends on
while it operates: vehicle code, aboard the vehicle, and MOC code, in the
mission operations centre. Everything else -- editors, simulators, test
stations, generators, packaging -- is non-production code. A name says
which: find the prefix, `tcslog` if the name starts with it and `tcs`
otherwise. A letter after it, or nothing, is production (`tcspecial`,
`tcsmoc`, `tcslog`, `tcslogc`, `tcsxtce`); a hyphen or an underscore is
not (`tcs-gui`, `tcs-verify`, `tcs_xtce`, `tcslog-tools`). The rule covers
published names, libraries, executables and header files, and not
projects or the packages they install with. tcspecial's design,
"Production code and its names", gives the requirements.

Production code is built only from production code, and
`bin/production-names` holds a project to that. It is the one statement of
the rule, and every project runs it from `make production-names`, which its
`make check` runs:

```sh
$(TCS_HELPERS)/bin/production-names \
	--pyproject python/pyproject.toml \
	--install tcspecial --install tcs-moc \
	--desk-feature tcspecial/visual=tcs-diagram \
	--except 'tcs-xtce=why, until it can go'
```

It fails where a production crate of the project's Cargo manifests
(`--manifest`, or `./Cargo.toml`) is built from a crate with a
non-production name, or where a production Python package of a
`--pyproject` imports one. `--install` names the crates a project builds
together for installing, which cargo builds with their features pooled;
they are checked as so built, and a `--desk-feature` found on in that
build -- tcspecial's visual window, which never flies -- is a warning, as is
each name given with `--except`, every run, until it is gone. The
pre-commit hook runs `make production-names` too, when a commit changes a
Cargo manifest or lock file, a `pyproject.toml` or Python, so that a
dependency on a tool is refused when it is committed.

## Third-party notices

Nearly every Rust crate's licence -- MIT, Apache-2.0, the BSD licences,
Zlib, Unicode-3.0, the SIL Open Font License of a font a crate embeds --
requires its copyright and licence notices to go with every copy, and a
program is a copy of the crates compiled into it. So each package of
compiled code carries `THIRD-PARTY-NOTICES` in its documentation
directory, which a project's `install-files` writes with
`third-party-notices.py`, as `packaging.mk`'s `THIRD_PARTY_NOTICES`:

```make
$(THIRD_PARTY_NOTICES) . $(DESTDIR)$(DOCDIR)/tcslog/THIRD-PARTY-NOTICES \
	tcslog tcslog-c
```

It is given the Cargo workspace, the file to write, the package's name and
the workspace's crates the package ships, or none for all of them. It
lists every crate those are built from for the host, without the ones they
are only tested or built with and without procedural macros, as `cargo
tree` resolves them with the build's features, and the Rust standard
library, whose notices come from the toolchain. Each crate is given with
its licence; where it offers a choice, the one taken, which is the first
in the script's `PREFERRED` list; and every licence and notice file it
ships, their texts following the list, each printed once. A crate that
ships none gets the standard text of its licence from `packaging/licences`
or `LICENSE-APACHE`, with its authors as the copyright holders.

Slint is offered under GPL-3.0, its royalty-free licence for desktop
applications and a commercial one; the projects take the royalty-free
one, which they meet with Slint's attribution badge in their READMEs.

cargo runs offline, so the workspace must have been built, as
`install-files` has done by then.

## Publishing a release

`make publish-release` builds the project's packages and publishes them as a
GitHub release, with `gh`:

```sh
git tag v1.2.0 && git push origin v1.2.0
make publish-release RELEASE_NOTES=notes.md
make publish-release RELEASE_TAG=rc10 RELEASE_NOTES=notes.md \
	RELEASE_FLAGS=--prerelease
```

The notes are the project's, written for the release. After them come
the attributions the project names in `RELEASE_ATTRIBUTION`, each from
`packaging/attribution/<name>.md`: a licence of something compiled into
the packages may ask to be credited where the packages are downloaded,
as Slint's royalty-free licence does, and the project says so once
rather than each release remembering it:

```make
RELEASE_ATTRIBUTION := slint
```

Nothing is published if the tag is not on GitHub, the tag has a release
already, or a package has no `THIRD-PARTY-NOTICES`. A release that
exists is left alone; replace its files with `gh release upload
--clobber`.

## What `make install` does in a project

`make install` builds the project's packages, the .deb and the RPM, as
whoever ran make, with `make packages`; then it installs those of the
kind this system takes, with its usual installer, which also installs
what they depend on:

| System, by `/etc/os-release`'s `ID` or `ID_LIKE` | Installs | With |
|---|---|---|
| `debian`, `ubuntu` | the .debs | `apt-get install ./<file>.deb` |
| `fedora`, `rhel`, `centos`, `rocky`, `almalinux` | the RPMs | `dnf install ./<file>.rpm`, or `yum` without dnf |
| `suse`, `opensuse`, `sles` | the RPMs | `zypper install ./<file>.rpm` |

The system is told by `/etc/os-release` rather than by which tools are
present, since a Debian system may have `rpm` installed too. The files
are named exactly, at the project's version and `DEB_REVISION`, which is
the RPM's release as well, so that nothing stale in `build/packages` is
installed. `make uninstall` removes the project's packages with the same
installer (`apt-get remove`, `dnf remove`, `zypper remove`); the
packages' own removal scripts take away any links `make links` made.

Only the installer runs privileged, under `SUDO`, which is `sudo`, and
empty when make runs as root. These, on the command line or in the
environment, change what happens:

| Variable | What it does |
|---|---|
| `DRY_RUN=1` | Runs the installer's own no-change mode -- `apt-get -s`, `dnf` or `yum --assumeno`, `zypper --dry-run`, `rpm --test` -- without `SUDO`, to show what install or uninstall would do |
| `PACKAGE_FORMAT=deb` or `rpm` | Installs that kind whatever the system is: with its usual installer where it has one, and otherwise with the first of `dnf`, `yum` and `zypper` present |
| `INSTALLER=<command>` | Runs that installer: `apt-get`, `apt`, `dpkg`, `dnf`, `yum`, `zypper` or `rpm`, or a path to one; the kind is the one it installs |
| `SUDO=<command>` | Runs the installer under that instead of `sudo`; `SUDO=` runs it as yourself |

```sh
make install DRY_RUN=1                      # see what it would do
make install                                # do it
PACKAGE_FORMAT=rpm make install DRY_RUN=1   # the RPM, on any system
make uninstall
```

On a system it does not know, `make install` stops, naming the `ID` and
`ID_LIKE` it read and saying to give `PACKAGE_FORMAT` and, if need be,
`INSTALLER`. If the kind the system takes was not built, because
`dpkg-deb` or `rpmbuild` is missing, it stops and says which to install;
`make deb` and `make rpm` themselves say so in a line and carry on, so
that `make packages` builds what it can.

`make install-files` is what `make install` was before 0.4.0: the
project's own copy of its files into `$(DESTDIR)$(PREFIX)`, which `make
stage` uses, as `STAGE_TARGET`, to make the tree the packages are cut
from, and which a developer can use to install without a package. `make
uninstall-files` removes that copy. `make install` and `make uninstall`
take no `DESTDIR` or `PREFIX`, the packages going under `/opt/tcs`, and
stop, naming `install-files`, if given either.

## Keeping it up to date

Pull it as you would any other repository:

```sh
cd ~/working/tcs-helpers
git pull
```

The projects use whatever the checkout holds, so a change here reaches them
at their next build. A project that needs a newer version than the
checkout's says so and stops, naming the version it needs.

`VERSION` holds this repository's version, and `CHANGELOG.md` what each
version changed. A change that a project comes to depend on raises the
version, and the project raises the version it requires.

## Uninstalling

Since nothing is installed, removing tcs-helpers is removing its checkout:

```sh
rm -rf ~/working/tcs-helpers
```

The projects then cannot build their packages until it is cloned again;
everything else they do -- building, testing, their own documentation --
does not use it.

Version 0.1.0 was installed rather than used from a checkout, with
`make install` putting the `tcs-helpers` command in `~/bin` and an empty
`~/lib/tcs-helpers`. On a machine where that was done, remove them before
removing the checkout:

```sh
cd ~/working/tcs-helpers
make uninstall
```

That removes `~/bin/tcs-helpers` and `~/lib/tcs-helpers`, or the same under
the `PREFIX`, `BINDIR` and `DATADIR` that `make install` was given, if any
were.

## This documentation

This file, `README.md`, is the documentation, in Markdown. `make
README.html` writes `README.html` from it with pandoc, for reading in a
browser; this checkout's own pre-commit hook does that and commits the two
together once `make hooks` has been run here.

## Checking

`make check` runs `bin/production-names --self-test`, which holds the rule
to names it must judge rightly, compiles `third-party-notices.py`, runs
shellcheck on every
script, `links.sh.in` with its
placeholders filled in, and `packaging/test-install-packages.sh`, which
runs `install-packages.sh` against os-release files and stand-in
installers of its own and checks the command it would have run on each
system. `install-packages.sh` reads the os-release file `TCS_OS_RELEASE`
names in place of `/etc/os-release`, for testing. `packaging.mk` is checked by the projects' own
`make packages` and `make lint-packages`.

## License

Licensed under either of the Apache License, Version 2.0, in
`LICENSE-APACHE`, or the MIT license, in `LICENSE-MIT`, at your option.
