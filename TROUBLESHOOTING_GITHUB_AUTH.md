# 🔧 GitHub Authentication Troubleshooting Guide

**Fecha de creación**: 20 de Septiembre, 2025
**Problema**: `failed to query provider` con diferentes variantes de conectividad

---

## 🎯 Síntomas del Problema

### Error Principal
```
failed to query provider "https://argocd.test.com/api/dex":
Get "https://argocd.test.com/api/dex/.well-known/openid-configuration":
dial tcp 127.0.0.1:443: connect: connection refused
```

### Otros Errores Relacionados
- `dial tcp 69.167.164.199:443: i/o timeout`
- `tls: failed to verify certificate: x509: certificate is valid for localhost, dexserver, not argocd-dex-server.argocd.svc.cluster.local`
- `Client sent an HTTP request to an HTTPS server`
- `no such host`

---

## 🔍 Diagnóstico Paso a Paso

### 1. Verificar Estado de Pods
```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-dex-server
```
**Resultado esperado**: Ambos pods en estado `Running` y `Ready 1/1`

### 2. Verificar Servicios
```bash
kubectl get svc -n argocd | grep -E "(dex|server)"
```
**Resultado esperado**:
```
argocd-dex-server    ClusterIP   10.96.x.x   <none>   5556/TCP,5557/TCP
argocd-server        ClusterIP   10.96.x.x   <none>   80/TCP,443/TCP
```

### 3. Verificar Resolución DNS
```bash
nslookup argocd.test.com
```
**PROBLEMA IDENTIFICADO**: DNS resuelve a IP externa `69.167.164.199`, pero ArgoCD está en cluster local.

### 4. Verificar Configuración OIDC
```bash
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 5 "oidc.config"
```

### 5. Verificar DEX Endpoint Directamente
```bash
kubectl port-forward svc/argocd-dex-server -n argocd 5556:5556 &
curl -k https://localhost:5556/dex/.well-known/openid-configuration
pkill -f "kubectl port-forward"
```

---

## 🚨 Causa Raíz del Problema

**ISSUE PRINCIPAL**: ArgoCD está configurado para usar `issuer: https://argocd.test.com/api/dex` pero esta URL resuelve a una IP externa que no es accesible desde dentro del cluster.

**¿Por qué ocurre esto?**
1. `argocd.test.com` está configurado en DNS externo
2. ArgoCD server intenta conectarse a DEX usando esta URL externa
3. Desde dentro del cluster, no puede alcanzar la IP externa
4. Los certificados TLS no coinciden con los hostnames internos del cluster

---

## 💡 Soluciones Probadas (Que NO Funcionaron)

### ❌ Intento 1: Usar servicio interno con HTTPS
```yaml
issuer: https://argocd-dex-server.argocd.svc.cluster.local:5556/dex
```
**Error**: `tls: failed to verify certificate: x509: certificate is valid for localhost, dexserver, not argocd-dex-server.argocd.svc.cluster.local`

### ❌ Intento 2: Usar HTTP interno
```yaml
issuer: http://argocd-dex-server.argocd.svc.cluster.local:5556/dex
```
**Error**: `Client sent an HTTP request to an HTTPS server`

### ❌ Intento 3: Usar hostname del certificado
```yaml
issuer: https://dexserver:5556/dex
```
**Error**: `dial tcp: lookup dexserver on 10.96.0.10:53: no such host`

### ❌ Intento 4: Añadir insecureSkipVerify
```yaml
issuer: https://argocd-dex-server.argocd.svc.cluster.local:5556/dex
insecureSkipVerify: true
```
**Error**: Mismo error de certificado (la opción no se aplicó correctamente)

---

## ✅ Solución Correcta (En Progreso)

La solución requiere una de estas aproximaciones:

### Opción A: Configurar CoreDNS para resolución interna
Hacer que `argocd.test.com` resuelva internamente al servicio de ArgoCD.

### Opción B: Usar ingress controller con certificados válidos
Configurar un ingress que maneje los certificados correctamente.

### Opción C: Deshabilitar OIDC y usar integración directa
Configurar GitHub directamente sin pasar por DEX/OIDC.

---

## 📚 Comandos de Diagnóstico Útiles

### Logs de ArgoCD Server
```bash
kubectl logs deployment/argocd-server -n argocd --tail=50 | grep -i "oidc\|dex\|github\|error"
```

### Logs de DEX Server
```bash
kubectl logs deployment/argocd-dex-server -n argocd --tail=50
```

### Test de Conectividad DEX
```bash
kubectl port-forward svc/argocd-dex-server -n argocd 5556:5556 &
curl -k https://localhost:5556/dex/.well-known/openid-configuration | jq
pkill -f "kubectl port-forward"
```

### Test de ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
curl -k -I https://localhost:8080/
pkill -f "kubectl port-forward"
```

### Verificar Configuración Actual
```bash
kubectl get configmap argocd-cm -n argocd -o yaml > current-config.yaml
kubectl get secret argocd-secret -n argocd -o yaml > current-secret.yaml
```

---

## 🔄 Estado Actual

**Problema**: DNS resolution issue - `argocd.test.com` resuelve a IP externa inaccesible
**Próximos pasos**: Implementar solución de conectividad interna
**Tiempo invertido**: ~45 minutos en troubleshooting

---

## 📝 Lecciones Aprendidas

1. **Verificar DNS SIEMPRE** antes de configurar OIDC external
2. **Los certificados TLS en DEX** están limitados a `localhost` y `dexserver`
3. **ArgoCD requiere acceso bidireccional** a DEX desde el cluster
4. **Los tests automatizados pasaron** pero no detectaron el problema de conectividad real
5. **La configuración de red del cluster** es crítica para OIDC

---

**🎯 Objetivo**: Resolver conectividad y documentar solución paso a paso para futuras implementaciones.