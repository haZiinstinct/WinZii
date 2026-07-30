# Core.Runspace — länger laufende Arbeit passiert in eigenen Runspaces,
# damit die Oberfläche nie einfriert. UI-Zugriffe ausschließlich über den
# Dispatcher des Hauptfensters.

function Initialize-WzRunspacePool {
    <#
    .SYNOPSIS
        Baut den Sitzungszustand auf, den jeder Hintergrund-Runspace erbt:
        alle Wz-Funktionen, $syncHash und die globalen Pfadvariablen.
    #>
    $sessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    foreach ($function in Get-ChildItem Function:\ | Where-Object { $_.Name -like '*-Wz*' }) {
        $entry = New-Object Management.Automation.Runspaces.SessionStateFunctionEntry(
            $function.Name, $function.Definition)
        $sessionState.Commands.Add($entry)
    }

    $variables = @{
        syncHash       = $syncHash
        WzRootPath     = $global:WzRootPath
        WzSessionStamp = $global:WzSessionStamp
    }
    foreach ($name in $variables.Keys) {
        $entry = New-Object Management.Automation.Runspaces.SessionStateVariableEntry(
            $name, $variables[$name], '')
        $sessionState.Variables.Add($entry)
    }

    $syncHash.SessionState = $sessionState
    return $sessionState
}

function Invoke-WzTask {
    <#
    .SYNOPSIS
        Führt einen Arbeitsschritt im Hintergrund aus und hält die UI frei.
    .PARAMETER Name
        Anzeigename für Statusleiste und Protokoll.
    .PARAMETER ScriptBlock
        Die Arbeit. Der Rückgabewert wird an OnComplete übergeben.
    .PARAMETER ArgumentList
        Argumente für den ScriptBlock.
    .PARAMETER OnComplete
        Läuft im UI-Thread und bekommt das Ergebnis als erstes Argument.
    .PARAMETER Silent
        Kein Start-/Ende-Eintrag im Protokoll.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnComplete,
        [switch]$Silent
    )

    if ($syncHash.Busy) {
        Write-WzLog "Es läuft bereits ein Vorgang ($($syncHash.BusyName)). Bitte abwarten." -Level Warn
        return
    }

    Set-WzBusy -On -Status $Name
    if (-not $Silent) { Write-WzLog "$Name gestartet..." -Level Action }

    $runspace = [runspacefactory]::CreateRunspace($syncHash.SessionState)
    $runspace.ApartmentState = 'MTA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript($ScriptBlock)
    foreach ($argument in $ArgumentList) { [void]$powershell.AddArgument($argument) }

    $state = [pscustomobject]@{
        PowerShell = $powershell
        Runspace   = $runspace
        Name       = $Name
        OnComplete = $OnComplete
        Silent     = $Silent.IsPresent
        Started    = Get-Date
    }
    $syncHash.CurrentTask = $state
    $handle = $powershell.BeginInvoke()

    # Fertigstellung im UI-Thread abholen, ohne zu blockieren
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()

        $result = $null
        $failed = $false
        try {
            $result = $state.PowerShell.EndInvoke($handle)
        } catch {
            $failed = $true
            Write-WzLog "$($state.Name) fehlgeschlagen: $($_.Exception.Message)" -Level Error
        }

        foreach ($errorRecord in $state.PowerShell.Streams.Error) {
            Write-WzLog "$($state.Name): $($errorRecord.Exception.Message)" -Level Error
            $failed = $true
        }

        $state.PowerShell.Dispose()
        $state.Runspace.Close()
        $state.Runspace.Dispose()
        $syncHash.CurrentTask = $null
        Set-WzBusy -Off

        if (-not $state.Silent) {
            $seconds = [math]::Round(((Get-Date) - $state.Started).TotalSeconds, 1)
            if ($failed) {
                Write-WzLog "$($state.Name) mit Fehlern beendet ($seconds s)." -Level Warn
            } else {
                Write-WzLog "$($state.Name) abgeschlossen ($seconds s)." -Level Ok
            }
        }

        if ($state.OnComplete) {
            try {
                $payload = $null
                if ($null -ne $result -and $result.Count -gt 0) {
                    # EndInvoke liefert eine Collection; bei einem Element dieses direkt reichen
                    $payload = if ($result.Count -eq 1) { $result[0] } else { @($result) }
                }
                & $state.OnComplete $payload
            } catch {
                Write-WzLog "Nachbereitung von $($state.Name) fehlgeschlagen: $($_.Exception.Message)" -Level Error
            }
        }
    }.GetNewClosure())
    $timer.Start()
}

