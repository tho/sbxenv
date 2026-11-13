# syntax=docker/dockerfile:1
# chezmoi as an overlay: a pinned, digest-verified binary at
# /usr/local/bin/chezmoi, laid out like sbx-kits-contrib's mise kit (v3
# branch).
#
# The build stage's base is public Debian trixie (glibc 2.41, as in the
# sandbox), pinned by digest, so builds need no registry login; Docker's
# dhi.io base refuses anonymous pulls. ADD --checksum downloads, so no curl.
ARG BASE_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

# From the descriptor (args.chezmoiVersion). No default, so a missing pin
# fails the build.
ARG CHEZMOI_VERSION

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

# hadolint doesn't expand build args, so it reads this stage reference as an
# untagged image. Drop the ignore once a release includes hadolint PR #1264.
# hadolint ignore=DL3006
FROM chezmoi-${TARGETARCH} AS chezmoi-dl

FROM ${BASE_IMAGE} AS build

# No version check: the pin is in the download URL, and --checksum fixes the
# bytes, so another version fails the ADD.
RUN --mount=from=chezmoi-dl,source=/chezmoi.tgz,target=/tmp/chezmoi.tgz <<'EOF'
set -eu
mkdir -p /tmp/chezmoi /out/usr/local/bin
tar -C /tmp/chezmoi -xzf /tmp/chezmoi.tgz chezmoi
install -m 0755 -o 0 -g 0 /tmp/chezmoi/chezmoi /out/usr/local/bin/chezmoi
EOF

# Overlay: one file under /usr/local/bin, nothing under /home, no ENTRYPOINT.
FROM scratch
COPY --from=build /out /
