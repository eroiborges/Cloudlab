#!/bin/bash

# Script para atualizar manifests Kubernetes com ACR específico
# Uso: ./update-manifests.sh [acr-name] [tag]

set -e

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ACR_NAME=${1:-"your-acr"}
TAG=${2:-"latest"}

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_step() {
    echo -e "${CYAN}$1${NC}"
}

if [[ "$ACR_NAME" == "your-acr" ]]; then
    echo "❌ Erro: Forneça o nome do ACR"
    echo "Uso: $0 <acr-name> [tag]"
    echo "Exemplo: $0 myacr latest"
    exit 1
fi

print_step "🔧 Atualizando manifests Kubernetes..."
print_info "ACR: $ACR_NAME.azurecr.io"
print_info "Tag: $TAG"

# Verificar se diretório k8s existe
if [[ ! -d "k8s" ]]; then
    echo "❌ Diretório k8s/ não encontrado"
    exit 1
fi

# Backup dos arquivos originais
print_step "💾 Criando backup dos manifests..."
if [[ ! -d "k8s-backup" ]]; then
    cp -r k8s k8s-backup
    print_status "Backup criado em k8s-backup/"
fi

# Atualizar ACR nos manifests
print_step "📝 Atualizando referências do ACR..."
find k8s/ -name "*.yaml" -exec sed -i.bak "s|your-acr\.azurecr\.io|$ACR_NAME.azurecr.io|g" {} +

# Atualizar tags se fornecida e diferente de 'latest'
if [[ "$TAG" != "latest" ]]; then
    print_step "🏷️  Atualizando tags para: $TAG"
    find k8s/ -name "*.yaml" -exec sed -i.bak "s|:latest|:$TAG|g" {} +
fi

# Remover arquivos de backup temporários
rm -f k8s/*.bak

# Verificar mudanças
print_step "📋 Arquivos atualizados:"
grep -l "$ACR_NAME.azurecr.io" k8s/*.yaml | while read -r file; do
    echo "   - $(basename "$file")"
done

print_status "Manifests atualizados com sucesso!"

echo
print_info "💡 Para aplicar no AKS:"
echo "   kubectl apply -f k8s/"
echo
print_info "🔍 Para verificar imagens nos manifests:"
echo "   grep -n 'image:' k8s/*.yaml"