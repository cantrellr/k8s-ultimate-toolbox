# Offline Deployment Guide

This guide covers building and deploying Ultimate K8s Toolbox v1.1.0 in an air-gapped or registry-isolated environment.

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
dist/ultimate-k8s-toolbox-offline-v1.1.0.tar.gz
```

The bundle contains:

```text
offline-bundle/
├── charts/
│   └── ultimate-k8s-toolbox-chart-1.1.0.tgz
├── docs/
├── images/
│   ├── ultimate-k8s-toolbox-v1.1.0.tar
│   └── ultimate-k8s-toolbox-v1.1.0.tar.sha256
├── scripts/
│   └── deploy-offline.sh
├── README.txt
├── SBOM.txt
└── SBOM.json
```

## Transfer to offline environment

```bash
scp dist/ultimate-k8s-toolbox-offline-v1.1.0.tar.gz user@offline-host:/tmp/
```

On the offline host:

```bash
cd /tmp
tar -xzf ultimate-k8s-toolbox-offline-v1.1.0.tar.gz
cd offline-bundle
sha256sum -c images/ultimate-k8s-toolbox-v1.1.0.tar.sha256
```

## Deploy with the helper script

```bash
cd offline-bundle/scripts
./deploy-offline.sh \
  --registry kuberegistry.k8.cantrellcloud.net:8443/library \
  --namespace toolbox \
  --release-name toolbox
```

With internal CA certificates:

```bash
./deploy-offline.sh \
  --registry kuberegistry.k8.cantrellcloud.net:8443/library \
  --namespace toolbox \
  --release-name toolbox \
  --root-ca /certs/root-ca.crt \
  --subordinate-ca /certs/subordinate-ca.crt
```

If the image was already pushed to the registry:

```bash
./deploy-offline.sh \
  --registry kuberegistry.k8.cantrellcloud.net:8443/library \
  --skip-registry-push
```

## Manual deployment path

Load and push image:

```bash
docker load -i images/ultimate-k8s-toolbox-v1.1.0.tar
docker tag ultimate-k8s-toolbox:v1.1.0 kuberegistry.k8.cantrellcloud.net:8443/library/ultimate-k8s-toolbox:v1.1.0
docker push kuberegistry.k8.cantrellcloud.net:8443/library/ultimate-k8s-toolbox:v1.1.0
```

Install chart:

```bash
helm upgrade --install toolbox charts/ultimate-k8s-toolbox-chart-1.1.0.tgz \
  -n toolbox --create-namespace \
  --set global.imageRegistry=kuberegistry.k8.cantrellcloud.net:8443/library \
  --set image.repository=ultimate-k8s-toolbox \
  --set image.tag=v1.1.0
```

## Validate deployment

```bash
kubectl -n toolbox get deploy,pods
kubectl -n toolbox rollout status deploy/toolbox-ultimate-k8s-toolbox --timeout=300s
kubectl -n toolbox exec -it deploy/toolbox-ultimate-k8s-toolbox -- bash
show-versions.sh
```

## Common failure points

| Failure | Cause | Fix |
|---|---|---|
| `ImagePullBackOff` | Wrong registry path, missing project, or auth failure | Verify `global.imageRegistry`, image tag, and pull secret |
| TLS error pulling image | Worker nodes do not trust registry CA | Add registry CA to node trust store/container runtime |
| Pod rejected by admission | Namespace policy blocks `NET_ADMIN` or `NET_RAW` | Deploy to an approved ops namespace or remove capabilities if packet tools are not required |
| CA trust not working inside toolbox | CA secret missing or wrong keys | Enable `customCA.enabled` and verify secret contents |
| Keycloak login fails | DNS, TLS, realm, or credential issue | Use `KEYCLOAK-GUIDE.md` workflow |
| PostgreSQL diagnostics fail | Missing network route, wrong credentials, or TLS enforcement | Use `POSTGRESQL-DIAGNOSTICS.md` first-response checklist |
