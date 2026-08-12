# Dev-Werkzeug: prüft Sicherung und Rücknahme der Tweak-Engine.
#
# Angefasst wird ein eigener Schlüssel unter HKCU:\Software\WinZii-Selbsttest
# und eine Wegwerfdatei im TEMP-Ordner. Geprüft wird die Kette, auf die sich der
# Anwender verlässt:
#   Wert setzen -> .reg-Sicherung -> undo.json -> zurücknehmen -> Ausgangszustand.
# Dazu die Kommando-Aktionen: Fallback bei fehlender Voraussetzung und die
# Zustandsprüfung, die ohne Registrywert auskommen muss.
#
# Einzige Ausnahme ist Abschnitt 7: Er legt einen Energieplan mit eindeutigem
# Wegwerf-Namen an und aktiviert ihn kurz, weil sich der Undo-Pfad dafür nicht
# glaubwürdig trockentesten lässt. Der vorherige Plan wird vorab festgehalten
# und am Ende in jedem Fall wiederhergestellt, der Wegwerf-Plan gelöscht. Ohne
# Administratorrechte wird der Abschnitt übersprungen.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Undo.ps1
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

# --- 6. Kommando-Aktionen ---------------------------------------------------
# Ein Befehl hinterlässt keinen Registrywert, an dem man ablesen könnte, ob er
# gewirkt hat. Beide Mechanismen dafür werden hier geprüft, ohne eine echte
# Systemeinstellung anzufassen: Der Hauptbefehl gelingt nur, wenn eine Marke im
# TEMP-Ordner liegt, und angelegt wird sie vom Fallback.
Write-Host ''
Write-Host '6. Kommando-Aktionen: Fallback und Zustandsprüfung' -ForegroundColor White

$marke = Join-Path $env:TEMP 'winzii-selbsttest-marke.txt'
$prueft = "/c if exist `"$marke`" (exit 0) else (exit 1)"
if (Test-Path -LiteralPath $marke) { Remove-Item -LiteralPath $marke -Force }

$mitFallback = [pscustomobject]@{
    id             = 'selbsttest-fallback'
    name           = 'Selbsttest Fallback'
    requiresReboot = $false
    actions        = @(
        [pscustomobject]@{
            type     = 'command'
            exec     = 'cmd.exe'
            args     = $prueft
            fallback = [pscustomobject]@{ exec = 'cmd.exe'; args = "/c echo da> `"$marke`"" }
        }
    )
}
$fallbackSummary = Invoke-WzTweaks -Tweaks @($mitFallback) -Scope 'selbsttest-fallback'
Write-Check 'Fallback schafft die Voraussetzung' (Test-Path -LiteralPath $marke)
Write-Check 'zweiter Versuch gelingt' ($fallbackSummary.Applied -eq 1 -and $fallbackSummary.Failed -eq 0) "Applied=$($fallbackSummary.Applied) Failed=$($fallbackSummary.Failed)"

# Ohne Fallback muss ein fehlschlagender Befehl weiterhin fehlschlagen —
# sonst würde der neue Zweig echte Fehler verschlucken.
Remove-Item -LiteralPath $marke -Force -ErrorAction SilentlyContinue
$ohneFallback = [pscustomobject]@{
    id             = 'selbsttest-ohne-fallback'
    name           = 'Selbsttest ohne Fallback'
    requiresReboot = $false
    actions        = @(
        [pscustomobject]@{ type = 'command'; exec = 'cmd.exe'; args = $prueft; failHint = 'Voraussetzung fehlt.' }
    )
}
$ohneSummary = Invoke-WzTweaks -Tweaks @($ohneFallback) -Scope 'selbsttest-ohne-fallback'
Write-Check 'ohne Fallback bleibt es ein Fehlschlag' ($ohneSummary.Failed -eq 1) "Applied=$($ohneSummary.Applied) Failed=$($ohneSummary.Failed)"

Write-Check 'Zustand: Muster trifft' (Test-WzCommandState -State ([pscustomobject]@{
    exec = 'cmd.exe'; args = '/c echo zustand-aktiv'; pattern = 'zustand-aktiv' }))
