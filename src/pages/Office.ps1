# Seite "Office" — Auswahl der Ausgabe, Sprache und Programme; danach
# Installation oder Ablage auf dem Datenträger.

function Initialize-WzOfficePage {
    $catalog = Get-WzOfficeCatalog

    foreach ($variant in $catalog.variants) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = $variant.name
        $item.Tag = $variant
        [void]$syncHash.OffVariant.Items.Add($item)
    }
    $syncHash.OffVariant.SelectedIndex = 0
    $syncHash.OffVariant.Add_SelectionChanged({ Update-WzOfficeSelection })

    foreach ($language in $catalog.languages) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = $language.name
        $item.Tag = $language.id
        [void]$syncHash.OffLanguage.Items.Add($item)
    }
    $syncHash.OffLanguage.SelectedIndex = 0
    $syncHash.OffLanguage.Add_SelectionChanged({ Update-WzOfficeSelection })

    $syncHash.OffAppBoxes = @()
    foreach ($app in $catalog.apps) {
        $checkBox = New-Object Windows.Controls.CheckBox
        $checkBox.Content = $app.name
        $checkBox.IsChecked = [bool]$app.defaultIncluded
        $checkBox.Style = $syncHash.Window.FindResource('WzCheckBox')
        $checkBox.Margin = New-Object Windows.Thickness(0, 4, 0, 4)
        $checkBox.Tag = $app
        [void]$syncHash.OffApps.Children.Add($checkBox)
        $syncHash.OffAppBoxes += $checkBox
    }

    $syncHash.OffBtnInstall.Add_Click({ Start-WzOfficeInstall })
    $syncHash.OffBtnDownload.Add_Click({ Start-WzOfficeDownload })
    $syncHash.OffBtnXml.Add_Click({ Show-WzOfficeXml })
    $syncHash.OffBtnLibre.Add_Click({ Start-WzLibreOfficeInstall })
    $syncHash.OffBtnRemove.Add_Click({ Start-WzOfficeRemove })

    Update-WzOfficeSelection
}

function Update-WzOfficePage {
    if ($syncHash.OffChecked) { return }
    $syncHash.OffChecked = $true

    Invoke-WzTask -Name 'Office prüfen' -Silent -ScriptBlock {
        Get-WzInstalledOffice
    } -OnComplete {
        param($office)
        if (-not $office) { return }

        $syncHash.OffInstalledTitle.Text = $office.Name
        $rows = $syncHash.OffInstalledRows
        $rows.Children.Clear()

        if ($office.Installed) {
            [void]$rows.Children.Add((New-WzInfoRow 'Version' $office.Version -Kind 'ok'))
            if ($office.Details) { [void]$rows.Children.Add((New-WzInfoRow 'Merkmale' $office.Details)) }
            [void]$rows.Children.Add((New-WzInfoRow 'Hinweis' 'Eine Neuinstallation ersetzt die vorhandene Fassung'))
        } else {
            [void]$rows.Children.Add((New-WzInfoRow 'Zustand' 'Auf diesem PC ist kein Office installiert'))
        }
        Write-WzLog "Office: $($office.Name)" -Level Info
    }
}

function Get-WzOfficeChoice {
    <#
    .SYNOPSIS
        Aktuelle Auswahl der Seite als Objekt.
    #>
    $variant = $syncHash.OffVariant.SelectedItem.Tag
    $language = $syncHash.OffLanguage.SelectedItem.Tag
    $apps = @($syncHash.OffAppBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag.id })

    return [pscustomobject]@{
        Variant  = $variant
        Language = $language
        Apps     = $apps
        Key      = $syncHash.OffKey.Text.Trim()
    }
}

function Update-WzOfficeSelection {
    if (-not $syncHash.OffVariant.SelectedItem) { return }
    $choice = Get-WzOfficeChoice

    $syncHash.OffVariantNote.Text = "$($choice.Variant.description) $($choice.Variant.note)"

    # Publisher gibt es in Office 2024 nicht mehr. Beim Zurückwechseln muss der
    # Haken wieder gesetzt werden — sonst bliebe er für den Rest der Sitzung weg.
    foreach ($checkBox in $syncHash.OffAppBoxes) {
        $app = $checkBox.Tag
        if (-not $app.PSObject.Properties['maxVariant']) { continue }
        if ($choice.Variant.id -eq 'office2024') {
            $checkBox.IsEnabled = $false
            $checkBox.IsChecked = $false
            $checkBox.Content = "$($app.name) (in dieser Ausgabe nicht enthalten)"
        } else {
            $checkBox.IsEnabled = $true
            $checkBox.IsChecked = [bool]$app.defaultIncluded
            $checkBox.Content = $app.name
        }
    }

    # Der Schlüssel wird nur bei den Volumenvarianten gebraucht
    $syncHash.OffKeyPanel.Visibility = if ($choice.Variant.productId -like '*Volume') {
        [Windows.Visibility]::Visible
    } else {
        [Windows.Visibility]::Collapsed
    }

    $cache = Test-WzOfficeCache -VariantId $choice.Variant.id -Language $choice.Language
    $syncHash.OffCacheHint.Text = if ($cache.Available) {
        "Auf dem Datenträger liegen bereits $(Format-WzBytes $cache.Bytes) — die Installation läuft ohne Internet."
    } elseif ($cache.Bytes -gt 0) {
        "Auf dem Datenträger liegen $(Format-WzBytes $cache.Bytes), der Satz ist aber $($cache.Detail). Die Installation lädt von Microsoft."
    } else {
        'Für diese Auswahl liegt noch nichts auf dem Datenträger. Die Installation lädt die Dateien von Microsoft.'
    }
}

