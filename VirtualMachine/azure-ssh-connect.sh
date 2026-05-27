#!/bin/bash
set -euo pipefail

# =============================
# CONFIGURACAO
# =============================
rg="rg-linux-entra-demo"
SSH_CONF="$HOME/.ssh/azure-vms.conf"
KEYS_DIR="$HOME/.aadkeys"

# =============================
# LISTAR VMs LINUX
# =============================
echo ""
echo "Buscando VMs Linux em: $rg"

mapfile -t vms < <(az vm list \
  --resource-group "$rg" \
  --query "[?storageProfile.osDisk.osType=='Linux'].name" \
  --output tsv 2>/dev/null | sort)

if [[ ${#vms[@]} -eq 0 ]]; then
    echo "Nenhuma VM Linux encontrada em '$rg'."
    exit 1
fi

# =============================
# SELECAO
# =============================
echo ""
echo "VMs disponíveis:"
for i in "${!vms[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${vms[$i]}"
done
echo ""

while true; do
    read -rp "Escolha o número da VM: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#vms[@]} )); then
        vm_name="${vms[$((choice-1))]}"
        break
    fi
    echo "  Opção inválida. Digite um número entre 1 e ${#vms[@]}."
done

echo ""
echo ">> VM selecionada: $vm_name"

# =============================
# LIMPEZA - azure-vms.conf
# =============================
mkdir -p "$(dirname "$SSH_CONF")"

if [[ -f "$SSH_CONF" ]]; then
    echo "Limpando entradas antigas de '$vm_name' em $SSH_CONF..."
    awk -v vm="$vm_name" '
        /^Host / {
            skip = (index($0, vm) > 0) ? 1 : 0
            if (skip) next
        }
        !skip { print }
    ' "$SSH_CONF" > "$SSH_CONF.tmp"
    mv "$SSH_CONF.tmp" "$SSH_CONF"
fi

# =============================
# LIMPEZA - chaves antigas
# =============================
mkdir -p "$KEYS_DIR"

if [[ -f "$KEYS_DIR/id_rsa" ]] || [[ -f "$KEYS_DIR/id_rsa.pub" ]]; then
    echo "Removendo chaves antigas em $KEYS_DIR..."
    rm -f "$KEYS_DIR/id_rsa" "$KEYS_DIR/id_rsa.pub"
fi

# =============================
# GERAR SSH CONFIG
# =============================
echo ""
echo "Gerando configuração SSH para '$vm_name'..."

az ssh config \
  --resource-group "$rg" \
  --name "$vm_name" \
  --file "$SSH_CONF" \
  --keys-dest-folder "$KEYS_DIR"

echo ""
echo "Configuração gerada com sucesso!"
echo ""
echo "Para conectar:"
echo "  ssh ${rg}-${vm_name}"
echo "  az ssh vm --resource-group $rg --name $vm_name"
echo ""
echo "Arquivo de config atualizado: $SSH_CONF"
