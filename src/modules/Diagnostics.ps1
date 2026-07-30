# Diagnostics — Fehlersuche mit deutscher Deutung.
#
# Ziel ist nicht, Ereignisprotokolle roh anzuzeigen, sondern die wichtigen
# Einträge zu bündeln und in Klartext zu übersetzen: Was ist passiert, was
# bedeutet es, was tut man dagegen.

function Get-WzEventSummary {
    <#
    .SYNOPSIS
        Kritische Einträge und Fehler aus System- und Anwendungsprotokoll,
        nach Quelle und Kennung zusammengefasst.
    .NOTES
        Ausschließlich über FilterHashtable — eine Filterung mit Where-Object
        über das volle Protokoll dauert ein Vielfaches.
    #>
    param(
        [int]$Days = 14,
        [string[]]$LogNames = @('System', 'Application'),
        [int]$MaxEvents = 3000
    )

    $startTime = (Get-Date).AddDays(-$Days)
    $map = Get-WzCatalog -Name 'eventmap'
    $events = @()

    foreach ($logName in $LogNames) {
        try {
            $filter = @{
                LogName   = $logName
                Level     = 1, 2
                StartTime = $startTime
            }
            $events += @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop)
        } catch {
            # "Keine Ereignisse gefunden" ist kein Fehler
            if ($_.Exception.Message -notmatch 'No events|Keine Ereignisse') {
                Write-WzLog "Protokoll '$logName' nicht lesbar: $($_.Exception.Message)" -Level Warn
            }
        }
    }

    $groups = $events | Group-Object -Property ProviderName, Id | ForEach-Object {
        $first = $_.Group[0]
        $known = $map.entries | Where-Object {
            $_.id -eq $first.Id -and $first.ProviderName -like "*$($_.provider)*"
        } | Select-Object -First 1

        $times = $_.Group | Select-Object -ExpandProperty TimeCreated | Sort-Object
        $severity = if ($known) {
            $known.severity
        } elseif ($first.Level -eq 1) {
            'critical'
        } else {
            'error'
        }

        [pscustomobject]@{
            Provider       = $first.ProviderName
            Id             = $first.Id
            Count          = $_.Count
            First          = $times[0]
            Last           = $times[-1]
            Severity       = $severity
            Title          = if ($known) { $known.title } else { "$($first.ProviderName) — Kennung $($first.Id)" }
            Explanation    = if ($known) { $known.explanation } else { '' }
            Recommendation = if ($known) { $known.recommendation } else { '' }
            Known          = [bool]$known
            Sample         = ($first.Message -split "`r?`n" | Select-Object -First 2) -join ' '
        }
    }

    $order = @{ 'critical' = 0; 'error' = 1; 'warning' = 2 }
    return @($groups | Sort-Object @{ Expression = { $order[$_.Severity] } }, @{ Expression = 'Count'; Descending = $true })
}

function Get-WzMinidumps {
    <#
    .SYNOPSIS
        Bluescreen-Abbilder samt übersetztem Stoppcode.
        Der Code stammt aus dem passenden Ereignis 1001; ersatzweise wird er
        aus dem Kopf der Abbilddatei gelesen.
    #>
    param([int]$Days = 90)

    $map = Get-WzCatalog -Name 'bugcheckmap'
    $dumps = @()

    $paths = @(
        (Join-Path $env:SystemRoot 'Minidump')
        $env:SystemRoot
    )
    $files = @()
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $files += @(Get-ChildItem -LiteralPath $path -Filter '*.dmp' -File -ErrorAction SilentlyContinue)
    }
    $files = @($files | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-$Days) } |
        Sort-Object LastWriteTime -Descending)

    # Stoppcodes aus den Bluescreen-Ereignissen sammeln
    $bugcheckEvents = @()
    try {
        $bugcheckEvents = @(Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
            Id           = 1001
            StartTime    = (Get-Date).AddDays(-$Days)
        } -ErrorAction Stop)
    } catch { }

    foreach ($file in $files) {
        $code = $null

        # Passendes Ereignis im Umkreis von zehn Minuten suchen
        $event = $bugcheckEvents | Where-Object {
            [math]::Abs(($_.TimeCreated - $file.LastWriteTime).TotalMinutes) -lt 10
        } | Select-Object -First 1
        if ($event -and $event.Message -match '0x([0-9a-fA-F]{8})') {
            $code = '0x' + $Matches[1].ToUpper()
        }

        if (-not $code) { $code = Read-WzDumpBugcheckCode -Path $file.FullName }

        $known = $null
        if ($code) {
            $known = $map.entries | Where-Object { $_.code -eq $code } | Select-Object -First 1
        }

        $dumps += [pscustomobject]@{
            File           = $file.Name
            Path           = $file.FullName
            Time           = $file.LastWriteTime
            SizeBytes      = $file.Length
            Code           = if ($code) { $code } else { 'unbekannt' }
            Name           = if ($known) { $known.name } else { 'nicht zugeordnet' }
            Cause          = if ($known) { $known.cause } else { 'Der Stoppcode ist nicht in der Übersetzungstabelle enthalten.' }
            Recommendation = if ($known) { $known.recommendation } else { 'Abbild mit WinDbg auswerten oder den Code nachschlagen.' }
        }
    }

    return @($dumps)
}

