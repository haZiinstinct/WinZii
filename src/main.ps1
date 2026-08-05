# WinZii — Hauptprogramm.
# Wird über Start.bat und launcher.ps1 gestartet (eleviert, STA).
[CmdletBinding()]
param(
    [switch]$DryRun,
    # Oberflächensprache erzwingen, z. B. -Language en. Ohne Angabe gilt die
    # gemerkte Wahl, sonst die Windows-Sprache. Gedacht zum Prüfen: Auf einem
    # deutschen Rechner bekommt man die englische Fassung sonst nie zu sehen.
    [string]$Language
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# --- Grundzustand ---------------------------------------------------------
$global:WzRootPath = Split-Path -Parent $PSScriptRoot
$global:WzSessionStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'

$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.Pages = @{}
$syncHash.NavButtons = @()
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
# Warteschlange für Konsolenzeilen aus Hintergrund-Runspaces
$syncHash.ConsoleQueue = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
# Was an diesem PC verändert wurde — Grundlage des Übergabeblatts
$syncHash.Actions = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.Busy = $false
$syncHash.DryRun = $DryRun.IsPresent
$syncHash.CurrentPage = $null

. (Join-Path $PSScriptRoot 'version.ps1')
$syncHash.Version = $script:WzVersion
$syncHash.BuildDate = $script:WzBuildDate

# --- Module laden ---------------------------------------------------------
$moduleOrder = @(
    'Core.Paths', 'Core.I18n', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Ui',
    'Core.System', 'Core.Backup',
    'Optimizer', 'AiRemoval', 'Cleanup', 'Apps', 'Office',
    'Diagnostics', 'NetworkDiag', 'Report', 'Autostart', 'Toolbox',
    'UserData', 'Migration', 'Drivers', 'Uninstall'
)
foreach ($moduleName in $moduleOrder) {
    $modulePath = Join-Path $PSScriptRoot "modules\$moduleName.ps1"
    if (Test-Path -LiteralPath $modulePath) { . $modulePath }
}

# Seitenlogik (je Seite eine Datei, Reihenfolge egal)
$pageDir = Join-Path $PSScriptRoot 'pages'
if (Test-Path -LiteralPath $pageDir) {
    foreach ($pageFile in Get-ChildItem -LiteralPath $pageDir -Filter '*.ps1' -File) {
        . $pageFile.FullName
    }
}

# --- Sprache festlegen ----------------------------------------------------
# Vor der Sitzung, damit auch die ersten Protokollzeilen schon übersetzt sind.
$wantedLanguage = if ($Language) { $Language } else { $env:WZ_SELFTEST_LANG }
[void](Initialize-WzLanguage -Preferred $wantedLanguage)

# --- Sitzung starten ------------------------------------------------------
[void](Start-WzSession)

# --- Oberfläche aufbauen --------------------------------------------------
$xamlDir = Join-Path $PSScriptRoot 'xaml'

try {
    $themeXaml = [IO.File]::ReadAllText((Join-Path $xamlDir 'Theme.xaml'), [Text.Encoding]::UTF8)
    $themeReader = New-Object Xml.XmlNodeReader ([xml]$themeXaml)
    $theme = [Windows.Markup.XamlReader]::Load($themeReader)
} catch {
    [Windows.Forms.MessageBox]::Show(
        "$(Get-WzText 'dialog.themeFailed')`n$($_.Exception.Message)",
        'WinZii', 'OK', 'Error')
    exit 1
}

try {
    $mainXaml = [IO.File]::ReadAllText((Join-Path $xamlDir 'MainWindow.xaml'), [Text.Encoding]::UTF8)
    [xml]$mainXml = $mainXaml
    $mainReader = New-Object Xml.XmlNodeReader($mainXml)
    $window = [Windows.Markup.XamlReader]::Load($mainReader)
} catch {
    [Windows.Forms.MessageBox]::Show(
        "$(Get-WzText 'dialog.windowFailed')`n$($_.Exception.Message)",
        'WinZii', 'OK', 'Error')
    exit 1
}

$window.Resources.MergedDictionaries.Add($theme)
$syncHash.Window = $window
Register-WzNames -Root $window -Xml $mainXml

# Sprachwörterbuch einhängen: Ab hier lösen alle {DynamicResource L.…} im XAML
# auf, und ein späterer Tausch schaltet die ganze Oberfläche live um.
Update-WzLanguageResources

# --- Mitgelieferte Schriften einbinden ------------------------------------
function Set-WzFonts {
    $fontDir = Get-WzFontDir
    if (-not (Test-Path -LiteralPath $fontDir)) { return }
    $uriBase = 'file:///' + ($fontDir -replace '\\', '/') + '/'
    try {
        # .PSObject.BaseObject ist nötig: sonst landet ein PSObject-Wrapper im
        # ResourceDictionary und WPF kann ihn nicht in FontFamily umwandeln.
        $mono = (New-Object Windows.Media.FontFamily(($uriBase + '#JetBrains Mono'))).PSObject.BaseObject
        $sans = (New-Object Windows.Media.FontFamily(($uriBase + '#Inter'))).PSObject.BaseObject
        if ($mono.GetTypefaces().Count -gt 0) { $syncHash.Window.Resources['WzFontMono'] = $mono }
        if ($sans.GetTypefaces().Count -gt 0) { $syncHash.Window.Resources['WzFontSans'] = $sans }
    } catch {
        Write-WzLog (Get-WzText 'start.fontsMissing') -Level Warn
    }
}
Set-WzFonts

# --- Fenstersymbol --------------------------------------------------------
try {
    $iconPath = Join-Path (Get-WzAssetDir) 'winzii.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $window.Icon = New-Object Windows.Media.Imaging.BitmapImage(
            (New-Object Uri($iconPath)))
    }
} catch {
    # Ohne Symbol läuft WinZii genauso
}

