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
make check-dependencies
make info
```

## Build the offline bundle

```bash
make offline-bundle
```

Expected output:

```text
dist/ultimate-k8s-toolbox-offline-v1.2.0.tar.gz
```

The bundle contains a packaged Helm chart, image tarball, image checksum, deployment helper script, SBOM text summary, and documentation.

## Transfer to offline environment

```bash
scp dist/ultimate-k8s-toolbox-offline-v1.2.0.tar.gz user@offline-host:/tmp/
```

On the offline host:

```bash
cd /tmp
tar -xzf ultimate-k8s-toolbox-offline-v1.2.0.tar.gz
cd offline-bundle
sha256sum -c images/ultimate-k8s-toolbox-v1.2.0.tar.sha256
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
docker load -i images/ultimate-k8s-toolbox-v1.2.0.tar
docker tag ultimate-k8s-toolbox:v1.2.0 kuberegistry.k8.cantrellcloud.net:8443/library/ultimate-k8s-toolbox:v1.2.0
docker push kuberegistry.k8.cantrellcloud.net:8443/library/ultimate-k8s-toolbox:v1.2.0

helm upgrade --install toolbox charts/ultimate-k8s-toolbox-chart-1.2.0.tgz \
  -n toolbox --create-namespace \
  --set global.imageRegistry=kuberegistry.k8.cantrellcloud.net:8443/library \
  --set image.repository=ultimate-k8s-toolbox \
  --set image.tag=v1.2.0
```

## Validate deployment

```bash
kubectl -n toolbox get deploy,pods
kubectl -n toolbox rollout status deploy/toolbox-ultimate-k8s-toolbox --timeout=300s
kubectl -n toolbox exec -it deploy/toolbox-ultimate-k8s-toolbox -- bash
show-versions.sh
command -v crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl
```

## Notes

The v1.2.0 image is larger than v1.1.0 because it now includes runtime, control-plane, certificate, upgrade, access-review, and CNI diagnostic tools. That is intentional; the value is fewer ad-hoc debug containers during incidents.
