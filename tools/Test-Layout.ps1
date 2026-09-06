# Dev-Werkzeug: prüft die Oberfläche auf einem niedrigen Bildschirm.
#
# Der Grund steht in docs\ABNAHME.md Punkt 8: Auf dem Entwicklungsrechner ist die
# Arbeitsfläche groß, das Fenster startet groß — die Anpassungen für niedrige
# Bildschirme laufen dort nie an und lassen sich deshalb auch nicht prüfen.
# WZ_SELFTEST_SIZE erzwingt die Fenstergröße, und dieses Werkzeug fährt damit
# jede Seite an.
#
# Geprüft wird bei 1000x560 — dem Mindestmaß und damit dem schlimmsten Fall:
#   * Startet die Konsole eingeklappt, und zieht ein Klick sie wieder auf?
#   * Holt die Seitenleiste den aktiven Eintrag ins Bild?
#   * Liegt ein Bedienelement außerhalb des Fensters?
#   * Wird ein Wort mitten durchtrennt? Gemessen mit FormattedText, nicht geraten.
# Dazu ein Lauf in Vorgabegröße: Sitzt das Fenster mittig in der Arbeitsfläche?
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Test-Layout.ps1
[CmdletBinding()]
param(
    [string]$Size = '1000x560',
    [string[]]$Only,
    [switch]$KeepShots
)

$root = Split-Path -Parent $PSScriptRoot

# Seitenliste aus der Navigation, wie in Test-Pages — eine fest eingetragene
# Aufzählung veraltet beim ersten Hinzufügen einer Seite still.
$navOrder = @()
foreach ($line in [IO.File]::ReadAllLines((Join-Path $root 'src\xaml\MainWindow.xaml'))) {
    if ($line -match 'Tag="([A-Za-z]+)"\s+Style="\{DynamicResource WzNavButton\}"') { $navOrder += $Matches[1] }
}
$onDisk = @(Get-ChildItem -LiteralPath (Join-Path $root 'src\xaml\pages') -Filter '*.xaml' -File |
    ForEach-Object { $_.BaseName })
$pages = @($navOrder | Where-Object { $onDisk -contains $_ }) +
         @($onDisk | Where-Object { $navOrder -notcontains $_ })
if ($Only) { $pages = @($pages | Where-Object { $Only -contains $_ }) }

if ($pages.Count -lt 10 -and -not $Only) {
    Write-Host ''
    Write-Host "  [FEHL] Nur $($pages.Count) Seite(n) gefunden — die Erkennung greift nicht mehr." -ForegroundColor Red
    exit 1
}

$arbeitsordner = Join-Path $env:TEMP "winzii-layout-$PID"
[void](New-Item -ItemType Directory -Path $arbeitsordner -Force)

# --- Die Sonde, die in der laufenden Oberfläche ausgeführt wird -------------
$sondeDatei = Join-Path $arbeitsordner 'sonde.ps1'
$sonde = @'
$w = $syncHash.Window
# Der Bildlauf zum aktiven Eintrag ist auf Loaded-Priorität eingereiht. Ohne
# das Leeren der Warteschlange misst man davor und hält das für einen Fehler.
$w.UpdateLayout()
[void]$w.Dispatcher.Invoke([action] { }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)

$befunde = New-Object Collections.ArrayList
$werte = [ordered]@{}

$werte['Fenster'] = '{0:N0}x{1:N0}' -f $w.ActualWidth, $w.ActualHeight
$werte['Seite'] = $syncHash.CurrentPage

