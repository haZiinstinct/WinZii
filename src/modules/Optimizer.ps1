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

    # Bewusst if/elseif statt switch: ein "continue" innerhalb eines switch
    # beendet nur den switch, nicht den Schleifendurchlauf — der Eintrag wäre
    # trotzdem durchgerutscht und der Windows-Filter damit wirkungslos.
    $tweaks = foreach ($tweak in $catalog.tweaks) {
        if ($Category -and $tweak.category -notin $Category) { continue }
        if ($tweak.appliesTo -eq 'win11' -and -not $isWin11) { continue }
        if ($tweak.appliesTo -eq 'win10' -and $isWin11) { continue }
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
                # Manche Werte schreibt Windows selbst um — CopilotDisabledReason
                # etwa trägt seinen eigenen Grund ein. Sie werden weiterhin
                # gesetzt, taugen aber nicht als Nachweis: Sonst stünde der
                # Eintrag dauerhaft auf »teilweise«, obwohl er wirkt. Bewusst
                # eine if-Bedingung statt break — ein break bräche nur aus dem
                # switch aus, nicht aus der Schleife über die Aktionen.
                $pruefbar = $true
                if ($action.PSObject.Properties['verify']) { $pruefbar = [bool]$action.verify }
                if ($pruefbar) {
                    $checkable++
                    $current = Get-WzRegistryValue -Path $action.path -Name $action.name
                    if ($current.Exists -and "$($current.Value)" -eq "$($action.value)") { $matching++ }
                }
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
                # Get-WzAppxMatches steht in AiRemoval.ps1. Im Betrieb lädt
                # main.ps1 alle Module; wird zum Prüfen nur der Optimizer
                # geladen, fehlt sie — dann ist der Zustand nicht messbar und
                # darf auch nicht mitgezählt werden.
                if (Get-Command Get-WzAppxMatches -ErrorAction SilentlyContinue) {
                    $checkable++
                    if (-not (Get-WzAppxMatches -Patterns $action.patterns)) { $matching++ }
                }
            }
            'command' {
                # Ein Befehl hinterlässt keinen Wert, den man nachschlagen
                # könnte. Nennt der Katalog eine Prüfung, wird sie ausgeführt und
                # ihre Ausgabe gegen das Muster gehalten. Ohne Prüfung bleibt die
                # Aktion ununterscheidbar — sie zählt dann nicht mit, statt einen
                # Zustand zu behaupten, der nie gemessen wurde.
                if ($action.state) {
                    $checkable++
                    if (Test-WzCommandState -State $action.state) { $matching++ }
                }
            }
            'powerplan' {
                # Der Plan gilt als angewendet, wenn er der aktive ist.
                # Verglichen werden GUIDs, nicht Namen: Der Name enthält ein
                # »—«, das die Konsolen-Codepage nicht kennt — in der Ausgabe
                # von powercfg steht dort ein schlichter Bindestrich. Der
                # frühere Textvergleich traf deshalb nie zu, der Eintrag galt
                # selbst unmittelbar nach dem Anwenden als »nicht angewendet«.
                $checkable++
                $planGuid = Find-WzPowerScheme -Name $action.planName
                if ($planGuid) {
                    $aktiv = @{ exec = 'powercfg.exe'; args = '/getactivescheme'
                                pattern = [regex]::Escape($planGuid) }
                    if (Test-WzCommandState -State ([pscustomobject]$aktiv)) { $matching++ }
                }
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
        Write-WzLog (Get-WzText 'opt.logRestorePoint') -Level Action
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
                    'capability'    { 'Invoke-WzCapabilityAction' }
                    'feature'       { 'Invoke-WzFeatureAction' }
                    'command'       { 'Invoke-WzCommandAction' }
                    'powerplan'     { 'Invoke-WzPowerPlanAction' }
                    default         { $null }
                }
                if (-not $handler) {
                Write-WzLog (Get-WzText 'opt.logUnknownAction' @{ typ = $action.type }) -Level Warn
                    continue
                }
                # Handler, die ihre Fehler selbst abfangen, melden über die
                # Sitzung zurück. Der Merker wird je Aktion zurückgesetzt.
                $session.ActionFailed = $false
                & $handler -Action $action -Session $session -Tweak $tweak
                if ($session.ActionFailed) { $tweakFailed = $true }
            } catch {
                $tweakFailed = $true
            Write-WzLog (Get-WzText 'opt.logError' @{ grund = $_.Exception.Message }) -Level Error
            }
        }

        if ($tweakFailed) {
            $summary.Failed++
        } else {
            $summary.Applied++
            # Ein Neustart ist nur nötig, wenn der Eintrag auch wirklich
            # angewendet wurde — bisher erschien die Meldung selbst dann, wenn
            # alles fehlgeschlagen war, und verlor dadurch ihre Aussage.
            if ($tweak.requiresReboot) { $summary.RebootRequired = $true }
        }
        if ($session.NeedsReboot) { $summary.RebootRequired = $true }
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
        Write-WzLog (Get-WzText 'opt.logAlreadySet' @{ name = $Action.name }) -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'opt.logTestRegistry' @{ pfad = $path; name = $Action.name; wert = $Action.value }) -Level Test
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
    Write-WzLog (Get-WzText 'opt.logSet' @{ name = $Action.name; wert = $Action.value }) -Level Ok
}

