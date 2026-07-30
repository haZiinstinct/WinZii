# Optimizer — deklarative Tweak-Engine.
# Alle Änderungen stehen in data\tweaks.json; dieses Modul führt sie aus.
# Dieselbe Engine bedient die Seiten "Optimierung" und "KI-Entfernung".
#
# Ablauf jeder Anwendung:
#   Bestätigung -> optional Wiederherstellungspunkt -> Registry-Export
#   -> Aktionen mit Zustandsaufzeichnung -> undo.json
# Im Testmodus wird nur protokolliert.

function Get-WzTweaks {
    <#
    .SYNOPSIS
        Liefert die Einträge aus dem Katalog, gefiltert nach Kategorie und
        Windows-Version.
    #>
    param([string[]]$Category)

    $catalog = Get-WzCatalog -Name 'tweaks'
    $build = if ($syncHash.SystemInfo) { $syncHash.SystemInfo.BuildNumber } else { 0 }
    if ($build -eq 0) {
        $build = try { [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild } catch { 0 }
    }
    $isWin11 = ($build -ge 22000)

    $tweaks = foreach ($tweak in $catalog.tweaks) {
        if ($Category -and $tweak.category -notin $Category) { continue }
        switch ($tweak.appliesTo) {
            'win11' { if (-not $isWin11) { continue } }
            'win10' { if ($isWin11) { continue } }
        }
        if ($tweak.PSObject.Properties['minBuild'] -and $build -lt $tweak.minBuild) { continue }
        $tweak
    }

    return @($tweaks)
}

function Get-WzTweakCategories {
    $catalog = Get-WzCatalog -Name 'tweaks'
    return @($catalog.categories)
}

function Test-WzTweakState {
    <#
    .SYNOPSIS
        Prüft, ob eine Änderung bereits angewendet ist.
    .OUTPUTS
        'Applied' | 'NotApplied' | 'Partial' | 'Unknown'
    #>
    param([Parameter(Mandatory = $true)]$Tweak)

    $checkable = 0
    $matching = 0

    foreach ($action in $Tweak.actions) {
        switch ($action.type) {
            'registry' {
                $checkable++
                $current = Get-WzRegistryValue -Path $action.path -Name $action.name
                if ($current.Exists -and "$($current.Value)" -eq "$($action.value)") { $matching++ }
            }
            'service' {
                $checkable++
                $service = Get-Service -Name $action.serviceName -ErrorAction SilentlyContinue
                if ($service) {
                    $startup = Get-WzServiceStartupType -Name $action.serviceName
                    if ($startup -eq $action.startupType) { $matching++ }
                } else {
                    # Dienst gibt es nicht mehr — Ziel gilt als erreicht
                    $matching++
                }
            }
            'scheduledTask' {
                $checkable++
                $task = Get-WzCachedTask -TaskPath $action.taskPath -TaskName $action.taskName
                if (-not $task) {
                    $matching++
                } elseif ($action.state -eq 'Disabled' -and $task.State -eq 'Disabled') {
                    $matching++
                } elseif ($action.state -eq 'Enabled' -and $task.State -ne 'Disabled') {
                    $matching++
                }
            }
            'appx' {
                $checkable++
                if (-not (Get-WzAppxMatches -Patterns $action.patterns)) { $matching++ }
            }
            'feature' {
                $checkable++
                $state = Get-WzCachedFeatureState -FeatureName $action.featureName
                if (-not $state) {
                    $matching++
                } elseif ($action.state -eq 'Disabled' -and $state -ne 'Enabled') {
                    $matching++
                } elseif ($action.state -eq 'Enabled' -and $state -eq 'Enabled') {
                    $matching++
                }
            }
        }
    }

    if ($checkable -eq 0) { return 'Unknown' }
    if ($matching -eq $checkable) { return 'Applied' }
    if ($matching -eq 0) { return 'NotApplied' }
    return 'Partial'
}

function Invoke-WzTweaks {
    <#
    .SYNOPSIS
        Wendet die übergebenen Einträge an, inklusive Sicherung und Undo-Datei.
    .PARAMETER CreateRestorePoint
        Vorab einen Systemwiederherstellungspunkt anlegen.
    .OUTPUTS
        PSCustomObject mit Applied, Failed, RebootRequired, UndoFile
    #>
    param(
        [Parameter(Mandatory = $true)]$Tweaks,
        [string]$Scope = 'tweaks',
        [switch]$CreateRestorePoint
    )

    $summary = [pscustomobject]@{
        Applied        = 0
        Failed         = 0
        RebootRequired = $false
        UndoFile       = $null
        Messages       = @()
    }

    $items = @($Tweaks)
    if ($items.Count -eq 0) { return $summary }

    if ($CreateRestorePoint) {
        Write-WzLog 'Erstelle Systemwiederherstellungspunkt (kann eine Minute dauern)...' -Level Action
        [void](New-WzRestorePoint -Description "WinZii — vor $Scope")
    }

    $session = New-WzUndoSession -Scope $Scope

    foreach ($tweak in $items) {
        Write-WzLog "$($tweak.name)" -Level Action
        $tweakFailed = $false

        foreach ($action in $tweak.actions) {
            try {
                $handler = switch ($action.type) {
                    'registry'      { 'Invoke-WzRegistryAction' }
                    'service'       { 'Invoke-WzServiceAction' }
                    'scheduledTask' { 'Invoke-WzScheduledTaskAction' }
                    'appx'          { 'Invoke-WzAppxAction' }
                    'cbsPackage'    { 'Invoke-WzCbsAction' }
                    'feature'       { 'Invoke-WzFeatureAction' }
                    'command'       { 'Invoke-WzCommandAction' }
                    default         { $null }
                }
                if (-not $handler) {
                    Write-WzLog "  Unbekannter Aktionstyp: $($action.type)" -Level Warn
                    continue
                }
                & $handler -Action $action -Session $session -Tweak $tweak
            } catch {
                $tweakFailed = $true
                Write-WzLog "  Fehler: $($_.Exception.Message)" -Level Error
            }
        }

        if ($tweakFailed) { $summary.Failed++ } else { $summary.Applied++ }
        if ($tweak.requiresReboot) { $summary.RebootRequired = $true }
    }

    if (-not $syncHash.DryRun) {
        $summary.UndoFile = Complete-WzUndoSession -Session $session
    } else {
        try { Remove-Item -LiteralPath $session.Directory -Recurse -Force -ErrorAction Stop } catch { }
    }

    return $summary
}

# ---------------------------------------------------------------------------
# Aktions-Handler. Jeder zeichnet den Vorzustand auf und respektiert den
# Testmodus.
# ---------------------------------------------------------------------------

function Invoke-WzRegistryAction {
    param($Action, $Session, $Tweak)

    $path = Resolve-WzRegistryPath $Action.path
    $current = Get-WzRegistryValue -Path $path -Name $Action.name
    if ($current.Exists -and "$($current.Value)" -eq "$($Action.value)") {
        Write-WzLog "  bereits gesetzt: $($Action.name)" -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog "  [Test] $path\$($Action.name) = $($Action.value)" -Level Test
        return
    }

    Export-WzRegistryKey -Session $Session -Path $path
    # Undo speichert den aufgelösten Pfad, damit das Zurücksetzen dieselbe
    # Stelle trifft wie das Setzen.
    $undoAction = $Action | Select-Object *
    $undoAction.path = $path
    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $undoAction -Previous @{
        existed   = $current.Exists
        value     = $current.Value
        valueType = if ($current.Exists) { $current.Type } else { $Action.valueType }
    }

    if (-not (Test-Path -LiteralPath $path)) {
        [void](New-Item -Path $path -Force -ErrorAction Stop)
    }
    Set-ItemProperty -Path $path -Name $Action.name -Value $Action.value -Type $Action.valueType -Force -ErrorAction Stop
    Write-WzLog "  gesetzt: $($Action.name) = $($Action.value)" -Level Ok
}

function Invoke-WzServiceAction {
    param($Action, $Session, $Tweak)

    $service = Get-Service -Name $Action.serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-WzLog "  Dienst nicht vorhanden: $($Action.serviceName)" -Level Info
        return
    }

    $currentStartup = Get-WzServiceStartupType -Name $Action.serviceName
    if ($currentStartup -eq $Action.startupType -and $service.Status -ne 'Running') {
        Write-WzLog "  bereits gesetzt: $($Action.serviceName)" -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog "  [Test] Dienst $($Action.serviceName): $currentStartup -> $($Action.startupType)" -Level Test
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        startupType = $currentStartup
        status      = [string]$service.Status
    }

    if ($Action.stop -and $service.Status -eq 'Running') {
        Stop-Service -Name $Action.serviceName -Force -ErrorAction SilentlyContinue
    }
    # Set-Service kann bei geschützten Diensten scheitern, dann direkt in die Registry
    try {
        Set-Service -Name $Action.serviceName -StartupType $Action.startupType -ErrorAction Stop
    } catch {
        $startValue = switch ($Action.startupType) {
            'Disabled'  { 4 }
            'Manual'    { 3 }
            'Automatic' { 2 }
            default     { 3 }
        }
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($Action.serviceName)" `
            -Name 'Start' -Value $startValue -Type DWord -ErrorAction Stop
    }
    Write-WzLog "  Dienst $($Action.serviceName): $($Action.startupType)" -Level Ok
}

