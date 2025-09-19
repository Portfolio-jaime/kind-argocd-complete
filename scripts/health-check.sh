#!/bin/bash

# ArgoCD + Kind Health Check Script
#
# Script completo para verificar el estado de la instalación

set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Funciones de utilidad
check_start() {
    ((CHECKS_TOTAL++))
    echo -n "🔍 $1... "
}

check_pass() {
    ((CHECKS_PASSED++))
    echo -e "${GREEN}✅ OK${NC}"
    [ -n "$1" ] && echo "   ℹ️  $1"
}

check_fail() {
    ((CHECKS_FAILED++))
    echo -e "${RED}❌ FAIL${NC}"
    [ -n "$1" ] && echo -e "   ${RED}💥 $1${NC}"
}

check_warning() {
    ((CHECKS_WARNING++))
    echo -e "${YELLOW}⚠️  WARNING${NC}"
    [ -n "$1" ] && echo -e "   ${YELLOW}⚠️  $1${NC}"
}

# Verificar Docker
check_docker() {
    check_start "Docker está corriendo"

    if ! docker info >/dev/null 2>&1; then
        check_fail "Docker no está corriendo"
        return 1
    fi

    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    check_pass "Docker v$docker_version"
}

# Verificar Kind
check_kind() {
    check_start "Kind cluster disponible"

    if ! command -v kind >/dev/null 2>&1; then
        check_fail "Kind no está instalado"
        return 1
    fi

    local clusters=$(kind get clusters 2>/dev/null | wc -l | tr -d ' ')
    if [ "$clusters" -eq 0 ]; then
        check_fail "No hay clusters Kind"
        return 1
    fi

    check_pass "$clusters cluster(s) encontrado(s)"
}

# Verificar kubectl
check_kubectl() {
    check_start "kubectl conectividad"

    if ! command -v kubectl >/dev/null 2>&1; then
        check_fail "kubectl no está instalado"
        return 1
    fi

    if ! kubectl cluster-info >/dev/null 2>&1; then
        check_fail "No se puede conectar al cluster"
        return 1
    fi

    local context=$(kubectl config current-context)
    check_pass "Conectado a $context"
}

# Verificar namespace ArgoCD
check_argocd_namespace() {
    check_start "Namespace argocd"

    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        check_fail "Namespace argocd no existe"
        return 1
    fi

    check_pass "Namespace argocd existe"
}

# Verificar pods de ArgoCD
check_argocd_pods() {
    check_start "Pods de ArgoCD"

    local pods_output=$(kubectl get pods -n argocd --no-headers 2>/dev/null)
    if [ -z "$pods_output" ]; then
        check_fail "No se encontraron pods de ArgoCD"
        return 1
    fi

    local total_pods=$(echo "$pods_output" | wc -l | tr -d ' ')
    local running_pods=$(echo "$pods_output" | grep -c "Running" || echo "0")
    local ready_pods=$(echo "$pods_output" | awk '{print $2}' | grep -c "1/1\|2/2" || echo "0")

    if [ "$running_pods" -eq "$total_pods" ] && [ "$ready_pods" -eq "$total_pods" ]; then
        check_pass "$running_pods/$total_pods pods Running y Ready"
    elif [ "$running_pods" -eq "$total_pods" ]; then
        check_warning "$running_pods/$total_pods pods Running, pero algunos no Ready"
    else
        check_fail "$running_pods/$total_pods pods Running"
        echo "$pods_output" | grep -v "Running" | head -3
    fi
}

