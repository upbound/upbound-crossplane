# ====================================================================================
# Setup Project

PROJECT_NAME := upbound-crossplane
PROJECT_REPO := github.com/upbound/$(PROJECT_NAME)

PLATFORMS ?= linux_amd64 linux_arm64

# -include will silently skip missing files, which allows us
# to load those files with a target in the Makefile. If only
# "include" was used, the make command would fail and refuse
# to run a target until the include commands succeeded.
-include build/makelib/common.mk

# ====================================================================================
# Versions

CROSSPLANE_REPO := https://github.com/upbound/crossplane.git
# Tag corresponds to Docker image tag while commit is git-compatible signature
# for pulling. They do not always match.
CROSSPLANE_TAG := v2.0.0-rc.0
CROSSPLANE_COMMIT := v2.0.0-rc.0
export CROSSPLANE_TAG

# ====================================================================================
# Setup Kubernetes tools
KIND_VERSION = v0.29.0
USE_HELM3 = true

-include build/makelib/k8s_tools.mk
# ====================================================================================
# Setup Helm

# Note(turkenh): The OCI image published will be $(HELM_OCI_URL)/crossplane:$(VERSION). So,
# be careful not to change HELM_OCI_URL to something that could override an existing image.
# For example, we should not set it to xpkg.upbound.io/upbound, otherwise it will override the
# existing crossplane image at that location. If we ever need to publish the chart as OCI image
# at some point, we should consider using a different URL like xpkg.upbound.io/upbound-charts.
# For now, we are using the xpkg.upbound.io/upbound-dev as a stop gap solution until we start
# publishing to the public upbound-stable helm repository.
HELM_OCI_URL = xpkg.upbound.io/upbound-dev
HELM_CHARTS = upbound-crossplane
HELM_DOCS_ENABLED = true
HELM_VALUES_TEMPLATE_SKIPPED = true
HELM_CHART_LINT_STRICT = false
-include makelib/helmoci.mk

# ====================================================================================
# Targets

# run `make help` to see the targets and options

# We want submodules to be set up the first time `make` is run.
# We manage the build/ folder and its Makefiles as a submodule.
# The first time `make` is run, the includes of build/*.mk files will
# all fail, and this target will be run. The next time, the default as defined
# by the includes will be run instead.
fallthrough: submodules
	@echo Initial setup complete. Running make again . . .
	@make

# Update the submodules, such as the common build scripts.
submodules:
	@git submodule sync
	@git submodule update --init --recursive

GITCP_CMD?=git -C $(WORK_DIR)/crossplane

crossplane:
	@$(INFO) Fetching Crossplane chart $(CROSSPLANE_TAG)
	@rm -rf $(WORK_DIR)/crossplane
	@mkdir -p $(WORK_DIR)/crossplane
	@$(GITCP_CMD) init
	@$(GITCP_CMD) remote add origin $(CROSSPLANE_REPO) 2>/dev/null || true
	@$(GITCP_CMD) fetch origin
	@$(GITCP_CMD) checkout $(CROSSPLANE_COMMIT)
	@mkdir -p $(HELM_CHARTS_DIR)/upbound-crossplane/templates/crossplane
	@rm -f $(HELM_CHARTS_DIR)/upbound-crossplane/templates/crossplane/*
	@cp -a $(WORK_DIR)/crossplane/cluster/charts/crossplane/templates/* $(HELM_CHARTS_DIR)/upbound-crossplane/templates/crossplane
	@rm -f $(HELM_CHARTS_DIR)/upbound-crossplane/values.yaml
	@cp -a $(WORK_DIR)/crossplane/cluster/charts/crossplane/values.yaml $(HELM_CHARTS_DIR)/upbound-crossplane/values.yaml
	@# Note(turkenh): Using sed to replace the repository and tag values in the values.yaml of the upstream chart
	@# with the ones we want to use for the UXP chart. We also append the uxp-values.yaml to the values.yaml for UXP
	@# specific values.
	@# This is more like an interim solution until we need more differences between the upstream and UXP charts.
	@$(SED_CMD) 's|repository: crossplane/crossplane|repository: upbound/crossplane|g' '$(HELM_CHARTS_DIR)/upbound-crossplane/values.yaml'
	@$(SED_CMD) 's|repository: crossplane/xfn|repository: upbound/xfn|g' '$(HELM_CHARTS_DIR)/upbound-crossplane/values.yaml'
	@$(SED_CMD) 's|tag: ""|tag: "$(CROSSPLANE_TAG)"|g' $(HELM_CHARTS_DIR)/upbound-crossplane/values.yaml
	@cat $(HELM_CHARTS_DIR)/upbound-crossplane/uxp-values.yaml >> $(HELM_CHARTS_DIR)/upbound-crossplane/values.yaml
	@$(OK) Crossplane chart has been fetched

generate.init: crossplane

# ====================================================================================
# Local Development

# local-dev builds the controller manager, and deploys it to a kind cluster. It runs in your
# local environment, not a container. The kind cluster will keep running until
# you run the local-dev.down target. Run local-dev again to rebuild the controller manager and restart
# the kind cluster with the new build. Uses random version suffix to ensure existing pods are replaced.
local-dev: $(KIND) $(HELM) generate
	@$(INFO) Setting up local development environment
	@set -e; \
	if ! $(KIND) get clusters | grep -q "^uxp-dev$$"; then \
		$(KIND) create cluster --name uxp-dev; \
	fi; \
	docker pull xpkg.upbound.io/upbound/crossplane:$(CROSSPLANE_TAG); \
	$(KIND) load docker-image --name uxp-dev xpkg.upbound.io/upbound/crossplane:$(CROSSPLANE_TAG); \
	HELM_SETS="upbound.manager.image.pullPolicy=Never,upbound.manager.image.repository=upbound/controller-manager,upbound.manager.image.tag=$$IMAGE_TAG,upbound.manager.args={--debug}"; \
	if [ -n "$$UXP_LICENSE_KEY" ]; then \
		HELM_SETS="$$HELM_SETS,upbound.licenseKey=$$UXP_LICENSE_KEY"; \
	fi; \
	$(HELM) upgrade --install crossplane --namespace crossplane-system --create-namespace ./cluster/charts/upbound-crossplane \
		--set "$$HELM_SETS"
	@$(OK) Local development environment ready

# local-dev.down deletes the kind cluster created by the local-dev target.
local-dev.down: $(KIND)
	@$(INFO) Tearing down local development environment
	@$(KIND) delete cluster --name uxp-dev 2>/dev/null || true
	@$(OK) Local development environment removed

.PHONY: crossplane submodules fallthrough
