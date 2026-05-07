# SQL Best Practices Assessment em Arc-enabled Servers — Azure CLI direto

Alternativa ao Azure Policy para configurar o SQL Best Practices Assessment
diretamente nos Arc-enabled Servers via `az connectedmachine extension update`.

## Quando usar esta abordagem

| Situação | Policy (DINE) | CLI direto |
|---|---|---|
| Servidores novos onboardados automaticamente | ✅ | ❌ (deve re-executar o script) |
| Visibilidade de compliance no portal | ✅ | ❌ |
| Correção imediata em servidores já existentes | Lento (aguarda ciclo) | ✅ Imediato |
| Evita bugs do CLI (`ResolvePolicyId`) | ❌ | ✅ |
| Controle total sobre cada setting (ex: licença SQL) | ❌ | ✅ |

---

## Passo 0 — Configurar extensões do Azure CLI

Os comandos usados neste guia dependem de duas extensões:

| Extensão | Pacote | Usado em |
|---|---|---|
| `connectedmachine` | estável | `az connectedmachine extension show/update` |
| `resource-graph` | estável | `az graph query` |

> **`az monitor log-analytics workspace`** é parte do core do CLI — **não** instale
> a extensão `log-analytics` (preview, descontinuada). Se ela foi instalada por
> engano, remova-a.

```bash
# 1. Permitir instalação automática de extensões sem prompt interativo
az config set extension.use_dynamic_install=yes_without_prompt

# 2. Instalar/atualizar extensões necessárias (ambas têm versão estável)
az extension add --name connectedmachine --upgrade
az extension add --name resource-graph   --upgrade

# 3. Verificar versões instaladas
az extension list \
  --query "[?name=='connectedmachine' || name=='resource-graph'].{Name:name, Version:version, Preview:preview}" \
  --output table

# 4. Se a extensão log-analytics (preview/legada) foi instalada, remover
az extension remove --name log-analytics 2>/dev/null \
  && echo "log-analytics extension removida" \
  || echo "log-analytics extension não estava instalada"

# 5. Confirmar que az monitor log-analytics funciona pelo core do CLI (sem extensão)
az monitor log-analytics workspace list --query "[0].name" --output tsv
```

Saída esperada do passo 3 (sem `Preview: True`):
```
Name              Version    Preview
----------------  ---------  ---------
connectedmachine  0.x.x      False
resource-graph    2.x.x      False
```

---

## Variáveis

```bash
RG_NAME="rg-arcservers"
LA_RG_NAME="rg-arcservers"          # Resource Group do Log Analytics Workspace
LA_WORKSPACE_NAME="arclaw"          # Nome do Log Analytics Workspace
LA_WORKSPACE_LOCATION="centralus"
```

---

## Passo 1 — Resolver o ARM Resource ID do Log Analytics Workspace

Os comandos seguintes exigem o ARM resource ID completo do workspace:
`/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>`

Usando o Resource Group e o nome do workspace (informações visíveis no portal):

```bash
LA_RESOURCE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$LA_RG_NAME" \
  --workspace-name "$LA_WORKSPACE_NAME" \
  --query id \
  --output tsv | tr -d '[:space:]')

echo "LA Resource ID: $LA_RESOURCE_ID"
```

---

## Passo 2 — Listar Arc machines com extensão SQL instalada

Listar todas as máquinas Arc no resource group:

```bash
az connectedmachine list \
  --resource-group "$RG_NAME" \
  --query "[].name" \
  --output tsv
```

Por máquina, verificar se a extensão SQL está presente e seu estado:

```bash
MACHINE_NAME="SQLDB01"

az connectedmachine extension list \
  --machine-name   "$MACHINE_NAME" \
  --resource-group "$RG_NAME" \
  --query "[?name=='WindowsAgent.SqlServer'].{name:name, version:properties.typeHandlerVersion, state:properties.provisioningState}" \
  --output table
```

> A extensão relevante é `WindowsAgent.SqlServer`. Versão mínima recomendada: `1.1.x`
> para suporte GA a `AssessmentSettings`.

---

## Passo 3 — Ler as configurações atuais da extensão

**IMPORTANTE:** O `--settings` em `extension update` é uma substituição completa
do objeto, não um merge/diff. Leia os valores atuais antes de atualizar para
não sobrescrever configurações como `LicenseType`.

```bash
CURRENT_SETTINGS=$(az connectedmachine extension show \
  --machine-name   "$MACHINE_NAME" \
  --resource-group "$RG_NAME" \
  --name           "WindowsAgent.SqlServer" \
  --query          "properties.settings" \
  --output json)

echo "$CURRENT_SETTINGS" | jq .
```

