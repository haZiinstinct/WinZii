# Dev-Werkzeug: prüft die JSON-Kataloge auf Vollständigkeit und Konsistenz.
# Ein fehlender Pflichteintrag würde sonst erst zur Laufzeit auffallen —
# im schlimmsten Fall auf einem Kundenrechner.
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root 'data'
$problems = New-Object Collections.ArrayList
$checked = 0

function Add-Problem {
    param([string]$Catalog, [string]$Message)
    [void]$problems.Add("$Catalog : $Message")
}

function Read-Catalog {
    param([string]$Name)
    $path = Join-Path $dataDir "$Name.json"
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Problem $Name 'Datei fehlt'
        return $null
    }
    try {
        return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        Add-Problem $Name "nicht lesbar: $($_.Exception.Message)"
        return $null
    }
}

Write-Host ''
Write-Host '  WinZii Katalog-Prüfung' -ForegroundColor Cyan
Write-Host ''

# --- tweaks ----------------------------------------------------------------
$tweaks = Read-Catalog 'tweaks'
if ($tweaks) {
    $categoryIds = @($tweaks.categories | ForEach-Object { $_.id })
    $seenIds = @{}
    $validActions = @('registry', 'service', 'scheduledTask', 'appx', 'cbsPackage', 'capability', 'feature', 'command')

    foreach ($tweak in $tweaks.tweaks) {
        $checked++
        $label = if ($tweak.id) { $tweak.id } else { '(ohne Kennung)' }

        foreach ($field in @('id', 'category', 'name', 'description', 'level', 'risk')) {
            if (-not $tweak.$field) { Add-Problem 'tweaks' "$label : Feld '$field' fehlt" }
        }
        if ($seenIds.ContainsKey($tweak.id)) { Add-Problem 'tweaks' "$label : Kennung doppelt vergeben" }
        $seenIds[$tweak.id] = $true

        if ($tweak.category -notin $categoryIds) {
            Add-Problem 'tweaks' "$label : Kategorie '$($tweak.category)' ist nicht definiert"
        }
        if ($tweak.level -notin @('soft', 'hard')) { Add-Problem 'tweaks' "$label : level muss soft oder hard sein" }
        if ($tweak.risk -notin @('low', 'medium', 'high')) { Add-Problem 'tweaks' "$label : risk muss low, medium oder high sein" }
        if ($tweak.appliesTo -and $tweak.appliesTo -notin @('all', 'win10', 'win11')) {
            Add-Problem 'tweaks' "$label : appliesTo muss all, win10 oder win11 sein"
        }
        if (-not $tweak.actions -or @($tweak.actions).Count -eq 0) {
            Add-Problem 'tweaks' "$label : keine Aktionen hinterlegt"
        }

        foreach ($action in $tweak.actions) {
            if ($action.type -notin $validActions) {
                Add-Problem 'tweaks' "$label : unbekannter Aktionstyp '$($action.type)'"
                continue
            }
            switch ($action.type) {
                'registry' {
                    foreach ($field in @('path', 'name', 'valueType')) {
                        if (-not $action.$field) { Add-Problem 'tweaks' "$label : registry ohne '$field'" }
                    }
                    if ($action.path -notmatch '^HK(LM|CU|CR|U|CC):') {
                        Add-Problem 'tweaks' "$label : Registry-Pfad ohne gültigen Stamm ($($action.path))"
                    }
                    if ($action.valueType -notin @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')) {
                        Add-Problem 'tweaks' "$label : unbekannter Werttyp '$($action.valueType)'"
                    }
                }
                'service' {
                    if (-not $action.serviceName) { Add-Problem 'tweaks' "$label : service ohne serviceName" }
                    if ($action.startupType -notin @('Automatic', 'Manual', 'Disabled')) {
                        Add-Problem 'tweaks' "$label : ungültiger startupType"
                    }
                }
                'scheduledTask' {
                    foreach ($field in @('taskPath', 'taskName', 'state')) {
                        if (-not $action.$field) { Add-Problem 'tweaks' "$label : scheduledTask ohne '$field'" }
                    }
                }
                'command' {
                    if (-not $action.exec) { Add-Problem 'tweaks' "$label : command ohne exec" }
                    if (-not $action.undo) { Add-Problem 'tweaks' "$label : command ohne Rückgängig-Angabe" }
                }
                'appx' {
                    if (-not $action.patterns) { Add-Problem 'tweaks' "$label : appx ohne patterns" }
                    if (-not $action.undo) { Add-Problem 'tweaks' "$label : appx ohne Hinweis zum Zurückholen" }
                }
                'cbsPackage' {
                    if (-not $action.patterns) { Add-Problem 'tweaks' "$label : cbsPackage ohne patterns" }
                }
                'capability' {
                    if (-not $action.patterns) { Add-Problem 'tweaks' "$label : capability ohne patterns" }
                }
                'feature' {
                    if (-not $action.featureName) { Add-Problem 'tweaks' "$label : feature ohne featureName" }
                }
            }
        }
    }
    Write-Host "  tweaks      $($tweaks.tweaks.Count) Einträge in $($categoryIds.Count) Kategorien" -ForegroundColor Gray
}

