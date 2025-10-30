# Script PowerShell para instalação do Wireshark via share de rede
# Para uso com Azure Custom Script Extension
# Versão: 1.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "4.4.9",
    
    [Parameter(Mandatory = $false)]
    [string]$SharePath = "\\dc01\Share1\ARC"
)

# Configurar log
$LogFile = "C:\Windows\Temp\wireshark-install.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Output $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage -Force
}

try {
    Write-Log "=== INSTALAÇÃO WIRESHARK $Version ==="
    Write-Log "Servidor: $env:COMPUTERNAME"
    Write-Log "Usuário: $env:USERNAME"
    
    # Construir caminhos
    $SourceFile = Join-Path $SharePath "Wireshark-$Version-x64.exe"
    $TempDir = $env:TEMP
    $DestFile = Join-Path $TempDir "Wireshark-$Version-x64.exe"
    
    Write-Log "Share: $SharePath"
    Write-Log "Arquivo origem: $SourceFile"
    Write-Log "Arquivo destino: $DestFile"
    
    # Verificar se já está instalado
    $Installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
                 Where-Object { $_.DisplayName -like "*Wireshark*" }
    
    if ($Installed) {
        Write-Log "✅ Wireshark já instalado: $($Installed.DisplayVersion)"
        Write-Log "Localização: $($Installed.InstallLocation)"
        exit 0
    }
    
    # Verificar conectividade com share
    Write-Log "Testando acesso à share..."
    if (-not (Test-Path $SharePath)) {
        Write-Log "❌ ERRO: Share não acessível: $SharePath"
        exit 1
    }
    Write-Log "✅ Share acessível"
    
    # Verificar se arquivo existe na share
    Write-Log "Verificando arquivo na share..."
    if (-not (Test-Path $SourceFile)) {
        Write-Log "❌ ERRO: Arquivo não encontrado: $SourceFile"
        
        # Listar arquivos disponíveis
        $AvailableFiles = Get-ChildItem -Path $SharePath -Filter "Wireshark-*.exe" -ErrorAction SilentlyContinue
        if ($AvailableFiles) {
            Write-Log "Arquivos Wireshark disponíveis na share:"
            foreach ($file in $AvailableFiles) {
                $fileSize = [math]::Round($file.Length / 1MB, 2)
                Write-Log "  - $($file.Name) ($fileSize MB)"
            }
        } else {
            Write-Log "Nenhum arquivo Wireshark encontrado na share"
        }
        exit 1
    }
    
    $FileSize = [math]::Round((Get-Item $SourceFile).Length / 1MB, 2)
    Write-Log "✅ Arquivo encontrado: $FileSize MB"
    
    # Copiar arquivo da share
    Write-Log "Copiando arquivo da share..."
    try {
        Copy-Item -Path $SourceFile -Destination $DestFile -Force
        Write-Log "✅ Arquivo copiado com sucesso"
    }
    catch {
        Write-Log "❌ ERRO na cópia: $($_.Exception.Message)"
        exit 1
    }
    
    # Verificar se arquivo foi copiado
    if (-not (Test-Path $DestFile)) {
        Write-Log "❌ ERRO: Arquivo não foi copiado corretamente"
        exit 1
    }
    
    $CopiedSize = [math]::Round((Get-Item $DestFile).Length / 1MB, 2)
    Write-Log "✅ Arquivo copiado: $CopiedSize MB"
    
    # Verificar assinatura digital (opcional)
    try {
        $Signature = Get-AuthenticodeSignature -FilePath $DestFile
        if ($Signature.Status -eq "Valid") {
            Write-Log "✅ Assinatura digital válida"
        } else {
            Write-Log "⚠️ Assinatura digital não válida ou ausente"
        }
    }
    catch {
        Write-Log "⚠️ Não foi possível verificar assinatura digital"
    }
    
    # Executar instalação silenciosa
    Write-Log "Iniciando instalação silenciosa..."
    Write-Log "Comando: $DestFile /NCRC /S /desktopicon=yes"
    
    $Process = Start-Process -FilePath $DestFile -ArgumentList "/NCRC", "/S", "/desktopicon=yes" -Wait -PassThru -NoNewWindow
    
    Write-Log "Processo finalizado com código: $($Process.ExitCode)"
    
    if ($Process.ExitCode -eq 0) {
        Write-Log "✅ Instalação concluída com sucesso!"
        Write-Log "✅ Wireshark $Version instalado e pronto para uso"
    } else {
        Write-Log "❌ Instalação falhou com código: $($Process.ExitCode)"
        exit 1
    }
    
    # Limpeza
    if (Test-Path $DestFile) {
        Remove-Item $DestFile -Force -ErrorAction SilentlyContinue
        Write-Log "✅ Arquivo temporário removido"
    }
    
    Write-Log "=== INSTALAÇÃO CONCLUÍDA COM SUCESSO ==="
    Write-Log "Log salvo em: $LogFile"
    exit 0
    
} catch {
    Write-Log "❌ ERRO GERAL: $($_.Exception.Message)"
    exit 1
} 