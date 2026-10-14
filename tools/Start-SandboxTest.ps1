# Bereitet den Sandbox-Selbsttest vor und startet ihn.
#
# Die Sandbox bekommt NICHT den Arbeitsordner, sondern eine Kopie unter
# sandbox-staging\. Im Arbeitsordner liegen backups\ mit WLAN- und
# BitLocker-Schlüsseln im Klartext, logs\, reports\ und .git — und der Test
# lädt Software aus dem Internet und schreibt in den eingebundenen Ordner
# (Audit 2026-10, M39). Wie in New-Release.ps1 eine Weißliste: Was nicht
# genannt ist, kommt nicht mit.
#
# offline\ bleibt bewusst draußen. Dort liegen offline\daten\ (Kundendaten)
# und der Vorrat; ohne ihn läuft der Test die Ladepfade, die er prüfen soll.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Start-SandboxTest.ps1
# Ergebnis: sandbox-staging\sandbox-ergebnis\<Zeit>\
[CmdletBinding()]
param(
    # Nur die Kopie anlegen, die Sandbox nicht starten
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$staging = Join-Path $root 'sandbox-staging'

$includeFolders = @('src', 'data', 'assets', 'tools')
$includeFiles = @('Start.bat', 'LICENSE')

[void](New-Item -ItemType Directory -Path $staging -Force)
foreach ($folder in $includeFolders) {
    # /MIR hält die Kopie aktuell, ohne jedes Mal alles neu zu schreiben.
    # Rückgabewerte unter 8 sind bei robocopy Erfolg.
    & robocopy.exe (Join-Path $root $folder) (Join-Path $staging $folder) /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy $folder endete mit $LASTEXITCODE." }
}
foreach ($file in $includeFiles) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $staging -Force
}
# Reste eines früheren Laufs, die der Test selbst anlegt, gehören nicht in
# den nächsten. sandbox-ergebnis\ bleibt stehen.
foreach ($stale in 'offline', 'logs', 'backups', 'reports') {
    $path = Join-Path $staging $stale
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
}
[void](New-Item -ItemType Directory -Path (Join-Path $staging 'sandbox-ergebnis') -Force)
Write-Host "  [ok]   Kopie für die Sandbox: $staging" -ForegroundColor Green

if (-not $NoStart) {
    Start-Process -FilePath (Join-Path $PSScriptRoot 'Test-Sandbox.wsb')
}
