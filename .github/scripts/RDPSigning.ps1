param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    [Parameter(Mandatory=$true)]
    [string]$VaultName,
    [Parameter(Mandatory=$true)]
    [string]$CertName,
    [Parameter(Mandatory=$true)]
    [string]$Path
)

try {
    $files = Get-ChildItem -Path ".\$Path\*.rdp" -ErrorAction Stop
} catch {
    Write-Host "Finding list of RDP files produced an exception. $($_.Exception.Message)"
    exit 1
}

$fileCount = 0
try {
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://vault.azure.net" -ErrorAction Stop).Token | ConvertFrom-SecureString -AsPlainText
} catch {
    Write-Host "Azure access token was not retrieved. $($_.Exception.Message)"
    exit 1
}

$fullAddress = $null
$alternateFullAddress = $null
$signScope = @()
$secureSettings = @{
    "full address:s:" = "Full Address";
    "alternate full address:s:" = "Alternate Full Address";
	"pcb:s:" = "PCB";
	"use redirection server name:i:" = "Use Redirection Server Name";
	"server port:i:" = "Server Port";
	"negotiate security layer:i:" = "Negotiate Security Layer";
	"enablecredsspsupport:i:" = "EnableCredSspSupport";
	"disableconnectionsharing:i:" = "DisableConnectionSharing";
	"autoreconnection enabled:i:" = "AutoReconnection Enabled";
	"gatewayhostname:s:" = "GatewayHostname";
	"gatewayusagemethod:i:" = "GatewayUsageMethod";
	"gatewayprofileusagemethod:i:" = "GatewayProfileUsageMethod";
	"gatewaycredentialssource:i:" = "GatewayCredentialsSource";
	"support url:s:" = "Support URL";
	"promptcredentialonce:i:" = "PromptCredentialOnce";
	"require pre-authentication:i:" = "Require pre-authentication";
	"pre-authentication server address:s:" = "Pre-authentication server address";
	"alternate shell:s:" = "Alternate Shell";
	"shell working directory:s:" = "Shell Working Directory";
	"remoteapplicationprogram:s:" = "RemoteApplicationProgram";
	"remoteapplicationexpandworkingdir:s:" = "RemoteApplicationExpandWorkingdir";
	"remoteapplicationmode:i:" = "RemoteApplicationMode";
	"remoteapplicationguid:s:" = "RemoteApplicationGuid";
	"remoteapplicationname:s:" = "RemoteApplicationName";
	"remoteapplicationicon:s:" = "RemoteApplicationIcon";
	"remoteapplicationfile:s:" = "RemoteApplicationFile";
	"remoteapplicationfileextensions:s:" = "RemoteApplicationFileExtensions";
	"remoteapplicationcmdline:s:" = "RemoteApplicationCmdLine";
	"remoteapplicationexpandcmdline:s:" = "RemoteApplicationExpandCmdLine";
	"prompt for credentials:i:" = "Prompt For Credentials";
	"authentication level:i:" = "Authentication Level";
	"audiomode:i:" = "AudioMode";
	"redirectdrives:i:" = "RedirectDrives";
	"redirectprinters:i:" = "RedirectPrinters";
	"redirectcomports:i:" = "RedirectCOMPorts";
	"redirectsmartcards:i:" = "RedirectSmartCards";
	"redirectposdevices:i:" = "RedirectPOSDevices";
	"redirectclipboard:i:" = "RedirectClipboard";
	"devicestoredirect:s:" = "DevicesToRedirect";
	"drivestoredirect:s:" = "DrivesToRedirect";
	"loadbalanceinfo:s:" = "LoadBalanceInfo";
	"redirectdirectx:i:" = "RedirectDirectX";
	"rdgiskdcproxy:i:" = "RDGIsKDCProxy";
	"kdcproxyname:s:" = "KDCProxyName";
	"eventloguploadaddress:s:" = "EventLogUploadAddress";
}

