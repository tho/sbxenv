# syntax=docker/dockerfile:1
# chezmoi and uv as an overlay: pinned, digest-verified binaries at
# /usr/local/bin/{chezmoi,uv,uvx}, laid out like sbx-kits-contrib's mise kit
# (v3 branch). /usr/local/bin precedes /usr/bin on PATH, so this uv shadows
# sbx-kit-shell's (config.yaml says why).
#
# The build stage's base is public Debian trixie (glibc 2.41, as in the
# sandbox), pinned by digest, so builds need no registry login; Docker's
# dhi.io base refuses anonymous pulls. ADD --checksum downloads, so no curl.
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

# From the descriptor (args.chezmoiVersion, args.uvVersion). No defaults, so
# a missing pin fails the build.
ARG CHEZMOI_VERSION
ARG UV_VERSION

# Per-arch downloads; BuildKit builds only the stages TARGETARCH selects.
# Digest sources and provenance checks: kits/README.md.
#
# chezmoi: the musl tarball on amd64 (linux_amd64 is glibc-linked);
# linux_arm64 is already static.
FROM scratch AS chezmoi-amd64
ARG CHEZMOI_VERSION
ADD --checksum=sha256:f2fbda5a865e2725adc42090ea6deabf3e1a4d40bfd59a8942c3ad20284b39cb \
    https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux-musl_amd64.tar.gz \
    /chezmoi.tgz

FROM scratch AS chezmoi-arm64
ARG CHEZMOI_VERSION
ADD --checksum=sha256:c9e6a6e71eb5291018e161a8426d7c313cd2e8553c2ca4029511fec2a33bc28c \
    https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_arm64.tar.gz \
    /chezmoi.tgz

# uv: the glibc builds (glibc 2.28+), as Astral's own installer picks.
FROM scratch AS uv-amd64
ARG UV_VERSION
ADD --checksum=sha256:f29c3e94ffabd7e6f3ba521dba169a9b7ec12100bf3257087f0f24f6123f3645 \
    https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz \
    /uv.tgz

FROM scratch AS uv-arm64
ARG UV_VERSION
ADD --checksum=sha256:229e194255c7958d86d56e8790d969a6f74736592133f0dfd0076f754c642c1d \
    https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-aarch64-unknown-linux-gnu.tar.gz \
    /uv.tgz

# hadolint doesn't expand build args, so it reads these stage references as
# untagged images. Drop the ignores once a release includes hadolint PR #1264.
# hadolint ignore=DL3006
FROM chezmoi-${TARGETARCH} AS chezmoi-dl
# hadolint ignore=DL3006
FROM uv-${TARGETARCH} AS uv-dl

FROM ${BASE_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG CHEZMOI_VERSION
ARG UV_VERSION

# Extract each tool, then fail unless it reports its exact pin: chezmoi
# prints "chezmoi version vX.Y.Z, commit …", uv "uv X.Y.Z (…)". Builds run on
# 4K pages, so this can't catch uv's jemalloc failure (config.yaml): after a
# uv bump, run `uv --version` in a sandbox on Apple silicon.
RUN --mount=from=chezmoi-dl,source=/chezmoi.tgz,target=/tmp/chezmoi.tgz \
    --mount=from=uv-dl,source=/uv.tgz,target=/tmp/uv.tgz <<'EOF2'
set -eu
[ -n "${CHEZMOI_VERSION}" ] || { echo "CHEZMOI_VERSION must be set" >&2; exit 1; }
[ -n "${UV_VERSION}" ] || { echo "UV_VERSION must be set" >&2; exit 1; }
mkdir -p /tmp/chezmoi /tmp/uv /out/usr/local/bin
tar -C /tmp/chezmoi -xzf /tmp/chezmoi.tgz chezmoi
install -m 0755 -o 0 -g 0 /tmp/chezmoi/chezmoi /out/usr/local/bin/chezmoi
# Strip the archive's top dir (uv-<triple>/).
tar -C /tmp/uv --strip-components=1 --no-same-owner -xzf /tmp/uv.tgz
install -m 0755 -o 0 -g 0 /tmp/uv/uv /tmp/uv/uvx /out/usr/local/bin/
rm -rf /tmp/chezmoi /tmp/uv

# check <name> <expected token> <binary>: the first line of --version must
# contain the token as a whole word.
check() {
  out="$("$3" --version 2>&1)"
  reported="$(printf '%s\n' "$out" | head -n1)"
  echo "$1 --version: ${reported}"
  printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "$2" || {
    echo "pin mismatch: descriptor says $1 $2, binary reports '${reported}'" >&2
    exit 1
  }
}
check chezmoi "v${CHEZMOI_VERSION}" /out/usr/local/bin/chezmoi
check uv "${UV_VERSION}" /out/usr/local/bin/uv
EOF2

# Overlay: three files under /usr/local/bin, nothing under /home, no ENTRYPOINT.
FROM scratch
COPY --from=build /out /
