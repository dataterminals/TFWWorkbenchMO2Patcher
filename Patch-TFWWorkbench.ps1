<#
.SYNOPSIS
    Patches a stock TFWWorkbench install so it works under Mod Organizer 2.

.DESCRIPTION
    Applies two fixes to YOUR OWN copy of TFWWorkbench (smotti). Nothing is downloaded and no
    upstream code ships with this script.

      1. enabled.txt  - stock releases ship no marker and are absent from UE4SS's mods.txt, so
                        the mod never starts, with no error.
      2. ModChildDirs - emptied. Its only consumer, CreateModChildDirs(), builds the DataTable
                        tree via os.execute(), whose cmd.exe child access-violates under USVFS.
                        Every probe fails, so no mkdir is ever attempted: the table achieves
                        nothing except ~160 cmd.exe spawns per launch. Collection is unaffected
                        (main.lua iterates the real directory tree, not this table).

    FIX 2 REQUIRES the ForeverWinterMO2Support plugin (v0.2.0+), which pre-creates the DataTable
    tree in MO2's Overwrite before the game starts. Do NOT apply it to a non-MO2 install; use
    -EnabledTxtOnly there.

.PARAMETER Path
    Path to the TFWWorkbench mod folder (the one containing Scripts\ and dlls\).

.PARAMETER ModsPath
    An MO2 mods folder to search for TFWWorkbench instead of passing -Path.

.PARAMETER EnabledTxtOnly
    Apply only fix 1. Safe for non-MO2 installs.

.PARAMETER Revert
    Restore Settings.lua from the backup and remove enabled.txt.

.PARAMETER Force
    Proceed even if the file hashes are not a recognised release.

.EXAMPLE
    .\Patch-TFWWorkbench.ps1 -ModsPath "H:\MO2Instance_ModData\ForeverWinter\mods"
.EXAMPLE
    .\Patch-TFWWorkbench.ps1 -Path "...\ue4ss\Mods\TFWWorkbench" -Revert
#>
[CmdletBinding()]
param(
    [string]$Path,
    [string]$ModsPath,
    [switch]$EnabledTxtOnly,
    [switch]$Revert,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$BackupSuffix = '.stock.bak'

function Find-Workbench {
    param([string]$Root)
    $hit = Get-ChildItem -LiteralPath $Root -Recurse -Filter 'Settings.lua' -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '\\TFWWorkbench\\Scripts\\Settings\.lua$' } |
           Select-Object -First 1
    if ($hit) { return (Split-Path (Split-Path $hit.FullName -Parent) -Parent) }
    return $null
}

# --- resolve the mod folder -------------------------------------------------
if (-not $Path) {
    if (-not $ModsPath) { throw "Pass -Path <TFWWorkbench folder> or -ModsPath <MO2 mods folder>." }
    if (-not (Test-Path -LiteralPath $ModsPath)) { throw "No such folder: $ModsPath" }
    Write-Host "Searching $ModsPath ..." -ForegroundColor Cyan
    $Path = Find-Workbench -Root $ModsPath
    if (-not $Path) { throw "TFWWorkbench not found under $ModsPath" }
}
if (-not (Test-Path -LiteralPath $Path)) { throw "No such folder: $Path" }

$settings = Join-Path $Path 'Scripts\Settings.lua'
$enabled  = Join-Path $Path 'enabled.txt'
$backup   = "$settings$BackupSuffix"
if (-not (Test-Path -LiteralPath $settings)) { throw "Not a TFWWorkbench folder (no Scripts\Settings.lua): $Path" }
Write-Host "TFWWorkbench: $Path" -ForegroundColor Green

# --- revert -----------------------------------------------------------------
if ($Revert) {
    if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $settings -Force
        Remove-Item -LiteralPath $backup -Force
        Write-Host "  Settings.lua restored from backup." -ForegroundColor Green
    } else {
        Write-Warning "  No backup at $backup - Settings.lua left as-is."
    }
    if (Test-Path -LiteralPath $enabled) {
        Remove-Item -LiteralPath $enabled -Force
        Write-Host "  enabled.txt removed." -ForegroundColor Green
    }
    Write-Host "Reverted to stock." -ForegroundColor Cyan
    return
}

