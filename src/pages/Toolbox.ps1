# Seite "Reparatur" — Netzwerk, Windows Update, Drucker, Sicherung,
# vorinstallierte Apps.

function Initialize-WzToolboxPage {
    $syncHash.ToolBtnNetDiag.Add_Click({ Start-WzNetworkDiagnosis })
    $syncHash.ToolBtnScan.Add_Click({ Start-WzDefenderQuickScan })
    $syncHash.ToolBtnRenew.Add_Click({ Start-WzNetworkRenew })
    $syncHash.ToolBtnNetReset.Add_Click({ Start-WzNetworkReset })
    $syncHash.ToolBtnWuReset.Add_Click({ Start-WzUpdateReset })
    $syncHash.ToolBtnSpooler.Add_Click({ Start-WzSpoolerRepair })
    $syncHash.ToolBtnRestorePoint.Add_Click({ Start-WzRestorePoint })
    $syncHash.ToolBtnBloatScan.Add_Click({ Start-WzBloatwareScan })
    $syncHash.ToolBtnBloatRemove.Add_Click({ Start-WzBloatwareRemove })

    foreach ($pair in @(
        @('ToolBtnDnsCloudflare', 'Cloudflare'),
        @('ToolBtnDnsQuad9', 'Quad9'),
        @('ToolBtnDnsGoogle', 'Google'),
        @('ToolBtnDnsAuto', 'Auto')
    )) {
        $button = $syncHash[$pair[0]]
        $provider = $pair[1]
        $button.Add_Click({ Start-WzDnsChange -Provider $provider }.GetNewClosure())
    }

    [void]$syncHash.ToolNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'tool.noticeAsksFirst')))
}

function Update-WzToolboxPage {
    if ($syncHash.ToolLoaded) { return }
    $syncHash.ToolLoaded = $true
    Start-WzBloatwareScan
}

# --- Netzwerk prüfen -------------------------------------------------------

function Start-WzNetworkDiagnosis {
    $syncHash.NetDiagTitle.Text = Get-WzText 'tool.checking'
    $syncHash.NetDiagSteps.Children.Clear()
    $syncHash.NetDiagVerdict.Items.Clear()

    Invoke-WzTask -Name (Get-WzText 'tool.taskNetDiag') -ScriptBlock {
        Invoke-WzNetworkDiagnosis
    } -OnComplete {
        param($diagnosis)
        if (-not $diagnosis) { return }
        Write-WzNetworkDiagnosis -Diagnosis $diagnosis
    }
}

function Write-WzNetworkDiagnosis {
    param([Parameter(Mandatory = $true)]$Diagnosis)

    $failed = @($Diagnosis.Steps | Where-Object { $_.Status -eq 'fail' })
    $syncHash.NetDiagTitle.Text = if ($Diagnosis.Ok) {
        Get-WzText 'tool.netOk'
    } elseif ($failed.Count -gt 0) {
        Get-WzText 'tool.netStuckAt' @{ schritt = $failed[0].Name }
    } else {
        Get-WzText 'tool.netOdd'
    }

    $container = $syncHash.NetDiagSteps
    $container.Children.Clear()
    foreach ($step in $Diagnosis.Steps) {
        $kind = switch ($step.Status) {
            'ok'   { 'ok' }
            'warn' { 'warn' }
            default { 'error' }
        }
        $mark = switch ($step.Status) {
            'ok'   { '✓' }
            'warn' { '!' }
            default { '✗' }
        }
        [void]$container.Children.Add((New-WzInfoRow "$mark $($step.Name)" $step.Detail -Kind $kind))
    }

    $verdictKind = if ($Diagnosis.Ok) { 'ok' } else { 'warn' }
    [void]$syncHash.NetDiagVerdict.Items.Add((New-WzNotice -Kind $verdictKind -Text $Diagnosis.Verdict))
    [void]$syncHash.NetDiagVerdict.Items.Add((New-WzNotice -Kind 'info' -Text $Diagnosis.Recommendation))

    Write-WzLog $Diagnosis.Verdict -Level $(if ($Diagnosis.Ok) { 'Ok' } else { 'Warn' })
}

