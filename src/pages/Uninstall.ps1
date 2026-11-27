# Seite "Deinstallieren" — installierte Programme auflisten, filtern,
# sortieren, entfernen und die Reste wegräumen.

function Initialize-WzUninstallPage {
    $syncHash.UninstallAllPrograms = @()
    $syncHash.UninstallShowAll = $false

    foreach ($mode in @(
        @{ Id = 'name'; Label = (Get-WzText 'unin.sortName') }
        @{ Id = 'size'; Label = (Get-WzText 'unin.sortSize') }
        @{ Id = 'date'; Label = (Get-WzText 'unin.sortDate') }
    )) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = $mode.Label
        $item.Tag = $mode.Id
        [void]$syncHash.UninstallSort.Items.Add($item)
    }
    $syncHash.UninstallSort.SelectedIndex = 0

    $syncHash.UninstallBtnScan.Add_Click({ Start-WzUninstallScan })
    $syncHash.UninstallBtnRemove.Add_Click({ Start-WzUninstallSelected })
    $syncHash.UninstallSearch.Add_TextChanged({
        $syncHash.UninstallShowAll = $false
        Update-WzUninstallView
    })
    $syncHash.UninstallSort.Add_SelectionChanged({ Update-WzUninstallView })
}

function Update-WzUninstallPage {
    if ($syncHash.UninstallList.Children.Count -gt 0) { return }
    Start-WzUninstallScan
}

function Start-WzUninstallScan {
    $syncHash.UninstallTitle.Text = Get-WzText 'unin.reading'
    $syncHash.UninstallList.Children.Clear()
    $syncHash.UninstallShowAll = $false

    Invoke-WzTask -Name (Get-WzText 'unin.taskScan') -Cancelable -Silent -ScriptBlock {
        Get-WzInstalledPrograms
    } -OnComplete {
        param($programs)
        if (-not $programs) { $programs = @() }
        $syncHash.UninstallAllPrograms = @($programs)
        Update-WzUninstallView
    }
}

function Update-WzUninstallView {
    $all = @($syncHash.UninstallAllPrograms)
    $filter = if ($syncHash.UninstallSearch) { $syncHash.UninstallSearch.Text.Trim() } else { '' }

    $filtered = if ($filter) {
        $tokens = @($filter.ToLowerInvariant() -split '\s+' | Where-Object { $_ })
        @($all | Where-Object {
            $hay = "$($_.Name) $($_.Publisher) $($_.Version)".ToLowerInvariant()
            $ok = $true
            foreach ($t in $tokens) {
                if ($hay.IndexOf($t, [StringComparison]::Ordinal) -lt 0) { $ok = $false; break }
            }
            $ok
        })
    } else {
        $all
    }

    $sortMode = if ($syncHash.UninstallSort -and $syncHash.UninstallSort.SelectedItem) {
        [string]$syncHash.UninstallSort.SelectedItem.Tag
    } else { 'name' }

    $sorted = switch ($sortMode) {
        'size' { @($filtered | Sort-Object @{ Expression = 'SizeBytes'; Descending = $true }, Name) }
        'date' { @($filtered | Sort-Object @{ Expression = { if ($null -eq $_.Installed) { [datetime]::MinValue } else { $_.Installed } }; Descending = $true }, Name) }
        default { @($filtered | Sort-Object Name) }
    }

    Write-WzUninstallList -Programs $sorted
}

function Write-WzUninstallList {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Programs)

    $filter = $syncHash.UninstallSearch.Text.Trim()
    $syncHash.UninstallTitle.Text = if ($Programs.Count -eq 0 -and $filter) {
        Get-WzText 'unin.noMatch' @{ filter = $filter }
    } elseif ($Programs.Count -eq 0) {
        Get-WzText 'unin.noPrograms'
    } elseif ($filter) {
        Get-WzText 'unin.matches' @{ anzahl = $Programs.Count; filter = $filter }
    } else {
        Get-WzText 'unin.installedCount' @{ anzahl = $Programs.Count }
    }

    $container = $syncHash.UninstallList
    $container.Children.Clear()
    $syncHash.UninstallBoxes = @()

    $limit = if ($syncHash.UninstallShowAll -or $filter) { $Programs.Count } else { 50 }
    $shown = @($Programs | Select-Object -First $limit)
    foreach ($program in $shown) {
        $parts = @()
        if ($program.Version) { $parts += $program.Version }
        if ($program.Publisher) { $parts += $program.Publisher }
        if ($program.SizeBytes -gt 0) { $parts += Format-WzBytes $program.SizeBytes }
        if ($program.Installed) { $parts += $program.Installed.ToString('d', (Get-WzLanguageCulture)) }
        if (-not $program.CanSilent) { $parts += Get-WzText 'unin.asksOnRemoval' }

        $item = [pscustomobject]@{
            name        = $program.Name
            description = ($parts -join ' · ')
        }
        $row = New-WzCheckRow -Item $item -IsChecked $false
        $row.CheckBox.Tag = $program
        $row.CheckBox.Add_Click({ Update-WzUninstallSelection })
        [void]$container.Children.Add($row.Row)
        $syncHash.UninstallBoxes += $row.CheckBox
    }

    if ($Programs.Count -gt $shown.Count) {
        $remaining = $Programs.Count - $shown.Count
        $showAllBtn = New-Object Windows.Controls.Button
        $showAllBtn.Style = $syncHash.Window.FindResource('WzBtnSecondary')
        $showAllBtn.Content = Get-WzText 'unin.btnShowAll' @{ anzahl = $remaining }
        $showAllBtn.HorizontalAlignment = 'Left'
        $showAllBtn.Margin = New-Object Windows.Thickness(0, 10, 0, 0)
        $showAllBtn.Add_Click({
            $syncHash.UninstallShowAll = $true
            Update-WzUninstallView
        })
        [void]$container.Children.Add($showAllBtn)
    }

    Update-WzUninstallSelection
}

