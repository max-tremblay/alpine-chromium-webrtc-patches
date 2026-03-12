DOCKER_IMAGE        := apk-checksum-updater
DOCKER_BUILD_IMAGE  := chromium-apk-builder
CHROMIUM_DIR        := $(CURDIR)/chromium
OUTPUT_DIR          := $(CURDIR)/output
PLATFORMS           ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
#PLATFORMS          ?= linux/amd64 linux/arm64

# Local cache for downloaded sources (avoids re-downloading on each run)
SRCDEST     ?= $(HOME)/.cache/abuild-distfiles
# Local cache for ninja build output (avoids recompiling unchanged objects)
BUILDCACHE  ?= $(HOME)/.cache/chromium-apk-buildcache
PKGVER      := $(shell grep '^pkgver=' $(CHROMIUM_DIR)/APKBUILD_PATCHED | cut -d= -f2)
_BUILDOUT    = /home/builder/chromium/src/chromium-$(PKGVER)/out

.PHONY: update-checksums build resume
update-checksums:
	docker build \
		-f dockerfiles/apk-hashes-apkbuild-patched-checksum.dockerfile \
		-t $(DOCKER_IMAGE) \
		.
	mkdir -p $(SRCDEST)
	docker run --rm \
		-v $(CHROMIUM_DIR):/work \
		-v $(SRCDEST):/var/cache/distfiles \
		-w /work \
		$(DOCKER_IMAGE) \
		sh -c ' \
			adduser -D builder && \
			addgroup builder abuild && \
			chown builder:builder APKBUILD && \
			chmod a+rwx /var/cache/distfiles && \
			su builder -s /bin/sh -c "cd /work && SRCDEST=/var/cache/distfiles abuild checksum" \
		'

build:
	mkdir -p $(OUTPUT_DIR) $(SRCDEST) $(BUILDCACHE)
	for platform in $(PLATFORMS); do \
		arch=$$(echo $$platform | cut -d/ -f2); \
		docker build \
			--platform $$platform \
			-f dockerfiles/chromium-apk-build.dockerfile \
			-t $(DOCKER_BUILD_IMAGE)-$$arch \
			. && \
		docker run --rm \
			--platform $$platform \
			-v $(CHROMIUM_DIR):/home/builder/chromium \
			-v $(SRCDEST):/var/cache/distfiles \
			-v $(OUTPUT_DIR):/home/builder/packages \
			-v $(BUILDCACHE):$(_BUILDOUT) \
			$(DOCKER_BUILD_IMAGE)-$$arch \
			sh -c 'REPODEST=/home/builder/packages abuild -r deps fetch unpack prepare build package rootpkg'; \
	done

# Resume a previously started build, skipping source extraction and patching.
# Requires a previous 'make build' run that reached the compile stage.
resume:
	mkdir -p $(OUTPUT_DIR) $(SRCDEST) $(BUILDCACHE)
	for platform in $(PLATFORMS); do \
		arch=$$(echo $$platform | cut -d/ -f2); \
		docker run --rm \
			--platform $$platform \
			-v $(CHROMIUM_DIR):/home/builder/chromium \
			-v $(SRCDEST):/var/cache/distfiles \
			-v $(OUTPUT_DIR):/home/builder/packages \
			-v $(BUILDCACHE):$(_BUILDOUT) \
			$(DOCKER_BUILD_IMAGE)-$$arch \
			sh -c 'REPODEST=/home/builder/packages abuild -r deps build package rootpkg'; \
	done
