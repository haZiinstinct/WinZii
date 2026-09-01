# Dev-Werkzeug: prüft, ob ein Sprachwechsel im laufenden Betrieb wirklich alles
# umstellt — auch das, was kein Wörterbuch erreicht.
#
# Warum es dieses Werkzeug gibt: Aktivierung, BitLocker und Virenschutz sind
# keine Beschriftungen, sondern **fertige Sätze aus einer Messung**. Sie
# entstehen in der Sprache, die beim Messen galt. Ein Wörterbuchtausch geht an
# ihnen vorbei, und im englischen Übergabeblatt stand weiter Deutsch.
#
# Dafür gibt es `Update-WzMeasuredTexts`. Beim ersten Anlauf hat die Funktion
# nichts bewirkt: Sie stieß zwei Hintergrundaufgaben direkt hintereinander an,
# und `Invoke-WzTask` weist jede weitere ab, solange eine läuft — verworfen
# wurde ausgerechnet die zweite, in der Aktivierung, BitLocker und Virenschutz
# stecken. Im Quelltext sah es richtig aus. Aufgefallen ist es erst, als das
# Programm wirklich lief.
#
# Geprüft wird deshalb am laufenden Programm, nicht am Quelltext:
# starten, Bestandsaufnahme abwarten, umschalten, nachsehen.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-LanguageSwitch.ps1
[CmdletBinding()]
param([int]$TimeoutSeconds = 120)

$root = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '  WinZii Sprachwechsel im Betrieb' -ForegroundColor Cyan
Write-Host ''

# Der Prüfteil läuft IM Programm, über WZ_SELFTEST_ACTION. Er bekommt damit
# denselben $syncHash wie die Oberfläche und kann nachsehen, was dort steht.
$aktion = @'
$felder = { "$($syncHash.SecurityInfo.Activation)|$($syncHash.SecurityInfo.BitLocker)|$($syncHash.SecurityInfo.Defender)" }
$vorher = & $felder

[void](Set-WzLanguage -Code 'en')
Update-WzLanguageUi

# Neu gemessen wird im Hintergrund, in zwei Stufen nacheinander.
$grenze = (Get-Date).AddSeconds(90)
Start-Sleep -Milliseconds 400
while ((Get-Date) -lt $grenze) {
    Invoke-WzDoEvents
    Start-Sleep -Milliseconds 150
    if (-not $syncHash.Busy -and $syncHash.SecurityInfo -and (& $felder) -ne $vorher) { break }
}

$nachher = & $felder
Write-Host "WZTEST-VORHER  $vorher"
Write-Host "WZTEST-NACHHER $nachher"
# Ein deutsches Merkmal in der englischen Fassung ist der Befund
$deutsch = [regex]'(?i)[äöüß]|\b(nicht|aktiviert|Schutz|Signaturen|verschl)'
if ($nachher -eq $vorher) {
    Write-Host 'WZTEST-ERGEBNIS unveraendert'
} elseif ($deutsch.IsMatch($nachher)) {
    Write-Host 'WZTEST-ERGEBNIS deutsche-reste'
} else {
    Write-Host 'WZTEST-ERGEBNIS ok'
}
Invoke-WzDoEvents
'@

$aktionsDatei = Join-Path $env:TEMP "winzii-sprachwechsel-$PID.ps1"
[IO.File]::WriteAllText($aktionsDatei, $aktion, (New-Object Text.UTF8Encoding($true)))

$env:WZ_SELFTEST = '11000'
$env:WZ_SELFTEST_PAGE = 'Dashboard'
$env:WZ_SELFTEST_LANG = 'de'
$env:WZ_SELFTEST_ACTION = $aktionsDatei
$env:WZ_SELFTEST_OUT = Join-Path $env:TEMP "winzii-sprachwechsel-$PID.png"

try {
    $ausgabe = & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $root 'src\launcher.ps1') -NoElevate 2>&1
    $code = $LASTEXITCODE
} finally {
    foreach ($name in 'WZ_SELFTEST', 'WZ_SELFTEST_PAGE', 'WZ_SELFTEST_LANG', 'WZ_SELFTEST_ACTION', 'WZ_SELFTEST_OUT') {
        Set-Item -Path "Env:$name" -Value ''
    }
    if (Test-Path -LiteralPath $aktionsDatei) { [IO.File]::Delete($aktionsDatei) }
}

$zeilen = @($ausgabe | ForEach-Object { "$_" })
$vorher = @($zeilen | Where-Object { $_ -match 'WZTEST-VORHER' }) | Select-Object -First 1
$nachher = @($zeilen | Where-Object { $_ -match 'WZTEST-NACHHER' }) | Select-Object -First 1
$ergebnis = @($zeilen | Where-Object { $_ -match 'WZTEST-ERGEBNIS' }) | Select-Object -First 1

$fehler = 0
function Pruefe {
    param([string]$Was, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $farbe = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-42} {2}" -f $symbol, $Was, $Detail) -ForegroundColor $farbe
    if (-not $Ok) { $script:fehler++ }
}

Pruefe 'Programm startet und schließt sauber' ($code -eq 0) "exit=$code"
Pruefe 'Prüfteil hat gemessen' ($null -ne $ergebnis)

if ($vorher) { Write-Host ("         vorher : " + ($vorher -replace '.*WZTEST-VORHER\s*', '')) -ForegroundColor DarkGray }
if ($nachher) { Write-Host ("         nachher: " + ($nachher -replace '.*WZTEST-NACHHER\s*', '')) -ForegroundColor DarkGray }

if ($ergebnis) {
    $wert = ($ergebnis -replace '.*WZTEST-ERGEBNIS\s*', '').Trim()
    Pruefe 'gemessene Texte folgen der Sprache' ($wert -eq 'ok') $(switch ($wert) {
        'unveraendert'   { 'unverändert — Update-WzMeasuredTexts hat nichts bewirkt' }
        'deutsche-reste' { 'noch deutsche Wörter in der englischen Fassung' }
        default          { '' }
    })
}

Write-Host ''
if ($fehler -eq 0) {
    Write-Host '  Ergebnis: Der Sprachwechsel erreicht auch die gemessenen Texte.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $fehler Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
