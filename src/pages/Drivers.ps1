# Seite "Treiber" — Problemgeräte, Treiberbestand, Sicherung und Rückspielung.

function Initialize-WzDriversPage {
    $syncHash.DrvBtnScan.Add_Click({ Start-WzDriverScan })
    $syncHash.DrvBtnExport.Add_Click({ Start-WzDriverExport })
    $syncHash.DrvBtnImport.Add_Click({ Start-WzDriverImport })
    $syncHash.DrvShowMicrosoft.Add_Click({ Write-WzDriverList })
    $syncHash.DrvBtnOemInstall.Add_Click({ Start-WzOemToolInstall })
    $syncHash.DrvBtnOemScan.Add_Click({ Start-WzOemScan })
    $syncHash.DrvBtnOemApply.Add_Click({ Start-WzOemApply })

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
    foreach ($name in @('DrvProblems', 'DrvList', 'DrvBackupInfo', 'DrvBackups', 'DrvOemRows', 'DrvCatalogRows')) {
        $syncHash[$name].Children.Clear()
    }

    Invoke-WzTask -Name (Get-WzText 'drv.taskScan') -Cancelable -ScriptBlock {
        $problems = Get-WzProblemDevices
        $inventory = Get-WzDriverInventory -IncludeMicrosoft
        # Der Treiberspeicher braucht knapp zehn Sekunden — ohne Zwischenmeldung
        # sieht es aus, als hänge die Seite
        Write-WzLog (Get-WzText 'drv.logMeasuringStore') -Level Info
        [pscustomobject]@{
            Problems   = $problems
            Drivers    = $inventory
            Store      = Get-WzDriverStoreSize
            Volume     = Get-WzVolumeInfo
            Backups    = Get-WzDriverBackups
            OemTools   = Get-WzOemDriverTools
            Driverless = Get-WzDriverlessDevices
        }
    } -OnComplete {
        param($scan)
        if (-not $scan) { return }
        $syncHash.DrvScan = $scan

        Write-WzDriverProblems -Devices @($scan.Problems)
        Write-WzDriverList
        Write-WzDriverBackupInfo -Store $scan.Store -Volume $scan.Volume
        Write-WzDriverBackups -Backups @($scan.Backups)
        Write-WzDriverObtain -OemTools @($scan.OemTools) -Driverless @($scan.Driverless) -Backups @($scan.Backups)

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

# --- Treiber beschaffen ----------------------------------------------------

function Write-WzDriverObtain {
    <#
    .SYNOPSIS
        Füllt die Karte »Treiber beschaffen«: Werkzeug des Herstellers und
        Geräte, die noch ganz ohne Treiber dastehen.
    #>
    param(
        [AllowEmptyCollection()][array]$OemTools = @(),
        [AllowEmptyCollection()][array]$Driverless = @(),
        [AllowEmptyCollection()][array]$Backups = @()
    )

    $syncHash.DrvOemTools = @($OemTools)

    # Der passende Eintrag steht vorn — Get-WzOemDriverTools sortiert danach.
    $primary = @($OemTools | Where-Object { $_.Matches })[0]
    $syncHash.DrvOemPrimary = $primary

    $notices = $syncHash.DrvObtainNotices
    $notices.Items.Clear()
    if (@($Backups).Count -eq 0) {
        # Der wichtigste Satz dieser Karte: Ein Herstellertreiber, der schlechter
        # läuft als der bisherige, ist ein realer Fall — und ohne Sicherung gibt
        # es keinen Weg zurück.
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' -Text (Get-WzText 'drv.obtainNoBackup')))
    }

    $rows = $syncHash.DrvOemRows
    $rows.Children.Clear()

    if (-not $primary) {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'drv.oemVendor') (Get-WzText 'drv.oemNoMatch') -LabelWidth 150))
    } else {
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'drv.oemVendor') $primary.Tool.name -LabelWidth 150))
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'drv.oemState') `
            $(if ($primary.Installed) { Get-WzText 'drv.oemInstalled' } else { Get-WzText 'drv.oemMissing' }) `
            -Kind $(if ($primary.Installed) { 'ok' } else { 'warn' }) -LabelWidth 150))
        [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'drv.oemWhat') $primary.Tool.description -LabelWidth 150))
    }

    # Die Werkzeuge, die zu diesem Gerät nicht passen, aber trotzdem etwas
    # beitragen — Intel steht ohne Erkennungsmuster im Katalog.
    foreach ($entry in @($OemTools | Where-Object { -not $_.Matches })) {
        $state = if ($entry.Installed) { Get-WzText 'drv.oemInstalled' } else { Get-WzText 'drv.oemMissing' }
        [void]$rows.Children.Add((New-WzInfoRow $entry.Tool.name "$state · $($entry.Tool.description)" -LabelWidth 150))
    }

    $syncHash.DrvBtnOemInstall.IsEnabled = ($primary -and -not $primary.Installed)
    $syncHash.DrvBtnOemScan.IsEnabled = ($primary -and $primary.Installed -and $primary.Tool.silent)
    $syncHash.DrvBtnOemApply.IsEnabled = ($primary -and $primary.Installed -and $primary.Tool.silent)

    # --- Geräte ohne jeden Treiber ----------------------------------------
    $syncHash.DrvDriverless = @($Driverless)
    $catalogRows = $syncHash.DrvCatalogRows
    $catalogRows.Children.Clear()

    if (@($Driverless).Count -eq 0) {
        [void]$catalogRows.Children.Add((New-WzInfoRow (Get-WzText 'drv.catalogNoneLabel') (Get-WzText 'drv.catalogNone') -Kind 'ok' -LabelWidth 150))
        return
    }

    foreach ($device in $Driverless) {
        [void]$catalogRows.Children.Add((New-WzDriverlessRow -Device $device))
    }
}

