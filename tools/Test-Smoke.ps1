# Dev-Werkzeug: prüft ohne Systemeingriffe, ob WinZii startfähig ist.
#   1. Syntax aller PowerShell-Dateien
#   2. XAML-Dateien parsebar
#   3. JSON-Kataloge gültig
#   4. Encoding (UTF-8 mit BOM)
#   5. Log-Level jedes Write-WzLog-Aufrufs gegen das ValidateSet
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

# --- 5. Log-Level ----------------------------------------------------------
# Ein Level außerhalb des ValidateSet wirft erst zur Laufzeit, bei der
# Parameterbindung. »-Level Err« stand genau im Fehlerzweig des Dateiumzugs
# und brach ihn ab, statt den Fehler zu melden (Audit 2026-10, H8).
Write-Host ''
Write-Host '  Log-Level' -ForegroundColor White
$loggingAst = [Management.Automation.Language.Parser]::ParseFile("$root\src\modules\Core.Logging.ps1", [ref]$null, [ref]$null)
$writeLog = $loggingAst.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-WzLog' }, $true)
$levelParam = @($writeLog.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Level' })[0]
$validateSet = @($levelParam.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' })[0]
$allowedLevels = @($validateSet.PositionalArguments | ForEach-Object { $_.Value })

$badLevels = @()
foreach ($file in Get-ChildItem "$root\src", "$root\tools" -Recurse -Include '*.ps1' -File) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    $calls = $ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-WzLog' }, $true)
    foreach ($call in $calls) {
        $elements = $call.CommandElements
        for ($i = 0; $i -lt $elements.Count - 1; $i++) {
            if ($elements[$i] -is [Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -eq 'Level') {
                $value = $elements[$i + 1]
                if ($value -is [Management.Automation.Language.StringConstantExpressionAst] -and $allowedLevels -notcontains $value.Value) {
                    $badLevels += '{0}:{1} -Level {2}' -f $file.FullName.Substring($root.Length + 1), $value.Extent.StartLineNumber, $value.Value
                }
            }
        }
    }
}
$checked++
if ($allowedLevels.Count -eq 0) {
    $errors += 'Log-Level'
    Write-Result 'ValidateSet von Write-WzLog nicht gefunden' $false
} elseif ($badLevels.Count -eq 0) {
    Write-Result "alle -Level-Argumente gültig ($($allowedLevels -join ', '))" $true
} else {
    $errors += 'Log-Level'
    Write-Result "$($badLevels.Count) ungültige(s) -Level-Argument(e)" $false ($badLevels -join ', ')
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
