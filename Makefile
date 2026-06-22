# Makefile for Ultimate K8s Toolbox
# Runtime: Docker preferred, nerdctl/containerd fallback

CHART_NAME := ultimate-k8s-toolbox
CHART_VERSION := 1.1.0
BUNDLE_VERSION := v1.1.0
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
CONTAINERD_VERSION := 2.3.1

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
	@echo "Ultimate K8s Toolbox $(BUNDLE_VERSION)"
	@echo ""
	@echo "Targets:"
	@echo "  make build-image        Build the toolbox image"
	@echo "  make test-image         Verify the image toolchain"
	@echo "  make offline-bundle     Build image, package chart, and create air-gapped bundle"
	@echo "  make package-chart      Lint and package Helm chart"
	@echo "  make check-dependencies Check Docker/nerdctl availability"
	@echo "  make install-nerdctl    Install nerdctl $(NERDCTL_VERSION)"
	@echo "  make info               Print pinned component versions"
	@echo "  make clean              Remove generated artifacts"
	@echo ""
	@echo "Version set: kubectl=$(KUBECTL_VERSION), helm=$(HELM_VERSION), keycloak=$(KEYCLOAK_VERSION), postgres=Ubuntu 24.04 client stack"

.PHONY: all
all: offline-bundle

.PHONY: info
info:
	@echo "Chart:        $(CHART_NAME) $(CHART_VERSION)"
	@echo "Image:        $(TOOLBOX_IMAGE)"
	@echo "kubectl:      $(KUBECTL_VERSION)"
	@echo "Helm:         $(HELM_VERSION)"
	@echo "yq:           $(YQ_VERSION)"
	@echo "Keycloak:     $(KEYCLOAK_VERSION)"
	@echo "mongosh:      $(MONGOSH_VERSION)"
	@echo "Mongo tools:  $(MONGO_TOOLS_VERSION)"
	@echo "tridentctl:   $(TRIDENT_VERSION)"
	@echo "nerdctl:      $(NERDCTL_VERSION)"
	@echo "containerd:   $(CONTAINERD_VERSION)"

.PHONY: check-dependencies
check-dependencies:
	@echo "Checking container runtime..."
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		echo "✓ Docker detected"; \
	elif command -v $(NERDCTL) >/dev/null 2>&1; then \
		echo "✓ nerdctl detected"; \
	else \
		echo "✗ Docker or nerdctl is required. Run 'make install-nerdctl' or install Docker."; \
		exit 1; \
	fi
	@command -v helm >/dev/null 2>&1 || (echo "✗ helm is required to package the chart" && exit 1)
	@command -v curl >/dev/null 2>&1 || (echo "✗ curl is required" && exit 1)

.PHONY: install-nerdctl
install-nerdctl:
	@echo "Installing nerdctl $(NERDCTL_VERSION)..."
	@ARCH=$$(uname -m); \
	case "$$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "Unsupported arch: $$ARCH"; exit 1 ;; esac; \
	URL="https://github.com/containerd/nerdctl/releases/download/v$(NERDCTL_VERSION)/nerdctl-$(NERDCTL_VERSION)-linux-$${ARCH}.tar.gz"; \
	echo "Downloading $$URL"; \
	if [ "$$(id -u)" -ne 0 ]; then \
		curl -fsSL "$$URL" | sudo tar -xz -C /usr/local/bin nerdctl; \
		sudo chmod +x /usr/local/bin/nerdctl; \
	else \
		curl -fsSL "$$URL" | tar -xz -C /usr/local/bin nerdctl; \
		chmod +x /usr/local/bin/nerdctl; \
	fi
	@nerdctl version

.PHONY: check-internet
check-internet:
	@echo "Checking internet access needed for image build..."
	@curl -fsS --connect-timeout 10 https://registry-1.docker.io >/dev/null
	@curl -fsS --connect-timeout 10 https://github.com >/dev/null
	@curl -fsS --connect-timeout 10 https://dl.k8s.io >/dev/null
	@curl -fsS --connect-timeout 10 https://get.helm.sh >/dev/null
	@echo "✓ Internet connectivity verified"

.PHONY: prepare-bundle
prepare-bundle:
	@rm -rf dist/
	@mkdir -p $(IMAGES_DIR) $(CHARTS_DIR) $(SCRIPTS_DIR) $(DOCS_DIR)

