# Dev-Werkzeug: funktionale Prüfung der Module, die bisher nur »Seite lädt«
# kannten — Setup, WindowsUpdate, Toolbox, AiRemoval, Autostart, HealthCheck,
# Snapshot und Core.Version (Audit 2026-10, Testabdeckung je Modul).
#
# Geprüft wird die Logik zwischen Windows und Oberfläche: Validierung,
# Code-Deutung, Mustersuche, Vergleich. Was ins System schreibt, wird hier
# nicht ausgelöst; wo eine Funktion Windows fragt, steht eine Attrappe davor.
# Einzige Ausnahme ist ein eigener Schlüssel unter HKCU\Software\WinZiiTest,
# der am Ende wieder verschwindet.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Modules.ps1
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
$global:WzRootPath = $root
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.DryRun = $false
$syncHash.Language = 'de'

foreach ($modul in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.I18n', 'Core.Version', 'Core.Palette',
    'Report', 'AiRemoval', 'Toolbox', 'Autostart', 'HealthCheck', 'Snapshot', 'Drivers') {
    . (Join-Path $root "src\modules\$modul.ps1")
}
[void](Import-WzLanguage)

$script:fehler = 0
function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $farbe = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-50} {2}" -f $symbol, $Name, $Detail) -ForegroundColor $farbe
    if (-not $Ok) { $script:fehler++ }
}

Write-Host ''
Write-Host '  WinZii Modulprüfung' -ForegroundColor Cyan
Write-Host ''

# --- Core.Version ------------------------------------------------------------
Write-Host '1. Versionsvergleich (Core.Version)' -ForegroundColor White
$faelle = @(
    @{ Ist = '0.9.0';  Neu = '0.10.0'; Soll = $true;  Was = '0.10.0 ist neuer als 0.9.0' }
    @{ Ist = '0.7.0';  Neu = '0.7.0';  Soll = $false; Was = 'gleiche Fassung ist nicht neuer' }
    @{ Ist = '0.8.0';  Neu = '0.7.9';  Soll = $false; Was = 'ältere Fassung ist nicht neuer' }
    @{ Ist = '0.7.0';  Neu = 'kaputt'; Soll = $false; Was = 'unlesbare Fassung ist nicht neuer' }
    @{ Ist = '';       Neu = '1.0.0';  Soll = $false; Was = 'ohne eigene Fassung keine Meldung' }
    @{ Ist = '0.7.0';  Neu = '';       Soll = $false; Was = 'ohne Antwort keine Meldung' }
)
foreach ($fall in $faelle) {
    $ist = Test-WzVersionNewer -Current $fall.Ist -Candidate $fall.Neu
    Write-Check $fall.Was ($ist -eq $fall.Soll) "'$($fall.Ist)' → '$($fall.Neu)': $ist"
}

# --- Kommandopalette (Mehrwort-Suche) ---------------------------------------
Write-Host ''
Write-Host '2. Kommandopalette (Core.Palette)' -ForegroundColor White
$palEntries = @(
    [pscustomobject]@{ Title = 'Optimierung'; Detail = 'Telemetrie Edge Dienste Datenschutz' }
    [pscustomobject]@{ Title = 'Reparatur';   Detail = 'Netzwerk DNS Drucker Spooler' }
    [pscustomobject]@{ Title = 'Dashboard';   Detail = 'System Hardware Übersicht' }
)
$treffer = @(Select-WzPaletteMatches -Entries $palEntries -Query 'edge tele')
Write-Check 'Mehrwort-Suche findet Optimierung' ($treffer.Count -eq 1 -and $treffer[0].Title -eq 'Optimierung')
$trefferPrefix = @(Select-WzPaletteMatches -Entries $palEntries -Query 'dash')
Write-Check 'Präfix-Treffer steht vorn' ($trefferPrefix.Count -eq 1 -and $trefferPrefix[0].Title -eq 'Dashboard')