# --- Fenster an den Bildschirm anpassen -----------------------------------
# Die Vorgabe 1280×820 passt nicht auf jedes Kundengerät: 1366×768 bei 125 %
# Skalierung sind logisch nur 1092×614 — Statusleiste und Konsole lägen
# außerhalb des Bildschirms und wären nicht erreichbar.
try {
    $workArea = [Windows.SystemParameters]::WorkArea
    if ($window.Height -gt $workArea.Height) {
        $window.Height = [math]::Max($window.MinHeight, $workArea.Height - 20)
    }
    if ($window.Width -gt $workArea.Width) {
        $window.Width = [math]::Max($window.MinWidth, $workArea.Width - 20)
    }
} catch {
    # Ohne Anpassung bleibt die Vorgabegröße
}

# --- Kopfzeile füllen -----------------------------------------------------
$syncHash.HeaderHost.Text = $env:COMPUTERNAME.ToUpper()
$syncHash.SidebarVersion.Text = "v$($syncHash.Version)"
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $displayVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
    $shortName = if ($osInfo.Caption -match 'Windows (\d+)') { "WINDOWS $($Matches[1])" } else { 'WINDOWS' }
    $syncHash.HeaderOs.Text = if ($displayVersion) { "$shortName $displayVersion" } else { $shortName }
} catch {
    $syncHash.HeaderOs.Text = 'WINDOWS'
}

$volume = Get-WzVolumeInfo
$syncHash.StatusPath.Text = "$($volume.DisplayName) $($volume.FileSystem)"

# --- Fenstersteuerung -----------------------------------------------------
$syncHash.BtnMinimize.Add_Click({ $syncHash.Window.WindowState = 'Minimized' })
$syncHash.BtnMaximize.Add_Click({
    if ($syncHash.Window.WindowState -eq 'Maximized') {
        $syncHash.Window.WindowState = 'Normal'
        $syncHash.BtnMaximize.Content = [char]0xE922
    } else {
        $syncHash.Window.WindowState = 'Maximized'
        $syncHash.BtnMaximize.Content = [char]0xE923
    }
})
$syncHash.BtnClose.Add_Click({
    if ($syncHash.Busy) {
        $answer = Show-WzConfirm -Title (Get-WzText 'dialog.busyTitle') `
            -Message (Get-WzText 'dialog.busyMessage' @{ name = $syncHash.BusyName }) `
            -ConfirmText (Get-WzText 'dialog.busyConfirm') -Danger
        if (-not $answer.Confirmed) { return }
    }
    $syncHash.Window.Close()
})

# --- Log-Konsole ein- und ausklappen --------------------------------------
$syncHash.LogHeader.Add_MouseLeftButtonUp({
    if ($syncHash.LogConsole.Visibility -eq [Windows.Visibility]::Visible) {
        $syncHash.LogConsole.Visibility = [Windows.Visibility]::Collapsed
        $syncHash.LogChevron.Text = [char]0xE70E
        $syncHash.LogHint.Text = Get-WzText 'shell.consoleCollapsed'
    } else {
        $syncHash.LogConsole.Visibility = [Windows.Visibility]::Visible
        $syncHash.LogChevron.Text = [char]0xE70D
        $syncHash.LogHint.Text = Get-WzText 'shell.consoleHint'
    }
})
$syncHash.BtnClearLog.Add_Click({ Clear-WzConsole })

# --- Testmodus ------------------------------------------------------------
$syncHash.DryRunToggle.IsChecked = $syncHash.DryRun
$syncHash.DryRunBadge.Visibility = if ($syncHash.DryRun) {
    [Windows.Visibility]::Visible
} else {
    [Windows.Visibility]::Collapsed
}
$syncHash.DryRunToggle.Add_Click({
    $syncHash.DryRun = [bool]$syncHash.DryRunToggle.IsChecked
    $syncHash.DryRunBadge.Visibility = if ($syncHash.DryRun) {
        [Windows.Visibility]::Visible
    } else {
        [Windows.Visibility]::Collapsed
    }
    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'start.dryRunOn') -Level Test
    } else {
        Write-WzLog (Get-WzText 'start.dryRunOff') -Level Warn
    }
})

