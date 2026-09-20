# Core.Palette — die Suche über alles, was WinZii kann.
#
# Sechzehn Seiten sind zu viele, um jede Funktion aus dem Gedächtnis zu
# finden. Wer weiß, dass es »irgendwo« einen Knopf für die Druckerwarteschlange
# gibt, sucht sonst drei Seiten ab. Strg+K fragt danach.
#
# Bewusst nur Sprungziele und Handgriffe ohne eigene Rückfrage: Ein Eingriff,
# der aus einem Suchfeld heraus losläuft, ist genau die Art Überraschung, die
# dieses Werkzeug sonst vermeidet.

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

    # Stichwörter je Seite. Ohne sie fände die Suche nur den Seitennamen — wer
    # »drucker« tippt, weiß aber nicht, dass die Warteschlange unter
    # »Reparatur« liegt. Ausgeschrieben statt zusammengesetzt, damit
    # Test-Language die Schlüssel als benutzt erkennt.
    $keywords = @{
        Dashboard   = (Get-WzText 'palette.keysDashboard')
        Setup       = (Get-WzText 'palette.keysSetup')
        Diagnostics = (Get-WzText 'palette.keysDiagnostics')
        Updates     = (Get-WzText 'palette.keysUpdates')
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
        # Die Beschriftung steht im zweiten Textblock des Knopfes — der erste
        # trägt das Symbol.
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
            $syncHash.DryRunToggle.IsChecked = (-not $syncHash.DryRunToggle.IsChecked)
            # Den Klick nachbilden, damit Abzeichen und Protokollzeile mitgehen
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
        Action = { Start-Process (Get-WzReportDir) }
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
        Filtert die Einträge nach der Eingabe.
    .DESCRIPTION
        Gesucht wird in Titel und Erläuterung, Groß- und Kleinschreibung egal.
        Wer »drucker« tippt, soll die Reparaturseite finden, ohne zu wissen,
        dass sie so heißt — deshalb steht in der Erläuterung der Seiten
        mehr als nur das Wort »Seite«.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Entries,
        [AllowEmptyString()][string]$Query
    )

    if ([string]::IsNullOrWhiteSpace($Query)) { return @($Entries) }

    $needle = $Query.Trim()
    # Erst die Einträge, die vorn passen, dann die übrigen Treffer: Wer »dash«
    # tippt, will das Dashboard oben sehen und nicht an dritter Stelle.
    $starts = @($Entries | Where-Object { $_.Title -like "$needle*" })
    $contains = @($Entries | Where-Object {
        $_ -notin $starts -and ("$($_.Title) $($_.Detail)" -like "*$needle*") })

    return @($starts + $contains)
}

