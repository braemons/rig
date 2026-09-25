#!/bin/sh
set -e

systemd-tmpfiles --create /usr/lib/tmpfiles.d/braemons.conf 2>/dev/null || true

if [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
fi

# Enabled, not started: renaming a box under a running session is a surprise
# nobody wants from `apt install`. The name takes effect at the next boot, or
# now with `systemctl start braemons-hostname`.
systemctl enable braemons-hostname.service >/dev/null 2>&1 || true

cat <<'MESSAGE'
braemons-rig is installed. At the next boot this box is named
braemons-XXXXXX, after its network interface's MAC address.
To rename it now:   sudo systemctl start braemons-hostname
To name it by hand: sudo systemctl disable braemons-hostname
MESSAGE
