param(
	[Parameter(Mandatory=$true)]
	[string]$Base64Cert,
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
	Start-Process -FilePath "$(env:SYSTEMROOT)\System32\certutil.exe" -ArgumentList "-decode","$($env:TEMP)\CodeSigning.pfx.txt","$($env:TEMP)\CodeSiging.pfx" -Wait -ErrorAction Stop
	
	if ((Test-Path ".\SignedDocuments") -eq $false) {
		New-Item -Path ".\" -Name "SignedDocuments" -ItemType "Directory" -ErrorAction Stop | Out-Null
	}
	
	$officeFiles = Get-ChildItem -Path ".\Office\*" -Include "*.docm","*.dotm","*.pptm","*.potm","*.ppsm","*.ppam","*.xlsm","*.xltm" -ErrorAction Stop
	foreach ($officeFile in $officeFiles) {
		$process = (Start-Process -FilePath "C:\OfficeSIP\OffSign.bat" -ArgumentList $signtool.Path,"sign /f $(env:TEMP)\CodeSigning.pfx /p $Password /fd SHA256 /tr http://timestamp.digicert.com /td SHA256","verify /pa",$officeFile.FullName)
		if ($process.ExitCode -ne 0) {
			Write-Host "Code signing failed on file $($officeFile.FullName). Error Code $($process.ExitCode)"
			continue
		}
		
		Move-Item -Path $officeFile.FullName -Destination ".\SignedDocuments"
	}
} catch {
    Write-Host "Failed to code sign office macros. $($_.Exception.Message)"
    exit 1
}
