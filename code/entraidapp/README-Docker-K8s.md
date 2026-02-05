# Microsoft Entra ID OAuth2.0 Demo - Docker & Kubernetes

Este projeto demonstra autenticação OAuth2.0 com Microsoft Entra ID em uma aplicação Flask containerizada.

## 🏗️ Arquitetura

- **Multi-stage Dockerfile** para imagem Alpine otimizada
- **Kubernetes Deployment** com ConfigMap e Secrets
- **Probes de Health** para liveness e readiness
- **Security context** com usuário não-root
- **Ingress** para acesso externo

## 📦 Estrutura de Arquivos

```
/
├── app.py                  # Aplicação Flask principal
├── config.py              # Configuração da aplicação
├── requirements.txt        # Dependências Python
├── templates/             # Templates HTML
├── Dockerfile             # Build multi-stage
├── .dockerignore          # Arquivos excluídos do build
├── build-and-deploy.sh    # Script de build e deploy
└── k8s/
    ├── configmap.yaml     # ConfigMap e Secrets
    └── deployment.yaml    # Deployment, Service e Ingress
```

## 🚀 Build e Deploy

### 1. Configurar Variáveis

Edite o arquivo `k8s/configmap.yaml` com seus valores:

```yaml
# Substitua os valores genéricos pelos seus:
AZURE_TENANT_ID: "seu-tenant-id"
AZURE_CLIENT_ID: "seu-client-id"
AZURE_CLIENT_SECRET: "seu-client-secret"
AZURE_AUTHORITY: "https://login.microsoftonline.com/seu-tenant-id"
CUSTOM_FQDN: "seu-dominio.com"
FLASK_SECRET_KEY: "sua-chave-secreta-32-chars"
```

### 2. Build da Imagem Docker

```bash
# Build local
docker build -t entraiddemo:v1 .

# Tag para registry
docker tag entraiddemo:v1 seu-registry/entraiddemo:v1

# Push para registry
docker push seu-registry/entraiddemo:v1
```

### 3. Deploy no Kubernetes

```bash
# Usar o script automatizado
./build-and-deploy.sh

# Ou manualmente:
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
```

## 🔧 Configuração de Registry

Por padrão, a imagem usa `docker.io`. Para alterar:

1. **No script `build-and-deploy.sh`:**
   ```bash
   REGISTRY="seu-registry.com"
   ```

2. **No deployment `k8s/deployment.yaml`:**
   ```yaml
   image: seu-registry.com/entraiddemo:v1
   ```

## 🌐 Acesso à Aplicação

### Port Forward (Desenvolvimento)
```bash
kubectl port-forward service/entraiddemo-service 8080:80
# Acesse: http://localhost:8080
```

### Ingress (Produção)
```bash
# Configure seu domínio no Ingress
# Acesse: https://seu-dominio.com
```

## 📊 Monitoramento

```bash
# Logs da aplicação
kubectl logs -l app=entraiddemo --tail=50 -f

# Status dos pods
kubectl get pods -l app=entraiddemo

# Detalhes do deployment
kubectl describe deployment entraiddemo-deployment

# Health check
kubectl exec -it deployment/entraiddemo-deployment -- wget -qO- http://localhost:5000/health
```

## 🔒 Segurança

- ✅ Usuário não-root (UID 1001)
- ✅ Secrets separados do ConfigMap
- ✅ Security context restritivo
- ✅ Health checks configurados
- ✅ Resource limits definidos
- ✅ Imagem Alpine minimalista

## 🎯 Endpoints Disponíveis

- `/` - Página inicial
- `/login` - Iniciar autenticação
- `/auth/callback` - Callback OAuth
- `/profile` - Perfil do usuário (MS Graph)
- `/tokens` - Visualizar JWT tokens
- `/logout` - Logout
- `/health` - Health check

## 📝 Variáveis de Ambiente

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `AZURE_TENANT_ID` | ID do tenant Entra ID | `ab3bf950-...` |
| `AZURE_CLIENT_ID` | ID da aplicação registrada | `de741bd5-...` |
| `AZURE_CLIENT_SECRET` | Secret da aplicação | `XpL8Q~s6...` |
| `AZURE_AUTHORITY` | URL de autoridade | `https://login.microsoftonline.com/{tenant}` |
| `APP_ENVIRONMENT` | Ambiente (dev/prd) | `dev` |
| `CUSTOM_FQDN` | Domínio personalizado | `api.exemplo.com` |
| `FLASK_SECRET_KEY` | Chave secreta do Flask | `32-character-secret` |
| `SESSION_TIMEOUT_MINUTES` | Timeout da sessão | `5` |

## 🐛 Troubleshooting

### Container não inicia
```bash
# Verificar logs
docker logs <container-id>

# Executar interativamente
docker run -it --rm entraiddemo:v1 sh
```

### Kubernetes deployment falha
```bash
# Verificar eventos
kubectl describe pod <pod-name>

# Verificar configuração
kubectl get configmap entraiddemo-config -o yaml
kubectl get secret entraiddemo-secrets -o yaml
```

### Erro de autenticação
- Verificar se o redirect URI está registrado no Azure
- Confirmar se as variáveis de ambiente estão corretas
- Verificar se o domínio corresponde ao APP_ENVIRONMENT