function Start-WzDefenderQuickScan {
    $answer = Show-WzConfirm -Title (Get-WzText 'tool.scanTitle') `
        -Message (Get-WzText 'tool.scanMessage') `
        -ConfirmText 'Starten'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.scanTitle') -ScriptBlock {
        Start-WzDefenderScan
    } -OnComplete {
        param($scan)
        if (-not $scan) { return }
        Add-WzAction -Area 'Sicherheit' -Summary (Get-WzText 'tool.actionScan' @{ ergebnis = $scan.Summary })
        Show-WzInfo -Title (Get-WzText 'tool.scanTitle') -Message $scan.Summary -Items @($scan.Threats)
    }
}

# --- Netzwerk reparieren ---------------------------------------------------

function Start-WzNetworkRenew {
    Invoke-WzTask -Name (Get-WzText 'tool.taskRenew') -ScriptBlock {
        Repair-WzNetworkAdapter
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' -Summary (Get-WzText 'tool.actionRenew')
        Show-WzInfo -Title (Get-WzText 'tool.renewTitle') `
            -Message (Get-WzText 'tool.renewMessage' @{ anzahl = $result.Done })
    }
}

function Start-WzNetworkReset {
    $answer = Show-WzConfirm -Title (Get-WzText 'tool.resetTitle') `
        -Message (Get-WzText 'tool.resetMessage') `
        -Items @((Get-WzText 'tool.resetItem1'), (Get-WzText 'tool.resetItem2'), (Get-WzText 'tool.resetItem3'), (Get-WzText 'tool.resetItem4')) `
        -ConfirmText (Get-WzText 'tool.btnReset') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.resetTitle') -ScriptBlock {
        Invoke-WzNetworkReset -Winsock -IpStack -FlushDns -ResetProxy
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' -RebootRequired `
            -Summary (Get-WzText 'tool.actionReset')
        Show-WzInfo -Title (Get-WzText 'tool.resetDoneTitle') `
            -Message (Get-WzText 'tool.resetDoneMessage' @{ anzahl = $result.Done })
    }
}

function Start-WzDnsChange {
    param([string]$Provider)

    $description = switch ($Provider) {
        'Cloudflare' { Get-WzText 'tool.dnsCloudflare' }
        'Quad9'      { Get-WzText 'tool.dnsQuad9' }
        'Google'     { Get-WzText 'tool.dnsGoogle' }
        default      { Get-WzText 'tool.dnsRouter' }
    }

    # Bewusst genau formuliert: »zurück auf Router« stellt auf DHCP um und ist
    # nicht dasselbe wie ein von Hand eingetragener Server. Die bisherigen Werte
    # landen deshalb vorher als Datei im Sicherungsordner.
    $answer = Show-WzConfirm -Title (Get-WzText 'tool.dnsDialogTitle' @{ anbieter = $Provider }) `
        -Message ("$description`n`n" + (Get-WzText 'tool.dnsMessage')) `
        -ConfirmText (Get-WzText 'tool.btnSwitch')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.taskDns' @{ anbieter = $Provider }) -ArgumentList @($Provider) -ScriptBlock {
        param($provider)
        Set-WzDnsServers -Provider $provider
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' -Summary (Get-WzText 'tool.actionDns' @{ anbieter = $Provider }) `
            -Detail @($result.Adapters)
        $message = Get-WzText 'tool.dnsChanged' @{ anzahl = $result.Changed }
        if ($result.BackupFile) { $message += Get-WzText 'tool.dnsBackupHint' }
        Show-WzInfo -Title (Get-WzText 'tool.dnsDoneTitle') -Message $message `
            -Items @(@($result.Adapters) + @($result.BackupFile | Where-Object { $_ }))
    }.GetNewClosure()
}

# --- Windows Update und Drucker -------------------------------------------

function Start-WzUpdateReset {
    $answer = Show-WzConfirm -Title (Get-WzText 'tool.wuTitle') `
        -Message (Get-WzText 'tool.wuMessage') `
        -ConfirmText (Get-WzText 'tool.btnReset') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.taskWu') -ScriptBlock {
        Repair-WzWindowsUpdate
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $message = if ($result.Success) {
            Get-WzText 'tool.wuOk'
        } else {
            Get-WzText 'tool.wuFail'
        }
        if ($result.Success) {
            Add-WzAction -Area 'Reparatur' -Summary (Get-WzText 'tool.actionWu')
        }
        Show-WzInfo -Title 'Windows Update' -Message $message -Items @($result.Messages)
    }
}

function Start-WzSpoolerRepair {
    $answer = Show-WzConfirm -Title (Get-WzText 'tool.spoolerTitle') `
        -Message (Get-WzText 'tool.spoolerMessage') `
        -ConfirmText (Get-WzText 'tool.btnClear')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.taskSpooler') -ScriptBlock {
        Repair-WzSpooler
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' `
            -Summary (Get-WzText 'tool.actionSpooler' @{ anzahl = $result.Removed })
        Show-WzInfo -Title (Get-WzText 'tool.spoolerDoneTitle') `
            -Message (Get-WzText 'tool.spoolerDoneMessage' @{ anzahl = $result.Removed })
    }
}

function Start-WzRestorePoint {
    $answer = Show-WzConfirm -Title (Get-WzText 'tool.rpTitle') `
        -Message (Get-WzText 'tool.rpMessage') `
        -ConfirmText (Get-WzText 'tool.btnCreate')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.taskRp') -ScriptBlock {
        New-WzRestorePoint -Description (Get-WzText 'tool.rpDescription')
    } -OnComplete {
        param($ok)
        if ($ok) { Add-WzAction -Area 'Sicherung' -Summary (Get-WzText 'tool.actionRp') }
        $message = if ($ok) {
            Get-WzText 'tool.rpOk'
        } else {
            Get-WzText 'tool.rpFail'
        }
        Show-WzInfo -Title (Get-WzText 'tool.rpDoneTitle') -Message $message
    }
}

# --- Vorinstallierte Apps --------------------------------------------------

function Start-WzBloatwareScan {
    $syncHash.ToolBloatTitle.Text = Get-WzText 'tool.checking'
    $syncHash.ToolBloatList.Children.Clear()

    Invoke-WzTask -Name (Get-WzText 'tool.taskBloatScan') -Silent -ScriptBlock {
        Get-WzBloatwareList -Level 'extended'
    } -OnComplete {
        param($packages)
        $packages = @($packages)
        $syncHash.ToolBloatPackages = $packages

        $syncHash.ToolBloatTitle.Text = if ($packages.Count -eq 0) {
            Get-WzText 'tool.bloatNone'
        } else {
            Get-WzText 'tool.bloatCount' @{ anzahl = $packages.Count }
        }

        $container = $syncHash.ToolBloatList
        $container.Children.Clear()
        $syncHash.ToolBloatBoxes = @()

        foreach ($package in $packages) {
            $item = [pscustomobject]@{
                name        = $package.DisplayName
                description = $package.Description
            }
            $row = New-WzCheckRow -Item $item -IsChecked $false
            $row.CheckBox.Tag = $package
            $row.CheckBox.Add_Click({ Update-WzBloatwareSelection })
            [void]$container.Children.Add($row.Row)
            $syncHash.ToolBloatBoxes += $row.CheckBox
        }

        Update-WzBloatwareSelection
        if ($packages.Count -gt 0) {
            Write-WzLog (Get-WzText 'tool.logBloatFound' @{ anzahl = $packages.Count }) -Level Info
        }
    }
}

function Update-WzBloatwareSelection {
    $count = @($syncHash.ToolBloatBoxes | Where-Object { $_.IsChecked }).Count
    $syncHash.ToolBtnBloatRemove.IsEnabled = ($count -gt 0)
}

function Start-WzBloatwareRemove {
    $selected = @($syncHash.ToolBloatBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'tool.bloatDialogTitle') `
        -Message (Get-WzText 'tool.bloatMessage' @{ anzahl = $selected.Count }) `
        -Items @($selected | ForEach-Object { $_.DisplayName }) `
        -ConfirmText (Get-WzText 'tool.btnRemove2') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'tool.taskBloatRemove') -ArgumentList (, $selected) -ScriptBlock {
        param($packages)
        Remove-WzBloatware -Packages $packages
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Vorinstallierte Apps' `
            -Summary (Get-WzText 'tool.actionBloat' @{ anzahl = $result.Removed }) `
            -Detail @($selected | ForEach-Object { $_.DisplayName })

        $message = Get-WzText 'tool.bloatDoneMessage' @{ entfernt = $result.Removed; fehlgeschlagen = $result.Failed }
        if ($result.RecordFile) { $message += Get-WzText 'tool.bloatRecordHint' }
        Show-WzInfo -Title (Get-WzText 'tool.doneTitle') -Message $message `
            -Items @($result.RecordFile | Where-Object { $_ })
        Start-WzBloatwareScan
    }.GetNewClosure()
}
