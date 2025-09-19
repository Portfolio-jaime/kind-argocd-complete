#!/bin/bash

# Complete ArgoCD + Kind Backup Script
#
# Este script crea un backup completo de la instalación de ArgoCD en Kind
# incluyendo configuraciones, secrets, datos y estado del cluster

set -e

# Configuración
BACKUP_DIR="/Users/jaime.henao/arheanja/Backstage-solutions/kind-argocd-complete/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/complete-backup-$TIMESTAMP"

echo "🗄️  Iniciando backup completo de ArgoCD + Kind..."
echo "📁 Directorio de backup: $BACKUP_PATH"

# Crear directorio de backup
mkdir -p "$BACKUP_PATH"

# Verificar prerequisitos
echo "🔍 Verificando prerequisitos..."

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl no está instalado"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ helm no está instalado"
    exit 1
fi

if ! command -v kind &> /dev/null; then
    echo "❌ kind no está instalado"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ No se puede conectar al cluster"
    exit 1
fi

echo "✅ Prerequisitos verificados"

# 1. Backup de ArgoCD Resources
echo "📦 1/8 - Backup de recursos de ArgoCD..."
kubectl get all -n argocd -o yaml > "$BACKUP_PATH/argocd-all-resources.yaml"
kubectl get configmaps -n argocd -o yaml > "$BACKUP_PATH/argocd-configmaps.yaml"
kubectl get secrets -n argocd -o yaml > "$BACKUP_PATH/argocd-secrets.yaml"
kubectl get ingress -n argocd -o yaml > "$BACKUP_PATH/argocd-ingress.yaml"

# 2. Backup de Helm Information
echo "📦 2/8 - Backup de información de Helm..."
helm list -A -o yaml > "$BACKUP_PATH/helm-releases.yaml"
helm get values argocd -n argocd > "$BACKUP_PATH/argocd-helm-values.yaml"
helm get manifest argocd -n argocd > "$BACKUP_PATH/argocd-helm-manifest.yaml"
helm get hooks argocd -n argocd > "$BACKUP_PATH/argocd-helm-hooks.yaml" 2>/dev/null || echo "No hooks found"
helm get notes argocd -n argocd > "$BACKUP_PATH/argocd-helm-notes.txt"

# 3. Backup de ArgoCD Applications
echo "📦 3/8 - Backup de aplicaciones de ArgoCD..."
kubectl get applications -n argocd -o yaml > "$BACKUP_PATH/argocd-applications.yaml" 2>/dev/null || echo "No applications found"
kubectl get appprojects -n argocd -o yaml > "$BACKUP_PATH/argocd-appprojects.yaml" 2>/dev/null || echo "No app projects found"

# 4. Backup de Ingress Controller
echo "📦 4/8 - Backup de Ingress Controller..."
kubectl get all -n ingress-nginx -o yaml > "$BACKUP_PATH/ingress-nginx-resources.yaml" 2>/dev/null || echo "Ingress nginx not found"

# 5. Backup de Certificates y TLS
echo "📦 5/8 - Backup de certificados..."
kubectl get certificates -A -o yaml > "$BACKUP_PATH/certificates.yaml" 2>/dev/null || echo "No certificates found"
kubectl get certificaterequests -A -o yaml > "$BACKUP_PATH/certificate-requests.yaml" 2>/dev/null || echo "No certificate requests found"

# 6. Backup de Kind Cluster Info
echo "📦 6/8 - Backup de información del cluster Kind..."
kind get clusters > "$BACKUP_PATH/kind-clusters.txt"
kubectl cluster-info > "$BACKUP_PATH/cluster-info.txt"
kubectl get nodes -o yaml > "$BACKUP_PATH/nodes.yaml"
kubectl get namespaces -o yaml > "$BACKUP_PATH/namespaces.yaml"

# 7. Backup de Network Configuration
echo "📦 7/8 - Backup de configuración de red..."
kubectl get networkpolicies -A -o yaml > "$BACKUP_PATH/network-policies.yaml" 2>/dev/null || echo "No network policies found"
kubectl get services -A -o yaml > "$BACKUP_PATH/all-services.yaml"

# 8. Backup de RBAC y Security
echo "📦 8/8 - Backup de RBAC y configuraciones de seguridad..."
kubectl get clusterroles -o yaml > "$BACKUP_PATH/cluster-roles.yaml"
kubectl get clusterrolebindings -o yaml > "$BACKUP_PATH/cluster-role-bindings.yaml"
kubectl get roles -A -o yaml > "$BACKUP_PATH/roles.yaml"
kubectl get rolebindings -A -o yaml > "$BACKUP_PATH/role-bindings.yaml"

# Crear archivo de metadatos
echo "📝 Creando metadatos del backup..."
cat > "$BACKUP_PATH/backup-metadata.yaml" <<EOF
backupInfo:
  timestamp: $TIMESTAMP
  date: $(date)
  backupPath: $BACKUP_PATH
  createdBy: $(whoami)
  hostname: $(hostname)
clusterInfo:
  kindVersion: $(kind version | head -1)
  kubectlVersion: $(kubectl version --client --short)
  helmVersion: $(helm version --short)
  clusterName: $(kubectl config current-context)
argoCDInfo:
  namespace: argocd
  helmRelease: $(helm list -n argocd -o json | jq -r '.[0].name' 2>/dev/null || echo "argocd")
  chartVersion: $(helm list -n argocd -o json | jq -r '.[0].chart' 2>/dev/null || echo "unknown")
  appVersion: $(helm list -n argocd -o json | jq -r '.[0].app_version' 2>/dev/null || echo "unknown")
  domain: $(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}' 2>/dev/null || echo "unknown")
