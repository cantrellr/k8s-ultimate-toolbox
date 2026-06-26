#!/bin/bash
# Helm Chart Testing and Validation Script

set -euo pipefail

CHART_DIR="./chart"
EXAMPLES_DIR="./examples"
VALUES_ONLINE="$EXAMPLES_DIR/values-online.yaml"
VALUES_OFFLINE="$EXAMPLES_DIR/values-offline.yaml"
NAMESPACE="toolbox-test"
RELEASE_NAME="test-toolbox"

print_info() { echo "INFO: $*"; }
print_success() { echo "OK: $*"; }
print_error() { echo "ERROR: $*" >&2; }

check_prerequisites() {
  command -v helm >/dev/null 2>&1 || { print_error "Helm is not installed"; exit 1; }
  command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is not installed"; exit 1; }
  kubectl cluster-info >/dev/null 2>&1 || { print_error "Cannot connect to Kubernetes cluster"; exit 1; }
  print_success "Prerequisites satisfied"
}

validate_chart() {
  helm lint "$CHART_DIR"
  print_success "Chart validation passed"
}

test_template() {
  DEFAULT_RENDER=$(helm template test-render "$CHART_DIR")
  echo "$DEFAULT_RENDER" > /tmp/k8s-ultimate-toolbox-default-render.yaml

  if echo "$DEFAULT_RENDER" | grep -q 'ultimate-k8s-toolbox'; then
    print_error "Rendered chart still contains old name ultimate-k8s-toolbox"
    exit 1
  fi

  for expected in 'k8s-ultimate-toolbox' 'kcadm.sh' 'crictl' 'etcdctl' 'cmctl' 'kubent' 'kubeconform' 'popeye' 'kubectl-who-can' 'rbac-lookup' 'cilium' 'hubble' 'calicoctl'; do
    echo "$DEFAULT_RENDER" | grep -q "$expected" || { print_error "Missing expected render text: $expected"; exit 1; }
  done

  [ -f "$VALUES_ONLINE" ] && helm template test-render "$CHART_DIR" -f "$VALUES_ONLINE" >/dev/null
  [ -f "$VALUES_OFFLINE" ] && helm template test-render "$CHART_DIR" -f "$VALUES_OFFLINE" >/dev/null
  print_success "Template rendering passed"
}

deploy_chart() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
    --set image.repository="ubuntu" \
    --set image.tag="24.04" \
    -n "$NAMESPACE" \
    --wait --timeout 5m
  print_success "Chart deployed"
}

verify_deployment() {
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance="$RELEASE_NAME" -n "$NAMESPACE" --timeout=300s
  POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
  CONTAINER_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].name}')
  [ "$CONTAINER_NAME" = "toolbox" ] || { print_error "Expected toolbox container"; exit 1; }
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "echo 'Hello from toolbox'" >/dev/null
  print_success "Deployment verified"
  echo "Access: kubectl -n $NAMESPACE exec -it deploy/$RELEASE_NAME-k8s-ultimate-toolbox -- bash"
}

main() {
  check_prerequisites
  validate_chart
  test_template
  deploy_chart
  verify_deployment
  print_success "All tests passed"
}

main "$@"