foreach ($file in $files) {
    try {
        $fileContents = Get-Content $file.FullName
        foreach ($line in $fileContents) {
            if ($line -match "^(?<Name>[a-zA-Z ]+:[a-zA-Z]:)(?<Value>.*)$") {
                if ($Matches.Name -eq "full address:s:") {
                    $fullAddress = $Matches.Value
                } elseif ($Matches.Name -eq "alternate full address:s:") {
                    $alternateFullAddress = $Matches.Value
                }
                
                if ($secureSettings.ContainsKey($Matches.Name)) {
                    $signScope += $secureSettings[$Matches.Name]
                }
            }
        }
        
        $lineNumber = 0

        foreach ($line in $fileContents) {
            try {
                if ($line.StartsWith("signscope:s:")) {
                    continue
                }
                
                if ($lineNumber -eq 0) {
                    "$line`r`n" | Out-File "$($env:TEMP)\$($file.Name)" -Encoding unicode -ErrorAction Stop
                } else {
                    "$line`r`n" | Out-File "$($env:TEMP)\$($file.Name)" -Encoding unicode -Append -ErrorAction Stop
                }

                if ($line.StartsWith("full address:s:") -and $null -eq $alternateFullAddress) {
                    "alternate full address:s:$fullAddress`r`n" | Out-File "$($env:TEMP)\$($file.Name)" -Encoding unicode -Append -ErrorAction Stop
                    $signScope += $secureSettings["alternate full address:s:"]
                }

                $lineNumber++
            } catch {
                Write-Host "Failed to write line to temporary RDP file. $($_.Exception.Message)"
                exit 1
            }

        }

        try {
            "signscope:s:$($signScope -join ",")`r`n" | Out-File "$($env:TEMP)\$($file.Name)" -Encoding unicode -Append -ErrorAction Stop
        } catch {
            Write-Host "Failed to write signscope line to temporary RDP file. $($_.Exception.Message)"
            exit 1
        }

        $fileHash = Get-FileHash -Path "$($env:TEMP)\$($file.Name)" -Algorithm SHA256 -ErrorAction Stop
        $fileHashBytes = [Convert]::FromHexString($fileHash.Hash)
        $fileHashBase64 = [Convert]::ToBase64String($fileHashBytes)

        $url = "https://$VaultName.vault.azure.net/certificates/$CertName/?api-version=2025-07-01"
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers @{ Authorization = "Bearer $accessToken"; } -ErrorAction Stop
        $padded = $response.cer -replace "[-]","+" -replace "[_]","/"
        switch ($padded.Length % 4) {
            2 { $padded += "=="}
            3 { $padded += "="}
        }

        $cert = [Convert]::FromBase64String($padded)

        $url = "https://$VaultName.vault.azure.net/keys/$CertName/sign?api-version=7.4"
        $body = @{ alg = "RS256"; value = $fileHashBase64; } | ConvertTo-Json
        $response = Invoke-RestMethod -Method Post -Uri $url -Headers @{ Authorization = "Bearer $accessToken"; } -Body $body -ContentType "application/json" -ErrorAction Stop
        $padded = $response.value -replace "[-]","+" -replace "[_]","/"
        switch ($padded.Length % 4) {
            2 { $padded += "=="}
            3 { $padded += "="}
        }

        $signedFileHash = [Convert]::FromBase64String($padded)
        $signature = @(1,0,1,0,1,0,0,0)
        $signature += [BitConverter]::GetBytes($signedFileHash.Count + $cert.Count)
        $signature += $cert
        $signature += $signedFileHash
        $signature = [Convert]::ToBase64String($signature)
        $chunks = ($signature -split "(.{1,64})") | Where-Object { $_ -ne "" }

        "signature:s:$($chunks -join "  ")`r`n" | Out-File "$($env:TEMP)\$($file.Name)" -Encoding unicode -Append -ErrorAction Stop

        $fileCount++
    } catch {
        Write-Host "RDP file signing failed for '$($file.FullName)'. $($_.Exception.Message)"
        continue
    }
}
