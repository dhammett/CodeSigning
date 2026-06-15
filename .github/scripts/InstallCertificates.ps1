param(
	[switch]$ImportCert,
	[Parameter(Mandatory=$true)]
    [string]$RootCert,
    [string]$IntermediateCert,
	[Parameter(Mandatory=$true)]
	[string]$TenantId,
	[Parameter(Mandatory=$true)]
	[string]$KeyVaultName,
	[Parameter(Mandatory=$true)]
	[string]$CertName
)

$codeSigningCertPath = "$($env:TEMP)\CodeSigning.pfx"
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

if ($ImportCert.IsPresent) {
	try {
		$pemCert = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CertName -AsPlainText -ErrorAction Stop
		$pfxCert = [Convert]::FromBase64String($pemCert)
		$pfxCert | Out-File $codeSigningCertPath -ErrorAction Stop
		$cert = Import-PfxCertificate -FilePath $codeSigningCertPath -CertStoreLocation "Cert:\LocalMachine\My" -ErrorAction Stop
		"Thumbprint=$($cert.Thumbprint)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -ErrorAction Stop
		Remove-Item -Path $codeSigningCertPath -Force -Confirm:$false -ErrorAction SilentlyContinue
	} catch {
		Write-Host "Importing certificate failed. $($_.Exception.Message)"
		exit 1
	}
}
