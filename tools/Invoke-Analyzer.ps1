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

# -ErrorAction Stop: Ließ sich ein Modul nicht laden, fiel das Ergebnis
# bisher still auf 0 Befunde (Audit 2026-10, H13).
$results = @(Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Settings $settings -ErrorAction Stop)
$results += @(Invoke-ScriptAnalyzer -Path (Join-Path $root 'tools') -Recurse -Settings $settings -ErrorAction Stop)

# Write-Host ist in den Dev-Werkzeugen erwünscht — sie haben keine Oberfläche.
# Drei Globale sind Absicht: Programm und Hintergrund-Runspaces teilen sie.
# Jede weitere Globale fällt weiter auf.
$gewollteGlobale = '\$global:(WzRootPath|WzSessionStamp|syncHash)\b'
$results = @($results | Where-Object {
    -not ($_.RuleName -eq 'PSAvoidUsingWriteHost' -and $_.ScriptPath -like '*\tools\*') -and
    -not ($_.RuleName -eq 'PSAvoidUsingWriteHost' -and $_.ScriptName -eq 'launcher.ps1') -and
    -not ($_.RuleName -eq 'PSAvoidUsingWriteHost' -and $_.ScriptName -eq 'main.ps1') -and
    -not ($_.RuleName -eq 'PSAvoidGlobalVars' -and $_.Extent.Text -match $gewollteGlobale)
})

# Fehler, Parse-Fehler und Warnungen zählen alle als Fehlschlag. Bisher
# scheiterte die CI nur an Severity »Error«, und das hatte allein
# PSUseCompatibleSyntax; ein »$x -eq $null« oder ein Syntaxfehler in
# New-Release.ps1 ging durch (Audit 2026-10, H13).
$errors = @($results | Where-Object { $_.Severity -eq 'Error' -or "$($_.Severity)" -eq 'ParseError' })
$warnings = @($results | Where-Object { $_.Severity -eq 'Warning' })
$information = @($results | Where-Object { $_.Severity -eq 'Information' })

foreach ($item in $errors) {
    Write-Host "  [FEHL] $($item.ScriptName):$($item.Line)  $($item.RuleName)" -ForegroundColor Red
    Write-Host "         $($item.Message)" -ForegroundColor DarkGray
}

# Warnungen sind ein Fehlschlag und stehen deshalb immer da. -IncludeWarnings
# zeigt zusätzlich die Hinweise (Severity Information).
foreach ($item in $warnings) {
    Write-Host "  [warn] $($item.ScriptName):$($item.Line)  $($item.RuleName)" -ForegroundColor Yellow
    Write-Host "         $($item.Message)" -ForegroundColor DarkGray
}
if ($IncludeWarnings) {
    foreach ($item in $information) {
        Write-Host "  [info] $($item.ScriptName):$($item.Line)  $($item.RuleName)" -ForegroundColor DarkGray
    }
}

$sauber = ($errors.Count -eq 0 -and $warnings.Count -eq 0)
Write-Host ''
Write-Host "  Ergebnis: $($errors.Count) Fehler, $($warnings.Count) Warnungen, $($information.Count) Hinweise." -ForegroundColor $(if ($sauber) { 'Green' } else { 'Red' })
Write-Host ''

exit $(if ($sauber) { 0 } else { 1 })