.PHONY: build-image
build-image: check-dependencies
	@echo "Building $(TOOLBOX_IMAGE)..."
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker build \
		  --build-arg TOOLBOX_VERSION=$(CHART_VERSION) \
		  --build-arg MONGOSH_VERSION=$(MONGOSH_VERSION) \
		  --build-arg MONGO_TOOLS_VERSION=$(MONGO_TOOLS_VERSION) \
		  --build-arg KUBECTL_VERSION=$(KUBECTL_VERSION) \
		  --build-arg HELM_VERSION=$(HELM_VERSION) \
		  --build-arg YQ_VERSION=$(YQ_VERSION) \
		  --build-arg KEYCLOAK_VERSION=$(KEYCLOAK_VERSION) \
		  --build-arg TRIDENT_VERSION=$(TRIDENT_VERSION) \
		  -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/; \
	else \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) build \
		  --build-arg TOOLBOX_VERSION=$(CHART_VERSION) \
		  --build-arg MONGOSH_VERSION=$(MONGOSH_VERSION) \
		  --build-arg MONGO_TOOLS_VERSION=$(MONGO_TOOLS_VERSION) \
		  --build-arg KUBECTL_VERSION=$(KUBECTL_VERSION) \
		  --build-arg HELM_VERSION=$(HELM_VERSION) \
		  --build-arg YQ_VERSION=$(YQ_VERSION) \
		  --build-arg KEYCLOAK_VERSION=$(KEYCLOAK_VERSION) \
		  --build-arg TRIDENT_VERSION=$(TRIDENT_VERSION) \
		  -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/; \
	fi
	@$(MAKE) test-image

.PHONY: test-image
test-image:
	@echo "Verifying image toolchain..."
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		RUNNER="docker run --rm $(TOOLBOX_IMAGE)"; \
	else \
		RUNNER="$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) run --rm $(TOOLBOX_IMAGE)"; \
	fi; \
	$$RUNNER bash -lc "show-versions.sh; \
	  kubectl version --client=true >/dev/null; \
	  helm version --short >/dev/null; \
	  yq --version >/dev/null; \
	  kcadm.sh --help >/dev/null; \
	  psql --version >/dev/null; \
	  pg_isready --version >/dev/null; \
	  pg-diagnostics.sh --help >/dev/null; \
	  mongosh --version >/dev/null; \
	  mongodump --version >/dev/null; \
	  tridentctl version --client >/dev/null 2>&1; \
	  echo '✓ critical tools verified'"

.PHONY: package-chart
package-chart:
	@echo "Linting and packaging Helm chart..."
	@helm lint $(CHART_DIR)/
	@mkdir -p $(CHARTS_DIR)
	@helm package $(CHART_DIR)/ -d $(CHARTS_DIR)
	@ORIG_CHART_FILE=$(CHARTS_DIR)/$(CHART_NAME)-$(CHART_VERSION).tgz; \
	NEW_CHART_FILE=$(CHARTS_DIR)/$(CHART_NAME)-chart-$(CHART_VERSION).tgz; \
	if [ -f "$$ORIG_CHART_FILE" ]; then mv "$$ORIG_CHART_FILE" "$$NEW_CHART_FILE"; fi

.PHONY: create-scripts
create-scripts:
	@mkdir -p $(SCRIPTS_DIR)
	@if [ -f scripts/deploy-offline.sh.template ]; then \
		cp scripts/deploy-offline.sh.template $(SCRIPTS_DIR)/deploy-offline.sh; \
		sed -i 's/^IMAGE_REPO=.*/IMAGE_REPO=$$(printf "%q" "$(TOOLBOX_IMAGE_REPO)")/' $(SCRIPTS_DIR)/deploy-offline.sh || true; \
		sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=$$(printf "%q" "$(TOOLBOX_IMAGE_TAG)")/' $(SCRIPTS_DIR)/deploy-offline.sh || true; \
		chmod +x $(SCRIPTS_DIR)/deploy-offline.sh; \
	fi
	@printf '%s\n' \
	  "Ultimate K8s Toolbox Offline Bundle" \
	  "Version: $(BUNDLE_VERSION)" \
	  "Chart Version: $(CHART_VERSION)" \
	  "Image: $(TOOLBOX_IMAGE)" \
	  "Created: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	  "" \
	  "Quick start:" \
	  "  1. Load/push images from images/" \
	  "  2. Install chart from charts/" \
	  "  3. Review docs/POSTGRESQL-DIAGNOSTICS.md and docs/KEYCLOAK-GUIDE.md" \
	  > $(BUNDLE_DIR)/README.txt

