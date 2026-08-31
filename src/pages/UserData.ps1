# Seite "Daten" — Bestandsaufnahme vor der Neuinstallation.

function Initialize-WzUserDataPage {
    $syncHash.DataBtnScan.Add_Click({ Start-WzUserDataScan })
    $syncHash.DataBtnBookmarks.Add_Click({ Start-WzBookmarkExport })
    $syncHash.DataBtnWlan.Add_Click({ Start-WzWlanExport })
    $syncHash.DataBtnDevices.Add_Click({ Start-WzDeviceExport })
    $syncHash.DataBtnHydrate.Add_Click({ Start-WzOneDriveHydration })
    $syncHash.DataBtnMove.Add_Click({ Start-WzFileMigration })
    $syncHash.DataBtnBitLocker.Add_Click({ Start-WzBitLockerExport })
    $syncHash.DataBtnReport.Add_Click({ Start-WzUserDataReport })

    [void]$syncHash.DataNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'data.noticeReadOnly')))
}

function Update-WzUserDataPage {
    if ($syncHash.DataLoaded) { return }
    $syncHash.DataLoaded = $true
    Start-WzUserDataScan
}

function Start-WzUserDataScan {
    $syncHash.DataTitle.Text = Get-WzText 'data.scanning'
    foreach ($name in @('DataProfiles', 'DataOneDrive', 'DataOutlook', 'DataBrowsers', 'DataDevices', 'DataKeys')) {
        $syncHash[$name].Children.Clear()
    }
    $syncHash.DataOneDriveNotice.Items.Clear()

    Invoke-WzTask -Name (Get-WzText 'data.taskScan') -Cancelable -ScriptBlock {
        Get-WzUserDataOverview
    } -OnComplete {
        param($overview)
        if (-not $overview) { return }
        $syncHash.DataOverview = $overview
        Write-WzUserDataOverview -Overview $overview
    }
}

function Write-WzUserDataOverview {
    param([Parameter(Mandatory = $true)]$Overview)

    Write-WzDataProfiles -Profiles @($Overview.Profiles)
    Write-WzDataOneDrive -State $Overview.OneDrive
    Write-WzDataOutlook -Files @($Overview.Outlook)
    Write-WzDataBrowsers -Browsers @($Overview.Browsers)
    Write-WzDataDevices -Printers @($Overview.Printers) -NetDrives @($Overview.NetDrives)
    Write-WzDataKeys -Overview $Overview
    Write-WzDataMove -Profiles @($Overview.Profiles)

    $total = ($Overview.Profiles | Measure-Object -Property TotalBytes -Sum).Sum
    $syncHash.DataTitle.Text = Get-WzText 'data.totalInProfiles' @{ groesse = (Format-WzBytes ([int64]$total)) }
    $syncHash.DataBtnReport.IsEnabled = $true
}

function Write-WzDataProfiles {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles)

    $container = $syncHash.DataProfiles
    $syncHash.DataProfilesTitle.Text = if ($Profiles.Count -eq 0) {
        Get-WzText 'data.noProfiles'
    } elseif ($Profiles.Count -eq 1) {
        Get-WzText 'data.oneProfile'
    } else {
        Get-WzText 'data.nProfiles' @{ anzahl = $Profiles.Count }
    }

    foreach ($profileEntry in $Profiles) {
        $suffix = if ($profileEntry.IsCurrent) { Get-WzText 'data.suffixSignedIn' } else { '' }
        [void]$container.Children.Add((New-WzInfoRow "$($profileEntry.Account)$suffix" `
            (Format-WzBytes $profileEntry.TotalBytes) -Kind 'ok' -LabelWidth 250))

        # Ein Profil, an dem seit Jahren niemand angemeldet war, muss beim Umzug
        # nicht mit — ohne diese Zeile wandern Karteileichen kommentarlos mit.
        if (-not $profileEntry.IsCurrent -and $profileEntry.LastUse) {
            $ago = Format-WzAgo $profileEntry.LastUse
            $stale = ((Get-Date) - [datetime]$profileEntry.LastUse).TotalDays -ge 365
            [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblLastUse') `
                $(if ($stale) { Get-WzText 'data.staleProfile' @{ wann = $ago } } else { $ago }) `
                -Kind $(if ($stale) { 'warn' } else { 'normal' }) -LabelWidth 250))
        }

        foreach ($folder in $profileEntry.Folders) {
            [void]$container.Children.Add((New-WzInfoRow "    $($folder.Name)" `
                (Get-WzText 'data.folderSize' @{ groesse = (Format-WzBytes $folder.Bytes); anzahl = $folder.Items }) -LabelWidth 250))
        }
        if ($profileEntry.Folders.Count -eq 0) {
            $reason = if ($profileEntry.Accessible) {
                Get-WzText 'data.emptyProfile'
            } else {
                Get-WzText 'data.noAccessProfile'
            }
            [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblPersonalFolders') $reason -Kind 'warn' -LabelWidth 250))
        }
    }
}

