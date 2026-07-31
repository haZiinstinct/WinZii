# Seite "Treiber" — Problemgeräte, Treiberbestand, Sicherung und Rückspielung.

function Initialize-WzDriversPage {
    $syncHash.DrvBtnScan.Add_Click({ Start-WzDriverScan })
    $syncHash.DrvBtnExport.Add_Click({ Start-WzDriverExport })
    $syncHash.DrvBtnImport.Add_Click({ Start-WzDriverImport })
    $syncHash.DrvShowMicrosoft.Add_Click({ Write-WzDriverList })

    [void]$syncHash.DrvNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Eine Treibersicherung vor dem Neuaufsetzen erspart die Suche nach Downloads, die es für ältere Notebooks oft gar nicht mehr gibt.'))
}

function Update-WzDriversPage {
    if ($syncHash.DrvLoaded) { return }
    $syncHash.DrvLoaded = $true
    Start-WzDriverScan
}

function Start-WzDriverScan {
    $syncHash.DrvTitle.Text = 'wird geprüft...'
    foreach ($name in @('DrvProblems', 'DrvList', 'DrvBackupInfo', 'DrvBackups')) {
        $syncHash[$name].Children.Clear()
    }

    Invoke-WzTask -Name 'Geräte prüfen' -ScriptBlock {
        $problems = Get-WzProblemDevices
        $inventory = Get-WzDriverInventory -IncludeMicrosoft
        # Der Treiberspeicher braucht knapp zehn Sekunden — ohne Zwischenmeldung
        # sieht es aus, als hänge die Seite
        Write-WzLog 'Treiberspeicher wird vermessen...' -Level Info
        [pscustomobject]@{
            Problems = $problems
            Drivers  = $inventory
            Store    = Get-WzDriverStoreSize
            Volume   = Get-WzVolumeInfo
            Backups  = Get-WzDriverBackups
        }
    } -OnComplete {
        param($scan)
        if (-not $scan) { return }
        $syncHash.DrvScan = $scan

        Write-WzDriverProblems -Devices @($scan.Problems)
        Write-WzDriverList
        Write-WzDriverBackupInfo -Store $scan.Store -Volume $scan.Volume
        Write-WzDriverBackups -Backups @($scan.Backups)

        $critical = @($scan.Problems | Where-Object { $_.IsCritical })
        $syncHash.DrvTitle.Text = if ($critical.Count -eq 0) {
            'Alle Geräte laufen'
        } elseif ($critical.Count -eq 1) {
            'Ein Gerät hat ein Problem'
        } else {
            "$($critical.Count) Geräte haben ein Problem"
        }
    }
}

