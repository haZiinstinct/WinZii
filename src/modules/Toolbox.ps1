# Toolbox — die Handgriffe, die im Technikeralltag immer wieder gebraucht werden.

function Invoke-WzNetworkReset {
    <#
    .SYNOPSIS
        Setzt den Netzwerkstapel zurück: Winsock, IP-Konfiguration, DNS-Cache
        und Proxy-Einstellungen. Danach ist ein Neustart nötig.
    #>
    param(
        [switch]$Winsock,
        [switch]$IpStack,
        [switch]$FlushDns,
        [switch]$ResetProxy
    )

    $steps = @()
    if ($Winsock) { $steps += @{ Name = (Get-WzText 'tool.stepWinsock'); File = 'netsh.exe'; Args = 'winsock reset' } }
    if ($IpStack) {
        $steps += @{ Name = (Get-WzText 'tool.stepIpv4'); File = 'netsh.exe'; Args = 'int ip reset' }
        $steps += @{ Name = (Get-WzText 'tool.stepIpv6'); File = 'netsh.exe'; Args = 'int ipv6 reset' }
    }
    if ($FlushDns) { $steps += @{ Name = (Get-WzText 'tool.stepFlushDns'); File = 'ipconfig.exe'; Args = '/flushdns' } }
    if ($ResetProxy) { $steps += @{ Name = (Get-WzText 'tool.stepProxy'); File = 'netsh.exe'; Args = 'winhttp reset proxy' } }

    $result = [pscustomobject]@{ Done = 0; Failed = 0; RebootRequired = ($Winsock -or $IpStack) }

    foreach ($step in $steps) {
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'tool.logTestStep' @{ schritt = $step.Name }) -Level Test
            continue
        }
        Write-WzLog $step.Name -Level Action
        $processResult = Invoke-WzProcess -FilePath $step.File -Arguments $step.Args -TimeoutSeconds 120
        if ($processResult.ExitCode -eq 0) {
            $result.Done++
            Write-WzLog (Get-WzText 'tool.logStepDone') -Level Ok
        } else {
            $result.Failed++
            Write-WzLog (Get-WzText 'tool.logStepFailed' @{ code = $processResult.ExitCode }) -Level Warn
        }
    }

    return $result
}

function Save-WzDnsState {
    <#
    .SYNOPSIS
        Schreibt die aktuelle DNS-Konfiguration aller Netzwerkkarten in den
        Sicherungsordner und gibt den Dateipfad zurück.
    .NOTES
        Set-DnsClientServerAddress kennt keinen Rückweg: »Auto« stellt auf DHCP um,
        und ein von Hand eingetragener Server ist damit weg. Diese Datei ist der
        einzige Weg zurück — deshalb läuft sie vor jeder Änderung.
    #>
    [CmdletBinding()]
    param()

    $lines = @(
        (Get-WzText 'tool.dnsBackupHeader')
        (Get-WzText 'core.fileComputer' @{ name = $env:COMPUTERNAME })
        (Get-WzText 'core.fileTimestamp' @{ zeit = (Get-Date).ToString('G', (Get-WzLanguageCulture)) })
        ''
    )
    $found = 0

    try {
        foreach ($entry in (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop)) {
            $addresses = @($entry.ServerAddresses)
            $lines += "$($entry.InterfaceAlias) (Index $($entry.InterfaceIndex))"
            $lines += if ($addresses.Count -gt 0) {
                "  $($addresses -join ', ')"
            } else {
                (Get-WzText 'tool.dnsAuto')
            }
            $lines += (Get-WzText 'tool.dnsBackupRestore' @{ index = $entry.InterfaceIndex }) + $(
                if ($addresses.Count -gt 0) { "-ServerAddresses $($addresses -join ',')" } else { '-ResetServerAddresses' })
            $lines += ''
            $found++
        }
    } catch {
        Write-WzLog (Get-WzText 'tool.logDnsUnreadable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        return ''
    }

    if ($found -eq 0) { return '' }
    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'tool.logDnsBackupTest') -Level Test
        return ''
    }

    try {
        $target = Join-Path (Get-WzBackupDir -Stamp "$(Get-Date -Format 'yyyy-MM-dd_HHmmss')-dns") 'dns-vorher.txt'
        [IO.File]::WriteAllText($target, ($lines -join [Environment]::NewLine), [Text.Encoding]::UTF8)
        Write-WzLog (Get-WzText 'tool.logDnsBackupSaved' @{ ziel = $target }) -Level Ok
        return $target
    } catch {
        Write-WzLog (Get-WzText 'tool.logDnsBackupFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        return ''
    }
}