function New-WzDriverlessRow {
    <#
    .SYNOPSIS
        Eine Zeile je Gerät ohne Treiber: Name, Kennung und der Knopf, der die
        Suche im Update-Katalog anstößt.
    #>
    param([Parameter(Mandatory = $true)]$Device)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 4, 0, 4)
    $textColumn = New-Object Windows.Controls.ColumnDefinition
    $textColumn.Width = '*'
    $buttonColumn = New-Object Windows.Controls.ColumnDefinition
    $buttonColumn.Width = 'Auto'
    [void]$grid.ColumnDefinitions.Add($textColumn)
    [void]$grid.ColumnDefinitions.Add($buttonColumn)

    $stack = New-Object Windows.Controls.StackPanel
    $name = New-Object Windows.Controls.TextBlock
    $name.Text = $Device.Name
    $name.Style = $syncHash.Window.FindResource('WzValue')
    $name.TextWrapping = 'Wrap'
    [void]$stack.Children.Add($name)

    $detail = New-Object Windows.Controls.TextBlock
    $detail.Text = "$($Device.Class) · $($Device.SearchId)"
    $detail.Style = $syncHash.Window.FindResource('WzLabel')
    $detail.TextWrapping = 'Wrap'
    [void]$stack.Children.Add($detail)
    [Windows.Controls.Grid]::SetColumn($stack, 0)
    [void]$grid.Children.Add($stack)

    $button = New-Object Windows.Controls.Button
    $button.Content = Get-WzText 'drv.btnCatalogSearch'
    $button.Style = $syncHash.Window.FindResource('WzBtnSecondary')
    $button.Margin = New-Object Windows.Thickness(10, 0, 0, 0)
    $button.VerticalAlignment = 'Center'
    $button.Tag = $Device
    $button.Add_Click({ Start-WzCatalogSearch -Device $this.Tag })
    [Windows.Controls.Grid]::SetColumn($button, 1)
    [void]$grid.Children.Add($button)

    return $grid
}

function Start-WzOemToolInstall {
    $primary = $syncHash.DrvOemPrimary
    if (-not $primary) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'drv.oemInstallTitle') `
        -Message (Get-WzText 'drv.oemInstallMessage' @{ name = $primary.Tool.name }) `
        -Items @($primary.Tool.description, (Get-WzText 'drv.oemInstallItem' @{ id = $primary.Tool.wingetId })) `
        -ConfirmText (Get-WzText 'drv.btnOemInstall')
    if (-not $answer.Confirmed) { return }

    # Über denselben Weg wie jedes andere Programm: Install-WzApps prüft die
    # Verbindung, wertet den Rückgabewert aus und sieht danach nach, ob das
    # Programm wirklich da ist.
    $app = [pscustomobject]@{ name = $primary.Tool.name; wingetId = $primary.Tool.wingetId }

    Invoke-WzTask -Name (Get-WzText 'drv.taskOemInstall') -ArgumentList (, @($app)) -ScriptBlock {
        param($apps)
        Install-WzApps -Apps $apps
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        if ($summary.Installed -gt 0) {
            Add-WzAction -Area 'Treiber' -Summary (Get-WzText 'drv.actionOemInstalled' @{ name = $primary.Tool.name })
        }
        Show-WzInfo -Title (Get-WzText 'drv.oemInstallTitle') `
            -Message $(if ($summary.Installed -gt 0) {
                Get-WzText 'drv.oemInstallOk' @{ name = $primary.Tool.name }
            } else {
                Get-WzText 'drv.oemInstallFailed' @{ name = $primary.Tool.name }
            }) -Items @($summary.Details)
        Start-WzDriverScan
    }.GetNewClosure()
}

function Start-WzOemScan {
    Start-WzOemRun -Apply $false
}

function Start-WzOemApply {
    Start-WzOemRun -Apply $true
}

