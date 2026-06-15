[CmdletBinding(DefaultParameterSetName= 'AzureSignTool')]
param(
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[switch]$SignTool,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[switch]$AzureSignTool,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$TenantId,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$KeyVaultUrl,
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$CertName,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[string]$Thumbprint,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string]$Path,
	[Parameter(Mandatory=$true, ParameterSetName="SignTool")]
	[Parameter(Mandatory=$true, ParameterSetName="AzureSignTool")]
	[string[]]$FileExtension
)

$FileExtension = $FileExtension | ForEach-Object {
    if ($_.StartsWith("*.")) {
        $_
    } elseif ($_.StartsWith(".")) {
        "*$_"
    } else {
        "*.$_"
    }
}

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

$signedFilePath = "signed-files"

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
		if ($SignTool.IsPresent) {
			& C:\OfficeSIP\OffSign.bat "$($signtool.Path)" "sign /sha1 $Thumbprint /sm /fd SHA256 /tr http://timestamp.digicert.com /td SHA256" "verify /pa" "$($file.FullName)"
		} elseif ($AzureSignTool.IsPresent) {
			& C:\OfficeSIP\AzureOffSign.bat "$($signtool.Path)" "sign -kvu $KeyVaultUrl -kvt $TenantId -kvm -kvc $CertName -fd SHA256 -tr http://timestamp.digicert.com -td SHA256" "verify /pa" "$($file.FullName)"
		}
		
		if ($LastExitCode -ne 0) {
			Write-Host "Code signing failed on file $($file.FullName). Error Code $LastExitCode"
			continue
		}
	} elseif ($file.Extension -eq ".rdp") {
		if ($PSBoundParameters.ContainsKey("CodeSigningCert")) {
			& "$($env:SYSTEMROOT)\System32\rdpsign.exe" /sha256 $cert.Thumbprint /v "$($file.FullName)"
			if ($LastExitCode -ne 0) {
				Write-Host "Signing RDP file '$($file.FullName)' failed with error code $LastExitCode"
				continue
			}
		} else {
			Write-Host "Need to specify the CodeSigningCert script parameter to sign RDP file. The ClientId option does not work"
			continue
		}
	}else {
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

Remove-Item -Path $codeSigningPfxPath,$codeSigningPemPath,$rootCertPath,$intermediateCertPath -ErrorAction SilentlyContinue
