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

    Invoke-WzTask -Name (Get-WzText 'dash.taskSystem') -Silent -ScriptBlock {
        Get-WzSystemInfo
    } -OnComplete {
        param($info)
        if (-not $info) {
            Write-WzLog (Get-WzText 'dash.logNoSystemData') -Level Error
            return
        }
        $syncHash.SystemInfo = $info
        # Der allererste Stand bleibt liegen — das Übergabeblatt vergleicht
        # damit später den freien Speicher.
        if (-not $syncHash.SessionStartInfo) { $syncHash.SessionStartInfo = $info }
        Write-WzDashboardCards -Info $info
        Write-WzLog (Get-WzText 'dash.logWindows' @{ name = $info.OsCaption; version = $info.OsVersion; build = $info.OsBuild }) -Level Info

        # Stufe 2 anstoßen (Lizenz, BitLocker, Virenschutz, Laufwerkszustand)
        Invoke-WzTask -Name (Get-WzText 'dash.taskSecurity') -Silent -ScriptBlock {
            Get-WzSecurityInfo
        } -OnComplete {
            param($security)
            if (-not $security) { return }
            $syncHash.SecurityInfo = $security
            Write-WzDashboardSecurity -Security $security
            Write-WzLog (Get-WzText 'dash.logSecurity' @{ aktivierung = $security.Activation; bitlocker = $security.BitLocker }) -Level Info
        }
    }
}

