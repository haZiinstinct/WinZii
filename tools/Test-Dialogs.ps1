# Dev-Werkzeug: prüft die Bestätigungsfenster.
#
# Für jede Dialogvariante wird geprüft, dass sie sich auf dem jeweiligen Weg
# schließen lässt — Escape, Klick auf die Abdunklung daneben, Schließkreuz.
# Von jeder Variante entsteht ein Abbild zur Sichtprüfung.
#
# Aufruf:  powershell -NoProfile -STA -File tools\Test-Dialogs.ps1
[CmdletBinding()]
param([switch]$KeepImages)

$root = Split-Path -Parent $PSScriptRoot
$shotDir = Join-Path $env:TEMP 'winzii-dialoge'
if (-not (Test-Path $shotDir)) { [void](New-Item -ItemType Directory -Path $shotDir -Force) }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# --- Umgebung wie in main.ps1 aufbauen -------------------------------------
$global:WzRootPath = $root
$global:WzSessionStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.Pages = @{}
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.Busy = $false
$syncHash.DryRun = $true
. (Join-Path $root 'src\version.ps1')
$syncHash.Version = $script:WzVersion

foreach ($module in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Ui') {
    . (Join-Path $root "src\modules\$module.ps1")
}

$xamlDir = Join-Path $root 'src\xaml'
$themeReader = New-Object Xml.XmlNodeReader ([xml][IO.File]::ReadAllText((Join-Path $xamlDir 'Theme.xaml'), [Text.Encoding]::UTF8))
$theme = [Windows.Markup.XamlReader]::Load($themeReader)

[xml]$mainXml = [IO.File]::ReadAllText((Join-Path $xamlDir 'MainWindow.xaml'), [Text.Encoding]::UTF8)
$mainReader = New-Object Xml.XmlNodeReader($mainXml)
$window = [Windows.Markup.XamlReader]::Load($mainReader)
$window.Resources.MergedDictionaries.Add($theme)
$syncHash.Window = $window
Register-WzNames -Root $window -Xml $mainXml

# Mitgelieferte Schriften wie im Programm
$fontDir = Join-Path $root 'assets\fonts'
if (Test-Path $fontDir) {
    $uriBase = 'file:///' + ($fontDir -replace '\\', '/') + '/'
    try {
        $mono = (New-Object Windows.Media.FontFamily(($uriBase + '#JetBrains Mono'))).PSObject.BaseObject
        $sans = (New-Object Windows.Media.FontFamily(($uriBase + '#Inter'))).PSObject.BaseObject
        if ($mono.GetTypefaces().Count -gt 0) { $window.Resources['WzFontMono'] = $mono }
        if ($sans.GetTypefaces().Count -gt 0) { $window.Resources['WzFontSans'] = $sans }
    } catch { }
}