# --- apps ------------------------------------------------------------------
$apps = Read-Catalog 'apps'
if ($apps) {
    $categoryIds = @($apps.categories | ForEach-Object { $_.id })
    $seenIds = @{}
    foreach ($app in $apps.apps) {
        $checked++
        $label = if ($app.id) { $app.id } else { '(ohne Kennung)' }
        foreach ($field in @('id', 'name', 'category', 'wingetId', 'description')) {
            if (-not $app.$field) { Add-Problem 'apps' "$label : Feld '$field' fehlt" }
        }
        if ($seenIds.ContainsKey($app.id)) { Add-Problem 'apps' "$label : Kennung doppelt vergeben" }
        $seenIds[$app.id] = $true
        if ($app.category -notin $categoryIds) {
            Add-Problem 'apps' "$label : Kategorie '$($app.category)' ist nicht definiert"
        }
        # winget-Kennungen sind immer Herausgeber.Paket — ein Tippfehler fällt
        # sonst erst beim Kunden auf, wenn die Installation nichts findet
        if ($app.wingetId -and $app.wingetId -notmatch '^[\w+.-]+\.[\w+.-]+$') {
            Add-Problem 'apps' "$label : '$($app.wingetId)' sieht nicht wie eine winget-Kennung aus"
        }
    }
    Write-Host "  apps        $($apps.apps.Count) Programme in $($categoryIds.Count) Kategorien" -ForegroundColor Gray
}

# --- cleanup ---------------------------------------------------------------
$cleanup = Read-Catalog 'cleanup'
if ($cleanup) {
    $groupIds = @($cleanup.groups | ForEach-Object { $_.id })
    $methods = @('files', 'recycleBin', 'doCache', 'dism', 'windowsOld', 'reportOnly')
    foreach ($category in $cleanup.categories) {
        $checked++
        $label = if ($category.id) { $category.id } else { '(ohne Kennung)' }
        foreach ($field in @('id', 'name', 'description', 'method', 'risk', 'group')) {
            if (-not $category.$field) { Add-Problem 'cleanup' "$label : Feld '$field' fehlt" }
        }
        if ($category.group -notin $groupIds) { Add-Problem 'cleanup' "$label : Gruppe '$($category.group)' ist nicht definiert" }
        if ($category.method -notin $methods) { Add-Problem 'cleanup' "$label : unbekannte Methode '$($category.method)'" }
        if ($category.method -in @('files', 'windowsOld', 'reportOnly') -and -not $category.paths) {
            Add-Problem 'cleanup' "$label : Methode '$($category.method)' braucht Pfade"
        }
        # Sicherheitsnetz: keine Pfade in eigene Dateien des Anwenders
        foreach ($path in $category.paths) {
            if ($category.method -ne 'reportOnly' -and
                $path -match '(?i)%USERPROFILE%\\(Documents|Desktop|Pictures|Downloads|Videos|Music)') {
                Add-Problem 'cleanup' "$label : Pfad zeigt in persönliche Dateien ($path)"
            }
        }
    }
    Write-Host "  cleanup     $($cleanup.categories.Count) Kategorien in $($groupIds.Count) Gruppen" -ForegroundColor Gray
}

