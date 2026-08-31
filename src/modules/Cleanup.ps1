# Cleanup — erst analysieren, dann gezielt löschen.
#
# Grundsätze:
#   * Es wird nie automatisch gelöscht. Erst die Größen zeigen, dann auswählen.
#   * Nur System- und Zwischenspeicherorte aus data\cleanup.json — niemals
#     eigene Dateien des Anwenders.
#   * Der Download-Ordner wird ausschließlich ausgewertet, nie geleert.

function Get-WzCleanupCategories {
    <#
    .SYNOPSIS
        Kategorien aus dem Katalog, passend zum vorhandenen System gefiltert.
    #>
    $catalog = Get-WzCatalog -Name 'cleanup'
    $categories = foreach ($category in $catalog.categories) {
        # Browser-Kategorien nur zeigen, wenn der Browser überhaupt Daten hat
        if ($category.group -eq 'browser') {
            $hasData = $false
            foreach ($path in $category.paths) {
                $base = Split-Path -Parent (Expand-WzUserPath $path)
                $base = $base -replace '\\\*.*$', ''
                if (Test-Path -Path $base -ErrorAction SilentlyContinue) { $hasData = $true; break }
            }
            if (-not $hasData) { continue }
        }
        if ($category.method -eq 'windowsOld') {
            $target = Expand-WzUserPath $category.paths[0]
            if (-not (Test-Path -LiteralPath $target)) { continue }
        }
        $category
    }
    return @($categories)
}

function Get-WzCleanupGroups {
    $catalog = Get-WzCatalog -Name 'cleanup'
    return @($catalog.groups)
}

function Format-WzPathSetAge {
    <#
    .SYNOPSIS
        Formt die 90-Tage-Aufteilung einer Messung in einen Satz.
    .NOTES
        Measure-WzPathSet rechnet die Aufteilung ohnehin in jedem Durchlauf mit.
        »12.480 Dateien, davon 11.900 älter als 90 Tage« beantwortet die Frage,
        die vor dem Löschen wirklich zählt: Ist das hier Karteileiche oder etwas,
        das gestern noch gebraucht wurde?
    #>
    param([Parameter(Mandatory = $true)]$Measure)

    # Bei einer Handvoll Dateien ist die Aufteilung keine Auskunft, sondern eine
    # Zeile mehr unter jeder Kategorie. Erst ab einer nennenswerten Menge — oder
    # sobald überhaupt etwas Altes dabei ist — steht dort etwas Verwertbares.
    if ($Measure.Items -lt 20 -and $Measure.OldItems -le 0) { return '' }

    $culture = Get-WzLanguageCulture
    $total = $Measure.Items.ToString('N0', $culture)
    if ($Measure.OldItems -le 0) {
        return Get-WzText 'clean.filesAllNew' @{ gesamt = $total }
    }
    if ($Measure.OldItems -eq $Measure.Items) {
        return Get-WzText 'clean.filesAllOld' @{ gesamt = $total }
    }
    $old = $Measure.OldItems.ToString('N0', $culture)
    return Get-WzText 'clean.filesMixed' @{ gesamt = $total; alt = $old; groesse = (Format-WzBytes $Measure.OldBytes) }
}