function Start-WzOemRun {
    <#
    .SYNOPSIS
        Lässt das Werkzeug des Herstellers suchen oder einspielen.
    #>
    param([bool]$Apply)

    $primary = $syncHash.DrvOemPrimary
    if (-not $primary) { return }

    $items = @($primary.Tool.description)
    if ($Apply) {
        $items += Get-WzText 'drv.oemApplyItemReboot'
        $backups = @($syncHash.DrvScan.Backups)
        $items += if ($backups.Count -gt 0) {
            Get-WzText 'drv.oemApplyItemBackupOk'
        } else {
            Get-WzText 'drv.oemApplyItemNoBackup'
        }
    }

    $answer = Show-WzConfirm `
        -Title $(if ($Apply) { Get-WzText 'drv.oemApplyTitle' } else { Get-WzText 'drv.oemScanTitle' }) `
        -Message $(if ($Apply) {
            Get-WzText 'drv.oemApplyMessage' @{ name = $primary.Tool.name }
        } else {
            Get-WzText 'drv.oemScanMessage' @{ name = $primary.Tool.name }
        }) `
        -Items $items `
        -ConfirmText $(if ($Apply) { Get-WzText 'drv.btnOemApply' } else { Get-WzText 'drv.btnOemScan' }) `
        -Danger:$Apply
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'drv.taskOemRun' @{ name = $primary.Tool.name }) `
        -ArgumentList @($primary, $Apply) -ScriptBlock {
            param($entry, $apply)
            Invoke-WzOemDriverUpdate -Entry $entry -ApplyUpdates:$apply
        } -OnComplete {
            param($result)
            if (-not $result) { return }
            if ($result.Success -and $Apply) {
                Add-WzAction -Area 'Treiber' -RebootRequired `
                    -Summary (Get-WzText 'drv.actionOemApplied' @{ name = $primary.Tool.name })
            }
            Show-WzInfo -Title (Get-WzText 'drv.oemDoneTitle') -Message $result.Summary
        }.GetNewClosure()
}

function Start-WzCatalogSearch {
    <#
    .SYNOPSIS
        Sucht im Update-Katalog nach einem Treiber für ein Gerät, das noch
        keinen hat, und bietet die Treffer zur Auswahl an.
    #>
    param([Parameter(Mandatory = $true)]$Device)

    Invoke-WzTask -Name (Get-WzText 'drv.taskCatalogSearch' @{ geraet = $Device.Name }) -Cancelable -ArgumentList @($Device.SearchId) -ScriptBlock {
        param($hardwareId)
        Find-WzCatalogDrivers -HardwareId $hardwareId
    } -OnComplete {
        param($hits)
        $hits = @($hits)
        if ($hits.Count -eq 0) {
            Show-WzInfo -Title (Get-WzText 'drv.catalogTitle') `
                -Message (Get-WzText 'drv.catalogNothing' @{ geraet = $Device.Name; kennung = $Device.SearchId })
            return
        }

        # Die Treffer kommen aus dem Netz und sind für WinZii nichts als Text:
        # Was davon zum Gerät passt, entscheidet der Techniker am Namen und am
        # Datum — deshalb die Auswahl und kein automatisches Nehmen des ersten.
        $choices = @($hits | ForEach-Object {
            Get-WzText 'drv.catalogChoice' @{ titel = $_.Title; datum = $_.Date; groesse = $_.SizeText } })

        $answer = Show-WzConfirm -Title (Get-WzText 'drv.catalogTitle') `
            -Message (Get-WzText 'drv.catalogFoundMessage' @{ anzahl = $hits.Count; geraet = $Device.Name }) `
            -Items @((Get-WzText 'drv.catalogItemSource'), (Get-WzText 'drv.catalogItemRestore')) `
            -Choices $choices -ChoiceLabel (Get-WzText 'drv.catalogChoiceLabel') `
            -ConfirmText (Get-WzText 'drv.btnCatalogInstall') -Danger
        if (-not $answer.Confirmed) { return }

        $selected = $hits[$answer.SelectedIndex]
        Start-WzCatalogInstall -Entry $selected -Device $Device
    }.GetNewClosure()
}

function Start-WzCatalogInstall {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)]$Device
    )

    Invoke-WzTask -Name (Get-WzText 'drv.taskCatalogInstall') -ArgumentList @($Entry, $Device.Name) -ScriptBlock {
        param($entry, $deviceName)
        Install-WzCatalogDriver -Entry $entry -DeviceName $deviceName
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Treiber' `
                -Summary (Get-WzText 'drv.actionCatalog' @{ geraet = $Device.Name }) `
                -Detail @($Entry.Title)
        }
        Show-WzInfo -Title (Get-WzText 'drv.catalogTitle') -Message $result.Summary `
            -Items @($result.Path | Where-Object { $_ })
        Start-WzDriverScan
    }.GetNewClosure()
}