function global:Find-WzCloseButton {
    <#
    .SYNOPSIS
        Sucht das Schließkreuz im Dialogbaum (Knopf mit dem Schließen-Zeichen).
    .NOTES
        Muss global sein: GetNewClosure() bindet den Zeitgeber-Block an ein
        eigenes dynamisches Modul, aus dem heraus Funktionen des Skripts nicht
        sichtbar sind. Vorher flog beim Fall »CloseBtn« eine Ausnahme, der
        Dialog schloss sich als Nebenwirkung — und der Test meldete trotzdem
        bestanden, ohne je das Kreuz gedrückt zu haben.
    #>
    param($Element)
    if ($Element -is [Windows.Controls.Button] -and "$($Element.Content)" -eq [string][char]0xE8BB) {
        return $Element
    }
    $count = [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
    for ($i = 0; $i -lt $count; $i++) {
        $found = Find-WzCloseButton ([Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
        if ($found) { return $found }
    }
    return $null
}

# --- Prüffälle -------------------------------------------------------------
$longText = 1..40 | ForEach-Object { "Eintrag $_ mit einer absichtlich langen Beschreibung, damit der Inhalt überläuft" }

$cases = @(
    @{ Name = 'kurz';        Close = 'Escape';   Args = @{ Title = 'Kurze Rückfrage'; Message = 'Nur eine Zeile Text und zwei Knöpfe.' } }
    @{ Name = 'liste';       Close = 'Backdrop'; Args = @{ Title = 'Mit Aufzählung'; Message = 'Fünf Einträge werden angewendet.'; Items = @('Erster Eintrag', 'Zweiter Eintrag', 'Dritter Eintrag', 'Vierter Eintrag', 'Fünfter Eintrag') } }
    @{ Name = 'option';      Close = 'CloseBtn'; Args = @{ Title = 'Mit Wahlmöglichkeit'; Message = 'Hier gibt es zusätzlich ein Kästchen zum Ankreuzen.'; Items = @('Telemetrie abschalten', 'Werbe-ID abschalten'); OptionText = 'Vorher einen Systemwiederherstellungspunkt anlegen (empfohlen)' } }
    @{ Name = 'gefahr';      Close = 'Escape';   Args = @{ Title = 'Gefährliche Aktion'; Message = 'Diese Aktion lässt sich nicht rückgängig machen.'; Items = @('Windows.old entfernen'); Danger = $true } }
    @{ Name = 'hinweis';     Close = 'Backdrop'; Args = @{ Title = 'Reiner Hinweis'; Message = 'Nur ein Knopf, weil es nichts abzubrechen gibt.'; HideCancel = $true; ConfirmText = 'Verstanden' } }
    @{ Name = 'sehr-lang';   Close = 'Escape';   Args = @{ Title = 'Sehr viele Einträge in einem Titel, der ebenfalls über mehrere Zeilen laufen kann'; Message = ('Ein absichtlich sehr langer Nachrichtentext. ' * 12); Items = $longText; OptionText = 'Auch hier gibt es noch ein Kästchen'; Danger = $true } }
)

# Script-Gültigkeitsbereich, weil die Auswertung im Ereignishandler läuft
$script:results = New-Object Collections.ArrayList
$script:failed = 0
$script:noCloseButton = $false

Write-Host ''
Write-Host '  WinZii Dialogtest' -ForegroundColor Cyan
Write-Host ''

$window.Add_ContentRendered({
    foreach ($case in $cases) {
        $shotPath = Join-Path $shotDir "$($case.Name).png"
        $closed = $false
        $mode = $case.Close

        # Der Dialog blockiert, sobald er offen ist — deshalb wird das Schließen
        # von einem Zeitgeber aus erledigt, der währenddessen weiterläuft.
        $timer = New-Object Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(700)
        $timer.Add_Tick({
            $timer.Stop()
            $dialog = $syncHash.ActiveDialog
            if (-not $dialog) { return }

            try {
                $dialog.UpdateLayout()
                $target = New-Object Windows.Media.Imaging.RenderTargetBitmap(
                    [int]$dialog.ActualWidth, [int]$dialog.ActualHeight, 96, 96,
                    [Windows.Media.PixelFormats]::Pbgra32)
                $target.Render($dialog)
                $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($target))
                $stream = [IO.File]::Create($shotPath)
                $encoder.Save($stream)
                $stream.Close()
            } catch { }

            switch ($mode) {
                'Escape' {
                    $keyArgs = New-Object Windows.Input.KeyEventArgs(
                        [Windows.Input.Keyboard]::PrimaryDevice,
                        [Windows.PresentationSource]::FromVisual($dialog),
                        0, [Windows.Input.Key]::Escape)
                    $keyArgs.RoutedEvent = [Windows.Input.Keyboard]::PreviewKeyDownEvent
                    $dialog.RaiseEvent($keyArgs)
                }
                'Backdrop' {
                    # Klick auf die Abdunklung: das Wurzel-Grid selbst als Quelle
                    $backdrop = $dialog.Content
                    $mouseArgs = New-Object Windows.Input.MouseButtonEventArgs(
                        [Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Left)
                    $mouseArgs.RoutedEvent = [Windows.UIElement]::MouseLeftButtonDownEvent
                    $mouseArgs.Source = $backdrop
                    $backdrop.RaiseEvent($mouseArgs)
                }
                'CloseBtn' {
                    $button = Find-WzCloseButton -Element $dialog.Content
                    if ($button) {
                        $button.RaiseEvent((New-Object Windows.RoutedEventArgs(
                            [Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                    } else {
                        # Ohne Kreuz bliebe der Dialog stehen und der Lauf hinge.
                        # Also über Escape schließen und den Fall als Fehlschlag merken.
                        $script:noCloseButton = $true
                        $keyArgs = New-Object Windows.Input.KeyEventArgs(
                            [Windows.Input.Keyboard]::PrimaryDevice,
                            [Windows.PresentationSource]::FromVisual($dialog),
                            0, [Windows.Input.Key]::Escape)
                        $keyArgs.RoutedEvent = [Windows.Input.Keyboard]::PreviewKeyDownEvent
                        $dialog.RaiseEvent($keyArgs)
                    }
                }
            }
        }.GetNewClosure())
        $timer.Start()

        $splat = $case.Args
        $answer = Show-WzConfirm @splat
        $closed = $true

        $shotOk = Test-Path $shotPath
        $stillOpen = ($null -ne $syncHash.ActiveDialog)
        $ok = ($closed -and -not $stillOpen -and -not $answer.Confirmed -and $shotOk)
        if ($mode -eq 'CloseBtn' -and $script:noCloseButton) { $ok = $false }

        [void]$script:results.Add([pscustomobject]@{
            Name = $case.Name
            Weg  = $mode
            Bild = $shotOk
            Zu   = (-not $stillOpen)
            Abbr = (-not $answer.Confirmed)
            Ok   = $ok
        })
        if (-not $ok) { $script:failed++ }
    }

    $window.Close()
})

[void]$window.ShowDialog()

# --- Ergebnis --------------------------------------------------------------
foreach ($entry in $script:results) {
    $symbol = if ($entry.Ok) { '[ok]  ' } else { '[FEHL]' }
    $color = if ($entry.Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-11} schließen per {2,-9} Abbild={3,-5} geschlossen={4,-5} abgebrochen={5}" -f `
        $symbol, $entry.Name, $entry.Weg, $entry.Bild, $entry.Zu, $entry.Abbr) -ForegroundColor $color
}

Write-Host ''
if ($script:failed -eq 0) {
    Write-Host "  Ergebnis: alle $($script:results.Count) Dialogvarianten lassen sich schließen." -ForegroundColor Green
    Write-Host "  Abbilder: $shotDir" -ForegroundColor DarkGray
    exit 0
}
Write-Host "  Ergebnis: $script:failed von $($script:results.Count) Varianten fehlerhaft." -ForegroundColor Red
exit 1
