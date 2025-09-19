# GitHub Authentication for ArgoCD

Esta guía te ayudará a configurar la autenticación de GitHub OAuth para tu instalación de ArgoCD.

## 📋 Prerrequisitos

- ArgoCD funcionando en Kind (ver [02-argocd-installation.md](02-argocd-installation.md))
- Cuenta de GitHub con permisos de administrador en una organización
- kubectl configurado y funcionando
- Acceso a `https://argocd.test.com`

## 🎯 Arquitectura de Autenticación

```
GitHub OAuth ──► DEX ──► ArgoCD Server ──► RBAC
     │            │         │              │
     │            │         │              └─ Roles y Permisos
     │            │         └─ UI/API Access
     │            └─ OIDC Provider
     └─ OAuth 2.0 Provider
```

## 🚀 Configuración Paso a Paso

### 1. Crear GitHub OAuth App

#### 1.1. Acceder a GitHub Developer Settings

1. Ve a GitHub.com
2. Click en tu avatar → **Settings**
3. En el menú izquierdo → **Developer settings**
4. Click en **OAuth Apps**
5. Click en **New OAuth App**

#### 1.2. Configurar OAuth App

Completa el formulario con estos valores:

```
Application name: ArgoCD
Homepage URL: https://argocd.test.com
Application description: ArgoCD GitOps Platform
Authorization callback URL: https://argocd.test.com/api/dex/callback
```

#### 1.3. Obtener Credenciales

Después de crear la app:

1. Copia el **Client ID**
2. Click en **Generate a new client secret**
3. Copia el **Client Secret** (solo se muestra una vez)

⚠️ **Importante**: Guarda estas credenciales de forma segura.

### 2. Configurar Teams en GitHub (Opcional pero Recomendado)

#### 2.1. Crear Teams para RBAC

En tu organización de GitHub, crea estos teams:

```bash
# Admins de ArgoCD (acceso completo)
your-org/argocd-admins

# Desarrolladores (acceso limitado)
your-org/developers
```

#### 2.2. Asignar Usuarios a Teams

1. Ve a tu organización en GitHub
2. Click en **Teams**
3. Selecciona cada team
4. Agrega usuarios apropiados

### 3. Aplicar Configuración Automática

#### 3.1. Usar el Script Automatizado

```bash
# Ejecutar el script de configuración
./scripts/setup-github-auth.sh
```

El script te pedirá:
- GitHub Client ID
- GitHub Client Secret
- Nombre de tu organización de GitHub

#### 3.2. Configuración Manual (Alternativa)

Si prefieres configurar manualmente:

```bash
# 1. Backup de configuración actual
kubectl get configmap argocd-cm -n argocd -o yaml > backup-argocd-cm.yaml
kubectl get secret argocd-secret -n argocd -o yaml > backup-argocd-secret.yaml

# 2. Aplicar nueva configuración
kubectl apply -f configs/argocd-github-auth-config.yaml

# 3. Reiniciar componentes
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-dex-server -n argocd
```

### 4. Verificar Configuración

#### 4.1. Verificar Pods

```bash
# Verificar que todos los pods estén corriendo
kubectl get pods -n argocd

# Esperar a que estén listos
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

#### 4.2. Verificar Logs

```bash
# Logs del servidor ArgoCD
kubectl logs deployment/argocd-server -n argocd

# Logs de DEX (OAuth provider)
kubectl logs deployment/argocd-dex-server -n argocd
```

#### 4.3. Verificar Configuración

```bash
# Verificar ConfigMap de ArgoCD
kubectl get configmap argocd-cm -n argocd -o yaml

# Verificar RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
```

## 🌐 Acceso y Pruebas

### 1. Acceder a ArgoCD

1. Abre `https://argocd.test.com` en tu navegador
2. Deberías ver la pantalla de login con un botón **"Login via GitHub"**
3. Click en **"Login via GitHub"**

### 2. Flujo de Autenticación

```
1. Click "Login via GitHub"
      ↓
2. Redirección a GitHub OAuth
      ↓
3. Autorizar aplicación ArgoCD
      ↓
4. Redirección de vuelta a ArgoCD
      ↓
5. Autenticado en ArgoCD
```

### 3. Verificar Permisos

Una vez autenticado, verifica:

- **Admin users**: Deberían ver todas las opciones del menú
- **Developer users**: Deberían tener acceso limitado según RBAC

## 🔧 Configuraciones Avanzadas

### 1. Personalizar RBAC

