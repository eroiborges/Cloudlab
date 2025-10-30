#!/bin/bash

# Comando Azure CLI para instalar Wireshark via Custom Script Extension em VM Azure Arc
# Uso: ./install-wireshark-simple.sh <arc-machine-name> <resource-group> [wireshark-version]
# Exemplo: ./install-wireshark-simple.sh fs03 rg-arcservers 4.4.9

ARC_MACHINE_NAME="${1:-fs03}"
RESOURCE_GROUP="${2:-rg-arcservers}"

echo "🚀 Instalando Wireshark na máquina Azure Arc: $ARC_MACHINE_NAME"

# Versão do Wireshark (pode ser passada como terceiro parâmetro)
WIRESHARK_VERSION="${3:-4.4.9}"

# URL do script PowerShell no servidor local
SCRIPT_URL="http://fs03.park.local/Install-Wireshark-Share.ps1"

# Comando para baixar e executar o script PowerShell (força download mesmo se arquivo existir)
POWERSHELL_COMMAND="Remove-Item 'C:\\\\Windows\\\\Temp\\\\Install-Wireshark-Share.ps1' -Force -ErrorAction SilentlyContinue; Invoke-WebRequest -Uri '$SCRIPT_URL' -OutFile 'C:\\\\Windows\\\\Temp\\\\Install-Wireshark-Share.ps1' -UseBasicParsing; & 'C:\\\\Windows\\\\Temp\\\\Install-Wireshark-Share.ps1' -Version '$WIRESHARK_VERSION' -SharePath '\\\\\\\\dc01\\\\Share1\\\\ARC'"

# Executar Custom Script Extension em VM Azure Arc
az connectedmachine extension create \
    --machine-name "$ARC_MACHINE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name "CustomScriptExtension" \
    --publisher "Microsoft.Compute" \
    --type "CustomScriptExtension" \
    --settings "{\"commandToExecute\": \"powershell -Command \\\"$POWERSHELL_COMMAND\\\"\"}"

echo "✅ Custom Script Extension configurada. Verificando status..."

# Aguardar e verificar
sleep 30

STATUS=$(az connectedmachine extension show \
    --machine-name "$ARC_MACHINE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name "CustomScriptExtension" \
    --query "provisioningState" \
    --output tsv 2>/dev/null)

echo "Status: $STATUS"

if [ "$STATUS" = "Succeeded" ]; then
    echo "🎉 Wireshark instalado com sucesso na máquina Arc $ARC_MACHINE_NAME!"
else
    echo "⚠️  Verificar logs da máquina Arc para detalhes"
fi