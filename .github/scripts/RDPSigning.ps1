param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultUrl,
    [Parameter(Mandatory=$true)]
    [string]$CertName,
    [Parameter(Mandatory=$true)]
    [string]$Path
)

try {
    $files = Get-ChildItem -Path ".\$Path\*.rdp" -ErrorAction Stop
} catch {
    Write-Host "Finding list of RDP files produced an exception. $($_.Exception.Message)"
    exit 1
}

try {
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://vault.azure.net" -ErrorAction Stop).Token
} catch {
    Write-Host "Azure access token was not retrieved. $($_.Exception.Message)"
    exit 1
}

if ($KeyVaultUrl -match "^https://(?<VaultName>[a-zA-Z0-9-]+)\.vault\.azure\.net") {
    $vaultName = $Matches.VaultName
} else {
    Write-Host "Key Vault URL does not match regex!"
    exit 1
}

$fileCount = 0

foreach ($file in $files) {
    Write-Host "Signing RDP file $($file.Name)"
    $fileCount++
}

Write-Host "Signed $fileCount of $($files.Count) RDP files"
if ($fileCount -ne $files.Count) {
    exit 1
}
