# Seite "Deinstallieren" — installierte Programme auflisten, entfernen und
# die Reste wegräumen. Bis 0.5.0 hing das als zweiter Bereich unter den
# installierbaren Programmen; dort musste man erst an hundert Katalogzeilen
# vorbeiscrollen.

function Initialize-WzUninstallPage {
    $syncHash.UninstallBtnScan.Add_Click({ Start-WzUninstallScan })
    $syncHash.UninstallBtnRemove.Add_Click({ Start-WzUninstallSelected })
    # Enter im Suchfeld sucht, statt nur den Fokus zu halten
    $syncHash.UninstallSearch.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [Windows.Input.Key]::Return) { Start-WzUninstallScan }
    })
}

function Update-WzUninstallPage {
    # Nach jedem Seitenaufbau (auch nach einem Sprachwechsel) ist die Liste
    # leer — dann neu lesen. Sonst bleibt der letzte Stand stehen.
    if ($syncHash.UninstallList.Children.Count -gt 0) { return }
    Start-WzUninstallScan
}

function Start-WzUninstallScan {
    $filter = $syncHash.UninstallSearch.Text
    $syncHash.UninstallTitle.Text = 'wird gelesen...'
    $syncHash.UninstallList.Children.Clear()

    Invoke-WzTask -Name 'Programmliste lesen' -Cancelable -Silent -ArgumentList @($filter) -ScriptBlock {
        param($needle)
        Get-WzInstalledPrograms -Filter $needle
    } -OnComplete {
        param($programs)
        # Ohne Fund kommt $null herein, und @($null) lehnt der Binder ab
        if (-not $programs) { $programs = @() }
        Write-WzUninstallList -Programs @($programs)
    }
}

