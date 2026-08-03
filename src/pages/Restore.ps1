# Seite "Zurückspielen" — das Gegenstück zu den Exporten auf der Datenseite.

function Initialize-WzRestorePage {
    $syncHash.RstBtnScan.Add_Click({ Start-WzRestoreScan })
    $syncHash.RstBtnWlan.Add_Click({ Start-WzWlanImport })
    $syncHash.RstBtnMarks.Add_Click({ Start-WzBookmarkImport })
    $syncHash.RstBtnPrinters.Add_Click({ Start-WzPrinterImport })
    $syncHash.RstBtnDrives.Add_Click({ Start-WzDriveImport })

    [void]$syncHash.RstNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Jeder Knopf fragt vorher nach und sagt genau, was er anlegt. Zurückspielen verändert diesen PC — anders als die Datenseite, die nur liest.'))
}

function Update-WzRestorePage {
    if ($syncHash.RstLoaded) { return }
    $syncHash.RstLoaded = $true
    Start-WzRestoreScan
}

function Start-WzRestoreScan {
    $syncHash.RstSourceTitle.Text = 'wird gesucht...'
    foreach ($name in @('RstSources', 'RstWlan', 'RstMarks', 'RstDevices')) {
        $syncHash[$name].Children.Clear()
    }

    Invoke-WzTask -Name 'Sicherungen suchen' -ScriptBlock {
        Get-WzBackupSources
    } -OnComplete {
        param($sources)
        Write-WzRestoreSources -Sources @($sources)
    }
}

function Write-WzRestoreSources {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Sources)

    $syncHash.RstSourcesList = $Sources
    $container = $syncHash.RstSources

    if ($Sources.Count -eq 0) {
        $syncHash.RstSourceTitle.Text = 'Keine Sicherung gefunden'
        [void]$container.Children.Add((New-WzInfoRow 'Gesucht in' `
            (Get-WzPath 'offline' 'daten') -LabelWidth 200))
        [void]$container.Children.Add((New-WzInfoRow 'Hinweis' `
            'Erst auf der Seite »Daten« sichern, dann steht hier etwas zum Zurückspielen.' -LabelWidth 200))
        Set-WzRestoreSelection -Source $null
        return
    }

    $syncHash.RstSourceTitle.Text = if ($Sources.Count -eq 1) {
        "Sicherung von $($Sources[0].Computer)"
    } else {
        "$($Sources.Count) Sicherungen gefunden"
    }

    foreach ($source in $Sources) {
        $parts = @()
        if (@($source.Contents.WlanFiles).Count -gt 0) { $parts += "$(@($source.Contents.WlanFiles).Count) WLAN-Netz(e)" }
        if (@($source.Contents.BookmarkFiles).Count -gt 0) { $parts += "$(@($source.Contents.BookmarkFiles).Count) Lesezeichen-Datei(en)" }
        if (@($source.Contents.Printers).Count -gt 0) { $parts += "$(@($source.Contents.Printers).Count) Drucker" }
        if (@($source.Contents.NetDrives).Count -gt 0) { $parts += "$(@($source.Contents.NetDrives).Count) Netzlaufwerk(e)" }

        $label = if ($source.IsCurrent) { "$($source.Computer) (dieser PC)" } else { $source.Computer }
        [void]$container.Children.Add((New-WzInfoRow $label `
            "$($parts -join ' · ') · gesichert $(Format-WzAgo $source.Saved)" `
            -Kind $(if ($source.IsCurrent) { 'ok' } else { 'normal' }) -LabelWidth 250))
    }

    # Die Sicherung dieses Rechners steht vorne und ist die sinnvolle Vorgabe.
    # Eine fremde lässt sich über den Knopf darunter wählen — mit Warnung.
    Set-WzRestoreSelection -Source $Sources[0]

    if ($Sources.Count -gt 1) {
        # Bewusst als Fließtext über die ganze Breite: In einer Infozeile stünde
        # der Satz in der Wertespalte und sähe aus wie eine Angabe zur letzten
        # Sicherung darüber.
        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = 'Verwendet wird die oberste Sicherung. Zum Wechseln den Knopf darunter.'
        $hint.Style = $syncHash.Window.FindResource('WzHint')
        $hint.Margin = New-Object Windows.Thickness(0, 8, 0, 0)
        [void]$container.Children.Add($hint)

        $button = New-Object Windows.Controls.Button
        $button.Content = 'Andere Quelle wählen'
        $button.Style = $syncHash.Window.FindResource('WzBtnGhost')
        $button.HorizontalAlignment = 'Left'
        $button.Margin = New-Object Windows.Thickness(0, 8, 0, 0)
        $button.Add_Click({ Select-WzRestoreSource })
        [void]$container.Children.Add($button)
    }
}

