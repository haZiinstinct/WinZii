# Seite "Diagnose" — Analyse und Reparaturwerkzeuge.

function Initialize-WzDiagnosticsPage {
    foreach ($range in @(7, 14, 30, 90)) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = "letzte $range Tage"
        $item.Tag = $range
        [void]$syncHash.DiagRange.Items.Add($item)
    }
    $syncHash.DiagRange.SelectedIndex = 1

    $syncHash.DiagBtnScan.Add_Click({ Start-WzDiagnosticsScan })
    $syncHash.DiagBtnReport.Add_Click({ Start-WzDiagnosticsReport })
    $syncHash.DiagBtnSfc.Add_Click({ Start-WzRepairTool -Kind 'sfc' })
    $syncHash.DiagBtnDism.Add_Click({ Start-WzRepairTool -Kind 'dism' })
    $syncHash.DiagBtnChkdsk.Add_Click({ Start-WzRepairTool -Kind 'chkdsk' })
    $syncHash.DiagBtnBattery.Add_Click({ Start-WzBatteryReport })

    [void]$syncHash.DiagNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Die Analyse liest nur mit und verändert nichts. Die Reparaturwerkzeuge darunter greifen dagegen ins System ein.'))
}

function Start-WzDiagnosticsScan {
    $days = $syncHash.DiagRange.SelectedItem.Tag

    $syncHash.DiagEventsTitle.Text = 'wird ausgewertet...'
    $syncHash.DiagEvents.Children.Clear()
    $syncHash.DiagDumps.Children.Clear()
    $syncHash.DiagDisks.Children.Clear()

    Invoke-WzTask -Name 'Diagnose' -ArgumentList @($days) -ScriptBlock {
        param($days)
        [pscustomobject]@{
            Events = Get-WzEventSummary -Days $days
            Dumps  = Get-WzMinidumps -Days 90
            Disks  = Get-WzSmartStatus
            Days   = $days
        }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $syncHash.DiagResult = $result
        Write-WzDiagnosticsResult -Result $result
        $syncHash.DiagBtnReport.IsEnabled = $true
    }
}

