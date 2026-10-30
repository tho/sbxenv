# syntax=docker/dockerfile:1
# uv as an overlay: Astral's pinned, digest-verified release binaries at
# /usr/local/bin/{uv,uvx}. /usr/local/bin precedes /usr/bin on PATH, so they
# shadow sbx-kit-shell's /usr/bin/uv (see uv.yaml for why). Build-only base:
# see kits/chezmoi/chezmoi.dockerfile.
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

# From the descriptor (args.version). No default, so a missing pin fails the build.
ARG UV_VERSION

# Per-arch downloads; BuildKit only builds the stage TARGETARCH selects.
# The glibc builds (glibc >= 2.28; trixie has 2.41), which Astral's own
# installer picks too. Digests from the release's <asset>.sha256 files;
# GitHub attestations: gh attestation verify <file> -R astral-sh/uv.
FROM scratch AS dl-amd64
ARG UV_VERSION
ADD --checksum=sha256:f29c3e94ffabd7e6f3ba521dba169a9b7ec12100bf3257087f0f24f6123f3645 \
    https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz \
    /uv.tgz

FROM scratch AS dl-arm64
ARG UV_VERSION
ADD --checksum=sha256:229e194255c7958d86d56e8790d969a6f74736592133f0dfd0076f754c642c1d \
    https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-aarch64-unknown-linux-gnu.tar.gz \
    /uv.tgz

# hadolint expands no build args, so it reads this stage reference as an
# untagged image. Fixed upstream by hadolint PR #1264; drop this
# ignore once a hadolint release includes it.
# hadolint ignore=DL3006
FROM dl-${TARGETARCH} AS dl

FROM ${BASE_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG UV_VERSION

# Strip the archive's top dir (uv-<triple>/); gate on the exact pin
# ("uv X.Y.Z (…)"). Builds run on 4K pages, so this can't catch the jemalloc
# issue (see uv.yaml): after a bump, run `uv --version` in a sandbox.
RUN --mount=from=dl,source=/uv.tgz,target=/tmp/uv.tgz <<'EOF2'
set -eu
[ -n "${UV_VERSION}" ] || { echo "UV_VERSION must be set" >&2; exit 1; }
mkdir -p /tmp/uv /out/usr/local/bin
tar -C /tmp/uv --strip-components=1 --no-same-owner -xzf /tmp/uv.tgz
install -m 0755 -o 0 -g 0 /tmp/uv/uv /tmp/uv/uvx /out/usr/local/bin/
rm -rf /tmp/uv
out="$(/out/usr/local/bin/uv --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "uv --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "${UV_VERSION}" || {
  echo "pin mismatch: descriptor says ${UV_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
EOF2

# Overlay: two files under /usr/local/bin, nothing under /home, no ENTRYPOINT.
FROM scratch
COPY --from=build /out /
