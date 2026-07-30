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
    if ($Winsock) { $steps += @{ Name = 'Winsock zurücksetzen'; File = 'netsh.exe'; Args = 'winsock reset' } }
    if ($IpStack) {
        $steps += @{ Name = 'IPv4 zurücksetzen'; File = 'netsh.exe'; Args = 'int ip reset' }
        $steps += @{ Name = 'IPv6 zurücksetzen'; File = 'netsh.exe'; Args = 'int ipv6 reset' }
    }
    if ($FlushDns) { $steps += @{ Name = 'DNS-Zwischenspeicher leeren'; File = 'ipconfig.exe'; Args = '/flushdns' } }
    if ($ResetProxy) { $steps += @{ Name = 'Proxy zurücksetzen'; File = 'netsh.exe'; Args = 'winhttp reset proxy' } }

    $result = [pscustomobject]@{ Done = 0; Failed = 0; RebootRequired = ($Winsock -or $IpStack) }

    foreach ($step in $steps) {
        if ($syncHash.DryRun) {
            Write-WzLog "[Test] $($step.Name)" -Level Test
            continue
        }
        Write-WzLog $step.Name -Level Action
        $processResult = Invoke-WzProcess -FilePath $step.File -Arguments $step.Args -TimeoutSeconds 120
        if ($processResult.ExitCode -eq 0) {
            $result.Done++
            Write-WzLog "  erledigt" -Level Ok
        } else {
            $result.Failed++
            Write-WzLog "  fehlgeschlagen (Code $($processResult.ExitCode))" -Level Warn
        }
    }

    return $result
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

    $result = [pscustomobject]@{ Changed = 0; Failed = 0; Adapters = @() }

    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
    } catch {
        Write-WzLog "Netzwerkkarten nicht abfragbar: $($_.Exception.Message)" -Level Error
        return $result
    }

    foreach ($adapter in $adapters) {
        if ($syncHash.DryRun) {
            $target = if ($servers.Count -gt 0) { $servers -join ', ' } else { 'automatisch' }
            Write-WzLog "[Test] $($adapter.Name) -> $target" -Level Test
            continue
        }

        try {
            if ($Provider -eq 'Auto') {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
                Write-WzLog "$($adapter.Name): DNS vom Router" -Level Ok
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
        Write-WzLog '[Test] Windows-Update-Zwischenspeicher würde zurückgesetzt' -Level Test
        $result.Success = $true
        return $result
    }

    Write-WzLog 'Halte Update-Dienste an...' -Level Action
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
            Write-WzLog "  $($folder.Name) umbenannt in $newName" -Level Ok
        } catch {
            $result.Messages += "$($folder.Name) ist gesperrt und blieb unverändert"
            Write-WzLog "  $($folder.Name) konnte nicht umbenannt werden: $($_.Exception.Message)" -Level Warn
        }
    }

    Write-WzLog 'Starte Update-Dienste...' -Level Action
    foreach ($serviceName in $services) {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    }

    $result.Success = ($result.Renamed.Count -gt 0)
    if ($result.Success) {
        $result.Messages += 'Windows legt die Ordner beim nächsten Update neu an. Die alten Ordner können nach ein paar Tagen gelöscht werden.'
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
        Write-WzLog "[Test] $($jobs.Count) Druckauftrag/-aufträge würden entfernt" -Level Test
        $result.Success = $true
        return $result
    }

    try {
        Write-WzLog 'Halte Druckwarteschlange an...' -Level Action
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
        Write-WzLog "$($result.Removed) hängende(r) Druckauftrag/-aufträge entfernt, Dienst neu gestartet" -Level Ok
        $result.Success = $true
    } catch {
        Write-WzLog "Druckwarteschlange: $($_.Exception.Message)" -Level Error
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
        @{ Name = 'IP-Adresse freigeben'; File = 'ipconfig.exe'; Args = '/release' }
        @{ Name = 'IP-Adresse neu anfordern'; File = 'ipconfig.exe'; Args = '/renew' }
        @{ Name = 'DNS-Zwischenspeicher leeren'; File = 'ipconfig.exe'; Args = '/flushdns' }
        @{ Name = 'DNS neu registrieren'; File = 'ipconfig.exe'; Args = '/registerdns' }
    )

    $result = [pscustomobject]@{ Done = 0; Failed = 0 }
    foreach ($step in $steps) {
        if ($syncHash.DryRun) {
            Write-WzLog "[Test] $($step.Name)" -Level Test
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

    $result = [pscustomobject]@{ Removed = 0; Failed = 0 }

    foreach ($package in $Packages) {
        if ($syncHash.DryRun) {
            Write-WzLog "[Test] $($package.DisplayName) würde entfernt" -Level Test
            continue
        }

        try {
            Remove-AppxPackage -Package $package.FullName -AllUsers -ErrorAction Stop
            $result.Removed++
            Write-WzLog "$($package.DisplayName) entfernt" -Level Ok
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
    return $result
}