function Write-WzDiagnosticsResult {
    param([Parameter(Mandatory = $true)]$Result)

    # --- Ereignisse -------------------------------------------------------
    $events = @($Result.Events)
    $critical = @($events | Where-Object { $_.Severity -eq 'critical' })
    $syncHash.DiagEventsTitle.Text = if ($events.Count -eq 0) {
        "Keine Fehler in den letzten $($Result.Days) Tagen"
    } else {
        "$($events.Count) Auffälligkeit(en), davon $($critical.Count) kritisch"
    }

    $container = $syncHash.DiagEvents
    $container.Children.Clear()
    if ($events.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Ergebnis' 'unauffällig' -Kind 'ok'))
    }
    foreach ($event in ($events | Select-Object -First 20)) {
        [void]$container.Children.Add((New-WzFindingRow -Finding $event))
    }
    if ($events.Count -gt 20) {
        [void]$container.Children.Add((New-WzInfoRow 'Hinweis' "$($events.Count - 20) weitere Einträge stehen im Bericht"))
    }

    # --- Abstürze ---------------------------------------------------------
    $dumps = @($Result.Dumps)
    $syncHash.DiagDumpsTitle.Text = if ($dumps.Count -eq 0) {
        'Keine Bluescreens in den letzten 90 Tagen'
    } else {
        "$($dumps.Count) Absturzabbild(er) gefunden"
    }

    $container = $syncHash.DiagDumps
    $container.Children.Clear()
    if ($dumps.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Ergebnis' 'keine Abstürze aufgezeichnet' -Kind 'ok'))
    }
    foreach ($dump in ($dumps | Select-Object -First 10)) {
        $finding = [pscustomobject]@{
            Severity       = 'critical'
            Title          = "$($dump.Code) — $($dump.Name)"
            Count          = 1
            Last           = $dump.Time
            Explanation    = $dump.Cause
            Recommendation = $dump.Recommendation
        }
        [void]$container.Children.Add((New-WzFindingRow -Finding $finding))
    }

    # --- Datenträger ------------------------------------------------------
    $disks = @($Result.Disks)
    $problems = @($disks | Where-Object { $_.Assessment -ne 'unauffällig' })
    $syncHash.DiagDisksTitle.Text = if ($problems.Count -gt 0) {
        "$($problems.Count) von $($disks.Count) Datenträger(n) auffällig"
    } else {
        "$($disks.Count) Datenträger, alle unauffällig"
    }

    $container = $syncHash.DiagDisks
    $container.Children.Clear()
    foreach ($disk in $disks) {
        $kind = if ($disk.Assessment -eq 'unauffällig') { 'ok' } else { 'warn' }
        [void]$container.Children.Add((New-WzInfoRow $disk.Model "$($disk.MediaType) · $(Format-WzBytes $disk.SizeBytes) · $($disk.BusType)"))
        [void]$container.Children.Add((New-WzInfoRow 'Zustand' $disk.Assessment -Kind $kind))
        if ($disk.PowerOnHours -ne 'n/v') { [void]$container.Children.Add((New-WzInfoRow 'Betriebszeit' $disk.PowerOnHours)) }
        if ($disk.Temperature -ne 'n/v') { [void]$container.Children.Add((New-WzInfoRow 'Temperatur' $disk.Temperature)) }
        if ($disk.Wear -ne 'n/v') { [void]$container.Children.Add((New-WzInfoRow 'Abnutzung' $disk.Wear)) }
    }

    $syncHash.DiagSummary.Text = "$($events.Count) Ereignisse · $($dumps.Count) Abstürze · $($problems.Count) Datenträgerhinweise"
    Write-WzLog "Diagnose: $($events.Count) Auffälligkeiten, $($dumps.Count) Abstürze, $($problems.Count) Datenträgerhinweise" -Level Ok
}

function New-WzFindingRow {
    <#
    .SYNOPSIS
        Ein Befund mit Titel, Häufigkeit, Erklärung und Empfehlung.
    #>
    param([Parameter(Mandatory = $true)]$Finding)

    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = $syncHash.Window.FindResource('WzBorder')
    $border.BorderThickness = New-Object Windows.Thickness(0, 0, 0, 1)
    $border.Padding = New-Object Windows.Thickness(0, 10, 0, 10)

    $stack = New-Object Windows.Controls.StackPanel

    $headerRow = New-Object Windows.Controls.StackPanel
    $headerRow.Orientation = 'Horizontal'

    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 7
    $dot.Height = 7
    $dot.VerticalAlignment = 'Center'
    $dot.Margin = New-Object Windows.Thickness(0, 0, 9, 0)
    $dot.Fill = switch ($Finding.Severity) {
        'critical' { $syncHash.Window.FindResource('WzRed') }
        'error'    { $syncHash.Window.FindResource('WzOrange') }
        default    { $syncHash.Window.FindResource('WzAmber') }
    }
    [void]$headerRow.Children.Add($dot)

    $titleBlock = New-Object Windows.Controls.TextBlock
    $titleBlock.Text = $Finding.Title
    $titleBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $titleBlock.FontSize = 13.5
    $titleBlock.FontWeight = 'SemiBold'
    $titleBlock.Foreground = $syncHash.Window.FindResource('WzTextBright')
    $titleBlock.VerticalAlignment = 'Center'
    [void]$headerRow.Children.Add($titleBlock)

    if ($Finding.Count -gt 1) {
        [void]$headerRow.Children.Add((New-WzBadge -Text "$($Finding.Count)×" -Kind 'warn'))
    }
    [void]$stack.Children.Add($headerRow)

    $metaBlock = New-Object Windows.Controls.TextBlock
    $metaBlock.Text = "zuletzt $($Finding.Last.ToString('dd.MM.yyyy HH:mm'))"
    $metaBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $metaBlock.FontSize = 10.5
    $metaBlock.Foreground = $syncHash.Window.FindResource('WzTextFaint')
    $metaBlock.Margin = New-Object Windows.Thickness(16, 3, 0, 0)
    [void]$stack.Children.Add($metaBlock)

    if ($Finding.Explanation) {
        $explanationBlock = New-Object Windows.Controls.TextBlock
        $explanationBlock.Text = $Finding.Explanation
        $explanationBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
        $explanationBlock.FontSize = 12
        $explanationBlock.Foreground = $syncHash.Window.FindResource('WzText')
        $explanationBlock.TextWrapping = 'Wrap'
        $explanationBlock.Margin = New-Object Windows.Thickness(16, 6, 0, 0)
        [void]$stack.Children.Add($explanationBlock)
    }

    if ($Finding.Recommendation) {
        $recommendationBlock = New-Object Windows.Controls.TextBlock
        $recommendationBlock.Text = "→ $($Finding.Recommendation)"
        $recommendationBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
        $recommendationBlock.FontSize = 12
        $recommendationBlock.Foreground = $syncHash.Window.FindResource('WzCyan')
        $recommendationBlock.TextWrapping = 'Wrap'
        $recommendationBlock.Margin = New-Object Windows.Thickness(16, 5, 0, 0)
        [void]$stack.Children.Add($recommendationBlock)
    }

    $border.Child = $stack
    return $border
}

