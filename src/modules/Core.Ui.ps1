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
        throw (Get-WzText 'core.xamlNotFound' @{ pfad = $Path })
    }

    $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    [xml]$xaml = $raw

    $reader = New-Object Xml.XmlNodeReader($xaml)
    try {
        $root = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        throw (Get-WzText 'core.xamlLoadFailed' @{ datei = [IO.Path]::GetFileName($Path); grund = $_.Exception.Message })
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
        if (-not $element) { continue }
        $syncHash[$name] = $element

        # Behälter für Infozeilen bekommen einen gemeinsamen Größenbereich:
        # Damit richten sich die Beschriftungen EINER Karte nach der längsten
        # unter ihnen, statt jede Zeile für sich zu rechnen — und schmale
        # Karten bekommen trotzdem eine schmale Spalte. Siehe New-WzInfoRow.
        if ($name -like '*Rows') {
            [Windows.Controls.Grid]::SetIsSharedSizeScope($element, $true)
        }
    }
}

function Show-WzPage {
    <#
    .SYNOPSIS
        Wechselt zu einer Seite. Seiten werden beim ersten Aufruf geladen
        und danach wiederverwendet.
    #>
    param([Parameter(Mandatory = $true)][string]$Id)

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
                Write-WzLog (Get-WzText 'core.pageLoadFailed' @{ seite = $Id; grund = $_.Exception.Message }) -Level Error
                return
            }
        }
    }

    $syncHash.PageHost.Content = $syncHash.Pages[$Id]
    $syncHash.PageScroller.ScrollToTop()
    $syncHash.CurrentPage = $Id
    Update-WzNavState -ActiveId $Id

    # Läuft im Hintergrund noch etwas, wird der Seiteninhalt nicht automatisch
    # aktualisiert — der Anwender kann die Seite trotzdem ansehen.
    if ($syncHash.Busy) { return }

    $refresher = "Update-Wz$($Id)Page"
    if (Get-Command $refresher -ErrorAction SilentlyContinue) { & $refresher }
}

function Update-WzNavState {
    <#
    .SYNOPSIS
        Markiert den aktiven Eintrag in der Seitenleiste.
    #>
    param([string]$ActiveId)
    $active = $null
    foreach ($button in $syncHash.NavButtons) {
        $isActive = ($button.Tag -eq $ActiveId)
        $button.Style = if ($isActive) {
            $syncHash.Window.FindResource('WzNavButtonActive')
        } else {
            $syncHash.Window.FindResource('WzNavButton')
        }
        if ($isActive) { $active = $button }
    }

    # Auf einem niedrigen Bildschirm passen nicht alle vierzehn Einträge
    # untereinander. Wer über einen Schnellstart-Knopf auf eine der unteren
    # Seiten sprang, sah die Markierung gar nicht — die Leiste blieb oben
    # stehen, und es sah aus, als sei nichts passiert.
    #
    # Erst nach dem Layoutlauf: Direkt aufgerufen kennt der Bildlauf die
    # endgültigen Positionen noch nicht und bleibt auf halbem Weg stehen.
    if ($active -and $syncHash.Window) {
        [void]$syncHash.Window.Dispatcher.BeginInvoke(
            [Windows.Threading.DispatcherPriority]::Loaded,
            [action]{ try { $active.BringIntoView() } catch { } }.GetNewClosure())
    }
}

