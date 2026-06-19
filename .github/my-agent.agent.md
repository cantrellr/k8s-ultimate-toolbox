# Ultimate K8s Toolbox - Agent Instructions

## Project Overview

This repository contains the **Ultimate Kubernetes Admin Workstation** - a comprehensive Helm chart for deploying a Swiss-army knife toolbox pod inside Kubernetes clusters. The toolbox comes pre-loaded with 50+ operational tools for MongoDB operations, TLS debugging, networking diagnostics, storage management, and cluster inspection.

### Key Features
- **Container Runtime**: nerdctl + containerd (Kubernetes-native)
- **MongoDB Stack**: mongosh, mongodump, mongorestore, mongostat, mongotop, and more
- **Kubernetes Tools**: kubectl v1.31.4, Helm 3, jq, yq, envsubst
- **Networking**: dig, ping, traceroute, netcat, tcpdump, nmap, curl, wget, iperf3
- **Storage**: tridentctl (NetApp Trident), NFS utilities, rsync
- **TLS/X.509**: openssl, gnutls-bin, CA trust integration
- **Python 3.12**: With pymongo, kubernetes, pyyaml, requests, jinja2
- **Offline/Air-gapped Support**: Full support for disconnected environments

---

## Repository Structure

```
ultimate-k8s-toolbox/
├── Makefile                    # Build automation (offline bundles, images)
├── README.md                   # Main documentation
├── INDEX.md                    # Quick navigation index
├── QUICKSTART.md              # Fast deployment guide
├── QUICK-REFERENCE.md         # One-page cheat sheet
├── TOOLS-REFERENCE.md         # Complete tools documentation
├── OFFLINE-DEPLOYMENT.md      # Air-gapped deployment guide
├── NERDCTL-GUIDE.md           # nerdctl + containerd setup
├── MAKEFILE.md                # Makefile documentation
├── SBOM.md                    # Software Bill of Materials docs
├── ENCRYPTION.md              # Encryption implementation plan
├── REORGANIZATION.md          # Project structure notes
│
├── build/
│   └── Dockerfile             # Toolbox image with all 50+ tools
│
├── chart/                     # Helm chart
│   ├── Chart.yaml             # Chart metadata (v0.1.0)
│   ├── values.yaml            # Default configuration
│   └── templates/
│       ├── _helpers.tpl       # Helper templates (image resolution, CA bundle)
│       ├── deployment.yaml    # Deployment manifest
│       ├── serviceaccount.yaml
│       └── ca-secret.yaml     # Optional CA certificate secret
│
├── examples/                  # Example configurations
│   ├── README.md
│   ├── values-online.yaml     # Internet-connected deployment
│   ├── values-offline.yaml    # Air-gapped deployment template
│   ├── values-mongodb.yaml    # MongoDB namespace example
│   ├── values-with-ca.yaml    # Custom CA certificate example
│   └── DEPLOYMENT-EXAMPLES.sh # 10 deployment scenarios
│
├── scripts/
│   ├── deploy-offline.sh.template  # Offline deployment automation
│   └── import-ca-certs.sh          # CA certificate import utility
│
└── tests/
    ├── README.md
    ├── test-helm-chart.sh     # Automated testing script
    └── TEST-RESULTS.md        # Validation results
```

---

## Key Files Reference

### Build & Deployment
| File | Purpose |
|------|---------|
| `build/Dockerfile` | Multi-stage Dockerfile with all tools (Ubuntu 24.04 base) |
| `Makefile` | Build automation: `make build-image`, `make offline-bundle`, `make test-image` |
| `chart/values.yaml` | Default Helm values with all configuration options |
| `chart/templates/_helpers.tpl` | Critical helper for image resolution, offline registry support, and CA bundle |
| `chart/templates/ca-secret.yaml` | Optional CA certificate secret for enterprise PKI |
| `scripts/import-ca-certs.sh` | Standalone CA certificate validation and import utility |

### Configuration Patterns
| File | Use Case |
|------|----------|
| `examples/values-online.yaml` | Internet-connected environments |
| `examples/values-offline.yaml` | Air-gapped with internal registry |
| `examples/values-mongodb.yaml` | Reusing existing service accounts |
| `examples/values-with-ca.yaml` | Custom CA certificate trust |

---

## Common Tasks

### Building the Image
```bash
# Build with auto-detected runtime (Docker or nerdctl)
make build-image

# Test the built image
make test-image

# Create complete offline bundle
make offline-bundle
```

### Deploying the Chart
```bash
# Online deployment
helm install my-toolbox ./chart \
  -f examples/values-online.yaml \
  -n toolbox --create-namespace

# Offline deployment
helm install my-toolbox ./chart \
  -f examples/values-offline.yaml \
  -n toolbox --create-namespace

# Access the pod
kubectl -n toolbox exec -it deploy/my-toolbox-ultimate-k8s-toolbox -- bash
```

### Testing
```bash
# Lint the chart
helm lint ./chart

# Template rendering test
helm template test ./chart -f examples/values-offline.yaml

# Run automated tests
./tests/test-helm-chart.sh
```

---

## Architecture Notes

### Image Resolution Logic
The `chart/templates/_helpers.tpl` contains the critical `ultimate-k8s-toolbox.image` helper that constructs image paths:

 
- **Online**: `image.repository:image.tag` → `ultimate-k8s-toolbox:v1.0.2`
- **Offline**: `global.imageRegistry/image.repository:image.tag` → `harbor.internal.com/platform/ultimate-k8s-toolbox:v1.0.2`

