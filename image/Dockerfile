# Toolchain for image/build-sd-image.sh: turns a stock Raspberry Pi OS Lite
# (arm64) image into a ready-to-flash braemons rig.
#
# Needs loop devices + mount + chroot, so the container must run with
# --privileged (see `make image`). qemu-user-static provides the arm64
# binfmt handler so `chroot` into the arm64 rootfs works on an amd64 host —
# the handler is registered against the host kernel's binfmt_misc, which is
# normally already set up on Linux CI runners/dev hosts that have
# qemu-user-static installed; if not, run this once on the host:
#   docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
#
# Usage: see `make image`.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl openssl xz-utils util-linux \
        parted e2fsprogs dosfstools \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# The script and the archive key it installs. Only dist/ and the cache dir are
# bind-mounted at run time, so anything the script reads out of the repo has
# to be COPYed in here or it is simply not there.
COPY image/build-sd-image.sh image/braemons-archive-keyring.asc image/

ENTRYPOINT ["image/build-sd-image.sh"]
