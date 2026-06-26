#!/bin/bash
# Example deployment commands for common K8s Ultimate Toolbox scenarios.

set -euo pipefail

cat <<'HEADER'
============================================
K8s Ultimate Toolbox Deployment Examples
============================================
HEADER

echo ""
echo "Scenario 1: Quick online deployment"
echo "-----------------------------------"
cat <<'CMD'
helm upgrade --install toolbox ../chart \
  -n toolbox --create-namespace

kubectl wait --for=condition=available deploy/toolbox-k8s-ultimate-toolbox \
  -n toolbox --timeout=300s

kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
CMD

echo ""
echo "Scenario 2: Validate built-in tools"
echo "-----------------------------------"
cat <<'CMD'
kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
show-versions.sh
command -v crictl etcdctl etcdutl cmctl step kubent kubeconform popeye kubectl-who-can rbac-lookup cilium hubble calicoctl
CMD

echo ""
echo "Scenario 3: Offline registry values"
echo "-----------------------------------"
cat <<'CMD'
helm upgrade --install toolbox ../chart \
  --set global.imageRegistry="registry.example.com/library" \
  --set image.repository="k8s-ultimate-toolbox" \
  --set image.tag="v1.2.0" \
  -n toolbox --create-namespace
CMD

echo ""
echo "Scenario 4: Generated offline bundle helper"
echo "-------------------------------------------"
cat <<'CMD'
make offline-bundle

tar -xzf dist/k8s-ultimate-toolbox-offline-v1.2.0.tar.gz
cd offline-bundle/scripts

./deploy-offline.sh \
  --registry registry.example.com/library \
  --namespace toolbox \
  --release-name toolbox
CMD

echo ""
echo "Scenario 5: Package and install from chart archive"
echo "--------------------------------------------------"
cat <<'CMD'
helm package ../chart -d /tmp
helm upgrade --install toolbox /tmp/k8s-ultimate-toolbox-1.2.0.tgz \
  -n toolbox --create-namespace
CMD

echo ""
echo "Common management commands"
echo "--------------------------"
cat <<'CMD'
helm status toolbox -n toolbox
kubectl get pods -n toolbox
kubectl logs -n toolbox deploy/toolbox-k8s-ultimate-toolbox
kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
helm uninstall toolbox -n toolbox
CMD