### Security Context
Default security settings in `values.yaml`:
- `runAsNonRoot: true`
- `runAsUser: 10000`
- `allowPrivilegeEscalation: false`
- `NET_ADMIN` and `NET_RAW` capabilities for network tools

### Custom CA Certificate Trust
Enterprise PKI support via `customCA` configuration:
- **Secret-based**: Mount CA certs from Kubernetes secret
- **Helm-managed**: Inline certificates in values.yaml
- **Auto-trust**: `update-ca-trust.sh` script updates system trust store

Configuration in `values.yaml`:
```yaml
customCA:
  enabled: true
  secretName: "toolbox-ca-certs"
  mountPath: /etc/ssl/custom-ca
  createSecret: false  # or true for Helm-managed
```

Deploy script flags:
```bash
./deploy-offline.sh --root-ca /path/to/root.crt --subordinate-ca /path/to/sub.crt
```

### SBOM with SHA256 Hashes
The SBOM generation includes cryptographic hashes for artifact verification:
- **image_digest**: Docker/nerdctl image digest (sha256)
- **tarball_hash**: SHA256 of exported image tarball
- **chart_hash**: SHA256 of packaged Helm chart

Verification:
```bash
# From SBOM.json
jq '.metadata.properties[] | select(.name=="tarball_hash")' SBOM.json
sha256sum images/*.tar
```

### Tool Versions (Dockerfile)
| Tool | Version |
|------|---------|
| mongosh | 2.3.7 |
| MongoDB Tools | 100.13.0 |
| kubectl | v1.31.4 |
| yq | v4.45.1 |
| tridentctl | 24.10.0 |
| Python | 3.12 |

---

## Development Guidelines

### Adding New Tools
1. Add installation to appropriate section in `build/Dockerfile`
2. Update `TOOLS-REFERENCE.md` with usage examples
3. Update SBOM generation in `Makefile` (`create-sbom` target)
4. Rebuild: `make build-image`

### Modifying Helm Templates
1. Test changes with `helm template test ./chart`
2. Run `helm lint ./chart`
3. Test all example values files
4. Update `tests/TEST-RESULTS.md` with validation results

### Documentation Updates
- `README.md` - Main features and configuration reference
- `INDEX.md` - Update navigation if adding new docs
- `QUICKSTART.md` - Keep commands current
- `QUICK-REFERENCE.md` - One-page cheat sheet

---

## Offline Bundle Contents

When running `make offline-bundle`, the output includes:

```
dist/offline-bundle/
├── images/
│   └── ultimate-k8s-toolbox-v1.0.2.tar   # Docker/OCI image
├── charts/
│   └── ultimate-k8s-toolbox-chart-1.0.2.tgz    # Packaged Helm chart
├── scripts/
│   ├── deploy-offline.sh                  # Deployment automation (with CA support)
│   └── import-ca-certs.sh                 # CA certificate import utility
├── docs/                                  # Documentation copies
├── SBOM.txt                               # Human-readable SBOM with SHA hashes
├── SBOM.json                              # CycloneDX JSON SBOM with SHA hashes
├── README.txt                             # Quick start guide
└── MANIFEST.txt                           # SHA256 checksums
```

---

## Troubleshooting

### Common Issues

**Image pull errors in offline environment:**
- Verify `global.imageRegistry` is set correctly
- Ensure `imagePullSecrets` references a valid secret
- Check image was pushed to internal registry

**Pod not starting:**
- Check security context compatibility with cluster policies
- Verify resource limits are appropriate
- Review events: `kubectl get events -n <namespace>`

**Tools not working inside pod:**
- Run `show-versions.sh` to verify installations
- Check if custom CA needs to be configured via `customCA` in values.yaml
- Run `/usr/local/bin/update-ca-trust.sh --verify` to check CA trust

**CA certificate trust issues:**
- Verify secret exists: `kubectl get secret toolbox-ca-certs -n <namespace>`
- Check if certs are mounted: `kubectl exec -it <pod> -- ls /etc/ssl/custom-ca/`
- Validate certificate: `openssl x509 -in /etc/ssl/custom-ca/root-ca.crt -text -noout`
- Run CA trust update: `/usr/local/bin/update-ca-trust.sh`

---

## Related Technologies

- **Helm 3**: Package manager for Kubernetes
- **nerdctl**: Docker-compatible CLI for containerd
- **containerd**: Kubernetes container runtime
- **MongoDB**: Database tools target
- **NetApp Trident**: Storage orchestration (tridentctl)

---

## Agent Instructions

When working on this repository:

1. **Before making changes**: Review relevant documentation files and understand the impact
2. **Helm changes**: Always test with `helm lint` and `helm template`
3. **Dockerfile changes**: Consider offline deployment implications
4. **Makefile changes**: Ensure all targets remain functional
5. **Documentation**: Keep docs in sync with code changes
6. **Testing**: Run `./tests/test-helm-chart.sh` after significant changes
7. **Versioning**: Update `Chart.yaml` version and `BUNDLE_VERSION` in Makefile when releasing

### Code Style
- Shell scripts: Use `set -e` and proper error handling
- YAML: 2-space indentation, descriptive comments
- Makefile: Document each target with comments
- Markdown: Follow existing formatting patterns
