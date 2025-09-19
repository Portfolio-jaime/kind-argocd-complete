#!/bin/bash

# ArgoCD GitHub Authentication Setup Script
# This script configures GitHub OAuth authentication for ArgoCD

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="argocd"
CONFIG_FILE="configs/argocd-github-auth-config.yaml"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    # Check if ArgoCD namespace exists
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "ArgoCD namespace '$NAMESPACE' does not exist"
        exit 1
    fi

    # Check if ArgoCD is running
    if ! kubectl get deployment argocd-server -n $NAMESPACE &> /dev/null; then
        log_error "ArgoCD server deployment not found in namespace '$NAMESPACE'"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Get GitHub OAuth credentials
get_github_credentials() {
    log_info "GitHub OAuth App Configuration Required"
    echo ""
    echo "Before proceeding, you need to create a GitHub OAuth App:"
    echo "1. Go to GitHub → Settings → Developer settings → OAuth Apps"
    echo "2. Click 'New OAuth App'"
    echo "3. Configure:"
    echo "   - Application name: ArgoCD"
    echo "   - Homepage URL: https://argocd.test.com"
    echo "   - Authorization callback URL: https://argocd.test.com/api/dex/callback"
    echo ""

    read -p "Enter your GitHub OAuth Client ID: " GITHUB_CLIENT_ID
    read -s -p "Enter your GitHub OAuth Client Secret: " GITHUB_CLIENT_SECRET
    echo ""
    read -p "Enter your GitHub Organization name: " GITHUB_ORG

    if [[ -z "$GITHUB_CLIENT_ID" || -z "$GITHUB_CLIENT_SECRET" || -z "$GITHUB_ORG" ]]; then
        log_error "All GitHub OAuth credentials are required"
        exit 1
    fi
}

# Generate random secrets
generate_secrets() {
    log_info "Generating random secrets..."

    OIDC_CLIENT_SECRET=$(openssl rand -base64 32)
    SERVER_SECRET_KEY=$(openssl rand -base64 32)

    log_success "Random secrets generated"
}

# Backup current configuration
backup_current_config() {
    log_info "Creating backup of current configuration..."

    BACKUP_DIR="backups/github-auth-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR

    # Backup ConfigMaps
    kubectl get configmap argocd-cm -n $NAMESPACE -o yaml > $BACKUP_DIR/argocd-cm-backup.yaml 2>/dev/null || log_warning "argocd-cm ConfigMap not found"
    kubectl get configmap argocd-rbac-cm -n $NAMESPACE -o yaml > $BACKUP_DIR/argocd-rbac-cm-backup.yaml 2>/dev/null || log_warning "argocd-rbac-cm ConfigMap not found"

    # Backup Secret
    kubectl get secret argocd-secret -n $NAMESPACE -o yaml > $BACKUP_DIR/argocd-secret-backup.yaml 2>/dev/null || log_warning "argocd-secret Secret not found"

    log_success "Configuration backed up to $BACKUP_DIR"
}

# Apply GitHub authentication configuration
apply_github_config() {
    log_info "Applying GitHub authentication configuration..."

    # Create temporary file with substituted values
    TEMP_CONFIG=$(mktemp)

    # Copy the config file and substitute variables
    cp $CONFIG_FILE $TEMP_CONFIG

    # Replace placeholders
    sed -i.bak "s/your-github-client-id/$GITHUB_CLIENT_ID/g" $TEMP_CONFIG
    sed -i.bak "s/your-github-client-secret/$GITHUB_CLIENT_SECRET/g" $TEMP_CONFIG
    sed -i.bak "s/your-github-org/$GITHUB_ORG/g" $TEMP_CONFIG
    sed -i.bak "s/random-generated-secret-string/$OIDC_CLIENT_SECRET/g" $TEMP_CONFIG
    sed -i.bak "s/generated-secret-key-for-jwt-signing/$SERVER_SECRET_KEY/g" $TEMP_CONFIG

    # Apply the configuration
    kubectl apply -f $TEMP_CONFIG

    # Clean up
    rm $TEMP_CONFIG $TEMP_CONFIG.bak

    log_success "GitHub authentication configuration applied"
}

# Restart ArgoCD components
restart_argocd() {
    log_info "Restarting ArgoCD components to apply changes..."

    # Restart server and dex
    kubectl rollout restart deployment/argocd-server -n $NAMESPACE
    kubectl rollout restart deployment/argocd-dex-server -n $NAMESPACE

    # Wait for rollout to complete
    kubectl rollout status deployment/argocd-server -n $NAMESPACE --timeout=300s
    kubectl rollout status deployment/argocd-dex-server -n $NAMESPACE --timeout=300s

    log_success "ArgoCD components restarted successfully"
}

# Verify configuration
verify_config() {
    log_info "Verifying GitHub authentication configuration..."

    # Check if pods are running
    if kubectl get pods -n $NAMESPACE | grep -E "(argocd-server|argocd-dex-server)" | grep -q "Running"; then
        log_success "ArgoCD pods are running"
    else
        log_warning "Some ArgoCD pods may not be running properly"
        kubectl get pods -n $NAMESPACE
    fi

    # Check if service is accessible
    log_info "Checking if ArgoCD server is accessible..."

    # Port forward for testing (run in background)
    kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:443 &
    PF_PID=$!

    sleep 5

    # Test connection
    if curl -k -s https://localhost:8080/api/version > /dev/null; then
        log_success "ArgoCD server is accessible"
    else
        log_warning "ArgoCD server may not be fully ready yet"
    fi

    # Kill port forward
    kill $PF_PID 2>/dev/null || true
}

# Display next steps
show_next_steps() {
    log_success "GitHub authentication setup completed!"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Access ArgoCD at: https://argocd.test.com"
    echo "2. You should now see a 'Login via GitHub' button"
    echo "3. Click it to authenticate with your GitHub account"
    echo ""
    echo -e "${BLUE}GitHub Team Configuration:${NC}"
    echo "Make sure your GitHub organization has these teams configured:"
    echo "- ${GITHUB_ORG}:argocd-admins (for admin access)"
    echo "- ${GITHUB_ORG}:developers (for developer access)"
    echo ""
    echo -e "${BLUE}Troubleshooting:${NC}"
    echo "- Check logs: kubectl logs deployment/argocd-server -n argocd"
    echo "- Check dex logs: kubectl logs deployment/argocd-dex-server -n argocd"
    echo "- Verify config: kubectl get configmap argocd-cm -n argocd -o yaml"
    echo ""
    echo -e "${YELLOW}Important:${NC} The admin user is still enabled for emergency access"
}

# Main execution
main() {
    log_info "Starting ArgoCD GitHub Authentication Setup"
    echo ""

    check_prerequisites
    get_github_credentials
    generate_secrets
    backup_current_config
    apply_github_config
    restart_argocd
    verify_config
    show_next_steps

    log_success "Setup completed successfully!"
}

# Run main function
main "$@"