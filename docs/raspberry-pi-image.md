# Raspberry Pi 5 rig image

Every [release](https://github.com/braemons/rig/releases) of this repository
ships a ready-to-flash Raspberry Pi OS Lite (arm64) image with a whole braemons
rig installed and configured: the four daemons (vstimd, statemachined,
mousewheeld, triald), gpiochip-daqd, the console, and the command-line tools.
Write it to an SD card, plug the Pi in, and it comes up as a rig on the
network — no install steps, no keyboard, no monitor needed for setup.

This page is the flash-to-first-experiment walkthrough. To do the same thing by
hand on other hardware (Jetson, desktop x86, a different Pi model), follow
[Manual appliance setup](https://vstimd.readthedocs.io/en/latest/operations/appliance-setup/) instead. To build the image
yourself, see [Building the image](#building-the-image) below.

---

## What you need

| | |
|---|---|
| Board | Raspberry Pi 5 (validated on the 8 GB Model B Rev 1.1) |
| Power | The official 27 W USB-C supply. A weaker one boots but throttles — a red status LED after firmware init usually means an underpowered PSU |
| Storage | microSD card, **16 GB or larger** (the image expands to ~6.5 GB before the rootfs grows to fill the card) |
| Network | Wired Ethernet to the same LAN/subnet as your experiment PC. Discovery is mDNS, which does not cross subnets |
| Display | HDMI cable into the Pi 5's **micro-HDMI** port — use `HDMI0`, the one nearest the USB-C connector |
| Optional | GPIO wiring for hardware triggers; a DisplayLink USB screen for auxiliary output |

---

## 1. Download and verify

From the [releases page](https://github.com/braemons/rig/releases), grab both:

- `braemons-<version>-raspios-lite-arm64.img.xz`
- `braemons-<version>-raspios-lite-arm64.img.xz.sha256`

Then check the download before spending ten minutes writing a corrupt card. The
`.sha256` file names the image by its bare filename, so run the check from the
directory holding both:

=== "Linux / macOS"

    ```bash
    sha256sum -c braemons-*-raspios-lite-arm64.img.xz.sha256
    # → braemons-….img.xz: OK
    ```

    On macOS use `shasum -a 256 -c` instead.

=== "Windows (PowerShell)"

    ```powershell
    (Get-FileHash .\braemons-0.3.0-raspios-lite-arm64.img.xz -Algorithm SHA256).Hash.ToLower()
    Get-Content .\braemons-0.3.0-raspios-lite-arm64.img.xz.sha256
    # the two hashes must match
    ```

!!! note "Pre-releases"
    A tag like `v0.3.0-alpha1` is published as a GitHub **pre-release**, so it is
    not badged "Latest" — tick *Show pre-releases* on the releases page if you are
    tracking alphas. Images built from a pre-release also track the archive's
    `testing` suite, so they keep receiving pre-releases; see
    [Updating](#5-updating-never-re-flash).

## 2. Flash with balenaEtcher

[balenaEtcher](https://etcher.balena.io/) reads `.xz` directly — **do not
decompress the image first**.

1. Insert the microSD card (a USB reader is fine).
2. Open Etcher → **Flash from file** → select the `.img.xz` you just verified.
3. **Select target** → pick the card. Check the size and drive letter; Etcher
   hides system drives, but confirm you are not about to overwrite a backup disk.
4. **Flash!** — then let it finish its verification pass.
5. Windows may pop up *"You need to format the disk before you can use it"* when
   Etcher is done. **Cancel it.** Windows is seeing the Linux root partition it
   cannot read; formatting would destroy the card you just wrote.

Eject the card and move on to first boot.

??? tip "Alternatives to Etcher"
    **Raspberry Pi Imager** — choose *Use custom* and select the `.img.xz`. When
    it offers OS customisation, choose **No**: the image already has its own
    login user, and Imager's customisation writes a `userconf.txt` for a
    first-boot wizard this image deliberately disables.

    **`dd` (Linux/macOS)** — no verification pass, so check the hash first:

    ```bash
    xz -dc braemons-<version>-raspios-lite-arm64.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
    ```

    Get `/dev/sdX` wrong and you overwrite the wrong disk. `lsblk` before, always.

## 3. First boot

Insert the card, connect Ethernet and the display, then power up.

The first boot expands the root filesystem to fill the card and reboots once by
itself; allow a couple of minutes before the rig answers. It then boots straight
into `vstimd.target` — no desktop, no login prompt on the primary console —
and the attached display shows vstimd's output (a black screen with the
configured background, not a terminal). The other daemons and the console come
up alongside it.

There is **no interactive setup wizard**: the stock Raspberry Pi OS first-boot
user prompt is disabled in the image precisely so a raw-flashed card
(Etcher, `dd`) does not sit waiting on a keyboard nobody plugged in.

### Find it on the network

The rig names itself `braemons-XXXXXX` from its MAC address (`braemons-rig`,
from this repository), and each daemon advertises itself over mDNS
(`_vstimd._tcp`, `_statemachined._tcp`, and so on). See
[Discovery & hostnames](https://vstimd.readthedocs.io/en/latest/operations/discovery/) for the full policy.

```console
$ vstimctl discover | jq -r '.[].address'
tcp://braemons-a1b2c3.local:5555
```

Without the Python client installed, `avahi-browse -r _vstimd._tcp` (Linux),
`dns-sd -B _vstimd._tcp` (macOS, and Windows with Bonjour installed — see
[Discovery on Windows](https://vstimd.readthedocs.io/en/latest/operations/discovery/#on-windows-without-the-python-client)), or
your router's DHCP lease table will do.

Quickest confirmation that it is alive: browse to
**`http://braemons-XXXXXX.local:9000`** — the
[console](https://github.com/braemons/console), every daemon's panels on one
page, served from the rig itself and needing nothing installed locally.

| | port | |
|---|---|---|
| console | 9000 | every daemon on one page |
| vstimd | 8080 (web), 5555 (API) | the display; its own [web UI](https://vstimd.readthedocs.io/en/latest/client/web/) |
| statemachined | 8081 | the state machine board; enabled, and waits for its board |
| mousewheeld | 8083 | the running wheel; installed but **not enabled** until `/etc/braemons/mousewheeld-rig-config.toml` names the board's port, then `sudo systemctl enable --now mousewheeld` |
| triald | 8420 | the trial logic; listens on **loopback** until its rig config says otherwise, because its API runs Python |

### Put something on the display

`vstimctl scene-configs load demos/first_light` shows a self-explaining scene; the
other [demo scenes](https://vstimd.readthedocs.io/en/latest/getting-started/demos/) cover a drifting grating,
trigger-driven flashes and a photodiode flicker. The trigger demos use the
header pins this image's `gpiochip-daqd` config already wires up, so they drive
real pins with nothing further to configure.

## 4. Get in

### SSH

```bash
ssh braemons-admin@braemons-a1b2c3.local
```

| | |
|---|---|
| User | `braemons-admin` — a normal `sudo` account, **not** one of the daemons' service accounts (which have no login shell). Also in `dialout`, `gpio`, `i2c`, `spi`, `video`, `render`, `input`, `plugdev`, `adm` and `systemd-journal`, so the boards, the header and the daemons' logs are reachable without `sudo` |
| Password | `braemons`, unless the release notes for your download say otherwise |
| First login | You are **forced to change the password** (`chage -d 0`) before you get a shell |

Changing it also changes the Samba password: a `pam_exec` hook sits in the
password-change stack and pushes the new value into Samba's passdb, so the two
never drift apart.

!!! danger "The default login is public"
    Anyone can download the image and read the password out of it. Change it at
    first login (you are made to), and treat these rigs as **lab-network
    devices** — the network is the security boundary. Do not expose one to the
    internet.

Windows has a built-in `ssh` client in PowerShell; PuTTY works too (host
`braemons-a1b2c3.local`, port 22).

### Files over SMB/CIFS

Two shares are exported, so you can edit configs and pull saved scenes from a
lab Windows or macOS machine without an SSH session:

| Share | Path on the rig | Contents |
|---|---|---|
| `braemons-config` | `/etc/braemons` | every daemon's rig config (`vstimd-rig-config.toml`, `gpiochip-daqd-config.toml`, …) and `console.env` |
| `braemons-data` | `/var/lib/braemons` | every daemon's documents, one directory each: vstimd's saved scene-configs, triald's sessions, … |

Both are **browsable read-only by anyone on the LAN with no credentials**;
writing requires the `braemons-admin` login.

=== "Windows"

    In Explorer's address bar:

    ```
    \\braemons-a1b2c3\braemons-config
    ```

    Read-only browsing needs no credentials. To write, map it as a drive with
    *Connect using different credentials* and log in as `braemons-admin`.

=== "macOS"

    Finder → **Go → Connect to Server** (++cmd+k++):

    ```
    smb://braemons-a1b2c3.local/braemons-data
    ```

    Choose *Guest* to read, or *Registered User* → `braemons-admin` to write.

=== "Linux"

    ```bash
    # Read-only, no credentials:
    sudo mount -t cifs //braemons-a1b2c3.local/braemons-data /mnt -o guest,vers=3.0

    # Read-write:
    sudo mount -t cifs //braemons-a1b2c3.local/braemons-config /mnt \
        -o username=braemons-admin,vers=3.0
    ```

    Requires `cifs-utils`. A desktop file manager can also open
    `smb://braemons-a1b2c3.local/` directly via gvfs.

!!! info "The rig shows up in Explorer's Network list"
    Samba announces itself over NetBIOS, but modern Windows builds that list
    from WS-Discovery instead — so the image also ships `wsdd2`, enabled by
    default, to cover that. On a hand-built rig without it, `\\braemons-a1b2c3`
    still connects fine typed directly; only the icon is missing.

After editing a rig config, restart that daemon so it takes effect:

```bash
sudo systemctl restart vstimd    # or statemachined, mousewheeld, triald, braemons-console
```

### Drive it from an experiment script

```python
from vstimd_client import VstimdClient

with VstimdClient("tcp://braemons-a1b2c3.local:5555") as conn:
    print(conn.system.query_server_info())
```

or from a shell, with the tools the image installs (`braemons-tools`):
`vstimctl --rig braemons-a1b2c3.local state`, and likewise `statemachinectl`,
`mousewheelctl` and `trialctl`.

## 5. Updating — never re-flash

Re-flashing wipes `/etc/braemons` and `/var/lib/braemons`: the rig config and
every project of saved scene-configs. The image ships with the braemons apt archive
already configured and its signing key installed, so upgrades are in place:

```bash
sudo apt update && sudo apt upgrade
```

See [Deployment → Updating a deployed rig](https://vstimd.readthedocs.io/en/latest/operations/deployment/#updating-a-deployed-rig)
for how the `stable`/`testing` suites and conffile handling work. Reserve
re-flashing for a new rig or a failed card.

---

## What is baked into the image

| | |
|---|---|
| Base | Raspberry Pi OS Lite (arm64), rootfs grown by 4 GB for the DKMS builds |
| Packages | From the apt archive: `braemons` (`braemons-rig`, `braemons-tools`), `braemons-vstimd`, `braemons-gpiochip-daqd`, `braemons-statemachined`, `braemons-mousewheeld`, `braemons-triald`, `braemons-console`. A release's own `braemons-rig`, `braemons-tools` and `braemons` go in from that release, before the archive has them |
| Boot | Default target set to `vstimd.target`; `vstimd`, `gpiochip-daqd`, `statemachined`, `triald`, `braemons-console` and `braemons-hostname` enabled; `mousewheeld` installed, not enabled |
| Console | `CONSOLE_HOST=0.0.0.0` in `/etc/braemons/console.env`, so a laptop on the rig network opens it |
| Rig config | `/usr/share/braemons/vstimd/raspberry-pi-5.toml` installed as `/etc/braemons/vstimd-rig-config.toml` (not the generic all-commented-out default) |
| GPIO config | `raspberry-pi-5_in16_out4.toml` installed as `/etc/braemons/gpiochip-daqd-config.toml` |
| Services | `sshd`, `smbd`/`nmbd` with both shares (`braemons-rig`'s `braemons-shares.conf`), `avahi-daemon`, `wsdd2` |
| Login | `braemons-admin` in `sudo` and the device and log groups, password change forced at first login, Samba password kept in sync by a `pam_exec` hook |
| Updates | `/etc/apt/sources.list.d/braemons.sources` + `/etc/apt/keyrings/braemons.asc`, plus an unattended-upgrade conffile policy so a headless rig never hangs on a dpkg prompt |
| DisplayLink | `displaylink-driver` with `evdi` pinned to 1.14.16 and DKMS-built for both shipped kernels (see [caveats](https://vstimd.readthedocs.io/en/latest/developer/platform-notes/)) |
| Workaround | udev rule disabling Energy-Efficient Ethernet, which otherwise drops the Pi 5's link |
| Dev tooling | `git`, `build-essential`, the vstimd build dependencies, `protobuf-compiler` with the well-known types (`libprotobuf-dev`), `cmake`, `ninja-build`, `clang`/`clangd`, `npm`, `dfu-util`, `shellcheck`, `gh`; for `braemons-admin` a rustup toolchain and uv with PlatformIO 6.1.16 and clang-format 23.1.0; plus `btop`, `vim`, `tmux`. Enough to build, test and flash every repository in the family on the Pi itself |

The stock `dtoverlay=vc4-kms-v3d` (full KMS) that vstimd's DRM backend needs is
already the Raspberry Pi OS default — no `config.txt` edit is required.

---

## Troubleshooting

Nothing on the display
:   Check the cable is in the **`HDMI0`** micro-HDMI port (nearest USB-C), and
    that it was connected at boot. Then SSH in and run
    `systemctl status vstimd` and `journalctl -u vstimd -b`.

Red status LED, board does not come up
:   Almost always the power supply. Use the official 27 W USB-C unit.

The Ethernet link keeps dropping
:   Energy-Efficient Ethernet; the image already ships the udev rule that
    disables it. Confirm with `ethtool --show-eee eth0`. On a rig set up by hand,
    see [Platform notes](https://vstimd.readthedocs.io/en/latest/developer/platform-notes/).

Still called `raspberrypi`, or `discover` finds nothing
:   See [Discovery & hostnames → Troubleshooting](https://vstimd.readthedocs.io/en/latest/operations/discovery/#troubleshooting).

A DisplayLink screen flickers on and off
:   Do not power it through a USB-C power switch. And note DisplayLink output is
    only appropriate for behavioural training or auxiliary displays — it has no
    GPU vsync, so stimulus onset cannot be trusted to the frame. See
    [Platform notes](https://vstimd.readthedocs.io/en/latest/developer/platform-notes/).

---

## Building the image

```bash
make image                                   # dist/braemons-<version>-raspios-lite-arm64.img.xz (+ .sha256)
make image IMAGE_EXTRA_DEBS="dist/a.deb dist/b.deb"   # with .debs that are not in the archive yet
make image APT_SUITE=stable                  # choose the suite; a pre-release version picks testing
```

`image/build-sd-image.sh` runs inside `image/Dockerfile`, which loop-mounts a
stock Raspberry Pi OS Lite image, chroots into it under qemu, and installs
everything from the [braemons apt archive](https://github.com/braemons/packages).
It needs Docker with `--privileged` and an arm64 binfmt handler on the host:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

- Slow: most of the time goes on DKMS-building the evdi module for every kernel
  in the image under emulation (about 40 minutes on a GitHub-hosted runner).
  Needs ~10 GB free: a ~6.5 GB working image plus the compressed output.
- The base image is cached in `image/.cache/`; `FORCE_DOWNLOAD=1` refreshes it.
- Extra `.debs` must sit under `dist/`, the only directory the container sees.
  They are installed in the same apt transaction as the archive's packages and
  win over the archive's version of the same package.
- The build fails if any of the packages above is missing afterwards; a
  Recommends that apt could not find would otherwise leave a rig without it.
- The login is `IMAGE_USER` / `IMAGE_PASSWORD` (default `braemons-admin` /
  `braemons`). `IMAGE_PASSWORD=""` generates a random one per build and writes
  it to `dist/*-credentials.txt`, which never belongs in git or a release; the
  release workflow uploads only `*.img.xz*`.
- A release (`git tag v…`) builds the image from that release's own three
  packages, and attaches it. Set an `IMAGE_PASSWORD` repository secret to give
  published images a password other than the default.
