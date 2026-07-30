# Dev-Werkzeug: PSScriptAnalyzer mit Schwerpunkt auf PowerShell-5.1-Verträglichkeit.
# WinZii läuft auf fremden PCs mit der eingebauten PowerShell — moderne Syntax
# (Ternary, ??, ?.) würde dort erst zur Laufzeit scheitern.
[CmdletBinding()]
param([switch]$IncludeWarnings)

$root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host ''
    Write-Host '  PSScriptAnalyzer ist nicht installiert.' -ForegroundColor Yellow
    Write-Host '  Installation:  Install-Module PSScriptAnalyzer -Scope CurrentUser' -ForegroundColor DarkGray
    Write-Host ''
    exit 2
}

Import-Module PSScriptAnalyzer -ErrorAction Stop

$settings = @{
    IncludeRules = @(
        'PSUseCompatibleSyntax'
        'PSAvoidUsingCmdletAliases'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidUsingPositionalParameters'
        'PSUseApprovedVerbs'
        'PSAvoidGlobalVars'
        'PSAvoidUsingWriteHost'
        'PSPossibleIncorrectComparisonWithNull'
        'PSAvoidTrailingWhitespace'
        'PSUseBOMForUnicodeEncodedFile'
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
    }
}

Write-Host ''
Write-Host '  WinZii Code-Prüfung (Ziel: PowerShell 5.1)' -ForegroundColor Cyan
Write-Host ''

$results = @(Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Settings $settings -ErrorAction SilentlyContinue)
$results += @(Invoke-ScriptAnalyzer -Path (Join-Path $root 'tools') -Recurse -Settings $settings -ErrorAction SilentlyContinue)

# Write-Host ist in den Dev-Werkzeugen erwünscht — sie haben keine Oberfläche
$results = @($results | Where-Object {
    -not ($_.RuleName -eq 'PSAvoidUsingWriteHost' -and $_.ScriptPath -like '*\tools\*') -and
    -not ($_.RuleName -eq 'PSAvoidUsingWriteHost' -and $_.ScriptName -eq 'launcher.ps1') -and
    -not ($_.RuleName -eq 'PSAvoidUsingWriteHost' -and $_.ScriptName -eq 'main.ps1')
})

$errors = @($results | Where-Object { $_.Severity -eq 'Error' })
$warnings = @($results | Where-Object { $_.Severity -eq 'Warning' })
$information = @($results | Where-Object { $_.Severity -eq 'Information' })

foreach ($item in $errors) {
    Write-Host "  [FEHL] $($item.ScriptName):$($item.Line)  $($item.RuleName)" -ForegroundColor Red
    Write-Host "         $($item.Message)" -ForegroundColor DarkGray
}

if ($IncludeWarnings) {
    foreach ($item in $warnings) {
        Write-Host "  [warn] $($item.ScriptName):$($item.Line)  $($item.RuleName)" -ForegroundColor Yellow
        Write-Host "         $($item.Message)" -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host "  Ergebnis: $($errors.Count) Fehler, $($warnings.Count) Warnungen, $($information.Count) Hinweise." -ForegroundColor $(if ($errors.Count -eq 0) { 'Green' } else { 'Red' })
if (-not $IncludeWarnings -and $warnings.Count -gt 0) {
    Write-Host '  Warnungen anzeigen mit -IncludeWarnings' -ForegroundColor DarkGray
}
Write-Host ''

exit $(if ($errors.Count -eq 0) { 0 } else { 1 })