function Write-WzDataOneDrive {
    param([Parameter(Mandatory = $true)]$State)

    $container = $syncHash.DataOneDrive
    if (-not $State.Configured) {
        $syncHash.DataOneDriveTitle.Text = Get-WzText 'data.oneDriveNotSetUp'
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblResult') `
            (Get-WzText 'data.oneDriveNoAccount') -LabelWidth 250))
        return
    }

    $cloudOnly = ($State.Folders | Measure-Object -Property CloudOnly -Sum).Sum
    $incomplete = (@($State.Folders | Where-Object { $_.Incomplete }).Count -gt 0)
    $syncHash.DataOneDriveTitle.Text = if ($incomplete) {
        Get-WzText 'data.oneDriveIncomplete'
    } elseif ($cloudOnly -gt 0) {
        Get-WzText 'data.oneDriveCloudOnly' @{ anzahl = $cloudOnly }
    } else {
        Get-WzText 'data.oneDriveAllLocal'
    }

    if ($State.PlaceholderWarning) {
        [void]$syncHash.DataOneDriveNotice.Items.Add((New-WzNotice -Kind 'warn' -Text $State.PlaceholderWarning))
        if (-not $incomplete) {
            Write-WzLog (Get-WzText 'data.logPlaceholders' @{ anzahl = $cloudOnly }) -Level Warn
        }
    }

    foreach ($folder in $State.Folders) {
        [void]$container.Children.Add((New-WzInfoRow $folder.Account $folder.Path -LabelWidth 250))
        $suffix = if ($folder.Incomplete) { Get-WzText 'data.suffixPartialCount' } else { '' }
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblOnDisk') `
            (Get-WzText 'data.onDiskValue' @{ groesse = (Format-WzBytes $folder.LocalBytes); anzahl = $folder.LocalFiles; zusatz = $suffix }) `
            -Kind $(if ($folder.Incomplete) { 'warn' } else { 'ok' }) -LabelWidth 250))
        if ($folder.CloudOnly -gt 0) {
            [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblCloudOnly') `
                (Get-WzText 'data.cloudOnlyValue' @{ anzahl = $folder.CloudOnly; zusatz = $suffix }) -Kind 'warn' -LabelWidth 250))
        }
    }

    # Der Knopf gehört auch dann angeboten, wenn die Zählung abgebrochen wurde:
    # Gerade dann weiß niemand, wie viele Platzhalter noch schlummern.
    $syncHash.DataBtnHydrate.IsEnabled = ($cloudOnly -gt 0 -or $incomplete)
}

