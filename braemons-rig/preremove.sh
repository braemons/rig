#!/bin/sh
set -e

# The hostname it set stays: a box that loses its name on uninstall would drop
# off the network in the middle of whatever removed the package.
systemctl disable braemons-hostname.service >/dev/null 2>&1 || true
