# Dev-Werkzeug: öffnet nacheinander jede Seite und meldet Fehler.
# Erkennt Verdrahtungsfehler, die der reine Syntax-Test nicht sieht.
# Aufruf:  powershell -NoProfile -STA -File tools\Test-Pages.ps1
[CmdletBinding()]
param([switch]$Screenshots)

$root = Split-Path -Parent $PSScriptRoot
$pages = @('Dashboard', 'Diagnostics', 'Optimizer', 'AiRemoval', 'Cleanup', 'Apps', 'Office', 'Autostart', 'Toolbox', 'Protocol')

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

Remove-Item Env:\WZ_SELFTEST, Env:\WZ_SELFTEST_PAGE, Env:\WZ_SELFTEST_OUT -ErrorAction SilentlyContinue

Write-Host ''
if ($failed -eq 0) {
    Write-Host "  Ergebnis: alle $($pages.Count) Seiten laden fehlerfrei." -ForegroundColor Green
    if ($Screenshots) { Write-Host "  Abbilder: $shotDir" -ForegroundColor DarkGray }
    exit 0
}
Write-Host "  Ergebnis: $failed von $($pages.Count) Seiten mit Fehlern." -ForegroundColor Red
exit 1
