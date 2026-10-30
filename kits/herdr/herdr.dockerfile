# syntax=docker/dockerfile:1
# herdr as an overlay: one pinned, digest-verified static (musl) binary at
# /usr/local/bin/herdr, plus the config merge script. `herdr machine add`
# finds the binary via `command -v herdr` and skips its remote install.
# Build-only base: see kits/chezmoi/chezmoi.dockerfile.
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

# From the descriptor (args.version). No default, so a missing pin fails the build.
ARG HERDR_VERSION

# Per-arch downloads; BuildKit only builds the stage TARGETARCH selects.
# Upstream ships bare binaries named aarch64/x86_64 with no checksum file or
# signature; these are the GitHub release asset digests, which match
# herdr.dev's manifest.
FROM scratch AS dl-amd64
ARG HERDR_VERSION
ADD --checksum=sha256:14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d \
    https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-x86_64 \
    /herdr

FROM scratch AS dl-arm64
ARG HERDR_VERSION
ADD --checksum=sha256:17d7536f2da50859523680ef279dffcac8e4a235f4e46fe8da6c2ec44141897c \
    https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-aarch64 \
    /herdr

# hadolint expands no build args, so it reads this stage reference as an
# untagged image. Fixed upstream by hadolint PR #1264; drop this
# ignore once a hadolint release includes it.
# hadolint ignore=DL3006
FROM dl-${TARGETARCH} AS dl

FROM ${BASE_IMAGE} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG HERDR_VERSION

# Install, gate on the exact pin ("herdr X.Y.Z"), then smoke-test the merge.
RUN --mount=from=dl,source=/herdr,target=/tmp/herdr \
    --mount=type=bind,source=merge-config.sh,target=/tmp/merge-config.sh <<'EOF2'
set -eu
[ -n "${HERDR_VERSION}" ] || { echo "HERDR_VERSION must be set" >&2; exit 1; }
mkdir -p /out/usr/local/bin
install -m 0755 -o 0 -g 0 /tmp/herdr /out/usr/local/bin/herdr
mkdir -p /out/usr/local/lib/herdr-kit
install -m 0755 -o 0 -g 0 /tmp/merge-config.sh /out/usr/local/lib/herdr-kit/merge-config
out="$(/out/usr/local/bin/herdr --version 2>&1)"
reported="$(printf '%s\n' "$out" | head -n1)"
echo "herdr --version: ${reported}"
printf '%s\n' "$reported" | tr -s ' ,():\t' '\n' | grep -Fxq "${HERDR_VERSION}" || {
  echo "pin mismatch: descriptor says ${HERDR_VERSION}, binary reports '${reported}'" >&2
  exit 1
}
# Smoke-test merge-config against this herdr: the output passes
# `config check`, sets the keys and keeps existing ones (unknown sections
# too); a merge that can't parse fails and leaves the file byte-identical.
printf '[update]\nchannel = "stable"\n' >/tmp/config.toml
HERDR=/out/usr/local/bin/herdr /out/usr/local/lib/herdr-kit/merge-config /tmp/wt /tmp/config.toml
for line in 'channel = "stable"' 'version_check = false' 'manifest_check = false' \
  'directory = "/tmp/wt"' 'default_shell = "/bin/bash"'; do
  grep -Fqx "$line" /tmp/config.toml || { echo "merge-config smoke test: missing $line" >&2; exit 1; }
done
printf '[unknown]\nkey = 1\n' >/tmp/extra.toml
HERDR=/out/usr/local/bin/herdr /out/usr/local/lib/herdr-kit/merge-config /tmp/wt /tmp/extra.toml
printf 'update = { channel = "stable" }\n' >/tmp/bad.toml
cp /tmp/bad.toml /tmp/bad.orig
if HERDR=/out/usr/local/bin/herdr /out/usr/local/lib/herdr-kit/merge-config /tmp/wt /tmp/bad.toml 2>/dev/null; then
  echo "merge-config smoke test: an unparsable merge succeeded" >&2; exit 1
fi
cmp /tmp/bad.toml /tmp/bad.orig
rm -f /tmp/config.toml /tmp/extra.toml /tmp/bad.toml /tmp/bad.orig
EOF2

# Overlay: herdr + the merge script, nothing under /home, no ENTRYPOINT.
FROM scratch
COPY --from=build /out /
