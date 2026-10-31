# tcs-helpers: one copy of what the tcs projects share for packaging, used
# from this checkout rather than installed.
#
#   make README.html write README.html from README.md
#   make check       shellcheck every script
#   make uninstall   remove what make install put in ~/bin and ~/lib in
#                    version 0.1.0, which installed it
#
# A project finds this checkout beside itself, as ../tcs-helpers, or
# wherever its TCS_HELPERS says: see README.md.

# Where version 0.1.0's `make install` put things, which is what uninstall
# removes: ~/bin/tcs-helpers and ~/lib/tcs-helpers, or the same under the
# PREFIX, BINDIR and DATADIR that install was given.
PREFIX  ?= $(HOME)
BINDIR  ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/lib/tcs-helpers

.PHONY: all
all:
	@echo "Nothing to build: tcs-helpers is used from this checkout."
	@echo "See make help and README.md."

.PHONY: help
help:
	@sed -n 's/^#   //p' Makefile

# README.md is the documentation; README.html is it as a page of its own,
# with pandoc's --standalone giving it a head and a title.
README.html: README.md
	pandoc --standalone --metadata pagetitle=tcs-helpers README.md \
		-o README.html

.PHONY: check
check:
	shellcheck bin/tcs-helpers packaging/lint-packages.sh \
		packaging/debian-files.sh packaging/build-deb.sh
	sed -e 's|@PACKAGE@|example|g' -e 's|@PREFIX@|/opt/tcs|g' \
		-e 's|@PROGRAMS@|example|g' packaging/links.sh.in \
		| shellcheck -s sh -
	@echo "shellcheck found nothing"

.PHONY: uninstall
uninstall:
	rm -f $(BINDIR)/tcs-helpers
	rm -rf $(DATADIR)
	@echo "Removed anything installed in $(BINDIR) and $(DATADIR)"
