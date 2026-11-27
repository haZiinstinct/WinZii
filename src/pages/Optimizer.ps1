# Seite "Optimierung" — Geschwindigkeit, Telemetrie, Datenschutz, Sicherheit.
# Die KI-Entfernung nutzt dieselbe Engine, hat aber eine eigene Seite.

$script:WzOptimizerCategories = @('performance', 'telemetry', 'privacy', 'security')

function Initialize-WzOptimizerPage {
    $syncHash.OptFilterOnlyOpen = $false
    $syncHash.OptRows = New-WzTweakList -Container $syncHash.OptCategories `
        -Categories $script:WzOptimizerCategories `
        -OnSelectionChanged { Update-WzOptimizerSelection }

    $syncHash.OptBtnApply.Add_Click({
        Invoke-WzTweakSelection -Rows $syncHash.OptRows -Scope 'optimierung' `
            -Title (Get-WzText 'opt.applyTitle') -OnDone { Update-WzOptimizerStates }
    })

    $syncHash.OptBtnUndo.Add_Click({
        Show-WzUndoDialog -OnDone { Update-WzOptimizerStates }
    })

    $syncHash.OptBtnRefresh.Add_Click({ Update-WzOptimizerStates })

    $syncHash.OptBtnRestartExplorer.Add_Click({
        Invoke-WzTask -Name (Get-WzText 'opt.btnRestartExplorer') -ScriptBlock {
            Restart-WzExplorer
        } -OnComplete {
            param($ok)
            if ($ok) {
                Show-WzInfo -Title (Get-WzText 'opt.btnRestartExplorer') -Message (Get-WzText 'opt.explorerRestarted')
            }
        }
    })

    # 1-Klick-Schnellprofile (wählen nur Einträge aus, die noch nicht aktiv sind)
    $syncHash.OptBtnRecommended.Add_Click({
        foreach ($entry in $syncHash.OptRows) {
            $entry.CheckBox.IsChecked = ([bool]$entry.Tweak.defaultChecked -and $entry.State -ne 'Applied')
        }
        Update-WzOptimizerSelection
    })
    $syncHash.OptBtnMaxLean.Add_Click({
        $leanExtras = @(
            'perf-startup-delay', 'perf-animations-off', 'perf-sysmain-off',
            'perf-bg-apps-off', 'perf-services-lean', 'perf-explorer-clean',
            'perf-win11-endtask', 'priv-app-tracking', 'priv-clipboard-cloud'
        )
        foreach ($entry in $syncHash.OptRows) {
            $want = ([bool]$entry.Tweak.defaultChecked -or ($leanExtras -contains $entry.Tweak.id))
            $entry.CheckBox.IsChecked = ($want -and $entry.State -ne 'Applied')
        }
        Update-WzOptimizerSelection
    })
    $syncHash.OptBtnTelemetry.Add_Click({
        foreach ($entry in $syncHash.OptRows) {
            $want = ($entry.Tweak.category -in @('telemetry', 'privacy') -and $entry.Tweak.risk -eq 'low')
            $entry.CheckBox.IsChecked = ($want -and $entry.State -ne 'Applied')
        }
        Update-WzOptimizerSelection
    })
    $syncHash.OptBtnAll.Add_Click({
        foreach ($entry in $syncHash.OptRows) { $entry.CheckBox.IsChecked = ($entry.State -ne 'Applied') }
        Update-WzOptimizerSelection
    })
    $syncHash.OptBtnNone.Add_Click({
        foreach ($entry in $syncHash.OptRows) { $entry.CheckBox.IsChecked = $false }
        Update-WzOptimizerSelection
    })

    $syncHash.OptBtnRemember.Add_Click({ Save-WzTweakSelection })
    $syncHash.OptSearch.Add_TextChanged({ Update-WzOptimizerFilter })
    $syncHash.OptBtnFilterOpen.Add_Click({
        $syncHash.OptFilterOnlyOpen = (-not [bool]$syncHash.OptFilterOnlyOpen)
        $syncHash.OptBtnFilterOpen.Content = if ($syncHash.OptFilterOnlyOpen) {
            Get-WzText 'opt.btnFilterAll'
        } else {
            Get-WzText 'opt.btnFilterOpen'
        }
        Update-WzOptimizerFilter
    })

    $notices = $syncHash.OptNotices
    [void]$notices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'opt.noticeBackup')))

    Restore-WzTweakSelection
    Update-WzOptimizerSelection
}

function Save-WzTweakSelection {
    $ids = @($syncHash.OptRows | Where-Object { $_.CheckBox.IsChecked } |
        ForEach-Object { $_.Tweak.id })

    Save-WzSetting -Name 'optimierungAuswahl' -Value ($ids -join ',')
    Write-WzLog (Get-WzText 'opt.logSelectionSaved' @{ anzahl = $ids.Count }) -Level Ok
    Show-WzInfo -Title (Get-WzText 'opt.rememberTitle') `
        -Message (Get-WzText 'opt.rememberDone' @{ anzahl = $ids.Count })
}

function Restore-WzTweakSelection {
    $saved = [string](Get-WzSetting -Name 'optimierungAuswahl')
    if ([string]::IsNullOrWhiteSpace($saved)) { return }

    $ids = @($saved -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($entry in $syncHash.OptRows) {
        $entry.CheckBox.IsChecked = ($ids -contains $entry.Tweak.id)
    }
    Write-WzLog (Get-WzText 'opt.logSelectionRestored' @{ anzahl = $ids.Count }) -Level Info
}

function Select-WzOptimizerTweaks {
    <#
    .SYNOPSIS
        Springt auf die Optimierungsseite und hakt genau die genannten
        Einträge an (z. B. nach einem Snapshot-Vergleich).
    #>
    param([Parameter(Mandatory = $true)][string[]]$Ids)

    Show-WzPage -Id 'Optimizer'
    if (-not $syncHash.OptRows) { return }
    foreach ($entry in $syncHash.OptRows) {
        $entry.CheckBox.IsChecked = ($Ids -contains $entry.Tweak.id)
    }
    Update-WzOptimizerSelection
}

function Update-WzOptimizerPage {
    if (-not $syncHash.OptStatesChecked) {
        $syncHash.OptStatesChecked = $true
        Update-WzOptimizerStates
    }
}

function Update-WzOptimizerStates {
    Update-WzTweakStates -Rows $syncHash.OptRows -HintTarget $syncHash.OptStatusHint `
        -OnDone {
            Update-WzOptimizerFilter
            Update-WzOptimizerSelection
        }
}

function Update-WzOptimizerFilter {
    $query = if ($syncHash.OptSearch) { $syncHash.OptSearch.Text.Trim().ToLowerInvariant() } else { '' }
    $tokens = if ($query) { @($query -split '\s+' | Where-Object { $_ }) } else { @() }
    $onlyOpen = [bool]$syncHash.OptFilterOnlyOpen

    $byCard = @{}
    foreach ($entry in @($syncHash.OptRows)) {
        $match = $true
        if ($onlyOpen -and $entry.State -eq 'Applied') { $match = $false }
        if ($match) {
            foreach ($token in $tokens) {
                if ($entry.SearchText.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                    $match = $false
                    break
                }
            }
        }
        $entry.Row.Visibility = if ($match) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
        if ($entry.Card) {
            if (-not $byCard.ContainsKey($entry.Card)) { $byCard[$entry.Card] = $false }
            if ($match) { $byCard[$entry.Card] = $true }
        }
    }

    foreach ($pair in $byCard.GetEnumerator()) {
        $pair.Key.Visibility = if ($pair.Value) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    }
}

function Update-WzOptimizerSelection {
    $count = @($syncHash.OptRows | Where-Object { $_.CheckBox.IsChecked }).Count
    $syncHash.OptSelectionCount.Text = Get-WzText 'opt.selectedCount' @{ anzahl = $count }
    $syncHash.OptBtnApply.IsEnabled = ($count -gt 0)
}
