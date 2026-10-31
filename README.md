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
| `links.sh.in` | The template of each package's `<package>-links` script, which links its programs into `/usr/local/bin` |

What differs between projects -- their `make install-files`, Debian control files
and maintainer scripts, RPM specs, `copyright.in`, rpmlint settings and
install hooks -- stays in each project.

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
browser; run it after editing `README.md`, and commit the two together.

## Checking

`make check` runs shellcheck on every script, `links.sh.in` with its
placeholders filled in, and `packaging/test-install-packages.sh`, which
runs `install-packages.sh` against os-release files and stand-in
installers of its own and checks the command it would have run on each
system. `install-packages.sh` reads the os-release file `TCS_OS_RELEASE`
names in place of `/etc/os-release`, for testing. `packaging.mk` is checked by the projects' own
`make packages` and `make lint-packages`.

## License

Licensed under either of the Apache License, Version 2.0, in
`LICENSE-APACHE`, or the MIT license, in `LICENSE-MIT`, at your option.
