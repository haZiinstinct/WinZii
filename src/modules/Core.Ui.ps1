# Core.Ui — XAML laden, Seiten verwalten, Dialoge im haZii-Look.
# Regeln für alle XAML-Dateien:
#   * kein x:Class, keine Event-Attribute (Verdrahtung erfolgt im Code)
#   * Ressourcen nur über DynamicResource (Seiten werden einzeln geparst)
#   * Elemente mit Name="..." landen automatisch im $syncHash

function Import-WzXaml {
    <#
    .SYNOPSIS
        Parst eine XAML-Datei und gibt das Wurzelelement zurück.
    .PARAMETER Path
        Pfad zur XAML-Datei.
    .PARAMETER Prefix
        Kennzeichnung für die Namensregistrierung im $syncHash.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Prefix = ''
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "XAML-Datei nicht gefunden: $Path"
    }

    $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    [xml]$xaml = $raw

    $reader = New-Object Xml.XmlNodeReader($xaml)
    try {
        $root = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        throw "XAML '$([IO.Path]::GetFileName($Path))' konnte nicht geladen werden: $($_.Exception.Message)"
    }

    Register-WzNames -Root $root -Xml $xaml -Prefix $Prefix
    return $root
}

function Register-WzNames {
    <#
    .SYNOPSIS
        Trägt alle benannten Elemente eines XAML-Baums in den $syncHash ein.
    #>
    param(
        [Parameter(Mandatory = $true)]$Root,
        [Parameter(Mandatory = $true)][xml]$Xml,
        [string]$Prefix = ''
    )

    foreach ($node in $Xml.SelectNodes('//*[@Name]')) {
        $name = $node.GetAttribute('Name')
        if (-not $name) { continue }
        $element = $Root.FindName($name)
        if ($element) { $syncHash[$name] = $element }
    }
}

function Show-WzPage {
    <#
    .SYNOPSIS
        Wechselt zu einer Seite. Seiten werden beim ersten Aufruf geladen
        und danach wiederverwendet.
    #>
    param([Parameter(Mandatory = $true)][string]$Id)

    if ($syncHash.Busy) {
        Write-WzLog 'Seitenwechsel während eines laufenden Vorgangs nicht möglich.' -Level Warn
        return
    }

    if (-not $syncHash.Pages.ContainsKey($Id)) {
        $pagePath = Join-Path (Get-WzXamlDir) "pages\$Id.xaml"
        if (-not (Test-Path -LiteralPath $pagePath)) {
            $syncHash.Pages[$Id] = New-WzPlaceholderPage -Id $Id
        } else {
            try {
                $syncHash.Pages[$Id] = Import-WzXaml -Path $pagePath -Prefix $Id
                $initializer = "Initialize-Wz$($Id)Page"
                if (Get-Command $initializer -ErrorAction SilentlyContinue) { & $initializer }
            } catch {
                Write-WzLog "Seite '$Id' konnte nicht geladen werden: $($_.Exception.Message)" -Level Error
                return
            }
        }
    }

    $syncHash.PageHost.Content = $syncHash.Pages[$Id]
    $syncHash.PageScroller.ScrollToTop()
    $syncHash.CurrentPage = $Id
    Update-WzNavState -ActiveId $Id

    $refresher = "Update-Wz$($Id)Page"
    if (Get-Command $refresher -ErrorAction SilentlyContinue) { & $refresher }
}

function Update-WzNavState {
    <#
    .SYNOPSIS
        Markiert den aktiven Eintrag in der Seitenleiste.
    #>
    param([string]$ActiveId)
    foreach ($button in $syncHash.NavButtons) {
        $isActive = ($button.Tag -eq $ActiveId)
        $button.Style = if ($isActive) {
            $syncHash.Window.FindResource('WzNavButtonActive')
        } else {
            $syncHash.Window.FindResource('WzNavButton')
        }
    }
}

