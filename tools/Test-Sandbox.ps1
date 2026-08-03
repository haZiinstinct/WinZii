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
$syncHash.Actions = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.DryRun = $false
# Cleanup ist für Measure-WzPathSet dabei, das der Dateiumzug zum Nachmessen braucht
foreach ($m in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Ui', 'Core.System', 'Core.Backup', 'Cleanup', 'Optimizer') {
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

# --- 6. Zurückspielen und Dateiumzug ---------------------------------------
# Genau hier gehören diese Prüfungen hin: Auf dem Entwicklungsrechner lässt
# sich weder ein Drucker anlegen noch ein WLAN-Profil einspielen, ohne echte
# Einstellungen zu verändern.
Schreib ''
Schreib '6. Zurückspielen (WLAN, Drucker, Lesezeichen) und Dateiumzug'
foreach ($m in 'UserData', 'Migration') { . (Join-Path $root "src\modules\$m.ps1") }

$backupDir = Join-Path $root "offline\daten\$env:COMPUTERNAME"
$wlanDir = Join-Path $backupDir 'wlan'
[void](New-Item -ItemType Directory -Path $wlanDir -Force)

# Ein Profil im netsh-Format, mit Schlüssel — der Wert ist erfunden.
$profileXml = @'
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>WinZii-Sandboxtest</name>
  <SSIDConfig><SSID><name>WinZii-Sandboxtest</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM><security>
    <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
    <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>SandboxTestNichtEcht</keyMaterial></sharedKey>
  </security></MSM>
</WLANProfile>
'@
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $wlanDir 'WLAN-Sandbox.xml'), $profileXml, $utf8)

# Geräteliste mit einem Drucker. Der Treibername kommt aus dem, was hier
# wirklich eingerichtet ist — geprüft werden soll der WinZii-Code, nicht welche
# Treiber Windows in dieser Ausgabe zufällig mitliefert. Die Sandbox hat zum
# Beispiel kein »Microsoft Print To PDF«.
$anyDriver = @(Get-PrinterDriver -ErrorAction SilentlyContinue)
Schreib "  Eingerichtete Druckertreiber: $($anyDriver.Count) — $((@($anyDriver | Select-Object -First 4).Name) -join ', ')"

# In der Sandbox gibt es nur Klassentreiber und den RDP-Umleitungstreiber.
# Beide hängen an erkannter Hardware beziehungsweise an einer Sitzung und lassen
# sich nicht für einen Drucker von Hand verwenden. Versucht wird trotzdem, einen
# echten aus dem Treiberspeicher zu holen — ob Add-Printer selbst gelingt, hängt
# danach allein an Windows und wird hier deshalb berichtet, nicht bewertet.
$driverName = ''
foreach ($candidate in 'Generic / Text Only', 'Microsoft Print To PDF', 'Microsoft XPS Document Writer v4') {
    try {
        Add-PrinterDriver -Name $candidate -ErrorAction Stop
        $driverName = $candidate
        Schreib "  Treiber »$candidate« aus dem Treiberspeicher eingerichtet"
        break
    } catch { }
}
if (-not $driverName) {
    $driverName = @($anyDriver)[0].Name
    Schreib "  Kein von Hand verwendbarer Treiber verfügbar — ersatzweise »$driverName«."
}

# Zwei Drucker, damit beide Zweige geprüft werden: ein Netzwerkanschluss, den
# WinZii selbst anlegen kann, und ein USB-Anschluss, den niemand anlegen kann.
$devices = [pscustomobject]@{
    computer  = $env:COMPUTERNAME
    erstellt  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    drucker   = @(
        [pscustomobject]@{
            name = 'WinZii-Testdrucker'; treiber = $driverName
            anschluss = '192.168.222.240'; standard = $false; netzwerk = $false
        }
        [pscustomobject]@{
            name = 'WinZii-USB-Drucker'; treiber = $driverName
            anschluss = 'USB001'; standard = $false; netzwerk = $false
        }
    )
    laufwerke = @()
}
[void](Save-WzJson -InputObject $devices -Path (Join-Path $backupDir 'geraete.json'))

