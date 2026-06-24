# Build environment for producing an aarch64-host OpenWrt SDK tarball.
#
# The official downloads.openwrt.org SDK tarballs are Linux-x86_64 only.
# This image builds the SDK from source natively on arm64 so the resulting
# tarball is Linux-aarch64 — usable directly on Apple Silicon / arm64 CI
# without Rosetta emulation.
#
# The SDK is NOT baked into the image. It's built into a named volume on
# first run (see scripts/build-sdk.sh) and the final tarball is dropped
# into /out.

FROM --platform=linux/arm64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Deps list lives in scripts/install-deps.sh (shared with the CI workflow
# so both paths stay in sync). Script defaults to no sudo — fine here,
# we're root during image build.
COPY scripts/install-deps.sh /tmp/install-deps.sh
RUN /tmp/install-deps.sh && rm /tmp/install-deps.sh

RUN useradd -m -u 1000 -s /bin/bash builder
USER builder
WORKDIR /home/builder
