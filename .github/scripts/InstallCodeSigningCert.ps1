param(
	[Parameter(Mandatory=$true)]
    [string]$RootCert,
    [string]$IntermediateCert,
	[Parameter(Mandatory=$true)]
	[string]$TenantId,
	[Parameter(Mandatory=$true)]
	[string]$KeyVaultUrl,
	[Parameter(Mandatory=$true)]
	[string]$CertName
)

$rootCertPath = "$($env:TEMP)\Root.cer"
$intermediateCertPath = "$($env:TEMP)\Intermediate.cer"

try {
    $RootCert | Out-File $rootCertPath -Force -ErrorAction Stop
} catch {
	Write-Host "Downloading root cert from GitHub secret failed. $($_.Exception.Message)"
	exit 1
}

if ((Test-Path $rootCertPath) -eq $false) {
	Write-Host "Root certificate not found!"
	exit 1
}

try {
    Import-Certificate -FilePath $rootCertPath -CertStoreLocation "cert:\LocalMachine\Root" -ErrorAction Stop | Out-Null
} catch {
	Write-Host "Importing root cert into cert store failed. $($_.Exception.Message)"
	exit 1
}

try {
    if ($PSBoundParameters.ContainsKey("IntermediateCert")) {
        $IntermediateCert | Out-File $intermediateCertPath -Force -ErrorAction Stop
        if ((Test-Path $intermediateCertPath) -eq $false) {
            Write-Host "Intermediate certificate not found!"
            exit 1
        }

        Import-Certificate -FilePath $intermediateCertPath -CertStoreLocation "cert:\LocalMachine\CA" -ErrorAction Stop | Out-Null
    }
} catch {
	Write-Host "Importing intermediate cert into cert store failed. $($_.Exception.Message)"
	exit 1
}
