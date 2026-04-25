"""
=============================================================
  Windows Security Scanner  —  Github-Specialist / scanner
=============================================================
  Run in VS Code terminal:  python scan.py
  Requires Python 3.9+  |  Run as Administrator for full results
=============================================================
"""

import os
import sys
import json
import hashlib
import subprocess
import winreg
import ctypes
import datetime
import platform
import shutil
from pathlib import Path
from collections import defaultdict

try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False

# ─────────────────────────────────────────────
#  ANSI colours (work in VS Code terminal)
# ─────────────────────────────────────────────
RED    = "\033[91m"
YELLOW = "\033[93m"
GREEN  = "\033[92m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

BANNER = f"""
{CYAN}{BOLD}
 ██████╗  ██████╗ █████╗ ███╗   ██╗
██╔════╝ ██╔════╝██╔══██╗████╗  ██║
╚█████╗  ██║     ███████║██╔██╗ ██║
 ╚═══██╗ ██║     ██╔══██║██║╚██╗██║
██████╔╝ ╚██████╗██║  ██║██║ ╚████║
╚═════╝   ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝
  Windows Security Scanner  v1.0
  github: mortaldevelopments-debug/Github-Specialist
{RESET}"""

# ─────────────────────────────────────────────
#  Known-bad process names (common RATs / miners / loggers)
# ─────────────────────────────────────────────
SUSPECT_PROCESS_NAMES = {
    # Remote-access trojans / stealers
    "njrat", "nanocore", "asyncrat", "darkcomet", "remcos",
    "quasarrat", "xrat", "imminent", "netwire", "orcus",
    # Keyloggers
    "ardamax", "revealer", "refog", "spyrix", "actual keylogger",
    # Miners
    "xmrig", "minerd", "cpuminer", "ethminer",
    # Generic stagers
    "mshta", "wscript", "cscript", "regsvr32", "rundll32",
    "powershell", "cmd",  # flagged only when hidden / unsigned
    # Adware / PUA droppers
    "opensubtitles", "soylent", "conduit", "mypcbackup",
}

