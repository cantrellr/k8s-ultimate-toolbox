# 📚 Ultimate K8s Toolbox - Documentation Index

**v1.0.2 "First Flight" Release**

> A comprehensive Kubernetes administration workstation with 50+ pre-installed tools

---

## 📖 Quick Navigation

### Core Documentation

| Document | Description | When to Use |
|----------|-------------|-------------|
| [README.md](README.md) | Main project overview, features, architecture | Start here |
| [QUICKSTART.md](QUICKSTART.md) | 5-minute deployment guide | Get running fast |
| [TOOLS-REFERENCE.md](TOOLS-REFERENCE.md) | Complete tool list with examples | Learn available tools |
| [CHANGELOG.md](CHANGELOG.md) | Version history and release notes | See what's new |

### Deployment Guides

| Document | Description | When to Use |
|----------|-------------|-------------|
| [OFFLINE-DEPLOYMENT.md](OFFLINE-DEPLOYMENT.md) | Air-gapped deployment guide | No internet access |
| [NERDCTL-GUIDE.md](NERDCTL-GUIDE.md) | Container runtime setup | Building images |
| [MAKEFILE.md](MAKEFILE.md) | Build system documentation | Automation & CI |
| [SBOM.md](SBOM.md) | Software Bill of Materials | Security & compliance |

### Community & Contributing

| Document | Description |
|----------|-------------|
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community guidelines |
| [SECURITY.md](SECURITY.md) | Security policy |
| [LICENSE](LICENSE) | MIT License |

---

## 📁 Project Structure

```
ultimate-k8s-toolbox/
├── 📄 README.md                 # Main documentation
├── 📄 QUICKSTART.md             # Quick deployment guide
├── 📄 TOOLS-REFERENCE.md        # Tool documentation
├── 📄 OFFLINE-DEPLOYMENT.md     # Air-gapped guide
├── 📄 NERDCTL-GUIDE.md          # Container runtime guide
├── 📄 MAKEFILE.md               # Build system docs
├── 📄 SBOM.md                   # SBOM documentation
├── 📄 QUICK-REFERENCE.md        # Cheat sheet
├── 📄 CHANGELOG.md              # Release history
├── 📄 CONTRIBUTING.md           # Contribution guide
├── 📄 CODE_OF_CONDUCT.md        # Community guidelines
├── 📄 SECURITY.md               # Security policy
├── 📄 LICENSE                   # MIT License
├── 📄 Makefile                  # Build automation
│
├── 📁 build/
│   └── Dockerfile               # Container image definition
│
├── 📁 chart/                    # Helm chart
│   ├── Chart.yaml               # Chart metadata
│   ├── values.yaml              # Default configuration
│   └── templates/
│       ├── _helpers.tpl         # Template helpers
│       ├── deployment.yaml      # Deployment manifest
│       └── serviceaccount.yaml  # ServiceAccount + RBAC
│
├── 📁 configs/
│   └── example-values-offline.yaml  # Offline deployment config
│
├── 📁 examples/
│   ├── README.md                # Examples documentation
│   ├── values-online.yaml       # Online deployment
│   ├── values-offline.yaml      # Offline deployment
│   ├── values-mongodb.yaml      # MongoDB namespace example
│   ├── values-with-ca.yaml      # Custom CA example
│   ├── patch-host-aliases.yaml  # /etc/hosts patch
│   ├── coredns-custom-forward.yaml  # DNS forwarding
│   └── DEPLOYMENT-EXAMPLES.sh   # CLI examples
│
├── 📁 scripts/
│   ├── deploy-offline.sh.template   # Offline deploy script
│   ├── import-ca-certs.sh       # CA certificate helper
│   ├── install-toolbox.sh       # CLI installer
│   └── toolbox                  # Quick exec script
│
├── 📁 tests/
│   ├── README.md                # Test documentation
│   ├── test-helm-chart.sh       # Helm chart tests
│   └── TEST-RESULTS.md          # Test results
│
└── 📁 .github/
    ├── ISSUE_TEMPLATE/          # Issue templates
    ├── PULL_REQUEST_TEMPLATE.md # PR template
    └── workflows/               # CI/CD pipelines
```

---

## 🚀 Quick Start

### Online Deployment

```bash
# Deploy
helm install toolbox ./chart -n toolbox --create-namespace

# Access
kubectl exec -it -n toolbox deploy/toolbox-ultimate-k8s-toolbox -- bash

# Or use helper script
./scripts/toolbox
```

### Offline Deployment

```bash
# Create bundle
make offline-bundle

# Transfer and deploy
./scripts/deploy-offline.sh --registry registry.local:5000 --namespace toolbox
```

---

## 📦 Configuration Files

### Values Files

| File | Purpose | Location |
|------|---------|----------|
| `values.yaml` | Default configuration | `chart/values.yaml` |
| `values-online.yaml` | Internet-connected deployment | `examples/` |
| `values-offline.yaml` | Air-gapped deployment | `examples/` |
| `values-mongodb.yaml` | MongoDB namespace | `examples/` |
| `values-with-ca.yaml` | Custom CA certificates | `examples/` |

### Key Configuration Options

```yaml
# Registry for offline deployments
global:
  imageRegistry: "registry.example.com:5000"

# Image settings
image:
  repository: "ultimate-k8s-toolbox"
  tag: "v1.0.2"

# Custom CA certificates
customCA:
  enabled: true
  secretName: "ca-certs"

# Resources
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

---

## 🛠️ Build Commands

```bash
# Build image
make build

# Multi-arch build
make build-multi

# Create offline bundle
make offline-bundle

# Generate SBOM
make sbom

# Run tests
make test

# View all targets
make help
```

---

## 📊 Deployment Scenarios

| Scenario | Values File | Guide |
|----------|-------------|-------|
| Online (with internet) | `values-online.yaml` | [QUICKSTART.md](QUICKSTART.md) |
| Offline (air-gapped) | `values-offline.yaml` | [OFFLINE-DEPLOYMENT.md](OFFLINE-DEPLOYMENT.md) |
| With custom CA | `values-with-ca.yaml` | [OFFLINE-DEPLOYMENT.md](OFFLINE-DEPLOYMENT.md) |
| MongoDB namespace | `values-mongodb.yaml` | [examples/README.md](examples/README.md) |

---

## 🔗 External Resources

- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [nerdctl Documentation](https://github.com/containerd/nerdctl)

---

## 📬 Getting Help

1. **Quick questions** → [QUICKSTART.md](QUICKSTART.md)
2. **Tool usage** → [TOOLS-REFERENCE.md](TOOLS-REFERENCE.md)
3. **Offline deployment** → [OFFLINE-DEPLOYMENT.md](OFFLINE-DEPLOYMENT.md)
4. **Build issues** → [MAKEFILE.md](MAKEFILE.md)
5. **Bug reports** → [GitHub Issues](https://github.com/cantrellr/ultimate-k8s-toolbox/issues)
6. **Feature requests** → [GitHub Discussions](https://github.com/cantrellr/ultimate-k8s-toolbox/discussions)

---

*✈️ "First Flight" Release - v1.0.2*
