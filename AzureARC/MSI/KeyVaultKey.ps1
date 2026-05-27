param(
    [Parameter(Mandatory)][string] $KeyVaultUrl,   # ex: https://myvault.vault.azure.net
    [Parameter(Mandatory)][string] $SecretName     # ex: mysecret
)

# ================================
# MSI TOKEN + KEY VAULT (ARC MSI)
# ================================

function Get-ManagedIdentityToken {

    $Resource   = "https://vault.azure.net"
    $ApiVersion = "2020-06-01"

    if ($env:IDENTITY_ENDPOINT) {

        $endpoint = "$($env:IDENTITY_ENDPOINT)?resource=$Resource&api-version=$ApiVersion"

        try {
            Invoke-WebRequest -Method GET -Uri $endpoint -Headers @{ Metadata = "true" } -UseBasicParsing | Out-Null
        }
        catch {
            $wwwAuthHeader = $_.Exception.Response.Headers["WWW-Authenticate"]
            if (-not $wwwAuthHeader) {
                throw "N?o foi poss?vel obter o header WWW-Authenticate. Ambiente MSI configurado?"
            }

            $secretFile = ($wwwAuthHeader -split "Basic realm=")[1]
            if (-not $secretFile) {
                throw "N?o foi poss?vel extrair o caminho do secret file."
            }

            $secret = Get-Content -Raw $secretFile

            $resp = Invoke-WebRequest `
                -Method GET `
                -Uri $endpoint `
                -Headers @{
                    Metadata      = "true"
                    Authorization = "Basic $secret"
                } `
                -UseBasicParsing

            $json = $resp.Content | ConvertFrom-Json
            return $json.access_token
        }

        throw "Falha ao obter token MSI via IDENTITY_ENDPOINT."
    }

    # Fallback: IMDS (VM comum ou Arc sem IDENTITY_ENDPOINT)
    $imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token" +
               "?api-version=2020-06-01&resource=$([uri]::EscapeDataString($Resource))"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $imdsUri -Headers @{ Metadata = "true" } -TimeoutSec 10
        return $resp.access_token
    }
    catch {
        throw "Falha ao obter token MSI via IMDS: $($_.Exception.Message)"
    }
}

# ================================
# Obter token MSI
# ================================

Write-Host "`nObtendo token MSI para Key Vault..." -ForegroundColor Cyan
$token = Get-ManagedIdentityToken
Write-Host "Token obtido com sucesso." -ForegroundColor Green

# ================================
# Consultar o secret no Key Vault
# ================================

$kvBaseUrl  = $KeyVaultUrl.TrimEnd("/")
$secretUri  = "$kvBaseUrl/secrets/$SecretName`?api-version=7.4"

Write-Host "`nConsultando secret $SecretName em $kvBaseUrl ..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod `
        -Method GET `
        -Uri $secretUri `
        -Headers @{
            Authorization  = "Bearer $token"
            "Content-Type" = "application/json"
        }

    Write-Host "`nSecret encontrado:`n" -ForegroundColor Green
    $createdAt = ([DateTimeOffset]::FromUnixTimeSeconds($response.attributes.created)).ToString("yyyy-MM-dd HH:mm:ss")
    $updatedAt = ([DateTimeOffset]::FromUnixTimeSeconds($response.attributes.updated)).ToString("yyyy-MM-dd HH:mm:ss")

    Write-Host "  Nome       : $($response.id -replace '.*/secrets/', '' -replace '/.*', '')"
    Write-Host "  ID         : $($response.id)"
    Write-Host "  Valor      : $($response.value)"
    Write-Host "  Habilitado : $($response.attributes.enabled)"
    Write-Host "  Criado em  : $createdAt"
    Write-Host "  Atualizado : $updatedAt"

    if ($response.attributes.exp) {
        $expiresAt = ([DateTimeOffset]::FromUnixTimeSeconds($response.attributes.exp)).ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "  Expira em  : $expiresAt"
    }

    Write-Host "`n  [Objeto completo]" -ForegroundColor DarkGray
    try { $response | ConvertTo-Json -Depth 5 } catch {}
}
catch {
    $statusCode = $null
    $body       = $null

    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body   = $reader.ReadToEnd()
        } catch {}
    }

    if ($statusCode) {
        Write-Host "`nErro ao consultar Key Vault (HTTP $statusCode)" -ForegroundColor Red
    } else {
        Write-Host "`nErro inesperado: $($_.Exception.Message)" -ForegroundColor Red
    }
    if ($body) { Write-Host $body -ForegroundColor Red }
    throw
}
