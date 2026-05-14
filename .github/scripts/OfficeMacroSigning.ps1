param(
	[Parameter(Mandatory=$true)]
	[string]$Base64Cert,
    [Parameter(Mandatory=$true)]
    [string]$RootCert,
    [string]$IntermidateCert,
	[Parameter(Mandatory=$true)]
	[string]$Password
)
try {
    $windowsSdkRegistry = Get-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows Kits\Installed Roots" -ErrorAction Stop
    $windowsSdkPath = $windowsSdkRegistry.KitsRoot10
    $signToolFiles = Get-ChildItem -Path $windowsSdkPath -Recurse -Filter "signtool.exe" -ErrorAction Stop
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
                ($Matches.Major -eq $signTool.Major -and $Matches.Minor -eq $signTool.Minor-and $Matches.Build -gt $signTool.Build) -or
                ($Matches.Major -eq $signTool.Major -and $Matches.Minor -eq $signTool.Minor-and $Matches.Build -eq $signTool.Build -and $Matches.Revision -gt $signTool.Revision)) {
                $signTool.Path = "$($signToolFile.DirectoryName)\"
                $signTool.Major = $Matches.Major
                $signTool.Minor = $Matches.Minor
                $signTool.Build = $Matches.Build
                $signTool.Revision = $Matches.Revision
            }
        }
    }
	
	$Base64Cert | Out-File "$($env:TEMP)\CodeSigning.pfx.txt" -Force -ErrorAction Stop
    $RootCert | Out-File "$($env:TEMP)\Root.cer" -Force -ErrorAction Stop
    if ((Test-Path "$($env:TEMP)\Root.cer") -eq $false) {
        Write-Host "Root certificate not found!"
        exit 1
    }

    Import-Certificate -FilePath "$($env:TEMP)\Root.cer" -CertStoreLocation "cert:\LocalMachine\Root" -ErrorAction Stop | Out-Null
    if ($null -ne $IntermidateCert -and $IntermidateCert -ne "") {
        $IntermidateCert | Out-File "$($env:TEMP)\Intermediate.cer" -Force -ErrorAction Stop
        if ((Test-Path "$($env:TEMP)\Intermediate.cer") -eq $false) {
            Write-Host "Intermediate certificate not found!"
            exit 1
        }

        Import-Certificate -FilePath "$($env:TEMP)\Intermediate.cer" -CertStoreLocation "cert:\LocalMachine\CA" -ErrorAction Stop | Out-Null
    }

	Start-Process -FilePath "$($env:SYSTEMROOT)\System32\certutil.exe" -ArgumentList "-decode","$($env:TEMP)\CodeSigning.pfx.txt","$($env:TEMP)\CodeSigning.pfx" -Wait -ErrorAction Stop
    if ((Test-Path "$($env:TEMP)\CodeSigning.pfx") -eq $false) {
        Write-Host "Code signing PFX file is not found!"
        exit 1
    }

	if ((Test-Path ".\Office\SignedDocuments") -eq $false) {
		New-Item -Path ".\Office" -Name "SignedDocuments" -ItemType "Directory" -ErrorAction Stop | Out-Null
	}
	
	$officeFiles = Get-ChildItem -Path ".\Office\*" -Include "*.docm","*.dotm","*.pptm","*.potm","*.ppsm","*.ppam","*.xlsm","*.xltm" -ErrorAction Stop
    $officeFileCount = 0

	foreach ($officeFile in $officeFiles) {
		& C:\OfficeSIP\OffSign.bat "$($signtool.Path)" "sign /f $($env:TEMP)\CodeSigning.pfx /p $Password /fd SHA256 /tr http://timestamp.digicert.com /td SHA256" "verify /pa" "$($officeFile.FullName)"
		if ($LASTEXITCODE -ne 0) {
			Write-Host "Code signing failed on file $($officeFile.FullName). Error Code $LASTEXITCODE"
			continue
		}
		
		Move-Item -Path $officeFile.FullName -Destination ".\Office\SignedDocuments" -ErrorAction Stop
        $officeFileCount++
	}
} catch {
    Write-Host "Failed to code sign office macros. $($_.Exception.Message)"
    exit 1
}

Remove-Item -Path "$($env:TEMP)\CodeSigning.pfx","$($env:TEMP)\CodeSigning.pfx.txt","$($env:TEMP)\Root.cer","$($env:TEMP)\Intermediate.cer" -ErrorAction SilentlyContinue

If ($officeFileCount -ne $officeFiles.Count) {
    Write-Host "Code signing succeeeded for $officeFileCount out of $($officeFiles.Count)"
    exit 1
}