Campos críticos a preservar:

| Campo | Valores possíveis | Impacto se resetado |
|---|---|---|
| `LicenseType` | `PAYG`, `LicenseOnly`, `ServerCAL` | Altera cobrança |
| `EnableExtendedSecurityUpdates` | `true` / `false` | Desativa ESUs |
| `ExcludedInstances` | array de strings | Remove exclusões configuradas |

---

## Passo 4 — Aplicar configuração de Assessment com merge dos valores existentes

Usar `jq` para fazer merge apenas dos campos de assessment, preservando o resto.

**Nota sobre CSP (Cloud Solution Provider):** se o `LicenseType` for `PAYG` em
uma subscription CSP, o campo `ConsentToRecurringPAYG` é obrigatório. O merge
abaixo o preserva se já existir nos settings atuais, e o injeta automaticamente
se `LicenseType` for `PAYG` e ainda não estiver presente.

**Schedule — valores válidos:**

| Campo | Valores aceitos | Equivalente no portal |
|---|---|---|
| `Frequency` | `"Weekly"`, `"Monthly"` | Frequency radio |
| `DayOfWeek` | `"Sunday"` … `"Saturday"` | Day of week dropdown |
| `WeeklyInterval` | `1` … `6` | Recurrence (Every N week(s)) |
| `MonthlyOccurrence` | `1` … `5` | Recurrence (Monthly, week N of month) |
| `StartTime` | `"HH:MM"` (24h, hora local da máquina) | Assessment start |

Omitir `Schedule` mantém o padrão do portal (Weekly, Monday, cada 1 semana).

```bash
CONSENT_TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Ajuste os valores de agendamento conforme necessário
SCHEDULE_FREQUENCY="Weekly"     # Weekly | Monthly
SCHEDULE_DAY="Monday"           # Sunday..Saturday
SCHEDULE_INTERVAL=1             # a cada N semanas (Weekly) ou N ocorrências (Monthly)
SCHEDULE_START="02:00"          # hora local da máquina

NEW_SETTINGS=$(echo "$CURRENT_SETTINGS" | jq \
  --arg laId        "$LA_RESOURCE_ID" \
  --arg laLoc       "$LA_WORKSPACE_LOCATION" \
  --arg consentTs   "$CONSENT_TIMESTAMP" \
  --arg freq        "$SCHEDULE_FREQUENCY" \
  --arg day         "$SCHEDULE_DAY" \
  --argjson interval "$SCHEDULE_INTERVAL" \
  --arg startTime   "$SCHEDULE_START" \
  '
  # Adiciona/atualiza AssessmentSettings com agendamento
  .AssessmentSettings = {
    "Enable":              true,
    "WorkspaceResourceId": $laId,
    "WorkspaceLocation":   $laLoc,
    "Schedule": {
      "Frequency":       $freq,
      "DayOfWeek":       $day,
      "WeeklyInterval":  $interval,
      "StartTime":       $startTime
    }
  }
  |
  # Se LicenseType for PAYG e ConsentToRecurringPAYG ainda não existir, injeta.
  # Se já existir, preserva o valor original (incluindo ConsentTimestamp original).
  if .LicenseType == "PAYG" and (.ConsentToRecurringPAYG == null) then
    .ConsentToRecurringPAYG = {
      "Consented":        true,
      "ConsentTimestamp": $consentTs
    }
  else
    .
  end
  ')

echo "Settings a aplicar:"
echo "$NEW_SETTINGS" | jq .

az connectedmachine extension update \
  --machine-name   "$MACHINE_NAME" \
  --resource-group "$RG_NAME" \
  --name           "WindowsAgent.SqlServer" \
  --settings       "$NEW_SETTINGS"
```

Campos críticos preservados pelo merge:

| Campo | Comportamento |
|---|---|
| `LicenseType` | Preservado do estado atual |
| `ConsentToRecurringPAYG` | Preservado se existir; injetado se PAYG sem consentimento |
| `EnableExtendedSecurityUpdates` | Preservado do estado atual |
| `ExcludedInstances` | Preservado do estado atual |
| `AssessmentSettings` | **Sobrescrito** com novos valores de workspace |

---

## Passo 5 — Aplicar em todos os servidores do resource group (loop)

Usar **Azure Resource Graph** para obter apenas as máquinas com extensão SQL instalada

