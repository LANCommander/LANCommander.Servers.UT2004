#Requires -Modules Logging
#Requires -Modules Hooks

Invoke-Hook "PreInstallUT2004"

Write-Log -Message "Installing Unreal Tournament 2004 dedicated server..."

if (-not (Test-Path -Path "${Env:SERVER_DIR}/System/ucc-bin") -and -not (Test-Path -Path "${Env:SERVER_DIR}/System/ucc")) {
    Write-Log "Could not find ucc-bin or ucc in ${Env:SERVER_DIR}/System, proceeding with installation."

    $downloadUrl = $Env:UT2004_DOWNLOAD_URL

    Write-Log "Downloading UT2004 dedicated server from $downloadUrl"

    curl --output /tmp/ut2004-server.tar.gz "$downloadUrl"

    Write-Log "Extracting UT2004 dedicated server..."

    tar -xzf /tmp/ut2004-server.tar.gz -C /tmp

    Move-Item -Force -Path "/tmp/ut-server/*" -Destination $Env:SERVER_DIR

    if (Test-Path -Path "${Env:SERVER_DIR}/System/ucc-bin") {
        chmod +x "${Env:SERVER_DIR}/System/ucc-bin"
    }

    if (Test-Path -Path "${Env:SERVER_DIR}/System/ucc") {
        chmod +x "${Env:SERVER_DIR}/System/ucc"
    }
} else {
    Write-Log "UT2004 dedicated server already installed in ${Env:SERVER_DIR}, skipping installation."
}

Write-Log -Message "Patching master server configuration..."

$iniFile = "${Env:SERVER_DIR}/System/UT2004.ini"

if (-not (Test-Path -Path $iniFile)) {
    $iniFile = "${Env:SERVER_DIR}/System/Default.ini"
}

if (Test-Path -Path $iniFile) {
    $inSection = $false
    $result = [System.Collections.Generic.List[string]]::new()

    foreach ($line in (Get-Content $iniFile)) {
        if ($line -match '^\[IpDrv\.MasterServerLink\]') {
            $inSection = $true
            $result.Add($line)
            $result.Add('MasterServerList=(Address="utmaster.openspy.net",Port=28902)')
        } elseif ($inSection -and $line -match '^\[') {
            $inSection = $false
            $result.Add($line)
        } elseif ($inSection -and $line -match '^MasterServerList') {
            # Skip existing MasterServerList entries to avoid duplicates
        } else {
            $result.Add($line)
        }
    }

    $result | Set-Content $iniFile

    Write-Log "Master server configuration patched successfully."
} else {
    Write-Log "Warning: Could not find UT2004.ini or Default.ini, skipping master server patch."
}

Write-Log -Message "Unreal Tournament 2004 installation complete."

Invoke-Hook "PostInstallUT2004"

Set-Location $Env:SERVER_ROOT
