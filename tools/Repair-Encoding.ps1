# Dev-Werkzeug: richtet die Kodierung aller Textdateien ein.
#   - PowerShell und XAML: UTF-8 MIT BOM. PowerShell 5.1 liest UTF-8 ohne BOM
#     als ANSI — deutsche Umlaute wären zerstört.
#   - JSON, Markdown, HTML: UTF-8 OHNE BOM. Externe Werkzeuge (jq, Pythons
#     json.load, viele Markdown-Renderer) stolpern über die BOM; WinZii selbst
#     liest beides (Audit 2026-10, M37).
[CmdletBinding()]
param([switch]$WhatIfOnly)

$root = Split-Path -Parent $PSScriptRoot
$utf8Bom = New-Object Text.UTF8Encoding($true)
$utf8 = New-Object Text.UTF8Encoding($false)
$changed = 0

$files = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.xaml', '*.json', '*.md', '*.html' |
    Where-Object { $_.FullName -notmatch '\\(offline|logs|backups|reports|dist|\.git)\\' }

foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $wantBom = $file.Extension -in @('.ps1', '.xaml')
    if ($hasBom -eq $wantBom) { continue }

    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }
    $relative = $file.FullName.Substring($root.Length + 1)
    if ($WhatIfOnly) {
        Write-Host "  offen: $relative" -ForegroundColor Yellow
    } elseif ($wantBom) {
        [IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        Write-Host "  BOM ergänzt: $relative" -ForegroundColor Cyan
    } else {
        [IO.File]::WriteAllText($file.FullName, $text, $utf8)
        Write-Host "  BOM entfernt: $relative" -ForegroundColor Cyan
    }
    $changed++
}

if ($changed -eq 0) {
    Write-Host '  Alle Dateien sind richtig kodiert.' -ForegroundColor Green
} else {
    Write-Host "  $changed Datei(en) betroffen." -ForegroundColor Green
}
