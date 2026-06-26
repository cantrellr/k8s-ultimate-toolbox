# Recommended Tools Roadmap

The original high-priority recommendations have been implemented in v1.2.0. SELinux and audit utilities were also added for hardened Linux, RHEL-family, OpenShift-adjacent, and policy troubleshooting workflows.

## Implemented in v1.2.0

| Area | Tools |
|---|---|
| Runtime inspection | `crictl` |
| Control-plane recovery | `etcdctl`, `etcdutl` |
| Certificate operations | `cmctl`, `step` |
| Upgrade and schema checks | `kubent`, `kubeconform` |
| Cluster hygiene | `popeye` |
| Access review | `kubectl-who-can`, `rbac-lookup` |
| CNI diagnostics | `cilium`, `hubble`, `calicoctl` |
| SELinux / audit | `getenforce`, `sestatus`, `semanage`, `semodule`, `seinfo`, `sesearch`, `checkpolicy`, `checkmodule`, `audit2allow`, `audit2why`, `ausearch`, `aureport` |
| Air-gapped host utilities | `scripts/build-selinux-utils-bundle.sh` creates a `.deb` dependency tarball for offline targets |

## Still recommended for future releases

| Area | Candidate tools |
|---|---|
| Registry and OCI workflows | `oras`, `skopeo`, `regctl` |
| Supply-chain verification | `cosign`, `syft`, `grype` |
| Log inspection | `stern` |
| Manifest cleanup | `kubectl-neat`, `kubectl-tree` |
| Interactive navigation | `k9s` |
| Service mesh | `istioctl`, `linkerd` |
| GitOps | `argocd`, `flux` |
| Backup and restore | `velero`, `restic` |
| Object storage | `mc`, `rclone` |

## Selection rule

Do not add tools just because they are popular. Default image additions must reduce time-to-evidence during incidents, support air-gapped operations, or close a real operational gap without turning the image into a bloated artifact landfill.
