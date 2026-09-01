# Seite "Autostart" — Einträge ein- und ausschalten wie im Task-Manager.

function Initialize-WzAutostartPage {
    $syncHash.AutoBtnRefresh.Add_Click({ Update-WzAutostartPage -Force })

    [void]$syncHash.AutoNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'auto.noticeDisable')))
}

function Update-WzAutostartPage {
    param([switch]$Force)

    if ($syncHash.AutoLoaded -and -not $Force) { return }
    $syncHash.AutoLoaded = $true

    $syncHash.AutoCountHint.Text = Get-WzText 'auto.loading'

    Invoke-WzTask -Name (Get-WzText 'auto.taskLoad') -Silent -ScriptBlock {
        Get-WzAutostartItems
    } -OnComplete {
        param($items)
        if (-not $items) { $items = @() }
        Write-WzAutostartList -Items @($items)
    }
}

function Write-WzAutostartList {
    param([Parameter(Mandatory = $true)]$Items)

    $active = @($Items | Where-Object { $_.Enabled })
    $syncHash.AutoCount.Text = Get-WzText 'auto.activeCount' @{ anzahl = $active.Count }
    $syncHash.AutoCountHint.Text = Get-WzText 'auto.ofTotal' @{ anzahl = $Items.Count }

    $container = $syncHash.AutoItems
    $container.Children.Clear()

    if ($Items.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'auto.lblResult') (Get-WzText 'auto.noEntries') -Kind 'ok'))
        return
    }

    foreach ($item in $Items) {
        [void]$container.Children.Add((New-WzAutostartRow -Item $item))
    }
    Write-WzLog (Get-WzText 'auto.logActive' @{ aktiv = $active.Count; gesamt = $Items.Count }) -Level Info
}

function New-WzAutostartRow {
    param([Parameter(Mandatory = $true)]$Item)

    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = $syncHash.Window.FindResource('WzBorder')
    $border.BorderThickness = New-Object Windows.Thickness(0, 0, 0, 1)
    $border.Padding = New-Object Windows.Thickness(0, 9, 0, 9)

    $grid = New-Object Windows.Controls.Grid
    foreach ($width in @('Auto', '*')) {
        $column = New-Object Windows.Controls.ColumnDefinition
        $column.Width = $width
        [void]$grid.ColumnDefinitions.Add($column)
    }

    $toggle = New-Object Windows.Controls.CheckBox
    $toggle.IsChecked = $Item.Enabled
    $toggle.Style = $syncHash.Window.FindResource('WzToggle')
    $toggle.VerticalAlignment = 'Top'
    $toggle.Margin = New-Object Windows.Thickness(0, 2, 14, 0)
    $toggle.Tag = $Item
    $toggle.Add_Click({
        $target = [bool]$this.IsChecked
        if (Set-WzAutostartItem -Item $this.Tag -Enabled $target) {
            # Beide Zweige ausgeschrieben: Test-Language findet nur wortwoertliche
            # Schluessel, ein berechneter waere fuer die Pruefung unsichtbar.
            $summary = if ($target) {
                Get-WzText 'auto.actionOn' @{ name = $this.Tag.Name }
            } else {
                Get-WzText 'auto.actionOff' @{ name = $this.Tag.Name }
            }
            Add-WzAction -Area 'Autostart' -Summary $summary
        } else {
            $this.IsChecked = -not $target
        }
        Update-WzAutostartCounts
    })
    [Windows.Controls.Grid]::SetColumn($toggle, 0)
    [void]$grid.Children.Add($toggle)

    $stack = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($stack, 1)

    $headerRow = New-Object Windows.Controls.StackPanel
    $headerRow.Orientation = 'Horizontal'

    $nameBlock = New-Object Windows.Controls.TextBlock
    $nameBlock.Text = $Item.Name
    $nameBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $nameBlock.FontSize = 13.5
    $nameBlock.Foreground = if ($Item.Enabled) {
        $syncHash.Window.FindResource('WzTextBright')
    } else {
        $syncHash.Window.FindResource('WzTextFaint')
    }
    [void]$headerRow.Children.Add($nameBlock)

    if ($Item.Publisher) {
        [void]$headerRow.Children.Add((New-WzBadge -Text $Item.Publisher -Kind 'info'))
    }
    [void]$headerRow.Children.Add((New-WzBadge -Text $Item.Source.ToUpper() -Kind 'low'))
    [void]$stack.Children.Add($headerRow)

    $commandBlock = New-Object Windows.Controls.TextBlock
    $commandBlock.Text = $Item.Command
    $commandBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $commandBlock.FontSize = 10.5
    $commandBlock.Foreground = $syncHash.Window.FindResource('WzTextDim')
    $commandBlock.TextTrimming = 'CharacterEllipsis'
    $commandBlock.Margin = New-Object Windows.Thickness(0, 3, 12, 0)
    $commandBlock.ToolTip = Get-WzText 'auto.tipCommand' @{ befehl = $Item.Command; pfad = $Item.Path; bereich = $Item.Scope }
    [void]$stack.Children.Add($commandBlock)

    [void]$grid.Children.Add($stack)
    $border.Child = $grid
    return $border
}

function Update-WzAutostartCounts {
    $toggles = @()
    foreach ($child in $syncHash.AutoItems.Children) {
        $grid = $child.Child
        if ($grid -and $grid.Children.Count -gt 0) { $toggles += $grid.Children[0] }
    }
    $active = @($toggles | Where-Object { $_.IsChecked }).Count
    $syncHash.AutoCount.Text = Get-WzText 'auto.activeCount' @{ anzahl = $active }
    $syncHash.AutoCountHint.Text = Get-WzText 'auto.ofTotal' @{ anzahl = $toggles.Count }
}
