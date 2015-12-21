ifeq ($(V),)
hide := @
else
hide :=
endif

empty :=

ifeq ($(realpath $(ANDROID_BUILD_TOP)),)
$(error ANDROID_BUILD_TOP not defined)
endif

AOSP_TARGET_ARCHS ?= arm arm64 mips mips64 x86 x86_64

AOSP_IMAGE_TYPES := system root
DOCKERFILE_VARS := \
  BUILD_ID \
  PLATFORM_VERSION \
  TARGET_BUILD_VARIANT \
  TARGET_PRODUCT \
  TARGET_ARCH \
  TARGET_ARCH_VARIANT \
  TARGET_CPU_VARIANT \
  TARGET_2ND_ARCH \
  TARGET_2ND_ARCH_VARIANT \
  TARGET_2ND_CPU_VARIANT \
  $(empty)

setup-env = cd $(ANDROID_BUILD_TOP); source build/envsetup.sh >/dev/null 2>&1; export OUT_DIR=out-$(1); lunch aosp_$(1)-eng >/dev/null 2>&1

SHELL := bash
SUDO ?= $(shell which sudo)

all:

.PHONY: dockerfiles

define build-dockerfile-target
@echo "$< => $@"
@mkdir -p $(@D)
$(hide) cat $< | ($(call setup-env,$(PRIVATE_ARCH)); sed $(foreach v,$(DOCKERFILE_VARS),-e "s,@$(v)@,`get_build_var $(v)`,g")) >$@
endef

define define-dockerfile-target
$(1)/$(2)/Dockerfile: PRIVATE_ARCH := $(1)
$(1)/$(2)/Dockerfile: PRIVATE_TYPE := $(2)
$(1)/$(2)/Dockerfile: Dockerfile.$(2).template Makefile
	$$(call build-dockerfile-target)

dockerfiles: $(1)/$(2)/Dockerfile
endef

.PHONY: android-targets

define build-android-target
$(hide) $(call setup-env,$(PRIVATE_ARCH)); make -j $$(nproc)
endef

define define-android-target
android-target-$(1): PRIVATE_ARCH := $(1)
android-target-$(1):
	$$(call build-android-target)

android-targets: android-target-$(1)
endef

define build-system-tarball-target
@mkdir -p $(@D)
$(hide) $(call setup-env,$(PRIVATE_ARCH)); \
  [ -d "$$(ANDROID_PRODUCT_OUT)/system" ] || mkdir -p $$(ANDROID_PRODUCT_OUT)/system; \
  if [ -n "$$(file $$(ANDROID_PRODUCT_OUT)/system.img | grep ext4)" ]; then \
    $(SUDO) mount -o ro $$(ANDROID_PRODUCT_OUT)/system.img $$(ANDROID_PRODUCT_OUT)/system; \
  else \
    simg2img $$(ANDROID_PRODUCT_OUT)/system.img $$(ANDROID_PRODUCT_OUT)/system.ext4; \
    $(SUDO) mount -o ro $$(ANDROID_PRODUCT_OUT)/system.ext4 $$(ANDROID_PRODUCT_OUT)/system; \
  fi; \
  tar -C $$(ANDROID_PRODUCT_OUT)/system -zcpf $@ --numeric-owner .; \
  $(SUDO) umount $$(ANDROID_PRODUCT_OUT)/system;
endef

define build-root-tarball-target
@mkdir -p $(@D)
$(hide) $(call setup-env,$(PRIVATE_ARCH)); \
  tar -C $$(ANDROID_PRODUCT_OUT)/root -zcpf $@ --numeric-owner --owner root --group root .
endef

.PHONY: system-tarballs root-tarballs

define define-tarball-target
$(1)/$(2)/$(2).tar.gz: PRIVATE_ARCH := $(1)
$(1)/$(2)/$(2).tar.gz: PRIVATE_TYPE := $(2)
$(1)/$(2)/$(2).tar.gz: android-target-$(1) | $(1)/$(2)/Dockerfile
	$$(call build-$(2)-tarball-target)

$(2)-tarballs: $(1)/$(2)/$(2).tar.gz
endef

define define-arch
$(call define-android-target,$(1))
$(foreach image_type,$(AOSP_IMAGE_TYPES), \
  $(call define-dockerfile-target,$(1),$(image_type)) \
  $(call define-tarball-target,$(1),$(image_type)) \
)
endef

$(foreach target,$(AOSP_TARGET_ARCHS),$(eval $(call define-arch,$(target))))

all: system-tarballs root-tarballs
