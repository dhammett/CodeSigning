param(
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[string]$CodeSigningCert,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
    [string]$RootCert,
	[Parameter(ParameterSetName="SignTool")]
	[Parameter(ParameterSetName="AzureSignTool")]
    [string]$IntermidateCert,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$Password,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$TenantId,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$ClientId,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$KeyVaultUrl,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$CertName,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$Path,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string[]]$FileExtension
)

$FileExtension | ForEach-Object { Write-Host "File Extension: $_" }

if ((Test-Path $Path) -eq $false) {
	Write-Host "Unable to find $Path in the repo!"
	exit 1
}

try {
    $windowsSdkRegistry = Get-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows Kits\Installed Roots" -ErrorAction Stop
    $windowsSdkPath = $windowsSdkRegistry.KitsRoot10
} catch {
	Write-Host "Getting registry location for Windows SDK failed. $($_.Exception.Message)"
	exit 1
}

try {
    $signToolFiles = Get-ChildItem -Path $windowsSdkPath -Recurse -Filter "signtool.exe" -ErrorAction Stop
} catch {
	Write-Host "Exception thrown while locating signtool.exe. $($_.Exception.Message)"
	exit 1
}

$signTool = @{
	Path = $null;
	Major = 0;
	Minor = 0;
	Build = 0;
	Revision = 0;
}

$patternMatch = $windowsSdkPath -replace "[\\]","\\"
$patternMatch = $patternMatch -replace "[\(]","\("
$patternMatch = $patternMatch -replace "[\)]","\)"

foreach ($signToolFile in $signToolFiles) {
	if ($signToolFile.DirectoryName -match "^$($patternMatch)bin\\(?<Major>\d+)\.(?<Minor>\d+)\.(?<Build>\d+)\.(?<Revision>\d+)\\x86$") {
		if ($Matches.Major -gt $signTool.Major -or
			($Matches.Major -eq $signTool.Major -and $Matches.Minor -gt $signTool.Minor) -or
			($Matches.Major -eq $signTool.Major -and $Matches.Minor -eq $signTool.Minor -and $Matches.Build -gt $signTool.Build) -or
			($Matches.Major -eq $signTool.Major -and $Matches.Minor -eq $signTool.Minor -and $Matches.Build -eq $signTool.Build -and $Matches.Revision -gt $signTool.Revision)) {
			$signTool.Path = "$($signToolFile.DirectoryName)\"
			$signTool.Major = $Matches.Major
			$signTool.Minor = $Matches.Minor
			$signTool.Build = $Matches.Build
			$signTool.Revision = $Matches.Revision
		}
	}
}

$codeSigningPemPath = "$($env:TEMP)\CodeSigning.pem"
$codeSigningPfxPath = "$($env:TEMP)\CodeSigning.pfx"
$rootCertPath = "$($env:TEMP)\Root.cer"
$intermidateCertPath = "$($env:TEMP)\Intermediate.cer"
$signedFilePath = "signed-files"

if ($PSBoundParameters.ContainsKey("CodeSigningCert")) {
	try {
		$CodeSigningCert | Out-File $codeSigningPemPath -Force -ErrorAction Stop
	} catch {
		Write-Host "Downloading CodeSigning cert from GitHub secret failed. $($_.Exception.Message)"
		exit 1
	}

	try {
		Start-Process -FilePath "$($env:SYSTEMROOT)\System32\certutil.exe" -ArgumentList "-decode",$codeSigningPemPath,$codeSigningPfxPath -Wait -ErrorAction Stop
		if ((Test-Path $codeSigningPfxPath) -eq $false) {
			Write-Host "Code signing PFX file is not found!"
			exit 1
		}
	} catch {
		Write-Host "Converting CodeSigning PEM to PFX failed. $($_.Exception.Message)"
		exit 1
	}
}

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
    if ($PSBoundParameters.ContainsKey("IntermidateCert")) {
        $IntermidateCert | Out-File $intermidateCertPath -Force -ErrorAction Stop
        if ((Test-Path $intermidateCertPath) -eq $false) {
            Write-Host "Intermediate certificate not found!"
            exit 1
        }

        Import-Certificate -FilePath $intermidateCertPath -CertStoreLocation "cert:\LocalMachine\CA" -ErrorAction Stop | Out-Null
    }
} catch {
	Write-Host "Importing intermediate cert into cert store failed. $($_.Exception.Message)"
	exit 1
}

try {
	if ((Test-Path ".\$signedFilePath\$Path") -eq $false) {
		New-Item -Path ".\$signedFilePath" -Name $Path -ItemType "Directory" -ErrorAction Stop | Out-Null
	}
} catch {
	Write-Host "Creating folder '.\$signedFilePath\$Path' for moving signed documents to failed. $($_.Exception.Message)"
	exit 1
}

$officeFileExtensions = @(".docm",".dotm",".pptm",".potm",".ppsm",".ppam",".xlsm",".xltm")

try {
	$files = Get-ChildItem -Path ".\$Path\*" -Include $FileExtension -ErrorAction Stop
} catch {
	Write-Host "Finding files in '$Path' threw an exception. $($_.Exception.Message)"
	exit 1
}

$fileCount = 0

foreach ($file in $files) {
	if ($officeFileExtensions -contains $file.Extension) {
		if ($PSBoundParameters.ContainsKey("CodeSigningCert")) {
			& C:\OfficeSIP\OffSign.bat "$($signtool.Path)" "sign /f $codeSigningPfxPath /p $Password /fd SHA256 /tr http://timestamp.digicert.com /td SHA256" "verify /pa" "$($file.FullName)"
		} elseif ($PSBoundParameters.ContainsKey("ClientId")) {
			& C:\OfficeSIP\AzureOffSign.bat "$($signtool.Path)" "sign -kvu $KeyVaultUrl -kvt $TenantId -kvi $ClientId -kvs $Password -kvc $CertName -fd SHA256 -tr http://timestamp.digicert.com -td SHA256" "verify /pa" "$($file.FullName)"
		}
		
		if ($LastExitCode -ne 0) {
			Write-Host "Code signing failed on file $($file.FullName). Error Code $LastExitCode"
			continue
		}
	} else {
		Write-Host "File extension $($file.Extension) is not currently supported, '$file.FullName'"
		continue
	}
	
	try {
		Move-Item -Path $file.FullName -Destination ".\$signedFilePath\$Path" -Force -ErrorAction Stop
	} catch {
		Write-Host "Moving file '$($file.FullName)' to '.\$signedFilePath\$Path' failed. $($_.Exception.Message)"
		continue
	}
	
	$fileCount++
}

Write-Host "File signing succeeeded for $fileCount out of $($files.Count)"
if ($fileCount -ne $files.Count) {
	exit 1
}

Remove-Item -Path $codeSigningPfxPath,$codeSigningPemPath,$rootCertPath,$intermidateCertPath -ErrorAction SilentlyContinue