function Write-WzDataMove {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles)

    $container = $syncHash.DataMove
    $container.Children.Clear()

    # Nur Profile mit vermessenen Ordnern taugen als Quelle. Ein Konto ohne
    # Zugriff hat keine Ordnerliste — dort wüsste robocopy nicht, was kopieren.
    $usable = @($Profiles | Where-Object { @($_.Folders).Count -gt 0 })
    $syncHash.DataMoveProfiles = $usable
    $volumes = @(Get-WzMigrationVolumes)
    $syncHash.DataMoveVolumes = $volumes

    if ($usable.Count -eq 0) {
        $syncHash.DataMoveTitle.Text = Get-WzText 'data.noFoldersToCopy'
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblHint') `
            (Get-WzText 'data.noAccessHint') `
            -Kind 'warn' -LabelWidth 220))
        $syncHash.DataBtnMove.IsEnabled = $false
        return
    }

    $largest = ($usable | Measure-Object -Property TotalBytes -Maximum).Maximum
    foreach ($volume in $volumes) {
        $notes = @()
        if ($volume.IsWinZii) { $notes += Get-WzText 'data.noteWinZiiHere' }
        if ($volume.IsFat32) { $notes += Get-WzText 'data.noteFat32' }
        if ($volume.FreeBytes -lt $largest) { $notes += Get-WzText 'data.noteTooSmall' }
        $kind = if ($notes.Count -gt 0) { 'warn' } elseif ($volume.IsRemovable) { 'ok' } else { 'normal' }

        $text = Get-WzText 'data.freeOfTotal' @{ frei = (Format-WzBytes $volume.FreeBytes); gesamt = (Format-WzBytes $volume.SizeBytes) }
        if ($notes.Count -gt 0) { $text += ' · ' + ($notes -join ' · ') }
        [void]$container.Children.Add((New-WzInfoRow "$($volume.Letter) $($volume.Label)" $text `
            -Kind $kind -LabelWidth 220))
    }

    if ($volumes.Count -eq 0) {
        $syncHash.DataMoveTitle.Text = Get-WzText 'data.noTargetDrive'
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblHint') `
            (Get-WzText 'data.noTargetHint') `
            -Kind 'warn' -LabelWidth 220))
        $syncHash.DataBtnMove.IsEnabled = $false
        return
    }

    $syncHash.DataMoveTitle.Text = Get-WzText 'data.accountsAndTargets' @{ konten = $usable.Count; ziele = $volumes.Count }
    $syncHash.DataBtnMove.IsEnabled = $true
}

function Write-WzDataOutlook {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Files)

    $syncHash.DataOutlookTitle.Text = if ($Files.Count -eq 0) {
        Get-WzText 'data.noOutlook'
    } else {
        Get-WzText 'data.nFilesFound' @{ anzahl = $Files.Count }
    }

    $container = $syncHash.DataOutlook
    foreach ($file in $Files) {
        $kind = if ($file.Path -like '*.pst') { 'warn' } else { 'normal' }
        [void]$container.Children.Add((New-WzInfoRow $file.Name (Format-WzBytes $file.Bytes) -Kind $kind -LabelWidth 200))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblMeaning') $file.Kind -LabelWidth 200))
    }
    if ($Files.Count -eq 0) {
        # Eine leere Karte sieht aus, als wäre etwas abgestürzt
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblResult') `
            (Get-WzText 'data.outlookNone') -LabelWidth 200))
    }
}

function Write-WzDataBrowsers {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Browsers)

    $syncHash.DataBrowsersTitle.Text = if ($Browsers.Count -eq 0) {
        Get-WzText 'data.noBrowsers'
    } else {
        Get-WzText 'data.nBrowsers' @{ anzahl = $Browsers.Count }
    }

    $container = $syncHash.DataBrowsers
    foreach ($browser in $Browsers) {
        [void]$container.Children.Add((New-WzInfoRow $browser.Name (Format-WzBytes $browser.Bytes) -Kind 'ok' -LabelWidth 200))
        $bookmarks = @($browser.BookmarkFiles).Count
        $text = if ($bookmarks -eq 0) { Get-WzText 'data.noBookmarkFile' } else { Get-WzText 'data.nBookmarkProfiles' @{ anzahl = $bookmarks } }
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblBookmarks') $text -LabelWidth 200))
    }
    if ($Browsers.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblResult') `
            (Get-WzText 'data.browsersNone') -LabelWidth 200))
    }

    $exportable = @($Browsers | Where-Object { @($_.BookmarkFiles).Count -gt 0 })
    $syncHash.DataBtnBookmarks.IsEnabled = ($exportable.Count -gt 0)
}

