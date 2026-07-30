# Seite "Bereinigung" — Analyse mit Größenangaben, dann gezieltes Löschen.

function Initialize-WzCleanupPage {
    $syncHash.CleanRows = Build-WzCleanupList

    $syncHash.CleanBtnAnalyze.Add_Click({ Start-WzCleanupScan })
    $syncHash.CleanBtnClean.Add_Click({ Start-WzCleanupRun })
    $syncHash.CleanBtnRecommended.Add_Click({
        foreach ($entry in $syncHash.CleanRows) {
            $entry.CheckBox.IsChecked = [bool]$entry.Category.defaultChecked
        }
        Update-WzCleanupSelection
    })

    [void]$syncHash.CleanNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Browser sollten vor dem Löschen geschlossen sein, sonst bleiben gesperrte Dateien liegen. Anmeldungen, Lesezeichen und Passwörter sind nicht betroffen.'))

    Update-WzCleanupSelection
}

function Build-WzCleanupList {
    <#
    .SYNOPSIS
        Baut die Gruppenkarten mit je einer Zeile pro Kategorie.
    #>
    $container = $syncHash.CleanGroups
    $container.Children.Clear()
    $rows = New-Object Collections.ArrayList

    $categories = Get-WzCleanupCategories
    foreach ($group in (Get-WzCleanupGroups)) {
        $groupCategories = @($categories | Where-Object { $_.group -eq $group.id })
        if ($groupCategories.Count -eq 0) { continue }

        $card = New-Object Windows.Controls.Border
        $card.Style = $syncHash.Window.FindResource('WzCardStatic')
        $card.Margin = New-Object Windows.Thickness(0, 0, 0, 14)

        $stack = New-Object Windows.Controls.StackPanel

        $eyebrow = New-Object Windows.Controls.TextBlock
        $eyebrow.Text = "// $($group.name.ToUpper())"
        $eyebrow.Style = $syncHash.Window.FindResource('WzEyebrow')
        [void]$stack.Children.Add($eyebrow)

        $lead = New-Object Windows.Controls.TextBlock
        $lead.Text = $group.description
        $lead.Style = $syncHash.Window.FindResource('WzLabel')
        $lead.TextWrapping = 'Wrap'
        $lead.Margin = New-Object Windows.Thickness(0, 0, 0, 12)
        [void]$stack.Children.Add($lead)

        foreach ($category in $groupCategories) {
            $row = New-WzCleanupRow -Category $category
            [void]$stack.Children.Add($row.Row)
            [void]$rows.Add($row)
        }

        $card.Child = $stack
        [void]$container.Children.Add($card)
    }

    return $rows
}

