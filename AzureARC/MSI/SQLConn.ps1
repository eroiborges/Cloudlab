# ================================
# MSI TOKEN + SQL QUERY (POWERSHELL NINJA)
# ================================

$apiVersion = "2020-06-01"
$resource   = "https://database.windows.net/"
$endpoint   = "$($env:IDENTITY_ENDPOINT)?resource=$resource&api-version=$apiVersion"

function Get-MsiToken {
    try {
        Invoke-WebRequest -Method GET -Uri $endpoint -Headers @{Metadata='true'} -UseBasicParsing | Out-Null
        throw "Expected 401 challenge, but request succeeded. Check environment/headers."
    }
    catch {
        $wwwAuthHeader = $_.Exception.Response.Headers["WWW-Authenticate"]
        if (-not $wwwAuthHeader) { throw "No WWW-Authenticate header found. Not running in MSI-enabled environment?" }

        $secretFile = ($wwwAuthHeader -split "Basic realm=")[1]
        if (-not $secretFile) { throw "Could not parse secret file path from WWW-Authenticate header." }

        $secret = Get-Content -Raw $secretFile

        $response = Invoke-WebRequest -Method GET -Uri $endpoint -Headers @{
            Metadata      = 'true'
            Authorization = "Basic $secret"
        } -UseBasicParsing

        return (ConvertFrom-Json $response.Content).access_token
    }
}

$token = Get-MsiToken

# Dica: para evitar reaproveitamento com AccessToken, desligue pooling.
$connString = @"
Data Source=sqldb01.park.local;
Initial Catalog=WideWorldImporters;
Encrypt=True;
TrustServerCertificate=True;
Pooling=False
"@

$conn = New-Object System.Data.SqlClient.SqlConnection
$cmd  = $null
$rdr  = $null

try {
    $conn.ConnectionString = $connString
    $conn.AccessToken      = $token
    $conn.Open()
    Write-Host "✅ Connected"

    $cmd = $conn.CreateCommand()

    # 1) Debug de sessão (SPID e usuário)
    $cmd.CommandText = "SELECT @@SPID AS SessionID, SYSTEM_USER AS Username;"
    $rdr = $cmd.ExecuteReader()

    while ($rdr.Read()) {
        Write-Host "SPID :" $rdr["SessionID"]
        Write-Host "User :" $rdr["Username"]
    }
    $rdr.Close()
    $rdr.Dispose()
    $rdr = $null

    # 2) Query principal
    $cmd.CommandText = "SELECT TOP (2) * FROM sales.orders;"
    $rdr = $cmd.ExecuteReader()

    $dt = New-Object System.Data.DataTable
    $dt.Load($rdr)
    $dt | Format-Table -AutoSize
}
finally {
    # Fecha e libera reader
    if ($rdr) { try { $rdr.Close() } catch {} ; $rdr.Dispose() }

    # Libera command
    if ($cmd) { $cmd.Dispose() }

    # Fecha e libera connection
    if ($conn) { try { $conn.Close() } catch {} ; $conn.Dispose() }

    # Garante que nada do pool fica "vivo" por acidente (mesmo com Pooling=False é ok chamar)
    [System.Data.SqlClient.SqlConnection]::ClearAllPools() | Out-Null

    Write-Host "`n✅ Connection disposed + pools cleared"
}