function Invoke-WzServiceAction {
    param($Action, $Session, $Tweak)

    $service = Get-Service -Name $Action.serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-WzLog (Get-WzText 'opt.logNoService' @{ name = $Action.serviceName }) -Level Info
        return
    }

    $currentStartup = Get-WzServiceStartupType -Name $Action.serviceName
    if ($currentStartup -eq $Action.startupType -and $service.Status -ne 'Running') {
        Write-WzLog (Get-WzText 'opt.logAlreadySetService' @{ name = $Action.serviceName }) -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'opt.logTestService' @{ name = $Action.serviceName; vorher = $currentStartup; nachher = $Action.startupType }) -Level Test
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        startupType = $currentStartup
        status      = [string]$service.Status
    }

    if ($Action.stop -and $service.Status -eq 'Running') {
        # Bisher ohne jede Prüfung: Blieb der Dienst laufen, galt der Eintrag
        # trotzdem als erledigt — und weil requiresReboot bei beiden
        # Dienst-Einträgen false ist, erfuhr der Anwender nicht einmal, dass
        # ein Neustart nötig wäre, damit die Änderung greift.
        Stop-Service -Name $Action.serviceName -Force -ErrorAction SilentlyContinue
        $after = Get-Service -Name $Action.serviceName -ErrorAction SilentlyContinue
        if ($after -and $after.Status -eq 'Running') {
            Write-WzLog (Get-WzText 'opt.logServiceStillRuns' @{ name = $Action.serviceName }) -Level Warn
            if ($Session) { $Session.NeedsReboot = $true }
        }
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
    Write-WzLog (Get-WzText 'opt.logService' @{ name = $Action.serviceName; starttyp = $Action.startupType }) -Level Ok
}

function Invoke-WzScheduledTaskAction {
    param($Action, $Session, $Tweak)

    $task = Get-ScheduledTask -TaskPath $Action.taskPath -TaskName $Action.taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-WzLog (Get-WzText 'opt.logNoTask' @{ name = $Action.taskName }) -Level Info
        return
    }
    if ($Action.state -eq 'Disabled' -and $task.State -eq 'Disabled') {
        Write-WzLog (Get-WzText 'opt.logAlreadyDisabled' @{ name = $Action.taskName }) -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'opt.logTestTask' @{ name = $Action.taskName; zustand = $Action.state }) -Level Test
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
    Write-WzLog (Get-WzText 'opt.logTask' @{ name = $Action.taskName; zustand = $Action.state }) -Level Ok
}

function Invoke-WzFeatureAction {
    param($Action, $Session, $Tweak)

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $Action.featureName -ErrorAction SilentlyContinue
    if (-not $feature) {
        Write-WzLog (Get-WzText 'opt.logNoFeature' @{ name = $Action.featureName }) -Level Info
        return
    }
    $targetEnabled = ($Action.state -eq 'Enabled')
    $isEnabled = ($feature.State -eq 'Enabled')
    if ($targetEnabled -eq $isEnabled) {
        Write-WzLog (Get-WzText 'opt.logAlreadyTarget' @{ name = $Action.featureName }) -Level Info
        return
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'opt.logTestFeature' @{ name = $Action.featureName; zustand = $Action.state }) -Level Test
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
    Write-WzLog (Get-WzText 'opt.logFeature' @{ name = $Action.featureName; zustand = $Action.state }) -Level Ok
}

