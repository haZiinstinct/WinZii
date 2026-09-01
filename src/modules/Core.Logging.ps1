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

    $osCaption = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { Get-WzText 'core.unknown' }
    # Die Sprache steht hier schon: main.ps1 laedt die Tabelle vor Start-WzSession.
    # Die Beschriftungen sind unterschiedlich lang, deshalb wird die Spalte
    # mit -f ausgerichtet statt mit festen Leerzeichen.
    $header = @(
        '======================================================================'
        ' ' + (Get-WzText 'core.logHeadTitle' @{ version = $syncHash.Version })
        ' {0,-10}{1}' -f ((Get-WzText 'core.logHeadStart') + ':'), $syncHash.SessionStart.ToString('G', (Get-WzLanguageCulture))
        ' {0,-10}{1}' -f ((Get-WzText 'core.logHeadComputer') + ':'), $env:COMPUTERNAME
        ' {0,-10}{1}' -f ((Get-WzText 'core.logHeadUser') + ':'), "$env:USERDOMAIN\$env:USERNAME"
        ' {0,-10}{1}' -f ((Get-WzText 'core.logHeadWindows') + ':'), $osCaption
        ' {0,-10}{1}' -f ((Get-WzText 'core.logHeadSource') + ':'), (Get-WzRoot)
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
        Hängt eine Zeile an die Log-Konsole der Oberfläche an (Thread-sicher).
    .NOTES
        Aus einem Hintergrund-Runspace darf hier kein Skriptblock über den
        Dispatcher laufen: Er gehört zum Sitzungszustand seines Runspaces und
        lässt sich vom UI-Thread nicht ausführen. Der Aufruf schlug bisher
        kommentarlos fehl — jede Meldung aus einer Hintergrundarbeit landete
        zwar in der Protokolldatei, aber nie in der Konsole. Stattdessen wird
        die Zeile eingereiht; der Zeitgeber in Invoke-WzTask holt sie ab.
    #>
    param([string]$Line, [string]$Level = 'Info')

    if (-not $syncHash -or -not $syncHash.Window -or -not $syncHash.LogConsole) { return }

    if (-not $syncHash.Window.Dispatcher.CheckAccess()) {
        if ($null -ne $syncHash.ConsoleQueue) {
            [void]$syncHash.ConsoleQueue.Add([pscustomobject]@{ Line = $Line; Level = $Level })
        }
        return
    }

    Add-WzConsoleLine -Line $Line -Level $Level
}

function Sync-WzConsoleQueue {
    <#
    .SYNOPSIS
        Zeichnet die aus Hintergrundarbeiten eingereihten Zeilen. Nur im UI-Thread.
    #>
    if (-not $syncHash -or $null -eq $syncHash.ConsoleQueue) { return }
    if (-not $syncHash.Window -or -not $syncHash.Window.Dispatcher.CheckAccess()) { return }

    # Erst herausnehmen, dann zeichnen: Nur dieser Thread entfernt Einträge,
    # deshalb kann dabei nichts doppelt erscheinen.
    while ($syncHash.ConsoleQueue.Count -gt 0) {
        $entry = $syncHash.ConsoleQueue[0]
        $syncHash.ConsoleQueue.RemoveAt(0)
        Add-WzConsoleLine -Line $entry.Line -Level $entry.Level
    }
}

function Add-WzConsoleLine {
    <#
    .SYNOPSIS
        Zeichnet eine einzelne Zeile. Setzt den UI-Thread voraus.
    #>
    param([string]$Line, [string]$Level = 'Info')

    if (-not $syncHash -or -not $syncHash.LogConsole) { return }

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
}

function Add-WzAction {
    <#
    .SYNOPSIS
        Hält fest, was an diesem PC tatsächlich verändert wurde.
    .DESCRIPTION
        Das Protokoll ist ein Entwicklerlog und für den Kunden unbrauchbar.
        Hier landet dieselbe Arbeit noch einmal in einem Satz Klartext — daraus
        entsteht später das Übergabeblatt.
    .PARAMETER Area
        Bereich in Kundensprache, z. B. "Optimierung" oder "Speicherplatz".
    .PARAMETER Summary
        Ein Satz, den auch jemand ohne Fachkenntnis versteht.
    .PARAMETER Detail
        Optionale Einzelposten.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Area,
        [Parameter(Mandatory = $true, Position = 1)][string]$Summary,
        [string[]]$Detail = @(),
        [switch]$RebootRequired
    )

    if (-not $syncHash -or $null -eq $syncHash.Actions) { return }

    [void]$syncHash.Actions.Add([pscustomobject]@{
        Time           = Get-Date
        Area           = $Area
        Summary        = $Summary
        Detail         = @($Detail)
        RebootRequired = $RebootRequired.IsPresent
        IsTest         = [bool]$syncHash.DryRun
    })
}

function Get-WzActions {
    if ($syncHash -and $syncHash.Actions) { return @($syncHash.Actions.ToArray()) }
    return @()
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
