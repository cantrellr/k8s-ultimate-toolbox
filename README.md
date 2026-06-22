# Ultimate Kubernetes Toolbox

```
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║   █░█ █░░ ▀█▀ █ █▀▄▀█ ▄▀█ ▀█▀ █▀▀   █▄▀ ▄▀█ █▀   ▀█▀ █▀█ █▀█ █░░      ║
║   █▄█ █▄▄ ░█░ █ █░▀░█ █▀█ ░█░ ██▄   █░█ ▀▀█ ▄█   ░█░ █▄█ █▄█ █▄▄      ║
║                                                                       ║
║                 Platform Diagnostics Release - v1.1.0                 ║
╚═══════════════════════════════════════════════════════════════════════╝
```

**A Kubernetes administration workstation pod for cluster, identity, database, network, storage, and air-gapped troubleshooting.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Helm](https://img.shields.io/badge/Helm-4.x-blue.svg)](https://helm.sh)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36+-326CE5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io)

## Executive summary

Ultimate Kubernetes Toolbox deploys a controlled, repeatable troubleshooting pod into a Kubernetes namespace. It is designed for platform engineers who need fast access to known-good tools without turning every application container into a debugging science project.

The v1.1.0 release updates the core toolchain, adds first-class Keycloak support, and adds PostgreSQL diagnostics that are useful in the real world: readiness checks, connection inspection, lock analysis, query visibility, backup/restore validation, `pgBadger`, `pgcli`, `pg_activity`, and the helper script `pg-diagnostics.sh`.

## What changed in v1.1.0

| Area | Change |
|---|---|
| Kubernetes | Updated `kubectl` to `v1.36.1` |
| Helm | Updated to `v4.2.1` |
| YAML | Updated `yq` to `v4.53.3` |
| Identity | Updated Keycloak CLI tooling to `26.6.3` and retained optional Keycloak sidecar support |
| MongoDB | Updated `mongosh` to `2.8.3` and MongoDB Database Tools to `100.17.0` |
| PostgreSQL | Added `psql`, `pg_isready`, `pg_dump`, `pg_restore`, `pgbench`, `pgBadger`, `pgcli`, `pg_activity`, Python `psycopg`, and `pg-diagnostics.sh` |
| Storage | Updated `tridentctl` to `26.02.0` |
| Build | Refreshed Makefile, SBOM generation, offline bundle packaging, and image verification |
| Docs | Added PostgreSQL, Keycloak, tool reference, and recommended-tooling documentation |

## Architecture

```text
Kubernetes Cluster
└── toolbox namespace
    └── Deployment: ultimate-k8s-toolbox
        ├── init container: update-ca-trust      # optional, root, CA trust only
        ├── container: toolbox                  # non-root UID 10000
        │   ├── kubectl / helm / yq / jq
        │   ├── Keycloak CLI tools
        │   ├── PostgreSQL diagnostics
        │   ├── MongoDB tools
        │   ├── network and TLS tools
        │   └── storage tools
        ├── optional sidecar: keycloak-cli
        └── workspace volume: emptyDir or PVC
```

The main container runs as non-root by default. Network diagnostics require `NET_ADMIN` and `NET_RAW`; that is deliberate, but it also means this pod should be deployed with intent, not sprayed into every namespace like confetti.

## Quick start

```bash
git clone https://github.com/cantrellr/k8s-ultimate-toolbox.git
cd k8s-ultimate-toolbox

helm install toolbox ./chart \
  -n toolbox --create-namespace

kubectl wait --for=condition=available deploy/toolbox-ultimate-k8s-toolbox \
  -n toolbox --timeout=300s

kubectl exec -it -n toolbox deploy/toolbox-ultimate-k8s-toolbox -- bash
```

Show installed tools:

```bash
show-versions.sh
```

## Deploy with Keycloak sidecar

The main image already includes `kcadm.sh`, `kcreg.sh`, and `kc.sh`. The optional sidecar is useful when you want identity work isolated into the official Keycloak container image.

```bash
helm install toolbox ./chart \
  -n keycloak-system --create-namespace \
  --set keycloakCli.enabled=true

kubectl exec -it -n keycloak-system deploy/toolbox-ultimate-k8s-toolbox -c keycloak-cli -- /bin/sh
```

## PostgreSQL diagnostics example

```bash
kubectl exec -it -n toolbox deploy/toolbox-ultimate-k8s-toolbox -- bash

export PGHOST=postgres.postgres.svc.cluster.local
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD='<use-a-secret-not-shell-history>'

pg_isready
pg-diagnostics.sh
pgcli
```

For log analysis:

```bash
pgbadger /workspace/postgresql.log -o /workspace/postgres-report.html
```

## Included tools

| Category | Tools |
|---|---|
| Kubernetes | `kubectl`, `helm`, `yq`, `jq` |
| Identity | `kcadm.sh`, `kcreg.sh`, `kc.sh`, `keycloak-login.sh` |
| PostgreSQL | `psql`, `pg_isready`, `pg_dump`, `pg_restore`, `pgbench`, `pgcli`, `pg_activity`, `pgbadger`, `pg-diagnostics.sh`, Python `psycopg` |
| MongoDB | `mongosh`, `mongodump`, `mongorestore`, `mongoexport`, `mongoimport`, `mongostat`, `mongotop`, `bsondump` |
| Network | `curl`, `wget`, `dig`, `nslookup`, `host`, `nc`, `nmap`, `tcpdump`, `traceroute`, `mtr`, `iperf3`, `socat`, `ping`, `telnet`, `ss`, `netstat`, `whois` |
| TLS/X.509 | `openssl`, `certtool`, custom CA trust helper |
| Storage | `tridentctl`, `nfs-common`, `rsync`, `ssh`, `tar`, `zip`, `unzip` |
| System | `git`, `vim`, `nano`, `htop`, `less`, `strace`, `lsof`, `iotop`, `file`, `bash-completion` |
| Scripting | Python 3, `kubernetes`, `requests`, `PyYAML`, `Jinja2`, `click`, `SQLAlchemy` |
| Other DB clients | MySQL client, Redis CLI |

## Documentation

| Document | Purpose |
|---|---|
| [QUICKSTART.md](QUICKSTART.md) | Fast deployment and validation |
| [TOOLS-REFERENCE.md](TOOLS-REFERENCE.md) | Tool inventory and version matrix |
| [POSTGRESQL-DIAGNOSTICS.md](POSTGRESQL-DIAGNOSTICS.md) | PostgreSQL troubleshooting runbook |
| [KEYCLOAK-GUIDE.md](KEYCLOAK-GUIDE.md) | Keycloak CLI and sidecar usage |
| [RECOMMENDED-TOOLS.md](RECOMMENDED-TOOLS.md) | Recommended future additions and priority |
| [OFFLINE-DEPLOYMENT.md](OFFLINE-DEPLOYMENT.md) | Air-gapped bundle workflow |
| [MAKEFILE.md](MAKEFILE.md) | Build system notes |
| [SBOM.md](SBOM.md) | SBOM and supply-chain notes |
| [NERDCTL-GUIDE.md](NERDCTL-GUIDE.md) | Container runtime guidance |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Configuration highlights

| Value | Default | Notes |
|---|---:|---|
| `image.repository` | `ultimate-k8s-toolbox` | Toolbox image repository |
| `image.tag` | `v1.1.0` | Deterministic default image tag |
| `global.imageRegistry` | empty | Prefix for private/offline registries |
| `workspace.enabled` | `true` | Mounts `/workspace` |
| `workspace.storageClass` | empty | Empty means `emptyDir`; set for PVC |
| `customCA.enabled` | `false` | Enables CA trust init container |
| `keycloakCli.enabled` | `false` | Optional official Keycloak sidecar |
| `resources.limits.memory` | `2Gi` | Higher than v1.0.2 because PostgreSQL/Java tooling is included |

## Build and offline bundle

```bash
make info
make build-image
make offline-bundle
```

The offline bundle includes the image tarball, packaged Helm chart, deployment scripts, SBOM, checksums, and docs.

## Security posture

This toolbox is powerful. Treat it as privileged operational tooling even though the main container runs as non-root.

Do not bake credentials into the image. Use Kubernetes Secrets, short-lived tokens, restricted service accounts, and namespace-scoped RBAC wherever possible. Remove the deployment when troubleshooting is complete in sensitive environments.

## Recommended next additions

The next best additions are `crictl`, `etcdctl`/`etcdutl`, `cmctl`, `step`, `kubent`, `kubeconform`, `popeye`, `kubectl-who-can`, `rbac-lookup`, and CNI-specific CLIs such as `cilium`, `hubble`, or `calicoctl` where applicable. See [RECOMMENDED-TOOLS.md](RECOMMENDED-TOOLS.md) for the rationale and priority.