.PHONY: create-sbom
create-sbom:
	@mkdir -p $(BUNDLE_DIR)
	@IMAGE_ID="unknown"; \
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		IMAGE_ID=$$(docker inspect --format='{{.Id}}' $(TOOLBOX_IMAGE) 2>/dev/null | sed 's/sha256://'); \
	elif command -v $(NERDCTL) >/dev/null 2>&1; then \
		IMAGE_ID=$$($(NERDCTL) --namespace $(NERDCTL_NAMESPACE) inspect --format='{{.Id}}' $(TOOLBOX_IMAGE) 2>/dev/null | sed 's/sha256://'); \
	fi; \
	printf '%s\n' \
	  "Software Bill of Materials" \
	  "==========================" \
	  "Bundle: $(CHART_NAME) $(BUNDLE_VERSION)" \
	  "Image Digest: sha256:$$IMAGE_ID" \
	  "" \
	  "Pinned components:" \
	  "- kubectl $(KUBECTL_VERSION)" \
	  "- Helm $(HELM_VERSION)" \
	  "- yq $(YQ_VERSION)" \
	  "- Keycloak CLI $(KEYCLOAK_VERSION)" \
	  "- mongosh $(MONGOSH_VERSION)" \
	  "- MongoDB Database Tools $(MONGO_TOOLS_VERSION)" \
	  "- tridentctl $(TRIDENT_VERSION)" \
	  "- PostgreSQL client/contrib stack from Ubuntu 24.04 repositories" \
	  "- pgcli, pg_activity, psycopg from PyPI" \
	  "- nerdctl $(NERDCTL_VERSION) build host helper" \
	  > $(BUNDLE_DIR)/SBOM.txt; \
	printf '{\n  "bomFormat": "CycloneDX",\n  "specVersion": "1.5",\n  "version": 1,\n  "metadata": { "component": { "type": "container", "name": "$(CHART_NAME)", "version": "$(BUNDLE_VERSION)" } },\n  "components": [\n    { "type": "application", "name": "kubectl", "version": "$(KUBECTL_VERSION)" },\n    { "type": "application", "name": "helm", "version": "$(HELM_VERSION)" },\n    { "type": "application", "name": "yq", "version": "$(YQ_VERSION)" },\n    { "type": "application", "name": "keycloak", "version": "$(KEYCLOAK_VERSION)" },\n    { "type": "application", "name": "mongosh", "version": "$(MONGOSH_VERSION)" },\n    { "type": "application", "name": "mongodb-database-tools", "version": "$(MONGO_TOOLS_VERSION)" },\n    { "type": "application", "name": "tridentctl", "version": "$(TRIDENT_VERSION)" },\n    { "type": "application", "name": "postgresql-client", "version": "ubuntu-24.04" }\n  ]\n}\n' > $(BUNDLE_DIR)/SBOM.json

.PHONY: create-docs
create-docs:
	@mkdir -p $(DOCS_DIR)
	@for doc in README.md QUICKSTART.md OFFLINE-DEPLOYMENT.md MAKEFILE.md SBOM.md TOOLS-REFERENCE.md POSTGRESQL-DIAGNOSTICS.md KEYCLOAK-GUIDE.md RECOMMENDED-TOOLS.md NERDCTL-GUIDE.md CHANGELOG.md; do \
		if [ -f "$$doc" ]; then cp "$$doc" $(DOCS_DIR)/; fi; \
	done

.PHONY: export-image
export-image:
	@mkdir -p $(IMAGES_DIR)
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar; \
	else \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar; \
	fi
	@sha256sum $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar > $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar.sha256

.PHONY: bundle-archive
bundle-archive:
	@cd dist && tar -czf $(notdir $(BUNDLE_ARCHIVE)) offline-bundle/
	@echo "✓ Created $(BUNDLE_ARCHIVE)"
	@ls -lh $(BUNDLE_ARCHIVE)

.PHONY: offline-bundle
offline-bundle: check-dependencies check-internet prepare-bundle build-image export-image package-chart create-scripts create-sbom create-docs bundle-archive
	@echo "✓ Offline bundle complete: $(BUNDLE_ARCHIVE)"

.PHONY: clean
clean:
	@rm -rf dist/ $(CHART_NAME)-*.tgz offline-bundle/ *.tar.gz build-output.log build-latest.log offline-bundle-build.log
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then docker rmi $(TOOLBOX_IMAGE) 2>/dev/null || true; fi
	@if command -v $(NERDCTL) >/dev/null 2>&1; then $(NERDCTL) --namespace $(NERDCTL_NAMESPACE) rmi $(TOOLBOX_IMAGE) 2>/dev/null || true; fi

.PHONY: clean-all
clean-all: clean
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then docker system prune -f; fi
	@if command -v $(NERDCTL) >/dev/null 2>&1; then $(NERDCTL) --namespace $(NERDCTL_NAMESPACE) system prune -f; fi
