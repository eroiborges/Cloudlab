# Northwind E-commerce - Demo Azure Application Insights

Aplicação de demonstração em 3 camadas containerizada para showcase das capacidades do Azure Application Insights com monitoramento de performance, telemetria distribuída e análise de erros em aplicações reais.

## 📋 Visão Geral

Esta demo implementa um e-commerce completo baseado no clássico banco de dados Northwind, incluindo:

- **Frontend React SPA** com Bootstrap e Application Insights JavaScript SDK
- **Backend Python FastAPI** com OpenTelemetry e Application Insights Python SDK  
- **PostgreSQL** com banco de dados Northwind completo
- **Simulação de cenários** para demonstração de monitoramento APM
- **Gerador de carga** para testes realistas de performance
- **Deploy Kubernetes** com manifests para AKS

## 🏗️ Arquitetura

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │     Backend     │    │   PostgreSQL    │
│   React SPA     │───▶│   FastAPI       │───▶│   Northwind DB  │
│   Port: 80      │    │   Port: 8000    │    │   Port: 5432    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
          │                       │                       │
          ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                Azure Application Insights                      │
│             Telemetria, Métricas e Monitoramento               │
└─────────────────────────────────────────────────────────────────┘
```

**Importante para SPAs**: O backend deve estar acessível publicamente pois o React (SPA) faz chamadas diretas do browser do usuário para a API.

## 🗄️ Database Setup

### 1. Criar banco PostgreSQL
```sql
-- Conectar como superuser e criar database
CREATE DATABASE northwind;
CREATE USER dbadmin WITH PASSWORD 'your_secure_password';
CREATE USER demouser WITH PASSWORD 'your_app_password';
GRANT ALL PRIVILEGES ON DATABASE northwind TO dbadmin;
```

### 2. Importar dados Northwind
```bash
# Download do arquivo SQL do Northwind (exemplo)
wget https://raw.githubusercontent.com/Microsoft/sql-server-samples/master/samples/databases/northwind-pubs/northwind.sql

# Importar dados para o PostgreSQL
PGPASSWORD=your_secure_password psql -h your-postgres-host -p 5432 -U dbadmin -d northwind --set=sslmode=require --file ./northwind.sql
```

### 3. Configurar permissões para aplicação
```sql
-- Conectar como dbadmin e dar permissões para demouser
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO demouser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO demouser;
GRANT USAGE ON SCHEMA public TO demouser;
```

## ⚡ Quick Start

### 🔧 Pré-requisitos
- Azure Container Registry (ACR)
- Cluster AKS ou Kubernetes
- PostgreSQL server com banco Northwind
- Azure Application Insights resource

### 🚀 Deploy Rápido
```bash
# 1. Configurar variáveis de ambiente
export ACR_NAME="your-registry"
export RESOURCE_GROUP="your-rg"
export AKS_CLUSTER="your-aks"
export APP_INSIGHTS_CONNECTION_STRING="your-connection-string"
export DATABASE_URL="postgresql://user:pass@host:5432/northwind"

# 2. Build e push das imagens
docker build -t $ACR_NAME.azurecr.io/northwind-frontend:latest -f frontend/Dockerfile frontend/
docker build -t $ACR_NAME.azurecr.io/northwind-backend:latest -f backend/Dockerfile backend/
docker push $ACR_NAME.azurecr.io/northwind-frontend:latest
docker push $ACR_NAME.azurecr.io/northwind-backend:latest

# 3. Deploy no Kubernetes
kubectl apply -f k8s/

# 4. Verificar deployment
kubectl get svc -n northwind-demo
```

### 🌐 Acessar aplicação
```bash
# Obter IP do frontend
kubectl get svc northwind-frontend-service -n northwind-demo

# Obter IP do backend (para verificar API)
kubectl get svc northwind-backend-service -n northwind-demo

# Health check
curl http://<backend-ip>:8000/api/health
```

### 🧪 Load Testing (Opcional)
```bash
# 1. Verificar se loadgen está ativo
kubectl get svc northwind-loadgen-service -n northwind-demo

# 2. Acessar interface Locust
# http://<loadgen-service-ip>:8089

# 3. Configuração inicial recomendada:
# - Users: 10
# - Spawn rate: 2 
# - Host: http://<backend-service-ip>:8000
```

### 📊 Monitorar Application Insights
```bash
# Configurar connection string da sua instância Application Insights:
# InstrumentationKey=your-key;IngestionEndpoint=https://your-region.in.applicationinsights.azure.com/

