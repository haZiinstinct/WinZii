# Seite "Treiber" — Problemgeräte, Treiberbestand, Sicherung und Rückspielung.

function Initialize-WzDriversPage {
    $syncHash.DrvBtnScan.Add_Click({ Start-WzDriverScan })
    $syncHash.DrvBtnExport.Add_Click({ Start-WzDriverExport })
    $syncHash.DrvBtnImport.Add_Click({ Start-WzDriverImport })
    $syncHash.DrvShowMicrosoft.Add_Click({ Write-WzDriverList })

    [void]$syncHash.DrvNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'drv.noticeBackup')))
}

function Update-WzDriversPage {
    if ($syncHash.DrvLoaded) { return }
    $syncHash.DrvLoaded = $true
    Start-WzDriverScan
}

function Start-WzDriverScan {
    $syncHash.DrvTitle.Text = Get-WzText 'drv.checking'
    foreach ($name in @('DrvProblems', 'DrvList', 'DrvBackupInfo', 'DrvBackups')) {
        $syncHash[$name].Children.Clear()
    }

    Invoke-WzTask -Name (Get-WzText 'drv.taskScan') -Cancelable -ScriptBlock {
        $problems = Get-WzProblemDevices
        $inventory = Get-WzDriverInventory -IncludeMicrosoft
        # Der Treiberspeicher braucht knapp zehn Sekunden — ohne Zwischenmeldung
        # sieht es aus, als hänge die Seite
        Write-WzLog (Get-WzText 'drv.logMeasuringStore') -Level Info
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
            Get-WzText 'drv.allDevicesOk'
        } elseif ($critical.Count -eq 1) {
            Get-WzText 'drv.oneDeviceProblem'
        } else {
            Get-WzText 'drv.nDevicesProblem' @{ anzahl = $critical.Count }
        }
    }
}

function Write-WzDriverProblems {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Devices)

    $container = $syncHash.DrvProblems
    $critical = @($Devices | Where-Object { $_.IsCritical })

    $syncHash.DrvProblemsTitle.Text = if ($Devices.Count -eq 0) {
        Get-WzText 'drv.noDeviceError'
    } elseif ($critical.Count -eq 0) {
        Get-WzText 'drv.onlyUnplugged'
    } else {
        Get-WzText 'drv.realErrors' @{ kritisch = $critical.Count; gesamt = $Devices.Count }
    }

    foreach ($device in $Devices) {
        $kind = if ($device.IsCritical) { 'error' } else { 'normal' }
        [void]$container.Children.Add((New-WzInfoRow $device.Name `
            (Get-WzText 'drv.deviceCode' @{ code = $device.Code; klasse = $device.Class }) -Kind $kind -LabelWidth 250))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblMeaning') $device.Meaning -LabelWidth 250))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblFix') $device.Fix -LabelWidth 250))
    }

    if ($critical.Count -gt 0) {
        Write-WzLog (Get-WzText 'drv.logDevicesWithError' @{ anzahl = $critical.Count }) -Level Warn
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
        Get-WzText 'drv.driversForDevices' @{ anzahl = $total }
    } else {
        Get-WzText 'drv.driversFromVendors' @{ anzahl = $drivers.Count; gesamt = $total }
    }

    $container = $syncHash.DrvList
    $container.Children.Clear()

    # Nur die ältesten zeigen — die vollständige Liste hilft am Bildschirm niemandem
    foreach ($driver in ($drivers | Select-Object -First 15)) {
        $age = if ($null -ne $driver.AgeYears) { Format-WzNumber $driver.AgeYears (Get-WzText 'drv.unitYears') } else { Get-WzText 'drv.noDate' }
        $kind = if ($null -ne $driver.AgeYears -and $driver.AgeYears -ge 5 -and -not $driver.IsMicrosoft) { 'warn' } else { 'normal' }
        # Die Kategorie davor macht aus »irgendein Treiber ist sieben Jahre alt«
        # ein »der Grafiktreiber ist sieben Jahre alt« — erst das ist eine Aussage.
        $parts = @()
        if ($driver.Class) { $parts += $driver.Class }
        $parts += @($driver.Provider, $driver.Version, $age)
        [void]$container.Children.Add((New-WzInfoRow $driver.Device `
            ($parts -join ' · ') -Kind $kind -LabelWidth 250))
    }

    if ($drivers.Count -gt 15) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblMore') `
            (Get-WzText 'drv.driversHidden' @{ anzahl = ($drivers.Count - 15) }) -LabelWidth 250))
    }
    if ($drivers.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblNothingFound') `
            (Get-WzText 'drv.driverListFailed') -Kind 'warn' -LabelWidth 250))
    }
}