function Measure-WzCleanupCategory {
    <#
    .SYNOPSIS
        Ermittelt Umfang und Dateizahl einer Kategorie, ohne etwas zu ändern.
    .OUTPUTS
        PSCustomObject mit Id, Bytes, Items, Detail, Blocked
    #>
    param([Parameter(Mandatory = $true)]$Category)

    $result = [pscustomobject]@{
        Id      = $Category.id
        Bytes   = [int64]0
        Items   = 0
        AgeText = ''
        Detail  = ''
        Blocked = $null
    }

    switch ($Category.method) {
        { $_ -in 'files', 'reportOnly' } {
            $measure = Measure-WzPathSet -Paths $Category.paths
            $result.Bytes = $measure.Bytes
            $result.Items = $measure.Items
            $result.AgeText = Format-WzPathSetAge -Measure $measure
        }
        'recycleBin' {
            try {
                $shell = New-Object -ComObject Shell.Application
                $bin = $shell.NameSpace(0x0a)
                foreach ($item in $bin.Items()) {
                    $result.Items++
                    try { $result.Bytes += [int64]$item.Size } catch { }
                }
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
            } catch {
                $result.Detail = Get-WzText 'clean.detailUnreadable'
            }
        }
        'doCache' {
            try {
                $cache = Get-DeliveryOptimizationStatus -ErrorAction Stop
                $result.Bytes = ($cache | Measure-Object -Property FileSizeInCache -Sum).Sum
                $result.Items = @($cache).Count
            } catch {
                $result.Detail = Get-WzText 'clean.detailNoService'
            }
        }
        'dism' {
            $result.Detail = Get-WzText 'clean.detailDismOnly'
        }
        'windowsOld' {
            $measure = Measure-WzPathSet -Paths $Category.paths -Recurse
            $result.Bytes = $measure.Bytes
            $result.Items = $measure.Items
        }
    }

    if ($Category.PSObject.Properties['blockingProcesses']) {
        $running = @($Category.blockingProcesses | Where-Object {
            Get-Process -Name $_ -ErrorAction SilentlyContinue
        })
        if ($running.Count -gt 0) {
            $result.Blocked = Get-WzText 'clean.blockedBy' @{ prozesse = ($running -join ', ') }
        }
    }

    return $result
}

function Measure-WzPathSet {
    <#
    .SYNOPSIS
        Summiert Größe und Anzahl der Dateien hinter einer Pfadliste mit Platzhaltern.
    .NOTES
        Bewusst über .NET statt Get-ChildItem -Recurse: Letzteres braucht auf
        einer einzelnen großen Datei wie MEMORY.DMP über eine Minute, weil es
        sie als Container zu durchsuchen versucht.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [switch]$Recurse
    )

    $bytes = [int64]0
    $items = 0
    $oldBytes = [int64]0
    $oldItems = 0
    $threshold = (Get-Date).AddDays(-90)

    foreach ($rawPath in $Paths) {
        $path = Expand-WzUserPath $rawPath

        # Platzhalter auflösen; das liefert Dateien und Ordner der ersten Ebene
        $targets = @()
        try {
            if ($path -match '[\*\?]') {
                $targets = @(Resolve-Path -Path $path -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty ProviderPath)
            } elseif (Test-Path -LiteralPath $path) {
                $targets = @($path)
            }
        } catch { }

        foreach ($target in $targets) {
            try {
                if ([IO.Directory]::Exists($target)) {
                    foreach ($file in [IO.Directory]::EnumerateFiles($target, '*', [IO.SearchOption]::AllDirectories)) {
                        try {
                            $info = New-Object IO.FileInfo($file)
                            $bytes += $info.Length
                            $items++
                            if ($info.LastWriteTime -lt $threshold) {
                                $oldBytes += $info.Length
                                $oldItems++
                            }
                        } catch { }
                    }
                } elseif ([IO.File]::Exists($target)) {
                    $info = New-Object IO.FileInfo($target)
                    $bytes += $info.Length
                    $items++
                    if ($info.LastWriteTime -lt $threshold) {
                        $oldBytes += $info.Length
                        $oldItems++
                    }
                }
            } catch {
                # Gesperrte oder geschützte Pfade überspringen
            }
        }
    }

    return [pscustomobject]@{
        Bytes    = $bytes
        Items    = $items
        OldBytes = $oldBytes
        OldItems = $oldItems
    }
}

