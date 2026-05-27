# =============================
# CONFIGURACAO
# =============================
$rg        = "rg-linux-entra-demo"
$sshConf   = "$HOME\.ssh\azure-vms.conf"
$keysDir   = "$HOME\.aadkeys"

# =============================
# LISTAR VMs LINUX
# =============================
Write-Host ""
Write-Host "Buscando VMs Linux em: $rg"

$vms = az vm list `
    --resource-group $rg `
    --query "[?storageProfile.osDisk.osType=='Linux'].name" `
    --output tsv 2>$null | Sort-Object

if (-not $vms) {
    Write-Host "Nenhuma VM Linux encontrada em '$rg'."
    exit 1
}

# =============================
# SELECAO
# =============================
Write-Host ""
Write-Host "VMs disponíveis:"
$vmList = @($vms)
for ($i = 0; $i -lt $vmList.Count; $i++) {
    Write-Host ("  {0,2}) {1}" -f ($i + 1), $vmList[$i])
}
Write-Host ""

$vmName = $null
while (-not $vmName) {
    $choice = Read-Host "Escolha o número da VM"
    if ($choice -match '^\d+$') {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $vmList.Count) {
            $vmName = $vmList[$index]
        }
    }
    if (-not $vmName) {
        Write-Host "  Opção inválida. Digite um número entre 1 e $($vmList.Count)."
    }
}

Write-Host ""
Write-Host ">> VM selecionada: $vmName"

# =============================
# LIMPEZA - azure-vms.conf
# =============================
$sshDir = Split-Path $sshConf
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
}

if (Test-Path $sshConf) {
    Write-Host "Limpando entradas antigas de '$vmName' em $sshConf..."

    $lines   = Get-Content $sshConf
    $skip    = $false
    $cleaned = foreach ($line in $lines) {
        if ($line -match '^Host ') {
            $skip = $line -match [regex]::Escape($vmName)
        }
        if (-not $skip) { $line }
    }
    $cleaned | Set-Content $sshConf
}

# =============================
# LIMPEZA - chaves antigas
# =============================
if (-not (Test-Path $keysDir)) {
    New-Item -ItemType Directory -Path $keysDir | Out-Null
}

@("id_rsa", "id_rsa.pub") | ForEach-Object {
    $keyFile = Join-Path $keysDir $_
    if (Test-Path $keyFile) {
        Write-Host "Removendo chave antiga: $keyFile"
        Remove-Item $keyFile -Force
    }
}

# =============================
# GERAR SSH CONFIG
# =============================
Write-Host ""
Write-Host "Gerando configuração SSH para '$vmName'..."

az ssh config `
    --resource-group $rg `
    --name $vmName `
    --file $sshConf `
    --keys-dest-folder $keysDir

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Configuração gerada com sucesso!"
    Write-Host ""
    Write-Host "Para conectar:"
    Write-Host "  ssh $rg-$vmName"
    Write-Host "  az ssh vm --resource-group $rg --name $vmName"
    Write-Host ""
    Write-Host "Arquivo de config atualizado: $sshConf"
} else {
    Write-Host ""
    Write-Host "Erro ao gerar configuração SSH."
    exit 1
}
