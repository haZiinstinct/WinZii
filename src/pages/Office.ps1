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
    }
}

function Update-WzOfficeSelection {
    if (-not $syncHash.OffVariant.SelectedItem) { return }
    $choice = Get-WzOfficeChoice

    $syncHash.OffVariantNote.Text = "$($choice.Variant.description) $($choice.Variant.note)"

    # Publisher gibt es in Office 2024 nicht mehr
    foreach ($checkBox in $syncHash.OffAppBoxes) {
        $app = $checkBox.Tag
        if ($app.PSObject.Properties['maxVariant'] -and $choice.Variant.id -eq 'office2024') {
            $checkBox.IsEnabled = $false
            $checkBox.IsChecked = $false
            $checkBox.Content = "$($app.name) (in dieser Ausgabe nicht enthalten)"
        } elseif ($app.PSObject.Properties['maxVariant']) {
            $checkBox.IsEnabled = $true
            $checkBox.Content = $app.name
        }
    }

    $cache = Test-WzOfficeCache -VariantId $choice.Variant.id -Language $choice.Language
    $syncHash.OffCacheHint.Text = if ($cache.Available) {
        "Auf dem Datenträger liegen bereits $(Format-WzBytes $cache.Bytes) — die Installation läuft ohne Internet."
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

    $message = 'Office wird installiert. Vorhandene Office-Versionen werden dabei ersetzt. Der Vorgang dauert je nach Verbindung 10 bis 30 Minuten.'
    if ($choice.Variant.note) { $message += " $($choice.Variant.note)" }

    $answer = Show-WzConfirm -Title 'Office installieren' -Message $message -Items $items `
        -ConfirmText $(if ($syncHash.DryRun) { 'Testlauf starten' } else { 'Installieren' }) -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Office installieren' -ArgumentList @($choice.Variant.id, $choice.Language, $choice.Apps) -ScriptBlock {
        param($variantId, $language, $apps)
        Invoke-WzOfficeInstall -VariantId $variantId -Language $language -IncludedApps $apps
    } -OnComplete {
        param($ok)
        $syncHash.OffChecked = $false
        Update-WzOfficePage
        if ($ok) {
            Add-WzAction -Area 'Office' -Summary "$($choice.Variant.name) installiert ($($choice.Language))" `
                -Detail @($choice.Apps)
            Show-WzInfo -Title 'Office eingerichtet' `
                -Message 'Beim ersten Start ist die Anmeldung beziehungsweise die Eingabe des Lizenzschlüssels nötig.'
        } else {
            Show-WzInfo -Title 'Nicht abgeschlossen' -Message 'Die Installation lief nicht durch. Einzelheiten stehen im Protokoll.'
        }
    }.GetNewClosure()
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
    $answer = Show-WzConfirm -Title 'LibreOffice installieren' `
        -Message 'LibreOffice wird über winget installiert. Es ist kostenfrei und braucht keinen Lizenzschlüssel.' `
        -ConfirmText 'Installieren'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'LibreOffice installieren' -ScriptBlock {
        Install-WzLibreOffice
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        if ($summary.Installed -gt 0) {
            Show-WzInfo -Title 'LibreOffice eingerichtet' -Message 'Die Installation ist abgeschlossen.'
        } elseif ($summary.Skipped -gt 0) {
            Show-WzInfo -Title 'Bereits vorhanden' -Message 'LibreOffice ist auf diesem PC schon installiert.'
        } else {
            Show-WzInfo -Title 'Nicht abgeschlossen' -Message 'Die Installation lief nicht durch. Einzelheiten stehen im Protokoll.'
        }
    }
}