function Invoke-WzScheduledTaskAction {
    param($Action, $Session, $Tweak)

    $task = Get-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-WzLog "  Aufgabe nicht vorhanden: $($Action.taskName)" -Level Info
        return
    }
    if ($Action.state -eq 'Disabled' -and $task.State -eq 'Disabled') {
        Write-WzLog "  bereits deaktiviert: $($Action.taskName)" -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog "  [Test] Aufgabe $($Action.taskName) -> $($Action.state)" -Level Test
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        state = [string]$task.State
    }

    if ($Action.state -eq 'Disabled') {
        Disable-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction Stop | Out-Null
    } else {
        Enable-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction Stop | Out-Null
    }
    Write-WzLog "  Aufgabe $($Action.taskName): $($Action.state)" -Level Ok
}

function Invoke-WzFeatureAction {
    param($Action, $Session, $Tweak)

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $Action.featureName -ErrorAction SilentlyContinue
    if (-not $feature) {
        Write-WzLog "  Funktion nicht vorhanden: $($Action.featureName)" -Level Info
        return
    }
    $targetEnabled = ($Action.state -eq 'Enabled')
    $isEnabled = ($feature.State -eq 'Enabled')
    if ($targetEnabled -eq $isEnabled) {
        Write-WzLog "  bereits im Zielzustand: $($Action.featureName)" -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog "  [Test] Funktion $($Action.featureName) -> $($Action.state)" -Level Test
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        state = [string]$feature.State
    }

    if ($targetEnabled) {
        Enable-WindowsOptionalFeature -Online -FeatureName $Action.featureName -NoRestart -ErrorAction Stop | Out-Null
    } else {
        Disable-WindowsOptionalFeature -Online -FeatureName $Action.featureName -NoRestart -ErrorAction Stop | Out-Null
    }
    Write-WzLog "  Funktion $($Action.featureName): $($Action.state)" -Level Ok
}