# Acessar:
# Azure Portal > Application Insights > Live Metrics Stream
# Para ver telemetria em tempo real
```

## 🏗️ Arquitetura

```
┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│   Frontend      │    │   Backend       │    │   Database       │
│   React/Nginx   │◄──►│   Python FastAPI│◄──►│   PostgreSQL     │
│   Port 80       │    │   Port 8000     │    │   Port 5432      │
└─────────────────┘    └─────────────────┘    └──────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│              Azure Application Insights                         │
│        Telemetria • Métricas • Logs • Dashboards              │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Funcionalidades

### 🔍 Monitoramento Completo
- **Rastreamento de requisições HTTP** entre todas as camadas
- **Captura automática de exceções** Python e JavaScript
- **Métricas customizadas de negócio** (receita, conversão, produtos)
- **Telemetria distribuída** com correlação entre serviços
- **Monitoramento de performance** de banco de dados

### 🛒 Cenários de E-commerce
- **Catálogo de produtos** completo com filtros por categoria
- **Carrinho de compras** simulado com métricas de conversão
- **Checkout com múltiplos cenários** (sucesso/erro)
- **Dados realistas** do banco Northwind com 77 produtos e 8 categorias

### ⚠️ Simulação de Erros
- **Timeout de pagamento** - Simula falha do gateway de pagamento
- **Erro de validação de estoque** - Simula produto indisponível
- **Exceções JavaScript** - Demonstra captura de erros frontend
- **Cenários probabilísticos** - Mix realista de sucessos e falhas

## 📦 Estrutura do Projeto

```
appinsights/
├── backend/                 # API Python FastAPI
│   ├── main.py             # Aplicação principal
│   ├── models.py           # Modelos SQLAlchemy
│   ├── schemas.py          # Schemas Pydantic
│   ├── services.py         # Lógica de negócio
│   ├── database.py         # Conexão BD e Managed Identity
│   ├── telemetry.py        # Configuração OpenTelemetry
│   ├── config.py           # Configurações da aplicação
│   ├── requirements.txt    # Dependências Python
│   └── Dockerfile          # Container do backend
├── frontend/               # SPA React
│   ├── src/
│   │   ├── components/     # Componentes React
│   │   ├── pages/          # Páginas da aplicação
│   │   ├── services/       # API client e App Insights
│   │   └── App.js          # Aplicação principal
│   ├── public/             # Arquivos estáticos
│   ├── package.json        # Dependências Node.js
│   ├── nginx.conf          # Configuração Nginx
│   └── Dockerfile          # Container do frontend
├── loadgen/                # Gerador de carga
│   ├── locustfile.py       # Cenários de teste Locust
│   ├── requirements.txt    # Dependências Python
│   └── Dockerfile          # Container do load gen
├── k8s/                    # Manifests Kubernetes
│   ├── namespace.yaml      # Namespace da aplicação
│   ├── configmap.yaml      # ConfigMaps e Secrets
│   ├── backend-deployment.yaml     # Deploy do backend
│   ├── frontend-deployment.yaml    # Deploy do frontend
│   ├── loadgen-deployment.yaml     # Deploy do load gen
│   ├── ingress-hpa.yaml    # Ingress e autoscaling
│   └── policies.yaml       # Políticas de rede
├── scripts/                # Scripts de automação
│   ├── build-and-deploy.sh # Build e push automatizado
│   ├── build-and-deploy.ps1 # Versão PowerShell
│   ├── deploy-aks.sh       # Deploy específico AKS
│   ├── update-manifests.sh # Atualização de manifests
│   └── setup-demo.sh       # Setup completo end-to-end
├── .env.example            # Variáveis de ambiente
├── queries-examples.md     # Queries Application Insights
├── scripts-overview.md     # Documentação dos scripts
└── README.md               # Esta documentação
```

## 🚀 Quick Start

### ⚡ Método Rápido (Recomendado)
```bash
# 1. Clone e configure
git clone <repository>
cd appinsights
cp .env.example .env

# 2. Configure suas variáveis no .env:
#    - DATABASE_URL (PostgreSQL)
#    - APPLICATIONINSIGHTS_CONNECTION_STRING
#    - USE_MANAGED_IDENTITY=true/false

# 3. Execute setup completo
./setup-demo.sh mynorthwindacr rg-northwind-demo aks-northwind

# 🎉 Pronto! Aplicação deployada e rodando
```

### 📖 Método Detalhado

Se preferir controle passo-a-passo:

