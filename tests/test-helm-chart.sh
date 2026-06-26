#!/bin/bash
set -euo pipefail

helm lint ./chart
helm template test-render ./chart >/tmp/k8s-ultimate-toolbox-default-render.yaml

grep -q 'k8s-ultimate-toolbox' /tmp/k8s-ultimate-toolbox-default-render.yaml
grep -q 'SELinux/audit' /tmp/k8s-ultimate-toolbox-default-render.yaml
grep -q 'semanage' /tmp/k8s-ultimate-toolbox-default-render.yaml

echo 'K8s Ultimate Toolbox Helm smoke test passed.'
