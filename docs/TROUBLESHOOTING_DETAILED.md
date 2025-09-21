# 🔧 ArgoCD GitHub Authentication - Troubleshooting Detallado

**Fecha**: 20 de Septiembre, 2025
**Versión**: 1.0
**Estado**: Basado en implementación exitosa

---

## 📋 Índice de Problemas

1. [Problemas de Conectividad](#problemas-de-conectividad)
2. [Errores de Certificados TLS](#errores-de-certificados-tls)
3. [Problemas de Configuración](#problemas-de-configuración)
4. [Errores de RBAC y Permisos](#errores-de-rbac-y-permisos)
5. [Problemas de GitHub OAuth](#problemas-de-github-oauth)
6. [Problemas de CoreDNS](#problemas-de-coredns)
7. [Diagnóstico General](#diagnóstico-general)

---

## 🌐 Problemas de Conectividad

### Error 1: "dial tcp 127.0.0.1:443: connect: connection refused"

**Síntoma Completo**:
```
failed to query provider "https://argocd.test.com/api/dex":
Get "https://argocd.test.com/api/dex/.well-known/openid-configuration":
dial tcp 127.0.0.1:443: connect: connection refused
```

**Causa Raíz**: ArgoCD está intentando conectarse a `argocd.test.com` que resuelve a una IP externa (`127.0.0.1` o IP externa) inaccesible desde dentro del cluster.

**Diagnóstico**:
```bash
# 1. Verificar resolución DNS desde host
nslookup argocd.test.com
# Output problemático: Address: 127.0.0.1 o IP externa

# 2. Verificar resolución desde cluster
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup argocd.test.com
# Output problemático: misma IP externa

# 3. Verificar IP del servicio ArgoCD
kubectl get svc argocd-server -n argocd
# Output esperado: ClusterIP interna como 10.96.149.62
```

**Solución**:
```bash
# Configurar CoreDNS para resolución interna
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.clusterIP}'
# Usar esta IP en configuración CoreDNS

cat > /tmp/coredns-fix.yaml << EOF
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
           [IP_DEL_SERVICIO] argocd.test.com
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

kubectl apply -f /tmp/coredns-fix.yaml
kubectl rollout restart deployment/coredns -n kube-system
```

**Validación**:
```bash
# Verificar resolución interna
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup argocd.test.com
# Output esperado: Address: [IP interna del servicio]
```

### Error 2: "dial tcp [IP]:443: i/o timeout"

**Síntoma Completo**:
```
failed to query provider "https://argocd.test.com/api/dex":
Get "https://argocd.test.com/api/dex/.well-known/openid-configuration":
dial tcp 69.167.164.199:443: i/o timeout
```

**Causa Raíz**: DNS resuelve a IP externa real pero inaccesible desde dentro del cluster debido a firewall o red.

**Diagnóstico**:
```bash
# 1. Verificar conectividad externa desde cluster
kubectl run test-connectivity --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I --connect-timeout 10 https://69.167.164.199:443

# 2. Verificar que sea la IP correcta
nslookup argocd.test.com
```

**Solución**: Mismo que Error 1 - configurar CoreDNS.

---

## 🔒 Errores de Certificados TLS

### Error 3: "certificate is valid for localhost, not argocd.test.com"

**Síntoma Completo**:
```
tls: failed to verify certificate: x509: certificate is valid for
localhost, argocd-server, argocd-server.argocd, argocd-server.argocd.svc,
argocd-server.argocd.svc.cluster.local, not argocd.test.com
```

**Causa Raíz**: El certificado TLS de ArgoCD no incluye `argocd.test.com` como Subject Alternative Name (SAN).

**Diagnóstico**:
```bash
# 1. Verificar certificado del servidor
kubectl get secret argocd-server-tls -n argocd -o yaml

# 2. Examinar SANs del certificado
kubectl get secret argocd-server-tls -n argocd -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout | grep -A 5 "Subject Alternative Name"
```

**Soluciones**:

#### Opción A: insecureSkipVerify (Desarrollo)
```bash
# Agregar a configuración OIDC
kubectl patch configmap argocd-cm -n argocd --type='merge' -p='{"data":{"oidc.config":"name: GitHub\nissuer: https://argocd.test.com/api/dex\nclientId: argocd\nclientSecret: $oidc.clientSecret\nrequestredScopes: [\"openid\", \"profile\", \"email\", \"groups\"]\nrequestedIDTokenClaims: {\"groups\": {\"essential\": true}}\ninsecureSkipVerify: true"}}'
```

#### Opción B: Usar Servicios Internos
```bash
# Cambiar issuer a servicio interno
kubectl patch configmap argocd-cm -n argocd --type='merge' -p='{"data":{"oidc.config":"name: GitHub\nissuer: https://argocd-server.argocd.svc.cluster.local/api/dex\nclientId: argocd\nclientSecret: $oidc.clientSecret\nrequestedScopes: [\"openid\", \"profile\", \"email\", \"groups\"]\nrequestedIDTokenClaims: {\"groups\": {\"essential\": true}}"}}'
```

#### Opción C: Eliminar OIDC (Recomendado)
```bash
# Usar DEX directo sin OIDC intermedio (solución final exitosa)
kubectl patch configmap argocd-cm -n argocd --type='merge' -p='{"data":{"oidc.config":null}}'
```

### Error 4: "certificate signed by unknown authority"

**Síntoma Completo**:
```
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Causa Raíz**: Certificado auto-firmado no es reconocido por el cliente OIDC.

**Solución**: Usar configuración simplificada sin OIDC (ver Opción C arriba).

---

## ⚙️ Problemas de Configuración

### Error 5: "Client sent an HTTP request to an HTTPS server"

**Síntoma Completo**:
```
failed to query provider "http://argocd-dex-server:5556/dex":
Client sent an HTTP request to an HTTPS server
```

**Causa Raíz**: Intento de usar HTTP en endpoint que solo acepta HTTPS.

**Diagnóstico**:
```bash
# Verificar puertos del servicio DEX
kubectl get svc argocd-dex-server -n argocd -o yaml

# Test HTTP vs HTTPS
kubectl run test-http --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://argocd-dex-server.argocd.svc.cluster.local:5556/dex/health

kubectl run test-https --image=curlimages/curl --rm -it --restart=Never -- \
  curl -k -v https://argocd-dex-server.argocd.svc.cluster.local:5556/dex/health
```

**Solución**:
```bash
# Usar HTTPS en todas las configuraciones
kubectl patch configmap argocd-cm -n argocd --type='merge' -p='{"data":{"oidc.config":"issuer: https://argocd-dex-server.argocd.svc.cluster.local:5556/dex"}}'
```

### Error 6: "no such host"

**Síntoma Completo**:
```
dial tcp: lookup dexserver on 10.96.0.10:53: no such host
```

**Causa Raíz**: Hostname `dexserver` no existe en DNS del cluster.

**Diagnóstico**:
```bash
# Verificar servicios disponibles
kubectl get svc -n argocd | grep dex

# Verificar resolución DNS
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup dexserver
```

**Solución**:
```bash
# Usar nombre completo del servicio
kubectl patch configmap argocd-cm -n argocd --type='merge' -p='{"data":{"oidc.config":"issuer: https://argocd-dex-server.argocd.svc.cluster.local:5556/dex"}}'
```

### Error 7: insecureSkipVerify no se aplica

**Síntoma**: `insecureSkipVerify: true` está en la configuración pero sigue fallando certificado.

**Causa Raíz**: Formato YAML incorrecto o ArgoCD no reconoce la opción.

**Diagnóstico**:
```bash
# Verificar formato YAML
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 "oidc.config"

# Verificar logs de ArgoCD
kubectl logs deployment/argocd-server -n argocd | grep -i "insecure\|skip\|verify"
```

**Solución**: Usar configuración simplificada sin OIDC.

---

## 👥 Errores de RBAC y Permisos

### Error 8: Usuario autenticado pero sin permisos

**Síntoma**: Login exitoso pero error "permission denied" al acceder recursos.

**Diagnóstico**:
```bash
# 1. Verificar configuración RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# 2. Verificar membership en GitHub
# (Revisar en GitHub web interface)

# 3. Verificar logs de autorización
kubectl logs deployment/argocd-server -n argocd | grep -i "rbac\|policy\|denied"

# 4. Verificar usuario autenticado
# En ArgoCD UI: Settings → Accounts
```

**Solución**:
```bash
# Verificar y corregir mapping RBAC
kubectl edit configmap argocd-rbac-cm -n argocd

# Ejemplo de configuración correcta:
# policy.csv: |
#   g, Portfolio-jaime:argocd-admins, role:admin
#   g, Portfolio-jaime:developers, role:developer
```

### Error 9: Teams no reconocidos

**Síntoma**: Usuario en team correcto pero no tiene permisos mapeados.

**Diagnóstico**:
```bash
# Verificar configuración DEX
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 15 "dex.config"

# Verificar campo teamNameField
```

**Solución**:
```bash
# Asegurar configuración correcta de teams
kubectl patch configmap argocd-cm -n argocd --type='merge' -p='{"data":{"dex.config":"connectors:\n- type: github\n  id: github\n  name: GitHub\n  config:\n    clientID: $dex.github.clientId\n    clientSecret: $dex.github.clientSecret\n    orgs:\n    - name: Portfolio-jaime\n    teamNameField: slug\n    useLoginAsID: false"}}'
```

---

## 🔑 Problemas de GitHub OAuth

### Error 10: "invalid_client" en GitHub

**Síntoma**: Redirect a GitHub muestra error "invalid_client".

**Causa Raíz**: Client ID incorrecto o OAuth App mal configurada.

**Diagnóstico**:
```bash
# Verificar credenciales en secret
kubectl get secret argocd-secret -n argocd -o yaml | grep -E "(clientId|clientSecret)"

# Decodificar para verificar
kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.dex\.github\.clientId}' | base64 -d
```

**Solución**:
```bash
# Verificar en GitHub OAuth App settings:
# 1. Client ID correcto
# 2. Client Secret regenerado si necesario
# 3. Callback URL: https://argocd.test.com/api/dex/callback

# Actualizar secret si necesario
kubectl patch secret argocd-secret -n argocd --type='merge' -p='{"stringData":{"dex.github.clientId":"CLIENT_ID_CORRECTO","dex.github.clientSecret":"SECRET_CORRECTO"}}'
```

### Error 11: "redirect_uri_mismatch"

**Síntoma**: GitHub OAuth error sobre callback URL.

**Causa Raíz**: Callback URL en GitHub OAuth App no coincide con el configurado.

**Solución**:
```bash
# Verificar/Corregir en GitHub OAuth App:
# Authorization callback URL: https://argocd.test.com/api/dex/callback
# (Exactamente esta URL, sin trailing slash)
```

### Error 12: "access_denied" después de autorizar

**Síntoma**: Usuario autoriza en GitHub pero ArgoCD muestra access denied.

**Diagnóstico**:
```bash
# 1. Verificar membership en organización
# GitHub → Organizations → Portfolio-jaime → Members

# 2. Verificar configuración de organización en DEX
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 "orgs:"

# 3. Verificar logs DEX
kubectl logs deployment/argocd-dex-server -n argocd | grep -i "github\|oauth\|error"
```

**Solución**:
```bash
# Asegurar que usuario es miembro de la organización
# Verificar configuración org en DEX es correcta
```

---

## 🌐 Problemas de CoreDNS

### Error 13: CoreDNS no aplica configuración

**Síntoma**: Configuración CoreDNS aplicada pero DNS sigue resolviendo a IP externa.

**Diagnóstico**:
```bash
# 1. Verificar ConfigMap aplicado
kubectl get configmap coredns -n kube-system -o yaml | grep -A 5 "hosts"

# 2. Verificar pods CoreDNS reiniciados
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 3. Test desde pod nuevo
kubectl run test-dns-new --image=busybox --rm -it --restart=Never -- nslookup argocd.test.com
```

**Solución**:
```bash
# Forzar reload de CoreDNS
kubectl delete pods -n kube-system -l k8s-app=kube-dns
kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=60s
```

### Error 14: CoreDNS syntax error

**Síntoma**: CoreDNS pods en CrashLoopBackOff después de aplicar configuración.

**Diagnóstico**:
```bash
# Verificar logs CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Solución**:
```bash
# Verificar sintaxis Corefile
# Común: falta de fallthrough, indentación incorrecta

# Ejemplo sintaxis correcta:
# hosts {
#    10.96.149.62 argocd.test.com
#    fallthrough
# }
```

---

## 🔍 Diagnóstico General

### Comandos de Diagnóstico Completo

#### Estado de Componentes
```bash
#!/bin/bash
echo "=== ArgoCD Components Status ==="
kubectl get pods -n argocd -l app.kubernetes.io/part-of=argocd
kubectl get svc -n argocd
kubectl get configmap -n argocd | grep argocd
kubectl get secret -n argocd | grep argocd

echo -e "\n=== CoreDNS Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get configmap coredns -n kube-system

echo -e "\n=== Network Connectivity ==="
kubectl run diagnostic --image=busybox --rm -it --restart=Never -- sh -c "
  nslookup argocd.test.com
  nslookup argocd-server.argocd.svc.cluster.local
  nslookup argocd-dex-server.argocd.svc.cluster.local
"
```

#### Logs Centralizados
```bash
#!/bin/bash
echo "=== ArgoCD Server Logs (Last 50 lines) ==="
kubectl logs deployment/argocd-server -n argocd --tail=50

echo -e "\n=== DEX Server Logs (Last 50 lines) ==="
kubectl logs deployment/argocd-dex-server -n argocd --tail=50

echo -e "\n=== CoreDNS Logs (Last 20 lines) ==="
kubectl logs deployment/coredns -n kube-system --tail=20

echo -e "\n=== Filtering for Errors ==="
kubectl logs deployment/argocd-server -n argocd --tail=100 | grep -i "error\|failed\|panic"
kubectl logs deployment/argocd-dex-server -n argocd --tail=100 | grep -i "error\|failed\|panic"
```

#### Test de Conectividad Completo
```bash
#!/bin/bash
echo "=== DNS Resolution Tests ==="
kubectl run test-dns --image=busybox --rm -it --restart=Never -- sh -c "
  echo 'Testing argocd.test.com:'
  nslookup argocd.test.com
  echo 'Testing internal services:'
  nslookup argocd-server.argocd.svc.cluster.local
  nslookup argocd-dex-server.argocd.svc.cluster.local
"

echo -e "\n=== HTTP/HTTPS Connectivity Tests ==="
kubectl run test-connectivity --image=curlimages/curl --rm -it --restart=Never -- sh -c "
  echo 'Testing ArgoCD server health:'
  curl -k -I https://argocd-server.argocd.svc.cluster.local/healthz
  echo 'Testing DEX endpoint:'
  curl -k -s https://argocd-dex-server.argocd.svc.cluster.local:5556/dex/.well-known/openid-configuration | head -5
"

echo -e "\n=== External Access Test ==="
kubectl run test-external --image=curlimages/curl --rm -it --restart=Never -- sh -c "
  curl -k -I https://argocd.test.com/healthz
"
```

### Health Check Script Automatizado

```bash
#!/bin/bash
# health-check-github-auth.sh

NAMESPACE="argocd"
PASS=0
FAIL=0

check() {
    if eval "$2"; then
        echo "✅ $1"
        ((PASS++))
    else
        echo "❌ $1"
        ((FAIL++))
    fi
}

echo "🔍 ArgoCD GitHub Authentication Health Check"
echo "=============================================="

# Component Health
check "ArgoCD Server Running" "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server | grep -q Running"
check "DEX Server Running" "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-dex-server | grep -q Running"
check "CoreDNS Running" "kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q Running"

# Configuration
check "DEX Config Present" "kubectl get configmap argocd-cm -n $NAMESPACE -o yaml | grep -q 'dex.config'"
check "GitHub Credentials Present" "kubectl get secret argocd-secret -n $NAMESPACE -o yaml | grep -q 'dex.github.clientId'"
check "RBAC Config Present" "kubectl get configmap argocd-rbac-cm -n $NAMESPACE -o yaml | grep -q 'policy.csv'"

# Network Connectivity
check "DNS Resolution Internal" "kubectl run test-dns-check --image=busybox --rm --restart=Never -- nslookup argocd.test.com | grep -q '10.96'"
check "ArgoCD Health Endpoint" "kubectl run test-health --image=curlimages/curl --rm --restart=Never -- curl -k -f https://argocd.test.com/healthz >/dev/null 2>&1"

# Authentication Endpoints
check "DEX Endpoint Accessible" "kubectl run test-dex-check --image=curlimages/curl --rm --restart=Never -- curl -k -f https://argocd-dex-server.argocd.svc.cluster.local:5556/dex/.well-known/openid-configuration >/dev/null 2>&1"

echo "=============================================="
echo "Results: ✅ $PASS passed, ❌ $FAIL failed"

if [ $FAIL -eq 0 ]; then
    echo "🎉 All checks passed! GitHub authentication should be working."
    exit 0
else
    echo "⚠️  Some checks failed. Review the failed items above."
    exit 1
fi
```

### Recovery Script Completo

```bash
#!/bin/bash
# recovery-github-auth.sh

echo "🔧 ArgoCD GitHub Authentication Recovery"
echo "========================================"

# Check if backup exists
if [ -z "$1" ]; then
    echo "Usage: $0 <backup-directory>"
    echo "Available backups:"
    ls -la backups/ | grep github-auth
    exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "📦 Restoring from backup: $BACKUP_DIR"

# Stop current components
echo "⏸️  Stopping ArgoCD components..."
kubectl scale deployment argocd-server --replicas=0 -n argocd
kubectl scale deployment argocd-dex-server --replicas=0 -n argocd

# Restore configurations
echo "📥 Restoring configurations..."
if [ -f "$BACKUP_DIR/argocd-cm-backup.yaml" ]; then
    kubectl apply -f "$BACKUP_DIR/argocd-cm-backup.yaml"
    echo "✅ ConfigMap restored"
fi

if [ -f "$BACKUP_DIR/argocd-secret-backup.yaml" ]; then
    kubectl apply -f "$BACKUP_DIR/argocd-secret-backup.yaml"
    echo "✅ Secret restored"
fi

if [ -f "$BACKUP_DIR/argocd-rbac-cm-backup.yaml" ]; then
    kubectl apply -f "$BACKUP_DIR/argocd-rbac-cm-backup.yaml"
    echo "✅ RBAC restored"
fi

# Restart components
echo "▶️  Restarting ArgoCD components..."
kubectl scale deployment argocd-server --replicas=1 -n argocd
kubectl scale deployment argocd-dex-server --replicas=1 -n argocd

# Wait for ready
echo "⏳ Waiting for components to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-dex-server -n argocd --timeout=120s

echo "✅ Recovery completed!"
echo "🔍 Run health check to verify: ./health-check-github-auth.sh"
```

---

## 📞 Escalation y Soporte

### Información para Recolectar

Antes de escalar, recolectar:

```bash
# 1. Información del entorno
kubectl version
kubectl get nodes
kubectl get ns argocd

# 2. Estado actual
kubectl get all -n argocd
kubectl get configmap -n argocd
kubectl get secret -n argocd

# 3. Logs relevantes
kubectl logs deployment/argocd-server -n argocd --since=1h > argocd-server.log
kubectl logs deployment/argocd-dex-server -n argocd --since=1h > argocd-dex.log
kubectl logs deployment/coredns -n kube-system --since=1h > coredns.log

# 4. Configuraciones actuales
kubectl get configmap argocd-cm -n argocd -o yaml > current-argocd-cm.yaml
kubectl get configmap argocd-rbac-cm -n argocd -o yaml > current-rbac-cm.yaml
kubectl get configmap coredns -n kube-system -o yaml > current-coredns.yaml

# 5. Network info
kubectl get svc -n argocd -o wide
kubectl run network-debug --image=nicolaka/netshoot --rm -it --restart=Never -- /bin/bash
```

### Contactos de Escalation

- **Autor Original**: Jaime Henao (jaime.andres.henao.arbelaez@ba.com)
- **Documentación**: Este repositorio GitHub
- **Logs**: Centralizar en directorio `troubleshooting/`

---

**📝 Esta guía de troubleshooting cubre todos los problemas identificados durante la implementación y sus soluciones probadas.**