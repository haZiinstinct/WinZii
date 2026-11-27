# Core.Palette — die Suche über alles, was WinZii kann.
# Strg+K oder der Suchknopf in der Kopfleiste öffnen das Schnellmenü.

function Get-WzPaletteEntries {
    <#
    .SYNOPSIS
        Alle Einträge: erst die Seiten, dann die Handgriffe.
    .OUTPUTS
        Liste mit Title, Detail, Kind und Action
    #>
    [CmdletBinding()]
    param()

    $entries = @()

    $keywords = @{
        Dashboard   = (Get-WzText 'palette.keysDashboard')
        Diagnostics = (Get-WzText 'palette.keysDiagnostics')
        Optimizer   = (Get-WzText 'palette.keysOptimizer')
        AiRemoval   = (Get-WzText 'palette.keysAiRemoval')
        Cleanup     = (Get-WzText 'palette.keysCleanup')
        Autostart   = (Get-WzText 'palette.keysAutostart')
        Apps        = (Get-WzText 'palette.keysApps')
        Uninstall   = (Get-WzText 'palette.keysUninstall')
        Office      = (Get-WzText 'palette.keysOffice')
        UserData    = (Get-WzText 'palette.keysUserData')
        Restore     = (Get-WzText 'palette.keysRestore')
        Drivers     = (Get-WzText 'palette.keysDrivers')
        Toolbox     = (Get-WzText 'palette.keysToolbox')
        Protocol    = (Get-WzText 'palette.keysProtocol')
    }

    foreach ($button in @($syncHash.NavButtons)) {
        $id = [string]$button.Tag
        if (-not $id) { continue }
        $label = $id
        try {
            $blocks = @($button.Content.Children | Where-Object { $_ -is [Windows.Controls.TextBlock] })
            if ($blocks.Count -gt 1) { $label = $blocks[1].Text }
        } catch { }

        $entries += [pscustomobject]@{
            Title  = $label
            Detail = if ($keywords.ContainsKey($id)) { $keywords[$id] } else { Get-WzText 'palette.detailPage' }
            Kind   = 'page'
            Action = { Show-WzPage -Id $id }.GetNewClosure()
        }
    }

    $entries += [pscustomobject]@{
        Title  = Get-WzText 'palette.cmdDryRun'
        Detail = Get-WzText 'palette.detailToggle'
        Kind   = 'command'
        Action = {
            if ($syncHash.Busy) {
                Write-WzLog (Get-WzText 'core.busyLog' @{ name = $syncHash.BusyName }) -Level Warn
                return
            }
            $syncHash.DryRunToggle.IsChecked = (-not $syncHash.DryRunToggle.IsChecked)
            $syncHash.DryRunToggle.RaiseEvent(
                (New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    }

    $entries += [pscustomobject]@{
        Title  = Get-WzText 'palette.cmdLanguage'
        Detail = Get-WzText 'palette.detailDialog'
        Kind   = 'command'
        Action = { Show-WzLanguageChooser }
    }

    $entries += [pscustomobject]@{
        Title  = Get-WzText 'palette.cmdConsole'
        Detail = Get-WzText 'palette.detailToggle'
        Kind   = 'command'
        Action = {
            Set-WzConsoleCollapsed -Collapsed ($syncHash.LogConsole.Visibility -eq [Windows.Visibility]::Visible)
        }
    }

    $entries += [pscustomobject]@{
        Title  = Get-WzText 'palette.cmdReportFolder'
        Detail = Get-WzText 'palette.detailOpens'
        Kind   = 'command'
        Action = {
            $folder = Get-WzReportDir
            if (Test-Path -LiteralPath $folder) { Start-Process $folder }
            else { Show-WzInfo -Title (Get-WzText 'palette.title') -Message (Get-WzText 'palette.noReports') }
        }
    }

    $entries += [pscustomobject]@{
        Title  = Get-WzText 'palette.cmdBackupFolder'
        Detail = Get-WzText 'palette.detailOpens'
        Kind   = 'command'
        Action = {
            $folder = Get-WzBackupRoot
            if (Test-Path -LiteralPath $folder) { Start-Process $folder }
            else { Show-WzInfo -Title (Get-WzText 'palette.title') -Message (Get-WzText 'palette.noBackups') }
        }
    }

    return @($entries)
}

function Select-WzPaletteMatches {
    <#
    .SYNOPSIS
        Filtert die Einträge nach einem oder mehreren Suchwörtern.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Entries,
        [AllowEmptyString()][string]$Query
    )

    if ([string]::IsNullOrWhiteSpace($Query)) { return @($Entries) }

    $needle = $Query.Trim()
    $tokens = @($needle -split '\s+' | Where-Object { $_ })

    $starts = @($Entries | Where-Object { "$($_.Title)".StartsWith($needle, [StringComparison]::OrdinalIgnoreCase) })
    $contains = @($Entries | Where-Object {
        if ($_ -in $starts) { return $false }
        $hay = "$($_.Title) $($_.Detail)"
        foreach ($token in $tokens) {
            if ($hay.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
        }
        return $true
    })

    return @($starts + $contains)
}

function Show-WzPalette {
    <#
    .SYNOPSIS
        Öffnet die Suche über alle Seiten und Handgriffe.
    #>
    [CmdletBinding()]
    param()

    if (-not $syncHash.Window) { return }
    if ($syncHash.Busy) { return }

    $entries = Get-WzPaletteEntries
    $bounds = Get-WzOverlayBounds

    $window = New-Object Windows.Window
    $window.Title = Get-WzText 'palette.title'
    $window.ResizeMode = 'NoResize'
    $window.WindowStyle = 'None'
    $window.AllowsTransparency = $true
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar = $false
    $window.Resources.MergedDictionaries.Add($syncHash.Window.Resources)

    if ($bounds) {
        $window.Owner = $syncHash.Window
        $window.WindowStartupLocation = 'Manual'
        $window.Left = $bounds.Left
        $window.Top = $bounds.Top
        $window.Width = $bounds.Width
        $window.Height = $bounds.Height
    } else {
        $window.WindowStartupLocation = 'CenterScreen'
        $window.Width = 580
        $window.Height = 460
    }

    $backdrop = New-Object Windows.Controls.Grid
    $backdrop.Background = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString('#B3000000'))
    $backdrop.Add_MouseLeftButtonDown({ $window.Close() }.GetNewClosure())

    $card = New-Object Windows.Controls.Border
    $card.Background = $syncHash.Window.FindResource('WzBgCard')
    $card.BorderBrush = $syncHash.Window.FindResource('WzCyanBorder')
    $card.BorderThickness = New-Object Windows.Thickness(1)
    $card.CornerRadius = New-Object Windows.CornerRadius(16)
    $card.Width = 580
    $card.MaxHeight = 460
    $card.VerticalAlignment = 'Top'
    $card.HorizontalAlignment = 'Center'
    $card.Margin = New-Object Windows.Thickness(0, 76, 0, 0)
    $card.Add_MouseLeftButtonDown({ param($sender, $eventArgs) $eventArgs.Handled = $true })

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = New-Object Windows.Thickness(20)

    $eyebrow = New-Object Windows.Controls.TextBlock
    $eyebrow.Text = Get-WzText 'palette.eyebrow'
    $eyebrow.Style = $syncHash.Window.FindResource('WzEyebrow')
    [void]$stack.Children.Add($eyebrow)

    $box = New-Object Windows.Controls.TextBox
    $box.Style = $syncHash.Window.FindResource('WzTextBox')
    $box.Margin = New-Object Windows.Thickness(0, 6, 0, 12)
    [void]$stack.Children.Add($box)

    $list = New-Object Windows.Controls.ListBox
    $list.Background = [Windows.Media.Brushes]::Transparent
    $list.BorderThickness = New-Object Windows.Thickness(0)
    $list.MaxHeight = 300
    $list.Foreground = $syncHash.Window.FindResource('WzText')
    $list.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $list.ItemContainerStyle = $syncHash.Window.FindResource('WzPaletteItem')
    [Windows.Controls.ScrollViewer]::SetHorizontalScrollBarVisibility($list, 'Disabled')
    [void]$stack.Children.Add($list)

    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = Get-WzText 'palette.hint'
    $hint.Style = $syncHash.Window.FindResource('WzHint')
    $hint.Margin = New-Object Windows.Thickness(0, 10, 0, 0)
    [void]$stack.Children.Add($hint)

    $card.Child = $stack
    [void]$backdrop.Children.Add($card)
    $window.Content = $backdrop

    $run = {
        param($chosenItem)
        $chosen = if ($chosenItem) { $chosenItem } else { $list.SelectedItem }
        if (-not $chosen) { return }
        $entry = $chosen.Tag
        $window.Close()
        [void]$syncHash.Window.Dispatcher.BeginInvoke(
            [Windows.Threading.DispatcherPriority]::Background,
            [action]{ & $entry.Action }.GetNewClosure())
    }.GetNewClosure()

    $fill = {
        param($query)
        $found = Select-WzPaletteMatches -Entries $entries -Query $query
        $list.Items.Clear()
        foreach ($entry in $found) {
            $item = New-Object Windows.Controls.ListBoxItem
            $item.Tag = $entry

            $rowPanel = New-Object Windows.Controls.StackPanel
            $titleBlock = New-Object Windows.Controls.TextBlock
            $titleBlock.Text = $entry.Title
            $titleBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
            $titleBlock.FontSize = 13
            $titleBlock.FontWeight = 'SemiBold'
            $titleBlock.Foreground = $syncHash.Window.FindResource('WzTextBright')
            [void]$rowPanel.Children.Add($titleBlock)

            if ($entry.Detail) {
                $detailBlock = New-Object Windows.Controls.TextBlock
                $detailBlock.Text = $entry.Detail
                $detailBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
                $detailBlock.FontSize = 11
                $detailBlock.Foreground = $syncHash.Window.FindResource('WzTextDim')
                $detailBlock.TextTrimming = 'CharacterEllipsis'
                [void]$rowPanel.Children.Add($detailBlock)
            }

            $item.Content = $rowPanel
            $capturedItem = $item
            $item.Add_MouseLeftButtonUp({ & $run $capturedItem }.GetNewClosure())
            [void]$list.Items.Add($item)
        }
        if ($list.Items.Count -gt 0) {
            $list.SelectedIndex = 0
            $list.ScrollIntoView($list.SelectedItem)
        }
    }.GetNewClosure()

    $box.Add_TextChanged({ & $fill $box.Text }.GetNewClosure())

    $window.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        switch ($eventArgs.Key) {
            'Down' {
                if ($list.SelectedIndex -lt $list.Items.Count - 1) {
                    $list.SelectedIndex++
                    $list.ScrollIntoView($list.SelectedItem)
                }
                $eventArgs.Handled = $true
            }
            'Up' {
                if ($list.SelectedIndex -gt 0) {
                    $list.SelectedIndex--
                    $list.ScrollIntoView($list.SelectedItem)
                }
                $eventArgs.Handled = $true
            }
            'Enter' { & $run $null; $eventArgs.Handled = $true }
            'Escape' { $window.Close(); $eventArgs.Handled = $true }
        }
    }.GetNewClosure())

    & $fill ''
    $window.Add_Loaded({ [void]$box.Focus() }.GetNewClosure())

    $syncHash.ActiveDialog = $window
    try {
        [void]$window.ShowDialog()
    } finally {
        $syncHash.ActiveDialog = $null
    }
}

function Register-WzPaletteShortcut {
    <#
    .SYNOPSIS
        Legt Strg+K auf das Hauptfenster.
    #>
    param([Parameter(Mandatory = $true)]$Window)

    $Window.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq 'K' -and
            ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            $eventArgs.Handled = $true
            Show-WzPalette
        }
    })
}
