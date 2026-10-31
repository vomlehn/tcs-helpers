# tcs-helpers: one copy of what the tcs projects share for packaging,
# installed where they use it from.
#
#   make install     commands into $(BINDIR), data into $(DATADIR)
#   make uninstall   remove what install put there
#   make check       shellcheck every script
#
# The defaults install into your own home, so nothing needs root:
# ~/bin, which is on PATH, and ~/lib/tcs-helpers. Set PREFIX to install
# elsewhere, BINDIR and DATADIR to split them.

PREFIX  ?= $(HOME)
BINDIR  ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/lib/tcs-helpers

VERSION := $(shell cat VERSION)

# The commands, from bin/, each written from its .in with the version and
# the data directory filled in.
COMMANDS := $(patsubst bin/%.in,%,$(wildcard bin/*.in))

# The data, from lib/, installed as it is.
DATA := $(wildcard lib/*)

.PHONY: all
all:
	@echo "Nothing to build: run make install, or make help."

.PHONY: help
help:
	@sed -n 's/^#   //p' Makefile

.PHONY: install
install:
	install -d $(BINDIR) $(DATADIR)
	for c in $(COMMANDS); do \
		sed -e 's|@VERSION@|$(VERSION)|g' \
		    -e 's|@DATADIR@|$(DATADIR)|g' bin/$$c.in \
		    > $(BINDIR)/$$c.new \
		&& chmod 755 $(BINDIR)/$$c.new \
		&& mv $(BINDIR)/$$c.new $(BINDIR)/$$c || exit 1; \
	done
	$(if $(DATA),install -m 644 $(DATA) $(DATADIR))
	@echo "Installed tcs-helpers $(VERSION): $(BINDIR), $(DATADIR)"

.PHONY: uninstall
uninstall:
	for c in $(COMMANDS); do rm -f $(BINDIR)/$$c; done
	rm -rf $(DATADIR)

.PHONY: check
check:
	shellcheck $(wildcard bin/*.in) $(filter %.sh,$(DATA))
	@echo "shellcheck found nothing"
