# Core.Logging — Sitzungsprotokoll in Datei, UI-Konsole und Speicher.
# Der Zustand liegt im $syncHash und nicht im Script-Scope, damit Hintergrund-
# Runspaces dieselben Daten sehen. UI-Ausgaben laufen über den Dispatcher.

function Start-WzSession {
    <#
    .SYNOPSIS
        Legt das Sitzungsprotokoll an und schreibt den Systemkopf.
    #>
    $logDir = Get-WzLogDir
    $syncHash.LogFile = Join-Path $logDir 'session.log'
    $syncHash.SessionStart = Get-Date

    $osCaption = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { 'unbekannt' }
    $header = @(
        '======================================================================'
        " WinZii $($syncHash.Version) — Sitzungsprotokoll"
        " Start:    $($syncHash.SessionStart.ToString('dd.MM.yyyy HH:mm:ss'))"
        " Computer: $env:COMPUTERNAME"
        " Benutzer: $env:USERDOMAIN\$env:USERNAME"
        " Windows:  $osCaption"
        " Quelle:   $(Get-WzRoot)"
        '======================================================================'
    ) -join [Environment]::NewLine

    try {
        [IO.File]::WriteAllText($syncHash.LogFile, $header + [Environment]::NewLine, [Text.Encoding]::UTF8)
    } catch {
        # Stick schreibgeschützt — Protokoll nur im Speicher führen
        $syncHash.LogFile = $null
    }
    return $syncHash.LogFile
}

function Write-WzLog {
    <#
    .SYNOPSIS
        Schreibt eine Protokollzeile in Datei, UI-Konsole und Speicher.
    .PARAMETER Level
        Info | Ok | Warn | Error | Action | Test — steuert Farbe und Symbol.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Action', 'Test')][string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        'Ok'     { '[ok]  ' }
        'Warn'   { '[ ! ] ' }
        'Error'  { '[ x ] ' }
        'Action' { '[ > ] ' }
        'Test'   { '[test]' }
        default  { '[ i ] ' }
    }
    $line = "$timestamp $prefix $Message"

    # $null links: bei einer leeren Collection würde "$collection -ne $null"
    # als Filter ausgewertet und ergäbe false.
    if ($syncHash -and $null -ne $syncHash.LogEntries) {
        [void]$syncHash.LogEntries.Add([pscustomobject]@{
            Time    = $timestamp
            Level   = $Level
            Message = $Message
        })
    }

    if ($syncHash -and $syncHash.LogFile) {
        try {
            [IO.File]::AppendAllText($syncHash.LogFile, $line + [Environment]::NewLine, [Text.Encoding]::UTF8)
        } catch {
            # Schreibfehler dürfen den Ablauf nie stoppen
        }
    }

    Write-WzConsole -Line $line -Level $Level
}

function Write-WzConsole {
    <#
    .SYNOPSIS
        Hängt eine Zeile an die Log-Konsole der Oberfläche an (Dispatcher-sicher).
    #>
    param([string]$Line, [string]$Level = 'Info')

    if (-not $syncHash -or -not $syncHash.Window -or -not $syncHash.LogConsole) { return }

    # Rot heller als die Statusfarbe WzRed — auf dem dunklen Konsolengrund
    # käme #EF4444 nur auf 5,4:1.
    $color = switch ($Level) {
        'Ok'     { '#22C55E' }
        'Warn'   { '#F59E0B' }
        'Error'  { '#FCA5A5' }
        'Action' { '#00D4FF' }
        'Test'   { '#7DD3FC' }
        default  { '#94A3B8' }
    }

    $action = [Action]{
        try {
            $console = $syncHash.LogConsole
            $paragraph = New-Object Windows.Documents.Paragraph
            $paragraph.Margin = New-Object Windows.Thickness(0)
            $paragraph.LineHeight = 17
            $run = New-Object Windows.Documents.Run($Line)
            $run.Foreground = New-Object Windows.Media.SolidColorBrush(
                [Windows.Media.ColorConverter]::ConvertFromString($color))
            [void]$paragraph.Inlines.Add($run)
            [void]$console.Document.Blocks.Add($paragraph)

            while ($console.Document.Blocks.Count -gt 600) {
                $console.Document.Blocks.Remove($console.Document.Blocks.FirstBlock)
            }
            $console.ScrollToEnd()
        } catch {
            # Fenster wurde bereits geschlossen
        }
    }.GetNewClosure()

    try {
        if ($syncHash.Window.Dispatcher.CheckAccess()) {
            $action.Invoke()
        } else {
            [void]$syncHash.Window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, $action)
        }
    } catch {
        # UI nicht mehr erreichbar
    }
}

function Get-WzLogEntries {
    if ($syncHash -and $syncHash.LogEntries) { return @($syncHash.LogEntries.ToArray()) }
    return @()
}

function Clear-WzConsole {
    if ($syncHash -and $syncHash.LogConsole) {
        [void]$syncHash.Window.Dispatcher.Invoke([Action]{ $syncHash.LogConsole.Document.Blocks.Clear() })
    }
}
