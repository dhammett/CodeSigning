param(
	[switch]$Latest
)

$windowsSdkDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2361309"
$officeSipX86DownloadUrl = "https://download.microsoft.com/download/c53e473c-3060-4ee9-ac5c-0ddbbeced4e5/OfficeSips_x86_16-0-19416-43425.exe"
$visualCppRuntimeUrl = "https://download.microsoft.com/download/C/6/D/C6D0FD4E-9E53-4897-9B91-836EBA2AACD3/vcredist_x86.exe"
$dotNetDownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.300/dotnet-sdk-10.0.300-win-x86.exe"

$windowsSdkFilePath = "$($env:TEMP)\winsdksetup.exe"
$officeSipX86FilePath = "$($env:TEMP)\OfficeSips_x86_16-0-19416-43425.exe"
$visualCppRedistFilePath = "$($env:TEMP)\vcredist_x86.exe"
$dotnetFilePath = "$($env:TEMP)\dotnet-sdk-10.0.300-win-x86.exe"
$regsvr32FilePath = "$($env:SYSTEMROOT)\System32\regsvr32.exe"
$officeSipPath = "C:\OfficeSIP"

if ($Latest.IsPresent -and (Test-Path $windowsSdkFilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $windowsSdkDownloadUrl -Method Get -OutFile $windowsSdkFilePath -ErrorAction Stop
        Unblock-File -Path $windowsSdkFilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the Windows SDK!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ((Test-Path $visualCppRedistFilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $visualCppRuntimeUrl -Method Get -OutFile $visualCppRedistFilePath -ErrorAction Stop
        Unblock-File -Path $visualCppRedistFilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the Visual C++!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ((Test-Path $officeSipX86FilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $officeSipX86DownloadUrl -Method Get -OutFile $officeSipX86FilePath -ErrorAction Stop
        Unblock-File -Path $officeSipX86FilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the Office SIP!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ((Test-Path $dotnetFilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $dotNetDownloadUrl -Method Get -OutFile $dotnetFilePath -ErrorAction Stop
        Unblock-File -Path $dotnetFilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the .NET!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ($Latest.IsPresent) {
	$process = (Start-Process -FilePath $windowsSdkFilePath -ArgumentList "/features","OptionId.SigningTools","/q","/norestart" -PassThru -Wait)
	if ($process.ExitCode -ne 0) {
		Write-Host "$windowsSdkFilePath returned error code $($process.ExitCode)" -ForegroundColor Red
		exit $process.ExitCode
	}
}

$process = (Start-Process -FilePath $visualCppRedistFilePath -ArgumentList "/quiet","/norestart" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "$visualCppRedistFilePath returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
}

$process = (Start-Process -FilePath $officeSipX86FilePath -ArgumentList "/extract:$officeSipPath","/quiet","/norestart" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "$officeSipX86FilePath returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
}

$process = (Start-Process -FilePath $regsvr32FilePath -ArgumentList "/s","$officeSipPath\msosip.dll" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "Registering $officeSipPath\msosip.dll returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
}

$process = (Start-Process -FilePath $regsvr32FilePath -ArgumentList "/s","$officeSipPath\msosipx.dll" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "Registering $officeSipPath\msosipx.dll returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
}

$process = (Start-Process -FilePath $dotnetFilePath -ArgumentList "/install","/quiet","/norestart" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "Installing .NET returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
}

$process = (Start-Process -FilePath "C:\Program Files (x86)\dotnet\dotnet.exe" -ArgumentList "tool","install","--global","AzureSignTool","--version","7.0.0" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "Installing AzureSignTool returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
}

try {
    Copy-Item ".\.github\scripts\AzureOffSign.bat" $officeSipPath -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to move AzureSignTool and/or copy AzureOffSign.bat. $($_.Exception.Message)"
    exit 1
}

# OffSign.bat "C:\WindowsSDK\bin\10.0.28000.0\x86\" "sign /f C:\Users\Administrator\Documents\CodeSigning.pfx /p Password1 /fd SHA256 /tr http://timestamp.digicert.com /td SHA256" "verify /pa" "C:\Users\Administrator\Documents\Button Macro Test Signed.xlsm"
