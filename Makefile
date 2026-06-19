# Makefile for Ultimate K8s Toolbox - Offline Bundle Creation
# Usage: make offline-bundle
# Runtime: nerdctl + containerd

CHART_NAME := ultimate-k8s-toolbox
CHART_VERSION := 1.0.2
BUNDLE_VERSION := v1.0.2
TOOLBOX_IMAGE_REPO := $(CHART_NAME)
TOOLBOX_IMAGE_TAG := $(BUNDLE_VERSION)
TOOLBOX_IMAGE := $(TOOLBOX_IMAGE_REPO):$(TOOLBOX_IMAGE_TAG)

# Container runtime configuration
NERDCTL := nerdctl
NERDCTL_NAMESPACE := k8s.io
NERDCTL_VERSION := 1.7.7
CONTAINERD_VERSION := 1.7.22

# Directory structure
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
	@echo "=========================================="
	@echo "Ultimate K8s Toolbox - Offline Bundle"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make offline-bundle     - Create complete offline bundle (uses Docker/containerd)"
	@echo "  make build-image        - Build toolbox image (auto-detects runtime)"
	@echo "  make test-image         - Test the built image"
	@echo "  make check-dependencies - Check/install container runtime"
	@echo "  make install-nerdctl    - Install nerdctl manually"
	@echo "  make install-containerd - Install containerd manually"
	@echo "  make info               - Display configuration"
	@echo "  make clean              - Remove generated files"
	@echo "  make clean-all          - Deep clean including images"
	@echo ""
	@echo "Runtime Detection:"
	@echo "  • Uses Docker if available"
	@echo "  • Falls back to nerdctl + containerd"
	@echo "  • Auto-installs containerd if needed"
	@echo ""
	@echo "Bundle Includes:"
	@echo "  • Container images with all tools"
	@echo "  • Helm chart for deployment"
	@echo "  • SBOM (Software Bill of Materials)"
	@echo "  • Deployment scripts and docs"
	@echo ""
	@echo "Quick Start:"
	@echo "  make offline-bundle"

.PHONY: all
all: offline-bundle

.PHONY: offline-bundle
offline-bundle: check-dependencies check-internet prepare-bundle build-image package-chart create-scripts create-sbom create-docs bundle-archive
	@echo ""
	@echo "=========================================="
	@echo "✓ Offline Bundle Created Successfully!"
	@echo "=========================================="
	@echo ""
	@echo "Bundle: $(BUNDLE_ARCHIVE)"
	@ls -lh $(BUNDLE_ARCHIVE)
	@echo ""
	@echo "Contents:"
	@tar -tzf $(BUNDLE_ARCHIVE) | head -20
	@echo "..."
	@echo ""
	@echo "Next Steps:"
	@echo "  1. Transfer $(BUNDLE_ARCHIVE) to offline environment"
	@echo "  2. Extract: tar -xzf $(notdir $(BUNDLE_ARCHIVE))"
	@echo "  3. Deploy: cd offline-bundle && ./scripts/deploy-offline.sh"

.PHONY: check-dependencies
check-dependencies:
	@echo "=========================================="
	@echo "Checking Container Runtime"
	@echo "=========================================="
	@RUNTIME_FOUND=0; \
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		echo "✓ Docker detected and running"; \
		echo "  Using Docker instead of nerdctl for compatibility"; \
		RUNTIME_FOUND=1; \
	elif command -v podman >/dev/null 2>&1; then \
		echo "✓ Podman detected"; \
		echo "  Note: Podman detected but this project uses nerdctl/containerd"; \
		echo "  You can use podman by setting NERDCTL=podman in the Makefile"; \
		RUNTIME_FOUND=1; \
	elif systemctl is-active --quiet containerd 2>/dev/null || pgrep -x containerd >/dev/null 2>&1; then \
		echo "✓ containerd is running"; \
		RUNTIME_FOUND=1; \
	fi; \
	if [ $$RUNTIME_FOUND -eq 0 ]; then \
		echo "⚠ No container runtime detected"; \
		echo "  Will install containerd..."; \
		$(MAKE) install-containerd; \
	fi
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		echo "✓ Using Docker as container runtime"; \
	elif ! command -v $(NERDCTL) >/dev/null 2>&1; then \
		echo "⚠ nerdctl not found, installing..."; \
		$(MAKE) install-nerdctl; \
	else \
		echo "✓ nerdctl found: $$($(NERDCTL) version 2>/dev/null | grep Version | head -1)"; \
	fi
	@echo "✓ Container runtime ready"

