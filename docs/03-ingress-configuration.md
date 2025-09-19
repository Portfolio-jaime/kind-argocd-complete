# Ingress Configuration Guide

Guía completa para configurar nginx Ingress Controller con ArgoCD incluyendo TLS y certificados.

## 📋 Análisis de Configuración Actual

Tu configuración actual incluye:
- **Ingress Controller**: nginx
- **Ingress Class**: nginx
- **Host**: `argocd.test.com`
- **TLS**: Habilitado con certificado auto-generado
- **Backend Protocol**: HTTPS
- **Load Balancer**: localhost (Kind)

## 🚀 Configuración Paso a Paso

### 1. Instalar nginx Ingress Controller

#### Instalación en Kind
```bash
# Aplicar nginx ingress controller específico para Kind
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Verificar instalación
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

#### Verificar instalación
```bash
# Verificar pods
kubectl get pods -n ingress-nginx

# Verificar servicios
kubectl get svc -n ingress-nginx

# Verificar ingress class
kubectl get ingressclass
```

### 2. Configurar ArgoCD Ingress

#### Opción A: Via Helm Values (Recomendado)

```yaml
# argocd-ingress-values.yaml
server:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      # Configurar backend protocol
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"

      # Forzar redirección HTTPS
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

      # Configurar proxy protocol
      nginx.ingress.kubernetes.io/proxy-protocol: "false"

      # Configurar proxy headers
      nginx.ingress.kubernetes.io/proxy-set-headers: "argocd/proxy-headers"

      # Configurar WebSocket support (para ArgoCD streaming)
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"

    hosts:
      - argocd.test.com

    tls:
      - secretName: argocd-server-tls
        hosts:
          - argocd.test.com

# Configurar certificados
certificate:
  enabled: true
  domain: argocd.test.com

# Domain global
global:
  domain: argocd.test.com
```

#### Opción B: Ingress Manifest Manual

```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - argocd.test.com
    secretName: argocd-server-tls
  rules:
  - host: argocd.test.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

### 3. Configurar Headers para ArgoCD

```yaml
# proxy-headers-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: proxy-headers
  namespace: argocd
data:
  X-Forwarded-Proto: "https"
  X-Forwarded-For: "$proxy_add_x_forwarded_for"
  X-Real-IP: "$remote_addr"
  Host: "$host"
  X-Forwarded-Host: "$host"
  X-Forwarded-Port: "443"
  X-Forwarded-Server: "$host"
```

## 🔐 Configuración TLS/SSL

### 1. Certificados Auto-generados (Actual)

ArgoCD genera automáticamente certificados TLS cuando `certificate.enabled: true`.

```bash
# Verificar certificado actual
kubectl get secret argocd-server-tls -n argocd -o yaml

# Ver detalles del certificado
kubectl get secret argocd-server-tls -n argocd -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

### 2. Usar cert-manager (Recomendado para producción)

#### Instalar cert-manager
```bash
# Agregar repositorio
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Instalar cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.0 \
  --set installCRDs=true
```

#### Configurar ClusterIssuer
```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: ca-key-pair
```

#### Certificado con cert-manager
```yaml
# argocd-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-server-cert
  namespace: argocd
spec:
  secretName: argocd-server-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - argocd.test.com
  - localhost
  ipAddresses:
  - 127.0.0.1
```

### 3. Certificados personalizados

```bash
# Generar certificado auto-firmado
openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 365 -nodes \
  -subj "/CN=argocd.test.com" \
  -addext "subjectAltName=DNS:argocd.test.com,DNS:localhost,IP:127.0.0.1"

# Crear secret
kubectl create secret tls argocd-server-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n argocd
```

## 🌐 Configuración de DNS/Hosts

### 1. Archivo hosts local

```bash
# Agregar entrada al archivo hosts
echo "127.0.0.1 argocd.test.com" | sudo tee -a /etc/hosts

# Verificar entrada
cat /etc/hosts | grep argocd
```

### 2. Configuración de DNS local (opcional)

#### macOS con dnsmasq
```bash
# Instalar dnsmasq
brew install dnsmasq

# Configurar
echo 'address=/test.com/127.0.0.1' > /usr/local/etc/dnsmasq.conf

# Iniciar servicio
sudo brew services start dnsmasq

# Configurar resolver
sudo mkdir -p /etc/resolver
echo 'nameserver 127.0.0.1' | sudo tee /etc/resolver/test.com
```

#### Windows con Acrylic DNS Proxy
```powershell
# Descargar e instalar Acrylic DNS Proxy
# Configurar en AcrylicHosts.txt:
# 127.0.0.1 argocd.test.com
```

## 🔧 Configuraciones Avanzadas

### 1. Load Balancing y High Availability

```yaml
# ha-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ha
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "argocd-server"
    nginx.ingress.kubernetes.io/session-cookie-expires: "86400"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "86400"
    nginx.ingress.kubernetes.io/session-cookie-path: "/"
