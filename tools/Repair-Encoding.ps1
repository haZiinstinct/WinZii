# Dev-Werkzeug: erzwingt UTF-8 mit BOM für alle PowerShell- und XAML-Dateien.
# PowerShell 5.1 liest UTF-8 ohne BOM als ANSI — deutsche Umlaute wären zerstört.
[CmdletBinding()]
param([switch]$WhatIfOnly)

$root = Split-Path -Parent $PSScriptRoot
$utf8Bom = New-Object Text.UTF8Encoding($true)
$changed = 0

$files = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.xaml' |
    Where-Object { $_.FullName -notmatch '\\(offline|logs|backups|reports)\\' }

foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) { continue }

    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $relative = $file.FullName.Substring($root.Length + 1)
    if ($WhatIfOnly) {
        Write-Host "  offen: $relative" -ForegroundColor Yellow
    } else {
        [IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        Write-Host "  BOM ergänzt: $relative" -ForegroundColor Cyan
    }
    $changed++
}

if ($changed -eq 0) {
    Write-Host '  Alle Dateien sind bereits UTF-8 mit BOM.' -ForegroundColor Green
} else {
    Write-Host "  $changed Datei(en) betroffen." -ForegroundColor Green
}
