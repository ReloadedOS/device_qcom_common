# Enter project path into pathmap
#
# $(1): name
# $(2): path
#
define project-set-path
$(eval pathmap_PROJ += $(1):$(2))
$(eval PRODUCT_SOONG_NAMESPACES += $(2))
endef

# Returns the path to the requested module's include directory,
# relative to the root of the source tree.
#
# $(1): a list of modules (or other named entities) to find the projects for
define project-path-for
$(foreach n,$(1),$(patsubst $(n):%,%,$(filter $(n):%,$(pathmap_PROJ))))
endef

# Set device-specific HALs into project pathmap
define set-device-specific-path
$(if $(USE_DEVICE_SPECIFIC_$(1)), \
    $(if $(DEVICE_SPECIFIC_$(1)_PATH), \
        $(eval path := $(DEVICE_SPECIFIC_$(1)_PATH)), \
        $(eval path := )),
    $(eval path := $(3))) \
$(call project-set-path,qcom-$(2),$(strip $(path)))
endef