```bash
# 1. Preparar ambiente
az login
az aks get-credentials --resource-group rg-demo --name aks-demo

# 2. Build e push das imagens
./build-and-deploy.sh mynorthwindacr latest rg-demo

# 3. Atualizar manifests
./update-manifests.sh mynorthwindacr latest

# 4. Deploy no AKS
./deploy-aks.sh northwind-demo

# 5. Verificar status
kubectl get pods -n northwind-demo
```

### 🪟 Windows PowerShell
```powershell
# Alternativa para Windows
.\build-and-deploy.ps1 mynorthwindacr latest
```

## ⚙️ Configuração

### 🔧 Pré-requisitos

Antes de executar os scripts, certifique-se de ter instalado:

- **Azure CLI** - `az --version` (v2.0+)
- **Docker** - `docker --version` 
- **kubectl** - `kubectl version --client`
- **Git Bash** (Windows) ou terminal bash (Linux/macOS)

### 🎯 Setup Automático vs Manual

| Método | Tempo | Complexidade | Recomendado Para |
|--------|-------|-------------|------------------|
| **Setup Automático**<br/>`./setup-demo.sh` | ~5-10 min | 🟢 Baixa | Demos, POCs, Primeiros usos |
| **Setup Manual**<br/>Scripts individuais | ~15-20 min | 🟡 Média | Ambientes de desenvolvimento |
| **Build Manual**<br/>Comandos docker | ~30-45 min | 🔴 Alta | Ambientes de produção customizados |

### 1. Variáveis de Ambiente

Copie o arquivo `.env.example` para `.env` e configure:

```bash
# Configuração de Banco de Dados PostgreSQL
DATABASE_URL=postgresql://username:password@hostname:5432/northwind
USE_MANAGED_IDENTITY=false  # true para usar System Managed Identity

# Azure Application Insights
APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=your-key;IngestionEndpoint=https://your-region.in.applicationinsights.azure.com/

# Configurações da Aplicação
API_HOST=0.0.0.0
API_PORT=8000
DEBUG=false

# Frontend
REACT_APP_API_BASE_URL=http://localhost:8000
REACT_APP_APPINSIGHTS_CONNECTION_STRING=your-app-insights-connection-string

# Cenários de Erro (probabilidades em %)
ERROR_PAYMENT_RATE=15
ERROR_STOCK_RATE=15
SUCCESS_RATE=70
```

### 2. Banco de Dados

1. **Crie um Azure PostgreSQL Flexible Server**
2. **Importe o schema Northwind** usando o arquivo `TrainingDay/files/northwind.sql`
3. **Configure Managed Identity** (opcional):
   - Habilite System Managed Identity no AKS
   - Configure Azure AD authentication no PostgreSQL
   - Defina `USE_MANAGED_IDENTITY=true`

### 3. Application Insights

1. **Crie um workspace do Application Insights** no Azure Portal
2. **Copie a Connection String** completa
3. **Configure nos secrets** do Kubernetes ou variáveis de ambiente

## 🔨 Compilação e Deploy

### 🚀 Scripts de Automação (Recomendado)

A demo inclui scripts bash completos para automatizar todo o processo:

#### Setup Completo - Uma Única Execução
```bash
# Setup completo: ACR + Build + Push + Deploy AKS
./setup-demo.sh mynorthwindacr rg-northwind-demo aks-northwind

# Este comando faz tudo automaticamente:
# ✅ Valida pré-requisitos (Azure CLI, Docker, kubectl)
# ✅ Cria/configura ACR se não existir
# ✅ Build e push de todas as imagens
# ✅ Conecta ao AKS automaticamente
# ✅ Atualiza manifests com seu ACR
# ✅ Deploy completo da aplicação
# ✅ Aguarda pods ficarem prontos
# ✅ Exibe informações de acesso
```

#### Scripts Individuais
```bash
# 1. Build e push das imagens (com criação automática de ACR)
./build-and-deploy.sh mynorthwindacr latest rg-northwind-demo

# 2. Atualizar manifests Kubernetes
./update-manifests.sh mynorthwindacr latest

# 3. Deploy no AKS
./deploy-aks.sh northwind-demo
```

#### PowerShell (Windows)
```powershell
# Versão PowerShell alternativa
.\build-and-deploy.ps1 mynorthwindacr latest
```

### 📋 Funcionalidades dos Scripts

| Script | Funcionalidades |
|--------|----------------|
| `setup-demo.sh` | **Setup completo end-to-end**<br/>• Validação de pré-requisitos<br/>• Criação automática de ACR<br/>• Build paralelo das imagens<br/>• Deploy automatizado no AKS<br/>• Verificação de status |
| `build-and-deploy.sh` | **Build e push otimizado**<br/>• Validação de ambiente<br/>• Build com tratamento de erro<br/>• Push com retry automático<br/>• Criação de ACR se necessário |
| `update-manifests.sh` | **Atualização de manifests**<br/>• Backup automático<br/>• Substituição de ACR e tags<br/>• Validação de arquivos |
| `deploy-aks.sh` | **Deploy específico AKS**<br/>• Deploy ordenado<br/>• Aguarda pods prontos<br/>• Status dos recursos |

