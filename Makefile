# The three packages a braemons rig is built from, besides the daemons' own,
# and the Raspberry Pi image that puts all of them on a card.
#
#   make packages       all three, for this machine's architecture, into dist/
#   make rig            braemons-rig    (arch: all)
#   make tools          braemons-tools  (this architecture: a vendored Python)
#   make meta           braemons        (arch: all)
#   make check          stage the tools and run each command's --version
#   make image          the Raspberry Pi SD image, from the apt archive (docker)
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

# ── The Raspberry Pi SD image ───────────────────────────────────────────────
#
# Every package comes from the apt archive: `braemons` and everything it
# recommends, and gpiochip-daqd. More .debs go in beside them and win over the
# archive's version, which is how an image takes packages that are not released
# yet: make image IMAGE_EXTRA_DEBS="dist/braemons-rig_0.3.0~alpha1_all.deb"
# Paths must be under dist/, the only directory the container sees.
IMAGE_BUILDER ?= braemons-image-builder
IMAGE_CACHE_DIR ?= image/.cache
IMAGE_EXTRA_DEBS ?=
# The version in the image's file name, and the suite it tracks: a
# pre-release (a '~' in it) installs from and upgrades on `testing`.
IMAGE_VERSION ?= $(VERSION)
# Login user/password baked into the image (SSH + Samba). The image forces a
# password change at first login. IMAGE_PASSWORD="" generates a random one per
# build and writes it to dist/*-credentials.txt, which must stay out of git.
IMAGE_USER ?= braemons-admin
IMAGE_PASSWORD ?= braemons

.PHONY: packages rig tools meta stage-tools check image print-version clean help

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

image:
	docker build -f image/Dockerfile -t $(IMAGE_BUILDER) .
	mkdir -p $(DIST) $(IMAGE_CACHE_DIR)
	docker run --rm --privileged \
	  -v $(DIST):/src/dist \
	  -v $(abspath $(IMAGE_CACHE_DIR)):/src/$(IMAGE_CACHE_DIR) \
	  -e IMAGE_USER=$(IMAGE_USER) \
	  -e IMAGE_PASSWORD=$(IMAGE_PASSWORD) \
	  -e IMAGE_VERSION=$(IMAGE_VERSION) \
	  -e CACHE_DIR=$(IMAGE_CACHE_DIR) \
	  -e DIST_DIR=dist \
	  $(if $(FORCE_DOWNLOAD),-e FORCE_DOWNLOAD=1) \
	  $(if $(APT_SUITE),-e APT_SUITE=$(APT_SUITE)) \
	  $(IMAGE_BUILDER) $(IMAGE_EXTRA_DEBS)

print-version:
	@echo $(VERSION)

clean:
	rm -rf $(BUILD) $(DIST)
