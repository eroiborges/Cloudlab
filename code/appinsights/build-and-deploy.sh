#!/bin/bash

# Script de build e deploy das imagens Docker
# Uso: ./build-and-deploy.sh [acr-name] [tag] [resource-group]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parâmetros
ACR_NAME=${1:-"your-acr"}
TAG=${2:-"latest"}
RESOURCE_GROUP=${3:-""}

# Funções auxiliares
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
    echo -e "${CYAN}$1${NC}"
}

# Validar se Azure CLI está instalado
if ! command -v az &> /dev/null; then
    print_error "Azure CLI não está instalado. Instale em: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Validar se Docker está rodando
if ! docker info &> /dev/null; then
    print_error "Docker não está rodando. Inicie o Docker Desktop."
    exit 1
fi

# Verificar login no Azure
if ! az account show &> /dev/null; then
    print_warning "Não está logado no Azure. Fazendo login..."
    az login
fi

print_step "🏗️  Iniciando build das imagens Docker..."
print_info "ACR: $ACR_NAME.azurecr.io"
print_info "Tag: $TAG"

# Verificar se ACR existe
print_step "🔍 Verificando Azure Container Registry..."
if ! az acr show --name "$ACR_NAME" &> /dev/null; then
    if [[ -n "$RESOURCE_GROUP" ]]; then
        print_warning "ACR '$ACR_NAME' não existe. Criando..."
        az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Basic --admin-enabled true
        print_status "ACR criado com sucesso!"
    else
        print_error "ACR '$ACR_NAME' não existe e resource group não foi fornecido."
        print_info "Uso: $0 <acr-name> [tag] [resource-group]"
        exit 1
    fi
fi

# Build com tratamento de erro
build_image() {
    local service=$1
    local dir=$2
    
    print_step "📦 Building $service..."
    
    if [[ ! -d "$dir" ]]; then
        print_error "Diretório '$dir' não encontrado"
        return 1
    fi
    
    cd "$dir"
    
    if [[ ! -f "Dockerfile" ]]; then
        print_error "Dockerfile não encontrado em '$dir'"
        cd ..
        return 1
    fi
    
    # Validação específica para frontend
    if [[ "$service" == "frontend" ]]; then
        if [[ ! -f "package.json" ]]; then
            print_error "package.json não encontrado no frontend"
            cd ..
            return 1
        fi
        
        if ! grep -q "react-scripts" package.json; then
            print_error "react-scripts não encontrado em package.json. Verifique as dependências."
            cd ..
            return 1
        fi
        
        # Verificar dependências críticas
        missing_deps=()
        if ! grep -q "bootstrap-icons" package.json; then
            missing_deps+=("bootstrap-icons")
        fi
        
        if [ ${#missing_deps[@]} -ne 0 ]; then
            print_error "Dependências faltando no package.json: ${missing_deps[*]}"
            print_error "Execute: cd frontend && npm install ${missing_deps[*]}"
            cd ..
            return 1
        fi
        
        # Verificar se node_modules existe localmente (pode interferir no build)
        if [[ -d "node_modules" ]]; then
            print_status "Removendo node_modules local para build limpo..."
            rm -rf node_modules
        fi
    fi
    
    print_status "Building $service..."
    if ! docker build -t "northwind-$service:$TAG" .; then
        print_error "Falha no build do $service"
        print_error "Verifique os logs acima para mais detalhes"
        cd ..
        return 1
    fi
    
    docker tag "northwind-$service:$TAG" "$ACR_NAME.azurecr.io/northwind-$service:$TAG"
    cd ..
    
    print_status "$service built successfully"
}

# Build das imagens
build_image "backend" "backend" || exit 1
build_image "frontend" "frontend" || exit 1  
build_image "loadgen" "loadgen" || exit 1

print_status "Build de todas as imagens concluído!"

# Listar imagens criadas
print_step "📋 Imagens criadas:"
docker images | grep northwind | grep "$TAG"

# Push to ACR (opcional)
echo
read -p "Fazer push para $ACR_NAME.azurecr.io? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "🚀 Fazendo login no ACR..."
    
    # Login com admin credentials ou managed identity
    if ! az acr login --name "$ACR_NAME"; then
        print_warning "Falha no login automático. Tentando com credenciais admin..."
        # Habilita admin user se necessário
        az acr update --name "$ACR_NAME" --admin-enabled true
        az acr login --name "$ACR_NAME"
    fi

    print_step "📤 Pushing images para ACR..."
    
    # Push com retry e verificação
    push_image() {
        local image=$1
        local max_retries=3
        local retry=0
        
        while [[ $retry -lt $max_retries ]]; do
            if docker push "$ACR_NAME.azurecr.io/northwind-$image:$TAG"; then
                print_status "$image pushed successfully"
                return 0
            else
                ((retry++))
                print_warning "Retry $retry/$max_retries para $image..."
                sleep 2
            fi
        done
        
        print_error "Falha no push de $image após $max_retries tentativas"
        return 1
    }
    
    push_image "backend" || exit 1
    push_image "frontend" || exit 1
    push_image "loadgen" || exit 1
    
    print_status "Deploy no ACR concluído!"
    
    # Listar repositórios no ACR
    print_step "📋 Repositórios no ACR:"
    az acr repository list --name "$ACR_NAME" --output table
fi

# Instruções finais
echo
print_step "🎯 Próximos passos:"
echo "   1. Atualizar k8s/*.yaml substituindo 'your-acr' por: $ACR_NAME"
echo "   2. Aplicar no AKS: kubectl apply -f k8s/"
echo "   3. Ou usar o script: ./deploy-aks.sh"

# Comando para atualizar manifests automaticamente
echo
print_info "💡 Para atualizar automaticamente os manifests k8s:"
echo "   find k8s/ -name '*.yaml' -exec sed -i 's/your-acr.azurecr.io/$ACR_NAME.azurecr.io/g' {} +"

# Informações do ACR
echo
print_step "📊 Informações do ACR:"
az acr show --name "$ACR_NAME" --query "{name:name,loginServer:loginServer,resourceGroup:resourceGroup,sku:sku.name}" --output table