function New-WzPlaceholderPage {
    <#
    .SYNOPSIS
        Platzhalter für Seiten, die noch nicht gebaut sind.
    #>
    param([Parameter(Mandatory = $true)][string]$Id)

    $stack = New-Object Windows.Controls.StackPanel

    $eyebrow = New-Object Windows.Controls.TextBlock
    $eyebrow.Text = '// IN ARBEIT'
    $eyebrow.Style = $syncHash.Window.FindResource('WzEyebrow')
    [void]$stack.Children.Add($eyebrow)

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $Id
    $title.Style = $syncHash.Window.FindResource('WzPageTitle')
    [void]$stack.Children.Add($title)

    $lead = New-Object Windows.Controls.TextBlock
    $lead.Text = 'Dieser Bereich wird gerade gebaut.'
    $lead.Style = $syncHash.Window.FindResource('WzPageLead')
    [void]$stack.Children.Add($lead)

    return $stack
}

function Show-WzConfirm {
    <#
    .SYNOPSIS
        Bestätigungsdialog im haZii-Look.
    .PARAMETER Items
        Zeilen, die genau auflisten, was passieren wird.
    .PARAMETER OptionText
        Wenn gesetzt, erscheint eine zusätzliche Checkbox (z. B. Wiederherstellungspunkt).
    .OUTPUTS
        PSCustomObject mit Confirmed (bool) und OptionChecked (bool)
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Items = @(),
        [string]$OptionText,
        [bool]$OptionDefault = $true,
        [string]$ConfirmText = 'Ausführen',
        [switch]$Danger
    )

    $result = [pscustomobject]@{ Confirmed = $false; OptionChecked = $OptionDefault }

    $window = New-Object Windows.Window
    $window.Title = $Title
    $window.Width = 580
    $window.SizeToContent = 'Height'
    $window.MaxHeight = 640
    $window.WindowStartupLocation = 'CenterOwner'
    $window.Owner = $syncHash.Window
    $window.ResizeMode = 'NoResize'
    $window.WindowStyle = 'None'
    $window.AllowsTransparency = $true
    $window.Background = [Windows.Media.Brushes]::Transparent

    $shell = New-Object Windows.Controls.Border
    $shell.Background = $syncHash.Window.FindResource('WzBgCard')
    $shell.BorderBrush = $syncHash.Window.FindResource('WzBorder')
    $shell.BorderThickness = New-Object Windows.Thickness(1)
    $shell.CornerRadius = New-Object Windows.CornerRadius(16)
    $shell.Padding = New-Object Windows.Thickness(28, 24, 28, 22)

    $stack = New-Object Windows.Controls.StackPanel

    $eyebrow = New-Object Windows.Controls.TextBlock
    $eyebrow.Text = if ($Danger) { '// ACHTUNG' } else { '// BESTÄTIGUNG' }
    $eyebrow.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $eyebrow.FontSize = 10.5
    $eyebrow.Foreground = if ($Danger) {
        $syncHash.Window.FindResource('WzRed')
    } else {
        $syncHash.Window.FindResource('WzCyan')
    }
    $eyebrow.Margin = New-Object Windows.Thickness(0, 0, 0, 8)
    [void]$stack.Children.Add($eyebrow)

    $titleBlock = New-Object Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $titleBlock.FontSize = 19
    $titleBlock.FontWeight = 'SemiBold'
    $titleBlock.Foreground = $syncHash.Window.FindResource('WzTextBright')
    $titleBlock.TextWrapping = 'Wrap'
    $titleBlock.Margin = New-Object Windows.Thickness(0, 0, 0, 10)
    [void]$stack.Children.Add($titleBlock)

    $messageBlock = New-Object Windows.Controls.TextBlock
    $messageBlock.Text = $Message
    $messageBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $messageBlock.FontSize = 13
    $messageBlock.Foreground = $syncHash.Window.FindResource('WzTextDim')
    $messageBlock.TextWrapping = 'Wrap'
    $messageBlock.Margin = New-Object Windows.Thickness(0, 0, 0, 16)
    [void]$stack.Children.Add($messageBlock)

    if ($Items.Count -gt 0) {
        $listBorder = New-Object Windows.Controls.Border
        $listBorder.Background = $syncHash.Window.FindResource('WzBgDarker')
        $listBorder.BorderBrush = $syncHash.Window.FindResource('WzBorder')
        $listBorder.BorderThickness = New-Object Windows.Thickness(1)
        $listBorder.CornerRadius = New-Object Windows.CornerRadius(10)
        $listBorder.Padding = New-Object Windows.Thickness(14, 12, 14, 12)
        $listBorder.Margin = New-Object Windows.Thickness(0, 0, 0, 16)
        $listBorder.MaxHeight = 280

        $scroller = New-Object Windows.Controls.ScrollViewer
        $scroller.VerticalScrollBarVisibility = 'Auto'
        $listStack = New-Object Windows.Controls.StackPanel
        foreach ($item in $Items) {
            $itemBlock = New-Object Windows.Controls.TextBlock
            $itemBlock.Text = "· $item"
            $itemBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
            $itemBlock.FontSize = 11.5
            $itemBlock.Foreground = $syncHash.Window.FindResource('WzText')
            $itemBlock.TextWrapping = 'Wrap'
            $itemBlock.Margin = New-Object Windows.Thickness(0, 2, 0, 2)
            [void]$listStack.Children.Add($itemBlock)
        }
        $scroller.Content = $listStack
        $listBorder.Child = $scroller
        [void]$stack.Children.Add($listBorder)
    }

    $optionBox = $null
    if ($OptionText) {
        $optionBox = New-Object Windows.Controls.CheckBox
        $optionBox.Content = $OptionText
        $optionBox.IsChecked = $OptionDefault
        $optionBox.Style = $syncHash.Window.FindResource('WzCheckBox')
        $optionBox.Margin = New-Object Windows.Thickness(0, 0, 0, 18)
        [void]$stack.Children.Add($optionBox)
    }

    $buttonRow = New-Object Windows.Controls.StackPanel
    $buttonRow.Orientation = 'Horizontal'
    $buttonRow.HorizontalAlignment = 'Right'

    $cancelButton = New-Object Windows.Controls.Button
    $cancelButton.Content = 'Abbrechen'
    $cancelButton.Style = $syncHash.Window.FindResource('WzBtnSecondary')
    $cancelButton.Margin = New-Object Windows.Thickness(0, 0, 10, 0)
    $cancelButton.Add_Click({ $window.DialogResult = $false; $window.Close() }.GetNewClosure())
    [void]$buttonRow.Children.Add($cancelButton)

    $okButton = New-Object Windows.Controls.Button
    $okButton.Content = $ConfirmText
    $okButton.Style = if ($Danger) {
        $syncHash.Window.FindResource('WzBtnDanger')
    } else {
        $syncHash.Window.FindResource('WzBtnPrimary')
    }
    $okButton.Add_Click({
        $result.Confirmed = $true
        if ($optionBox) { $result.OptionChecked = [bool]$optionBox.IsChecked }
        $window.DialogResult = $true
        $window.Close()
    }.GetNewClosure())
    [void]$buttonRow.Children.Add($okButton)

    [void]$stack.Children.Add($buttonRow)
    $shell.Child = $stack
    $window.Content = $shell
    $window.Add_KeyDown({
        if ($_.Key -eq 'Escape') { $window.DialogResult = $false; $window.Close() }
    }.GetNewClosure())

    [void]$window.ShowDialog()
    return $result
}

