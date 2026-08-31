# Seite "Diagnose" — Analyse und Reparaturwerkzeuge.

function Initialize-WzDiagnosticsPage {
    foreach ($range in @(7, 14, 30, 90)) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = Get-WzText 'diag.periodDays' @{ tage = $range }
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
        -Text (Get-WzText 'diag.noticeReadOnly')))
}

function Start-WzDiagnosticsScan {
    $days = $syncHash.DiagRange.SelectedItem.Tag

    $syncHash.DiagEventsTitle.Text = Get-WzText 'diag.analysing'
    $syncHash.DiagEvents.Children.Clear()
    $syncHash.DiagDumps.Children.Clear()
    $syncHash.DiagDisks.Children.Clear()

    Invoke-WzTask -Name (Get-WzText 'diag.taskDiag') -ArgumentList @($days) -ScriptBlock {
        param($days)
        [pscustomobject]@{
            Events      = Get-WzEventSummary -Days $days
            Dumps       = Get-WzMinidumps -Days 90
            Disks       = Get-WzSmartStatus
            Boot        = Get-WzBootPerformance
            # Die Zuverlässigkeitsüberwachung war fertig gebaut, wurde aber von
            # niemandem aufgerufen. Sie stellt Abstürze und Installationen
            # nebeneinander — das kann die Ereignisauswertung nicht.
            Reliability = Get-WzReliabilityRecords -Days $days
            Days        = $days
        }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $syncHash.DiagResult = $result
        Write-WzDiagnosticsResult -Result $result
        $syncHash.DiagBtnReport.IsEnabled = $true
    }
}

function Write-WzDiagnosticsReliability {
    <#
    .SYNOPSIS
        Füllt die Karte »Zuverlässigkeit«.
    .NOTES
        Get-WzReliabilityRecords war seit Phase 7 fertig gebaut und hatte
        keinen einzigen Aufrufer.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Records)

    $container = $syncHash.DiagReliability
    $container.Children.Clear()

    $problems = @($Records | Where-Object { $_.Type -ne 'Ereignis' })
    $syncHash.DiagReliabilityTitle.Text = if ($Records.Count -eq 0) {
        Get-WzText 'diag.relNone'
    } elseif ($problems.Count -eq 0) {
        Get-WzText 'diag.relClean' @{ anzahl = $Records.Count }
    } else {
        Get-WzText 'diag.relProblems' @{ probleme = $problems.Count; gesamt = $Records.Count }
    }

    # Nur die jüngsten zeigen; die vollständige Liste steht im Bericht
    foreach ($record in ($Records | Select-Object -First 12)) {
        $kind = switch ($record.Type) {
            'Absturz'       { 'error' }
            'Programmfehler' { 'warn' }
            default         { 'normal' }
        }
        [void]$container.Children.Add((New-WzInfoRow `
            (Get-WzText 'diag.relRow' @{ zeit = $record.Time.ToString('g', (Get-WzLanguageCulture)); typ = $record.Type }) `
            (Get-WzText 'diag.relDetail' @{ quelle = $record.Source; meldung = $record.Message }) -Kind $kind -LabelWidth 190))
    }
    if ($Records.Count -gt 12) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblMore') `
            (Get-WzText 'diag.relMore' @{ anzahl = ($Records.Count - 12) }) -LabelWidth 190))
    }
}

