#!/bin/bash

# Script para instalação em massa do Wireshark via Custom Script Extension em VMs Azure Arc
# Baseado no conceito do demo.sh para extensões SQL Server
# Uso: ./install-wireshark-bulk.sh [resource-group] [wireshark-version]

# Variables
export RESOURCE_GROUP="${1:-rg-arcservers}"
export WIRESHARK_VERSION="${2:-4.4.9}"
export EXTENSION_NAME="CustomScriptExtension"

echo "🚀 Iniciando instalação em massa do Wireshark $WIRESHARK_VERSION"
echo "📁 Resource Group: $RESOURCE_GROUP"
echo "🔧 Extensão: $EXTENSION_NAME"
echo "=================================="

# Get the list of connected Windows VM names (filtro para VMs Windows conectadas)
echo "🔍 Buscando VMs Windows conectadas..."
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='windows' && status=='Connected'].name" -o tsv)

if [ -z "$arcvmnames" ]; then
    echo "❌ Nenhuma VM Windows conectada encontrada no resource group: $RESOURCE_GROUP"
    exit 1
fi

echo "✅ VMs encontradas:"
for vm in $arcvmnames; do
    echo "  - $vm"
done
echo "=================================="

# Loop through each VM name
for vm in $arcvmnames; do
    echo "🖥️  Processando VM: $vm"

    # Verificar se a extensão CustomScriptExtension já existe
    az connectedmachine extension show --name "$EXTENSION_NAME" --machine-name "$vm" --resource-group "$RESOURCE_GROUP" &> /dev/null

    if [ $? -eq 0 ]; then
        echo "⚠️  Extensão $EXTENSION_NAME já existe em $vm - removendo..."
        az connectedmachine extension delete --name "$EXTENSION_NAME" --machine-name "$vm" --resource-group "$RESOURCE_GROUP" --no-wait
        echo "⏳ Aguardando remoção da extensão..."
        sleep 30
    fi

    echo "📦 Instalando Wireshark $WIRESHARK_VERSION em $vm..."
    
    # Executar o script de instalação individual
    ./install-wireshark-simple.sh "$vm" "$RESOURCE_GROUP" "$WIRESHARK_VERSION"
    
    if [ $? -eq 0 ]; then
        echo "✅ Instalação iniciada com sucesso em $vm"
    else
        echo "❌ Falha ao iniciar instalação em $vm"
    fi
    
    echo "⏳ Aguardando antes da próxima VM..."
    sleep 60
    echo "=================================="
done

echo "🎉 Processo de instalação em massa concluído!"
echo "📝 Para verificar o status das instalações, use:"
echo "   az connectedmachine extension list --machine-name <vm-name> -g $RESOURCE_GROUP -o table"
echo ""
echo "📊 Para verificar logs detalhados:"
echo "   az connectedmachine extension show --name CustomScriptExtension --machine-name <vm-name> -g $RESOURCE_GROUP --query instanceView"