function Show-WzOfficeXml {
    $choice = Get-WzOfficeChoice
    if ($choice.Apps.Count -eq 0) {
        Show-WzInfo -Title 'Kein Programm gewählt' -Message 'Bitte mindestens ein Office-Programm auswählen.'
        return
    }

    $file = New-WzOfficeConfigXml -VariantId $choice.Variant.id -Language $choice.Language -IncludedApps $choice.Apps
    $content = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)

    Show-WzInfo -Title 'Konfiguration für das Bereitstellungswerkzeug' `
        -Message "Diese Datei steuert die Installation. Sie liegt unter $file." `
        -Items @($content -split "`r?`n")
}

function Start-WzOfficeInstall {
    $choice = Get-WzOfficeChoice
    if ($choice.Apps.Count -eq 0) {
        Show-WzInfo -Title 'Kein Programm gewählt' -Message 'Bitte mindestens ein Office-Programm auswählen.'
        return
    }

    $cache = Test-WzOfficeCache -VariantId $choice.Variant.id -Language $choice.Language
    $languageName = $syncHash.OffLanguage.SelectedItem.Content

    $items = @("Ausgabe: $($choice.Variant.name)", "Sprache: $languageName")
    $items += "Programme: $($choice.Apps -join ', ')"
    $items += if ($cache.Available) { 'Quelle: Datenträger (kein Internet nötig)' } else { 'Quelle: Microsoft (Internet nötig)' }

    # Die Installation läuft mit FORCEAPPSHUTDOWN: laufende Office-Programme
    # werden ohne eigene Nachfrage beendet. Das gehört in den Dialog — sonst
    # verliert der Kunde ein offenes, ungespeichertes Dokument.
    $officeProcessNames = @{
        winword = 'Word'; excel = 'Excel'; powerpnt = 'PowerPoint'; outlook = 'Outlook'
        onenote = 'OneNote'; msaccess = 'Access'; visio = 'Visio'; mspub = 'Publisher'
    }
    $running = @(Get-Process -Name @($officeProcessNames.Keys) -ErrorAction SilentlyContinue |
        ForEach-Object { $officeProcessNames[$_.ProcessName.ToLower()] } | Sort-Object -Unique)
    foreach ($name in $running) {
        $items += "Läuft gerade: $name — wird beim Installieren beendet, ungespeicherte Dokumente gehen verloren"
    }

    # Vorhandenes Office in anderer Bitness blockiert die Installation — ODT
    # bricht dann ab, ohne verlässlich einen Fehlercode zu liefern. Das ist der
    # Klassiker auf Laptops mit vorinstalliertem 32-Bit-OEM-Office.
    $installed = Get-WzInstalledOffice
    $edition = '64'
    if ($installed.Installed -and $installed.Bitness -and $installed.Bitness -ne '64') {
        $conflict = Show-WzConfirm -Title 'Vorhandenes Office steht im Weg' `
            -Message "Auf diesem PC ist $($installed.Name) als $($installed.Bitness)-Bit-Fassung installiert. Eine 64-Bit-Installation daneben lehnt Windows ab. Entweder wird das vorhandene Office zuerst entfernt, oder die neue Fassung wird ebenfalls als $($installed.Bitness)-Bit eingerichtet." `
            -Items @("Vorhanden: $($installed.Name)", "Merkmale: $($installed.Details)") `
            -Choices @("$($installed.Bitness)-Bit installieren, vorhandenes ersetzen", 'Vorhandenes zuerst entfernen') `
            -ChoiceLabel 'Vorgehen' -ConfirmText 'Weiter'
        if (-not $conflict.Confirmed) { return }
        if ($conflict.SelectedIndex -eq 1) {
            Start-WzOfficeRemove
            return
        }
        $edition = $installed.Bitness
        $items += "Bitness: $edition-Bit (wie die vorhandene Installation)"
    }

    if ($choice.Variant.productId -like '*Volume' -and -not $choice.Key) {
        $items += 'Ohne Volumenlizenz-Schlüssel: Office wird installiert, aber nicht aktiviert'
    }

    $message = 'Office wird installiert. Vorhandene Office-Versionen werden dabei ersetzt, laufende Office-Programme werden ohne Nachfrage beendet. Der Vorgang dauert je nach Verbindung 10 bis 30 Minuten.'
    if ($running.Count -gt 0) { $message += ' Bitte vorher alle offenen Dokumente speichern.' }
    if ($choice.Variant.note) { $message += " $($choice.Variant.note)" }

    $answer = Show-WzConfirm -Title 'Office installieren' -Message $message -Items $items `
        -ConfirmText $(if ($syncHash.DryRun) { 'Testlauf starten' } else { 'Installieren' }) -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Office installieren' -Cancelable `
        -ArgumentList @($choice.Variant.id, $choice.Language, $choice.Apps, $choice.Key, $edition) -ScriptBlock {
        param($variantId, $language, $apps, $key, $edition)
        Invoke-WzOfficeInstall -VariantId $variantId -Language $language -IncludedApps $apps `
            -ProductKey $key -Edition $edition
    } -OnComplete {
        param($ok)
        $syncHash.OffChecked = $false
        Update-WzOfficePage
        if ($syncHash.DryRun) {
            Show-WzInfo -Title 'Testlauf beendet' `
                -Message 'Es wurde nichts verändert. Im Protokoll steht, was passiert wäre.'
            return
        }
        if ($ok) {
            # Erst festhalten, wenn Office wirklich nachweisbar da ist
            Add-WzAction -Area 'Office' -Summary "$($choice.Variant.name) installiert ($($choice.Language))" `
                -Detail @($choice.Apps)
            Show-WzInfo -Title 'Office eingerichtet' `
                -Message 'Beim ersten Start ist die Anmeldung beziehungsweise die Eingabe des Lizenzschlüssels nötig.'
        } else {
            Show-WzInfo -Title 'Nicht abgeschlossen' `
                -Message 'Die Installation lief nicht durch. Die Fehlernummern des Bereitstellungswerkzeugs stehen im Protokoll; die Protokolldatei liegt unter offline\odt\logs.'
        }
    }.GetNewClosure()
}

function Start-WzOfficeRemove {
    <#
    .SYNOPSIS
        Office entfernen — gestuft, mit Wiederherstellungspunkt bei der
        gründlichen Variante.
    #>
    $installed = Get-WzInstalledOffice
    $remnants = Get-WzOfficeRemnants

    if (-not $installed.Installed -and $remnants.Items.Count -eq 0) {
        Show-WzInfo -Title 'Kein Office gefunden' `
            -Message 'Auf diesem PC ist kein Microsoft Office installiert. Es gibt nichts zu entfernen.'
        return
    }

    $items = @()
    if ($installed.Installed) { $items += "$($installed.Name) — $($installed.Details)" }
    $items += $remnants.Items

    $answer = Show-WzConfirm -Title 'Office entfernen' `
        -Message ('Office wird über das offizielle Bereitstellungswerkzeug von Microsoft entfernt. Laufende Office-Programme werden dabei ohne Nachfrage beendet — bitte vorher alle Dokumente speichern.' + [Environment]::NewLine + [Environment]::NewLine +
            'Gründlich entfernt zusätzlich die Store-Fassung und die Ordner, die das Werkzeug stehen lässt. Das lässt sich nicht rückgängig machen; dafür wird vorher ein Wiederherstellungspunkt angelegt.') `
        -Items $items `
        -Choices @('Sauber entfernen (empfohlen)', 'Gründlich entfernen, samt Resten') `
        -ChoiceLabel 'Umfang' `
        -ConfirmText $(if ($syncHash.DryRun) { 'Testlauf starten' } else { 'Entfernen' }) -Danger
    if (-not $answer.Confirmed) { return }

    $thorough = ($answer.SelectedIndex -eq 1)
    if ($thorough -and -not $syncHash.DryRun) {
        $sure = Show-WzConfirm -Title 'Gründlich entfernen' `
            -Message 'Dabei werden auch Ordner gelöscht, in denen Vorlagen oder Erweiterungen liegen können. Es gibt keinen Rückweg.' `
            -Items @($remnants.Items) -ConfirmText 'Trotzdem gründlich entfernen' -Danger
        if (-not $sure.Confirmed) { return }
        [void](New-WzRestorePoint -Description 'WinZii: vor dem gründlichen Entfernen von Office')
    }

    Invoke-WzTask -Name 'Office entfernen' -Cancelable -ArgumentList @($thorough) -ScriptBlock {
        param($thorough)
        Remove-WzOffice -Thorough:$thorough
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        $syncHash.OffChecked = $false
        Update-WzOfficePage

        if ($syncHash.DryRun) {
            Show-WzInfo -Title 'Testlauf beendet' `
                -Message 'Es wurde nichts entfernt. Im Protokoll steht, was passiert wäre.' `
                -Items @($summary.Details)
            return
        }

        $lines = @($summary.Steps) + @($summary.Details)
        if ($lines.Count -eq 0) { $lines = @('Es gab nichts zu tun.') }
        Show-WzInfo -Title $(if ($summary.Ok) { 'Office entfernt' } else { 'Nicht vollständig entfernt' }) `
            -Message $(if ($summary.Ok) {
                'Office ist entfernt. Ein Neustart räumt die letzten Reste weg.'
            } else {
                'Es ist noch Office auffindbar. Einzelheiten stehen unten und im Protokoll.'
            }) -Items $lines
    }
}

