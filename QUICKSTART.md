# Quick Start Guide - Ultimate K8s Toolbox

## 1. Online Deployment (5 minutes)

```bash
# Clone/download the chart
cd /path/to/charts

# Install with default values
helm install my-toolbox ./chart \
  --set image.repository=ubuntu \
  --set image.tag=24.04 \
  -n toolbox --create-namespace

# Wait for pod to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ultimate-k8s-toolbox \
  -n toolbox --timeout=300s

# Access the pod
kubectl exec -n toolbox -it deploy/my-toolbox-ultimate-k8s-toolbox -- bash
```

## 2. Offline Deployment (Quick)

```bash
# 1. Edit values-offline.yaml with your registry
vim values-offline.yaml

# 2. Create image pull secret (if needed)
kubectl create secret docker-registry regcred \
  --docker-server=myregistry.local:5000 \
  --docker-username=user \
  --docker-password=pass \
  -n toolbox --create-namespace

# 3. Deploy
helm install my-toolbox ./chart \
  -f values-offline.yaml \
  -n toolbox

# 4. Access
kubectl exec -n toolbox -it deploy/my-toolbox-ultimate-k8s-toolbox -- bash
```

## 3. Common Commands

```bash
# List deployments
helm list -n toolbox

# Get pod name
kubectl get pods -n toolbox

# Execute into pod
POD=$(kubectl get pod -n toolbox -l app.kubernetes.io/name=ultimate-k8s-toolbox -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n toolbox -it $POD -- bash

# View logs
kubectl logs -n toolbox -l app.kubernetes.io/name=ultimate-k8s-toolbox

# Upgrade
helm upgrade my-toolbox ./chart \
  --reuse-values \
  --set image.tag=v1.1.0 \
  -n toolbox

# Uninstall
helm uninstall my-toolbox -n toolbox
```

## 4. Configuration Examples

### Workspace Storage
By default, the toolbox mounts `/workspace` as an ephemeral `emptyDir` (non-persistent).
To persist `/workspace`, set a StorageClass and size to create a PVC:

```bash
helm install my-toolbox ./chart \
  --set workspace.storageClass=<your-storage-class> \
  --set workspace.size=20Gi \
  -n toolbox --create-namespace
```

### Using Existing Service Account
```bash
helm install my-toolbox ./chart \
  --set serviceAccount.create=false \
  --set serviceAccount.name=mongodb-operator \
  -n mongodb
```

### Custom Resources
```bash
helm install my-toolbox ./chart \
  --set resources.limits.cpu=4 \
  --set resources.limits.memory=8Gi \
  -n toolbox --create-namespace
```

### Multiple Replicas
```bash
helm install my-toolbox ./chart \
  --set replicaCount=3 \
  -n toolbox --create-namespace
```

## 5. Troubleshooting

```bash
# Check pod status
kubectl describe pod -n toolbox -l app.kubernetes.io/name=ultimate-k8s-toolbox

# View events
kubectl get events -n toolbox --sort-by='.lastTimestamp'

# Test template rendering
helm template test ./chart -f values-offline.yaml

# Validate chart
helm lint ./chart
```

## 6. Image Registry Configuration

| Scenario | global.imageRegistry | image.repository | Result |
|----------|---------------------|------------------|--------|
| Docker Hub | `""` | `ultimate-k8s-toolbox` | `ultimate-k8s-toolbox:tag` |
| Simple Registry | `registry.local:5000` | `ultimate-k8s-toolbox` | `registry.local:5000/ultimate-k8s-toolbox:tag` |
| With Project | `harbor.com` | `platform/toolbox` | `harbor.com/platform/toolbox:tag` |
| Full Path | `gcr.io/project` | `toolbox` | `gcr.io/project/toolbox:tag` |

## 7. Testing the Chart

```bash
# Run included test script
./test-helm-chart.sh

# Or manually:
helm lint ./chart
helm template test ./chart
helm install test ./chart -n test --dry-run
```

## 8. Offline Bundle Creation

```bash
# 1. Save image
docker save ultimate-k8s-toolbox:v1.0.2 -o toolbox.tar

# 2. Package chart
helm package ./chart

# 3. Create bundle
tar -czf offline-bundle.tar.gz toolbox.tar ultimate-k8s-toolbox-chart-*.tgz values-offline.yaml

# 4. Transfer to offline environment

# 5. In offline environment:
tar -xzf offline-bundle.tar.gz
docker load -i toolbox.tar
docker tag ultimate-k8s-toolbox:v1.0.2 myregistry:5000/toolbox:v1.0.2
docker push myregistry:5000/toolbox:v1.0.2
helm install my-toolbox ultimate-k8s-toolbox-chart-*.tgz -f values-offline.yaml -n toolbox
```

## 9. Values File Examples

All example values files are included:
- `values.yaml` - Default configuration with all options
- `values-online.yaml` - Internet-connected deployment
- `values-offline.yaml` - Air-gapped deployment template
- `values-mongodb.yaml` - MongoDB namespace example

## 10. Getting Help

```bash
# View all chart values
helm show values ./chart

# View chart information
helm show chart ./chart

# View README
helm show readme ./chart

# Get deployed values
helm get values my-toolbox -n toolbox
```

---

For detailed information, see:
- `README.md` - Complete documentation
- `OFFLINE-DEPLOYMENT.md` - Detailed offline deployment guide
- `values.yaml` - All configuration options with comments
