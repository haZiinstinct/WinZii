# Seite "Updates" — ausstehende Windows-Updates finden und einspielen.
#
# Der Grund, warum es sie gibt: Beim Aufsetzen eines PCs ist das Einspielen der
# Updates Pflicht, und bisher musste der Techniker dafür das Fenster wechseln.
#
# Treiber stehen unten und sind nie vorausgewählt — dazu steht die Begründung
# im Modul.

function Initialize-WzUpdatesPage {
    $syncHash.UpdatesBtnScan.Add_Click({ Start-WzUpdateScan })
    $syncHash.UpdatesBtnAll.Add_Click({
        # Treiber bleiben aussen vor: »alle« meint die Updates, die Windows
        # ohnehin einspielen würde, nicht die Herstellerstände.
        foreach ($box in $syncHash.UpdateBoxes) {
            if (-not $box.Tag.IsDriver) { $box.IsChecked = $true }
        }
        Update-WzUpdateSelection
    })
    $syncHash.UpdatesBtnNone.Add_Click({
        foreach ($box in $syncHash.UpdateBoxes) { $box.IsChecked = $false }
        Update-WzUpdateSelection
    })
    $syncHash.UpdatesBtnInstall.Add_Click({ Start-WzUpdateInstall })
}

function Update-WzUpdatesPage {
    if ($syncHash.UpdatesLoaded) { return }
    $syncHash.UpdatesLoaded = $true
    $syncHash.UpdateBoxes = @()
    Write-WzUpdateState
}

