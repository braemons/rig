# The three packages a braemons rig is built from, besides the daemons' own.
#
#   make packages       all three, for this machine's architecture, into dist/
#   make rig            braemons-rig    (arch: all)
#   make tools          braemons-tools  (this architecture: a vendored Python)
#   make meta           braemons        (arch: all)
#   make check          stage the tools and run each command's --version
#
# The version is the git tag's (scripts/git-version.sh); pass RIG_VERSION=... to
# build outside a tagged checkout. nfpm and uv are the only tools needed.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD := $(ROOT)/build
TOOLS := $(BUILD)/tools
DIST ?= $(ROOT)/dist

UV ?= uv
NFPM ?= nfpm

# The interpreter braemons-tools vendors. 3.12 because three of the four
# clients require it, and Raspberry Pi OS ships 3.11.
PYTHON_VERSION ?= 3.12

MAINTAINER ?= Joscha Schmiedt <joscha.schmiedt@gmail.com>

RESOLVED_VERSION := $(shell RIG_VERSION='$(RIG_VERSION)' $(ROOT)/scripts/git-version.sh 2>/dev/null)
VERSION = $(or $(RESOLVED_VERSION),$(error Cannot determine the version. Run \
scripts/git-version.sh to see why, or pass RIG_VERSION=<version>))

# dpkg's names for the two architectures a rig runs on.
UNAME_M := $(shell uname -m)
ARCH := $(if $(filter x86_64,$(UNAME_M)),amd64,$(if $(filter aarch64 arm64,$(UNAME_M)),arm64,))

COMMANDS := vstimctl statemachinectl mousewheelctl trialctl

# Exported only where a package is cut, so `make clean` works in a checkout with
# no tag.
rig meta tools: export VERSION = $(or $(RESOLVED_VERSION),$(error Cannot determine the version))
rig meta tools: export MAINTAINER := $(MAINTAINER)
rig meta tools: export ARCH := $(ARCH)

# Which clients to install. The pinned releases, unless a local build of the
# tools against checkouts is wanted: `make check CLIENTS=local-clients.txt`.
CLIENTS ?= braemons-tools/clients.txt

.PHONY: packages rig tools meta stage-tools check print-version clean help

help:
	@sed -n 's/^#   make \([a-z-]*\) *\(.*\)/  \1|\2/p' $(MAKEFILE_LIST) | column -t -s '|'

packages: rig tools meta

rig:
	@mkdir -p $(DIST)
	cd braemons-rig && $(NFPM) package -f nfpm.yaml -p deb -t $(DIST)/

meta:
	@mkdir -p $(DIST)
	cd braemons && $(NFPM) package -f nfpm.yaml -p deb -t $(DIST)/

tools: check
	@mkdir -p $(DIST)
	cd braemons-tools && $(NFPM) package -f nfpm.yaml -p deb -t $(DIST)/

# The tree that lands in /opt/braemons/tools: a relocatable CPython from
# python-build-standalone, copied out of uv's store rather than linked into it,
# with the four clients installed into it from clients.txt.
stage-tools: $(TOOLS)/.stamp
$(TOOLS)/.stamp: $(CLIENTS)
	@test -n "$(ARCH)" || { echo "error: no dpkg architecture known for $(UNAME_M)"; exit 1; }
	rm -rf $(TOOLS) && mkdir -p $(TOOLS)
	$(UV) python install --managed-python $(PYTHON_VERSION)
	cp -a "$$(dirname $$(dirname $$($(UV) python find --managed-python $(PYTHON_VERSION))))/." $(TOOLS)/
	@# uv marks its own installs externally managed; this copy is a package
	@# being built, and the clients are about to be installed into it.
	find $(TOOLS) -name EXTERNALLY-MANAGED -delete
	$(UV) pip install --python $(TOOLS)/bin/python3 --no-cache --prerelease allow \
	  -r $(CLIENTS)
	@# The console scripts pip wrote name this build's path in their shebang.
	@# /usr/bin carries launchers of its own (braemons-tools/bin/) instead.
	rm -f $(addprefix $(TOOLS)/bin/,$(COMMANDS))
	find $(TOOLS) -name __pycache__ -type d -prune -exec rm -rf {} +
	@touch $@

# Each command, run from the staged tree the way its launcher runs it: -I, and
# the import its launcher names. A command that cannot print its version is a
# package that installs a broken tool.
check: stage-tools
	@for launcher in braemons-tools/bin/*; do \
	  module=$$(sed -n 's/^from \([a-z_.]*\) import main$$/\1/p' $$launcher); \
	  $(TOOLS)/bin/python3 -I -c "import sys; from $$module import main; sys.exit(main(['--version']))" \
	    || exit 1; \
	done

print-version:
	@echo $(VERSION)

clean:
	rm -rf $(BUILD) $(DIST)
