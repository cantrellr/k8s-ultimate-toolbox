# Quick Start - K8s Ultimate Toolbox

This guide gets the v1.2.0 toolbox running and validates the Kubernetes, runtime, Keycloak, MongoDB, PostgreSQL, RBAC, policy, CNI, SELinux, and audit tooling.

## 1. Deploy online

```bash
git clone https://github.com/cantrellr/k8s-ultimate-toolbox.git
cd k8s-ultimate-toolbox

helm upgrade --install toolbox ./chart \
  -n toolbox --create-namespace

kubectl wait --for=condition=available deploy/toolbox-k8s-ultimate-toolbox \
  -n toolbox --timeout=300s

kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
```

Inside the pod:

```bash
show-versions.sh
```

## 2. Validate v1.2.0 additions

```bash
command -v crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl
command -v getenforce sestatus semanage semodule seinfo sesearch checkpolicy checkmodule audit2allow audit2why ausearch aureport
```

## 3. Deploy with persistent workspace

Use this when you want to keep generated reports, exported manifests, PostgreSQL log reports, snapshots, or packet captures.

```bash
helm upgrade --install toolbox ./chart \
  -n toolbox --create-namespace \
  --set workspace.storageClass=<storage-class> \
  --set workspace.size=20Gi
```

## 4. Deploy with internal CA certificates

```bash
kubectl create namespace toolbox --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic toolbox-ca-certs \
  --from-file=root-ca.crt=/path/to/root-ca.crt \
  --from-file=subordinate-ca.crt=/path/to/subordinate-ca.crt \
  -n toolbox

helm upgrade --install toolbox ./chart \
  -n toolbox \
  --set customCA.enabled=true \
  --set customCA.secretName=toolbox-ca-certs
```

Validate from inside the pod:

```bash
update-ca-trust.sh --list
curl -Iv https://internal-service.example.com
```

## 5. Runtime and control-plane diagnostics

```bash
crictl ps -a
crictl images
etcdctl endpoint health --cluster
etcdutl snapshot status /workspace/snapshot.db
```

## 6. Certificate and PKI diagnostics

```bash
cmctl check api
cmctl status certificate <certificate-name> -n <namespace>
step certificate inspect /path/to/cert.crt --short
```

## 7. RBAC, policy, and upgrade diagnostics

```bash
kubent
kubeconform -summary rendered.yaml
popeye
kubectl-who-can get pods -A
rbac-lookup system:serviceaccount:default:default
```

## 8. SELinux and audit diagnostics

```bash
getenforce
sestatus
semanage boolean -l
semodule -l
seinfo
sesearch --allow -s container_t 2>/dev/null | head
audit2allow --help
audit2why --help
ausearch --help
aureport --help
```

## 9. CNI diagnostics

Use these only where the matching CNI exists in the target cluster.

```bash
cilium status
hubble status
calicoctl get ippools
```

## 10. Build a SELinux utilities air-gap tarball

Run this on an internet-connected Ubuntu/Debian host that matches the target release and architecture:

```bash
make selinux-bundle
```

Copy `dist/selinux-utils-bundle/*.tar.gz` to the air-gapped target, then:

```bash
tar -xzf selinux-utils-*.tar.gz
./install-selinux-utils.sh
```

## 11. Keycloak usage

The default toolbox container includes `kcadm.sh`, `kcreg.sh`, `kc.sh`, and `keycloak-login.sh`. No sidecar is needed.

```bash
kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
keycloak-login.sh
kcadm.sh get realms
```

## 12. PostgreSQL diagnostics

Set the PostgreSQL host, port, database, and user in your shell. Source credentials from your approved secret workflow instead of typing them into shared shell history.

```bash
kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
pg_isready
pg-diagnostics.sh
```

## 13. MongoDB diagnostics

```bash
mongosh "$MONGODB_URI"
mongostat --uri "$MONGODB_URI" --rowcount 5
mongotop --uri "$MONGODB_URI" 5
mongodump --uri "$MONGODB_URI" --archive=/workspace/mongodb.archive --gzip
```

## 14. Build and test the image

```bash
make info
make build-image
make test-image
```

## 15. Offline bundle

On an internet-connected build host:

```bash
make offline-bundle
```

Transfer `dist/k8s-ultimate-toolbox-offline-v1.2.0.tar.gz` to the offline environment, extract it, load/push the image to the internal registry, then install the packaged chart.

```bash
tar -xzf k8s-ultimate-toolbox-offline-v1.2.0.tar.gz
cd offline-bundle
cat SBOM.txt
```

## 16. Common operations

```bash
helm list -n toolbox
kubectl get pods -n toolbox
kubectl logs -n toolbox -l app.kubernetes.io/name=k8s-ultimate-toolbox
kubectl describe pod -n toolbox -l app.kubernetes.io/name=k8s-ultimate-toolbox
kubectl get events -n toolbox --sort-by='.lastTimestamp'
helm get values toolbox -n toolbox
helm upgrade toolbox ./chart --reuse-values -n toolbox
helm uninstall toolbox -n toolbox
```

Hard truth: most failures here are image pull paths, missing registry credentials, insufficient RBAC, or clusters blocking `NET_ADMIN`/`NET_RAW` through Pod Security Admission. Check those first before chasing ghosts.
