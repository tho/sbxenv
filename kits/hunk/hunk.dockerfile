# syntax=docker/dockerfile:1
# hunk as an overlay: the whole release archive at /opt/hunk (binary,
# metadata.json, skills/) plus a /usr/local/bin/hunk symlink. The skills dir
# must ship: the skill text is not embedded in the binary, and hunk finds it
# relative to its executable path. Build-only base: see
# kits/chezmoi/chezmoi.dockerfile.
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

# From the descriptor (args.version). No default, so a missing pin fails the build.
ARG HUNK_VERSION

# Per-arch downloads; BuildKit only builds the stage TARGETARCH selects.
# Upstream names the archs arm64/x64. Digests from the release's SHA256SUMS
# (no signature; GitHub attestations: gh attestation verify -R modem-dev/hunk).
# The binary is a Bun single-file glibc build (glibc >= 2.17; trixie has 2.41).
FROM scratch AS dl-amd64
ARG HUNK_VERSION
ADD --checksum=sha256:4b8c98f8d97745499916cc1e1d2f27ffd258c6d6358dd4532f61e41c5eb19692 \
    https://github.com/modem-dev/hunk/releases/download/v${HUNK_VERSION}/hunkdiff-linux-x64.tar.gz \
    /hunk.tgz

FROM scratch AS dl-arm64
ARG HUNK_VERSION
ADD --checksum=sha256:ab49c8aba82c3c9872f1c5eefd96d1c4c2491e5b80647f97b2e81fc6c4676deb \
    https://github.com/modem-dev/hunk/releases/download/v${HUNK_VERSION}/hunkdiff-linux-arm64.tar.gz \
    /hunk.tgz

# hadolint expands no build args, so it reads this stage reference as an
# untagged image. Fixed upstream by hadolint PR #1264; drop this
# ignore once a hadolint release includes it.
# hadolint ignore=DL3006
FROM dl-${TARGETARCH} AS dl

FROM ${BASE_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG HUNK_VERSION

# Strip the archive's top dir (hunkdiff-linux-<arch>/); gate on the exact pin
# (bare "X.Y.Z").
RUN --mount=from=dl,source=/hunk.tgz,target=/tmp/hunk.tgz <<'EOF2'
set -eu
[ -n "${HUNK_VERSION}" ] || { echo "HUNK_VERSION must be set" >&2; exit 1; }
mkdir -p /out/opt/hunk /out/usr/local/bin
tar -C /out/opt/hunk --strip-components=1 --no-same-owner -xzf /tmp/hunk.tgz
[ -f /out/opt/hunk/skills/hunk-review/SKILL.md ] || { echo "archive lacks skills/hunk-review/SKILL.md" >&2; exit 1; }
chown -R 0:0 /out/opt/hunk
chmod -R a+rX,go-w /out/opt/hunk
chmod 0755 /out/opt/hunk/hunk
ln -s /opt/hunk/hunk /out/usr/local/bin/hunk
out="$(HUNK_DISABLE_UPDATE_NOTICE=1 /out/opt/hunk/hunk --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "hunk --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "${HUNK_VERSION}" || {
  echo "pin mismatch: descriptor says ${HUNK_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
EOF2

# Overlay: /opt/hunk + one symlink, nothing under /home, no ENTRYPOINT.
FROM scratch
COPY --from=build /out /
