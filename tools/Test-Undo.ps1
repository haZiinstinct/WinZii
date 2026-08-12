# Dev-Werkzeug: prüft Sicherung und Rücknahme der Tweak-Engine.
#
# Angefasst wird ausschließlich ein eigener Schlüssel unter
# HKCU:\Software\WinZii-Selbsttest — keine einzige Windows-Einstellung.
# Geprüft wird die Kette, auf die sich der Anwender verlässt:
#   Wert setzen -> .reg-Sicherung -> undo.json -> zurücknehmen -> Ausgangszustand.
#
# Aufruf:  powershell -NoProfile -File tools\Test-Undo.ps1
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot

$global:WzRootPath = $root
$global:WzSessionStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.DryRun = $false
. (Join-Path $root 'src\version.ps1')
$syncHash.Version = $script:WzVersion

foreach ($module in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Backup', 'Optimizer') {
    . (Join-Path $root "src\modules\$module.ps1")
}

$script:failed = 0
$testKey = 'HKCU:\Software\WinZii-Selbsttest'

function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-42} {2}" -f $symbol, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:failed++ }
}

Write-Host ''
Write-Host '  WinZii Sicherungs- und Rücknahmetest' -ForegroundColor Cyan
Write-Host ''

# --- 1. Pfadumschreibung für reg.exe ---------------------------------------
Write-Host '1. Pfadumschreibung für reg.exe' -ForegroundColor White

