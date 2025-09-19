#!/bin/bash

# ArgoCD + Kind Rollback Script
#
# Script maestro para diferentes tipos de rollback:
# 1. Rollback desde backup completo
# 2. Rollback de Helm
# 3. Rollback de configuración específica
# 4. Emergency rollback

set -e

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$(dirname "$SCRIPT_DIR")/backups"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones de utilidad
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Verificar prerequisitos
verify_prerequisites() {
    log_info "Verificando prerequisitos..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl no está instalado"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm no está instalado"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "No se puede conectar al cluster"
        exit 1
    fi

    log_success "Prerequisitos verificados"
}

# Mostrar backups disponibles
show_available_backups() {
    log_info "Backups disponibles:"
    echo ""

    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "No se encontró directorio de backups: $BACKUP_DIR"
        return 1
    fi

    local backups=($(find "$BACKUP_DIR" -name "complete-backup-*" -type d | sort -r))

    if [ ${#backups[@]} -eq 0 ]; then
        log_warning "No se encontraron backups"
        return 1
    fi

    local count=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local timestamp=${backup_name#complete-backup-}
        local date=$(echo "$timestamp" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

        # Verificar si existe archivo de metadatos
        local metadata_file="$backup/backup-metadata.yaml"
        local additional_info=""
        if [ -f "$metadata_file" ]; then
            additional_info=$(grep -A 10 "argoCDInfo:" "$metadata_file" 2>/dev/null | grep "chartVersion\|domain" | head -2 | tr '\n' ' ' || echo "")
        fi

        echo "$count) $backup_name"
        echo "   📅 Fecha: $date"
        echo "   📁 Ruta: $backup"
        [ -n "$additional_info" ] && echo "   ℹ️  Info: $additional_info"
        echo ""
        ((count++))
    done
}

# Rollback desde backup completo
rollback_from_backup() {
    log_info "Rollback desde backup completo"
    echo ""

    show_available_backups || return 1

    echo ""
    echo "Selecciona el número del backup para restaurar (0 para cancelar):"
    read -r selection

    if [ "$selection" = "0" ]; then
        log_info "Rollback cancelado"
        return 0
    fi

    local backups=($(find "$BACKUP_DIR" -name "complete-backup-*" -type d | sort -r))

    if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
        log_error "Selección inválida"
        return 1
    fi

    local selected_backup="${backups[$((selection-1))]}"
    log_info "Backup seleccionado: $(basename "$selected_backup")"

    # Verificar que existe el script de restauración
    local restore_script="$selected_backup/restore.sh"
    if [ ! -f "$restore_script" ]; then
        log_error "Script de restauración no encontrado: $restore_script"
        return 1
    fi

    # Confirmación final
    echo ""
    log_warning "ADVERTENCIA: Esto sobrescribirá la configuración actual de ArgoCD"
    echo "¿Continuar con el rollback? (y/N)"
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelado"
        return 0
    fi

    # Ejecutar rollback
    log_info "Ejecutando rollback..."
    bash "$restore_script"

    log_success "Rollback desde backup completado"
}

# Rollback de Helm
rollback_helm() {
    log_info "Rollback de Helm para ArgoCD"
    echo ""

    # Verificar que existe el release
    if ! helm list -n argocd | grep -q argocd; then
        log_error "Release de ArgoCD no encontrado"
        return 1
    fi

    # Mostrar historial
    log_info "Historial de releases:"
    helm history argocd -n argocd

    echo ""
    echo "¿A qué revisión quieres hacer rollback? (Enter para la anterior, 0 para cancelar):"
    read -r revision

    if [ "$revision" = "0" ]; then
        log_info "Rollback cancelado"
        return 0
    fi

    # Hacer backup antes del rollback
    log_info "Creando backup antes del rollback..."
    local pre_rollback_backup="$BACKUP_DIR/pre-rollback-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$pre_rollback_backup"
    helm get values argocd -n argocd > "$pre_rollback_backup/values-before-rollback.yaml"
    kubectl get configmap argocd-cm -n argocd -o yaml > "$pre_rollback_backup/configmap-before-rollback.yaml"

    # Ejecutar rollback
    if [ -z "$revision" ]; then
        log_info "Haciendo rollback a la revisión anterior..."
        helm rollback argocd -n argocd
    else
        log_info "Haciendo rollback a la revisión $revision..."
        helm rollback argocd "$revision" -n argocd
    fi

    # Esperar a que el rollback complete
    log_info "Esperando a que el rollback complete..."
    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

    log_success "Rollback de Helm completado"
}

# Rollback de configuración específica
rollback_config() {
    log_info "Rollback de configuración específica"
    echo ""

    echo "Opciones de rollback de configuración:"
    echo "1) ConfigMap argocd-cm (configuración principal)"
    echo "2) ConfigMap argocd-rbac-cm (RBAC)"
    echo "3) Secret argocd-secret (credenciales)"
    echo "4) Ingress argocd-server"
    echo "5) Volver al menú principal"
    echo ""
    echo "Selecciona una opción:"
    read -r config_option

    case $config_option in
        1)
            rollback_specific_resource "configmap" "argocd-cm"
            ;;
        2)
            rollback_specific_resource "configmap" "argocd-rbac-cm"
            ;;
        3)
            rollback_specific_resource "secret" "argocd-secret"
            ;;
        4)
            rollback_specific_resource "ingress" "argocd-server"
            ;;
        5)
            return 0
            ;;
        *)
            log_error "Opción inválida"
            return 1
            ;;
    esac
}