EOF

# Crear script de restauración
echo "🔧 Creando script de restauración..."
cat > "$BACKUP_PATH/restore.sh" <<'EOF'
#!/bin/bash

# ArgoCD + Kind Restore Script
# Generado automáticamente durante el backup

set -e

BACKUP_DIR="$(dirname "$0")"
echo "🔄 Restaurando desde: $BACKUP_DIR"

echo "⚠️  ADVERTENCIA: Este script restaurará la configuración completa de ArgoCD"
echo "Esto sobrescribirá la configuración actual. ¿Continuar? (y/N)"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "❌ Restauración cancelada"
    exit 1
fi

# Verificar que el cluster esté disponible
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ No se puede conectar al cluster"
    exit 1
fi

echo "🔄 1/5 - Restaurando namespace argocd..."
kubectl apply -f "$BACKUP_DIR/namespaces.yaml" || echo "Warning: Could not restore all namespaces"

echo "🔄 2/5 - Restaurando configuraciones de ArgoCD..."
kubectl apply -f "$BACKUP_DIR/argocd-configmaps.yaml"
kubectl apply -f "$BACKUP_DIR/argocd-secrets.yaml"

echo "🔄 3/5 - Restaurando recursos de ArgoCD..."
kubectl apply -f "$BACKUP_DIR/argocd-all-resources.yaml"

echo "🔄 4/5 - Restaurando ingress..."
kubectl apply -f "$BACKUP_DIR/argocd-ingress.yaml" || echo "Warning: Could not restore ingress"

echo "🔄 5/5 - Restaurando aplicaciones..."
kubectl apply -f "$BACKUP_DIR/argocd-applications.yaml" || echo "Warning: No applications to restore"
kubectl apply -f "$BACKUP_DIR/argocd-appprojects.yaml" || echo "Warning: No app projects to restore"

echo "⏳ Esperando a que ArgoCD esté listo..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo "✅ Restauración completada!"
echo "🌐 ArgoCD debería estar disponible en: $(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}' 2>/dev/null || echo 'URL not found')"
EOF

chmod +x "$BACKUP_PATH/restore.sh"

# Crear script de rollback específico para Helm
echo "🔧 Creando script de rollback Helm..."
cat > "$BACKUP_PATH/helm-rollback.sh" <<EOF
#!/bin/bash

# Helm Rollback Script para ArgoCD

set -e

echo "🔄 Rollback de ArgoCD usando Helm..."

# Verificar release actual
CURRENT_REVISION=\$(helm list -n argocd -o json | jq -r '.[0].revision')
echo "📊 Revisión actual: \$CURRENT_REVISION"

# Mostrar historial
echo "📋 Historial de releases:"
helm history argocd -n argocd

echo "¿A qué revisión quieres hacer rollback? (Enter para la anterior)"
read -r revision

if [ -z "\$revision" ]; then
    echo "🔄 Haciendo rollback a la revisión anterior..."
    helm rollback argocd -n argocd
else
    echo "🔄 Haciendo rollback a la revisión \$revision..."
    helm rollback argocd \$revision -n argocd
fi

echo "⏳ Esperando a que el rollback complete..."
kubectl rollout status deployment/argocd-server -n argocd

echo "✅ Rollback completado!"
EOF

chmod +x "$BACKUP_PATH/helm-rollback.sh"

# Comprimir backup (opcional)
if command -v tar &> /dev/null; then
    echo "🗜️  Comprimiendo backup..."
    tar -czf "$BACKUP_PATH.tar.gz" -C "$BACKUP_DIR" "complete-backup-$TIMESTAMP"
    echo "📦 Backup comprimido: $BACKUP_PATH.tar.gz"
fi

# Crear índice de backups
echo "📋 Actualizando índice de backups..."
cat > "$BACKUP_DIR/backup-index.txt" <<EOF
# ArgoCD + Kind Backup Index
# Última actualización: $(date)

EOF

ls -la "$BACKUP_DIR"/complete-backup-* >> "$BACKUP_DIR/backup-index.txt" 2>/dev/null || true

echo ""
echo "✅ Backup completo finalizado exitosamente!"
echo ""
echo "📁 Ubicación: $BACKUP_PATH"
echo "📦 Comprimido: $BACKUP_PATH.tar.gz"
echo ""
echo "🔄 Para restaurar:"
echo "   $BACKUP_PATH/restore.sh"
echo ""
echo "🔄 Para rollback Helm:"
echo "   $BACKUP_PATH/helm-rollback.sh"
echo ""
echo "📊 Contenido del backup:"
echo "   - Recursos de ArgoCD (all, configmaps, secrets, ingress)"
echo "   - Información de Helm (values, manifest, hooks, notes)"
echo "   - Aplicaciones y proyectos de ArgoCD"
echo "   - Configuración de Ingress Controller"
echo "   - Certificados y TLS"
echo "   - Información del cluster Kind"
echo "   - Configuración de red"
echo "   - RBAC y seguridad"
echo "   - Scripts de restauración y rollback"
echo ""

# Limpiar backups antiguos (mantener últimos 10)
echo "🧹 Limpiando backups antiguos..."
find "$BACKUP_DIR" -name "complete-backup-*" -type d | sort -r | tail -n +11 | xargs rm -rf 2>/dev/null || true
find "$BACKUP_DIR" -name "complete-backup-*.tar.gz" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true

echo "📈 Backups disponibles: $(find "$BACKUP_DIR" -name "complete-backup-*" -type d | wc -l)"