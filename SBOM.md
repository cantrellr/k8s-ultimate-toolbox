# SBOM and Supply Chain Notes

K8s Ultimate Toolbox v1.2.0 generates a lightweight SBOM during `make offline-bundle`.

## Generated files

| File | Purpose |
|---|---|
| `SBOM.txt` | Human-readable component summary |
| `images/*.sha256` | SHA256 checksum for exported image tarball |
| `dist/selinux-utils-bundle/*.tar.gz` | Optional host-installable SELinux utilities and dependency tarball |

## Pinned components

The build pins the external binary components that are downloaded directly during the image build:

- `kubectl v1.36.1`
- `Helm v4.2.1`
- `yq v4.53.3`
- `Keycloak 26.6.3`
- `mongosh 2.8.3`
- `MongoDB Database Tools 100.17.0`
- `tridentctl 26.02.0`
- `crictl v1.36.0`
- `etcdctl/etcdutl v3.6.12`
- `cmctl v2.2.0`
- `step v0.30.2`
- `kubent 0.7.3`
- `kubeconform v0.8.0`
- `popeye v0.22.1`
- `kubectl-who-can v0.4.0`
- `rbac-lookup v0.10.3`
- `cilium v0.19.2`
- `hubble v1.18.6`
- `calicoctl v3.32.0`
- `nerdctl 2.3.2` for build-host fallback workflows

The remaining Linux packages are sourced from Ubuntu 24.04 package repositories. That package-managed set now includes SELinux and audit utilities such as `selinux-utils`, `policycoreutils`, `policycoreutils-python-utils`, `semanage-utils`, `semodule-utils`, `checkpolicy`, `setools`, and `auditd`.

## SELinux offline package bundle

`make selinux-bundle` creates a separate `.deb` bundle for installing SELinux utilities on an air-gapped Ubuntu/Debian host. The bundle includes package files, `SHA256SUMS`, a manifest, README, and an installer script.

## Recommended hardening

For production supply-chain governance, add these next:

1. Generate a full image SBOM with `syft`.
2. Scan the image with `grype` or Trivy.
3. Sign the image with `cosign`.
4. Publish checksums for the Helm chart and image tarball.
5. Store the offline bundle in an immutable artifact repository.
6. Record the exact base image digest instead of relying only on `ubuntu:24.04`.

The current SBOM is useful for air-gap handoff and operator visibility. It is not a replacement for enterprise-grade artifact attestation.
