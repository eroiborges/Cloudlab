Set-StrictMode -Version Latest

function Get-ManagedIdentityToken {

    $Resource   = "https://database.windows.net/"
    $ApiVersion = "2020-06-01"

    if ($env:IDENTITY_ENDPOINT) {

        # ✅ FIX: & ao invés de &amp;
        $endpoint = "$($env:IDENTITY_ENDPOINT)?resource=$Resource&api-version=$ApiVersion"

        try {
            Invoke-WebRequest -Method GET -Uri $endpoint -Headers @{ Metadata = 'true' } -UseBasicParsing | Out-Null
        }
        catch {
            $wwwAuthHeader = $_.Exception.Response.Headers["WWW-Authenticate"]
            if (-not $wwwAuthHeader) {
                throw "Não foi possível obter o header WWW-Authenticate."
            }

            $secretFile = ($wwwAuthHeader -split "Basic realm=")[1]
            if (-not $secretFile) {
                throw "Não foi possível extrair o caminho do secret file."
            }

            $secret = Get-Content -Raw $secretFile

            $resp = Invoke-WebRequest `
                -Method GET `
                -Uri $endpoint `
                -Headers @{
                    Metadata      = 'true'
                    Authorization = "Basic $secret"
                } `
                -UseBasicParsing

            $json = $resp.Content | ConvertFrom-Json
            return $json.access_token
        }

        throw "Falha ao obter token MSI via IDENTITY_ENDPOINT."
    }

    # ✅ FIX: & ao invés de &amp;
    $imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$ApiVersion&resource=$([uri]::EscapeDataString($Resource))"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $imdsUri -Headers @{ Metadata = 'true' } -TimeoutSec 10
        return $resp.access_token
    }
    catch {
        throw "Falha ao obter token MSI via IMDS: $($_.Exception.Message)"
    }
}

function Invoke-SqlQueryWithManagedIdentity {

    param(
        [Parameter(Mandatory)][string] $Server,
        [Parameter(Mandatory)][string] $Database,
        [Parameter(Mandatory)][string] $Query
    )

    $token = Get-ManagedIdentityToken

    # ✅ Pooling OFF para evitar reuse com AccessToken
    $connString = @"
Data Source=$Server;
Initial Catalog=$Database;
Encrypt=True;
TrustServerCertificate=True;
Pooling=False;
Connect Timeout=15;
Application Name=PS-Demo-Entra;
"@

    $conn = New-Object System.Data.SqlClient.SqlConnection
    $cmd  = $null
    $rdr  = $null

    $attempt = 0
    $RetryCount = 3

    while ($attempt -lt $RetryCount) {
        $attempt++

        try {

            Write-Host "`nTentativa ${attempt}/${RetryCount}..." -ForegroundColor Yellow

            $conn.ConnectionString = $connString
            $conn.AccessToken      = $token
            $conn.Open()

            $cmd = $conn.CreateCommand()
            $cmd.CommandTimeout = 30

            # ✅ DEBUG SESSION INFO (ótimo pra demo)
            $cmd.CommandText = @"
SELECT
    @@SPID                  AS SessionID,
    SUSER_SNAME()           AS LoginName,
    ORIGINAL_LOGIN()        AS OriginalLogin;
"@

            $rdr = $cmd.ExecuteReader()

            $session = New-Object System.Data.DataTable
            $session.Load($rdr)

            Write-Host "`n===== SESSION INFO =====" -ForegroundColor Cyan
            $session | Format-Table -AutoSize
            Write-Host "========================" -ForegroundColor Cyan

            $rdr.Close()
            $rdr.Dispose()
            $rdr = $null

            # ✅ MAIN QUERY
            $cmd.CommandText = $Query
            $rdr = $cmd.ExecuteReader()

            $dt = New-Object System.Data.DataTable
            $dt.Load($rdr)

            Write-Host "`n===== SQL RESULT =====" -ForegroundColor Green
            $dt | Format-Table -AutoSize
            Write-Host "======================" -ForegroundColor Green

            return
        }
        catch {
            Write-Warning "Falha tentativa ${attempt}: $($_.Exception.Message)"
            Start-Sleep -Seconds (2 * $attempt)
        }
        finally {
            if ($rdr) { try { $rdr.Close() } catch {} ; $rdr.Dispose() }
            if ($cmd) { $cmd.Dispose() }
            if ($conn) { try { $conn.Close() } catch {} }
        }
    }

    throw "Falhou após ${RetryCount} tentativas."
}

# ============================
# EXECUÇÃO (DEMO)
# ============================

Invoke-SqlQueryWithManagedIdentity `
  -Server "sqldb01.park.local" `
  -Database "WideWorldImporters" `
  -Query "SELECT TOP (2) * FROM sales.orders;"

# ✅ garante nova sessão na próxima execução
[System.Data.SqlClient.SqlConnection]::ClearAllPools() | Out-Null