$sources = @(Get-WzBackupSources)
Pruefe 'Sicherung wird gefunden' ($sources.Count -ge 1) "$($sources.Count) Quelle(n)"
if ($sources.Count -ge 1) {
    $contents = $sources[0].Contents
    Pruefe 'Eigene Sicherung erkannt' $sources[0].IsCurrent
    Pruefe 'WLAN-Profil gelesen' (@($contents.WlanFiles).Count -eq 1)
    Pruefe 'SSID aus der Datei' ((Get-WzWlanProfileName -Path @($contents.WlanFiles)[0]) -eq 'WinZii-Sandboxtest')
    Pruefe 'Schlüssel erkannt' (Test-WzWlanProfileHasKey -Path @($contents.WlanFiles)[0])

    # WLAN: In der Sandbox gibt es keinen Adapter. Geprüft wird deshalb nicht
    # der Erfolg, sondern dass der Fehlschlag sauber gemeldet wird.
    $wlan = Import-WzWlanProfiles -Files @($contents.WlanFiles)
    $wlanClean = (@($wlan.Applied).Count + @($wlan.Failed).Count) -eq 1
    Pruefe 'WLAN-Rückspielung meldet ein Ergebnis' $wlanClean `
        "angewandt=$(@($wlan.Applied).Count) fehlgeschlagen=$(@($wlan.Failed).Count)"

    # Drucker: Der Treiber ist eingerichtet, der Netzwerkdrucker muss entstehen.
    $printer = Import-WzPrinters -Printers @($contents.Printers)
    $printerOk = @($printer.Applied).Count -eq 1
    $bilanz = "angewandt=$(@($printer.Applied).Count) ohneTreiber=$(@($printer.MissingDriver).Count) ohneAnschluss=$(@($printer.MissingPort).Count) fehlgeschlagen=$(@($printer.Failed).Count)"
    # Bewusst nicht als Fehler gezählt: Ob Add-Printer gelingt, entscheidet der
    # Treiber, und die Sandbox bringt keinen mit, der sich von Hand verwenden
    # lässt. Eine rote Zeile ohne Aussagekraft macht den ganzen Bericht wertlos.
    Schreib "  [--]   Drucker anlegen (nur berichtet)              $bilanz"

    # Diese drei sind dagegen reine WinZii-Logik und müssen stimmen
    Pruefe 'USB-Anschluss ehrlich abgelehnt' (@($printer.MissingPort).Count -eq 1) ($printer.MissingPort -join '')
    Pruefe 'kein verwaister Anschluss nach Fehlschlag' `
        ($printerOk -or -not (Get-PrinterPort -Name '192.168.222.240' -ErrorAction SilentlyContinue))
    if ($printerOk) {
        Pruefe 'Drucker steht im System' ([bool](Get-Printer -Name 'WinZii-Testdrucker' -ErrorAction SilentlyContinue))
        # Zweiter Lauf: ein vorhandener Drucker darf nicht doppelt entstehen
        $again = Import-WzPrinters -Printers @($contents.Printers)
        Pruefe 'Zweiter Lauf legt nichts doppelt an' (@($again.Applied).Count -eq 0)
        Remove-Printer -Name 'WinZii-Testdrucker' -ErrorAction SilentlyContinue
        Remove-PrinterPort -Name '192.168.222.240' -ErrorAction SilentlyContinue
    }
}

# Dateiumzug: In der Sandbox gibt es nur C:, also greift die ehrliche Absage.
$volumes = @(Get-WzMigrationVolumes)
Pruefe 'Systemlaufwerk fällt als Ziel weg' ($volumes.Count -eq 0) "$($volumes.Count) Ziel(e)"

# robocopy selbst trotzdem prüfen — mit einem Ziel auf demselben Laufwerk
$moveSource = Join-Path $env:TEMP 'wz-umzug-quelle'
$moveTarget = Join-Path $env:TEMP 'wz-umzug-ziel'
[void](New-Item -ItemType Directory -Path (Join-Path $moveSource 'Unterordner') -Force)
[IO.File]::WriteAllText((Join-Path $moveSource 'a.txt'), 'eins', $utf8)
[IO.File]::WriteAllText((Join-Path $moveSource 'Unterordner\b.txt'), 'zwei', $utf8)
$job = [pscustomobject]@{
    Name = 'Testordner'; Source = $moveSource; Destination = $moveTarget; Bytes = 8; Items = 2
}
$move = Invoke-WzFileMigration -Jobs @($job)
Pruefe 'Dateiumzug kopiert' (@($move.Applied).Count -eq 1) ($move.Applied -join '')
Pruefe 'Unterordner mitgekommen' (Test-Path (Join-Path $moveTarget 'Unterordner\b.txt'))
Pruefe 'Quelle unangetastet' (Test-Path (Join-Path $moveSource 'a.txt'))

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
