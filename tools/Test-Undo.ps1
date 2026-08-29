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
# Abschnitt 8 nimmt sich die Restesuche vor — die einzige Stelle in WinZii, die
# Ordner endgültig löscht. Erst die beiden Regelwerke, die davor stehen, dann
# die ganze Kette an einem Wegwerf-Programm, das der Abschnitt selbst anlegt.
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

foreach ($module in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Backup',
    'Optimizer', 'Core.System', 'Uninstall') {
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

# --- 8. Restesuche nach dem Deinstallieren ----------------------------------
# Hier wird endgültig gelöscht, deshalb steht vor dem Löschen zweimal dasselbe
# Regelwerk. Beide werden zuerst trocken durchgeprüft — auf Pfade, die es gibt,
# aber niemand anfassen darf. Erst danach läuft die Kette an einem Wegwerf-
# Programm, das dieser Abschnitt selbst anlegt.
Write-Host ''
Write-Host '8. Restesuche: Regeln, Fund und Rücknahme' -ForegroundColor White

# Die Wurzeln kommen aus derselben Quelle wie in der Prüfung selbst. Unter einem
# Technikerkonto zeigen $env:LOCALAPPDATA und Get-WzUserFolder auf verschiedene
# Profile — mit $env:… prüfte der Test etwas anderes als den Ernstfall.
$lokal = Get-WzUserFolder -Kind 'LocalAppData'
$programme = $env:ProgramFiles
$startmenue = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'

$pfadRegeln = @(
    @{ Pfad = $programme;                                          Erlaubt = $false; Was = 'Wurzel selbst' }
    @{ Pfad = 'C:\';                                               Erlaubt = $false; Was = 'Laufwerkswurzel' }
    @{ Pfad = 'C:\Windows\System32';                               Erlaubt = $false; Was = 'außerhalb der Wurzeln' }
    @{ Pfad = (Join-Path $programme 'Common Files');               Erlaubt = $false; Was = 'Sammelordner' }
    @{ Pfad = (Join-Path $programme 'WindowsApps\Wegwerf');        Erlaubt = $false; Was = 'Store-Apps, auch darunter' }
    @{ Pfad = (Join-Path $lokal 'Temp\Wegwerf');                   Erlaubt = $false; Was = 'Zwischenspeicher, auch darunter' }
    @{ Pfad = (Join-Path $lokal 'Programs');                       Erlaubt = $false; Was = 'Programs als Sammelordner' }
    @{ Pfad = (Join-Path $programme 'Wegwerfprogramm');            Erlaubt = $true;  Was = 'Programmordner' }
    @{ Pfad = (Join-Path $lokal 'Programs\Wegwerfprogramm');       Erlaubt = $true;  Was = 'Programm unter Programs' }
    @{ Pfad = (Join-Path $startmenue 'Wegwerfprogramm');           Erlaubt = $true;  Was = 'Startmenü-Eintrag' }
)
foreach ($regel in $pfadRegeln) {
    Write-Check "Ordner: $($regel.Was)" ((Test-WzLeftoverPathSafe -Path $regel.Pfad) -eq $regel.Erlaubt)
}

$keyRegeln = @(
    @{ Pfad = 'HKLM:\SOFTWARE';                                      Erlaubt = $false; Was = 'Zweig selbst' }
    @{ Pfad = 'HKLM:\SOFTWARE\WOW6432Node';                          Erlaubt = $false; Was = '32-Bit-Zweig selbst' }
    @{ Pfad = 'HKLM:\SYSTEM\CurrentControlSet\Services';             Erlaubt = $false; Was = 'außerhalb von SOFTWARE' }
    @{ Pfad = 'HKLM:\SOFTWARE\Wegwerfprogramm';                      Erlaubt = $true;  Was = 'Schlüssel unter SOFTWARE' }
    @{ Pfad = 'HKLM:\SOFTWARE\WOW6432Node\Wegwerfprogramm';          Erlaubt = $true;  Was = 'Schlüssel im 32-Bit-Zweig' }
    @{ Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Wegwerf'; Erlaubt = $true; Was = 'Deinstallationsschlüssel' }
    # Dieselben beiden Fälle in der Schreibweise, die unter fremdem Konto entsteht.
    @{ Pfad = 'Registry::HKEY_USERS\S-1-5-21-1-2-3-1001\SOFTWARE';   Erlaubt = $false; Was = 'fremdes Konto, Zweig selbst' }
    @{ Pfad = 'Registry::HKEY_USERS\S-1-5-21-1-2-3-1001\SOFTWARE\Wegwerf'; Erlaubt = $true; Was = 'fremdes Konto, Schlüssel' }
)
foreach ($regel in $keyRegeln) {
    Write-Check "Registry: $($regel.Was)" ((Test-WzLeftoverKeySafe -Path $regel.Pfad) -eq $regel.Erlaubt)
}

# Aus dem Anzeigenamen wird der Ordnername. Trifft er zu breit, räumt die Suche
# beim Nachbarprogramm auf.
$namensFaelle = @(
    @{ Name = 'Mozilla Firefox 128.0 (x64 de)'; Erwartet = 'Mozilla Firefox'; Was = 'Version und Klammer fallen weg' }
    @{ Name = 'VLC';                            Erwartet = $null;             Was = 'zu kurzer Name fällt raus' }
    @{ Name = 'C:\Unsinn';                      Erwartet = $null;             Was = 'Pfadzeichen fallen raus' }
)
foreach ($fall in $namensFaelle) {
    $kandidaten = @(Get-WzLeftoverNameCandidates -Program ([pscustomobject]@{ Name = $fall.Name }))
    $ok = if ($fall.Erwartet) { $kandidaten -contains $fall.Erwartet } else { $kandidaten.Count -eq 0 }
    Write-Check "Name: $($fall.Was)" $ok ($kandidaten -join ', ')
}

# Ein Wegwerf-Programm: ein Ordner mit Inhalt und ein eigener Schlüssel.
$restName = 'WinZii-Selbsttest-Restprogramm'
$restKey = "HKCU:\Software\$restName"
$restOrdner = Join-Path $lokal $restName

if (-not (Test-Path -LiteralPath $restKey)) { [void](New-Item -Path $restKey -Force) }
Set-ItemProperty -Path $restKey -Name 'DisplayName' -Value $restName -Force
[void](New-Item -Path $restOrdner -ItemType Directory -Force)
Set-Content -LiteralPath (Join-Path $restOrdner 'rest.txt') -Value 'Wegwerfdatei des Selbsttests'

# Ein Assistent, den der Techniker wegklickt, meldet mitunter trotzdem Erfolg.
# Steht der Eintrag danach noch in der Liste, ist nichts entfernt worden.
Write-Check 'noch eingetragen gilt als nicht entfernt' `
    (-not (Test-WzProgramGone -Program ([pscustomobject]@{ Name = $restName; RegistryPath = $restKey })))
Write-Check 'fehlender Schlüssel gilt als entfernt' `
    (Test-WzProgramGone -Program ([pscustomobject]@{ Name = $restName; RegistryPath = "$restKey-GibtEsNicht" }))
Write-Check 'ohne Schlüsselpfad gilt als entfernt' `
    (Test-WzProgramGone -Program ([pscustomobject]@{ Name = $restName; RegistryPath = '' }))

$restProgramm = [pscustomobject]@{
    Name            = $restName
    InstallLocation = $restOrdner
    RegistryPath    = $restKey
}
$funde = @(Find-WzUninstallLeftovers -Programs @($restProgramm))
$ordnerFunde = @($funde | Where-Object { $_.Kind -eq 'Ordner' })
$keyFunde = @($funde | Where-Object { $_.Kind -eq 'Registry' })

Write-Check 'Ordner gefunden, genau einmal' `
    ($ordnerFunde.Count -eq 1 -and $ordnerFunde[0].TargetPath -eq $restOrdner) ("{0} Fund(e)" -f $ordnerFunde.Count)
Write-Check 'Größe des Ordners ermittelt' ($ordnerFunde.Count -eq 1 -and $ordnerFunde[0].SizeBytes -gt 0)
Write-Check 'Schlüssel gefunden, genau einmal' ($keyFunde.Count -eq 1) ("{0} Fund(e)" -f $keyFunde.Count)

# Ein Programm ohne Reste darf auch keine melden — sonst stünde nach jeder
# Deinstallation ein Dialog mit fremden Ordnern darin.
$ohneReste = @(Find-WzUninstallLeftovers -Programs @([pscustomobject]@{
    Name = 'WinZii-Selbsttest-GibtEsNicht'; InstallLocation = ''; RegistryPath = '' }))
Write-Check 'ohne Reste bleibt die Liste leer' ($ohneReste.Count -eq 0) ("{0} Fund(e)" -f $ohneReste.Count)

# Der Fall vom Abnahmelaptop: Ein Hersteller trägt als Installationsordner den
# Sammelordner der ganzen Familie ein, und ein Nachbarprogramm wohnt darunter.
# Angeboten werden darf der Sammelordner dann nicht — das Löschen ist endgültig.
$sammelOrdner = Join-Path $lokal 'WinZii-Selbsttest-Sammelordner'
$nachbarOrdner = Join-Path $sammelOrdner 'Nachbarprogramm'
$nachbarKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinZii-Selbsttest-Nachbar'
[void](New-Item -Path $nachbarOrdner -ItemType Directory -Force)
Set-Content -LiteralPath (Join-Path $nachbarOrdner 'nachbar.txt') -Value 'Gehört dem Nachbarprogramm'
if (-not (Test-Path -LiteralPath $nachbarKey)) { [void](New-Item -Path $nachbarKey -Force) }
Set-ItemProperty -Path $nachbarKey -Name 'DisplayName' -Value 'WinZii-Selbsttest-Nachbarprogramm' -Force
Set-ItemProperty -Path $nachbarKey -Name 'UninstallString' -Value 'cmd.exe /c rem' -Force
Set-ItemProperty -Path $nachbarKey -Name 'InstallLocation' -Value $nachbarOrdner -Force

$sammelProgramm = [pscustomobject]@{
    Name            = 'WinZii-Selbsttest-Sammelprogramm'
    InstallLocation = $sammelOrdner
    RegistryPath    = ''
}
$sammelFunde = @(Find-WzUninstallLeftovers -Programs @($sammelProgramm))
Write-Check 'geteilter Ordner wird nicht angeboten' `
    (@($sammelFunde | Where-Object { $_.TargetPath -eq $sammelOrdner }).Count -eq 0) `
    ("{0} Fund(e)" -f $sammelFunde.Count)

# Und wenn er trotzdem in der Liste steht — aus einem älteren Lauf, aus einem
# Hintergrundlauf vor der Installation des Nachbarn —, muss ihn die Nachprüfung
# unmittelbar vor dem Löschen abweisen.
$sammelAbgewiesen = Remove-WzUninstallLeftovers -Leftovers @([pscustomobject]@{
    Kind = 'Ordner'; Path = $sammelOrdner; TargetPath = $sammelOrdner
    SizeBytes = 0; Program = $sammelProgramm.Name })
Write-Check 'geteilter Ordner wird vor dem Löschen abgewiesen' `
    ($sammelAbgewiesen.Removed -eq 0 -and $sammelAbgewiesen.Failed -eq 1) `
    "Removed=$($sammelAbgewiesen.Removed) Failed=$($sammelAbgewiesen.Failed)"
Write-Check 'Nachbarprogramm steht danach noch' (Test-Path -LiteralPath $nachbarOrdner)

# Der eigene Unterordner bleibt erlaubt, sonst wäre nach dieser Regel gar
# nichts mehr aufräumbar, was unter einem geteilten Ordner liegt.
$eigenerUnterordner = Join-Path $sammelOrdner 'WinZii-Selbsttest-Eigenprogramm'
[void](New-Item -Path $eigenerUnterordner -ItemType Directory -Force)
Set-Content -LiteralPath (Join-Path $eigenerUnterordner 'eigen.txt') -Value 'Wegwerfdatei'
$eigeneFunde = @(Find-WzUninstallLeftovers -Programs @([pscustomobject]@{
    Name            = 'WinZii-Selbsttest-Eigenprogramm'
    InstallLocation = $eigenerUnterordner
    RegistryPath    = '' }))
Write-Check 'eigener Unterordner bleibt auffindbar' `
    (@($eigeneFunde | Where-Object { $_.TargetPath -eq $eigenerUnterordner }).Count -eq 1) `
    ("{0} Fund(e)" -f $eigeneFunde.Count)

Remove-Item -LiteralPath $nachbarKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $sammelOrdner -Recurse -Force -ErrorAction SilentlyContinue

$syncHash.DryRun = $true
$trockenReste = Remove-WzUninstallLeftovers -Leftovers $funde
$syncHash.DryRun = $false
Write-Check 'Testmodus fasst nichts an' `
    ((Test-Path -LiteralPath $restOrdner) -and (Test-Path -LiteralPath $restKey))
Write-Check 'Testmodus legt keine Sicherung an' ($null -eq $trockenReste.UndoFile)

# Zwischen Suchen und Bestätigen liegt ein Dialog. Was danach gelöscht wird,
# muss noch einmal durch dasselbe Regelwerk — hier mit einem Ordner, den es
# wirklich gibt, der aber gesperrt ist.
$verboten = Join-Path $lokal 'Temp\winzii-selbsttest-verboten'
[void](New-Item -Path $verboten -ItemType Directory -Force)
$abgewiesen = Remove-WzUninstallLeftovers -Leftovers @([pscustomobject]@{
    Kind = 'Ordner'; Path = $verboten; TargetPath = $verboten; SizeBytes = 0; Program = 'Selbsttest' })
Write-Check 'gesperrter Ordner wird abgewiesen' `
    ($abgewiesen.Removed -eq 0 -and $abgewiesen.Failed -eq 1) "Removed=$($abgewiesen.Removed) Failed=$($abgewiesen.Failed)"
Write-Check 'gesperrter Ordner steht danach noch' (Test-Path -LiteralPath $verboten)
Remove-Item -LiteralPath $verboten -Recurse -Force -ErrorAction SilentlyContinue

$restLauf = Remove-WzUninstallLeftovers -Leftovers $funde
Write-Check 'beide Reste entfernt' `
    ($restLauf.Removed -eq 2 -and $restLauf.Failed -eq 0) "Removed=$($restLauf.Removed) Failed=$($restLauf.Failed)"
Write-Check 'Ordner ist weg' (-not (Test-Path -LiteralPath $restOrdner))
Write-Check 'Schlüssel ist weg' (-not (Test-Path -LiteralPath $restKey))
Write-Check 'freigewordener Platz gezählt' ($restLauf.Bytes -gt 0) ("{0} Byte" -f $restLauf.Bytes)

Write-Check 'undo.json geschrieben' ($restLauf.UndoFile -and (Test-Path -LiteralPath $restLauf.UndoFile)) $restLauf.UndoFile
if ($restLauf.UndoFile) {
    $restSession = Split-Path -Parent $restLauf.UndoFile
    $restRegDateien = @(Get-ChildItem -LiteralPath $restSession -Filter '*.reg' -ErrorAction SilentlyContinue)
    Write-Check '.reg-Sicherung des Schlüssels' ($restRegDateien.Count -ge 1) ("{0} Datei(en)" -f $restRegDateien.Count)
    if ($restRegDateien.Count -ge 1) {
        $restText = [IO.File]::ReadAllText($restRegDateien[0].FullName, [Text.Encoding]::Unicode)
        Write-Check '.reg enthält den Schlüssel' ($restText -match [regex]::Escape($restName))
    }

    $restManifest = Read-WzJson -Path $restLauf.UndoFile
    $restEintraege = @($restManifest.entries)
    Write-Check 'Sicherung nennt die entfernten Pfade' `
        ($restEintraege.Count -eq 1 -and @($restEintraege[0].previous.paths).Count -eq 2) ("{0} Pfad(e)" -f @($restEintraege[0].previous.paths).Count)

    try { Remove-Item -LiteralPath $restSession -Recurse -Force -ErrorAction Stop } catch { }
}

# --- Aufräumen --------------------------------------------------------------
# Sicherheitsnetz: Bricht Abschnitt 8 mittendrin ab, bleibt weder der
# Wegwerf-Ordner noch der Schlüssel liegen.
foreach ($rest in @($restOrdner, $verboten, $sammelOrdner)) {
    if ($rest -and (Test-Path -LiteralPath $rest)) {
        try { Remove-Item -LiteralPath $rest -Recurse -Force -ErrorAction Stop } catch { }
    }
}
foreach ($schluessel in @($restKey, $nachbarKey)) {
    if ($schluessel -and (Test-Path -LiteralPath $schluessel)) {
        try { Remove-Item -LiteralPath $schluessel -Recurse -Force -ErrorAction Stop } catch { }
    }
}
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
