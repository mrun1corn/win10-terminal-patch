# Windows 10 Modern Terminal & Win+X Context Menu Patch

[![GitHub release](https://img.shields.io/github/v/release/mrun1corn/win10-terminal-patch?color=2ea44f&logo=github)](https://github.com/mrun1corn/win10-terminal-patch/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows 10](https://img.shields.io/badge/Platform-Windows%2010-0078D6.svg?logo=windows)](https://microsoft.com/windows)
[![Tested On](https://img.shields.io/badge/Windows%2010%20Build-22H2%20(19045)-blueviolet.svg)](https://microsoft.com/windows)
[![Shell: PowerShell](https://img.shields.io/badge/Shell-PowerShell-5391FE.svg?logo=powershell)](https://github.com/PowerShell/PowerShell)

A fast, lightweight, and 100% reversible tool that brings modern Windows Terminal directly to the **Windows 10 Win+X Start context menu**. Especially vital for **Windows 10 LTSC, Enterprise, or builds prior to KB5026435** where native terminal delegation does not exist.

Automatically retargets the **Win+X Start context menu** to open **Windows Terminal** directly (with Administrator elevation support), installs **JetBrains Mono Nerd Font**, and fixes broken font/glyph icons and legacy OEM codepages across classic Windows consoles.

---

## 🧐 The Problem: Why Windows 10 Needs This

| Behavior | Windows 11 | Windows 10 (Default) | Windows 10 (With This Patch) |
| :--- | :---: | :---: | :---: |
| **Win+X launches** | Modern Windows Terminal | Legacy 1995 `conhost.exe` | **Modern Windows Terminal** |
| **Admin (`Win+X, A`) launches** | Windows Terminal (Admin) | Legacy `conhost.exe` | **Windows Terminal (Admin)** |
| **Nerd Font Glyphs & Icons** | Native rendering | Broken `[?]` boxes | **Solid glyphs (`JetBrainsMono NF`)** |
| **Console Encoding** | Native UTF-8 | OEM legacy codepage (437) | **UTF-8 (CodePage 65001)** |

### Why manual shortcuts don't work on Windows 10:
Windows Explorer protects the shortcuts inside `%LocalAppData%\Microsoft\Windows\WinX\Group3\` with an undocumented cryptographic checksum (`PKEY_WINX_HASH`). If you try to manually change the shortcut target to `wt.exe`, **Windows Explorer silently deletes or hides the entry**. 

This patch calculates the exact cryptographic hash using the Windows Shell API (`shlwapi.dll!HashData`) and signs the shortcuts so Windows Explorer accepts them.

---

## ⚡ Quick Start (1-Click Install)

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
irm https://raw.githubusercontent.com/mrun1corn/win10-terminal-patch/main/Patch-Win10Terminal.ps1 | iex
```

*That's it! Press `Win+X` and click `Windows PowerShell` — it will immediately open in Windows Terminal.*

---

## 📦 What the Script Does Automatically

1. **Detects & Installs Windows Terminal**: If `wt.exe` is missing, installs it silently via WinGet.
2. **Installs JetBrainsMono Nerd Font**: Automatically installs `DEVCOM.JetBrainsMonoNerdFont` so icons, folders, and powerline prompts render without broken symbols.
3. **Upgrades Win+X Menu**:
   - Replaces `01a - Windows PowerShell.lnk` with a direct link to `wt.exe`.
   - Replaces `02a - Windows PowerShell.lnk` with an elevated link to `wt.exe` (Admin).
   - Generates and stamps valid `PKEY_WINX_HASH` properties on both shortcuts.
4. **Fixes Legacy Console Subsystem**: Whitelists TrueType Nerd Fonts in `HKLM:\...\Console\TrueTypeFont` and configures UTF-8 (`65001`) with ANSI virtual terminal processing.
5. **Backs Up Originals**: Backs up factory shortcuts to `%LocalAppData%\Microsoft\Windows\WinX\Group3_OriginalBackup`.

---

## 🔄 How to Revert (100% Safe)

To restore factory Windows 10 shortcuts and registry settings at any time, run:

```powershell
& ".\Patch-Win10Terminal.ps1" -Revert
```
*(Or via direct one-liner:)*
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mrun1corn/win10-terminal-patch/main/Patch-Win10Terminal.ps1))) -Revert
```

---

## 🛠️ Building from Source (Auditing & Transparency)

The repository provides full C++ source code in [`src/`](src/) so users never have to run untrusted binaries.

### Requirements:
- Visual Studio 2022 / C++ Build Tools (MSVC v143)
- Windows SDK (10 or 11)

### Build command:
```cmd
vcvars64.bat
cl /EHsc /O2 /std:c++17 src\hashlnk.cpp /Fe:hashlnk.exe
```

### Precompiled Binary Verification (SHA256):
```text
hashlnk.exe: 7d30b1ec2d488c323decc8f9c92cb71454e893b572f80226eb6475ff1f0a28a3
```

---

## 🌟 Contributing & Feedback

- Issues and Pull Requests are welcome!
- If this saved you time configuring Windows 10, consider giving the repository a ⭐️!

---

## 📄 License

Distributed under the [MIT License](LICENSE).
Hash algorithm research credited to [Rafael Rivera](https://github.com/riverar/hashlnk).