# --- identify the release ---------------------------------------------------
$known = $null
$hashFile = Join-Path $PSScriptRoot 'hashes.json'
if (Test-Path -LiteralPath $hashFile) {
    $db = Get-Content -LiteralPath $hashFile -Raw | ConvertFrom-Json
    # hash the STOCK settings if we already patched, so re-runs still identify correctly
    $probe = $settings
    if (Test-Path -LiteralPath $backup) { $probe = $backup }
    $sha = (Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLower()
    foreach ($rel in $db.releases) {
        if ($rel.files.'Scripts/Settings.lua'.sha256 -eq $sha) { $known = $rel.version; break }
    }
}
if ($known) {
    Write-Host "  Identified release: $known" -ForegroundColor Green
} else {
    $msg = "Unrecognised Settings.lua - not a release this script has been verified against."
    if (-not $Force) {
        Write-Warning $msg
        Write-Warning "ModChildDirs is the contract with the MO2 plugin: if a new release changes that"
        Write-Warning "list, the plugin's pre-created tree must change too. Re-read Settings.lua, then"
        Write-Warning "re-run with -Force if you are satisfied."
        throw "Refusing to patch an unverified build (use -Force to override)."
    }
    Write-Warning "$msg Proceeding because -Force was passed."
}

# --- fix 1: enabled.txt -----------------------------------------------------
if (Test-Path -LiteralPath $enabled) {
    Write-Host "  [1/2] enabled.txt already present - skipped." -ForegroundColor DarkGray
} else {
    [System.IO.File]::WriteAllBytes($enabled, @())
    Write-Host "  [1/2] enabled.txt created (0 bytes) - the mod will now start." -ForegroundColor Green
}

if ($EnabledTxtOnly) {
    Write-Host "-EnabledTxtOnly: leaving ModChildDirs alone. Done." -ForegroundColor Cyan
    return
}

# --- fix 2: empty ModChildDirs ---------------------------------------------
$text = Get-Content -LiteralPath $settings -Raw
if ($text -match '(?s)Settings\.ModChildDirs\s*=\s*\{\s*\}') {
    Write-Host "  [2/2] ModChildDirs already emptied - skipped." -ForegroundColor DarkGray
    Write-Host "Already patched. Nothing to do." -ForegroundColor Cyan
    return
}
if ($text -notmatch '(?s)Settings\.ModChildDirs\s*=\s*\{.*?\r?\n\}\r?\n') {
    throw "Could not locate the Settings.ModChildDirs block in $settings - aborting rather than guessing."
}

if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $settings -Destination $backup -Force
    Write-Host "  backed up stock Settings.lua -> $(Split-Path $backup -Leaf)" -ForegroundColor DarkGray
}

$replacement = @"
-- MO2 TWEAK (not upstream) - applied by TFWWorkbenchMO2Patcher. Emptied deliberately.
-- CreateModChildDirs() is the ONLY consumer of this table, and it cannot work under MO2: it
-- probes/creates each dir via os.execute(), whose cmd.exe child access-violates under USVFS
-- (0xC0000005). Every probe returns falsy, so no mkdir is ever attempted -- the table achieves
-- nothing here except ~160 cmd.exe spawns (20 handlers x 8 children) and ~60s of flashing
-- windows on every launch. The DataTable tree is instead pre-created in MO2's Overwrite by the
-- ForeverWinterMO2Support plugin, before the game process starts.
-- Collection is unaffected: main.lua iterates modDir.DataTable (the real, snapshotted directory
-- tree), never this table.
-- RESTORE THIS TABLE IF YOU EVER RUN TFWWorkbench OUTSIDE MO2 (or re-run with -Revert).
Settings.ModChildDirs = {}
"@

$patched = [regex]::Replace($text, '(?s)Settings\.ModChildDirs\s*=\s*\{.*?\r?\n\}\r?\n', ($replacement + "`n"), 1)
Set-Content -LiteralPath $settings -Value $patched -NoNewline -Encoding utf8
Write-Host "  [2/2] ModChildDirs emptied - ~160 cmd.exe spawns/launch removed." -ForegroundColor Green

Write-Host ""
Write-Host "Done. Requires ForeverWinterMO2Support v0.2.0+ to pre-create the DataTable tree." -ForegroundColor Cyan
Write-Host "Verify next launch: UE4SS.log should show 'has enabled.txt, starting mod' and" -ForegroundColor Cyan
Write-Host "'CollectData] Collecting data from ...\Content\Paks\Mods\TFWWorkbench\DataTable\<dir>'." -ForegroundColor Cyan
