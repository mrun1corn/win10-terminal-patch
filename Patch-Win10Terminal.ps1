<#
.SYNOPSIS
    Windows 10 Modern Terminal & Win+X Context Menu Patch
    https://github.com/mrun1corn/win10-terminal-patch

.DESCRIPTION
    Automates switching Windows 10 Start Menu Context (Win+X) shortcuts to Windows Terminal (PowerShell 7)
    with admin elevation support and ensures Nerd Font / UTF-8 rendering across Windows consoles.
#>

[CmdletBinding()]
param (
    [switch]$Revert
)

$ErrorActionPreference = "Stop"

# Assert Administrator privileges (required for HKLM font whitelisting and WinX Group updates)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Administrator privileges required. Please re-run from an elevated PowerShell prompt."
    return
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Windows 10 Modern Terminal & Win+X Patch Utility        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$WinXGroup3 = "$env:LOCALAPPDATA\Microsoft\Windows\WinX\Group3"
$BackupDir  = "$env:LOCALAPPDATA\Microsoft\Windows\WinX\Group3_OriginalBackup"
$HasherExe = if ($PSScriptRoot) { Join-Path $PSScriptRoot "hashlnk.exe" } else { "$env:TEMP\hashlnk.exe" }
if (-not (Test-Path $HasherExe)) {
    $altPath = Join-Path $PSScriptRoot "bin\hashlnk.exe"
    if ($PSScriptRoot -and (Test-Path $altPath)) {
        $HasherExe = $altPath
    }
}

# If invoked via `irm ... | iex` where hashlnk.exe is not adjacent, auto-download from GitHub releases
if (-not (Test-Path $HasherExe)) {
    $HasherExe = "$env:TEMP\hashlnk.exe"
    if (-not (Test-Path $HasherExe)) {
        Write-Host "Downloading hashlnk utility from GitHub release..." -ForegroundColor Yellow
        $releaseUrl = "https://github.com/mrun1corn/win10-terminal-patch/releases/download/v1.0.0/hashlnk.exe"
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-WebRequest -Uri $releaseUrl -OutFile $HasherExe -UseBasicParsing
    }
}

# Verify SHA256 integrity of the hasher binary before executing
$expectedHash = "7D30B1EC2D488C323DECC8F9C92CB71454E893B572F80226EB6475FF1F0A28A3"
$actualHash = (Get-FileHash -Path $HasherExe -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    Write-Error "Security verification failed: hashlnk.exe checksum mismatch ($actualHash vs $expectedHash). Aborting."
    return
}
$WTPath     = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"

if (-not (Test-Path $WinXGroup3)) {
    Write-Error "Could not find WinX Group3 directory at: $WinXGroup3"
    return
}

# -------------------------------------------------------------
# MODE: REVERT
# -------------------------------------------------------------
if ($Revert) {
    Write-Host "`n[Reverting] Restoring original Windows 10 shortcuts..." -ForegroundColor Yellow
    if (Test-Path $BackupDir) {
        Get-ChildItem -Path $BackupDir -Filter "*.lnk" | ForEach-Object {
            Copy-Item $_.FullName -Destination $WinXGroup3 -Force
            Write-Host "  -> Restored $($_.Name)" -ForegroundColor DarkGray
        }
        Remove-Item $BackupDir -Recurse -Force
        Write-Host "Original WinX shortcuts restored successfully." -ForegroundColor Green
    } else {
        Write-Warning "No backup folder found at $BackupDir. Nothing to restore."
    }

    Write-Host "Restarting Windows Explorer..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force
    Write-Host "Done." -ForegroundColor Green
    return
}

# -------------------------------------------------------------
# MODE: APPLY PATCH
# -------------------------------------------------------------

# 1. Ensure Windows Terminal is installed
if (-not (Test-Path $WTPath)) {
    Write-Host "[1/5] Installing Windows Terminal via WinGet..." -ForegroundColor Yellow
    winget install --id Microsoft.WindowsTerminal -e --source winget --accept-source-agreements --accept-package-agreements --silent
} else {
    Write-Host "[1/5] Windows Terminal is installed." -ForegroundColor Green
}

