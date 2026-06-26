# 📚 K8s Ultimate Toolbox - Documentation Index

**v1.1.0 Platform Diagnostics Release**

> Kubernetes administration workstation tooling for cluster, identity, database, network, storage, and air-gapped troubleshooting.

---

## 📖 Quick navigation

### Core documentation

| Document | Description | When to use |
|----------|-------------|-------------|
| [README.md](../README.md) | Main project overview, architecture, and release highlights | Start here |
| [QUICKSTART.md](../QUICKSTART.md) | Fast deployment and validation guide | Get running fast |
| [TOOLS-REFERENCE.md](../TOOLS-REFERENCE.md) | Current tool inventory and version matrix | Confirm what is installed |
| [POSTGRESQL-DIAGNOSTICS.md](../POSTGRESQL-DIAGNOSTICS.md) | PostgreSQL troubleshooting runbook | Triage PostgreSQL connectivity, locks, activity, and reports |
| [KEYCLOAK-GUIDE.md](../KEYCLOAK-GUIDE.md) | Keycloak CLI usage in the default toolbox container | Work with Keycloak realms, clients, and admin sessions |
| [RECOMMENDED-TOOLS.md](../RECOMMENDED-TOOLS.md) | Recommended future additions and priority | Plan the next capability bump |
| [CHANGELOG.md](../CHANGELOG.md) | Version history and release notes | See what changed |

### Deployment and build guides

| Document | Description | When to use |
|----------|-------------|-------------|
| [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md) | Air-gapped bundle workflow | No internet access or controlled registry imports |
| [NERDCTL-GUIDE.md](NERDCTL-GUIDE.md) | Container runtime guidance | Build or load images with containerd/nerdctl |
| [MAKEFILE.md](../MAKEFILE.md) | Build system notes | Automation, packaging, and CI-like tasks |
| [SBOM.md](../SBOM.md) | SBOM and supply-chain notes | Security review and compliance evidence |

### Community and governance

| Document | Description |
|----------|-------------|
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Contribution workflow and coding expectations |
| [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Community guidelines |
| [SECURITY.md](../SECURITY.md) | Security reporting and operating guidance |
| [LICENSE](../LICENSE) | MIT License |

---

## 📁 Project structure

```text
k8s-ultimate-toolbox/
├── README.md                    # Main documentation
├── QUICKSTART.md                # Quick deployment guide
├── TOOLS-REFERENCE.md           # Current tool inventory and version matrix
├── POSTGRESQL-DIAGNOSTICS.md    # PostgreSQL troubleshooting runbook
├── KEYCLOAK-GUIDE.md            # Keycloak operations guide
├── RECOMMENDED-TOOLS.md         # Tooling roadmap
├── OFFLINE-DEPLOYMENT.md        # Air-gapped guide
├── MAKEFILE.md                  # Build system docs
├── SBOM.md                      # SBOM documentation
├── QUICK-REFERENCE.md           # Cheat sheet
├── CHANGELOG.md                 # Release history
├── CONTRIBUTING.md              # Contribution guide
├── CODE_OF_CONDUCT.md           # Community guidelines
├── SECURITY.md                  # Security policy
├── LICENSE                      # MIT License
├── Makefile                     # Build automation
│
├── build/
│   └── Dockerfile               # Container image definition
│
├── chart/                       # Helm chart
│   ├── Chart.yaml               # Chart metadata
│   ├── values.yaml              # Default configuration
│   └── templates/               # Kubernetes manifests
│
├── docs/                        # Secondary navigation and compatibility docs
│   ├── INDEX.md                 # Documentation index
│   └── NERDCTL-GUIDE.md         # Container runtime guide
│
├── examples/                    # Example values and deployment snippets
├── scripts/                     # Install, exec, CA, and offline helper scripts
├── tests/                       # Helm/chart validation scripts and notes
└── .github/                     # GitHub templates and workflows
```

---

## 🚀 Quick start

### Online deployment

```bash
helm install toolbox ./chart -n toolbox --create-namespace
kubectl wait --for=condition=available deploy/toolbox-ultimate-k8s-toolbox \
  -n toolbox --timeout=300s
kubectl exec -it -n toolbox deploy/toolbox-ultimate-k8s-toolbox -- bash
```

### Keycloak tooling

```bash
kubectl exec -it -n toolbox deploy/toolbox-ultimate-k8s-toolbox -- bash
keycloak-login.sh
kcadm.sh get realms
```

### Offline deployment

```bash
make offline-bundle
./scripts/deploy-offline.sh --registry registry.local:5000 --namespace toolbox
```

---

## 📦 Key configuration options

```yaml
global:
  imageRegistry: "registry.example.com:5000"

image:
  repository: "ultimate-k8s-toolbox"
  tag: "v1.1.0"

customCA:
  enabled: true
  secretName: "ca-certs"

workspace:
  enabled: true
  storageClass: ""
  size: "10Gi"
```

---

## 🛠️ Build commands

```bash
make info
make build-image
make test-image
make package-chart
make offline-bundle
make sbom
make clean
```

---

## 📊 Deployment scenarios

| Scenario | Primary guide |
|----------|---------------|
| Online / connected cluster | [QUICKSTART.md](../QUICKSTART.md) |
| Offline / air-gapped cluster | [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md) |
| Internal CA trust | [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md) |
| Keycloak CLI operations | [KEYCLOAK-GUIDE.md](../KEYCLOAK-GUIDE.md) |
| PostgreSQL triage | [POSTGRESQL-DIAGNOSTICS.md](../POSTGRESQL-DIAGNOSTICS.md) |

---

## 🔗 External resources

- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [nerdctl Documentation](https://github.com/containerd/nerdctl)

---

## 📬 Getting help

1. **Quick questions** → [QUICKSTART.md](../QUICKSTART.md)
2. **Tool inventory** → [TOOLS-REFERENCE.md](../TOOLS-REFERENCE.md)
3. **Offline deployment** → [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md)
4. **Build issues** → [MAKEFILE.md](../MAKEFILE.md)
5. **Bug reports** → [GitHub Issues](https://github.com/cantrellr/k8s-ultimate-toolbox/issues)
6. **Feature requests** → [GitHub Discussions](https://github.com/cantrellr/k8s-ultimate-toolbox/discussions)

---

*Platform Diagnostics Release - v1.1.0*
