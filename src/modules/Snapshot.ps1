# Snapshot — was hat sich seit dem letzten Besuch verändert?
#
# Ein Kundengerät steht selten nur einmal auf dem Tisch. Beim zweiten Mal ist
# die erste Frage immer dieselbe: Was ist seitdem passiert? Windows beantwortet
# sie nicht — und die interessanteste Hälfte der Antwort bemerkt sonst niemand:
# Funktionsupdates drehen Telemetrie- und Datenschutzeinstellungen still
# zurück, und im Protokoll des letzten Besuchs steht, dass sie abgeschaltet
# waren.

function Get-WzSnapshotPath {
    <#
    .SYNOPSIS
        Wo die Momentaufnahme dieses Rechners liegt.
    .NOTES
        Auf dem Datenträger neben den Sicherungen, nicht im Profil des
        Kunden: Sie soll mit dem Stick reisen, nicht mit dem Gerät.
    #>
    return (Join-Path (New-WzDirectory (Get-WzPath 'offline' 'zustand')) "$env:COMPUTERNAME.json")
}

function New-WzSnapshot {
    <#
    .SYNOPSIS
        Nimmt den jetzigen Zustand auf: Programme, Autostart, Optimierungen,
        Speicherplatz.
    .DESCRIPTION
        Bewusst schmal gehalten. Aufgenommen wird, was sich zwischen zwei
        Besuchen erfahrungsgemäß ändert und wofür die Antwort dem Techniker
        etwas nützt — nicht alles, was sich messen lässt.
    #>
    [CmdletBinding()]
    param()

    $programs = @()
    try {
        $programs = @(Get-WzInstalledPrograms | ForEach-Object {
            [pscustomobject]@{ name = $_.Name; version = $_.Version }
        })
    } catch { }

    $autostart = @()
    try {
        $autostart = @(Get-WzAutostartItems | Where-Object { $_.Enabled } |
            ForEach-Object { $_.Name })
    } catch { }

    # Nur die Kennungen der Optimierungen, die gerade greifen. Beim Vergleich
    # zählt, welche dazugekommen und welche verschwunden sind.
    $tweaks = @()
    try {
        $catalog = Get-WzTweaks
        foreach ($tweak in $catalog) {
            if ((Test-WzTweakState -Tweak $tweak) -eq 'Applied') { $tweaks += $tweak.id }
        }
    } catch { }

    $volumes = @()
    try {
        $info = Get-WzSystemInfo
        $volumes = @($info.Volumes | ForEach-Object {
            [pscustomobject]@{ letter = $_.Letter; freeBytes = [int64]$_.FreeBytes }
        })
    } catch { }

    return [pscustomobject]@{
        computer   = $env:COMPUTERNAME
        created    = (Get-Date).ToString('o')
        version    = $syncHash.Version
        programs   = $programs
        autostart  = $autostart
        tweaks     = $tweaks
        volumes    = $volumes
    }
}

function Save-WzSnapshot {
    <#
    .SYNOPSIS
        Schreibt die Momentaufnahme auf den Datenträger.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ Success = $false; Path = ''; Programs = 0 }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'snap.logSaveTest') -Level Test
        return $result
    }

    $snapshot = New-WzSnapshot
    $path = Get-WzSnapshotPath
    try {
        Save-WzJson -InputObject $snapshot -Path $path
        $result.Success = $true
        $result.Path = $path
        $result.Programs = @($snapshot.programs).Count
        Write-WzLog (Get-WzText 'snap.logSaved' @{ datei = $path }) -Level Ok
    } catch {
        Write-WzLog (Get-WzText 'snap.logSaveFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return $result
}

function Get-WzSavedSnapshot {
    <#
    .SYNOPSIS
        Die zuletzt gespeicherte Momentaufnahme dieses Rechners, falls es eine gibt.
    #>
    [CmdletBinding()]
    param()

    $path = Get-WzSnapshotPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Read-WzJson -Path $path)
    } catch {
        Write-WzLog (Get-WzText 'snap.logUnreadable' @{ datei = $path }) -Level Warn
        return $null
    }
}

function Compare-WzSnapshot {
    <#
    .SYNOPSIS
        Vergleicht den jetzigen Zustand mit der gespeicherten Momentaufnahme.
    .OUTPUTS
        PSCustomObject mit Since, AddedPrograms, RemovedPrograms, UpdatedPrograms,
        AddedAutostart, LostTweaks, NewTweaks, SpaceChange, HasSnapshot
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{
        HasSnapshot     = $false
        Since           = $null
        AddedPrograms   = @()
        RemovedPrograms = @()
        UpdatedPrograms = @()
        AddedAutostart  = @()
        LostTweaks      = @()
        NewTweaks       = @()
        SpaceChange     = @()
    }

    $old = Get-WzSavedSnapshot
    if (-not $old) { return $result }
    $result.HasSnapshot = $true
    try { $result.Since = [datetime]::Parse($old.created) } catch { }

    $now = New-WzSnapshot

    # --- Programme ---------------------------------------------------------
    $oldByName = @{}
    foreach ($entry in @($old.programs)) { if ($entry.name) { $oldByName[$entry.name] = $entry.version } }
    $newByName = @{}
    foreach ($entry in @($now.programs)) { if ($entry.name) { $newByName[$entry.name] = $entry.version } }

    foreach ($name in $newByName.Keys) {
        if (-not $oldByName.ContainsKey($name)) {
            $result.AddedPrograms += $name
        } elseif ($oldByName[$name] -ne $newByName[$name]) {
            $result.UpdatedPrograms += Get-WzText 'snap.updatedItem' @{
                name = $name; alt = $oldByName[$name]; neu = $newByName[$name] }
        }
    }
    foreach ($name in $oldByName.Keys) {
        if (-not $newByName.ContainsKey($name)) { $result.RemovedPrograms += $name }
    }

    # --- Autostart ---------------------------------------------------------
    $oldAutostart = @($old.autostart)
    $result.AddedAutostart = @(@($now.autostart) | Where-Object { $oldAutostart -notcontains $_ })

    # --- Optimierungen -----------------------------------------------------
    # Die wertvollste Zeile dieser Karte: Ein Funktionsupdate dreht Telemetrie-
    # und Datenschutzeinstellungen still zurück. Ohne Vergleich merkt das
    # niemand, und im Protokoll des letzten Besuchs steht das Gegenteil.
    $oldTweaks = @($old.tweaks)
    $nowTweaks = @($now.tweaks)
    $result.LostTweaks = @($oldTweaks | Where-Object { $nowTweaks -notcontains $_ })
    $result.NewTweaks = @($nowTweaks | Where-Object { $oldTweaks -notcontains $_ })

    # --- Speicherplatz -----------------------------------------------------
    foreach ($volume in @($now.volumes)) {
        $before = @($old.volumes | Where-Object { $_.letter -eq $volume.letter })[0]
        if (-not $before) { continue }
        $difference = [int64]$volume.freeBytes - [int64]$before.freeBytes
        $result.SpaceChange += [pscustomobject]@{
            Letter = $volume.letter
            Bytes  = $difference
        }
    }

    return $result
}