function Start-WzOfficeDownload {
    $choice = Get-WzOfficeChoice
    if ($choice.Apps.Count -eq 0) { return }

    $volume = Get-WzVolumeInfo
    if ($volume.IsFat32) {
        Show-WzInfo -Title 'Dateisystem ungeeignet' `
            -Message 'Der Datenträger ist mit FAT32 formatiert. Office-Pakete sind größer als die dort mögliche Dateigröße von 4 GB. Bitte den Stick mit exFAT oder NTFS formatieren.'
        return
    }

    $languageName = $syncHash.OffLanguage.SelectedItem.Content
    $answer = Show-WzConfirm -Title 'Office auf den Datenträger laden' `
        -Message "Die Installationsdateien werden auf dem WinZii-Datenträger abgelegt. Danach lässt sich Office auf jedem PC ohne Internet einrichten. Benötigt werden etwa 4 GB, frei sind $(Format-WzBytes $volume.FreeBytes)." `
        -Items @("Ausgabe: $($choice.Variant.name)", "Sprache: $languageName") -ConfirmText 'Laden'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Office laden' -ArgumentList @($choice.Variant.id, $choice.Language, $choice.Apps) -ScriptBlock {
        param($variantId, $language, $apps)
        Invoke-WzOfficeDownload -VariantId $variantId -Language $language -IncludedApps $apps
    } -OnComplete {
        param($ok)
        Update-WzOfficeSelection
        if ($ok) {
            Show-WzInfo -Title 'Fertig' -Message 'Office liegt jetzt auf dem Datenträger und lässt sich ohne Internet installieren.'
        }
    }
}

function Start-WzLibreOfficeInstall {
    # Der Dialog versprach winget, ohne je zu prüfen, ob es da ist. Fehlte es,
    # brach die Installation mit 0/0/0 ab und meldete »lief nicht durch«, ohne
    # einen Weg vorwärts zu nennen.
    $winget = Test-WzWinget
    if (-not $winget.Available -and -not $syncHash.DryRun) {
        Show-WzInfo -Title 'winget fehlt' `
            -Message 'LibreOffice wird über winget installiert, und das ist auf diesem PC nicht einsatzbereit. Auf der Seite »Programme« lässt es sich mit »winget einrichten« nachinstallieren.' `
            -Items @($(if ($winget.Path) { "Gefunden, aber nicht lauffähig: $($winget.Path)" } else { 'winget wurde nicht gefunden.' }))
        return
    }

    $answer = Show-WzConfirm -Title 'LibreOffice installieren' `
        -Message 'LibreOffice wird über winget installiert. Es ist kostenfrei und braucht keinen Lizenzschlüssel.' `
        -ConfirmText 'Installieren'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'LibreOffice installieren' -Cancelable -ScriptBlock {
        Install-WzLibreOffice
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        if ($syncHash.DryRun) {
            Show-WzInfo -Title 'Testlauf beendet' -Message 'Es wurde nichts installiert.'
            return
        }
        if ($summary.Installed -gt 0) {
            Add-WzAction -Area 'Office' -Summary 'LibreOffice installiert' `
                -RebootRequired:$summary.RebootRequired
            Show-WzInfo -Title 'LibreOffice eingerichtet' `
                -Message $(if ($summary.RebootRequired) {
                    'Die Installation ist abgeschlossen. Ein Neustart schließt sie ab.'
                } else {
                    'Die Installation ist abgeschlossen.'
                })
        } elseif ($summary.Skipped -gt 0) {
            Show-WzInfo -Title 'Bereits vorhanden' -Message 'LibreOffice ist auf diesem PC schon installiert.'
        } else {
            # Der Grund stand bisher nur als nackte Zahl im Protokoll
            Show-WzInfo -Title 'Nicht abgeschlossen' `
                -Message 'Die Installation lief nicht durch.' -Items @($summary.Details)
        }
    }
}
