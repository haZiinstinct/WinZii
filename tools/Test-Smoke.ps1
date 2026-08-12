# Dev-Werkzeug: prüft ohne Systemeingriffe, ob WinZii startfähig ist.
#   1. Syntax aller PowerShell-Dateien
#   2. XAML-Dateien parsebar
#   3. JSON-Kataloge gültig
#   4. Encoding (UTF-8 mit BOM)
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Test-Smoke.ps1
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
$errors = @()
$checked = 0

function Write-Result {
    param([string]$Label, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host "  $symbol $Label" -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host '  WinZii Smoke-Test' -ForegroundColor Cyan
Write-Host ''

# --- 1. PowerShell-Syntax -------------------------------------------------
Write-Host '  PowerShell-Syntax' -ForegroundColor White
foreach ($file in Get-ChildItem "$root\src" -Recurse -Include '*.ps1' -File) {
    $checked++
    $parseErrors = $null
    $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    $relative = $file.FullName.Substring($root.Length + 1)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $errors += $relative
        Write-Result $relative $false "$($parseErrors[0].Message) (Zeile $($parseErrors[0].Extent.StartLineNumber))"
    } else {
        Write-Result $relative $true
    }
}

# --- 2. XAML --------------------------------------------------------------
Write-Host ''
Write-Host '  XAML' -ForegroundColor White
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

foreach ($file in Get-ChildItem "$root\src\xaml" -Recurse -Include '*.xaml' -File) {
    $checked++
    $relative = $file.FullName.Substring($root.Length + 1)
    try {
        $content = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $reader = New-Object Xml.XmlNodeReader ([xml]$content)
        [void][Windows.Markup.XamlReader]::Load($reader)
        Write-Result $relative $true
    } catch {
        $errors += $relative
        Write-Result $relative $false $_.Exception.Message
    }
}

# --- 3. JSON-Kataloge -----------------------------------------------------
Write-Host ''
Write-Host '  Kataloge' -ForegroundColor White
$catalogs = @(Get-ChildItem "$root\data" -Include '*.json' -File -Recurse -ErrorAction SilentlyContinue)
if ($catalogs.Count -eq 0) {
    Write-Host '         (noch keine Kataloge vorhanden)' -ForegroundColor DarkGray
}
foreach ($file in $catalogs) {
    $checked++
    $relative = $file.FullName.Substring($root.Length + 1)
    try {
        [void]([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json)
        Write-Result $relative $true
    } catch {
        $errors += $relative
        Write-Result $relative $false $_.Exception.Message
    }
}

# --- 4. Encoding ----------------------------------------------------------
Write-Host ''
Write-Host '  Encoding (UTF-8 mit BOM)' -ForegroundColor White
$noBom = @()
foreach ($file in Get-ChildItem $root -Recurse -Include '*.ps1', '*.xaml' -File |
    Where-Object { $_.FullName -notmatch '\\(offline|logs|backups|reports)\\' }) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        $noBom += $file.FullName.Substring($root.Length + 1)
    }
}
if ($noBom.Count -eq 0) {
    Write-Result 'alle Dateien mit BOM' $true
} else {
    $errors += 'Encoding'
    Write-Result "$($noBom.Count) Datei(en) ohne BOM" $false ($noBom -join ', ')
    Write-Host '         Abhilfe: tools\Repair-Encoding.ps1' -ForegroundColor DarkGray
}

# --- Ergebnis -------------------------------------------------------------
Write-Host ''
if ($errors.Count -eq 0) {
    Write-Host "  Ergebnis: $checked Prüfungen, keine Fehler." -ForegroundColor Green
    exit 0
} else {
    Write-Host "  Ergebnis: $($errors.Count) Problem(e) in $checked Prüfungen." -ForegroundColor Red
    exit 1
}
