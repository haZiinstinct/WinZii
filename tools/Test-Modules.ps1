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

foreach ($modul in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.I18n', 'Core.Version', 'Setup',
    'WindowsUpdate', 'AiRemoval', 'Toolbox', 'Autostart', 'HealthCheck', 'Snapshot') {
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

# --- Setup -------------------------------------------------------------------
Write-Host ''
Write-Host '2. Rechnername und Produktschlüssel (Setup)' -ForegroundColor White
$namen = @(
    @{ Name = 'BUERO-PC01';       Soll = $true }
    @{ Name = 'A';                Soll = $true }
    @{ Name = 'ABCDEFGHIJKLMNO';  Soll = $true }
    @{ Name = 'ABCDEFGHIJKLMNOP'; Soll = $false }
    @{ Name = 'Büro';             Soll = $false }
    @{ Name = 'PC_01';            Soll = $false }
    @{ Name = 'PC 01';            Soll = $false }
    @{ Name = '12345';            Soll = $false }
    @{ Name = '-PC';              Soll = $false }
    @{ Name = 'PC-';              Soll = $false }
    @{ Name = '';                 Soll = $false }
    @{ Name = '   ';              Soll = $false }
)
foreach ($fall in $namen) {
    $r = Test-WzComputerNameValid -Name $fall.Name
    $grundOk = $r.Valid -or [bool]$r.Reason
    Write-Check "Rechnername '$($fall.Name)'" ($r.Valid -eq $fall.Soll -and $grundOk) $(if ($r.Valid) { 'gültig' } else { $r.Reason })
}
$schluessel = @(
    @{ Key = 'ABCDE-FGHIJ-KLMNO-PQRST-UVWXY'; Soll = $true }
    @{ Key = 'abcdefghijklmnopqrstuvwxy';     Soll = $true }
    @{ Key = 'ABCDE-FGHIJ-KLMNO-PQRST';       Soll = $false }
    @{ Key = 'ABCDE-FGHIJ-KLMNO-PQRST-UVWXYZ'; Soll = $false }
    @{ Key = '';                              Soll = $false }
)
foreach ($fall in $schluessel) {
    Write-Check "Schlüsselform '$($fall.Key)'" ((Test-WzProductKeyFormat -Key $fall.Key) -eq $fall.Soll)
}

# --- WindowsUpdate -----------------------------------------------------------
Write-Host ''
Write-Host '3. Update-Fehlercodes (WindowsUpdate)' -ForegroundColor White
Write-Check 'negativer HResult als Hex' ((Format-WzUpdateCode (-2145124284)) -eq '0x80240044') (Format-WzUpdateCode (-2145124284))
Write-Check 'Null als 0x00000000' ((Format-WzUpdateCode 0) -eq '0x00000000')
Write-Check 'ohne Wert leer' ((Format-WzUpdateCode $null) -eq '')

# Die äußere Ausnahme trägt nur den Sammelcode von PowerShell; der echte Grund
# steckt innen.
$innen = New-Object Runtime.InteropServices.COMException('Netz', -2145107924)
$aussen = New-Object Management.Automation.MethodInvocationException('außen', $innen)
$record = New-Object Management.Automation.ErrorRecord($aussen, 'x', 'NotSpecified', $null)
$code = Get-WzUpdateHResult -ErrorRecord $record
Write-Check 'innerste Ursache der Ausnahmekette' ($code -eq '0x8024402C') $code

$text = Get-WzUpdateCodeText -Code '0x80240044'
Write-Check 'bekannter Code aus dem Katalog' ($text.Outcome -eq 'fail' -and $text.Text -match 'Administrator') $text.Text
$text = Get-WzUpdateCodeText -Code '0x00240006'
Write-Check 'bereits eingespielt zählt als skip' ($text.Outcome -eq 'skip')
$text = Get-WzUpdateCodeText -Code '0x8BADF00D'
Write-Check 'unbekannter Code ist fail und nennt die Zahl' ($text.Outcome -eq 'fail' -and $text.Text -match '0x8BADF00D') $text.Text
$text = Get-WzUpdateCodeText -Code ''
Write-Check 'ohne Code fail' ($text.Outcome -eq 'fail' -and [bool]$text.Text)

# Ergebnisobjekt der COM-Schnittstelle nachgebaut: HResult der Sammlung und
# GetUpdateResult(0) für das einzelne Update.
function New-UpdateResult {
    param([int]$Sammel, $Einzel, [switch]$Wirft)
    $o = [pscustomobject]@{ HResult = $Sammel; Einzel = $Einzel; Wirft = [bool]$Wirft }
    $o | Add-Member -MemberType ScriptMethod -Name GetUpdateResult -Value {
        param($i)
        if ($this.Wirft) { throw 'kein Einzelergebnis' }
        if ($null -eq $this.Einzel) { return $null }
        [pscustomobject]@{ HResult = $this.Einzel }
    }
    return $o
}
$faelle = @(
    @{ R = (New-UpdateResult -Sammel (-2145124318) -Einzel (-2145124284)); Soll = '0x80240044'; Was = 'Einzelcode schlägt Sammelcode' }
    @{ R = (New-UpdateResult -Sammel 0 -Einzel 0);                         Soll = '0x00000000'; Was = 'beides 0 bleibt 0' }
    @{ R = (New-UpdateResult -Sammel (-2145124318) -Einzel 0);             Soll = '0x80240022'; Was = 'Einzel 0, Sammlung nicht: Sammelcode' }
    @{ R = (New-UpdateResult -Sammel (-2145124318) -Wirft);                Soll = '0x80240022'; Was = 'ohne Einzelergebnis der Sammelcode' }
)
foreach ($fall in $faelle) {
    $ist = Get-WzUpdateResultCode -Result $fall.R
    Write-Check $fall.Was ($ist -eq $fall.Soll) $ist
}

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

Write-Host ''
if ($script:fehler -eq 0) {
    Write-Host '  Ergebnis: alle Prüfungen bestanden.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $($script:fehler) Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