function Show-WzInfo {
    <#
    .SYNOPSIS
        Kurze Hinweismeldung im haZii-Look.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Items = @()
    )
    [void](Show-WzConfirm -Title $Title -Message $Message -Items $Items -ConfirmText 'Verstanden')
}

function New-WzCard {
    <#
    .SYNOPSIS
        Erzeugt eine Karte im haZii-Look mit optionaler Überschrift.
    #>
    param(
        [string]$Title,
        [string]$Eyebrow,
        [switch]$Static
    )

    $card = New-Object Windows.Controls.Border
    $card.Style = if ($Static) {
        $syncHash.Window.FindResource('WzCardStatic')
    } else {
        $syncHash.Window.FindResource('WzCard')
    }
    $card.Margin = New-Object Windows.Thickness(0, 0, 0, 14)

    $stack = New-Object Windows.Controls.StackPanel

    if ($Eyebrow) {
        $eyebrowBlock = New-Object Windows.Controls.TextBlock
        $eyebrowBlock.Text = $Eyebrow
        $eyebrowBlock.Style = $syncHash.Window.FindResource('WzEyebrow')
        [void]$stack.Children.Add($eyebrowBlock)
    }
    if ($Title) {
        $titleBlock = New-Object Windows.Controls.TextBlock
        $titleBlock.Text = $Title
        $titleBlock.Style = $syncHash.Window.FindResource('WzCardTitle')
        [void]$stack.Children.Add($titleBlock)
    }

    $card.Child = $stack
    return [pscustomobject]@{ Card = $card; Content = $stack }
}

