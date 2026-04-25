# 🛡️ Windows Security Scanner

A single-file Python security scanner you run directly inside **VS Code**.  
It checks your PC for malware, keyloggers, suspicious startup entries, hidden executables, and unusual network connections — then triggers a Windows Defender scan.

---

## ⚡ Quick Start (VS Code)

### 1 — Open folder in VS Code
```
File → Open Folder → select the `scanner/` folder
```

### 2 — Install the one dependency
Open the **VS Code integrated terminal** (`Ctrl + \``) and run:
```powershell
pip install -r requirements.txt
```

### 3 — Run the scanner
> **Tip:** For the most complete scan, open VS Code as Administrator  
> (right-click the VS Code icon → "Run as administrator")

```powershell
python scan.py
```

The scanner prints colour-coded results directly in the terminal and saves a `scan_report_<timestamp>.json` to your Desktop.

---

## 🔍 What it checks

| # | Check | What it looks for |
|---|-------|-------------------|
| 1 | **System info** | OS, hostname, admin status |
| 2 | **Running processes** | Known RAT / keylogger / miner names, processes running from Temp, hidden PowerShell flags |
| 3 | **Registry startup keys** | All `Run` / `RunOnce` entries in HKCU & HKLM, flags entries pointing to Temp/AppData/scripts |
| 4 | **Suspicious files** | `.exe .bat .vbs .ps1 .cmd .scr .hta .jar` inside Temp, AppData, ProgramData |
| 5 | **Startup folders** | Both user and system startup folders |
| 6 | **Network connections** | ESTABLISHED connections to known C2 ports (4444, 1337, 31337 …) or unusual outbound ports |
| 7 | **Windows Defender** | Triggers a Quick Scan via `MpCmdRun.exe` |

---

## 🗂️ Output

- **Terminal** — colour-coded findings (green ✔ / yellow ⚠ / red ✘)
- **Desktop JSON report** — `scan_report_YYYYMMDD_HHMMSS.json` with every finding

---

## 🧹 Cleanup options

After the scan, if suspicious files are found you get an interactive prompt:

```
[a] allow    — mark it safe, skip
[q] quarantine — moves file to C:\SecurityScanner_Quarantine\  (safe, reversible)
[d] delete   — permanently removes the file
[s] skip     — do nothing for now
```

Quarantined files are renamed to `.quarantined` so they cannot execute accidentally.

---

## 🔒 Requirements

| Requirement | Notes |
|------------|-------|
| Windows 10 / 11 | macOS / Linux not supported (Windows-specific APIs used) |
| Python 3.9+ | `python --version` to check |
| `psutil` | `pip install psutil` — enables process + network scanning |
| Administrator (optional) | Required for full registry access and all network connections |
| Windows Defender | Required for the built-in AV scan step |

---

## ❓ FAQ

**Q: Will this delete my files without asking?**  
A: No. The scanner only reads and reports by default. Deletions only happen if you type `d` in the interactive cleanup prompt.

**Q: Is the Defender scan slow?**  
A: A Quick Scan usually takes 1–5 minutes. The scanner waits up to 10 minutes before timing out.

**Q: What if I want a Full Scan instead of Quick?**  
A: Edit `scan.py`, find `run_defender_scan(quick=True)` near the bottom of `main()`, and change it to `run_defender_scan(quick=False)`.

**Q: A file was flagged but I know it's safe — what do I do?**  
A: Choose `[a] allow` in the cleanup prompt, or simply ignore the warning. The scanner is heuristic — false positives can occur.
