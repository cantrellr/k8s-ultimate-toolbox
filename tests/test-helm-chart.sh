#!/bin/bash
# Helm Chart Testing and Validation Script

set -e

CHART_DIR="./chart"
EXAMPLES_DIR="./examples"
VALUES_ONLINE="$EXAMPLES_DIR/values-online.yaml"
VALUES_OFFLINE="$EXAMPLES_DIR/values-offline.yaml"
NAMESPACE="toolbox-test"
RELEASE_NAME="test-toolbox"

echo "=========================================="
echo "Ultimate K8s Toolbox - Helm Chart Tester"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install Helm 3.0+"
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

# Validate chart
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

# Template rendering test
test_template() {
    print_info "Testing template rendering..."
    
    # Test default values
    print_info "Testing with default values..."
    helm template test-render "$CHART_DIR" > /dev/null
    print_success "Default values template render successful"
    
    # Test online values
    if [ -f "$VALUES_ONLINE" ]; then
        print_info "Testing with online values..."
        helm template test-render "$CHART_DIR" -f "$VALUES_ONLINE" > /dev/null
        print_success "Online values template render successful"
    fi
    
    # Test offline values
    if [ -f "$VALUES_OFFLINE" ]; then
        print_info "Testing with offline values..."
        helm template test-render "$CHART_DIR" -f "$VALUES_OFFLINE" > /dev/null
        print_success "Offline values template render successful"
    fi
    
    echo ""
}

# Deploy chart
deploy_chart() {
    print_info "Deploying chart to Kubernetes..."
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace $NAMESPACE ready"
    
    # Install chart (using ubuntu image for testing)
    # Prefer example values if present, but always force the test image to avoid requiring the toolbox image.
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

# Verify deployment
verify_deployment() {
    print_info "Verifying deployment..."
    
    # Check if deployment exists
    if ! kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" &> /dev/null; then
        print_error "Deployment not found"
        exit 1
    fi
    print_success "Deployment exists"
    
    # Check if pod is running
    print_info "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance="$RELEASE_NAME" \
        -n "$NAMESPACE" \
        --timeout=300s
    print_success "Pod is ready"
    
    # Get pod info
    POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
    print_success "Pod name: $POD_NAME"
    
    # Check service account
    SA_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}')
    print_success "Service account: $SA_NAME"
    
    # Check image
    IMAGE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].image}')
    print_success "Image: $IMAGE"
    
    echo ""
}

# Test pod functionality
test_pod() {
    print_info "Testing pod functionality..."
    
    POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
    
    # Test basic command execution
    print_info "Testing command execution..."
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "echo 'Hello from toolbox'" &> /dev/null; then
        print_success "Command execution works"
    else
        print_error "Command execution failed"
    fi
    
    # Test environment variables
    print_info "Testing environment variables..."
    POD_NS=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "echo \$POD_NAMESPACE")
    if [ "$POD_NS" == "$NAMESPACE" ]; then
        print_success "Environment variables set correctly (POD_NAMESPACE=$POD_NS)"
    else
        print_error "Environment variable POD_NAMESPACE not set correctly"
    fi
    
    echo ""
}

# Display access instructions
show_access_info() {
    POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
    
    echo "=========================================="
    echo "Deployment Successful!"
    echo "=========================================="
    echo ""
    echo "Access your toolbox pod:"
    echo "  kubectl -n $NAMESPACE exec -it $POD_NAME -- bash"
    echo ""
    echo "Or using deployment:"
    echo "  kubectl -n $NAMESPACE exec -it deploy/$RELEASE_NAME-ultimate-k8s-toolbox -- bash"
    echo ""
    echo "View pod details:"
    echo "  kubectl -n $NAMESPACE get pods"
    echo "  kubectl -n $NAMESPACE describe pod $POD_NAME"
    echo ""
    echo "View logs:"
    echo "  kubectl -n $NAMESPACE logs $POD_NAME"
    echo ""
    echo "Uninstall:"
    echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
    echo "  kubectl delete namespace $NAMESPACE"
    echo ""
}

# Cleanup function
cleanup() {
    if [ "$1" == "cleanup" ]; then
        print_info "Cleaning up test deployment..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true
        kubectl delete namespace "$NAMESPACE" 2>/dev/null || true
        print_success "Cleanup complete"
        exit 0
    fi
}

# Main execution
main() {
    if [ "$1" == "cleanup" ]; then
        cleanup "cleanup"
    fi
    
    check_prerequisites
    validate_chart
    test_template
    deploy_chart
    verify_deployment
    test_pod
    show_access_info
    
    echo "=========================================="
    echo "All tests passed!"
    echo "=========================================="
}

# Run main with arguments
main "$@"
