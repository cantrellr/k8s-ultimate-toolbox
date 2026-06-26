# K8s Ultimate Toolbox

```
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║                         K8s Ultimate Toolbox                          ║
║                                                                       ║
║                 Platform Diagnostics Release - v1.2.0                 ║
╚═══════════════════════════════════════════════════════════════════════╝
```

**A Kubernetes administration workstation pod for cluster, identity, database, network, storage, runtime, RBAC, policy, CNI, and air-gapped troubleshooting.**

## Executive summary

K8s Ultimate Toolbox deploys a controlled, repeatable troubleshooting pod into a Kubernetes namespace. It gives platform engineers one known-good operational shell instead of forcing troubleshooting tools into every application image.

The v1.2.0 release implements the recommended next additions: `crictl`, `etcdctl`, `etcdutl`, `cmctl`, `step`, `kubent`, `kubeconform`, `popeye`, `kubectl-who-can`, `rbac-lookup`, `cilium`, `hubble`, and `calicoctl`.

## What changed in v1.2.0

| Area | Added |
|---|---|
| Runtime | `crictl` |
| Control plane | `etcdctl`, `etcdutl` |
| Certificates / PKI | `cmctl`, `step` |
| Upgrade safety | `kubent`, `kubeconform` |
| Cluster hygiene | `popeye` |
| RBAC | `kubectl-who-can`, `rbac-lookup` |
| CNI | `cilium`, `hubble`, `calicoctl` |

## Architecture

```text
Kubernetes Cluster
└── toolbox namespace
    └── Deployment: k8s-ultimate-toolbox
        ├── init container: update-ca-trust      # optional, root, CA trust only
        ├── container: toolbox                  # non-root UID 10000
        │   ├── kubectl / helm / yq / jq
        │   ├── crictl / etcdctl / etcdutl
        │   ├── Keycloak CLI tools
        │   ├── cmctl / step
        │   ├── kubent / kubeconform / popeye
        │   ├── kubectl-who-can / rbac-lookup
        │   ├── cilium / hubble / calicoctl
        │   ├── PostgreSQL and MongoDB diagnostics
        │   ├── network and TLS tools
        │   └── storage tools
        └── workspace volume: emptyDir or PVC
```

## Quick start

```bash
git clone https://github.com/cantrellr/k8s-ultimate-toolbox.git
cd k8s-ultimate-toolbox

helm upgrade --install toolbox ./chart \
  -n toolbox --create-namespace

kubectl wait --for=condition=available deploy/toolbox-k8s-ultimate-toolbox \
  -n toolbox --timeout=300s

kubectl exec -it -n toolbox deploy/toolbox-k8s-ultimate-toolbox -- bash
```

Show installed tools:

```bash
show-versions.sh
```

## Included tools

| Category | Tools |
|---|---|
| Kubernetes | `kubectl`, `helm`, `yq`, `jq` |
| Runtime / control plane | `crictl`, `etcdctl`, `etcdutl` |
| Identity | `kcadm.sh`, `kcreg.sh`, `kc.sh`, `keycloak-login.sh` |
| Certificates / PKI | `cmctl`, `step`, `openssl`, `certtool` |
| Policy / RBAC / upgrade | `kubent`, `kubeconform`, `popeye`, `kubectl-who-can`, `rbac-lookup` |
| CNI | `cilium`, `hubble`, `calicoctl` |
| PostgreSQL | `psql`, `pg_isready`, `pg_dump`, `pg_restore`, `pgbench`, `pgcli`, `pg_activity`, `pgbadger`, `pg-diagnostics.sh` |
| MongoDB | `mongosh`, `mongodump`, `mongorestore`, `mongoexport`, `mongoimport`, `mongostat`, `mongotop`, `bsondump` |
| Network | `curl`, `wget`, `dig`, `nslookup`, `host`, `nc`, `nmap`, `tcpdump`, `traceroute`, `mtr`, `iperf3`, `socat`, `ping`, `telnet`, `ss`, `netstat`, `whois` |
| Storage | `tridentctl`, `nfs-common`, `rsync`, `ssh`, `tar`, `zip`, `unzip` |
| Scripting | Python 3, `kubernetes`, `requests`, `PyYAML`, `Jinja2`, `click`, `SQLAlchemy` |

## Documentation

| Document | Purpose |
|---|---|
| [QUICKSTART.md](QUICKSTART.md) | Fast deployment and validation |
| [TOOLS-REFERENCE.md](TOOLS-REFERENCE.md) | Tool inventory and version matrix |
| [POSTGRESQL-DIAGNOSTICS.md](POSTGRESQL-DIAGNOSTICS.md) | PostgreSQL troubleshooting runbook |
| [KEYCLOAK-GUIDE.md](KEYCLOAK-GUIDE.md) | Keycloak CLI usage in the default toolbox container |
| [RECOMMENDED-TOOLS.md](RECOMMENDED-TOOLS.md) | Implemented and future tooling roadmap |
| [OFFLINE-DEPLOYMENT.md](OFFLINE-DEPLOYMENT.md) | Air-gapped bundle workflow |
| [MAKEFILE.md](MAKEFILE.md) | Build system notes |
| [SBOM.md](SBOM.md) | SBOM and supply-chain notes |
| [docs/NERDCTL-GUIDE.md](docs/NERDCTL-GUIDE.md) | Container runtime guidance |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Configuration highlights

| Value | Default | Notes |
|---|---:|---|
| `image.repository` | `k8s-ultimate-toolbox` | Toolbox image repository |
| `image.tag` | `v1.2.0` | Deterministic default image tag |
| `global.imageRegistry` | empty | Prefix for private/offline registries |
| `workspace.enabled` | `true` | Mounts `/workspace` |
| `workspace.storageClass` | empty | Empty means `emptyDir`; set for PVC |
| `customCA.enabled` | `false` | Enables CA trust init container |

## Build and offline bundle

```bash
make info
make build-image
make offline-bundle
```

The offline bundle includes the image tarball, packaged Helm chart, deployment scripts, SBOM text output, checksums, and docs.

## Security posture

This toolbox is powerful. Treat it as privileged operational tooling even though the main container runs as non-root. Use Kubernetes Secrets, short-lived tokens, restricted service accounts, and namespace-scoped RBAC wherever possible. Remove the deployment when troubleshooting is complete in sensitive environments.
