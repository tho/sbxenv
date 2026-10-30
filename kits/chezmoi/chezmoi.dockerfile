# syntax=docker/dockerfile:1
# chezmoi as an overlay: one pinned, digest-verified static binary at
# /usr/local/bin/chezmoi (layout after sbx-kits-contrib mise, v3 branch).
#
# Build-only base: public Debian trixie (glibc 2.41, like the sandbox),
# pinned by digest, so host builds need no registry login (Docker's dhi.io
# base refuses anonymous pulls). Downloads use ADD --checksum, so it needs no
# curl. The overlay is FROM scratch.
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

# From the descriptor (args.version). No default, so a missing pin fails the build.
ARG CHEZMOI_VERSION

# Per-arch downloads; BuildKit only builds the stage TARGETARCH selects.
# amd64 uses the musl tarball (the plain linux_amd64 one is glibc-linked);
# linux_arm64 is already static. Digests from chezmoi_<version>_checksums.txt
# (cosign-signed; see kits/README.md).
FROM scratch AS dl-amd64
ARG CHEZMOI_VERSION
ADD --checksum=sha256:f2fbda5a865e2725adc42090ea6deabf3e1a4d40bfd59a8942c3ad20284b39cb \
    https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux-musl_amd64.tar.gz \
    /chezmoi.tgz

FROM scratch AS dl-arm64
ARG CHEZMOI_VERSION
ADD --checksum=sha256:c9e6a6e71eb5291018e161a8426d7c313cd2e8553c2ca4029511fec2a33bc28c \
    https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_arm64.tar.gz \
    /chezmoi.tgz

# hadolint expands no build args, so it reads this stage reference as an
# untagged image. Fixed upstream by hadolint PR #1264; drop this
# ignore once a hadolint release includes it.
# hadolint ignore=DL3006
FROM dl-${TARGETARCH} AS dl

FROM ${BASE_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG CHEZMOI_VERSION

# Extract, then gate on the exact pin. chezmoi prints "chezmoi version vX.Y.Z,
# commit …", hence "v<pin>".
RUN --mount=from=dl,source=/chezmoi.tgz,target=/tmp/chezmoi.tgz <<'EOF2'
set -eu
[ -n "${CHEZMOI_VERSION}" ] || { echo "CHEZMOI_VERSION must be set" >&2; exit 1; }
mkdir -p /tmp/chezmoi /out/usr/local/bin
tar -C /tmp/chezmoi -xzf /tmp/chezmoi.tgz chezmoi
install -m 0755 -o 0 -g 0 /tmp/chezmoi/chezmoi /out/usr/local/bin/chezmoi
rm -rf /tmp/chezmoi
out="$(/out/usr/local/bin/chezmoi --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "chezmoi --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "v${CHEZMOI_VERSION}" || {
  echo "pin mismatch: descriptor says ${CHEZMOI_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
EOF2

# Overlay: one file under /usr/local/bin, nothing under /home, no ENTRYPOINT.
FROM scratch
COPY --from=build /out /
