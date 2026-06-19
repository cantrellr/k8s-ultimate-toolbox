# syntax=docker/dockerfile:1.4
FROM ubuntu:24.04

# Metadata
LABEL maintainer="Platform Team"
LABEL description="Swiss-army knife for Kubernetes, MongoDB, Ops Manager, networking, storage, and cluster inspection - True Admin Workstation"
LABEL version="1.0.2"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/bin:${PATH}"

# ============================================================================
# SECTION 1: Base System + Core Utilities
# ============================================================================
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    # Text editors
    vim \
    nano \
    # Version control
    git \
    # System monitoring and debugging
    htop \
    less \
    psmisc \
    strace \
    procps \
    lsof \
    iotop \
    file \
    # Shell enhancements
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# SECTION 2: X.509 / TLS / Certificate Tools
# ============================================================================
RUN apt-get update && apt-get install -y \
    openssl \
    gnutls-bin \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# SECTION 3: Networking Tools (Complete Debug Stack)
# ============================================================================
RUN apt-get update && apt-get install -y \
    dnsutils \
    iputils-ping \
    iproute2 \
    netcat-openbsd \
    tcpdump \
    traceroute \
    net-tools \
    telnet \
    nmap \
    iperf3 \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# SECTION 4: Storage + File Transfer Tools
# ============================================================================
RUN apt-get update && apt-get install -y \
    nfs-common \
    zip \
    unzip \
    tar \
    gzip \
    rsync \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# SECTION 5: MongoDB Client Stack (Complete Suite)
# ============================================================================

# Install MongoDB Shell (mongosh)
RUN MONGOSH_VERSION="2.3.7" && \
    ARCH=$(dpkg --print-architecture) && \
    wget -q https://downloads.mongodb.com/compass/mongodb-mongosh_${MONGOSH_VERSION}_${ARCH}.deb && \
    dpkg -i mongodb-mongosh_${MONGOSH_VERSION}_${ARCH}.deb || apt-get install -f -y && \
    rm mongodb-mongosh_${MONGOSH_VERSION}_${ARCH}.deb

