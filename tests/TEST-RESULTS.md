# Deployment Test Results

## Current naming

The chart, image, labels, and generated deployment names now use `k8s-ultimate-toolbox`.

## Expected examples

```text
Chart name: k8s-ultimate-toolbox
Image: k8s-ultimate-toolbox:v1.2.0
Deployment: toolbox-test-k8s-ultimate-toolbox
ServiceAccount: toolbox-test-k8s-ultimate-toolbox
```

## Template checks

```bash
helm lint chart/
helm template toolbox-test chart/
helm template toolbox-test chart/ -f examples/values-online.yaml
helm template toolbox-test chart/ -f examples/values-offline.yaml
```

## Image path examples

```text
k8s-ultimate-toolbox:v1.2.0
myregistry.local:5000/platform/k8s-ultimate-toolbox:v1.2.0
harbor.internal.com/platform/k8s-ultimate-toolbox:v1.2.0
```