function New-WzCleanupRow {
    <#
    .SYNOPSIS
        Eine Kategoriezeile: Checkbox, Name, Beschreibung, Größe rechts.
    #>
    param([Parameter(Mandatory = $true)]$Category)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 5, 0, 5)
    foreach ($width in @('Auto', '*', 'Auto')) {
        $column = New-Object Windows.Controls.ColumnDefinition
        $column.Width = $width
        [void]$grid.ColumnDefinitions.Add($column)
    }

    $checkBox = New-Object Windows.Controls.CheckBox
    $checkBox.IsChecked = [bool]$Category.defaultChecked
    $checkBox.Style = $syncHash.Window.FindResource('WzCheckBox')
    $checkBox.VerticalAlignment = 'Top'
    $checkBox.Margin = New-Object Windows.Thickness(0, 2, 10, 0)
    $checkBox.Add_Click({ Update-WzCleanupSelection })
    [Windows.Controls.Grid]::SetColumn($checkBox, 0)
    [void]$grid.Children.Add($checkBox)

    $textStack = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($textStack, 1)

    $headerRow = New-Object Windows.Controls.StackPanel
    $headerRow.Orientation = 'Horizontal'

    $nameBlock = New-Object Windows.Controls.TextBlock
    $nameBlock.Text = $Category.name
    $nameBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $nameBlock.FontSize = 13.5
    $nameBlock.Foreground = $syncHash.Window.FindResource('WzTextBright')
    [void]$headerRow.Children.Add($nameBlock)

    if ($Category.risk -ne 'low') {
        [void]$headerRow.Children.Add((New-WzBadge -Text $Category.risk.ToUpper() -Kind $Category.risk))
    }
    if ($Category.method -eq 'reportOnly') {
        [void]$headerRow.Children.Add((New-WzBadge -Text 'NUR ANZEIGE' -Kind 'info'))
    }
    [void]$textStack.Children.Add($headerRow)

    $descriptionBlock = New-Object Windows.Controls.TextBlock
    $descriptionBlock.Text = $Category.description
    $descriptionBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $descriptionBlock.FontSize = 11.5
    $descriptionBlock.Foreground = $syncHash.Window.FindResource('WzTextDim')
    $descriptionBlock.TextWrapping = 'Wrap'
    $descriptionBlock.Margin = New-Object Windows.Thickness(0, 2, 12, 0)
    [void]$textStack.Children.Add($descriptionBlock)

    $noteBlock = New-Object Windows.Controls.TextBlock
    $noteBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $noteBlock.FontSize = 10.5
    $noteBlock.Foreground = $syncHash.Window.FindResource('WzAmber')
    $noteBlock.TextWrapping = 'Wrap'
    $noteBlock.Visibility = [Windows.Visibility]::Collapsed
    $noteBlock.Margin = New-Object Windows.Thickness(0, 3, 12, 0)
    [void]$textStack.Children.Add($noteBlock)

    [void]$grid.Children.Add($textStack)

    $sizeBlock = New-Object Windows.Controls.TextBlock
    $sizeBlock.Text = '—'
    $sizeBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $sizeBlock.FontSize = 13
    $sizeBlock.Foreground = $syncHash.Window.FindResource('WzTextFaint')
    $sizeBlock.VerticalAlignment = 'Top'
    $sizeBlock.MinWidth = 80
    $sizeBlock.TextAlignment = 'Right'
    [Windows.Controls.Grid]::SetColumn($sizeBlock, 2)
    [void]$grid.Children.Add($sizeBlock)

    return [pscustomobject]@{
        Category  = $Category
        Row       = $grid
        CheckBox  = $checkBox
        SizeBlock = $sizeBlock
        NoteBlock = $noteBlock
        Bytes     = [int64]0
    }
}

function Start-WzCleanupScan {
    <#
    .SYNOPSIS
        Ermittelt für jede Kategorie den belegten Platz.
    #>
    $syncHash.CleanTotal.Text = 'wird berechnet...'
    $syncHash.CleanTotalHint.Text = 'Große Ordner brauchen einen Moment.'
    foreach ($entry in $syncHash.CleanRows) {
        $entry.SizeBlock.Text = '...'
        $entry.SizeBlock.Foreground = $syncHash.Window.FindResource('WzTextFaint')
    }

    $categories = @($syncHash.CleanRows | ForEach-Object { $_.Category })

    Invoke-WzTask -Name 'Speicherplatz analysieren' -ArgumentList (, $categories) -ScriptBlock {
        param($categories)
        $results = @{}
        foreach ($category in $categories) {
            $results[$category.id] = Measure-WzCleanupCategory -Category $category
        }
        $results
    } -OnComplete {
        param($results)
        if (-not $results) { return }

        $total = [int64]0
        foreach ($entry in $syncHash.CleanRows) {
            if (-not $results.ContainsKey($entry.Category.id)) { continue }
            $measure = $results[$entry.Category.id]
            $entry.Bytes = $measure.Bytes

            if ($measure.Detail -and $measure.Bytes -eq 0) {
                $entry.SizeBlock.Text = '?'
            } else {
                $entry.SizeBlock.Text = Format-WzBytes $measure.Bytes
            }
            $entry.SizeBlock.Foreground = if ($measure.Bytes -gt 500MB) {
                $syncHash.Window.FindResource('WzAmber')
            } elseif ($measure.Bytes -gt 0) {
                $syncHash.Window.FindResource('WzText')
            } else {
                $syncHash.Window.FindResource('WzTextFaint')
            }

            $notes = @()
            if ($measure.Blocked) { $notes += $measure.Blocked }
            if ($measure.Detail) { $notes += $measure.Detail }
            if ($notes.Count -gt 0) {
                $entry.NoteBlock.Text = $notes -join ' · '
                $entry.NoteBlock.Visibility = [Windows.Visibility]::Visible
            } else {
                $entry.NoteBlock.Visibility = [Windows.Visibility]::Collapsed
            }

            # Nur Kategorien zählen, die auch wirklich gelöscht werden
            if ($entry.Category.method -ne 'reportOnly') { $total += $measure.Bytes }
        }

        $syncHash.CleanTotal.Text = Format-WzBytes $total
        $syncHash.CleanTotalHint.Text = 'insgesamt löschbar — die Auswahl bestimmt, was davon entfernt wird'
        $syncHash.CleanScanned = $true
        Update-WzCleanupSelection
        Write-WzLog "Analyse abgeschlossen: $(Format-WzBytes $total) könnten freigegeben werden." -Level Ok
    }
}