function Set-WzConsoleCollapsed {
    <#
    .SYNOPSIS
        Klappt die Protokollkonsole ein oder aus.
    .NOTES
        Eine Stelle für beide Aufrufer: den Klick auf die Kopfzeile und den
        Start auf einem niedrigen Bildschirm.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][bool]$Collapsed)

    if (-not $syncHash.LogConsole) { return }
    $syncHash.LogConsole.Visibility = if ($Collapsed) {
        [Windows.Visibility]::Collapsed
    } else {
        [Windows.Visibility]::Visible
    }
    if ($syncHash.LogChevron) {
        $syncHash.LogChevron.Text = if ($Collapsed) { [char]0xE70E } else { [char]0xE70D }
    }
    # Zwei ausgeschriebene Aufrufe statt eines mit Bedingung darin: Test-Language
    # gleicht benutzte gegen definierte Schlüssel ab und sucht nach
    # »Get-WzText '<schlüssel>'«. Steht der Schlüssel in einer Variablen, hält
    # der Abgleich ihn für tot — und ein Tippfehler fiele nicht mehr auf.
    if ($syncHash.LogHint) {
        $syncHash.LogHint.Text = if ($Collapsed) {
            Get-WzText 'shell.consoleCollapsed'
        } else {
            Get-WzText 'shell.consoleHint'
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
    $eyebrow.Text = Get-WzText 'core.placeholderEyebrow'
    $eyebrow.Style = $syncHash.Window.FindResource('WzEyebrow')
    [void]$stack.Children.Add($eyebrow)

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $Id
    $title.Style = $syncHash.Window.FindResource('WzPageTitle')
    [void]$stack.Children.Add($title)

    $lead = New-Object Windows.Controls.TextBlock
    $lead.Text = Get-WzText 'core.placeholderLead'
    $lead.Style = $syncHash.Window.FindResource('WzPageLead')
    [void]$stack.Children.Add($lead)

    return $stack
}

function Get-WzOverlayBounds {
    <#
    .SYNOPSIS
        Fläche, die ein Dialog abdecken soll — die des Hauptfensters.
    .DESCRIPTION
        Im Normalzustand reichen Left/Top/Width/Height des Fensters. Ist es
        maximiert, stimmen diese Werte nicht, dann wird der Arbeitsbereich des
        zugehörigen Bildschirms genommen und von Geräte- in WPF-Einheiten
        umgerechnet (sonst sitzt die Abdunklung auf hoch aufgelösten
        Bildschirmen falsch).
    .OUTPUTS
        PSCustomObject mit Left, Top, Width, Height — oder $null, wenn es kein
        nutzbares Hauptfenster gibt.
    #>
    $owner = $syncHash.Window
    if (-not $owner -or -not $owner.IsLoaded) { return $null }

    try {
        if ($owner.WindowState -eq 'Normal' -and $owner.ActualWidth -gt 0) {
            return [pscustomobject]@{
                Left   = $owner.Left
                Top    = $owner.Top
                Width  = $owner.ActualWidth
                Height = $owner.ActualHeight
            }
        }

        $helper = New-Object Windows.Interop.WindowInteropHelper($owner)
        $screen = [Windows.Forms.Screen]::FromHandle($helper.Handle)
        $area = $screen.WorkingArea

        $scaleX = 1.0
        $scaleY = 1.0
        $source = [Windows.PresentationSource]::FromVisual($owner)
        if ($source -and $source.CompositionTarget) {
            $transform = $source.CompositionTarget.TransformFromDevice
            $scaleX = $transform.M11
            $scaleY = $transform.M22
        }

        return [pscustomobject]@{
            Left   = $area.Left * $scaleX
            Top    = $area.Top * $scaleY
            Width  = $area.Width * $scaleX
            Height = $area.Height * $scaleY
        }
    } catch {
        return $null
    }
}

function Show-WzConfirm {
    <#
    .SYNOPSIS
        Bestätigungsdialog im haZii-Look.
    .DESCRIPTION
        Der Dialog legt sich als abgedunkelte Fläche über das Hauptfenster und
        lässt sich auf vier Wegen schließen: Schließkreuz, Escape, Klick auf die
        Abdunklung daneben und der Abbrechen-Knopf. Alle vier bedeuten Abbruch.
        Der Inhalt sitzt in einem Scrollbereich, die Knopfzeile darunter fest —
        so können die Knöpfe auch bei viel Text nie aus dem Bild rutschen.
    .PARAMETER Items
        Zeilen, die genau auflisten, was passieren wird.
    .PARAMETER OptionText
        Wenn gesetzt, erscheint eine zusätzliche Checkbox (z. B. Wiederherstellungspunkt).
    .PARAMETER Choices
        Wenn gesetzt, erscheint ein Auswahlfeld. Die getroffene Wahl steht
        danach in SelectedIndex.
    .PARAMETER HideCancel
        Nur einen Knopf zeigen — für reine Hinweise ohne Entscheidung.
    .OUTPUTS
        PSCustomObject mit Confirmed, OptionChecked und SelectedIndex
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Items = @(),
        [string]$OptionText,
        [bool]$OptionDefault = $true,
        [string[]]$Choices = @(),
        [string]$ChoiceLabel = 'Auswahl',
        [int]$ChoiceDefault = 0,
        [string]$ConfirmText,
        [switch]$Danger,
        [switch]$HideCancel
    )

    $result = [pscustomobject]@{
        Confirmed     = $false
        OptionChecked = $OptionDefault
        SelectedIndex = $ChoiceDefault
    }

    # Ohne Hauptfenster gibt es keine Ressourcen für das Design — dann lieber
    # nichts anzeigen als abstürzen (kommt vor, wenn beim Beenden noch eine
    # Hintergrundarbeit fertig wird).
    if (-not $syncHash.Window) {
        Write-WzLog (Get-WzText 'core.dialogSkipped' @{ titel = $Title }) -Level Warn
        return $result
    }

    $bounds = Get-WzOverlayBounds

    $window = New-Object Windows.Window
    $window.Title = $Title
    $window.ResizeMode = 'NoResize'
    $window.WindowStyle = 'None'
    $window.AllowsTransparency = $true
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar = $false

    # Das Design mitgeben. Ein Dialog ist ein eigenes Fenster und damit ein
    # eigener Ressourcenbaum — ohne diese Zeile finden die {DynamicResource}-
    # Verweise in den Stilen nichts und WPF nimmt seine Standardfarben
    # (weißer Knopf, grauer Text) mitten im dunklen Design.
    $window.Resources.MergedDictionaries.Add($syncHash.Window.Resources)

    if ($bounds) {
        $window.Owner = $syncHash.Window
        $window.WindowStartupLocation = 'Manual'
        $window.Left = $bounds.Left
        $window.Top = $bounds.Top
        $window.Width = $bounds.Width
        $window.Height = $bounds.Height
    } else {
        # Kein nutzbares Hauptfenster (z. B. beim Beenden): freistehend anzeigen
        $window.WindowStartupLocation = 'CenterScreen'
        $window.Width = 640
        $window.SizeToContent = 'Height'
        $window.MaxHeight = 640
    }

    # --- Abdunklung; ein Klick darauf bricht ab --------------------------
    $backdrop = New-Object Windows.Controls.Grid
    if ($bounds) {
        $backdrop.Background = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString('#B3000000'))
    } else {
        $backdrop.Background = [Windows.Media.Brushes]::Transparent
    }

    # --- Karte ------------------------------------------------------------
    $shell = New-Object Windows.Controls.Border
    $shell.Background = $syncHash.Window.FindResource('WzBgCard')
    $shell.BorderBrush = $syncHash.Window.FindResource('WzBorder')
    $shell.BorderThickness = New-Object Windows.Thickness(1)
    $shell.CornerRadius = New-Object Windows.CornerRadius(16)
    $shell.Padding = New-Object Windows.Thickness(28, 22, 28, 22)
    $shell.HorizontalAlignment = 'Center'
    $shell.VerticalAlignment = 'Center'
    $shell.MaxWidth = 640
    $shell.Margin = New-Object Windows.Thickness(24)
    if ($bounds) {
        $shell.MaxHeight = [math]::Max(320, $bounds.Height * 0.84)
        $shell.Effect = $syncHash.Window.FindResource('WzGlow')
    }

    $layout = New-Object Windows.Controls.Grid
    foreach ($height in @('Auto', '*', 'Auto')) {
        $row = New-Object Windows.Controls.RowDefinition
        $row.Height = $height
        [void]$layout.RowDefinitions.Add($row)
    }

    # --- Kopf: Eyebrow, Titel, Schließkreuz -------------------------------
    $header = New-Object Windows.Controls.Grid
    $header.Margin = New-Object Windows.Thickness(0, 0, 0, 14)
    $titleColumn = New-Object Windows.Controls.ColumnDefinition
    $titleColumn.Width = '*'
    $closeColumn = New-Object Windows.Controls.ColumnDefinition
    $closeColumn.Width = 'Auto'
    [void]$header.ColumnDefinitions.Add($titleColumn)
    [void]$header.ColumnDefinitions.Add($closeColumn)

    $headerText = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($headerText, 0)

    $eyebrow = New-Object Windows.Controls.TextBlock
    $eyebrow.Text = if ($Danger) {
        '// ACHTUNG'
    } elseif ($HideCancel) {
        '// HINWEIS'
    } else {
        Get-WzText 'core.confirmEyebrow'
    }
    $eyebrow.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $eyebrow.FontSize = 10.5
    $eyebrow.Foreground = if ($Danger) {
        $syncHash.Window.FindResource('WzRedText')
    } else {
        $syncHash.Window.FindResource('WzCyan')
    }
    $eyebrow.Margin = New-Object Windows.Thickness(0, 0, 0, 8)
    [void]$headerText.Children.Add($eyebrow)

    $titleBlock = New-Object Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontFamily = $syncHash.Window.FindResource('WzFontSans')
    $titleBlock.FontSize = 19
    $titleBlock.FontWeight = 'SemiBold'
    $titleBlock.Foreground = $syncHash.Window.FindResource('WzTextBright')
    $titleBlock.TextWrapping = 'Wrap'
    $titleBlock.Margin = New-Object Windows.Thickness(0, 0, 12, 0)
    [void]$headerText.Children.Add($titleBlock)
    [void]$header.Children.Add($headerText)

    $closeButton = New-Object Windows.Controls.Button
    $closeButton.Content = [char]0xE8BB
    $closeButton.FontFamily = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
    $closeButton.FontSize = 10
    $closeButton.Width = 34
    $closeButton.Height = 30
    $closeButton.Padding = New-Object Windows.Thickness(0)
    $closeButton.Style = $syncHash.Window.FindResource('WzBtnGhost')
    $closeButton.VerticalAlignment = 'Top'
    $closeButton.ToolTip = Get-WzText 'core.closeTip'
    [Windows.Controls.Grid]::SetColumn($closeButton, 1)
    [void]$header.Children.Add($closeButton)

    [Windows.Controls.Grid]::SetRow($header, 0)
    [void]$layout.Children.Add($header)

    # --- Inhalt: scrollt, damit nichts abgeschnitten wird -----------------
    $bodyScroller = New-Object Windows.Controls.ScrollViewer
    $bodyScroller.VerticalScrollBarVisibility = 'Auto'
    $bodyScroller.HorizontalScrollBarVisibility = 'Disabled'
    $bodyScroller.Padding = New-Object Windows.Thickness(0, 0, 4, 0)
    [Windows.Controls.Grid]::SetRow($bodyScroller, 1)

    $stack = New-Object Windows.Controls.StackPanel

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
        $listBorder.Child = $listStack
        [void]$stack.Children.Add($listBorder)
    }

    $choiceBox = $null
    if ($Choices.Count -gt 0) {
        $choiceCaption = New-Object Windows.Controls.TextBlock
        $choiceCaption.Text = $ChoiceLabel
        $choiceCaption.Style = $syncHash.Window.FindResource('WzLabel')
        $choiceCaption.Margin = New-Object Windows.Thickness(0, 0, 0, 5)
        [void]$stack.Children.Add($choiceCaption)

        $choiceBox = New-Object Windows.Controls.ComboBox
        $choiceBox.Style = $syncHash.Window.FindResource('WzComboBox')
        $choiceBox.Margin = New-Object Windows.Thickness(0, 0, 0, 14)
        foreach ($choice in $Choices) {
            $item = New-Object Windows.Controls.ComboBoxItem
            $item.Content = $choice
            [void]$choiceBox.Items.Add($item)
        }
        $choiceBox.SelectedIndex = [math]::Max(0, [math]::Min($ChoiceDefault, $Choices.Count - 1))
        [void]$stack.Children.Add($choiceBox)
    }

    $optionBox = $null
    if ($OptionText) {
        $optionBox = New-Object Windows.Controls.CheckBox
        $optionBox.Content = $OptionText
        $optionBox.IsChecked = $OptionDefault
        $optionBox.Style = $syncHash.Window.FindResource('WzCheckBox')
        $optionBox.Margin = New-Object Windows.Thickness(0, 0, 0, 4)
        [void]$stack.Children.Add($optionBox)
    }

    $bodyScroller.Content = $stack
    [void]$layout.Children.Add($bodyScroller)

    # --- Knopfzeile: fest unten, immer sichtbar ---------------------------
    $buttonRow = New-Object Windows.Controls.StackPanel
    $buttonRow.Orientation = 'Horizontal'
    $buttonRow.HorizontalAlignment = 'Right'
    $buttonRow.Margin = New-Object Windows.Thickness(0, 18, 0, 0)
    [Windows.Controls.Grid]::SetRow($buttonRow, 2)

    $closeDialog = {
        param($Confirmed)
        if ($Confirmed) {
            $result.Confirmed = $true
            if ($optionBox) { $result.OptionChecked = [bool]$optionBox.IsChecked }
            if ($choiceBox) { $result.SelectedIndex = [int]$choiceBox.SelectedIndex }
        }
        $window.DialogResult = [bool]$Confirmed
        $window.Close()
    }.GetNewClosure()

    $cancelButton = $null
    if (-not $HideCancel) {
        $cancelButton = New-Object Windows.Controls.Button
        $cancelButton.Content = 'Abbrechen'
        $cancelButton.Style = $syncHash.Window.FindResource('WzBtnSecondary')
        $cancelButton.Margin = New-Object Windows.Thickness(0, 0, 10, 0)
        $cancelButton.IsCancel = $true
        $cancelButton.Add_Click({ & $closeDialog $false }.GetNewClosure())
        [void]$buttonRow.Children.Add($cancelButton)
    }

    $okButton = New-Object Windows.Controls.Button
    $okButton.Content = if ($ConfirmText) { $ConfirmText } else { Get-WzText 'core.btnExecute' }
    $okButton.IsDefault = $true
    $okButton.Style = if ($Danger) {
        $syncHash.Window.FindResource('WzBtnDanger')
    } else {
        $syncHash.Window.FindResource('WzBtnPrimary')
    }
    $okButton.Add_Click({ & $closeDialog $true }.GetNewClosure())
    [void]$buttonRow.Children.Add($okButton)

    [void]$layout.Children.Add($buttonRow)

    $shell.Child = $layout
    [void]$backdrop.Children.Add($shell)
    $window.Content = $backdrop

    # --- Schließwege ------------------------------------------------------
    $closeButton.Add_Click({ & $closeDialog $false }.GetNewClosure())

    # Klick neben die Karte bricht ab. Klicks auf die Karte selbst laufen
    # ebenfalls hier durch (sie steckt im Grid), deshalb die Herkunftsprüfung.
    $backdrop.Add_MouseLeftButtonDown({
        param($eventSender, $eventArgs)
        if ($eventArgs.OriginalSource -eq $backdrop) { & $closeDialog $false }
    }.GetNewClosure())

    # IsCancel deckt Escape bereits ab; bei reinen Hinweisen ohne
    # Abbrechen-Knopf braucht es zusätzlich diesen Handler.
    $window.Add_PreviewKeyDown({
        param($eventSender, $eventArgs)
        if ($eventArgs.Key -eq 'Escape') {
            $eventArgs.Handled = $true
            & $closeDialog $false
        }
    }.GetNewClosure())

    # Bei gefährlichen Aktionen liegt der Fokus auf »Abbrechen« — sonst löst
    # ein unbedachter Druck auf die Eingabetaste die Löschung aus.
    $window.Add_Loaded({
        if ($Danger -and $cancelButton) {
            [void]$cancelButton.Focus()
        } else {
            [void]$okButton.Focus()
        }
    }.GetNewClosure())

    $syncHash.ActiveDialog = $window
    try {
        [void]$window.ShowDialog()
    } finally {
        $syncHash.ActiveDialog = $null
    }
    return $result
}

