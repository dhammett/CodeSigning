param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    [Parameter(Mandatory=$true)]
    [string]$VaultName,
    [Parameter(Mandatory=$true)]
    [string]$CertName,
    [Parameter(Mandatory=$true)]
    [string]$Path
)

try {
    $files = Get-ChildItem -Path ".\$Path" -Include "*.rdp" -ErrorAction Stop
} catch {
    Write-Host "Finding list of RDP files produced an exception. $($_.Exception.Message)"
    exit 1
}

$fileCount = 0
try {
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://vault.azure.net" -ErrorAction Stop).Token | ConvertFrom-SecureString -AsPlainText
} catch {
    Write-Host "Azure access token was not retrieved. $($_.Exception.Message)"
    exit 1
}

foreach ($file in $files) {
    try {
        $fileHash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop
        $fileHashBytes = [Convert]::FromHexString($fileHash.Hash)
        $fileHashBase64 = [Convert]::ToBase64String($fileHashBytes)

        $url = "$VaultName.vault.azure.net/keys/$CertName/sign?api-version=7.4"
        $body = @{ alg = "RS256"; value = $fileHashBase64; } | ConvertTo-Json
        $response = Invoke-RestMethod -Method Post -Uri $url -Headers @{ Authorization = "Bearer $accessToken"; } -Body $body -ContentType "application/json" -ErrorAction Stop
        $signature = $response.value

        "signature:s:$signature" | Out-File $file.FullName -Append -ErrorAction Stop
        "signscope:s:" | Out-File $file.FullName -Append -ErrorAction Stop

        $fileCount++
    } catch {
        Write-Host "RDP file signing failed for '$($file.FullName)'. $($_.Exception.Message)"
        continue
    }
}
