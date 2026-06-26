# Makefile for K8s Ultimate Toolbox

CHART_NAME := k8s-ultimate-toolbox
CHART_VERSION := 1.2.0
BUNDLE_VERSION := v1.2.0
TOOLBOX_IMAGE_REPO := $(CHART_NAME)
TOOLBOX_IMAGE_TAG := $(BUNDLE_VERSION)
TOOLBOX_IMAGE := $(TOOLBOX_IMAGE_REPO):$(TOOLBOX_IMAGE_TAG)

BUILD_DIR := build
CHART_DIR := chart
DIST_DIR := dist
BUNDLE_DIR := $(DIST_DIR)/offline-bundle
BUNDLE_ARCHIVE := $(DIST_DIR)/$(CHART_NAME)-offline-$(BUNDLE_VERSION).tar.gz

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "K8s Ultimate Toolbox $(BUNDLE_VERSION)"
	@echo "make info"
	@echo "make build-image"
	@echo "make test-image"
	@echo "make package-chart"
	@echo "make offline-bundle"

.PHONY: info
info:
	@echo "Chart: $(CHART_NAME) $(CHART_VERSION)"
	@echo "Image: $(TOOLBOX_IMAGE)"
	@echo "Bundle: $(BUNDLE_ARCHIVE)"

.PHONY: build-image
build-image:
	docker build -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/

.PHONY: test-image
test-image:
	docker run --rm $(TOOLBOX_IMAGE) bash -lc 'show-versions.sh && command -v kubectl helm yq kcadm.sh psql mongosh tridentctl crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl >/dev/null'

.PHONY: package-chart
package-chart:
	helm lint $(CHART_DIR)/
	mkdir -p $(BUNDLE_DIR)/charts
	helm package $(CHART_DIR)/ -d $(BUNDLE_DIR)/charts

.PHONY: offline-bundle
offline-bundle: build-image package-chart
	mkdir -p $(BUNDLE_DIR)/images $(BUNDLE_DIR)/scripts $(BUNDLE_DIR)/docs
	docker save $(TOOLBOX_IMAGE) -o $(BUNDLE_DIR)/images/$(CHART_NAME)-$(BUNDLE_VERSION).tar
	cp scripts/deploy-offline.sh.template $(BUNDLE_DIR)/scripts/deploy-offline.sh
	cp README.md QUICKSTART.md OFFLINE-DEPLOYMENT.md TOOLS-REFERENCE.md SBOM.md CHANGELOG.md $(BUNDLE_DIR)/docs/
	cd $(DIST_DIR) && tar -czf $(notdir $(BUNDLE_ARCHIVE)) offline-bundle/

.PHONY: clean
clean:
	@echo "Remove generated artifacts under $(DIST_DIR)/ as needed."