# --- Systemempfehlungen (kein SSD-Fehlalarm bei Unspecified) -----------------
Write-Host ''
Write-Host '3. Systemempfehlungen (Report)' -ForegroundColor White
$dummyInfo = [pscustomobject]@{ PendingReboot = $null; Volumes = @(); IsLaptop = $false; RamTotalBytes = 16GB; RamSlots = 2; RamSlotsUsed = 2 }
$secUnspec = [pscustomobject]@{ DefenderOk = $true; ActivationOk = $true; BitLockerOn = $true; PhysicalDisks = @([pscustomobject]@{ Model = 'NVMe RAID'; MediaType = 'Unspecified'; Health = 'Healthy' }) }
$secHdd    = [pscustomobject]@{ DefenderOk = $true; ActivationOk = $true; BitLockerOn = $true; PhysicalDisks = @([pscustomobject]@{ Model = 'WD Blue'; MediaType = 'HDD'; Health = 'Healthy' }) }
$recUnspec = @(Get-WzSystemRecommendations -Info $dummyInfo -Security $secUnspec -Actions @())
$recHdd    = @(Get-WzSystemRecommendations -Info $dummyInfo -Security $secHdd -Actions @())
Write-Check 'Unspecified-Datenträger löst keinen SSD-Alarm aus' ($recUnspec.Count -eq 0) "Hinweise: $($recUnspec.Count)"
Write-Check 'HDD ohne SSD löst SSD-Empfehlung aus' ($recHdd.Count -eq 1) "Hinweise: $($recHdd.Count)"

# --- AiRemoval und Toolbox: Paketsuche ----------------------------------------
Write-Host ''
Write-Host '4. App-Pakete finden (AiRemoval, Toolbox)' -ForegroundColor White
# Statt Get-AppxPackage eine feste Liste im Zwischenspeicher
$script:WzAppxCache = @(
    [pscustomobject]@{ Name = 'Microsoft.Copilot'; PackageFullName = 'Microsoft.Copilot_1.0_x64__8wekyb3d8bbwe' }
    [pscustomobject]@{ Name = 'Microsoft.BingNews'; PackageFullName = 'Microsoft.BingNews_1.0_x64__8wekyb3d8bbwe' }
    [pscustomobject]@{ Name = 'Microsoft.XboxApp'; PackageFullName = 'Microsoft.XboxApp_1.0_x64__8wekyb3d8bbwe' }
    [pscustomobject]@{ Name = 'Microsoft.WindowsCalculator'; PackageFullName = 'Microsoft.WindowsCalculator_1.0_x64__8wekyb3d8bbwe' }
)
$treffer = @(Get-WzAppxMatches -Patterns @('Microsoft.Copilot*', 'Microsoft.Windows.Ai.*'))
Write-Check 'Muster findet genau das Paket' ($treffer.Count -eq 1 -and $treffer[0].Name -eq 'Microsoft.Copilot') "$($treffer.Count) Treffer"
$treffer = @(Get-WzAppxMatches -Patterns @('Microsoft.Copilot*', 'Microsoft.*Copilot*'))
Write-Check 'zwei passende Muster, ein Treffer' ($treffer.Count -eq 1)
$treffer = @(Get-WzAppxMatches -Patterns @('Nichts.*'))
Write-Check 'kein Treffer ist eine leere Liste' ($treffer.Count -eq 0)

$sicher = @(Get-WzBloatwareList -Level 'safe')
$erweitert = @(Get-WzBloatwareList -Level 'extended')
Write-Check 'Taschenrechner ist nie Ballast' (@($erweitert | Where-Object { $_.Name -eq 'Microsoft.WindowsCalculator' }).Count -eq 0)
Write-Check 'erweitert umfasst unstrittig' ($erweitert.Count -ge $sicher.Count) "$($sicher.Count) / $($erweitert.Count)"
Write-Check 'Treffer tragen Anzeigenamen und Paketnamen' (@($erweitert | Where-Object { -not $_.DisplayName -or -not $_.FullName }).Count -eq 0)
$script:WzAppxCache = $null

# DNS-Sicherung im Testmodus: liest, schreibt aber nichts
$syncHash.DryRun = $true
$dns = Save-WzDnsState
Write-Check 'DNS-Sicherung schreibt im Testmodus nichts' ($dns -eq '')
$syncHash.DryRun = $false

