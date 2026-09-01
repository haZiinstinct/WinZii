# Seite "Protokoll" — Sitzungsverlauf und Berichtsausgabe.

function Initialize-WzProtocolPage {
    $syncHash.ProtoBtnExport.Add_Click({
        try {
            $file = Export-WzProtocol
            Show-WzInfo -Title (Get-WzText 'log.savedTitle') `
                -Message (Get-WzText 'log.savedMessage') `
                -Items @($file)
            Start-Process $file
        } catch {
            Write-WzLog (Get-WzText 'log.logSaveFailed' @{ grund = $_.Exception.Message }) -Level Error
        }
    })

    $syncHash.ProtoBtnOpenFolder.Add_Click({
        Start-Process (Get-WzReportDir)
    })

    $syncHash.ProtoBtnHandover.Add_Click({ Start-WzHandoverReport })

    # Der Briefkopf wird gemerkt, sobald ein Feld verlassen wird. Ein eigener
    # »Speichern«-Knopf waere eine Falle: Wer ihn uebersieht, tippt beim
    # naechsten Auftrag alles noch einmal.
    $felder = @{
        ProtoCompany    = 'firma'
        ProtoTechnician = 'techniker'
        ProtoPhone      = 'telefon'
        ProtoMail       = 'epost'
    }
    foreach ($paar in $felder.GetEnumerator()) {
        $feld = $syncHash[$paar.Key]
        if (-not $feld) { continue }
        $feld.Tag = $paar.Value
        $feld.Add_LostFocus({ Save-WzSetting -Name $this.Tag -Value $this.Text.Trim() })
    }

    $syncHash.ProtoBtnLogo.Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = Get-WzText 'log.logoDialogTitle'
        $dialog.Filter = Get-WzText 'log.logoFilter'
        if ($dialog.ShowDialog()) {
            $syncHash.ProtoLogo.Text = $dialog.FileName
            Save-WzSetting -Name 'logo' -Value $dialog.FileName
            Write-WzLog (Get-WzText 'log.senderSaved') -Level Ok
        }
    })

    $syncHash.ProtoBtnLogoClear.Add_Click({
        $syncHash.ProtoLogo.Text = ''
        Save-WzSetting -Name 'logo' -Value ''
    })

    $syncHash.ProtoBtnOpenLog.Add_Click({
        if ($syncHash.LogFile -and (Test-Path -LiteralPath $syncHash.LogFile)) {
            Start-Process notepad.exe -ArgumentList $syncHash.LogFile
        } else {
            Write-WzLog (Get-WzText 'log.logNoFile') -Level Warn
        }
    })
}

function Write-WzSenderFields {
    <#
    .SYNOPSIS
        Fuellt den Briefkopf aus den gemerkten Einstellungen.
    #>
    $profil = Get-WzTechnicianProfile
    $syncHash.ProtoCompany.Text = $profil.Company
    $syncHash.ProtoTechnician.Text = $profil.Technician
    $syncHash.ProtoPhone.Text = $profil.Phone
    $syncHash.ProtoMail.Text = $profil.Mail
    $syncHash.ProtoLogo.Text = $profil.LogoPath
}

function Start-WzHandoverReport {
    $actions = Get-WzActions
    if ($actions.Count -eq 0) {
        $answer = Show-WzConfirm -Title (Get-WzText 'log.noWorkTitle') `
            -Message (Get-WzText 'log.noWorkMessage') `
            -ConfirmText (Get-WzText 'log.btnCreateAnyway')
        if (-not $answer.Confirmed) { return }
    }

    # Der Techniker steht im Briefkopf und wird nicht je Auftrag getippt.
    $arguments = @(
        $syncHash.ProtoTechnician.Text.Trim()
        $syncHash.ProtoCustomer.Text.Trim()
        $syncHash.ProtoOrderNumber.Text.Trim()
    )

    Invoke-WzTask -Name (Get-WzText 'log.taskHandover') -ArgumentList $arguments -ScriptBlock {
        param($technician, $customer, $orderNumber)
        New-WzHandoverReport -Technician $technician -Customer $customer -OrderNumber $orderNumber
    } -OnComplete {
        param($file)
        if (-not $file) { return }
        Show-WzInfo -Title (Get-WzText 'log.handoverDoneTitle') `
            -Message (Get-WzText 'log.handoverDoneMessage') `
            -Items @($file)
        Start-Process $file
    }
}

