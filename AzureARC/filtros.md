# Azure Arc - Filtros de Query para Connected Machines

Este documento apresenta exemplos de como filtrar a lista de servidores Azure Arc usando queries JMESPath no Azure CLI.

## Comando Base
```bash
az connectedmachine list -g "$RESOURCE_GROUP" --query "[].name" -o tsv
```

## Filtros por Nome

### Filtrar por padrão de nome
```bash
# Máquinas com nomes que começam com "web"
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?starts_with(name, 'web')].name" -o tsv)

# Máquinas com nomes que contêm "prod"
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?contains(name, 'prod')].name" -o tsv)

# Máquinas com nomes que terminam com "01"
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?ends_with(name, '01')].name" -o tsv)

# Máquinas que NÃO contêm "test" no nome
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?!contains(name, 'test')].name" -o tsv)
```

### Filtrar nomes específicos
```bash
# Filtrar máquinas específicas
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?name=='vm1' || name=='vm2' || name=='vm3'].name" -o tsv)

# Usando array contains
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?contains(['vm1','vm2','vm3'], name)].name" -o tsv)
```

## Filtros por Status

```bash
# Apenas máquinas conectadas
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?status=='Connected'].name" -o tsv)

# Apenas máquinas desconectadas
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?status=='Disconnected'].name" -o tsv)
```

## Filtros por Sistema Operacional

```bash
# Apenas máquinas Windows
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='windows'].name" -o tsv)

# Apenas máquinas Linux
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='linux'].name" -o tsv)
```

## Filtros por Tags

```bash
# Máquinas com tag específica
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?tags.Environment=='Production'].name" -o tsv)

# Máquinas que possuem uma tag específica (independente do valor)
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?tags.Owner].name" -o tsv)

# Máquinas com múltiplas condições de tags
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?tags.Environment=='Production' && tags.Team=='DevOps'].name" -o tsv)
```

## Filtros Combinados

```bash
# Windows conectadas com "web" no nome
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='windows' && status=='Connected' && contains(name, 'web')].name" -o tsv)

# Linux em produção que estão conectadas
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='linux' && status=='Connected' && tags.Environment=='Production'].name" -o tsv)

# Máquinas conectadas excluindo ambiente de teste
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?status=='Connected' && !contains(name, 'test') && tags.Environment!='Test'].name" -o tsv)
```

## Obtendo Informações Adicionais

```bash
# Nome e status para máquinas conectadas
export arcvminfo=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?status=='Connected'].[name,status]" -o tsv)

# Nome e SO para máquinas de produção
export arcvminfo=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?contains(name, 'prod')].[name,osName]" -o tsv)

# Informações completas com filtros
export arcvminfo=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?status=='Connected'].[name,osName,status,tags.Environment]" -o table)
```

## Filtros por Localização

```bash
# Máquinas em região específica
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?location=='eastus2'].name" -o tsv)

# Máquinas em múltiplas regiões
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?contains(['eastus','westus','centralus'], location)].name" -o tsv)
```

## Filtros por Versão do Agente

```bash
# Máquinas com versão específica do agente
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?agentVersion=='1.34.02345.1234'].name" -o tsv)

# Máquinas com versões antigas do agente (exemplo)
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?agentVersion<'1.30'].name" -o tsv)
```

## Exemplo Prático no Script

```bash
#!/bin/bash

# Variables
export RESOURCE_GROUP="rg-arcservers"
export EXTENSION_NAME="WindowsAgent.SqlServer"

# Obter apenas máquinas Windows conectadas (mais eficiente para extensões SQL)
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='windows' && status=='Connected'].name" -o tsv)

# Loop through each VM name
for vm in $arcvmnames; do
  echo "Checking VM: $vm"
  
  az connectedmachine extension show --name "$EXTENSION_NAME" --machine-name "$vm" --resource-group "$RESOURCE_GROUP" &> /dev/null
  
  if [ $? -eq 0 ]; then
    echo "Extension $EXTENSION_NAME exists on $vm"
    echo "updating extension $EXTENSION_NAME from $vm"
    az connectedmachine extension update --extension-name $EXTENSION_NAME --type WindowsAgent.SqlServer --publisher Microsoft.AzureData --type-handler-version 1.1.3049.285 --machine-name $vm -g $RESOURCE_GROUP --no-wait true
  else
    echo "Extension $EXTENSION_NAME not found on $vm, moving to next"
  fi
done
```

## Operadores Úteis

| Operador | Descrição | Exemplo |
|----------|-----------|---------|
| `==` | Igual | `status=='Connected'` |
| `!=` | Diferente | `status!='Disconnected'` |
| `<` | Menor que | `agentVersion<'1.30'` |
| `>` | Maior que | `agentVersion>'1.25'` |
| `<=` | Menor ou igual | `agentVersion<='1.30'` |
| `>=` | Maior ou igual | `agentVersion>='1.25'` |
| `&&` | E lógico | `status=='Connected' && osName=='windows'` |
| `\|\|` | OU lógico | `name=='vm1' \|\| name=='vm2'` |
| `!` | NÃO lógico | `!contains(name, 'test')` |
| `starts_with()` | Começa com | `starts_with(name, 'web')` |
| `ends_with()` | Termina com | `ends_with(name, '01')` |
| `contains()` | Contém | `contains(name, 'prod')` |

## Dicas

1. **Performance**: Use filtros para reduzir o número de máquinas processadas
2. **Status**: Sempre considere filtrar por `status=='Connected'` para operações de extensão
3. **OS**: Filtre por sistema operacional quando relevante para a extensão
4. **Tags**: Use tags para organizar e filtrar máquinas por ambiente, equipe, etc.
5. **Teste**: Teste os filtros com `-o table` primeiro para validar os resultados