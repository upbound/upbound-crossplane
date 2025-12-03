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

# Define GOHOST for helm-docs installation (from golang.mk but without Go targets)
GO ?= go
GOHOST := GOOS=$(HOSTOS) GOARCH=$(TARGETARCH) $(GO)

# ====================================================================================
# Versions

CROSSPLANE_REPO := https://github.com/upbound/crossplane.git
CROSSPLANE_TAG := v2.0.6-up.1

# ====================================================================================
# Setup Output

S3_BUCKET ?= public-upbound.releases/crossplane
-include build/makelib/output.mk

# ====================================================================================
# Setup Kubernetes tools
KIND_VERSION = v0.29.0
USE_HELM3 = true

-include build/makelib/k8s_tools.mk
# ====================================================================================
# Setup Helm

HELM_BASE_URL = https://charts.upbound.io
HELM_OCI_URL = xpkg.upbound.io/upbound
HELM_CHARTS = crossplane
HELM_S3_BUCKET = public-upbound.charts
HELM_DOCS_ENABLED = false
HELM_VALUES_TEMPLATE_SKIPPED = true
HELM_CHART_LINT_STRICT = false
-include build/makelib/helm.mk
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
# Extract commit from tag if it contains .g<commit> pattern, otherwise use tag as-is
# Example: v2.0.0-rc.0.151.gfdc0c3a14 → fdc0c3a14
# Example: v2.0.0-rc.0 → v2.0.0-rc.0
CROSSPLANE_COMMIT := $(shell echo $(CROSSPLANE_TAG) | grep -oE '\.g[a-f0-9]+$$' | sed 's/\.g//' || echo $(CROSSPLANE_TAG))
ifeq ($(CROSSPLANE_COMMIT),)
	CROSSPLANE_COMMIT := $(CROSSPLANE_TAG)
endif

# TODO(turkenh): Avoid fetching the entire Crossplane repository every time by checking whether it is already checked out.
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

generate-chart: $(YQ) crossplane helm.lint
	@$(INFO) Generating Chart from Upbound Crossplane
	@rm -f $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@cp -a $(WORK_DIR)/crossplane/cluster/charts/crossplane/values.yaml $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@# Note(turkenh): We need to patch the deployment.yaml file to add the UXP specific flags.
	@# Since deployment.yaml is a Helm template with {{ }} syntax, we can't use YQ (it would fail to parse).
	@# We use sed with pattern matching to inject after "- core" and "- start" args. While sed could fail
	@# silently if the pattern changes, we have a grep check below to ensure the injection succeeded.
	@# Any pattern changes in upstream would be caught either by the grep check or during PR review since
	@# the generated chart is also committed to the repository.
	@sed -i -e '/^        - core$$/{n' -e '/^        - start$$/a\        - --enable-operations' -e '/^        - start$$/a\        - --package-runtime=External' -e '}' $(HELM_CHARTS_DIR)/crossplane/templates/crossplane/deployment.yaml
	@if ! grep -q -- '--enable-operations' $(HELM_CHARTS_DIR)/crossplane/templates/crossplane/deployment.yaml; then \
		echo "ERROR: Failed to inject --enable-operations arg"; \
		exit 1; \
	fi
	@if ! grep -q -- '--package-runtime=External' $(HELM_CHARTS_DIR)/crossplane/templates/crossplane/deployment.yaml; then \
		echo "ERROR: Failed to inject --package-runtime arg"; \
		exit 1; \
	fi
	@echo "Successfully injected args"
	@# Note(turkenh): YQ strips out the empty lines in the values.yaml file, which is not ideal: https://github.com/mikefarah/yq/issues/515
	@# After spending some time, I couldn't find a better/lightweight alternative. Tried dasel and dyff but no luck.
	@# We may still chose using sed just to be consistent with the above (where YQ cannot work), but I kept yq since it
	@# is more robust here.
	@$(YQ) eval '.image.tag = "$(CROSSPLANE_TAG)"' -i $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@$(YQ) eval '.rbac.clusterAdmin = false' -i $(HELM_CHARTS_DIR)/crossplane/values.yaml
	@$(OK) Generated Chart from Upbound Crossplane

helm.dep: generate-chart

# ====================================================================================
# Local Development

# local-dev builds the controller manager, and deploys it to a kind cluster. It runs in your
# local environment, not a container. The kind cluster will keep running until
# you run the local-dev.down target. Run local-dev again to rebuild the controller manager and restart
# the kind cluster with the new build. Uses random version suffix to ensure existing pods are replaced.
# Make sure you set the UPBOUND_PULLBOT_ID and UPBOUND_PULLBOT_TOKEN environment variables
local-dev: $(KUBECTL) $(KIND) $(HELM)
	@$(INFO) Setting up local development environment
	@if [ -z "$$UPBOUND_PULLBOT_ID" ] || [ -z "$$UPBOUND_PULLBOT_TOKEN" ]; then \
		echo "ERROR: UPBOUND_PULLBOT_ID and UPBOUND_PULLBOT_TOKEN environment variables must be set"; \
		exit 1; \
	fi
	@set -e; \
	if ! $(KIND) get clusters | grep -q "^uxp-dev$$"; then \
		$(KIND) create cluster --name uxp-dev; \
	fi; \
	$(KUBECTL) create namespace crossplane-system --dry-run=client -o yaml | $(KUBECTL) apply -f - ; \
	$(KUBECTL) -n crossplane-system create secret docker-registry uxpv2-pull --docker-server=xpkg.upbound.io --docker-username=$$UPBOUND_PULLBOT_ID --docker-password=$$UPBOUND_PULLBOT_TOKEN --dry-run=client -o yaml | $(KUBECTL) apply -f - ; \
	HELM_SETS="upbound.manager.args={--debug},upbound.manager.imagePullSecrets[0].name=uxpv2-pull,webui.imagePullSecrets[0].name=uxpv2-pull,apollo.imagePullSecrets[0].name=uxpv2-pull"; \
	$(HELM) upgrade --install crossplane --namespace crossplane-system ./cluster/charts/crossplane \
		--set "$$HELM_SETS"; \
	if [ -n "$$UXP_LICENSE_FILE" ]; then \
		$(KUBECTL) -n crossplane-system wait deployment upbound-controller-manager --for=condition=Available; \
		$(KUBECTL) create secret generic uxp-license --namespace crossplane-system --from-file=license.json=$$UXP_LICENSE_FILE -o yaml --dry-run=client | $(KUBECTL) apply -f - ; \
		$(KUBECTL) patch license uxp --type merge --patch '{"spec":{"secretRef":{"name":"uxp-license","namespace":"crossplane-system","key":"license.json"}}}'; \
	fi
	@$(OK) Local development environment ready

# local-dev.down deletes the kind cluster created by the local-dev target.
local-dev.down: $(KIND)
	@$(INFO) Tearing down local development environment
	@$(KIND) delete cluster --name uxp-dev 2>/dev/null || true
	@$(OK) Local development environment removed

.PHONY: crossplane submodules fallthrough

get-versions:
	@echo CROSSPLANE_VERSION=$(CROSSPLANE_TAG)
	@echo HELM_CHART_VERSION=$(HELM_CHART_VERSION)