function Set-WzDnsServers {
    <#
    .SYNOPSIS
        Trägt DNS-Server auf allen aktiven Netzwerkkarten ein.
    .PARAMETER Provider
        Cloudflare, Quad9, Google oder Auto (Einstellungen des Routers).
    #>
    param([ValidateSet('Cloudflare', 'Quad9', 'Google', 'Auto')][string]$Provider)

    $servers = switch ($Provider) {
        'Cloudflare' { @('1.1.1.1', '1.0.0.1') }
        'Quad9'      { @('9.9.9.9', '149.112.112.112') }
        'Google'     { @('8.8.8.8', '8.8.4.4') }
        default      { @() }
    }

    $result = [pscustomobject]@{ Changed = 0; Failed = 0; Adapters = @(); BackupFile = '' }

    # Vor jeder Änderung den Vorzustand wegschreiben. »Auto« bedeutet DHCP — ein
    # fest eingetragener Firmen-DNS wäre danach unwiederbringlich weg, und der
    # Dialog hat früher trotzdem behauptet, das sei umkehrbar.
    $result.BackupFile = Save-WzDnsState

    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
    } catch {
        Write-WzLog (Get-WzText 'tool.logAdaptersUnreadable' @{ grund = $_.Exception.Message }) -Level Error
        return $result
    }

    foreach ($adapter in $adapters) {
        if ($syncHash.DryRun) {
            $target = if ($servers.Count -gt 0) { $servers -join ', ' } else { Get-WzText 'tool.dnsAuto' }
            Write-WzLog (Get-WzText 'tool.logTestDns' @{ adapter = $adapter.Name; ziel = $target }) -Level Test
            continue
        }

        try {
            if ($Provider -eq 'Auto') {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
                Write-WzLog (Get-WzText 'tool.logDnsRouter' @{ adapter = $adapter.Name }) -Level Ok
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
                Write-WzLog "$($adapter.Name): $($servers -join ', ')" -Level Ok
            }
            $result.Changed++
            $result.Adapters += $adapter.Name
        } catch {
            $result.Failed++
            Write-WzLog "$($adapter.Name): $($_.Exception.Message)" -Level Warn
        }
    }

    if (-not $syncHash.DryRun) {
        [void](Invoke-WzProcess -FilePath 'ipconfig.exe' -Arguments '/flushdns' -TimeoutSeconds 60)
    }
    return $result
}

function Repair-WzWindowsUpdate {
    <#
    .SYNOPSIS
        Setzt Windows Update zurück: Dienste anhalten, Zwischenspeicher
        umbenennen, Dienste starten. Die alten Ordner bleiben als .old
        erhalten, falls etwas schiefgeht.
    #>
    $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $result = [pscustomobject]@{ Success = $false; Renamed = @(); Messages = @() }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'tool.logWuTest') -Level Test
        $result.Success = $true
        return $result
    }

    Write-WzLog (Get-WzText 'tool.logStopUpdateServices') -Level Action
    foreach ($serviceName in $services) {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    $folders = @(
        @{ Path = Join-Path $env:SystemRoot 'SoftwareDistribution'; Name = 'SoftwareDistribution' }
        @{ Path = Join-Path $env:SystemRoot 'System32\catroot2'; Name = 'catroot2' }
    )

    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder.Path)) { continue }
        $newName = "$($folder.Name).old_$stamp"
        try {
            Rename-Item -LiteralPath $folder.Path -NewName $newName -ErrorAction Stop
            $result.Renamed += $newName
            Write-WzLog (Get-WzText 'tool.logFolderRenamed' @{ name = $folder.Name; neu = $newName }) -Level Ok
        } catch {
            $result.Messages += Get-WzText 'tool.msgFolderLocked' @{ name = $folder.Name }
            Write-WzLog (Get-WzText 'tool.logFolderRename' @{ name = $folder.Name; grund = $_.Exception.Message }) -Level Warn
        }
    }

    Write-WzLog (Get-WzText 'tool.logStartUpdateServices') -Level Action
    foreach ($serviceName in $services) {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    }

    $result.Success = ($result.Renamed.Count -gt 0)
    if ($result.Success) {
        $result.Messages += Get-WzText 'tool.msgFoldersRecreated'
    }
    return $result
}