function Write-WzDashboardCards {
    param([Parameter(Mandatory = $true)]$Info)

    # --- Windows ----------------------------------------------------------
    $syncHash.DashOsTitle.Text = $Info.OsCaption
    $rows = $syncHash.DashOsRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblVersion') "$($Info.OsVersion)  ·  Build $($Info.OsBuild)"))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblEdition') $Info.OsEdition))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblArchitecture') $Info.OsArchitecture))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblLanguage') $Info.OsLanguage))
    if ($Info.InstallDate) {
        $age = [math]::Round(((Get-Date) - $Info.InstallDate).TotalDays)
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblInstalled') `
            (Get-WzText 'dash.installedAgo' @{ datum = $Info.InstallDate.ToString('d', (Get-WzLanguageCulture)); tage = $age })))
    }

    # --- Hardware ---------------------------------------------------------
    $syncHash.DashHwTitle.Text = if ($Info.Model -and $Info.Model -ne 'n/v') {
        "$($Info.Manufacturer) $($Info.Model)".Trim()
    } else { Get-WzText 'dash.unknownSystem' }
    $rows = $syncHash.DashHwRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblCpu') $Info.CpuName))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblCores') `
        (Get-WzText 'dash.coresThreads' @{ kerne = $Info.CpuCores; threads = $Info.CpuThreads })))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblRam') (Format-WzBytes $Info.RamTotalBytes)))
    if ($Info.RamTotalBytes -gt 0) {
        [void]$rows.Children.Add((New-WzMeter -Percent $Info.RamUsedPercent `
            -Caption (Get-WzText 'dash.ramUsed' @{ prozent = $Info.RamUsedPercent; frei = (Format-WzBytes $Info.RamFreeBytes) })))
    }
    if ($Info.RamModules.Count -gt 0) {
        $speeds = ($Info.RamModules | Where-Object { $_.Speed } | Select-Object -ExpandProperty Speed -Unique) -join '/'
        $moduleText = Get-WzText 'dash.moduleCount' @{ anzahl = $Info.RamModules.Count }
        if ($speeds) { $moduleText += " · $speeds MHz" }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblModules') $moduleText))
    }
    if ($Info.RamSlots -gt 0) {
        # Die Aufrüstfrage: Ist noch ein Steckplatz frei, und wie viel geht rein?
        $free = $Info.RamSlots - $Info.RamSlotsUsed
        $slotText = Get-WzText 'dash.slotsUsed' @{ belegt = $Info.RamSlotsUsed; gesamt = $Info.RamSlots }
        if ($Info.RamMaxBytes -gt 0) { $slotText += " · max. $(Format-WzBytes $Info.RamMaxBytes)" }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblSlots') $slotText -Kind $(if ($free -gt 0) { 'ok' } else { 'normal' })))
    }
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblChassis') `
        $(if ($Info.IsLaptop) { Get-WzText 'dash.chassisNotebook' } else { Get-WzText 'dash.chassisDesktop' })))
    if ($Info.Battery.Present) {
        $batteryKind = if ($null -eq $Info.Battery.WearPercent) { 'normal' }
                       elseif ($Info.Battery.WearPercent -ge 40) { 'warn' }
                       else { 'ok' }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblBattery') $Info.Battery.Verdict -Kind $batteryKind))
        # Derselbe Balken wie bei Arbeitsspeicher und Platte: »37 %« als Zahl
        # sagt wenig, als Balken neben den anderen sieht man den Verschleiß.
        if ($null -ne $Info.Battery.WearPercent) {
            [void]$rows.Children.Add((New-WzMeter -Percent ([int]$Info.Battery.WearPercent) `
                -Caption (Get-WzText 'dash.batteryLost' @{ prozent = [int]$Info.Battery.WearPercent })))
        }
    }

    Write-WzDashboardDevices -Info $Info

    # --- Sicherheit (Platzhalter bis Stufe 2 fertig ist) ------------------
    if (-not $syncHash.SecurityInfo) {
        $syncHash.DashSecTitle.Text = Get-WzText 'dash.secChecking'
        $rows = $syncHash.DashSecRows
        $rows.Children.Clear()
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblActivation') (Get-WzText 'dash.queried')))
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblBitLocker') (Get-WzText 'dash.queried')))
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblDefender') (Get-WzText 'dash.queried')))
    }

    # --- Datenträger ------------------------------------------------------
    $rows = $syncHash.DashDiskRows
    $rows.Children.Clear()
    if ($Info.Volumes.Count -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblDrives') (Get-WzText 'dash.noDrives')))
    }
    foreach ($volume in $Info.Volumes) {
        $label = if ($volume.Label) { "$($volume.Letter) $($volume.Label)" } else { $volume.Letter }
        [void]$rows.Children.Add((New-WzInfoRow $label `
            (Get-WzText 'dash.freeOf' @{ frei = (Format-WzBytes $volume.FreeBytes); gesamt = (Format-WzBytes $volume.SizeBytes) })))
        [void]$rows.Children.Add((New-WzMeter -Percent $volume.UsedPercent `
            -Caption (Get-WzText 'dash.usedPercent' @{ prozent = $volume.UsedPercent })))
    }

    # --- Netzwerk ---------------------------------------------------------
    $rows = $syncHash.DashNetRows
    $rows.Children.Clear()
    if ($Info.Network.Count -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblStatus') (Get-WzText 'dash.noConnection') -Kind 'warn'))
    }
    foreach ($adapter in $Info.Network) {
        [void]$rows.Children.Add((New-WzInfoRow $adapter.Adapter $adapter.IPv4))
        if ($adapter.Gateway) { [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblGateway') $adapter.Gateway)) }
        if ($adapter.Dns) { [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblDns') $adapter.Dns)) }
    }

    # --- Sitzung ----------------------------------------------------------
    $rows = $syncHash.DashSessionRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblUptime') (Format-WzUptime $Info.Uptime)))
    if ($Info.LastBoot) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblLastBoot') `
            $Info.LastBoot.ToString('g', (Get-WzLanguageCulture))))
    }
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblDomain') $Info.Domain))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblSignedIn') $Info.UserName))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblStick') `
        (Get-WzText 'dash.stickFree' @{ laufwerk = $Info.StickDrive; frei = (Format-WzBytes $Info.StickFreeBytes) })))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblWinget') `
        $(if ($Info.WingetAvailable) { Get-WzText 'dash.wingetAvailable' } else { Get-WzText 'dash.wingetMissing' }) `
        -Kind $(if ($Info.WingetAvailable) { 'ok' } else { 'warn' })))

    Write-WzDashboardNotices -Info $Info
}

function Write-WzDashboardDevices {
    <#
    .SYNOPSIS
        Füllt die Karten Grafik, Anzeige und Firmware.
    #>
    param([Parameter(Mandatory = $true)]$Info)

    # --- Grafik -----------------------------------------------------------
    $gpus = @($Info.Gpus)
    $syncHash.DashGpuTitle.Text = if ($gpus.Count -eq 0) { Get-WzText 'dash.gpuNotQueryable' } else { $gpus[0].Name }
    $rows = $syncHash.DashGpuRows
    $rows.Children.Clear()
    foreach ($gpu in $gpus) {
        if ($gpus.Count -gt 1) { [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblCard') $gpu.Name)) }
        if ($gpu.MemoryBytes -gt 0) {
            [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblVram') (Format-WzBytes $gpu.MemoryBytes)))
        }
        if ($gpu.Resolution) { [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblResolution') $gpu.Resolution)) }
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblDriver') $gpu.DriverVersion))
    }
    if ($gpus.Count -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblResult') (Get-WzText 'dash.noGpu') -Kind 'warn'))
    }

    # --- Anzeige ----------------------------------------------------------
    $monitors = @($Info.Monitors)
    $syncHash.DashMonitorTitle.Text = switch ($monitors.Count) {
        0       { Get-WzText 'dash.monitors0' }
        1       { Get-WzText 'dash.monitors1' }
        default { Get-WzText 'dash.monitorsN' @{ anzahl = $monitors.Count } }
    }
    $rows = $syncHash.DashMonitorRows
    $rows.Children.Clear()
    foreach ($monitor in $monitors) {
        $parts = @()
        if ($monitor.Inches -gt 0) { $parts += "$(Format-WzNumber $monitor.Inches)″" }
        if ($monitor.Year -gt 0) { $parts += Get-WzText 'dash.monitorYear' @{ jahr = $monitor.Year } }
        $label = "$($monitor.Vendor) $($monitor.Name)".Trim()
        [void]$rows.Children.Add((New-WzInfoRow $label ($parts -join ' · ') -LabelWidth 140))
    }
    if ($monitors.Count -eq 0) {
        # Über Fernwartung ist das normal und kein Fehler
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblResult') (Get-WzText 'dash.noMonitor')))
    }

    # --- Firmware ---------------------------------------------------------
    $syncHash.DashFirmwareTitle.Text = if ($Info.BiosVersion -ne 'n/v') {
        "BIOS $($Info.BiosVersion)"
    } else { Get-WzText 'dash.gpuNotQueryable' }
    $rows = $syncHash.DashFirmwareRows
    $rows.Children.Clear()
    if ($Info.BiosDate) {
        $years = Format-WzNumber (((Get-Date) - $Info.BiosDate).TotalDays / 365.25) (Get-WzText 'dash.unitYearsOld')
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblBiosDate') `
            "$($Info.BiosDate.ToString('d', (Get-WzLanguageCulture))) · $years"))
    }
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblVendor') $Info.BiosVendor))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblBoard') $Info.BaseBoard))
    if ($Info.SerialNumber) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblSerial') $Info.SerialNumber -Kind 'ok'))
    } else {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblSerial') (Get-WzText 'dash.serialNone')))
    }
}

