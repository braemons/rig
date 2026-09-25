# braemons rig

This repository builds the packages that make a box a braemons rig, apart from
the daemons themselves. A rig can run any of the four daemons:
[vstimd](https://github.com/braemons/vstimd) drives the display,
[statemachined](https://github.com/braemons/statemachined) the state machine
board, [mousewheeld](https://github.com/braemons/mousewheeld) the running
wheel, and [triald](https://github.com/braemons/triald) the trial logic. What
they share lives here rather than in any one of them.

| package | what it installs | arch |
|---|---|---|
| `braemons-rig` | the box's name, `braemons-XXXXXX`, and `/etc/braemons` and `/var/lib/braemons` | all |
| `braemons-tools` | `vstimctl`, `statemachinectl`, `mousewheelctl` and `trialctl`, in one vendored Python | amd64, arm64 |
| `braemons` | depends on the two above, and recommends the four daemons | all |

```bash
sudo apt install braemons                          # a whole rig
sudo apt install --no-install-recommends braemons  # the rig and the tools, no daemons yet
sudo apt install braemons-tools                    # the tools on a workstation
```

The packages come from the braemons apt archive. See
[braemons/packages](https://github.com/braemons/packages) for how to add it to a
machine.

**No daemon depends on anything here.** A box that runs only statemachined
installs `braemons-statemachined` and works. It keeps its stock hostname until
`braemons-rig` is installed, and its tool is a `pip install` away.

## `braemons-rig`: the rig's name

`braemons-hostname.service` runs at boot, before Avahi and Samba start, and
names the box `braemons-XXXXXX`. `XXXXXX` is the last six hex digits of the
primary network interface's MAC address. The name:

- is the same on every boot and survives a re-flash, with no stored state;
- is 15 characters, Samba's NetBIOS limit, so `\\braemons-a1b2c3` and
  `braemons-a1b2c3.local` are the same name;
- follows the board, not the SD card.

The interface is `eth0`, `end0` or `eno1`, else the first non-loopback one with
a MAC. The unit waits up to 20 s for it, because a Raspberry Pi 5's NIC can
enumerate late.

It is enabled when the package is installed and takes effect at the next boot.
Run `sudo systemctl start braemons-hostname` to rename the box now, or
`sudo systemctl disable braemons-hostname` and `hostnamectl` to name it by hand.
Nothing else reads the name: every daemon advertises `_<daemon>._tcp` over mDNS
itself, under whatever the hostname is, with a `rig=` TXT record they all share
(`sha256("braemons:" + machine-id)`), which is how a console groups them.

## `braemons-tools`: the four commands

Each daemon's Python client installs one command, and the four follow the same
rules, written down in
[contracts/DAEMON_LAYOUT.md](https://github.com/braemons/contracts/blob/main/DAEMON_LAYOUT.md):

- `--rig HOST[:PORT]`, else `$BRAEMONS_RIG`, else `localhost`. Each command fills
  in its own daemon's port, so `export BRAEMONS_RIG=braemons-a1b2c3.local`
  reaches all four daemons on one box.
- JSON on stdout. A stream prints one object per line.
- A failure is one JSON object on stderr, with the same exit statuses from all
  four: 3 means nothing answered, 5 refused, and 6 not found.

This package puts all four on a rig without pip. They run from a CPython 3.12 of
their own under `/opt/braemons/tools`, because three of the clients need 3.12
and Raspberry Pi OS ships 3.11, and because an OS upgrade that moves Python must
not break the tools a rig is repaired with. The launchers in `/usr/bin` run it
with `-I`, so nothing in the caller's environment chooses the code.

Which release of each client goes in is pinned in
[`braemons-tools/clients.txt`](braemons-tools/clients.txt). Bumping a pin is a
deliberate change, like a pin in the end-to-end suite.

## Building

```bash
make packages                 # all three, for this machine, into dist/
make check                    # stage the tools and run each command's --version
make check CLIENTS=local.txt  # the same against client checkouts, one path per line
```

The version is the latest `v*` tag (`scripts/git-version.sh`), or
`RIG_VERSION=...`. It needs `uv` and `nfpm`. A tag builds the release:

```bash
git tag v0.3.0-alpha1 && git push origin v0.3.0-alpha1
```

## Licence

AGPL-3.0-or-later.