```bash
# Query Resource Graph: retorna apenas máquinas com WindowsAgent.SqlServer ou LinuxAgent.SqlServer
SQL_MACHINES_QUERY='resources
| where type == "microsoft.hybridcompute/machines/extensions"
| where properties.type in ("WindowsAgent.SqlServer","LinuxAgent.SqlServer")
| extend machineId = substring(id, 0, indexof(id, "/extensions"))
| extend extensionName = substring(id, indexof(id, "/extensions/") + 12)
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | where resourceGroup == "'"$RG_NAME"'"
) on $left.machineId == $right.id
| project MachineName = name1, ResourceGroup = resourceGroup1, ExtensionName = extensionName'

echo "Buscando máquinas Arc com extensão SQL via Resource Graph..."
SQL_MACHINES=$(az graph query -q "$SQL_MACHINES_QUERY" --output json)

MACHINE_COUNT=$(echo "$SQL_MACHINES" | jq '.data | length')
echo "  Encontradas: $MACHINE_COUNT máquina(s) com extensão SQL"

if [[ "$MACHINE_COUNT" -eq 0 ]]; then
  echo "Nenhuma máquina com extensão SQL encontrada no resource group $RG_NAME."
  exit 0
fi

CONSENT_TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Agendamento — ajuste conforme necessário
SCHEDULE_FREQUENCY="Weekly"   # Weekly | Monthly
SCHEDULE_DAY="Monday"         # Sunday..Saturday
SCHEDULE_INTERVAL=1           # a cada N semanas
SCHEDULE_START="02:00"        # hora local da máquina

echo "$SQL_MACHINES" | jq -r '.data[] | [.MachineName, .ResourceGroup, .ExtensionName] | @tsv' | \
while IFS=$'\t' read -r MACHINE_NAME RESOURCE_GROUP EXTENSION_NAME; do

  echo "Processando: $MACHINE_NAME (RG: $RESOURCE_GROUP, ext: $EXTENSION_NAME)"

  # Ler settings atuais — leitura antes de qualquer escrita para não perder campos
  CURRENT_SETTINGS=$(az connectedmachine extension show \
    --machine-name   "$MACHINE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name           "$EXTENSION_NAME" \
    --query          "properties.settings" \
    --output json)

  # Merge: preserva todos os campos existentes, inclui CSP consent se PAYG, sobrescreve AssessmentSettings
  NEW_SETTINGS=$(echo "$CURRENT_SETTINGS" | jq \
    --arg laId      "$LA_RESOURCE_ID" \
    --arg laLoc     "$LA_WORKSPACE_LOCATION" \
    --arg consentTs "$CONSENT_TIMESTAMP" \
    --arg freq      "$SCHEDULE_FREQUENCY" \
    --arg day       "$SCHEDULE_DAY" \
    --argjson interval "$SCHEDULE_INTERVAL" \
    --arg startTime "$SCHEDULE_START" \
    '
    .AssessmentSettings = {
      "Enable":              true,
      "WorkspaceResourceId": $laId,
      "WorkspaceLocation":   $laLoc,
      "Schedule": {
        "Frequency":      $freq,
        "DayOfWeek":      $day,
        "WeeklyInterval": $interval,
        "StartTime":      $startTime
      }
    }
    |
    if .LicenseType == "PAYG" and (.ConsentToRecurringPAYG == null) then
      .ConsentToRecurringPAYG = {
        "Consented":        true,
        "ConsentTimestamp": $consentTs
      }
    else
      .
    end
    ')

  az connectedmachine extension update \
    --machine-name   "$MACHINE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name           "$EXTENSION_NAME" \
    --settings       "$NEW_SETTINGS"

  echo "  ✓ Assessment configurado em $MACHINE_NAME"
done
```

---

## Passo 6 — Verificar resultado

```bash
# Confirmar settings aplicados por máquina
az connectedmachine extension show \
  --machine-name   "$MACHINE_NAME" \
  --resource-group "$RG_NAME" \
  --name           "WindowsAgent.SqlServer" \
  --query          "properties.settings.AssessmentSettings" \
  --output json

# Verificar assessments gerados no Log Analytics
# (pode levar até 24h para a primeira execução)
az monitor log-analytics query \
  --workspace "$LA_RESOURCE_ID" \
  --analytics-query "SqlAssessmentRecommendation | where TimeGenerated > ago(24h) | summarize count() by Computer" \
  --output table
```

---

## Notas adicionais

- A primeira avaliação pode levar **até 24 horas** após a configuração.
- O agendamento é configurável em `AssessmentSettings.Schedule` (`Frequency`, `DayOfWeek`, `WeeklyInterval`, `StartTime`). Se omitido, o padrão é Weekly/Monday/1 semana.
- Para desabilitar o assessment: altere `"Enable": false` no mesmo fluxo de merge.
- Esta abordagem **não cria compliance visibility** no Azure Policy — combine com
  a policy assignment se quiser dashboard de conformidade, usando este script
  para remediação imediata dos servidores já existentes.
