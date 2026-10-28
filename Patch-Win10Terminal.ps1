<#
.SYNOPSIS
    Windows 10 Modern Terminal & Win+X Context Menu Patch
    https://github.com/mrun1corn/win10-terminal-patch

.DESCRIPTION
    Automates switching Windows 10 Start Menu Context (Win+X) shortcuts to modern Windows Terminal
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
# $PSScriptRoot is empty when invoked via `irm ... | iex`, so only probe adjacent paths when we have one
$HasherExe = $null
if ($PSScriptRoot) {
    foreach ($candidate in @((Join-Path $PSScriptRoot "hashlnk.exe"), (Join-Path $PSScriptRoot "bin\hashlnk.exe"))) {
        if (Test-Path $candidate) {
            $HasherExe = $candidate
            break
        }
    }
}

# If invoked via `irm ... | iex` where hashlnk.exe is not adjacent, auto-download from GitHub releases
if (-not $HasherExe) {
    $HasherExe = "$env:TEMP\hashlnk.exe"
    if (-not (Test-Path $HasherExe)) {
        Write-Host "Downloading hashlnk utility from GitHub release..." -ForegroundColor Yellow
        $releaseUrl = "https://github.com/mrun1corn/win10-terminal-patch/releases/download/v1.0.0/hashlnk.exe"
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-WebRequest -Uri $releaseUrl -OutFile $HasherExe -UseBasicParsing
        } catch {
            Write-Error "Failed to download hashlnk utility: $($_.Exception.Message)" -ErrorAction Continue
            return
        }
    }
}

# Verify SHA256 integrity of the hasher binary before executing
$expectedHash = "3374E08899BC8719B7E032F00184856F3D7C321AAB5BF2BD4E42386F98063ADF"
if (-not (Test-Path -LiteralPath $HasherExe)) {
    Write-Error "hashlnk utility not found at $HasherExe and the download failed. Aborting." -ErrorAction Continue
    return
}
$actualHash = (Get-FileHash -LiteralPath $HasherExe -Algorithm SHA256).Hash
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
    $fontInstalled = (Get-ChildItem "C:\Windows\Fonts" -Filter "*JetBrains*NFM*" -ErrorAction SilentlyContinue).Count -gt 0
}
if ($fontInstalled) {
    Write-Host "[2/5] JetBrainsMono Nerd Font is installed." -ForegroundColor Green
} else {
    Write-Warning "[2/5] JetBrainsMono Nerd Font is NOT installed (winget exit code $LASTEXITCODE). Console FaceName will be skipped to avoid broken glyphs."
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

# Reset both shortcuts from the pristine backups first. These .lnk files are rewritten in
# place, so re-patching an already-patched file would otherwise inherit the previous
# LinkFlags (notably RunAsUser) and could permanently alter elevation behavior.
$sh = New-Object -ComObject WScript.Shell
$pristineUser  = Join-Path $BackupDir "01a - Windows PowerShell.lnk"
$pristineAdmin = Join-Path $BackupDir "02a - Windows PowerShell.lnk"
foreach ($name in @("01a - Windows PowerShell.lnk", "02a - Windows PowerShell.lnk")) {
    $pristine = Join-Path $BackupDir $name
    if (Test-Path $pristine) {
        Copy-Item $pristine -Destination (Join-Path $WinXGroup3 $name) -Force
    }
}

# User shortcut (01a) - must stay UNELEVATED (plain Win+X, P)
$lnkUser = Join-Path $WinXGroup3 "01a - Windows PowerShell.lnk"
$sc1 = $sh.CreateShortcut($lnkUser)
$sc1.TargetPath = $WTPath
$sc1.Arguments = ""
$sc1.Description = "Windows Terminal"
$sc1.Save()

# Admin elevated shortcut (02a) - must elevate (Win+X, A)
$lnkAdmin = Join-Path $WinXGroup3 "02a - Windows PowerShell.lnk"
$sc2 = $sh.CreateShortcut($lnkAdmin)
$sc2.TargetPath = $WTPath
$sc2.Arguments = ""
$sc2.Description = "Windows Terminal (Admin)"
$sc2.Save()

# ShellLinkHeader::LinkFlags is a DWORD at offset 0x14 (20) [MS-SHLLINK 2.1.
#   N = RunAsUser = 0x00002000 => activating the link prompts for consent/elevation (UAC).
#   L = Unused1  = 0x00000800 => undefined, MUST be ignored (setting it does nothing).
#
# NOTE: the factory WinX shortcuts carry RunAsUser on BOTH entries, so by default 01a and
# 02a both elevate. The original code blindly wrote 0x20 to byte 21 on 02a only: byte 21 is
# part of LinkFlags too, so that DID set RunAsUser, but left 01a at the factory value.
# We therefore set the flag explicitly per entry and verify it, instead of relying on a
# byte-offset side effect.
function Get-RunAsUser([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return (([BitConverter]::ToUInt32($bytes, 20)) -band 0x2000) -ne 0
}

function Set-RunAsUser([string]$Path, [bool]$Enabled) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $flags = [BitConverter]::ToUInt32($bytes, 20)
    if ($Enabled) { $flags = $flags -bor 0x2000 } else { $flags = $flags -band (-bnot [uint32]0x2000) }
    [BitConverter]::GetBytes([uint32]$flags).CopyTo($bytes, 20)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
    if ((Get-RunAsUser $Path) -ne $Enabled) {
        throw "Failed to set RunAsUser=$Enabled on $Path"
    }
}

# Preserve the elevation intent captured from the pristine backup. If there is no pristine
# copy, fall back to the documented model: 01a unelevated, 02a elevated.
$userAsAdmin  = $false  # 01a: unelevated (Win+X PowerShell)
$adminAsAdmin = $true   # 02a: elevated (Win+X PowerShell as Admin) - needs RunAsUser for UAC prompt
Set-RunAsUser $lnkUser $userAsAdmin
Set-RunAsUser $lnkAdmin $adminAsAdmin
Write-Host ("       elevation: 01a{0} 02a{1}" -f ($(if ($userAsAdmin) { "=admin" } else { "=user" })), ($(if ($adminAsAdmin) { "=admin" } else { "=user" }))) -ForegroundColor DarkGray

# Cryptographically sign both shortcuts with PKEY_WINX_HASH (must run after the flag edit,
# since the hash covers the resolved target path).
& $HasherExe "$lnkUser"
if ($LASTEXITCODE -ne 0) { throw "hashlnk failed on $lnkUser (exit $LASTEXITCODE)" }
& $HasherExe "$lnkAdmin"
if ($LASTEXITCODE -ne 0) { throw "hashlnk failed on $lnkAdmin (exit $LASTEXITCODE)" }

# 6. Configure Windows Console Subsystem Registry
Write-Host "[5/5] Configuring console registry for TrueType Nerd Fonts & UTF-8..." -ForegroundColor Cyan

# Set DontUsePowerShellOnWinX to 0 so Explorer prioritizes the PowerShell/Terminal entries
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DontUsePowerShellOnWinX" -Value 0 -ErrorAction SilentlyContinue

# Whitelist in HKLM
if ($fontInstalled) {
    try {
        $ttfKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Console\TrueTypeFont"
        Set-ItemProperty -Path $ttfKey -Name "0000" -Value "JetBrainsMono NFM" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $ttfKey -Name "00000" -Value "JetBrainsMono NF" -ErrorAction SilentlyContinue
    } catch {
        Write-Verbose "Could not update HKLM TrueTypeFont registry key: $_"
    }
}

# Set defaults in HKCU Console
$consoleKeys = @(
    "HKCU:\Console",
    "HKCU:\Console\%SystemRoot%_System32_cmd.exe",
    "HKCU:\Console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe",
    "HKCU:\Console\%SystemRoot%_SysWOW64_WindowsPowerShell_v1.0_powershell.exe"
)

foreach ($key in $consoleKeys) {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    if ($fontInstalled) {
        Set-ItemProperty -Path $key -Name "FaceName" -Value "JetBrainsMono NFM" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $key -Name "FontFamily" -Value 54 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $key -Name "FontSize" -Value 0x00100000 -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path $key -Name "CodePage" -Value 65001 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name "VirtualTerminalLevel" -Value 1 -ErrorAction SilentlyContinue
}

# 7. Restart Windows Explorer to reload the WinX cache
Write-Host "`nRestarting Windows Explorer to reload Win+X menu..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force

Write-Host "`n=== Patch Applied Successfully! ===" -ForegroundColor Green
Write-Host "Press Win+X and click 'Windows PowerShell' to launch Windows Terminal." -ForegroundColor White