function Write-WzDriverProblems {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Devices)

    $container = $syncHash.DrvProblems
    $critical = @($Devices | Where-Object { $_.IsCritical })

    $syncHash.DrvProblemsTitle.Text = if ($Devices.Count -eq 0) {
        'Kein Gerät meldet einen Fehler'
    } elseif ($critical.Count -eq 0) {
        'Nur abgesteckte Geräte — kein Handlungsbedarf'
    } else {
        "$($critical.Count) von $($Devices.Count) Meldung(en) sind echte Fehler"
    }

    foreach ($device in $Devices) {
        $kind = if ($device.IsCritical) { 'error' } else { 'normal' }
        [void]$container.Children.Add((New-WzInfoRow $device.Name `
            "Code $($device.Code) · $($device.Class)" -Kind $kind -LabelWidth 250))
        [void]$container.Children.Add((New-WzInfoRow '    Bedeutung' $device.Meaning -LabelWidth 250))
        [void]$container.Children.Add((New-WzInfoRow '    Abhilfe' $device.Fix -LabelWidth 250))
    }

    if ($critical.Count -gt 0) {
        Write-WzLog "$($critical.Count) Gerät(e) mit Fehlercode gefunden." -Level Warn
    }
}

function Write-WzDriverList {
    if (-not $syncHash.DrvScan) { return }

    $showMicrosoft = [bool]$syncHash.DrvShowMicrosoft.IsChecked
    $drivers = @($syncHash.DrvScan.Drivers)
    if (-not $showMicrosoft) {
        $drivers = @($drivers | Where-Object { -not $_.IsMicrosoft })
    }

    # Bewusst "angeschlossene Geräte": Diese Liste kommt aus dem Geräte-Manager
    # und zählt anderes als der Treiberspeicher in der Karte darunter, in dem
    # auch alte Fassungen und Pakete ohne passendes Gerät liegen.
    $total = @($syncHash.DrvScan.Drivers).Count
    $syncHash.DrvListTitle.Text = if ($showMicrosoft) {
        "$total Treiber für angeschlossene Geräte"
    } else {
        "$($drivers.Count) von $total Treibern stammen von Geräteherstellern"
    }

    $container = $syncHash.DrvList
    $container.Children.Clear()

    # Nur die ältesten zeigen — die vollständige Liste hilft am Bildschirm niemandem
    foreach ($driver in ($drivers | Select-Object -First 15)) {
        $age = if ($null -ne $driver.AgeYears) { "$($driver.AgeYears) Jahre" } else { 'ohne Datum' }
        $kind = if ($null -ne $driver.AgeYears -and $driver.AgeYears -ge 5 -and -not $driver.IsMicrosoft) { 'warn' } else { 'normal' }
        [void]$container.Children.Add((New-WzInfoRow $driver.Device `
            "$($driver.Provider) · $($driver.Version) · $age" -Kind $kind -LabelWidth 250))
    }

    if ($drivers.Count -gt 15) {
        [void]$container.Children.Add((New-WzInfoRow 'weitere' `
            "$($drivers.Count - 15) jüngere Treiber sind hier nicht aufgeführt" -LabelWidth 250))
    }
    if ($drivers.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Nichts gefunden' `
            'Die Treiberliste ließ sich nicht abfragen.' -Kind 'warn' -LabelWidth 250))
    }
}

