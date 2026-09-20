# HealthCheck — läuft das Gerät auch unter Last?
#
# Die Frage, die nach der Übergabe zurückkommt: »Seit Sie da waren, stürzt er
# unter Last ab.« Ein PC, der im Leerlauf sauber aussieht, sagt darüber nichts.
# Deshalb hier drei Messungen unter echter Belastung — Rechenwerk, Speicher
# und Datenträger — und die ehrliche Angabe, was sie NICHT ersetzen.

function Get-WzTemperatures {
    <#
    .SYNOPSIS
        Temperaturen aus den Wärmezonen des BIOS, sofern es welche meldet.
    .NOTES
        Viele Desktop-Boards melden gar nichts, und was sie melden, ist die
        Zone, nicht der Kern — dafür gibt es keine allgemeine Schnittstelle.
        Deshalb wird nichts geschätzt: Kommt keine Zahl, steht »nicht
        messbar« da und nicht eine erfundene.
    #>
    [CmdletBinding()]
    param()

    $zones = @()
    try {
        foreach ($zone in (Get-CimInstance -Namespace 'root/WMI' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)) {
            # Zehntelkelvin — 3002 sind 27,05 °C
            $celsius = [math]::Round(($zone.CurrentTemperature / 10) - 273.15, 1)
            if ($celsius -le 0 -or $celsius -gt 150) { continue }
            $zones += [pscustomobject]@{
                Name    = ($zone.InstanceName -replace '^.*_', '')
                Celsius = $celsius
            }
        }
    } catch { }

    return @($zones)
}

function Get-WzCpuClock {
    <#
    .SYNOPSIS
        Aktueller und höchster Takt in MHz.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ CurrentMhz = 0; MaxMhz = 0; LoadPercent = 0 }
    try {
        $cpu = Get-CimInstance -Query 'SELECT CurrentClockSpeed,MaxClockSpeed,LoadPercentage FROM Win32_Processor' -ErrorAction Stop |
            Select-Object -First 1
        $result.CurrentMhz = [int]$cpu.CurrentClockSpeed
        $result.MaxMhz = [int]$cpu.MaxClockSpeed
        $result.LoadPercent = [int]$cpu.LoadPercentage
    } catch { }
    return $result
}