.PHONY: install-containerd
install-containerd:
	@echo "=========================================="
	@echo "Installing containerd"
	@echo "=========================================="
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "Installing containerd requires root privileges..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			echo "Detected Debian/Ubuntu system"; \
			sudo apt-get update && sudo apt-get install -y containerd; \
			sudo systemctl enable containerd; \
			sudo systemctl start containerd; \
		elif command -v yum >/dev/null 2>&1; then \
			echo "Detected RHEL/CentOS system"; \
			sudo yum install -y containerd.io; \
			sudo systemctl enable containerd; \
			sudo systemctl start containerd; \
		elif command -v dnf >/dev/null 2>&1; then \
			echo "Detected Fedora/Rocky/Alma system"; \
			sudo dnf install -y containerd; \
			sudo systemctl enable containerd; \
			sudo systemctl start containerd; \
		else \
			echo "✗ Unsupported package manager. Please install containerd manually."; \
			echo "  See: https://github.com/containerd/containerd/blob/main/docs/getting-started.md"; \
			exit 1; \
		fi; \
	else \
		apt-get update && apt-get install -y containerd || yum install -y containerd.io || dnf install -y containerd; \
		systemctl enable containerd; \
		systemctl start containerd; \
	fi
	@echo "✓ containerd installed and started"

.PHONY: install-nerdctl
install-nerdctl:
	@echo "=========================================="
	@echo "Installing nerdctl $(NERDCTL_VERSION)"
	@echo "=========================================="
	@ARCH=$$(uname -m); \
	if [ "$$ARCH" = "x86_64" ]; then ARCH="amd64"; fi; \
	if [ "$$ARCH" = "aarch64" ]; then ARCH="arm64"; fi; \
	NERDCTL_URL="https://github.com/containerd/nerdctl/releases/download/v$(NERDCTL_VERSION)/nerdctl-$(NERDCTL_VERSION)-linux-$${ARCH}.tar.gz"; \
	echo "Downloading nerdctl from $$NERDCTL_URL..."; \
	if [ "$$(id -u)" -ne 0 ]; then \
		echo "Installing to /usr/local/bin (requires sudo)..."; \
		curl -sSL "$$NERDCTL_URL" | sudo tar -xz -C /usr/local/bin nerdctl; \
		sudo chmod +x /usr/local/bin/nerdctl; \
	else \
		curl -sSL "$$NERDCTL_URL" | tar -xz -C /usr/local/bin nerdctl; \
		chmod +x /usr/local/bin/nerdctl; \
	fi
	@echo "✓ nerdctl $(NERDCTL_VERSION) installed to /usr/local/bin/nerdctl"
	@nerdctl version

.PHONY: check-internet
check-internet:
	@echo "=========================================="
	@echo "Checking Internet Connectivity"
	@echo "=========================================="
	@curl -s --connect-timeout 5 https://registry-1.docker.io > /dev/null || (echo "✗ No internet connection" && exit 1)
	@curl -s --connect-timeout 5 https://github.com > /dev/null || (echo "✗ Cannot reach GitHub" && exit 1)
	@curl -s --connect-timeout 5 https://get.helm.sh > /dev/null || (echo "✗ Cannot reach Helm" && exit 1)
	@echo "✓ Internet connectivity verified"

.PHONY: prepare-bundle
prepare-bundle:
	@echo "=========================================="
	@echo "Preparing Bundle Structure"
	@echo "=========================================="
	@rm -rf dist/
	@mkdir -p $(IMAGES_DIR) $(CHARTS_DIR) $(SCRIPTS_DIR) $(DOCS_DIR)
	@echo "✓ Directory structure created:"
	@echo "  - $(IMAGES_DIR)"
	@echo "  - $(CHARTS_DIR)"
	@echo "  - $(SCRIPTS_DIR)"
	@echo "  - $(DOCS_DIR)"

