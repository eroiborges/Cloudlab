# Azure Arc - Custom Extension Script para Instalação de Software

## Visão Geral

Este documento descreve um cenário de teste para instalação automatizada de software em servidores Azure Arc Connected Machines usando Custom Extension Script. O exemplo demonstra a instalação do Wireshark através de uma arquitetura distribuída com servidor web e servidor de arquivos.

## Arquitetura do Cenário

```text
Azure Portal/CLI
    ↓ (Custom Script Extension)
VM Azure Arc ←→ Web Server (HTTP) ←→ File Server (SMB/Share)
    ↓                ↓                    ↓
Script Local    Script PowerShell      Binário Wireshark
```

### Componentes da Solução

1. **VM Azure Arc**: Servidor de destino onde o software será instalado
2. **Web Server**: Servidor HTTP local que hospeda o script PowerShell
3. **File Server**: Servidor de arquivos (SMB share) que armazena os binários
4. **Custom Script Extension**: Extensão do Azure que executa o script remotamente

## Arquivos do Projeto

### 1. `install-wireshark-simple.sh`

**Função**: Script de injeção do Custom Script Extension

- **Tipo**: Bash script para Azure CLI
- **Objetivo**: Executar o Custom Script Extension em uma VM Azure Arc específica
- **Localização**: Executado localmente (workstation do administrador)

**Funcionalidades**:

- Recebe parâmetros de nome da VM e resource group
- Aplica o Custom Script Extension na VM especificada
- Configura o download do script PowerShell do servidor web
- Monitora o status da execução

### 2. `Install-Wireshark-Share.ps1`

**Função**: Script PowerShell de instalação

- **Tipo**: PowerShell script
- **Objetivo**: Realizar a instalação do Wireshark na VM de destino
- **Localização**: Hospedado no servidor web, executado na VM Arc

**Funcionalidades**:

- Conecta ao servidor de arquivos (SMB share)
- Baixa o binário do Wireshark
- Verifica integridade e assinatura digital
- Executa instalação silenciosa
- Gera logs detalhados do processo
- Limpa arquivos temporários

### 3. `install-wireshark-bulk.sh`

**Função**: Script de instalação em massa com filtros

- **Tipo**: Bash script para Azure CLI
- **Objetivo**: Executar instalação do Wireshark em múltiplas VMs Azure Arc
- **Localização**: Executado localmente (workstation do administrador)

**Funcionalidades**:

- Lista VMs Windows conectadas automaticamente
- Remove extensões existentes antes de nova instalação
- Aplica filtros de query (status, OS, etc.)
- Executa instalação sequencial com intervalo entre VMs
- Fornece logs detalhados do processo em massa
- Suporte a parâmetros para resource group e versão

## Requisitos Técnicos

### Pré-requisitos da Infraestrutura

#### Servidor Web (HTTP)

- **Função**: Hospedar o script PowerShell
- **Requisitos**:
  - Servidor web (IIS, Apache, Nginx, etc.)
  - Acesso HTTP da VM Arc
  - Arquivo `Install-Wireshark-Share.ps1` disponível via URL

#### Servidor de Arquivos (SMB)

- **Função**: Armazenar binários do software
- **Requisitos**:
  - Compartilhamento SMB configurado
  - Permissões de leitura para VMs Arc
  - Binário do Wireshark (exemplo: `Wireshark-4.4.9-x64.exe`)

#### VM Azure Arc

- **Função**: Destino da instalação
- **Requisitos**:
  - Azure Arc Agent instalado e conectado
  - PowerShell 5.1 ou superior
  - Conectividade com servidor web e file server
  - Permissões de administrador local

### Conectividade de Rede

```text
VM Arc ─── HTTP ───→ Web Server (porta 80/443)
   └─── SMB ────→ File Server (porta 445)
```

## Fluxo de Execução

### 1. Preparação do Ambiente

```bash
# 1. Disponibilizar script no servidor web
# Exemplo: http://webserver.local/scripts/Install-Wireshark-Share.ps1

# 2. Colocar binário no file server
# Exemplo: \\fileserver\share\ARC\Wireshark-4.4.9-x64.exe
```

### 2. Execução do Custom Script Extension

```bash
# Executar o script de injeção com parâmetros
./install-wireshark-simple.sh <arc-machine-name> <resource-group> [wireshark-version]

# Exemplo com parâmetros específicos
./install-wireshark-simple.sh fs03 rg-arcservers 4.4.9

# Exemplo usando valores padrão (fs03 e rg-arcservers)
./install-wireshark-simple.sh
```

### 3. Processo na VM Arc