function Invoke-WzCpuStress {
    <#
    .SYNOPSIS
        Lastet alle Kerne aus und misst dabei Takt und Temperatur.
    .DESCRIPTION
        Gesucht wird nicht die Rechenleistung, sondern die Drosselung: Fällt
        der Takt unter Last deutlich unter das, was der Prozessor kann, ist die
        Kühlung am Ende — verstaubter Lüfter, eingetrocknete Wärmeleitpaste,
        verstopftes Notebook. Genau das ist die Ursache hinter »er wird immer
        langsamer«, und im Leerlauf sieht man davon nichts.
    .PARAMETER Seconds
        Dauer der Belastung.
    #>
    [CmdletBinding()]
    param([int]$Seconds = 60)

    $result = [pscustomobject]@{
        Seconds       = $Seconds
        Cores         = [Environment]::ProcessorCount
        MaxMhz        = 0
        MinMhzOnLoad  = 0
        AvgMhzOnLoad  = 0
        StartCelsius  = $null
        PeakCelsius   = $null
        Throttled     = $false
        Samples       = 0
        Verdict       = ''
        Ok            = $true
    }

    $start = Get-WzTemperatures
    if ($start.Count -gt 0) {
        $result.StartCelsius = ($start | Measure-Object -Property Celsius -Maximum).Maximum
    }

    $clock = Get-WzCpuClock
    $result.MaxMhz = $clock.MaxMhz

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'health.logCpuTest' @{ sekunden = $Seconds }) -Level Test
        $result.Verdict = Get-WzText 'core.dryRunSummary'
        return $result
    }

    Write-WzLog (Get-WzText 'health.logCpuRunning' @{ sekunden = $Seconds; kerne = $result.Cores }) -Level Action

    # Je Kern ein eigener Faden. Bewusst reine Rechenarbeit ohne Speicher- oder
    # Dateizugriff: Sonst misst man die Platte mit und nicht die Kühlung.
    $workers = @()
    $deadline = (Get-Date).AddSeconds($Seconds)
    try {
        for ($index = 0; $index -lt $result.Cores; $index++) {
            $worker = [powershell]::Create()
            [void]$worker.AddScript({
                param($until)
                $value = 0.0
                while ((Get-Date) -lt $until) {
                    for ($step = 0; $step -lt 200000; $step++) { $value = [math]::Sqrt($value + $step) }
                }
            }).AddArgument($deadline)
            $workers += [pscustomobject]@{ Shell = $worker; Handle = $worker.BeginInvoke() }
        }

        # Während die Kerne rechnen, alle zwei Sekunden Takt und Wärme ablesen
        $clocks = @()
        $peak = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 2000
            $sample = Get-WzCpuClock
            if ($sample.CurrentMhz -gt 0) { $clocks += $sample.CurrentMhz }
            $temperatures = Get-WzTemperatures
            if ($temperatures.Count -gt 0) {
                $highest = ($temperatures | Measure-Object -Property Celsius -Maximum).Maximum
                if ($null -eq $peak -or $highest -gt $peak) { $peak = $highest }
            }
        }

        $result.Samples = $clocks.Count
        if ($clocks.Count -gt 0) {
            $result.MinMhzOnLoad = ($clocks | Measure-Object -Minimum).Minimum
            $result.AvgMhzOnLoad = [int](($clocks | Measure-Object -Average).Average)
        }
        $result.PeakCelsius = $peak
    } finally {
        foreach ($worker in $workers) {
            try { [void]$worker.Shell.EndInvoke($worker.Handle) } catch { }
            try { $worker.Shell.Dispose() } catch { }
        }
    }

    # Unter 70 Prozent des Grundtakts über die ganze Messung hinweg ist kein
    # Sparmodus mehr, sondern Drosselung. Der Grundtakt ist die Bezugsgröße,
    # nicht der Turbotakt — den hält ohnehin kein Gerät dauerhaft.
    if ($result.MaxMhz -gt 0 -and $result.AvgMhzOnLoad -gt 0) {
        $share = $result.AvgMhzOnLoad / $result.MaxMhz
        $result.Throttled = ($share -lt 0.7)
    }

    $result.Verdict = if ($result.AvgMhzOnLoad -eq 0) {
        Get-WzText 'health.cpuNoClock'
    } elseif ($result.Throttled) {
        $result.Ok = $false
        Get-WzText 'health.cpuThrottled' @{ takt = $result.AvgMhzOnLoad; max = $result.MaxMhz }
    } else {
        Get-WzText 'health.cpuFine' @{ takt = $result.AvgMhzOnLoad; max = $result.MaxMhz }
    }

    # Über 90 Grad wird abgeriegelt, lange bevor etwas kaputtgeht — aber es ist
    # der Punkt, an dem man den Lüfter aufmacht.
    if ($null -ne $result.PeakCelsius -and $result.PeakCelsius -ge 90) {
        $result.Ok = $false
        $result.Verdict += ' ' + (Get-WzText 'health.cpuHot' @{ grad = $result.PeakCelsius })
    }

    Write-WzLog $result.Verdict -Level $(if ($result.Ok) { 'Ok' } else { 'Warn' })
    return $result
}

