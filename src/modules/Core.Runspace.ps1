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
        # Früher nur eine Protokollzeile: Wer während des Startscans auf
        # »Installieren« klickte, bestätigte den Dialog und sah dann — nichts.
        # Der Auftrag verschwand lautlos. Jetzt sagt es der Aufrufer.
        Write-WzLog (Get-WzText 'core.busyLog' @{ name = $syncHash.BusyName }) -Level Warn
        if (-not $Silent) {
            Show-WzInfo -Title (Get-WzText 'core.busyInfoTitle') `
                -Message (Get-WzText 'core.busyInfoMessage' @{ name = $syncHash.BusyName }) `
                -Items @((Get-WzText 'core.busyRequested' @{ name = $Name }))
        }
        return
    }

    Set-WzBusy -On -Status $Name -Cancelable:$Cancelable
    if (-not $Silent) { Write-WzLog (Get-WzText 'core.taskStarted' @{ name = $Name }) -Level Action }

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
                Write-WzLog (Get-WzText 'core.logTaskFailed' @{ name = $state.Name; grund = $_.Exception.Message }) -Level Error
            }
        }

        if (-not $state.Canceled) {
            foreach ($errorRecord in $state.PowerShell.Streams.Error) {
                Write-WzLog (Get-WzText 'core.logTaskError' @{ name = $state.Name; grund = $errorRecord.Exception.Message }) -Level Error
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
                Write-WzLog (Get-WzText 'core.logTaskCancelled' @{ name = $state.Name; sekunden = $seconds }) -Level Warn
            } elseif ($failed) {
                Write-WzLog (Get-WzText 'core.taskFailed' @{ name = $state.Name; sekunden = $seconds }) -Level Warn
            } else {
                Write-WzLog (Get-WzText 'core.taskDone' @{ name = $state.Name; sekunden = $seconds }) -Level Ok
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
                Write-WzLog (Get-WzText 'core.taskPostFailed' @{ name = $state.Name; grund = $_.Exception.Message }) -Level Error
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
    Write-WzLog (Get-WzText 'core.taskCancelling' @{ name = $state.Name }) -Level Warn
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

function Stop-WzProcessTree {
    <#
    .SYNOPSIS
        Beendet einen Prozess samt allem, was er selbst gestartet hat.
    .NOTES
        Über taskkill statt Kill(): Kill() trifft nur das gestartete Programm
        selbst. Ein von ihm gestartetes Unterprogramm liefe weiter und hielte
        die Ausgabeleitung offen — beim Bereitstellungswerkzeug für Office ist
        genau das der Normalfall, setup.exe startet einen zweiten Prozess.
    #>
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    try {
        $killer = New-Object Diagnostics.ProcessStartInfo
        $killer.FileName = 'taskkill.exe'
        $killer.Arguments = "/PID $ProcessId /T /F"
        $killer.UseShellExecute = $false
        $killer.CreateNoWindow = $true
        [void][Diagnostics.Process]::Start($killer).WaitForExit(5000)
    } catch { }

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        if (-not $process.HasExited) { $process.Kill() }
    } catch { }
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
        [string]$WorkingDirectory,
        [switch]$KillOnCancel
    )

    $result = [pscustomobject]@{
        ExitCode = -1
        StdOut   = ''
        StdErr   = ''
        TimedOut = $false
        Canceled = $false
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

        # Nicht in einem Zug warten, sondern in kurzen Schritten: Nur so lässt
        # sich zwischendurch nachsehen, ob der Anwender abgebrochen hat.
        $frist = if ($TimeoutSeconds -gt 0) { [int64]$TimeoutSeconds * 1000 } else { [int64]0 }
        $uhr = [Diagnostics.Stopwatch]::StartNew()

        while (-not $process.WaitForExit(200)) {
            if ($frist -gt 0 -and $uhr.ElapsedMilliseconds -ge $frist) {
                $result.TimedOut = $true
                Stop-WzProcessTree -ProcessId $process.Id
        Write-WzLog (Get-WzText 'core.logProcessTimeout' @{ datei = [IO.Path]::GetFileName($FilePath); sekunden = $TimeoutSeconds }) -Level Warn
                [void]$process.WaitForExit(5000)
                break
            }

            # »Abbrechen« beendete bisher nur die PowerShell-Pipeline. Das
            # gestartete Programm lief weiter — ein abgebrochener Download hing
            # unsichtbar an der Leitung, und der Runspace blieb in »Stopping«,
            # weil dieser Thread noch im Warten stand. Beendet wird nur, wo der
            # Aufrufer es ausdrücklich erlaubt: Einen laufenden Deinstallierer
            # mitten im Wort abzuschneiden wäre schlimmer als das Warten.
            if ($KillOnCancel -and $syncHash -and $syncHash.CurrentTask -and $syncHash.CurrentTask.Canceled) {
                $result.Canceled = $true
                Stop-WzProcessTree -ProcessId $process.Id
                Write-WzLog (Get-WzText 'core.procCancelled' @{ datei = [IO.Path]::GetFileName($FilePath) }) -Level Warn
                [void]$process.WaitForExit(5000)
                break
            }
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
        Write-WzLog (Get-WzText 'core.procStartFailed' @{ datei = $FilePath; grund = $_.Exception.Message }) -Level Error
    } finally {
        if ($process) { $process.Dispose() }
    }

    return $result
}
