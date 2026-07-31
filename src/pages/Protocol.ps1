# Seite "Protokoll" — Sitzungsverlauf und Berichtsausgabe.

function Initialize-WzProtocolPage {
    $syncHash.ProtoBtnExport.Add_Click({
        try {
            $file = Export-WzProtocol
            Show-WzInfo -Title 'Protokoll gesichert' `
                -Message 'Der Bericht liegt auf dem WinZii-Datenträger und lässt sich in jedem Browser öffnen.' `
                -Items @($file)
            Start-Process $file
        } catch {
            Write-WzLog "Protokoll konnte nicht gesichert werden: $($_.Exception.Message)" -Level Error
        }
    })

    $syncHash.ProtoBtnOpenFolder.Add_Click({
        Start-Process (Get-WzReportDir)
    })

    $syncHash.ProtoBtnHandover.Add_Click({ Start-WzHandoverReport })

    $syncHash.ProtoBtnOpenLog.Add_Click({
        if ($syncHash.LogFile -and (Test-Path -LiteralPath $syncHash.LogFile)) {
            Start-Process notepad.exe -ArgumentList $syncHash.LogFile
        } else {
            Write-WzLog 'Es gibt keine Protokolldatei (Datenträger schreibgeschützt?).' -Level Warn
        }
    })
}

function Start-WzHandoverReport {
    $actions = Get-WzActions
    if ($actions.Count -eq 0) {
        $answer = Show-WzConfirm -Title 'Noch keine Arbeiten' `
            -Message 'In dieser Sitzung wurde bisher nichts am PC verändert. Das Übergabeblatt hält dann nur den Zustand des Geräts fest — als Geräteblatt ist das durchaus brauchbar.' `
            -ConfirmText 'Trotzdem erstellen'
        if (-not $answer.Confirmed) { return }
    }

    $arguments = @(
        $syncHash.ProtoTechnician.Text.Trim()
        $syncHash.ProtoCustomer.Text.Trim()
        $syncHash.ProtoOrderNumber.Text.Trim()
    )

    Invoke-WzTask -Name 'Übergabeblatt erstellen' -ArgumentList $arguments -ScriptBlock {
        param($technician, $customer, $orderNumber)
        New-WzHandoverReport -Technician $technician -Customer $customer -OrderNumber $orderNumber
    } -OnComplete {
        param($file)
        if (-not $file) { return }
        Show-WzInfo -Title 'Übergabeblatt erstellt' `
            -Message 'Das Blatt liegt im Berichtsordner. Zum Ausdrucken im Browser öffnen und dort »Drucken« wählen — dabei lässt es sich auch als PDF speichern.' `
            -Items @($file)
        Start-Process $file
    }
}

function Update-WzProtocolPage {
    $entries = Get-WzLogEntries

    $actions = Get-WzActions
    $syncHash.ProtoHandoverTitle.Text = if ($actions.Count -eq 0) {
        'Übergabeblatt für den Kunden'
    } elseif ($actions.Count -eq 1) {
        'Ein Arbeitsschritt zum Übergeben'
    } else {
        "$($actions.Count) Arbeitsschritte zum Übergeben"
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
        $syncHash.ProtoStart.Text = "seit $($syncHash.SessionStart.ToString('HH:mm'))"
    }

    $syncHash.ProtoPathHint.Text = if ($syncHash.LogFile) {
        "Textprotokoll: $($syncHash.LogFile)`nBerichte: $(Get-WzReportDir)"
    } else {
        'Der Datenträger ist schreibgeschützt — es kann nichts gespeichert werden.'
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