function Invoke-WzMemoryTest {
    <#
    .SYNOPSIS
        Schreibt Muster in den Arbeitsspeicher und liest sie zurück.
    .DESCRIPTION
        Das ist ausdrücklich KEIN Speichertest im Sinne von memtest86: Geprüft
        wird nur der Teil, den Windows gerade hergibt, und zwar aus einem
        laufenden System heraus. Ein Fehler hier ist ein sicherer Befund; kein
        Fehler hier ist keine Entwarnung. Dafür gibt es die Windows-eigene
        Speicherdiagnose, die vor dem Systemstart läuft.
    .PARAMETER PercentOfFree
        Anteil des freien Speichers, der geprüft wird.
    #>
    [CmdletBinding()]
    param([int]$PercentOfFree = 25)

    $result = [pscustomobject]@{
        TestedBytes = [int64]0
        Blocks      = 0
        Errors      = 0
        Verdict     = ''
        Ok          = $true
    }

    $freeBytes = [int64]0
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $freeBytes = [int64]$os.FreePhysicalMemory * 1024
    } catch { }

    if ($freeBytes -le 0) {
        $result.Verdict = Get-WzText 'health.memNoReading'
        return $result
    }

    # Blockweise statt am Stück: Ein einzelner Block von mehreren Gigabyte
    # würde die Auslagerungsdatei beschäftigen statt den Speicher, und genau
    # das soll er nicht.
    $blockBytes = 64MB
    $budget = [int64]($freeBytes * $PercentOfFree / 100)
    $blocks = [int]([math]::Floor($budget / $blockBytes))
    if ($blocks -lt 1) {
        $result.Verdict = Get-WzText 'health.memTooLittle'
        return $result
    }
    if ($blocks -gt 32) { $blocks = 32 }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'health.logMemTest' @{ groesse = (Format-WzBytes ($blocks * $blockBytes)) }) -Level Test
        $result.Verdict = Get-WzText 'core.dryRunSummary'
        return $result
    }

    Write-WzLog (Get-WzText 'health.logMemRunning' @{ groesse = (Format-WzBytes ($blocks * $blockBytes)) }) -Level Action

    # Das Muster ist klein und bleibt die Referenz. Gegen eine Kopie zu
    # vergleichen wäre wertlos: Sie läge im selben Speicher und trüge denselben
    # Fehler. Vervielfältigt wird es blockweise über Buffer.BlockCopy — eine
    # Schleife über 64 Millionen Bytes wäre in PowerShell nicht zu bezahlen.
    $patternSize = 4096
    $pattern = New-Object byte[] $patternSize
    (New-Object Random(12345)).NextBytes($pattern)

    for ($index = 0; $index -lt $blocks; $index++) {
        $buffer = $null
        try {
            $buffer = New-Object byte[] $blockBytes
            for ($offset = 0; $offset -lt $blockBytes; $offset += $patternSize) {
                [Buffer]::BlockCopy($pattern, 0, $buffer, $offset, $patternSize)
            }

            # Geprüft wird jeder 997. Wert — eine Primzahl, damit die
            # Schrittweite nicht mit der Mustergröße zusammenfällt und immer
            # dieselben Stellen im Muster trifft.
            for ($position = 0; $position -lt $blockBytes; $position += 997) {
                if ($buffer[$position] -ne $pattern[$position % $patternSize]) { $result.Errors++ }
            }

            $result.TestedBytes += $blockBytes
            $result.Blocks++
        } catch {
            Write-WzLog (Get-WzText 'health.logMemBlockFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
            break
        } finally {
            $buffer = $null
        }
    }
    [GC]::Collect()

    $result.Ok = ($result.Errors -eq 0)
    $result.Verdict = if ($result.Errors -gt 0) {
        Get-WzText 'health.memErrors' @{ anzahl = $result.Errors }
    } else {
        Get-WzText 'health.memOk' @{ groesse = (Format-WzBytes $result.TestedBytes) }
    }

    Write-WzLog $result.Verdict -Level $(if ($result.Ok) { 'Ok' } else { 'Error' })
    return $result
}