function Select-WzRestoreSource {
    <#
    .SYNOPSIS
        Auswahl unter mehreren Sicherungen — fremde ausdrücklich gekennzeichnet.
    #>
    $sources = @($syncHash.RstSourcesList)
    if ($sources.Count -lt 2) { return }

    $choices = @($sources | ForEach-Object {
        if ($_.IsCurrent) { "$($_.Computer) — dieser PC" } else { "$($_.Computer) — anderer PC" }
    })
    $current = @($sources | ForEach-Object { $_.Computer }).IndexOf($syncHash.RstSource.Computer)

    $answer = Show-WzConfirm -Title 'Quelle wählen' `
        -Message 'Aus welcher Sicherung soll zurückgespielt werden? Eine Sicherung von einem anderen Rechner passt nicht zwangsläufig: Drucker hängen dort an anderen Anschlüssen, und Browser-Profile heißen anders.' `
        -Choices $choices -ChoiceLabel 'Sicherung' -ChoiceDefault ([math]::Max(0, $current)) `
        -ConfirmText 'Übernehmen'
    if (-not $answer.Confirmed) { return }

    Set-WzRestoreSelection -Source $sources[$answer.SelectedIndex]
}

function Set-WzRestoreSelection {
    <#
    .SYNOPSIS
        Setzt die aktive Quelle und baut die drei Karten darunter neu auf.
    #>
    param($Source)

    $syncHash.RstSource = $Source
    Write-WzRestoreWlan -Source $Source
    Write-WzRestoreMarks -Source $Source
    Write-WzRestoreDevices -Source $Source
}

function Write-WzRestoreWlan {
    param($Source)

    $container = $syncHash.RstWlan
    $container.Children.Clear()
    $files = if ($Source) { @($Source.Contents.WlanFiles) } else { @() }

    if ($files.Count -eq 0) {
        $syncHash.RstWlanTitle.Text = 'Keine WLAN-Netze in der Sicherung'
        $syncHash.RstBtnWlan.IsEnabled = $false
        return
    }

    $withoutKey = 0
    foreach ($file in $files) {
        $name = Get-WzWlanProfileName -Path $file
        if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($file) }
        $hasKey = Test-WzWlanProfileHasKey -Path $file
        if (-not $hasKey) { $withoutKey++ }
        [void]$container.Children.Add((New-WzInfoRow $name `
            $(if ($hasKey) { 'mit Schlüssel' } else { 'ohne Schlüssel — verbindet sich nicht von selbst' }) `
            -Kind $(if ($hasKey) { 'ok' } else { 'warn' }) -LabelWidth 250))
    }

    $syncHash.RstWlanTitle.Text = if ($withoutKey -gt 0) {
        "$($files.Count) WLAN-Netz(e), davon $withoutKey ohne Schlüssel"
    } else {
        "$($files.Count) WLAN-Netz(e) mit Schlüssel"
    }
    $syncHash.RstBtnWlan.IsEnabled = $true
}

function Write-WzRestoreMarks {
    param($Source)

    $container = $syncHash.RstMarks
    $container.Children.Clear()
    $files = if ($Source) { @($Source.Contents.BookmarkFiles) } else { @() }

    if ($files.Count -eq 0) {
        $syncHash.RstMarksTitle.Text = 'Keine Lesezeichen in der Sicherung'
        $syncHash.RstBtnMarks.IsEnabled = $false
        $syncHash.RstMarkTargets = @()
        return
    }

    $targets = @(Get-WzBookmarkTargets -Files $files)
    $syncHash.RstMarkTargets = $targets
    $usable = @($targets | Where-Object { $_.Target })

    foreach ($entry in $targets) {
        if ($entry.Target) {
            [void]$container.Children.Add((New-WzInfoRow "$($entry.BrowserName) / $($entry.ProfileName)" `
                'lässt sich zurückspielen' -Kind 'ok' -LabelWidth 250))
        } else {
            $label = if ($entry.BrowserName) { $entry.BrowserName } else { Split-Path -Leaf $entry.Source }
            [void]$container.Children.Add((New-WzInfoRow $label $entry.Reason -Kind 'warn' -LabelWidth 250))
        }
    }

    $syncHash.RstMarksTitle.Text = "$($usable.Count) von $($files.Count) Datei(en) passen zu diesem PC"
    $syncHash.RstBtnMarks.IsEnabled = ($usable.Count -gt 0)
}

