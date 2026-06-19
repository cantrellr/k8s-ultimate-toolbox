#!/bin/bash
# =============================================================================
# CA Certificate Import Script for Ultimate K8s Toolbox
# =============================================================================
# This script validates and imports CA certificates into Kubernetes as secrets
# for use with the toolbox pod's CA trust integration.
#
# Usage:
#   ./import-ca-certs.sh [OPTIONS]
#
# Options:
#   --root-ca <path>           Path to root CA certificate file
#   --subordinate-ca <path>    Path to subordinate/intermediate CA certificate
#   --secret-name <name>       Kubernetes secret name (default: toolbox-ca-certs)
#   --namespace <ns>           Kubernetes namespace (default: toolbox)
#   --dry-run                  Validate certificates without creating secret
#   --force                    Overwrite existing secret without prompting
#   --help                     Show this help message
#
# Examples:
#   ./import-ca-certs.sh --root-ca /path/to/root-ca.crt
#   ./import-ca-certs.sh --root-ca root.crt --subordinate-ca intermediate.crt
#   ./import-ca-certs.sh --root-ca root.crt --namespace mongodb --secret-name mongo-ca
# =============================================================================

set -e

# Colors for output
COLOR_GREEN='\033[32m'
COLOR_RED='\033[31m'
COLOR_YELLOW='\033[1;33m'
COLOR_CYAN='\033[36m'
COLOR_RESET='\033[0m'

# Default values
SECRET_NAME="toolbox-ca-certs"
NAMESPACE="toolbox"
ROOT_CA_PATH=""
SUBORDINATE_CA_PATH=""
DRY_RUN=false
FORCE=false

# Functions
print_header() {
    echo ""
    echo -e "${COLOR_CYAN}========================================"
    echo -e "  $1"
    echo -e "========================================${COLOR_RESET}"
    echo ""
}

print_success() { echo -e "${COLOR_GREEN}✓ $1${COLOR_RESET}"; }
print_error() { echo -e "${COLOR_RED}✗ $1${COLOR_RESET}"; }
print_warning() { echo -e "${COLOR_YELLOW}⚠ $1${COLOR_RESET}"; }
print_info() { echo -e "${COLOR_CYAN}ℹ $1${COLOR_RESET}"; }

