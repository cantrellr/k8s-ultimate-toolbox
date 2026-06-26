# Tools Reference - K8s Ultimate Toolbox v1.2.0

## Pinned and package-managed tools

| Tool | Version / Source |
|---|---:|
| kubectl | v1.36.1 |
| helm | v4.2.1 |
| yq | v4.53.3 |
| Keycloak CLI | 26.6.3 |
| mongosh | 2.8.3 |
| MongoDB Database Tools | 100.17.0 |
| PostgreSQL client stack | Ubuntu 24.04 packages |
| tridentctl | 26.02.0 |
| crictl | v1.36.0 |
| etcdctl | v3.6.12 |
| etcdutl | v3.6.12 |
| cmctl | v2.2.0 |
| step | v0.30.2 |
| kubent | 0.7.3 |
| kubeconform | v0.8.0 |
| popeye | v0.22.1 |
| kubectl-who-can | v0.4.0 |
| rbac-lookup | v0.10.3 |
| cilium | v0.19.2 |
| hubble | v1.18.6 |
| calicoctl | v3.32.0 |
| SELinux utilities | Ubuntu 24.04 packages |
| audit utilities | Ubuntu 24.04 packages |

## Tool groups

| Group | Tools |
|---|---|
| Kubernetes | kubectl, helm, yq, jq |
| Runtime | crictl |
| Control plane | etcdctl, etcdutl |
| Certificates | cmctl, step, openssl, certtool |
| Upgrade and validation | kubent, kubeconform, popeye |
| Access review | kubectl-who-can, rbac-lookup |
| SELinux / audit | getenforce, sestatus, semanage, semodule, seinfo, sesearch, checkpolicy, checkmodule, audit2allow, audit2why, ausearch, aureport |
| CNI | cilium, hubble, calicoctl |
| Identity | kcadm.sh, kcreg.sh, kc.sh, keycloak-login.sh |
| Databases | PostgreSQL tools, MongoDB tools, MySQL client, Redis CLI |
| Network and storage | curl, dig, nc, nmap, tcpdump, tridentctl, nfs-common, rsync |

## SELinux air-gap bundle

Use `make selinux-bundle` to create a tarball containing SELinux utility `.deb` packages and dependencies for an air-gapped host. The generated tarball includes `install-selinux-utils.sh`, `README.md`, `manifest.txt`, `SHA256SUMS`, and the downloaded packages.

## Helpers

| Helper | Purpose |
|---|---|
| show-versions.sh | Installed tool summary |
| pg-diagnostics.sh | PostgreSQL triage |
| keycloak-login.sh | Keycloak CLI authentication helper |
| update-ca-trust.sh | Custom CA trust helper |
| scripts/build-selinux-utils-bundle.sh | Build host-installable SELinux utilities tarball |
