# Läuft INNERHALB der Windows Sandbox (gestartet über Test-Sandbox.wsb) und
# prüft die Pfade, die sich auf dem Entwicklungsrechner nicht gefahrlos testen
# lassen: echte Eingriffe samt Rücknahme, den Start über den Launcher und die
# winget-Nachinstallation. Die Sandbox ist Wegwerf-Umgebung — hier darf
# wirklich verändert werden.
#
# Ergebnisse landen im eingebundenen Ordner unter sandbox-ergebnis\<Zeit>\,
# damit sie das Schließen der Sandbox überleben.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$resultDir = Join-Path $root "sandbox-ergebnis\$stamp"
[void](New-Item -ItemType Directory -Path $resultDir -Force)
$resultFile = Join-Path $resultDir 'ergebnis.txt'

$script:lines = @()
$script:failed = 0
function Schreib {
    param([string]$Text)
    $script:lines += $Text
    Write-Host $Text
    # Nach jeder Zeile sichern — falls die Sandbox mittendrin zugeht
    [IO.File]::WriteAllLines($resultFile, $script:lines)
}
function Pruefe {
    param([string]$Was, [bool]$Ok, [string]$Detail = '')
    $mark = if ($Ok) { '[ok]  ' } else { $script:failed++; '[FEHL]' }
    Schreib ("  {0} {1,-46} {2}" -f $mark, $Was, $Detail)
}

Schreib "WinZii Sandbox-Test — $stamp"
Schreib "Rechner: $env:COMPUTERNAME   Benutzer: $env:USERNAME"
Schreib ''

# --- 0. Umgebung -----------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Pruefe 'Administratorrechte in der Sandbox' $isAdmin
$build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
Schreib "  Windows-Build: $build"

# --- 1. Smoke-Test im fremden System --------------------------------------
Schreib ''
Schreib '1. Smoke-Test (Syntax, XAML, Kataloge, BOM)'
$smoke = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\Test-Smoke.ps1') 2>&1
$smokeText = $smoke -join "`n"
Pruefe 'Test-Smoke' ($smokeText -match 'keine Fehler') ($smoke | Select-Object -Last 1)

# --- 2. Start über den Launcher + Abbild ----------------------------------
Schreib ''
Schreib '2. Start über launcher.ps1 mit Abbild'
$env:WZ_SELFTEST = '2500'
$env:WZ_SELFTEST_PAGE = 'Dashboard'
$env:WZ_SELFTEST_OUT = Join-Path $resultDir 'sandbox-dashboard.png'
$start = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'src\launcher.ps1') 2>&1
Remove-Item Env:\WZ_SELFTEST, Env:\WZ_SELFTEST_PAGE, Env:\WZ_SELFTEST_OUT -ErrorAction SilentlyContinue
$startText = $start -join "`n"
Pruefe 'Fenster gerendert, Abbild gespeichert' (Test-Path (Join-Path $resultDir 'sandbox-dashboard.png'))
Pruefe 'keine Fehler beim Start' ($startText -notmatch 'wurde nicht als Name|Exception|fehlgeschlagen')

# --- 3. Module laden für die Modultests ------------------------------------
Schreib ''
Schreib '3. Echte Eingriffe: anwenden, prüfen, zurücknehmen'
Add-Type -AssemblyName PresentationFramework
$global:WzRootPath = $root
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.DryRun = $false
foreach ($m in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Ui', 'Core.System', 'Core.Backup', 'Optimizer') {
    . (Join-Path $root "src\modules\$m.ps1")
}
. (Join-Path $root 'src\version.ps1')
$syncHash.Version = $script:WzVersion
$syncHash.SystemInfo = [pscustomobject]@{ BuildNumber = $build }

# Zwei risikoarme Einträge, die nur Registry-Werte setzen
$catalog = Get-WzCatalog -Name 'tweaks'
$candidates = @($catalog.tweaks | Where-Object {
    $_.risk -eq 'low' -and
    (@($_.actions | Where-Object { $_.type -ne 'registry' }).Count -eq 0) -and
    ($_.appliesTo -eq 'all' -or ($_.appliesTo -eq 'win11' -and $build -ge 22000))
} | Select-Object -First 2)
Schreib "  Kandidaten: $(@($candidates | ForEach-Object { $_.id }) -join ', ')"

