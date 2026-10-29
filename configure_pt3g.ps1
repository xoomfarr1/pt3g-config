<#
.SYNOPSIS
    Configure a PT3G (Porsche PIWIS 3 VCI) for use with MBTools / Vediamo.
.DESCRIPTION
    Automates the scriptable parts of PT3G + MBTools/Vediamo setup:
      - Detects installed J2534 pass-through devices from the registry
      - Warns if EDIC 11.26 is installed (incompatible with MBTools)
      - Backs up and patches Vediamo's slave.ini [PartJ] DeviceName
      - Verifies Vediamo install path and slave.ini location
    Run as Administrator. Hardware/driver installation steps are NOT automated
    (interactive installers) - see the printed checklist.
.NOTES
    Only Vediamo 4.x supports J2534. Vediamo 5 does NOT.
    PT3G brand matters: VXDIAG/genuine support J2534 passthru; VNCI does not.
#>

param(
    [string]$DeviceName = "",          # Override: force a specific J2534 device name
    [string]$VediamoDir = "",          # Override: Vediamo install dir
    [switch]$DryRun                    # Preview changes without writing
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [ERR]  $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# 1. Admin check
# ---------------------------------------------------------------------------
Write-Step "Checking privileges"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Err "This script must be run as Administrator."
    Write-Host "  Right-click PowerShell -> 'Run as Administrator', then re-run." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Running as Administrator"

# ---------------------------------------------------------------------------
# 2. Detect J2534 devices from registry
# ---------------------------------------------------------------------------
Write-Step "Detecting J2534 pass-through devices"
$regPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\PassThruSupport.04.04",
    "HKLM:\SOFTWARE\PassThruSupport.04.04"
)
$devices = @()
foreach ($rp in $regPaths) {
    if (Test-Path $rp) {
        Get-ChildItem $rp | ForEach-Object {
            $devices += $_.PSChildName
        }
    }
}
$devices = $devices | Sort-Object -Unique

if ($devices.Count -eq 0) {
    Write-Err "No J2534 devices found in registry."
    Write-Host "  Install the PT3G OEM driver (Actia PUD API) first, then re-run." -ForegroundColor Yellow
    Write-Host "  Expected registry path: HKLM\SOFTWARE\WOW6432Node\PassThruSupport.04.04" -ForegroundColor Yellow
} else {
    Write-Ok "Found $($devices.Count) J2534 device(s):"
    $devices | ForEach-Object { Write-Host "     - $_" }
}

