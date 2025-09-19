# Kind Installation Guide

Guía completa para instalar Kind (Kubernetes in Docker) en Docker Desktop.

## 📋 Prerrequisitos

### Herramientas Requeridas

1. **Docker Desktop**
   - Versión mínima: 4.0+
   - RAM asignada: Mínimo 4GB, recomendado 8GB
   - CPU asignada: Mínimo 2 cores, recomendado 4 cores

2. **Kind**
   - Versión mínima: 0.20+

3. **kubectl**
   - Compatible con la versión de Kubernetes que usarás

## 🚀 Instalación

### 1. Instalar Docker Desktop

#### macOS:
```bash
# Usando Homebrew
brew install --cask docker

# O descargar desde: https://www.docker.com/products/docker-desktop
```

#### Windows:
```powershell
# Usando winget
winget install Docker.DockerDesktop

# O descargar desde: https://www.docker.com/products/docker-desktop
```

#### Linux:
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Reiniciar sesión después de agregar usuario al grupo docker
```

### 2. Configurar Docker Desktop

1. Abrir Docker Desktop
2. Ir a **Settings** → **Resources**
3. Configurar:
   - **Memory**: 8GB (mínimo 4GB)
   - **CPUs**: 4 cores (mínimo 2)
   - **Swap**: 2GB
   - **Disk image size**: 64GB

4. **Apply & Restart**

### 3. Instalar Kind

#### macOS:
```bash
# Usando Homebrew
brew install kind

# O usando curl
[ $(uname -m) = arm64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-arm64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

#### Windows:
```powershell
# Usando winget
winget install Kubernetes.kind

# O usando curl (PowerShell)
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe c:\windows\system32\kind.exe
```

#### Linux:
```bash
# Para AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
# Para ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### 4. Instalar kubectl

#### macOS:
```bash
# Usando Homebrew
brew install kubectl

# O usando curl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
```

#### Windows:
```powershell
# Usando winget
winget install Kubernetes.kubectl

# O usando curl
curl.exe -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"
```

#### Linux:
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
```

## 🔧 Configuración del Cluster Kind

### 1. Crear archivo de configuración

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kind
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
- role: worker
```

### 2. Crear el cluster

```bash
# Crear cluster con configuración personalizada
kind create cluster --config kind-config.yaml --name kind

# O crear cluster básico (single node)
kind create cluster --name kind
```

### 3. Verificar instalación

```bash
# Verificar cluster
kubectl cluster-info --context kind-kind

# Verificar nodos
kubectl get nodes

# Verificar que kubectl esté configurado correctamente
kubectl config current-context
```

## 🌐 Configurar Ingress

### 1. Instalar nginx Ingress Controller

```bash
# Aplicar nginx ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Esperar a que esté listo
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### 2. Verificar ingress

```bash
# Verificar pods de ingress
kubectl get pods -n ingress-nginx

# Verificar servicios
kubectl get svc -n ingress-nginx
```

## 🔍 Comandos Útiles

### Gestión del Cluster
```bash
# Listar clusters
kind get clusters

# Obtener kubeconfig
kind get kubeconfig --name kind

# Eliminar cluster
kind delete cluster --name kind

# Ver nodos del cluster
docker ps | grep kind
```

### Información del Cluster
```bash
# Ver información detallada
kubectl cluster-info dump

# Ver recursos del sistema
kubectl get all --all-namespaces

# Ver eventos
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Debugging
```bash
# Logs de un nodo específico
docker logs kind-control-plane

# Acceder a un nodo
docker exec -it kind-control-plane bash

# Ver configuración de kubelet
docker exec kind-control-plane cat /var/lib/kubelet/config.yaml
```

## 🐛 Troubleshooting

### Problemas Comunes

#### 1. Docker no está corriendo
```bash
# Verificar estado de Docker
docker info

# En macOS/Windows, asegurar que Docker Desktop esté corriendo
```

#### 2. Puertos ocupados
```bash
# Verificar puertos en uso
netstat -tulpn | grep :80
netstat -tulpn | grep :443

# Liberar puertos si es necesario
sudo lsof -ti:80 | xargs kill -9
sudo lsof -ti:443 | xargs kill -9
```

#### 3. Recursos insuficientes
```bash
# Verificar recursos de Docker
docker system df
docker system prune -a

# Aumentar recursos en Docker Desktop Settings
```

#### 4. kubectl no encuentra el cluster
```bash
# Verificar contexto
kubectl config get-contexts

# Cambiar al contexto correcto
kubectl config use-context kind-kind

# Regenerar kubeconfig
kind get kubeconfig --name kind > ~/.kube/config
```

## 📊 Monitoreo y Métricas

### Herramientas Recomendadas

```bash
# Instalar k9s para interfaz visual
brew install k9s  # macOS
winget install k9s  # Windows

# Instalar Helm para gestión de paquetes
brew install helm  # macOS
winget install Helm.Helm  # Windows
```

### Comandos de Monitoreo
```bash
# Ver uso de recursos
kubectl top nodes
kubectl top pods --all-namespaces

# Interfaz visual con k9s
k9s

# Ver métricas de Docker
docker stats
```

## 🔐 Seguridad

### Configuraciones de Seguridad
```bash
# Verificar políticas de red
kubectl get networkpolicies --all-namespaces

# Verificar RBAC
kubectl get clusterroles
kubectl get clusterrolebindings

# Verificar security contexts
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\n"}{end}'
```

## 📚 Referencias

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Docker Desktop Documentation](https://docs.docker.com/desktop/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Reference](https://kubernetes.io/docs/reference/kubectl/)

---

**Siguiente**: [Instalación de ArgoCD](02-argocd-installation.md)