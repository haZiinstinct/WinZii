# Dev-Werkzeug: prüft, wann ein Office-Vorrat als vollständig gilt.
#
# Der Grund für dieses Werkzeug steht in 0.4.1: Im Abnahmelauf wurde ein
# Download nach 75 Sekunden abgebrochen. Katalogdatei und Paket-Cabs lagen
# schon da, die eigentlichen Programmdateien hatten 0 Byte — und WinZii
# meldete 39 MB als »vollständig«. Beim Kunden ohne Netz ist das die
# Installation, die nicht startet.
#
# Angefasst wird nichts Echtes: Der Vorrat wird im TEMP-Ordner nachgebaut,
# Schritt für Schritt, wie ODT ihn anlegt. Die großen Dateien sind dünn besetzt
# (sparse) — 2 GB logische Größe, kein einziges geschriebenes Byte.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Office.ps1
[CmdletBinding()]
param()

$repo = Split-Path -Parent $PSScriptRoot
$spielwiese = Join-Path $env:TEMP "winzii-office-test-$PID"

$global:WzRootPath = $spielwiese
$global:WzSessionStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.DryRun = $false
. (Join-Path $repo 'src\version.ps1')
$syncHash.Version = $script:WzVersion

foreach ($modul in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.I18n', 'Core.Runspace', 'Office') {
    . (Join-Path $repo "src\modules\$modul.ps1")
}

# Die Module holen ihre Texte ueber Get-WzText — ohne Sprachtabelle liefert der
# Aufruf nur den Schluessel zurueck, und die Pruefungen unten vergleichen Text.
# Die Wurzel zeigt hier absichtlich auf die Spielwiese; die Sprachdateien liegen
# aber im Repo, also fuer den Ladevorgang kurz umgebogen.
$syncHash.Language = 'de'
$global:WzRootPath = $repo
[void](Import-WzLanguage)
$global:WzRootPath = $spielwiese

$script:fehler = 0
function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $farbe = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-46} {2}" -f $symbol, $Name, $Detail) -ForegroundColor $farbe
    if (-not $Ok) { $script:fehler++ }
}

function New-DuenneDatei {
    # Legt eine Datei mit logischer Größe an, ohne sie wirklich zu schreiben.
    param([string]$Pfad, [long]$Groesse)
    $ordner = Split-Path -Parent $Pfad
    if (-not (Test-Path -LiteralPath $ordner)) { [void](New-Item -ItemType Directory -Path $ordner -Force) }
    if (Test-Path -LiteralPath $Pfad) { Remove-Item -LiteralPath $Pfad -Force }
    [void](New-Item -ItemType File -Path $Pfad)
    if ($Groesse -gt 1MB) { [void](fsutil sparse setflag "$Pfad" 2>&1) }
    $strom = [IO.File]::Open($Pfad, 'Open', 'Write')
    $strom.SetLength($Groesse)
    $strom.Close()
}

Write-Host ''
Write-Host '  WinZii Office-Vorrat' -ForegroundColor Cyan
Write-Host ''

$variante = 'm365home'
$sprache = 'de-de'
$vorrat = Join-Path $spielwiese "offline\office\$variante-$sprache"
$daten = Join-Path $vorrat 'Office\Data'
$fassung = Join-Path $daten '16.0.20228.20190'

function Get-Urteil { Test-WzOfficeCache -VariantId $variante -Language $sprache }

