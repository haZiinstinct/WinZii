# Seite "Daten" — Bestandsaufnahme vor der Neuinstallation.

function Initialize-WzUserDataPage {
    $syncHash.DataBtnScan.Add_Click({ Start-WzUserDataScan })
    $syncHash.DataBtnBookmarks.Add_Click({ Start-WzBookmarkExport })
    $syncHash.DataBtnWlan.Add_Click({ Start-WzWlanExport })
    $syncHash.DataBtnBitLocker.Add_Click({ Start-WzBitLockerExport })
    $syncHash.DataBtnReport.Add_Click({ Start-WzUserDataReport })

    [void]$syncHash.DataNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Diese Seite liest nur. Die Exporte darunter schreiben einzelne Dateien auf den Datenträger und fragen jeweils vorher nach.'))
}

function Update-WzUserDataPage {
    if ($syncHash.DataLoaded) { return }
    $syncHash.DataLoaded = $true
    Start-WzUserDataScan
}

function Start-WzUserDataScan {
    $syncHash.DataTitle.Text = 'wird aufgenommen...'
    foreach ($name in @('DataProfiles', 'DataOneDrive', 'DataOutlook', 'DataBrowsers', 'DataDevices', 'DataKeys')) {
        $syncHash[$name].Children.Clear()
    }
    $syncHash.DataOneDriveNotice.Items.Clear()

    Invoke-WzTask -Name 'Daten aufnehmen' -ScriptBlock {
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

    $total = ($Overview.Profiles | Measure-Object -Property TotalBytes -Sum).Sum
    $syncHash.DataTitle.Text = "$(Format-WzBytes ([int64]$total)) in den persönlichen Ordnern"
    $syncHash.DataBtnReport.IsEnabled = $true
}

function Write-WzDataProfiles {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles)

    $container = $syncHash.DataProfiles
    $syncHash.DataProfilesTitle.Text = if ($Profiles.Count -eq 0) {
        'Keine Benutzerprofile gefunden'
    } elseif ($Profiles.Count -eq 1) {
        'Ein Benutzerkonto'
    } else {
        "$($Profiles.Count) Benutzerkonten"
    }

    foreach ($profileEntry in $Profiles) {
        $suffix = if ($profileEntry.IsCurrent) { ' (angemeldet)' } else { '' }
        [void]$container.Children.Add((New-WzInfoRow "$($profileEntry.Account)$suffix" `
            (Format-WzBytes $profileEntry.TotalBytes) -Kind 'ok' -LabelWidth 250))

        foreach ($folder in $profileEntry.Folders) {
            [void]$container.Children.Add((New-WzInfoRow "    $($folder.Name)" `
                "$(Format-WzBytes $folder.Bytes) · $($folder.Items) Datei(en)" -LabelWidth 250))
        }
        if ($profileEntry.Folders.Count -eq 0) {
            $reason = if ($profileEntry.Accessible) {
                'vorhanden, aber leer'
            } else {
                'kein Zugriff — das Profil gehört einem anderen Konto'
            }
            [void]$container.Children.Add((New-WzInfoRow '    persönliche Ordner' $reason -Kind 'warn' -LabelWidth 250))
        }
    }
}

