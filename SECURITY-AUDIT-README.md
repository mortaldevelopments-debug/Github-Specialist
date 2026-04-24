# 🛡️ Local Windows Security Audit Tool

A **Windows-only**, read-only security audit script that uses **only built-in Windows tools**. It never downloads external binaries, never modifies security settings, and never changes Defender exclusions or execution policy.

---

## What it does

| Check | Tool used |
|---|---|
| Malware scan | Microsoft Defender `MpCmdRun.exe` |
| Startup items | Registry `Run` / `RunOnce` keys + Startup folders |
| Scheduled tasks | `Get-ScheduledTask` (non-Microsoft, enabled) |
| Running services | `Win32_Service` WMI + Authenticode publisher check |
| Process resource usage | `Get-Process` + `Win32_PerfFormattedData` WMI |
| Report export | JSON + TXT with timestamp in `./output/` |

---

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or later (built into Windows)
- Microsoft Defender enabled (for scan modes)
- No third-party installs needed

---

## Setup

1. **Clone or download** this repository to your machine.
2. Open **PowerShell** (not PowerShell ISE) in the folder containing `security-audit.ps1`.
3. If your execution policy blocks running scripts, allow it for the current session only:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
   ```
   > This only affects the current PowerShell window. It does **not** change system-wide policy.
4. Run the script with one of the modes below.

---

## Usage

### Report only (no Defender scan)
```powershell
.\security-audit.ps1 -ReportOnly
```
Collects startup items, scheduled tasks, services, and process info. No scan invoked.

### Quick scan
```powershell
.\security-audit.ps1 -QuickScan
```
Runs Microsoft Defender quick scan. You will be asked to confirm before it starts.

### Full scan
```powershell
.\security-audit.ps1 -FullScan
```
Runs a full Defender scan. **This can take 30–90+ minutes.** You will be asked to confirm.

### Custom path scan
```powershell
.\security-audit.ps1 -PathScan "C:\Users\YourName\Downloads"
```
Scans only the specified file or folder. Useful for checking a specific suspicious item.

---

## Output

Reports are written to the `output/` folder:

```
output/
  security-audit_20260424_143012.json   ← structured data (all findings)
  security-audit_20260424_143012.txt    ← human-readable summary
```

Each run creates a new timestamped file. Nothing is sent to the internet.

---

## Running from VS Code

Use the **Run Security Audit** task (manual only):

1. Open the Command Palette: `Ctrl+Shift+P`
2. Select **Tasks: Run Task**
3. Choose **Run Security Audit (Report Only)**

> The task will **not** run automatically when you open the folder. It only runs when you explicitly choose it.

---

## What to look for in the report

| Section | Red flags |
|---|---|
| **StartupItems** | Entries pointing to `%TEMP%`, `%APPDATA%\Roaming`, random filenames, or paths with no obvious publisher |
| **ScheduledTasks** | Tasks with encoded PowerShell commands, `curl`/`wget`, paths in temp folders, or unfamiliar names |
| **NonMsSServices** | Services with no publisher signature, paths in user profile directories |
| **HighCpuProcesses** | Unknown processes consistently above 10–20% CPU (possible miner) |
| **HighRamProcesses** | Unknown processes using 500MB+ with no clear application name |

---

## What this tool does NOT do

- ❌ Does not change any Windows settings
- ❌ Does not add or remove Defender exclusions
- ❌ Does not change execution policy permanently
- ❌ Does not download or run external code
- ❌ Does not auto-run when the folder is opened
- ❌ Does not send data anywhere

---

## Troubleshooting

**"MpCmdRun.exe not found"**  
Defender may be disabled or your Windows installation is non-standard. Check Windows Security in the Start menu.

**Scheduled tasks or services show "access denied"**  
Run PowerShell as Administrator for more complete results. Right-click PowerShell → "Run as administrator".

**Script is blocked by execution policy**  
Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` first (current session only).