function Write-WzDataDevices {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Printers,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$NetDrives
    )

    $syncHash.DataDevicesTitle.Text = Get-WzText 'data.printersAndDrives' @{ drucker = $Printers.Count; laufwerke = $NetDrives.Count }

    $container = $syncHash.DataDevices
    foreach ($printer in $Printers) {
        $marker = if ($printer.IsDefault) { Get-WzText 'data.suffixDefault' } else { '' }
        # Der Treibername gehört dazu: Nach einer Neuinstallation ist genau er
        # die Antwort auf »welchen Treiber muss ich jetzt suchen?«.
        $detail = @($printer.Port, $printer.Driver) | Where-Object { $_ }
        [void]$container.Children.Add((New-WzInfoRow "$($printer.Name)$marker" `
            ($detail -join ' · ') -LabelWidth 220))
    }
    foreach ($drive in $NetDrives) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblDrive' @{ buchstabe = $drive.Letter }) $drive.Target -Kind 'ok' -LabelWidth 220))
    }
    if ($Printers.Count -eq 0 -and $NetDrives.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblNothingSetUp') (Get-WzText 'data.nothingSetUpValue') -LabelWidth 220))
    }
    $syncHash.DataBtnDevices.IsEnabled = ($Printers.Count -gt 0 -or $NetDrives.Count -gt 0)
}

function Write-WzDataKeys {
    param([Parameter(Mandatory = $true)]$Overview)

    $container = $syncHash.DataKeys
    $wlan = @($Overview.Wlan)
    $encrypted = @($Overview.Encrypted)
    $keys = $Overview.Keys

    $syncHash.DataKeysTitle.Text = Get-WzText 'data.wlanAndEncrypted' @{ netze = $wlan.Count; laufwerke = $encrypted.Count }

    $width = 200
    if ($keys.FirmwareKey) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblUefiKey') (Get-WzText 'data.uefiKeyPresent') -Kind 'ok' -LabelWidth $width))
    } else {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblUefiKey') (Get-WzText 'data.uefiKeyNone') -LabelWidth $width))
    }
    if ($keys.Channel) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblLicenceType') `
            (Get-WzText 'data.licenceEnding' @{ kanal = $keys.Channel; teil = $keys.PartialKey }) -LabelWidth $width))
    }
    foreach ($office in @($keys.Office)) {
        # lang-ok: »Office« ist der Produktname und lautet in jeder Sprache gleich
        [void]$container.Children.Add((New-WzInfoRow 'Office' "$($office.Name) · $($office.Channel)" -LabelWidth $width))  # lang-ok
    }

    if ($wlan.Count -gt 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblSavedWlan') ($wlan -join ', ') -LabelWidth $width))
    }
    if ($encrypted.Count -gt 0) {
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'data.lblBitLockerOn') ($encrypted -join ', ') -Kind 'warn' -LabelWidth $width))
    }

    $syncHash.DataBtnWlan.IsEnabled = ($wlan.Count -gt 0)
    $syncHash.DataBtnBitLocker.IsEnabled = ($encrypted.Count -gt 0)
}

# --- Exporte ---------------------------------------------------------------

