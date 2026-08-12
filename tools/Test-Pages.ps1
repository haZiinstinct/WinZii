# Dev-Werkzeug: öffnet nacheinander jede Seite und meldet Fehler.
# Erkennt Verdrahtungsfehler, die der reine Syntax-Test nicht sieht.
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Test-Pages.ps1
[CmdletBinding()]
param([switch]$Screenshots)

$root = Split-Path -Parent $PSScriptRoot

# Die Liste kommt aus dem Verzeichnis, nicht aus dieser Datei: Eine fest
# eingetragene Aufzählung veraltet beim ersten Hinzufügen einer Seite still —
# der Test meldet dann weiter "alles in Ordnung" und prüft die neue Seite nie.
# Die Reihenfolge folgt der Navigation, damit die Ausgabe der Oberfläche gleicht.
$navOrder = @()
foreach ($line in [IO.File]::ReadAllLines((Join-Path $root 'src\xaml\MainWindow.xaml'))) {
    if ($line -match 'Tag="([A-Za-z]+)"\s+Style="\{DynamicResource WzNavButton\}"') {
        $navOrder += $Matches[1]
    }
}
$onDisk = @(Get-ChildItem -LiteralPath (Join-Path $root 'src\xaml\pages') -Filter '*.xaml' -File |
    ForEach-Object { $_.BaseName })
$pages = @($navOrder | Where-Object { $onDisk -contains $_ }) +
         @($onDisk | Where-Object { $navOrder -notcontains $_ })

# Ohne diese Prüfung meldet der Test »alle 0 Seiten laden fehlerfrei« und endet
# mit Erfolg, sobald sich am Aufbau der Navigationsknöpfe etwas ändert und der
# Regex oben ins Leere greift. Ein grüner Test, der nichts geprüft hat, ist
# schlimmer als gar keiner.
if ($pages.Count -lt 10) {
    Write-Host ''
    Write-Host "  [FEHL] Nur $($pages.Count) Seite(n) gefunden — die Erkennung greift nicht mehr." -ForegroundColor Red
    Write-Host '         Navigation in MainWindow.xaml oder src\xaml\pages\ prüfen.' -ForegroundColor DarkGray
    exit 1
}

$failed = 0
$shotDir = Join-Path $env:TEMP 'winzii-pages'
if ($Screenshots -and -not (Test-Path $shotDir)) { [void](New-Item -ItemType Directory -Path $shotDir -Force) }

Write-Host ''
Write-Host '  WinZii Seitentest' -ForegroundColor Cyan
Write-Host ''

foreach ($page in $pages) {
    $env:WZ_SELFTEST = '1500'
    $env:WZ_SELFTEST_PAGE = $page
    $env:WZ_SELFTEST_OUT = if ($Screenshots) { Join-Path $shotDir "$page.png" } else { Join-Path $env:TEMP 'winzii-page-test.png' }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'src\main.ps1') 2>&1
    $text = $output -join "`n"

    if ($text -match 'fehlgeschlagen|Exception|konnte nicht geladen') {
        Write-Host "  [FEHL] $page" -ForegroundColor Red
        foreach ($line in ($output | Where-Object { $_ -match 'fehlgeschlagen|Stelle:|Zeile:' })) {
            Write-Host "         $line" -ForegroundColor DarkGray
        }
        $failed++
    } else {
        Write-Host "  [ok]   $page" -ForegroundColor Green
    }
}

# Zusätzlich der Startweg über den Launcher. Die Prüfungen oben rufen main.ps1
# direkt mit -File auf und würden nicht bemerken, wenn der Launcher die Module
# in einen Bereich lädt, den die Ereignisbehandlungen von WPF nicht sehen.
$env:WZ_SELFTEST = '1500'
$env:WZ_SELFTEST_PAGE = 'Dashboard'
$env:WZ_SELFTEST_OUT = Join-Path $env:TEMP 'winzii-launcher-test.png'
$launcherOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'src\launcher.ps1') -NoElevate 2>&1
$launcherText = $launcherOutput -join "`n"

if ($launcherText -match 'wurde nicht als Name|fehlgeschlagen|Exception') {
    Write-Host '  [FEHL] Launcher-Startweg' -ForegroundColor Red
    foreach ($line in ($launcherOutput | Where-Object { $_ -match 'wurde nicht als Name|fehlgeschlagen|Stelle:' })) {
        Write-Host "         $line" -ForegroundColor DarkGray
    }
    $failed++
} else {
    Write-Host '  [ok]   Launcher-Startweg' -ForegroundColor Green
}

Remove-Item Env:\WZ_SELFTEST, Env:\WZ_SELFTEST_PAGE, Env:\WZ_SELFTEST_OUT -ErrorAction SilentlyContinue

Write-Host ''
if ($failed -eq 0) {
    Write-Host "  Ergebnis: alle $($pages.Count) Seiten und der Launcher laden fehlerfrei." -ForegroundColor Green
    if ($Screenshots) { Write-Host "  Abbilder: $shotDir" -ForegroundColor DarkGray }
    exit 0
}
Write-Host "  Ergebnis: $failed von $($pages.Count) Seiten und der Launcher mit Fehlern." -ForegroundColor Red
exit 1
