# Seite "Dashboard" — Systemübersicht.
# Zweistufig: die schnellen Daten stehen sofort, Lizenz/Verschlüsselung/
# Virenschutz werden danach im Hintergrund nachgeladen (siehe Core.System).

function Initialize-WzDashboardPage {
    $syncHash.DashBtnDiagnose.Add_Click({ Show-WzPage -Id 'Diagnostics' })
    $syncHash.DashBtnCleanup.Add_Click({ Show-WzPage -Id 'Cleanup' })
    $syncHash.DashBtnOptimize.Add_Click({ Show-WzPage -Id 'Optimizer' })
    $syncHash.DashBtnAi.Add_Click({ Show-WzPage -Id 'AiRemoval' })
    $syncHash.DashBtnRefresh.Add_Click({ Update-WzDashboardPage -Force })
}

function Update-WzDashboardPage {
    param([switch]$Force)

    if ($syncHash.SystemInfo -and -not $Force) {
        Write-WzDashboardCards -Info $syncHash.SystemInfo
        if ($syncHash.SecurityInfo) { Write-WzDashboardSecurity -Security $syncHash.SecurityInfo }
        return
    }

    if ($Force) {
        $syncHash.SystemInfo = $null
        $syncHash.SecurityInfo = $null
    }

    Invoke-WzTask -Name 'Systemdaten einlesen' -Silent -ScriptBlock {
        Get-WzSystemInfo
    } -OnComplete {
        param($info)
        if (-not $info) {
            Write-WzLog 'Systemdaten konnten nicht gelesen werden.' -Level Error
            return
        }
        $syncHash.SystemInfo = $info
        Write-WzDashboardCards -Info $info
        Write-WzLog "$($info.OsCaption) · Version $($info.OsVersion) · Build $($info.OsBuild)" -Level Info

        # Stufe 2 anstoßen (Lizenz, BitLocker, Virenschutz, Laufwerkszustand)
        Invoke-WzTask -Name 'Sicherheitsstatus prüfen' -Silent -ScriptBlock {
            Get-WzSecurityInfo
        } -OnComplete {
            param($security)
            if (-not $security) { return }
            $syncHash.SecurityInfo = $security
            Write-WzDashboardSecurity -Security $security
            Write-WzLog "Aktivierung: $($security.Activation) · BitLocker: $($security.BitLocker)" -Level Info
        }
    }
}

function Write-WzDashboardCards {
    param([Parameter(Mandatory = $true)]$Info)

    # --- Windows ----------------------------------------------------------
    $syncHash.DashOsTitle.Text = $Info.OsCaption
    $rows = $syncHash.DashOsRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow 'Version' "$($Info.OsVersion)  ·  Build $($Info.OsBuild)"))
    [void]$rows.Children.Add((New-WzInfoRow 'Edition' $Info.OsEdition))
    [void]$rows.Children.Add((New-WzInfoRow 'Architektur' $Info.OsArchitecture))
    [void]$rows.Children.Add((New-WzInfoRow 'Sprache' $Info.OsLanguage))
    if ($Info.InstallDate) {
        $age = [math]::Round(((Get-Date) - $Info.InstallDate).TotalDays)
        [void]$rows.Children.Add((New-WzInfoRow 'Installiert' "$($Info.InstallDate.ToString('dd.MM.yyyy')) (vor $age Tagen)"))
    }

    # --- Hardware ---------------------------------------------------------
    $syncHash.DashHwTitle.Text = if ($Info.Model -and $Info.Model -ne 'n/v') {
        "$($Info.Manufacturer) $($Info.Model)".Trim()
    } else { 'Unbekanntes System' }
    $rows = $syncHash.DashHwRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow 'Prozessor' $Info.CpuName))
    [void]$rows.Children.Add((New-WzInfoRow 'Kerne' "$($Info.CpuCores) Kerne · $($Info.CpuThreads) Threads"))
    [void]$rows.Children.Add((New-WzInfoRow 'Arbeitsspeicher' (Format-WzBytes $Info.RamTotalBytes)))
    if ($Info.RamTotalBytes -gt 0) {
        [void]$rows.Children.Add((New-WzMeter -Percent $Info.RamUsedPercent `
            -Caption "$($Info.RamUsedPercent) % belegt · $(Format-WzBytes $Info.RamFreeBytes) frei"))
    }
    if ($Info.RamModules.Count -gt 0) {
        $speeds = ($Info.RamModules | Where-Object { $_.Speed } | Select-Object -ExpandProperty Speed -Unique) -join '/'
        $moduleText = "$($Info.RamModules.Count) Modul(e)"
        if ($speeds) { $moduleText += " · $speeds MHz" }
        [void]$rows.Children.Add((New-WzInfoRow 'Bestückung' $moduleText))
    }
    [void]$rows.Children.Add((New-WzInfoRow 'Bauform' $(if ($Info.IsLaptop) { 'Notebook' } else { 'Desktop' })))

    # --- Sicherheit (Platzhalter bis Stufe 2 fertig ist) ------------------
    if (-not $syncHash.SecurityInfo) {
        $syncHash.DashSecTitle.Text = 'wird geprüft'
        $rows = $syncHash.DashSecRows
        $rows.Children.Clear()
        [void]$rows.Children.Add((New-WzInfoRow 'Aktivierung' 'wird abgefragt...'))
        [void]$rows.Children.Add((New-WzInfoRow 'BitLocker' 'wird abgefragt...'))
        [void]$rows.Children.Add((New-WzInfoRow 'Virenschutz' 'wird abgefragt...'))
    }

    # --- Datenträger ------------------------------------------------------
    $rows = $syncHash.DashDiskRows
    $rows.Children.Clear()
    if ($Info.Volumes.Count -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow 'Laufwerke' 'keine gefunden'))
    }
    foreach ($volume in $Info.Volumes) {
        $label = if ($volume.Label) { "$($volume.Letter) $($volume.Label)" } else { $volume.Letter }
        [void]$rows.Children.Add((New-WzInfoRow $label "$(Format-WzBytes $volume.FreeBytes) frei von $(Format-WzBytes $volume.SizeBytes)"))
        [void]$rows.Children.Add((New-WzMeter -Percent $volume.UsedPercent -Caption "$($volume.UsedPercent) % belegt"))
    }

    # --- Netzwerk ---------------------------------------------------------
    $rows = $syncHash.DashNetRows
    $rows.Children.Clear()
    if ($Info.Network.Count -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow 'Status' 'keine aktive Verbindung' -Kind 'warn'))
    }
    foreach ($adapter in $Info.Network) {
        [void]$rows.Children.Add((New-WzInfoRow $adapter.Adapter $adapter.IPv4))
        if ($adapter.Gateway) { [void]$rows.Children.Add((New-WzInfoRow 'Gateway' $adapter.Gateway)) }
        if ($adapter.Dns) { [void]$rows.Children.Add((New-WzInfoRow 'DNS' $adapter.Dns)) }
    }

    # --- Sitzung ----------------------------------------------------------
    $rows = $syncHash.DashSessionRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow 'Laufzeit' (Format-WzUptime $Info.Uptime)))
    if ($Info.LastBoot) {
        [void]$rows.Children.Add((New-WzInfoRow 'Letzter Start' $Info.LastBoot.ToString('dd.MM.yyyy HH:mm')))
    }
    [void]$rows.Children.Add((New-WzInfoRow 'Zugehörigkeit' $Info.Domain))
    [void]$rows.Children.Add((New-WzInfoRow 'Angemeldet' $Info.UserName))
    [void]$rows.Children.Add((New-WzInfoRow 'WinZii liegt auf' "$($Info.StickDrive) · $(Format-WzBytes $Info.StickFreeBytes) frei"))
    [void]$rows.Children.Add((New-WzInfoRow 'winget' $(if ($Info.WingetAvailable) { 'verfügbar' } else { 'fehlt — kann nachinstalliert werden' }) `
        -Kind $(if ($Info.WingetAvailable) { 'ok' } else { 'warn' })))

    Write-WzDashboardNotices -Info $Info
}

