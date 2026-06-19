#!/bin/bash
# Example deployment commands for various scenarios

# ============================================
# SCENARIO 1: Quick Online Test Deployment
# ============================================
echo "Scenario 1: Quick Online Test"
echo "------------------------------"
cat <<'CMD'
helm install quick-test ../chart \
  --set image.repository=ubuntu \
  --set image.tag=24.04 \
  -n default

kubectl get pods -l app.kubernetes.io/name=ultimate-k8s-toolbox
kubectl exec -it deploy/quick-test-ultimate-k8s-toolbox -- bash
CMD
echo ""

# ============================================
# SCENARIO 2: Production Online Deployment
# ============================================
echo "Scenario 2: Production Online"
echo "------------------------------"
cat <<'CMD'
helm install prod-toolbox ../chart \
  -f values-online.yaml \
  --set replicaCount=2 \
  --set resources.limits.cpu=4 \
  --set resources.limits.memory=8Gi \
  -n toolbox --create-namespace

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ultimate-k8s-toolbox \
  -n toolbox --timeout=300s
CMD
echo ""

# ============================================
# SCENARIO 3: Offline Deployment (Harbor)
# ============================================
echo "Scenario 3: Offline with Harbor Registry"
echo "-----------------------------------------"
cat <<'CMD'
# 1. Create namespace and secret
kubectl create namespace toolbox

kubectl create secret docker-registry regcred \
  --docker-server=harbor.internal.company.com \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n toolbox

# 2. Deploy with offline values
helm install toolbox ../chart \
  --set global.imageRegistry="harbor.internal.company.com" \
  --set image.repository="platfor../chart" \
  --set image.tag="v1.0.2" \
  --set imagePullSecrets[0].name="regcred" \
  -n toolbox

# 3. Verify
kubectl get all -n toolbox
CMD
echo ""

# ============================================
# SCENARIO 4: Offline Deployment (Nexus)
# ============================================
echo "Scenario 4: Offline with Nexus Registry"
echo "----------------------------------------"
cat <<'CMD'
kubectl create namespace toolbox

kubectl create secret docker-registry nexus-cred \
  --docker-server=nexus.internal.company.com:8082 \
  --docker-username=nexus-user \
  --docker-password=nexus-pass \
  -n toolbox

helm install toolbox ../chart \
  --set global.imageRegistry="nexus.internal.company.com:8082" \
  --set image.repository="ultimate-k8s-toolbox" \
  --set image.tag="latest" \
  --set imagePullSecrets[0].name="nexus-cred" \
  -n toolbox
CMD
echo ""

# ============================================
# SCENARIO 5: MongoDB Namespace with Existing SA
# ============================================
echo "Scenario 5: MongoDB Namespace (Existing SA)"
echo "-------------------------------------------"
cat <<'CMD'
helm install mongo-toolbox ../chart \
  --set global.imageRegistry="harbor.internal.com" \
  --set image.repository="platfor../chart" \
  --set serviceAccount.create=false \
  --set serviceAccount.name="mongodb-operator" \
  --set global.namespaceOverride="mongodb" \
  --set imagePullSecrets[0].name="altregistry-secret" \
  -n mongodb

kubectl -n mongodb get pods
CMD
echo ""

# ============================================
# SCENARIO 6: Multi-Environment Deployment
# ============================================
echo "Scenario 6: Multi-Environment"
echo "------------------------------"
cat <<'CMD'
# Development
helm install dev-toolbox ../chart \
  --set global.imageRegistry="registry.dev.local" \
  --set image.tag="dev" \
  -n dev-tools --create-namespace

# Staging
helm install staging-toolbox ../chart \
  --set global.imageRegistry="registry.staging.local" \
  --set image.tag="staging" \
  -n staging-tools --create-namespace

# Production
helm install prod-toolbox ../chart \
  --set global.imageRegistry="registry.prod.local" \
  --set image.tag="v1.0.2" \
  --set replicaCount=3 \
  --set resources.limits.memory=8Gi \
  -n prod-tools --create-namespace
CMD
echo ""

# ============================================
# SCENARIO 7: Using Values Files
# ============================================
echo "Scenario 7: Using Custom Values Files"
echo "--------------------------------------"
cat <<'CMD'
# Create custom values file
cat > my-values.yaml <<EOF
global:
  imageRegistry: "myregistry.local:5000"
  
image:
  repository: "platform/toolbox"
  tag: "v1.2.0"
  
imagePullSecrets:
  - name: my-regcred

replicaCount: 2

resources:
  limits:
    cpu: "4"
    memory: "8Gi"

nodeSelector:
  disktype: ssd
EOF

# Deploy using custom values
helm install my-toolbox ../chart \
  -f my-values.yaml \
  -n toolbox --create-namespace
CMD
echo ""

# ============================================
# SCENARIO 8: Upgrade Scenarios
# ============================================
echo "Scenario 8: Upgrade Operations"
echo "-------------------------------"
cat <<'CMD'
# Upgrade image version
helm upgrade toolbox ../chart \
  --reuse-values \
  --set image.tag=v1.1.0 \
  -n toolbox

# Scale replicas
helm upgrade toolbox ../chart \
  --reuse-values \
  --set replicaCount=5 \
  -n toolbox

# Change resources
helm upgrade toolbox ../chart \
  --reuse-values \
  --set resources.limits.memory=16Gi \
  -n toolbox

# Rollback if needed
helm rollback toolbox 1 -n toolbox
CMD
echo ""

# ============================================
# SCENARIO 9: Package and Install from Archive
# ============================================
echo "Scenario 9: Package and Deploy from Archive"
echo "--------------------------------------------"
cat <<'CMD'
# Package the chart
helm package ../chart

# This creates: ultimate-k8s-toolbox-chart-1.0.2.tgz

# Install from package
helm install my-toolbox ultimate-k8s-toolbox-chart-1.0.2.tgz \
  -f values-offline.yaml \
  -n toolbox --create-namespace

# Or install from URL (if hosted)
helm install my-toolbox https://charts.example.co../ultimate-k8s-toolbox-chart-1.0.2.tgz \
  -f values-offline.yaml \
  -n toolbox
CMD
echo ""

# ============================================
# SCENARIO 10: Dry-run and Template Testing
# ============================================
echo "Scenario 10: Testing and Validation"
echo "------------------------------------"
cat <<'CMD'
# Dry-run installation
helm install test-toolbox ../chart \
  -f values-offline.yaml \
  --dry-run \
  -n toolbox

# Template rendering
helm template test-toolbox ../chart \
  -f values-offline.yaml \
  -n toolbox

# Specific template output
helm template test-toolbox ../chart \
  -f values-offline.yaml \
  -s templates/deployment.yaml

# Debug mode
helm install test-toolbox ../chart \
  -f values-offline.yaml \
  --debug \
  -n toolbox
CMD
echo ""

# ============================================
# Common Management Commands
# ============================================
echo "Common Management Commands"
echo "--------------------------"
cat <<'CMD'
# List all releases
helm list -A

# Get release information
helm get all toolbox -n toolbox

# Get values
helm get values toolbox -n toolbox

# History
helm history toolbox -n toolbox

# Status
helm status toolbox -n toolbox

# Uninstall
helm uninstall toolbox -n toolbox

# Cleanup namespace
kubectl delete namespace toolbox
CMD
echo ""

echo "============================================"
echo "For more information, see:"
echo "  - README.md"
echo "  - QUICKSTART.md"
echo "  - OFFLINE-DEPLOYMENT.md"
echo "============================================"