# ---------------------------------------------------------------------------
# 3. EDIC check (MBTools incompatibility)
# ---------------------------------------------------------------------------
Write-Step "Checking EDIC version (MBTools compatibility)"
$edicKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$edicFound = $false
foreach ($k in $edicKeys) {
    $items = Get-ItemProperty $k -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match "EDIC" }
    foreach ($it in $items) {
        $edicFound = $true
        if ($it.DisplayName -match "11\.26") {
            Write-Err "EDIC 11.26 detected: $($it.DisplayName) - INCOMPATIBLE with MBTools"
            Write-Host "  Uninstall it from Control Panel, then re-run the MBTools driver installer." -ForegroundColor Yellow
        } else {
            Write-Ok "EDIC found: $($it.DisplayName) (likely compatible)"
        }
    }
}
if (-not $edicFound) {
    Write-Warn "No EDIC installation detected. MBTools J2534 route requires EDIC 1.20."
    Write-Host "  Run the MBTools Launcher -> select J2534 -> 'Set-up platform'." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. Resolve Vediamo directory
# ---------------------------------------------------------------------------
Write-Step "Locating Vediamo installation"
if (-not $VediamoDir) {
    $candidates = @(
        "C:\Program Files (x86)\Vediamo",
        "C:\Program Files\Vediamo"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $VediamoDir = $c; break }
    }
}
if (-not $VediamoDir -or -not (Test-Path $VediamoDir)) {
    Write-Warn "Vediamo not found in default locations."
    Write-Host "  Pass -VediamoDir 'C:\path\to\Vediamo' if installed elsewhere." -ForegroundColor Yellow
    $slavePath = $null
} else {
    Write-Ok "Vediamo found: $VediamoDir"
    $slavePath = Join-Path $VediamoDir "Caesar\driver\slave.ini"
    if (Test-Path $slavePath) {
        Write-Ok "slave.ini found: $slavePath"
    } else {
        Write-Warn "slave.ini not found at $slavePath"
        Write-Host "  (Vediamo 4.x required; 5.x does not support J2534)" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 5. Pick the device name
# ---------------------------------------------------------------------------
Write-Step "Selecting J2534 device name for slave.ini"
if ($DeviceName) {
    $chosen = $DeviceName
    Write-Ok "Using user-specified device: $chosen"
} elseif ($devices.Count -eq 1) {
    $chosen = $devices[0]
    Write-Ok "Auto-selected single device: $chosen"
} elseif ($devices.Count -gt 1) {
    Write-Host "  Multiple devices found. Pass -DeviceName '<exact name>' to choose." -ForegroundColor Yellow
    Write-Host "  Showing list again:" -ForegroundColor Yellow
    $devices | ForEach-Object { Write-Host "     - $_" }
    # Default to first PT3G-looking entry if any
    $pt3g = $devices | Where-Object { $_ -match "PT3G|Actia|Porsche" } | Select-Object -First 1
    if ($pt3g) {
        $chosen = $pt3g
        Write-Warn "Defaulting to PT3G-looking entry: $chosen"
    } else {
        $chosen = $devices[0]
        Write-Warn "Defaulting to first entry: $chosen"
    }
} else {
    $chosen = $null
}

# ---------------------------------------------------------------------------
# 6. Patch slave.ini
# ---------------------------------------------------------------------------
if ($slavePath -and (Test-Path $slavePath) -and $chosen) {
    Write-Step "Patching slave.ini [PartJ]"
    $backup = "$slavePath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (-not $DryRun) {
        Copy-Item $slavePath $backup -Force
        Write-Ok "Backup created: $backup"
    } else {
        Write-Host "  (DryRun) would back up to: $backup" -ForegroundColor Gray
    }

    $content = Get-Content $slavePath -Raw
    # Ensure [PartJ] section exists
    if ($content -notmatch "\[PartJ\]") {
        Write-Warn "[PartJ] section not found; appending it."
        $content += "`n[PartJ]`nPassThruVersion=`"04.04`"`nDeviceName=`"$chosen`"`n"
    } else {
        # Replace PassThruVersion line within [PartJ] block (best-effort regex)
        $content = $content -replace '(?ms)(\[PartJ\].*?PassThruVersion=)"[^"]*"', "`$1`"04.04`""
        # Replace DeviceName line within [PartJ] block
        $content = $content -replace '(?ms)(\[PartJ\].*?DeviceName=)"[^"]*"', "`$1`"$chosen`""
        # If DeviceName wasn't present in [PartJ], add it
        if ($content -notmatch '(?ms)\[PartJ\].*?DeviceName=') {
            $content = $content -replace '(\[PartJ\])', "`$1`nDeviceName=`"$chosen`""
        }
    }

    if ($DryRun) {
        Write-Host "  (DryRun) would write patched slave.ini. Preview of [PartJ]:" -ForegroundColor Gray
        ($content -split "`n") | Where-Object { $_ -match "PartJ|PassThruVersion|DeviceName" } | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    } else {
        # Write via temp file to avoid permission issues (copy-back pattern)
        $tmp = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmp -Value $content -NoNewline
        Copy-Item $tmp $slavePath -Force
        Remove-Item $tmp
        Write-Ok "slave.ini patched: DeviceName = `"$chosen`""
    }
} elseif (-not $chosen) {
    Write-Warn "No device name resolved; slave.ini not patched. Re-run with -DeviceName."
}

# ---------------------------------------------------------------------------
# 7. Summary / manual checklist
# ---------------------------------------------------------------------------
Write-Step "Manual steps still required (not scriptable)"
$checklist = @(
    "1. Confirm PT3G brand supports J2534 passthru (VXDIAG/genuine yes; VNCI no).",
    "2. Install PIWIS OEM driver (Actia PUD API) -> select module type PT3G-VCI (not 6154a).",
    "3. Verify serial number in PT3G Device Manager matches D-PDU API driver.",
    "4. MBTools: run Launcher -> select J2534 -> 'Set-up platform' (installs EDIC 1.20).",
    "5. Uninstall EDIC 11.26 if present (incompatible with MBTools).",
    "6. Connect PT3G to BOTH PC (USB) and car (OBD - it is OBD-powered).",
    "7. Only ONE app (MBTools/Vediamo/Xentry) may use the VCI at a time.",
    "8. Vediamo: launch -> Update -> select Part J only -> Update.",
    "9. Vediamo 4.x only (5.x does not support J2534)."
)
$checklist | ForEach-Object { Write-Host "  $_" }

Write-Host "`nDone." -ForegroundColor Cyan
if ($DryRun) { Write-Host "(DryRun mode - no files were changed)" -ForegroundColor Gray }