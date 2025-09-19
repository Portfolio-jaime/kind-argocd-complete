# ArgoCD Installation Guide

Guía completa para instalar ArgoCD en Kind usando Helm Chart.

## 📋 Prerrequisitos

- Kind cluster funcionando (ver [01-kind-installation.md](01-kind-installation.md))
- kubectl configurado
- Helm 3.x instalado
- nginx Ingress Controller instalado

## 🎯 Resumen de la Instalación Detectada

Tu instalación actual utiliza:
- **Helm Chart**: `argo-cd-8.3.7`
- **ArgoCD Version**: `v3.1.5`
- **Namespace**: `argocd`
- **Domain**: `argocd.test.com`
- **TLS**: Habilitado
- **Ingress**: nginx con backend HTTPS

## 🚀 Instalación Paso a Paso

### 1. Instalar Helm

#### macOS:
```bash
brew install helm
```

#### Windows:
```bash
winget install Helm.Helm
```

#### Linux:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 2. Agregar repositorio de ArgoCD

```bash
# Agregar repositorio oficial de ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm

# Actualizar repositorios
helm repo update

# Verificar repositorio
helm search repo argo/argo-cd
```

### 3. Crear namespace

```bash
# Crear namespace para ArgoCD
kubectl create namespace argocd
```

### 4. Configurar valores de Helm

Crear archivo `argocd-values.yaml`:

```yaml
# argocd-values.yaml
global:
  domain: argocd.test.com

# Controller configuration
controller:
  replicas: 1

# Repository server configuration
repoServer:
  replicas: 1

# ApplicationSet controller configuration
applicationSet:
  replicas: 1

# Server configuration
server:
  # Enable ingress
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    tls: true
    # hosts será generado automáticamente basado en global.domain

# Certificate configuration
certificate:
  enabled: true
  # domain será tomado de global.domain

# Redis configuration (disable HA for local development)
redis-ha:
  enabled: false

# Disable monitoring (optional para local)
prometheus:
  enabled: false

grafana:
  enabled: false

# Additional server configurations
configs:
  # Allow insecure local connections (solo para desarrollo local)
  params:
    server.insecure: false

  # Repository credentials (opcional)
  repositories: {}

  # Git repository access (opcional)
  secret:
    createSecret: true
    argocdServerAdminPassword: "$2a$12$I8zNl.j5fJ7M5K5k5K5k5K5k5K5k5K5k5K5k5K5k5K5k5K5k5K5k5K5"
    argocdServerAdminPasswordMtime: "2023-01-01T00:00:00Z"
```

### 5. Instalar ArgoCD con Helm

```bash
# Instalar ArgoCD usando los valores personalizados
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml \
  --version 8.3.7

# O instalar con valores en línea (como tu instalación actual)
helm install argocd argo/argo-cd \
  --namespace argocd \
  --set global.domain=argocd.test.com \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=nginx \
  --set server.ingress.annotations."nginx\.ingress\.kubernetes\.io/backend-protocol"=HTTPS \
  --set server.ingress.tls=true \
  --set certificate.enabled=true \
  --set controller.replicas=1 \
  --set repoServer.replicas=1 \
  --set applicationSet.replicas=1 \
  --set redis-ha.enabled=false \
  --version 8.3.7
```

### 6. Verificar instalación

```bash
# Verificar status de Helm
helm status argocd -n argocd

# Verificar pods
kubectl get pods -n argocd

# Verificar servicios
kubectl get svc -n argocd

# Verificar ingress
kubectl get ingress -n argocd

# Esperar a que todos los pods estén ready
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

## 🌐 Acceso a ArgoCD

### 1. Configurar hosts file

```bash
# Agregar entrada al archivo hosts
echo "127.0.0.1 argocd.test.com" | sudo tee -a /etc/hosts
```

### 2. Obtener contraseña inicial

```bash
# Obtener contraseña del admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Usuario por defecto: admin
```

### 3. Acceder via Web UI

1. Abrir navegador en: `https://argocd.test.com`
2. Usuario: `admin`
3. Contraseña: (obtenida en paso anterior)

## 🔧 Configuraciones Adicionales

### 1. Instalar ArgoCD CLI