# --- Autostart ---------------------------------------------------------------
Write-Host ''
Write-Host '5. Autostart: Schaltbyte und Herausgeber' -ForegroundColor White
$testKey = 'HKCU:\Software\WinZiiTest\StartupApproved'
try {
    [void](New-Item -Path $testKey -Force)
    New-ItemProperty -Path $testKey -Name 'An' -PropertyType Binary -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Force | Out-Null
    New-ItemProperty -Path $testKey -Name 'Aus' -PropertyType Binary -Value ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Force | Out-Null
    Write-Check 'gerades Byte ist eingeschaltet' (Test-WzStartupApproved -ApprovedPath $testKey -Name 'An')
    Write-Check 'ungerades Byte ist ausgeschaltet' (-not (Test-WzStartupApproved -ApprovedPath $testKey -Name 'Aus'))
    Write-Check 'ohne Eintrag eingeschaltet' (Test-WzStartupApproved -ApprovedPath $testKey -Name 'Fehlt')
    Write-Check 'ohne Schlüssel eingeschaltet' (Test-WzStartupApproved -ApprovedPath 'HKCU:\Software\WinZiiTest\Gibtsnicht' -Name 'An')
} finally {
    Remove-Item -Path 'HKCU:\Software\WinZiiTest' -Recurse -Force -ErrorAction SilentlyContinue
}