function New-WzCheckRow {
    <#
    .SYNOPSIS
        Checkbox-Zeile mit Titel, Beschreibung und Abzeichen für Risiko und Zustand.
    .PARAMETER Item
        Objekt mit name, description und optional risk/level.
    #>
    param(
        [Parameter(Mandatory = $true)]$Item,
        [bool]$IsChecked = $false,
        [string]$StatusText,
        [string]$StatusKind = 'info'
    )

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 5, 0, 5)
    $col1 = New-Object Windows.Controls.ColumnDefinition
    $col1.Width = 'Auto'
    $col2 = New-Object Windows.Controls.ColumnDefinition
    $col2.Width = '*'
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)

    $checkBox = New-Object Windows.Controls.CheckBox
    $checkBox.IsChecked = $IsChecked
    $checkBox.Style = $syncHash.Window.FindResource('WzCheckBox')
    $checkBox.VerticalAlignment = 'Top'
    $checkBox.Margin = New-Object Windows.Thickness(0, 2, 10, 0)
    $checkBox.Tag = $Item
    [Windows.Controls.Grid]::SetColumn($checkBox, 0)
    [void]$grid.Children.Add($checkBox)

    $textStack = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($textStack, 1)

    $headerRow = New-Object Windows.Controls.StackPanel
    $headerRow.Orientation = 'Horizontal'

    $nameBlock = New-Object Windows.Controls.TextBlock
    $nameBlock.Text = $Item.name
    $nameBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $nameBlock.FontSize = 13.5
    $nameBlock.Foreground = $syncHash.Window.FindResource('WzTextBright')
    $nameBlock.VerticalAlignment = 'Center'
    [void]$headerRow.Children.Add($nameBlock)

    if ($Item.PSObject.Properties['risk'] -and $Item.risk -ne 'low') {
        [void]$headerRow.Children.Add((New-WzBadge -Text $Item.risk.ToUpper() -Kind $Item.risk))
    }
    if ($Item.PSObject.Properties['level'] -and $Item.level -eq 'hard') {
        [void]$headerRow.Children.Add((New-WzBadge -Text 'ENTFERNT' -Kind 'hard'))
    }
    if ($StatusText) {
        [void]$headerRow.Children.Add((New-WzBadge -Text $StatusText -Kind $StatusKind))
    }
    [void]$textStack.Children.Add($headerRow)

    if ($Item.PSObject.Properties['description'] -and $Item.description) {
        $descriptionBlock = New-Object Windows.Controls.TextBlock
        $descriptionBlock.Text = $Item.description
        $descriptionBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
        $descriptionBlock.FontSize = 11.5
        $descriptionBlock.Foreground = $syncHash.Window.FindResource('WzTextDim')
        $descriptionBlock.TextWrapping = 'Wrap'
        $descriptionBlock.Margin = New-Object Windows.Thickness(0, 2, 0, 0)
        [void]$textStack.Children.Add($descriptionBlock)
    }

    [void]$grid.Children.Add($textStack)
    return [pscustomobject]@{ Row = $grid; CheckBox = $checkBox }
}