function Update-WzUninstallSelection {
    $count = @($syncHash.UninstallBoxes | Where-Object { $_.IsChecked }).Count
    $syncHash.UninstallBtnRemove.IsEnabled = ($count -gt 0)
}

function Start-WzUninstallSelected {
    $selected = @($syncHash.UninstallBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    $loud = @($selected | Where-Object { -not $_.CanSilent })
    $message = Get-WzText 'unin.confirmMessage' @{ anzahl = $selected.Count }
    if ($loud.Count -gt 0) {
        $message += "`n`n" + (Get-WzText 'unin.confirmLoud' @{ anzahl = $loud.Count })
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'unin.confirmTitle') -Message $message `
        -Items @($selected | ForEach-Object { $_.Name }) `
        -ConfirmText (Get-WzText 'unin.btnConfirmRemove') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'unin.taskRemove') -ArgumentList (, $selected) -ScriptBlock {
        param($programs)
        $summary = Uninstall-WzPrograms -Programs $programs
        $leftovers = @()
        if (@($summary.RemovedPrograms).Count -gt 0) {
            $leftovers = @(Find-WzUninstallLeftovers -Programs $summary.RemovedPrograms)
        }
        [pscustomobject]@{ Summary = $summary; Leftovers = $leftovers }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $summary = $result.Summary
        $leftovers = @($result.Leftovers | Where-Object { $_ })

        $detail = if ($syncHash.DryRun) {
            @($selected | ForEach-Object { $_.Name })
        } else {
            $weg = @($summary.RemovedPrograms | ForEach-Object { $_.Name })
            $weg + @($selected | Where-Object { $weg -notcontains $_.Name } |
                ForEach-Object { Get-WzText 'unin.detailFailed' @{ name = $_.Name } })
        }
        if ($summary.Removed -gt 0 -or $summary.Failed -gt 0) {
            Add-WzAction -Area 'Programme' `
                -Summary ((Get-WzText 'unin.actionRemoved' @{ anzahl = $summary.Removed }) + $(if ($summary.Failed -gt 0) { Get-WzText 'unin.actionFailedSuffix' @{ anzahl = $summary.Failed } })) `
                -Detail @($detail)
        }

        if ($leftovers.Count -eq 0) {
            Show-WzInfo -Title (Get-WzText 'unin.doneTitle') `
                -Message ((Get-WzText 'unin.doneMessage' @{ entfernt = $summary.Removed; fehlgeschlagen = $summary.Failed }) + $(if ($summary.Removed -gt 0) { Get-WzText 'unin.doneNoLeftovers' })) `
                -Items @($summary.Details)
            Start-WzUninstallScan
            return
        }

        $bytes = [int64]0
        $measure = ($leftovers | Measure-Object -Property SizeBytes -Sum).Sum
        if ($measure) { $bytes = [int64]$measure }

        $answer = Show-WzConfirm -Title (Get-WzText 'unin.doneTitle') `
            -Message (Get-WzText 'unin.leftoverMessage' @{
                entfernt = $summary.Removed; fehlgeschlagen = $summary.Failed
                groesse  = (Format-WzBytes $bytes) }) `
            -Items @($leftovers | ForEach-Object {
                $art = if ($_.Kind -eq 'Registry') { Get-WzText 'unin.kindRegistry' } else { Get-WzText 'unin.kindFolder' }
                $zusatz = if ($_.PSObject.Properties['UserData'] -and $_.UserData) { Get-WzText 'unin.userDataSuffix' } else { '' }
                "$($art): $($_.Path)$(if ($_.SizeBytes -gt 0) { " — $(Format-WzBytes $_.SizeBytes)" })$zusatz"
            }) `
            -ConfirmText (Get-WzText 'unin.btnRemoveLeftovers') -Danger
        if (-not $answer.Confirmed) {
            Start-WzUninstallScan
            return
        }

        Invoke-WzTask -Name (Get-WzText 'unin.taskLeftovers') -ArgumentList (, $leftovers) -ScriptBlock {
            param($items)
            Remove-WzUninstallLeftovers -Leftovers $items
        } -OnComplete {
            param($cleanup)
            if (-not $cleanup) { return }
            if ($cleanup.Removed -gt 0) {
                Add-WzAction -Area 'Programme' `
                    -Summary ((Get-WzText 'unin.actionLeftovers' @{ anzahl = $cleanup.Removed }) + $(if ($cleanup.Bytes -gt 0) { " ($(Format-WzBytes $cleanup.Bytes))" }))
            }
            Show-WzInfo -Title (Get-WzText 'unin.leftoverDoneTitle') `
                -Message (Get-WzText 'unin.doneMessage' @{ entfernt = $cleanup.Removed; fehlgeschlagen = $cleanup.Failed }) `
                -Items @($cleanup.Details)
            Start-WzUninstallScan
        }
    }.GetNewClosure()
}