function Invoke-WzCleanup {
    <#
    .SYNOPSIS
        Löscht die gewählten Kategorien.
    .OUTPUTS
        PSCustomObject mit FreedBytes, Removed, Failed, Messages
    #>
    param([Parameter(Mandatory = $true)]$Categories)

    $summary = [pscustomobject]@{
        FreedBytes = [int64]0
        Removed    = 0
        Failed     = 0
        Messages   = @()
    }

    foreach ($category in $Categories) {
        Write-WzLog "$($category.name)" -Level Action

        if ($category.method -eq 'reportOnly') {
            Write-WzLog (Get-WzText 'clean.logAnalysisOnly') -Level Info
            continue
        }

        $before = Measure-WzCleanupCategory -Category $category
        $stoppedServices = @()

        try {
            if ($category.PSObject.Properties['requiresServiceStop']) {
                foreach ($serviceName in $category.requiresServiceStop) {
                    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                    if ($service -and $service.Status -eq 'Running') {
                        if ($syncHash.DryRun) {
                            Write-WzLog (Get-WzText 'clean.logWouldStopService' @{ dienst = $serviceName }) -Level Test
                        } else {
                            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                            $stoppedServices += $serviceName
                        }
                    }
                }
            }

            switch ($category.method) {
                'files'      { $result = Remove-WzPathSet -Paths $category.paths }
                'windowsOld' { $result = Remove-WzWindowsOld -Path $category.paths[0] }
                'recycleBin' { $result = Clear-WzRecycleBin }
                'doCache'    { $result = Clear-WzDeliveryOptimization }
                'dism'       { $result = Invoke-WzComponentCleanup }
                default      { $result = [pscustomobject]@{ Removed = 0; Failed = 0 } }
            }

            $summary.Removed += $result.Removed
            $summary.Failed += $result.Failed
            if (-not $syncHash.DryRun -and $category.method -ne 'dism') {
                $after = Measure-WzCleanupCategory -Category $category
                $freed = [math]::Max(0, $before.Bytes - $after.Bytes)
                $summary.FreedBytes += $freed
                Write-WzLog "  $(Format-WzBytes $freed) freigegeben, $($result.Removed) Objekt(e) entfernt" -Level Ok
            }
        } catch {
            $summary.Failed++
            Write-WzLog "  Fehler: $($_.Exception.Message)" -Level Error
        } finally {
            foreach ($serviceName in $stoppedServices) {
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
            }
        }
    }

    return $summary
}

function Remove-WzPathSet {
    <#
    .SYNOPSIS
        Löscht Dateien hinter einer Pfadliste. Gesperrte Dateien werden
        übersprungen, das ist bei Zwischenspeichern normal.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $removed = 0
    $failed = 0

    foreach ($rawPath in $Paths) {
        $path = Expand-WzUserPath $rawPath

        if ($syncHash.DryRun) {
            $measure = Measure-WzPathSet -Paths @($rawPath)
            Write-WzLog "  [Test] $path — $($measure.Items) Objekt(e), $(Format-WzBytes $measure.Bytes)" -Level Test
            continue
        }

        try {
            $entries = Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                try {
                    Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
                    $removed++
                } catch {
                    $failed++
                }
            }
        } catch {
            $failed++
        }
    }

    return [pscustomobject]@{ Removed = $removed; Failed = $failed }
}

function Clear-WzRecycleBin {
    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'clean.logWouldEmptyBin') -Level Test
        return [pscustomobject]@{ Removed = 0; Failed = 0 }
    }
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        return [pscustomobject]@{ Removed = 1; Failed = 0 }
    } catch {
        # Ein leerer Papierkorb meldet ebenfalls einen Fehler
        return [pscustomobject]@{ Removed = 0; Failed = 0 }
    }
}

function Clear-WzDeliveryOptimization {
    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'clean.logWouldClearDo') -Level Test
        return [pscustomobject]@{ Removed = 0; Failed = 0 }
    }
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        return [pscustomobject]@{ Removed = 1; Failed = 0 }
    } catch {
        return [pscustomobject]@{ Removed = 0; Failed = 1 }
    }
}

function Invoke-WzComponentCleanup {
    <#
    .SYNOPSIS
        Räumt den Komponentenspeicher auf (DISM StartComponentCleanup).
        Läuft mehrere Minuten.
    #>
    param([switch]$AnalyzeOnly)

    $arguments = if ($AnalyzeOnly) {
        '/Online /Cleanup-Image /AnalyzeComponentStore'
    } else {
        '/Online /Cleanup-Image /StartComponentCleanup /NoRestart'
    }

    if ($syncHash.DryRun) {
        Write-WzLog "  [Test] dism.exe $arguments" -Level Test
        return [pscustomobject]@{ Removed = 0; Failed = 0 }
    }

    Write-WzLog (Get-WzText 'clean.logDismRunning') -Level Info
    $result = Invoke-WzProcess -FilePath 'dism.exe' -Arguments $arguments -TimeoutSeconds 1800

    if ($result.ExitCode -eq 0) {
        Write-WzLog (Get-WzText 'clean.logComponentStoreDone') -Level Ok
        return [pscustomobject]@{ Removed = 1; Failed = 0 }
    }
    Write-WzLog (Get-WzText 'clean.logDismFailed' @{ code = $result.ExitCode }) -Level Warn
    return [pscustomobject]@{ Removed = 0; Failed = 1 }
}

