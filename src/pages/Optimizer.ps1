# Seite "Optimierung" — Geschwindigkeit, Telemetrie, Datenschutz, Sicherheit.
# Die KI-Entfernung nutzt dieselbe Engine, hat aber eine eigene Seite.

$script:WzOptimizerCategories = @('performance', 'telemetry', 'privacy', 'security')

function Initialize-WzOptimizerPage {
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

    $syncHash.OptBtnRemember.Add_Click({ Save-WzTweakSelection })

    $notices = $syncHash.OptNotices
    [void]$notices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'opt.noticeBackup')))

    # Die gemerkte Auswahl gilt ab hier statt der empfohlenen. Sie liegt in
    # einstellungen.json und reist damit mit dem Stick, nicht mit dem Gerät:
    # Wer achtundvierzig Einträge einmal durchgegangen ist, will das beim
    # nächsten Kunden nicht wiederholen.
    Restore-WzTweakSelection

    Update-WzOptimizerSelection
}

function Save-WzTweakSelection {
    <#
    .SYNOPSIS
        Merkt sich die angekreuzten Optimierungen für die nächsten Aufträge.
    #>
    $ids = @($syncHash.OptRows | Where-Object { $_.CheckBox.IsChecked } |
        ForEach-Object { $_.Tweak.id })

    Save-WzSetting -Name 'optimierungAuswahl' -Value ($ids -join ',')
    Write-WzLog (Get-WzText 'opt.logSelectionSaved' @{ anzahl = $ids.Count }) -Level Ok
    Show-WzInfo -Title (Get-WzText 'opt.rememberTitle') `
        -Message (Get-WzText 'opt.rememberDone' @{ anzahl = $ids.Count })
}

function Restore-WzTweakSelection {
    <#
    .SYNOPSIS
        Stellt die gemerkte Auswahl wieder her, falls es eine gibt.
    .NOTES
        Kennungen, die es nicht mehr gibt, werden übergangen — ein Katalog
        wächst. Und wurde nie etwas gemerkt, bleibt die empfohlene Auswahl
        stehen, mit der die Seite aufgebaut wurde.
    #>
    $saved = [string](Get-WzSetting -Name 'optimierungAuswahl')
    if ([string]::IsNullOrWhiteSpace($saved)) { return }

    $ids = @($saved -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($entry in $syncHash.OptRows) {
        $entry.CheckBox.IsChecked = ($ids -contains $entry.Tweak.id)
    }
    Write-WzLog (Get-WzText 'opt.logSelectionRestored' @{ anzahl = $ids.Count }) -Level Info
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