function Invoke-WzCommandAction {
    param($Action, $Session, $Tweak)

    if ($syncHash.DryRun) {
        Write-WzLog "  [Test] $($Action.exec) $($Action.args)" -Level Test
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        note = 'Befehl ausgeführt'
    }

    $result = Invoke-WzProcess -FilePath $Action.exec -Arguments $Action.args -TimeoutSeconds 120
    if ($result.ExitCode -eq 0) {
        Write-WzLog "  ausgeführt: $($Action.exec) $($Action.args)" -Level Ok
    } else {
        throw "$($Action.exec) endete mit Code $($result.ExitCode)"
    }
}

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

function Get-WzCachedFeatureState {
    <#
    .SYNOPSIS
        Zustand einer Windows-Funktion. Der erste Aufruf holt alle Funktionen
        auf einmal — einzeln kostet jede Abfrage ein bis drei Sekunden.
    #>
    param([Parameter(Mandatory = $true)][string]$FeatureName)

    if (-not $script:WzFeatureCache) {
        $script:WzFeatureCache = @{}
        try {
            foreach ($feature in Get-WindowsOptionalFeature -Online -ErrorAction Stop) {
                $script:WzFeatureCache[$feature.FeatureName] = [string]$feature.State
            }
        } catch {
            Write-WzLog "Windows-Funktionen nicht abfragbar: $($_.Exception.Message)" -Level Warn
        }
    }
    if ($script:WzFeatureCache.ContainsKey($FeatureName)) { return $script:WzFeatureCache[$FeatureName] }
    return $null
}

function Get-WzCachedTask {
    <#
    .SYNOPSIS
        Geplante Aufgabe aus dem Zwischenspeicher (alle Aufgaben auf einmal).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    if (-not $script:WzTaskCache) {
        $script:WzTaskCache = @{}
        try {
            foreach ($task in Get-ScheduledTask -ErrorAction Stop) {
                $script:WzTaskCache["$($task.TaskPath)$($task.TaskName)"] = $task
            }
        } catch {
            Write-WzLog "Geplante Aufgaben nicht abfragbar: $($_.Exception.Message)" -Level Warn
        }
    }
    $key = "$TaskPath$TaskName"
    if ($script:WzTaskCache.ContainsKey($key)) { return $script:WzTaskCache[$key] }
    return $null
}

function Clear-WzStateCache {
    <#
    .SYNOPSIS
        Verwirft die Zwischenspeicher, damit der Zustand neu ermittelt wird.
    #>
    $script:WzFeatureCache = $null
    $script:WzTaskCache = $null
    $script:WzAppxCache = $null
}