### 🛠️ Build Manual das Imagens (Avançado)

Para usuários que preferem controle manual:

```bash
# Backend
cd backend
docker build -t northwind-backend:latest .

# Frontend  
cd ../frontend
docker build -t northwind-frontend:latest .

# Load Generator
cd ../loadgen
docker build -t northwind-loadgen:latest .

# Tag e push manual
ACR_NAME="your-acr"
docker tag northwind-backend:latest $ACR_NAME.azurecr.io/northwind-backend:latest
docker tag northwind-frontend:latest $ACR_NAME.azurecr.io/northwind-frontend:latest
docker tag northwind-loadgen:latest $ACR_NAME.azurecr.io/northwind-loadgen:latest

az acr login --name $ACR_NAME
docker push $ACR_NAME.azurecr.io/northwind-backend:latest
docker push $ACR_NAME.azurecr.io/northwind-frontend:latest
docker push $ACR_NAME.azurecr.io/northwind-loadgen:latest
```

### 📦 Deploy Manual no AKS (Avançado)

```bash
# Atualizar manifests com sua ACR
find k8s/ -name "*.yaml" -exec sed -i 's/your-acr.azurecr.io/your-actual-acr.azurecr.io/g' {} +

# Aplicar manifests na ordem
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/loadgen-deployment.yaml
kubectl apply -f k8s/ingress-hpa.yaml
kubectl apply -f k8s/policies.yaml

# Verificar status
kubectl get pods -n northwind-demo
kubectl get services -n northwind-demo
```

## 🎯 Cenários de Demonstração

### 1. Fluxo de Sucesso ✅
- Navega pelo catálogo de produtos
- Adiciona itens ao carrinho
- Completa checkout com sucesso
- **Métricas geradas**: receita, conversão, tempo de resposta

### 2. Erro de Pagamento ⚠️
- Simula timeout do gateway de pagamento
- **Status Code**: 503 Service Unavailable
- **Métricas geradas**: falhas de pagamento, abandono de carrinho

### 3. Erro de Estoque ❌
- Simula produto sem estoque suficiente
- **Status Code**: 409 Conflict  
- **Métricas geradas**: falhas de estoque, indisponibilidade

### 4. Erro JavaScript 🐛
- Força exceção no frontend
- **Demonstra**: captura de erros client-side
- **Métricas geradas**: exceções JavaScript, impacto no usuário

## 📊 Métricas Customizadas

A aplicação envia as seguintes métricas para o Application Insights:

### Métricas de Negócio
- `northwind_orders_total` - Número total de pedidos
- `northwind_revenue_total` - Receita total gerada  
- `northwind_conversion_events` - Eventos de conversão (sucesso/falha)

### Métricas Técnicas
- `API_Response_Time` - Tempo de resposta das APIs
- `Demo_Scenario_Duration` - Duração dos cenários de demonstração
- `Cart_Addition_Rate` - Taxa de adição ao carrinho

### Eventos Customizados
- `Product_Added_To_Cart` - Produto adicionado ao carrinho
- `Demo_Scenario_Start/Complete` - Execução dos cenários
- `Health_Check_Success` - Verificações de saúde

## 🧪 Testes de Carga - Guia Prático

### 🚀 Iniciando os Testes

#### Opção 1: Deploy do LoadGen no Kubernetes
```bash
# Verificar se o loadgen está deployado
kubectl get pods -n northwind-demo -l app=northwind-loadgen

# Se não estiver, deploy manual:
kubectl apply -f k8s/loadgen-deployment.yaml

# Obter IP do serviço LoadGen
kubectl get svc northwind-loadgen-service -n northwind-demo
```

#### Opção 2: Locust Local (Desenvolvimento)
```bash
cd loadgen/
pip install -r requirements.txt

# Executar contra o backend no Kubernetes
LOAD_TARGET_URL=http://20.84.225.223:8000 locust -f locustfile.py --host=http://20.84.225.223:8000
```

### 🎯 Interface Web do Locust

**Acesse**: `http://<loadgen-service-ip>:8089`

