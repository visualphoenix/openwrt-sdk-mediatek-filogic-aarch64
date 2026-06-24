#!/bin/bash
# Install buildroot host deps for OpenWrt. Shared between the Dockerfile
# (local dev) and the GitHub Actions workflow (bare ubuntu-24.04-arm
# runner). Keep in sync with the dep list in Dockerfile — this script is
# the single source of truth.
#
# Assumes a Debian/Ubuntu host with apt-get and root/sudo.

set -euo pipefail

# Empty by default — assumes root (Dockerfile build) or a context where
# apt-get is already privileged. CI runners set SUDO=sudo to elevate.
: "${SUDO:=}"

$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
    build-essential \
    bison \
    ca-certificates \
    ccache \
    clang \
    cmake \
    curl \
    file \
    flex \
    gawk \
    gettext \
    git \
    grep \
    gzip \
    jq \
    libboost-dev \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    libxml2-dev \
    perl \
    python3 \
    python3-pyelftools \
    python3-setuptools \
    rsync \
    sed \
    swig \
    tar \
    unzip \
    wget \
    xsltproc \
    zlib1g-dev \
    zstd

$SUDO rm -rf /var/lib/apt/lists/*