function Update-WzProtocolPage {
    # Beim Sprachwechsel wird die Seite neu aufgebaut — der Briefkopf muss
    # dann wieder aus den Einstellungen kommen, sonst steht er leer da.
    Write-WzSenderFields

    $entries = Get-WzLogEntries

    $actions = Get-WzActions
    $syncHash.ProtoHandoverTitle.Text = if ($actions.Count -eq 0) {
        Get-WzText 'log.handoverForCustomer'
    } elseif ($actions.Count -eq 1) {
        Get-WzText 'log.oneStep'
    } else {
        Get-WzText 'log.nSteps' @{ anzahl = $actions.Count }
    }

    $syncHash.ProtoCount.Text = [string]$entries.Count
    $issues = @($entries | Where-Object { $_.Level -in @('Warn', 'Error') })
    $syncHash.ProtoIssues.Text = [string]$issues.Count
    $syncHash.ProtoIssues.Foreground = if ($issues.Count -gt 0) {
        $syncHash.Window.FindResource('WzAmber')
    } else {
        $syncHash.Window.FindResource('WzGreen')
    }

    if ($syncHash.SessionStart) {
        $syncHash.ProtoDuration.Text = Format-WzUptime ((Get-Date) - $syncHash.SessionStart)
        $syncHash.ProtoStart.Text = Get-WzText 'log.since' @{ zeit = $syncHash.SessionStart.ToString('t', (Get-WzLanguageCulture)) }
    }

    # Auf einem schreibgeschuetzten Datentraeger scheitert jede Ausgabe. Der
    # Hinweis darueber sagt es, aber ein Knopf, der zum Klicken einlaedt und
    # dann fehlschlaegt, ist eine Zumutung — im Abnahmelauf zu Punkt 16
    # aufgefallen.
    $schreibbar = Test-WzWritableRoot
    foreach ($knopf in @($syncHash.ProtoBtnExport, $syncHash.ProtoBtnOpenFolder,
                         $syncHash.ProtoBtnOpenLog, $syncHash.ProtoBtnHandover)) {
        if ($knopf) { $knopf.IsEnabled = $schreibbar }
    }

    $syncHash.ProtoPathHint.Text = if ($syncHash.LogFile) {
        Get-WzText 'log.pathHint' @{ protokoll = $syncHash.LogFile; berichte = (Get-WzReportDir) }
    } else {
        Get-WzText 'log.readOnlyDrive'
    }

    # Nur die letzten Einträge zeigen, neueste zuerst
    $list = $syncHash.ProtoEntries
    $list.Items.Clear()
    $recent = @($entries | Select-Object -Last 40)
    [array]::Reverse($recent)
    foreach ($entry in $recent) {
        [void]$list.Items.Add((New-WzLogRow -Entry $entry))
    }
}

function New-WzLogRow {
    <#
    .SYNOPSIS
        Eine Protokollzeile für die Verlaufsliste.
    #>
    param([Parameter(Mandatory = $true)]$Entry)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 3, 0, 3)
    $timeColumn = New-Object Windows.Controls.ColumnDefinition
    $timeColumn.Width = New-Object Windows.GridLength(64)
    $textColumn = New-Object Windows.Controls.ColumnDefinition
    $textColumn.Width = '*'
    [void]$grid.ColumnDefinitions.Add($timeColumn)
    [void]$grid.ColumnDefinitions.Add($textColumn)

    $timeBlock = New-Object Windows.Controls.TextBlock
    $timeBlock.Text = $Entry.Time
    $timeBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $timeBlock.FontSize = 11
    $timeBlock.Foreground = $syncHash.Window.FindResource('WzTextFaint')
    $timeBlock.VerticalAlignment = 'Top'
    [Windows.Controls.Grid]::SetColumn($timeBlock, 0)
    [void]$grid.Children.Add($timeBlock)

    $textBlock = New-Object Windows.Controls.TextBlock
    $textBlock.Text = $Entry.Message
    $textBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $textBlock.FontSize = 11.5
    $textBlock.TextWrapping = 'Wrap'
    $textBlock.Foreground = switch ($Entry.Level) {
        'Ok'     { $syncHash.Window.FindResource('WzGreen') }
        'Warn'   { $syncHash.Window.FindResource('WzAmber') }
        'Error'  { $syncHash.Window.FindResource('WzRedText') }
        'Action' { $syncHash.Window.FindResource('WzCyan') }
        default  { $syncHash.Window.FindResource('WzTextDim') }
    }
    [Windows.Controls.Grid]::SetColumn($textBlock, 1)
    [void]$grid.Children.Add($textBlock)

    return $grid
}