function Update-WzCleanupSelection {
    $selected = @($syncHash.CleanRows | Where-Object { $_.CheckBox.IsChecked })
    $bytes = ($selected | Where-Object { $_.Category.method -ne 'reportOnly' } |
        Measure-Object -Property Bytes -Sum).Sum
    if (-not $bytes) { $bytes = 0 }

    $syncHash.CleanSelectionInfo.Text = if ($syncHash.CleanScanned) {
        "$($selected.Count) Kategorie(n) ausgewählt · $(Format-WzBytes $bytes) werden gelöscht"
    } else {
        "$($selected.Count) Kategorie(n) ausgewählt"
    }
    $syncHash.CleanBtnClean.IsEnabled = ($selected.Count -gt 0)
}

function Start-WzCleanupRun {
    $selected = @($syncHash.CleanRows | Where-Object { $_.CheckBox.IsChecked })
    if ($selected.Count -eq 0) { return }

    $deletable = @($selected | Where-Object { $_.Category.method -ne 'reportOnly' })
    if ($deletable.Count -eq 0) {
        Show-WzInfo -Title 'Nichts zu löschen' `
            -Message 'Die gewählten Einträge dienen nur der Auswertung. WinZii löscht dort nichts.'
        return
    }

    $bytes = ($deletable | Measure-Object -Property Bytes -Sum).Sum
    $items = foreach ($entry in $deletable) {
        if ($entry.Bytes -gt 0) {
            "$($entry.Category.name) — $(Format-WzBytes $entry.Bytes)"
        } else {
            $entry.Category.name
        }
    }

    $riskyCount = @($deletable | Where-Object { $_.Category.risk -eq 'high' }).Count
    $message = "$($deletable.Count) Kategorie(n) werden gelöscht"
    if ($bytes -gt 0) { $message += ", etwa $(Format-WzBytes $bytes)" }
    $message += '.'
    if ($riskyCount -gt 0) {
        $message += ' Darunter sind Einträge, die sich nicht rückgängig machen lassen.'
    }
    if ($syncHash.DryRun) { $message = "Testmodus: Es wird nur aufgelistet, was gelöscht würde. $message" }

    $answer = Show-WzConfirm -Title 'Bereinigung starten' -Message $message -Items $items `
        -ConfirmText $(if ($syncHash.DryRun) { 'Testlauf starten' } else { 'Jetzt löschen' }) `
        -Danger:($riskyCount -gt 0)
    if (-not $answer.Confirmed) {
        Write-WzLog 'Bereinigung abgebrochen.' -Level Info
        return
    }

    $categories = @($deletable | ForEach-Object { $_.Category })

    Invoke-WzTask -Name 'Bereinigung' -ArgumentList (, $categories) -ScriptBlock {
        param($categories)
        Invoke-WzCleanup -Categories $categories
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        $lines = @()
        if ($syncHash.DryRun) {
            $lines += 'Testlauf beendet — es wurde nichts gelöscht.'
        } else {
            $lines += "$(Format-WzBytes $summary.FreedBytes) freigegeben."
            $lines += "$($summary.Removed) Objekt(e) entfernt."
        }
        if ($summary.Failed -gt 0) {
            $lines += "$($summary.Failed) Objekt(e) waren gesperrt und blieben liegen — bei Zwischenspeichern ist das normal."
        }

        Show-WzInfo -Title 'Bereinigung abgeschlossen' -Message ($lines -join ' ')
        Start-WzCleanupScan
    }
}
