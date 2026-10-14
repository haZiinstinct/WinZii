# Dev-Werkzeug: liest die Aussteller der Installationsdateien im Programme-Vorrat
# und vergleicht sie mit »signers« in data/apps.json.
#
# Warum es das gibt: Aus dem Vorrat installiert WinZii nur, wenn die Datei
# gültig von einem im Katalog hinterlegten Aussteller signiert ist (Audit
# 2026-10, M8). Die Einträge entstehen hier — aber nur auf einem eigenen,
# vertrauenswürdigen Rechner, direkt nach dem Vorabladen. Was ein Stick nach
# dem Einsatz bei Kunden enthält, taugt nicht als Quelle: Genau davor soll
# der Abgleich ja schützen.
#
# Das Werkzeug ändert nichts. Es zeigt je Programm den gefundenen Aussteller
# und die Zeile, die in apps.json unter dem Eintrag ergänzt werden kann.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Get-VaultSigners.ps1
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
$catalog = [IO.File]::ReadAllText((Join-Path $root 'data\apps.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$vault = Join-Path $root 'offline\installers'

Write-Host ''
Write-Host '  WinZii Aussteller im Programme-Vorrat' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-Path -LiteralPath $vault)) {
    Write-Host '  Kein Vorrat unter offline\installers. Erst in WinZii »Vorabladen« ausführen.' -ForegroundColor Yellow
    exit 0
}

$vorschlaege = 0
foreach ($app in $catalog.apps) {
    $dir = Join-Path $vault $app.id
    if (-not (Test-Path -LiteralPath $dir)) { continue }

    $dateien = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.exe', '.msi') })
    if ($dateien.Count -eq 0) {
        Write-Host ("  [--]   {0,-20} keine EXE/MSI (Appx/MSIX prüft Windows, ZIP geht online)" -f $app.id) -ForegroundColor DarkGray
        continue
    }

    $namen = @()
    $ungueltig = $false
    foreach ($datei in $dateien) {
        $signatur = Get-AuthenticodeSignature -LiteralPath $datei.FullName
        if ($signatur.Status -ne 'Valid') { $ungueltig = $true; continue }
        $namen += $signatur.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    }
    $namen = @($namen | Sort-Object -Unique)
    $hinterlegt = @($app.signers | Where-Object { $_ })

    if ($ungueltig -or $namen.Count -eq 0) {
        Write-Host ("  [!!]   {0,-20} nicht gültig signiert — aus dem Vorrat wird nie installiert" -f $app.id) -ForegroundColor Yellow
    } elseif ($hinterlegt.Count -eq 0) {
        $vorschlaege++
        $liste = ($namen | ForEach-Object { '"' + ($_ -replace '\\', '\\' -replace '"', '\"') + '"' }) -join ', '
        Write-Host ("  [neu]  {0,-20} {1}" -f $app.id, ($namen -join ' / ')) -ForegroundColor Cyan
        Write-Host ("         in apps.json ergänzen:  ""signers"": [{0}]," -f $liste) -ForegroundColor DarkGray
    } elseif (@($namen | Where-Object { $hinterlegt -cnotcontains $_ }).Count -gt 0) {
        Write-Host ("  [!!]   {0,-20} gefunden: {1}  hinterlegt: {2}" -f $app.id, ($namen -join ' / '), ($hinterlegt -join ' / ')) -ForegroundColor Yellow
    } else {
        Write-Host ("  [ok]   {0,-20} {1}" -f $app.id, ($namen -join ' / ')) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host "  $vorschlaege Programm(e) ohne hinterlegten Aussteller. Nur übernehmen, wenn der Vorrat auf einem eigenen Rechner frisch geladen wurde." -ForegroundColor Gray
exit 0