function Write-WzDataOneDrive {
    param([Parameter(Mandatory = $true)]$State)

    $container = $syncHash.DataOneDrive
    if (-not $State.Configured) {
        $syncHash.DataOneDriveTitle.Text = 'OneDrive ist auf diesem PC nicht eingerichtet'
        [void]$container.Children.Add((New-WzInfoRow 'Ergebnis' `
            'Kein Konto angemeldet — es liegen keine Dateien in der Cloud, die beim Kopieren fehlen könnten.' -LabelWidth 250))
        return
    }

    $cloudOnly = ($State.Folders | Measure-Object -Property CloudOnly -Sum).Sum
    $syncHash.DataOneDriveTitle.Text = if ($cloudOnly -gt 0) {
        "$cloudOnly Datei(en) liegen nur in der Cloud"
    } else {
        'Alle Dateien liegen auch auf der Platte'
    }

    if ($State.PlaceholderWarning) {
        [void]$syncHash.DataOneDriveNotice.Items.Add((New-WzNotice -Kind 'warn' -Text $State.PlaceholderWarning))
        Write-WzLog "OneDrive: $cloudOnly Datei(en) sind nur Platzhalter — vor dem Kopieren herunterladen." -Level Warn
    }

    foreach ($folder in $State.Folders) {
        [void]$container.Children.Add((New-WzInfoRow $folder.Account $folder.Path -LabelWidth 250))
        [void]$container.Children.Add((New-WzInfoRow '    auf der Platte' `
            "$(Format-WzBytes $folder.LocalBytes) · $($folder.LocalFiles) Datei(en)" -Kind 'ok' -LabelWidth 250))
        if ($folder.CloudOnly -gt 0) {
            [void]$container.Children.Add((New-WzInfoRow '    nur in der Cloud' `
                "$($folder.CloudOnly) Datei(en)" -Kind 'warn' -LabelWidth 250))
        }
    }
}

function Write-WzDataOutlook {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Files)

    $syncHash.DataOutlookTitle.Text = if ($Files.Count -eq 0) {
        'Keine Outlook-Dateien gefunden'
    } else {
        "$($Files.Count) Datei(en) gefunden"
    }

    $container = $syncHash.DataOutlook
    foreach ($file in $Files) {
        $kind = if ($file.Path -like '*.pst') { 'warn' } else { 'normal' }
        [void]$container.Children.Add((New-WzInfoRow $file.Name (Format-WzBytes $file.Bytes) -Kind $kind -LabelWidth 200))
        [void]$container.Children.Add((New-WzInfoRow '    Bedeutung' $file.Kind -LabelWidth 200))
    }
    if ($Files.Count -eq 0) {
        # Eine leere Karte sieht aus, als wäre etwas abgestürzt
        [void]$container.Children.Add((New-WzInfoRow 'Ergebnis' `
            'Outlook ist nicht eingerichtet oder arbeitet nur im Web.' -LabelWidth 200))
    }
}

function Write-WzDataBrowsers {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Browsers)

    $syncHash.DataBrowsersTitle.Text = if ($Browsers.Count -eq 0) {
        'Keine Browser-Profile gefunden'
    } else {
        "$($Browsers.Count) Browser gefunden"
    }

    $container = $syncHash.DataBrowsers
    foreach ($browser in $Browsers) {
        [void]$container.Children.Add((New-WzInfoRow $browser.Name (Format-WzBytes $browser.Bytes) -Kind 'ok' -LabelWidth 200))
        $bookmarks = @($browser.BookmarkFiles).Count
        $text = if ($bookmarks -eq 0) { 'keine Lesezeichen-Datei gefunden' } else { "$bookmarks Profil(e) mit Lesezeichen" }
        [void]$container.Children.Add((New-WzInfoRow '    Lesezeichen' $text -LabelWidth 200))
    }
    if ($Browsers.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Ergebnis' `
            'Weder Edge, Chrome, Brave noch Firefox haben hier ein Profil angelegt.' -LabelWidth 200))
    }

    $exportable = @($Browsers | Where-Object { @($_.BookmarkFiles).Count -gt 0 })
    $syncHash.DataBtnBookmarks.IsEnabled = ($exportable.Count -gt 0)
}

function Write-WzDataDevices {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Printers,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$NetDrives
    )

    $syncHash.DataDevicesTitle.Text = "$($Printers.Count) Drucker · $($NetDrives.Count) Netzlaufwerk(e)"

    $container = $syncHash.DataDevices
    foreach ($printer in $Printers) {
        $marker = if ($printer.IsDefault) { ' (Standard)' } else { '' }
        [void]$container.Children.Add((New-WzInfoRow "$($printer.Name)$marker" $printer.Port -LabelWidth 220))
    }
    foreach ($drive in $NetDrives) {
        [void]$container.Children.Add((New-WzInfoRow "Laufwerk $($drive.Letter)" $drive.Target -Kind 'ok' -LabelWidth 220))
    }
    if ($Printers.Count -eq 0 -and $NetDrives.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Nichts eingerichtet' 'kein Drucker, kein Netzlaufwerk' -LabelWidth 220))
    }
}

