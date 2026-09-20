# Seite "Programme" — winget-Katalog mit Auswahl, Installation und
# Vorablade-Funktion für den Einsatz ohne Internet.

function Initialize-WzAppsPage {
    $syncHash.AppsRows = New-WzAppList

    $syncHash.AppsBtnInstall.Add_Click({ Start-WzAppInstall })
    $syncHash.AppsBtnDownload.Add_Click({ Start-WzAppDownload })
    $syncHash.AppsBtnWinget.Add_Click({ Start-WzWingetBootstrap })

    $syncHash.AppsBtnRecommended.Add_Click({
        foreach ($entry in $syncHash.AppsRows) {
            $entry.CheckBox.IsChecked = [bool]$entry.App.defaultChecked
        }
        Update-WzAppsSelection
    })
    $syncHash.AppsBtnNone.Add_Click({
        foreach ($entry in $syncHash.AppsRows) { $entry.CheckBox.IsChecked = $false }
        Update-WzAppsSelection
    })

    $syncHash.AppsBtnUpgradeScan.Add_Click({ Start-WzUpgradeScan })
    $syncHash.AppsBtnUpgrade.Add_Click({ Start-WzAppUpgrade })
    $syncHash.AppsBtnUpgradeAll.Add_Click({
        foreach ($box in @($syncHash.AppsUpgradeBoxes)) { $box.IsChecked = $true }
        Update-WzUpgradeSelection
    })

    Update-WzAppsSelection
}

function Update-WzAppsPage {
    if ($syncHash.AppsChecked) { return }
    $syncHash.AppsChecked = $true

    Invoke-WzTask -Name (Get-WzText 'apps.taskCheckWinget') -Silent -ScriptBlock {
        [pscustomobject]@{
            Winget  = Test-WzWinget
            Offline = Get-WzOfflineInstallerInfo
        }
    } -OnComplete {
        param($info)
        if (-not $info) { return }
        Write-WzAppsStatus -Info $info
    }
}

function Write-WzAppsStatus {
    param([Parameter(Mandatory = $true)]$Info)

    $notices = $syncHash.AppsNotices
    $notices.Items.Clear()

    if ($Info.Winget.Available) {
        Write-WzLog (Get-WzText 'apps.logWingetFound' @{ version = $Info.Winget.Version }) -Level Info
        $syncHash.AppsBtnWinget.Visibility = [Windows.Visibility]::Collapsed
        $syncHash.AppsBtnInstall.IsEnabled = $true
    } else {
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text (Get-WzText 'apps.noticeNoWinget')))
        $syncHash.AppsBtnWinget.Visibility = [Windows.Visibility]::Visible
        $syncHash.AppsBtnInstall.IsEnabled = $false
        Write-WzLog (Get-WzText 'apps.logWingetMissing') -Level Warn
    }

    if ($Info.Offline.Count -gt 0) {
        $syncHash.AppsOfflineHint.Text =
            Get-WzText 'apps.offlineHave' @{ anzahl = $Info.Offline.Count; groesse = (Format-WzBytes $Info.Offline.Bytes) }
    } else {
        $syncHash.AppsOfflineHint.Text = Get-WzText 'apps.offlineNone'
    }

    # Die Suche nach veralteten Programmen läuft NICHT von selbst, obwohl sie
    # gerade dann am nützlichsten wäre. Zwei Gründe, beide schwerer als die
    # Bequemlichkeit: Sie fragt winget, und das geht ins Netz — ungefragt, beim
    # bloßen Öffnen einer Seite, tut WinZii das nirgends. Und sie dauert auf
    # einem gewachsenen Gerät bis zu einer Minute, in der kein anderer Schritt
    # anlaufen kann. Wer nur ein Programm installieren will, stünde davor.
    $syncHash.AppsBtnUpgradeScan.IsEnabled = $Info.Winget.Available
    $syncHash.AppsBtnUpgradeAll.IsEnabled = $false
    $syncHash.AppsUpgradeTitle.Text = if ($Info.Winget.Available) {
        Get-WzText 'apps.upgradeNotChecked'
    } else {
        Get-WzText 'apps.upgradeNoWinget'
    }
}