function New-WzInfoRow {
    <#
    .SYNOPSIS
        Zeile mit Bezeichnung links und Wert rechts (Karteninhalt).
    .PARAMETER Kind
        normal | ok | warn | error — färbt den Wert ein.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Label,
        [Parameter(Position = 1)][string]$Value,
        [ValidateSet('normal', 'ok', 'warn', 'error')][string]$Kind = 'normal'
    )

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 3, 0, 3)
    $labelColumn = New-Object Windows.Controls.ColumnDefinition
    $labelColumn.Width = New-Object Windows.GridLength(112)
    $valueColumn = New-Object Windows.Controls.ColumnDefinition
    $valueColumn.Width = '*'
    [void]$grid.ColumnDefinitions.Add($labelColumn)
    [void]$grid.ColumnDefinitions.Add($valueColumn)

    $labelBlock = New-Object Windows.Controls.TextBlock
    $labelBlock.Text = $Label
    $labelBlock.Style = $syncHash.Window.FindResource('WzLabel')
    $labelBlock.VerticalAlignment = 'Top'
    $labelBlock.Margin = New-Object Windows.Thickness(0, 1, 8, 0)
    $labelBlock.TextWrapping = 'Wrap'
    [Windows.Controls.Grid]::SetColumn($labelBlock, 0)
    [void]$grid.Children.Add($labelBlock)

    $valueBlock = New-Object Windows.Controls.TextBlock
    $valueBlock.Text = if ($Value) { $Value } else { 'n/v' }
    $valueBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $valueBlock.FontSize = 12
    $valueBlock.TextWrapping = 'Wrap'
    $valueBlock.Foreground = switch ($Kind) {
        'ok'    { $syncHash.Window.FindResource('WzGreen') }
        'warn'  { $syncHash.Window.FindResource('WzAmber') }
        'error' { $syncHash.Window.FindResource('WzRed') }
        default { $syncHash.Window.FindResource('WzText') }
    }
    [Windows.Controls.Grid]::SetColumn($valueBlock, 1)
    [void]$grid.Children.Add($valueBlock)

    return $grid
}

function New-WzMeter {
    <#
    .SYNOPSIS
        Schmaler Auslastungsbalken mit Beschriftung.
        Färbt sich ab 75 % gelb und ab 90 % rot.
    #>
    param(
        [Parameter(Mandatory = $true)][int]$Percent,
        [string]$Caption
    )

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = New-Object Windows.Thickness(0, 2, 0, 8)

    $track = New-Object Windows.Controls.Border
    $track.Height = 5
    $track.CornerRadius = New-Object Windows.CornerRadius(999)
    $track.Background = $syncHash.Window.FindResource('WzBgDarker')
    $track.BorderBrush = $syncHash.Window.FindResource('WzBorder')
    $track.BorderThickness = New-Object Windows.Thickness(1)
    $track.HorizontalAlignment = 'Stretch'

    $fillHost = New-Object Windows.Controls.Grid
    $fillHost.HorizontalAlignment = 'Stretch'

    $fill = New-Object Windows.Controls.Border
    $fill.CornerRadius = New-Object Windows.CornerRadius(999)
    $fill.HorizontalAlignment = 'Left'
    $fill.Background = if ($Percent -ge 90) {
        $syncHash.Window.FindResource('WzRed')
    } elseif ($Percent -ge 75) {
        $syncHash.Window.FindResource('WzAmber')
    } else {
        $syncHash.Window.FindResource('WzCyan')
    }
    # Breite erst berechnen, wenn die Zeile ihre echte Breite kennt
    $fill.Tag = $Percent
    $fillHost.Add_SizeChanged({
        $ratio = [math]::Max(0, [math]::Min(100, [int]$fill.Tag)) / 100
        $fill.Width = [math]::Max(2, $fillHost.ActualWidth * $ratio)
    }.GetNewClosure())

    [void]$fillHost.Children.Add($fill)
    $track.Child = $fillHost
    [void]$stack.Children.Add($track)

    if ($Caption) {
        $captionBlock = New-Object Windows.Controls.TextBlock
        $captionBlock.Text = $Caption
        $captionBlock.FontFamily = $syncHash.Window.FindResource('WzFontMono')
        $captionBlock.FontSize = 10
        $captionBlock.Foreground = $syncHash.Window.FindResource('WzTextFaint')
        $captionBlock.Margin = New-Object Windows.Thickness(0, 3, 0, 0)
        [void]$stack.Children.Add($captionBlock)
    }

    return $stack
}

