# openwrt-aarch64

Builds an aarch64-host OpenWrt SDK tarball from source — the Linux-aarch64
equivalent of the official Linux-x86_64 SDK tarballs on
downloads.openwrt.org.

## Why

Sometimes you want to build an openwrt apk on aarch64 linux. I'm using this
for a beryl7. (`scripts/build.sh`) downloads a prebuilt SDK tarball from 
downloads.openwrt.org. OpenWrt only publishes `Linux-x86_64`
host tarballs, so on Apple Silicon an openwrt apk builder Dockerfile would need
`--platform=linux/amd64` and pays Rosetta emulation cost on every build.

This repo builds the same SDK natively on arm64. The resulting tarball —
`openwrt-sdk-mediatek-filogic_gcc-14.3.0_musl.Linux-aarch64.tar.zst` —
can be dropped into a build in place of the x86_64 one.

## Usage

```
make build
```

First run clones OpenWrt at `SNAPSHOT` (master), installs feeds, builds
host tools + toolchain, then `make sdk` to pack the tarball. Expect
~1-2h and ~10-15 GB of disk the first time. Subsequent runs skip
straight to `make sdk` (seconds) — the buildroot is cached in a Docker
named volume (`openwrt-aarch64-sdk`).

Artifact lands in `./bin/`:

```
bin/openwrt-sdk-mediatek-filogic_gcc-14.3.0_musl.Linux-aarch64.tar.zst
```

### Other targets

- `make shell` — interactive shell in the build container (debugging)
- `make reseed` — destroy the cached buildroot volume (forces re-clone)
- `make image` — rebuild just the Docker image

### Override target / branch

```
make build SDK_TARGET=x86/64 OPENWRT_BRANCH=24.10
```

Defaults match: `mediatek/filogic` + `SNAPSHOT`.

## Layout

```
Dockerfile              # native arm64 debian + buildroot deps
scripts/build-sdk.sh    # clone, feeds, defconfig, tools, toolchain, make sdk
Makefile                # image / build / shell / reseed
bin/                    # tarball output
```