function Write-WzDiagnosticsResult {
    param([Parameter(Mandatory = $true)]$Result)

    # --- Ereignisse -------------------------------------------------------
    $events = @($Result.Events)
    $critical = @($events | Where-Object { $_.Severity -eq 'critical' })
    $syncHash.DiagEventsTitle.Text = if ($events.Count -eq 0) {
        Get-WzText 'diag.eventsNone' @{ tage = $Result.Days }
    } else {
        Get-WzText 'diag.eventsFound' @{ anzahl = $events.Count; kritisch = $critical.Count }
    }

    $container = $syncHash.DiagEvents
    $container.Children.Clear()
    if ($events.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblResult') (Get-WzText 'diag.inconspicuous') -Kind 'ok'))
    }
    foreach ($event in ($events | Select-Object -First 20)) {
        [void]$container.Children.Add((New-WzFindingRow -Finding $event))
    }
    if ($events.Count -gt 20) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblHint') (Get-WzText 'diag.eventsMore' @{ anzahl = ($events.Count - 20) })))
    }

    # --- Startdauer -------------------------------------------------------
    $boot = $Result.Boot
    $container = $syncHash.DiagBoot
    $container.Children.Clear()

    if (-not $boot -or $boot.Runs.Count -eq 0) {
        $syncHash.DiagBootTitle.Text = Get-WzText 'diag.bootNone'
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblHint') $(if ($boot) { $boot.Hint } else { Get-WzText 'diag.notQueryable' })))
    } else {
        $syncHash.DiagBootTitle.Text = Get-WzText 'diag.bootAverage' @{ dauer = (Format-WzSeconds $boot.AverageSeconds -Unit (Get-WzText 'diag.unitSeconds')) }
        $kind = if ($boot.AverageSeconds -lt 30) { 'ok' } elseif ($boot.AverageSeconds -lt 60) { 'warn' } else { 'error' }
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblRating') $boot.Hint -Kind $kind))

        $latest = $boot.Runs[0]
        # Die Aufteilung lag schon immer im Ergebnis und wurde nie gezeigt. Sie
        # beantwortet die eigentliche Frage: liegt es an Windows oder am Autostart?
        $windowsSeconds = $latest.MainPathMs / 1000
        $afterSeconds = [int]$latest.DegradedBy / 1000
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblLastBoot') `
            (Get-WzText 'diag.bootLastValue' @{ zeit = $latest.Time.ToString('g', (Get-WzLanguageCulture)); dauer = (Format-WzSeconds $latest.TotalSeconds) })))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblOfWindows') (Format-WzSeconds $windowsSeconds)))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblOfStartup') (Format-WzSeconds $afterSeconds) `
            -Kind $(if ($afterSeconds -gt $windowsSeconds) { 'warn' } else { 'normal' })))

        if ($boot.Runs.Count -gt 1) {
            $oldest = $boot.Runs[$boot.Runs.Count - 1]
            [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblOldest') `
                (Get-WzText 'diag.bootOldestValue' @{ zeit = $oldest.Time.ToString('d', (Get-WzLanguageCulture)); dauer = (Format-WzSeconds $oldest.TotalSeconds); anzahl = $boot.Runs.Count })))
        }

        if ($boot.Worst.Count -gt 0) {
            foreach ($culprit in $boot.Worst) {
                [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblSlowsDown') `
                    (Get-WzText 'diag.culpritValue' @{ name = $culprit.Name; dauer = (Format-WzSeconds $culprit.DelaySeconds) }) -Kind 'warn'))
            }
        }
    }

    # --- Zuverlässigkeitsverlauf ------------------------------------------
    Write-WzDiagnosticsReliability -Records @($Result.Reliability)

    # --- Abstürze (Fortsetzung nach der Zuverlässigkeit) ------------------
    $dumps = @($Result.Dumps)
    $syncHash.DiagDumpsTitle.Text = if ($dumps.Count -eq 0) {
        Get-WzText 'diag.dumpsNone'
    } else {
        Get-WzText 'diag.dumpsFound' @{ anzahl = $dumps.Count }
    }

    $container = $syncHash.DiagDumps
    $container.Children.Clear()
    if ($dumps.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblResult') (Get-WzText 'diag.noCrashes') -Kind 'ok'))
    }
    foreach ($dump in ($dumps | Select-Object -First 10)) {
        $finding = [pscustomobject]@{
            Severity       = 'critical'
            Title          = (Get-WzText 'diag.dumpTitle' @{ code = $dump.Code; name = $dump.Name })
            Count          = 1
            Last           = $dump.Time
            Explanation    = $dump.Cause
            Recommendation = $dump.Recommendation
        }
        [void]$container.Children.Add((New-WzFindingRow -Finding $finding))
    }

    # --- Datenträger ------------------------------------------------------
    $disks = @($Result.Disks)
    $problems = @($disks | Where-Object { -not $_.AssessmentOk })
    $syncHash.DiagDisksTitle.Text = if ($problems.Count -gt 0) {
        Get-WzText 'diag.disksProblems' @{ probleme = $problems.Count; gesamt = $disks.Count }
    } else {
        Get-WzText 'diag.disksClean' @{ anzahl = $disks.Count }
    }

    $container = $syncHash.DiagDisks
    $container.Children.Clear()
    foreach ($disk in $disks) {
        $kind = if ($disk.AssessmentOk) { 'ok' } else { 'warn' }
        [void]$container.Children.Add((New-WzInfoRow $disk.Model (Get-WzText 'diag.diskDetail' @{ art = $disk.MediaType; groesse = (Format-WzBytes $disk.SizeBytes); bus = $disk.BusType })))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblCondition') $disk.Assessment -Kind $kind))
        if ($disk.PowerOnHours -ne 'n/v') { [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblPowerOn') $disk.PowerOnHours)) }
        if ($disk.Temperature -ne 'n/v') { [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblTemperature') $disk.Temperature)) }
        if ($disk.Wear -ne 'n/v') {
            [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'diag.lblWear') $disk.Wear))
            if ($null -ne $disk.WearPercent) {
                [void]$container.Children.Add((New-WzMeter -Percent $disk.WearPercent `
                    -Caption (Get-WzText 'diag.wearCaption' @{ prozent = $disk.WearPercent })))
            }
        }
    }

    $syncHash.DiagSummary.Text = Get-WzText 'diag.summary' @{ ereignisse = $events.Count; abstuerze = $dumps.Count; datentraeger = $problems.Count }
    Write-WzLog (Get-WzText 'diag.logSummary' @{ ereignisse = $events.Count; abstuerze = $dumps.Count; datentraeger = $problems.Count }) -Level Ok
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

    Invoke-WzTask -Name (Get-WzText 'diag.taskReport') -ScriptBlock {
        New-WzDiagReport -Result $syncHash.DiagResult
    } -OnComplete {
        param($file)
        if (-not $file) { return }
        Show-WzInfo -Title (Get-WzText 'diag.reportTitle') `
            -Message (Get-WzText 'diag.reportMessage') `
            -Items @($file)
        Start-Process $file
    }
}

function Start-WzRepairTool {
    param([ValidateSet('sfc', 'dism', 'chkdsk')][string]$Kind)

    $config = switch ($Kind) {
        'sfc' {
            @{ Title = (Get-WzText 'diag.sfcTitle')
               Message = (Get-WzText 'diag.sfcMessage')
               Block = { Invoke-WzSfc } }
        }
        'dism' {
            @{ Title = (Get-WzText 'diag.dismTitle')
               Message = (Get-WzText 'diag.dismMessage')
               Block = { Invoke-WzDismRepair -Action RestoreHealth } }
        }
        'chkdsk' {
            @{ Title = (Get-WzText 'diag.chkdskTitle')
               Message = (Get-WzText 'diag.chkdskMessage')
               Block = { Invoke-WzChkdsk } }
        }
    }

    $answer = Show-WzConfirm -Title $config.Title -Message $config.Message -ConfirmText (Get-WzText 'diag.btnStart')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name $config.Title -ScriptBlock $config.Block -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzInfo -Title $config.Title -Message $result.Summary
    }.GetNewClosure()
}

function Start-WzBatteryReport {
    Invoke-WzTask -Name (Get-WzText 'diag.taskBattery') -ScriptBlock {
        New-WzBatteryReport
    } -OnComplete {
        param($file)
        if ($file) {
            Start-Process $file
        } else {
            Show-WzInfo -Title (Get-WzText 'diag.noBatteryTitle') -Message (Get-WzText 'diag.noBatteryMessage')
        }
    }
}