function New-WzAppList {
    $container = $syncHash.AppsCategories
    $container.Children.Clear()
    $rows = New-Object Collections.ArrayList

    foreach ($category in (Get-WzAppCategories)) {
        $apps = @(Get-WzApps -Category $category.id)
        if ($apps.Count -eq 0) { continue }

        $card = New-WzCard -Eyebrow "// $($category.name.ToUpper())"
        $stack = $card.Content

        $lead = New-Object Windows.Controls.TextBlock
        $lead.Text = $category.description
        $lead.Style = $syncHash.Window.FindResource('WzLabel')
        # Ohne Umbruch lief der Satz rechts aus der Karte heraus und wurde
        # abgeschnitten — auffällig erst bei den längeren Beschreibungen.
        $lead.TextWrapping = 'Wrap'
        $lead.Margin = New-Object Windows.Thickness(0, 0, 0, 12)
        [void]$stack.Children.Add($lead)

        foreach ($app in $apps) {
            $row = New-WzCheckRow -Item $app -IsChecked ([bool]$app.defaultChecked)
            $row.CheckBox.Add_Click({ Update-WzAppsSelection })
            [void]$stack.Children.Add($row.Row)
            [void]$rows.Add([pscustomobject]@{ App = $app; CheckBox = $row.CheckBox })
        }

        [void]$container.Children.Add($card.Card)
    }

    return $rows
}

function Update-WzAppsSelection {
    $count = @($syncHash.AppsRows | Where-Object { $_.CheckBox.IsChecked }).Count
    $syncHash.AppsSelectionCount.Text = Get-WzText 'apps.selectedCount' @{ anzahl = $count }
    $syncHash.AppsBtnDownload.IsEnabled = ($count -gt 0)
}

function Get-WzSelectedApps {
    return @($syncHash.AppsRows | Where-Object { $_.CheckBox.IsChecked } | ForEach-Object { $_.App })
}

