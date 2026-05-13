$windowsSdkDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2361309"
$officeSipX86DownloadUrl = "https://download.microsoft.com/download/c53e473c-3060-4ee9-ac5c-0ddbbeced4e5/OfficeSips_x86_16-0-19416-43425.exe"
$visualCppRuntimeUrl = "https://download.microsoft.com/download/C/6/D/C6D0FD4E-9E53-4897-9B91-836EBA2AACD3/vcredist_x86.exe"

$windowsSdkFilePath = "$($env:TEMP)\winsdksetup.exe"
$officeSipX86FilePath = "$($env:TEMP)\OfficeSips_x86_16-0-19416-43425.exe"
$visualCppRedistFilePath = "$($env:TEMP)\vcredist_x86.exe"
$regsvr32FilePath = "$($env:SYSTEMROOT)\System32\regsvr32.exe"
$officeSipPath = "C:\OfficeSIP"
$windowsSdkPath = "C:\WindowsSDK"

if ((Test-Path $windowsSdkFilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $windowsSdkDownloadUrl -Method Get -OutFile $windowsSdkFilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the Windows SDK!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ((Test-Path $visualCppRedistFilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $visualCppRuntimeUrl -Method Get -OutFile $visualCppRedistFilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the Visual C++!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ((Test-Path $officeSipX86FilePath) -eq $false) {
    try {
	    Invoke-WebRequest -Uri $officeSipX86DownloadUrl -Method Get -OutFile $officeSipX86FilePath -ErrorAction Stop
    } catch {
        Write-Host "Failed to download the Office SIP!. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$process = (Start-Process -FilePath $windowsSdkFilePath -ArgumentList "/installpath","$windowsSdkPath","/features","OptionId.SigningTools","/q","/norestart" -PassThru -Wait)
if ($process.ExitCode -ne 0) {
    Write-Host "$windowsSdkFilePath returned error code $($process.ExitCode)" -ForegroundColor Red
    exit $process.ExitCode
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

# New-SelfSignedCertificate -Type CodeSigningCert -KeyAlgorithm RSA -KeyLength 2048 -KeyExportPolicy Exportable -Subject "E=david.hammett@domain.net,CN=David Hammett" -CertStoreLocation "Cert:\CurrentUser\My"
# OffSign.bat "C:\WindowsSDK\bin\10.0.28000.0\x86\" "sign /f C:\Users\Administrator\Documents\CodeSigning.pfx /p Password1 /fd SHA256 /tr http://timestamp.digicert.com /td SHA256" "verify /pa" "C:\Users\Administrator\Documents\Button Macro Test Signed.xlsm"
