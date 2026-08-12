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

foreach ($modul in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Office') {
    . (Join-Path $repo "src\modules\$modul.ps1")
}

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
    Write-Host '3. Bitness ist offen' -ForegroundColor White
    Remove-Item -LiteralPath $fassung -Recurse -Force
    New-DuenneDatei -Pfad (Join-Path $fassung 'stream.x86.x-none.dat') -Groesse 1500MB
    New-DuenneDatei -Pfad (Join-Path $fassung "stream.x86.$sprache.dat") -Groesse 600MB
    $u = Get-Urteil
    Write-Check '32-Bit-Satz gilt auch' ($u.Available) $u.Detail
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