function Start-WzAppInstall {
    $selected = Get-WzSelectedApps
    if ($selected.Count -eq 0) {
        Show-WzInfo -Title (Get-WzText 'apps.nothingSelectedTitle') -Message (Get-WzText 'apps.nothingSelectedMessage')
        return
    }

    # Vorher sagen, was aus dem Vorrat kommt und was aus dem Netz — das
    # entscheidet darüber, ob der Vorgang auch ohne Verbindung durchläuft.
    $fromVault = @($selected | Where-Object { Get-WzOfflineInstallerPath -App $_ })
    $message = Get-WzText 'apps.installMessage' @{ anzahl = $selected.Count }
    if ($fromVault.Count -eq $selected.Count) {
        $message = Get-WzText 'apps.installFromVault' @{ anzahl = $selected.Count }
    } elseif ($fromVault.Count -gt 0) {
        $message += Get-WzText 'apps.installMixed' @{ anzahl = $fromVault.Count }
    }
    if ($syncHash.DryRun) { $message = Get-WzText 'apps.installDryRun' @{ rest = $message } }

    $answer = Show-WzConfirm -Title (Get-WzText 'apps.installTitle') -Message $message `
        -Items @($selected | ForEach-Object {
            if (Get-WzOfflineInstallerPath -App $_) { Get-WzText 'apps.itemFromVault' @{ name = $_.name } } else { $_.name }
        }) `
        -ConfirmText $(if ($syncHash.DryRun) { Get-WzText 'apps.btnDryRun' } else { Get-WzText 'apps.btnInstallNow' })
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'apps.taskInstall') -ArgumentList (, $selected) -ScriptBlock {
        param($apps)
        Install-WzApps -Apps $apps
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        $lines = @(Get-WzText 'apps.lineInstalled' @{ anzahl = $summary.Installed })
        if ($summary.Skipped -gt 0) { $lines += Get-WzText 'apps.lineSkipped' @{ anzahl = $summary.Skipped } }
        if ($summary.Failed -gt 0) { $lines += Get-WzText 'apps.lineFailed' @{ anzahl = $summary.Failed } }
        if ($summary.RebootRequired) { $lines += Get-WzText 'apps.lineReboot' }

        # Nur festhalten, was wirklich angekommen ist — vorher wanderte die
        # ganze Auswahl ins Übergabeblatt, auch die gescheiterten Programme.
        if ($summary.Installed -gt 0) {
            Add-WzAction -Area 'Programme' `
                -Summary ((Get-WzText 'apps.actionInstalled' @{ anzahl = $summary.Installed }) + $(if ($summary.Failed -gt 0) { Get-WzText 'apps.actionFailedSuffix' @{ anzahl = $summary.Failed } })) `
                -Detail @($summary.InstalledNames) -RebootRequired:$summary.RebootRequired
        }

        Show-WzInfo -Title $(if ($summary.Failed -gt 0) { Get-WzText 'apps.donePartialTitle' } else { Get-WzText 'apps.doneTitle' }) `
            -Message ($lines -join ' · ') -Items @($summary.Details)
    }.GetNewClosure()
}

function Start-WzAppDownload {
    $selected = Get-WzSelectedApps
    if ($selected.Count -eq 0) { return }

    $volume = Get-WzVolumeInfo
    $answer = Show-WzConfirm -Title (Get-WzText 'apps.downloadTitle') `
        -Message (Get-WzText 'apps.downloadMessage' @{ anzahl = $selected.Count; frei = (Format-WzBytes $volume.FreeBytes) }) `
        -Items @($selected | ForEach-Object { $_.name }) -ConfirmText (Get-WzText 'apps.btnDownload2')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'apps.taskDownload') -ArgumentList (, $selected) -ScriptBlock {
        param($apps)
        Save-WzOfflineInstallers -Apps $apps
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        $message = Get-WzText 'apps.downloadDone' @{ anzahl = $summary.Saved; groesse = (Format-WzBytes $summary.Bytes) }
        if ($summary.Failed -gt 0) { $message += Get-WzText 'apps.downloadFailedSuffix' @{ anzahl = $summary.Failed } }
        if ($summary.Saved -gt 0) {
            Add-WzAction -Area 'Programme' `
                -Summary (Get-WzText 'apps.actionDownloaded' @{ anzahl = $summary.Saved; groesse = (Format-WzBytes $summary.Bytes) })
        }
        Show-WzInfo -Title $(if ($summary.Failed -gt 0) { Get-WzText 'apps.downloadPartialTitle' } else { Get-WzText 'apps.downloadDoneTitle' }) `
            -Message $message -Items @($summary.Details)
        $syncHash.AppsChecked = $false
        Update-WzAppsPage
    }
}

function Start-WzWingetBootstrap {
    # Ehrliche Mengenangabe: Liegen die Pakete schon auf dem Stick, geht es in
    # Sekunden. Beim ersten Mal sind es rund 315 MB — das darf nicht als
    # »drei Pakete« verharmlost werden, wenn jemand im Hotel-WLAN sitzt.
    $cached = Test-Path -LiteralPath (Join-Path (Join-Path (Get-WzOfflineDir) 'winget') 'AppInstaller.msixbundle')
    $sizeNote = if ($cached) {
        Get-WzText 'apps.bootstrapCached'
    } else {
        Get-WzText 'apps.bootstrapDownload'
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'apps.bootstrapTitle') `
        -Message (Get-WzText 'apps.bootstrapMessage' @{ hinweis = $sizeNote }) `
        -Items @((Get-WzText 'apps.bootstrapItem1'), (Get-WzText 'apps.bootstrapItem2')) `
        -ConfirmText (Get-WzText 'apps.btnBootstrapGo')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'apps.taskBootstrap') -ScriptBlock {
        Install-WzWingetBootstrap
    } -OnComplete {
        param($ok)
        $syncHash.AppsChecked = $false
        Update-WzAppsPage
        if ($syncHash.DryRun) {
            # Im Testmodus liefert der Vorgang immer $false — das las sich bisher
            # wie ein Fehlschlag, obwohl gar nichts versucht wurde.
            Show-WzInfo -Title (Get-WzText 'apps.dryRunDoneTitle') `
                -Message (Get-WzText 'apps.dryRunDoneMessage')
            return
        }
        if ($ok) {
            Show-WzInfo -Title (Get-WzText 'apps.bootstrapOkTitle') -Message (Get-WzText 'apps.bootstrapOkMessage')
        } else {
            Show-WzInfo -Title (Get-WzText 'apps.bootstrapFailTitle') `
                -Message (Get-WzText 'apps.bootstrapFailMessage')
        }
    }
}

