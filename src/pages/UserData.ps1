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
        -Text 'Die Bestandsaufnahme liest nur. Die Knöpfe darunter schreiben — Exporte auf den Datenträger, der Dateiumzug auf ein zweites Laufwerk, das OneDrive-Herunterladen auf die Systemplatte. Jeder fragt vorher und sagt genau, was passiert. Gelöscht wird nie etwas.'))
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

    Invoke-WzTask -Name 'Daten aufnehmen' -Cancelable -ScriptBlock {
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

        # Ein Profil, an dem seit Jahren niemand angemeldet war, muss beim Umzug
        # nicht mit — ohne diese Zeile wandern Karteileichen kommentarlos mit.
        if (-not $profileEntry.IsCurrent -and $profileEntry.LastUse) {
            $ago = Format-WzAgo $profileEntry.LastUse
            $stale = ((Get-Date) - [datetime]$profileEntry.LastUse).TotalDays -ge 365
            [void]$container.Children.Add((New-WzInfoRow '    zuletzt benutzt' `
                $(if ($stale) { "$ago — vermutlich nicht mehr in Gebrauch" } else { $ago }) `
                -Kind $(if ($stale) { 'warn' } else { 'normal' }) -LabelWidth 250))
        }

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
    $incomplete = (@($State.Folders | Where-Object { $_.Incomplete }).Count -gt 0)
    $syncHash.DataOneDriveTitle.Text = if ($incomplete) {
        'Prüfung unvollständig — Ordner sehr groß'
    } elseif ($cloudOnly -gt 0) {
        "$cloudOnly Datei(en) liegen nur in der Cloud"
    } else {
        'Alle Dateien liegen auch auf der Platte'
    }

    if ($State.PlaceholderWarning) {
        [void]$syncHash.DataOneDriveNotice.Items.Add((New-WzNotice -Kind 'warn' -Text $State.PlaceholderWarning))
        if (-not $incomplete) {
            Write-WzLog "OneDrive: $cloudOnly Datei(en) sind nur Platzhalter — vor dem Kopieren herunterladen." -Level Warn
        }
    }

    foreach ($folder in $State.Folders) {
        [void]$container.Children.Add((New-WzInfoRow $folder.Account $folder.Path -LabelWidth 250))
        $suffix = if ($folder.Incomplete) { ' (unvollständig gezählt)' } else { '' }
        [void]$container.Children.Add((New-WzInfoRow '    auf der Platte' `
            "$(Format-WzBytes $folder.LocalBytes) · $($folder.LocalFiles) Datei(en)$suffix" `
            -Kind $(if ($folder.Incomplete) { 'warn' } else { 'ok' }) -LabelWidth 250))
        if ($folder.CloudOnly -gt 0) {
            [void]$container.Children.Add((New-WzInfoRow '    nur in der Cloud' `
                "$($folder.CloudOnly) Datei(en)$suffix" -Kind 'warn' -LabelWidth 250))
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
        $syncHash.DataMoveTitle.Text = 'Keine Ordner zum Kopieren gefunden'
        [void]$container.Children.Add((New-WzInfoRow 'Hinweis' `
            'Ohne Zugriff auf die persönlichen Ordner lässt sich nichts kopieren. Mit Administratorrechten starten, dann sind auch fremde Konten lesbar.' `
            -Kind 'warn' -LabelWidth 220))
        $syncHash.DataBtnMove.IsEnabled = $false
        return
    }

    $largest = ($usable | Measure-Object -Property TotalBytes -Maximum).Maximum
    foreach ($volume in $volumes) {
        $notes = @()
        if ($volume.IsWinZii) { $notes += 'WinZii liegt hier — für Kundendaten ungeeignet' }
        if ($volume.IsFat32) { $notes += 'FAT32: keine Datei über 4 GB' }
        if ($volume.FreeBytes -lt $largest) { $notes += 'zu wenig Platz für das größte Konto' }
        $kind = if ($notes.Count -gt 0) { 'warn' } elseif ($volume.IsRemovable) { 'ok' } else { 'normal' }

        $text = "$(Format-WzBytes $volume.FreeBytes) frei von $(Format-WzBytes $volume.SizeBytes)"
        if ($notes.Count -gt 0) { $text += ' · ' + ($notes -join ' · ') }
        [void]$container.Children.Add((New-WzInfoRow "$($volume.Letter) $($volume.Label)" $text `
            -Kind $kind -LabelWidth 220))
    }

    if ($volumes.Count -eq 0) {
        $syncHash.DataMoveTitle.Text = 'Kein Ziellaufwerk vorhanden'
        [void]$container.Children.Add((New-WzInfoRow 'Hinweis' `
            'Außer dem Systemlaufwerk ist nichts angeschlossen. Eine Sicherung auf dieselbe Platte überlebt keine Neuinstallation — bitte eine externe Platte anstecken.' `
            -Kind 'warn' -LabelWidth 220))
        $syncHash.DataBtnMove.IsEnabled = $false
        return
    }

    $syncHash.DataMoveTitle.Text = "$($usable.Count) Konto/Konten · $($volumes.Count) mögliche(s) Ziel(e)"
    $syncHash.DataBtnMove.IsEnabled = $true
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
        # Der Treibername gehört dazu: Nach einer Neuinstallation ist genau er
        # die Antwort auf »welchen Treiber muss ich jetzt suchen?«.
        $detail = @($printer.Port, $printer.Driver) | Where-Object { $_ }
        [void]$container.Children.Add((New-WzInfoRow "$($printer.Name)$marker" `
            ($detail -join ' · ') -LabelWidth 220))
    }
    foreach ($drive in $NetDrives) {
        [void]$container.Children.Add((New-WzInfoRow "Laufwerk $($drive.Letter)" $drive.Target -Kind 'ok' -LabelWidth 220))
    }
    if ($Printers.Count -eq 0 -and $NetDrives.Count -eq 0) {
        [void]$container.Children.Add((New-WzInfoRow 'Nichts eingerichtet' 'kein Drucker, kein Netzlaufwerk' -LabelWidth 220))
    }
    $syncHash.DataBtnDevices.IsEnabled = ($Printers.Count -gt 0 -or $NetDrives.Count -gt 0)
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
        Add-WzAction -Area 'Datensicherung' `
            -Summary "Lesezeichen von $($result.Count) Browser-Profil(en) gesichert" -Detail @($result.Path)
        Show-WzInfo -Title 'Lesezeichen' `
            -Message "$($result.Count) Datei(en) gesichert." -Items @($result.Path)
    }
}

function Start-WzOneDriveHydration {
    $folders = @($syncHash.DataOverview.OneDrive.Folders)
    if ($folders.Count -eq 0) { return }

    $cloudOnly = ($folders | Measure-Object -Property CloudOnly -Sum).Sum
    $running = [bool](Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)

    $message = "OneDrive wird angewiesen, alle Dateien dauerhaft auf diesem PC zu behalten. Erst danach kopiert eine Sicherung echte Dateien statt leerer Platzhalter — hier sind es $cloudOnly Stück." + "`n`n" +
        'Das braucht Platz auf der Systemplatte und dauert je nach Menge und Leitung lange. WinZii wartet höchstens 15 Minuten mit und meldet dann ehrlich, ob es fertig wurde.'
    if (-not $running) {
        $message += "`n`nOneDrive läuft gerade nicht. Ohne den Dienst passiert nichts — bitte zuerst starten und anmelden."
    }

    $items = @($folders | ForEach-Object { "$($_.Path) — $($_.CloudOnly) Platzhalter" })
    $answer = Show-WzConfirm -Title 'Alle Dateien herunterladen' -Message $message -Items $items `
        -ConfirmText 'Herunterladen' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'OneDrive herunterladen' -Cancelable -ArgumentList (, @($folders | ForEach-Object { $_.Path })) -ScriptBlock {
        param($paths)
        @($paths | ForEach-Object { Invoke-WzOneDriveHydration -Path $_ })
    } -OnComplete {
        param($results)
        if (-not $results) { return }
        $lines = @($results | ForEach-Object {
            if ($_.Complete) { "$($_.Path): vollständig heruntergeladen" }
            elseif ($_.Started) { "$($_.Path): noch $($_.Remaining) Platzhalter — $($_.Reason)" }
            else { "$($_.Path): nicht gestartet — $($_.Reason)" }
        })
        $allDone = -not (@($results | Where-Object { -not $_.Complete }).Count -gt 0)
        [void](Show-WzConfirm -Title 'OneDrive' -HideCancel -ConfirmText 'Verstanden' `
            -Message $(if ($allDone) {
                'Alle Dateien liegen jetzt auf der Platte. Eine Sicherung erfasst sie damit vollständig.'
            } else {
                'Noch nicht fertig. Erst kopieren, wenn keine Platzhalter mehr übrig sind — sonst landen leere Hüllen in der Sicherung.'
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
        $answer = Show-WzConfirm -Title 'Konto wählen' `
            -Message 'Von welchem Konto sollen die persönlichen Ordner kopiert werden?' `
            -Choices @($profiles | ForEach-Object { "$($_.Account) — $(Format-WzBytes $_.TotalBytes)" }) `
            -ChoiceLabel 'Konto' -ConfirmText 'Weiter'
        if (-not $answer.Confirmed) { return }
        $profileChoice = $answer.SelectedIndex
    }
    $selected = $profiles[$profileChoice]

    $labels = @($volumes | ForEach-Object {
        $note = if ($_.IsWinZii) { ' — WinZii-Datenträger' } elseif ($_.IsRemovable) { ' — Wechseldatenträger' } else { '' }
        "$($_.Letter) $($_.Label) · $(Format-WzBytes $_.FreeBytes) frei$note"
    })
    $answer = Show-WzConfirm -Title 'Ziel wählen' `
        -Message ("$($selected.Account) belegt $(Format-WzBytes $selected.TotalBytes). Wohin soll die Kopie?`n`n" +
            'Eine externe Platte ist die richtige Wahl. Der Technikerstick nicht: Dort liegen bis zu vier Gigabyte Office-Vorrat, und Kundendaten gehören nicht auf ein Werkzeug, das am nächsten PC wieder steckt.') `
        -Choices $labels -ChoiceLabel 'Ziel' -ConfirmText 'Weiter'
    if (-not $answer.Confirmed) { return }
    $target = $volumes[$answer.SelectedIndex]

    $jobs = @(New-WzMigrationJobs -UserProfile $selected -Target "$($target.Letter)\")
    if ($jobs.Count -eq 0) { return }

    $warnings = @()
    if ($target.FreeBytes -lt $selected.TotalBytes) {
        $warnings += "Auf $($target.Letter) sind nur $(Format-WzBytes $target.FreeBytes) frei — das reicht nicht für $(Format-WzBytes $selected.TotalBytes)."
    }
    if ($target.IsFat32) {
        $warnings += 'Das Ziel ist FAT32: Dateien über 4 GB scheitern einzeln, der Rest wird trotzdem kopiert.'
    }
    if ($target.IsWinZii) {
        $warnings += 'Das Ziel ist der WinZii-Datenträger. Kundendaten haben darauf nichts verloren.'
    }

    $message = "Die Ordner werden nach $($target.Letter)\WinZii-Daten\$env:COMPUTERNAME\ kopiert. Die Quelle bleibt vollständig erhalten — WinZii löscht und verschiebt nichts."
    if ($warnings.Count -gt 0) { $message += "`n`n" + ($warnings -join "`n") }

    $answer = Show-WzConfirm -Title 'Dateien kopieren' -Message $message `
        -Items @($jobs | ForEach-Object { "$($_.Name) — $(Format-WzBytes $_.Bytes) in $($_.Items) Datei(en)" }) `
        -ConfirmText 'Kopieren' -Danger:($warnings.Count -gt 0)
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Dateien kopieren' -Cancelable -ArgumentList (, $jobs) -ScriptBlock {
        param($jobs)
        Invoke-WzFileMigration -Jobs $jobs
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $lines = @($result.Applied) + @($result.Failed | ForEach-Object { "fehlgeschlagen: $_" })
        if ($lines.Count -eq 0) { $lines = @('Es wurde nichts kopiert.') }
        [void](Show-WzConfirm -Title 'Dateiumzug' -HideCancel -ConfirmText 'Verstanden' `
            -Message $(if (@($result.Failed).Count -gt 0) {
                'Ein Teil hat nicht geklappt. Die Gründe stehen im Protokoll. Die Quelle ist unverändert.'
            } else {
                "$(Format-WzBytes $result.CopiedBytes) kopiert. Bitte auf dem Ziel stichprobenartig nachsehen, bevor am Quell-PC etwas gelöscht wird."
            }) -Items $lines)
    }
}

function Start-WzDeviceExport {
    $printers = @($syncHash.DataOverview.Printers)
    $drives = @($syncHash.DataOverview.NetDrives)
    if ($printers.Count -eq 0 -and $drives.Count -eq 0) { return }

    $items = @($printers | ForEach-Object { "$($_.Name) an $($_.Port)" }) +
             @($drives | ForEach-Object { "Laufwerk $($_.Letter) auf $($_.Target)" })

    $answer = Show-WzConfirm -Title 'Geräteliste sichern' `
        -Message 'Drucker und Netzlaufwerke werden als geraete.json auf den Datenträger geschrieben. Auf der Seite »Zurückspielen« lassen sie sich damit nach dem Neuaufsetzen wieder anlegen. Kennwörter für geschützte Freigaben sind nicht dabei.' `
        -Items $items -ConfirmText 'Sichern'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Geräteliste sichern' -ArgumentList @($printers, $drives) -ScriptBlock {
        param($printers, $drives)
        Export-WzDeviceList -Printers $printers -NetDrives $drives
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Datensicherung' `
            -Summary "Drucker und Netzlaufwerke gesichert ($($result.Count) Eintrag/Einträge)" -Detail @($result.Path)
        Show-WzInfo -Title 'Geräteliste' `
            -Message "$($result.Count) Eintrag/Einträge gesichert." -Items @($result.Path)
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
        Add-WzAction -Area 'Datensicherung' `
            -Summary "$($result.Count) WLAN-Netz(e) gesichert. $($result.Note)" -Detail @($result.Path)
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
        if ($result.Path) {
            # Bewusst nur Anzahl und Ablageort — die Schlüssel selbst gehören
            # in keinen Bericht und in kein Protokoll.
            Add-WzAction -Area 'Datensicherung' `
                -Summary "$($result.Count) BitLocker-Wiederherstellungsschlüssel gesichert" -Detail @($result.Path)
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