**Configurações Recomendadas**:
```
👥 Usuários Simultâneos: 10-50 (início)
📈 Taxa de Spawn: 2 users/segundo  
⏱️ Duração: 5-10 minutos (teste inicial)
🎯 Host: http://20.84.225.223:8000
```

### 📊 Cenários Realistas

O **locustfile.py** simula comportamento real de e-commerce:

| Ação | Peso | Descrição |
|------|------|-----------|
| **🏠 Navegação** | 40% | Visita home, categorias, produtos |
| **🔍 Busca** | 25% | Filtra produtos por categoria |
| **🛒 Carrinho** | 20% | Adiciona/remove produtos |
| **💳 Checkout** | 15% | Mix sucesso/erro (70/15/15) |

### ⚙️ Configuração de Cenários

Ajuste as probabilidades via **ConfigMap**:

```yaml
# k8s/configmap.yaml
ERROR_PAYMENT_RATE: "15"     # 15% erro pagamento
ERROR_STOCK_RATE: "15"       # 15% erro estoque  
SUCCESS_RATE: "70"           # 70% sucesso
```

### 📈 Monitoramento Durante Testes

**Application Insights**:
- Live Metrics Stream: Telemetria em tempo real
- Application Map: Dependências e latência
- Performance: Response times e throughput

**Kubernetes Logs**:
```bash
# Backend logs durante carga
kubectl logs -f deployment/northwind-backend -n northwind-demo

# Frontend access logs  
kubectl logs -f deployment/northwind-frontend -n northwind-demo

# LoadGen status
kubectl logs -f deployment/northwind-loadgen -n northwind-demo
```

### 🎯 Testes Específicos

#### Teste de Stress (Alta Carga)
```bash
# 100 usuários simultâneos
# Configure na UI: Users: 100, Spawn rate: 5
```

#### Teste de Cenários de Erro
```bash
# Força erros para testar alerting
kubectl patch configmap northwind-config -n northwind-demo --patch '{"data":{"ERROR_PAYMENT_RATE":"50"}}'
kubectl rollout restart deployment/northwind-backend -n northwind-demo
```

#### Teste de Recuperação
```bash
# Volta configuração normal
kubectl patch configmap northwind-config -n northwind-demo --patch '{"data":{"ERROR_PAYMENT_RATE":"15"}}'
```

### 🔍 Métricas de Avaliação

**Performance**:
- Response Time < 500ms (95th percentile)
- Throughput > 50 RPS
- Error Rate < 5%

**Application Insights**:
- Dependency calls tracking
- Custom events firing
- Exception handling

### 💡 Dicas Importantes

1. **Warm-up**: Inicie com poucos usuários e aumente gradualmente
2. **Baseline**: Faça medição sem carga primeiro
3. **Recursos**: Monitor CPU/Memory dos pods durante testes
4. **Custos**: Monitore custos do Application Insights com alta telemetria

## 🔧 Troubleshooting

### ❗ Problemas Comuns

#### Scripts não executam
```bash
# Tornar scripts executáveis (Linux/macOS/WSL)
chmod +x *.sh

# No Windows, usar Git Bash ou WSL
# Evitar PowerShell para scripts .sh
```

#### Falha no login Azure
```bash
# Fazer login explícito
az login --use-device-code

# Verificar subscription ativa
az account show
az account set --subscription "sua-subscription-id"
```

#### Falha no build do frontend
```bash
# Erro comum: npm ci/install falha
# Soluções por ordem de prioridade:

# 1. Erro de dependência faltando (ex: bootstrap-icons)
# Verificar mensagem "Module not found" no log
# Adicionar dependência no package.json e rebuildar

# 2. Limpar cache do npm e node_modules
cd frontend
rm -rf node_modules package-lock.json
npm cache clean --force
npm install

# 3. Verificar versões do Node.js
node --version  # Deve ser 18.x
npm --version   # Deve ser 8.x+

# 4. Build local para debug detalhado
cd frontend
npm install --verbose
npm run build --verbose

# 5. Limpar cache do Docker se necessário  
docker system prune -f
docker build -t test-frontend . --no-cache --progress=plain

# 6. Se persistir, gerar package-lock.json
npm install  # Gera o package-lock.json
git add package-lock.json
```

#### Erro de módulo não encontrado
```bash
# Se vir "Module not found: Error: Can't resolve 'package-name'"
# 1. Verificar se a dependência está no package.json
# 2. Verificar se o import está correto no código
# 3. Adicionar dependência faltando:
cd frontend
npm install bootstrap-icons  # ou outro pacote necessário
```

#### Warnings no Dockerfile
```bash
# Warnings sobre múltiplas instruções HEALTHCHECK/CMD são informativos
# O Dockerfile foi corrigido para usar apenas uma instrução de cada
```