function Read-WzDumpBugcheckCode {
    <#
    .SYNOPSIS
        Liest den Stoppcode direkt aus dem Kopf einer Abbilddatei.
        Der Wert steht bei 64-Bit-Abbildern an einer festen Stelle.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $header = New-Object byte[] 64
            [void]$stream.Read($header, 0, 64)

            $signature = [Text.Encoding]::ASCII.GetString($header, 0, 4)
            if ($signature -ne 'PAGE') { return $null }

            # 64-Bit-Abbilder tragen den Stoppcode bei Offset 0x38
            $code = [BitConverter]::ToUInt32($header, 0x38)
            if ($code -eq 0) { return $null }
            return ('0x{0:X8}' -f $code)
        } finally {
            $stream.Close()
        }
    } catch {
        return $null
    }
}

function Get-WzReliabilityRecords {
    <#
    .SYNOPSIS
        Einträge der Zuverlässigkeitsüberwachung (Abstürze, Installationen).
    #>
    param([int]$Days = 30, [int]$MaxRecords = 60)

    try {
        $since = (Get-Date).AddDays(-$Days)
        $records = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
            Where-Object { $_.TimeGenerated -gt $since } |
            Sort-Object TimeGenerated -Descending |
            Select-Object -First $MaxRecords)

        return @($records | ForEach-Object {
            [pscustomobject]@{
                Time    = $_.TimeGenerated
                Source  = $_.SourceName
                Type    = switch ($_.EventIdentifier) {
                    1001 { 'Absturz' }
                    1000 { 'Programmfehler' }
                    default { 'Ereignis' }
                }
                Message = ($_.Message -split "`r?`n" | Select-Object -First 1)
            }
        })
    } catch {
        return @()
    }
}

function Get-WzSmartStatus {
    <#
    .SYNOPSIS
        Zustand der Datenträger inklusive Betriebsstunden und Abnutzung.
        USB-Gehäuse geben diese Werte oft nicht weiter — dann bleibt es bei "n/v".
    #>
    $disks = @()

    try {
        foreach ($disk in (Get-PhysicalDisk -ErrorAction Stop)) {
            $entry = [pscustomobject]@{
                Number       = $disk.DeviceId
                Model        = $disk.FriendlyName
                MediaType    = if ($disk.MediaType) { [string]$disk.MediaType } else { 'unbekannt' }
                BusType      = [string]$disk.BusType
                SizeBytes    = [int64]$disk.Size
                Health       = [string]$disk.HealthStatus
                Temperature  = 'n/v'
                PowerOnHours = 'n/v'
                Wear         = 'n/v'
                ReadErrors   = 'n/v'
                Assessment   = ''
            }

            try {
                $counter = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
                if ($null -ne $counter.Temperature -and $counter.Temperature -gt 0) {
                    $entry.Temperature = "$($counter.Temperature) °C"
                }
                if ($null -ne $counter.PowerOnHours) {
                    $years = [math]::Round($counter.PowerOnHours / 8760, 1)
                    $entry.PowerOnHours = "$($counter.PowerOnHours) h (rund $years Jahre)"
                }
                if ($null -ne $counter.Wear) { $entry.Wear = "$($counter.Wear) %" }
                if ($null -ne $counter.ReadErrorsUncorrected) { $entry.ReadErrors = [string]$counter.ReadErrorsUncorrected }
            } catch { }

            $notes = @()
            if ($entry.Health -ne 'Healthy') { $notes += 'Windows meldet einen Fehlerzustand' }
            if ($counter -and $counter.Wear -gt 80) { $notes += 'Abnutzung über 80 Prozent — Austausch einplanen' }
            if ($counter -and $counter.ReadErrorsUncorrected -gt 0) { $notes += 'nicht behebbare Lesefehler vorhanden' }
            if ($counter -and $counter.Temperature -gt 60) { $notes += 'Temperatur auffällig hoch' }
            $entry.Assessment = if ($notes.Count -gt 0) { $notes -join '; ' } else { 'unauffällig' }

            $disks += $entry
        }
    } catch {
        Write-WzLog "Datenträgerzustand nicht abfragbar: $($_.Exception.Message)" -Level Warn
    }

    return @($disks)
}