# Rollback de recurso específico
rollback_specific_resource() {
    local resource_type="$1"
    local resource_name="$2"

    log_info "Rollback de $resource_type/$resource_name"

    show_available_backups || return 1

    echo ""
    echo "Selecciona el número del backup para restaurar $resource_type/$resource_name (0 para cancelar):"
    read -r selection

    if [ "$selection" = "0" ]; then
        log_info "Rollback cancelado"
        return 0
    fi

    local backups=($(find "$BACKUP_DIR" -name "complete-backup-*" -type d | sort -r))

    if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
        log_error "Selección inválida"
        return 1
    fi

    local selected_backup="${backups[$((selection-1))]}"

    # Buscar el archivo apropiado
    local backup_file=""
    case $resource_type in
        "configmap")
            backup_file="$selected_backup/argocd-configmaps.yaml"
            ;;
        "secret")
            backup_file="$selected_backup/argocd-secrets.yaml"
            ;;
        "ingress")
            backup_file="$selected_backup/argocd-ingress.yaml"
            ;;
    esac

    if [ ! -f "$backup_file" ]; then
        log_error "Archivo de backup no encontrado: $backup_file"
        return 1
    fi

    # Hacer backup del recurso actual
    local current_backup="$BACKUP_DIR/current-$resource_type-$resource_name-$(date +%Y%m%d-%H%M%S).yaml"
    kubectl get "$resource_type" "$resource_name" -n argocd -o yaml > "$current_backup" 2>/dev/null || log_warning "No se pudo hacer backup del recurso actual"

    # Extraer y aplicar el recurso específico
    log_info "Restaurando $resource_type/$resource_name..."

    # Usar yq si está disponible, sino usar grep/awk
    if command -v yq &> /dev/null; then
        yq eval "select(.metadata.name == \"$resource_name\")" "$backup_file" | kubectl apply -f -
    else
        # Método alternativo sin yq
        kubectl apply -f "$backup_file"
    fi

    log_success "Rollback de $resource_type/$resource_name completado"
}

# Emergency rollback
emergency_rollback() {
    log_warning "EMERGENCY ROLLBACK - Restauración rápida a estado funcional"
    echo ""

    log_info "Este rollback intentará:"
    echo "1. Restaurar la configuración básica de ArgoCD"
    echo "2. Reiniciar todos los servicios"
    echo "3. Verificar que esté funcionando"
    echo ""

    echo "¿Continuar con emergency rollback? (y/N)"
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Emergency rollback cancelado"
        return 0
    fi

    # Buscar el backup más reciente
    local latest_backup=$(find "$BACKUP_DIR" -name "complete-backup-*" -type d | sort -r | head -1)

    if [ -z "$latest_backup" ]; then
        log_error "No se encontró ningún backup para emergency rollback"
        return 1
    fi

    log_info "Usando backup más reciente: $(basename "$latest_backup")"

    # Restaurar configuraciones críticas
    log_info "Restaurando configuraciones críticas..."

    if [ -f "$latest_backup/argocd-configmaps.yaml" ]; then
        kubectl apply -f "$latest_backup/argocd-configmaps.yaml" || log_warning "No se pudieron restaurar algunos ConfigMaps"
    fi

    if [ -f "$latest_backup/argocd-secrets.yaml" ]; then
        kubectl apply -f "$latest_backup/argocd-secrets.yaml" || log_warning "No se pudieron restaurar algunos Secrets"
    fi

    # Reiniciar servicios
    log_info "Reiniciando servicios de ArgoCD..."
    kubectl rollout restart deployment/argocd-server -n argocd
    kubectl rollout restart deployment/argocd-dex-server -n argocd
    kubectl rollout restart deployment/argocd-repo-server -n argocd
    kubectl rollout restart statefulset/argocd-application-controller -n argocd

    # Esperar a que estén listos
    log_info "Esperando a que los servicios estén listos..."
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

    # Verificar estado
    if kubectl get pods -n argocd | grep -q "Running"; then
        log_success "Emergency rollback completado - ArgoCD parece estar funcionando"

        local argocd_url=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}' 2>/dev/null || echo "URL no encontrada")
        log_info "ArgoCD URL: $argocd_url"
    else
        log_error "Emergency rollback falló - revisa los logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd"
        return 1
    fi
}

# Menú principal
show_menu() {
    echo ""
    echo "=================================="
    echo "   ArgoCD + Kind Rollback Tool"
    echo "=================================="
    echo ""
    echo "Opciones de rollback:"
    echo ""
    echo "1) 🔄 Rollback desde backup completo"
    echo "2) ⎈  Rollback de Helm"
    echo "3) ⚙️  Rollback de configuración específica"
    echo "4) 🚨 Emergency rollback (último backup)"
    echo "5) 📋 Mostrar backups disponibles"
    echo "6) ❌ Salir"
    echo ""
    echo "Selecciona una opción:"
}

# Función principal
main() {
    verify_prerequisites

    while true; do
        show_menu
        read -r choice

        case $choice in
            1)
                rollback_from_backup
                ;;
            2)
                rollback_helm
                ;;
            3)
                rollback_config
                ;;
            4)
                emergency_rollback
                ;;
            5)
                show_available_backups
                ;;
            6)
                log_info "Saliendo..."
                exit 0
                ;;
            *)
                log_error "Opción inválida"
                ;;
        esac

        echo ""
        echo "Presiona Enter para continuar..."
        read -r
    done
}

# Verificar si se está ejecutando directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi