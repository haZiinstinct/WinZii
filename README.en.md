<div align="center">

<img src="docs/banner.svg" alt="WinZii" width="100%">

# WinZii

**Portable Windows toolkit for everyday technician work.**
Run it from a USB stick: clean up, optimize, set up — no installation, no account, no telemetry.

[Deutsch](README.md) · **English**

<sub>The interface, reports, and most documentation are **German only**. This readme exists so you can tell what the tool does before deciding whether that works for you.</sub>

![Version](https://img.shields.io/badge/Version-0.2.2-00d4ff?labelColor=0a0a0f&style=flat-square)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-00d4ff?labelColor=0a0a0f&style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-00d4ff?labelColor=0a0a0f&style=flat-square)
![Install](https://img.shields.io/badge/Install-none-00d4ff?labelColor=0a0a0f&style=flat-square)

[Getting started](#-getting-started) · [Features](#-features) · [Safety](#-safety) · [Known limits](#-known-limits) · [Layout](#-layout) · [Extending](#-extending)

</div>

---

## ✨ Features

| Area | What it does |
| --- | --- |
| **Dashboard** | Windows version, hardware, GPU, monitors, BIOS, RAM slots and battery wear, plus activation, BitLocker, antivirus, disks and network — everything at a glance when taking on a PC. |
| **Diagnostics** | Reads the event logs and translates them into plain language: what happened, what it means, what to do. Plus bluescreen stop codes, disk health, and the sfc, DISM and chkdsk tools. |
| **Optimization** | 41 tweaks for speed, telemetry, privacy and security. Each one explained, each one individually reversible. |
| **AI removal** | Finds Copilot, Recall and Click to Do — blocks them by policy or removes them entirely. The blocks also act preventively against feature updates. |
| **Cleanup** | First shows where the space went (caches, update leftovers, browser caches, Windows.old), then deletes selectively. Personal files are excluded. |
| **Programs** | 52 programs via winget, including bootstrapping winget itself on LTSC systems. Installers can be cached on the stick for offline use. A second section finds and uninstalls installed programs — silently where possible. |
| **Office** | Microsoft 365, Office LTSC 2024 and 2021 via the official Deployment Tool — fully offline from the stick if you want. Plus LibreOffice. |
| **Data** | Answers the question before every reinstall: what needs backing up? Profile sizes per account, Outlook data files, browser profiles, printers, network drives, product keys. Warns about OneDrive placeholders that look like files in Explorer but are empty. Exports bookmarks, Wi-Fi credentials and BitLocker recovery keys. |
| **Drivers** | Devices with error codes in plain language instead of numbers. Driver inventory sorted by age — the fastest route to a suspect after bluescreens. Back up drivers to the stick and restore them in one go after reinstalling. |
| **Autostart** | Shows everything that starts at sign-in, with publisher. Disable instead of delete — reversible at any time. |
| **Repair** | Measures first where the problem sits (adapter, IP, router, DNS, internet), then names the matching fix. Plus Windows Update cache reset, print queue flush, quick virus scan, preinstalled app removal. |
| **Protocol** | Every step is recorded. Two outputs: the technical log and the **handover sheet** — what was done, how much space was gained, how the PC is equipped and what remains, in customer language with fields for technician, customer and order number. |

---

## 🚀 Getting started

1. Download the latest ZIP from the [releases](https://github.com/haZiinstinct/WinZii/releases) and extract it onto a USB stick (**exFAT or NTFS**, not FAT32 — the Office payloads would not fit).
2. Double-click `Start.bat`.
3. Confirm the administrator prompt.

That is all. WinZii needs no installation, no runtime, no particular drive letter. The folder can have any name and live anywhere — including paths with spaces.

> **Windows shows a blue SmartScreen warning?**
> Click "More info" and then "Run anyway". The warning appears for any unsigned file downloaded from the internet. Every release ships a SHA256 checksum so you can verify the archive before extracting:
> ```powershell
> Get-FileHash .\WinZii-0.2.2.zip -Algorithm SHA256
> ```

**Requirements:** Windows 10 or 11 with administrator rights. PowerShell 5.1 and .NET Framework ship with Windows.

**First run: use test mode.** The toggle in the bottom right logs every change without executing it. `Start.bat` passes switches through — `Start.bat -DryRun` starts straight into test mode, `Start.bat -NoElevate` skips the elevation prompt.

---

## 🛡 Safety

A tool that reaches deep into the system must know the way back:

- **Restore point** before every larger intervention (optional, on by default).
- **Registry export** of every touched key as a `.reg` file.
- **Undo file** with the exact prior state of every single action — the "revert changes" button restores it.
- **Test mode** that only logs.
- **Confirmation before every intervention**, listing exactly what will happen.

Everything lands under `backups\<hostname>\<timestamp>\`.

What does **not** happen: no telemetry, no outbound connections except downloads you explicitly trigger (winget, Office, LibreOffice), no deletion of personal files. The Downloads folder is only measured, never emptied.

Two exports intentionally write secrets in plain text to the stick, each behind its own confirmation: the **Wi-Fi export with keys** and the **BitLocker recovery keys**. Do not hand the stick to strangers afterwards. Details in [SECURITY.md](SECURITY.md) (German).

> **No warranty.** WinZii modifies Windows at a low level. Use at your own risk — review in test mode first, let it create a restore point before larger interventions, and back up customer data beforehand.

---

## ⚠ Known limits

To be blunt, so nobody gets surprised: WinZii was developed and tested on **one** machine — Windows 11 Enterprise, German locale, a desktop without battery, Wi-Fi, BitLocker or OneDrive.

| Area | Status |
| --- | --- |
| **Windows 10** | The version switch works (33 tweaks for both systems, 7 Windows-11-only, 1 Windows-10-only), but a full run never happened there. |
| **Non-German Windows** | The code that parses Windows output knows German and English; `takeown` adapts to the UI language. Only the German side has been exercised. |
| **Battery, Wi-Fi, BitLocker, OneDrive** | The "not present" paths are verified and report cleanly. The positive cases are untested for lack of hardware. |
| **Driver backup, Office install** | Verified read-only, never executed end to end. |
| **Small screens** | The window needs at least 1000 × 560 device-independent pixels and shrinks itself to the working area. |

**Verified in Windows Sandbox** (`tools\Test-Sandbox.wsb`, a pristine Windows 11 24H2 without winget): launcher startup, applying real tweaks and reverting them, network diagnosis, and the winget bootstrap — all on a system that knows nothing about this project.

Feedback from other systems is very welcome — especially from Windows 10 and non-German installations.

---

## 🖼️ Interface

Dark theme in the haZii style, German, with a live console: every action is visible while it runs. Long operations never block the UI.

<img src="docs/screenshot-dashboard.png" alt="WinZii dashboard" width="100%">

Twelve pages in five groups:

```
// SYSTEM        Dashboard · Diagnostics
// OPTIMIZE      Optimization · AI removal · Cleanup · Autostart
// INSTALL       Programs · Office
// TAKE OVER     Data · Drivers
// TOOLS         Repair · Protocol
```

---

## 🛠 Layout

```
WinZii/
├─ Start.bat              double-click entry point
├─ src/
│  ├─ launcher.ps1        elevation, unblocking, STA start
│  ├─ main.ps1            window, navigation and module setup
│  ├─ modules/            logic (Optimizer, Cleanup, Apps, Office, Diagnostics …)
│  ├─ pages/              per-page UI logic
│  ├─ xaml/               UI: Theme.xaml + one file per page
│  └─ templates/          template for the HTML reports
├─ data/                  catalogs as JSON — extend the tool here
├─ assets/fonts/          JetBrains Mono and Inter (SIL OFL 1.1, see below)
├─ tools/                 dev checks and the release build script
├─ docs/                  banner and screenshot for the readme
├─ offline/               cache for installers
├─ logs/ backups/ reports/  per-computer results
```

**Tech:** PowerShell 5.1 with WPF. No compilation, no dependencies — the code is readable and directly editable. Long operations run in their own runspaces so the UI stays responsive.

---

## 🔧 Extending

All content lives in `data/` as JSON. New entries need zero lines of code — the file formats are documented in the German readme, the fields are self-explanatory. Validate after every change:

```powershell
powershell -NoProfile -File tools\Test-Catalogs.ps1
```

Contribution guidelines (including the **UTF-8 BOM requirement** for all `.ps1`/`.xaml` files — PowerShell 5.1 reads files without a BOM as ANSI and destroys non-ASCII text) are in [CONTRIBUTING.md](CONTRIBUTING.md) (German). Version history: [CHANGELOG.md](CHANGELOG.md) (German).

---

## 📄 License

**WinZii** is MIT-licensed — see [LICENSE](LICENSE).

**The bundled fonts are not.** [Inter](https://github.com/rsms/inter) and [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) under `assets/fonts/` are licensed under the **SIL Open Font License 1.1**; the license texts sit next to them as `OFL-Inter.txt` and `OFL-JetBrainsMono.txt`.

The AI-removal techniques draw on [zoicware/RemoveWindowsAI](https://github.com/zoicware/RemoveWindowsAI); the portable-toolkit approach on [Chris Titus WinUtil](https://github.com/christitustech/winutil).

---

<div align="center">

Built by haZii · `// code:` [**haZii.org**](https://hazii.org)

</div>
