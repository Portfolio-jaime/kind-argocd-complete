# GitHub Authentication Configuration

Guía completa para configurar autenticación OAuth con GitHub en ArgoCD, incluyendo RBAC y configuraciones avanzadas.

## 📋 Prerrequisitos

- ArgoCD instalado y funcionando
- Acceso a GitHub (cuenta personal u organización)
- Permisos para crear OAuth Apps en GitHub
- kubectl y acceso al cluster

## 🎯 Configuración OAuth en GitHub

### 1. Crear OAuth App en GitHub

#### Acceso a configuración
1. Ve a [GitHub](https://github.com)
2. Click en tu avatar → **Settings**
3. En el menú lateral → **Developer settings**
4. Selecciona **OAuth Apps**
5. Click **New OAuth App**

#### Configuración de la aplicación
```
Application name: ArgoCD Local Development
Homepage URL: https://argocd.test.com
Application description: ArgoCD instance for local Kubernetes development
Authorization callback URL: https://argocd.test.com/api/dex/callback
```

#### Obtener credenciales
1. **Register application**
2. Anota el **Client ID**
3. Genera y anota el **Client Secret**

### 2. Configurar OAuth para Organización

Si quieres usar una organización GitHub:

1. Ve a tu organización → **Settings**
2. **OAuth App policy** → **Setup application**
3. Agrega tu OAuth App
4. Configura permisos requeridos

## 🔧 Configuración en ArgoCD

### 1. Configurar ConfigMap Principal

```yaml
# argocd-github-auth.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.test.com

  # GitHub OAuth configuration
  oidc.config: |
    name: GitHub
    issuer: https://github.com
    clientId: YOUR_GITHUB_CLIENT_ID
    clientSecret: YOUR_GITHUB_CLIENT_SECRET
    requestedScopes: ["user:email", "read:org"]
    requestedIDTokenClaims:
      groups:
        essential: true
    requestedIDTokenClaims:
      email:
        essential: true

  # RBAC Configuration
  policy.default: role:readonly
  policy.csv: |
    # Admin role permissions
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:admin, certificates, *, *, allow
    p, role:admin, gpgkeys, *, *, allow
    p, role:admin, logs, *, *, allow
    p, role:admin, exec, *, *, allow

    # Developer role permissions
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, */*, allow
    p, role:developer, applications, action/*, */*, allow
    p, role:developer, logs, get, */*, allow
    p, role:developer, repositories, get, *, allow

    # Readonly role permissions
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, logs, get, */*, allow
    p, role:readonly, repositories, get, *, allow
    p, role:readonly, clusters, get, *, allow

    # Map GitHub users to roles
    # Replace with your actual GitHub usernames
    g, YOUR_GITHUB_USERNAME, role:admin
    g, your-teammate, role:developer

    # Map GitHub organization/teams to roles
    # Format: org:team
    g, your-org:devops, role:admin
    g, your-org:developers, role:developer
    g, your-org:viewers, role:readonly

  # Additional configurations
  admin.enabled: "true"
  application.instanceLabelKey: argocd.argoproj.io/instance
  exec.enabled: "false"
  server.rbac.log.enforce.enable: "true"

  # Resource exclusions (keeping existing ones)
  resource.exclusions: |
    - apiGroups:
      - cilium.io
      kinds:
      - CiliumIdentity
      - CiliumEndpoint
    - apiGroups:
      - coordination.k8s.io
      kinds:
      - Lease
```

### 2. Configurar Secret para GitHub

```yaml
# github-oauth-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-oauth-secret
  namespace: argocd
type: Opaque
stringData:
  clientId: YOUR_GITHUB_CLIENT_ID
  clientSecret: YOUR_GITHUB_CLIENT_SECRET
```

### 3. Configuración Avanzada con Dex

```yaml
# argocd-dex-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: $github-oauth-secret:clientId
        clientSecret: $github-oauth-secret:clientSecret
        orgs:
        - name: your-organization
          teams:
          - devops
          - developers
        - name: another-org
        loadAllGroups: false
        teamNameField: slug
        useLoginAsID: false
```

## 🔐 Configuración RBAC Avanzada

### 1. Roles Detallados

```yaml
# rbac-detailed.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Cluster Admin - Full access
    p, role:cluster-admin, *, *, *, allow

    # Application Admin - Full app management
    p, role:app-admin, applications, *, */*, allow
    p, role:app-admin, repositories, *, *, allow
    p, role:app-admin, certificates, *, *, allow

    # Developer - App deployment and management
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, create, */*, allow
    p, role:developer, applications, update, */*, allow
    p, role:developer, applications, sync, */*, allow
    p, role:developer, applications, action/*, */*, allow
    p, role:developer, applications, delete, */*, allow
    p, role:developer, logs, get, */*, allow
    p, role:developer, repositories, get, *, allow

    # DevOps Engineer - Infrastructure focus
    p, role:devops, applications, *, */*, allow
    p, role:devops, clusters, *, *, allow
    p, role:devops, repositories, *, *, allow
    p, role:devops, certificates, get, *, allow

    # QA Tester - Read and action
    p, role:qa, applications, get, */*, allow
    p, role:qa, applications, sync, qa/*, allow
    p, role:qa, applications, action/*, qa/*, allow
    p, role:qa, logs, get, */*, allow

    # Viewer - Read only
    p, role:viewer, applications, get, */*, allow
    p, role:viewer, logs, get, */*, allow

    # Project-specific permissions
    p, role:project-alpha-dev, applications, *, alpha/*, allow
    p, role:project-beta-dev, applications, *, beta/*, allow

    # GitHub user/team mappings
    g, your-admin-user, role:cluster-admin
    g, your-org:platform-team, role:devops
    g, your-org:backend-team, role:developer
    g, your-org:frontend-team, role:developer
    g, your-org:qa-team, role:qa
    g, your-org:stakeholders, role:viewer

    # Project team mappings
    g, your-org:alpha-team, role:project-alpha-dev
    g, your-org:beta-team, role:project-beta-dev
```

### 2. Configuración por Proyectos

```yaml
# project-rbac.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: development
  namespace: argocd
spec:
  description: Development project
  sourceRepos:
  - 'https://github.com/your-org/*'
  destinations:
  - namespace: 'dev-*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  roles:
  - name: dev-team
    description: Development team access
    policies:
    - p, proj:development:dev-team, applications, *, development/*, allow
    groups:
    - your-org:dev-team
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: Production project
  sourceRepos:
  - 'https://github.com/your-org/production-*'
  destinations:
  - namespace: 'prod-*'
    server: https://kubernetes.default.svc
  roles:
  - name: prod-team
    description: Production team access
    policies:
    - p, proj:production:prod-team, applications, get, production/*, allow
    - p, proj:production:prod-team, applications, sync, production/*, allow
    groups:
    - your-org:devops-team
```

## 🚀 Scripts de Configuración

### 1. Script de Setup Completo

```bash
#!/bin/bash
# setup-github-auth.sh

set -e

echo "🔧 Configurando autenticación GitHub para ArgoCD..."

# Verificar variables requeridas
if [ -z "$GITHUB_CLIENT_ID" ] || [ -z "$GITHUB_CLIENT_SECRET" ]; then
    echo "❌ Variables requeridas no configuradas:"
    echo "export GITHUB_CLIENT_ID='your-client-id'"
    echo "export GITHUB_CLIENT_SECRET='your-client-secret'"
    exit 1
fi

# Crear backup
echo "📦 Creando backup de configuración actual..."
kubectl get configmap argocd-cm -n argocd -o yaml > argocd-cm-backup-$(date +%Y%m%d-%H%M%S).yaml

# Actualizar configuración
echo "🔧 Aplicando configuración GitHub OAuth..."

# Crear secret con credenciales
kubectl create secret generic github-oauth-secret \
  --from-literal=clientId="$GITHUB_CLIENT_ID" \
  --from-literal=clientSecret="$GITHUB_CLIENT_SECRET" \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# Aplicar configuración
envsubst < argocd-github-auth.yaml | kubectl apply -f -

# Reiniciar servicios
echo "🔄 Reiniciando ArgoCD server..."
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-dex-server -n argocd

# Esperar a que esté listo
kubectl rollout status deployment argocd-server -n argocd
kubectl rollout status deployment argocd-dex-server -n argocd

echo "✅ Configuración completada!"
echo "🌐 Accede a: https://argocd.test.com"
echo "📝 Verás el botón 'LOG IN VIA GITHUB'"
```

### 2. Script de Verificación

```bash
#!/bin/bash
# verify-github-auth.sh

echo "🔍 Verificando configuración GitHub OAuth..."

# Verificar secret
if kubectl get secret github-oauth-secret -n argocd >/dev/null 2>&1; then
    echo "✅ Secret github-oauth-secret existe"
else
    echo "❌ Secret github-oauth-secret no encontrado"
fi

# Verificar configuración en ConfigMap
if kubectl get configmap argocd-cm -n argocd -o yaml | grep -q "oidc.config"; then
    echo "✅ Configuración OIDC encontrada"
else
    echo "❌ Configuración OIDC no encontrada"
fi

# Verificar pods
echo "📊 Estado de pods ArgoCD:"
kubectl get pods -n argocd | grep -E "(server|dex)"

# Verificar logs
echo "📝 Últimos logs del server:"
kubectl logs deployment/argocd-server -n argocd --tail=10 | grep -i github || echo "Sin logs de GitHub aún"

echo "🌐 Accede a https://argocd.test.com para probar la autenticación"
```

## 🧪 Testing y Verificación

### 1. Verificar Configuración OAuth

```bash
# Verificar que la configuración se aplicó
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 20 "oidc.config"

# Verificar secret
kubectl get secret github-oauth-secret -n argocd -o yaml

# Verificar logs del servidor
kubectl logs deployment/argocd-server -n argocd | grep -i github
kubectl logs deployment/argocd-dex-server -n argocd | grep -i github
```

### 2. Test de Conectividad

```bash
# Test de callback URL
curl -k "https://argocd.test.com/api/dex/callback"

# Test de configuración Dex
curl -k "https://argocd.test.com/.well-known/openid_configuration"

# Verificar que GitHub aparece como opción
curl -k "https://argocd.test.com/auth/callback" | grep -i github
```

### 3. Test de CLI

```bash
# Login via CLI con GitHub
argocd login argocd.test.com --sso

# Verificar contexto actual
argocd context

# Test de permisos
argocd app list
argocd cluster list
```

## 🐛 Troubleshooting

### Problemas Comunes

#### 1. Botón GitHub no aparece
```bash
# Verificar configuración Dex
kubectl logs deployment/argocd-dex-server -n argocd

# Verificar configuración OIDC
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 oidc.config

# Reiniciar servicios
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-dex-server -n argocd
```

#### 2. Error "Invalid redirect URI"
```bash
# Verificar URL de callback en GitHub OAuth App
echo "Callback URL debe ser: https://argocd.test.com/api/dex/callback"

# Verificar configuración de dominio en ArgoCD
kubectl get configmap argocd-cm -n argocd -o yaml | grep url
```

#### 3. Error de permisos después del login
```bash
# Verificar mapeo RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Verificar grupos del usuario
argocd account get --account your-github-username

# Ver políticas aplicadas
argocd account can-i sync applications '*'
```

#### 4. Error de certificados
```bash
# Verificar certificado TLS
openssl s_client -connect argocd.test.com:443 -showcerts

# Regenerar certificados si es necesario
kubectl delete secret argocd-server-tls -n argocd
kubectl rollout restart deployment/argocd-server -n argocd
```

### Debug Commands

```bash
# Ver configuración completa de Dex
kubectl exec deployment/argocd-dex-server -n argocd -- cat /shared/dex-config.yaml

# Ver logs detallados
kubectl logs deployment/argocd-server -n argocd -f | grep -E "(oidc|github|oauth)"
kubectl logs deployment/argocd-dex-server -n argocd -f

# Verificar conectividad GitHub
kubectl exec deployment/argocd-server -n argocd -- curl -s https://api.github.com/rate_limit
```

## 📊 Monitoreo y Auditoría

### 1. Logs de Autenticación

```bash
# Monitorear logins
kubectl logs deployment/argocd-server -n argocd | grep "login successful"

# Monitorear errores de autenticación
kubectl logs deployment/argocd-server -n argocd | grep -E "(login failed|authentication error)"

# Monitorear acceso RBAC
kubectl logs deployment/argocd-server -n argocd | grep "rbac"
```

### 2. Métricas y Alerting

```yaml
# prometheus-rules.yaml
groups:
- name: argocd-auth
  rules:
  - alert: ArgoCDAuthFailure
    expr: increase(argocd_server_login_failures_total[5m]) > 5
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High number of ArgoCD authentication failures"

  - alert: ArgoCDRBACDenied
    expr: increase(argocd_server_rbac_denials_total[5m]) > 10
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High number of ArgoCD RBAC denials"
```

## 📋 Checklist de Configuración

- [ ] OAuth App creada en GitHub
- [ ] Client ID y Secret obtenidos
- [ ] ConfigMap argocd-cm actualizado
- [ ] Secret github-oauth-secret creado
- [ ] RBAC configurado correctamente
- [ ] Servicios ArgoCD reiniciados
- [ ] Botón GitHub visible en UI
- [ ] Login GitHub funcional
- [ ] Permisos RBAC verificados
- [ ] Logs sin errores
- [ ] CLI funcional con SSO

---

**Siguiente**: [Configuraciones Avanzadas](05-advanced-configurations.md)