# --- Konsole ---------------------------------------------------------------
$eingeklappt = ($syncHash.LogConsole.Visibility -ne [Windows.Visibility]::Visible)
$werte['Konsole'] = if ($eingeklappt) { 'eingeklappt' } else { 'ausgeklappt' }
if ($w.ActualHeight -lt 700 -and -not $eingeklappt) {
    [void]$befunde.Add('Konsole startet ausgeklappt und frisst die halbe Höhe')
}
$ereignis = New-Object Windows.Input.MouseButtonEventArgs(
    [Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Left)
$ereignis.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
$syncHash.LogHeader.RaiseEvent($ereignis)
$w.UpdateLayout()
if (($syncHash.LogConsole.Visibility -ne [Windows.Visibility]::Visible) -eq $eingeklappt) {
    [void]$befunde.Add('Klick auf die Klappzeile ändert nichts')
}
Set-WzConsoleCollapsed -Collapsed $eingeklappt
$w.UpdateLayout()

# --- Seitenleiste ----------------------------------------------------------
$sicht = $syncHash.NavPanel
while ($sicht -and -not ($sicht -is [Windows.Controls.ScrollViewer])) {
    $sicht = [Windows.Media.VisualTreeHelper]::GetParent($sicht)
}
$aktiv = $null
foreach ($kind in $syncHash.NavPanel.Children) {
    if ($kind -is [Windows.Controls.Button] -and "$($kind.Tag)" -eq "$($syncHash.CurrentPage)") { $aktiv = $kind }
}
if ($sicht -and $aktiv) {
    $p = $aktiv.TransformToAncestor($sicht).Transform((New-Object Windows.Point 0, 0))
    $werte['LeisteOffset'] = '{0:N0}' -f $sicht.VerticalOffset
    if ($p.Y -lt -1 -or ($p.Y + $aktiv.ActualHeight) -gt ($sicht.ViewportHeight + 1)) {
        [void]$befunde.Add(('aktiver Eintrag »{0}« liegt außerhalb der Seitenleiste (y={1:N0})' -f $aktiv.Tag, $p.Y))
    }
}

# --- Liegt etwas außerhalb des Fensters? -----------------------------------
foreach ($name in 'BtnClose', 'BtnMinimize', 'BtnMaximize', 'StatusPath', 'LogHeader') {
    $e = $syncHash[$name]
    if (-not $e -or $e.ActualWidth -le 0) { continue }
    try {
        $p = $e.TransformToAncestor($w).Transform((New-Object Windows.Point 0, 0))
        if ($p.X -lt -1 -or $p.Y -lt -1 -or
            ($p.X + $e.ActualWidth) -gt ($w.ActualWidth + 1) -or
            ($p.Y + $e.ActualHeight) -gt ($w.ActualHeight + 1)) {
            [void]$befunde.Add(('{0} liegt außerhalb des Fensters' -f $name))
        }
    } catch { }
}

# --- Wird ein Wort mitten durchtrennt? -------------------------------------
# Zwei Fallen, in die eine naive Prüfung tappt:
#
# 1. FormattedText misst 2 bis 4 px breiter als das Layout eines TextBlocks —
#    andere Textformatierung. Genau in dieser Größenordnung liegt der echte
#    Fehler, den wir suchen; die Messung muss also aus derselben Quelle kommen.
#    Deshalb wird ein loser TextBlock mit denselben Schrifteigenschaften
#    vermessen: Das IST WPFs Layout.
# 2. WPF darf nicht nur an Leerzeichen umbrechen, sondern auch nach einem
#    Bindestrich und einem weichen Trennzeichen. »Micro-Star« zählt also als
#    zwei Stücke — sonst meldet die Prüfung Umbrüche, die völlig in Ordnung sind.
$getrennt = New-Object Collections.ArrayList

function New-Nachbau {
    # Ein loser TextBlock mit denselben Schrifteigenschaften. Selbst messen
    # statt rechnen: FormattedText liegt je nach Textformatierung zwei bis vier
    # Pixel daneben, und genau in dieser Größenordnung liegt der gesuchte
    # Fehler. Ein TextBlock misst mit demselben Verfahren wie das Original.
    param($vorbild, [string]$text, $umbruch)
    $p = New-Object Windows.Controls.TextBlock
    $p.FontFamily = $vorbild.FontFamily
    $p.FontSize = $vorbild.FontSize
    $p.FontStyle = $vorbild.FontStyle
    $p.FontWeight = $vorbild.FontWeight
    $p.FontStretch = $vorbild.FontStretch
    [Windows.Media.TextOptions]::SetTextFormattingMode($p, [Windows.Media.TextOptions]::GetTextFormattingMode($vorbild))
    $p.TextWrapping = $umbruch
    $p.Text = $text
    return $p
}

function Test-Umbruch {
    param($e, [int]$tiefe = 0)
    if ($tiefe -gt 40 -or -not $e) { return }
    if ($e -is [Windows.Controls.TextBlock] -and
        $e.TextWrapping -ne [Windows.TextWrapping]::NoWrap -and
        $e.ActualWidth -gt 0 -and $e.Text -and $e.Text.Trim()) {

        # Zerlegt wird an den Stellen, an denen WPF umbrechen DARF: Leerraum,
        # nach einem Bindestrich, nach einem weichen Trennzeichen. Was dazwischen
        # steht, muss am Stück in die Spalte passen — sonst schneidet WPF
        # mittendrin: »Systemlaufwe rk«.
        #
        # Gemessen wird jedes Stück einzeln und ohne Breitenvorgabe. Mit Vorgabe
        # kappt WPF die gewünschte Breite auf eben diese Vorgabe, und ein zu
        # breites Stück fiele nie auf.
        foreach ($stueck in @([regex]::Split($e.Text.Trim(), '(?<=[-­])|\s+') | Where-Object { $_ })) {
            if ($stueck.Length -lt 4) { continue }
            $nachbau = New-Nachbau $e $stueck ([Windows.TextWrapping]::NoWrap)
            $nachbau.Measure((New-Object Windows.Size ([double]::PositiveInfinity), ([double]::PositiveInfinity)))
            if ($nachbau.DesiredSize.Width -gt $e.ActualWidth + 0.5) {
                [void]$getrennt.Add(('»{0}« braucht {1:N0} px, Spalte hat {2:N0}' -f `
                    $stueck, $nachbau.DesiredSize.Width, $e.ActualWidth))
            }
        }
    }
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($e); $i++) {
        Test-Umbruch ([Windows.Media.VisualTreeHelper]::GetChild($e, $i)) ($tiefe + 1)
    }
}
try { Test-Umbruch $w } catch { [void]$befunde.Add("Textprüfung fehlgeschlagen: $($_.Exception.Message)") }
foreach ($g in ($getrennt | Select-Object -Unique)) { [void]$befunde.Add("mitten im Wort getrennt: $g") }

# --- Fensterlage (nur ohne erzwungene Größe sinnvoll) ----------------------
if (-not $env:WZ_SELFTEST_SIZE) {
    $a = [Windows.SystemParameters]::WorkArea
    $oben = $w.Top - $a.Top
    $unten = ($a.Top + $a.Height) - ($w.Top + $w.ActualHeight)
    $links = $w.Left - $a.Left
    $rechts = ($a.Left + $a.Width) - ($w.Left + $w.ActualWidth)
    $werte['Raender'] = 'oben {0:N0}, unten {1:N0}, links {2:N0}, rechts {3:N0}' -f $oben, $unten, $links, $rechts
    # »Lage:« davor, damit der Lauf in Vorgabegröße nur diese Befunde bewertet —
    # die Textumbrüche dort gehören zur Seitenprüfung, nicht zur Fensterlage.
    if ($unten -lt -1) { [void]$befunde.Add(('Lage: Fenster ragt {0:N0} px hinter die Taskleiste' -f (-$unten))) }
    if ($oben -lt -1) { [void]$befunde.Add('Lage: Fenster ragt über die Arbeitsfläche hinaus') }
    # Mittig heißt: oben und unten gleich viel, auf 2 px genau.
    if ([math]::Abs($oben - $unten) -gt 2) {
        [void]$befunde.Add(('Lage: senkrecht nicht mittig, {0:N0} px oben gegen {1:N0} px unten' -f $oben, $unten))
    }
    if ([math]::Abs($links - $rechts) -gt 2) {
        [void]$befunde.Add(('Lage: waagerecht nicht mittig, {0:N0} px links gegen {1:N0} px rechts' -f $links, $rechts))
    }
}

$aus = foreach ($k in $werte.Keys) { "WERT|$k|$($werte[$k])" }
$aus += foreach ($b in $befunde) { "BEFUND|$b" }
[IO.File]::WriteAllLines($env:WZ_PROBE_OUT, @($aus), [Text.Encoding]::UTF8)
'@
[IO.File]::WriteAllText($sondeDatei, $sonde, (New-Object Text.UTF8Encoding $true))

$fehler = 0
function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $farbe = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-16} {2}" -f $symbol, $Name, $Detail) -ForegroundColor $farbe
    if (-not $Ok) { $script:fehler++ }
}

function Invoke-Lauf {
    param([string]$Seite, [string]$Groesse)
    $env:WZ_SELFTEST = '2000'
    $env:WZ_SELFTEST_PAGE = $Seite
    $env:WZ_SELFTEST_ACTION = $sondeDatei
    $env:WZ_PROBE_OUT = Join-Path $arbeitsordner "$Seite-$Groesse.txt"
    $env:WZ_SELFTEST_OUT = Join-Path $arbeitsordner "$Seite-$Groesse.png"
    if ($Groesse) { $env:WZ_SELFTEST_SIZE = $Groesse } else { Remove-Item Env:WZ_SELFTEST_SIZE -ErrorAction SilentlyContinue }

    $ausgabe = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'src\main.ps1') 2>&1
    if (-not (Test-Path -LiteralPath $env:WZ_PROBE_OUT)) {
        return @{ Ok = $false; Befunde = @('Sonde lieferte nichts — Seite gar nicht aufgebaut?'); Werte = @{} }
    }
    $zeilen = [IO.File]::ReadAllLines($env:WZ_PROBE_OUT)
    $werte = @{}
    $befunde = @()
    foreach ($z in $zeilen) {
        $teile = $z -split '\|', 3
        if ($teile[0] -eq 'WERT') { $werte[$teile[1]] = $teile[2] } elseif ($teile[0] -eq 'BEFUND') { $befunde += $teile[1] }
    }
    if ($ausgabe -join "`n" -match 'fehlgeschlagen|Exception') { $befunde += 'Ausnahme beim Seitenaufbau' }
    return @{ Ok = ($befunde.Count -eq 0); Befunde = $befunde; Werte = $werte }
}

Write-Host ''
Write-Host "  WinZii Layout-Prüfung bei $Size" -ForegroundColor Cyan
Write-Host ''

foreach ($seite in $pages) {
    $e = Invoke-Lauf -Seite $seite -Groesse $Size
    $anhang = if ($e.Werte['Konsole']) { $e.Werte['Konsole'] } else { '' }
    Write-Check $seite $e.Ok $anhang
    foreach ($b in $e.Befunde) { Write-Host "         $b" -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host '  Fensterlage in Vorgabegröße' -ForegroundColor Cyan
Write-Host ''
$lage = Invoke-Lauf -Seite 'Dashboard' -Groesse ''
$lageBefunde = @($lage.Befunde | Where-Object { $_ -like 'Lage:*' })
Write-Check 'mittig' ($lageBefunde.Count -eq 0) $lage.Werte['Raender']
foreach ($b in $lageBefunde) { Write-Host "         $b" -ForegroundColor DarkGray }

if ($KeepShots) {
    Write-Host ''
    Write-Host "  Abbilder: $arbeitsordner" -ForegroundColor DarkGray
} else {
    Remove-Item -LiteralPath $arbeitsordner -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fehler -eq 0) {
    Write-Host '  Ergebnis: alle Prüfungen bestanden.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $fehler Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
