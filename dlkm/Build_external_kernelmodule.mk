## Input Arguments:
# LOCAL_MODULE: name of the .ko to be generated (e.g. kp_module.ko)
# LOCAL_MODULE_PATH: location to put the module, $(KERNEL_MODULES_OUT)
#                    for a common output directory
# LOCAL_MODULE_KBUILD_NAME: name of the .ko that is generated by kbuild (see below)
# LOCAL_ADDITIONAL_DEPENDENCIES: just that
# KBUILD_OPTIONS: Additional parameters to give to kbuild when compiling module

# Assign external kernel modules to the DLKM class
LOCAL_MODULE_CLASS := DLKM

# Set the default install path to system/lib/modules
LOCAL_MODULE_PATH := $(strip $(LOCAL_MODULE_PATH))
ifeq ($(LOCAL_MODULE_PATH),)
  LOCAL_MODULE_PATH := $(TARGET_OUT)/lib/modules
endif

# LOCAL_MODULE_KBUILD_NAME is the name of the .ko that kernel makefiles generate
# for instance, one could write my_device.ko, but want it to be called
# the_device.ko on vendor image (and rest of Android build system)
ifeq ($(LOCAL_MODULE_KBUILD_NAME),)
    LOCAL_MODULE_KBUILD_NAME := $(LOCAL_MODULE)
endif
LOCAL_MODULE_KBUILD_NAME := $(strip $(LOCAL_MODULE_KBUILD_NAME))

include $(BUILD_SYSTEM)/base_rules.mk

################################################################################
KERNEL_PLATFORM_PATH:=kernel_platform
KERNEL_PLATFORM_TO_ROOT:=../

################################################################################
KP_DLKM_INTERMEDIATE:=$(TARGET_OUT_INTERMEDIATES)/DLKM_OBJ
# Intermediate directory where the kernel modules are created
# by the kernel platform. Ideally this would be the same
# directory as LOCAL_BUILT_MODULE, but because we're using
# relative paths for both O= and M=, we don't have much choice
MODULE_KP_OUT_DIR := $(KP_DLKM_INTERMEDIATE)/$(LOCAL_PATH)

# The kernel build system doesn't support parallel kernel module builds
# that share the same output directory. Thus, in order to build multiple
# kernel modules that reside in a single directory (and therefore have
# the same output directory), there must be just one invocation of the
# kernel build system that builds all the modules of a given directory.
#
# Therefore, all kernel modules must depend on the same, unique target
# that invokes the kernel build system and builds all of the modules
# for the directory. The $(MODULE_KP_COMBINED_TARGET) target serves this purpose.
MODULE_KP_COMBINED_TARGET := $(MODULE_KP_OUT_DIR)/buildko.timestamp
# When MODULE_KP_COMBINED_TARGET is built, then out pops the MODULE_KP_TARGET (by essentially running `make modules`)
MODULE_KP_TARGET := $(MODULE_KP_OUT_DIR)/$(LOCAL_MODULE_KBUILD_NAME)

# The final built module for Android Build System
$(LOCAL_BUILT_MODULE): $(MODULE_KP_TARGET) | $(ACP)
	$(transform-prebuilt-to-target)

# To build the module inside kernel_platform, depend on the kbuild_target
$(MODULE_KP_TARGET): $(MODULE_KP_COMBINED_TARGET)
$(MODULE_KP_TARGET): $(LOCAL_ADDITIONAL_DEPENDENCIES)

# Ensure the kernel module created by the kernel build system, as
# well as all the other intermediate files, are removed during a clean.
$(cleantarget): PRIVATE_CLEAN_FILES := $(PRIVATE_CLEAN_FILES) $(MODULE_KP_OUT_DIR)