function Invoke-WzCommandAction {
    param($Action, $Session, $Tweak)

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'opt.logTestExec' @{ befehl = $Action.exec; argumente = $Action.args }) -Level Test
        return
    }

    # Kennt der Katalog einen Weg, den Vorzustand auszulesen (undoCapture),
    # wird er hier eingefangen und in die Undo-Sitzung geschrieben. Beispiel
    # Energiesparplan: Ohne das würde die Rücknahme stur auf »Ausbalanciert«
    # stellen und einen vom Hersteller eingerichteten Plan verwerfen.
    $previous = @{ note = (Get-WzText 'opt.noteCommandRun') }
    if ($Action.undoCapture) {
        $capture = Invoke-WzProcess -FilePath $Action.undoCapture.exec `
            -Arguments $Action.undoCapture.args -TimeoutSeconds 60
        if ($capture.ExitCode -eq 0 -and $capture.StdOut -match $Action.undoCapture.pattern) {
            $value = if ($Matches.Count -gt 1) { $Matches[1] } else { $Matches[0] }
            $previous.undoArgs = $Action.undoCapture.argsFormat -f $value
        } else {
            Write-WzLog (Get-WzText 'opt.logNoPreviousState') -Level Info
        }
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous $previous

    $result = Invoke-WzProcess -FilePath $Action.exec -Arguments $Action.args -TimeoutSeconds 120

    # Ein Fehlschlag heißt nicht immer, dass die Einstellung unmöglich wäre —
    # manchmal fehlt nur die Voraussetzung. Der Höchstleistungsplan etwa ist auf
    # vielen Geräten gar nicht angelegt, »/setactive« scheitert dann an einer
    # GUID, die es nicht gibt. Der Fallback schafft die Voraussetzung, danach
    # bekommt der Hauptbefehl einen zweiten Versuch. Er läuft ausschließlich nach
    # einem Fehlschlag: »-duplicatescheme« würde sonst bei jedem Durchgang eine
    # weitere Kopie des Plans anlegen.
    if ($result.ExitCode -ne 0 -and $Action.fallback) {
        Write-WzLog (Get-WzText 'opt.logFallback' @{ befehl = $Action.fallback.exec; argumente = $Action.fallback.args }) -Level Info
        $prepare = Invoke-WzProcess -FilePath $Action.fallback.exec `
            -Arguments $Action.fallback.args -TimeoutSeconds 120
        if ($prepare.ExitCode -eq 0) {
            $result = Invoke-WzProcess -FilePath $Action.exec -Arguments $Action.args -TimeoutSeconds 120
        }
    }

    if ($result.ExitCode -eq 0) {
        Write-WzLog (Get-WzText 'opt.logCommandRun' @{ befehl = "$($Action.exec) $($Action.args)" }) -Level Ok
    } elseif ($Action.failHint) {
        # Ein erklärter Fehlschlag ist besser als ein roher Exit-Code
        throw [string]$Action.failHint
    } else {
        throw (Get-WzText 'opt.errCommandCode' @{ befehl = $Action.exec; code = $result.ExitCode })
    }
}