#### macOS:
```bash
brew install argocd
```

#### Windows:
```bash
# Descargar desde GitHub releases
curl -sSL -o argocd.exe https://github.com/argoproj/argo-cd/releases/latest/download/argocd-windows-amd64.exe
```

#### Linux:
```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

### 2. Login via CLI

```bash
# Login usando CLI
argocd login argocd.test.com

# Cambiar contraseña de admin
argocd account update-password
```

### 3. Configurar repositorios

```bash
# Agregar repositorio Git privado
argocd repo add https://github.com/your-org/your-repo \
  --username your-username \
  --password your-token

# Agregar repositorio Git con SSH
argocd repo add git@github.com:your-org/your-repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

## 📊 Comandos de Gestión

### Helm Operations
```bash
# Ver valores actuales
helm get values argocd -n argocd

# Actualizar configuración
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml

# Ver historial de releases
helm history argocd -n argocd

# Rollback a versión anterior
helm rollback argocd 1 -n argocd
```

### ArgoCD Operations
```bash
# Ver aplicaciones
argocd app list

# Ver detalles de aplicación
argocd app get myapp

# Sincronizar aplicación
argocd app sync myapp

# Ver logs
kubectl logs deployment/argocd-server -n argocd
```

## 🔄 Actualización de ArgoCD

### 1. Actualizar repositorio Helm

```bash
helm repo update
helm search repo argo/argo-cd --versions
```

### 2. Actualizar ArgoCD

```bash
# Hacer backup antes de actualizar
kubectl get all -n argocd -o yaml > argocd-backup-$(date +%Y%m%d).yaml

# Actualizar a versión específica
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml \
  --version 8.4.0

# O actualizar a la última versión
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml
```

## 🔐 Configuraciones de Seguridad

### 1. RBAC básico

```yaml
# rbac.yaml
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
    g, admin, role:admin
```

### 2. Network Policies (opcional)

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-server-network-policy
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - {}
```

## 🐛 Troubleshooting

### Problemas Comunes

#### 1. Pods no inician
```bash
# Ver eventos
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Ver logs específicos
kubectl logs deployment/argocd-server -n argocd
kubectl logs statefulset/argocd-application-controller -n argocd

# Verificar recursos
kubectl describe pod <pod-name> -n argocd
```

#### 2. Ingress no funciona
```bash
# Verificar ingress controller
kubectl get pods -n ingress-nginx

# Verificar certificados
kubectl get secrets -n argocd | grep tls

# Verificar configuración de hosts
nslookup argocd.test.com
```

#### 3. Certificados SSL
```bash
# Regenerar certificados
kubectl delete secret argocd-server-tls -n argocd

# Reiniciar servidor
kubectl rollout restart deployment/argocd-server -n argocd
```

### Logs Importantes

```bash
# Logs de servidor
kubectl logs deployment/argocd-server -n argocd -f

# Logs de controller
kubectl logs statefulset/argocd-application-controller -n argocd -f

# Logs de repo server
kubectl logs deployment/argocd-repo-server -n argocd -f

# Logs de ingress
kubectl logs deployment/ingress-nginx-controller -n ingress-nginx -f
```

## 📚 Configuraciones Avanzadas

### 1. Configurar Git Webhooks

```yaml
# webhook-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.webhook.webhook-github: |
    url: https://argocd.test.com/api/webhook
    headers:
    - name: Authorization
      value: Bearer $webhook-token
```

### 2. Configurar SSO (preparación para GitHub)

```yaml
# sso-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.test.com
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: $github-client-id
        clientSecret: $github-client-secret
        orgs:
        - name: your-org
```

## 📋 Checklist de Verificación

- [ ] Kind cluster corriendo
- [ ] nginx Ingress Controller instalado
- [ ] Helm 3.x instalado
- [ ] Namespace `argocd` creado
- [ ] ArgoCD chart instalado
- [ ] Todos los pods en estado `Running`
- [ ] Ingress configurado correctamente
- [ ] Hosts file actualizado
- [ ] Acceso web funcionando
- [ ] ArgoCD CLI configurado
- [ ] Contraseña de admin cambiada

---

**Siguiente**: [Configuración de Ingress](03-ingress-configuration.md)