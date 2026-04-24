#Requires -Version 5.1
<#
.SYNOPSIS
    Local Windows Security Audit Tool — reads system state and invokes Microsoft Defender.
    Does NOT modify security settings, add exclusions, change execution policy, or download anything.

.DESCRIPTION
    Collects system security information using only built-in Windows tools:
      - Microsoft Defender MpCmdRun.exe (Quick / Full / Custom path scan)
      - Registry Run keys (startup persistence check)
      - Startup folders
      - Scheduled tasks
      - Non-Microsoft services
      - High-resource processes
    Exports a timestamped report to the ./output/ folder in JSON and TXT format.

.PARAMETER QuickScan
    Run a Microsoft Defender quick scan.

.PARAMETER FullScan
    Run a Microsoft Defender full scan.

.PARAMETER PathScan
    Run a Microsoft Defender scan on a specific file or folder path.

.PARAMETER ReportOnly
    Skip all Defender scans and only collect system audit information.

.EXAMPLE
    .\security-audit.ps1 -QuickScan
    .\security-audit.ps1 -FullScan
    .\security-audit.ps1 -PathScan "C:\Users\YourName\Downloads"
    .\security-audit.ps1 -ReportOnly

.NOTES
    Windows only. Run from PowerShell (no elevated privileges required for most checks;
    Defender scans may show more detail when elevated).
    Review all output in the ./output/ folder — nothing is sent anywhere.
#>