Write-Check 'Zustand: Muster trifft nicht' (-not (Test-WzCommandState -State ([pscustomobject]@{
    exec = 'cmd.exe'; args = '/c echo etwas-anderes'; pattern = 'zustand-aktiv' })))

# Ohne Prüfvorschrift darf kein Zustand behauptet werden.
Clear-WzStateCache
$ohnePruefung = [pscustomobject]@{
    id      = 'selbsttest-ohne-state'
    actions = @([pscustomobject]@{ type = 'command'; exec = 'cmd.exe'; args = '/c exit 0' })
}
Write-Check 'ohne Prüfvorschrift bleibt der Zustand offen' ((Test-WzTweakState -Tweak $ohnePruefung) -eq 'Unknown')

Remove-Item -LiteralPath $marke -Force -ErrorAction SilentlyContinue

# --- 7. Energieplan-Aktion --------------------------------------------------
# Der einzige Abschnitt, der kurzzeitig eine echte Windows-Einstellung anfasst:
# Er legt einen Wegwerf-Plan mit eindeutigem Namen an, aktiviert ihn und nimmt
# beides über den Undo-Pfad zurück — genau die Kette, auf die sich der Techniker
# beim Zurücknehmen verlässt. Der vorherige Plan wird vorab festgehalten und am
# Ende in jedem Fall wiederhergestellt.
Write-Host ''
Write-Host '7. Energieplan: anlegen, aktivieren, zurücknehmen' -ForegroundColor White

