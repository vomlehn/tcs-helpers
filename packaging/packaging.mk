# packaging.mk: the make rules the TCS projects share for packaging what
# they install, included by each project's Makefile from the tcs-helpers
# checkout:
#
#   include $(TCS_HELPERS)/packaging/packaging.mk
#
# It gives the targets
#
#   install        build the packages and install those of the kind this
#                  system takes with its usual installer, apt-get, dnf or
#                  zypper, under sudo; SIMULATE=1 shows what it would do
#   uninstall      remove the packages with the same installer
#   stage          install each package into build/stage/<package>
#   deb            build each package's .deb into build/packages
#   rpm            build each package's .rpm into build/packages
#   packages       build both
#   lint-packages  check what packages built with lintian, rpmlint and
#                  shellcheck
#   links          link the installed programs into LINKDIR; unlinks
#                  removes the links
#
# from what the project says before including it:
#
#   PACKAGES       the packages, each installed into a stage of its own
#   VERSION        the version they are all built at
#   PREFIX         where install-files installs, for links and unlinks
#   TCS_HELPERS    this checkout
#   tcs-helpers    a target that stops unless TCS_HELPERS is a checkout
#                  new enough for the project, which every target here
#                  but links and unlinks depends on
#
# and, if it needs to:
#
#   TCS_SOURCE     the source package's name, by default the first of
#                  PACKAGES
#   STAGE_TARGET   the target that copies a package's files into place,
#                  by default install-files; $$package in it is the
#                  package's name
#   STAGE_VARS     more variables the stage's install-files is given
#   RPM_DEFINES    more --define options for rpmbuild, as the specs need
#   LINT_SCRIPTS   more shell scripts for lint-packages to check
#
# A project keeps what differs between projects in its packaging directory:
# packaging/deb/<package>/DEBIAN, with the control file and maintainer
# scripts build-deb.sh takes, packaging/deb/<package>/lintian-overrides and
# packaging/deb/copyright.in, which debian-files.sh takes, and
# packaging/rpm/<package>.spec, with the rpmlint.toml lint-packages gives
# rpmlint. A spec is given tcs_version, tcs_date, the date of the changelog
# entry, tcs_release, the package's release, and tcs_stage, the package's
# stage, besides RPM_DEFINES.
#
# STRIP=0 on the command line, or in the environment, reaches the stage's
# install-files as it does any sub-make, and leaves the packages unstripped.
#
# install and uninstall take, from the command line or the environment,
# PACKAGE_FORMAT, deb or rpm, to install that kind whatever the system is;
# INSTALLER, the installer to run; SUDO, what runs it, sudo unless make
# runs as root; and SIMULATE=1, to have the installer show what it would do
# and change nothing, without SUDO: see install-packages.sh.

TCS_SOURCE   ?= $(firstword $(PACKAGES))
# install-files, the project's own copy of its files into DESTDIR, rather
# than install, which builds the packages from the stage and so would
# stage again for ever.
STAGE_TARGET ?= install-files
LINKDIR      ?= /usr/local/bin

# Where the packages are built: build/, which git ignores. The stage is one
# directory per package, installed into with the paths the package is for
# and the hooks on, so that the package is exactly what install-files
# installs.
STAGE       := $(CURDIR)/build/stage
PACKAGE_DIR := $(CURDIR)/build/packages
DEB_TOP     := $(CURDIR)/build/deb
RPM_TOP     := $(CURDIR)/build/rpm

# The Debian revision, for a package rebuilt from the same source, which
# is the RPM's release too, so that the two are built and named alike.
DEB_REVISION ?= 1
DEB_VERSION  := $(VERSION)-$(DEB_REVISION)

# The package files, each by its exact name, so that install installs what
# was just built and never another version or revision left beside it.
# The architectures and the RPM's dist tag, such as .fc41, are the build
# tools', asked only when a file name is wanted; without the tool, its
# packages are not built, and install says so.
DEB_ARCH   = $(shell dpkg --print-architecture 2>/dev/null)
RPM_ARCH   = $(shell rpm --eval '%{_target_cpu}' 2>/dev/null)
RPM_DIST   = $(shell rpm --eval '%{?dist}' 2>/dev/null)
RPM_VERSION = $(VERSION)-$(DEB_REVISION)$(RPM_DIST)
DEB_FILES  = $(foreach package,$(PACKAGES), \
		$(PACKAGE_DIR)/$(package)_$(DEB_VERSION)_$(DEB_ARCH).deb)
