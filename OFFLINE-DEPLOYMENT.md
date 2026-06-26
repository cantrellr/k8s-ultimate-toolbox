# Offline Deployment Guide

This guide covers building and deploying K8s Ultimate Toolbox v1.2.0 in an air-gapped or registry-isolated environment.

## Build host requirements

The build host needs internet access and the following tools:

- Docker or nerdctl/containerd
- Helm
- curl
- GNU make

Validate:

```bash
make info
```

## Build the offline toolbox bundle

```bash
make offline-bundle
```

Expected output:

```text
dist/k8s-ultimate-toolbox-offline-v1.2.0.tar.gz
```

The bundle contains a packaged Helm chart, image tarball, image checksum, deployment helper script, SBOM text summary, and documentation.

## Build the SELinux utilities host bundle

When you also need SELinux utilities installed directly on an air-gapped Ubuntu/Debian host, build the separate `.deb` dependency tarball from a matching internet-connected system:

```bash
make selinux-bundle
```

Expected output:

```text
dist/selinux-utils-bundle/*.tar.gz
```

Copy that tarball to the target host, extract it, and run:

```bash
tar -xzf selinux-utils-*.tar.gz
./install-selinux-utils.sh
```

## Transfer toolbox bundle to offline environment

```bash
scp dist/k8s-ultimate-toolbox-offline-v1.2.0.tar.gz user@offline-host:/tmp/
```

On the offline host:

```bash
cd /tmp
tar -xzf k8s-ultimate-toolbox-offline-v1.2.0.tar.gz
cd offline-bundle
sha256sum -c images/k8s-ultimate-toolbox-v1.2.0.tar.sha256
```

## Deploy with the helper script

```bash
cd offline-bundle/scripts
./deploy-offline.sh \
  --registry kuberegistry.k8.cantrellcloud.net:8443/library \
  --namespace toolbox \
  --release-name toolbox
```

## Manual deployment path

```bash
docker load -i images/k8s-ultimate-toolbox-v1.2.0.tar
docker tag k8s-ultimate-toolbox:v1.2.0 kuberegistry.k8.cantrellcloud.net:8443/library/k8s-ultimate-toolbox:v1.2.0
docker push kuberegistry.k8.cantrellcloud.net:8443/library/k8s-ultimate-toolbox:v1.2.0

helm upgrade --install toolbox charts/k8s-ultimate-toolbox-chart-1.2.0.tgz \
  -n toolbox --create-namespace \
  --set global.imageRegistry=kuberegistry.k8.cantrellcloud.net:8443/library \
  --set image.repository=k8s-ultimate-toolbox \
  --set image.tag=v1.2.0
```

## Validate deployment

```bash
kubectl -n toolbox get deploy,pods
kubectl -n toolbox rollout status deploy/toolbox-k8s-ultimate-toolbox --timeout=300s
kubectl -n toolbox exec -it deploy/toolbox-k8s-ultimate-toolbox -- bash
show-versions.sh
command -v crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl
command -v getenforce sestatus semanage semodule seinfo sesearch checkpolicy checkmodule audit2allow audit2why ausearch aureport
```

## Notes

The v1.2.0 image is larger than v1.1.0 because it now includes runtime, control-plane, certificate, upgrade, access-review, CNI, SELinux, and audit diagnostic tools. That is intentional; the value is fewer ad-hoc debug containers during incidents.