# --- Sprachwahl -----------------------------------------------------------
# Nur die Sprachen anbieten, für die auch eine Datei da ist. Eine ausgegraute
# Zeile »Español (noch nicht übersetzt)« hilft niemandem.
foreach ($language in (Get-WzLanguageList | Where-Object { $_.Available })) {
    $item = New-Object Windows.Controls.ComboBoxItem
    $item.Content = $language.Name
    $item.Tag = $language.Code
    [void]$syncHash.LanguagePicker.Items.Add($item)
    if ($language.Code -eq $syncHash.Language) { $syncHash.LanguagePicker.SelectedItem = $item }
}
$syncHash.LanguagePicker.Add_SelectionChanged({
    $chosen = $syncHash.LanguagePicker.SelectedItem
    if (-not $chosen -or $chosen.Tag -eq $syncHash.Language) { return }
    $name = $chosen.Content
    [void](Set-WzLanguage -Code $chosen.Tag)
    Update-WzLanguageUi
    Write-WzLog (Get-WzText 'start.languageChanged' @{ sprache = $name }) -Level Info
    if (-not (Test-WzWritableRoot)) {
        Write-WzLog (Get-WzText 'start.settingsReadOnly') -Level Warn
    }
})

# --- haZii-Credit ---------------------------------------------------------
$syncHash.HaziiBadge.Add_MouseLeftButtonUp({
    Start-Process 'https://hazii.org'
})

# --- Laufende Bestandsaufnahme abbrechen ----------------------------------
$syncHash.BtnCancelTask.Add_Click({ Stop-WzTask })

# --- Navigation verdrahten ------------------------------------------------
$navButtons = @()
foreach ($child in $syncHash.NavPanel.Children) {
    if ($child -is [Windows.Controls.Button] -and $child.Tag) {
        $navButtons += $child
        $child.Add_Click({ Show-WzPage -Id $this.Tag }.GetNewClosure())
    }
}
$syncHash.NavButtons = $navButtons

# --- Runspace-Umgebung ----------------------------------------------------
[void](Initialize-WzRunspacePool)

# --- Start ----------------------------------------------------------------
$window.Add_ContentRendered({
    Write-WzLog (Get-WzText 'start.started' @{ version = $syncHash.Version; computer = $env:COMPUTERNAME }) -Level Ok
    Write-WzLog (Get-WzText 'start.source' @{ pfad = (Get-WzRoot) }) -Level Info
    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'start.dryRunActive') -Level Test
    }
    if (-not (Test-WzWritableRoot)) {
        Write-WzLog (Get-WzText 'start.readOnly') -Level Warn
    }
    Show-WzPage -Id 'Dashboard'
})

$window.Add_Closed({
    Write-WzLog (Get-WzText 'start.closed') -Level Info
})

# --- Selbsttest (nur Entwicklung): rendern, abbilden, schließen -----------
if ($env:WZ_SELFTEST) {
    $shotTimer = New-Object Windows.Threading.DispatcherTimer
    $shotTimer.Interval = [TimeSpan]::FromMilliseconds([int]$env:WZ_SELFTEST)
    $shotTimer.Add_Tick({
        $shotTimer.Stop()
        try {
            $waitFor = {
                $limit = (Get-Date).AddSeconds(90)
                while ($syncHash.Busy -and (Get-Date) -lt $limit) {
                    Invoke-WzDoEvents
                    Start-Sleep -Milliseconds 100
                }
            }

            # Erst den Start abwarten, dann wechseln — sonst greift die
            # Seite auf Elemente zu, die noch nicht aufgebaut sind
            & $waitFor
            $page = if ($env:WZ_SELFTEST_PAGE) { $env:WZ_SELFTEST_PAGE } else { 'Dashboard' }
            if ($syncHash.CurrentPage -ne $page) { Show-WzPage -Id $page }
            & $waitFor

            if ($env:WZ_SELFTEST_ACTION) {
                Write-Host "  Testaktion: $env:WZ_SELFTEST_ACTION" -ForegroundColor DarkGray
                & $env:WZ_SELFTEST_ACTION
            }

            # Laufende Hintergrundarbeit abwarten, damit das Abbild den
            # fertigen Zustand zeigt und nicht den Ladezustand
            $deadline = (Get-Date).AddSeconds(90)
            while ($syncHash.Busy -and (Get-Date) -lt $deadline) {
                Invoke-WzDoEvents
                Start-Sleep -Milliseconds 100
            }
            Invoke-WzDoEvents
            $syncHash.Window.UpdateLayout()

            $target = New-Object Windows.Media.Imaging.RenderTargetBitmap(
                [int]$syncHash.Window.ActualWidth, [int]$syncHash.Window.ActualHeight,
                96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $target.Render($syncHash.Window)
            $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($target))
            $outFile = if ($env:WZ_SELFTEST_OUT) { $env:WZ_SELFTEST_OUT } else { (Join-Path (Get-WzRoot) 'selftest.png') }
            $stream = [IO.File]::Create($outFile)
            $encoder.Save($stream)
            $stream.Close()
            Write-Host "  Abbild gespeichert: $outFile" -ForegroundColor Cyan
        } catch {
            Write-Host "  Abbild fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Stelle: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
            Write-Host "  Zeile:  $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
        }
        $syncHash.Window.Close()
    }.GetNewClosure())
    $shotTimer.Start()
}

[void]$window.ShowDialog()
