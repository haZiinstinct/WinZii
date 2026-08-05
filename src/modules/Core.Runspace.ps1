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
        [switch]$Silent,
        # Nur für reine Lese-Aufgaben gedacht: Eingriffe dürfen nicht mitten in
        # der Arbeit angehalten werden, eine Bestandsaufnahme schon.
        [switch]$Cancelable
    )

    if ($syncHash.Busy) {
        Write-WzLog "Es läuft bereits ein Vorgang ($($syncHash.BusyName)). Bitte abwarten." -Level Warn
        return
    }

    Set-WzBusy -On -Status $Name -Cancelable:$Cancelable
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
        Cancelable = $Cancelable.IsPresent
        Canceled   = $false
        Started    = Get-Date
    }
    $syncHash.CurrentTask = $state
    $handle = $powershell.BeginInvoke()

    # Fertigstellung im UI-Thread abholen, ohne zu blockieren
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        # Zeilen aus dem Hintergrund gehören in die Konsole, während die Arbeit
        # läuft — nicht erst am Ende
        Sync-WzConsoleQueue
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()

        $result = $null
        $failed = $false
        try {
            $result = $state.PowerShell.EndInvoke($handle)
        } catch {
            if ($state.Canceled) {
                # Der Abbruch beendet die Pipeline mit einer Ausnahme — das ist
                # gewollt und kein Fehler.
            } else {
                $failed = $true
                Write-WzLog "$($state.Name) fehlgeschlagen: $($_.Exception.Message)" -Level Error
            }
        }

        if (-not $state.Canceled) {
            foreach ($errorRecord in $state.PowerShell.Streams.Error) {
                Write-WzLog "$($state.Name): $($errorRecord.Exception.Message)" -Level Error
                $failed = $true
            }
        }

        # Nachzügler abholen, bevor die Abschlussmeldung geschrieben wird
        Sync-WzConsoleQueue

        $state.PowerShell.Dispose()
        $state.Runspace.Close()
        $state.Runspace.Dispose()
        $syncHash.CurrentTask = $null
        Set-WzBusy -Off

        if (-not $state.Silent -or $state.Canceled) {
            $seconds = Format-WzNumber ((Get-Date) - $state.Started).TotalSeconds
            if ($state.Canceled) {
                Write-WzLog "$($state.Name) abgebrochen ($seconds s)." -Level Warn
            } elseif ($failed) {
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
    param([switch]$On, [switch]$Off, [string]$Status, [switch]$Cancelable)

    $isBusy = $On.IsPresent
    $canCancel = ($isBusy -and $Cancelable.IsPresent)
    $syncHash.Busy = $isBusy
    $syncHash.BusyName = if ($isBusy) { $Status } else { $null }

    $action = [Action]{
        if ($syncHash.StatusText) {
            $syncHash.StatusText.Text = if ($isBusy) { $Status } else { Get-WzText 'shell.statusReady' }
        }
        if ($syncHash.BtnCancelTask) {
            $syncHash.BtnCancelTask.Visibility = if ($canCancel) {
                [Windows.Visibility]::Visible
            } else {
                [Windows.Visibility]::Collapsed
            }
            $syncHash.BtnCancelTask.IsEnabled = $canCancel
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

function Stop-WzTask {
    <#
    .SYNOPSIS
        Bricht die laufende Hintergrundarbeit ab — nur wenn sie als abbrechbar
        gekennzeichnet ist.
    .NOTES
        BeginStop statt Stop: Stop blockiert den UI-Thread, bis die Pipeline
        wirklich steht. Das Ende holt der ohnehin laufende Zeitgeber ab.
    #>
    $state = $syncHash.CurrentTask
    if (-not $state -or -not $state.Cancelable -or $state.Canceled) { return }

    $state.Canceled = $true
    Write-WzLog "$($state.Name) wird abgebrochen..." -Level Warn
    try {
        [void]$state.PowerShell.BeginStop($null, $null)
    } catch { }
}

function Invoke-WzDoEvents {
    <#
    .SYNOPSIS
        Lässt anstehende UI-Ereignisse verarbeiten, ohne den Dispatcher zu
        blockieren. Nötig, wenn im UI-Thread auf eine Hintergrundarbeit
        gewartet wird (Start-Sleep würde auch die Timer anhalten).
    #>
    # Ein leerer Aufruf mit niedriger Priorität kehrt erst zurück, wenn alles
    # Wichtigere abgearbeitet ist — das entspricht einem DoEvents.
    # (DispatcherFrame und PushFrame scheitern hier, weil New-Object den Frame
    # in ein PSObject verpackt und PushFrame damit nichts anfangen kann.)
    $dispatcher = if ($syncHash -and $syncHash.Window) {
        $syncHash.Window.Dispatcher
    } else {
        [Windows.Threading.Dispatcher]::CurrentDispatcher
    }
    try {
        [void]$dispatcher.Invoke([Action]{ }, [Windows.Threading.DispatcherPriority]::Background)
    } catch {
        # Fenster bereits geschlossen
    }
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
    .DESCRIPTION
        Bewusst über System.Diagnostics.Process statt Start-Process:
        `Start-Process -PassThru` **ohne** `-Wait` liefert unter PowerShell 5.1
        immer `ExitCode = $null`, auch nach `WaitForExit()`. Da `$null -eq 0`
        falsch ist, hätte damit jedes erfolgreich gelaufene Programm als
        Fehlschlag gegolten — und `$null -le 1` umgekehrt jeden chkdsk-Lauf als
        fehlerfrei. `-Wait` wäre keine Lösung, weil es sich mit der zeitlich
        begrenzten Variante von `WaitForExit` ausschließt.
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

    $result = [pscustomobject]@{
        ExitCode = -1
        StdOut   = ''
        StdErr   = ''
        TimedOut = $false
    }

    $process = $null
    try {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = $Arguments
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        # Ohne feste Codierung dekodiert .NET die Ausgabe mit der Codepage der
        # Konsole — die es in einem Hintergrund-Runspace nicht zwingend gibt.
        # Aus »Hinzugefügte Treiberpakete« wird dann Buchstabensalat, und die
        # Muster in Drivers.ps1 und Diagnostics.ps1 greifen nicht mehr.
        $consoleEncoding = try { [Console]::OutputEncoding } catch { $null }
        if (-not $consoleEncoding) {
            $consoleEncoding = [Text.Encoding]::GetEncoding(
                [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        }
        $startInfo.StandardOutputEncoding = $consoleEncoding
        $startInfo.StandardErrorEncoding = $consoleEncoding

        if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()

        # Beide Ausgabekanäle gleichzeitig leerlesen. Läse man erst den einen
        # ganz und dann den anderen, könnte ein Programm mit viel Ausgabe auf
        # dem vollen Puffer des zweiten Kanals stehen bleiben.
        # Bewusst über .NET-Aufgaben statt Register-ObjectEvent: Letzteres
        # bräuchte die Ereignisschleife von PowerShell, die es in den
        # Hintergrund-Runspaces nicht gibt.
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()

        if ($TimeoutSeconds -gt 0) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $result.TimedOut = $true
                # Den ganzen Prozessbaum beenden: Kill() trifft nur das
                # gestartete Programm selbst, ein von ihm gestartetes
                # Unterprogramm liefe weiter und hielte die Ausgabeleitung offen.
                try {
                    $killer = New-Object Diagnostics.ProcessStartInfo
                    $killer.FileName = 'taskkill.exe'
                    $killer.Arguments = "/PID $($process.Id) /T /F"
                    $killer.UseShellExecute = $false
                    $killer.CreateNoWindow = $true
                    [void][Diagnostics.Process]::Start($killer).WaitForExit(5000)
                } catch { }
                try { if (-not $process.HasExited) { $process.Kill() } } catch { }
                Write-WzLog "$([IO.Path]::GetFileName($FilePath)) nach $TimeoutSeconds s abgebrochen." -Level Warn
                [void]$process.WaitForExit(5000)
            }
        } else {
            $process.WaitForExit()
        }

        $result.ExitCode = $process.ExitCode

        # Das Lesen ebenfalls begrenzen: Hält nach einem Abbruch noch ein
        # Unterprogramm die Leitung offen, würde .Result sonst weiter warten.
        try { if ($outTask.Wait(5000)) { $result.StdOut = $outTask.Result } } catch { }
        try { if ($errTask.Wait(2000)) { $result.StdErr = $errTask.Result } } catch { }

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
        if ($process) { $process.Dispose() }
    }

    return $result
}