function Set-WzBusy {
    <#
    .SYNOPSIS
        Sperrt beziehungsweise entsperrt die Oberfläche während eines Vorgangs.
    #>
    param([switch]$On, [switch]$Off, [string]$Status)

    $isBusy = $On.IsPresent
    $syncHash.Busy = $isBusy
    $syncHash.BusyName = if ($isBusy) { $Status } else { $null }

    $action = [Action]{
        if ($syncHash.StatusText) {
            $syncHash.StatusText.Text = if ($isBusy) { $Status } else { 'Bereit' }
        }
        if ($syncHash.BusyBar) {
            $syncHash.BusyBar.Visibility = if ($isBusy) {
                [Windows.Visibility]::Visible
            } else {
                [Windows.Visibility]::Collapsed
            }
        }
        if ($syncHash.Window) {
            $syncHash.Window.Cursor = if ($isBusy) { [Windows.Input.Cursors]::AppStarting } else { $null }
        }
    }.GetNewClosure()

    if ($syncHash.Window) {
        if ($syncHash.Window.Dispatcher.CheckAccess()) {
            $action.Invoke()
        } else {
            [void]$syncHash.Window.Dispatcher.Invoke($action)
        }
    }
}

function Invoke-WzDoEvents {
    <#
    .SYNOPSIS
        Lässt anstehende UI-Ereignisse verarbeiten, ohne den Dispatcher zu
        blockieren. Nötig, wenn im UI-Thread auf eine Hintergrundarbeit
        gewartet wird (Start-Sleep würde auch die Timer anhalten).
    #>
    $frame = New-Object Windows.Threading.DispatcherFrame
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [Windows.Threading.DispatcherPriority]::Background,
        [Action]{ $frame.Continue = $false }.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Invoke-WzDispatcher {
    <#
    .SYNOPSIS
        Führt einen Block sicher im UI-Thread aus.
    #>
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock)
    if (-not $syncHash.Window) { return & $ScriptBlock }
    if ($syncHash.Window.Dispatcher.CheckAccess()) { return & $ScriptBlock }
    return $syncHash.Window.Dispatcher.Invoke([Func[object]]{ & $ScriptBlock })
}

function Invoke-WzProcess {
    <#
    .SYNOPSIS
        Externes Programm ausführen und die Ausgabe ins Protokoll spiegeln.
    .PARAMETER FilePath
        Programm, zum Beispiel dism.exe.
    .PARAMETER Arguments
        Argumentzeile.
    .PARAMETER LogOutput
        Ausgabe zeilenweise ins Protokoll schreiben.
    .PARAMETER TimeoutSeconds
        Abbruch nach n Sekunden (0 = unbegrenzt).
    .OUTPUTS
        PSCustomObject mit ExitCode, StdOut, StdErr, TimedOut
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = '',
        [switch]$LogOutput,
        [int]$TimeoutSeconds = 0,
        [string]$WorkingDirectory
    )

    $stdOutFile = [IO.Path]::GetTempFileName()
    $stdErrFile = [IO.Path]::GetTempFileName()
    $result = [pscustomobject]@{
        ExitCode = -1
        StdOut   = ''
        StdErr   = ''
        TimedOut = $false
    }

    try {
        $startParams = @{
            FilePath               = $FilePath
            NoNewWindow            = $true
            PassThru               = $true
            RedirectStandardOutput = $stdOutFile
            RedirectStandardError  = $stdErrFile
        }
        if ($Arguments) { $startParams.ArgumentList = $Arguments }
        if ($WorkingDirectory) { $startParams.WorkingDirectory = $WorkingDirectory }

        $process = Start-Process @startParams
        if ($TimeoutSeconds -gt 0) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $result.TimedOut = $true
                try { $process.Kill() } catch { }
                Write-WzLog "$([IO.Path]::GetFileName($FilePath)) nach $TimeoutSeconds s abgebrochen." -Level Warn
            }
        } else {
            $process.WaitForExit()
        }
        $result.ExitCode = $process.ExitCode

        if (Test-Path $stdOutFile) { $result.StdOut = Get-Content $stdOutFile -Raw -ErrorAction SilentlyContinue }
        if (Test-Path $stdErrFile) { $result.StdErr = Get-Content $stdErrFile -Raw -ErrorAction SilentlyContinue }

        if ($LogOutput -and $result.StdOut) {
            foreach ($line in ($result.StdOut -split "`r?`n")) {
                $trimmed = $line.Trim()
                if ($trimmed) { Write-WzLog "  $trimmed" -Level Info }
            }
        }
    } catch {
        $result.StdErr = $_.Exception.Message
        Write-WzLog "Start von $FilePath fehlgeschlagen: $($_.Exception.Message)" -Level Error
    } finally {
        Remove-Item $stdOutFile, $stdErrFile -Force -ErrorAction SilentlyContinue
    }

    return $result
}