function Write-WzDataKeys {
    param([Parameter(Mandatory = $true)]$Overview)

    $container = $syncHash.DataKeys
    $wlan = @($Overview.Wlan)
    $encrypted = @($Overview.Encrypted)
    $keys = $Overview.Keys

    $syncHash.DataKeysTitle.Text = "$($wlan.Count) WLAN-Netz(e) · $($encrypted.Count) verschlüsselte(s) Laufwerk(e)"

    $width = 200
    if ($keys.FirmwareKey) {
        [void]$container.Children.Add((New-WzInfoRow 'Windows-Schlüssel im UEFI' 'vorhanden' -Kind 'ok' -LabelWidth $width))
    } else {
        [void]$container.Children.Add((New-WzInfoRow 'Windows-Schlüssel im UEFI' 'keiner hinterlegt' -LabelWidth $width))
    }
    if ($keys.Channel) {
        [void]$container.Children.Add((New-WzInfoRow 'Lizenzart' `
            "$($keys.Channel) · endet auf $($keys.PartialKey)" -LabelWidth $width))
    }
    foreach ($office in @($keys.Office)) {
        [void]$container.Children.Add((New-WzInfoRow 'Office' "$($office.Name) · $($office.Channel)" -LabelWidth $width))
    }

    if ($wlan.Count -gt 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Gespeicherte WLAN-Netze' ($wlan -join ', ') -LabelWidth $width))
    }
    if ($encrypted.Count -gt 0) {
        [void]$container.Children.Add((New-WzInfoRow 'BitLocker aktiv auf' ($encrypted -join ', ') -Kind 'warn' -LabelWidth $width))
    }

    $syncHash.DataBtnWlan.IsEnabled = ($wlan.Count -gt 0)
    $syncHash.DataBtnBitLocker.IsEnabled = ($encrypted.Count -gt 0)
}

# --- Exporte ---------------------------------------------------------------

function Start-WzBookmarkExport {
    $browsers = @($syncHash.DataOverview.Browsers | Where-Object { @($_.BookmarkFiles).Count -gt 0 })
    if ($browsers.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title 'Lesezeichen sichern' `
        -Message 'Die Lesezeichen-Dateien werden auf den Datenträger kopiert. Passwörter sind nicht dabei — die bleiben verschlüsselt im Profil.' `
        -Items @($browsers | ForEach-Object { $_.Name }) `
        -ConfirmText 'Sichern'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Lesezeichen sichern' -ArgumentList (, $browsers) -ScriptBlock {
        param($list)
        Export-WzBrowserBookmarks -Browsers $list
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzInfo -Title 'Lesezeichen' `
            -Message "$($result.Count) Datei(en) gesichert." -Items @($result.Path)
    }
}

function Start-WzWlanExport {
    $wlan = @($syncHash.DataOverview.Wlan)
    if ($wlan.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title 'WLAN-Netze sichern' `
        -Message ("$($wlan.Count) gespeicherte Netz(e) werden als Dateien auf den Datenträger geschrieben.`n`n" +
            'Mit Schlüsseln stehen die WLAN-Passwörter im Klartext in diesen Dateien. Das ist der Sinn der Sache — ' +
            'ohne sie kommt der PC nach dem Neuaufsetzen nicht ins Netz. Der Datenträger gehört danach nicht in fremde Hände.') `
        -Items $wlan `
        -Choices @('mit Schlüsseln (Klartext)', 'nur die Netznamen') `
        -ChoiceLabel 'Umfang' -ChoiceDefault 0 `
        -ConfirmText 'Sichern' -Danger
    if (-not $answer.Confirmed) { return }

    # Der Hinweistext wird schon im Hintergrund gesetzt: OnComplete läuft in
    # einem eigenen Bereich und sieht die Variablen von hier oben nicht.
    Invoke-WzTask -Name 'WLAN-Netze sichern' -ArgumentList @(($answer.SelectedIndex -eq 0)) -ScriptBlock {
        param($withKeys)
        $export = if ($withKeys) { Export-WzWlanProfiles -IncludeKeys } else { Export-WzWlanProfiles }
        $note = if ($withKeys) { 'Die Dateien enthalten die Passwörter im Klartext.' } else { 'Die Dateien enthalten keine Passwörter.' }
        [pscustomobject]@{ Count = $export.Count; Path = $export.Path; Note = $note }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzInfo -Title 'WLAN gesichert' `
            -Message "$($result.Count) Netz(e) gesichert. $($result.Note)" -Items @($result.Path)
    }
}

function Start-WzBitLockerExport {
    $encrypted = @($syncHash.DataOverview.Encrypted)
    if ($encrypted.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title 'BitLocker-Schlüssel sichern' `
        -Message ("Die Wiederherstellungsschlüssel für $($encrypted -join ', ') werden als Textdatei im Sicherungsordner abgelegt.`n`n" +
            'Mit diesem Schlüssel lässt sich das Laufwerk öffnen. Er gehört an einen sicheren Ort — ohne ihn ist das ' +
            'Laufwerk nach einem Mainboardtausch oder BIOS-Update aber unwiederbringlich zu.') `
        -ConfirmText 'Sichern' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'BitLocker-Schlüssel sichern' -ScriptBlock {
        $keys = Get-WzBitLockerKeys
        $path = Save-WzBitLockerKeys -Keys $keys
        [pscustomobject]@{ Count = @($keys).Count; Path = $path }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $message = if ($result.Count -eq 0) {
            'Es ließ sich kein Schlüssel auslesen. Dafür sind Administratorrechte nötig.'
        } elseif ($result.Path) {
            "$($result.Count) Schlüssel gesichert. Die Datei bitte vertraulich behandeln."
        } else {
            "$($result.Count) Schlüssel gefunden — im Testmodus wurde nichts geschrieben."
        }
        Show-WzInfo -Title 'BitLocker' -Message $message -Items @($result.Path | Where-Object { $_ })
    }
}

function Start-WzUserDataReport {
    if (-not $syncHash.DataOverview) { return }

    Invoke-WzTask -Name 'Übernahme-Bericht erstellen' -ArgumentList @($syncHash.DataOverview) -ScriptBlock {
        param($overview)
        New-WzUserDataReport -Overview $overview
    } -OnComplete {
        param($path)
        if (-not $path) { return }
        Show-WzInfo -Title 'Bericht erstellt' `
            -Message 'Der Übernahme-Bericht liegt im Ordner reports. Zum Ausdrucken im Browser öffnen und dort »Drucken« wählen.' `
            -Items @($path)
    }
}