function Find-WzPowerScheme {
    <#
    .SYNOPSIS
        GUID eines Energieplans anhand seines Namens, sonst $null.
    .DESCRIPTION
        Gesucht wird in der Registry, nicht in der Ausgabe von »powercfg /list«.
        Zwei Gründe, beide auf dem Abnahme-Notebook nachgewiesen:

        Erstens die Codierung. Der Planname enthält ein »—« (U+2014). Die
        Ausgabe von powercfg wird mit der Konsolen-Codepage gelesen, und weder
        850 noch 437 kennen dieses Zeichen — zurück kommt ein schlichter »-«.
        Der Textvergleich mit dem Katalognamen traf deshalb nie zu: Jeder
        Durchlauf hätte eine weitere Kopie angelegt, und der Eintrag galt
        selbst unmittelbar nach dem Anwenden als »nicht angewendet«.

        Zweitens die Vollständigkeit. »powercfg /list« zeigt auf demselben
        Gerät nur »Ausbalanciert«, obwohl sieben Schemata eingetragen sind.
        Die Registry zeigt alle und ist für Lesezugriffe nicht gesperrt.
    .OUTPUTS
        GUID als Zeichenkette, oder $null
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $schemePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    try {
        foreach ($key in @(Get-ChildItem -LiteralPath $schemePath -ErrorAction Stop)) {
            $friendly = (Get-ItemProperty -LiteralPath $key.PSPath -Name 'FriendlyName' `
                -ErrorAction SilentlyContinue).FriendlyName
            if ($friendly -eq $Name) { return $key.PSChildName }
        }
        # Alle Schemata stehen unter diesem Schlüssel — was hier fehlt, gibt es
        # nicht. Kein Ausweichweg über powercfg, der bei jedem Seitenaufbau
        # einen Prozess starten würde.
        return $null
    } catch {
        # Nur wenn der Schlüssel selbst nicht lesbar ist, bleibt die Textsuche.
        # Für jedes Zeichen, das die Konsolen-Codepage nicht abbilden kann,
        # steht dabei ein Platzhalter.
        $muster = [regex]::Replace($Name, '[^\x20-\x7E]', '?')
        $liste = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments '/list' -TimeoutSeconds 30
        foreach ($zeile in ($liste.StdOut -split "`r?`n")) {
            if ($zeile -notlike "*$muster*") { continue }
            $treffer = [regex]::Match($zeile,
                '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
            if ($treffer.Success) { return $treffer.Value }
        }
        return $null
    }
}

function Invoke-WzPowerPlanAction {
    <#
    .SYNOPSIS
        Legt einen eigenen Energieplan mit getrennten Netz- und Akkuwerten an
        und aktiviert ihn.
    .DESCRIPTION
        Bewusst ein eigener Plan statt Werte im vorhandenen: Der bisherige Plan
        bleibt unangetastet, und die Rücknahme ist ein Umschalten plus Löschen
        der Kopie — ohne die alten Werte einzeln sichern zu müssen.

        Alles läuft über GUIDs und über den Namen, den WinZii selbst vergibt.
        Die Textausgabe von powercfg ist übersetzt: »Wechselstromeinstellung«
        hier, »AC Power Setting Index« auf einem englischen Kundengerät. Ein
        Vergleich darauf würde dort scheitern, eine GUID nie.
    #>
    param($Action, $Session, $Tweak)

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'opt.logPlanTest' @{ name = $Action.planName }) -Level Test
        foreach ($setting in $Action.settings) {
            Write-WzLog (Get-WzText 'opt.logPlanSettingTest' @{ name = $setting.setting; ac = $setting.ac; dc = $setting.dc }) -Level Test
        }
        return
    }

    $guidMuster = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

    # 1. Den aktiven Plan festhalten. Ohne ihn gäbe es keinen Weg zurück, also
    #    wird hier abgebrochen statt blind weiterzumachen.
    $aktiv = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments '/getactivescheme' -TimeoutSeconds 30
    $vorher = $null
    if ($aktiv.ExitCode -eq 0 -and $aktiv.StdOut -match $guidMuster) { $vorher = $Matches[0] }
    if (-not $vorher) {
        Write-WzLog (Get-WzText 'opt.logNoActivePlan') -Level Error
        $Session.ActionFailed = $true
        return
    }

    # 2. Gibt es den Plan schon? Ohne diese Prüfung legt jeder weitere Durchlauf
    #    eine zusätzliche Kopie an, bis die Planliste zugemüllt ist.
    $planGuid = Find-WzPowerScheme -Name $Action.planName
    $neuAngelegt = $false

    if (-not $planGuid) {
        $kopie = Invoke-WzProcess -FilePath 'powercfg.exe' `
            -Arguments "-duplicatescheme $($Action.baseScheme)" -TimeoutSeconds 60
        # Bewusst [regex]::Match statt -match: Der Treffer wird hier außerhalb
        # der Bedingung gebraucht, und $Matches trägt bei verkürzter Auswertung
        # noch den Wert des vorherigen Vergleichs — man bekäme stillschweigend
        # die falsche GUID statt eines Fehlers.
        $neueGuid = [regex]::Match([string]$kopie.StdOut, $guidMuster)
        if ($kopie.ExitCode -ne 0 -or -not $neueGuid.Success) {
            Write-WzLog (Get-WzText 'opt.logPlanCreateFailed' @{ vorlage = $Action.baseScheme }) -Level Error
            $Session.ActionFailed = $true
            return
        }
        $planGuid = $neueGuid.Value
        $neuAngelegt = $true

        $beschreibung = if ($Action.planDescription) { $Action.planDescription } else { Get-WzText 'opt.planDefaultDescription' }
        [void](Invoke-WzProcess -FilePath 'powercfg.exe' `
            -Arguments "-changename $planGuid `"$($Action.planName)`" `"$beschreibung`"" -TimeoutSeconds 30)
        Write-WzLog (Get-WzText 'opt.logPlanCreated' @{ name = $Action.planName }) -Level Ok
    } else {
        Write-WzLog (Get-WzText 'opt.logPlanExists' @{ name = $Action.planName }) -Level Info
    }

    # 3. Erst sichern, dann verändern. Bricht etwas danach ab, lässt sich die
    #    angelegte Kopie trotzdem über die Rücknahme entfernen.
    $previous = @{ note = "Energieplan »$($Action.planName)«"; previousScheme = $vorher }
    if ($neuAngelegt) { $previous.createdScheme = $planGuid }
    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous $previous

    # 4. Werte je Betriebsart setzen.
    # Mitgezählt wird, wie viele der Werte, die Netz und Akku überhaupt
    # unterscheiden, wirklich angekommen sind — siehe Schritt 6.
    $unterschiedGewollt = 0
    $unterschiedGesetzt = 0
    foreach ($setting in $Action.settings) {
        $trenntBetriebsarten = ("$($setting.ac)" -ne "$($setting.dc)")
        if ($trenntBetriebsarten) { $unterschiedGewollt++ }
        $beideSeitenOk = $true

        $seiten = @(
            @{ Schalter = '/setacvalueindex'; Wert = $setting.ac; Betrieb = 'Netz' },
            @{ Schalter = '/setdcvalueindex'; Wert = $setting.dc; Betrieb = 'Akku' }
        )
        foreach ($seite in $seiten) {
            $gesetzt = Invoke-WzProcess -FilePath 'powercfg.exe' `
                -Arguments "$($seite.Schalter) $planGuid $($setting.subgroup) $($setting.setting) $($seite.Wert)" `
                -TimeoutSeconds 30
            if ($gesetzt.ExitCode -eq 0) { continue }
            $beideSeitenOk = $false

            # Nicht jedes Gerät bietet jede Einstellung an — Kühlungsrichtlinie
            # und Turbo-Verhalten sind auf manchen Notebooks ausgeblendet. Als
            # »optional« gekennzeichnete Werte dürfen den Eintrag deshalb nicht
            # scheitern lassen, die tragenden schon.
            if ($setting.optional) {
                Write-WzLog (Get-WzText 'opt.logSettingOptional' @{ name = $setting.setting; betrieb = $seite.Betrieb }) -Level Info
            } else {
                Write-WzLog (Get-WzText 'opt.logSettingFailed' @{ name = $setting.setting; betrieb = $seite.Betrieb; code = $gesetzt.ExitCode }) -Level Warn
                $Session.ActionFailed = $true
            }
        }
        if ($trenntBetriebsarten -and $beideSeitenOk) { $unterschiedGesetzt++ }
    }

    # 5. Aktivieren.
    $aktivieren = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments "/setactive $planGuid" -TimeoutSeconds 30
    if ($aktivieren.ExitCode -eq 0) {
        Write-WzLog (Get-WzText 'opt.logPlanActive' @{ name = $Action.planName }) -Level Ok
    } else {
        Write-WzLog (Get-WzText 'opt.logPlanActivateFailed' @{ code = $aktivieren.ExitCode }) -Level Error
        $Session.ActionFailed = $true
    }

    # 6. Und hat es etwas gebracht? Auf dem Abnahme-Notebook sind SYSCOOLPOL und
    #    PERFBOOSTMODE ausgeblendet (Attributes=1). Beide sind »optional«, also
    #    scheitert nichts — übrig bleiben aber nur Werte, die für Netz und Akku
    #    gleich sind. Der Plan wäre dann eine Kopie des bisherigen, während der
    #    Eintrag getrennte Betriebsarten verspricht. Das gehört ins Protokoll,
    #    statt es als Erfolg durchgehen zu lassen.
    if ($unterschiedGewollt -gt 0 -and $unterschiedGesetzt -eq 0) {
        Write-WzLog (Get-WzText 'opt.logPlanNoEffect') -Level Warn
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
            Write-WzLog (Get-WzText 'opt.logFeaturesUnreadable' @{ grund = $_.Exception.Message }) -Level Warn
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
            Write-WzLog (Get-WzText 'opt.logTasksUnreadable' @{ grund = $_.Exception.Message }) -Level Warn
        }
    }
    $key = "$TaskPath$TaskName"
    if ($script:WzTaskCache.ContainsKey($key)) { return $script:WzTaskCache[$key] }
    return $null
}

function Test-WzCommandState {
    <#
    .SYNOPSIS
        Prüft über einen lesenden Befehl, ob eine Kommando-Aktion bereits greift.
    .DESCRIPTION
        Die Ausgabe wird zwischengespeichert. Die Optimierungsseite ermittelt den
        Zustand beim Aufbau für jeden Eintrag, und ein eigener Prozessaufruf je
        Eintrag wäre als Verzögerung sichtbar.
    #>
    param([Parameter(Mandatory = $true)]$State)

    if (-not $script:WzCommandCache) { $script:WzCommandCache = @{} }
    $key = "$($State.exec) $($State.args)"

    if (-not $script:WzCommandCache.ContainsKey($key)) {
        $output = ''
        try {
            $run = Invoke-WzProcess -FilePath $State.exec -Arguments $State.args -TimeoutSeconds 20
            if ($run.ExitCode -eq 0) { $output = [string]$run.StdOut }
        } catch {
            Write-WzLog (Get-WzText 'opt.logStateUnreadable' @{ schluessel = $key; grund = $_.Exception.Message }) -Level Warn
        }
        $script:WzCommandCache[$key] = $output
    }

    if (-not $script:WzCommandCache[$key]) { return $false }
    return [bool]($script:WzCommandCache[$key] -match $State.pattern)
}

function Clear-WzStateCache {
    <#
    .SYNOPSIS
        Verwirft die Zwischenspeicher, damit der Zustand neu ermittelt wird.
    #>
    $script:WzFeatureCache = $null
    $script:WzTaskCache = $null
    $script:WzAppxCache = $null
    $script:WzCommandCache = $null
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

        Write-WzLog (Get-WzText 'opt.logInteractiveUser' @{ angemeldet = $interactive; konto = $currentName }) -Level Info
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
            'registry'      { Get-WzText 'opt.sumRegistry' @{ pfad = "$($action.path -replace '^HK(LM|CU):', 'HK$1')\$($action.name)"; wert = $action.value } }
            'service'       { Get-WzText 'opt.sumService' @{ name = $action.serviceName; ziel = $action.startupType } }
            'scheduledTask' { Get-WzText 'opt.sumTask' @{ name = $action.taskName; ziel = $action.state } }
            'appx'          { Get-WzText 'opt.sumAppx' @{ muster = ($action.patterns -join ', ') } }
            'capability'    { Get-WzText 'opt.sumCapability' @{ muster = ($action.patterns -join ', ') } }
            'feature'       { Get-WzText 'opt.sumFeature' @{ name = $action.featureName; ziel = $action.state } }
            'command'       { Get-WzText 'opt.sumCommand' @{ befehl = "$($action.exec) $($action.args)" } }
            'powerplan'     {
                $werte = foreach ($s in $action.settings) { Get-WzText 'opt.sumPowerSetting' @{ name = $s.setting; ac = $s.ac; dc = $s.dc } }
                Get-WzText 'opt.sumPowerPlan' @{ name = $action.planName; werte = ($werte -join ', ') }
            }
            default         { $action.type }
        }
    }
    return @($lines)
}