# Verificar servicios de ArgoCD
check_argocd_services() {
    check_start "Servicios de ArgoCD"

    local services=$(kubectl get svc -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$services" -eq 0 ]; then
        check_fail "No se encontraron servicios"
        return 1
    fi

    local server_svc=$(kubectl get svc argocd-server -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$server_svc" -eq 0 ]; then
        check_fail "Servicio argocd-server no encontrado"
        return 1
    fi

    check_pass "$services servicios encontrados"
}

# Verificar Helm release
check_helm_release() {
    check_start "Helm release de ArgoCD"

    if ! command -v helm >/dev/null 2>&1; then
        check_warning "Helm no está instalado"
        return 0
    fi

    local helm_status=$(helm status argocd -n argocd --output json 2>/dev/null | jq -r '.info.status' 2>/dev/null || echo "")

    if [ "$helm_status" = "deployed" ]; then
        local chart_version=$(helm list -n argocd --output json 2>/dev/null | jq -r '.[0].chart' 2>/dev/null || echo "unknown")
        check_pass "Status: $helm_status, Chart: $chart_version"
    elif [ -n "$helm_status" ]; then
        check_warning "Status: $helm_status"
    else
        check_warning "Release no encontrado o no gestionado por Helm"
    fi
}

# Verificar Ingress
check_ingress() {
    check_start "Ingress de ArgoCD"

    local ingress_exists=$(kubectl get ingress argocd-server -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$ingress_exists" -eq 0 ]; then
        check_warning "Ingress argocd-server no encontrado"
        return 0
    fi

    local ingress_host=$(kubectl get ingress argocd-server -n argocd -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
    local ingress_class=$(kubectl get ingress argocd-server -n argocd -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)

    check_pass "Host: $ingress_host, Class: $ingress_class"
}

# Verificar Ingress Controller
check_ingress_controller() {
    check_start "Ingress Controller (nginx)"

    local nginx_pods=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$nginx_pods" -eq 0 ]; then
        check_warning "nginx Ingress Controller no encontrado"
        return 0
    fi

    check_pass "$nginx_pods pod(s) nginx corriendo"
}

# Verificar certificados TLS
check_tls_certificates() {
    check_start "Certificados TLS"

    local tls_secret=$(kubectl get secret argocd-server-tls -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$tls_secret" -eq 0 ]; then
        check_warning "Secret argocd-server-tls no encontrado"
        return 0
    fi

    # Verificar validez del certificado
    local cert_data=$(kubectl get secret argocd-server-tls -n argocd -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null)
    if [ -n "$cert_data" ]; then
        local expiry=$(echo "$cert_data" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
        if [ -n "$expiry" ]; then
            check_pass "Certificado válido hasta: $expiry"
        else
            check_warning "No se pudo verificar la validez del certificado"
        fi
    else
        check_warning "No se pudo leer el certificado"
    fi
}

# Verificar conectividad HTTP
check_http_connectivity() {
    check_start "Conectividad HTTP"

    local argocd_url=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}' 2>/dev/null || echo "")

    if [ -z "$argocd_url" ]; then
        check_warning "URL de ArgoCD no configurada"
        return 0
    fi

    # Test básico de conectividad
    if curl -k -s -o /dev/null -w "%{http_code}" "$argocd_url" --connect-timeout 10 | grep -q "200\|302\|401"; then
        check_pass "Respuesta HTTP desde $argocd_url"
    else
        # Verificar hosts file
        local host=$(echo "$argocd_url" | sed 's|https\?://||' | cut -d'/' -f1)
        if ! grep -q "$host" /etc/hosts 2>/dev/null; then
            check_warning "Agregue '$host' a /etc/hosts: echo '127.0.0.1 $host' | sudo tee -a /etc/hosts"
        else
            check_warning "No se pudo conectar a $argocd_url"
        fi
    fi
}

# Verificar autenticación GitHub (si está configurada)
check_github_auth() {
    check_start "Configuración GitHub OAuth"

    local oidc_config=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.oidc\.config}' 2>/dev/null)

    if [ -z "$oidc_config" ]; then
        check_warning "GitHub OAuth no configurado"
        return 0
    fi

    if echo "$oidc_config" | grep -q "github"; then
        local client_id=$(echo "$oidc_config" | grep "clientId" | awk '{print $2}' || echo "")
        if [ -n "$client_id" ]; then
            check_pass "GitHub OAuth configurado (Client ID: ${client_id:0:8}...)"
        else
            check_warning "GitHub OAuth configurado pero sin Client ID válido"
        fi
    else
        check_warning "OAuth configurado pero no para GitHub"
    fi
}

# Verificar recursos del sistema
check_system_resources() {
    check_start "Recursos del sistema"

    # Verificar memoria y CPU de pods
    local high_memory_pods=$(kubectl top pods -n argocd 2>/dev/null | awk 'NR>1 && $3~/[0-9]+Mi/ && $3+0 > 500 {print $1}' | wc -l | tr -d ' ')
    local high_cpu_pods=$(kubectl top pods -n argocd 2>/dev/null | awk 'NR>1 && $2~/[0-9]+m/ && $2+0 > 100 {print $1}' | wc -l | tr -d ' ')

    if [ "$high_memory_pods" -gt 0 ] || [ "$high_cpu_pods" -gt 0 ]; then
        check_warning "$high_memory_pods pod(s) con alta memoria, $high_cpu_pods pod(s) con alta CPU"
    else
        check_pass "Uso de recursos normal"
    fi
}

# Verificar logs para errores
check_error_logs() {
    check_start "Logs de errores recientes"

    local error_count=$(kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --since=10m 2>/dev/null | grep -i "error\|fail\|panic" | wc -l | tr -d ' ')

    if [ "$error_count" -gt 5 ]; then
        check_warning "$error_count errores en logs recientes (últimos 10 min)"
    else
        check_pass "Sin errores significativos en logs recientes"
    fi
}

# Verificar Applications de ArgoCD
check_argocd_applications() {
    check_start "Aplicaciones de ArgoCD"

    local app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$app_count" -eq 0 ]; then
        check_warning "No hay aplicaciones desplegadas"
    else
        local healthy_apps=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c "Healthy" || echo "0")
        local synced_apps=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c "Synced" || echo "0")

        if [ "$healthy_apps" -eq "$app_count" ] && [ "$synced_apps" -eq "$app_count" ]; then
            check_pass "$app_count aplicaciones - todas Healthy y Synced"
        else
            check_warning "$healthy_apps/$app_count Healthy, $synced_apps/$app_count Synced"
        fi
    fi
}

# Función principal
main() {
    echo "🏥 ArgoCD + Kind Health Check"
    echo "============================="
    echo ""

    # Ejecutar todas las verificaciones
    check_docker
    check_kind
    check_kubectl
    check_argocd_namespace
    check_argocd_pods
    check_argocd_services
    check_helm_release
    check_ingress
    check_ingress_controller
    check_tls_certificates
    check_http_connectivity
    check_github_auth
    check_system_resources
    check_error_logs
    check_argocd_applications

    # Resumen
    echo ""
    echo "📊 Resumen del Health Check"
    echo "=========================="
    echo -e "Total verificaciones: $CHECKS_TOTAL"
    echo -e "${GREEN}✅ Pasaron: $CHECKS_PASSED${NC}"
    echo -e "${YELLOW}⚠️  Advertencias: $CHECKS_WARNING${NC}"
    echo -e "${RED}❌ Fallaron: $CHECKS_FAILED${NC}"

    # Determinar estado general
    if [ "$CHECKS_FAILED" -eq 0 ]; then
        if [ "$CHECKS_WARNING" -eq 0 ]; then
            echo -e "\n${GREEN}🎉 Sistema completamente saludable!${NC}"
            exit_code=0
        else
            echo -e "\n${YELLOW}⚠️  Sistema funcionando con algunas advertencias${NC}"
            exit_code=1
        fi
    else
        echo -e "\n${RED}💥 Sistema tiene problemas críticos${NC}"
        exit_code=2
    fi

    # Información útil
    echo ""
    echo "🔧 Información útil:"
    local argocd_url=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}' 2>/dev/null || echo "No configurado")
    echo "   ArgoCD URL: $argocd_url"

    local admin_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "No disponible")
    if [ "$admin_password" != "No disponible" ]; then
        echo "   Admin password: $admin_password"
    fi

    echo ""
    echo "📝 Para más detalles:"
    echo "   kubectl get all -n argocd"
    echo "   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server"
    echo "   helm status argocd -n argocd"

    exit $exit_code
}

# Verificar si se está ejecutando directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi