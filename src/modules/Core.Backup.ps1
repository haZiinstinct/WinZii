# Core.Backup — Sicherung vor jedem Eingriff.
# Drei Ebenen:
#   1. Systemwiederherstellungspunkt (optional, vom Anwender bestätigt)
#   2. Registry-Export der berührten Schlüssel als .reg-Datei
#   3. Undo-Datei mit dem exakten Zustand vor jeder Einzelaktion
# Alles landet unter backups\<hostname>\<zeitstempel>\.

function New-WzUndoSession {
    <#
    .SYNOPSIS
        Legt einen Sicherungsordner an und liefert das Sitzungsobjekt.
    .PARAMETER Scope
        Kurzbezeichnung, erscheint im Ordnernamen und in der Übersicht.
    #>
    param([Parameter(Mandatory = $true)][string]$Scope)

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $directory = Get-WzBackupDir -Stamp "$stamp-$Scope"

    return [pscustomobject]@{
        Scope        = $Scope
        Directory    = $directory
        Created      = Get-Date
        Entries      = New-Object Collections.ArrayList
        ExportedKeys = New-Object Collections.ArrayList
        # Handler, die ihre Fehler selbst abfangen (Appx, Systempakete,
        # Funktionen), melden hier zurück. Ohne das galt ein Eintrag als
        # erledigt, bei dem kein einziges Paket entfernt werden konnte.
        ActionFailed = $false
        # Ein Dienst, der sich nicht anhalten ließ, wirkt erst nach einem Neustart
        NeedsReboot  = $false
    }
}

function Save-WzUndoState {
    <#
    .SYNOPSIS
        Merkt sich den Zustand vor einer Änderung.
    .PARAMETER Item
        Bezeichnung der übergeordneten Änderung (Tweak-Name).
    .PARAMETER Action
        Die Aktion selbst (aus dem Katalog).
    .PARAMETER Previous
        Zustand vor der Änderung, als Hashtable.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$ItemId,
        [Parameter(Mandatory = $true)][string]$ItemName,
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)]$Previous
    )

    [void]$Session.Entries.Add([pscustomobject]@{
        itemId   = $ItemId
        itemName = $ItemName
        action   = $Action
        previous = $Previous
        time     = (Get-Date).ToString('s')
    })
}

function Complete-WzUndoSession {
    <#
    .SYNOPSIS
        Schreibt undo.json und eine lesbare Zusammenfassung.
    #>
    param([Parameter(Mandatory = $true)]$Session)

    if ($Session.Entries.Count -eq 0) {
        # Nichts geändert: leeren Ordner wieder entfernen
        try { Remove-Item -LiteralPath $Session.Directory -Recurse -Force -ErrorAction Stop } catch { }
        return $null
    }

    $manifest = [ordered]@{
        scope        = $Session.Scope
        created      = $Session.Created.ToString('s')
        host         = $env:COMPUTERNAME
        user         = "$env:USERDOMAIN\$env:USERNAME"
        winZiiVersion = $syncHash.Version
        entries      = @($Session.Entries)
        exportedKeys = @($Session.ExportedKeys)
    }

    $undoFile = Join-Path $Session.Directory 'undo.json'
    [void](Save-WzJson -InputObject $manifest -Path $undoFile -Depth 12)
    Write-WzLog "Sicherung abgelegt: $($Session.Directory)" -Level Info
    return $undoFile
}

function Export-WzRegistryKey {
    <#
    .SYNOPSIS
        Exportiert einen Registry-Schlüssel als .reg-Datei in den Sicherungsordner.
        Fehlt der Schlüssel, wird das vermerkt (beim Rückgängigmachen muss er
        dann wieder entfernt werden).
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($Session.ExportedKeys -contains $Path) { return }

    $regPath = ConvertTo-WzRegExePath $Path
    if (-not $regPath) { return }

    $fileName = ($regPath -replace '[\\:]', '_') + '.reg'
    $target = Join-Path $Session.Directory $fileName

    if (-not (Test-Path -LiteralPath $Path)) {
        [void]$Session.ExportedKeys.Add($Path)
        return
    }

    $result = Invoke-WzProcess -FilePath 'reg.exe' -Arguments "export `"$regPath`" `"$target`" /y"
    if ($result.ExitCode -eq 0) {
        [void]$Session.ExportedKeys.Add($Path)
    } else {
        Write-WzLog "Registry-Export fehlgeschlagen: $Path" -Level Warn
    }
}

function Test-WzSystemProtectionOn {
    <#
    .SYNOPSIS
        Ist der Systemschutz für das Systemlaufwerk eingeschaltet?
    .NOTES
        Auf Windows-11-OEM-Geräten ist er häufig aus. Ein Wiederherstellungspunkt
        schaltet ihn dann dauerhaft ein — das gehört in den Dialog, nicht nur
        hinterher ins Protokoll.
    #>
    [CmdletBinding()]
    param()

    try {
        $config = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction Stop
        return ([int]$config.RPSessionInterval -ne 0)
    } catch {
        return $false
    }
}

function ConvertTo-WzRegExePath {
    <#
    .SYNOPSIS
        Wandelt einen PowerShell-Pfad (HKLM:\...) in die Schreibweise von reg.exe um.
    #>
    param([string]$Path)
    if (-not $Path) { return $null }

    # Bei Elevierung mit einem fremden Konto löst Resolve-WzRegistryPath auf
    # »Registry::HKEY_USERS\<SID>\...« auf. Diese Schreibweise stand nicht in
    # der Tabelle, die Funktion lieferte $null, und Export-WzRegistryKey stieg
    # kommentarlos aus — für JEDEN HKCU-Wert entstand also keine .reg-Sicherung,
    # während die Oberfläche versprach, jeder Schlüssel werde gesichert.
    $providerMap = @{
        'Registry::HKEY_LOCAL_MACHINE' = 'HKLM'
        'Registry::HKEY_CURRENT_USER'  = 'HKCU'
        'Registry::HKEY_CLASSES_ROOT'  = 'HKCR'
        'Registry::HKEY_USERS'         = 'HKU'
        'Registry::HKEY_CURRENT_CONFIG' = 'HKCC'
    }
    foreach ($prefix in $providerMap.Keys) {
        if ($Path -like "$prefix\*") {
            return $Path -replace "^$([regex]::Escape($prefix))", $providerMap[$prefix]
        }
    }

    $map = @{
        'HKLM:'  = 'HKLM'
        'HKCU:'  = 'HKCU'
        'HKCR:'  = 'HKCR'
        'HKU:'   = 'HKU'
        'HKCC:'  = 'HKCC'
    }
    foreach ($prefix in $map.Keys) {
        if ($Path -like "$prefix\*") {
            return $Path -replace "^$([regex]::Escape($prefix))", $map[$prefix]
        }
    }
    return $null
}

function New-WzRestorePoint {
    <#
    .SYNOPSIS
        Erstellt einen Systemwiederherstellungspunkt.
        Windows erlaubt standardmäßig nur einen Punkt pro 24 Stunden; diese
        Sperre wird kurzzeitig aufgehoben und danach wiederhergestellt.
    .OUTPUTS
        $true bei Erfolg.
    #>
    param([string]$Description = 'WinZii — vor Änderungen')

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] Wiederherstellungspunkt '$Description' würde erstellt." -Level Test
        return $true
    }

    $frequencyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $previousFrequency = $null
    $frequencyChanged = $false

    try {
        # Systemschutz muss für C: aktiv sein. War er aus, ist das Einschalten
        # eine bleibende Änderung — die gehört ins Protokoll. Zurückschalten
        # wäre falsch: Damit wäre der frisch angelegte Punkt gleich wieder weg.
        $protectionWasOff = $false
        try {
            $restoreConfig = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
            $protectionWasOff = (-not $restoreConfig -or [int]$restoreConfig.RPSessionInterval -eq 0)
        } catch { }
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
            if ($protectionWasOff) {
                Write-WzLog "Der Systemschutz für $env:SystemDrive war ausgeschaltet und wurde eingeschaltet. Er bleibt an — sonst wäre der Punkt sofort wieder weg. Das kostet etwas Speicherplatz." -Level Warn
            }
        } catch {
            Write-WzLog 'Systemschutz konnte nicht aktiviert werden — Wiederherstellungspunkt evtl. nicht möglich.' -Level Warn
        }

        $current = Get-ItemProperty -Path $frequencyPath -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        $previousFrequency = if ($current) { $current.SystemRestorePointCreationFrequency } else { $null }
        Set-ItemProperty -Path $frequencyPath -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction Stop
        $frequencyChanged = $true

        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-WzLog "Wiederherstellungspunkt erstellt: $Description" -Level Ok
        return $true
    } catch {
        Write-WzLog "Wiederherstellungspunkt fehlgeschlagen: $($_.Exception.Message)" -Level Warn
        return $false
    } finally {
        if ($frequencyChanged) {
            try {
                if ($null -eq $previousFrequency) {
                    Remove-ItemProperty -Path $frequencyPath -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
                } else {
                    Set-ItemProperty -Path $frequencyPath -Name 'SystemRestorePointCreationFrequency' -Value $previousFrequency -Type DWord -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }
}

function Get-WzUndoSessions {
    <#
    .SYNOPSIS
        Listet vorhandene Sicherungen dieses PCs, neueste zuerst.
    #>
    $root = Get-WzBackupRoot
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $sessions = foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
        $undoFile = Join-Path $directory.FullName 'undo.json'
        if (-not (Test-Path -LiteralPath $undoFile)) { continue }
        $data = Read-WzJson -Path $undoFile
        if (-not $data) { continue }

        $created = $directory.CreationTime
        if ($data.created) {
            try { $created = [datetime]$data.created } catch { }
        }

        $restoredAt = $null
        if ($data.PSObject.Properties['restoredAt'] -and $data.restoredAt) {
            try { $restoredAt = [datetime]$data.restoredAt } catch { }
        }

        [pscustomobject]@{
            Directory   = $directory.FullName
            UndoFile    = $undoFile
            Scope       = $data.scope
            Created     = $created
            ItemCount   = @($data.entries | Select-Object -ExpandProperty itemId -Unique).Count
            ActionCount = @($data.entries).Count
            Restored    = ($null -ne $restoredAt)
            RestoredAt  = $restoredAt
            Data        = $data
        }
    }

    return @($sessions | Sort-Object Created -Descending)
}

function Restore-WzUndoSession {
    <#
    .SYNOPSIS
        Macht die Änderungen einer Sicherung rückgängig.
        Entfernte Apps und Systempakete lassen sich so nicht zurückholen —
        dafür wird ein Hinweis ausgegeben.
    .OUTPUTS
        PSCustomObject mit Restored, Skipped, Failed
    #>
    param([Parameter(Mandatory = $true)][string]$UndoFile)

    $data = Read-WzJson -Path $UndoFile
    if (-not $data) { throw "Sicherung nicht lesbar: $UndoFile" }

    $result = [pscustomobject]@{ Restored = 0; Skipped = 0; Failed = 0; Notes = @() }

    # Rückwärts abarbeiten, damit die zuletzt gesetzten Werte zuerst zurückgehen
    $entries = @($data.entries)
    [array]::Reverse($entries)

    foreach ($entry in $entries) {
        $action = $entry.action
        $previous = $entry.previous

        try {
            switch ($action.type) {
                'registry' {
                    if ($previous.existed) {
                        if (-not (Test-Path -LiteralPath $action.path)) {
                            [void](New-Item -Path $action.path -Force -ErrorAction Stop)
                        }
                        Set-ItemProperty -Path $action.path -Name $action.name `
                            -Value $previous.value -Type $previous.valueType -ErrorAction Stop
                    } else {
                        Remove-ItemProperty -Path $action.path -Name $action.name -ErrorAction SilentlyContinue
                    }
                    $result.Restored++
                }
                'service' {
                    if ($previous.startupType) {
                        Set-Service -Name $action.serviceName -StartupType $previous.startupType -ErrorAction Stop
                    }
                    if ($previous.status -eq 'Running') {
                        Start-Service -Name $action.serviceName -ErrorAction SilentlyContinue
                    }
                    $result.Restored++
                }
                'scheduledTask' {
                    if ($previous.state -eq 'Ready' -or $previous.state -eq 'Running') {
                        Enable-ScheduledTask -TaskPath $action.taskPath -TaskName $action.taskName -ErrorAction Stop | Out-Null
                    } else {
                        Disable-ScheduledTask -TaskPath $action.taskPath -TaskName $action.taskName -ErrorAction SilentlyContinue | Out-Null
                    }
                    $result.Restored++
                }
                'feature' {
                    $target = if ($previous.state -eq 'Enabled') { 'Enable' } else { 'Disable' }
                    if ($target -eq 'Enable') {
                        Enable-WindowsOptionalFeature -Online -FeatureName $action.featureName -NoRestart -ErrorAction Stop | Out-Null
                    } else {
                        Disable-WindowsOptionalFeature -Online -FeatureName $action.featureName -NoRestart -ErrorAction Stop | Out-Null
                    }
                    $result.Restored++
                }
                'command' {
                    if ($action.undo -and $action.undo.exec) {
                        # Der beim Anwenden eingefangene Vorzustand geht vor dem
                        # statischen Katalogwert — er stellt genau das wieder
                        # her, was vorher eingestellt war.
                        $undoArgs = $action.undo.args
                        if ($entry.previous -and $entry.previous.undoArgs) {
                            $undoArgs = $entry.previous.undoArgs
                        }
                        $undoResult = Invoke-WzProcess -FilePath $action.undo.exec -Arguments $undoArgs
                        if ($undoResult.ExitCode -eq 0) { $result.Restored++ } else { $result.Failed++ }
                    } else {
                        $result.Skipped++
                        $result.Notes += "$($entry.itemName): kein Rückgängig-Befehl hinterlegt"
                    }
                }
                'powerplan' {
                    # Die Reihenfolge ist zwingend: Ein aktiver Energieplan lässt
                    # sich nicht löschen. Erst auf den vorherigen zurückschalten,
                    # dann die Kopie entfernen.
                    $vorherigerPlan = $null
                    if ($entry.previous) { $vorherigerPlan = $entry.previous.previousScheme }

                    if ($vorherigerPlan) {
                        $zurueck = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments "/setactive $vorherigerPlan"
                        if ($zurueck.ExitCode -eq 0) { $result.Restored++ } else { $result.Failed++ }
                    } else {
                        $result.Skipped++
                        $result.Notes += "$($entry.itemName): kein vorheriger Energieplan vermerkt"
                    }

                    # Entfernt wird nur, was WinZii in diesem Lauf selbst angelegt
                    # hat. War der Plan schon vorher da, gehört er dem Anwender.
                    $eigeneKopie = $null
                    if ($entry.previous) { $eigeneKopie = $entry.previous.createdScheme }
                    if ($eigeneKopie -and $vorherigerPlan) {
                        [void](Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments "/delete $eigeneKopie")
                    }
                }
                default {
                    # appx, capability: nicht automatisch zurückholbar
                    $result.Skipped++
                    $hint = if ($action.undo -and $action.undo.hint) { $action.undo.hint } else { 'nicht automatisch wiederherstellbar' }
                    $note = "$($entry.itemName): $hint"
                    if ($result.Notes -notcontains $note) { $result.Notes += $note }
                }
            }
        } catch {
            $result.Failed++
            Write-WzLog "Rückgängig fehlgeschlagen ($($entry.itemName)): $($_.Exception.Message)" -Level Warn
        }
    }

    # Erledigt vermerken. Ohne diese Markierung bliebe die Sicherung für immer
    # die "neueste" und ältere wären nie erreichbar.
    if (-not $syncHash.DryRun) {
        try {
            $data | Add-Member -NotePropertyName 'restoredAt' -NotePropertyValue ((Get-Date).ToString('s')) -Force
            [void](Save-WzJson -InputObject $data -Path $UndoFile -Depth 12)
        } catch {
            Write-WzLog "Sicherung konnte nicht als zurückgenommen vermerkt werden: $($_.Exception.Message)" -Level Warn
        }
    }

    return $result
}