#### ACR não encontrado
```bash
# O script criará automaticamente se você fornecer o resource group
./setup-demo.sh mynorthwindacr rg-existe aks-existe

# Ou criar manualmente
az acr create --name mynorthwindacr --resource-group rg-demo --sku Basic
```

#### Build falha - Docker não rodando
```bash
# Verificar status do Docker
docker info

# No Windows: iniciar Docker Desktop
# No Linux: sudo systemctl start docker
```

#### kubectl não conecta ao AKS
```bash
# Obter credenciais novamente
az aks get-credentials --resource-group rg-demo --name aks-demo --overwrite-existing

# Verificar contexto
kubectl config current-context
kubectl cluster-info
```

#### Pods ficam em Pending
```bash
# Verificar recursos do cluster
kubectl describe nodes
kubectl get pods -n northwind-demo -o wide

# Verificar eventos
kubectl get events -n northwind-demo --sort-by=.metadata.creationTimestamp
```

### 🔍 Debug dos Scripts

#### Modo debug detalhado
```bash
# Executar com debug verbose
bash -x ./setup-demo.sh mynorthwindacr rg-demo aks-demo

# Ou adicionar no início do script
set -x  # Habilita debug
```

#### Logs das aplicações
```bash
# Backend logs
kubectl logs -f deployment/northwind-backend -n northwind-demo

# Frontend logs
kubectl logs -f deployment/northwind-frontend -n northwind-demo

# Logs de todos os pods
kubectl logs -f -l app=northwind-backend -n northwind-demo --all-containers
```

### 📊 Verificações de Status

#### Verificar imagens no ACR
```bash
# Listar repositórios
az acr repository list --name mynorthwindacr --output table

# Verificar tags específicas
az acr repository show-tags --name mynorthwindacr --repository northwind-backend
```

#### Status completo dos recursos
```bash
# Status geral
kubectl get all -n northwind-demo

# Detalhes dos pods
kubectl describe pods -n northwind-demo

# Status dos PVCs e ConfigMaps  
kubectl get configmaps,secrets -n northwind-demo
```

#### Conectividade de rede
```bash
# Teste de conectividade interna
kubectl exec -it deployment/northwind-backend -n northwind-demo -- curl http://localhost:8000/health

# Teste entre serviços
kubectl exec -it deployment/northwind-frontend -n northwind-demo -- curl http://northwind-backend-service:8000/health
```

### 🆘 Recovery e Cleanup

#### Restart dos deployments
```bash
# Restart individual
kubectl rollout restart deployment/northwind-backend -n northwind-demo

# Restart de todos
kubectl rollout restart deployment -n northwind-demo
```

#### Cleanup completo
```bash
# Remover tudo do namespace
kubectl delete namespace northwind-demo

# Limpar imagens Docker locais
docker system prune -a

# Remover ACR (cuidado!)
# az acr delete --name mynorthwindacr --resource-group rg-demo
```

#### Re-deploy completo
```bash
# Em caso de problemas, re-executar setup completo
kubectl delete namespace northwind-demo
./setup-demo.sh mynorthwindacr rg-demo aks-demo
```

## 📈 Dashboards Recomendados

### Dashboard de Negócio
- **Receita por período** - Acompanhamento de vendas
- **Taxa de conversão** - Funil de vendas
- **Produtos mais vendidos** - Análise de categoria
- **Abandono de carrinho** - Oportunidades de melhoria

### Dashboard Técnico  
- **Tempo de resposta** - Performance das APIs
- **Taxa de erro** - Disponibilidade do serviço
- **Throughput** - Volume de requisições
- **Dependências** - Status do PostgreSQL

### Dashboard de Usuário
- **Page views** - Navegação no site
- **Sessões** - Engajamento do usuário
- **Exceções JavaScript** - Experiência do usuário
- **Performance de carregamento** - Core Web Vitals

## 🚀 Próximos Passos

1. **Configure alertas** no Application Insights para cenários críticos
2. **Crie dashboards personalizados** com métricas de negócio
3. **Implemente Log Analytics** queries para análise avançada
4. **Configure CI/CD** para deploy automatizado
5. **Adicione testes automatizados** com Application Insights

## 🔄 DevOps e CI/CD

