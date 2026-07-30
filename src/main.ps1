# WinZii — Hauptprogramm.
# Wird über Start.bat und launcher.ps1 gestartet (eleviert, STA).
[CmdletBinding()]
param([switch]$DryRun)

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
$syncHash.Busy = $false
$syncHash.DryRun = $DryRun.IsPresent
$syncHash.CurrentPage = $null

. (Join-Path $PSScriptRoot 'version.ps1')
$syncHash.Version = $script:WzVersion
$syncHash.BuildDate = $script:WzBuildDate

# --- Module laden ---------------------------------------------------------
$moduleOrder = @(
    'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace', 'Core.Ui',
    'Core.System', 'Core.Backup',
    'Optimizer', 'AiRemoval', 'Cleanup', 'Apps', 'Office',
    'Diagnostics', 'Report', 'Autostart', 'Toolbox'
)
foreach ($moduleName in $moduleOrder) {
    $modulePath = Join-Path $PSScriptRoot "modules\$moduleName.ps1"
    if (Test-Path -LiteralPath $modulePath) { . $modulePath }
}

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
        "Das Design konnte nicht geladen werden:`n$($_.Exception.Message)",
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
        "Das Hauptfenster konnte nicht geladen werden:`n$($_.Exception.Message)",
        'WinZii', 'OK', 'Error')
    exit 1
}

$window.Resources.MergedDictionaries.Add($theme)
$syncHash.Window = $window
Register-WzNames -Root $window -Xml $mainXml

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
        Write-WzLog 'Mitgelieferte Schriften nicht nutzbar, System-Schriften werden verwendet.' -Level Warn
    }
}
Set-WzFonts

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
$syncHash.StatusPath.Text = "$($volume.DriveLetter): $($volume.FileSystem)"

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
        $answer = Show-WzConfirm -Title 'Vorgang läuft' `
            -Message "'$($syncHash.BusyName)' ist noch aktiv. Ein Abbruch kann das System in einem halben Zustand hinterlassen." `
            -ConfirmText 'Trotzdem beenden' -Danger
        if (-not $answer.Confirmed) { return }
    }
    $syncHash.Window.Close()
})

# --- Log-Konsole ein- und ausklappen --------------------------------------
$syncHash.LogHeader.Add_MouseLeftButtonUp({
    if ($syncHash.LogConsole.Visibility -eq [Windows.Visibility]::Visible) {
        $syncHash.LogConsole.Visibility = [Windows.Visibility]::Collapsed
        $syncHash.LogChevron.Text = [char]0xE70E
        $syncHash.LogHint.Text = 'eingeklappt'
    } else {
        $syncHash.LogConsole.Visibility = [Windows.Visibility]::Visible
        $syncHash.LogChevron.Text = [char]0xE70D
        $syncHash.LogHint.Text = 'Klicken zum Ein- oder Ausklappen'
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
        Write-WzLog 'Testmodus aktiv — Änderungen werden nur protokolliert.' -Level Test
    } else {
        Write-WzLog 'Testmodus aus — Änderungen werden wirklich ausgeführt.' -Level Warn
    }
})

# --- haZii-Credit ---------------------------------------------------------
$syncHash.HaziiBadge.Add_MouseLeftButtonUp({
    Start-Process 'https://hazii.org'
})

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
    Write-WzLog "WinZii $($syncHash.Version) gestartet — $env:COMPUTERNAME" -Level Ok
    Write-WzLog "Quelle: $(Get-WzRoot)" -Level Info
    if ($syncHash.DryRun) {
        Write-WzLog 'Testmodus ist aktiv. Es werden keine Änderungen vorgenommen.' -Level Test
    }
    if (-not (Test-WzWritableRoot)) {
        Write-WzLog 'Der Datenträger ist schreibgeschützt — Protokolle und Berichte können nicht gespeichert werden.' -Level Warn
    }
    Show-WzPage -Id 'Dashboard'
})

$window.Add_Closed({
    Write-WzLog 'WinZii beendet.' -Level Info
})

# --- Selbsttest (nur Entwicklung): rendern, abbilden, schließen -----------
if ($env:WZ_SELFTEST) {
    $shotTimer = New-Object Windows.Threading.DispatcherTimer
    $shotTimer.Interval = [TimeSpan]::FromMilliseconds([int]$env:WZ_SELFTEST)
    $shotTimer.Add_Tick({
        $shotTimer.Stop()
        try {
            $page = if ($env:WZ_SELFTEST_PAGE) { $env:WZ_SELFTEST_PAGE } else { 'Dashboard' }
            if ($syncHash.CurrentPage -ne $page) { Show-WzPage -Id $page }
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
        }
        $syncHash.Window.Close()
    }.GetNewClosure())
    $shotTimer.Start()
}

[void]$window.ShowDialog()
