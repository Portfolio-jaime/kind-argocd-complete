#!/bin/bash

# ArgoCD GitHub Authentication Test Script
# This script tests the GitHub OAuth authentication configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="argocd"
ARGOCD_URL="https://argocd.test.com"

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

# Test functions
test_argocd_pods() {
    log_info "Testing ArgoCD pods status..."

    local failed=0

    # Check ArgoCD server
    if ! kubectl get deployment argocd-server -n $NAMESPACE &> /dev/null; then
        log_error "ArgoCD server deployment not found"
        failed=1
    else
        local server_ready=$(kubectl get deployment argocd-server -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
        local server_desired=$(kubectl get deployment argocd-server -n $NAMESPACE -o jsonpath='{.spec.replicas}')

        if [[ "$server_ready" == "$server_desired" ]]; then
            log_success "ArgoCD server is ready ($server_ready/$server_desired)"
        else
            log_error "ArgoCD server is not ready ($server_ready/$server_desired)"
            failed=1
        fi
    fi

    # Check DEX server
    if ! kubectl get deployment argocd-dex-server -n $NAMESPACE &> /dev/null; then
        log_error "ArgoCD DEX server deployment not found"
        failed=1
    else
        local dex_ready=$(kubectl get deployment argocd-dex-server -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
        local dex_desired=$(kubectl get deployment argocd-dex-server -n $NAMESPACE -o jsonpath='{.spec.replicas}')

        if [[ "$dex_ready" == "$dex_desired" ]]; then
            log_success "ArgoCD DEX server is ready ($dex_ready/$dex_desired)"
        else
            log_error "ArgoCD DEX server is not ready ($dex_ready/$dex_desired)"
            failed=1
        fi
    fi

    return $failed
}

test_configuration() {
    log_info "Testing ArgoCD configuration..."

    local failed=0

    # Check if GitHub configuration exists in argocd-cm
    if ! kubectl get configmap argocd-cm -n $NAMESPACE -o yaml | grep -q "dex.config"; then
        log_error "DEX configuration not found in argocd-cm"
        failed=1
    else
        log_success "DEX configuration found in argocd-cm"
    fi

    # Check if GitHub connector is configured
    if ! kubectl get configmap argocd-cm -n $NAMESPACE -o yaml | grep -q "type: github"; then
        log_error "GitHub connector not configured in DEX"
        failed=1
    else
        log_success "GitHub connector configured in DEX"
    fi

    # Check RBAC configuration
    if ! kubectl get configmap argocd-rbac-cm -n $NAMESPACE &> /dev/null; then
        log_error "RBAC configuration not found"
        failed=1
    else
        log_success "RBAC configuration found"
    fi

    # Check if secrets exist
    if ! kubectl get secret argocd-secret -n $NAMESPACE &> /dev/null; then
        log_error "ArgoCD secret not found"
        failed=1
    else
        # Check if GitHub credentials exist in secret
        if kubectl get secret argocd-secret -n $NAMESPACE -o yaml | grep -q "dex.github.clientId"; then
            log_success "GitHub OAuth credentials found in secret"
        else
            log_error "GitHub OAuth credentials not found in secret"
            failed=1
        fi
    fi

    return $failed
}

test_dex_endpoints() {
    log_info "Testing DEX endpoints..."

    local failed=0

    # Port forward to test locally
    kubectl port-forward svc/argocd-dex-server -n $NAMESPACE 5556:5556 &
    local pf_dex_pid=$!

    sleep 5

    # Test DEX well-known endpoint
    if curl -s -k http://localhost:5556/dex/.well-known/openid_configuration > /dev/null; then
        log_success "DEX OpenID configuration endpoint is accessible"
    else
        log_error "DEX OpenID configuration endpoint is not accessible"
        failed=1
    fi

    # Kill port forward
    kill $pf_dex_pid 2>/dev/null || true

    return $failed
}

test_argocd_server() {
    log_info "Testing ArgoCD server endpoints..."

    local failed=0

    # Port forward to test locally
    kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:443 &
    local pf_server_pid=$!

    sleep 5

    # Test ArgoCD server health
    if curl -s -k https://localhost:8080/healthz | grep -q "ok"; then
        log_success "ArgoCD server health endpoint is accessible"
    else
        log_error "ArgoCD server health endpoint is not accessible"
        failed=1
    fi

    # Test if login page includes GitHub option
    local login_page=$(curl -s -k https://localhost:8080/ || echo "")

    if echo "$login_page" | grep -q -i "github\|login.*via"; then
        log_success "GitHub login option appears to be available"
    else
        log_warning "GitHub login option not clearly visible (manual verification needed)"
    fi

    # Kill port forward
    kill $pf_server_pid 2>/dev/null || true

    return $failed
}

test_dns_resolution() {
    log_info "Testing DNS resolution for ArgoCD..."

    if nslookup argocd.test.com &> /dev/null || getent hosts argocd.test.com &> /dev/null; then
        log_success "DNS resolution for argocd.test.com is working"
    else
        log_warning "DNS resolution for argocd.test.com failed"
        log_info "Make sure you have this entry in /etc/hosts:"
        log_info "127.0.0.1 argocd.test.com"
        return 1
    fi

    return 0
}

check_logs_for_errors() {
    log_info "Checking logs for authentication errors..."

    local failed=0

    # Check ArgoCD server logs for errors
    local server_errors=$(kubectl logs deployment/argocd-server -n $NAMESPACE --tail=50 | grep -i "error\|failed\|panic" | wc -l)

    if [[ $server_errors -gt 0 ]]; then
        log_warning "Found $server_errors potential errors in ArgoCD server logs"
        log_info "Recent errors:"
        kubectl logs deployment/argocd-server -n $NAMESPACE --tail=10 | grep -i "error\|failed\|panic" || true
    else
        log_success "No obvious errors in ArgoCD server logs"
    fi

    # Check DEX server logs for errors
    local dex_errors=$(kubectl logs deployment/argocd-dex-server -n $NAMESPACE --tail=50 | grep -i "error\|failed\|panic" | wc -l)

    if [[ $dex_errors -gt 0 ]]; then
        log_warning "Found $dex_errors potential errors in DEX server logs"
        log_info "Recent errors:"
        kubectl logs deployment/argocd-dex-server -n $NAMESPACE --tail=10 | grep -i "error\|failed\|panic" || true
    else
        log_success "No obvious errors in DEX server logs"
    fi

    return 0
}

display_manual_test_instructions() {
    log_info "Manual testing instructions:"
    echo ""
    echo -e "${BLUE}1. Access ArgoCD UI:${NC}"
    echo "   Open https://argocd.test.com in your browser"
    echo ""
    echo -e "${BLUE}2. Verify GitHub login option:${NC}"
    echo "   - You should see a 'Login via GitHub' button"
    echo "   - If not visible, check browser console for errors"
    echo ""
    echo -e "${BLUE}3. Test GitHub authentication:${NC}"
    echo "   - Click 'Login via GitHub'"
    echo "   - You should be redirected to GitHub OAuth"
    echo "   - Authorize the ArgoCD application"
    echo "   - You should be redirected back to ArgoCD"
    echo ""
    echo -e "${BLUE}4. Verify RBAC permissions:${NC}"
    echo "   - Check if you can access appropriate resources"
    echo "   - Admin users should see all options"
    echo "   - Regular users should have limited access"
    echo ""
    echo -e "${BLUE}5. Test emergency admin access:${NC}"
    echo "   - The admin user should still work for emergency access"
    echo "   - Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
}

generate_test_report() {
    local total_tests=$1
    local failed_tests=$2

    echo ""
    echo "=========================="
    echo "  GitHub Auth Test Report"
    echo "=========================="
    echo ""
    echo "Total tests: $total_tests"
    echo "Passed: $((total_tests - failed_tests))"
    echo "Failed: $failed_tests"
    echo ""

    if [[ $failed_tests -eq 0 ]]; then
        log_success "All automated tests passed! 🎉"
        echo ""
        log_info "Proceed with manual testing using the instructions above."
    else
        log_warning "Some tests failed. Please review the errors above."
        echo ""
        log_info "Common issues and solutions:"
        echo "- Pod not ready: Wait longer or check resource limits"
        echo "- Configuration missing: Re-run setup-github-auth.sh"
        echo "- DNS issues: Add argocd.test.com to /etc/hosts"
        echo "- Secret issues: Verify GitHub OAuth credentials"
    fi
}

# Main test execution
main() {
    log_info "Starting ArgoCD GitHub Authentication Tests"
    echo ""

    local total_tests=0
    local failed_tests=0

    # Test 1: ArgoCD pods
    ((total_tests++))
    if ! test_argocd_pods; then
        ((failed_tests++))
    fi
    echo ""

    # Test 2: Configuration
    ((total_tests++))
    if ! test_configuration; then
        ((failed_tests++))
    fi
    echo ""

    # Test 3: DNS resolution
    ((total_tests++))
    if ! test_dns_resolution; then
        ((failed_tests++))
    fi
    echo ""

    # Test 4: DEX endpoints
    ((total_tests++))
    if ! test_dex_endpoints; then
        ((failed_tests++))
    fi
    echo ""

    # Test 5: ArgoCD server
    ((total_tests++))
    if ! test_argocd_server; then
        ((failed_tests++))
    fi
    echo ""

    # Check logs (informational only)
    check_logs_for_errors
    echo ""

    # Display manual testing instructions
    display_manual_test_instructions

    # Generate report
    generate_test_report $total_tests $failed_tests

    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Run main function
main "$@"