# Makefile for K8s Ultimate Toolbox
# Runtime: Docker preferred, nerdctl/containerd fallback

CHART_NAME := ultimate-k8s-toolbox
CHART_VERSION := 1.2.0
BUNDLE_VERSION := v1.2.0
TOOLBOX_IMAGE_REPO := $(CHART_NAME)
TOOLBOX_IMAGE_TAG := $(BUNDLE_VERSION)
TOOLBOX_IMAGE := $(TOOLBOX_IMAGE_REPO):$(TOOLBOX_IMAGE_TAG)

KUBECTL_VERSION := v1.36.1
HELM_VERSION := v4.2.1
YQ_VERSION := v4.53.3
KEYCLOAK_VERSION := 26.6.3
MONGOSH_VERSION := 2.8.3
MONGO_TOOLS_VERSION := 100.17.0
TRIDENT_VERSION := 26.02.0
NERDCTL_VERSION := 2.3.2
CRICTL_VERSION := v1.36.0
ETCD_VERSION := v3.6.12
CMCTL_VERSION := v2.2.0
STEP_VERSION := v0.30.2
KUBENT_VERSION := 0.7.3
KUBECONFORM_VERSION := v0.8.0
POPEYE_VERSION := v0.22.1
KUBECTL_WHO_CAN_VERSION := v0.4.0
RBAC_LOOKUP_VERSION := v0.10.3
CILIUM_CLI_VERSION := v0.19.2
HUBBLE_VERSION := v1.18.6
CALICOCTL_VERSION := v3.32.0

NERDCTL := nerdctl
NERDCTL_NAMESPACE := k8s.io
BUILD_DIR := build
CHART_DIR := chart
BUNDLE_DIR := dist/offline-bundle
BUNDLE_ARCHIVE := dist/$(CHART_NAME)-offline-$(BUNDLE_VERSION).tar.gz
IMAGES_DIR := $(BUNDLE_DIR)/images
CHARTS_DIR := $(BUNDLE_DIR)/charts
SCRIPTS_DIR := $(BUNDLE_DIR)/scripts
DOCS_DIR := $(BUNDLE_DIR)/docs

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "K8s Ultimate Toolbox $(BUNDLE_VERSION)"
	@echo "Targets: build-image, test-image, package-chart, offline-bundle, info, clean"

.PHONY: info
info:
	@echo "Chart: $(CHART_NAME) $(CHART_VERSION)"
	@echo "Image: $(TOOLBOX_IMAGE)"
	@echo "kubectl=$(KUBECTL_VERSION) helm=$(HELM_VERSION) yq=$(YQ_VERSION)"
	@echo "keycloak=$(KEYCLOAK_VERSION) mongosh=$(MONGOSH_VERSION) mongo-tools=$(MONGO_TOOLS_VERSION) trident=$(TRIDENT_VERSION)"
	@echo "crictl=$(CRICTL_VERSION) etcd=$(ETCD_VERSION) cmctl=$(CMCTL_VERSION) step=$(STEP_VERSION)"
	@echo "kubent=$(KUBENT_VERSION) kubeconform=$(KUBECONFORM_VERSION) popeye=$(POPEYE_VERSION)"
	@echo "kubectl-who-can=$(KUBECTL_WHO_CAN_VERSION) rbac-lookup=$(RBAC_LOOKUP_VERSION)"
	@echo "cilium=$(CILIUM_CLI_VERSION) hubble=$(HUBBLE_VERSION) calicoctl=$(CALICOCTL_VERSION)"

.PHONY: check-dependencies
check-dependencies:
	@command -v helm >/dev/null 2>&1 || (echo "helm is required" && exit 1)
	@command -v curl >/dev/null 2>&1 || (echo "curl is required" && exit 1)
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then echo "Docker detected"; elif command -v $(NERDCTL) >/dev/null 2>&1; then echo "nerdctl detected"; else echo "Docker or nerdctl is required"; exit 1; fi

