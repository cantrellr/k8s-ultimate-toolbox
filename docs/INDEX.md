# 📚 K8s Ultimate Toolbox - Documentation Index

**v1.2.0 Platform Diagnostics Release**

> Kubernetes administration workstation tooling for cluster, identity, database, runtime, control-plane, certificate, policy, SELinux, audit, CNI, network, storage, and air-gapped troubleshooting.

## Core documentation

| Document | Description | When to use |
|----------|-------------|-------------|
| [README.md](../README.md) | Main project overview, architecture, and release highlights | Start here |
| [QUICKSTART.md](../QUICKSTART.md) | Fast deployment and validation guide | Get running fast |
| [TOOLS-REFERENCE.md](../TOOLS-REFERENCE.md) | Current tool inventory and version matrix | Confirm what is installed |
| [SELINUX-UTILITIES.md](../SELINUX-UTILITIES.md) | SELinux/audit tooling and offline package bundle guide | Build or install SELinux utilities in air-gapped environments |
| [POSTGRESQL-DIAGNOSTICS.md](../POSTGRESQL-DIAGNOSTICS.md) | PostgreSQL troubleshooting runbook | Triage PostgreSQL issues |
| [KEYCLOAK-GUIDE.md](../KEYCLOAK-GUIDE.md) | Keycloak CLI usage in the default toolbox container | Work with Keycloak |
| [RECOMMENDED-TOOLS.md](../RECOMMENDED-TOOLS.md) | Implemented and future tooling roadmap | Plan the next capability bump |
| [CHANGELOG.md](../CHANGELOG.md) | Version history and release notes | See what changed |

## Deployment and build guides

| Document | Description | When to use |
|----------|-------------|-------------|
| [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md) | Air-gapped bundle workflow | No internet access or controlled registry imports |
| [NERDCTL-GUIDE.md](NERDCTL-GUIDE.md) | Container runtime guidance | Build or load images with containerd/nerdctl |
| [MAKEFILE.md](../MAKEFILE.md) | Build system notes | Automation and packaging tasks |
| [SBOM.md](../SBOM.md) | SBOM and supply-chain notes | Security review and compliance evidence |

## Quick start

```bash
helm upgrade --install toolbox ./chart -n toolbox --create-namespace
kubectl wait --for=condition=available deploy/toolbox-k8s-ultimate-toolbox -n toolbox --timeout=300s
kubectl exec -it -n toolbox deploy/toolbox-k8s-ultimate-toolbox -- bash
show-versions.sh
```

## SELinux air-gap bundle

```bash
make selinux-bundle
```

## Key configuration options

```yaml
image:
  repository: "k8s-ultimate-toolbox"
  tag: "v1.2.0"
```

## Getting help

1. **Quick questions** → [QUICKSTART.md](../QUICKSTART.md)
2. **Tool inventory** → [TOOLS-REFERENCE.md](../TOOLS-REFERENCE.md)
3. **Offline deployment** → [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md)
4. **Build issues** → [MAKEFILE.md](../MAKEFILE.md)
5. **Bug reports** → [GitHub Issues](https://github.com/cantrellr/k8s-ultimate-toolbox/issues)

---

*Platform Diagnostics Release - v1.2.0*
