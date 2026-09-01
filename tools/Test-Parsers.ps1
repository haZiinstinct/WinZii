# Dev-Werkzeug: prüft die Stellen, die Ausgaben von Windows-Werkzeugen deuten —
# gegen die deutschen **und** die englischen Wortlaute.
#
# Warum es das gibt: WinZii liest die Ausgabe von `sfc`, `DISM`, `chkdsk`,
# `pnputil` und `winget` und entscheidet daran, was im Protokoll steht. Diese
# Muster sind auf einem deutschen Windows entstanden. Auf einem englischen
# System kommt anderer Text zurück, und ein Muster, das dort nicht trifft,
# fällt nicht auf: Es meldet einfach »unbekannt« oder wählt die falsche
# Protokollstufe. Genau diese Klasse Fehler ist bei der Übersetzung dreimal
# aufgetreten.
#
# Ein englisches Windows steht hier nicht zur Verfügung — geprüft wird deshalb
# gegen die **echten Wortlaute**, die diese Werkzeuge ausgeben. Das ersetzt
# Punkt 13 der Abnahme nicht, deckt aber den Teil ab, der sich ohne fremdes
# Gerät prüfen lässt.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Parsers.ps1
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot

$script:fehler = 0
function Pruefe {
    param([string]$Was, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $farbe = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-46} {2}" -f $symbol, $Was, $Detail) -ForegroundColor $farbe
    if (-not $Ok) { $script:fehler++ }
}

Write-Host ''
Write-Host '  WinZii Ausgabedeutung (deutsch und englisch)' -ForegroundColor Cyan

# Jeder Fall nennt das Muster aus dem Quelltext und die echten Ausgaben, die
# darauf treffen müssen. Die englischen Sätze stammen aus den Werkzeugen
# selbst, nicht aus einer Übersetzung.
$faelle = @(
    @{ Werkzeug = 'sfc — sauber'
       Muster = 'keine Integritätsverletzungen|did not find any integrity violations'
       Treffer = @(
         'Der Windows-Ressourcenschutz hat keine Integritätsverletzungen gefunden.'
         'Windows Resource Protection did not find any integrity violations.') }

    @{ Werkzeug = 'sfc — repariert'
       Muster = 'erfolgreich repariert|successfully repaired'
       Treffer = @(
         'Der Windows-Ressourcenschutz hat beschädigte Dateien gefunden und erfolgreich repariert.'
         'Windows Resource Protection found corrupt files and successfully repaired them.') }

    @{ Werkzeug = 'sfc — nicht reparierbar'
       Muster = 'nicht reparieren|unable to fix'
       Treffer = @(
         'Der Windows-Ressourcenschutz hat beschädigte Dateien gefunden, konnte jedoch einige davon nicht reparieren.'
         'Windows Resource Protection found corrupt files but was unable to fix some of them.') }

    @{ Werkzeug = 'pnputil — Anzahl eingespielter Pakete'
       Muster = '(?m)^\s*(?:Hinzugefügte Treiberpakete|Total driver packages added)\s*:\s*(\d+)'
       Treffer = @(
         "Gesamtzahl der versuchten Treiberpakete:  5`r`n  Hinzugefügte Treiberpakete:  4"
         "Total driver packages attempted:  5`r`n  Total driver packages added:  4") }

    @{ Werkzeug = 'winget — bereits vorhanden'
       Muster = '0x80073D06|höhere Version|higher version|already installed'
       Treffer = @(
         'Eine höhere Version dieses Pakets ist bereits installiert.'
         'A higher version of this package is already installed.'
         'Das Paket ist bereits installiert. (0x80073D06)') }

    @{ Werkzeug = 'Ereignisprotokoll — keine Treffer'
       Muster = 'Keine Ereignisse|No events'
       Treffer = @(
         'Keine Ereignisse stimmen mit der angegebenen Auswahl überein.'
         'No events were found that match the specified selection criteria.') }

    @{ Werkzeug = 'Ereignisprotokoll — Zugriff verweigert'
       Muster = 'nicht autorisiert|not authorized|Zugriff verweigert|access is denied'
       Treffer = @(
         'Der Aufrufer ist nicht autorisiert, auf das Protokoll zuzugreifen.'
         'The caller is not authorized to access this log.'
         'Zugriff verweigert.'
         'Access is denied.') }

    @{ Werkzeug = 'Sicherheitszertifikat abgelehnt'
       Muster = 'SSL|TLS|Vertrauensstellung|Zertifikat|trust'
       Treffer = @(
         'Die zugrunde liegende Verbindung wurde geschlossen: Für den geschützten SSL/TLS-Kanal konnte keine Vertrauensstellung hergestellt werden.'
         'The underlying connection was closed: Could not establish trust relationship for the SSL/TLS secure channel.') }

    @{ Werkzeug = 'Bereinigung — ungültiger Pfad'
       Muster = '(?i)invalid|ungültig|ungueltig'
       Treffer = @(
         'Der angegebene Pfad ist ungültig.'
         'The specified path is invalid.') }
)

Write-Host ''
foreach ($fall in $faelle) {
    # Das Muster muss noch so im Quelltext stehen — sonst prüft der Test eine
    # Fassung, die es nicht mehr gibt.
    $imCode = @(Get-ChildItem -LiteralPath (Join-Path $root 'src\modules') -Filter '*.ps1' -File |
        Where-Object { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8).Contains($fall.Muster) })
    Pruefe "$($fall.Werkzeug): Muster steht im Code" ($imCode.Count -gt 0) `
        $(if ($imCode.Count -gt 0) { $imCode[0].Name } else { 'nicht gefunden — Test veraltet' })

    foreach ($text in $fall.Treffer) {
        $sprache = if ($text -match '[äöüßÄÖÜ]|Der |Die |Das |Eine |Keine |Zugriff') { 'de' } else { 'en' }
        $kurz = ($text -split "`r`n")[-1]
        if ($kurz.Length -gt 40) { $kurz = $kurz.Substring(0, 40) + '…' }
        Pruefe "  trifft auf [$sprache]" ([bool]($text -match $fall.Muster)) $kurz
    }
}

Write-Host ''
if ($script:fehler -eq 0) {
    Write-Host "  Ergebnis: alle $($faelle.Count) Deutungen treffen in beiden Sprachen." -ForegroundColor Green
    Write-Host '            Ersetzt Punkt 13 der Abnahme nicht — die Werkzeuge selbst' -ForegroundColor DarkGray
    Write-Host '            laufen hier auf einem deutschen Windows.' -ForegroundColor DarkGray
    exit 0
}
Write-Host "  Ergebnis: $script:fehler Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