.PHONY: check-internet
check-internet:
	@curl -fsS --connect-timeout 10 https://registry-1.docker.io >/dev/null
	@curl -fsS --connect-timeout 10 https://github.com >/dev/null
	@curl -fsS --connect-timeout 10 https://dl.k8s.io >/dev/null
	@curl -fsS --connect-timeout 10 https://get.helm.sh >/dev/null
	@echo "Internet connectivity verified"

.PHONY: prepare-bundle
prepare-bundle:
	@mkdir -p $(IMAGES_DIR) $(CHARTS_DIR) $(SCRIPTS_DIR) $(DOCS_DIR)

BUILD_ARGS := \
  --build-arg TOOLBOX_VERSION=$(CHART_VERSION) \
  --build-arg MONGOSH_VERSION=$(MONGOSH_VERSION) \
  --build-arg MONGO_TOOLS_VERSION=$(MONGO_TOOLS_VERSION) \
  --build-arg KUBECTL_VERSION=$(KUBECTL_VERSION) \
  --build-arg HELM_VERSION=$(HELM_VERSION) \
  --build-arg YQ_VERSION=$(YQ_VERSION) \
  --build-arg KEYCLOAK_VERSION=$(KEYCLOAK_VERSION) \
  --build-arg TRIDENT_VERSION=$(TRIDENT_VERSION) \
  --build-arg CRICTL_VERSION=$(CRICTL_VERSION) \
  --build-arg ETCD_VERSION=$(ETCD_VERSION) \
  --build-arg CMCTL_VERSION=$(CMCTL_VERSION) \
  --build-arg STEP_VERSION=$(STEP_VERSION) \
  --build-arg KUBENT_VERSION=$(KUBENT_VERSION) \
  --build-arg KUBECONFORM_VERSION=$(KUBECONFORM_VERSION) \
  --build-arg POPEYE_VERSION=$(POPEYE_VERSION) \
  --build-arg KUBECTL_WHO_CAN_VERSION=$(KUBECTL_WHO_CAN_VERSION) \
  --build-arg RBAC_LOOKUP_VERSION=$(RBAC_LOOKUP_VERSION) \
  --build-arg CILIUM_CLI_VERSION=$(CILIUM_CLI_VERSION) \
  --build-arg HUBBLE_VERSION=$(HUBBLE_VERSION) \
  --build-arg CALICOCTL_VERSION=$(CALICOCTL_VERSION)

.PHONY: build-image
build-image: check-dependencies
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then docker build $(BUILD_ARGS) -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/; else $(NERDCTL) --namespace $(NERDCTL_NAMESPACE) build $(BUILD_ARGS) -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/; fi
	@$(MAKE) test-image

.PHONY: test-image
test-image:
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then RUNNER="docker run --rm $(TOOLBOX_IMAGE)"; else RUNNER="$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) run --rm $(TOOLBOX_IMAGE)"; fi; $$RUNNER bash -lc "show-versions.sh; command -v crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl >/dev/null; command -v kubectl helm yq kcadm.sh psql mongosh tridentctl >/dev/null; echo verified"

.PHONY: package-chart
package-chart:
	@helm lint $(CHART_DIR)/
	@mkdir -p $(CHARTS_DIR)
	@helm package $(CHART_DIR)/ -d $(CHARTS_DIR)
	@if [ -f $(CHARTS_DIR)/$(CHART_NAME)-$(CHART_VERSION).tgz ]; then mv $(CHARTS_DIR)/$(CHART_NAME)-$(CHART_VERSION).tgz $(CHARTS_DIR)/$(CHART_NAME)-chart-$(CHART_VERSION).tgz; fi

