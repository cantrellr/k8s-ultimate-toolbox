# Tests

Tests and validation notes for the K8s Ultimate Toolbox Helm chart.

## Quick checks

```bash
helm lint chart/
helm template test-release chart/ -f examples/values-online.yaml
helm template test-release chart/ -f examples/values-offline.yaml
```

## Test script

```bash
cd tests
./test-helm-chart.sh
```

## Deployment name

The default test deployment name now follows the renamed chart:

```text
toolbox-test-k8s-ultimate-toolbox
```