# ─────────────────────────────────────────────
#  Suspicious registry run-key paths
# ─────────────────────────────────────────────
REGISTRY_RUN_KEYS = [
    (winreg.HKEY_CURRENT_USER,  r"Software\Microsoft\Windows\CurrentVersion\Run"),
    (winreg.HKEY_CURRENT_USER,  r"Software\Microsoft\Windows\CurrentVersion\RunOnce"),
    (winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\Run"),
    (winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\RunOnce"),
    (winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\RunServices"),
    # 64-bit mirror
    (winreg.HKEY_LOCAL_MACHINE, r"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"),
]

# ─────────────────────────────────────────────
#  Suspicious file extensions in temp / appdata
# ─────────────────────────────────────────────
SUSPECT_EXTENSIONS = {".exe", ".bat", ".vbs", ".ps1", ".cmd", ".scr", ".pif", ".jar", ".hta"}

SUSPECT_DIRS = [
    os.environ.get("TEMP", ""),
    os.environ.get("TMP", ""),
    os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup"),
    os.path.join(os.environ.get("APPDATA", ""), "Roaming"),
    os.path.join(os.environ.get("LOCALAPPDATA", ""), "Temp"),
    r"C:\Windows\Temp",
    r"C:\ProgramData",
]

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────

def is_admin() -> bool:
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        return False


def sha256(path: str) -> str:
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return "unreadable"


def header(title: str) -> None:
    print(f"\n{CYAN}{BOLD}{'─'*60}{RESET}")
    print(f"{CYAN}{BOLD}  {title}{RESET}")
    print(f"{CYAN}{'─'*60}{RESET}")


def ok(msg: str) -> None:
    print(f"  {GREEN}✔  {msg}{RESET}")


def warn(msg: str) -> None:
    print(f"  {YELLOW}⚠  {msg}{RESET}")


def bad(msg: str) -> None:
    print(f"  {RED}✘  {msg}{RESET}")


def info(msg: str) -> None:
    print(f"  {CYAN}ℹ  {msg}{RESET}")


# ─────────────────────────────────────────────
#  1 · System info
# ─────────────────────────────────────────────

def check_system_info() -> None:
    header("SYSTEM INFORMATION")
    info(f"OS        : {platform.platform()}")
    info(f"Hostname  : {platform.node()}")
    info(f"Python    : {platform.python_version()}")
    info(f"Admin     : {'YES — full scan enabled' if is_admin() else 'NO — re-run as Administrator for complete results'}")
    if not is_admin():
        warn("Some checks require Administrator privileges. Right-click → Run as Administrator.")


# ─────────────────────────────────────────────
#  2 · Running processes
# ─────────────────────────────────────────────

def check_processes() -> list[dict]:
    header("RUNNING PROCESSES — THREAT CHECK")
    findings: list[dict] = []

    if not PSUTIL_AVAILABLE:
        warn("psutil not installed — skipping process scan.  Run:  pip install psutil")
        return findings

    for proc in psutil.process_iter(["pid", "name", "exe", "username", "cmdline"]):
        try:
            name_lower = (proc.info["name"] or "").lower()
            exe        = proc.info.get("exe") or ""
            pid        = proc.info["pid"]
            cmdline    = " ".join(proc.info.get("cmdline") or [])

            flagged = False
            reason  = []

            # Name matches known-bad list
            for bad_name in SUSPECT_PROCESS_NAMES:
                if bad_name in name_lower:
                    reason.append(f"name matches known threat '{bad_name}'")
                    flagged = True

            # Executable lives in Temp
            if exe and ("\\temp\\" in exe.lower() or "\\tmp\\" in exe.lower()):
                reason.append("executable running from Temp folder")
                flagged = True

            # PowerShell / cmd with encoded / hidden flags
            if "powershell" in name_lower or "cmd" in name_lower:
                suspicious_flags = ["-enc", "-encodedcommand", "-windowstyle hidden", "-noprofile -noninteractive"]
                for flag in suspicious_flags:
                    if flag in cmdline.lower():
                        reason.append(f"suspicious flag: {flag}")
                        flagged = True

            if flagged:
                entry = {"pid": pid, "name": proc.info["name"], "exe": exe, "reason": reason}
                findings.append(entry)
                bad(f"PID {pid:>6}  {proc.info['name']:<30}  {'; '.join(reason)}")
                if exe:
                    bad(f"           Path: {exe}")

        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    if not findings:
        ok("No obviously malicious processes detected.")
    return findings


# ─────────────────────────────────────────────
#  3 · Registry startup entries
# ─────────────────────────────────────────────

def check_registry_startup() -> list[dict]:
    header("REGISTRY STARTUP ENTRIES")
    findings: list[dict] = []

    for hive, key_path in REGISTRY_RUN_KEYS:
        try:
            with winreg.OpenKey(hive, key_path, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
                i = 0
                while True:
                    try:
                        name, value, _ = winreg.EnumValue(key, i)
                        value_lower = value.lower()
                        suspicious = any(x in value_lower for x in ["temp\\", "tmp\\", "appdata\\roaming\\", ".vbs", ".bat", ".ps1", ".hta", "regsvr32", "mshta", "wscript"])
                        hive_name = "HKCU" if hive == winreg.HKEY_CURRENT_USER else "HKLM"
                        entry = {"hive": hive_name, "key": key_path, "name": name, "value": value, "suspicious": suspicious}
                        findings.append(entry)
                        if suspicious:
                            bad(f"[{hive_name}] {name}")
                            bad(f"           → {value}")
                        else:
                            ok(f"[{hive_name}] {name:<35}  {value[:80]}")
                        i += 1
                    except OSError:
                        break
        except PermissionError:
            warn(f"Access denied: {key_path}  (run as Administrator)")
        except FileNotFoundError:
            pass

    suspicious_count = sum(1 for f in findings if f["suspicious"])
    if suspicious_count:
        bad(f"{suspicious_count} suspicious startup entries found — review above.")
    else:
        ok("All visible startup entries look clean.")
    return findings


# ─────────────────────────────────────────────
#  4 · Suspicious files in hot directories
# ─────────────────────────────────────────────

def check_suspicious_files() -> list[dict]:
    header("SUSPICIOUS FILES IN TEMP / STARTUP DIRS")
    findings: list[dict] = []

    for base_dir in SUSPECT_DIRS:
        if not base_dir or not os.path.isdir(base_dir):
            continue
        try:
            for root, _dirs, files in os.walk(base_dir):
                for fname in files:
                    ext = Path(fname).suffix.lower()
                    if ext in SUSPECT_EXTENSIONS:
                        full_path = os.path.join(root, fname)
                        try:
                            size = os.path.getsize(full_path)
                            mtime = datetime.datetime.fromtimestamp(os.path.getmtime(full_path))
                        except OSError:
                            size, mtime = 0, "unknown"
                        entry = {"path": full_path, "size": size, "modified": str(mtime)}
                        findings.append(entry)
                        warn(f"{full_path}")
                        info(f"           size={size} bytes  modified={mtime}")
        except PermissionError:
            pass

    if not findings:
        ok("No suspicious executables found in Temp/Startup directories.")
    else:
        warn(f"{len(findings)} suspicious file(s) found — review before deleting.")
    return findings


# ─────────────────────────────────────────────
#  5 · Windows Defender full scan (async)
# ─────────────────────────────────────────────

def run_defender_scan(quick: bool = True) -> None:
    header("WINDOWS DEFENDER SCAN")
    mpcmdrun = r"C:\Program Files\Windows Defender\MpCmdRun.exe"
    if not os.path.exists(mpcmdrun):
        warn("MpCmdRun.exe not found — Windows Defender may not be installed.")
        return

    scan_type = "-ScanType 1" if quick else "-ScanType 2"
    info(f"Launching Defender {'Quick' if quick else 'Full'} Scan …  (this may take a while)")
    try:
        result = subprocess.run(
            [mpcmdrun, "-Scan", scan_type],
            capture_output=True, text=True, timeout=600
        )
        if result.returncode == 0:
            ok("Defender scan completed — no threats found.")
        else:
            bad(f"Defender returned exit code {result.returncode}.")
            bad("Open Windows Security → Protection history to review threats.")
        if result.stdout:
            info(result.stdout.strip())
    except subprocess.TimeoutExpired:
        warn("Defender scan timed out. Check Windows Security manually.")
    except Exception as e:
        warn(f"Could not launch Defender: {e}")


# ─────────────────────────────────────────────
#  6 · Network connections (potential C2 / exfil)
# ─────────────────────────────────────────────

def check_network_connections() -> list[dict]:
    header("ACTIVE NETWORK CONNECTIONS — ANOMALY CHECK")
    findings: list[dict] = []

    if not PSUTIL_AVAILABLE:
        warn("psutil not installed — skipping network scan.")
        return findings

    # Ports that malware commonly uses for C2
    suspicious_ports = {1080, 4444, 4445, 5555, 6666, 6667, 7777, 8888, 9999, 31337, 1337}

    try:
        connections = psutil.net_connections(kind="inet")
        for conn in connections:
            if conn.status != "ESTABLISHED":
                continue
            raddr = conn.raddr
            if not raddr:
                continue
            remote_port = raddr.port
            remote_ip   = raddr.ip

            flagged = False
            reason  = []

            if remote_port in suspicious_ports:
                reason.append(f"known C2/backdoor port {remote_port}")
                flagged = True

            # Private-range IPs tunnelling out on unusual ports — skip RFC1918
            if not (remote_ip.startswith("10.") or remote_ip.startswith("192.168.") or remote_ip.startswith("172.")):
                if remote_port not in {80, 443, 53, 8080, 8443, 22, 25, 587, 993, 995}:
                    reason.append(f"unusual outbound port {remote_port} to {remote_ip}")
                    flagged = True

            pid = conn.pid
            try:
                pname = psutil.Process(pid).name() if pid else "unknown"
            except Exception:
                pname = "unknown"

            entry = {"pid": pid, "process": pname, "remote": f"{remote_ip}:{remote_port}", "reason": reason}

            if flagged:
                bad(f"PID {str(pid):<6} {pname:<25}  {remote_ip}:{remote_port}  — {'; '.join(reason)}")
                findings.append(entry)
            else:
                ok(f"PID {str(pid):<6} {pname:<25}  {remote_ip}:{remote_port}")

    except psutil.AccessDenied:
        warn("Access denied reading connections — run as Administrator.")

    if not findings:
        ok("No obviously suspicious outbound connections detected.")
    return findings


# ─────────────────────────────────────────────
#  7 · Startup folder files
# ─────────────────────────────────────────────

def check_startup_folders() -> None:
    header("STARTUP FOLDER CONTENTS")
    startup_dirs = [
        os.path.join(os.environ.get("APPDATA", ""), r"Microsoft\Windows\Start Menu\Programs\Startup"),
        r"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
    ]
    found_any = False
    for d in startup_dirs:
        if not os.path.isdir(d):
            continue
        entries = os.listdir(d)
        if entries:
            found_any = True
            for entry in entries:
                full = os.path.join(d, entry)
                ext  = Path(entry).suffix.lower()
                if ext in SUSPECT_EXTENSIONS:
                    bad(f"{full}")
                else:
                    ok(f"{full}")
    if not found_any:
        ok("Startup folders are empty.")


# ─────────────────────────────────────────────
#  8 · Quarantine / remove helpers
# ─────────────────────────────────────────────

def quarantine_file(path: str, quarantine_dir: str = r"C:\SecurityScanner_Quarantine") -> bool:
    """Move a suspect file to a quarantine directory instead of deleting."""
    os.makedirs(quarantine_dir, exist_ok=True)
    dest = os.path.join(quarantine_dir, os.path.basename(path) + ".quarantined")
    try:
        shutil.move(path, dest)
        ok(f"Quarantined: {path}  →  {dest}")
        return True
    except Exception as e:
        bad(f"Could not quarantine {path}: {e}")
        return False


def interactive_cleanup(suspicious_files: list[dict]) -> None:
    if not suspicious_files:
        return
    header("INTERACTIVE CLEANUP")
    print(f"  {YELLOW}Found {len(suspicious_files)} suspicious file(s).{RESET}")
    print(f"  Options per file:  {GREEN}[a]{RESET}lllow  {YELLOW}[q]{RESET}uarantine  {RED}[d]{RESET}elete  {CYAN}[s]{RESET}kip\n")
    for entry in suspicious_files:
        path = entry["path"]
        print(f"  {YELLOW}{path}{RESET}")
        choice = input("  Choice [a/q/d/s]: ").strip().lower()
        if choice == "d":
            try:
                os.remove(path)
                ok(f"Deleted: {path}")
            except Exception as e:
                bad(f"Could not delete: {e}")
        elif choice == "q":
            quarantine_file(path)
        elif choice == "a":
            ok(f"Allowed (skipped): {path}")
        else:
            info(f"Skipped: {path}")


# ─────────────────────────────────────────────
#  9 · Save report
# ─────────────────────────────────────────────

def save_report(data: dict) -> None:
    ts   = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    name = f"scan_report_{ts}.json"
    path = os.path.join(os.path.expanduser("~"), "Desktop", name)
    try:
        with open(path, "w") as f:
            json.dump(data, f, indent=2, default=str)
        ok(f"Report saved to Desktop: {name}")
    except Exception as e:
        warn(f"Could not save report: {e}  (trying current dir)")
        with open(name, "w") as f:
            json.dump(data, f, indent=2, default=str)
        ok(f"Report saved to current directory: {name}")


# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

def main() -> None:
    # Enable ANSI in Windows terminal
    os.system("")

    print(BANNER)

    if not is_admin():
        print(f"  {YELLOW}⚠  Not running as Administrator — some checks will be limited.{RESET}")
        print(f"  {YELLOW}   To get full results, right-click scan.py → Run as Administrator,{RESET}")
        print(f"  {YELLOW}   or open VS Code as Administrator.{RESET}\n")

    print(f"  {CYAN}Scan started:  {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}{RESET}")

    # ── run all checks ──────────────────────────
    check_system_info()
    procs        = check_processes()
    reg_entries  = check_registry_startup()
    susp_files   = check_suspicious_files()
    check_startup_folders()
    net_findings = check_network_connections()
    run_defender_scan(quick=True)

    # ── summary ─────────────────────────────────
    header("SCAN SUMMARY")
    total_issues = len(procs) + sum(1 for r in reg_entries if r["suspicious"]) + len(susp_files) + len(net_findings)
    if total_issues == 0:
        ok("✔  System appears clean based on automated checks.")
        ok("   Defender Quick Scan also completed — check Protection History if needed.")
    else:
        bad(f"  {total_issues} potential issue(s) found — review the output above.")
        warn("  Use the cleanup prompt below to remove specific files.")

    # ── interactive cleanup for suspicious files ─
    if susp_files:
        do_cleanup = input(f"\n  {YELLOW}Would you like to review suspicious files interactively? [y/N]: {RESET}").strip().lower()
        if do_cleanup == "y":
            interactive_cleanup(susp_files)

    # ── save report ──────────────────────────────
    report_data = {
        "scan_time":          datetime.datetime.now().isoformat(),
        "admin":              is_admin(),
        "suspicious_procs":   procs,
        "registry_entries":   reg_entries,
        "suspicious_files":   susp_files,
        "network_findings":   net_findings,
    }
    save_report(report_data)

    print(f"\n  {GREEN}{BOLD}Scan complete.{RESET}\n")


if __name__ == "__main__":
    main()
