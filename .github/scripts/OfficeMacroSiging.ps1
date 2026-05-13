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

    foreach ($signToolFile in $signToolFiles) {
        if ($signToolFile.DirectoryName -match "^$($windowsSdkPath -replace "[\\]","\\")bin\\(?<Major>\d+)\.(?<Minor>\d+)\.(?<Build>\d+)\.(?<Revision>\d+)\\x86$") {
            if ($Matches.Major -gt $signTool.Major -or
                ($Matches.Major -eq $signTool.Major -and $Matches.Minor -gt $signTool.Minor) -or
                ($Matches.Major -eq $signTool.Major -and $Matches.Minor -eq $signTool.Minor-and $Matches.Build -gt $signTool.Build) -or
                ($Matches.Major -eq $signTool.Major -and $Matches.Minor -eq $signTool.Minor-and $Matches.Build -eq $signTool.Build -and $Matches.Revision -gt $signTool.Revision)) {
                $signTool.Path = $signToolFile.FullName
                $signTool.Major = $Matches.Major
                $signTool.Minor = $Matches.Minor
                $signTool.Build = $Matches.Build
                $signTool.Revision = $Matches.Revision
            }
        }
    }

    $signTool
} catch {
    Write-Host "Failed to find signtool.exe. $($_.Exception.Message)"
    exit 1
}
