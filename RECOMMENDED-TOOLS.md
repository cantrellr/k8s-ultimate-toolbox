# Recommended Future Tools

The v1.1.0 release covers Kubernetes, Helm, Keycloak, MongoDB, PostgreSQL, network, TLS, and storage triage. The following tools are recommended next, prioritized by operational value.

## High-priority additions

| Tool | Priority | Why it should be added |
|---|---:|---|
| `crictl` | High | Direct CRI inspection when Kubernetes says a pod is broken but the runtime has the real answer |
| `ctr` | High | Low-level containerd inspection for air-gapped and RKE2-style environments |
| `etcdctl` / `etcdutl` | High | Control-plane health, snapshots, and disaster-recovery inspection |
| `cmctl` | High | cert-manager certificate, issuer, and challenge troubleshooting |
| `step` CLI | High | X.509, JWKS, OIDC, JWT, and internal PKI diagnostics |
| `kubent` | High | Detect deprecated Kubernetes APIs before upgrades break workloads |
| `kubeconform` | High | Fast schema validation for manifests and rendered Helm output |
| `kubectl-who-can` | High | RBAC troubleshooting and authorization blast-radius inspection |
| `rbac-lookup` | High | Find which users, groups, and service accounts have specific permissions |

## Medium-priority additions

| Tool | Priority | Why it should be added |
|---|---:|---|
| `popeye` | Medium | Cluster hygiene scans; good for platform readiness and cleanup work |
| `kubectl-neat` | Medium | Strips noisy runtime fields from manifests for clean diffs and handoffs |
| `kubectl-tree` | Medium | Visualizes object ownership chains during cleanup and incident response |
| `oras` | Medium | OCI artifact inspection and registry operations beyond container images |
| `skopeo` | Medium | Registry copy/inspect workflows without requiring a daemon |
| `cosign` | Medium | Image signature verification and supply-chain attestation workflows |
| `regctl` | Medium | Registry querying, tag discovery, digest inspection, and image promotion |
| `stern` | Medium | Multi-pod log tailing; high convenience, low risk |
| `k9s` | Medium | Fast terminal UI for operators who prefer interactive cluster navigation |

## Conditional additions

| Tool | Add when... |
|---|---|
| `cilium` and `hubble` | Clusters use Cilium or Hubble Relay |
| `calicoctl` | Clusters use Calico networking or Calico policy |
| `istioctl` | Istio is deployed or being evaluated |
| `linkerd` | Linkerd is deployed or being evaluated |
| `argocd` | Argo CD is part of the delivery plane |
| `flux` | Flux CD is part of the delivery plane |
| `velero` | Velero is the backup/restore standard |
| `mc` | MinIO or S3-compatible object storage is common in the environment |
| `rclone` | Cross-provider object/file movement is a recurring operational need |
| `restic` | File-level backup and recovery testing is needed from the toolbox |

## Tools to avoid by default

Do not add tools just because they are popular. Avoid default inclusion when a tool is highly vendor-specific, requires heavyweight runtimes, duplicates existing capability, cannot be pinned cleanly, or materially increases image attack surface without a strong incident-response use case.

## Recommended implementation roadmap

### v1.2.0 - Runtime and cluster-upgrade diagnostics

Add `crictl`, `ctr`, `etcdctl`, `etcdutl`, `kubent`, and `kubeconform`.

### v1.3.0 - Certificate, policy, and RBAC diagnostics

Add `cmctl`, `step`, `kubectl-who-can`, `rbac-lookup`, `opa`, and `conftest`.

### v1.4.0 - Registry and supply-chain workflows

Add `oras`, `skopeo`, `cosign`, `regctl`, and stronger SBOM generation with `syft`.

### Environment-specific profiles

Keep CNI, service mesh, and GitOps CLIs profile-driven instead of forcing them into every image. For example:

- `profile.cilium=true`
- `profile.calico=true`
- `profile.istio=true`
- `profile.argocd=true`

That keeps the default image useful without turning it into a bloated artifact landfill.
