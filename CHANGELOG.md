# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-03-07

### Added

- Keycloak CLI support in toolbox image: `kcadm.sh`, `kcreg.sh`, and `kc.sh`
- Java runtime (`openjdk-21-jre-headless`) required by Keycloak CLI tools
- Keycloak tooling references and quick examples in `README.md`, `QUICK-REFERENCE.md`, and `TOOLS-REFERENCE.md`

### Fixed

- Dockerfile heredoc terminator for the embedded CA trust update script

### Changed

- Release and chart version references updated to `v1.0.2` / `1.0.2`
- Helm chart default security context aligned to the image UID/GID (run as UID 10000)

## [1.0.0] - 2025-11-26 - "First Flight" 🛫

> *"The moment you doubt whether you can fly, you cease forever to be able to do it."* — J.M. Barrie

This is the first public release of Ultimate K8s Toolbox, codenamed **"First Flight"** — honoring the spirit of aviation pioneers who dared to leave the ground and explore new horizons.

### ✈️ Highlights

- **50+ pre-installed tools** for Kubernetes administration
- **Full air-gapped/offline deployment support** with comprehensive documentation
- **Multi-architecture support** (amd64, arm64)
- **Helm chart** with extensive customization options
- **SBOM (Software Bill of Materials)** generation for security compliance
- **Custom CA certificate support** via init container architecture

### Added

#### Container Image
- Base image: Ubuntu 24.04 LTS (Noble Numbat)
- **Kubernetes Tools**: kubectl, helm, k9s, kubectx/kubens, stern, kustomize, k3d, kind
- **Cloud CLI Tools**: AWS CLI v2, Azure CLI, Google Cloud SDK
- **Network Tools**: curl, wget, netcat, nmap, tcpdump, dig, host, traceroute, mtr, iperf3
- **Database Clients**: PostgreSQL, MySQL, MongoDB, Redis CLI
- **Development Tools**: git, vim, nano, jq, yq, fzf, bat, ripgrep, fd-find
- **Security Tools**: trivy, grype, syft (SBOM generation)
- **Monitoring Tools**: promtool, amtool
- **Storage Tools**: rclone, mc (MinIO client), restic
- **Service Mesh**: istioctl, linkerd

#### Helm Chart
- Deployment with configurable replicas
- ServiceAccount with optional RBAC (ClusterRole/Role)
- Custom CA certificate injection via init container
- Host aliases for custom /etc/hosts entries
- Resource limits and requests configuration
- Security context with non-root user by default
- Persistent storage support
- Node selector, tolerations, and affinity rules

#### Documentation
- Comprehensive README with architecture diagrams
- Quick-start guide for immediate deployment
- Detailed offline deployment documentation
- Tools reference with usage examples
- Makefile documentation
- SBOM and security documentation
- nerdctl/containerd guide for air-gapped environments

#### Build System
- Multi-stage Dockerfile optimized for size
- Makefile with targets for build, push, test, and release
- Multi-architecture build support (amd64, arm64)
- Automated SBOM generation with Syft
- Offline bundle creation with all dependencies

#### Scripts
- `deploy-offline.sh.template` - Automated offline deployment
- `import-ca-certs.sh` - CA certificate management
- `install-toolbox.sh` - CLI helper installation
- `toolbox` - Quick exec into running pod

#### Examples
- Online deployment values
- Offline/air-gapped deployment values
- Custom CA certificate configuration
- CoreDNS custom forwarding
- Host aliases patching

### Security

- Non-root container execution by default (UID 1000)
- Read-only root filesystem support (where tools allow)
- No privilege escalation by default
- RBAC with minimal required permissions
- SBOM for supply chain security
- Security policy (SECURITY.md) for vulnerability reporting

### Known Issues

- Some tools (dig, nslookup) may show permission errors due to non-root execution; functionality is not affected
- `tcpdump` and `nmap` require `CAP_NET_RAW` capability if packet capture is needed

### Migration Notes

This is the first public release. No migration required.

---

## Release Naming Convention

Ultimate K8s Toolbox releases are named after aviation milestones and concepts, reflecting the project maintainer's passion for general aviation:

| Version | Codename | Inspiration |
|---------|----------|-------------|
| 1.0.0 | First Flight | The Wright Brothers' historic achievement at Kitty Hawk |
| 1.1.0 | *TBD* | *Future release* |
| 1.2.0 | *TBD* | *Future release* |

Future release names may include: *Crosswind*, *Clear Skies*, *Final Approach*, *Tailwind*, *Airborne*, *Blue Yonder*, *Ceiling Unlimited*, *Dead Reckoning*, *Ground Effect*, *Hangar Flying*, *Instrument Rating*, *Jetstream*, *Knots*, *Lift Off*, *Mach Speed*, *Night VFR*, *Oscar Pattern*, *Pilot in Command*, *Quiet Flight*, *Roger That*, *Solo*, *Touch and Go*, *Unicom*, *Vector*, *Waypoint*, *X-Wind*, *Yankee Departure*, *Zulu Time*.

---

*Per aspera ad astra* — Through hardships to the stars ✈️