[CmdletBinding(DefaultParameterSetName = 'ReportOnly')]
param (
    [Parameter(ParameterSetName = 'QuickScan')]
    [switch]$QuickScan,

    [Parameter(ParameterSetName = 'FullScan')]
    [switch]$FullScan,

    [Parameter(ParameterSetName = 'PathScan')]
    [string]$PathScan,

    [Parameter(ParameterSetName = 'ReportOnly')]
    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # continue after non-terminating errors so the report is always written

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Header {
    param([string]$Title)
    $line = '=' * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Confirm-Action {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    $answer = Read-Host "Type YES to continue, anything else to skip"
    return ($answer -eq 'YES')
}

function Get-Timestamp {
    return (Get-Date -Format 'yyyyMMdd_HHmmss')
}

# ---------------------------------------------------------------------------
# Output setup
# ---------------------------------------------------------------------------

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir  = Join-Path $scriptDir 'output'

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$timestamp  = Get-Timestamp
$jsonReport = Join-Path $outputDir "security-audit_$timestamp.json"
$txtReport  = Join-Path $outputDir "security-audit_$timestamp.txt"

# Accumulate all findings into this object
$report = [ordered]@{
    GeneratedAt    = (Get-Date -Format 'o')
    ComputerName   = $env:COMPUTERNAME
    UserName       = $env:USERNAME
    ScanMode       = $PSCmdlet.ParameterSetName
    DefenderScan   = $null
    StartupItems   = @()
    ScheduledTasks = @()
    NonMsServices   = @()
    HighCpuProcesses = @()
    HighRamProcesses = @()
    Errors         = @()
}

$txtLines = [System.Collections.Generic.List[string]]::new()
$txtLines.Add("Security Audit Report — $($report.GeneratedAt)")
$txtLines.Add("Computer : $($report.ComputerName)   User: $($report.UserName)")
$txtLines.Add("Scan mode: $($report.ScanMode)")
$txtLines.Add(('=' * 70))

# ---------------------------------------------------------------------------
# Section 1 — Microsoft Defender scan
# ---------------------------------------------------------------------------

function Invoke-DefenderScan {
    param(
        [ValidateSet('QuickScan','FullScan','PathScan')]
        [string]$ScanType,
        [string]$ScanPath = ''
    )

    # Locate MpCmdRun.exe
    $mpCmd = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmd)) {
        $mpCmd = "${env:ProgramFiles(x86)}\Windows Defender\MpCmdRun.exe"
    }
    if (-not (Test-Path $mpCmd)) {
        Write-Warning "MpCmdRun.exe not found. Defender scan skipped."
        return @{ Status = 'Skipped'; Reason = 'MpCmdRun.exe not found' }
    }

    $scanArgs = switch ($ScanType) {
        'QuickScan' { @('-Scan', '-ScanType', '1') }
        'FullScan'  { @('-Scan', '-ScanType', '2') }
        'PathScan'  { @('-Scan', '-ScanType', '3', '-File', $ScanPath) }
    }

    Write-Host "Running Defender $ScanType via: $mpCmd $scanArgs" -ForegroundColor Green

    try {
        $proc = Start-Process -FilePath $mpCmd -ArgumentList $scanArgs `
                              -Wait -PassThru -NoNewWindow
        return @{
            Status   = if ($proc.ExitCode -eq 0) { 'Clean' } else { 'SeeDefenderUI' }
            ExitCode = $proc.ExitCode
            Note     = 'Check Windows Security app for full threat details.'
        }
    }
    catch {
        return @{ Status = 'Error'; Message = $_.Exception.Message }
    }
}

Write-Header "Microsoft Defender Scan"

if ($PSCmdlet.ParameterSetName -ne 'ReportOnly') {
    $scanLabel = switch ($PSCmdlet.ParameterSetName) {
        'QuickScan' { 'a QUICK scan' }
        'FullScan'  { 'a FULL scan (this may take a long time)' }
        'PathScan'  { "a custom scan of: $PathScan" }
    }

    if (Confirm-Action "This will invoke Microsoft Defender to run $scanLabel.") {
        $defResult = switch ($PSCmdlet.ParameterSetName) {
            'QuickScan' { Invoke-DefenderScan -ScanType 'QuickScan' }
            'FullScan'  { Invoke-DefenderScan -ScanType 'FullScan' }
            'PathScan'  { Invoke-DefenderScan -ScanType 'PathScan' -ScanPath $PathScan }
        }
        $report.DefenderScan = $defResult
        $txtLines.Add("[Defender] Status: $($defResult.Status)  ExitCode: $($defResult.ExitCode)")
    }
    else {
        $report.DefenderScan = @{ Status = 'Skipped'; Reason = 'User declined' }
        $txtLines.Add("[Defender] Skipped by user.")
    }
}
else {
    $report.DefenderScan = @{ Status = 'Skipped'; Reason = 'ReportOnly mode' }
    $txtLines.Add("[Defender] Skipped (ReportOnly mode).")
}

# ---------------------------------------------------------------------------
# Section 2 — Startup items (Run keys + Startup folders)
# ---------------------------------------------------------------------------

Write-Header "Startup Items"

$startupItems = [System.Collections.Generic.List[object]]::new()

$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)

foreach ($key in $runKeys) {
    if (Test-Path $key) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            $props.PSObject.Properties |
                Where-Object { $_.Name -notlike 'PS*' } |
                ForEach-Object {
                    $item = [ordered]@{
                        Source = "Registry: $key"
                        Name   = $_.Name
                        Value  = $_.Value
                    }
                    $startupItems.Add($item)
                    $txtLines.Add("[Startup] $($_.Name)  =>  $($_.Value)  (from $key)")
                }
        }
        catch {
            $report.Errors += "Startup registry read failed for $key : $($_.Exception.Message)"
        }
    }
}

$startupFolders = @(
    [System.Environment]::GetFolderPath('Startup'),
    [System.Environment]::GetFolderPath('CommonStartup')
)

foreach ($folder in $startupFolders) {
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -ErrorAction SilentlyContinue |
            ForEach-Object {
                $item = [ordered]@{
                    Source = "Startup Folder: $folder"
                    Name   = $_.Name
                    Value  = $_.FullName
                }
                $startupItems.Add($item)
                $txtLines.Add("[Startup Folder] $($_.Name)  =>  $($_.FullName)")
            }
    }
}

$report.StartupItems = $startupItems
Write-Host "Found $($startupItems.Count) startup item(s)." -ForegroundColor White

# ---------------------------------------------------------------------------
# Section 3 — Scheduled tasks (non-Microsoft, enabled)
# ---------------------------------------------------------------------------

Write-Header "Scheduled Tasks (Non-Microsoft, Enabled)"

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop |
        Where-Object {
            $_.State -eq 'Ready' -and
            $_.TaskPath -notlike '\Microsoft\*'
        } |
        ForEach-Object {
            $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            [ordered]@{
                TaskName    = $_.TaskName
                TaskPath    = $_.TaskPath
                State       = $_.State
                LastRunTime = if ($info) { $info.LastRunTime } else { 'N/A' }
                NextRunTime = if ($info) { $info.NextRunTime } else { 'N/A' }
                Actions     = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' | '
            }
        }

    $report.ScheduledTasks = @($tasks)
    $tasks | ForEach-Object {
        $txtLines.Add("[Task] $($_.TaskPath)$($_.TaskName)  =>  $($_.Actions)")
    }
    Write-Host "Found $($report.ScheduledTasks.Count) non-Microsoft enabled scheduled task(s)." -ForegroundColor White
}
catch {
    $report.Errors += "Scheduled tasks read failed: $($_.Exception.Message)"
    Write-Warning "Could not read scheduled tasks: $_"
}

# ---------------------------------------------------------------------------
# Section 4 — Non-Microsoft services (running)
# ---------------------------------------------------------------------------

Write-Header "Running Non-Microsoft Services"

try {
    $services = Get-WmiObject Win32_Service -ErrorAction Stop |
        Where-Object { $_.State -eq 'Running' } |
        ForEach-Object {
            # Try to get the file publisher to identify Microsoft services
            $publisher = ''
            $exePath = ($_.PathName -replace '"', '') -split ' ' | Select-Object -First 1
            if ($exePath -and (Test-Path $exePath -ErrorAction SilentlyContinue)) {
                try {
                    $sig = Get-AuthenticodeSignature -FilePath $exePath -ErrorAction SilentlyContinue
                    $publisher = $sig.SignerCertificate.Subject
                }
                catch { }
            }
            $_ | Add-Member -NotePropertyName Publisher -NotePropertyValue $publisher -PassThru
        } |
        Where-Object { $_.Publisher -notlike '*Microsoft*' } |
        ForEach-Object {
            [ordered]@{
                Name      = $_.Name
                DisplayName = $_.DisplayName
                PathName  = $_.PathName
                Publisher = $_.Publisher
                StartMode = $_.StartMode
            }
        }

    $report.NonMsServices = @($services)
    $services | ForEach-Object {
        $txtLines.Add("[Service] $($_.DisplayName)  |  $($_.PathName)  |  Publisher: $($_.Publisher)")
    }
    Write-Host "Found $($report.NonMsServices.Count) running non-Microsoft service(s)." -ForegroundColor White
}
catch {
    $report.Errors += "Services read failed: $($_.Exception.Message)"
    Write-Warning "Could not read services: $_"
}

# ---------------------------------------------------------------------------
# Section 5 — High-resource processes
# ---------------------------------------------------------------------------

Write-Header "High-Resource Processes"

$cpuThreshold = 10    # % CPU (approximate via WMI)
$ramThresholdMB = 200 # MB working set

try {
    $allProcs = Get-Process -ErrorAction Stop

    # High CPU (use WMI for a snapshot figure)
    $wmiProcs = Get-WmiObject Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue

    $highCpu = @()
    if ($wmiProcs) {
        $highCpu = $wmiProcs |
            Where-Object { [int]$_.PercentProcessorTime -ge $cpuThreshold -and $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
            ForEach-Object {
                [ordered]@{
                    Name = $_.Name
                    PID  = $_.IDProcess
                    CpuPercent = $_.PercentProcessorTime
                }
            }
    }

    $highRam = $allProcs |
        Where-Object { $_.WorkingSet64 / 1MB -ge $ramThresholdMB } |
        Sort-Object WorkingSet64 -Descending |
        ForEach-Object {
            [ordered]@{
                Name      = $_.ProcessName
                PID       = $_.Id
                RamMB     = [math]::Round($_.WorkingSet64 / 1MB, 1)
                Path      = try { $_.Path } catch { 'N/A' }
            }
        }

    $report.HighCpuProcesses = @($highCpu)
    $report.HighRamProcesses = @($highRam)

    $highCpu | ForEach-Object { $txtLines.Add("[High CPU] $($_.Name) (PID $($_.PID))  CPU: $($_.CpuPercent)%") }
    $highRam | ForEach-Object { $txtLines.Add("[High RAM] $($_.Name) (PID $($_.PID))  RAM: $($_.RamMB) MB  Path: $($_.Path)") }

    Write-Host "High CPU processes (>=$cpuThreshold%): $($report.HighCpuProcesses.Count)" -ForegroundColor White
    Write-Host "High RAM processes (>=$($ramThresholdMB)MB): $($report.HighRamProcesses.Count)" -ForegroundColor White
}
catch {
    $report.Errors += "Process read failed: $($_.Exception.Message)"
    Write-Warning "Could not read processes: $_"
}

# ---------------------------------------------------------------------------
# Section 6 — Export reports
# ---------------------------------------------------------------------------

Write-Header "Exporting Report"

try {
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonReport -Encoding UTF8
    Write-Host "JSON report: $jsonReport" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to write JSON report: $_"
}

try {
    $txtLines | Set-Content -Path $txtReport -Encoding UTF8
    Write-Host "TXT  report: $txtReport" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to write TXT report: $_"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Header "Audit Complete"
Write-Host "Startup items  : $($report.StartupItems.Count)"  -ForegroundColor White
Write-Host "Scheduled tasks: $($report.ScheduledTasks.Count)" -ForegroundColor White
Write-Host "Services       : $($report.NonMsServices.Count)"  -ForegroundColor White
Write-Host "High RAM procs : $($report.HighRamProcesses.Count)" -ForegroundColor White
if ($report.Errors.Count -gt 0) {
    Write-Host "Errors         : $($report.Errors.Count) (see report for details)" -ForegroundColor Red
}
Write-Host ""
Write-Host "Reports saved to: $outputDir" -ForegroundColor Cyan
Write-Host "Open the .json or .txt file to review all findings." -ForegroundColor Cyan