try {
    # 1. Nichts geladen
    Write-Host '1. Die Stufen eines abgebrochenen Downloads' -ForegroundColor White
    $u = Get-Urteil
    Write-Check 'gar nichts da' (-not $u.Available -and $u.Detail -match 'noch nichts') $u.Detail

    # 2. Ordner da, aber keine Datenablage
    [void](New-Item -ItemType Directory -Path $vorrat -Force)
    $u = Get-Urteil
    Write-Check 'leerer Ordner' (-not $u.Available -and $u.Detail -match 'Datenablage') $u.Detail

    # 3. Datenablage ohne Katalogdatei
    [void](New-Item -ItemType Directory -Path $daten -Force)
    $u = Get-Urteil
    Write-Check 'Datenablage ohne Katalogdatei' (-not $u.Available -and $u.Detail -match 'Katalogdatei') $u.Detail

    # 4. Katalogdatei und Paket-Cabs — genau hier hörte die Prüfung bis 0.4.1 auf
    New-DuenneDatei -Pfad (Join-Path $daten 'v64.cab') -Groesse 6KB
    New-DuenneDatei -Pfad (Join-Path $fassung 'i640.cab') -Groesse 31MB
    New-DuenneDatei -Pfad (Join-Path $fassung 's640.cab') -Groesse 2MB
    $u = Get-Urteil
    Write-Check 'Katalog und Cabs, keine Programmdateien' (-not $u.Available -and $u.Detail -match 'Programmdateien von Office fehlen') $u.Detail

    # 5. Der Stand aus dem Abnahmelauf: stream-Datei angelegt, aber leer
    New-DuenneDatei -Pfad (Join-Path $fassung 'stream.x64.x-none.dat') -Groesse 0
    $u = Get-Urteil
    Write-Check 'Programmdateien erst angefangen (0 Byte)' (-not $u.Available -and $u.Detail -match 'erst angefangen') `
        "$([math]::Round($u.Bytes/1MB)) MB galten früher als vollständig"

    # 6. Programmdateien vollständig, Sprache fehlt
    New-DuenneDatei -Pfad (Join-Path $fassung 'stream.x64.x-none.dat') -Groesse 1900MB
    $u = Get-Urteil
    Write-Check 'ohne Sprachdateien' (-not $u.Available -and $u.Detail -match 'Sprachdateien') $u.Detail

    # 7. Sprachdatei da, aber selbst erst angefangen
    New-DuenneDatei -Pfad (Join-Path $fassung "stream.x64.$sprache.dat") -Groesse 8MB
    $u = Get-Urteil
    Write-Check 'Sprachdateien erst angefangen' (-not $u.Available -and $u.Detail -match 'Sprachdateien') $u.Detail

    # 8. Alles da
    New-DuenneDatei -Pfad (Join-Path $fassung "stream.x64.$sprache.dat") -Groesse 380MB
    $u = Get-Urteil
    Write-Check 'vollständiger Satz' ($u.Available -and $u.Detail -eq 'vollständig') `
        "$([math]::Round($u.Bytes/1GB,2)) GB"

    # 9. Andere Sprache im selben Vorrat zählt nicht
    Write-Host ''
    Write-Host '2. Die Sprache muss stimmen' -ForegroundColor White
    Remove-Item -LiteralPath (Join-Path $fassung "stream.x64.$sprache.dat") -Force
    New-DuenneDatei -Pfad (Join-Path $fassung 'stream.x64.en-us.dat') -Groesse 380MB
    $u = Get-Urteil
    Write-Check 'fremde Sprache genügt nicht' (-not $u.Available -and $u.Detail -match 'Sprachdateien') $u.Detail

    # 10. 32-Bit-Ablage wird genauso erkannt
    Write-Host ''
    Write-Host '3. Bitness: Anzeige offen, Installation genau' -ForegroundColor White
    Remove-Item -LiteralPath $fassung -Recurse -Force
    New-DuenneDatei -Pfad (Join-Path $fassung 'stream.x86.x-none.dat') -Groesse 1500MB
    New-DuenneDatei -Pfad (Join-Path $fassung "stream.x86.$sprache.dat") -Groesse 600MB
    $u = Get-Urteil
    Write-Check '32-Bit-Satz gilt auch' ($u.Available) $u.Detail

    # Für eine bestimmte Installation zählt die Architektur (Audit M12): Ein
    # 32-Bit-Vorrat taugt nicht für 64 Bit und umgekehrt.
    $u = Test-WzOfficeCache -VariantId $variante -Language $sprache -Edition '64'
    Write-Check '32-Bit-Satz taugt nicht für 64 Bit' (-not $u.Available -and $u.OtherBitness) $u.Detail
    $u = Test-WzOfficeCache -VariantId $variante -Language $sprache -Edition '32'
    Write-Check '32-Bit-Satz taugt für 32 Bit' ($u.Available) $u.Detail

    # Angefangener 64-Bit-Satz neben dem vollen 32-Bit-Satz: Die Größe der
    # fremden Architektur darf die 2-GB-Schranke nicht füllen.
    New-DuenneDatei -Pfad (Join-Path $fassung 'stream.x64.x-none.dat') -Groesse 1100MB
    New-DuenneDatei -Pfad (Join-Path $fassung "stream.x64.$sprache.dat") -Groesse 60MB
    $u = Test-WzOfficeCache -VariantId $variante -Language $sprache -Edition '64'
    Write-Check 'fremde Architektur zählt nicht zur Größe' (-not $u.Available) $u.Detail

    # 4. Eine unsignierte setup.exe im Vorrat läuft nicht eleviert los (M8).
    #    Im Testmodus, damit danach kein echter Download startet.
    Write-Host ''
    Write-Host '4. Signatur des Bereitstellungswerkzeugs' -ForegroundColor White
    $fremdeSetup = Join-Path (Join-Path (Get-WzOfflineDir) 'odt') 'setup.exe'
    New-DuenneDatei -Pfad $fremdeSetup -Groesse 2MB
    $syncHash.DryRun = $true
    $geliefert = Get-WzOdtSetup
    $syncHash.DryRun = $false
    Write-Check 'unsignierte setup.exe abgewiesen' ($null -eq $geliefert) "$geliefert"
    Write-Check 'unsignierte setup.exe gelöscht' (-not (Test-Path -LiteralPath $fremdeSetup))

    # 5. Programme-Vorrat: Das Manifest muss zur winget-ID und zur Datei
    #    daneben passen und darf keine eigenen Schalter mitbringen.
    Write-Host ''
    Write-Host '5. Manifest im Programme-Vorrat' -ForegroundColor White
    . (Join-Path $repo 'src\modules\Apps.ps1')
    $vorrat = Join-Path $spielwiese 'vorrat-test'
    [void](New-Item -ItemType Directory -Path $vorrat -Force)
    $setupDatei = Join-Path $vorrat 'Beispiel_1.0.exe'
    [IO.File]::WriteAllText($setupDatei, 'kein echtes Programm')
    $hash = (Get-FileHash -LiteralPath $setupDatei -Algorithm SHA256).Hash
    $manifestPfad = Join-Path $vorrat 'Beispiel.Paket_1.0.yaml'
    function Set-Manifest([string]$Id, [string]$Sha, [string]$Zusatz = '') {
        $text = "PackageIdentifier: $Id`nPackageVersion: 1.0`nInstallers:`n- Architecture: x64`n  InstallerType: exe`n  InstallerSha256: $Sha`n$Zusatz"
        [IO.File]::WriteAllText($manifestPfad, $text)
    }
    $dateien = @(Get-Item -LiteralPath $setupDatei)

    Set-Manifest 'Beispiel.Paket' $hash
    Write-Check 'passendes Manifest angenommen' ($null -eq (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Fremd.Paket' $hash
    Write-Check 'fremde winget-ID abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Beispiel.Paket' ('0' * 64)
    Write-Check 'falsche Prüfsumme abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Beispiel.Paket' $hash "  InstallerSwitches:`n    Custom: /evil"
    Write-Check 'eigene Installer-Schalter abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Beispiel.Paket' $hash
    [IO.File]::WriteAllText((Join-Path $vorrat 'zweites.yaml'), "PackageIdentifier: Beispiel.Paket")
    Write-Check 'zweites Manifest abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Remove-Item -LiteralPath (Join-Path $vorrat 'zweites.yaml') -Force
    Set-Manifest 'Beispiel.Paket' $hash "  InstallerSwitches:`n    Silent: /S /D=C:\fremd"
    Write-Check 'Silent-Schalter abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Beispiel.Paket' $hash "  InstallerSwitches: { Silent: /evil }"
    Write-Check 'Schalter in Kurzschreibweise abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Beispiel.Paket' $hash "  'InstallerSwitches':`n    `"Silent`": /evil"
    Write-Check 'Schalter in Anführungszeichen abgewiesen' ($null -ne (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))
    Set-Manifest 'Beispiel.Paket' $hash "Description: |-`n  Ein ganz normales Programm."
    Write-Check 'Block-Text bleibt erlaubt' ($null -eq (Test-WzVaultManifest -Directory $vorrat -WingetId 'Beispiel.Paket' -Installers $dateien))

    # 6. Aussteller: gültig signiert genügt nicht, er muss im Katalog stehen.
    #    Als signierte Datei dient eine Kopie von powershell.exe — die Signatur
    #    ist eingebettet und auf jedem Windows vorhanden (CN »Microsoft Windows«).
    Write-Host ''
    Write-Host '6. Aussteller im Programme-Vorrat' -ForegroundColor White
    $appOrdner = Join-Path (Join-Path (Get-WzOfflineDir) 'installers') 'beispiel'
    [void](New-Item -ItemType Directory -Path $appOrdner -Force)
    $signiert = Join-Path $appOrdner 'Beispiel_1.0.exe'
    Copy-Item -LiteralPath "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination $signiert -Force
    $manifestPfad = Join-Path $appOrdner 'Beispiel.Paket_1.0.yaml'
    Set-Manifest 'Beispiel.Paket' (Get-FileHash -LiteralPath $signiert -Algorithm SHA256).Hash

    $ohneAussteller = [pscustomobject]@{ id = 'beispiel'; name = 'Beispiel'; wingetId = 'Beispiel.Paket' }
    $richtig = [pscustomobject]@{ id = 'beispiel'; name = 'Beispiel'; wingetId = 'Beispiel.Paket'; signers = @('Microsoft Windows') }
    $falsch = [pscustomobject]@{ id = 'beispiel'; name = 'Beispiel'; wingetId = 'Beispiel.Paket'; signers = @('Google LLC') }
    Write-Check 'ohne hinterlegten Aussteller: online' ($null -eq (Get-WzOfflineInstallerPath -App $ohneAussteller -Verify))
    Write-Check 'fremder Aussteller: online' ($null -eq (Get-WzOfflineInstallerPath -App $falsch -Verify))
    Write-Check 'passender Aussteller: aus dem Vorrat' ($appOrdner -eq (Get-WzOfflineInstallerPath -App $richtig -Verify))
    Write-Check 'CN-Vergleich achtet auf Schreibung' (-not (Test-WzFileSignature -Path $signiert -ExpectedSigners @('microsoft windows')))
} finally {
    Remove-Item -LiteralPath $spielwiese -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fehler -eq 0) {
    Write-Host '  Ergebnis: alle Prüfungen bestanden.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $($script:fehler) Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