spec:
  # ... resto de la configuración
```

### 2. Rate Limiting

```yaml
# Agregar a annotations del Ingress
nginx.ingress.kubernetes.io/rate-limit: "100"
nginx.ingress.kubernetes.io/rate-limit-window: "1m"
nginx.ingress.kubernetes.io/rate-limit-connections: "10"
```

### 3. IP Whitelisting

```yaml
# Agregar a annotations del Ingress
nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.1/32"
```

### 4. Configurar CORS

```yaml
# cors-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-cors-config
  namespace: ingress-nginx
data:
  enable-cors: "true"
  cors-allow-origin: "https://argocd.test.com"
  cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
  cors-allow-headers: "DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization"
```

## 📊 Monitoreo y Logs

### 1. Verificar estado del Ingress

```bash
# Ver ingress
kubectl get ingress -n argocd

# Describir ingress
kubectl describe ingress argocd-server -n argocd

# Ver eventos relacionados
kubectl get events -n argocd | grep ingress
```

### 2. Logs del Ingress Controller

```bash
# Ver logs del controller
kubectl logs deployment/ingress-nginx-controller -n ingress-nginx -f

# Ver logs específicos de un host
kubectl logs deployment/ingress-nginx-controller -n ingress-nginx | grep argocd.test.com
```

### 3. Testing de conectividad

```bash
# Test HTTP
curl -H "Host: argocd.test.com" http://localhost/

# Test HTTPS
curl -k -H "Host: argocd.test.com" https://localhost/

# Test con headers completos
curl -k -H "Host: argocd.test.com" \
     -H "X-Forwarded-Proto: https" \
     -H "X-Forwarded-For: 127.0.0.1" \
     https://localhost/
```

## 🐛 Troubleshooting

### Problemas Comunes

#### 1. 502 Bad Gateway
```bash
# Verificar backend service
kubectl get svc argocd-server -n argocd

# Verificar endpoints
kubectl get endpoints argocd-server -n argocd

# Verificar pods de ArgoCD
kubectl get pods -n argocd | grep argocd-server
```

#### 2. Certificado no válido
```bash
# Regenerar certificado
kubectl delete secret argocd-server-tls -n argocd

# Si usas cert-manager
kubectl delete certificate argocd-server-cert -n argocd

# Reiniciar ArgoCD server
kubectl rollout restart deployment/argocd-server -n argocd
```

#### 3. Redirección infinita
```bash
# Verificar configuración de ArgoCD
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml

# Verificar insecure flag
kubectl patch configmap argocd-cmd-params-cm -n argocd --patch '{"data":{"server.insecure":"false"}}'
```

#### 4. WebSocket no funciona
```bash
# Agregar configuración de WebSocket al ingress
kubectl patch ingress argocd-server -n argocd --type='merge' -p='{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-read-timeout":"3600","nginx.ingress.kubernetes.io/proxy-send-timeout":"3600"}}}'
```

### Debug Commands

```bash
# Ver configuración completa del ingress controller
kubectl exec deployment/ingress-nginx-controller -n ingress-nginx -- cat /etc/nginx/nginx.conf

# Test interno de conectividad
kubectl run test-pod --image=curlimages/curl -it --rm -- /bin/sh

# Dentro del pod:
curl http://argocd-server.argocd.svc.cluster.local
curl https://argocd-server.argocd.svc.cluster.local
```

## 📈 Optimizaciones de Performance

### 1. Configurar buffer sizes

```yaml
# Agregar a annotations del Ingress
nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
nginx.ingress.kubernetes.io/proxy-buffers-number: "8"
nginx.ingress.kubernetes.io/client-body-buffer-size: "16k"
```

### 2. Configurar timeouts

```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
nginx.ingress.kubernetes.io/client-header-timeout: "60"
nginx.ingress.kubernetes.io/client-body-timeout: "60"
```

### 3. Enable gzip

```yaml
nginx.ingress.kubernetes.io/enable-gzip: "true"
nginx.ingress.kubernetes.io/gzip-level: "6"
nginx.ingress.kubernetes.io/gzip-types: "application/json,application/xml,text/css,text/javascript,text/plain,text/xml"
```

## 📋 Checklist de Verificación

- [ ] nginx Ingress Controller instalado
- [ ] IngressClass `nginx` disponible
- [ ] Ingress para ArgoCD configurado
- [ ] TLS/SSL certificados válidos
- [ ] Headers proxy configurados
- [ ] Archivo hosts actualizado
- [ ] Conectividad HTTP/HTTPS funcionando
- [ ] WebSocket support habilitado
- [ ] Logs del ingress sin errores
- [ ] Performance optimizada

---

**Siguiente**: [Autenticación GitHub](04-github-authentication.md)