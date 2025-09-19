# 🔐 GitHub Authentication Setup - Checklist de Pruebas

**Fecha**: 20 de Septiembre, 2025
**Estado**: Pendiente de configuración
**Tiempo estimado**: 30-45 minutos

---

## 📋 Pre-requisitos - Verificar ANTES de empezar

- [ ] Kind cluster corriendo
- [ ] ArgoCD funcionando en `https://argocd.test.com`
- [ ] kubectl configurado
- [ ] Acceso de admin a organización GitHub
- [ ] Navegador web disponible

### Verificar estado actual:
```bash
# Verificar cluster
kubectl get nodes

# Verificar ArgoCD
kubectl get pods -n argocd

# Verificar acceso web
curl -k https://argocd.test.com/healthz
```

---

## 🎯 Paso 1: Crear GitHub OAuth App (15 min)

### 1.1 Acceder a GitHub Developer Settings
- [ ] Ir a GitHub.com → Settings → Developer settings → OAuth Apps
- [ ] Click "New OAuth App"

### 1.2 Configurar OAuth App
Usar EXACTAMENTE estos valores:

```
Application name: ArgoCD
Homepage URL: https://argocd.test.com
Authorization callback URL: https://argocd.test.com/api/dex/callback
```

### 1.3 Guardar credenciales
- [ ] Copiar **Client ID**: `_______________________`
- [ ] Generar y copiar **Client Secret**: `_______________________`
- [ ] Nombre de organización GitHub: `_______________________`

⚠️ **IMPORTANTE**: El Client Secret solo se muestra UNA vez

### 1.4 Configurar Teams (Opcional)
- [ ] Crear team: `tu-org/argocd-admins`
- [ ] Crear team: `tu-org/developers`
- [ ] Asignar usuarios a teams apropiados

---

## ⚙️ Paso 2: Aplicar Configuración (10 min)

### 2.1 Ejecutar script automatizado
```bash
cd /Users/jaime.henao/arheanja/Backstage-solutions/kind-argocd-complete

# Ejecutar configuración
./scripts/setup-github-auth.sh
```

**El script pedirá**:
- [ ] GitHub Client ID
- [ ] GitHub Client Secret
- [ ] Nombre de organización

### 2.2 Verificar aplicación
- [ ] Script completado sin errores
- [ ] Pods reiniciados correctamente
- [ ] Backup creado automáticamente

---

## 🧪 Paso 3: Verificar Configuración (10 min)

### 3.1 Ejecutar tests automatizados
```bash
# Ejecutar tests
./scripts/test-github-auth.sh
```

### 3.2 Verificar resultados esperados
- [ ] ✅ ArgoCD pods ready
- [ ] ✅ DEX configuration found
- [ ] ✅ GitHub connector configured
- [ ] ✅ RBAC configuration found
- [ ] ✅ GitHub credentials in secret
- [ ] ✅ DEX endpoints accessible
- [ ] ✅ ArgoCD server health OK

---

## 🌐 Paso 4: Pruebas Manuales (10 min)

### 4.1 Acceso Web
- [ ] Abrir `https://argocd.test.com`
- [ ] Verificar que aparece botón **"Login via GitHub"**
- [ ] NO hacer click todavía

### 4.2 Flujo de autenticación completo
- [ ] Click en "Login via GitHub"
- [ ] Redirección a GitHub OAuth ✓
- [ ] Autorizar aplicación ArgoCD
- [ ] Redirección de vuelta a ArgoCD ✓
- [ ] Usuario autenticado correctamente ✓

### 4.3 Verificar permisos RBAC
- [ ] Verificar acceso según rol asignado
- [ ] Admin: acceso completo
- [ ] Developer: acceso limitado

### 4.4 Verificar acceso de emergencia
- [ ] Abrir nueva ventana incógnito
- [ ] Ir a `https://argocd.test.com`
- [ ] Login con usuario `admin` funciona ✓

```bash
# Obtener password de admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## 🐛 Troubleshooting - Si algo falla

### Problema: "Login via GitHub" no aparece
```bash
# Verificar logs DEX
kubectl logs deployment/argocd-dex-server -n argocd

# Verificar configuración
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 "dex.config"

# Reiniciar servidor
kubectl rollout restart deployment/argocd-server -n argocd
```

### Problema: Error de OAuth callback
- [ ] Verificar URL callback en GitHub OAuth App
- [ ] Debe ser: `https://argocd.test.com/api/dex/callback`

### Problema: Usuario sin permisos
```bash
# Verificar RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Verificar membership en GitHub teams
```

### Logs importantes
```bash
# Logs de autenticación
kubectl logs deployment/argocd-server -n argocd | grep -i auth

# Logs de DEX
kubectl logs deployment/argocd-dex-server -n argocd

# Eventos del namespace
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

---

## 📊 Checklist Final

### ✅ Funcionalidades que DEBEN funcionar:
- [ ] GitHub OAuth login funciona
- [ ] Usuarios se autentican correctamente
- [ ] RBAC permissions aplicadas según teams
- [ ] Admin emergency access disponible
- [ ] No errores en logs

### 📝 Notas de la prueba:
```
Fecha/Hora: _______________
Usuario de prueba: _______________
GitHub Org: _______________
Resultado: _______________

Problemas encontrados:
_________________________________
_________________________________
_________________________________

Soluciones aplicadas:
_________________________________
_________________________________
_________________________________
```

---

## 🔄 Rollback (Si es necesario)

Si algo sale mal y necesitas volver atrás:

```bash
# Los backups están en:
ls backups/github-auth-*

# Restaurar configuración anterior
kubectl apply -f backups/github-auth-YYYYMMDD-HHMMSS/argocd-cm-backup.yaml
kubectl apply -f backups/github-auth-YYYYMMDD-HHMMSS/argocd-secret-backup.yaml

# Reiniciar componentes
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-dex-server -n argocd
```

---

## 📞 Contactos/Referencias

- **Documentación**: `docs/03-github-authentication.md`
- **Scripts**: `scripts/setup-github-auth.sh`, `scripts/test-github-auth.sh`
- **Configuración**: `configs/argocd-github-auth-config.yaml`
- **ArgoCD Docs**: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#oidc

---

**🎯 Meta**: Tener GitHub authentication funcionando completamente en 45 minutos o menos.

**⏰ Tiempo real empleado**: _____ minutos

**🏆 Resultado**: ⭐⭐⭐⭐⭐ / 5 estrellas