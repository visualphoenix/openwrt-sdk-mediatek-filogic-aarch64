#!/bin/bash
# Build the OpenWrt SDK tarball from source on a native aarch64 host.
# Produces openwrt-sdk-<target>_<gcc>_<libc>.Linux-aarch64.tar.zst under
# /out — the aarch64 equivalent of the x86_64 tarballs on
# downloads.openwrt.org.
#
# Environment:
#   SDK_TARGET       e.g. "mediatek/filogic" (default)
#   OPENWRT_BRANCH   "SNAPSHOT" (default) or a release like "24.10"
#   SDK_DIR          where the buildroot lives (default /sdk, a volume)
#   OUT_DIR          where to drop the tarball (default /out)

set -euo pipefail

SDK_TARGET="${SDK_TARGET:-mediatek/filogic}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-SNAPSHOT}"
SDK_DIR="${SDK_DIR:-/sdk}"
OUT_DIR="${OUT_DIR:-/out}"

mkdir -p "$SDK_DIR" "$OUT_DIR"

# Resolve the git ref for the requested branch.
case "$OPENWRT_BRANCH" in
    SNAPSHOT) ref="master" ;;
    *)        ref="openwrt-${OPENWRT_BRANCH}" ;;
esac

# Bootstrap: clone OpenWrt if missing. We do NOT auto-update an existing
# clone — bumping SNAPSHOT requires `make reseed` to start fresh, so a
# cached toolchain always matches its source tree.
if [[ ! -d "$SDK_DIR/.git" ]]; then
    echo "==> Cloning OpenWrt ($OPENWRT_BRANCH -> $ref) into $SDK_DIR"
    find "$SDK_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    git clone --depth 1 --branch "$ref" \
        https://git.openwrt.org/openwrt/openwrt.git "$SDK_DIR"
fi

cd "$SDK_DIR"

# Feeds must be installed before defconfig so feed packages (luci etc.)
# appear in the generated .config.
if [[ ! -f "$SDK_DIR/.feeds-installed" ]]; then
    echo "==> Updating + installing feeds"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    touch "$SDK_DIR/.feeds-installed"
fi

# Target config. SDK_TARGET is "target/subtarget" -> CONFIG_TARGET_<target>
# and CONFIG_TARGET_<target>_<subtarget>. We seed .config with the target
# *before* the first defconfig so Kconfig resolves the choice cleanly —
# appending after a defconfig (which already picked a default target)
# triggers "override: changes choice state" warnings.
IFS=/ read -r target subtarget <<<"$SDK_TARGET"
echo "==> Generating .config for $target/$subtarget"
{
    echo "CONFIG_TARGET_${target}=y"
    echo "CONFIG_TARGET_${target}_${subtarget}=y"
    # The SDK tarball target is gated on CONFIG_SDK — without it the
    # toplevel `target/sdk/compile` dispatch is filtered out and
    # `make sdk` (or any sdk-related target) dies with "No rule".
    echo "CONFIG_SDK=y"
} > .config
make defconfig >/dev/null

# Tools + toolchain. This is the slow part (~1-2h first time). Cached in
# the volume, so subsequent runs skip straight to the kernel + tarball.
if [[ ! -f "$SDK_DIR/.bootstrapped" ]]; then
    echo "==> Building host tools"
    make tools/install -j"$(nproc)"
    echo "==> Building toolchain"
    make toolchain/install -j"$(nproc)"
    touch "$SDK_DIR/.bootstrapped"
fi

# Kernel. target/sdk/compile packs *.ko modules and firmware out of
# build_dir/.../linux-<ver>/, so it needs the kernel build tree in place
# first. The dep isn't declared on the compile stamp, so we run linux
# explicitly. Cached on second run.
if [[ ! -f "$SDK_DIR/.kernel-built" ]]; then
    echo "==> Building target/linux (kernel)"
    make target/linux/compile -j"$(nproc)"
    touch "$SDK_DIR/.kernel-built"
fi

# Host apk. The SDK's include/package-pack.mk shells out to
# $(STAGING_DIR_HOST)/bin/apk to assemble .apk packages, but
# target/sdk/compile doesn't pull in package/system/apk/host/compile
# as a dep — it just packs whatever is in staging_dir/host/bin/. Without
# this step the tarball ships without apk, and `make package/<x>/compile`
# inside the unpacked SDK dies with "apk: No such file or directory".
# Upstream fixed the dep chain for in-tree builds (commit 617431685eb0)
# but the SDK pack step still relies on apk being pre-built.
echo "==> Building host apk"
make package/system/apk/host/compile -j"$(nproc)"

# Pack the SDK tarball. Building natively on aarch64 yields
# openwrt-sdk-<target>_<gcc>_<libc>.Linux-aarch64.tar.zst — the same
# shape as the official x86_64 tarballs, just a different host arch.
#
# target/sdk/compile is the stamp that produces
# $(BIN_DIR)/$(SDK_NAME).tar.zst. It dispatches via the `target` subdir
# only when CONFIG_SDK=y (set above). We don't `make world` — that would
# build every package; we just want the tarball, so hit the stamp directly.
echo "==> Building SDK tarball"
make target/sdk/compile -j"$(nproc)" V=s

# Collect the artifact. make sdk drops it under
# bin/targets/<target>/<subtarget>/.
echo "==> Collecting tarball to $OUT_DIR"
shopt -s nullglob
tarballs=( bin/targets/"$target"/"$subtarget"/openwrt-sdk-*.Linux-aarch64.tar.zst )
shopt -u nullglob
if [[ ${#tarballs[@]} -eq 0 ]]; then
    echo "ERROR: no aarch64 SDK tarball produced" >&2
    echo "Searched bin/targets/$target/$subtarget/:" >&2
    find "bin/targets/$target/$subtarget" -type f 2>/dev/null | head -50 >&2 || true
    exit 1
fi
for t in "${tarballs[@]}"; do
    cp -v "$t" "$OUT_DIR/"
done

echo
echo "==> Done. Artifact(s):"
ls -la "$OUT_DIR/"