function Invoke-WzDiskSpeedTest {
    <#
    .SYNOPSIS
        Misst, wie schnell das Systemlaufwerk schreibt und liest.
    .DESCRIPTION
        Beide Richtungen am Zwischenspeicher vorbei: Beim Schreiben über
        WriteThrough, beim Lesen ohne Puffer. Ohne das misst man den
        Arbeitsspeicher und bekommt für jede Platte Traumwerte.

        Der Wert ist die Zahl, die im Übergabeblatt etwas aussagt — eine
        Festplatte mit 80 MB/s gegen eine SSD mit 500 erklärt dem Kunden das
        Angebot besser als jede Beschreibung.
    #>
    [CmdletBinding()]
    param([int]$SizeMb = 256)

    $result = [pscustomobject]@{
        SizeMb       = $SizeMb
        WriteMbPerS  = 0
        ReadMbPerS   = 0
        Verdict      = ''
        Ok           = $true
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'health.logDiskTest' @{ groesse = $SizeMb }) -Level Test
        $result.Verdict = Get-WzText 'core.dryRunSummary'
        return $result
    }

    # Auf dem Systemlaufwerk, nicht auf dem Stick: Gefragt ist die Platte, mit
    # der der Kunde arbeitet.
    $folder = Join-Path $env:TEMP 'WinZii-Tempo'
    [void](New-WzDirectory $folder)
    $file = Join-Path $folder 'messung.bin'

    # 4-MB-Puffer, ein Vielfaches von 4096: Ohne Puffer verlangt Windows, dass
    # Größe und Lage an Sektorgrenzen ausgerichtet sind.
    $bufferSize = 4MB
    $buffer = New-Object byte[] $bufferSize
    (New-Object Random(7)).NextBytes($buffer)
    $rounds = [int]($SizeMb * 1MB / $bufferSize)

    Write-WzLog (Get-WzText 'health.logDiskRunning' @{ groesse = $SizeMb }) -Level Action

    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $stream = New-Object IO.FileStream($file, [IO.FileMode]::Create, [IO.FileAccess]::Write,
            [IO.FileShare]::None, $bufferSize, [IO.FileOptions]::WriteThrough)
        try {
            for ($index = 0; $index -lt $rounds; $index++) { $stream.Write($buffer, 0, $bufferSize) }
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        $watch.Stop()
        if ($watch.Elapsed.TotalSeconds -gt 0) {
            $result.WriteMbPerS = [int]($SizeMb / $watch.Elapsed.TotalSeconds)
        }

        # 0x20000000 ist FILE_FLAG_NO_BUFFERING. Es gibt dafür keinen Namen in
        # der .NET-Aufzählung, aber ohne die Angabe liest der Durchgang die
        # eben geschriebenen Daten aus dem Arbeitsspeicher zurück.
        $noBuffering = [IO.FileOptions]0x20000000
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $stream = New-Object IO.FileStream($file, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            [IO.FileShare]::None, $bufferSize, ($noBuffering -bor [IO.FileOptions]::SequentialScan))
        try {
            while ($stream.Read($buffer, 0, $bufferSize) -gt 0) { }
        } finally { $stream.Dispose() }
        $watch.Stop()
        if ($watch.Elapsed.TotalSeconds -gt 0) {
            $result.ReadMbPerS = [int]($SizeMb / $watch.Elapsed.TotalSeconds)
        }
    } catch {
        $result.Ok = $false
        $result.Verdict = Get-WzText 'health.diskFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }
        Write-WzLog $result.Verdict -Level Warn
        return $result
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }

    # Unter 100 MB/s schreibend ist es eine Festplatte oder eine SSD am Ende.
    # Welches von beidem, sagt der Datenträgertyp auf dem Dashboard.
    $result.Verdict = if ($result.WriteMbPerS -lt 100) {
        $result.Ok = $false
        Get-WzText 'health.diskSlow' @{ schreiben = $result.WriteMbPerS; lesen = $result.ReadMbPerS }
    } else {
        Get-WzText 'health.diskFine' @{ schreiben = $result.WriteMbPerS; lesen = $result.ReadMbPerS }
    }

    Write-WzLog $result.Verdict -Level $(if ($result.Ok) { 'Ok' } else { 'Warn' })
    return $result
}

function Invoke-WzHealthCheck {
    <#
    .SYNOPSIS
        Die drei Messungen nacheinander, mit einem Gesamturteil.
    .PARAMETER CpuSeconds
        Dauer der Prozessorbelastung.
    #>
    [CmdletBinding()]
    param(
        [int]$CpuSeconds = 60,
        [switch]$SkipMemory,
        [switch]$SkipDisk
    )

    $check = [pscustomobject]@{
        Started  = Get-Date
        Cpu      = $null
        Memory   = $null
        Disk     = $null
        Ok       = $true
        Warnings = @()
    }

    $check.Cpu = Invoke-WzCpuStress -Seconds $CpuSeconds
    if (-not $check.Cpu.Ok) { $check.Warnings += $check.Cpu.Verdict }

    if (-not $SkipMemory) {
        $check.Memory = Invoke-WzMemoryTest
        if (-not $check.Memory.Ok) { $check.Warnings += $check.Memory.Verdict }
    }

    if (-not $SkipDisk) {
        $check.Disk = Invoke-WzDiskSpeedTest
        if (-not $check.Disk.Ok) { $check.Warnings += $check.Disk.Verdict }
    }

    $check.Ok = ($check.Warnings.Count -eq 0)

    # Für das Übergabeblatt: Der Bericht fragt diesen Stand ab, statt dass die
    # Seite ihn dorthin durchreichen müsste.
    $syncHash.HealthCheck = $check

    return $check
}