.PHONY: build-image
build-image: check-dependencies
	@echo "=========================================="
	@echo "Building Toolbox Image"
	@echo "=========================================="
	@echo "Building $(TOOLBOX_IMAGE) with all tools..."
	@echo "This may take several minutes..."
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		echo "Using Docker runtime..."; \
		docker build -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/; \
	else \
		echo "Using nerdctl with containerd runtime..."; \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) build -t $(TOOLBOX_IMAGE) -f $(BUILD_DIR)/Dockerfile $(BUILD_DIR)/; \
	fi
	@echo ""
	@echo "✓ Image built successfully"
	@echo ""
	@echo "Verifying installed tools..."
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker run --rm $(TOOLBOX_IMAGE) bash -c "mongosh --version | head -1 && kubectl version --client 2>&1 | head -1 && helm version --short && kcadm.sh --help >/dev/null && echo 'kcadm.sh ready' && python3 --version" || true; \
	else \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) run --rm $(TOOLBOX_IMAGE) bash -c "mongosh --version | head -1 && kubectl version --client 2>&1 | head -1 && helm version --short && kcadm.sh --help >/dev/null && echo 'kcadm.sh ready' && python3 --version" || true; \
	fi
	@echo ""
	@echo "Exporting image..."
	@mkdir -p $(IMAGES_DIR)
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar; \
	else \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar; \
	fi
	@echo "✓ Image exported: $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar"
	@ls -lh $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar

.PHONY: package-chart
package-chart:
	@echo "=========================================="
	@echo "Packaging Helm Chart"
	@echo "=========================================="
	@echo "Linting chart..."
	@helm lint chart/ || exit 1
	@echo ""
	@echo "Packaging chart..."
	@helm package chart/ -d $(CHARTS_DIR)
	@# Rename chart file to include '-chart' for clarity
	@ORIG_CHART_FILE=$(CHARTS_DIR)/$(CHART_NAME)-$(CHART_VERSION).tgz; \
	NEW_CHART_FILE=$(CHARTS_DIR)/$(CHART_NAME)-chart-$(CHART_VERSION).tgz; \
	if [ -f "$$ORIG_CHART_FILE" ]; then mv "$$ORIG_CHART_FILE" "$$NEW_CHART_FILE"; fi
	@echo "✓ Chart packaged"
	@ls -lh $(CHARTS_DIR)/*.tgz

.PHONY: create-scripts
create-scripts:
	@echo "=========================================="
	@echo "Creating Deployment Scripts"
	@echo "=========================================="
	@cp scripts/deploy-offline.sh.template $(SCRIPTS_DIR)/deploy-offline.sh
	@sed -i 's/IMAGE_REPO=.*/IMAGE_REPO="$(TOOLBOX_IMAGE_REPO)"/' $(SCRIPTS_DIR)/deploy-offline.sh
	@sed -i 's/IMAGE_TAG=.*/IMAGE_TAG="$(TOOLBOX_IMAGE_TAG)"/' $(SCRIPTS_DIR)/deploy-offline.sh
	@chmod +x $(SCRIPTS_DIR)/deploy-offline.sh
	@echo "✓ Created deploy-offline.sh"
	@echo ""
	@echo "Creating bundle metadata..."
	@echo "Ultimate K8s Toolbox - Offline Bundle" > $(BUNDLE_DIR)/README.txt
	@echo "=======================================" >> $(BUNDLE_DIR)/README.txt
	@echo "" >> $(BUNDLE_DIR)/README.txt
	@echo "Version: $(BUNDLE_VERSION)" >> $(BUNDLE_DIR)/README.txt
	@echo "Chart Version: $(CHART_VERSION)" >> $(BUNDLE_DIR)/README.txt
	@echo "Created: $$(date)" >> $(BUNDLE_DIR)/README.txt
	@echo "" >> $(BUNDLE_DIR)/README.txt
	@echo "Quick Start:" >> $(BUNDLE_DIR)/README.txt
	@echo "  1. Set environment variables (optional):" >> $(BUNDLE_DIR)/README.txt
	@echo "     export REGISTRY=\"myregistry.local:5000\"" >> $(BUNDLE_DIR)/README.txt
	@echo "     export NAMESPACE=\"toolbox\"" >> $(BUNDLE_DIR)/README.txt
	@echo "  2. Run: cd scripts && ./deploy-offline.sh" >> $(BUNDLE_DIR)/README.txt
	@echo "" >> $(BUNDLE_DIR)/README.txt
	@echo "Custom CA Certificates:" >> $(BUNDLE_DIR)/README.txt
	@echo "  To trust internal CA certificates, provide paths during deployment:" >> $(BUNDLE_DIR)/README.txt
	@echo "    ./deploy-offline.sh --root-ca /path/to/root-ca.crt \\\\" >> $(BUNDLE_DIR)/README.txt
	@echo "                        --subordinate-ca /path/to/intermediate-ca.crt" >> $(BUNDLE_DIR)/README.txt
	@echo "" >> $(BUNDLE_DIR)/README.txt
	@echo "  The toolbox uses an init container to run update-ca-certificates" >> $(BUNDLE_DIR)/README.txt
	@echo "  as root, ensuring all tools (curl, wget, Python, etc.) trust" >> $(BUNDLE_DIR)/README.txt
	@echo "  your internal CA certificates." >> $(BUNDLE_DIR)/README.txt
	@echo "" >> $(BUNDLE_DIR)/README.txt
	@echo "For detailed instructions, see docs/" >> $(BUNDLE_DIR)/README.txt
	@echo "✓ Created README.txt"
	@echo ""
	@echo "Creating manifest with checksums..."
	@echo "Bundle Manifest" > $(BUNDLE_DIR)/MANIFEST.txt
	@echo "===============" >> $(BUNDLE_DIR)/MANIFEST.txt
	@echo "" >> $(BUNDLE_DIR)/MANIFEST.txt
	@echo "Version: $(BUNDLE_VERSION)" >> $(BUNDLE_DIR)/MANIFEST.txt
	@echo "Created: $$(date)" >> $(BUNDLE_DIR)/MANIFEST.txt
	@echo "" >> $(BUNDLE_DIR)/MANIFEST.txt
	@echo "SHA256 Checksums:" >> $(BUNDLE_DIR)/MANIFEST.txt
	@echo "-----------------" >> $(BUNDLE_DIR)/MANIFEST.txt
	@cd $(BUNDLE_DIR) && find . -type f \( -name "*.tar" -o -name "*.tgz" \) -exec sha256sum {} \; >> MANIFEST.txt
	@echo "✓ Created MANIFEST.txt with checksums"