### Azure DevOps Pipeline
```yaml
# azure-pipelines.yml
trigger:
- main

variables:
  acrName: 'mynorthwindacr'
  resourceGroup: 'rg-northwind-demo'
  aksName: 'aks-northwind'

stages:
- stage: Build
  jobs:
  - job: BuildAndPush
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - script: |
        ./build-and-deploy.sh $(acrName) $(Build.BuildNumber) $(resourceGroup)
      displayName: 'Build and Push Images'

- stage: Deploy
  jobs:
  - deployment: DeployToAKS
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          - script: |
              ./setup-demo.sh $(acrName) $(resourceGroup) $(aksName)
            displayName: 'Deploy to AKS'
```

### GitHub Actions
```yaml
# .github/workflows/deploy.yml
name: Deploy Northwind Demo

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Setup and Deploy
      run: |
        chmod +x ./setup-demo.sh
        ./setup-demo.sh ${{ vars.ACR_NAME }} ${{ vars.RESOURCE_GROUP }} ${{ vars.AKS_NAME }}
```

### Terraform Integration
```hcl
# main.tf - Exemplo de integração com IaC
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  sku                = "Standard"
  admin_enabled      = true
}

resource "null_resource" "build_and_deploy" {
  depends_on = [azurerm_container_registry.acr]
  
  provisioner "local-exec" {
    command = "./build-and-deploy.sh ${var.acr_name} latest ${var.resource_group_name}"
  }
  
  triggers = {
    always_run = "${timestamp()}"
  }
}
```

### Monitoring e Alertas
```bash
# Scripts de monitoramento personalizados
./scripts/setup-alerts.sh     # Configura alertas automáticos
./scripts/create-dashboard.sh # Cria dashboards personalizados
./scripts/health-check.sh     # Verificação de saúde contínua
```

### Ambientes Múltiplos
```bash
# Deploy em diferentes ambientes
./setup-demo.sh northwind-dev rg-dev aks-dev          # Desenvolvimento
./setup-demo.sh northwind-staging rg-staging aks-staging  # Staging  
./setup-demo.sh northwind-prod rg-prod aks-prod       # Produção
```

---

## � Otimizações de Performance

### 🚀 Scaling Automático Avançado

#### Horizontal Pod Autoscaler (HPA) Personalizado
```bash
# HPA baseado em múltiplas métricas
kubectl autoscale deployment northwind-backend --cpu-percent=70 --memory-percent=80 --min=2 --max=10 -n northwind-demo

# HPA customizado com métricas da aplicação
kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: northwind-hpa-custom
  namespace: northwind-demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: northwind-backend
  minReplicas: 2
  maxReplicas: 15
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "100"
EOF
```

#### Vertical Pod Autoscaler (VPA)
```bash
# VPA para otimização automática de recursos
kubectl apply -f - <<EOF
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: northwind-backend-vpa
  namespace: northwind-demo
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: northwind-backend
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: northwind-backend
      maxAllowed:
        cpu: 2
        memory: 4Gi
      minAllowed:
        cpu: 100m
        memory: 128Mi
EOF
```

### 💾 Cache e Performance

#### Redis Cache para API
```bash
# Instalar Redis usando Helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis bitnami/redis -n northwind-demo \
  --set auth.enabled=false \
  --set master.persistence.enabled=false

# Configurar backend para usar cache
kubectl set env deployment/northwind-backend \
  REDIS_URL=redis://redis-master:6379 \
  CACHE_TTL=300 \
  -n northwind-demo
```

#### CDN para Frontend
```bash
# Azure CDN para assets estáticos
az cdn profile create \
  --name northwind-cdn \
  --resource-group $RESOURCE_GROUP \
  --sku Standard_Microsoft

az cdn endpoint create \
  --name northwind-assets \
  --profile-name northwind-cdn \
  --resource-group $RESOURCE_GROUP \
  --origin northwind-frontend-service.northwind-demo.svc.cluster.local
```

### 🗄️ Otimização de Database

#### Connection Pooling
```yaml
# ConfigMap para pool de conexões otimizado
apiVersion: v1
kind: ConfigMap
metadata:
  name: northwind-db-tuning
  namespace: northwind-demo
data:
  SQLALCHEMY_POOL_SIZE: "20"
  SQLALCHEMY_MAX_OVERFLOW: "30"
  SQLALCHEMY_POOL_TIMEOUT: "30"
  SQLALCHEMY_POOL_RECYCLE: "3600"
  SQLALCHEMY_POOL_PRE_PING: "true"
```

#### Read Replicas
```bash
# Configurar read replica para PostgreSQL
az postgres flexible-server replica create \
  --replica-name northwind-db-read \
  --source-server northwind-db \
  --resource-group $RESOURCE_GROUP

# Configurar aplicação para usar read replica em queries
kubectl set env deployment/northwind-backend \
  DATABASE_READ_URL="postgresql://user:pass@northwind-db-read.postgres.database.azure.com/northwind" \
  -n northwind-demo
```