function Write-WzUpdateState {
    <#
    .SYNOPSIS
        Die Zustandskarte — beantwortet, ob dieser PC überhaupt Updates bekommt.
    #>
    $syncHash.UpdatesStateRows.Children.Clear()

    Invoke-WzTask -Name (Get-WzText 'upd.taskState') -Silent -ScriptBlock {
        Get-WzUpdateState
    } -OnComplete {
        param($state)
        if (-not $state) { return }

        # Ueber $syncHash statt ueber eine oertliche Variable: Wenn der
        # Abschluss laeuft, ist Write-WzUpdateState laengst zurueck und ihr
        # Gueltigkeitsbereich abgeraeumt. Eine mitgenommene Variable waere
        # dann $null — der Fehler landete nur in der Nachbereitungsmeldung.
        $rows = $syncHash.UpdatesStateRows

        $dienst = if ($state.ServiceOk) {
            Get-WzText 'upd.serviceOk' @{ start = $state.ServiceStartup }
        } else {
            Get-WzText 'upd.serviceOff'
        }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'upd.lblService') $dienst `
            -Kind $(if ($state.ServiceOk) { 'ok' } else { 'warn' }) -LabelWidth 200))

        $letzte = if ($state.LastInstall) {
            Format-WzAgo $state.LastInstall
        } else {
            Get-WzText 'upd.neverInstalled'
        }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'upd.lblLast') $letzte -LabelWidth 200))

        if ($state.Managed) {
            [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'upd.lblManaged') `
                (Get-WzText 'upd.managed') -Kind 'warn' -LabelWidth 200))
        }
        if ($state.RebootPending) {
            [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'upd.lblReboot') `
                (Get-WzText 'upd.rebootPending') -Kind 'warn' -LabelWidth 200))
        }
    }
}

function Start-WzUpdateScan {
    # Die Suche fragt beim Server nach und dauert auf langsamen Verbindungen
    # ein bis zwei Minuten. Abbrechbar, weil sie nichts verändert.
    Invoke-WzTask -Name (Get-WzText 'upd.taskScan') -Cancelable -ScriptBlock {
        Find-WzUpdates
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if (-not $result.Ok) {
            $syncHash.UpdatesListTitle.Text = Get-WzText 'upd.searchFailed'
            Write-WzLog (Get-WzText 'upd.logSearchFailed' @{ grund = $result.Error }) -Level Error
            Show-WzInfo -Title (Get-WzText 'upd.searchFailedTitle') -Message $result.Error
            return
        }
        Write-WzUpdateList -Updates @($result.Updates)
    }
}

function Write-WzUpdateList {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Updates)

    # Erst die gewöhnlichen Updates, dann die Treiber. Das ist keine Kosmetik:
    # Wer von oben nach unten abhakt, hakt die Treiber zuletzt an — und liest
    # dann eher, was daneben steht.
    $normal = @($Updates | Where-Object { -not $_.IsDriver })
    $treiber = @($Updates | Where-Object { $_.IsDriver })
    $bytes = ($Updates | Measure-Object -Property SizeBytes -Sum).Sum

    $syncHash.UpdatesListTitle.Text = if ($Updates.Count -eq 0) {
        Get-WzText 'upd.upToDate'
    } else {
        Get-WzText 'upd.foundCount' @{ anzahl = $Updates.Count; groesse = (Format-WzBytes ([int64]$bytes)) }
    }

    $container = $syncHash.UpdatesList
    $container.Children.Clear()
    $syncHash.UpdateBoxes = @()

    foreach ($update in ($normal + $treiber)) {
        $teile = @()
        if ($update.KB) { $teile += $update.KB }
        if ($update.SizeBytes -gt 0) { $teile += Format-WzBytes $update.SizeBytes }
        if ($update.IsDownloaded) { $teile += Get-WzText 'upd.alreadyDownloaded' }
        if ($update.RebootRequired) { $teile += Get-WzText 'upd.needsReboot' }
        if ($update.IsDriver) { $teile += Get-WzText 'upd.driverHint' }

        $item = [pscustomobject]@{
            name        = $update.Title
            description = ($teile -join ' · ')
        }

        # Sicherheitsupdates bekommen ein Abzeichen — sie sind der Grund, warum
        # die Seite überhaupt existiert.
        $status = $null
        $kind = 'info'
        if ($update.IsDriver) {
            $status = Get-WzText 'upd.badgeDriver'
            $kind = 'warn'
        } elseif ($update.Severity -eq 'Critical') {
            $status = Get-WzText 'upd.badgeCritical'
            $kind = 'high'
        } elseif ($update.Severity -eq 'Important') {
            $status = Get-WzText 'upd.badgeImportant'
            $kind = 'medium'
        }

        $row = if ($status) {
            New-WzCheckRow -Item $item -IsChecked (-not $update.IsDriver) -StatusText $status -StatusKind $kind
        } else {
            New-WzCheckRow -Item $item -IsChecked (-not $update.IsDriver)
        }
        $row.CheckBox.Tag = $update
        $row.CheckBox.Add_Click({ Update-WzUpdateSelection })
        [void]$container.Children.Add($row.Row)
        $syncHash.UpdateBoxes += $row.CheckBox
    }

    $syncHash.UpdatesBtnAll.IsEnabled = ($Updates.Count -gt 0)
    $syncHash.UpdatesBtnNone.IsEnabled = ($Updates.Count -gt 0)
    Update-WzUpdateSelection
}

function Update-WzUpdateSelection {
    $selected = @($syncHash.UpdateBoxes | Where-Object { $_.IsChecked })
    $bytes = ($selected | ForEach-Object { $_.Tag.SizeBytes } | Measure-Object -Sum).Sum
    $syncHash.UpdatesSelection.Text = if ($selected.Count -eq 0) {
        Get-WzText 'upd.selectionCount'
    } else {
        Get-WzText 'upd.selectedCount' @{ anzahl = $selected.Count; groesse = (Format-WzBytes ([int64]$bytes)) }
    }
    $syncHash.UpdatesBtnInstall.IsEnabled = ($selected.Count -gt 0)
}

function Start-WzUpdateInstall {
    $selected = @($syncHash.UpdateBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    $bytes = ($selected | Measure-Object -Property SizeBytes -Sum).Sum
    $neustart = @($selected | Where-Object { $_.RebootRequired }).Count
    $treiber = @($selected | Where-Object { $_.IsDriver }).Count

    $message = Get-WzText 'upd.confirmMessage' @{ anzahl = $selected.Count; groesse = (Format-WzBytes ([int64]$bytes)) }
    if ($neustart -gt 0) { $message += "`n`n" + (Get-WzText 'upd.confirmReboot' @{ anzahl = $neustart }) }
    if ($treiber -gt 0) { $message += "`n`n" + (Get-WzText 'upd.confirmDriver' @{ anzahl = $treiber }) }
    if ($syncHash.DryRun) { $message += "`n`n" + (Get-WzText 'upd.confirmDryRun') }

    $answer = Show-WzConfirm -Title (Get-WzText 'upd.confirmTitle') -Message $message `
        -Items @($selected | Select-Object -First 12 | ForEach-Object { $_.Title }) `
        -ConfirmText $(if ($syncHash.DryRun) { Get-WzText 'upd.btnDryRun' } else { Get-WzText 'upd.btnInstallNow' })
    if (-not $answer.Confirmed) { return }

    $ids = @($selected | ForEach-Object { $_.Id })
    Invoke-WzTask -Name (Get-WzText 'upd.taskInstall') -ArgumentList @(, $ids) -ScriptBlock {
        param($ids)
        Install-WzUpdates -UpdateIds $ids
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        $zeilen = @()
        if ($summary.Installed -gt 0) { $zeilen += Get-WzText 'upd.lineInstalled' @{ anzahl = $summary.Installed } }
        if ($summary.Skipped -gt 0) { $zeilen += Get-WzText 'upd.lineSkipped' @{ anzahl = $summary.Skipped } }
        if ($summary.Failed -gt 0) { $zeilen += Get-WzText 'upd.lineFailed' @{ anzahl = $summary.Failed } }
        if ($summary.RebootRequired) { $zeilen += Get-WzText 'upd.lineReboot' }

        Show-WzInfo -Title (Get-WzText 'upd.doneTitle') -Message ($zeilen -join ' ') -Items @($summary.Details)

        if ($summary.Installed -gt 0) {
            Add-WzAction -Area 'Updates' -RebootRequired:([bool]$summary.RebootRequired) `
                -Summary (Get-WzText 'upd.actionInstalled' @{ anzahl = $summary.Installed }) `
                -Detail $summary.Details
        }

        # Nach dem Einspielen ist die Liste veraltet — der Zustand ebenso.
        Write-WzUpdateState
        Start-WzUpdateScan
    }
}