$(MODULE_KP_COMBINED_TARGET): $(LOCAL_ADDITIONAL_DEPENDENCIES)
$(MODULE_KP_COMBINED_TARGET): $(foreach file,$(LOCAL_SRC_FILES), \
						$(or $(wildcard $(local_path)/$(file)), \
						  $(wildcard $(file)), \
						  $(error File: $(file) doesn't exist)))
KERNEL_PREBUILT_DIR ?= device/qcom/$(TARGET_BOARD_PLATFORM)-kernel

# Use $(wildcard $(KERNEL_PREBUILT_DIR)/.config) as an indicator of KERNEL_KIT support
# KERNEL_KIT support removes the requirement on a full prebuilt kernel platform output tree,
# instead just the prebuilt kernel platform DIST_DIR. The DIST_DIR is copied to
# device/qcom/*-kernel by prepare_vendor.sh.
ifneq ($(wildcard $(KERNEL_PREBUILT_DIR)/.config),)

# We need to run make modules_prepare before compiling out-of-tree modules
# As with other Kbuild commands, there should only be one build command running modules_prepare,
# so guard it with obj/DLKM_OBJ/build.timestamp file
MODULE_KP_COMMON_TARGET := $(KP_DLKM_INTERMEDIATE)/build.timestamp
ifndef $(MODULE_KP_COMMON_TARGET)_RULE
$(MODULE_KP_COMMON_TARGET)_RULE := 1

$(MODULE_KP_COMMON_TARGET): $(KERNEL_PREBUILT_DIR)/.config $(KERNEL_PREBUILT_DIR)/Module.symvers
	(cd $(KERNEL_PLATFORM_PATH) && \
	    OUT_DIR=$(KERNEL_PLATFORM_TO_ROOT)/$(KP_DLKM_INTERMEDIATE)/kernel_platform \
	    KERNEL_KIT=$(KERNEL_PLATFORM_TO_ROOT)/$(KERNEL_PREBUILT_DIR) \
	    ./build/build_module.sh $(kbuild_options) \
	    ANDROID_BUILD_TOP=$$(realpath $$(pwd)/$(KERNEL_PLATFORM_TO_ROOT)) \
	)
	touch $@
endif

ifndef $(MODULE_KP_COMBINED_TARGET)_RULE
$(MODULE_KP_COMBINED_TARGET)_RULE := 1

# Kernel modules have to be built after:
#  * the kernel config has been created
#  * host executables, like scripts/basic/fixdep, have been built
#    (otherwise parallel invocations of the kernel build system will
#    fail as they all try to compile these executables at the same time)
#  * Module.symvers is available (prebuilt or after full kernel build)
$(MODULE_KP_COMBINED_TARGET): local_path     := $(LOCAL_PATH)
$(MODULE_KP_COMBINED_TARGET): local_out      := $(MODULE_KP_OUT_DIR)
$(MODULE_KP_COMBINED_TARGET): kbuild_options := $(KBUILD_OPTIONS)
$(MODULE_KP_COMBINED_TARGET): $(MODULE_KP_COMMON_TARGET)
	(cd $(KERNEL_PLATFORM_PATH) && \
	    EXT_MODULES=$(KERNEL_PLATFORM_TO_ROOT)/$(local_path) \
	    OUT_DIR=$(KERNEL_PLATFORM_TO_ROOT)/$(KP_DLKM_INTERMEDIATE)/kernel_platform \
	    KERNEL_KIT=$(KERNEL_PLATFORM_TO_ROOT)/$(KERNEL_PREBUILT_DIR) \
	    ./build/build_module.sh $(kbuild_options) \
	    ANDROID_BUILD_TOP=$$(realpath $$(pwd)/$(KERNEL_PLATFORM_TO_ROOT)) \
	)
	touch $@

endif

else # Use old full prebuilt kernel platform method

# Since this file will be included more than once for directories
# with more than one kernel module, the shared KBUILD_TARGET rule should
# only be defined once to avoid "overriding commands ..." warnings.
ifndef $(MODULE_KP_COMBINED_TARGET)_RULE
$(MODULE_KP_COMBINED_TARGET)_RULE := 1

# Kernel modules have to be built after:
#  * the kernel config has been created
#  * host executables, like scripts/basic/fixdep, have been built
#    (otherwise parallel invocations of the kernel build system will
#    fail as they all try to compile these executables at the same time)
#  * a full kernel build (to make module versioning work)
$(MODULE_KP_COMBINED_TARGET): local_path     := $(LOCAL_PATH)
$(MODULE_KP_COMBINED_TARGET): local_out      := $(MODULE_KP_OUT_DIR)
$(MODULE_KP_COMBINED_TARGET): kbuild_options := $(KBUILD_OPTIONS)
$(MODULE_KP_COMBINED_TARGET):
	(cd $(KERNEL_PLATFORM_PATH) && \
	    EXT_MODULES=la/$(local_path) \
	    MODULE_OUT=$(KERNEL_PLATFORM_TO_ROOT)$(local_out) \
	    ./build/build_module.sh $(kbuild_options) \
	    ANDROID_BUILD_TOP=$$(realpath $$(pwd)/$(KERNEL_PLATFORM_TO_ROOT)) \
	)
	touch $@

endif
endif

# Once the KBUILD_OPTIONS variable has been used for the target
# that's specific to the LOCAL_PATH, clear it. If this isn't done,
# then every kernel module would need to explicitly set KBUILD_OPTIONS,
# or the variable would have to be cleared in 'include $(CLEAR_VARS)'
# which would require a change to build/core.
KBUILD_OPTIONS :=
LOCAL_ADDITIONAL_DEPENDENCIES :=
LOCAL_MODULE_KBUILD_NAME :=