### 📊 Monitoramento de Performance

#### Métricas Customizadas Avançadas
```python
# Exemplos de métricas customizadas no backend
from prometheus_client import Counter, Histogram, Gauge

# Contadores de negócio
orders_total = Counter('northwind_orders_total', 'Total orders processed', ['status'])
revenue_total = Counter('northwind_revenue_total', 'Total revenue generated', ['currency'])

# Histogramas para latência
request_duration = Histogram('northwind_request_duration_seconds', 'Request duration', ['endpoint'])

# Gauges para recursos
active_connections = Gauge('northwind_db_active_connections', 'Active database connections')
```

#### Alertas Inteligentes
```bash
# Script para criar alertas baseados em métricas de negócio
./scripts/create-smart-alerts.sh <<EOF
# Alerta de alta latência
az monitor metrics alert create \
  --name "NorthwindHighLatency" \
  --resource-group $RESOURCE_GROUP \
  --scopes /subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/components/$APP_INSIGHTS \
  --condition "avg requests/duration > 5000" \
  --description "API latency above 5 seconds"

# Alerta de erro rate
az monitor metrics alert create \
  --name "NorthwindErrorRate" \
  --resource-group $RESOURCE_GROUP \
  --scopes /subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/components/$APP_INSIGHTS \
  --condition "avg requests/failed > 10" \
  --description "Error rate above 10%"
EOF
```

### 🎯 Testes de Performance

#### Testes de Carga Customizados
```bash
# Teste de pico de tráfego (Black Friday simulation)
kubectl patch deployment northwind-loadgen -n northwind-demo -p '{
  "spec":{
    "replicas":5,
    "template":{
      "spec":{
        "containers":[{
          "name":"northwind-loadgen",
          "env":[
            {"name":"LOAD_USERS","value":"100"},
            {"name":"LOAD_SPAWN_RATE","value":"10"},
            {"name":"LOAD_DURATION","value":"3600"},
            {"name":"SCENARIOS","value":"checkout_heavy"}
          ]
        }]
      }
    }
  }
}'

# Teste de stress prolongado
kubectl set env deployment/northwind-loadgen \
  LOAD_USERS=200 \
  LOAD_DURATION=7200 \
  ERROR_PAYMENT_RATE=15 \
  ERROR_STOCK_RATE=10 \
  -n northwind-demo

# Teste de cenários específicos
kubectl create job northwind-peak-test --from=deployment/northwind-loadgen -n northwind-demo
```

#### Benchmark de Performance
```bash
# Script de benchmark automatizado
./scripts/performance-benchmark.sh <<EOF
#!/bin/bash
echo "🚀 Iniciando benchmark de performance..."

# Baseline test
echo "📊 Teste baseline (10 usuários)"
kubectl set env deployment/northwind-loadgen LOAD_USERS=10 LOAD_DURATION=300 -n northwind-demo

# Load test  
echo "📈 Teste de carga (50 usuários)"
kubectl set env deployment/northwind-loadgen LOAD_USERS=50 LOAD_DURATION=600 -n northwind-demo

# Stress test
echo "⚡ Teste de stress (100 usuários)" 
kubectl set env deployment/northwind-loadgen LOAD_USERS=100 LOAD_DURATION=900 -n northwind-demo

# Coleta de métricas
kubectl top pods -n northwind-demo
az monitor metrics list --resource $APP_INSIGHTS_ID --metrics requests/rate
EOF
```

---

## � Licença

Este projeto está licenciado sob a MIT License com disclaimers específicos para uso de demonstração.
Consulte o arquivo [LICENSE](LICENSE) para detalhes completos sobre:

- ✅ **Permitido**: Uso livre, cópia, modificação e distribuição
- ⚠️ **Responsabilidade**: Uso por conta e risco próprios
- 🚫 **Sem suporte**: Não há suporte técnico ou garantias
- 🏢 **Disclaimer corporativo**: Sem vínculo com empresa empregadora

## 📞 Suporte

Para dúvidas sobre esta demonstração:
- Verifique os logs dos pods no AKS
- Consulte a documentação do Application Insights
- Analise as métricas no Azure Portal
- Use os scripts de troubleshooting em `./scripts/`

**⚠️ AVISO IMPORTANTE**: Este é um ambiente de demonstração. Não use em produção sem:
- Revisão completa de segurança
- Adaptação às suas políticas corporativas
- Implementação de práticas adequadas de governança
- Testes de penetração e auditoria de código