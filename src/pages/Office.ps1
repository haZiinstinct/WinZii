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

    Invoke-WzTask -Name (Get-WzText 'off.taskCheck') -Silent -ScriptBlock {
        Get-WzInstalledOffice
    } -OnComplete {
        param($office)
        if (-not $office) { return }

        $syncHash.OffInstalledTitle.Text = $office.Name
        $rows = $syncHash.OffInstalledRows
        $rows.Children.Clear()

        if ($office.Installed) {
            [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'off.lblVersion') $office.Version -Kind 'ok'))
            if ($office.Details) { [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'off.lblFeatures') $office.Details)) }
            [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'off.lblHint') (Get-WzText 'off.hintReplaces')))
        } else {
            [void]$rows.Children.Add((New-WzInfoRow (Get-WzText 'off.lblState') (Get-WzText 'off.stateNone')))
        }
        Write-WzLog (Get-WzText 'off.logInstalled' @{ name = $office.Name }) -Level Info
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
            $checkBox.Content = Get-WzText 'off.appNotIncluded' @{ name = $app.name }
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
        Get-WzText 'off.cacheReady' @{ groesse = (Format-WzBytes $cache.Bytes) }
    } elseif ($cache.Bytes -gt 0) {
        Get-WzText 'off.cachePartial' @{ groesse = (Format-WzBytes $cache.Bytes); grund = $cache.Detail }
    } else {
        Get-WzText 'off.cacheNone'
    }
}