1. **Custom Script Extension**: Azure Arc recebe o comando da extensão
2. **Download**: VM baixa o script PowerShell do servidor web via HTTP
3. **Execução**: Script PowerShell é executado localmente na VM especificada
4. **Conexão**: Script conecta ao servidor de arquivos via SMB
5. **Download**: Binário do Wireshark é copiado para pasta temporária
6. **Instalação**: Execução silenciosa do instalador
7. **Limpeza**: Remoção de arquivos temporários
8. **Log**: Registro detalhado em `C:\Windows\Temp\wireshark-install.log`
9. **Status**: Script bash monitora o status da extensão

## Configuração e Uso

### 1. Configurar Servidor Web

```bash
# Exemplo com servidor web simples Python
cd /caminho/para/scripts
python3 -m http.server 8080
```

### 2. Configurar File Server

```powershell
# Exemplo de share SMB no Windows
New-SmbShare -Name "ARC" -Path "C:\Share\ARC" -ReadAccess "Everyone"
```

### 3. Executar Instalação

#### Instalação em VM Única

```bash
# Executar com parâmetros específicos
./install-wireshark-simple.sh fs03 rg-arcservers 4.4.9

# Executar com valores padrão
./install-wireshark-simple.sh

# Executar apenas especificando a VM (usando resource group padrão)
./install-wireshark-simple.sh minha-vm
```

#### Instalação em Múltiplas VMs (com Filtros)

Para instalar em múltiplas VMs, você pode usar loops com filtros de query. Consulte o arquivo [`filtros.md`](../filtros.md) para mais exemplos de filtros disponíveis.

```bash
# Loop manual em VMs específicas
for vm in vm1 vm2 vm3; do
    echo "Instalando Wireshark na VM: $vm"
    ./install-wireshark-simple.sh "$vm" "rg-arcservers" "4.4.9"
    sleep 60  # Aguardar entre execuções
done

# Usando lista de VMs conectadas (filtro por status)
export RESOURCE_GROUP="rg-arcservers"
for vm in $(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?status=='Connected'].name" -o tsv); do
    echo "Instalando Wireshark na VM: $vm"
    ./install-wireshark-simple.sh "$vm" "$RESOURCE_GROUP" "4.4.9"
    sleep 60
done

# Filtrar apenas VMs Windows conectadas
for vm in $(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?osName=='windows' && status=='Connected'].name" -o tsv); do
    echo "Instalando Wireshark na VM Windows: $vm"
    ./install-wireshark-simple.sh "$vm" "$RESOURCE_GROUP" "4.4.9"
    sleep 60
done

# Filtrar VMs que contêm "prod" no nome
for vm in $(az connectedmachine list -g "$RESOURCE_GROUP" --query "[?contains(name, 'prod') && status=='Connected'].name" -o tsv); do
    echo "Instalando Wireshark na VM de produção: $vm"
    ./install-wireshark-simple.sh "$vm" "$RESOURCE_GROUP" "4.4.9"
    sleep 60
done
```

#### Script de Loop Automatizado (`install-wireshark-bulk.sh`)

Para facilitar a instalação em múltiplas VMs, você pode usar o script `install-wireshark-bulk.sh` que implementa a lógica de loop com verificação de status e filtros automáticos:

```bash
# Executar com valores padrão (rg-arcservers, versão 4.4.9)
./install-wireshark-bulk.sh

# Especificar resource group
./install-wireshark-bulk.sh "meu-resource-group"

# Especificar resource group e versão
./install-wireshark-bulk.sh "meu-resource-group" "4.2.0"
```

**Características do script bulk**:

- ✅ **Filtro automático**: Apenas VMs Windows conectadas
- ✅ **Limpeza prévia**: Remove extensões existentes antes de instalar
- ✅ **Intervalo entre VMs**: 60 segundos de pausa entre instalações
- ✅ **Logs detalhados**: Status de cada etapa do processo
- ✅ **Tratamento de erros**: Continua mesmo se uma VM falhar
- ✅ **Baseado no padrão**: Usa a mesma lógica do `demo.sh` original

**Filtro aplicado no script bulk**:

```bash
# Lista apenas VMs Windows conectadas
az connectedmachine list -g "$RESOURCE_GROUP" \
  --query "[?osName=='windows' && status=='Connected'].name" -o tsv
```

> 💡 **Dica**: Para conhecer outros filtros disponíveis (por tags, região, nome, etc.), consulte o arquivo [`filtros.md`](../filtros.md) que contém exemplos detalhados de queries JMESPath para diferentes cenários.

## Parâmetros Configuráveis

### Script PowerShell (`Install-Wireshark-Share.ps1`)

- `$Version`: Versão do Wireshark (padrão: "4.4.9")
- `$SharePath`: Caminho do share SMB (padrão: "\\dc01\Share1\ARC")