# Der Name trägt bewusst denselben Geviertstrich wie der echte Katalogeintrag.
# Vorher stand hier ein reiner ASCII-Name — deshalb blieb unentdeckt, dass die
# Textausgabe von powercfg das Zeichen zu einem schlichten »-« verschluckt und
# die Wiedererkennung des Plans daran scheitert.
$planName = 'WinZii — Selbsttest-Wegwerfplan'
$guidMuster = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-WzTestSchemeCount {
    # Zählt über die Registry statt über »powercfg /list«: verlustfrei, und
    # ungefiltert — auf manchen Notebooks zeigt /list nur einen von sieben Plänen.
    param([string]$Name)
    $pfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    $treffer = 0
    foreach ($key in @(Get-ChildItem -LiteralPath $pfad -ErrorAction SilentlyContinue)) {
        $freundlich = (Get-ItemProperty -LiteralPath $key.PSPath -Name 'FriendlyName' `
            -ErrorAction SilentlyContinue).FriendlyName
        if ($freundlich -eq $Name) { $treffer++ }
    }
    return $treffer
}
$istAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

$planVorher = $null
$aktivAusgabe = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments '/getactivescheme' -TimeoutSeconds 30
if ($aktivAusgabe.ExitCode -eq 0 -and $aktivAusgabe.StdOut -match $guidMuster) { $planVorher = $Matches[0] }

if (-not $istAdmin) {
    Write-Host '  [--]   übersprungen: Energiepläne ändern verlangt Administratorrechte' -ForegroundColor DarkGray
} elseif (-not $planVorher) {
    Write-Host '  [--]   übersprungen: aktiver Energieplan nicht auslesbar' -ForegroundColor DarkGray
} else {
    $planTweak = [pscustomobject]@{
        id             = 'selbsttest-powerplan'
        name           = 'Selbsttest Energieplan'
        requiresReboot = $false
        actions        = @(
            [pscustomobject]@{
                type            = 'powerplan'
                planName        = $planName
                planDescription = 'Wegwerf-Plan des WinZii-Selbsttests.'
                baseScheme      = '381b4222-f694-41f0-9685-ff5bb260df2e'
                settings        = @(
                    [pscustomobject]@{ subgroup = 'SUB_PROCESSOR'; setting = 'PROCTHROTTLEMIN'; ac = 10; dc = 5 }
                )
            }
        )
    }

    # Testmodus zuerst — er darf nichts anlegen.
    $syncHash.DryRun = $true
    [void](Invoke-WzTweaks -Tweaks @($planTweak) -Scope 'selbsttest-plan-trocken')
    $syncHash.DryRun = $false
    Write-Check 'Testmodus legt keinen Plan an' ((Get-WzTestSchemeCount -Name $planName) -eq 0)

    $planLauf = Invoke-WzTweaks -Tweaks @($planTweak) -Scope 'selbsttest-plan'
    Write-Check 'Eintrag angewendet' ($planLauf.Applied -eq 1 -and $planLauf.Failed -eq 0) "Applied=$($planLauf.Applied) Failed=$($planLauf.Failed)"

    # Verglichen werden GUIDs, nicht Namen: In der Ausgabe von powercfg steht
    # statt des Geviertstrichs ein »-«, ein Textvergleich träfe nie zu.
    $planGuid = Find-WzPowerScheme -Name $planName
    Write-Check 'Plan ist eingetragen' ([bool]$planGuid) "GUID: $planGuid"

    $nachLauf = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments '/getactivescheme' -TimeoutSeconds 30
    Write-Check 'Plan ist aktiv' ($planGuid -and $nachLauf.StdOut -match [regex]::Escape($planGuid))

    # Zweiter Durchlauf darf keinen weiteren Plan anlegen — sonst wächst die
    # Planliste mit jedem Technikereinsatz.
    [void](Invoke-WzTweaks -Tweaks @($planTweak) -Scope 'selbsttest-plan-zweitlauf')
    $anzahl = Get-WzTestSchemeCount -Name $planName
    Write-Check 'zweiter Durchlauf legt keine Kopie an' ($anzahl -eq 1) "gefunden: $anzahl"

    if ($planLauf.UndoFile) {
        $planRestore = Restore-WzUndoSession -UndoFile $planLauf.UndoFile
        Write-Check 'Rücknahme meldet Erfolg' ($planRestore.Failed -eq 0) "Restored=$($planRestore.Restored) Failed=$($planRestore.Failed)"

        $nachUndo = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments '/getactivescheme' -TimeoutSeconds 30
        Write-Check 'vorheriger Plan wieder aktiv' ($nachUndo.StdOut -match [regex]::Escape($planVorher))

        Write-Check 'Wegwerf-Plan wurde entfernt' ((Get-WzTestSchemeCount -Name $planName) -eq 0)
    } else {
        Write-Check 'Sicherungsdatei geschrieben' $false 'keine undo.json'
    }

    # Sicherheitsnetz: Bricht oben etwas ab, bleibt weder ein fremder Plan aktiv
    # noch der Wegwerf-Plan liegen.
    [void](Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments "/setactive $planVorher" -TimeoutSeconds 30)
    # Begrenzt, damit ein Plan, der sich nicht löschen lässt, den Selbsttest
    # nicht in eine Endlosschleife schickt.
    for ($versuch = 0; $versuch -lt 5; $versuch++) {
        $uebrig = Find-WzPowerScheme -Name $planName
        if (-not $uebrig) { break }
        [void](Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments "/delete $uebrig" -TimeoutSeconds 30)
    }
}

# --- Aufräumen --------------------------------------------------------------
try { Remove-Item -LiteralPath $testKey -Recurse -Force -ErrorAction Stop } catch { }
$backupRoot = Get-WzBackupRoot
if (Test-Path -LiteralPath $backupRoot) {
    Get-ChildItem -LiteralPath $backupRoot -Directory -Filter '*-selbsttest*' -ErrorAction SilentlyContinue |
        ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { } }

    # Bleibt danach nichts übrig, verschwindet auch der Ordner mit dem
    # Rechnernamen — sonst hinterlässt jeder Testlauf auf einem sauberen Gerät
    # einen leeren Ordner. Entfernt wird ausschließlich, was wirklich leer ist:
    # echte Sicherungen bleiben unangetastet.
    if (-not (Get-ChildItem -LiteralPath $backupRoot -Force -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $backupRoot -Force -ErrorAction Stop } catch { }
    }
}

Write-Host ''
if ($script:failed -eq 0) {
    Write-Host '  Ergebnis: Sicherung und Rücknahme arbeiten wie versprochen.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $script:failed Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