if ($candidates.Count -lt 1) {
    Pruefe 'Kandidaten gefunden' $false
} else {
    $summary = Invoke-WzTweaks -Tweaks $candidates -Scope 'sandbox-test'
    Pruefe 'Anwenden ohne Fehler' ($summary.Applied -eq $candidates.Count -and $summary.Failed -eq 0) "Applied=$($summary.Applied) Failed=$($summary.Failed)"
    Pruefe 'Undo-Datei geschrieben' ([bool]$summary.UndoFile -and (Test-Path $summary.UndoFile))

    # Gesetzte Werte nachlesen
    $valuesOk = $true
    foreach ($tweak in $candidates) {
        foreach ($action in $tweak.actions) {
            $current = Get-WzRegistryValue -Path $action.path -Name $action.name
            if ("$($current.Value)" -ne "$($action.value)") { $valuesOk = $false }
        }
    }
    Pruefe 'Registry-Werte stehen wie erwartet' $valuesOk

    # Und wieder zurück
    if ($summary.UndoFile) {
        $restore = Restore-WzUndoSession -UndoFile $summary.UndoFile
        Pruefe 'Rücknahme ohne Fehler' ($restore.Failed -eq 0) "Restored=$($restore.Restored) Skipped=$($restore.Skipped)"
    }
}

# --- 4. Netzwerk-Diagnose in der Sandbox-NAT-Umgebung ----------------------
Schreib ''
Schreib '4. Netzwerk-Diagnose'
. (Join-Path $root 'src\modules\NetworkDiag.ps1')
try {
    $diag = Invoke-WzNetworkDiagnosis
    foreach ($step in $diag.Steps) { Schreib ("    {0,-18} {1}  {2}" -f $step.Name, $step.Status, $step.Detail) }
    Pruefe 'Diagnose lief durch' ($null -ne $diag.Verdict) $diag.Verdict
} catch {
    Pruefe 'Diagnose lief durch' $false $_.Exception.Message
}

# --- 5. winget: Erkennung und Nachinstallation ------------------------------
Schreib ''
Schreib '5. winget-Nachinstallation (der nie getestete Pfad)'
. (Join-Path $root 'src\modules\Apps.ps1')
$wingetBefore = Test-WzWinget
Schreib "  winget vorher: Available=$($wingetBefore.Available)"
if ($wingetBefore.Available) {
    Pruefe 'Bootstrap' $true 'übersprungen — winget ist schon da'
} else {
    Schreib '  Starte Install-WzWingetBootstrap (lädt mehrere hundert MB — dauert)...'
    $bootstrapOk = $false
    try {
        $bootstrapOk = [bool](Install-WzWingetBootstrap)
    } catch {
        Schreib "  Ausnahme: $($_.Exception.Message)"
    }
    $wingetAfter = Test-WzWinget
    Pruefe 'winget nach Bootstrap vorhanden' $wingetAfter.Available "Version: $($wingetAfter.Version)"
    if (-not $wingetAfter.Available) {
        Schreib '  (In der Sandbox kann der Store-Unterbau fehlen — Befund zählt trotzdem.)'
    }
}

# --- Abschluss --------------------------------------------------------------
Schreib ''
Schreib "Protokollzeilen aus dem Modul-Teil:"
foreach ($e in @($syncHash.LogEntries.ToArray() | Select-Object -Last 25)) {
    Schreib "    [$($e.Level)] $($e.Message)"
}
Schreib ''
if ($script:failed -eq 0) {
    Schreib 'SANDBOX-TEST ABGESCHLOSSEN: alle Prüfungen bestanden.'
} else {
    Schreib "SANDBOX-TEST ABGESCHLOSSEN: $($script:failed) Prüfung(en) fehlgeschlagen."
}
Schreib 'Dieses Fenster kann geschlossen werden — die Sandbox darf zu.'
