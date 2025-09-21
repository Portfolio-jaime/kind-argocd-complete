# ⚙️ ArgoCD GitHub Authentication - Configuración Final

**Fecha**: 20 de Septiembre, 2025
**Estado**: ✅ Configuración Funcional Validada
**Implementación**: Exitosa y Operativa

---

## 📋 Índice de Configuraciones

1. [Configuración GitHub OAuth](#configuración-github-oauth)
2. [Configuración ArgoCD](#configuración-argocd)
3. [Configuración CoreDNS](#configuración-coredns)
4. [Configuración RBAC](#configuración-rbac)
5. [Variables de Entorno](#variables-de-entorno)
6. [Scripts de Despliegue](#scripts-de-despliegue)
7. [Validación de Configuración](#validación-de-configuración)

---

## 🔑 Configuración GitHub OAuth

### GitHub OAuth App Settings
```
Application Name: ArgoCD
Homepage URL: https://argocd.test.com
Authorization callback URL: https://argocd.test.com/api/dex/callback
```

### Credenciales Generadas
```bash
# Estas son las credenciales reales utilizadas (para propósitos de documentación)
export GITHUB_CLIENT_ID="Ov23liEQt4VaCr0gZWvH"
export GITHUB_CLIENT_SECRET="313208e7de3273228dfb87bb47e565030e853b4c"
export GITHUB_ORG="Portfolio-jaime"
```

### GitHub Organization Setup
```bash
# Teams configurados en GitHub (Portfolio-jaime)
- Portfolio-jaime/argocd-admins    # Admin completo
- Portfolio-jaime/developers       # Acceso limitado

# Organization Settings
- Third-party application access policy: No restrictions
- Member privileges: Read access to organization members
```

### OAuth App Permissions
```json
{
  "permissions": {
    "members": "read",
    "metadata": "read"
  },
  "scopes": [
    "read:user",
    "user:email",
    "read:org"
  ]
}
```

---

## 🏗️ Configuración ArgoCD

### Configuración Principal - argocd-cm ConfigMap
```yaml
# /tmp/argocd-github-auth-final.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # URL principal de ArgoCD
  url: https://argocd.test.com

  # Configuración de administración
  admin.enabled: "true"
  exec.enabled: "false"

  # Configuración DEX para GitHub OAuth (Configuración Final Exitosa)
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: $dex.github.clientId
        clientSecret: $dex.github.clientSecret
        orgs:
        - name: Portfolio-jaime
        teamNameField: slug
        useLoginAsID: false
```

### Secretos de ArgoCD - argocd-secret Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  # Credenciales GitHub OAuth
  dex.github.clientId: "Ov23liEQt4VaCr0gZWvH"
  dex.github.clientSecret: "313208e7de3273228dfb87bb47e565030e853b4c"

  # Clave secreta del servidor (generada aleatoriamente)
  server.secretkey: "b8edb657579e8f218aea1e59e5ec319b7ccd6150d3af3f1a8bb3d743bc04eb9a"
```

### Configuración RBAC - argocd-rbac-cm ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # Política por defecto para usuarios autenticados
  policy.default: role:readonly

  # Políticas RBAC detalladas
  policy.csv: |
    # Permisos de administrador completo
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:admin, certificates, *, *, allow
    p, role:admin, accounts, *, *, allow
    p, role:admin, gpgkeys, *, *, allow

    # Permisos limitados para desarrolladores
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, */*, allow
    p, role:developer, repositories, get, *, allow
    p, role:developer, clusters, get, *, allow

    # Mapeo de GitHub teams a roles ArgoCD
    g, Portfolio-jaime:argocd-admins, role:admin
    g, Portfolio-jaime:developers, role:developer

  # Modo de matching para políticas
  policy.matchMode: glob
```

---

## 🌐 Configuración CoreDNS

### CoreDNS ConfigMap - coredns (kube-system)
```yaml
# /tmp/coredns-config.yaml
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        # *** CONFIGURACIÓN CRÍTICA PARA GITHUB AUTH ***
        hosts {
           10.96.149.62 argocd.test.com
           fallthrough
        }
        # *** FIN CONFIGURACIÓN CRÍTICA ***
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
```

### Validación DNS
```bash
# Verificar resolución externa
$ nslookup argocd.test.com
Server:    8.8.8.8
Address:   8.8.8.8#53
Name:      argocd.test.com
Address:   69.167.164.199

# Verificar resolución interna (desde cluster)
$ kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup argocd.test.com
Server:    10.96.0.10
Address:   10.96.0.10:53
Name:      argocd.test.com
Address:   10.96.149.62    # ← IP interna del servicio ArgoCD
```

---

## 👥 Configuración RBAC

### Roles Definidos
```yaml
# role:admin - Acceso completo
permissions:
  - applications: [*, */*, allow]
  - clusters: [*, *, allow]
  - repositories: [*, *, allow]
  - certificates: [*, *, allow]
  - accounts: [*, *, allow]
  - gpgkeys: [*, *, allow]

# role:developer - Acceso limitado
permissions:
  - applications: [get, */*, allow]
  - applications: [sync, */*, allow]
  - repositories: [get, *, allow]
  - clusters: [get, *, allow]
```

### Mapeo GitHub Teams → ArgoCD Roles
```yaml
# Formato: g, {github-org}:{team-name}, {argocd-role}
group_mappings:
  - github_team: "Portfolio-jaime:argocd-admins"
    argocd_role: "role:admin"
  - github_team: "Portfolio-jaime:developers"
    argocd_role: "role:developer"
```

### Política de Acceso por Defecto
```yaml
policy.default: role:readonly
# Los usuarios autenticados que NO estén en teams específicos
# tendrán acceso de solo lectura básico
```

---

## 🔧 Variables de Entorno

### Variables de Configuración Principal
```bash
# GitHub OAuth Configuration
export GITHUB_CLIENT_ID="Ov23liEQt4VaCr0gZWvH"
export GITHUB_CLIENT_SECRET="313208e7de3273228dfb87bb47e565030e853b4c"
export GITHUB_ORG="Portfolio-jaime"
export GITHUB_ADMIN_TEAM="argocd-admins"
export GITHUB_DEVELOPER_TEAM="developers"

# ArgoCD Configuration
export ARGOCD_SERVER_URL="https://argocd.test.com"
export ARGOCD_NAMESPACE="argocd"
export ADMIN_ENABLED="true"
export EXEC_ENABLED="false"

# Generated Secrets
export SERVER_SECRET_KEY="b8edb657579e8f218aea1e59e5ec319b7ccd6150d3af3f1a8bb3d743bc04eb9a"

# Network Configuration
export ARGOCD_SERVICE_IP="10.96.149.62"
export COREDNS_NAMESPACE="kube-system"
```

### Variables de Entorno para Scripts
```bash
# Script Environment Variables
export BACKUP_DIR="backups/github-auth-$(date +%Y%m%d-%H%M%S)"
export CONFIG_TEMPLATE="configs/argocd-github-auth-config.yaml"
export FINAL_CONFIG="/tmp/argocd-github-auth-final.yaml"
export COREDNS_CONFIG="/tmp/coredns-config.yaml"

# Testing Variables
export TEST_NAMESPACE="argocd"
export TEST_TIMEOUT="60s"
export DNS_TEST_IMAGE="busybox"
export CURL_TEST_IMAGE="curlimages/curl"
```

---

## 📜 Scripts de Despliegue

### Script de Aplicación Completa
```bash
#!/bin/bash
# deploy-github-auth.sh - Script de despliegue completo

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuración
NAMESPACE="argocd"
GITHUB_CLIENT_ID="Ov23liEQt4VaCr0gZWvH"
GITHUB_CLIENT_SECRET="313208e7de3273228dfb87bb47e565030e853b4c"
GITHUB_ORG="Portfolio-jaime"
SERVER_SECRET_KEY="b8edb657579e8f218aea1e59e5ec319b7ccd6150d3af3f1a8bb3d743bc04eb9a"

log_info "Starting GitHub Authentication Configuration"

# Paso 1: Backup
log_info "Creating configuration backup..."
BACKUP_DIR="backups/github-auth-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
kubectl get configmap argocd-cm -n $NAMESPACE -o yaml > $BACKUP_DIR/argocd-cm-backup.yaml || true
log_success "Backup created in $BACKUP_DIR"

# Paso 2: CoreDNS Configuration
log_info "Configuring CoreDNS for internal resolution..."
ARGOCD_SERVICE_IP=$(kubectl get svc argocd-server -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
log_info "ArgoCD Service IP: $ARGOCD_SERVICE_IP"

cat > /tmp/coredns-config.yaml << EOF
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        hosts {
           $ARGOCD_SERVICE_IP argocd.test.com
           fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
EOF

kubectl apply -f /tmp/coredns-config.yaml
kubectl rollout restart deployment/coredns -n kube-system
kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=60s
log_success "CoreDNS configured and restarted"

# Paso 3: ArgoCD Configuration
log_info "Applying ArgoCD GitHub authentication configuration..."
cat > /tmp/argocd-github-auth-final.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.test.com
  admin.enabled: "true"
  exec.enabled: "false"
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: \$dex.github.clientId
        clientSecret: \$dex.github.clientSecret
        orgs:
        - name: $GITHUB_ORG
        teamNameField: slug
        useLoginAsID: false

---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  dex.github.clientId: "$GITHUB_CLIENT_ID"
  dex.github.clientSecret: "$GITHUB_CLIENT_SECRET"
  server.secretkey: "$SERVER_SECRET_KEY"

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:admin, certificates, *, *, allow
    p, role:admin, accounts, *, *, allow
    p, role:admin, gpgkeys, *, *, allow
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, */*, allow
    p, role:developer, repositories, get, *, allow
    p, role:developer, clusters, get, *, allow
    g, $GITHUB_ORG:argocd-admins, role:admin
    g, $GITHUB_ORG:developers, role:developer
  policy.matchMode: glob
EOF

kubectl apply -f /tmp/argocd-github-auth-final.yaml
log_success "ArgoCD configuration applied"

# Paso 4: Restart Components
log_info "Restarting ArgoCD components..."
kubectl rollout restart deployment/argocd-server -n $NAMESPACE
kubectl rollout restart deployment/argocd-dex-server -n $NAMESPACE
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n $NAMESPACE --timeout=120s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-dex-server -n $NAMESPACE --timeout=120s
log_success "ArgoCD components restarted and ready"

# Paso 5: Validation
log_info "Running validation tests..."
if ./scripts/test-github-auth.sh > /tmp/test-results.log 2>&1; then
    log_success "All validation tests passed!"
else
    log_warning "Some validation tests failed. Check /tmp/test-results.log"
fi

log_success "GitHub Authentication configuration completed!"
log_info "Access ArgoCD at: https://argocd.test.com"
log_info "Look for 'Login via GitHub' button"
```

### Script de Validación
```bash
#!/bin/bash
# validate-github-auth.sh - Script de validación post-deployment

set -e

NAMESPACE="argocd"
PASS=0
FAIL=0

check() {
    if eval "$2" >/dev/null 2>&1; then
        echo "✅ $1"
        ((PASS++))
    else
        echo "❌ $1"
        ((FAIL++))
    fi
}

echo "🔍 GitHub Authentication Validation"
echo "=================================="

# Component Health
check "ArgoCD Server Ready" "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server | grep -q Running"
check "DEX Server Ready" "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-dex-server | grep -q Running"
check "CoreDNS Ready" "kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q Running"

# Configuration
check "DEX Configuration Present" "kubectl get configmap argocd-cm -n $NAMESPACE -o yaml | grep -q 'dex.config'"
check "GitHub Credentials Present" "kubectl get secret argocd-secret -n $NAMESPACE -o yaml | grep -q 'dex.github.clientId'"
check "RBAC Configuration Present" "kubectl get configmap argocd-rbac-cm -n $NAMESPACE -o yaml | grep -q 'policy.csv'"

# Network
check "DNS Resolution Internal" "kubectl run test-dns-val --image=busybox --rm --restart=Never -- nslookup argocd.test.com | grep -q '10.96'"
check "ArgoCD Health Endpoint" "kubectl run test-health-val --image=curlimages/curl --rm --restart=Never -- curl -k -f https://argocd.test.com/healthz"
check "DEX Endpoint Accessible" "kubectl run test-dex-val --image=curlimages/curl --rm --restart=Never -- curl -k -f https://argocd-dex-server.argocd.svc.cluster.local:5556/dex/.well-known/openid-configuration"

echo "=================================="
echo "Results: ✅ $PASS passed, ❌ $FAIL failed"

if [ $FAIL -eq 0 ]; then
    echo "🎉 All validations passed! GitHub authentication is ready."
    exit 0
else
    echo "⚠️ Some validations failed. Check the failed items."
    exit 1
fi
```

---

## ✅ Validación de Configuración

### Checklist de Validación Pre-Deployment
```bash
# 1. GitHub OAuth App
[ ] OAuth App creada en GitHub
[ ] Client ID obtenido: Ov23liEQt4VaCr0gZWvH
[ ] Client Secret obtenido: 313208e7de3273228dfb87bb47e565030e853b4c
[ ] Callback URL configurada: https://argocd.test.com/api/dex/callback
[ ] Organización Portfolio-jaime accesible

# 2. Kubernetes Cluster
[ ] Cluster Kind funcionando
[ ] ArgoCD instalado en namespace 'argocd'
[ ] kubectl configurado y funcionando
[ ] Acceso administrativo al cluster

# 3. Componentes de Red
[ ] argocd.test.com resuelve externamente
[ ] Servicio argocd-server tiene ClusterIP asignada
[ ] CoreDNS en namespace kube-system funcionando
```

### Checklist de Validación Post-Deployment
```bash
# 1. Configuración Aplicada
[ ] ConfigMap argocd-cm contiene dex.config
[ ] Secret argocd-secret contiene credenciales GitHub
[ ] ConfigMap argocd-rbac-cm contiene políticas RBAC
[ ] CoreDNS ConfigMap contiene hosts entry

# 2. Servicios Funcionando
[ ] Pods argocd-server en estado Running
[ ] Pods argocd-dex-server en estado Running
[ ] Pods coredns en estado Running
[ ] Todos los servicios tienen endpoints

# 3. Conectividad de Red
[ ] DNS interno resuelve argocd.test.com a IP interna
[ ] ArgoCD health endpoint responde HTTP 200
[ ] DEX endpoint responde con configuración OIDC
[ ] No errores en logs de ArgoCD o DEX

# 4. Autenticación Funcional
[ ] UI ArgoCD muestra botón "Login via GitHub"
[ ] Redirección a GitHub OAuth funciona
[ ] Autorización en GitHub redirige de vuelta
[ ] Usuario autenticado tiene permisos correctos
```

### Comandos de Validación Rápida
```bash
# Validación en una línea
kubectl get pods -n argocd | grep Running | wc -l  # Debe ser >= 2
kubectl get configmap argocd-cm -n argocd -o yaml | grep -c "dex.config"  # Debe ser 1
kubectl run test-dns --image=busybox --rm --restart=Never -- nslookup argocd.test.com | grep "10.96"  # Debe mostrar IP interna

# Validación completa
./scripts/validate-github-auth.sh
```

### Estados de Configuración
```
CONFIGURATION STATES:

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Not Started   │───▶│   In Progress   │───▶│   Completed     │
│                 │    │                 │    │                 │
│ - No OAuth App  │    │ - Partial Config│    │ - All Tests Pass│
│ - No ArgoCD     │    │ - Some Failed   │    │ - Auth Working  │
│ - No CoreDNS    │    │ - Debugging     │    │ - Users Happy   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                        ┌─────────────────┐
                        │     Failed      │
                        │                 │
                        │ - Config Errors │
                        │ - Network Issues│
                        │ - Auth Failures │
                        └─────────────────┘
```

---

## 📊 Configuración de Monitoreo

### Métricas de Configuración
```yaml
# Prometheus Monitoring Configuration (opcional)
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: argocd-github-auth
  namespace: argocd
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

### Alertas Recomendadas
```yaml
# Ejemplo de alertas Prometheus
groups:
- name: argocd-github-auth
  rules:
  - alert: ArgoCDAuthenticationFailure
    expr: increase(argocd_auth_failures_total[5m]) > 10
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High number of authentication failures"

  - alert: DEXServerDown
    expr: up{job="argocd-dex-server"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "DEX server is down"
```

---

## 🔄 Procedimientos de Mantenimiento

### Rotación de Secretos (Cada 6 meses)
```bash
#!/bin/bash
# rotate-secrets.sh

# Generar nuevo server secret
NEW_SECRET=$(openssl rand -hex 32)

# Actualizar en cluster
kubectl patch secret argocd-secret -n argocd --type='merge' \
  -p='{"stringData":{"server.secretkey":"'$NEW_SECRET'"}}'

# Reiniciar servidor
kubectl rollout restart deployment/argocd-server -n argocd
```

### Actualización de GitHub Credentials
```bash
#!/bin/bash
# update-github-creds.sh

# Nuevas credenciales (obtener de GitHub OAuth App)
NEW_CLIENT_ID="nuevo-client-id"
NEW_CLIENT_SECRET="nuevo-client-secret"

# Actualizar secret
kubectl patch secret argocd-secret -n argocd --type='merge' \
  -p='{"stringData":{"dex.github.clientId":"'$NEW_CLIENT_ID'","dex.github.clientSecret":"'$NEW_CLIENT_SECRET'"}}'

# Reiniciar DEX
kubectl rollout restart deployment/argocd-dex-server -n argocd
```

---

## 📝 Configuración de Logging

### Configuración de Logs Estructurados
```yaml
# ArgoCD Server Logging
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  # Enable structured logging
  server.log.format: "json"
  server.log.level: "info"

  # DEX logging
  dex.log.format: "json"
  dex.log.level: "info"
```

### Campos de Log Importantes
```json
{
  "timestamp": "2025-09-20T23:30:00Z",
  "level": "info",
  "component": "argocd-server",
  "user": "jaime@Portfolio-jaime",
  "action": "login",
  "result": "success",
  "provider": "github",
  "session_id": "abc123",
  "groups": ["Portfolio-jaime:argocd-admins"],
  "role": "role:admin"
}
```

---

**⚙️ Esta configuración final representa el estado completamente funcional del sistema GitHub Authentication para ArgoCD, validado y probado.**

**Autor**: Jaime Henao
**Fecha**: 20 de Septiembre, 2025
**Estado**: ✅ Configuración Operativa y Validada