# Seite "KI-Entfernung" — nutzt dieselbe Engine wie die Optimierung,
# ergänzt um eine Bestandsaufnahme der tatsächlich vorhandenen Komponenten.

function Initialize-WzAiRemovalPage {
    $syncHash.AiRows = New-WzTweakList -Container $syncHash.AiCategories `
        -Categories @('ai-policy', 'ai-remove') `
        -OnSelectionChanged { Update-WzAiSelection }

    $syncHash.AiBtnApply.Add_Click({
        Invoke-WzTweakSelection -Rows $syncHash.AiRows -Scope 'ki-entfernung' `
            -Title (Get-WzText 'ai.applyTitle') -OnDone {
                Update-WzAiStates
                Update-WzAiScan
            }
    })

    $syncHash.AiBtnUndo.Add_Click({ Show-WzUndoDialog -OnDone { Update-WzAiStates } })
    $syncHash.AiBtnRefresh.Add_Click({ Update-WzAiStates })
    $syncHash.AiBtnScan.Add_Click({ Update-WzAiScan -Force })

    $syncHash.AiBtnRecommended.Add_Click({
        foreach ($entry in $syncHash.AiRows) {
            $entry.CheckBox.IsChecked = [bool]$entry.Tweak.defaultChecked
        }
        Update-WzAiSelection
    })
    $syncHash.AiBtnNone.Add_Click({
        foreach ($entry in $syncHash.AiRows) { $entry.CheckBox.IsChecked = $false }
        Update-WzAiSelection
    })

    [void]$syncHash.AiNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'ai.noticeReversible')))

    Update-WzAiSelection
}

function Update-WzAiRemovalPage {
    if (-not $syncHash.AiStatesChecked) {
        $syncHash.AiStatesChecked = $true
        Update-WzAiScan
    }
}

function Update-WzAiScan {
    <#
    .SYNOPSIS
        Sucht vorhandene KI-Bestandteile und prüft danach den Zustand der Einträge.
    #>
    param([switch]$Force)

    if ($syncHash.AiStatus -and -not $Force) {
        Write-WzAiScanResult -Status $syncHash.AiStatus
        return
    }

    $syncHash.AiScanTitle.Text = Get-WzText 'ai.checking'
    $syncHash.AiScanRows.Children.Clear()

    Invoke-WzTask -Name (Get-WzText 'ai.taskScan') -Silent -ScriptBlock {
        Get-WzAiStatus
    } -OnComplete {
        param($status)
        if (-not $status) {
            $syncHash.AiScanTitle.Text = Get-WzText 'ai.scanFailed'
            return
        }
        $syncHash.AiStatus = $status
        Write-WzAiScanResult -Status $status
        Write-WzLog $status.Summary -Level Info
        Update-WzAiStates
    }
}

function Write-WzAiScanResult {
    param([Parameter(Mandatory = $true)]$Status)

    $found = $Status.Packages.Count + $Status.Capabilities.Count + $Status.Tasks.Count
    $syncHash.AiScanTitle.Text = if ($found -eq 0) {
        Get-WzText 'ai.noneInstalled'
    } else {
        Get-WzText 'ai.foundCount' @{ anzahl = $found }
    }

    $rows = $syncHash.AiScanRows
    $rows.Children.Clear()

    if ($found -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'ai.lblResult') (Get-WzText 'ai.cleanValue') -Kind 'ok'))
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'ai.lblRecommendation') (Get-WzText 'ai.recommendBlock')))
        return
    }

    foreach ($package in $Status.Packages) {
        $suffix = if ($package.NonRemovable) { Get-WzText 'ai.suffixNonRemovableDot' } else { '' }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'ai.lblAppPackage') "$($package.Name)$suffix" -Kind 'warn'))
    }
    foreach ($capability in $Status.Capabilities) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'ai.lblCapability') $capability.Name -Kind 'warn'))
    }
    foreach ($feature in $Status.Features) {
        $kind = if ($feature.State -eq 'Enabled') { 'warn' } else { 'normal' }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'ai.lblFeature') (Get-WzText 'ai.stateValue' @{ name = $feature.Name; zustand = $feature.State }) -Kind $kind))
    }
    foreach ($task in $Status.Tasks) {
        $kind = if ($task.State -eq 'Disabled') { 'ok' } else { 'warn' }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'ai.lblTask') (Get-WzText 'ai.stateValue' @{ name = $task.Name; zustand = $task.State }) -Kind $kind))
    }
}

function Update-WzAiStates {
    Update-WzTweakStates -Rows $syncHash.AiRows -HintTarget $syncHash.AiStatusHint `
        -OnDone { Update-WzAiSelection }
}

function Update-WzAiSelection {
    $count = @($syncHash.AiRows | Where-Object { $_.CheckBox.IsChecked }).Count
    $syncHash.AiSelectionCount.Text = Get-WzText 'ai.selectedCount' @{ anzahl = $count }
    $syncHash.AiBtnApply.IsEnabled = ($count -gt 0)
}