function Show-WzOfficeXml {
    $choice = Get-WzOfficeChoice
    if ($choice.Apps.Count -eq 0) {
        Show-WzInfo -Title 'Kein Programm gewählt' -Message 'Bitte mindestens ein Office-Programm auswählen.'
        return
    }

    # Bisher entstand hier eine Konfiguration ohne Quellpfad und ohne Bitness —
    # also genau die, die beim Installieren NICHT verwendet wird. Wer sie las,
    # sah etwas anderes, als später lief.
    $cache = Test-WzOfficeCache -VariantId $choice.Variant.id -Language $choice.Language
    $installed = Get-WzInstalledOffice
    $edition = if ($installed.Installed -and $installed.Bitness) { $installed.Bitness } else { '64' }

    $file = New-WzOfficeConfigXml -VariantId $choice.Variant.id -Language $choice.Language `
        -IncludedApps $choice.Apps -SourcePath $(if ($cache.Available) { $cache.Path } else { $null }) `
        -Edition $edition
    $content = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)

    # Der Lizenzschlüssel steht bewusst nicht darin: Er wird erst unmittelbar
    # vor dem Start eingesetzt und danach wieder entfernt.
    $hint = if ($choice.Key) { Get-WzText 'off.xmlKeyHint' } else { '' }

    Show-WzInfo -Title (Get-WzText 'off.xmlTitle') `
        -Message (Get-WzText 'off.xmlMessage' @{ pfad = $file; hinweis = $hint }) `
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

    $items = @((Get-WzText 'off.itemEdition' @{ name = $choice.Variant.name }), (Get-WzText 'off.itemLanguage' @{ name = $languageName }))
    $items += Get-WzText 'off.itemApps' @{ liste = ($choice.Apps -join ', ') }
    $items += if ($cache.Available) { Get-WzText 'off.sourceDrive' } else { Get-WzText 'off.sourceMicrosoft' }

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
        $items += Get-WzText 'off.itemRunning' @{ name = $name }
    }

    # Vorhandenes Office in anderer Bitness blockiert die Installation — ODT
    # bricht dann ab, ohne verlässlich einen Fehlercode zu liefern. Das ist der
    # Klassiker auf Laptops mit vorinstalliertem 32-Bit-OEM-Office.
    $installed = Get-WzInstalledOffice
    $edition = '64'
    if ($installed.Installed -and $installed.Bitness -and $installed.Bitness -ne '64') {
        $conflict = Show-WzConfirm -Title (Get-WzText 'off.conflictTitle') `
            -Message (Get-WzText 'off.conflictMessage' @{ name = $installed.Name; bit = $installed.Bitness }) `
            -Items @((Get-WzText 'off.itemPresent' @{ name = $installed.Name }), (Get-WzText 'off.itemDetails' @{ details = $installed.Details })) `
            -Choices @((Get-WzText 'off.choiceSameBitness' @{ bit = $installed.Bitness }), (Get-WzText 'off.choiceRemoveFirst')) `
            -ChoiceLabel (Get-WzText 'off.lblApproach') -ConfirmText (Get-WzText 'off.btnNext')
        if (-not $conflict.Confirmed) { return }
        if ($conflict.SelectedIndex -eq 1) {
            Start-WzOfficeRemove
            return
        }
        $edition = $installed.Bitness
        $items += Get-WzText 'off.itemBitness' @{ bit = $edition }
    }

    if ($choice.Variant.productId -like '*Volume' -and -not $choice.Key) {
        $items += Get-WzText 'off.itemNoVolumeKey'
    }

    $message = Get-WzText 'off.installMessage'
    if ($running.Count -gt 0) { $message += Get-WzText 'off.installSaveFirst' }
    if ($choice.Variant.note) { $message += " $($choice.Variant.note)" }

    $answer = Show-WzConfirm -Title (Get-WzText 'off.installTitle') -Message $message -Items $items `
        -ConfirmText $(if ($syncHash.DryRun) { Get-WzText 'off.btnDryRun' } else { Get-WzText 'off.btnInstallGo' }) -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'off.taskInstall') -Cancelable `
        -ArgumentList @($choice.Variant.id, $choice.Language, $choice.Apps, $choice.Key, $edition) -ScriptBlock {
        param($variantId, $language, $apps, $key, $edition)
        Invoke-WzOfficeInstall -VariantId $variantId -Language $language -IncludedApps $apps `
            -ProductKey $key -Edition $edition
    } -OnComplete {
        param($ok)
        $syncHash.OffChecked = $false
        Update-WzOfficePage
        if ($syncHash.DryRun) {
            Show-WzInfo -Title (Get-WzText 'off.dryRunTitle') `
                -Message (Get-WzText 'off.dryRunInstall')
            return
        }
        if ($ok) {
            # Erst festhalten, wenn Office wirklich nachweisbar da ist
            Add-WzAction -Area 'Office' -Summary (Get-WzText 'off.actionInstalled' @{ name = $choice.Variant.name; sprache = $choice.Language }) `
                -Detail @($choice.Apps)
            Show-WzInfo -Title (Get-WzText 'off.installOkTitle') `
                -Message (Get-WzText 'off.installOkMessage')
        } else {
            Show-WzInfo -Title (Get-WzText 'off.notFinishedTitle') `
                -Message (Get-WzText 'off.installFailMessage')
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
        Show-WzInfo -Title (Get-WzText 'off.noOfficeTitle') `
            -Message (Get-WzText 'off.noOfficeMessage')
        return
    }

    $items = @()
    if ($installed.Installed) { $items += Get-WzText 'off.itemInstalledDetail' @{ name = $installed.Name; details = $installed.Details } }
    $items += $remnants.Items

    $answer = Show-WzConfirm -Title (Get-WzText 'off.removeTitle') `
        -Message ((Get-WzText 'off.removeMessage') + [Environment]::NewLine + [Environment]::NewLine +
            (Get-WzText 'off.removeMessage2')) `
        -Items $items `
        -Choices @((Get-WzText 'off.choiceClean'), (Get-WzText 'off.choiceThorough')) `
        -ChoiceLabel (Get-WzText 'off.lblScope') `
        -ConfirmText $(if ($syncHash.DryRun) { Get-WzText 'off.btnDryRun' } else { Get-WzText 'off.btnRemoveGo' }) -Danger
    if (-not $answer.Confirmed) { return }

    $thorough = ($answer.SelectedIndex -eq 1)
    if ($thorough -and -not $syncHash.DryRun) {
        $sure = Show-WzConfirm -Title (Get-WzText 'off.thoroughTitle') `
            -Message (Get-WzText 'off.thoroughMessage') `
            -Items @($remnants.Items) -ConfirmText (Get-WzText 'off.btnThoroughAnyway') -Danger
        if (-not $sure.Confirmed) { return }
        [void](New-WzRestorePoint -Description (Get-WzText 'off.restorePointThorough'))
    }

    Invoke-WzTask -Name (Get-WzText 'off.taskRemove') -Cancelable -ArgumentList @($thorough) -ScriptBlock {
        param($thorough)
        Remove-WzOffice -Thorough:$thorough
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        $syncHash.OffChecked = $false
        Update-WzOfficePage

        if ($syncHash.DryRun) {
            Show-WzInfo -Title (Get-WzText 'off.dryRunTitle') `
                -Message (Get-WzText 'off.dryRunRemove') `
                -Items @($summary.Details)
            return
        }

        $lines = @($summary.Steps) + @($summary.Details)
        if ($lines.Count -eq 0) { $lines = @(Get-WzText 'off.nothingToDo') }
        Show-WzInfo -Title $(if ($summary.Ok) { Get-WzText 'off.removeOkTitle' } else { Get-WzText 'off.removePartialTitle' }) `
            -Message $(if ($summary.Ok) {
                Get-WzText 'off.removeOkMessage'
            } else {
                Get-WzText 'off.removePartialMessage'
            }) -Items $lines
    }
}