RPM_FILES  = $(foreach package,$(PACKAGES), \
		$(PACKAGE_DIR)/$(package)-$(RPM_VERSION).$(RPM_ARCH).rpm)

# What install and uninstall run the installer under: sudo, so that only
# the installer runs as root and the packages are built as whoever ran
# make, or nothing when that is root already.
SUDO ?= $(if $(filter 0,$(shell id -u)),,sudo)

# The release's time, which dates the changelog entry each package carries:
# that of the commit being built, so that building the same commit again
# makes the same entry, or now outside a git clone. The name is the one
# reproducible builds give it, so that a builder's own SOURCE_DATE_EPOCH is
# taken. Worked out once, so that the .deb and the .rpm are dated alike.
ifndef SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH := $(shell git log -1 --format=%ct 2>/dev/null \
                             || date +%s)
endif

# Install each package into its stage, under /opt/tcs and with the hooks.
# The stage is emptied first, so that nothing a previous install left
# behind gets into a package. Files are then made writable by their owner
# alone, whatever the umask of whoever ran this, which is what both package
# formats expect.
.PHONY: stage
stage: tcs-helpers		## Install each package into build/stage
	rm -rf $(STAGE)
	for package in $(PACKAGES); do \
		$(MAKE) --no-print-directory $(STAGE_TARGET) \
			DESTDIR=$(STAGE)/$$package PREFIX=/opt/tcs HOOKS=1 \
			$(STAGE_VARS) || exit 1; \
	done
	chmod -R u+rwX,go=rX $(STAGE)
	@echo "[OK] Staged in $(STAGE)"

# The .deb, one per staged package: see build-deb.sh. A machine without
# dpkg-deb says so and carries on, as rpm does without rpmbuild, so that
# `make packages` still makes the RPMs; that is checked before staging, so
# as not to build for nothing.
.PHONY: deb
deb: tcs-helpers		## Build the .debs in build/packages
	@if ! command -v dpkg-deb > /dev/null 2>&1; then \
		echo "dpkg-deb is not installed, so no .deb was built:" \
			"install it (sudo apt-get install dpkg-dev) and run" \
			"make deb again"; \
		exit 0; \
	fi; \
	set -e; \
	$(MAKE) --no-print-directory stage; \
	for package in $(PACKAGES); do \
		$(TCS_HELPERS)/packaging/build-deb.sh \
			$(CURDIR)/packaging/deb $(TCS_SOURCE) $$package \
			$(STAGE)/$$package $(DEB_TOP) $(PACKAGE_DIR) \
			$(DEB_VERSION) $(DEB_ARCH) $(SOURCE_DATE_EPOCH); \
	done; \
	echo "[OK] .debs in $(PACKAGE_DIR)"

# The .rpm, one per staged package, with packaging/rpm/<package>.spec,
# whose %install copies the stage rather than building anything. A machine
# without rpmbuild says so and carries on, so that `make packages` still
# makes the .debs; that is checked before staging, so as not to build for
# nothing. rpmbuild is pointed at a database of its own under build/,
# because a Debian host has no RPM database in /var/lib/rpm to read, and
# rpmbuild complains at length when it finds none.
.PHONY: rpm
rpm: tcs-helpers		## Build the .rpms in build/packages
	@if ! command -v rpmbuild > /dev/null 2>&1; then \
		echo "rpmbuild is not installed, so no RPM was built:" \
			"install it (sudo apt install rpm, or sudo dnf" \
			"install rpm-build) and run make rpm again"; \
		exit 0; \
	fi; \
	set -e; \
	$(MAKE) --no-print-directory stage; \
	rm -rf $(RPM_TOP); \
	mkdir -p $(PACKAGE_DIR) $(RPM_TOP)/db; \
	for package in $(PACKAGES); do \
		rpmbuild -bb --quiet \
			--define "_topdir $(RPM_TOP)" \
			--define "_dbpath $(RPM_TOP)/db" \
			--define "tcs_version $(VERSION)" \
			--define "tcs_release $(DEB_REVISION)" \
			--define "tcs_date $$(date -u \
				-d @$(SOURCE_DATE_EPOCH) '+%a %b %d %Y')" \
			--define "tcs_stage $(STAGE)/$$package" \
			$(RPM_DEFINES) \
			packaging/rpm/$$package.spec; \
	done; \
	cp $(RPM_TOP)/RPMS/*/*.rpm $(PACKAGE_DIR); \
	echo "[OK] RPMs in $(PACKAGE_DIR)"

.PHONY: packages
packages: deb rpm		## Build both; STRIP=0 leaves them unstripped

# Check the packages `make packages` built, and the shell scripts they run
# or install, with lintian, rpmlint and shellcheck, any of which is skipped
# in a line if it is not installed: see lint-packages.sh. rpmlint is given
# packaging/rpm/rpmlint.toml, which says why each finding it accepts is
# intended; each .deb carries its own lintian overrides. The links scripts
# and the profile.d hooks are checked as the stage has them, with their
# placeholders filled in. The scripts here are checked by tcs-helpers'
# own make check.
.PHONY: lint-packages
lint-packages: tcs-helpers	## Lint the packages and their shell scripts
	$(TCS_HELPERS)/packaging/lint-packages.sh packaging/rpm/rpmlint.toml \
		$(wildcard $(DEB_FILES) $(RPM_FILES)) \
		-- $(wildcard $(STAGE)/*/opt/tcs/sbin/*-links \
			$(STAGE)/*/etc/profile.d/*.sh) \
		$(wildcard $(foreach script,preinst postinst prerm postrm, \
			packaging/deb/*/DEBIAN/$(script))) \
		$(LINT_SCRIPTS)

