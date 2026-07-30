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

    Update-WzAppsSelection
}

function Update-WzAppsPage {
    if ($syncHash.AppsChecked) { return }
    $syncHash.AppsChecked = $true

    Invoke-WzTask -Name 'winget prüfen' -Silent -ScriptBlock {
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
        Write-WzLog "winget gefunden: $($Info.Winget.Version)" -Level Info
        $syncHash.AppsBtnWinget.Visibility = [Windows.Visibility]::Collapsed
        $syncHash.AppsBtnInstall.IsEnabled = $true
    } else {
        [void]$notices.Items.Add((New-WzNotice -Kind 'warn' `
            -Text 'winget ist auf diesem PC nicht vorhanden. Das kommt bei LTSC-Versionen und älteren Windows-10-Ständen vor. Über "winget nachinstallieren" wird es eingerichtet — dafür ist einmalig Internet nötig.'))
        $syncHash.AppsBtnWinget.Visibility = [Windows.Visibility]::Visible
        $syncHash.AppsBtnInstall.IsEnabled = $false
        Write-WzLog 'winget nicht gefunden.' -Level Warn
    }

    if ($Info.Offline.Count -gt 0) {
        $syncHash.AppsOfflineHint.Text =
            "$($Info.Offline.Count) Programm(e) liegen bereits auf dem Datenträger ($(Format-WzBytes $Info.Offline.Bytes))"
    } else {
        $syncHash.AppsOfflineHint.Text = 'noch nichts auf dem Datenträger zwischengespeichert'
    }
}

function New-WzAppList {
    $container = $syncHash.AppsCategories
    $container.Children.Clear()
    $rows = New-Object Collections.ArrayList

    foreach ($category in (Get-WzAppCategories)) {
        $apps = @(Get-WzApps -Category $category.id)
        if ($apps.Count -eq 0) { continue }

        $card = New-Object Windows.Controls.Border
        $card.Style = $syncHash.Window.FindResource('WzCardStatic')
        $card.Margin = New-Object Windows.Thickness(0, 0, 0, 14)

        $stack = New-Object Windows.Controls.StackPanel

        $eyebrow = New-Object Windows.Controls.TextBlock
        $eyebrow.Text = "// $($category.name.ToUpper())"
        $eyebrow.Style = $syncHash.Window.FindResource('WzEyebrow')
        [void]$stack.Children.Add($eyebrow)

        $lead = New-Object Windows.Controls.TextBlock
        $lead.Text = $category.description
        $lead.Style = $syncHash.Window.FindResource('WzLabel')
        $lead.Margin = New-Object Windows.Thickness(0, 0, 0, 12)
        [void]$stack.Children.Add($lead)

        foreach ($app in $apps) {
            $row = New-WzCheckRow -Item $app -IsChecked ([bool]$app.defaultChecked)
            $row.CheckBox.Add_Click({ Update-WzAppsSelection })
            [void]$stack.Children.Add($row.Row)
            [void]$rows.Add([pscustomobject]@{ App = $app; CheckBox = $row.CheckBox })
        }

        $card.Child = $stack
        [void]$container.Children.Add($card)
    }

    return $rows
}

function Update-WzAppsSelection {
    $count = @($syncHash.AppsRows | Where-Object { $_.CheckBox.IsChecked }).Count
    $syncHash.AppsSelectionCount.Text = "$count ausgewählt"
    $syncHash.AppsBtnDownload.IsEnabled = ($count -gt 0)
}

function Get-WzSelectedApps {
    return @($syncHash.AppsRows | Where-Object { $_.CheckBox.IsChecked } | ForEach-Object { $_.App })
}

function Start-WzAppInstall {
    $selected = Get-WzSelectedApps
    if ($selected.Count -eq 0) {
        Show-WzInfo -Title 'Nichts ausgewählt' -Message 'Bitte zuerst mindestens ein Programm anhaken.'
        return
    }

    $message = "$($selected.Count) Programm(e) werden über winget installiert. Das kann je nach Umfang und Verbindung einige Minuten dauern."
    if ($syncHash.DryRun) { $message = "Testmodus: Es wird nur aufgelistet, was installiert würde. $message" }

    $answer = Show-WzConfirm -Title 'Programme installieren' -Message $message `
        -Items @($selected | ForEach-Object { $_.name }) `
        -ConfirmText $(if ($syncHash.DryRun) { 'Testlauf starten' } else { 'Installieren' })
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Programme installieren' -ArgumentList (, $selected) -ScriptBlock {
        param($apps)
        Install-WzApps -Apps $apps
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        $lines = @("$($summary.Installed) installiert")
        if ($summary.Skipped -gt 0) { $lines += "$($summary.Skipped) übersprungen (bereits vorhanden)" }
        if ($summary.Failed -gt 0) { $lines += "$($summary.Failed) fehlgeschlagen" }

        Show-WzInfo -Title 'Installation abgeschlossen' -Message ($lines -join ' · ') -Items @($summary.Details)
    }
}

function Start-WzAppDownload {
    $selected = Get-WzSelectedApps
    if ($selected.Count -eq 0) { return }

    $volume = Get-WzVolumeInfo
    $answer = Show-WzConfirm -Title 'Auf Datenträger laden' `
        -Message "$($selected.Count) Programm(e) werden auf den WinZii-Datenträger geladen und lassen sich danach ohne Internet installieren. Frei: $(Format-WzBytes $volume.FreeBytes)." `
        -Items @($selected | ForEach-Object { $_.name }) -ConfirmText 'Laden'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Installationsdateien laden' -ArgumentList (, $selected) -ScriptBlock {
        param($apps)
        Save-WzOfflineInstallers -Apps $apps
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }
        Show-WzInfo -Title 'Ablage abgeschlossen' `
            -Message "$($summary.Saved) Programm(e) gespeichert ($(Format-WzBytes $summary.Bytes)), $($summary.Failed) fehlgeschlagen."
        $syncHash.AppsChecked = $false
        Update-WzAppsPage
    }
}

function Start-WzWingetBootstrap {
    $answer = Show-WzConfirm -Title 'winget nachinstallieren' `
        -Message 'WinZii richtet den App-Installer von Microsoft ein. Dafür werden drei Pakete benötigt; sie werden auf dem Datenträger abgelegt und stehen beim nächsten PC ohne Internet bereit.' `
        -ConfirmText 'Einrichten'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'winget einrichten' -ScriptBlock {
        Install-WzWingetBootstrap
    } -OnComplete {
        param($ok)
        $syncHash.AppsChecked = $false
        Update-WzAppsPage
        if ($ok) {
            Show-WzInfo -Title 'winget eingerichtet' -Message 'Programme lassen sich jetzt installieren.'
        } else {
            Show-WzInfo -Title 'Nicht abgeschlossen' `
                -Message 'winget konnte nicht eingerichtet werden. Einzelheiten stehen im Protokoll. Nach einem Neustart klappt es oft.'
        }
    }
}