function Start-WzDiagnosticsReport {
    if (-not $syncHash.DiagResult) { return }

    Invoke-WzTask -Name 'Bericht erstellen' -ScriptBlock {
        New-WzDiagReport -Result $syncHash.DiagResult
    } -OnComplete {
        param($file)
        if (-not $file) { return }
        Show-WzInfo -Title 'Bericht erstellt' `
            -Message 'Der Bericht liegt auf dem WinZii-Datenträger und lässt sich in jedem Browser öffnen — auch als Ausdruck für den Kunden geeignet.' `
            -Items @($file)
        Start-Process $file
    }
}

function Start-WzRepairTool {
    param([ValidateSet('sfc', 'dism', 'chkdsk')][string]$Kind)

    $config = switch ($Kind) {
        'sfc' {
            @{ Title = 'Systemdateien prüfen'
               Message = 'Windows vergleicht alle Systemdateien mit dem Original und ersetzt beschädigte. Dauert 5 bis 15 Minuten.'
               Block = { Invoke-WzSfc } }
        }
        'dism' {
            @{ Title = 'Windows-Abbild reparieren'
               Message = 'DISM prüft das Windows-Abbild und lädt fehlende Bestandteile bei Bedarf von Microsoft nach. Dauert 5 bis 20 Minuten und braucht Internet.'
               Block = { Invoke-WzDismRepair -Action RestoreHealth } }
        }
        'chkdsk' {
            @{ Title = 'Dateisystem prüfen'
               Message = 'Prüft das Dateisystem im laufenden Betrieb. Ein Neustart ist dafür nicht nötig.'
               Block = { Invoke-WzChkdsk } }
        }
    }

    $answer = Show-WzConfirm -Title $config.Title -Message $config.Message -ConfirmText 'Starten'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name $config.Title -ScriptBlock $config.Block -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzInfo -Title $config.Title -Message $result.Summary
    }.GetNewClosure()
}

function Start-WzBatteryReport {
    Invoke-WzTask -Name 'Akkubericht' -ScriptBlock {
        New-WzBatteryReport
    } -OnComplete {
        param($file)
        if ($file) {
            Start-Process $file
        } else {
            Show-WzInfo -Title 'Kein Akku' -Message 'Dieser PC hat keinen Akku — ein Bericht ist daher nicht möglich.'
        }
    }
}