function Show-WzInfo {
    <#
    .SYNOPSIS
        Kurze Hinweismeldung im haZii-Look — mit nur einem Knopf, weil es
        nichts abzubrechen gibt.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Items = @()
    )
    [void](Show-WzConfirm -Title $Title -Message $Message -Items $Items `
        -ConfirmText (Get-WzText 'dialog.understood') -HideCancel)
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
    # Wie bei den XAML-Karten: Die Beschriftungen einer Karte richten sich
    # gemeinsam aus, nicht seitenweit (siehe New-WzInfoRow).
    [Windows.Controls.Grid]::SetIsSharedSizeScope($stack, $true)

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
    .PARAMETER LabelWidth
        HÖCHSTbreite der linken Spalte. Die Vorgabe reicht für kurze
        Bezeichnungen; Listen mit Geräte- oder Kontonamen brauchen deutlich
        mehr, sonst bricht jeder zweite Name um.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Label,
        [Parameter(Position = 1)][string]$Value,
        [ValidateSet('normal', 'ok', 'warn', 'error')][string]$Kind = 'normal',
        [int]$LabelWidth = 112
    )

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 3, 0, 3)
    $labelColumn = New-Object Windows.Controls.ColumnDefinition
    # Auto statt fester Breite: »Version« braucht keine 112 px. Auf einem
    # 1366er-Laptop ist eine Dashboard-Karte gut 210 px breit — blieben davon
    # feste 112 px für die Bezeichnung, hatte der Wert unter 100 px, und WPF
    # trennte mitten im Wort: »Systemlaufwe rk nicht verschlüssel t«.
    # Die Obergrenze verhindert, dass eine lange Bezeichnung die Spalte sprengt.
    $labelColumn.Width = 'Auto'
    $labelColumn.MaxWidth = $LabelWidth
    # Jede Zeile ist ein eigenes Grid. Ohne gemeinsamen Größenbereich rechnete
    # jede für sich, und die Werte einer Karte begännen an verschiedenen
    # Stellen. Der Bereich gilt je Behälter (siehe Register-WzNames), also
    # innerhalb einer Karte — nicht über die ganze Seite.
    $labelColumn.SharedSizeGroup = 'WzInfoLabel'
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
        'error' { $syncHash.Window.FindResource('WzRedText') }
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
    $track.BorderBrush = $syncHash.Window.FindResource('WzBorderControl')
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
        $captionBlock.FontSize = 10.5
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

    # Rot bekommt eine eigene, hellere Schriftfarbe — #EF4444 erreicht auf der
    # rot getönten Fläche keine 4,5:1.
    $colors = switch ($Kind) {
        'warn'  { @{ Brush = 'WzAmber';   Background = '#14F59E0B'; Border = '#4DF59E0B'; Glyph = [char]0xE7BA } }
        'error' { @{ Brush = 'WzRedText'; Background = '#14EF4444'; Border = '#4DEF4444'; Glyph = [char]0xEA39 } }
        'ok'    { @{ Brush = 'WzGreen';   Background = '#1422C55E'; Border = '#4D22C55E'; Glyph = [char]0xE73E } }
        default { @{ Brush = 'WzCyan';    Background = '#1400D4FF'; Border = '#3300D4FF'; Glyph = [char]0xE946 } }
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

    # Schrift und Rahmen getrennt: Rot ist als Rahmen kräftig genug, als
    # Schrift auf dunklem Grund aber zu dunkel.
    $textKey, $borderKey = switch ($Kind) {
        'high'   { 'WzRedText', 'WzRed' }
        'hard'   { 'WzRedText', 'WzRed' }
        'medium' { 'WzAmber', 'WzAmber' }
        'warn'   { 'WzAmber', 'WzAmber' }
        'ok'     { 'WzGreen', 'WzGreen' }
        default  { 'WzCyan', 'WzCyan' }
    }

    $badge = New-Object Windows.Controls.Border
    $badge.BorderBrush = $syncHash.Window.FindResource($borderKey)
    $badge.BorderThickness = New-Object Windows.Thickness(1)
    $badge.CornerRadius = New-Object Windows.CornerRadius(999)
    $badge.Padding = New-Object Windows.Thickness(7, 1, 7, 1)
    $badge.Margin = New-Object Windows.Thickness(8, 0, 0, 0)
    $badge.VerticalAlignment = 'Center'

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.FontFamily = $syncHash.Window.FindResource('WzFontMono')
    $label.FontSize = 10.5
    $label.Foreground = $syncHash.Window.FindResource($textKey)
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

function Format-WzNumber {
    <#
    .SYNOPSIS
        Dezimalzahl mit Einheit im deutschen Zahlenformat, z. B. »74,2 s«.
    .NOTES
        Ohne feste Kultur schreibt PowerShell »74.2« mit Punkt — direkt neben
        einem »13,1 GB« aus Format-WzBytes sieht das nach zwei Programmen aus.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)][double]$Value,
        [Parameter(Position = 1)][string]$Unit,
        [int]$Decimals = 1
    )
    $culture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $text = [math]::Round($Value, $Decimals).ToString($culture)
    if ($Unit) { return "$text $Unit" }
    return $text
}

function Format-WzSeconds {
    <#
    .SYNOPSIS
        Sekundenangabe im deutschen Zahlenformat, z. B. »74,2 s«.
    #>
    param(
        [Parameter(Mandatory = $true)][double]$Seconds,
        [int]$Decimals = 1,
        [string]$Unit = 's'
    )
    return Format-WzNumber -Value $Seconds -Unit $Unit -Decimals $Decimals
}

function Format-WzAgo {
    <#
    .SYNOPSIS
        Zeitpunkt als Abstand zu heute, z. B. »vor 3 Jahren (14.02.2022)«.
    .NOTES
        Ein nacktes Datum muss der Leser erst im Kopf verrechnen. Beim
        Datenumzug ist genau diese Rechnung die Entscheidung: Ein Profil, das
        seit drei Jahren niemand angefasst hat, muss nicht mitkopiert werden.
    #>
    param($Time)

    if (-not $Time) { return '' }
    try { $stamp = [datetime]$Time } catch { return '' }

    # Über Kalendertage, nicht über verstrichene Stunden: 23:50 Uhr gestern liegt
    # keine Stunde zurück, »heute« wäre trotzdem falsch.
    $now = Get-Date
    $days = [int]($now.Date - $stamp.Date).TotalDays
    $span = if ($days -lt 0) { Get-WzText 'core.agoFuture' }
        elseif ($days -eq 0) { Get-WzText 'core.agoToday' }
        elseif ($days -eq 1) { Get-WzText 'core.agoYesterday' }
        elseif ($days -lt 30) { Get-WzText 'core.agoDays' @{ tage = $days } }
        elseif ($days -lt 60) { Get-WzText 'core.agoMonth' }
        elseif ($days -lt 365) { Get-WzText 'core.agoMonths' @{ monate = [int][math]::Floor($days / 30) } }
        elseif ($days -lt 730) { Get-WzText 'core.agoOverYear' }
        else { Get-WzText 'core.agoOverYears' @{ jahre = [int][math]::Floor($days / 365) } }

    return "$span ($($stamp.ToString('dd.MM.yyyy')))"
}
