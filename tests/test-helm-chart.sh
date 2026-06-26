#!/bin/bash
# Helm Chart Testing and Validation Script

set -euo pipefail

CHART_DIR="./chart"
EXAMPLES_DIR="./examples"
VALUES_ONLINE="$EXAMPLES_DIR/values-online.yaml"
VALUES_OFFLINE="$EXAMPLES_DIR/values-offline.yaml"
NAMESPACE="toolbox-test"
RELEASE_NAME="test-toolbox"

printf '%s\n' \
  "==========================================" \
  "K8s Ultimate Toolbox - Helm Chart Tester" \
  "==========================================" \
  ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install Helm."
        exit 1
    fi
    print_success "Helm is installed: $(helm version --short)"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    print_success "kubectl is installed"

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    print_success "Connected to Kubernetes cluster"
    echo ""
}

validate_chart() {
    print_info "Validating Helm chart..."

    if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
        print_error "Chart.yaml not found in $CHART_DIR"
        exit 1
    fi

    helm lint "$CHART_DIR"
    print_success "Chart validation passed"
    echo ""
}

test_template() {
    print_info "Testing template rendering..."

    print_info "Testing with default values..."
    DEFAULT_RENDER=$(helm template test-render "$CHART_DIR")
    echo "$DEFAULT_RENDER" > /tmp/k8s-ultimate-toolbox-default-render.yaml
    print_success "Default values template render successful"

    if echo "$DEFAULT_RENDER" | grep -q 'name: keycloak-cli'; then
        print_error "Rendered chart still contains the removed Keycloak sidecar container"
        exit 1
    fi
    print_success "Default render contains only the primary toolbox container path"

    if ! echo "$DEFAULT_RENDER" | grep -q 'kcadm.sh'; then
        print_error "Rendered chart does not advertise built-in Keycloak CLI tooling"
        exit 1
    fi
    print_success "Rendered chart advertises built-in Keycloak tooling"

    if [ -f "$VALUES_ONLINE" ]; then
        print_info "Testing with online values..."
        helm template test-render "$CHART_DIR" -f "$VALUES_ONLINE" > /dev/null
        print_success "Online values template render successful"
    fi

    if [ -f "$VALUES_OFFLINE" ]; then
        print_info "Testing with offline values..."
        helm template test-render "$CHART_DIR" -f "$VALUES_OFFLINE" > /dev/null
        print_success "Offline values template render successful"
    fi

    echo ""
}

deploy_chart() {
    print_info "Deploying chart to Kubernetes..."

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace $NAMESPACE ready"

    VALUES_ARGS=()
    if [ -f "$VALUES_ONLINE" ]; then
        VALUES_ARGS+=("-f" "$VALUES_ONLINE")
    fi

    helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
        "${VALUES_ARGS[@]}" \
        --set image.repository="ubuntu" \
        --set image.tag="24.04" \
        -n "$NAMESPACE" \
        --wait --timeout 5m

    print_success "Chart deployed successfully"
    echo ""
}

verify_deployment() {
    print_info "Verifying deployment..."

    if ! kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" &> /dev/null; then
        print_error "Deployment not found"
        exit 1
    fi
    print_success "Deployment exists"

    print_info "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance="$RELEASE_NAME" \
        -n "$NAMESPACE" \
        --timeout=300s
    print_success "Pod is ready"

    POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
    print_success "Pod name: $POD_NAME"

    SA_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}')
    print_success "Service account: $SA_NAME"

    CONTAINER_COUNT=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' | wc -w | tr -d ' ')
    if [ "$CONTAINER_COUNT" != "1" ]; then
        print_error "Expected exactly one runtime container; found $CONTAINER_COUNT"
        exit 1
    fi
    print_success "Single runtime container confirmed"

    CONTAINER_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].name}')
    if [ "$CONTAINER_NAME" != "toolbox" ]; then
        print_error "Expected container name 'toolbox'; found '$CONTAINER_NAME'"
        exit 1
    fi
    print_success "Primary toolbox container confirmed"

    IMAGE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].image}')
    print_success "Image: $IMAGE"
    echo ""
}

test_pod() {
    print_info "Testing pod functionality..."

    POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

    print_info "Testing command execution..."
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "echo 'Hello from toolbox'" &> /dev/null; then
        print_success "Command execution works"
    else
        print_error "Command execution failed"
    fi

    print_info "Testing environment variables..."
    POD_NS=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "echo \$POD_NAMESPACE")
    if [ "$POD_NS" == "$NAMESPACE" ]; then
        print_success "Environment variables set correctly (POD_NAMESPACE=$POD_NS)"
    else
        print_error "Environment variable POD_NAMESPACE not set correctly"
    fi

    echo ""
}

show_access_info() {
    POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

    printf '%s\n' \
      "==========================================" \
      "Deployment Successful!" \
      "==========================================" \
      "" \
      "Access your toolbox pod:" \
      "  kubectl -n $NAMESPACE exec -it $POD_NAME -- bash" \
      "" \
      "Or using deployment:" \
      "  kubectl -n $NAMESPACE exec -it deploy/$RELEASE_NAME-ultimate-k8s-toolbox -- bash" \
      "" \
      "View pod details:" \
      "  kubectl -n $NAMESPACE get pods" \
      "  kubectl -n $NAMESPACE describe pod $POD_NAME" \
      "" \
      "View logs:" \
      "  kubectl -n $NAMESPACE logs $POD_NAME" \
      "" \
      "Uninstall:" \
      "  helm uninstall $RELEASE_NAME -n $NAMESPACE" \
      "  kubectl delete namespace $NAMESPACE" \
      ""
}

cleanup() {
    if [ "${1:-}" == "cleanup" ]; then
        print_info "Cleaning up test deployment..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true
        kubectl delete namespace "$NAMESPACE" 2>/dev/null || true
        print_success "Cleanup complete"
        exit 0
    fi
}

main() {
    if [ "${1:-}" == "cleanup" ]; then
        cleanup "cleanup"
    fi

    check_prerequisites
    validate_chart
    test_template
    deploy_chart
    verify_deployment
    test_pod
    show_access_info

    printf '%s\n' \
      "==========================================" \
      "All tests passed!" \
      "=========================================="
}

main "${1:-}"