function Write-WzDriverBackupInfo {
    param(
        [Parameter(Mandatory = $true)]$Store,
        [Parameter(Mandatory = $true)]$Volume
    )

    $container = $syncHash.DrvBackupInfo
    [void]$container.Children.Add((New-WzInfoRow 'Treiberspeicher gesamt' `
        "$(Format-WzBytes $Store.TotalBytes) in $($Store.TotalPackages) Paket(en)" -LabelWidth 250))

    if ($Store.ThirdPartyKnown) {
        [void]$container.Children.Add((New-WzInfoRow 'davon nachträglich eingespielt' `
            "$(Format-WzBytes $Store.ThirdPartyBytes) in $($Store.ThirdPartyPackages) Paket(en)" `
            -Kind 'ok' -LabelWidth 250))
    } else {
        [void]$container.Children.Add((New-WzInfoRow 'davon nachträglich eingespielt' `
            'nicht ermittelbar — dafür fehlen die Administratorrechte' -Kind 'warn' -LabelWidth 250))
    }

    $needed = if ($Store.ThirdPartyKnown) { $Store.ThirdPartyBytes } else { $Store.TotalBytes }
    $freeKind = if ($Volume.FreeBytes -lt $needed) { 'error' } else { 'ok' }
    [void]$container.Children.Add((New-WzInfoRow "Frei auf Laufwerk $($Volume.DriveLetter):" `
        (Format-WzBytes $Volume.FreeBytes) -Kind $freeKind -LabelWidth 250))

    if ($Volume.FreeBytes -lt $Store.TotalBytes) {
        $hint = if ($Volume.FreeBytes -lt $needed) {
            'Der Platz reicht auch für die kleine Sicherung nicht.'
        } else {
            'Für alle Treiber reicht der Platz nicht — die kleine Sicherung passt.'
        }
        [void]$container.Children.Add((New-WzInfoRow 'Hinweis' $hint -Kind 'warn' -LabelWidth 250))
    }
}

function Write-WzDriverBackups {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Backups)

    $syncHash.DrvBackupsTitle.Text = if ($Backups.Count -eq 0) {
        'Auf diesem Datenträger liegt noch keine Sicherung'
    } else {
        "$($Backups.Count) Sicherung(en) vorhanden"
    }

    $container = $syncHash.DrvBackups
    foreach ($backup in $Backups) {
        [void]$container.Children.Add((New-WzInfoRow $backup.Host `
            "$($backup.Packages) Paket(e) · $(Format-WzBytes $backup.Bytes) · $($backup.Created.ToString('dd.MM.yyyy'))" `
            -Kind 'ok' -LabelWidth 180))
    }

    $syncHash.DrvBackupList = $Backups
    $syncHash.DrvBtnImport.IsEnabled = ($Backups.Count -gt 0)
}

# --- Sichern und zurückspielen --------------------------------------------

function Start-WzDriverExport {
    if (-not $syncHash.DrvScan) { return }

    $store = $syncHash.DrvScan.Store
    $free = $syncHash.DrvScan.Volume.FreeBytes
    $thirdPartyLabel = if ($store.ThirdPartyKnown) {
        "nur nachträglich eingespielte Treiber — $(Format-WzBytes $store.ThirdPartyBytes) (empfohlen)"
    } else {
        'nur nachträglich eingespielte Treiber (empfohlen)'
    }

    $answer = Show-WzConfirm -Title 'Treiber sichern' `
        -Message ("Die Treiber werden nach offline\treiber\$env:COMPUTERNAME geschrieben. Je nach Umfang dauert das einige Minuten.`n`n" +
            'Die empfohlene Auswahl lässt weg, was Windows von sich aus mitbringt — nur die bringt eine ' +
            "Neuinstallation nicht selbst wieder mit.`n`nFrei auf dem Datenträger: $(Format-WzBytes $free)") `
        -Choices @($thirdPartyLabel, "alle Treiber — $(Format-WzBytes $store.TotalBytes)") `
        -ChoiceLabel 'Umfang' -ChoiceDefault 0 `
        -ConfirmText 'Sichern'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Treiber sichern' -ArgumentList @(($answer.SelectedIndex -eq 0)) -ScriptBlock {
        param($thirdPartyOnly)
        if ($thirdPartyOnly) { Export-WzDrivers -ThirdPartyOnly } else { Export-WzDrivers }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $message = if ($result.Success) {
            "$($result.Packages) Treiberpaket(e) gesichert ($(Format-WzBytes $result.Bytes))."
        } else {
            'Es wurde nichts gesichert. Für den Treiberexport sind Administratorrechte nötig.'
        }
        if ($result.Success) {
            Add-WzAction -Area 'Treiber' `
                -Summary "$($result.Packages) Treiberpaket(e) auf den Datenträger gesichert ($(Format-WzBytes $result.Bytes))" `
                -Detail @($result.Path)
        }
        Show-WzInfo -Title 'Treibersicherung' -Message $message -Items @($result.Path)
        Start-WzDriverScan
    }
}

function Start-WzDriverImport {
    $backups = @($syncHash.DrvBackupList)
    if ($backups.Count -eq 0) { return }

    $labels = @($backups | ForEach-Object {
        "$($_.Host) — $($_.Packages) Paket(e), $(Format-WzBytes $_.Bytes), $($_.Created.ToString('dd.MM.yyyy'))"
    })

    $answer = Show-WzConfirm -Title 'Treiber zurückspielen' `
        -Message ('Die Treiber aus der gewählten Sicherung werden in Windows aufgenommen und für passende Geräte installiert. ' +
            'Vorhandene, neuere Treiber ersetzt Windows dabei nicht. Nach dem Einspielen ist ein Neustart sinnvoll.') `
        -Choices $labels -ChoiceLabel 'Sicherung' -ChoiceDefault 0 `
        -ConfirmText 'Einspielen' -Danger
    if (-not $answer.Confirmed) { return }

    $selected = $backups[$answer.SelectedIndex]
    Invoke-WzTask -Name 'Treiber einspielen' -ArgumentList @($selected.Path) -ScriptBlock {
        param($path)
        Import-WzDrivers -Path $path
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Treiber' -RebootRequired -Summary "Treibersicherung eingespielt: $($result.Summary)"
        }
        Show-WzInfo -Title 'Treiber eingespielt' -Message $result.Summary
    }
}