function Write-WzRestoreDevices {
    param($Source)

    $container = $syncHash.RstDevices
    $container.Children.Clear()
    $printers = if ($Source) { @($Source.Contents.Printers) } else { @() }
    $drives = if ($Source) { @($Source.Contents.NetDrives) } else { @() }

    if ($printers.Count -eq 0 -and $drives.Count -eq 0) {
        $syncHash.RstDevicesTitle.Text = 'Keine Geräteliste in der Sicherung'
        [void]$container.Children.Add((New-WzInfoRow 'Hinweis' `
            'Die Geräteliste entsteht auf der Seite »Daten« über »Drucker und Laufwerke sichern«.' -LabelWidth 250))
        $syncHash.RstBtnPrinters.IsEnabled = $false
        $syncHash.RstBtnDrives.IsEnabled = $false
        return
    }

    foreach ($printer in $printers) {
        $marker = if ($printer.standard) { ' (Standard)' } else { '' }
        [void]$container.Children.Add((New-WzInfoRow "$($printer.name)$marker" `
            "$($printer.anschluss) · $($printer.treiber)" -LabelWidth 250))
    }
    foreach ($drive in $drives) {
        [void]$container.Children.Add((New-WzInfoRow "Laufwerk $($drive.buchstabe)" $drive.ziel -LabelWidth 250))
    }

    $syncHash.RstDevicesTitle.Text = "$($printers.Count) Drucker · $($drives.Count) Netzlaufwerk(e)"
    $syncHash.RstBtnPrinters.IsEnabled = ($printers.Count -gt 0)
    $syncHash.RstBtnDrives.IsEnabled = ($drives.Count -gt 0)
}

# --- Rückspielen -----------------------------------------------------------

function Get-WzRestoreForeignWarning {
    <#
    .SYNOPSIS
        Zusatzsatz, wenn die Sicherung von einem anderen Rechner stammt.
    #>
    if ($syncHash.RstSource -and -not $syncHash.RstSource.IsCurrent) {
        return " Achtung: Die Sicherung stammt von $($syncHash.RstSource.Computer), nicht von diesem PC."
    }
    return ''
}

function Start-WzWlanImport {
    $files = @($syncHash.RstSource.Contents.WlanFiles)
    if ($files.Count -eq 0) { return }

    $names = @($files | ForEach-Object {
        $name = Get-WzWlanProfileName -Path $_
        if ($name) { $name } else { [IO.Path]::GetFileNameWithoutExtension($_) }
    })

    $answer = Show-WzConfirm -Title 'WLAN-Netze einrichten' `
        -Message ("Diese Netze werden für alle Benutzer dieses PCs angelegt. Ein bereits vorhandenes Profil gleichen Namens wird dabei überschrieben." + (Get-WzRestoreForeignWarning)) `
        -Items $names -ConfirmText 'Einrichten'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'WLAN-Netze einrichten' -ArgumentList (, $files) -ScriptBlock {
        param($files)
        Import-WzWlanProfiles -Files $files
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title 'WLAN-Netze' -Result $result -ExtraKind 'WithoutKey' `
            -ExtraText 'angelegt, aber ohne Schlüssel — hier muss das Kennwort noch einmal eingegeben werden'
        Start-WzRestoreScan
    }
}

function Start-WzBookmarkImport {
    $targets = @($syncHash.RstMarkTargets | Where-Object { $_.Target })
    if ($targets.Count -eq 0) { return }

    $running = @($targets | ForEach-Object { $_.BrowserName } | Sort-Object -Unique |
        Where-Object { Get-WzBrowserProcess -BrowserName $_ })

    $items = @($targets | ForEach-Object { "$($_.BrowserName) / $($_.ProfileName)" })
    $message = 'Die vorhandenen Lesezeichen dieser Profile werden ersetzt. WinZii legt die bisherige Datei vorher als Kopie mit der Endung .winzii-vorher daneben.'
    if ($running.Count -gt 0) {
        $message += " $($running -join ' und ') läuft gerade — solange der Browser offen ist, schreibt er die alten Lesezeichen beim Beenden zurück. Bitte vorher schließen."
    }

    $answer = Show-WzConfirm -Title 'Lesezeichen zurückspielen' `
        -Message ($message + (Get-WzRestoreForeignWarning)) -Items $items `
        -ConfirmText 'Zurückspielen' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Lesezeichen zurückspielen' -ArgumentList (, $targets) -ScriptBlock {
        param($targets)
        Import-WzBrowserBookmarks -Targets $targets
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title 'Lesezeichen' -Result $result -ExtraKind 'Blocked' `
            -ExtraText 'übersprungen, weil der Browser noch lief'
    }
}