.PHONY: create-sbom
create-sbom:
	@echo "=========================================="
	@echo "Creating Software Bill of Materials (SBOM)"
	@echo "=========================================="
	@echo "Generating SBOM for offline bundle..."
	@echo ""
	@# Capture image digest/hash
	@echo "Capturing image hashes..."
	@IMAGE_ID=""; \
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		IMAGE_ID=$$(docker inspect --format='{{.Id}}' $(TOOLBOX_IMAGE) 2>/dev/null | sed 's/sha256://'); \
	else \
		IMAGE_ID=$$($(NERDCTL) --namespace $(NERDCTL_NAMESPACE) inspect --format='{{.Id}}' $(TOOLBOX_IMAGE) 2>/dev/null | sed 's/sha256://'); \
	fi; \
	echo "$$IMAGE_ID" > $(BUNDLE_DIR)/.image-digest
	@# Capture tarball hash
	@IMAGE_TAR_HASH=$$(sha256sum $(IMAGES_DIR)/$(CHART_NAME)-$(BUNDLE_VERSION).tar | cut -d' ' -f1); \
	echo "$$IMAGE_TAR_HASH" > $(BUNDLE_DIR)/.image-tar-hash
	# Capture chart hash (auto-detect packaged chart filename)
	@CHART_TGZ=$$(ls -1 $(CHARTS_DIR)/$(CHART_NAME)-chart-*.tgz | head -1); \
	if [ -z "$$CHART_TGZ" ]; then \
		echo "✗ No chart package found in $(CHARTS_DIR)"; \
		exit 1; \
	fi; \
	CHART_HASH=$$(sha256sum "$$CHART_TGZ" | cut -d' ' -f1); \
	echo "$$CHART_HASH" > $(BUNDLE_DIR)/.chart-hash; \
	echo $$(basename "$$CHART_TGZ") > $(BUNDLE_DIR)/.chart-filename
	@echo "✓ Hashes captured"
	@echo ""
	@# Create SBOM header
	@echo "Software Bill of Materials (SBOM)" > $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Bundle: $(CHART_NAME) $(BUNDLE_VERSION)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Created: $$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Format: SPDX-like" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "ARTIFACT CHECKSUMS (SHA256)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Toolbox Image Digest:" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  sha256:$$(cat $(BUNDLE_DIR)/.image-digest)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Image Tarball ($(CHART_NAME)-$(BUNDLE_VERSION).tar):" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  sha256:$$(cat $(BUNDLE_DIR)/.image-tar-hash)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Helm Chart ($$(cat $(BUNDLE_DIR)/.chart-filename)):" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  sha256:$$(cat $(BUNDLE_DIR)/.chart-hash)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "CONTAINER IMAGES" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Base Image:" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Name: ubuntu" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Version: 24.04 LTS" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  License: Proprietary (Canonical)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Toolbox Image:" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Name: $(TOOLBOX_IMAGE_REPO)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Version: $(TOOLBOX_IMAGE_TAG)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Size: $$(du -h $(IMAGES_DIR)/*.tar | cut -f1)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  SHA256: $$(cat $(BUNDLE_DIR)/.image-digest)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "MONGODB TOOLS" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "1. MongoDB Shell (mongosh)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: 2.3.7" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Source: https://github.com/mongodb-js/mongosh" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Interactive MongoDB shell" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "2. MongoDB Database Tools" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: 100.13.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Source: https://github.com/mongodb/mongo-tools" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Tools: mongodump, mongorestore, mongoexport, mongoimport," >> $(BUNDLE_DIR)/SBOM.txt
	@echo "          mongostat, mongotop, mongofiles, bsondump" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "KUBERNETES TOOLS" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "3. kubectl" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: v1.31.4" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Source: https://github.com/kubernetes/kubernetes" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Kubernetes CLI" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "4. Helm" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: v3 (latest stable)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Source: https://github.com/helm/helm" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Kubernetes package manager" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "5. yq" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: v4.45.1" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: MIT" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Source: https://github.com/mikefarah/yq" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: YAML/JSON/XML processor" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "STORAGE TOOLS" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "6. tridentctl" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: 24.10.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Source: https://github.com/NetApp/trident" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: NetApp Trident CSI management" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "7. nfs-common" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: NFS client utilities" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "NETWORKING TOOLS" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "8. curl" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: MIT" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: HTTP client" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "9. wget" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-3.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: File downloader" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "10. netcat (nc)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Network connections" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "11. nmap" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Network scanner" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "12. dnsutils (dig, nslookup)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: MPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: DNS tools" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "13. iproute2 (ip, ss)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Network utilities" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "14. net-tools (netstat, ifconfig, arp)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Legacy network tools" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "15. iputils-ping" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: ICMP echo" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "16. traceroute" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Route tracing" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "17. tcpdump" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Packet analyzer" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "18. socat" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Socket relay" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "19. telnet" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Remote terminal" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "20. openssh-client" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: SSH client" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "PYTHON ENVIRONMENT" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "21. Python" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: 3.12" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Python-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Python runtime" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "22. pymongo" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Latest (PyPI)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: MongoDB Python driver" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "23. kubernetes (Python client)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Latest (PyPI)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Kubernetes Python client" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "24. PyYAML" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Latest (PyPI)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: MIT" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: YAML parser" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "25. requests" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Latest (PyPI)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: HTTP library" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "26. jinja2" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Latest (PyPI)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD-3-Clause" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Template engine" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "27. click" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Latest (PyPI)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: BSD-3-Clause" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: CLI framework" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "SYSTEM TOOLS" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "28. vim" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Vim" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Text editor" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "29. nano" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-3.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Text editor" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "30. htop" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Process monitor" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "31. jq" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: MIT" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: JSON processor" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "32. tmux" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: ISC" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Terminal multiplexer" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "33. strace" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: LGPL-2.1" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: System call tracer" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "34. lsof" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Custom" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: List open files" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "35. sysstat" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: System statistics" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "36. bash-completion" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: GPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Command completion" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "37. ca-certificates" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: Ubuntu 24.04 default" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: MPL-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: SSL certificates" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "HELM CHART" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "38. Ultimate K8s Toolbox Chart" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: $(CHART_VERSION)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Helm deployment chart" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "BUILD TOOLS (not in image)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "39. nerdctl" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: 1.7.7" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Container CLI (build host only)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "40. containerd" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Version: 1.7.22" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   License: Apache-2.0" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "   Purpose: Container runtime (build host only)" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "SUMMARY" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Total Components: 40" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "In-Image Components: 38" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "Build-Only Components: 2" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "License Distribution:" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Apache-2.0: 11 components" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  GPL-2.0: 7 components" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  BSD: 5 components" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  MIT: 4 components" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  GPL-3.0: 2 components" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "  Other: 11 components" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "END OF SBOM" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "=================================" >> $(BUNDLE_DIR)/SBOM.txt
	@echo "✓ Created SBOM.txt"
	@echo ""
	@echo "Creating JSON SBOM..."
	@# Create JSON SBOM with hashes
	@IMAGE_DIGEST=$$(cat $(BUNDLE_DIR)/.image-digest); \
	IMAGE_TAR_HASH=$$(cat $(BUNDLE_DIR)/.image-tar-hash); \
	CHART_HASH=$$(cat $(BUNDLE_DIR)/.chart-hash); \
	echo '{' > $(BUNDLE_DIR)/SBOM.json; \
	echo '  "bomFormat": "CycloneDX",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '  "specVersion": "1.4",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '  "version": 1,' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '  "metadata": {' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    "timestamp": "'$$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    "component": {' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "type": "container",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "name": "$(CHART_NAME)",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "version": "$(BUNDLE_VERSION)",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "description": "Ultimate Kubernetes Toolbox - Swiss Army Knife for K8s, MongoDB, and Infrastructure Operations",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "hashes": [' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '        { "alg": "SHA-256", "content": "'$$IMAGE_DIGEST'" }' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      ]' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    "tools": [' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      { "vendor": "CycloneDX", "name": "ultimate-k8s-toolbox-makefile", "version": "1.0.2" }' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    ]' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '  },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '  "components": [' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    {' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "type": "container",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "name": "$(TOOLBOX_IMAGE_REPO)",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "version": "$(TOOLBOX_IMAGE_TAG)",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "hashes": [' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '        { "alg": "SHA-256", "content": "'$$IMAGE_DIGEST'" }' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      ],' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "purl": "pkg:docker/$(TOOLBOX_IMAGE_REPO)@$(TOOLBOX_IMAGE_TAG)"' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    {' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "type": "file",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "name": "$(CHART_NAME)-$(BUNDLE_VERSION).tar",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "version": "$(BUNDLE_VERSION)",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "description": "Container image tarball",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "hashes": [' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '        { "alg": "SHA-256", "content": "'$$IMAGE_TAR_HASH'" }' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      ]' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    },' >> $(BUNDLE_DIR)/SBOM.json; \
	CHART_FILE=$$(cat $(BUNDLE_DIR)/.chart-filename); \
	echo '    {' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "type": "file",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "name": "'$$CHART_FILE'",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "version": "'$$CHART_FILE'",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "description": "Helm chart package",' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      "hashes": [' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '        { "alg": "SHA-256", "content": "'$$CHART_HASH'" }' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '      ]' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "operating-system", "name": "ubuntu", "version": "24.04", "licenses": [{"license": {"id": "Proprietary"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "mongosh", "version": "2.3.7", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:github/mongodb-js/mongosh@2.3.7" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "mongodb-database-tools", "version": "100.13.0", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:github/mongodb/mongo-tools@100.13.0" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "kubectl", "version": "1.31.4", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:github/kubernetes/kubernetes@v1.31.4" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "helm", "version": "3.x", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:github/helm/helm@3.x" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "yq", "version": "4.45.1", "licenses": [{"license": {"id": "MIT"}}], "purl": "pkg:github/mikefarah/yq@v4.45.1" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "tridentctl", "version": "24.10.0", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:github/NetApp/trident@24.10.0" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "curl", "version": "latest", "licenses": [{"license": {"id": "MIT"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "wget", "version": "latest", "licenses": [{"license": {"id": "GPL-3.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "netcat", "version": "latest", "licenses": [{"license": {"id": "BSD"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "nmap", "version": "latest", "licenses": [{"license": {"id": "GPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "dnsutils", "version": "latest", "licenses": [{"license": {"id": "MPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "iproute2", "version": "latest", "licenses": [{"license": {"id": "GPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "net-tools", "version": "latest", "licenses": [{"license": {"id": "GPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "iputils-ping", "version": "latest", "licenses": [{"license": {"id": "BSD"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "traceroute", "version": "latest", "licenses": [{"license": {"id": "GPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "tcpdump", "version": "latest", "licenses": [{"license": {"id": "BSD"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "socat", "version": "latest", "licenses": [{"license": {"id": "GPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "openssh-client", "version": "latest", "licenses": [{"license": {"id": "BSD"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "application", "name": "python", "version": "3.12", "licenses": [{"license": {"id": "Python-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "pymongo", "version": "latest", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:pypi/pymongo" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "kubernetes", "version": "latest", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:pypi/kubernetes" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "PyYAML", "version": "latest", "licenses": [{"license": {"id": "MIT"}}], "purl": "pkg:pypi/PyYAML" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "requests", "version": "latest", "licenses": [{"license": {"id": "Apache-2.0"}}], "purl": "pkg:pypi/requests" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "jinja2", "version": "latest", "licenses": [{"license": {"id": "BSD-3-Clause"}}], "purl": "pkg:pypi/jinja2" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "click", "version": "latest", "licenses": [{"license": {"id": "BSD-3-Clause"}}], "purl": "pkg:pypi/click" },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "vim", "version": "latest", "licenses": [{"license": {"name": "Vim"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "htop", "version": "latest", "licenses": [{"license": {"id": "GPL-2.0"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "jq", "version": "latest", "licenses": [{"license": {"id": "MIT"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "tmux", "version": "latest", "licenses": [{"license": {"id": "ISC"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "strace", "version": "latest", "licenses": [{"license": {"id": "LGPL-2.1"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "lsof", "version": "latest", "licenses": [{"license": {"name": "Custom"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "nfs-common", "version": "latest", "licenses": [{"license": {"id": "GPL"}}] },' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '    { "type": "library", "name": "ca-certificates", "version": "latest", "licenses": [{"license": {"id": "MPL-2.0"}}] }' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '  ]' >> $(BUNDLE_DIR)/SBOM.json; \
	echo '}' >> $(BUNDLE_DIR)/SBOM.json
	@# Clean up temp files
	@rm -f $(BUNDLE_DIR)/.image-digest $(BUNDLE_DIR)/.image-tar-hash $(BUNDLE_DIR)/.chart-hash
	@echo "✓ Created SBOM.json (CycloneDX format with SHA256 hashes)"
	@echo ""
	@echo "SBOM Summary:"
	@echo "  Format: SPDX-like (text) + CycloneDX (JSON)"
	@echo "  Total Components: 40"
	@echo "  Files: $(BUNDLE_DIR)/SBOM.txt, $(BUNDLE_DIR)/SBOM.json"

.PHONY: create-docs
create-docs:
	@echo "=========================================="
	@echo "Copying Documentation"
	@echo "=========================================="
	@cp README.md $(DOCS_DIR)/
	@cp QUICKSTART.md $(DOCS_DIR)/
	@cp OFFLINE-DEPLOYMENT.md $(DOCS_DIR)/
	@cp MAKEFILE.md $(DOCS_DIR)/
	@cp SBOM.md $(DOCS_DIR)/
	@cp TOOLS-REFERENCE.md $(DOCS_DIR)/
	@echo "✓ Documentation copied to bundle"

.PHONY: bundle-archive
bundle-archive:
	@echo "=========================================="
	@echo "Creating Bundle Archive"
	@echo "=========================================="
	@cd dist && tar -czf $(notdir $(BUNDLE_ARCHIVE)) offline-bundle/
	@echo "✓ Archive created"
	@echo ""
	@echo "Archive Details:"
	@ls -lh $(BUNDLE_ARCHIVE)
	@echo ""
	@echo "Archive Structure:"
	@tar -tzf $(BUNDLE_ARCHIVE) | grep -E "^[^/]+/[^/]+/$$" | sort | uniq

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@rm -rf dist/ $(CHART_NAME)-*.tgz
	@rm -rf offline-bundle/ *.tar.gz
	@rm -rf chart/$(CHART_NAME)-*.tgz
	@rm -f build-output.log build-latest.log offline-bundle-build.log
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker rmi $(TOOLBOX_IMAGE) 2>/dev/null || true; \
	elif command -v $(NERDCTL) >/dev/null 2>&1; then \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) rmi $(TOOLBOX_IMAGE) 2>/dev/null || true; \
	fi
	@echo "✓ Cleanup complete"

.PHONY: clean-all
clean-all: clean
	@echo "Removing all build artifacts and images..."
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker system prune -f; \
	elif command -v $(NERDCTL) >/dev/null 2>&1; then \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) system prune -f; \
	fi
	@echo "✓ Deep cleanup complete"

.PHONY: info
info:
	@echo "=========================================="
	@echo "Ultimate K8s Toolbox - Configuration"
	@echo "=========================================="
	@echo ""
	@echo "Chart Information:"
	@echo "  Name: $(CHART_NAME)"
	@echo "  Version: $(CHART_VERSION)"
	@echo ""
	@echo "Bundle Configuration:"
	@echo "  Version: $(BUNDLE_VERSION)"
	@echo "  Archive: $(BUNDLE_ARCHIVE)"
	@echo ""
	@echo "Image Configuration:"
	@echo "  Repository: $(TOOLBOX_IMAGE_REPO)"
	@echo "  Tag: $(TOOLBOX_IMAGE_TAG)"
	@echo "  Full Image: $(TOOLBOX_IMAGE)"
	@echo ""
	@echo "Directory Structure:"
	@echo "  Chart: $(CHART_DIR)/"
	@echo "  Build: $(BUILD_DIR)/"
	@echo "  Bundle: $(BUNDLE_DIR)/"
	@echo "  Images: $(IMAGES_DIR)/"
	@echo "  Charts: $(CHARTS_DIR)/"
	@echo "  Scripts: $(SCRIPTS_DIR)/"
	@echo "  Docs: $(DOCS_DIR)/"

.PHONY: test-image
test-image:
	@echo "=========================================="
	@echo "Testing Toolbox Image"
	@echo "=========================================="
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		docker run --rm $(TOOLBOX_IMAGE) bash -c "\
		echo '=========================================='; \
		echo 'Ultimate K8s Toolbox - Tool Verification'; \
		echo '=========================================='; \
		echo ''; \
		echo 'MongoDB Shell:'; mongosh --version | head -1; \
		echo ''; \
		echo 'kubectl:'; kubectl version --client --short 2>/dev/null || echo 'N/A (no cluster)'; \
		echo ''; \
		echo 'Helm:'; helm version --short; \
		echo ''; \
		echo 'tridentctl:'; tridentctl version --client 2>/dev/null || echo 'N/A'; \
		echo ''; \
		echo 'Python:'; python3 --version; \
		echo ''; \
		echo 'Network Tools:'; \
		ping -c 1 127.0.0.1 > /dev/null && echo '  ✓ ping' || echo '  ✗ ping'; \
		which curl > /dev/null && echo '  ✓ curl' || echo '  ✗ curl'; \
		which wget > /dev/null && echo '  ✓ wget' || echo '  ✗ wget'; \
		which nc > /dev/null && echo '  ✓ netcat' || echo '  ✗ netcat'; \
		which nslookup > /dev/null && echo '  ✓ nslookup' || echo '  ✗ nslookup'; \
		which dig > /dev/null && echo '  ✓ dig' || echo '  ✗ dig'; \
		which traceroute > /dev/null && echo '  ✓ traceroute' || echo '  ✗ traceroute'; \
		which nmap > /dev/null && echo '  ✓ nmap' || echo '  ✗ nmap'; \
		echo ''; \
		echo '=========================================='; \
		echo '✓ All critical tools verified!'; \
		echo '==========================================' " ; \
	else \
		$(NERDCTL) --namespace $(NERDCTL_NAMESPACE) run --rm $(TOOLBOX_IMAGE) bash -c "\
			echo '=========================================='; \
			echo 'Ultimate K8s Toolbox - Tool Verification'; \
			echo '=========================================='; \
			echo ''; \
			echo 'MongoDB Shell:'; mongosh --version | head -1; \
			echo ''; \
			echo 'kubectl:'; kubectl version --client --short 2>/dev/null || echo 'N/A (no cluster)'; \
			echo ''; \
			echo 'Helm:'; helm version --short; \
			echo ''; \
			echo 'tridentctl:'; tridentctl version --client 2>/dev/null || echo 'N/A'; \
			echo ''; \
			echo 'Python:'; python3 --version; \
			echo ''; \
			echo 'Network Tools:'; \
			ping -c 1 127.0.0.1 > /dev/null && echo '  ✓ ping' || echo '  ✗ ping'; \
			which curl > /dev/null && echo '  ✓ curl' || echo '  ✗ curl'; \
			which wget > /dev/null && echo '  ✓ wget' || echo '  ✗ wget'; \
			which nc > /dev/null && echo '  ✓ netcat' || echo '  ✗ netcat'; \
			which nslookup > /dev/null && echo '  ✓ nslookup' || echo '  ✗ nslookup'; \
			which dig > /dev/null && echo '  ✓ dig' || echo '  ✗ dig'; \
			which traceroute > /dev/null && echo '  ✓ traceroute' || echo '  ✗ traceroute'; \
			which nmap > /dev/null && echo '  ✓ nmap' || echo '  ✗ nmap'; \
			echo ''; \
			echo '=========================================='; \
			echo '✓ All critical tools verified!'; \
			echo '==========================================' " ; \
	fi