$notepad = Join-Path $env:windir 'System32\notepad.exe'
$mitLeer = Join-Path $env:TEMP 'WinZii Test Ordner'
[void](New-Item -ItemType Directory -Path $mitLeer -Force)
try {
    Copy-Item -LiteralPath $notepad -Destination $mitLeer -Force
    $kopie = Join-Path $mitLeer 'notepad.exe'
    $erwartet = (Get-Item -LiteralPath $notepad).VersionInfo.CompanyName
    $faelle = @(
        @{ Befehl = "`"$kopie`" /x";                Was = 'Pfad in Anführungszeichen mit Argument' }
        @{ Befehl = "$kopie /x";                    Was = 'Pfad mit Leerzeichen ohne Anführungszeichen' }
        @{ Befehl = '%windir%\System32\notepad.exe'; Was = 'Umgebungsvariable im Pfad' }
    )
    foreach ($fall in $faelle) {
        $ist = Get-WzFilePublisher -Command $fall.Befehl
        Write-Check $fall.Was ($ist -and $ist -eq $erwartet) $ist
    }
    Write-Check 'fehlende Datei liefert leer' ((Get-WzFilePublisher -Command 'C:\gibtsnicht\x.exe') -eq '')
    Write-Check 'leerer Befehl liefert leer' ((Get-WzFilePublisher -Command '') -eq '')
} finally {
    Remove-Item -LiteralPath $mitLeer -Recurse -Force -ErrorAction SilentlyContinue
}

# --- HealthCheck -------------------------------------------------------------
Write-Host ''
Write-Host '6. Messwerte (HealthCheck)' -ForegroundColor White
$takt = Get-WzCpuClock
Write-Check 'Höchsttakt gemessen' ($takt.MaxMhz -gt 0) "$($takt.CurrentMhz) / $($takt.MaxMhz) MHz"
Write-Check 'Last zwischen 0 und 100' ($takt.LoadPercent -ge 0 -and $takt.LoadPercent -le 100) "$($takt.LoadPercent) %"
$zonen = @(Get-WzTemperatures)
# Viele Geräte und jede VM melden nichts — das ist erlaubt, eine erfundene Zahl nicht.
Write-Check 'Temperaturen nur im plausiblen Bereich' (@($zonen | Where-Object { $_.Celsius -le 0 -or $_.Celsius -gt 150 }).Count -eq 0) "$($zonen.Count) Zone(n)"

# --- Snapshot ----------------------------------------------------------------
Write-Host ''
Write-Host '7. Vergleich zweier Besuche (Snapshot)' -ForegroundColor White
# Gespeicherter und jetziger Zustand als Attrappen — so lässt sich jeder Zweig
# des Vergleichs gezielt treffen, ohne den Rechner zu vermessen.
function Get-WzSavedSnapshot { return $script:alt }
function New-WzSnapshot { return $script:neu }
$script:alt = $null
$vergleich = Compare-WzSnapshot
Write-Check 'ohne Momentaufnahme nichts zu vergleichen' (-not $vergleich.HasSnapshot)

$script:alt = [pscustomobject]@{
    created   = '2026-09-01T10:00:00.0000000+02:00'
    programs  = @(
        [pscustomobject]@{ name = 'Firefox'; version = '130.0' }
        [pscustomobject]@{ name = 'Alt-Programm'; version = '1.0' }
        [pscustomobject]@{ name = '7-Zip'; version = '24.08' }
    )
    autostart = @('OneDrive')
    tweaks    = @('telemetry-off', 'ads-off')
    volumes   = @([pscustomobject]@{ letter = 'C'; freeBytes = 50GB })
}
$script:neu = [pscustomobject]@{
    created   = (Get-Date).ToString('o')
    programs  = @(
        [pscustomobject]@{ name = 'Firefox'; version = '131.0' }
        [pscustomobject]@{ name = '7-Zip'; version = '24.08' }
        [pscustomobject]@{ name = 'Neu-Programm'; version = '2.0' }
    )
    autostart = @('OneDrive', 'Updater')
    tweaks    = @('ads-off', 'bing-off')
    volumes   = @([pscustomobject]@{ letter = 'C'; freeBytes = 40GB }, [pscustomobject]@{ letter = 'D'; freeBytes = 1GB })
}
$vergleich = Compare-WzSnapshot
Write-Check 'Momentaufnahme erkannt, Datum gelesen' ($vergleich.HasSnapshot -and $vergleich.Since -is [datetime])
Write-Check 'neues Programm' (@($vergleich.AddedPrograms) -join ',' -eq 'Neu-Programm') (@($vergleich.AddedPrograms) -join ',')
Write-Check 'entferntes Programm' (@($vergleich.RemovedPrograms) -join ',' -eq 'Alt-Programm') (@($vergleich.RemovedPrograms) -join ',')
Write-Check 'aktualisiertes Programm, gleiches nicht' (@($vergleich.UpdatedPrograms).Count -eq 1 -and $vergleich.UpdatedPrograms[0] -match 'Firefox') (@($vergleich.UpdatedPrograms) -join ',')
Write-Check 'neuer Autostart' (@($vergleich.AddedAutostart) -join ',' -eq 'Updater')
Write-Check 'zurückgedrehte Optimierung' (@($vergleich.LostTweaks) -join ',' -eq 'telemetry-off')
Write-Check 'neue Optimierung' (@($vergleich.NewTweaks) -join ',' -eq 'bing-off')
$c = @($vergleich.SpaceChange | Where-Object { $_.Letter -eq 'C' })
Write-Check 'Platzänderung je Laufwerk' ($c.Count -eq 1 -and $c[0].Bytes -eq -10GB) "$($c[0].Bytes)"
Write-Check 'neues Laufwerk ohne Vergleichswert' (@($vergleich.SpaceChange | Where-Object { $_.Letter -eq 'D' }).Count -eq 0)

# --- Drivers: Rückgabewerte der Herstellerwerkzeuge --------------------------
Write-Host ''
Write-Host '8. Rückgabewerte der Herstellerwerkzeuge (Drivers)' -ForegroundColor White
$werkzeuge = @{}
foreach ($t in (Get-WzCatalog -Name 'oemtools').tools) { $werkzeuge[$t.id] = $t }
$faelle = @(
    @{ Id = 'dell';   Code = 0;    Soll = 'ok' }
    @{ Id = 'dell';   Code = 1;    Soll = 'reboot'; Was = 'Dell 1 ist Erfolg mit Neustart' }
    @{ Id = 'dell';   Code = 500;  Soll = 'skip';   Was = 'Dell 500 ist »nichts zu tun«' }
    @{ Id = 'dell';   Code = 5;    Soll = 'retry' }
    @{ Id = 'dell';   Code = 2;    Soll = 'fail' }
    @{ Id = 'lenovo'; Code = 3010; Soll = 'reboot' }
    @{ Id = 'hp';     Code = 256;  Soll = 'skip' }
    @{ Id = 'hp';     Code = 3020; Soll = 'fail';   Was = 'HP 3020 (SoftPaq gescheitert) ist Fehlschlag' }
    @{ Id = 'dell';   Code = $null; Soll = 'fail' }
)
foreach ($fall in $faelle) {
    $ist = Get-WzOemOutcome -Tool $werkzeuge[$fall.Id] -ExitCode $fall.Code
    $was = if ($fall.Was) { $fall.Was } else { "$($fall.Id) $($fall.Code) → $($fall.Soll)" }
    Write-Check $was ($ist -eq $fall.Soll) $ist
}
Write-Check 'Lenovo nimmt keine Pakete mit erzwungenem Neustart' ($werkzeuge['lenovo'].applyArgs -match '-includerebootpackages 3(\s|$)') $werkzeuge['lenovo'].applyArgs

Write-Host ''
if ($script:fehler -eq 0) {
    Write-Host '  Ergebnis: alle Prüfungen bestanden.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $($script:fehler) Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