function Start-WzPrinterImport {
    $printers = @($syncHash.RstSource.Contents.Printers)
    if ($printers.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title 'Drucker anlegen' `
        -Message ('Diese Drucker werden neu eingerichtet. Bereits vorhandene bleiben unverändert. Fehlt ein Treiber, wird der Drucker übersprungen — WinZii lädt keine Treiber nach.' + (Get-WzRestoreForeignWarning)) `
        -Items @($printers | ForEach-Object { "$($_.name) an $($_.anschluss)" }) `
        -ConfirmText 'Anlegen'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Drucker anlegen' -ArgumentList (, $printers) -ScriptBlock {
        param($printers)
        Import-WzPrinters -Printers $printers
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title 'Drucker' -Result $result -ExtraKind 'MissingDriver' `
            -ExtraText 'übersprungen, weil der Treiber auf diesem PC fehlt'
    }
}

function Start-WzDriveImport {
    $drives = @($syncHash.RstSource.Contents.NetDrives)
    if ($drives.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title 'Netzlaufwerke verbinden' `
        -Message ('Diese Verbindungen werden dauerhaft angelegt. Ein bereits belegter Laufwerksbuchstabe wird übersprungen. Verlangt eine Freigabe eine Anmeldung, fragt Windows selbst danach — WinZii speichert keine Kennwörter.' + (Get-WzRestoreForeignWarning)) `
        -Items @($drives | ForEach-Object { "$($_.buchstabe) auf $($_.ziel)" }) `
        -ConfirmText 'Verbinden'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Netzlaufwerke verbinden' -ArgumentList (, $drives) -ScriptBlock {
        param($drives)
        Import-WzMappedDrives -Drives $drives
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title 'Netzlaufwerke' -Result $result
    }
}

function Show-WzRestoreResult {
    <#
    .SYNOPSIS
        Eine Rückmeldung für alle vier Vorgänge — geglückt, gescheitert und der
        jeweils dritte Fall, der weder das eine noch das andere ist.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)]$Result,
        [string]$ExtraKind,
        [string]$ExtraText
    )

    $applied = @($Result.Applied)
    $failed = @($Result.Failed)
    $extra = if ($ExtraKind) { @($Result.$ExtraKind) } else { @() }

    if ($syncHash.DryRun) {
        [void](Show-WzConfirm -Title $Title -HideCancel -ConfirmText 'Verstanden' `
            -Message 'Testmodus: Es wurde nichts verändert. Die Zeilen im Protokoll zeigen, was passiert wäre.')
        return
    }

    $lines = @()
    if ($applied.Count -gt 0) { $lines += "$($applied.Count) erledigt: $($applied -join ', ')" }
    if ($extra.Count -gt 0) { $lines += "$($extra.Count) $ExtraText`: $($extra -join ', ')" }
    if ($failed.Count -gt 0) { $lines += "$($failed.Count) fehlgeschlagen: $($failed -join ', ')" }
    if ($lines.Count -eq 0) { $lines += 'Es gab nichts zu tun — alles war schon eingerichtet.' }

    $message = if ($failed.Count -gt 0) {
        'Ein Teil hat nicht geklappt. Die Gründe stehen einzeln im Protokoll.'
    } elseif ($extra.Count -gt 0) {
        'Erledigt — mit Einschränkungen.'
    } else {
        'Erledigt.'
    }

    [void](Show-WzConfirm -Title $Title -Message $message -Items $lines `
        -HideCancel -ConfirmText 'Verstanden')
}