function New-WzNotice {
    <#
    .SYNOPSIS
        Hinweisleiste über dem Seiteninhalt (Neustart nötig, FAT32, Testmodus).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet('info', 'warn', 'error', 'ok')][string]$Kind = 'info'
    )

    $colors = switch ($Kind) {
        'warn'  { @{ Brush = 'WzAmber'; Background = '#14F59E0B'; Border = '#4DF59E0B'; Glyph = [char]0xE7BA } }
        'error' { @{ Brush = 'WzRed';   Background = '#14EF4444'; Border = '#4DEF4444'; Glyph = [char]0xEA39 } }
        'ok'    { @{ Brush = 'WzGreen'; Background = '#1422C55E'; Border = '#4D22C55E'; Glyph = [char]0xE73E } }
        default { @{ Brush = 'WzCyan';  Background = '#1400D4FF'; Border = '#3300D4FF'; Glyph = [char]0xE946 } }
    }

    $border = New-Object Windows.Controls.Border
    $border.Background = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($colors.Background))
    $border.BorderBrush = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($colors.Border))
    $border.BorderThickness = New-Object Windows.Thickness(1)
    $border.CornerRadius = New-Object Windows.CornerRadius(10)
    $border.Padding = New-Object Windows.Thickness(14, 9, 14, 9)
    $border.Margin = New-Object Windows.Thickness(0, 0, 0, 8)

    # Grid statt StackPanel: nur so bekommt der Text eine begrenzte Breite
    # und bricht um, statt rechts abgeschnitten zu werden.
    $row = New-Object Windows.Controls.Grid
    $iconColumn = New-Object Windows.Controls.ColumnDefinition
    $iconColumn.Width = 'Auto'
    $textColumn = New-Object Windows.Controls.ColumnDefinition
    $textColumn.Width = '*'
    [void]$row.ColumnDefinitions.Add($iconColumn)
    [void]$row.ColumnDefinitions.Add($textColumn)

    $icon = New-Object Windows.Controls.TextBlock
    $icon.Text = $colors.Glyph
    $icon.FontFamily = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
    $icon.FontSize = 13
    $icon.Foreground = $syncHash.Window.FindResource($colors.Brush)
    $icon.VerticalAlignment = 'Center'
    $icon.Margin = New-Object Windows.Thickness(0, 0, 10, 0)
    [Windows.Controls.Grid]::SetColumn($icon, 0)
    [void]$row.Children.Add($icon)

    $textBlock = New-Object Windows.Controls.TextBlock
    $textBlock.Text = $Text
    $textBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $textBlock.FontSize = 12.5
    $textBlock.Foreground = $syncHash.Window.FindResource($colors.Brush)
    $textBlock.TextWrapping = 'Wrap'
    $textBlock.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($textBlock, 1)
    [void]$row.Children.Add($textBlock)

    $border.Child = $row
    return $border
}

function New-WzBadge {
    <#
    .SYNOPSIS
        Kleines Abzeichen für Risiko-, Status- oder Zustandsangaben.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet('low', 'medium', 'high', 'hard', 'ok', 'info', 'warn')][string]$Kind = 'info'
    )

    $colorKey = switch ($Kind) {
        'high'   { 'WzRed' }
        'hard'   { 'WzRed' }
        'medium' { 'WzAmber' }
        'warn'   { 'WzAmber' }
        'ok'     { 'WzGreen' }
        default  { 'WzCyan' }
    }
    $brush = $syncHash.Window.FindResource($colorKey)

    $badge = New-Object Windows.Controls.Border
    $badge.BorderBrush = $brush
    $badge.BorderThickness = New-Object Windows.Thickness(1)
    $badge.CornerRadius = New-Object Windows.CornerRadius(999)
    $badge.Padding = New-Object Windows.Thickness(7, 1, 7, 1)
    $badge.Margin = New-Object Windows.Thickness(8, 0, 0, 0)
    $badge.VerticalAlignment = 'Center'
    $badge.Opacity = 0.85

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $label.FontSize = 9.5
    $label.Foreground = $brush
    $badge.Child = $label

    return $badge
}

function Format-WzBytes {
    <#
    .SYNOPSIS
        Byte-Zahl in lesbare Größe umwandeln (deutsches Zahlenformat).
    #>
    param([Parameter(Mandatory = $true)][double]$Bytes)
    if ($Bytes -le 0) { return '0 B' }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $index = [math]::Floor([math]::Log($Bytes, 1024))
    if ($index -ge $units.Count) { $index = $units.Count - 1 }
    $value = $Bytes / [math]::Pow(1024, $index)
    $decimals = if ($index -le 1) { 0 } else { 1 }
    $culture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    return ('{0} {1}' -f [math]::Round($value, $decimals).ToString($culture), $units[$index])
}
