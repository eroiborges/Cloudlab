#!/bin/bash

# Script completo de setup e deploy da demo Northwind
# Uso: ./setup-demo.sh [acr-name] [resource-group] [aks-name]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Parâmetros
ACR_NAME=${1}
RESOURCE_GROUP=${2}
AKS_NAME=${3}
TAG="latest"

# Funções auxiliares
print_header() {
    echo -e "${MAGENTA}=====================================${NC}"
    echo -e "${MAGENTA}🎯 $1${NC}"
    echo -e "${MAGENTA}=====================================${NC}"
}

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "${CYAN}🔸 $1${NC}"
}

# Validar parâmetros
if [[ -z "$ACR_NAME" || -z "$RESOURCE_GROUP" || -z "$AKS_NAME" ]]; then
    print_error "Parâmetros obrigatórios faltando!"
    echo
    echo "Uso: $0 <acr-name> <resource-group> <aks-name>"
    echo "Exemplo: $0 mynorthwindacr rg-northwind-demo aks-northwind"
    echo
    echo "Este script irá:"
    echo "  1. Criar/verificar ACR"
    echo "  2. Fazer build e push das imagens"
    echo "  3. Conectar ao AKS"
    echo "  4. Atualizar manifests Kubernetes"
    echo "  5. Fazer deploy completo no AKS"
    exit 1
fi

print_header "SETUP COMPLETO - NORTHWIND DEMO"
print_info "ACR: $ACR_NAME"
print_info "Resource Group: $RESOURCE_GROUP"
print_info "AKS: $AKS_NAME"
echo

# 1. Verificar pré-requisitos
print_header "1. VERIFICANDO PRÉ-REQUISITOS"

# Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI não encontrado. Instale: https://docs.microsoft.com/cli/azure/"
    exit 1
fi
print_status "Azure CLI encontrado"

# Docker
if ! docker info &> /dev/null; then
    print_error "Docker não está rodando"
    exit 1
fi
print_status "Docker está rodando"

# kubectl
if ! command -v kubectl &> /dev/null; then
    print_warning "kubectl não encontrado. Instalando..."
    az aks install-cli
fi
print_status "kubectl disponível"

# Login no Azure
if ! az account show &> /dev/null; then
    print_step "Fazendo login no Azure..."
    az login
fi

SUBSCRIPTION=$(az account show --query id -o tsv)
print_status "Logado na subscription: $SUBSCRIPTION"
echo

# 2. Configurar ACR
print_header "2. CONFIGURANDO AZURE CONTAINER REGISTRY"

if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_step "Criando ACR: $ACR_NAME"
    az acr create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACR_NAME" \
        --sku Standard \
        --admin-enabled true \
        --location eastus2
    print_status "ACR criado"
else
    print_status "ACR já existe"
fi

# Habilitar admin se necessário
az acr update --name "$ACR_NAME" --admin-enabled true
print_status "ACR configurado"
echo

# 3. Build e Push das imagens
print_header "3. BUILD E PUSH DAS IMAGENS"

build_and_push() {
    local service=$1
    local dir=$2
    
    print_step "Building northwind-$service..."
    cd "$dir"
    
    docker build -t "northwind-$service:$TAG" . --quiet
    docker tag "northwind-$service:$TAG" "$ACR_NAME.azurecr.io/northwind-$service:$TAG"
    
    cd ..
    print_status "$service built"
}

build_and_push "backend" "backend"
build_and_push "frontend" "frontend"
build_and_push "loadgen" "loadgen"

# Login no ACR e push
print_step "Fazendo login no ACR e push das imagens..."
az acr login --name "$ACR_NAME"

docker push "$ACR_NAME.azurecr.io/northwind-backend:$TAG" --quiet &
docker push "$ACR_NAME.azurecr.io/northwind-frontend:$TAG" --quiet &
docker push "$ACR_NAME.azurecr.io/northwind-loadgen:$TAG" --quiet &

wait
print_status "Todas as imagens enviadas para o ACR"
echo

# 4. Conectar ao AKS
print_header "4. CONECTANDO AO AKS"

print_step "Obtendo credenciais do AKS..."
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --overwrite-existing

# Verificar conexão
if kubectl cluster-info &> /dev/null; then
    print_status "Conectado ao AKS: $AKS_NAME"
else
    print_error "Falha ao conectar no AKS"
    exit 1
fi
echo

# 5. Atualizar manifests
print_header "5. ATUALIZANDO MANIFESTS KUBERNETES"

print_step "Atualizando referências do ACR nos manifests..."
find k8s/ -name "*.yaml" -exec sed -i.bak "s|your-acr\.azurecr\.io|$ACR_NAME.azurecr.io|g" {} +
rm -f k8s/*.bak

print_status "Manifests atualizados"
echo

# 6. Deploy no AKS
print_header "6. DEPLOY NO AKS"

print_step "Aplicando namespace..."
kubectl apply -f k8s/namespace.yaml

print_step "Aplicando configurações..."
kubectl apply -f k8s/configmap.yaml

print_step "Deploying aplicações..."
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/loadgen-deployment.yaml

print_step "Configurando ingress e scaling..."
kubectl apply -f k8s/ingress-hpa.yaml

print_step "Aplicando políticas de segurança..."
kubectl apply -f k8s/policies.yaml

print_status "Deploy aplicado no AKS"
echo

# 7. Aguardar pods
print_header "7. AGUARDANDO PODS FICAREM PRONTOS"

print_step "Aguardando backend ficar pronto..."
kubectl wait --for=condition=ready pod -l app=northwind-backend -n northwind-demo --timeout=300s

print_step "Aguardando frontend ficar pronto..."  
kubectl wait --for=condition=ready pod -l app=northwind-frontend -n northwind-demo --timeout=300s

print_status "Todos os pods estão prontos!"
echo

# 8. Informações finais
print_header "8. INFORMAÇÕES DE ACESSO"

echo "📋 Status dos recursos:"
kubectl get pods,services,ingress -n northwind-demo

echo
echo "🌐 Endpoints de acesso:"

# Frontend
FRONTEND_IP=$(kubectl get service northwind-frontend-service -n northwind-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "aguardando...")
echo "   Frontend: http://$FRONTEND_IP"

# Load Generator
LOADGEN_IP=$(kubectl get service northwind-loadgen-service -n northwind-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "aguardando...")
echo "   Load Generator: http://$LOADGEN_IP:8089"

echo
echo "🔍 Comandos úteis:"
echo "   kubectl logs -f deployment/northwind-backend -n northwind-demo"
echo "   kubectl logs -f deployment/northwind-frontend -n northwind-demo"
echo "   kubectl get events -n northwind-demo --sort-by=.metadata.creationTimestamp"

echo
print_status "🎉 SETUP COMPLETO! A demo está pronta para uso."

echo
print_info "📝 Próximos passos:"
echo "   1. Configure as variáveis de ambiente no ConfigMap/Secret"
echo "   2. Atualize a connection string do PostgreSQL"  
echo "   3. Configure a connection string do Application Insights"
echo "   4. Teste os cenários na aplicação web"