# What install and uninstall give install-packages.sh, which reads them
# from its environment: empty unless given on the command line or in
# make's environment, but for SUDO, above.
PACKAGE_FORMAT ?=
INSTALLER      ?=
SIMULATE       ?=
INSTALL_PACKAGES = PACKAGE_FORMAT='$(PACKAGE_FORMAT)' \
		INSTALLER='$(INSTALLER)' SUDO='$(SUDO)' SIMULATE='$(SIMULATE)' \
		$(TCS_HELPERS)/packaging/install-packages.sh

# install and uninstall are the system's installer's, which has no DESTDIR
# or PREFIX, the packages going under /opt/tcs. Given either, whoever ran
# make meant the copy of the files, install-files or uninstall-files,
# which install and uninstall once were, so they stop before anything is
# built or installed rather than install the packages instead.
define refuse-copy-vars
	@if [ -n "$(DESTDIR)" ] || { [ "$(PREFIX)" != /opt/tcs ] && \
		[ -n "$(filter command line environment,$(origin PREFIX))" ]; \
		}; then \
		echo "make $(1) $(2) the packages, which are under" \
			"/opt/tcs, and takes no DESTDIR or PREFIX: to $(3)" \
			"$(DESTDIR)$(PREFIX), run make $(1)-files with them" \
			"instead" >&2; \
		exit 1; \
	fi
endef

# Build the packages, both kinds, as whoever ran make, and install those
# of the kind this system takes, with its usual installer under SUDO:
# apt-get on Debian and Ubuntu, dnf on Fedora and Red Hat's, zypper on
# SUSE's, each of which also installs what they depend on. Which is the
# system's is read from /etc/os-release: see install-packages.sh, which
# says why, and how PACKAGE_FORMAT and INSTALLER change it. The files are
# named exactly, so that a stale package left in build/packages is never
# installed.
.PHONY: install
install: tcs-helpers		## Build packages, install with apt/dnf/zypper
	$(call refuse-copy-vars,install,installs,copy the files into)
	$(MAKE) --no-print-directory packages
	$(INSTALL_PACKAGES) install $(DEB_FILES) -- $(RPM_FILES)

# Remove the packages with the installer install installed them with. The
# packages' own removal scripts take away the links `make links` made.
.PHONY: uninstall
uninstall: tcs-helpers		## Remove the installed packages
	$(call refuse-copy-vars,uninstall,removes,remove the copy in)
	$(INSTALL_PACKAGES) remove $(PACKAGES)

# Link the installed programs into LINKDIR, which every environment
# searches, or take those links away, with the <package>-links script the
# package, or install-files, put in sbin from links.sh.in. Run as root for
# /usr/local/bin. Neither install nor install-files does this itself, the
# choice being the administrator's.
.PHONY: links
links:			## Link the installed programs into LINKDIR
	for package in $(PACKAGES); do \
		$(DESTDIR)$(PREFIX)/sbin/$$package-links --dir $(LINKDIR) \
			|| exit 1; \
	done

.PHONY: unlinks
unlinks:			## Remove the links `make links` made
	for package in $(PACKAGES); do \
		$(DESTDIR)$(PREFIX)/sbin/$$package-links --remove \
			--dir $(LINKDIR) || exit 1; \
	done