function Start-WzBookmarkExport {
    $browsers = @($syncHash.DataOverview.Browsers | Where-Object { @($_.BookmarkFiles).Count -gt 0 })
    if ($browsers.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'data.bookmarkTitle') `
        -Message (Get-WzText 'data.bookmarkMessage') `
        -Items @($browsers | ForEach-Object { $_.Name }) `
        -ConfirmText (Get-WzText 'data.btnBackup')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'data.taskBookmarks') -ArgumentList (, $browsers) -ScriptBlock {
        param($list)
        Export-WzBrowserBookmarks -Browsers $list
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Datensicherung' `
            -Summary (Get-WzText 'data.actionBookmarks' @{ anzahl = $result.Count }) -Detail @($result.Path)
        Show-WzInfo -Title (Get-WzText 'data.bookmarkDoneTitle') `
            -Message (Get-WzText 'data.nFilesSaved' @{ anzahl = $result.Count }) -Items @($result.Path)
    }
}

function Start-WzOneDriveHydration {
    $folders = @($syncHash.DataOverview.OneDrive.Folders)
    if ($folders.Count -eq 0) { return }

    $cloudOnly = ($folders | Measure-Object -Property CloudOnly -Sum).Sum
    $running = [bool](Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)

    $message = (Get-WzText 'data.hydrateMessage' @{ anzahl = $cloudOnly }) + "`n`n" +
        (Get-WzText 'data.hydrateMessage2')
    if (-not $running) {
        $message += "`n`n" + (Get-WzText 'data.hydrateNotRunning')
    }

    $items = @($folders | ForEach-Object { Get-WzText 'data.hydrateItem' @{ pfad = $_.Path; anzahl = $_.CloudOnly } })
    $answer = Show-WzConfirm -Title (Get-WzText 'data.hydrateTitle') -Message $message -Items $items `
        -ConfirmText (Get-WzText 'data.btnDownload') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'data.taskHydrate') -Cancelable -ArgumentList (, @($folders | ForEach-Object { $_.Path })) -ScriptBlock {
        param($paths)
        @($paths | ForEach-Object { Invoke-WzOneDriveHydration -Path $_ })
    } -OnComplete {
        param($results)
        if (-not $results) { return }
        $lines = @($results | ForEach-Object {
            if ($_.Complete) { Get-WzText 'data.hydrateComplete' @{ pfad = $_.Path } }
            elseif ($_.Started) { Get-WzText 'data.hydratePartial' @{ pfad = $_.Path; rest = $_.Remaining; grund = $_.Reason } }
            else { Get-WzText 'data.hydrateNotStarted' @{ pfad = $_.Path; grund = $_.Reason } }
        })
        $allDone = -not (@($results | Where-Object { -not $_.Complete }).Count -gt 0)
        [void](Show-WzConfirm -Title 'OneDrive' -HideCancel -ConfirmText (Get-WzText 'dialog.understood') `
            -Message $(if ($allDone) {
                Get-WzText 'data.hydrateDoneAll'
            } else {
                Get-WzText 'data.hydrateDonePartial'
            }) -Items $lines)
        Start-WzUserDataScan
    }
}

function Start-WzFileMigration {
    $profiles = @($syncHash.DataMoveProfiles)
    $volumes = @($syncHash.DataMoveVolumes)
    if ($profiles.Count -eq 0 -or $volumes.Count -eq 0) { return }

    $profileChoice = 0
    if ($profiles.Count -gt 1) {
        $answer = Show-WzConfirm -Title (Get-WzText 'data.chooseAccountTitle') `
            -Message (Get-WzText 'data.chooseAccountMessage') `
            -Choices @($profiles | ForEach-Object { Get-WzText 'data.accountChoice' @{ konto = $_.Account; groesse = (Format-WzBytes $_.TotalBytes) } }) `
            -ChoiceLabel (Get-WzText 'data.lblAccount') -ConfirmText (Get-WzText 'data.btnNext')
        if (-not $answer.Confirmed) { return }
        $profileChoice = $answer.SelectedIndex
    }
    $selected = $profiles[$profileChoice]

    $labels = @($volumes | ForEach-Object {
        $note = if ($_.IsWinZii) { Get-WzText 'data.noteWinZiiDrive' } elseif ($_.IsRemovable) { Get-WzText 'data.noteRemovable' } else { '' }
        Get-WzText 'data.targetChoice' @{ buchstabe = $_.Letter; bezeichnung = $_.Label; frei = (Format-WzBytes $_.FreeBytes); zusatz = $note }
    })
    $answer = Show-WzConfirm -Title (Get-WzText 'data.chooseTargetTitle') `
        -Message ((Get-WzText 'data.chooseTargetMessage' @{ konto = $selected.Account; groesse = (Format-WzBytes $selected.TotalBytes) }) + "`n`n" +
            (Get-WzText 'data.chooseTargetHint')) `
        -Choices $labels -ChoiceLabel (Get-WzText 'data.lblTarget') -ConfirmText (Get-WzText 'data.btnNext')
    if (-not $answer.Confirmed) { return }
    $target = $volumes[$answer.SelectedIndex]

    $jobs = @(New-WzMigrationJobs -UserProfile $selected -Target "$($target.Letter)\")
    if ($jobs.Count -eq 0) { return }

    $warnings = @()
    if ($target.FreeBytes -lt $selected.TotalBytes) {
        $warnings += Get-WzText 'data.warnNotEnoughRoom' @{ laufwerk = $target.Letter; frei = (Format-WzBytes $target.FreeBytes); noetig = (Format-WzBytes $selected.TotalBytes) }
    }
    if ($target.IsFat32) {
        $warnings += Get-WzText 'data.warnFat32Target'
    }
    if ($target.IsWinZii) {
        $warnings += Get-WzText 'data.warnWinZiiTarget'
    }

    $message = Get-WzText 'data.copyMessage' @{ ziel = "$($target.Letter)\WinZii-Daten\$env:COMPUTERNAME\" }
    if ($warnings.Count -gt 0) { $message += "`n`n" + ($warnings -join "`n") }

    $answer = Show-WzConfirm -Title (Get-WzText 'data.copyTitle') -Message $message `
        -Items @($jobs | ForEach-Object { Get-WzText 'data.copyItem' @{ name = $_.Name; groesse = (Format-WzBytes $_.Bytes); anzahl = $_.Items } }) `
        -ConfirmText (Get-WzText 'data.btnCopyGo') -Danger:($warnings.Count -gt 0)
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'data.taskCopy') -Cancelable -ArgumentList (, $jobs) -ScriptBlock {
        param($jobs)
        Invoke-WzFileMigration -Jobs $jobs
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $lines = @($result.Applied) + @($result.Failed | ForEach-Object { Get-WzText 'data.copyFailedItem' @{ name = $_ } })
        if ($lines.Count -eq 0) { $lines = @(Get-WzText 'data.copyNothing') }
        [void](Show-WzConfirm -Title (Get-WzText 'data.copyDoneTitle') -HideCancel -ConfirmText (Get-WzText 'dialog.understood') `
            -Message $(if (@($result.Failed).Count -gt 0) {
                Get-WzText 'data.copyPartial'
            } else {
                Get-WzText 'data.copyDone' @{ groesse = (Format-WzBytes $result.CopiedBytes) }
            }) -Items $lines)
    }
}

function Start-WzDeviceExport {
    $printers = @($syncHash.DataOverview.Printers)
    $drives = @($syncHash.DataOverview.NetDrives)
    if ($printers.Count -eq 0 -and $drives.Count -eq 0) { return }

    $items = @($printers | ForEach-Object { Get-WzText 'data.printerItem' @{ name = $_.Name; anschluss = $_.Port } }) +
             @($drives | ForEach-Object { Get-WzText 'data.driveItem' @{ buchstabe = $_.Letter; ziel = $_.Target } })

    $answer = Show-WzConfirm -Title (Get-WzText 'data.deviceTitle') `
        -Message (Get-WzText 'data.deviceMessage') `
        -Items $items -ConfirmText (Get-WzText 'data.btnBackup')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'data.taskDevices') -ArgumentList @($printers, $drives) -ScriptBlock {
        param($printers, $drives)
        Export-WzDeviceList -Printers $printers -NetDrives $drives
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Datensicherung' `
            -Summary (Get-WzText 'data.actionDevices' @{ anzahl = $result.Count }) -Detail @($result.Path)
        Show-WzInfo -Title (Get-WzText 'data.deviceDoneTitle') `
            -Message (Get-WzText 'data.deviceDoneMessage' @{ anzahl = $result.Count }) -Items @($result.Path)
    }
}

function Start-WzWlanExport {
    $wlan = @($syncHash.DataOverview.Wlan)
    if ($wlan.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'data.wlanTitle') `
        -Message ((Get-WzText 'data.wlanMessage' @{ anzahl = $wlan.Count }) + "`n`n" +
            (Get-WzText 'data.wlanMessage2')) `
        -Items $wlan `
        -Choices @((Get-WzText 'data.wlanChoiceKeys'), (Get-WzText 'data.wlanChoiceNames')) `
        -ChoiceLabel (Get-WzText 'data.lblScope') -ChoiceDefault 0 `
        -ConfirmText (Get-WzText 'data.btnBackup') -Danger
    if (-not $answer.Confirmed) { return }

    # Der Hinweistext wird schon im Hintergrund gesetzt: OnComplete läuft in
    # einem eigenen Bereich und sieht die Variablen von hier oben nicht.
    Invoke-WzTask -Name (Get-WzText 'data.taskWlan') -ArgumentList @(($answer.SelectedIndex -eq 0)) -ScriptBlock {
        param($withKeys)
        $export = if ($withKeys) { Export-WzWlanProfiles -IncludeKeys } else { Export-WzWlanProfiles }
        $note = if ($withKeys) { Get-WzText 'data.wlanNoteKeys' } else { Get-WzText 'data.wlanNoteNoKeys' }
        [pscustomobject]@{ Count = $export.Count; Path = $export.Path; Note = $note }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Datensicherung' `
            -Summary (Get-WzText 'data.actionWlan' @{ anzahl = $result.Count; hinweis = $result.Note }) -Detail @($result.Path)
        Show-WzInfo -Title (Get-WzText 'data.wlanDoneTitle') `
            -Message (Get-WzText 'data.wlanDoneMessage' @{ anzahl = $result.Count; hinweis = $result.Note }) -Items @($result.Path)
    }
}

function Start-WzBitLockerExport {
    $encrypted = @($syncHash.DataOverview.Encrypted)
    if ($encrypted.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'data.bitlockerTitle') `
        -Message ((Get-WzText 'data.bitlockerMessage' @{ laufwerke = ($encrypted -join ', ') }) + "`n`n" +
            (Get-WzText 'data.bitlockerMessage2')) `
        -ConfirmText (Get-WzText 'data.btnBackup') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'data.taskBitlocker') -ScriptBlock {
        $keys = Get-WzBitLockerKeys
        $path = Save-WzBitLockerKeys -Keys $keys
        [pscustomobject]@{ Count = @($keys).Count; Path = $path }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $message = if ($result.Count -eq 0) {
            Get-WzText 'data.bitlockerNoKeys'
        } elseif ($result.Path) {
            Get-WzText 'data.bitlockerSaved' @{ anzahl = $result.Count }
        } else {
            Get-WzText 'data.bitlockerDryRun' @{ anzahl = $result.Count }
        }
        if ($result.Path) {
            # Bewusst nur Anzahl und Ablageort — die Schlüssel selbst gehören
            # in keinen Bericht und in kein Protokoll.
            Add-WzAction -Area 'Datensicherung' `
                -Summary (Get-WzText 'data.actionBitlocker' @{ anzahl = $result.Count }) -Detail @($result.Path)
        }
        Show-WzInfo -Title (Get-WzText 'data.bitlockerDoneTitle') -Message $message -Items @($result.Path | Where-Object { $_ })
    }
}

function Start-WzUserDataReport {
    if (-not $syncHash.DataOverview) { return }

    Invoke-WzTask -Name (Get-WzText 'data.taskReport') -ArgumentList @($syncHash.DataOverview) -ScriptBlock {
        param($overview)
        New-WzUserDataReport -Overview $overview
    } -OnComplete {
        param($path)
        if (-not $path) { return }
        Show-WzInfo -Title (Get-WzText 'data.reportDoneTitle') `
            -Message (Get-WzText 'data.reportDoneMessage') `
            -Items @($path)
    }
}
