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
CONTROLLER_MANAGER_REPO := https://github.com/upbound/controller-manager.git
# Tag corresponds to Docker image tag while commit is git-compatible signature
# for pulling. They do not always match.
CROSSPLANE_TAG := v2.0.0-rc.0
CROSSPLANE_COMMIT := v2.0.0-rc.0

CONTROLLER_MANAGER_TAG := v0.1.0-rc.0.4.g0902b55
CONTROLLER_MANAGER_COMMIT := 0902b5518c8453ef45f4c33687cdd95a3680fe06

export CROSSPLANE_TAG
export CONTROLLER_MANAGER_TAG

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
HELM_CHARTS = crossplane
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

GITCP_CMD_CROSSPLANE ?= git -C $(WORK_DIR)/crossplane
GITCP_CMD_UPBOUND_CONTROLLER_MANAGER ?= git -C $(WORK_DIR)/controller-manager

crossplane:
	@$(INFO) Fetching Crossplane chart $(CROSSPLANE_TAG)
	@rm -rf $(WORK_DIR)/crossplane
	@mkdir -p $(WORK_DIR)/crossplane
	@$(GITCP_CMD_CROSSPLANE) init
	@$(GITCP_CMD_CROSSPLANE) remote add origin $(CROSSPLANE_REPO) 2>/dev/null || true
	@$(GITCP_CMD_CROSSPLANE) fetch origin
	@$(GITCP_CMD_CROSSPLANE) checkout $(CROSSPLANE_COMMIT)
	@mkdir -p $(HELM_CHARTS_DIR)/crossplane/templates/crossplane
	@rm -f $(HELM_CHARTS_DIR)/crossplane/templates/crossplane/*
	@cp -a $(WORK_DIR)/crossplane/cluster/charts/crossplane/templates/* $(HELM_CHARTS_DIR)/crossplane/templates/crossplane
	@$(OK) Crossplane chart has been fetched

upbound-controller-manager:
	@$(INFO) Fetching Upbound controller manager chart $(CONTROLLER_MANAGER_TAG)
	@rm -rf $(WORK_DIR)/controller-manager
	@mkdir -p $(WORK_DIR)/controller-manager
	@$(GITCP_CMD_UPBOUND_CONTROLLER_MANAGER) init
	@$(GITCP_CMD_UPBOUND_CONTROLLER_MANAGER) remote add origin $(CONTROLLER_MANAGER_REPO) 2>/dev/null || true
	@$(GITCP_CMD_UPBOUND_CONTROLLER_MANAGER) fetch origin
	@$(GITCP_CMD_UPBOUND_CONTROLLER_MANAGER) checkout $(CONTROLLER_MANAGER_COMMIT)
	@mkdir -p $(HELM_CHARTS_DIR)/crossplane/templates/upbound
	@rm -f $(HELM_CHARTS_DIR)/crossplane/templates/upbound/*
	@cp -a $(WORK_DIR)/controller-manager/cluster/charts/controller-manager/templates/* $(HELM_CHARTS_DIR)/crossplane/templates/upbound
	@cp -a $(WORK_DIR)/crossplane/cluster/charts/crossplane/values.yaml $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@$(OK) Upbound controller manager chart has been fetched

generate-chart: $(YQ) crossplane upbound-controller-manager
	@$(INFO) Merging Crossplane and Upbound controller manager values.yaml files
	@rm -f $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@cp -a $(WORK_DIR)/crossplane/cluster/charts/crossplane/values.yaml $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@cat $(WORK_DIR)/controller-manager/cluster/charts/controller-manager/values.yaml >> $(HELM_CHARTS_DIR)/crossplane/values.yaml
	# Note(turkenh): YQ strips out the empty lines in the values.yaml file, which is not ideal: https://github.com/mikefarah/yq/issues/515
	# After spending some time, I couldn't find a better/lightweight alternative. Tried sed, dasel and dyff but no luck.
	# If this hurts somehow in the future, we can revisit and consider building a more complex/hacky solution.
	@$(YQ) eval '.image.tag = "$(CROSSPLANE_TAG)" | .upbound.manager.image.tag = "$(CONTROLLER_MANAGER_TAG)"' -i $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@$(OK) Merged Crossplane and Upbound controller manager values.yaml files

generate.init: generate-chart

# ====================================================================================
# Local Development

# local-dev builds the controller manager, and deploys it to a kind cluster. It runs in your
# local environment, not a container. The kind cluster will keep running until
# you run the local-dev.down target. Run local-dev again to rebuild the controller manager and restart
# the kind cluster with the new build. Uses random version suffix to ensure existing pods are replaced.
local-dev: $(KIND) $(HELM)
	@$(INFO) Setting up local development environment
	@set -e; \
	if ! $(KIND) get clusters | grep -q "^uxp-dev$$"; then \
		$(KIND) create cluster --name uxp-dev; \
	fi; \
	docker pull xpkg.upbound.io/upbound/crossplane:$(CROSSPLANE_TAG); \
	$(KIND) load docker-image --name uxp-dev xpkg.upbound.io/upbound/crossplane:$(CROSSPLANE_TAG); \
	docker pull xpkg.upbound.io/upbound-dev/controller-manager:$(CONTROLLER_MANAGER_TAG); \
	$(KIND) load docker-image --name uxp-dev xpkg.upbound.io/upbound-dev/controller-manager:$(CONTROLLER_MANAGER_TAG); \
	HELM_SETS="upbound.manager.image.pullPolicy=Never,upbound.manager.image.tag=$$CONTROLLER_MANAGER_TAG,upbound.manager.args={--debug}"; \
	if [ -n "$$UXP_LICENSE_KEY" ]; then \
		HELM_SETS="$$HELM_SETS,upbound.licenseKey=$$UXP_LICENSE_KEY"; \
	fi; \
	$(HELM) upgrade --install crossplane --namespace crossplane-system --create-namespace ./cluster/charts/crossplane \
		--set "$$HELM_SETS"
	@$(OK) Local development environment ready

# local-dev.down deletes the kind cluster created by the local-dev target.
local-dev.down: $(KIND)
	@$(INFO) Tearing down local development environment
	@$(KIND) delete cluster --name uxp-dev 2>/dev/null || true
	@$(OK) Local development environment removed

.PHONY: crossplane submodules fallthrough