function Invoke-WzSfc {
    <#
    .SYNOPSIS
        Systemdateiprüfung. Die Ausgabe kommt in UTF-16 und wird deshalb
        über eine Datei eingelesen statt direkt weitergereicht.
    #>
    if ($syncHash.DryRun) {
        Write-WzLog '[Test] sfc /scannow' -Level Test
        return [pscustomobject]@{ Success = $true; Summary = 'Testmodus' }
    }

    Write-WzLog 'Systemdateien werden geprüft — das dauert einige Minuten...' -Level Action
    $outFile = [IO.Path]::GetTempFileName()
    try {
        $result = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments "/c sfc /scannow > `"$outFile`"" -TimeoutSeconds 2400
        $text = ''
        if (Test-Path $outFile) {
            $text = [IO.File]::ReadAllText($outFile, [Text.Encoding]::Unicode) -replace "`0", ''
        }

        $summary = if ($text -match 'keine Integritätsverletzungen|did not find any integrity violations') {
            'Keine beschädigten Systemdateien gefunden.'
        } elseif ($text -match 'erfolgreich repariert|successfully repaired') {
            'Beschädigte Dateien wurden gefunden und repariert. Ein Neustart wird empfohlen.'
        } elseif ($text -match 'nicht reparieren|unable to fix') {
            'Beschädigte Dateien gefunden, die nicht repariert werden konnten. Jetzt DISM ausführen.'
        } else {
            "Prüfung beendet (Code $($result.ExitCode))."
        }

        Write-WzLog $summary -Level $(if ($summary -like 'Keine*') { 'Ok' } else { 'Warn' })
        return [pscustomobject]@{ Success = ($result.ExitCode -eq 0); Summary = $summary }
    } finally {
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WzDismRepair {
    <#
    .SYNOPSIS
        Prüft und repariert das Windows-Abbild.
    #>
    param([ValidateSet('ScanHealth', 'RestoreHealth')][string]$Action = 'RestoreHealth')

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] dism /Online /Cleanup-Image /$Action" -Level Test
        return [pscustomobject]@{ Success = $true; Summary = 'Testmodus' }
    }

    Write-WzLog "Windows-Abbild wird geprüft ($Action) — das dauert 5 bis 20 Minuten..." -Level Action
    $result = Invoke-WzProcess -FilePath 'dism.exe' -Arguments "/Online /Cleanup-Image /$Action /NoRestart" -TimeoutSeconds 3600

    $summary = switch ($result.ExitCode) {
        0     { 'Das Windows-Abbild ist in Ordnung.' }
        87    { 'Der Befehl wurde nicht erkannt — diese Windows-Version kennt die Option nicht.' }
        default { "DISM endete mit Code $($result.ExitCode). Einzelheiten in %windir%\Logs\DISM\dism.log." }
    }

    Write-WzLog $summary -Level $(if ($result.ExitCode -eq 0) { 'Ok' } else { 'Warn' })
    return [pscustomobject]@{ Success = ($result.ExitCode -eq 0); Summary = $summary }
}

function Invoke-WzChkdsk {
    <#
    .SYNOPSIS
        Prüft das Dateisystem im laufenden Betrieb (ohne Neustart).
    #>
    param([string]$Drive = $env:SystemDrive)

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] chkdsk $Drive /scan" -Level Test
        return [pscustomobject]@{ Success = $true; Summary = 'Testmodus' }
    }

    Write-WzLog "Dateisystem von $Drive wird geprüft..." -Level Action
    $result = Invoke-WzProcess -FilePath 'chkdsk.exe' -Arguments "$Drive /scan /perf" -TimeoutSeconds 3600

    $summary = switch ($result.ExitCode) {
        0 { 'Keine Fehler im Dateisystem gefunden.' }
        1 { 'Fehler gefunden und behoben.' }
        2 { 'Aufräumarbeiten nötig — Prüfung mit Neustart einplanen.' }
        3 { 'Fehler gefunden, die einen Neustart zur Reparatur brauchen.' }
        default { "Prüfung endete mit Code $($result.ExitCode)." }
    }

    Write-WzLog $summary -Level $(if ($result.ExitCode -le 1) { 'Ok' } else { 'Warn' })
    return [pscustomobject]@{ Success = ($result.ExitCode -le 1); Summary = $summary }
}

function New-WzBatteryReport {
    <#
    .SYNOPSIS
        Akkubericht von Windows. Auf Desktop-PCs ohne Akku entfällt er.
    #>
    $outFile = Join-Path (Get-WzReportDir) "akku-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    $result = Invoke-WzProcess -FilePath 'powercfg.exe' -Arguments "/batteryreport /output `"$outFile`"" -TimeoutSeconds 120

    if ($result.ExitCode -eq 0 -and (Test-Path -LiteralPath $outFile)) {
        Write-WzLog "Akkubericht erstellt: $outFile" -Level Ok
        return $outFile
    }
    Write-WzLog 'Kein Akku vorhanden oder Bericht nicht erstellbar.' -Level Info
    return $null
}
