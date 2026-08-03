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
        # Der allererste Stand bleibt liegen — das Übergabeblatt vergleicht
        # damit später den freien Speicher.
        if (-not $syncHash.SessionStartInfo) { $syncHash.SessionStartInfo = $info }
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
    if ($Info.RamSlots -gt 0) {
        # Die Aufrüstfrage: Ist noch ein Steckplatz frei, und wie viel geht rein?
        $free = $Info.RamSlots - $Info.RamSlotsUsed
        $slotText = "$($Info.RamSlotsUsed) von $($Info.RamSlots) belegt"
        if ($Info.RamMaxBytes -gt 0) { $slotText += " · max. $(Format-WzBytes $Info.RamMaxBytes)" }
        [void]$rows.Children.Add((New-WzInfoRow 'Steckplätze' $slotText -Kind $(if ($free -gt 0) { 'ok' } else { 'normal' })))
    }
    [void]$rows.Children.Add((New-WzInfoRow 'Bauform' $(if ($Info.IsLaptop) { 'Notebook' } else { 'Desktop' })))
    if ($Info.Battery.Present) {
        $batteryKind = if ($null -eq $Info.Battery.WearPercent) { 'normal' }
                       elseif ($Info.Battery.WearPercent -ge 40) { 'warn' }
                       else { 'ok' }
        [void]$rows.Children.Add((New-WzInfoRow 'Akku' $Info.Battery.Verdict -Kind $batteryKind))
    }

    Write-WzDashboardDevices -Info $Info

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

function Write-WzDashboardDevices {
    <#
    .SYNOPSIS
        Füllt die Karten Grafik, Anzeige und Firmware.
    #>
    param([Parameter(Mandatory = $true)]$Info)

    # --- Grafik -----------------------------------------------------------
    $gpus = @($Info.Gpus)
    $syncHash.DashGpuTitle.Text = if ($gpus.Count -eq 0) { 'nicht abfragbar' } else { $gpus[0].Name }
    $rows = $syncHash.DashGpuRows
    $rows.Children.Clear()
    foreach ($gpu in $gpus) {
        if ($gpus.Count -gt 1) { [void]$rows.Children.Add((New-WzInfoRow 'Karte' $gpu.Name)) }
        if ($gpu.MemoryBytes -gt 0) {
            [void]$rows.Children.Add((New-WzInfoRow 'Speicher' (Format-WzBytes $gpu.MemoryBytes)))
        }
        if ($gpu.Resolution) { [void]$rows.Children.Add((New-WzInfoRow 'Auflösung' $gpu.Resolution)) }
        [void]$rows.Children.Add((New-WzInfoRow 'Treiber' $gpu.DriverVersion))
    }
    if ($gpus.Count -eq 0) {
        [void]$rows.Children.Add((New-WzInfoRow 'Ergebnis' 'Es ließ sich keine Grafikkarte auslesen.' -Kind 'warn'))
    }

    # --- Anzeige ----------------------------------------------------------
    $monitors = @($Info.Monitors)
    $syncHash.DashMonitorTitle.Text = switch ($monitors.Count) {
        0       { 'kein Bildschirm erkannt' }
        1       { 'Ein Bildschirm' }
        default { "$($monitors.Count) Bildschirme" }
    }
    $rows = $syncHash.DashMonitorRows
    $rows.Children.Clear()
    foreach ($monitor in $monitors) {
        $parts = @()
        if ($monitor.Inches -gt 0) { $parts += "$($monitor.Inches)″" }
        if ($monitor.Year -gt 0) { $parts += "Baujahr $($monitor.Year)" }
        $label = "$($monitor.Vendor) $($monitor.Name)".Trim()
        [void]$rows.Children.Add((New-WzInfoRow $label ($parts -join ' · ') -LabelWidth 140))
    }
    if ($monitors.Count -eq 0) {
        # Über Fernwartung ist das normal und kein Fehler
        [void]$rows.Children.Add((New-WzInfoRow 'Ergebnis' `
            'Kein Bildschirm meldet sich — bei Fernwartung ist das üblich.'))
    }

    # --- Firmware ---------------------------------------------------------
    $syncHash.DashFirmwareTitle.Text = if ($Info.BiosVersion -ne 'n/v') {
        "BIOS $($Info.BiosVersion)"
    } else { 'nicht abfragbar' }
    $rows = $syncHash.DashFirmwareRows
    $rows.Children.Clear()
    if ($Info.BiosDate) {
        $years = [math]::Round(((Get-Date) - $Info.BiosDate).TotalDays / 365.25, 1)
        [void]$rows.Children.Add((New-WzInfoRow 'Stand' "$($Info.BiosDate.ToString('dd.MM.yyyy')) · $years Jahre alt"))
    }
    [void]$rows.Children.Add((New-WzInfoRow 'Hersteller' $Info.BiosVendor))
    [void]$rows.Children.Add((New-WzInfoRow 'Mainboard' $Info.BaseBoard))
    if ($Info.SerialNumber) {
        [void]$rows.Children.Add((New-WzInfoRow 'Seriennummer' $Info.SerialNumber -Kind 'ok'))
    } else {
        [void]$rows.Children.Add((New-WzInfoRow 'Seriennummer' 'keine hinterlegt — bei Selbstbau normal'))
    }
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

    # Die Hinweisleiste neu aufbauen: Erst jetzt sind Aktivierung, Virenschutz
    # und Laufwerkszustand bekannt — genau die Befunde, aus denen die
    # Empfehlungen entstehen.
    if ($syncHash.SystemInfo) { Write-WzDashboardNotices -Info $syncHash.SystemInfo }

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
    if ($syncHash.WriteBlocked -or -not (Test-WzWritableRoot)) {
        # Auf einem schreibgeschützten Stick läuft WinZii weiter, kann aber weder
        # Protokoll noch Sicherungen noch Berichte ablegen. Das gehört sichtbar
        # nach oben und nicht nur ins Protokoll, das es ja gerade nicht gibt.
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text 'Auf diesen Datenträger lässt sich nicht schreiben. Protokoll, Sicherungen und Berichte können nicht gespeichert werden — und damit gibt es zu Änderungen keinen Rückweg. Vor Eingriffen bitte auf einen beschreibbaren Datenträger wechseln.'))
    }
    if ($Info.StickIsFat32) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text 'WinZii liegt auf einem FAT32-Datenträger. Für Office-Downloads werden exFAT oder NTFS empfohlen (4-GB-Dateigrenze).'))
    }
    if ($syncHash.DryRun) {
        [void]$notices.Items.Add((New-WzNotice -Kind 'info' `
            -Text 'Testmodus ist aktiv: Änderungen werden nur protokolliert, nicht ausgeführt.'))
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