# Install MongoDB Database Tools (mongodump, mongorestore, bsondump, mongostat, etc.)
RUN MONGO_TOOLS_VERSION="100.13.0" && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        MONGO_ARCH="x86_64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        MONGO_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    TOOLS_TGZ="mongodb-database-tools-ubuntu2404-${MONGO_ARCH}-${MONGO_TOOLS_VERSION}.tgz" && \
    wget -q "https://fastdl.mongodb.org/tools/db/${TOOLS_TGZ}" && \
    mkdir -p /tmp/mongo-tools && \
    tar -xzf "${TOOLS_TGZ}" -C /tmp/mongo-tools && \
    cp -f /tmp/mongo-tools/mongodb-database-tools-ubuntu2404-${MONGO_ARCH}-${MONGO_TOOLS_VERSION}/bin/* /usr/local/bin/ && \
    chmod +x /usr/local/bin/mongo* /usr/local/bin/bsondump /usr/local/bin/mongostat /usr/local/bin/mongotop || true && \
    rm -rf /tmp/mongo-tools "${TOOLS_TGZ}"

# Verify MongoDB tools installation
RUN mongosh --version && \
    mongodump --version && \
    mongorestore --version && \
    echo "MongoDB client stack installed successfully"

# ============================================================================
# SECTION 6: Kubernetes Admin Tooling
# ============================================================================

# Install kubectl
RUN KUBECTL_VERSION="v1.31.4" && \
    ARCH=$(dpkg --print-architecture) && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install jq (JSON processor) - already in base but ensuring it's here
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor)
RUN YQ_VERSION="v4.45.1" && \
    ARCH=$(dpkg --print-architecture) && \
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH} && \
    chmod +x /usr/local/bin/yq

# Install envsubst (part of gettext-base)
RUN apt-get update && apt-get install -y gettext-base && rm -rf /var/lib/apt/lists/*

# ============================================================================
# SECTION 7: Identity & Access Management Tools (Keycloak CLI)
# ============================================================================

# Install Java runtime required by Keycloak CLI scripts
RUN apt-get update && apt-get install -y openjdk-21-jre-headless && rm -rf /var/lib/apt/lists/*

# Install Keycloak admin and registration CLIs
RUN KEYCLOAK_VERSION="26.1.4" && \
    wget -q "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz" && \
    tar -xzf "keycloak-${KEYCLOAK_VERSION}.tar.gz" -C /opt && \
    mv "/opt/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak && \
    ln -sf /opt/keycloak/bin/kcadm.sh /usr/local/bin/kcadm.sh && \
    ln -sf /opt/keycloak/bin/kcreg.sh /usr/local/bin/kcreg.sh && \
    ln -sf /opt/keycloak/bin/kc.sh /usr/local/bin/kc.sh && \
    chmod +x /opt/keycloak/bin/*.sh && \
    rm -f "keycloak-${KEYCLOAK_VERSION}.tar.gz"

# Verify Keycloak CLI installation
RUN kcadm.sh --help >/dev/null && \
    kcreg.sh --help >/dev/null && \
    kc.sh --help >/dev/null && \
    java -version && \
    echo "Keycloak CLI tools installed successfully"

# ============================================================================
# SECTION 8: Storage Tools (Trident + NFS)
# ============================================================================

# Install tridentctl (NetApp Trident CLI)
RUN TRIDENT_VERSION="24.10.0" && \
    wget https://github.com/NetApp/trident/releases/download/v${TRIDENT_VERSION}/trident-installer-${TRIDENT_VERSION}.tar.gz && \
    tar -xzf trident-installer-${TRIDENT_VERSION}.tar.gz && \
    cp trident-installer/tridentctl /usr/local/bin/ && \
    chmod +x /usr/local/bin/tridentctl && \
    rm -rf trident-installer-${TRIDENT_VERSION}.tar.gz trident-installer

# ============================================================================
# SECTION 9: Python Environment (Scripting + Automation)
# ============================================================================

# Install Python
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install essential Python packages
RUN pip3 install --no-cache-dir --break-system-packages \
    pymongo \
    kubernetes \
    pyyaml \
    requests \
    jinja2 \
    click

# Verify Python installation
RUN python3 --version && pip3 --version

# ============================================================================
# SECTION 10: CA Trust Integration (Enterprise Best Practice)
# ============================================================================
# Industry best practice for CA trust integration:
# 1. Mount certificates as Kubernetes Secret/ConfigMap volume
# 2. Copy to /usr/local/share/ca-certificates/ on container startup
# 3. Run update-ca-certificates to update system trust store
# 4. All tools (curl, wget, openssl, Python, mongosh) will trust custom CAs

# Create directory for custom CA certificates
RUN mkdir -p /usr/local/share/ca-certificates/custom

# Add comprehensive CA trust update script
# This script handles multiple certificate sources and formats
RUN cat > /usr/local/bin/update-ca-trust.sh <<'CATRUSTSCRIPT'
#!/bin/bash
# =============================================================================
# CA Trust Update Script for Ultimate K8s Toolbox
# =============================================================================
# This script updates the system CA trust store with custom certificates.
# It supports multiple certificate sources and is designed to be idempotent.
#
# Sources checked (in order):
#   1. /etc/ssl/custom-ca/ - Primary mount point for Kubernetes secrets
#   2. /tls/ca.crt - Legacy single certificate mount
#   3. CA_CERT_DIR environment variable - Custom directory
#
# Usage:
#   update-ca-trust.sh              # Auto-detect and install CAs
#   update-ca-trust.sh --verify     # Verify CA installation
#   update-ca-trust.sh --list       # List installed custom CAs
# =============================================================================

# Configuration
CA_TARGET_DIR="/usr/local/share/ca-certificates/custom"
PRIMARY_CA_SOURCE="${CA_CERT_DIR:-/etc/ssl/custom-ca}"
LEGACY_CA_PATH="/tls/ca.crt"
VERBOSE=${VERBOSE:-false}

log_info() {
    echo "[CA-TRUST] $1"
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo "[CA-TRUST] DEBUG: $1"
    fi
}

# Install certificates from a directory
install_certs_from_dir() {
    local source_dir="$1"
    local installed=0
    
    if [ ! -d "$source_dir" ]; then
        log_debug "Directory not found: $source_dir"
        return 0
    fi
    
    # Process all .crt and .pem files
    for cert in "$source_dir"/*.crt "$source_dir"/*.pem; do
        if [ -f "$cert" ]; then
            local cert_name
            cert_name=$(basename "$cert")
            
            # Validate its a valid certificate
            if openssl x509 -in "$cert" -noout 2>/dev/null; then
                # Copy with .crt extension (required by update-ca-certificates)
                local target_name="${cert_name%.*}.crt"
                cp "$cert" "$CA_TARGET_DIR/$target_name"
                log_info "Installed: $cert_name"
                ((installed++))
            else
                log_debug "Skipping invalid certificate: $cert_name"
            fi
        fi
    done
    
    return $installed
}

# Install single certificate file
install_single_cert() {
    local cert_path="$1"
    local cert_name="$2"
    
    if [ ! -f "$cert_path" ]; then
        log_debug "Certificate not found: $cert_path"
        return 1
    fi
    
    if openssl x509 -in "$cert_path" -noout 2>/dev/null; then
        cp "$cert_path" "$CA_TARGET_DIR/${cert_name}.crt"
        log_info "Installed: $cert_name from $cert_path"
        return 0
    else
        log_debug "Invalid certificate: $cert_path"
        return 1
    fi
}

# Verify CA installation
verify_installation() {
    echo "Custom CA Certificates:"
    echo "========================"
    
    local count=0
    for cert in "$CA_TARGET_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            local subject
            subject=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null | sed 's/subject=//')
            echo "  $(basename "$cert"): $subject"
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo "  (none installed)"
    fi
    
    echo ""
    echo "System trust store: /etc/ssl/certs/ca-certificates.crt"
    echo "Custom CAs trusted: $count"
}

# List installed certificates
list_certificates() {
    echo "Installed Custom CA Certificates:"
    echo "=================================="
    
    for cert in "$CA_TARGET_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            echo ""
            echo "File: $(basename "$cert")"
            openssl x509 -in "$cert" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'
        fi
    done
}

# Main function
main() {
    case "${1:-}" in
        --verify)
            verify_installation
            exit 0
            ;;
        --list)
            list_certificates
            exit 0
            ;;
        --help)
            head -20 "$0" | tail -15 | sed 's/^# //'
            exit 0
            ;;
    esac
    
    log_info "Updating CA trust store..."
    
    # Ensure target directory exists
    mkdir -p "$CA_TARGET_DIR"
    
    local certs_installed=0
    
    # Source 1: Primary mount directory (Kubernetes secret/configmap)
    if [ -d "$PRIMARY_CA_SOURCE" ]; then
        log_debug "Checking primary source: $PRIMARY_CA_SOURCE"
        install_certs_from_dir "$PRIMARY_CA_SOURCE" || true
        certs_installed=$((certs_installed + $?))
    fi
    
    # Source 2: Legacy single certificate path
    if [ -f "$LEGACY_CA_PATH" ]; then
        log_debug "Checking legacy path: $LEGACY_CA_PATH"
        if install_single_cert "$LEGACY_CA_PATH" "legacy-ca"; then
            ((certs_installed++))
        fi
    fi
    
    # Source 3: Environment variable custom directory
    if [ -n "${CA_CERT_DIR:-}" ] && [ "$CA_CERT_DIR" != "$PRIMARY_CA_SOURCE" ]; then
        log_debug "Checking custom directory: $CA_CERT_DIR"
        install_certs_from_dir "$CA_CERT_DIR" || true
    fi
    
    # Update system trust store if any certificates were installed
    if [ "$(ls -A "$CA_TARGET_DIR" 2>/dev/null)" ]; then
        log_info "Running update-ca-certificates..."
        update-ca-certificates --fresh > /dev/null 2>&1 || update-ca-certificates > /dev/null 2>&1
        log_info "CA trust store updated successfully"
        
        # Show summary
        local count
        count=$(find "$CA_TARGET_DIR" -name "*.crt" -type f 2>/dev/null | wc -l)
        log_info "Total custom CAs installed: $count"
    else
        log_info "No custom CA certificates found"
    fi
}

main "$@"
CATRUSTSCRIPT
RUN chmod +x /usr/local/bin/update-ca-trust.sh

# ============================================================================
# SECTION 11: User Setup + Workspace Configuration
# ============================================================================

# Create a non-root user (use uid 10000 to avoid conflicts)
RUN useradd -m -s /bin/bash -u 10000 toolbox && \
    mkdir -p /home/toolbox/.kube /home/toolbox/scripts && \
    chown -R toolbox:toolbox /home/toolbox

# Set up workspace
WORKDIR /workspace
RUN chown toolbox:toolbox /workspace

# Create comprehensive tool verification script
RUN echo '#!/bin/bash' > /usr/local/bin/show-versions.sh && \
    echo 'echo "=============================================="' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  🚀 Ultimate K8s Admin Workstation 🚀"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  Swiss-army knife for K8s & MongoDB Ops"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "=============================================="' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "📦 MONGODB CLIENT STACK:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • mongosh: $(mongosh --version | head -1 | awk \"{print \\$2}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • mongodump: $(mongodump --version | grep version | awk \"{print \\$3}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • mongorestore: $(mongorestore --version | grep version | awk \"{print \\$3}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "☸️  KUBERNETES ADMIN TOOLS:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • kubectl: $(kubectl version --client --short 2>/dev/null | grep Client | awk \"{print \\$3}\" || echo \"ready\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • helm: $(helm version --short | cut -d+ -f1)"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • jq: $(jq --version)"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • yq: $(yq --version | awk \"{print \\$3}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "🔐 KEYCLOAK CLI TOOLS:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • kcadm.sh: $(kcadm.sh --help >/dev/null 2>&1 && echo ready || echo missing)"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • kcreg.sh: $(kcreg.sh --help >/dev/null 2>&1 && echo ready || echo missing)"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • kc.sh: $(kc.sh --help >/dev/null 2>&1 && echo ready || echo missing)"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • Java: $(java -version 2>&1 | head -1)"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "🔒 TLS / X.509 TOOLS:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • openssl: $(openssl version | awk \"{print \\$2}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • gnutls: $(certtool --version | head -1 | awk \"{print \\$2}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "🌐 NETWORKING TOOLS:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • dig, nslookup, ping, traceroute"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • tcpdump, netcat, nmap, curl, wget"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "💾 STORAGE TOOLS:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • tridentctl: $(tridentctl version --client 2>/dev/null | grep Version | awk \"{print \\$2}\" || echo \"ready\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • nfs-common, rsync, git"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "🐍 PYTHON ENVIRONMENT:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • Python: $(python3 --version | awk \"{print \\$2}\")"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • Packages: pymongo, kubernetes, pyyaml, requests"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "🛠️  SYSTEM TOOLS:"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • vim, nano, htop, less, strace, lsof"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  • bash-completion enabled"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "=============================================="' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "  Ready for cluster ops! 🎯"' >> /usr/local/bin/show-versions.sh && \
    echo 'echo "=============================================="' >> /usr/local/bin/show-versions.sh && \
    echo 'echo ""' >> /usr/local/bin/show-versions.sh && \
    chmod +x /usr/local/bin/show-versions.sh

# Switch to non-root user
USER toolbox

# Set default command
CMD ["/bin/bash", "-c", "show-versions.sh && tail -f /dev/null"]