function Remove-WzWindowsOld {
    <#
    .SYNOPSIS
        Entfernt den Ordner der vorherigen Windows-Installation.
        Erst über die Datenträgerbereinigung, bei Bedarf mit Übernahme der
        Besitzrechte — der Ordner gehört TrustedInstaller.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $target = Expand-WzUserPath $Path
    if (-not (Test-Path -LiteralPath $target)) {
        Write-WzLog (Get-WzText 'clean.logNotPresent') -Level Info
        return [pscustomobject]@{ Removed = 0; Failed = 0 }
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'clean.logWouldRemoveTarget' @{ ziel = $target }) -Level Test
        return [pscustomobject]@{ Removed = 0; Failed = 0 }
    }

    # Weg 1: Datenträgerbereinigung mit vorbereiteter Auswahl
    try {
        $stateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Previous Installations'
        if (Test-Path -LiteralPath $stateKey) {
            Set-ItemProperty -Path $stateKey -Name 'StateFlags0117' -Value 2 -Type DWord -ErrorAction Stop
            $result = Invoke-WzProcess -FilePath 'cleanmgr.exe' -Arguments '/sagerun:117' -TimeoutSeconds 1800
            if ($result.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $target)) {
                Write-WzLog (Get-WzText 'clean.logRemovedViaCleanmgr') -Level Ok
                return [pscustomobject]@{ Removed = 1; Failed = 0 }
            }
        }
    } catch { }

    # Weg 2: Besitzrechte übernehmen und löschen
    Write-WzLog (Get-WzText 'clean.logTakingOwnership') -Level Info
    Invoke-WzTakeOwnership -Path $target

    try {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        Write-WzLog (Get-WzText 'clean.logRemovedShort') -Level Ok
        return [pscustomobject]@{ Removed = 1; Failed = 0 }
    } catch {
        Write-WzLog (Get-WzText 'clean.logPartialRemove' @{ grund = $_.Exception.Message }) -Level Warn
        return [pscustomobject]@{ Removed = 0; Failed = 1 }
    }
}

function Get-WzAffirmativeLetter {
    <#
    .SYNOPSIS
        Der Buchstabe, mit dem man in der Oberflächensprache von Windows „ja" sagt.
    #>
    $language = try { (Get-UICulture).TwoLetterISOLanguageName } catch { 'en' }
    switch ($language) {
        'de' { 'j' }  # Ja
        'nl' { 'j' }  # Ja
        'fr' { 'o' }  # Oui
        'es' { 's' }  # Sí
        'it' { 's' }  # Sì
        'pt' { 's' }  # Sim
        'pl' { 't' }  # Tak
        'tr' { 'e' }  # Evet
        default { 'y' }
    }
}

function Invoke-WzTakeOwnership {
    <#
    .SYNOPSIS
        Übernimmt Besitz und Vollzugriff für einen Ordnerbaum.
    .NOTES
        Die Standardantwort von takeown (/d) ist übersetzt: deutsch »J«, englisch
        »Y«, französisch »O«. Hier stand früher fest »j« — auf jedem nicht-deutschen
        Windows quittiert takeown das mit »Ungültiges Argument«, die Besitzübernahme
        scheitert still und Windows.old bleibt liegen. Der Buchstabe kommt jetzt aus
        der Oberflächensprache; passt er trotzdem nicht, wird der Reihe nach
        nachgesetzt statt aufzugeben.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $answers = @((Get-WzAffirmativeLetter), 'y', 'j') | Select-Object -Unique
    foreach ($answer in $answers) {
        $result = Invoke-WzProcess -FilePath 'takeown.exe' `
            -Arguments "/f `"$Path`" /r /d $answer" -TimeoutSeconds 900
        if ($result.ExitCode -eq 0) { break }
        # Nur wenn takeown den Buchstaben bemängelt, lohnt ein zweiter Versuch
        if ("$($result.StdOut) $($result.StdErr)" -notmatch '(?i)invalid|ungültig|ungueltig') { break }
    }

    [void](Invoke-WzProcess -FilePath 'icacls.exe' `
        -Arguments "`"$Path`" /grant *S-1-5-32-544:F /t /c /q" -TimeoutSeconds 900)
}
