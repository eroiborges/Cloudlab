# Scripts de Automação - Northwind Demo

## 🚀 Scripts Disponíveis

### 1. `build-and-deploy.sh` - Build e Push das Imagens
**Conversão completa do PowerShell para Bash com Azure CLI**

```bash
./build-and-deploy.sh [acr-name] [tag] [resource-group]
```

**Funcionalidades:**
- ✅ Validação de pré-requisitos (Azure CLI, Docker)
- ✅ Verificação automática de login no Azure
- ✅ Criação automática de ACR se não existir
- ✅ Build com tratamento de erro robusto
- ✅ Push com retry automático
- ✅ Output colorido e informativos
- ✅ Listagem de repositórios no ACR
- ✅ Instruções automáticas para próximos passos

**Exemplo:**
```bash
./build-and-deploy.sh mynorthwindacr latest rg-northwind-demo
```

### 2. `update-manifests.sh` - Atualização dos Manifests K8s
```bash
./update-manifests.sh [acr-name] [tag]
```

**Funcionalidades:**
- 📝 Atualização automática das referências de ACR
- 🏷️ Atualização de tags das imagens
- 💾 Backup automático dos manifests originais
- ✅ Validações e verificações

### 3. `setup-demo.sh` - Setup Completo Automatizado
```bash
./setup-demo.sh <acr-name> <resource-group> <aks-name>
```

**Funcionalidades completas:**
1. **Validação de pré-requisitos**
   - Azure CLI, Docker, kubectl
   - Login automático no Azure

2. **Setup do ACR**
   - Criação automática se não existir
   - Configuração de credenciais admin

3. **Build e Deploy das imagens**
   - Build paralelo otimizado
   - Push simultâneo para melhor performance

4. **Conexão com AKS**
   - Obtenção automática das credenciais
   - Verificação de conectividade

5. **Deploy completo no Kubernetes**
   - Atualização automática dos manifests
   - Deploy ordenado dos componentes
   - Aguarda pods ficarem prontos

6. **Informações de acesso**
   - IPs dos LoadBalancers
   - Comandos úteis para monitoramento

### 4. `deploy-aks.sh` - Deploy Específico no AKS
```bash
./deploy-aks.sh [namespace]
```

**Funcionalidades:**
- 🚀 Deploy ordenado no AKS
- ⏳ Aguarda pods ficarem prontos
- 📋 Status completo dos recursos
- 🌐 Informações de acesso

## 🔄 Melhorias vs PowerShell Original

### ✨ Recursos Adicionais
- **Cores e emojis** para melhor UX
- **Validações robustas** de pré-requisitos
- **Tratamento de erro** com retry automático
- **Criação automática** de recursos Azure
- **Build paralelo** para melhor performance
- **Backup automático** de configurações
- **Output estruturado** com status detalhado

### 🛠️ Funcionalidades Azure CLI
- `az acr create` - Criação automática de ACR
- `az acr login` - Login com fallback para admin
- `az acr repository list` - Listagem de repositórios
- `az aks get-credentials` - Conexão automática ao AKS
- `az account show` - Verificação de login

### 🔧 Robustez
- **Verificação de existência** de arquivos/diretórios
- **Retry logic** para operações de rede
- **Validação de parâmetros** obrigatórios
- **Cleanup automático** de arquivos temporários
- **Status codes** apropriados para CI/CD

## 📖 Exemplos de Uso

### Setup Completo (Recomendado)
```bash
# Setup completo da demo
./setup-demo.sh mynorthwindacr rg-demo aks-demo

# Resultado: Aplicação totalmente deployada e pronta
```

### Build e Push Manual
```bash
# Build e push das imagens
./build-and-deploy.sh mynorthwindacr v1.0.0 rg-demo

# Atualizar manifests
./update-manifests.sh mynorthwindacr v1.0.0

# Deploy no AKS
./deploy-aks.sh northwind-demo
```

### Uso em CI/CD
```bash
# Para pipelines automatizadas
export ACR_NAME="mynorthwindacr"
export RESOURCE_GROUP="rg-demo"
export AKS_NAME="aks-demo"

./setup-demo.sh $ACR_NAME $RESOURCE_GROUP $AKS_NAME
```

## 🔍 Comparação PowerShell vs Bash

| Funcionalidade | PowerShell | Bash + Azure CLI |
|---|---|---|
| **Validação de pré-requisitos** | Básica | ✅ Completa |
| **Criação automática de ACR** | ❌ Manual | ✅ Automática |
| **Tratamento de erro** | Try/Catch | ✅ set -e + retry |
| **Build paralelo** | ❌ Sequencial | ✅ Paralelo |
| **Output colorido** | Write-Host | ✅ Códigos ANSI |
| **Backup de configs** | ❌ Não | ✅ Automático |
| **Deploy completo** | ❌ Separado | ✅ Integrado |
| **Verificação de status** | ❌ Manual | ✅ Automática |

---

**Resultado:** Scripts bash muito mais robustos, automatizados e adequados para uso profissional em ambientes DevOps e CI/CD.