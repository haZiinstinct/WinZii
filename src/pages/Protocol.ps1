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
        $folder = Get-WzReportDir
        if (Test-Path -LiteralPath $folder) {
            Start-Process $folder
        } else {
            Write-WzLog (Get-WzText 'log.logNoFile') -Level Warn
        }
    })

    $syncHash.ProtoBtnOpenLog.Add_Click({
        if ($syncHash.LogFile -and (Test-Path -LiteralPath $syncHash.LogFile)) {
            # In Anführungszeichen: Bei »D:\Mein Stick\« öffnete Notepad sonst
            # »D:\Mein« (Audit 2026-10, N).
            Start-Process notepad.exe -ArgumentList ('"{0}"' -f $syncHash.LogFile)
        } else {
            Write-WzLog (Get-WzText 'log.logNoFile') -Level Warn
        }
    })
}

function Update-WzProtocolPage {
    $entries = Get-WzLogEntries

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

    $schreibbar = Test-WzWritableRoot
    foreach ($knopf in @($syncHash.ProtoBtnExport, $syncHash.ProtoBtnOpenFolder, $syncHash.ProtoBtnOpenLog)) {
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
    $recent = @($entries | Select-Object -Last 60)
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