$pathCases = @(
    @{ In = 'HKLM:\SOFTWARE\Test';                                     Out = 'HKLM\SOFTWARE\Test' }
    @{ In = 'HKCU:\Software\Test';                                     Out = 'HKCU\Software\Test' }
    @{ In = 'HKCR:\.txt';                                              Out = 'HKCR\.txt' }
    # Der Fall aus dem Technikeralltag: Elevierung mit fremdem Konto. Diese
    # Schreibweise lieferte früher $null — es entstand gar keine Sicherung.
    @{ In = 'Registry::HKEY_USERS\S-1-5-21-1-2-3-1001\Software\Test';   Out = 'HKU\S-1-5-21-1-2-3-1001\Software\Test' }
    @{ In = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Test';               Out = 'HKLM\SOFTWARE\Test' }
    @{ In = 'Registry::HKEY_CURRENT_USER\Software\Test';                Out = 'HKCU\Software\Test' }
)
foreach ($case in $pathCases) {
    $got = ConvertTo-WzRegExePath $case.In
    Write-Check ($case.In -replace '\\.*', '\...') ($got -eq $case.Out) $got
}
Write-Check 'unbekannte Schreibweise liefert $null' ($null -eq (ConvertTo-WzRegExePath 'C:\kein\Registry-Pfad'))

# --- 2. Sitzungsobjekt ------------------------------------------------------
Write-Host ''
Write-Host '2. Sitzungsobjekt' -ForegroundColor White

$probe = New-WzUndoSession -Scope 'selbsttest-felder'
foreach ($field in 'Scope', 'Directory', 'Entries', 'ExportedKeys', 'ActionFailed', 'NeedsReboot') {
    Write-Check "Feld $field vorhanden" ($null -ne $probe.PSObject.Properties[$field])
}
# Beide Merker werden von Handlern gesetzt. Fehlte das Feld, flöge dort eine
# Ausnahme mitten im Eingriff — deshalb hier zuschreiben statt nur lesen.
$schreibenOk = $true
try { $probe.ActionFailed = $true; $probe.NeedsReboot = $true } catch { $schreibenOk = $false }
Write-Check 'Merker beschreibbar' ($schreibenOk -and $probe.NeedsReboot)
try { Remove-Item -LiteralPath $probe.Directory -Recurse -Force -ErrorAction Stop } catch { }

# --- 3. Anwenden, sichern, zurücknehmen -------------------------------------
Write-Host ''
Write-Host '3. Anwenden, sichern, zurücknehmen' -ForegroundColor White

# Ausgangslage: ein vorhandener Wert (muss zurückkehren) und ein neuer
# (muss verschwinden).
if (-not (Test-Path -LiteralPath $testKey)) { [void](New-Item -Path $testKey -Force) }
Set-ItemProperty -Path $testKey -Name 'Vorhanden' -Value 42 -Type DWord -Force

$tweak = [pscustomobject]@{
    id             = 'selbsttest'
    name           = 'Selbsttest — nur ein eigener Schlüssel'
    requiresReboot = $false
    actions        = @(
        [pscustomobject]@{ type = 'registry'; path = $testKey; name = 'Vorhanden'; valueType = 'DWord'; value = 7 }
        [pscustomobject]@{ type = 'registry'; path = $testKey; name = 'Neu';       valueType = 'DWord'; value = 1 }
    )
}

$summary = Invoke-WzTweaks -Tweaks @($tweak) -Scope 'selbsttest'
Write-Check 'ein Eintrag angewendet' ($summary.Applied -eq 1 -and $summary.Failed -eq 0) "Applied=$($summary.Applied) Failed=$($summary.Failed)"
Write-Check 'kein Neustart verlangt' (-not $summary.RebootRequired)

$nachher = Get-ItemProperty -LiteralPath $testKey
Write-Check 'Wert überschrieben' ($nachher.Vorhanden -eq 7) "Vorhanden=$($nachher.Vorhanden)"
Write-Check 'Wert neu angelegt' ($nachher.Neu -eq 1)

$undoFile = $summary.UndoFile
Write-Check 'undo.json geschrieben' ($undoFile -and (Test-Path -LiteralPath $undoFile)) $undoFile

$sessionDir = if ($undoFile) { Split-Path -Parent $undoFile } else { $null }
$regFiles = if ($sessionDir) { @(Get-ChildItem -LiteralPath $sessionDir -Filter '*.reg' -ErrorAction SilentlyContinue) } else { @() }
Write-Check '.reg-Sicherung angelegt' ($regFiles.Count -ge 1) ("{0} Datei(en)" -f $regFiles.Count)
if ($regFiles.Count -ge 1) {
    $regText = [IO.File]::ReadAllText($regFiles[0].FullName, [Text.Encoding]::Unicode)
    Write-Check '.reg enthält den Vorzustand' ($regText -match '(?i)"Vorhanden"=dword:0000002a')
}

if ($undoFile) {
    $undo = Read-WzJson -Path $undoFile
    Write-Check 'zwei Einträge in undo.json' (@($undo.entries).Count -eq 2) ("{0} Einträge" -f @($undo.entries).Count)
    $ersteter = @($undo.entries)[0]
    Write-Check 'Vorzustand festgehalten' ($ersteter.previous.existed -eq $true -and "$($ersteter.previous.value)" -eq '42')
    $zweiter = @($undo.entries)[1]
    Write-Check 'neuer Wert als »gab es nicht« vermerkt' ($zweiter.previous.existed -eq $false)

    $restore = Restore-WzUndoSession -UndoFile $undoFile
    Write-Check 'beide Änderungen zurückgenommen' ($restore.Restored -eq 2 -and $restore.Failed -eq 0) "Restored=$($restore.Restored) Failed=$($restore.Failed)"

    $zurueck = Get-ItemProperty -LiteralPath $testKey
    Write-Check 'alter Wert wieder da' ($zurueck.Vorhanden -eq 42) "Vorhanden=$($zurueck.Vorhanden)"
    Write-Check 'neuer Wert wieder weg' ($null -eq $zurueck.PSObject.Properties['Neu'])

    $undoDanach = Read-WzJson -Path $undoFile
    Write-Check 'Sicherung als erledigt vermerkt' ($null -ne $undoDanach.restoredAt)
}

# --- 4. Fehlschläge werden auch als solche gezählt --------------------------
Write-Host ''
Write-Host '4. Fehlschläge werden auch als solche gezählt' -ForegroundColor White

# Ein Pfad, den es nicht geben kann: New-Item scheitert, die Ausnahme muss
# durchschlagen. Früher zählte alles als »angewendet«, was keine Ausnahme warf.
$kaputt = [pscustomobject]@{
    id             = 'selbsttest-kaputt'
    name           = 'Selbsttest — unmöglicher Pfad'
    requiresReboot = $true
    actions        = @(
        [pscustomobject]@{ type = 'registry'; path = 'HKLM:\SOFTWARE\Classes\*\GibtEsNicht'; name = 'X'; valueType = 'DWord'; value = 1 }
    )
}
$kaputtSummary = Invoke-WzTweaks -Tweaks @($kaputt) -Scope 'selbsttest-kaputt'
Write-Check 'als Fehlschlag gezählt' ($kaputtSummary.Failed -eq 1 -and $kaputtSummary.Applied -eq 0) "Applied=$($kaputtSummary.Applied) Failed=$($kaputtSummary.Failed)"
Write-Check 'kein Neustart wegen eines Fehlschlags' (-not $kaputtSummary.RebootRequired)

# --- 5. Testmodus fasst nichts an -------------------------------------------
Write-Host ''
Write-Host '5. Testmodus fasst nichts an' -ForegroundColor White

$syncHash.DryRun = $true
$vorher = (Get-ItemProperty -LiteralPath $testKey).Vorhanden
$trocken = Invoke-WzTweaks -Tweaks @($tweak) -Scope 'selbsttest-trocken'
$syncHash.DryRun = $false
Write-Check 'Wert unverändert' ((Get-ItemProperty -LiteralPath $testKey).Vorhanden -eq $vorher)
Write-Check 'keine Sicherungsdatei' ($null -eq $trocken.UndoFile)

# --- Aufräumen --------------------------------------------------------------
try { Remove-Item -LiteralPath $testKey -Recurse -Force -ErrorAction Stop } catch { }
$backupRoot = Get-WzBackupRoot
if (Test-Path -LiteralPath $backupRoot) {
    Get-ChildItem -LiteralPath $backupRoot -Directory -Filter '*-selbsttest*' -ErrorAction SilentlyContinue |
        ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { } }
}

Write-Host ''
if ($script:failed -eq 0) {
    Write-Host '  Ergebnis: Sicherung und Rücknahme arbeiten wie versprochen.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $script:failed Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