function Write-WzUninstallList {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Programs)

    $filter = $syncHash.UninstallSearch.Text
    $syncHash.UninstallTitle.Text = if ($Programs.Count -eq 0 -and $filter) {
        "Nichts gefunden für »$filter«"
    } elseif ($Programs.Count -eq 0) {
        'Keine Programme gefunden'
    } elseif ($filter) {
        "$($Programs.Count) Treffer für »$filter«"
    } else {
        "$($Programs.Count) installierte Programme"
    }

    $container = $syncHash.UninstallList
    $container.Children.Clear()
    $syncHash.UninstallBoxes = @()

    # Bei einer vollen Liste sind über hundert Zeilen zu viel für den Bildschirm
    $shown = @($Programs | Select-Object -First 40)
    foreach ($program in $shown) {
        $parts = @()
        if ($program.Version) { $parts += $program.Version }
        if ($program.Publisher) { $parts += $program.Publisher }
        if ($program.SizeBytes -gt 0) { $parts += Format-WzBytes $program.SizeBytes }
        if (-not $program.CanSilent) { $parts += 'fragt beim Entfernen nach' }

        $item = [pscustomobject]@{
            name        = $program.Name
            description = ($parts -join ' · ')
        }
        $row = New-WzCheckRow -Item $item -IsChecked $false
        $row.CheckBox.Tag = $program
        $row.CheckBox.Add_Click({ Update-WzUninstallSelection })
        [void]$container.Children.Add($row.Row)
        $syncHash.UninstallBoxes += $row.CheckBox
    }

    if ($Programs.Count -gt $shown.Count) {
        [void]$container.Children.Add((New-WzInfoRow 'weitere' `
            "$($Programs.Count - $shown.Count) Einträge sind ausgeblendet — bitte die Suche oben nutzen." -LabelWidth 200))
    }

    Update-WzUninstallSelection
}

function Update-WzUninstallSelection {
    $count = @($syncHash.UninstallBoxes | Where-Object { $_.IsChecked }).Count
    $syncHash.UninstallBtnRemove.IsEnabled = ($count -gt 0)
}

function Start-WzUninstallSelected {
    $selected = @($syncHash.UninstallBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    $loud = @($selected | Where-Object { -not $_.CanSilent })
    $message = "$($selected.Count) Programm(e) werden entfernt. Das lässt sich nicht rückgängig machen — die Programme müssen danach neu installiert werden."
    if ($loud.Count -gt 0) {
        $message += "`n`n$($loud.Count) davon bringen einen eigenen Assistenten mit und fragen selbst noch einmal nach. " +
            'Solange muss WinZii warten; bitte die Fenster durchklicken.'
    }

    $answer = Show-WzConfirm -Title 'Programme entfernen' -Message $message `
        -Items @($selected | ForEach-Object { $_.Name }) `
        -ConfirmText 'Entfernen' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Programme entfernen' -ArgumentList (, $selected) -ScriptBlock {
        param($programs)
        $summary = Uninstall-WzPrograms -Programs $programs
        # Gleich nachsehen, was die Deinstallierer liegen gelassen haben —
        # aber nur bei den Programmen, die wirklich weg sind.
        $leftovers = @()
        if (@($summary.RemovedPrograms).Count -gt 0) {
            $leftovers = @(Find-WzUninstallLeftovers -Programs $summary.RemovedPrograms)
        }
        [pscustomobject]@{ Summary = $summary; Leftovers = $leftovers }
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $summary = $result.Summary
        $leftovers = @($result.Leftovers | Where-Object { $_ })

        Add-WzAction -Area 'Programme' `
            -Summary "$($summary.Removed) Programm(e) entfernt$(if ($summary.Failed -gt 0) { ", $($summary.Failed) ohne Erfolg" })" `
            -Detail @($selected | ForEach-Object { $_.Name })

        if ($leftovers.Count -eq 0) {
            Show-WzInfo -Title 'Deinstallation abgeschlossen' `
                -Message "$($summary.Removed) entfernt, $($summary.Failed) fehlgeschlagen.$(if ($summary.Removed -gt 0) { ' Reste wurden keine gefunden.' })" `
                -Items @($summary.Details)
            Start-WzUninstallScan
            return
        }

        # Reste gefunden: Ergebnis und Nachfrage in einem Dialog
        $bytes = [int64]0
        $measure = ($leftovers | Measure-Object -Property SizeBytes -Sum).Sum
        if ($measure) { $bytes = [int64]$measure }

        $answer = Show-WzConfirm -Title 'Deinstallation abgeschlossen' `
            -Message ("$($summary.Removed) entfernt, $($summary.Failed) fehlgeschlagen. " +
                "Die Deinstallierer haben Reste zurückgelassen ($(Format-WzBytes $bytes)). " +
                'Registry-Schlüssel werden vor dem Entfernen als .reg-Datei gesichert. ' +
                'Gelöschte Ordner sind endgültig weg — auch gespeicherte Einstellungen und Profile darin.') `
            -Items @($leftovers | ForEach-Object {
                "$($_.Kind): $($_.Path)$(if ($_.SizeBytes -gt 0) { " — $(Format-WzBytes $_.SizeBytes)" })"
            }) `
            -ConfirmText 'Reste entfernen' -Danger
        if (-not $answer.Confirmed) {
            Start-WzUninstallScan
            return
        }

        Invoke-WzTask -Name 'Programmreste entfernen' -ArgumentList (, $leftovers) -ScriptBlock {
            param($items)
            Remove-WzUninstallLeftovers -Leftovers $items
        } -OnComplete {
            param($cleanup)
            if (-not $cleanup) { return }
            if ($cleanup.Removed -gt 0) {
                Add-WzAction -Area 'Programme' `
                    -Summary "$($cleanup.Removed) Programmrest(e) entfernt$(if ($cleanup.Bytes -gt 0) { " ($(Format-WzBytes $cleanup.Bytes))" })"
            }
            Show-WzInfo -Title 'Reste entfernt' `
                -Message "$($cleanup.Removed) entfernt, $($cleanup.Failed) fehlgeschlagen." `
                -Items @($cleanup.Details)
            Start-WzUninstallScan
        }
    }.GetNewClosure()
}
