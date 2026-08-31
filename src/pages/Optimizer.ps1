# Seite "Optimierung" — Geschwindigkeit, Telemetrie, Datenschutz, Sicherheit.
# Die KI-Entfernung nutzt dieselbe Engine, hat aber eine eigene Seite.

$script:WzOptimizerCategories = @('performance', 'telemetry', 'privacy', 'security')

function Initialize-WzOptimizerPage {
    $syncHash.OptRows = New-WzTweakList -Container $syncHash.OptCategories `
        -Categories $script:WzOptimizerCategories `
        -OnSelectionChanged { Update-WzOptimizerSelection }

    $syncHash.OptBtnApply.Add_Click({
        Invoke-WzTweakSelection -Rows $syncHash.OptRows -Scope 'optimierung' `
            -Title 'Windows optimieren' -OnDone { Update-WzOptimizerStates }
    })

    $syncHash.OptBtnUndo.Add_Click({
        Show-WzUndoDialog -OnDone { Update-WzOptimizerStates }
    })

    $syncHash.OptBtnRefresh.Add_Click({ Update-WzOptimizerStates })

    $syncHash.OptBtnRecommended.Add_Click({
        foreach ($entry in $syncHash.OptRows) {
            $entry.CheckBox.IsChecked = [bool]$entry.Tweak.defaultChecked
        }
        Update-WzOptimizerSelection
    })
    $syncHash.OptBtnAll.Add_Click({
        foreach ($entry in $syncHash.OptRows) { $entry.CheckBox.IsChecked = $true }
        Update-WzOptimizerSelection
    })
    $syncHash.OptBtnNone.Add_Click({
        foreach ($entry in $syncHash.OptRows) { $entry.CheckBox.IsChecked = $false }
        Update-WzOptimizerSelection
    })

    $notices = $syncHash.OptNotices
    [void]$notices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'opt.noticeBackup')))

    Update-WzOptimizerSelection
}

function Update-WzOptimizerPage {
    # Zustand nur beim ersten Öffnen automatisch prüfen
    if (-not $syncHash.OptStatesChecked) {
        $syncHash.OptStatesChecked = $true
        Update-WzOptimizerStates
    }
}

function Update-WzOptimizerStates {
    Update-WzTweakStates -Rows $syncHash.OptRows -HintTarget $syncHash.OptStatusHint `
        -OnDone { Update-WzOptimizerSelection }
}

function Update-WzOptimizerSelection {
    $count = @($syncHash.OptRows | Where-Object { $_.CheckBox.IsChecked }).Count
    $syncHash.OptSelectionCount.Text = Get-WzText 'opt.selectedCount' @{ anzahl = $count }
    $syncHash.OptBtnApply.IsEnabled = ($count -gt 0)
}