function Repair-WzSpooler {
    <#
    .SYNOPSIS
        Behebt hängende Druckaufträge: Warteschlange leeren und Dienst neu starten.
    #>
    $result = [pscustomobject]@{ Success = $false; Removed = 0 }
    $spoolPath = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'

    if ($syncHash.DryRun) {
        $jobs = @(Get-ChildItem -LiteralPath $spoolPath -File -ErrorAction SilentlyContinue)
        Write-WzLog (Get-WzText 'tool.logSpoolerTest' @{ anzahl = $jobs.Count }) -Level Test
        $result.Success = $true
        return $result
    }

    try {
        Write-WzLog (Get-WzText 'tool.logStopSpooler') -Level Action
        Stop-Service -Name 'Spooler' -Force -ErrorAction Stop
        Start-Sleep -Seconds 1

        $jobs = @(Get-ChildItem -LiteralPath $spoolPath -File -ErrorAction SilentlyContinue)
        foreach ($job in $jobs) {
            try {
                Remove-Item -LiteralPath $job.FullName -Force -ErrorAction Stop
                $result.Removed++
            } catch { }
        }

        Start-Service -Name 'Spooler' -ErrorAction Stop
        Write-WzLog (Get-WzText 'tool.logSpoolerDone' @{ anzahl = $result.Removed }) -Level Ok
        $result.Success = $true
    } catch {
        Write-WzLog (Get-WzText 'tool.logSpoolerError' @{ grund = $_.Exception.Message }) -Level Error
        Start-Service -Name 'Spooler' -ErrorAction SilentlyContinue
    }

    return $result
}

function Repair-WzNetworkAdapter {
    <#
    .SYNOPSIS
        Aktualisiert IP-Adresse und DNS-Registrierung, ohne den Stapel
        zurückzusetzen — der schnelle erste Versuch bei Verbindungsproblemen.
    #>
    $steps = @(
        @{ Name = (Get-WzText 'tool.stepIpRelease'); File = 'ipconfig.exe'; Args = '/release' }
        @{ Name = (Get-WzText 'tool.stepIpRenew'); File = 'ipconfig.exe'; Args = '/renew' }
        @{ Name = (Get-WzText 'tool.stepFlushDns'); File = 'ipconfig.exe'; Args = '/flushdns' }
        @{ Name = (Get-WzText 'tool.stepDnsRegister'); File = 'ipconfig.exe'; Args = '/registerdns' }
    )

    $result = [pscustomobject]@{ Done = 0; Failed = 0 }
    foreach ($step in $steps) {
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'tool.logTestStep' @{ schritt = $step.Name }) -Level Test
            continue
        }
        Write-WzLog $step.Name -Level Action
        $processResult = Invoke-WzProcess -FilePath $step.File -Arguments $step.Args -TimeoutSeconds 120
        if ($processResult.ExitCode -eq 0) { $result.Done++ } else { $result.Failed++ }
    }
    return $result
}