function Write-WzDriverBackupInfo {
    param(
        [Parameter(Mandatory = $true)]$Store,
        [Parameter(Mandatory = $true)]$Volume
    )

    $container = $syncHash.DrvBackupInfo
    [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblStoreTotal') `
        (Get-WzText 'drv.storeValue' @{ groesse = (Format-WzBytes $Store.TotalBytes); anzahl = $Store.TotalPackages }) -LabelWidth 250))

    if ($Store.ThirdPartyKnown) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblThirdParty') `
            (Get-WzText 'drv.storeValue' @{ groesse = (Format-WzBytes $Store.ThirdPartyBytes); anzahl = $Store.ThirdPartyPackages }) `
            -Kind 'ok' -LabelWidth 250))
    } else {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblThirdParty') `
            (Get-WzText 'drv.thirdPartyUnknown') -Kind 'warn' -LabelWidth 250))
    }

    $needed = if ($Store.ThirdPartyKnown) { $Store.ThirdPartyBytes } else { $Store.TotalBytes }
    $freeKind = if ($Volume.FreeBytes -lt $needed) { 'error' } else { 'ok' }
    [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblFreeOn' @{ laufwerk = $Volume.DisplayName }) `
        (Format-WzBytes $Volume.FreeBytes) -Kind $freeKind -LabelWidth 250))

    if ($Volume.FreeBytes -lt $Store.TotalBytes) {
        $hint = if ($Volume.FreeBytes -lt $needed) {
            Get-WzText 'drv.hintNoRoomAtAll'
        } else {
            Get-WzText 'drv.hintRoomForSmall'
        }
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'drv.lblHint') $hint -Kind 'warn' -LabelWidth 250))
    }
}

function Write-WzDriverBackups {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Backups)

    $syncHash.DrvBackupsTitle.Text = if ($Backups.Count -eq 0) {
        Get-WzText 'drv.noBackupYet'
    } else {
        Get-WzText 'drv.nBackups' @{ anzahl = $Backups.Count }
    }

    $container = $syncHash.DrvBackups
    foreach ($backup in $Backups) {
        [void]$container.Children.Add((New-WzInfoRow $backup.Host `
            (Get-WzText 'drv.backupValue' @{ pakete = $backup.Packages; groesse = (Format-WzBytes $backup.Bytes); datum = $backup.Created.ToString('d', (Get-WzLanguageCulture)) }) `
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
        Get-WzText 'drv.choiceThirdPartySize' @{ groesse = (Format-WzBytes $store.ThirdPartyBytes) }
    } else {
        Get-WzText 'drv.choiceThirdParty'
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'drv.exportTitle') `
        -Message ((Get-WzText 'drv.exportMessage' @{ computer = $env:COMPUTERNAME }) + "`n`n" +
            (Get-WzText 'drv.exportMessage2') + "`n`n" +
            (Get-WzText 'drv.exportFree' @{ frei = (Format-WzBytes $free) })) `
        -Choices @($thirdPartyLabel, (Get-WzText 'drv.choiceAll' @{ groesse = (Format-WzBytes $store.TotalBytes) })) `
        -ChoiceLabel (Get-WzText 'drv.lblScope') -ChoiceDefault 0 `
        -ConfirmText (Get-WzText 'drv.btnBackupGo')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'drv.taskExport') -ArgumentList @(($answer.SelectedIndex -eq 0)) -ScriptBlock {
        param($thirdPartyOnly)
        if ($thirdPartyOnly) { Export-WzDrivers -ThirdPartyOnly } else { Export-WzDrivers }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $message = if ($result.Success) {
            Get-WzText 'drv.exportOk' @{ anzahl = $result.Packages; groesse = (Format-WzBytes $result.Bytes) }
        } else {
            Get-WzText 'drv.exportFailed'
        }
        if ($result.Success) {
            Add-WzAction -Area 'Treiber' `
                -Summary (Get-WzText 'drv.actionExport' @{ anzahl = $result.Packages; groesse = (Format-WzBytes $result.Bytes) }) `
                -Detail @($result.Path)
        }
        Show-WzInfo -Title (Get-WzText 'drv.exportDoneTitle') -Message $message -Items @($result.Path)
        Start-WzDriverScan
    }
}

function Start-WzDriverImport {
    $backups = @($syncHash.DrvBackupList)
    if ($backups.Count -eq 0) { return }

    $labels = @($backups | ForEach-Object {
        $marker = if ($_.Host -ne $env:COMPUTERNAME) { Get-WzText 'drv.markerOtherPc' } else { '' }
        Get-WzText 'drv.backupChoice' @{ rechner = $_.Host; markierung = $marker; pakete = $_.Packages
            groesse = (Format-WzBytes $_.Bytes); datum = $_.Created.ToString('d', (Get-WzLanguageCulture)) }
    })

    # Der Stick sammelt Sicherungen mehrerer Rechner — Treiber vom falschen PC
    # gehören nicht ungefragt auf fremde Hardware.
    $message = Get-WzText 'drv.importMessage'
    if (@($backups | Where-Object { $_.Host -ne $env:COMPUTERNAME }).Count -gt 0) {
        $message += "`n`n" + (Get-WzText 'drv.importWarnOther' @{ computer = $env:COMPUTERNAME })
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'drv.importTitle') -Message $message `
        -Choices $labels -ChoiceLabel (Get-WzText 'drv.lblBackup') -ChoiceDefault 0 `
        -ConfirmText (Get-WzText 'drv.btnImport') -Danger
    if (-not $answer.Confirmed) { return }

    $selected = $backups[$answer.SelectedIndex]
    Invoke-WzTask -Name (Get-WzText 'drv.taskImport') -ArgumentList @($selected.Path) -ScriptBlock {
        param($path)
        Import-WzDrivers -Path $path
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Treiber' -RebootRequired -Summary (Get-WzText 'drv.actionImport' @{ ergebnis = $result.Summary })
        }
        Show-WzInfo -Title (Get-WzText 'drv.importDoneTitle') -Message $result.Summary
    }
}
