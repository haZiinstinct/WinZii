# Seite "Autostart" — Einträge ein- und ausschalten wie im Task-Manager.

function Initialize-WzAutostartPage {
    $syncHash.AutoBtnRefresh.Add_Click({ Update-WzAutostartPage -Force })

    [void]$syncHash.AutoNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Im Zweifel abschalten statt löschen: Der Eintrag bleibt bestehen und lässt sich mit einem Klick zurückholen. Programme wie Virenschutz oder Cloud-Speicher sollten anbleiben.'))
}

function Update-WzAutostartPage {
    param([switch]$Force)

    if ($syncHash.AutoLoaded -and -not $Force) { return }
    $syncHash.AutoLoaded = $true

    $syncHash.AutoCountHint.Text = 'wird geladen...'

    Invoke-WzTask -Name 'Autostart einlesen' -Silent -ScriptBlock {
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
    $syncHash.AutoCount.Text = "$($active.Count) aktiv"
    $syncHash.AutoCountHint.Text = "von $($Items.Count) Einträgen insgesamt"

    $container = $syncHash.AutoItems
    $container.Children.Clear()

    if ($Items.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Ergebnis' 'keine Autostart-Einträge gefunden' -Kind 'ok'))
        return
    }

    foreach ($item in $Items) {
        [void]$container.Children.Add((New-WzAutostartRow -Item $item))
    }
    Write-WzLog "Autostart: $($active.Count) von $($Items.Count) Einträgen aktiv" -Level Info
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
            $verb = if ($target) { 'eingeschaltet' } else { 'abgeschaltet' }
            Add-WzAction -Area 'Autostart' -Summary "»$($this.Tag.Name)« beim Systemstart $verb"
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
    $commandBlock.ToolTip = "$($Item.Command)`n`nQuelle: $($Item.Path)`nGilt für: $($Item.Scope)"
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
    $syncHash.AutoCount.Text = "$active aktiv"
    $syncHash.AutoCountHint.Text = "von $($toggles.Count) Einträgen insgesamt"
}