function Get-WzBloatwareList {
    <#
    .SYNOPSIS
        Vorinstallierte Apps, die auf Kundenrechnern selten gebraucht werden.
    .PARAMETER Level
        safe = unstrittig entfernbar, extended = zusätzlich Xbox und Medien-Apps.
    #>
    param([ValidateSet('safe', 'extended')][string]$Level = 'safe')

    $catalog = Get-WzCatalog -Name 'bloatware'
    $patterns = @($catalog.safe)
    if ($Level -eq 'extended') { $patterns += @($catalog.extended) }

    $found = @()
    foreach ($package in (Get-WzAllAppxPackages)) {
        foreach ($entry in $patterns) {
            if ($package.Name -like $entry.pattern) {
                $found += [pscustomobject]@{
                    Name        = $package.Name
                    DisplayName = $entry.name
                    Description = $entry.description
                    FullName    = $package.PackageFullName
                    Pattern     = $entry.pattern
                }
                break
            }
        }
    }

    return @($found | Sort-Object DisplayName -Unique)
}

function Remove-WzBloatware {
    <#
    .SYNOPSIS
        Entfernt die übergebenen Apps für alle Benutzer und aus der
        Bereitstellung für neue Konten.
    #>
    param([Parameter(Mandatory = $true)]$Packages)

    $result = [pscustomobject]@{ Removed = 0; Failed = 0; RecordFile = '' }
    $removed = @()

    foreach ($package in $Packages) {
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'tool.logBloatTest' @{ name = $package.DisplayName }) -Level Test
            continue
        }

        try {
            Remove-AppxPackage -Package $package.FullName -AllUsers -ErrorAction Stop
            $result.Removed++
            $removed += $package
                Write-WzLog (Get-WzText 'tool.logAppxRemoved' @{ name = $package.DisplayName }) -Level Ok
        } catch {
            $result.Failed++
            Write-WzLog "$($package.DisplayName): $($_.Exception.Message)" -Level Warn
        }

        try {
            $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                Where-Object { $_.DisplayName -like $package.Pattern }
            foreach ($item in $provisioned) {
                Remove-AppxProvisionedPackage -Online -PackageName $item.PackageName -ErrorAction Stop | Out-Null
            }
        } catch { }
    }

    $script:WzAppxCache = $null
    $result.RecordFile = Save-WzRemovedAppsRecord -Packages $removed
    $result | Add-Member -NotePropertyName 'RemovedNames' -NotePropertyValue @($removed | ForEach-Object { $_.DisplayName }) -Force
    return $result
}

function Save-WzRemovedAppsRecord {
    <#
    .SYNOPSIS
        Hält fest, welche mitgelieferten Apps entfernt wurden.
    .NOTES
        Anders als bei den Optimierungen gibt es hier keine Rücknahme per Knopfdruck:
        Ein entferntes Appx-Paket lässt sich nur über den Store oder das
        Windows-Abbild zurückholen. Ohne diese Liste wüsste hinterher niemand mehr,
        was überhaupt weg ist — auch nicht, wenn der Kunde eine App vermisst.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Packages)

    $list = @($Packages)
    if ($list.Count -eq 0) { return '' }

    $lines = @(
        (Get-WzText 'tool.recordHeader')
        (Get-WzText 'core.fileComputer' @{ name = $env:COMPUTERNAME })
        (Get-WzText 'core.fileTimestamp' @{ zeit = (Get-Date).ToString('G', (Get-WzLanguageCulture)) })
        ''
        (Get-WzText 'tool.recordRestore')
        ''
    )
    foreach ($package in $list) {
        $lines += $package.DisplayName
        $lines += "  $($package.FullName)"
        $lines += ''
    }

    try {
        $target = Join-Path (Get-WzBackupDir -Stamp "$(Get-Date -Format 'yyyy-MM-dd_HHmmss')-apps") 'entfernte-apps.txt'
        [IO.File]::WriteAllText($target, ($lines -join [Environment]::NewLine), [Text.Encoding]::UTF8)
        Write-WzLog (Get-WzText 'tool.logRecordSaved' @{ ziel = $target }) -Level Ok
        return $target
    } catch {
        Write-WzLog (Get-WzText 'tool.logRecordFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        return ''
    }
}