# --- office ----------------------------------------------------------------
$office = Read-Catalog 'office'
if ($office) {
    foreach ($variant in $office.variants) {
        $checked++
        foreach ($field in @('id', 'name', 'productId', 'channel', 'description')) {
            if (-not $variant.$field) { Add-Problem 'office' "$($variant.id) : Feld '$field' fehlt" }
        }
    }
    if (-not $office.odtSetupUrl) { Add-Problem 'office' 'odtSetupUrl fehlt' }
    if (-not $office.libreOffice.wingetId) { Add-Problem 'office' 'libreOffice.wingetId fehlt' }
    Write-Host "  office      $($office.variants.Count) Ausgaben, $($office.languages.Count) Sprachen, $($office.apps.Count) Programme" -ForegroundColor Gray
}

# --- eventmap --------------------------------------------------------------
$eventmap = Read-Catalog 'eventmap'
if ($eventmap) {
    $seen = @{}
    foreach ($entry in $eventmap.entries) {
        $checked++
        $label = "$($entry.provider)/$($entry.id)"
        foreach ($field in @('provider', 'id', 'severity', 'title', 'explanation', 'recommendation')) {
            if ($null -eq $entry.$field -or $entry.$field -eq '') {
                Add-Problem 'eventmap' "$label : Feld '$field' fehlt"
            }
        }
        if ($entry.severity -notin @('critical', 'error', 'warning')) {
            Add-Problem 'eventmap' "$label : severity muss critical, error oder warning sein"
        }
        if ($seen.ContainsKey($label)) { Add-Problem 'eventmap' "$label : doppelt vorhanden" }
        $seen[$label] = $true
    }
    Write-Host "  eventmap    $($eventmap.entries.Count) gedeutete Ereignisse" -ForegroundColor Gray
}

# --- bugcheckmap -----------------------------------------------------------
$bugcheck = Read-Catalog 'bugcheckmap'
if ($bugcheck) {
    foreach ($entry in $bugcheck.entries) {
        $checked++
        foreach ($field in @('code', 'name', 'cause', 'recommendation')) {
            if (-not $entry.$field) { Add-Problem 'bugcheckmap' "$($entry.code) : Feld '$field' fehlt" }
        }
        if ($entry.code -notmatch '^0x[0-9A-F]{8}$') {
            Add-Problem 'bugcheckmap' "$($entry.code) : Stoppcode muss im Format 0x000000XX stehen"
        }
    }
    Write-Host "  bugcheckmap $($bugcheck.entries.Count) Stoppcodes" -ForegroundColor Gray
}

# --- bloatware -------------------------------------------------------------
$bloatware = Read-Catalog 'bloatware'
if ($bloatware) {
    foreach ($level in @('safe', 'extended')) {
        foreach ($entry in $bloatware.$level) {
            $checked++
            foreach ($field in @('pattern', 'name', 'description')) {
                if (-not $entry.$field) { Add-Problem 'bloatware' "$($entry.pattern) : Feld '$field' fehlt" }
            }
        }
    }
    Write-Host "  bloatware   $($bloatware.safe.Count) unstrittig, $($bloatware.extended.Count) erweitert" -ForegroundColor Gray
}

# --- Ergebnis --------------------------------------------------------------
Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host "  Ergebnis: $checked Einträge geprüft, keine Beanstandungen." -ForegroundColor Green
    exit 0
}
foreach ($problem in $problems) {
    Write-Host "  [FEHL] $problem" -ForegroundColor Red
}
Write-Host ''
Write-Host "  Ergebnis: $($problems.Count) Beanstandung(en) bei $checked Einträgen." -ForegroundColor Red
exit 1