function Show-WzPalette {
    <#
    .SYNOPSIS
        Öffnet die Suche über alle Seiten und Handgriffe.
    .NOTES
        Aufbau und Verhalten wie der Bestätigungsdialog: abgedunkelter Grund,
        Escape schließt, ein Klick daneben auch. Das ist der Weg, den alle
        anderen Fenster in WinZii nehmen, und der in Test-Dialogs abgedeckt ist.
    #>
    [CmdletBinding()]
    param()

    if (-not $syncHash.Window) { return }
    # Während eines Eingriffs hilft ein Sprung auf eine andere Seite niemandem
    # und würde nur den laufenden Vorgang verdecken.
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
        $window.Width = 560
        $window.Height = 420
    }

    $backdrop = New-Object Windows.Controls.Grid
    $backdrop.Background = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString('#B3000000'))
    $backdrop.Add_MouseLeftButtonDown({ $window.Close() }.GetNewClosure())

    $card = New-Object Windows.Controls.Border
    $card.Background = $syncHash.Window.FindResource('WzBgCard')
    $card.BorderBrush = $syncHash.Window.FindResource('WzBorder')
    $card.BorderThickness = New-Object Windows.Thickness(1)
    $card.Width = 560
    $card.MaxHeight = 420
    $card.VerticalAlignment = 'Top'
    $card.HorizontalAlignment = 'Center'
    $card.Margin = New-Object Windows.Thickness(0, 90, 0, 0)
    # Ein Klick auf die Karte darf nicht bis zur Abdunklung durchfallen und
    # das Fenster schließen.
    $card.Add_MouseLeftButtonDown({ param($sender, $eventArgs) $eventArgs.Handled = $true })

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = New-Object Windows.Thickness(18)

    $eyebrow = New-Object Windows.Controls.TextBlock
    $eyebrow.Text = Get-WzText 'palette.eyebrow'
    $eyebrow.Style = $syncHash.Window.FindResource('WzEyebrow')
    [void]$stack.Children.Add($eyebrow)

    $box = New-Object Windows.Controls.TextBox
    $box.Style = $syncHash.Window.FindResource('WzTextBox')
    $box.Margin = New-Object Windows.Thickness(0, 6, 0, 10)
    [void]$stack.Children.Add($box)

    $list = New-Object Windows.Controls.ListBox
    $list.Background = [Windows.Media.Brushes]::Transparent
    $list.BorderThickness = New-Object Windows.Thickness(0)
    $list.MaxHeight = 280
    $list.Foreground = $syncHash.Window.FindResource('WzText')
    $list.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    [void]$stack.Children.Add($list)

    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = Get-WzText 'palette.hint'
    $hint.Style = $syncHash.Window.FindResource('WzHint')
    $hint.Margin = New-Object Windows.Thickness(0, 10, 0, 0)
    [void]$stack.Children.Add($hint)

    $card.Child = $stack
    [void]$backdrop.Children.Add($card)
    $window.Content = $backdrop

    $fill = {
        param($query)
        $found = Select-WzPaletteMatches -Entries $entries -Query $query
        $list.Items.Clear()
        foreach ($entry in $found) {
            $item = New-Object Windows.Controls.ListBoxItem
            $item.Content = "$($entry.Title)   —   $($entry.Detail)"
            $item.Tag = $entry
            $item.Padding = New-Object Windows.Thickness(8, 6, 8, 6)
            [void]$list.Items.Add($item)
        }
        if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    }.GetNewClosure()

    $run = {
        $chosen = $list.SelectedItem
        if (-not $chosen) { return }
        $entry = $chosen.Tag
        $window.Close()
        # Erst schließen, dann handeln: Sonst legt sich ein Dialog des
        # aufgerufenen Handgriffs unter die Palette.
        [void]$syncHash.Window.Dispatcher.BeginInvoke(
            [Windows.Threading.DispatcherPriority]::Background,
            [action]{ & $entry.Action }.GetNewClosure())
    }.GetNewClosure()

    $box.Add_TextChanged({ & $fill $box.Text }.GetNewClosure())

    # Die Tasten hängen am FENSTER, nicht am Suchfeld. Am Feld griffen sie nur,
    # solange der Fokus dort steht — wer einmal in die Liste geklickt hat,
    # bekäme das Fenster mit Escape nicht mehr zu. Ein Suchfenster, das
    # hängen bleibt, sperrt die ganze Oberfläche.
    $window.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        switch ($eventArgs.Key) {
            'Down' {
                if ($list.SelectedIndex -lt $list.Items.Count - 1) { $list.SelectedIndex++ }
                $eventArgs.Handled = $true
            }
            'Up' {
                if ($list.SelectedIndex -gt 0) { $list.SelectedIndex-- }
                $eventArgs.Handled = $true
            }
            'Enter' { & $run; $eventArgs.Handled = $true }
            'Escape' { $window.Close(); $eventArgs.Handled = $true }
        }
    }.GetNewClosure())
    $list.Add_MouseDoubleClick({ & $run }.GetNewClosure())

    & $fill ''
    $window.Add_Loaded({ [void]$box.Focus() }.GetNewClosure())

    # Dieselbe Buchführung wie beim Bestätigungsdialog: Test-Dialogs prüft
    # daran, ob ein Fenster wirklich zugegangen ist.
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