# --- Vorhandene Programme aktualisieren ------------------------------------

function Start-WzUpgradeScan {
    $syncHash.AppsUpgradeTitle.Text = Get-WzText 'apps.upgradeChecking'
    $syncHash.AppsUpgradeList.Children.Clear()
    $syncHash.AppsUpgradeBoxes = @()
    $syncHash.AppsBtnUpgrade.IsEnabled = $false

    Invoke-WzTask -Name (Get-WzText 'apps.taskUpgradeScan') -Silent -Cancelable -ScriptBlock {
        Get-WzUpgradableApps
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Write-WzUpgradeList -Result $result
    }
}

function Write-WzUpgradeList {
    <#
    .SYNOPSIS
        Füllt die Karte mit dem, was sich aktualisieren lässt.
    #>
    param([Parameter(Mandatory = $true)]$Result)

    $apps = @($Result.Apps)
    $syncHash.AppsUpgradeApps = $apps

    $syncHash.AppsUpgradeTitle.Text = if (-not $Result.WingetAvailable) {
        Get-WzText 'apps.upgradeNoWinget'
    } elseif ($Result.Failed) {
        Get-WzText 'apps.upgradeFailed'
    } elseif ($apps.Count -eq 0) {
        Get-WzText 'apps.upgradeNone'
    } elseif ($apps.Count -eq 1) {
        Get-WzText 'apps.upgradeCountOne'
    } else {
        Get-WzText 'apps.upgradeCount' @{ anzahl = $apps.Count }
    }

    $container = $syncHash.AppsUpgradeList
    $container.Children.Clear()
    $syncHash.AppsUpgradeBoxes = @()

    foreach ($app in $apps) {
        $item = [pscustomobject]@{
            name        = $app.Name
            description = Get-WzText 'apps.upgradeFromTo' @{ alt = $app.Current; neu = $app.Available }
        }
        $row = New-WzCheckRow -Item $item -IsChecked $false
        $row.CheckBox.Tag = $app
        $row.CheckBox.Add_Click({ Update-WzUpgradeSelection })
        [void]$container.Children.Add($row.Row)
        $syncHash.AppsUpgradeBoxes += $row.CheckBox
    }

    $syncHash.AppsBtnUpgradeAll.IsEnabled = ($apps.Count -gt 0)
    Update-WzUpgradeSelection
}

function Update-WzUpgradeSelection {
    $count = @(@($syncHash.AppsUpgradeBoxes) | Where-Object { $_.IsChecked }).Count
    $syncHash.AppsBtnUpgrade.IsEnabled = ($count -gt 0)
}

function Start-WzAppUpgrade {
    $selected = @(@($syncHash.AppsUpgradeBoxes) | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'apps.upgradeDialogTitle') `
        -Message (Get-WzText 'apps.upgradeDialogMessage' @{ anzahl = $selected.Count }) `
        -Items @($selected | ForEach-Object {
            Get-WzText 'apps.upgradeDialogItem' @{ name = $_.Name; alt = $_.Current; neu = $_.Available } }) `
        -ConfirmText (Get-WzText 'apps.btnUpgrade')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'apps.taskUpgrade') -ArgumentList (, $selected) -ScriptBlock {
        param($apps)
        Update-WzApps -Apps $apps
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        if ($summary.Updated -gt 0) {
            Add-WzAction -Area 'Programme' -RebootRequired:$summary.RebootRequired `
                -Summary (Get-WzText 'apps.actionUpgrade' @{ anzahl = $summary.Updated }) `
                -Detail @($summary.UpdatedNames)
        }

        Show-WzInfo -Title (Get-WzText 'apps.upgradeDoneTitle') `
            -Message (Get-WzText 'apps.upgradeDoneMessage' @{
                aktualisiert = $summary.Updated; uebersprungen = $summary.Skipped; fehlgeschlagen = $summary.Failed }) `
            -Items @(@($summary.UpdatedNames) + @($summary.Details))

        # Neu messen statt die Liste zu Fuß zu pflegen: Ein Programm, das eine
        # zweite Aktualisierung nachzieht, stünde sonst als erledigt da.
        Start-WzUpgradeScan
    }
}