Edita el ConfigMap `argocd-rbac-cm`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # Políticas personalizadas
    p, role:devops, applications, *, */*, allow
    p, role:devops, repositories, *, *, allow

    # Mapear team específico
    g, your-org:devops-team, role:devops

    # Mapear usuario específico
    g, github-username, role:admin
```

### 2. Configurar Múltiples Organizaciones

```yaml
dex.config: |
  connectors:
  - type: github
    id: github
    name: GitHub
    config:
      clientID: $dex.github.clientId
      clientSecret: $dex.github.clientSecret
      orgs:
      - name: org1
      - name: org2
        teams:
        - admin-team
        - dev-team
```

### 3. Configurar Scopes Adicionales

```yaml
oidc.config: |
  name: GitHub
  issuer: https://dex.argocd.test.com/api/dex
  clientId: argocd
  clientSecret: $oidc.clientSecret
  requestedScopes: ["openid", "profile", "email", "groups"]
  requestedIDTokenClaims:
    groups:
      essential: true
    email:
      essential: true
```

## 🔐 Seguridad y Mejores Prácticas

### 1. Rotar Secretos Regularmente

```bash
# Generar nuevos secretos
NEW_OIDC_SECRET=$(openssl rand -base64 32)
NEW_SERVER_KEY=$(openssl rand -base64 32)

# Actualizar secret
kubectl patch secret argocd-secret -n argocd --type='merge' -p='{"stringData":{"oidc.clientSecret":"'$NEW_OIDC_SECRET'","server.secretkey":"'$NEW_SERVER_KEY'"}}'

# Reiniciar servidor
kubectl rollout restart deployment/argocd-server -n argocd
```

### 2. Configurar Network Policies

```yaml
# github-auth-network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-github-auth
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-dex-server
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 443  # GitHub API
    - protocol: TCP
      port: 80   # HTTP redirect
```

### 3. Configurar Session Management

```yaml
# En argocd-cm ConfigMap
data:
  oidc.config: |
    sessionDuration: 24h
    refreshTokenDuration: 720h  # 30 days
```

## 🐛 Troubleshooting

### Problemas Comunes

#### 1. "Login via GitHub" no aparece

**Síntomas**: Solo se ve el login de admin

**Soluciones**:
```bash
# Verificar configuración DEX
kubectl logs deployment/argocd-dex-server -n argocd

# Verificar ConfigMap
kubectl describe configmap argocd-cm -n argocd

# Reiniciar servidor
kubectl rollout restart deployment/argocd-server -n argocd
```

#### 2. Error de OAuth Callback

**Síntomas**: Error al redireccionar desde GitHub

**Verificar**:
- Callback URL en GitHub OAuth App: `https://argocd.test.com/api/dex/callback`
- URL configurada en ArgoCD: `https://argocd.test.com`

```bash
# Verificar configuración URL
kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.url}'
```

#### 3. Usuario Autenticado sin Permisos

**Síntomas**: Login exitoso pero sin acceso a recursos

**Verificar RBAC**:
```bash
# Ver configuración RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Verificar membership en teams de GitHub
curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/orgs/YOUR_ORG/teams/argocd-admins/members
```

#### 4. DEX Server no inicia

**Síntomas**: Pod `argocd-dex-server` en estado Error

**Verificar**:
```bash
# Logs de DEX
kubectl logs deployment/argocd-dex-server -n argocd

# Verificar secretos
kubectl get secret argocd-secret -n argocd -o yaml

# Verificar configuración DEX
kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.dex\.config}'
```

### Logs Importantes

```bash
# Logs de autenticación
kubectl logs deployment/argocd-server -n argocd | grep -i auth

# Logs de DEX
kubectl logs deployment/argocd-dex-server -n argocd

# Logs de RBAC
kubectl logs deployment/argocd-server -n argocd | grep -i rbac

# Eventos del namespace
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### Comandos de Diagnóstico

```bash
# Estado completo de ArgoCD
kubectl get all -n argocd

# Configuración actual
kubectl get configmap argocd-cm -n argocd -o yaml
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
kubectl get secret argocd-secret -n argocd -o yaml

# Test de conectividad
kubectl port-forward svc/argocd-server -n argocd 8080:443
curl -k https://localhost:8080/api/dex/.well-known/openid_configuration
```

## 🔄 Rollback

Si necesitas volver a la configuración anterior:

```bash
# Restaurar desde backup
kubectl apply -f backup-argocd-cm.yaml
kubectl apply -f backup-argocd-secret.yaml

# Reiniciar componentes
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-dex-server -n argocd

# Verificar rollback
kubectl rollout status deployment/argocd-server -n argocd
```

## 📊 Monitoreo

### Dashboard de Autenticación

Métricas importantes a monitorear:

- Login attempts
- Failed authentications
- Active sessions
- RBAC policy violations

```bash
# Métricas de ArgoCD (si Prometheus está habilitado)
kubectl port-forward svc/argocd-server-metrics -n argocd 8082:8082
curl http://localhost:8082/metrics | grep auth
```

## 📚 Referencias

- [ArgoCD OIDC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#oidc)
- [DEX GitHub Connector](https://dexidp.io/docs/connectors/github/)
- [ArgoCD RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)

---

**Siguiente**: [Configuración de Aplicaciones](04-application-configuration.md)