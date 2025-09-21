# 🔧 ArgoCD GitHub Authentication - Guía de Mantenimiento y Operaciones

**Fecha**: 20 de Septiembre, 2025
**Versión**: 1.0
**Estado**: Guía Operativa Completa

---

## 📋 Índice de Operaciones

1. [Operaciones Rutinarias](#operaciones-rutinarias)
2. [Monitoreo y Alertas](#monitoreo-y-alertas)
3. [Mantenimiento Preventivo](#mantenimiento-preventivo)
4. [Actualizaciones y Cambios](#actualizaciones-y-cambios)
5. [Backup y Recovery](#backup-y-recovery)
6. [Escalation y Soporte](#escalation-y-soporte)
7. [Automatización](#automatización)

---

## 🔄 Operaciones Rutinarias

### Verificación Diaria de Salud
```bash
#!/bin/bash
# daily-health-check.sh - Ejecutar cada mañana

echo "🔍 ArgoCD GitHub Auth - Daily Health Check $(date)"
echo "================================================="

# 1. Verificar estado de pods
echo "📦 Pod Status:"
kubectl get pods -n argocd -l app.kubernetes.io/part-of=argocd --no-headers | \
  awk '{print $1, $2, $3}' | column -t

# 2. Verificar servicios
echo -e "\n🌐 Service Status:"
kubectl get svc -n argocd --no-headers | awk '{print $1, $2, $3}' | column -t

# 3. Verificar logs de errores (últimas 24h)
echo -e "\n❌ Recent Errors:"
ERROR_COUNT=$(kubectl logs deployment/argocd-server -n argocd --since=24h | grep -i "error\|failed\|panic" | wc -l)
DEX_ERROR_COUNT=$(kubectl logs deployment/argocd-dex-server -n argocd --since=24h | grep -i "error\|failed\|panic" | wc -l)

echo "ArgoCD Server Errors (24h): $ERROR_COUNT"
echo "DEX Server Errors (24h): $DEX_ERROR_COUNT"

# 4. Verificar autenticación
echo -e "\n🔐 Authentication Test:"
if kubectl run auth-test --image=curlimages/curl --rm --restart=Never -- \
   curl -k -f https://argocd.test.com/healthz >/dev/null 2>&1; then
    echo "✅ ArgoCD endpoint accessible"
else
    echo "❌ ArgoCD endpoint not accessible"
fi

# 5. Verificar DNS
echo -e "\n🌐 DNS Resolution Test:"
if kubectl run dns-test --image=busybox --rm --restart=Never -- \
   nslookup argocd.test.com | grep -q "10.96"; then
    echo "✅ Internal DNS resolution working"
else
    echo "❌ Internal DNS resolution failed"
fi

echo -e "\n✅ Daily health check completed"
```

### Verificación Semanal de Configuración
```bash
#!/bin/bash
# weekly-config-check.sh - Ejecutar cada lunes

echo "📋 ArgoCD GitHub Auth - Weekly Configuration Check"
echo "================================================="

# 1. Verificar configuración DEX
echo "🔧 DEX Configuration:"
if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "dex.config"; then
    echo "✅ DEX configuration present"
    # Verificar GitHub org
    GITHUB_ORG=$(kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 "dex.config" | grep "name:" | tail -1 | awk '{print $3}')
    echo "📍 GitHub Organization: $GITHUB_ORG"
else
    echo "❌ DEX configuration missing"
fi

# 2. Verificar credenciales GitHub
echo -e "\n🔑 GitHub Credentials:"
if kubectl get secret argocd-secret -n argocd -o yaml | grep -q "dex.github.clientId"; then
    echo "✅ GitHub credentials present"
    CLIENT_ID=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientId}' | base64 -d)
    echo "📍 Client ID: ${CLIENT_ID:0:10}..."
else
    echo "❌ GitHub credentials missing"
fi

# 3. Verificar RBAC
echo -e "\n👥 RBAC Configuration:"
if kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep -q "policy.csv"; then
    echo "✅ RBAC policies present"
    ADMIN_GROUPS=$(kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep "role:admin" | wc -l)
    DEV_GROUPS=$(kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep "role:developer" | wc -l)
    echo "📍 Admin groups: $ADMIN_GROUPS, Developer groups: $DEV_GROUPS"
else
    echo "❌ RBAC policies missing"
fi

# 4. Verificar CoreDNS
echo -e "\n🌐 CoreDNS Configuration:"
if kubectl get configmap coredns -n kube-system -o yaml | grep -q "argocd.test.com"; then
    echo "✅ CoreDNS hosts entry present"
    ARGOCD_IP=$(kubectl get configmap coredns -n kube-system -o yaml | grep -B1 "argocd.test.com" | head -1 | awk '{print $1}')
    echo "📍 ArgoCD IP: $ARGOCD_IP"
else
    echo "❌ CoreDNS hosts entry missing"
fi

# 5. Verificar backup reciente
echo -e "\n💾 Backup Status:"
LATEST_BACKUP=$(ls -t backups/ | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    echo "✅ Latest backup: $LATEST_BACKUP"
else
    echo "⚠️ No backups found"
fi

echo -e "\n✅ Weekly configuration check completed"
```

---

## 📊 Monitoreo y Alertas

### Métricas Clave a Monitorear
```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: argocd-github-auth-rules
  namespace: argocd
spec:
  groups:
  - name: argocd-auth
    interval: 30s
    rules:
    # Disponibilidad de componentes
    - alert: ArgoCDServerDown
      expr: up{job="argocd-server-metrics"} == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "ArgoCD Server is down"
        description: "ArgoCD Server has been down for more than 2 minutes"

    - alert: DEXServerDown
      expr: up{job="argocd-dex-server"} == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "DEX Server is down"
        description: "DEX Server has been down for more than 2 minutes"

    # Errores de autenticación
    - alert: HighAuthenticationFailures
      expr: increase(argocd_auth_failures_total[5m]) > 10
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "High number of authentication failures"
        description: "More than 10 authentication failures in the last 5 minutes"

    # Recursos del sistema
    - alert: ArgoCDHighMemoryUsage
      expr: container_memory_usage_bytes{pod=~"argocd-server-.*"} / container_spec_memory_limit_bytes > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "ArgoCD Server high memory usage"
        description: "ArgoCD Server memory usage is above 80%"

    # DNS y conectividad
    - alert: DNSResolutionFailures
      expr: increase(coredns_dns_request_duration_seconds_count{type="NXDOMAIN"}[5m]) > 5
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "DNS resolution failures detected"
        description: "Multiple DNS resolution failures in the last 5 minutes"
```

### Dashboard de Monitoreo
```json
{
  "dashboard": {
    "title": "ArgoCD GitHub Authentication",
    "panels": [
      {
        "title": "Component Health",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"argocd-server-metrics\"}",
            "legendFormat": "ArgoCD Server"
          },
          {
            "expr": "up{job=\"argocd-dex-server\"}",
            "legendFormat": "DEX Server"
          }
        ]
      },
      {
        "title": "Authentication Success Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(argocd_auth_success_total[5m])",
            "legendFormat": "Success Rate"
          },
          {
            "expr": "rate(argocd_auth_failures_total[5m])",
            "legendFormat": "Failure Rate"
          }
        ]
      },
      {
        "title": "Active Sessions",
        "type": "graph",
        "targets": [
          {
            "expr": "argocd_active_sessions_total",
            "legendFormat": "Active Sessions"
          }
        ]
      },
      {
        "title": "Resource Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{pod=~\"argocd-.*\"}[5m])",
            "legendFormat": "CPU Usage - {{pod}}"
          },
          {
            "expr": "container_memory_usage_bytes{pod=~\"argocd-.*\"}/1024/1024",
            "legendFormat": "Memory Usage MB - {{pod}}"
          }
        ]
      }
    ]
  }
}
```

### Script de Monitoreo Automatizado
```bash
#!/bin/bash
# monitor-github-auth.sh - Ejecutar cada 5 minutos via cron

NAMESPACE="argocd"
WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"  # Opcional

# Función para enviar alertas
send_alert() {
    local message="$1"
    local severity="$2"

    echo "$(date): [$severity] $message" >> /var/log/argocd-monitor.log

    # Enviar a Slack (opcional)
    if [ -n "$WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 ArgoCD Alert [$severity]: $message\"}" \
            "$WEBHOOK_URL" >/dev/null 2>&1
    fi
}

# Verificaciones
check_pod_health() {
    local pod_count=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=argocd | grep Running | wc -l)
    if [ $pod_count -lt 2 ]; then
        send_alert "ArgoCD pods not all running. Only $pod_count/2 pods ready" "CRITICAL"
        return 1
    fi
    return 0
}

check_authentication() {
    if ! kubectl run monitor-auth-test --image=curlimages/curl --rm --restart=Never -- \
       curl -k -f https://argocd.test.com/healthz >/dev/null 2>&1; then
        send_alert "ArgoCD authentication endpoint not accessible" "CRITICAL"
        return 1
    fi
    return 0
}

check_dns_resolution() {
    if ! kubectl run monitor-dns-test --image=busybox --rm --restart=Never -- \
       nslookup argocd.test.com | grep -q "10.96" 2>/dev/null; then
        send_alert "DNS resolution for argocd.test.com failed" "WARNING"
        return 1
    fi
    return 0
}

check_error_rate() {
    local error_count=$(kubectl logs deployment/argocd-server -n $NAMESPACE --since=5m | grep -i "error\|failed" | wc -l)
    if [ $error_count -gt 5 ]; then
        send_alert "High error rate detected: $error_count errors in last 5 minutes" "WARNING"
        return 1
    fi
    return 0
}

# Ejecutar verificaciones
ALL_GOOD=true

check_pod_health || ALL_GOOD=false
check_authentication || ALL_GOOD=false
check_dns_resolution || ALL_GOOD=false
check_error_rate || ALL_GOOD=false

if [ "$ALL_GOOD" = true ]; then
    echo "$(date): All checks passed" >> /var/log/argocd-monitor.log
fi
```

---

## 🛠️ Mantenimiento Preventivo

### Rotación de Secretos (Cada 6 meses)
```bash
#!/bin/bash
# rotate-secrets.sh

echo "🔄 Starting secret rotation for ArgoCD GitHub Auth"

# 1. Generar nuevo server secret
NEW_SERVER_SECRET=$(openssl rand -hex 32)
echo "✅ New server secret generated"

# 2. Backup actual
BACKUP_DIR="backups/secret-rotation-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
kubectl get secret argocd-secret -n argocd -o yaml > $BACKUP_DIR/argocd-secret-before.yaml
echo "✅ Current secret backed up to $BACKUP_DIR"

# 3. Actualizar secret
kubectl patch secret argocd-secret -n argocd --type='merge' \
  -p='{"stringData":{"server.secretkey":"'$NEW_SERVER_SECRET'"}}'
echo "✅ Server secret updated in cluster"

# 4. Reiniciar servidor ArgoCD
kubectl rollout restart deployment/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
echo "✅ ArgoCD server restarted successfully"

# 5. Verificar funcionamiento
if ./scripts/test-github-auth.sh >/dev/null 2>&1; then
    echo "✅ Secret rotation completed successfully"
    # Guardar nuevo secret en backup
    kubectl get secret argocd-secret -n argocd -o yaml > $BACKUP_DIR/argocd-secret-after.yaml
else
    echo "❌ Secret rotation failed - rolling back"
    kubectl apply -f $BACKUP_DIR/argocd-secret-before.yaml
    kubectl rollout restart deployment/argocd-server -n argocd
    exit 1
fi

echo "🎉 Secret rotation completed at $(date)"
```

### Actualización de Certificados
```bash
#!/bin/bash
# update-certificates.sh

echo "🔒 Checking TLS certificates status"

# 1. Verificar expiración de certificados
CERT_EXPIRY=$(kubectl get secret argocd-server-tls -n argocd -o jsonpath='{.data.tls\.crt}' | \
              base64 -d | openssl x509 -enddate -noout | cut -d= -f2)
EXPIRY_TIMESTAMP=$(date -d "$CERT_EXPIRY" +%s)
CURRENT_TIMESTAMP=$(date +%s)
DAYS_TO_EXPIRY=$(( ($EXPIRY_TIMESTAMP - $CURRENT_TIMESTAMP) / 86400 ))

echo "📅 Certificate expires in $DAYS_TO_EXPIRY days ($CERT_EXPIRY)"

# 2. Alerta si queda menos de 30 días
if [ $DAYS_TO_EXPIRY -lt 30 ]; then
    echo "⚠️ Certificate expires in less than 30 days - consider renewal"

    # 3. Regenerar certificado automáticamente si queda menos de 7 días
    if [ $DAYS_TO_EXPIRY -lt 7 ]; then
        echo "🔄 Auto-renewing certificate (expires in $DAYS_TO_EXPIRY days)"

        # Backup certificado actual
        BACKUP_DIR="backups/cert-renewal-$(date +%Y%m%d-%H%M%S)"
        mkdir -p $BACKUP_DIR
        kubectl get secret argocd-server-tls -n argocd -o yaml > $BACKUP_DIR/argocd-server-tls.yaml

        # Regenerar certificado (esto depende de cómo tengas configurado cert-manager o similar)
        # kubectl delete secret argocd-server-tls -n argocd
        # kubectl rollout restart deployment/argocd-server -n argocd

        echo "⚠️ Manual intervention required for certificate renewal"
    fi
else
    echo "✅ Certificate validity is good"
fi
```

### Limpieza de Logs y Datos Temporales
```bash
#!/bin/bash
# cleanup-maintenance.sh - Ejecutar semanalmente

echo "🧹 Starting maintenance cleanup"

# 1. Limpiar logs antiguos (> 30 días)
echo "📝 Cleaning old log files..."
find /var/log -name "argocd-*.log" -mtime +30 -delete
find /tmp -name "argocd-*" -mtime +7 -delete

# 2. Limpiar backups antiguos (> 90 días)
echo "💾 Cleaning old backups..."
find backups/ -type d -name "github-auth-*" -mtime +90 -exec rm -rf {} \; 2>/dev/null || true
find backups/ -type d -name "secret-rotation-*" -mtime +90 -exec rm -rf {} \; 2>/dev/null || true

# 3. Limpiar recursos de testing temporales
echo "🧪 Cleaning test resources..."
kubectl delete pods -l "app=test" --all-namespaces --field-selector=status.phase!=Running 2>/dev/null || true

# 4. Verificar uso de disco
echo "💽 Disk usage check:"
df -h | grep -E "(backups|logs)"

# 5. Limpiar cachés de DNS si es necesario
echo "🌐 Flushing DNS cache..."
kubectl delete pods -n kube-system -l k8s-app=kube-dns --grace-period=0 --force 2>/dev/null || true

echo "✅ Maintenance cleanup completed"
```

---

## 🔄 Actualizaciones y Cambios

### Agregar Nuevos Usuarios/Teams
```bash
#!/bin/bash
# add-team.sh - Script para agregar nuevos teams GitHub

if [ $# -ne 2 ]; then
    echo "Usage: $0 <team-name> <role>"
    echo "Example: $0 new-team-name developer"
    exit 1
fi

TEAM_NAME="$1"
ROLE="$2"
GITHUB_ORG="Portfolio-jaime"

echo "➕ Adding GitHub team to ArgoCD RBAC"
echo "Team: $GITHUB_ORG:$TEAM_NAME"
echo "Role: role:$ROLE"

# 1. Backup configuración actual
BACKUP_DIR="backups/team-addition-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > $BACKUP_DIR/argocd-rbac-cm-before.yaml

# 2. Obtener configuración actual
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > /tmp/rbac-config.yaml

# 3. Agregar nueva línea de mapping
NEW_MAPPING="    g, $GITHUB_ORG:$TEAM_NAME, role:$ROLE"
sed -i "/g, $GITHUB_ORG:developers, role:developer/a\\$NEW_MAPPING" /tmp/rbac-config.yaml

# 4. Aplicar configuración actualizada
kubectl apply -f /tmp/rbac-config.yaml

# 5. Reiniciar ArgoCD server para aplicar cambios
kubectl rollout restart deployment/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=60s

# 6. Verificar configuración
if kubectl get configmap argocd-rbac-cm -n argocd -o yaml | grep -q "$TEAM_NAME"; then
    echo "✅ Team $TEAM_NAME added successfully with role $ROLE"
    kubectl get configmap argocd-rbac-cm -n argocd -o yaml > $BACKUP_DIR/argocd-rbac-cm-after.yaml
else
    echo "❌ Failed to add team - rolling back"
    kubectl apply -f $BACKUP_DIR/argocd-rbac-cm-before.yaml
    kubectl rollout restart deployment/argocd-server -n argocd
    exit 1
fi

echo "🎉 Team addition completed successfully"
```

### Actualizar GitHub OAuth Credentials
```bash
#!/bin/bash
# update-github-oauth.sh

echo "🔑 Updating GitHub OAuth credentials"

# Verificar que se proporcionaron las nuevas credenciales
if [ -z "$NEW_CLIENT_ID" ] || [ -z "$NEW_CLIENT_SECRET" ]; then
    echo "Error: Please set NEW_CLIENT_ID and NEW_CLIENT_SECRET environment variables"
    echo "Example:"
    echo "  export NEW_CLIENT_ID='new-client-id'"
    echo "  export NEW_CLIENT_SECRET='new-client-secret'"
    echo "  ./update-github-oauth.sh"
    exit 1
fi

# 1. Backup credenciales actuales
BACKUP_DIR="backups/oauth-update-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
kubectl get secret argocd-secret -n argocd -o yaml > $BACKUP_DIR/argocd-secret-before.yaml

# 2. Actualizar credenciales
kubectl patch secret argocd-secret -n argocd --type='merge' \
  -p='{"stringData":{"dex.github.clientId":"'$NEW_CLIENT_ID'","dex.github.clientSecret":"'$NEW_CLIENT_SECRET'"}}'

echo "✅ OAuth credentials updated in cluster"

# 3. Reiniciar DEX server
kubectl rollout restart deployment/argocd-dex-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-dex-server -n argocd --timeout=60s

echo "✅ DEX server restarted"

# 4. Verificar funcionamiento
echo "🧪 Testing new credentials..."
sleep 10  # Dar tiempo para que DEX se inicialice

if ./scripts/test-github-auth.sh >/dev/null 2>&1; then
    echo "✅ OAuth credential update successful"
    kubectl get secret argocd-secret -n argocd -o yaml > $BACKUP_DIR/argocd-secret-after.yaml
else
    echo "❌ OAuth credential update failed - rolling back"
    kubectl apply -f $BACKUP_DIR/argocd-secret-before.yaml
    kubectl rollout restart deployment/argocd-dex-server -n argocd
    exit 1
fi

echo "🎉 GitHub OAuth credentials updated successfully"
```

### Actualizar ArgoCD Version
```bash
#!/bin/bash
# upgrade-argocd.sh

NEW_VERSION="${1:-v3.1.6}"  # Default to next patch version

echo "⬆️ Upgrading ArgoCD to version $NEW_VERSION"

# 1. Pre-upgrade backup
echo "💾 Creating pre-upgrade backup..."
BACKUP_DIR="backups/upgrade-to-$NEW_VERSION-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup all ArgoCD resources
kubectl get all -n argocd -o yaml > $BACKUP_DIR/argocd-all-resources.yaml
kubectl get configmap -n argocd -o yaml > $BACKUP_DIR/argocd-configmaps.yaml
kubectl get secret -n argocd -o yaml > $BACKUP_DIR/argocd-secrets.yaml

echo "✅ Backup created in $BACKUP_DIR"

# 2. Verificar configuración actual
echo "🔍 Verifying current configuration..."
if ! ./scripts/test-github-auth.sh >/dev/null 2>&1; then
    echo "❌ Current installation is not healthy - aborting upgrade"
    exit 1
fi

# 3. Update ArgoCD using Helm (adjust based on your installation method)
echo "📦 Updating ArgoCD to $NEW_VERSION..."
helm upgrade argocd argo-cd \
  --namespace argocd \
  --version $NEW_VERSION \
  --reuse-values

# 4. Wait for rollout
echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl rollout status deployment/argocd-dex-server -n argocd --timeout=300s

# 5. Post-upgrade verification
echo "🧪 Running post-upgrade verification..."
sleep 30  # Give time for services to stabilize

if ./scripts/test-github-auth.sh >/dev/null 2>&1; then
    echo "✅ ArgoCD upgrade to $NEW_VERSION successful"
    echo "📊 Current version:"
    kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
    echo
else
    echo "❌ Post-upgrade verification failed"
    echo "🔄 Consider rolling back using: helm rollback argocd -n argocd"
    exit 1
fi

echo "🎉 ArgoCD upgrade completed successfully"
```

---

## 💾 Backup y Recovery

### Backup Automatizado Completo
```bash
#!/bin/bash
# automated-backup.sh - Ejecutar diariamente via cron

BACKUP_BASE_DIR="/var/backups/argocd"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_BASE_DIR/full-backup-$TIMESTAMP"
RETENTION_DAYS=30

mkdir -p $BACKUP_DIR

echo "💾 Starting full ArgoCD backup to $BACKUP_DIR"

# 1. Kubernetes resources
echo "📦 Backing up Kubernetes resources..."
kubectl get namespace argocd -o yaml > $BACKUP_DIR/namespace.yaml
kubectl get all -n argocd -o yaml > $BACKUP_DIR/all-resources.yaml
kubectl get configmap -n argocd -o yaml > $BACKUP_DIR/configmaps.yaml
kubectl get secret -n argocd -o yaml > $BACKUP_DIR/secrets.yaml
kubectl get persistentvolumeclaim -n argocd -o yaml > $BACKUP_DIR/pvcs.yaml

# 2. CoreDNS configuration
echo "🌐 Backing up CoreDNS configuration..."
kubectl get configmap coredns -n kube-system -o yaml > $BACKUP_DIR/coredns-config.yaml

# 3. ArgoCD applications (if any)
echo "📱 Backing up ArgoCD applications..."
kubectl get applications -n argocd -o yaml > $BACKUP_DIR/applications.yaml 2>/dev/null || echo "apiVersion: v1\nkind: List\nitems: []" > $BACKUP_DIR/applications.yaml

# 4. Application data (if using persistent storage)
echo "💽 Backing up application data..."
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' > /tmp/argocd-server-pod
if [ -s /tmp/argocd-server-pod ]; then
    POD_NAME=$(cat /tmp/argocd-server-pod)
    kubectl exec $POD_NAME -n argocd -- tar czf - /home/argocd 2>/dev/null | base64 > $BACKUP_DIR/argocd-data.tar.gz.b64 || echo "No data directory to backup"
fi

# 5. GitHub OAuth App configuration (metadata only - no secrets)
echo "🔑 Backing up OAuth app metadata..."
cat > $BACKUP_DIR/github-oauth-metadata.yaml << EOF
# GitHub OAuth App Configuration Metadata
# This file contains non-sensitive configuration information

github_org: "Portfolio-jaime"
oauth_app_name: "ArgoCD"
homepage_url: "https://argocd.test.com"
callback_url: "https://argocd.test.com/api/dex/callback"
teams:
  - name: "argocd-admins"
    role: "role:admin"
  - name: "developers"
    role: "role:developer"

# Note: Actual client ID and secret are stored in Kubernetes secrets
# and should be backed up separately with appropriate security measures
EOF

# 6. Crear checksum para verificación de integridad
echo "🔐 Creating integrity checksums..."
cd $BACKUP_DIR
find . -type f -exec sha256sum {} \; > checksums.sha256
cd - >/dev/null

# 7. Comprimir backup
echo "📦 Compressing backup..."
tar czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_BASE_DIR" "full-backup-$TIMESTAMP"
rm -rf $BACKUP_DIR

# 8. Limpiar backups antiguos
echo "🧹 Cleaning old backups..."
find $BACKUP_BASE_DIR -name "full-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete

# 9. Verificar backup
BACKUP_SIZE=$(du -h "$BACKUP_DIR.tar.gz" | cut -f1)
echo "✅ Backup completed: $BACKUP_DIR.tar.gz ($BACKUP_SIZE)"

# 10. Log backup completion
echo "$(date): Backup completed successfully - $BACKUP_DIR.tar.gz ($BACKUP_SIZE)" >> /var/log/argocd-backup.log
```

### Recovery Completo
```bash
#!/bin/bash
# complete-recovery.sh

if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo "Available backups:"
    ls -la /var/backups/argocd/full-backup-*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"
RECOVERY_DIR="/tmp/argocd-recovery-$(date +%Y%m%d-%H%M%S)"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "🔄 Starting complete recovery from $BACKUP_FILE"

# 1. Extraer backup
echo "📦 Extracting backup..."
mkdir -p $RECOVERY_DIR
tar xzf "$BACKUP_FILE" -C $RECOVERY_DIR
BACKUP_CONTENT_DIR=$(find $RECOVERY_DIR -name "full-backup-*" -type d)

# 2. Verificar integridad
echo "🔐 Verifying backup integrity..."
cd "$BACKUP_CONTENT_DIR"
if sha256sum -c checksums.sha256 >/dev/null 2>&1; then
    echo "✅ Backup integrity verified"
else
    echo "❌ Backup integrity check failed"
    exit 1
fi
cd - >/dev/null

# 3. Confirmar recovery
echo "⚠️ This will completely restore ArgoCD configuration from backup"
echo "Current deployment will be replaced with backup state"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Recovery cancelled"
    exit 0
fi

# 4. Crear backup del estado actual
echo "💾 Creating backup of current state..."
CURRENT_BACKUP_DIR="backups/pre-recovery-$(date +%Y%m%d-%H%M%S)"
mkdir -p $CURRENT_BACKUP_DIR
kubectl get all -n argocd -o yaml > $CURRENT_BACKUP_DIR/current-state.yaml 2>/dev/null || true

# 5. Scale down ArgoCD
echo "⏸️ Scaling down ArgoCD components..."
kubectl scale deployment argocd-server --replicas=0 -n argocd
kubectl scale deployment argocd-dex-server --replicas=0 -n argocd
kubectl scale deployment argocd-repo-server --replicas=0 -n argocd

# 6. Restore configurations
echo "📥 Restoring configurations..."
kubectl apply -f "$BACKUP_CONTENT_DIR/configmaps.yaml"
kubectl apply -f "$BACKUP_CONTENT_DIR/secrets.yaml"

# 7. Restore CoreDNS
echo "🌐 Restoring CoreDNS configuration..."
kubectl apply -f "$BACKUP_CONTENT_DIR/coredns-config.yaml"
kubectl rollout restart deployment/coredns -n kube-system

# 8. Scale up ArgoCD
echo "▶️ Scaling up ArgoCD components..."
kubectl scale deployment argocd-server --replicas=1 -n argocd
kubectl scale deployment argocd-dex-server --replicas=1 -n argocd
kubectl scale deployment argocd-repo-server --replicas=1 -n argocd

# 9. Wait for components to be ready
echo "⏳ Waiting for components to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-dex-server -n argocd --timeout=300s

# 10. Verify recovery
echo "🧪 Verifying recovery..."
sleep 30  # Allow time for services to initialize

if ./scripts/test-github-auth.sh >/dev/null 2>&1; then
    echo "✅ Recovery completed successfully"
    echo "📊 GitHub authentication is working"
else
    echo "❌ Recovery verification failed"
    echo "🔄 You may need to check configurations manually"
    exit 1
fi

# 11. Cleanup
rm -rf $RECOVERY_DIR

echo "🎉 Complete recovery finished successfully"
echo "📂 Pre-recovery backup saved in: $CURRENT_BACKUP_DIR"
```

---

## 🚨 Escalation y Soporte

### Procedimiento de Escalation
```yaml
# escalation-procedure.yaml
escalation_levels:
  level_1_alerts:
    - description: "Component health warnings"
    - response_time: "15 minutes"
    - contacts: ["ops-team@company.com"]
    - automated_actions:
      - restart_pods
      - check_logs
      - run_diagnostics

  level_2_alerts:
    - description: "Authentication failures"
    - response_time: "5 minutes"
    - contacts: ["ops-team@company.com", "security-team@company.com"]
    - automated_actions:
      - backup_current_state
      - collect_logs
      - notify_stakeholders

  level_3_alerts:
    - description: "Complete service outage"
    - response_time: "2 minutes"
    - contacts: ["ops-team@company.com", "management@company.com"]
    - automated_actions:
      - page_on_call_engineer
      - initiate_disaster_recovery
      - activate_backup_systems

contact_information:
  primary_engineer: "jaime.henao@company.com"
  backup_engineer: "backup-ops@company.com"
  manager: "ops-manager@company.com"
  security_team: "security@company.com"
```

### Script de Recolección de Información para Soporte
```bash
#!/bin/bash
# collect-support-info.sh

SUPPORT_DIR="support-info-$(date +%Y%m%d-%H%M%S)"
mkdir -p $SUPPORT_DIR

echo "📋 Collecting support information for ArgoCD GitHub Auth"

# 1. System information
echo "🖥️ Collecting system information..."
kubectl version > $SUPPORT_DIR/kubectl-version.txt
kubectl get nodes -o wide > $SUPPORT_DIR/nodes-info.txt

# 2. ArgoCD component status
echo "📦 Collecting ArgoCD status..."
kubectl get all -n argocd > $SUPPORT_DIR/argocd-resources.txt
kubectl describe pods -n argocd > $SUPPORT_DIR/pod-descriptions.txt

# 3. Configuration
echo "⚙️ Collecting configurations..."
kubectl get configmap argocd-cm -n argocd -o yaml > $SUPPORT_DIR/argocd-cm.yaml
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > $SUPPORT_DIR/argocd-rbac-cm.yaml
kubectl get configmap coredns -n kube-system -o yaml > $SUPPORT_DIR/coredns-config.yaml

# 4. Secrets (metadata only, no sensitive data)
echo "🔐 Collecting secret metadata..."
kubectl get secrets -n argocd > $SUPPORT_DIR/secret-list.txt

# 5. Logs (last 1000 lines)
echo "📝 Collecting logs..."
kubectl logs deployment/argocd-server -n argocd --tail=1000 > $SUPPORT_DIR/argocd-server.log
kubectl logs deployment/argocd-dex-server -n argocd --tail=1000 > $SUPPORT_DIR/argocd-dex-server.log
kubectl logs deployment/coredns -n kube-system --tail=500 > $SUPPORT_DIR/coredns.log

# 6. Events
echo "📅 Collecting events..."
kubectl get events -n argocd --sort-by='.lastTimestamp' > $SUPPORT_DIR/argocd-events.txt
kubectl get events -n kube-system --sort-by='.lastTimestamp' | grep -i dns > $SUPPORT_DIR/dns-events.txt

# 7. Network information
echo "🌐 Collecting network information..."
kubectl get svc -n argocd -o wide > $SUPPORT_DIR/services.txt
kubectl get endpoints -n argocd > $SUPPORT_DIR/endpoints.txt

# 8. Resource usage
echo "📊 Collecting resource usage..."
kubectl top pods -n argocd > $SUPPORT_DIR/pod-resources.txt 2>/dev/null || echo "Metrics server not available" > $SUPPORT_DIR/pod-resources.txt

# 9. Test results
echo "🧪 Running diagnostic tests..."
./scripts/test-github-auth.sh > $SUPPORT_DIR/test-results.txt 2>&1 || echo "Tests completed with errors"

# 10. GitHub OAuth app information (non-sensitive)
echo "🔑 Collecting OAuth app metadata..."
cat > $SUPPORT_DIR/github-oauth-info.txt << EOF
GitHub Organization: Portfolio-jaime
OAuth App Name: ArgoCD
Homepage URL: https://argocd.test.com
Callback URL: https://argocd.test.com/api/dex/callback
Teams configured: argocd-admins, developers

Note: Actual client credentials are stored in Kubernetes secrets
and are not included in this support bundle for security reasons.
EOF

# 11. Create summary
echo "📋 Creating summary..."
cat > $SUPPORT_DIR/SUMMARY.txt << EOF
ArgoCD GitHub Authentication Support Information
===============================================

Collection Date: $(date)
Kubernetes Version: $(kubectl version --short --client)
ArgoCD Namespace: argocd

Issue Description:
[Please describe the issue you're experiencing]

Recent Changes:
[List any recent changes to the system]

Error Messages:
[Include any specific error messages]

Steps to Reproduce:
[Describe how to reproduce the issue]

Files Included:
$(ls -la $SUPPORT_DIR/ | grep -v "^total")

Contact Information:
Primary: jaime.henao@company.com
Backup: ops-team@company.com
EOF

# 12. Compress collection
tar czf "$SUPPORT_DIR.tar.gz" $SUPPORT_DIR
rm -rf $SUPPORT_DIR

echo "✅ Support information collected: $SUPPORT_DIR.tar.gz"
echo "📧 Send this file to: jaime.henao@company.com"
echo "🔐 Note: This bundle contains configuration but no sensitive credentials"
```

---

## 🤖 Automatización

### Cron Jobs Recomendados
```bash
# /etc/crontab entries for ArgoCD GitHub Auth maintenance

# Daily health check
0 8 * * * root /path/to/daily-health-check.sh >> /var/log/argocd-health.log 2>&1

# Weekly configuration check
0 9 * * 1 root /path/to/weekly-config-check.sh >> /var/log/argocd-config.log 2>&1

# Daily backup
0 2 * * * root /path/to/automated-backup.sh >> /var/log/argocd-backup.log 2>&1

# Monitoring (every 5 minutes)
*/5 * * * * root /path/to/monitor-github-auth.sh

# Weekly cleanup
0 3 * * 0 root /path/to/cleanup-maintenance.sh >> /var/log/argocd-cleanup.log 2>&1

# Monthly secret rotation reminder
0 10 1 */6 * root echo "ArgoCD secret rotation due" | mail -s "ArgoCD Maintenance Reminder" ops-team@company.com
```

### Webhook Automation para Alertas
```bash
#!/bin/bash
# webhook-alert-handler.sh

# Webhook endpoint para recibir alertas de Prometheus/Grafana
# Configurar como servicio web que escuche en puerto específico

handle_alert() {
    local alert_data="$1"
    local severity=$(echo "$alert_data" | jq -r '.alerts[0].labels.severity')
    local alertname=$(echo "$alert_data" | jq -r '.alerts[0].labels.alertname')
    local description=$(echo "$alert_data" | jq -r '.alerts[0].annotations.description')

    case $severity in
        "critical")
            # Alertas críticas - acción inmediata
            /path/to/critical-alert-handler.sh "$alertname" "$description"
            ;;
        "warning")
            # Alertas de warning - log y notificación
            echo "$(date): WARNING - $alertname: $description" >> /var/log/argocd-alerts.log
            /path/to/send-notification.sh "WARNING" "$alertname" "$description"
            ;;
        *)
            # Otras alertas - solo log
            echo "$(date): INFO - $alertname: $description" >> /var/log/argocd-alerts.log
            ;;
    esac
}

# Ejemplo de uso con webhook
# curl -X POST http://localhost:9093/webhook -d @alert.json
```

### Terraform para Infraestructura como Código
```hcl
# argocd-github-auth.tf
# Terraform configuration for ArgoCD GitHub Authentication

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_config_map" "argocd_cm" {
  metadata {
    name      = "argocd-cm"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    "url"           = var.argocd_server_url
    "admin.enabled" = "true"
    "exec.enabled"  = "false"
    "dex.config" = templatefile("${path.module}/templates/dex-config.yaml", {
      github_org = var.github_org
    })
  }
}

resource "kubernetes_secret" "argocd_secret" {
  metadata {
    name      = "argocd-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    "dex.github.clientId"     = var.github_client_id
    "dex.github.clientSecret" = var.github_client_secret
    "server.secretkey"        = var.server_secret_key
  }

  type = "Opaque"
}

resource "kubernetes_config_map" "argocd_rbac_cm" {
  metadata {
    name      = "argocd-rbac-cm"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    "policy.default" = "role:readonly"
    "policy.csv" = templatefile("${path.module}/templates/rbac-policy.csv", {
      github_org    = var.github_org
      admin_team    = var.github_admin_team
      developer_team = var.github_developer_team
    })
    "policy.matchMode" = "glob"
  }
}

# Variables
variable "argocd_server_url" {
  description = "ArgoCD server URL"
  type        = string
  default     = "https://argocd.test.com"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "Portfolio-jaime"
}

variable "github_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
  sensitive   = true
}

variable "github_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  sensitive   = true
}

variable "server_secret_key" {
  description = "ArgoCD server secret key"
  type        = string
  sensitive   = true
}

variable "github_admin_team" {
  description = "GitHub admin team name"
  type        = string
  default     = "argocd-admins"
}

variable "github_developer_team" {
  description = "GitHub developer team name"
  type        = string
  default     = "developers"
}
```

---

**🔧 Esta guía de mantenimiento y operaciones proporciona todos los procedimientos necesarios para mantener el sistema GitHub Authentication funcionando de manera óptima y confiable.**

**Autor**: Jaime Henao
**Fecha**: 20 de Septiembre, 2025
**Estado**: ✅ Guía Operativa Completa