function Start-WzOfficeDownload {
    $choice = Get-WzOfficeChoice
    if ($choice.Apps.Count -eq 0) { return }

    # Derselbe Satz wie im Modul — die Prüfung hier erspart nur den vergeblichen
    # Start eines Vorgangs, der stundenlang laufen könnte.
    $target = Test-WzOfficeTarget
    if (-not $target.Ok) {
        Show-WzInfo -Title (Get-WzText 'off.badFsTitle') -Message $target.Message
        return
    }
    $volume = $target.Volume

    $languageName = $syncHash.OffLanguage.SelectedItem.Content
    $answer = Show-WzConfirm -Title (Get-WzText 'off.downloadTitle') `
        -Message (Get-WzText 'off.downloadMessage' @{ frei = (Format-WzBytes $volume.FreeBytes) }) `
        -Items @((Get-WzText 'off.itemEdition' @{ name = $choice.Variant.name }), (Get-WzText 'off.itemLanguage' @{ name = $languageName })) `
        -ConfirmText (Get-WzText 'off.btnDownloadGo')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'off.taskDownload') -ArgumentList @($choice.Variant.id, $choice.Language, $choice.Apps) -ScriptBlock {
        param($variantId, $language, $apps)
        Invoke-WzOfficeDownload -VariantId $variantId -Language $language -IncludedApps $apps
    } -OnComplete {
        param($ok)
        Update-WzOfficeSelection
        if ($syncHash.DryRun) {
            # Der Testmodus meldete bisher »Fertig«, als läge Office nun da.
            Show-WzInfo -Title (Get-WzText 'off.dryRunTitle') `
                -Message (Get-WzText 'off.dryRunDownload')
            return
        }
        if ($ok) {
            Add-WzAction -Area 'Office' `
                -Summary (Get-WzText 'off.actionDownloaded' @{ name = $choice.Variant.name; sprache = $choice.Language })
            Show-WzInfo -Title (Get-WzText 'off.downloadOkTitle') -Message (Get-WzText 'off.downloadOkMessage')
        }
    }.GetNewClosure()
}

function Start-WzLibreOfficeInstall {
    # Der Dialog versprach winget, ohne je zu prüfen, ob es da ist. Fehlte es,
    # brach die Installation mit 0/0/0 ab und meldete »lief nicht durch«, ohne
    # einen Weg vorwärts zu nennen.
    $winget = Test-WzWinget
    if (-not $winget.Available -and -not $syncHash.DryRun) {
        Show-WzInfo -Title (Get-WzText 'off.wingetMissingTitle') `
            -Message (Get-WzText 'off.wingetMissingMessage') `
            -Items @($(if ($winget.Path) { Get-WzText 'off.wingetFoundNotRunnable' @{ pfad = $winget.Path } } else { Get-WzText 'off.wingetNotFound' }))
        return
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'off.libreDialogTitle') `
        -Message (Get-WzText 'off.libreMessage') `
        -ConfirmText (Get-WzText 'off.btnInstallGo')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'off.taskLibre') -Cancelable -ScriptBlock {
        Install-WzLibreOffice
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        if ($syncHash.DryRun) {
            Show-WzInfo -Title (Get-WzText 'off.dryRunTitle') -Message (Get-WzText 'off.dryRunLibre')
            return
        }
        if ($summary.Installed -gt 0) {
            Add-WzAction -Area 'Office' -Summary (Get-WzText 'off.actionLibre') `
                -RebootRequired:$summary.RebootRequired
            Show-WzInfo -Title (Get-WzText 'off.libreOkTitle') `
                -Message $(if ($summary.RebootRequired) {
                    Get-WzText 'off.libreOkReboot'
                } else {
                    Get-WzText 'off.libreOkMessage'
                })
        } elseif ($summary.Skipped -gt 0) {
            Show-WzInfo -Title (Get-WzText 'off.librePresentTitle') -Message (Get-WzText 'off.librePresentMessage')
        } else {
            # Der Grund stand bisher nur als nackte Zahl im Protokoll
            Show-WzInfo -Title (Get-WzText 'off.notFinishedTitle') `
                -Message (Get-WzText 'off.libreFailMessage') -Items @($summary.Details)
        }
    }
}
