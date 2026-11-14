#Requires -Version 5.1
<#
.SYNOPSIS
  Build and install selected JetKVM modifications using WSL and Docker.
.EXAMPLE
  .\Install.ps1 -DeviceIP 192.168.1.207
.EXAMPLE
  .\Install.ps1 -DeviceIP 192.168.1.207 -Features BlackTheme,FillWindow
.EXAMPLE
  .\Install.ps1 -Features Audio,BlackTheme,FillWindow -PreviewOnly
#>
[CmdletBinding()]
param(
    [string]$DeviceIP,
    [ValidateSet('Audio', 'BlackTheme', 'FillWindow')]
    [string[]]$Features,
    [string]$UpstreamRef = 'release/0.5.10',
    [string]$SshKey = '',
    [switch]$PreviewOnly
)

$ErrorActionPreference = 'Stop'

function Confirm-Feature([string]$Prompt) {
    do {
        $response = Read-Host "$Prompt [Y/n]"
        if ([string]::IsNullOrWhiteSpace($response) -or $response -match '^(y|yes)$') {
            return $true
        }
        if ($response -match '^(n|no)$') {
            return $false
        }
        Write-Host 'Please answer Y or N.' -ForegroundColor Yellow
    } while ($true)
}

Write-Host ''
Write-Host 'JetKVM Custom Mod Installer' -ForegroundColor Cyan
Write-Host '--------------------------'

if (-not $PSBoundParameters.ContainsKey('Features')) {
    $chosen = @()
    if (Confirm-Feature 'Install HDMI/USB audio selector and volume controls?') {
        $chosen += 'Audio'
    }
    if (Confirm-Feature 'Install the neutral black theme?') {
        $chosen += 'BlackTheme'
    }
    if (Confirm-Feature 'Install Fill Window with hover-to-exit button?') {
        $chosen += 'FillWindow'
    }
} else {
    $chosen = @($Features)
}

if ($chosen.Count -eq 0) {
    throw 'No features selected. Nothing to install.'
}

if (-not $PreviewOnly) {
    if (-not $DeviceIP) {
        $DeviceIP = Read-Host 'JetKVM IPv4 address'
    }
    $parsedIP = $null
    if (-not [System.Net.IPAddress]::TryParse($DeviceIP, [ref]$parsedIP) -or
        $parsedIP.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Please enter a valid JetKVM IPv4 address.'
    }
}

if ($UpstreamRef -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$') {
    throw 'Invalid upstream Git reference.'
}

if (-not $PreviewOnly -and -not $SshKey) {
    Write-Host 'SSH authentication: an existing WSL SSH setup or root password will work.'
    $SshKey = Read-Host 'Optional SSH private key path in WSL (Enter to skip)'
}

Write-Host ''
Write-Host "Selected: $($chosen -join ', ')"
Write-Host "JetKVM source: $UpstreamRef"
if (-not $PreviewOnly) {
    Write-Host "Device: $DeviceIP"
    Write-Warning 'This replaces the installed JetKVM application and reboots the device.'
    Write-Warning 'The tested source is 0.5.10. Using it after a NEWER official app update may downgrade that app.'
    Write-Warning 'A full system update may also remove HDMI audio kernel support.'
    $confirmation = Read-Host 'Type INSTALL to continue'
    if ($confirmation -cne 'INSTALL') {
        Write-Host 'Cancelled; no device changes made.'
        return
    }
}

$wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCmd) {
    throw 'WSL is required. Install Ubuntu through Windows Subsystem for Linux first.'
}

$wslRootOutput = & wsl.exe --exec wslpath -u -a $PSScriptRoot
if ($LASTEXITCODE -ne 0 -or -not $wslRootOutput) {
    throw 'Could not locate this installer inside WSL. Start your Linux distribution and retry.'
}
$wslRoot = ($wslRootOutput | Select-Object -Last 1).Trim()
$wslScript = "$wslRoot/scripts/install.sh"

$wslKey = $SshKey
if ($SshKey -match '^[A-Za-z]:[\\/]') {
    $wslKeyOutput = & wsl.exe --exec wslpath -u -a $SshKey
    if ($LASTEXITCODE -ne 0 -or -not $wslKeyOutput) {
        throw 'Could not locate the SSH key inside WSL.'
    }
    $wslKey = ($wslKeyOutput | Select-Object -Last 1).Trim()
}

$arguments = @('--exec', 'bash', $wslScript, '--root', $wslRoot, '--ref', $UpstreamRef)
if ($chosen -contains 'Audio') { $arguments += '--audio' }
if ($chosen -contains 'BlackTheme') { $arguments += '--theme' }
if ($chosen -contains 'FillWindow') { $arguments += '--fill' }
if ($PreviewOnly) {
    $arguments += '--preview'
} else {
    $arguments += @('--device', $DeviceIP)
}
if ($wslKey) { $arguments += @('--ssh-key', $wslKey) }

Write-Host ''
Write-Host 'Preparing selected modifications...' -ForegroundColor Cyan
& wsl.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Installer failed with exit code $LASTEXITCODE. Check the build output and device status; any on-device backup remains available."
}
Write-Host 'Completed.' -ForegroundColor Green