function Write-WzDashboardSecurity {
    <#
    .SYNOPSIS
        Füllt die Sicherheitskarte, sobald Stufe 2 fertig ist.
    #>
    param([Parameter(Mandatory = $true)]$Security)

    $activationOk = [bool]$Security.ActivationOk
    $syncHash.DashSecTitle.Text = if ($activationOk) { Get-WzText 'dash.secTitleOk' } else { Get-WzText 'dash.secTitleCheck' }

    $rows = $syncHash.DashSecRows
    $rows.Children.Clear()
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblActivation') $Security.Activation `
        -Kind $(if ($activationOk) { 'ok' } else { 'warn' })))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblBitLocker') $Security.BitLocker))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblDefender') $Security.Defender `
        -Kind $(if ($Security.DefenderOk) { 'ok' } else { 'warn' })))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblSecureBoot') $Security.SecureBoot))
    [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'dash.lblTpm') $Security.Tpm))

    # Die Hinweisleiste neu aufbauen: Erst jetzt sind Aktivierung, Virenschutz
    # und Laufwerkszustand bekannt — genau die Befunde, aus denen die
    # Empfehlungen entstehen.
    if ($syncHash.SystemInfo) { Write-WzDashboardNotices -Info $syncHash.SystemInfo }

    # Laufwerkszustand an die Datenträgerkarte anhängen
    foreach ($disk in $Security.PhysicalDisks) {
        $health = if ($disk.Health -eq 'Healthy') { Get-WzText 'dash.diskHealthy' } else { $disk.Health }
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
            -Text (Get-WzText 'dash.noticeReboot' @{ grund = $Info.PendingReboot })))
    }
    if ($syncHash.WriteBlocked -or -not (Test-WzWritableRoot)) {
        # Auf einem schreibgeschützten Stick läuft WinZii weiter, kann aber weder
        # Protokoll noch Sicherungen noch Berichte ablegen. Das gehört sichtbar
        # nach oben und nicht nur ins Protokoll, das es ja gerade nicht gibt.
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text (Get-WzText 'dash.noticeWriteBlocked')))
    }
    if ($Info.StickIsFat32) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text (Get-WzText 'dash.noticeFat32')))
    }
    if ($syncHash.DryRun) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'info' `
            -Text (Get-WzText 'dash.noticeDryRun')))
    }

    # Die Befunde, die bisher nur im gedruckten Übergabeblatt landeten, gehören
    # auch hierher: Platte fast voll, Virenschutz veraltet, nicht aktiviert,
    # Datenträger meldet Fehler, Akku verschlissen. Die Daten liegen zu diesem
    # Zeitpunkt längst im Speicher — es kostet keine einzige neue Abfrage.
    if ($syncHash.SecurityInfo) {
        foreach ($recommendation in (Get-WzHandoverRecommendations -Info $Info `
                -Security $syncHash.SecurityInfo -Actions (Get-WzActions))) {
            # Zum Neustart steht oben schon eine Zeile — die nennt sogar den Grund
            if ($recommendation.Text -like '*neu gestartet*') { continue }
            $kind = if ($recommendation.Kind -eq 'err') { 'error' } else { $recommendation.Kind }
            [void]$notices.Items.Add((New-WzNotice -Kind $kind -Text $recommendation.Text))
        }
    }
}
