# Baut das Release-Archiv für den USB-Stick und nennt die Prüfsumme.
#
# Arbeitet bewusst mit einer WEISSLISTE. Ein "Ordner zippen" würde logs\, backups\
# und reports\ mitnehmen — die sind zwar in .gitignore, liegen aber im Arbeitsordner
# und enthalten echte Registry-Exporte, Systemberichte und den Rechnernamen des
# Entwicklungsrechners. Eine schwarze Liste würde bei jedem neuen Ordner erneut
# vergessen werden.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-Release.ps1
[CmdletBinding()]
param(
    [string]$OutputDir,
    [switch]$KeepStaging
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

. (Join-Path $root 'src\version.ps1')
$version = $script:WzVersion

if (-not $OutputDir) { $OutputDir = Join-Path $root 'dist' }
$staging = Join-Path $OutputDir "WinZii-$version"
$archive = Join-Path $OutputDir "WinZii-$version.zip"

# Was auf den Stick gehört. Ordner werden vollständig übernommen.
$includeFolders = @('src', 'data', 'assets')
$includeFiles = @('Start.bat', 'LICENSE', 'README.md', 'README.en.md', 'CHANGELOG.md', 'SECURITY.md')
# Aus tools\ nur die Sandbox-Konfigurationen — die Prüfwerkzeuge sind Entwicklerkram.
$includeToolPatterns = @('*.wsb')

Write-Host ''
Write-Host "  WinZii $version — Release bauen" -ForegroundColor Cyan
Write-Host ''

# --- Vorbedingungen -------------------------------------------------------
$missing = @()
foreach ($folder in $includeFolders) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $folder))) { $missing += $folder }
}
foreach ($file in $includeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { $missing += $file }
}
if ($missing.Count -gt 0) {
    Write-Host "  [FEHL] Fehlt im Arbeitsordner: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

# --- Bereitstellen --------------------------------------------------------
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
[void](New-Item -ItemType Directory -Path $staging -Force)

foreach ($folder in $includeFolders) {
    Copy-Item -LiteralPath (Join-Path $root $folder) -Destination $staging -Recurse -Force
    Write-Host "  [ok]   $folder\" -ForegroundColor Green
}
foreach ($file in $includeFiles) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $staging -Force
    Write-Host "  [ok]   $file" -ForegroundColor Green
}

$toolTarget = Join-Path $staging 'tools'
[void](New-Item -ItemType Directory -Path $toolTarget -Force)
foreach ($pattern in $includeToolPatterns) {
    foreach ($item in (Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Filter $pattern -File)) {
        Copy-Item -LiteralPath $item.FullName -Destination $toolTarget -Force
        Write-Host "  [ok]   tools\$($item.Name)" -ForegroundColor Green
    }
}

# offline\ legt WinZii selbst an, aber ein leerer Ordner im Archiv macht deutlich,
# wohin die vorab geladenen Installationsdateien gehören.
[void](New-Item -ItemType Directory -Path (Join-Path $staging 'offline') -Force)
[void](New-Item -ItemType File -Path (Join-Path $staging 'offline\.gitkeep') -Force)

# --- Gegenprobe: nichts Persönliches im Archiv ----------------------------
Write-Host ''
$forbidden = @('logs', 'backups', 'reports', 'docs', '.git')
$leaks = @()
foreach ($name in $forbidden) {
    if (Test-Path -LiteralPath (Join-Path $staging $name)) { $leaks += $name }
}
$devScripts = @(Get-ChildItem -LiteralPath $toolTarget -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
if ($devScripts.Count -gt 0) { $leaks += "tools\*.ps1 ($($devScripts.Count))" }

if ($leaks.Count -gt 0) {
    Write-Host "  [FEHL] Gehört nicht ins Archiv: $($leaks -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host '  [ok]   keine Laufzeit- oder Entwicklerdaten im Archiv' -ForegroundColor Green

# --- Packen ---------------------------------------------------------------
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive -CompressionLevel Optimal
if (-not $KeepStaging) { Remove-Item -LiteralPath $staging -Recurse -Force }

$info = Get-Item -LiteralPath $archive
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$checksumFile = "$archive.sha256"
[IO.File]::WriteAllText($checksumFile, "$hash  $($info.Name)$([Environment]::NewLine)", (New-Object Text.UTF8Encoding($false)))

# Kopie ohne Versionsnummer: hazii.org verlinkt releases/latest/download/WinZii.zip.
# Beide Dateien gehören ins Release — sonst bricht der Link beim nächsten Tag.
$stable = Join-Path $OutputDir 'WinZii.zip'
Copy-Item -LiteralPath $archive -Destination $stable -Force

Write-Host ''
Write-Host "  Archiv:    $archive" -ForegroundColor Cyan
Write-Host "  Stabil:    $stable  (fuer den Download-Link auf hazii.org)" -ForegroundColor Cyan
Write-Host ("  Größe:     {0:N1} MB" -f ($info.Length / 1MB))
Write-Host "  SHA256:    $hash"
Write-Host "  Prüfsumme: $checksumFile"
Write-Host ''
Write-Host '  Die Prüfsumme gehört in den Release-Text: WinZii ist nicht signiert, und' -ForegroundColor DarkGray
Write-Host '  das README bittet Nutzer, den SmartScreen-Hinweis wegzuklicken.' -ForegroundColor DarkGray
Write-Host ''