show_help() {
    head -35 "$0" | tail -30 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Validate that a file is a valid PEM certificate
validate_certificate() {
    local cert_path="$1"
    local cert_name="$2"
    
    if [ ! -f "$cert_path" ]; then
        print_error "Certificate file not found: $cert_path"
        return 1
    fi
    
    # Check if file is readable
    if [ ! -r "$cert_path" ]; then
        print_error "Cannot read certificate file: $cert_path"
        return 1
    fi
    
    # Validate PEM format using openssl
    if ! openssl x509 -in "$cert_path" -noout 2>/dev/null; then
        print_error "Invalid certificate format: $cert_path"
        print_info "Certificate must be in PEM format (-----BEGIN CERTIFICATE-----)"
        return 1
    fi
    
    # Extract certificate details
    local subject issuer expiry
    subject=$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/subject=//')
    issuer=$(openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    
    print_success "$cert_name certificate is valid"
    echo "    Subject: $subject"
    echo "    Issuer:  $issuer"
    echo "    Expires: $expiry"
    
    # Check if certificate is expired
    if ! openssl x509 -in "$cert_path" -noout -checkend 0 2>/dev/null; then
        print_warning "Certificate is EXPIRED: $cert_path"
        return 1
    fi
    
    # Check if certificate is a CA certificate
    local basic_constraints
    basic_constraints=$(openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A1 "Basic Constraints" | tail -1)
    if echo "$basic_constraints" | grep -q "CA:TRUE"; then
        print_info "Certificate is a CA certificate"
    else
        print_warning "Certificate may not be a CA certificate (no CA:TRUE in Basic Constraints)"
    fi
    
    return 0
}

# Check if secret already exists
check_existing_secret() {
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        return 0
    fi
    return 1
}

# Create or update the Kubernetes secret
create_ca_secret() {
    local secret_args=()
    
    # Add root CA if provided
    if [ -n "$ROOT_CA_PATH" ]; then
        secret_args+=("--from-file=root-ca.crt=$ROOT_CA_PATH")
    fi
    
    # Add subordinate CA if provided
    if [ -n "$SUBORDINATE_CA_PATH" ]; then
        secret_args+=("--from-file=subordinate-ca.crt=$SUBORDINATE_CA_PATH")
    fi
    
    # Create combined CA bundle
    if [ -n "$ROOT_CA_PATH" ] || [ -n "$SUBORDINATE_CA_PATH" ]; then
        local bundle_file
        bundle_file=$(mktemp)
        
        if [ -n "$ROOT_CA_PATH" ]; then
            cat "$ROOT_CA_PATH" >> "$bundle_file"
            echo "" >> "$bundle_file"
        fi
        if [ -n "$SUBORDINATE_CA_PATH" ]; then
            cat "$SUBORDINATE_CA_PATH" >> "$bundle_file"
        fi
        
        secret_args+=("--from-file=ca-bundle.crt=$bundle_file")
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN: Would create secret with:"
        echo "  kubectl create secret generic $SECRET_NAME ${secret_args[*]} -n $NAMESPACE"
        [ -n "$bundle_file" ] && rm -f "$bundle_file"
        return 0
    fi
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Delete existing secret if force flag is set
    if check_existing_secret; then
        if [ "$FORCE" = true ]; then
            print_info "Deleting existing secret: $SECRET_NAME"
            kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
        else
            print_error "Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'"
            print_info "Use --force to overwrite, or choose a different secret name"
            [ -n "$bundle_file" ] && rm -f "$bundle_file"
            return 1
        fi
    fi
    
    # Create the secret
    print_info "Creating Kubernetes secret: $SECRET_NAME"
    kubectl create secret generic "$SECRET_NAME" "${secret_args[@]}" -n "$NAMESPACE"
    
    # Clean up temp file
    [ -n "$bundle_file" ] && rm -f "$bundle_file"
    
    print_success "Secret '$SECRET_NAME' created in namespace '$NAMESPACE'"
    
    # Show secret contents
    echo ""
    print_info "Secret contents:"
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print('  Keys:', ', '.join(d.keys()))" 2>/dev/null || \
        kubectl describe secret "$SECRET_NAME" -n "$NAMESPACE" | grep -A10 "^Data"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --root-ca)
                ROOT_CA_PATH="$2"
                shift 2
                ;;
            --subordinate-ca)
                SUBORDINATE_CA_PATH="$2"
                shift 2
                ;;
            --secret-name)
                SECRET_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Interactive mode - prompt for certificates
interactive_mode() {
    print_header "CA Certificate Import (Interactive)"
    
    echo "This script will help you import CA certificates into Kubernetes"
    echo "for use with the Ultimate K8s Toolbox pod."
    echo ""
    
    # Prompt for root CA
    read -r -p "Enter path to root CA certificate (or press Enter to skip): " ROOT_CA_PATH
    if [ -n "$ROOT_CA_PATH" ]; then
        # Expand ~ to home directory
        ROOT_CA_PATH="${ROOT_CA_PATH/#\~/$HOME}"
    fi
    
    # Prompt for subordinate CA
    read -r -p "Enter path to subordinate CA certificate (or press Enter to skip): " SUBORDINATE_CA_PATH
    if [ -n "$SUBORDINATE_CA_PATH" ]; then
        SUBORDINATE_CA_PATH="${SUBORDINATE_CA_PATH/#\~/$HOME}"
    fi
    
    # Prompt for namespace
    read -r -p "Enter Kubernetes namespace [$NAMESPACE]: " input_ns
    [ -n "$input_ns" ] && NAMESPACE="$input_ns"
    
    # Prompt for secret name
    read -r -p "Enter secret name [$SECRET_NAME]: " input_secret
    [ -n "$input_secret" ] && SECRET_NAME="$input_secret"
}

# Main execution
main() {
    print_header "CA Certificate Import Tool"
    
    # Parse arguments
    parse_args "$@"
    
    # If no certificates provided, enter interactive mode
    if [ -z "$ROOT_CA_PATH" ] && [ -z "$SUBORDINATE_CA_PATH" ]; then
        interactive_mode
    fi
    
    # Validate at least one certificate is provided
    if [ -z "$ROOT_CA_PATH" ] && [ -z "$SUBORDINATE_CA_PATH" ]; then
        print_error "No certificates provided"
        print_info "Provide at least --root-ca or --subordinate-ca"
        exit 1
    fi
    
    # Check prerequisites
    print_info "Checking prerequisites..."
    if ! command -v kubectl &>/dev/null; then
        print_error "kubectl not found"
        exit 1
    fi
    if ! command -v openssl &>/dev/null; then
        print_error "openssl not found"
        exit 1
    fi
    print_success "Prerequisites satisfied"
    
    # Validate certificates
    print_header "Validating Certificates"
    
    validation_failed=false
    
    if [ -n "$ROOT_CA_PATH" ]; then
        if ! validate_certificate "$ROOT_CA_PATH" "Root CA"; then
            validation_failed=true
        fi
        echo ""
    fi
    
    if [ -n "$SUBORDINATE_CA_PATH" ]; then
        if ! validate_certificate "$SUBORDINATE_CA_PATH" "Subordinate CA"; then
            validation_failed=true
        fi
        echo ""
    fi
    
    if [ "$validation_failed" = true ]; then
        print_error "Certificate validation failed"
        exit 1
    fi
    
    print_success "All certificates validated"
    
    # Create the secret
    print_header "Creating Kubernetes Secret"
    
    echo "Configuration:"
    echo "  Namespace:   $NAMESPACE"
    echo "  Secret Name: $SECRET_NAME"
    [ -n "$ROOT_CA_PATH" ] && echo "  Root CA:     $ROOT_CA_PATH"
    [ -n "$SUBORDINATE_CA_PATH" ] && echo "  Sub CA:      $SUBORDINATE_CA_PATH"
    echo ""
    
    if ! create_ca_secret; then
        exit 1
    fi
    
    # Show next steps
    print_header "Next Steps"
    
    echo "To use these CA certificates with the toolbox:"
    echo ""
    echo "1. Deploy with CA trust enabled:"
    echo "   helm upgrade --install toolbox ./chart \\"
    echo "     --set customCA.enabled=true \\"
    echo "     --set customCA.secretName=$SECRET_NAME \\"
    echo "     -n $NAMESPACE"
    echo ""
    echo "2. Or add to your values file:"
    echo "   customCA:"
    echo "     enabled: true"
    echo "     secretName: $SECRET_NAME"
    echo ""
    echo "3. Verify CA trust inside the pod:"
    echo "   kubectl exec -it deploy/<release>-ultimate-k8s-toolbox -n $NAMESPACE -- \\"
    echo "     openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /etc/ssl/custom-ca/root-ca.crt"
    echo ""
    
    print_success "CA certificate import complete!"
}

# Run main function
main "$@"
