# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG TOOLBOX_VERSION="1.2.0"
ARG MONGOSH_VERSION="2.8.3"
ARG MONGO_TOOLS_VERSION="100.17.0"
ARG KUBECTL_VERSION="v1.36.1"
ARG HELM_VERSION="v4.2.1"
ARG YQ_VERSION="v4.53.3"
ARG KEYCLOAK_VERSION="26.6.3"
ARG TRIDENT_VERSION="26.02.0"
ARG CRICTL_VERSION="v1.36.0"
ARG ETCD_VERSION="v3.6.12"
ARG CMCTL_VERSION="v2.2.0"
ARG STEP_VERSION="v0.30.2"
ARG KUBENT_VERSION="0.7.3"
ARG KUBECONFORM_VERSION="v0.8.0"
ARG POPEYE_VERSION="v0.22.1"
ARG KUBECTL_WHO_CAN_VERSION="v0.4.0"
ARG RBAC_LOOKUP_VERSION="v0.10.3"
ARG CILIUM_CLI_VERSION="v0.19.2"
ARG HUBBLE_VERSION="v1.18.6"
ARG CALICOCTL_VERSION="v3.32.0"

LABEL maintainer="Platform Team"
LABEL description="Kubernetes administration workstation for cluster, identity, database, networking, storage, policy, RBAC, CNI, and air-gapped diagnostics"
LABEL version="${TOOLBOX_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/bin:/opt/keycloak/bin:${PATH}" \
    KC_HOME="/opt/keycloak" \
    PAGER="less"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    bash-completion \
    ca-certificates \
    curl \
    default-mysql-client \
    dnsutils \
    file \
    gettext-base \
    git \
    gnupg \
    gnutls-bin \
    gzip \
    htop \
    iperf3 \
    iproute2 \
    iputils-ping \
    iotop \
    jq \
    less \
    libpq-dev \
    lsb-release \
    lsof \
    mtr-tiny \
    nano \
    net-tools \
    netcat-openbsd \
    nfs-common \
    nmap \
    openjdk-21-jre-headless \
    openssh-client \
    openssl \
    pgbadger \
    pgbouncer \
    postgresql-client \
    postgresql-client-common \
    postgresql-contrib \
    procps \
    psmisc \
    python3 \
    python3-pip \
    python3-venv \
    redis-tools \
    rsync \
    socat \
    software-properties-common \
    strace \
    tar \
    tcpdump \
    telnet \
    traceroute \
    unzip \
    vim \
    wget \
    whois \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN cat > /usr/local/bin/install-github-release-tool <<'GHTOOL'
#!/bin/bash
set -euo pipefail
if [[ $# -lt 4 ]]; then
  echo "Usage: install-github-release-tool <owner/repo> <tag> <asset-regex> <binary> [binary...]" >&2
  exit 1
fi
repo="$1"
tag="$2"
asset_regex="$3"
shift 3
binaries=("$@")
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
asset_url="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}" | jq -r --arg re "$asset_regex" '.assets[] | select(.name | test($re)) | .browser_download_url' | head -1)"
if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
  echo "No release asset matched ${asset_regex} for ${repo}@${tag}" >&2
  exit 1
fi
echo "Installing ${repo}@${tag} from $(basename "$asset_url")"
archive="${tmpdir}/asset"
curl -fL "$asset_url" -o "$archive"
mkdir -p "${tmpdir}/extract"
case "$asset_url" in
  *.tar.gz|*.tgz) tar -xzf "$archive" -C "${tmpdir}/extract" ;;
  *.zip) unzip -q "$archive" -d "${tmpdir}/extract" ;;
  *) mkdir -p "${tmpdir}/extract/raw"; cp "$archive" "${tmpdir}/extract/raw/${binaries[0]}" ;;
esac
for binary in "${binaries[@]}"; do
  found="$(find "${tmpdir}/extract" -type f -name "$binary" | head -1)"
  if [[ -z "$found" ]]; then
    echo "Binary ${binary} not found in ${repo}@${tag}" >&2
    find "${tmpdir}/extract" -maxdepth 4 -type f >&2 || true
    exit 1
  fi
  install -m 0755 "$found" "/usr/local/bin/${binary}"
done
GHTOOL
RUN chmod +x /usr/local/bin/install-github-release-tool

RUN ARCH="$(dpkg --print-architecture)" && \
    wget -q "https://downloads.mongodb.com/compass/mongodb-mongosh_${MONGOSH_VERSION}_${ARCH}.deb" && \
    dpkg -i "mongodb-mongosh_${MONGOSH_VERSION}_${ARCH}.deb" || apt-get install -f -y && \
    rm -f "mongodb-mongosh_${MONGOSH_VERSION}_${ARCH}.deb"

RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64) MONGO_ARCH="x86_64" ;; \
      arm64) MONGO_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    TOOLS_TGZ="mongodb-database-tools-ubuntu2404-${MONGO_ARCH}-${MONGO_TOOLS_VERSION}.tgz" && \
    wget -q "https://fastdl.mongodb.org/tools/db/${TOOLS_TGZ}" && \
    mkdir -p /tmp/mongo-tools && \
    tar -xzf "${TOOLS_TGZ}" -C /tmp/mongo-tools && \
    cp -f /tmp/mongo-tools/mongodb-database-tools-ubuntu2404-${MONGO_ARCH}-${MONGO_TOOLS_VERSION}/bin/* /usr/local/bin/ && \
    chmod +x /usr/local/bin/mongo* /usr/local/bin/bsondump /usr/local/bin/mongostat /usr/local/bin/mongotop || true && \
    rm -rf /tmp/mongo-tools "${TOOLS_TGZ}"

RUN ARCH="$(dpkg --print-architecture)" && \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" && \
    chmod +x /usr/local/bin/kubectl

RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64) HELM_ARCH="amd64" ;; \
      arm64) HELM_ARCH="arm64" ;; \
      armhf) HELM_ARCH="arm" ;; \
      *) echo "Unsupported architecture for Helm: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSLo /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz" && \
    tar -xzf /tmp/helm.tgz -C /tmp && \
    mv "/tmp/linux-${HELM_ARCH}/helm" /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf /tmp/helm.tgz "/tmp/linux-${HELM_ARCH}"

RUN ARCH="$(dpkg --print-architecture)" && \
    wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" && \
    chmod +x /usr/local/bin/yq

RUN wget -q "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz" && \
    tar -xzf "keycloak-${KEYCLOAK_VERSION}.tar.gz" -C /opt && \
    mv "/opt/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak && \
    ln -sf /opt/keycloak/bin/kcadm.sh /usr/local/bin/kcadm.sh && \
    ln -sf /opt/keycloak/bin/kcreg.sh /usr/local/bin/kcreg.sh && \
    ln -sf /opt/keycloak/bin/kc.sh /usr/local/bin/kc.sh && \
    chmod +x /opt/keycloak/bin/*.sh && \
    rm -f "keycloak-${KEYCLOAK_VERSION}.tar.gz"

RUN wget -q "https://github.com/NetApp/trident/releases/download/v${TRIDENT_VERSION}/trident-installer-${TRIDENT_VERSION}.tar.gz" && \
    tar -xzf "trident-installer-${TRIDENT_VERSION}.tar.gz" && \
    cp trident-installer/tridentctl /usr/local/bin/ && \
    chmod +x /usr/local/bin/tridentctl && \
    rm -rf "trident-installer-${TRIDENT_VERSION}.tar.gz" trident-installer

RUN ARCH="$(dpkg --print-architecture)" && \
    case "$ARCH" in \
      amd64) GO_ARCH="amd64"; X86_ARCH="x86_64"; POPEYE_ARCH="x86_64" ;; \
      arm64) GO_ARCH="arm64"; X86_ARCH="arm64"; POPEYE_ARCH="arm64" ;; \
      *) echo "Unsupported architecture for diagnostic CLIs: $ARCH" && exit 1 ;; \
    esac && \
    install-github-release-tool kubernetes-sigs/cri-tools "${CRICTL_VERSION}" "crictl-${CRICTL_VERSION}-linux-${GO_ARCH}\\.tar\\.gz$" crictl && \
    install-github-release-tool etcd-io/etcd "${ETCD_VERSION}" "etcd-${ETCD_VERSION}-linux-${GO_ARCH}\\.tar\\.gz$" etcdctl etcdutl && \
    install-github-release-tool cert-manager/cmctl "${CMCTL_VERSION}" "cmctl.*linux.*${GO_ARCH}.*tar\\.gz$" cmctl && \
    install-github-release-tool smallstep/cli "${STEP_VERSION}" "step.*linux.*${GO_ARCH}.*tar\\.gz$" step && \
    install-github-release-tool doitintl/kube-no-trouble "${KUBENT_VERSION}" "kubent.*linux.*${GO_ARCH}.*tar\\.gz$" kubent && \
    install-github-release-tool yannh/kubeconform "${KUBECONFORM_VERSION}" "kubeconform.*linux.*${GO_ARCH}.*tar\\.gz$" kubeconform && \
    install-github-release-tool derailed/popeye "${POPEYE_VERSION}" "popeye.*[Ll]inux.*${POPEYE_ARCH}.*tar\\.gz$" popeye && \
    install-github-release-tool aquasecurity/kubectl-who-can "${KUBECTL_WHO_CAN_VERSION}" "kubectl-who-can.*linux.*${X86_ARCH}.*tar\\.gz$" kubectl-who-can && \
    install-github-release-tool FairwindsOps/rbac-lookup "${RBAC_LOOKUP_VERSION}" "rbac-lookup.*linux.*${GO_ARCH}.*tar\\.gz$" rbac-lookup && \
    install-github-release-tool cilium/cilium-cli "${CILIUM_CLI_VERSION}" "cilium.*linux.*${GO_ARCH}.*tar\\.gz$" cilium && \
    install-github-release-tool cilium/hubble "${HUBBLE_VERSION}" "hubble.*linux.*${GO_ARCH}.*tar\\.gz$" hubble && \
    install-github-release-tool projectcalico/calico "${CALICOCTL_VERSION}" "calicoctl-linux-${GO_ARCH}$" calicoctl

RUN pip3 install --no-cache-dir --break-system-packages \
    click \
    jinja2 \
    kubernetes \
    pg_activity \
    pgcli \
    psycopg[binary] \
    pymongo \
    pyyaml \
    requests \
    sqlalchemy

RUN cat > /usr/local/bin/pg-diagnostics.sh <<'PGDIAGS'
#!/bin/bash
set -euo pipefail
usage() {
  cat <<'EOF'
PostgreSQL diagnostic helper
Connection options are read from standard libpq environment variables.
Set PGHOST, PGPORT, PGDATABASE, PGUSER, and your credential through an approved secret workflow before running.
The script intentionally never prints sensitive connection values.
EOF
}
run_sql() {
  local title="$1"
  local sql="$2"
  echo ""
  echo "## ${title}"
  echo "--------------------------------------------------------------------------------"
  psql ${DATABASE_URL:+"$DATABASE_URL"} -v ON_ERROR_STOP=0 -P pager=off -x -c "$sql" 2>/dev/null || echo "Skipped or failed: insufficient permissions, missing extension, or connection issue."
}
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
if [[ -z "${DATABASE_URL:-}" && -z "${PGHOST:-}" ]]; then
  echo "PostgreSQL diagnostics are installed, but no target database was provided."
  echo "Set standard libpq environment variables or DATABASE_URL, then rerun."
  echo ""
  echo "Installed PostgreSQL tools:"
  psql --version || true
  pg_isready --version || true
  pg_dump --version || true
  pg_restore --version || true
  pgbench --version || true
  command -v pgbadger >/dev/null && pgbadger --version || true
  command -v pg_activity >/dev/null && pg_activity --version || true
  command -v pgcli >/dev/null && pgcli --version || true
  exit 0
fi
echo "PostgreSQL diagnostic summary"
echo "Target: ${PGHOST:-DATABASE_URL}:${PGPORT:-5432}/${PGDATABASE:-default}"
echo "User: ${PGUSER:-from-connection-string}"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""
echo "Connectivity:"
pg_isready -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -d "${PGDATABASE:-postgres}" -U "${PGUSER:-postgres}" || true
run_sql "Server and connection identity" "select version() as version, current_database() as database, current_user as user, inet_server_addr() as server_addr, inet_server_port() as server_port;"
run_sql "Database size summary" "select datname, pg_size_pretty(pg_database_size(datname)) as size from pg_database order by pg_database_size(datname) desc limit 20;"
run_sql "Connection state counts" "select state, count(*) from pg_stat_activity group by state order by count(*) desc;"
run_sql "Long running queries" "select pid, usename, state, now() - query_start as age, wait_event_type, wait_event, left(query, 240) as query from pg_stat_activity where state <> 'idle' order by age desc limit 15;"
run_sql "Blocking locks" "select blocked_locks.pid as blocked_pid, blocked_activity.usename as blocked_user, blocking_locks.pid as blocking_pid, blocking_activity.usename as blocking_user, left(blocked_activity.query, 160) as blocked_statement, left(blocking_activity.query, 160) as blocking_statement from pg_catalog.pg_locks blocked_locks join pg_catalog.pg_stat_activity blocked_activity on blocked_activity.pid = blocked_locks.pid join pg_catalog.pg_locks blocking_locks on blocking_locks.locktype = blocked_locks.locktype and blocking_locks.database is not distinct from blocked_locks.database and blocking_locks.relation is not distinct from blocked_locks.relation and blocking_locks.page is not distinct from blocked_locks.page and blocking_locks.tuple is not distinct from blocked_locks.tuple and blocking_locks.virtualxid is not distinct from blocked_locks.virtualxid and blocking_locks.transactionid is not distinct from blocked_locks.transactionid and blocking_locks.classid is not distinct from blocked_locks.classid and blocking_locks.objid is not distinct from blocked_locks.objid and blocking_locks.objsubid is not distinct from blocked_locks.objsubid and blocking_locks.pid != blocked_locks.pid join pg_catalog.pg_stat_activity blocking_activity on blocking_activity.pid = blocking_locks.pid where not blocked_locks.granted;"
run_sql "Replication senders" "select pid, usename, application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag from pg_stat_replication;"
run_sql "Database statistics" "select datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, deadlocks from pg_stat_database order by datname;"
echo ""
echo "Diagnostics complete. For log analysis, copy PostgreSQL logs into /workspace and run: pgbadger <logfile> -o /workspace/postgres-report.html"
PGDIAGS
RUN chmod +x /usr/local/bin/pg-diagnostics.sh

RUN cat > /usr/local/bin/keycloak-login.sh <<'KCLOGIN'
#!/bin/bash
set -euo pipefail
: "${KEYCLOAK_URL:?Set KEYCLOAK_URL, for example https://keycloak.example.com}"
: "${KEYCLOAK_USER:?Set KEYCLOAK_USER}"
: "${KEYCLOAK_SECRET:?Set KEYCLOAK_SECRET from an approved secret source}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-master}"
KEYCLOAK_CLIENT="${KEYCLOAK_CLIENT:-admin-cli}"
kcadm.sh config credentials --server "$KEYCLOAK_URL" --realm "$KEYCLOAK_REALM" --client "$KEYCLOAK_CLIENT" --user "$KEYCLOAK_USER" --password "$KEYCLOAK_SECRET"
echo "Authenticated to ${KEYCLOAK_URL} realm ${KEYCLOAK_REALM}."
kcadm.sh get realms --fields realm,enabled | head -40
KCLOGIN
RUN chmod +x /usr/local/bin/keycloak-login.sh

RUN cat > /usr/local/bin/update-ca-trust.sh <<'CATRUST'
#!/bin/bash
set -euo pipefail
CA_TARGET_DIR="/usr/local/share/ca-certificates/custom"
PRIMARY_CA_SOURCE="${CA_CERT_DIR:-/etc/ssl/custom-ca}"
LEGACY_CA_PATH="/tls/ca.crt"
mkdir -p "$CA_TARGET_DIR"
case "${1:-}" in
  --list|--verify)
    echo "Custom CA certificates in ${CA_TARGET_DIR}:"
    find "$CA_TARGET_DIR" -maxdepth 1 -type f -name '*.crt' -print -exec openssl x509 -in {} -noout -subject -issuer -dates \; 2>/dev/null || true
    exit 0 ;;
  --help|-h) echo "Usage: update-ca-trust.sh [--list|--verify]"; exit 0 ;;
esac
for source in "$PRIMARY_CA_SOURCE"; do
  if [[ -d "$source" ]]; then
    for cert in "$source"/*.crt "$source"/*.pem; do
      [[ -f "$cert" ]] || continue
      if openssl x509 -in "$cert" -noout >/dev/null 2>&1; then
        cp "$cert" "$CA_TARGET_DIR/$(basename "${cert%.*}").crt"
        echo "Installed CA: $(basename "$cert")"
      fi
    done
  fi
done
if [[ -f "$LEGACY_CA_PATH" ]] && openssl x509 -in "$LEGACY_CA_PATH" -noout >/dev/null 2>&1; then
  cp "$LEGACY_CA_PATH" "$CA_TARGET_DIR/legacy-ca.crt"
  echo "Installed CA: legacy-ca.crt"
fi
update-ca-certificates --fresh >/dev/null 2>&1 || update-ca-certificates >/dev/null 2>&1
echo "CA trust store refreshed."
CATRUST
RUN chmod +x /usr/local/bin/update-ca-trust.sh

RUN cat > /usr/local/bin/show-versions.sh <<'VERSIONS'
#!/bin/bash
set +e
cat <<'EOF'
==============================================
  K8s Ultimate Toolbox v1.2.0
  Cluster, identity, database, network, storage, RBAC, policy, and CNI diagnostics
==============================================
EOF

echo ""
echo "☸️  Kubernetes / GitOps"
kubectl version --client=true 2>/dev/null | head -1 || echo "  kubectl: installed"
helm version --short 2>/dev/null || true
yq --version 2>/dev/null || true
jq --version 2>/dev/null || true

echo ""
echo "🧱 Runtime / control plane"
crictl --version 2>/dev/null || true
etcdctl version 2>/dev/null | head -2 || true
etcdutl version 2>/dev/null | head -2 || true

echo ""
echo "🔐 Keycloak / certificates"
kcadm.sh --help >/dev/null 2>&1 && echo "  kcadm.sh: ready" || echo "  kcadm.sh: missing"
kcreg.sh --help >/dev/null 2>&1 && echo "  kcreg.sh: ready" || echo "  kcreg.sh: missing"
kc.sh --help >/dev/null 2>&1 && echo "  kc.sh: ready" || echo "  kc.sh: missing"
cmctl version --client 2>/dev/null || command -v cmctl >/dev/null && echo "  cmctl: ready"
step version 2>/dev/null || true
java -version 2>&1 | head -1

echo ""
echo "🧹 Policy / upgrade / RBAC"
kubent --version 2>/dev/null || command -v kubent >/dev/null && echo "  kubent: ready"
kubeconform -v 2>/dev/null || command -v kubeconform >/dev/null && echo "  kubeconform: ready"
popeye version 2>/dev/null || command -v popeye >/dev/null && echo "  popeye: ready"
kubectl-who-can --help >/dev/null 2>&1 && echo "  kubectl-who-can: ready" || echo "  kubectl-who-can: missing"
rbac-lookup --help >/dev/null 2>&1 && echo "  rbac-lookup: ready" || echo "  rbac-lookup: missing"

echo ""
echo "🕸️  CNI"
cilium version --client 2>/dev/null || command -v cilium >/dev/null && echo "  cilium: ready"
hubble version 2>/dev/null || command -v hubble >/dev/null && echo "  hubble: ready"
calicoctl version --help >/dev/null 2>&1 && echo "  calicoctl: ready" || command -v calicoctl >/dev/null && echo "  calicoctl: ready"

echo ""
echo "🐘 PostgreSQL"
psql --version 2>/dev/null || true
pg_isready --version 2>/dev/null || true
pg_dump --version 2>/dev/null || true
pg_restore --version 2>/dev/null || true
pgbench --version 2>/dev/null || true
command -v pg_activity >/dev/null && pg_activity --version 2>/dev/null || true
command -v pgcli >/dev/null && pgcli --version 2>/dev/null || true

echo ""
echo "🍃 MongoDB"
mongosh --version 2>/dev/null | head -1 || true
mongodump --version 2>/dev/null | grep version || true
mongorestore --version 2>/dev/null | grep version || true

echo ""
echo "🌐 Network / TLS"
echo "  curl, wget, dig, nslookup, nc, nmap, tcpdump, traceroute, mtr, iperf3, socat, openssl"
openssl version 2>/dev/null || true

echo ""
echo "💾 Storage"
tridentctl version --client 2>/dev/null || echo "  tridentctl: installed"
echo "  nfs-common, rsync, ssh, tar, zip/unzip"

echo ""
echo "🛠️  System / scripting"
python3 --version 2>/dev/null || true
echo "  git, vim, nano, htop, less, strace, lsof, jq, yq, shell UX"
echo ""
echo "Operational helpers: pg-diagnostics.sh, keycloak-login.sh, update-ca-trust.sh"
echo "Ready."
VERSIONS
RUN chmod +x /usr/local/bin/show-versions.sh

RUN kubectl version --client=true >/dev/null 2>&1 && \
    helm version --short >/dev/null && \
    yq --version >/dev/null && \
    kcadm.sh --help >/dev/null && \
    psql --version >/dev/null && \
    pg_isready --version >/dev/null && \
    pg-diagnostics.sh --help >/dev/null && \
    mongosh --version >/dev/null && \
    mongodump --version >/dev/null && \
    tridentctl version --client >/dev/null 2>&1 && \
    command -v crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl >/dev/null && \
    python3 --version >/dev/null

RUN useradd -m -s /bin/bash -u 10000 toolbox && \
    mkdir -p /home/toolbox/.kube /home/toolbox/scripts /workspace && \
    chown -R toolbox:toolbox /home/toolbox /workspace

WORKDIR /workspace
USER toolbox

CMD ["/bin/bash", "-c", "show-versions.sh && tail -f /dev/null"]