# 2. Ensure JetBrainsMono Nerd Font is installed
$fontInstalled = (Get-ChildItem "C:\Windows\Fonts" -Filter "*JetBrains*NFM*" -ErrorAction SilentlyContinue).Count -gt 0
if (-not $fontInstalled) {
    Write-Host "[2/5] Installing JetBrainsMono Nerd Font..." -ForegroundColor Yellow
    winget install --id DEVCOM.JetBrainsMonoNerdFont -e --source winget --accept-source-agreements --accept-package-agreements --silent
} else {
    Write-Host "[2/5] JetBrainsMono Nerd Font is already installed." -ForegroundColor Green
}

# 3. Verify Hasher binary exists
if (-not (Test-Path $HasherExe)) {
    Write-Error "hashlnk.exe is missing. Expected at $HasherExe"
    return
}

# 4. Create backup of original Group3 shortcuts
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Get-ChildItem -Path $WinXGroup3 -Filter "*.lnk" | ForEach-Object {
        Copy-Item $_.FullName -Destination $BackupDir -Force
    }
    Write-Host "[3/5] Backed up original WinX shortcuts to: $BackupDir" -ForegroundColor Green
} else {
    Write-Host "[3/5] Existing backup found at $BackupDir." -ForegroundColor DarkGray
}

# 5. Create and patch the WinX shortcuts
Write-Host "[4/5] Patching WinX shortcuts to launch Windows Terminal..." -ForegroundColor Cyan

$sh = New-Object -ComObject WScript.Shell

# User shortcut (01a)
$lnkUser = Join-Path $WinXGroup3 "01a - Windows PowerShell.lnk"
$sc1 = $sh.CreateShortcut($lnkUser)
$sc1.TargetPath = $WTPath
$sc1.Arguments = ""
$sc1.Description = "Windows Terminal"
$sc1.Save()

# Admin elevated shortcut (02a)
$lnkAdmin = Join-Path $WinXGroup3 "02a - Windows PowerShell.lnk"
$sc2 = $sh.CreateShortcut($lnkAdmin)
$sc2.TargetPath = $WTPath
$sc2.Arguments = ""
$sc2.Description = "Windows Terminal (Admin)"
$sc2.Save()

# Enable RunAsAdministrator bit on Admin shortcut (offset 21 -> 0x22 / bit 0x20)
$bytes = [System.IO.File]::ReadAllBytes($lnkAdmin)
$bytes[21] = $bytes[21] -bor 0x20
[System.IO.File]::WriteAllBytes($lnkAdmin, $bytes)

# Cryptographically sign both shortcuts with PKEY_WINX_HASH
& $HasherExe "$lnkUser"
& $HasherExe "$lnkAdmin"

# 6. Configure Windows Console Subsystem Registry
Write-Host "[5/5] Configuring console registry for TrueType Nerd Fonts & UTF-8..." -ForegroundColor Cyan

# Set DontUsePowerShellOnWinX to 0 so Explorer prioritizes the PowerShell/Terminal entries
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DontUsePowerShellOnWinX" -Value 0 -ErrorAction SilentlyContinue

# Whitelist in HKLM
try {
    $ttfKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Console\TrueTypeFont"
    Set-ItemProperty -Path $ttfKey -Name "0000" -Value "JetBrainsMono NFM" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $ttfKey -Name "00000" -Value "JetBrainsMono NF" -ErrorAction SilentlyContinue
} catch { }

# Set defaults in HKCU Console
$consoleKeys = @(
    "HKCU:\Console",
    "HKCU:\Console\%SystemRoot%_System32_cmd.exe",
    "HKCU:\Console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe",
    "HKCU:\Console\%SystemRoot%_SysWOW64_WindowsPowerShell_v1.0_powershell.exe"
)

foreach ($key in $consoleKeys) {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name "FaceName" -Value "JetBrainsMono NFM" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name "FontFamily" -Value 54 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name "FontSize" -Value 0x00100000 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name "CodePage" -Value 65001 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name "VirtualTerminalLevel" -Value 1 -ErrorAction SilentlyContinue
}

# 7. Restart Windows Explorer to reload the WinX cache
Write-Host "`nRestarting Windows Explorer to reload Win+X menu..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force

Write-Host "`n=== Patch Applied Successfully! ===" -ForegroundColor Green
Write-Host "Press Win+X and click 'Windows PowerShell' to launch Windows Terminal." -ForegroundColor White
