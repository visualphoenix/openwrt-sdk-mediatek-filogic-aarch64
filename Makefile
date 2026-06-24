# Build an aarch64-host OpenWrt SDK tarball from source.
#
# downloads.openwrt.org ships only Linux-x86_64 SDK tarballs. This
# Makefile builds the same SDK natively on arm64 so the resulting
# tarball (openwrt-sdk-<target>_<gcc>_<libc>.Linux-aarch64.tar.zst)
# can drop into the build flow for aarch64 openwrt packages in place
# of the x86_64 one — no Rosetta, no emulation.
#
# Two execution modes share scripts/build-sdk.sh:
#   - local (default): Dockerized via the Dockerfile + named volume cache
#   - bare: install deps on the host (make deps), then run build-sdk.sh
#     directly. Used by the GitHub Actions workflow on ubuntu-24.04-arm
#     to avoid DinD overhead.
#
# Targets:
#   image      build the docker image (debian + buildroot deps)
#   deps       install host build deps on the current machine (bare mode)
#   build      produce the SDK tarball under ./bin/ (Docker mode)
#   build-bare same, but directly on the host (no Docker)
#   shell      open an interactive shell in the build container (debugging)
#   reseed     destroy the cached buildroot volume (forces fresh clone)

VOL          := openwrt-aarch64-sdk
IMAGE        := openwrt-aarch64-builder
SDK_TARGET   ?= mediatek/filogic
OPENWRT_BRANCH ?= SNAPSHOT

DOCKER       := docker run --rm \
                  -v $(CURDIR)/scripts:/src:ro \
                  -v $(CURDIR)/bin:/out \
                  -v $(VOL):/sdk:Z \
                  -e SDK_TARGET=$(SDK_TARGET) \
                  -e OPENWRT_BRANCH=$(OPENWRT_BRANCH) \
                  $(IMAGE)
DOCKER_IT    := docker run --rm -it \
                  -v $(CURDIR)/scripts:/src \
                  -v $(CURDIR)/bin:/out \
                  -v $(VOL):/sdk:Z \
                  -e SDK_TARGET=$(SDK_TARGET) \
                  -e OPENWRT_BRANCH=$(OPENWRT_BRANCH) \
                  $(IMAGE)
DOCKER_ROOT  := docker run --rm --user 0:0 -v $(VOL):/sdk:Z $(IMAGE)

.PHONY: image volume fix-perms deps build build-bare shell reseed

image:
	docker build --rm --tag $(IMAGE) .

# Install host build deps directly on the current machine (no Docker).
# Used by the CI workflow. Set SUDO=sudo when not root.
deps:
	SUDO=sudo ./scripts/install-deps.sh

volume:
	@docker volume inspect $(VOL) >/dev/null 2>&1 || docker volume create $(VOL)

# Named volumes mount root-owned; chown to builder so the in-container
# user can write the buildroot. Idempotent.
fix-perms: volume
	$(DOCKER_ROOT) chown -R 1000:1000 /sdk

build: image fix-perms
	@mkdir -p bin
	$(DOCKER) /src/build-sdk.sh

# Bare-host build. SDK_DIR caches the buildroot under ./sdk so repeated
# runs skip the toolchain build; OUT_DIR drops the tarball in ./bin.
build-bare:
	@mkdir -p bin sdk
	SDK_DIR=$(CURDIR)/sdk OUT_DIR=$(CURDIR)/bin \
	  ./scripts/build-sdk.sh

shell: image fix-perms
	@mkdir -p bin
	$(DOCKER_IT) bash

# Nuclear: destroys the cached buildroot volume. Next build re-clones.
reseed:
	@printf "Destroy SDK volume '%s'? [y/N] " "$(VOL)"; \
	  read ans; [ "$$ans" = "y" ] || { echo aborted; exit 1; }
	docker volume rm $(VOL) || true
