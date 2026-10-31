# packaging.mk: the make rules the TCS projects share for packaging what
# they install, included by each project's Makefile from the tcs-helpers
# checkout:
#
#   include $(TCS_HELPERS)/packaging/packaging.mk
#
# It gives the targets
#
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
#   PREFIX         where install installs, for links and unlinks
#   TCS_HELPERS    this checkout
#   tcs-helpers    a target that stops unless TCS_HELPERS is a checkout
#                  new enough for the project, which every target here
#                  but links and unlinks depends on
#
# and, if it needs to:
#
#   TCS_SOURCE     the source package's name, by default the first of
#                  PACKAGES
#   STAGE_TARGET   the target that installs a package, by default install;
#                  $$package in it is the package's name
#   STAGE_VARS     more variables the stage's install is given
#   RPM_DEFINES    more --define options for rpmbuild, as the specs need
#   LINT_SCRIPTS   more shell scripts for lint-packages to check
#
# A project keeps what differs between projects in its packaging directory:
# packaging/deb/<package>/DEBIAN, with the control file and maintainer
# scripts build-deb.sh takes, packaging/deb/<package>/lintian-overrides and
# packaging/deb/copyright.in, which debian-files.sh takes, and
# packaging/rpm/<package>.spec, with the rpmlint.toml lint-packages gives
# rpmlint. A spec is given tcs_version, tcs_date, the date of the changelog
# entry, and tcs_stage, the package's stage, besides RPM_DEFINES.
#
# STRIP=0 on the command line, or in the environment, reaches the stage's
# install as it does any sub-make, and leaves the packages unstripped.

TCS_SOURCE   ?= $(firstword $(PACKAGES))
STAGE_TARGET ?= install
LINKDIR      ?= /usr/local/bin

# Where the packages are built: build/, which git ignores. The stage is one
# directory per package, installed into with the paths the package is for
# and the hooks on, so that the package is exactly what install installs.
STAGE       := $(CURDIR)/build/stage
PACKAGE_DIR := $(CURDIR)/build/packages
DEB_TOP     := $(CURDIR)/build/deb
RPM_TOP     := $(CURDIR)/build/rpm

# The Debian revision, for a package rebuilt from the same source.
DEB_REVISION ?= 1
DEB_VERSION  := $(VERSION)-$(DEB_REVISION)

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

# The .deb, one per staged package: see build-deb.sh.
.PHONY: deb
deb: stage			## Build the .debs in build/packages
	for package in $(PACKAGES); do \
		$(TCS_HELPERS)/packaging/build-deb.sh \
			$(CURDIR)/packaging/deb $(TCS_SOURCE) $$package \
			$(STAGE)/$$package $(DEB_TOP) $(PACKAGE_DIR) \
			$(DEB_VERSION) $$(dpkg --print-architecture) \
			$(SOURCE_DATE_EPOCH) || exit 1; \
	done
	@echo "[OK] .debs in $(PACKAGE_DIR)"

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
		$(wildcard $(foreach package,$(PACKAGES), \
			$(PACKAGE_DIR)/$(package)_$(DEB_VERSION)_*.deb \
			$(PACKAGE_DIR)/$(package)-$(VERSION)-*.rpm)) \
		-- $(wildcard $(STAGE)/*/opt/tcs/sbin/*-links \
			$(STAGE)/*/etc/profile.d/*.sh) \
		$(wildcard $(foreach script,preinst postinst prerm postrm, \
			packaging/deb/*/DEBIAN/$(script))) \
		$(LINT_SCRIPTS)

# Link the installed programs into LINKDIR, which every environment
# searches, or take those links away, with the <package>-links script
# install put in sbin from links.sh.in. Run as root for /usr/local/bin.
# install never does this itself, the choice being the administrator's.
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