.PHONY: create-scripts
create-scripts:
	@mkdir -p $(SCRIPTS_DIR)
	@if [ -f scripts/deploy-offline.sh.template ]; then cp scripts/deploy-offline.sh.template $(SCRIPTS_DIR)/deploy-offline.sh; sed -i 's|^IMAGE_REPO=.*|IMAGE_REPO=$${IMAGE_REPO:-"$(TOOLBOX_IMAGE_REPO)"}|' $(SCRIPTS_DIR)/deploy-offline.sh; sed -i 's|^IMAGE_TAG=.*|IMAGE_TAG=$${IMAGE_TAG:-"$(TOOLBOX_IMAGE_TAG)"}|' $(SCRIPTS_DIR)/deploy-offline.sh; chmod +x $(SCRIPTS_DIR)/deploy-offline.sh; fi
	@printf '%s\n' "K8s Ultimate Toolbox Offline Bundle" "Version: $(BUNDLE_VERSION)" "Chart Version: $(CHART_VERSION)" "Image: $(TOOLBOX_IMAGE)" > $(BUNDLE_DIR)/README.txt

.PHONY: create-sbom
create-sbom:
	@mkdir -p $(BUNDLE_DIR)
	@printf '%s\n' "Software Bill of Materials" "==========================" "Bundle: $(CHART_NAME) $(BUNDLE_VERSION)" "" "Pinned components:" "- kubectl $(KUBECTL_VERSION)" "- Helm $(HELM_VERSION)" "- yq $(YQ_VERSION)" "- Keycloak CLI $(KEYCLOAK_VERSION)" "- mongosh $(MONGOSH_VERSION)" "- MongoDB Database Tools $(MONGO_TOOLS_VERSION)" "- tridentctl $(TRIDENT_VERSION)" "- crictl $(CRICTL_VERSION)" "- etcdctl/etcdutl $(ETCD_VERSION)" "- cmctl $(CMCTL_VERSION)" "- step $(STEP_VERSION)" "- kubent $(KUBENT_VERSION)" "- kubeconform $(KUBECONFORM_VERSION)" "- popeye $(POPEYE_VERSION)" "- kubectl-who-can $(KUBECTL_WHO_CAN_VERSION)" "- rbac-lookup $(RBAC_LOOKUP_VERSION)" "- cilium $(CILIUM_CLI_VERSION)" "- hubble $(HUBBLE_VERSION)" "- calicoctl $(CALICOCTL_VERSION)" > $(BUNDLE_DIR)/SBOM.txt

.PHONY: create-docs
create-docs:
	@mkdir -p $(DOCS_DIR)
	@for doc in README.md QUICKSTART.md OFFLINE-DEPLOYMENT.md MAKEFILE.md SBOM.md TOOLS-REFERENCE.md POSTGRESQL-DIAGNOSTICS.md KEYCLOAK-GUIDE.md RECOMMENDED-TOOLS.md CHANGELOG.md; do if [ -f "$$doc" ]; then cp "$$doc" $(DOCS_DIR)/; fi; done
	@if [ -f docs/NERDCTL-GUIDE.md ]; then cp docs/NERDCTL-GUIDE.md $(DOCS_DIR)/; fi

.PHONY: export-image
export-image:
	@mkdir -p $(IMAGES_DIR)
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then docker save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar; else $(NERDCTL) --namespace $(NERDCTL_NAMESPACE) save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar; fi
	@sha256sum $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar > $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar.sha256

.PHONY: bundle-archive
bundle-archive:
	@cd dist && tar -czf $(notdir $(BUNDLE_ARCHIVE)) offline-bundle/
	@echo "Created $(BUNDLE_ARCHIVE)"

.PHONY: offline-bundle
offline-bundle: check-dependencies check-internet prepare-bundle build-image export-image package-chart create-scripts create-sbom create-docs bundle-archive
	@echo "Offline bundle complete: $(BUNDLE_ARCHIVE)"

.PHONY: clean
clean:
	@echo "Remove generated artifacts manually: dist/ offline-bundle/ build logs and local image cache as needed."