### Script Bash (`install-wireshark-simple.sh`)

**Parâmetros de linha de comando**:

- `$1` - `ARC_MACHINE_NAME`: Nome da VM Azure Arc (padrão: "fs03")
- `$2` - `RESOURCE_GROUP`: Grupo de recursos (padrão: "rg-arcservers")
- `$3` - `WIRESHARK_VERSION`: Versão do Wireshark (padrão: "4.4.9")

**Parâmetros internos**:

- `SCRIPT_URL`: URL do script PowerShell no servidor web
- `POWERSHELL_COMMAND`: Comando para download e execução na VM

### Script Bash (`install-wireshark-bulk.sh`)

**Parâmetros de linha de comando**:

- `$1` - `RESOURCE_GROUP`: Grupo de recursos (padrão: "rg-arcservers")
- `$2` - `WIRESHARK_VERSION`: Versão do Wireshark (padrão: "4.4.9")

**Parâmetros internos**:

- `EXTENSION_NAME`: Nome da extensão (fixo: "CustomScriptExtension")
- `arcvmnames`: Lista de VMs obtida via query filtrada

## Logs e Monitoramento

### Logs do Custom Script Extension

```bash
# Verificar status da extensão
az connectedmachine extension show \
  --name "CustomScriptExtension" \
  --machine-name "vm-name" \
  --resource-group "rg-name"

# Ver logs da extensão
az connectedmachine extension show \
  --name "CustomScriptExtension" \
  --machine-name "vm-name" \
  --resource-group "rg-name" \
  --query "instanceView"
```

### Logs da Instalação (na VM)

- **Localização**: `C:\Windows\Temp\wireshark-install.log`
- **Conteúdo**: Log detalhado com timestamps e status de cada etapa

## Segurança e Boas Práticas

### Segurança

- ✅ Verificação de assinatura digital dos binários
- ✅ Logs detalhados para auditoria
- ✅ Limpeza de arquivos temporários
- ✅ Validação de conectividade antes da execução

### Boas Práticas

- ✅ Filtrar VMs por status (apenas conectadas)
- ✅ Verificar se software já está instalado
- ✅ Tratamento de erros robusto
- ✅ Execução assíncrona (`--no-wait`)

## Troubleshooting

### Problemas Comuns

#### 1. Erro de Conectividade com Servidor Web

```text
ERRO: Não foi possível baixar o script
```

**Solução**: Verificar conectividade HTTP e URL do script

#### 2. Erro de Acesso ao File Server

```text
ERRO: Share não acessível
```

**Solução**: Verificar permissões SMB e conectividade de rede

#### 3. Falha na Instalação

```text
ERRO: Instalação falhou com código: 1
```

**Solução**: Verificar logs em `C:\Windows\Temp\wireshark-install.log`

### Comandos de Diagnóstico

```bash
# Verificar status das VMs Arc
az connectedmachine list -g "rg-arcservers" --query "[].{Name:name,Status:status}" -o table

# Verificar extensões instaladas em uma VM específica
az connectedmachine extension list --machine-name "fs03" -g "rg-arcservers" -o table

# Verificar detalhes da extensão CustomScriptExtension
az connectedmachine extension show \
  --name "CustomScriptExtension" \
  --machine-name "fs03" \
  --resource-group "rg-arcservers"

# Remover extensão com problema
az connectedmachine extension delete \
  --name "CustomScriptExtension" \
  --machine-name "fs03" \
  -g "rg-arcservers"
```

## Extensões do Cenário

### Outros Softwares

O mesmo padrão pode ser usado para instalar outros softwares:

- Antivírus corporativo
- Agentes de monitoramento
- Ferramentas administrativas
- Patches e atualizações

### Ambientes Diferentes

- **Desenvolvimento**: URLs e shares de teste
- **Produção**: URLs e shares corporativos
- **Staging**: Ambiente intermediário para validação

## Conclusão

Este cenário demonstra uma abordagem prática e escalável para distribuição e instalação automatizada de software em ambientes híbridos usando Azure Arc. A arquitetura distribuída oferece flexibilidade e permite o reuso de infraestrutura existente.

**Vantagens**:

- ✅ Escalabilidade para múltiplas VMs
- ✅ Reutilização de infraestrutura local
- ✅ Logs detalhados e rastreabilidade
- ✅ Flexibilidade de configuração

**Casos de Uso**:

- Instalação de software corporativo
- Atualizações de segurança
- Padronização de ambiente
- Automação de deployment

---

> **Nota**: Este é um exemplo educacional. Para ambientes de produção, considere implementar autenticação adicional, criptografia de dados em trânsito e validação de integridade mais rigorosa.