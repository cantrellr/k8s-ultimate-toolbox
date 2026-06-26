#!/bin/bash
# Example deployment commands for common K8s Ultimate Toolbox scenarios.
# These examples intentionally use placeholders. Do not paste real credentials into this file.

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

kubectl wait --for=condition=available deploy/toolbox-ultimate-k8s-toolbox \
  -n toolbox --timeout=300s

kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash
CMD

echo ""
echo "Scenario 2: Validate built-in Keycloak tooling"
echo "------------------------------------------------"
cat <<'CMD'
kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash

# Inside the toolbox container:
kcadm.sh --help
kcreg.sh --help
kc.sh --help
keycloak-login.sh
kcadm.sh get realms
CMD

echo ""
echo "Scenario 3: Deploy with internal CA certificates"
echo "------------------------------------------------"
cat <<'CMD'
kubectl create namespace toolbox --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic toolbox-ca-certs \
  --from-file=root-ca.crt=/path/to/root-ca.crt \
  --from-file=subordinate-ca.crt=/path/to/subordinate-ca.crt \
  -n toolbox

helm upgrade --install toolbox ../chart \
  -n toolbox \
  --set customCA.enabled=true \
  --set customCA.secretName=toolbox-ca-certs

kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- update-ca-trust.sh --list
CMD

echo ""
echo "Scenario 4: Deploy with persistent workspace"
echo "--------------------------------------------"
cat <<'CMD'
helm upgrade --install toolbox ../chart \
  -n toolbox --create-namespace \
  --set workspace.enabled=true \
  --set workspace.storageClass=<storage-class> \
  --set workspace.size=20Gi
CMD

echo ""
echo "Scenario 5: Offline deployment with internal registry"
echo "-----------------------------------------------------"
cat <<'CMD'
kubectl create namespace toolbox --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=<registry-user> \
  --docker-password=<registry-password> \
  -n toolbox

helm upgrade --install toolbox ../chart \
  --set global.imageRegistry="registry.example.com/library" \
  --set image.repository="ultimate-k8s-toolbox" \
  --set image.tag="v1.1.0" \
  --set imagePullSecrets[0].name="regcred" \
  -n toolbox
CMD

echo ""
echo "Scenario 6: Use generated offline bundle helper"
echo "-----------------------------------------------"
cat <<'CMD'
make offline-bundle

tar -xzf dist/ultimate-k8s-toolbox-offline-v1.1.0.tar.gz
cd offline-bundle/scripts

./deploy-offline.sh \
  --registry registry.example.com/library \
  --namespace toolbox \
  --release-name toolbox
CMD

echo ""
echo "Scenario 7: Custom values file"
echo "------------------------------"
cat <<'CMD'
cat > my-values.yaml <<'EOF'
global:
  imageRegistry: "registry.example.com/library"

image:
  repository: "ultimate-k8s-toolbox"
  tag: "v1.1.0"

imagePullSecrets:
  - name: regcred

workspace:
  enabled: true
  storageClass: ""
  size: "10Gi"

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "2"
    memory: "2Gi"
EOF

helm upgrade --install toolbox ../chart \
  -f my-values.yaml \
  -n toolbox --create-namespace
CMD

echo ""
echo "Scenario 8: PostgreSQL diagnostics"
echo "----------------------------------"
cat <<'CMD'
kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash

# Inside the toolbox container, source PostgreSQL connection details from your approved secret workflow.
pg_isready
pg-diagnostics.sh
pg_dump --schema-only --file=/workspace/schema.sql
CMD

echo ""
echo "Scenario 9: Package and install from chart archive"
echo "--------------------------------------------------"
cat <<'CMD'
helm package ../chart -d /tmp

helm upgrade --install toolbox /tmp/ultimate-k8s-toolbox-1.1.0.tgz \
  -n toolbox --create-namespace
CMD

echo ""
echo "Scenario 10: Dry-run and template validation"
echo "---------------------------------------------"
cat <<'CMD'
helm lint ../chart

helm template toolbox ../chart \
  -n toolbox

helm upgrade --install toolbox ../chart \
  --dry-run \
  --debug \
  -n toolbox
CMD

echo ""
echo "Common management commands"
echo "--------------------------"
cat <<'CMD'
helm list -A
helm status toolbox -n toolbox
helm get values toolbox -n toolbox
kubectl get pods -n toolbox
kubectl logs -n toolbox deploy/toolbox-ultimate-k8s-toolbox
kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash
helm uninstall toolbox -n toolbox
CMD

echo ""
echo "============================================"
echo "For more information, see:"
echo "  - ../README.md"
echo "  - ../QUICKSTART.md"
echo "  - ../KEYCLOAK-GUIDE.md"
echo "  - ../OFFLINE-DEPLOYMENT.md"
echo "============================================"