function Resolve-WzRegistryPath {
    <#
    .SYNOPSIS
        Löst HKCU auf das Profil des angemeldeten Anwenders auf.
    .DESCRIPTION
        WinZii läuft mit Administratorrechten. Startet der Techniker es über ein
        eigenes Admin-Konto, zeigt HKCU auf dessen Profil — die Einstellung würde
        beim falschen Benutzer landen. Deshalb wird auf HKEY_USERS\<SID des
        angemeldeten Anwenders> umgeschrieben, sobald sich die Konten unterscheiden.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -notlike 'HKCU:*') { return $Path }

    $sid = Get-WzInteractiveUserSid
    if (-not $sid) { return $Path }

    return $Path -replace '^HKCU:', "Registry::HKEY_USERS\$sid"
}

function Get-WzInteractiveUserSid {
    <#
    .SYNOPSIS
        SID des am Bildschirm angemeldeten Anwenders — aber nur, wenn das ein
        anderes Konto ist als das, unter dem WinZii läuft. Sonst $null.
    #>
    if ($script:WzInteractiveSid -is [string] -or $script:WzInteractiveSidChecked) {
        return $script:WzInteractiveSid
    }
    $script:WzInteractiveSidChecked = $true
    $script:WzInteractiveSid = $null

    try {
        $interactive = (Get-CimInstance -Query 'SELECT UserName FROM Win32_ComputerSystem' -ErrorAction Stop).UserName
        if (-not $interactive) { return $null }

        $currentName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($interactive -eq $currentName) { return $null }

        $account = New-Object Security.Principal.NTAccount($interactive)
        $sid = $account.Translate([Security.Principal.SecurityIdentifier]).Value

        # Nur verwenden, wenn der Profil-Hive tatsächlich geladen ist
        if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid")) { return $null }

        Write-WzLog "Angemeldet ist '$interactive', WinZii läuft als '$currentName' — Benutzereinstellungen werden für '$interactive' gesetzt." -Level Info
        $script:WzInteractiveSid = $sid
    } catch {
        $script:WzInteractiveSid = $null
    }
    return $script:WzInteractiveSid
}

function Get-WzRegistryValue {
    <#
    .SYNOPSIS
        Liest einen Registry-Wert samt Typ, ohne bei fehlendem Schlüssel zu scheitern.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $Path = Resolve-WzRegistryPath $Path

    $result = [pscustomobject]@{ Exists = $false; Value = $null; Type = 'DWord' }
    if (-not (Test-Path -LiteralPath $Path)) { return $result }

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $result.Exists = $true
        $result.Value = $item.$Name

        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $kind = $key.GetValueKind($Name)
        $result.Type = switch ($kind) {
            'DWord'        { 'DWord' }
            'QWord'        { 'QWord' }
            'String'       { 'String' }
            'ExpandString' { 'ExpandString' }
            'MultiString'  { 'MultiString' }
            'Binary'       { 'Binary' }
            default        { 'String' }
        }
    } catch {
        # Wert fehlt
    }
    return $result
}

function Get-WzServiceStartupType {
    <#
    .SYNOPSIS
        Starttyp eines Dienstes als Text (Get-Service liefert ihn unter
        PowerShell 5.1 nicht direkt).
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $start = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name 'Start' -ErrorAction SilentlyContinue).Start
    switch ($start) {
        0 { 'Boot' }
        1 { 'System' }
        2 { 'Automatic' }
        3 { 'Manual' }
        4 { 'Disabled' }
        default { 'Unknown' }
    }
}

function Get-WzTweakActionSummary {
    <#
    .SYNOPSIS
        Beschreibt die Aktionen eines Eintrags für den Bestätigungsdialog.
    #>
    param([Parameter(Mandatory = $true)]$Tweak)

    $lines = foreach ($action in $Tweak.actions) {
        switch ($action.type) {
            'registry'      { "Registry: $($action.path -replace '^HK(LM|CU):', 'HK$1')\$($action.name) = $($action.value)" }
            'service'       { "Dienst $($action.serviceName) -> $($action.startupType)" }
            'scheduledTask' { "Aufgabe $($action.taskName) -> $($action.state)" }
            'appx'          { "App entfernen: $($action.patterns -join ', ')" }
            'cbsPackage'    { "Systempaket entfernen: $($action.patterns -join ', ')" }
            'feature'       { "Windows-Funktion $($action.featureName) -> $($action.state)" }
            'command'       { "Befehl: $($action.exec) $($action.args)" }
            default         { $action.type }
        }
    }
    return @($lines)
}
