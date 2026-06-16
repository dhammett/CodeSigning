param(
	[Parameter(Mandatory=$true)]
	[string]$TenantId,
	[Parameter(Mandatory=$true)]
	[string]$KeyVaultUrl,
	[Parameter(Mandatory=$true)]
	[string]$CertName,
	[Parameter(Mandatory=$true)]
	[string]$Path,
	[Parameter(Mandatory=$true)]
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

$signToolDetails = @{
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
		if ($Matches.Major -gt $signToolDetails.Major -or
			($Matches.Major -eq $signToolDetails.Major -and $Matches.Minor -gt $signToolDetails.Minor) -or
			($Matches.Major -eq $signToolDetails.Major -and $Matches.Minor -eq $signToolDetails.Minor -and $Matches.Build -gt $signToolDetails.Build) -or
			($Matches.Major -eq $signToolDetails.Major -and $Matches.Minor -eq $signToolDetails.Minor -and $Matches.Build -eq $signToolDetails.Build -and $Matches.Revision -gt $signToolDetails.Revision)) {
			$signToolDetails.Path = "$($signToolFile.DirectoryName)\"
			$signToolDetails.Major = $Matches.Major
			$signToolDetails.Minor = $Matches.Minor
			$signToolDetails.Build = $Matches.Build
			$signToolDetails.Revision = $Matches.Revision
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
		& C:\OfficeSIP\AzureOffSign.bat "$($signToolDetails.Path)" "sign -kvu $KeyVaultUrl -kvt $TenantId -kvm -kvc $CertName -fd SHA256 -tr http://timestamp.digicert.com -td SHA256" "verify /pa" "$($file.FullName)"
		
		if ($LastExitCode -ne 0) {
			Write-Host "Code signing failed on file $($file.FullName). Error Code $LastExitCode"
			continue
		}
	} else {
		Write-Host "File extension $($file.Extension) is not currently supported, '$($file.FullName)'"
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