function Write-WzDashboardSecurity {
    <#
    .SYNOPSIS
        Füllt die Sicherheitskarte, sobald Stufe 2 fertig ist.
    #>
    param([Parameter(Mandatory = $true)]$Security)

    $activationOk = ($Security.Activation -like 'aktiviert*')
    $syncHash.DashSecTitle.Text = if ($activationOk) { 'Windows ist aktiviert' } else { 'Bitte prüfen' }

    $rows = $syncHash.DashSecRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow 'Aktivierung' $Security.Activation `
        -Kind $(if ($activationOk) { 'ok' } else { 'warn' })))
    [void]$rows.Children.Add((New-WzInfoRow 'BitLocker' $Security.BitLocker))
    [void]$rows.Children.Add((New-WzInfoRow 'Virenschutz' $Security.Defender `
        -Kind $(if ($Security.DefenderOk) { 'ok' } else { 'warn' })))
    [void]$rows.Children.Add((New-WzInfoRow 'Secure Boot' $Security.SecureBoot))
    [void]$rows.Children.Add((New-WzInfoRow 'TPM' $Security.Tpm))

    # Laufwerkszustand an die Datenträgerkarte anhängen
    foreach ($disk in $Security.PhysicalDisks) {
        $health = if ($disk.Health -eq 'Healthy') { 'in Ordnung' } else { $disk.Health }
        [void]$syncHash.DashDiskRows.Children.Add((New-WzInfoRow $disk.MediaType `
            "$($disk.Model) · $(Format-WzBytes $disk.SizeBytes) · $health" `
            -Kind $(if ($disk.Health -eq 'Healthy') { 'ok' } else { 'warn' })))
    }
}

function Write-WzDashboardNotices {
    param([Parameter(Mandatory = $true)]$Info)

    $notices = $syncHash.DashNotices
    $notices.Items.Clear()
    if ($Info.PendingReboot) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text "Ein Neustart steht aus ($($Info.PendingReboot)). Manche Änderungen greifen erst danach."))
    }
    if ($Info.StickIsFat32) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text 'WinZii liegt auf einem FAT32-Datenträger. Für Office-Downloads werden exFAT oder NTFS empfohlen (4-GB-Dateigrenze).'))
    }
    if ($syncHash.DryRun) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'info' `
            -Text 'Testmodus ist aktiv: Änderungen werden nur protokolliert, nicht ausgeführt.'))
    }
}