function Sync-WzSystemTime {
    <#
    .SYNOPSIS
        Startet den Zeitdienst und synchronisiert die Systemzeit automatisch
        mit dem Zeitserver.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ Success = $false; Summary = ''; Source = ''; Time = $null }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'tool.logTimeTest') -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    Write-WzLog (Get-WzText 'tool.logTimeRunning') -Level Action

    try {
        Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction Stop
        Start-Service -Name 'W32Time' -ErrorAction Stop
    } catch {
        Write-WzLog (Get-WzText 'tool.logTimeService' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    $resync = Invoke-WzProcess -FilePath 'w32tm.exe' -Arguments '/resync /force' -TimeoutSeconds 60 -LogOutput
    $result.Success = ($resync.ExitCode -eq 0)

    $source = Invoke-WzProcess -FilePath 'w32tm.exe' -Arguments '/query /source' -TimeoutSeconds 20
    if ($source.ExitCode -eq 0 -and $source.StdOut) { $result.Source = $source.StdOut.Trim() }

    $result.Time = Get-Date
    $result.Summary = if ($result.Success) {
        Get-WzText 'tool.timeSynced' @{ zeit = $result.Time.ToString('G', (Get-WzLanguageCulture)); quelle = $result.Source }
    } else {
        Get-WzText 'tool.timeFailed' @{ code = $resync.ExitCode }
    }

    Write-WzLog $result.Summary -Level $(if ($result.Success) { 'Ok' } else { 'Warn' })
    return $result
}

function Get-WzOemProductKey {
    <#
    .SYNOPSIS
        Liest den im UEFI/BIOS hinterlegten Windows-Produktschlüssel (OA3),
        falls das Gerät einen besitzt.
    #>
    [CmdletBinding()]
    param()

    try {
        $service = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
        if ($service.OA3xOriginalProductKey) { return $service.OA3xOriginalProductKey }
    } catch { }
    return ''
}

function Invoke-WzFirmwareActivation {
    <#
    .SYNOPSIS
        Aktiviert Windows vollautomatisch mit dem in der Firmware (UEFI/BIOS)
        hinterlegten Produktschlüssel — ohne manuelle Schlüsseleingabe.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ Success = $false; Activated = $false; Summary = '' }

    $key = Get-WzOemProductKey
    if (-not $key) {
        $result.Summary = Get-WzText 'tool.firmwareNoKey'
        Write-WzLog $result.Summary -Level Warn
        return $result
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'tool.logFirmwareTest') -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    Write-WzLog (Get-WzText 'tool.logFirmwareInstalling') -Level Action
    $install = Invoke-WzProcess -FilePath 'cscript.exe' `
        -Arguments "//nologo `"$slmgr`" /ipk $key" -TimeoutSeconds 180
    if ($install.ExitCode -ne 0) {
        $code = if ($null -ne $install.ExitCode) { '0x{0:X8}' -f [int]$install.ExitCode } else { '?' }
        $result.Summary = Get-WzText 'tool.firmwareInstallFailed' @{ code = $code }
        Write-WzLog $result.Summary -Level Error
        return $result
    }

    Write-WzLog (Get-WzText 'tool.logFirmwareActivating') -Level Action
    $activate = Invoke-WzProcess -FilePath 'cscript.exe' `
        -Arguments "//nologo `"$slmgr`" /ato" -TimeoutSeconds 300

    $status = Get-WzActivationStatus
    $result.Activated = (($activate.ExitCode -eq 0) -and $status.Ok)
    $result.Success = $true
    $result.Summary = if ($result.Activated) {
        Get-WzText 'tool.firmwareActivated'
    } else {
        Get-WzText 'tool.firmwareNotActive' @{ status = $status.Text }
    }

    Write-WzLog $result.Summary -Level $(if ($result.Activated) { 'Ok' } else { 'Warn' })
    return $result
}
