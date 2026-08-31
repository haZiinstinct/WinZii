# Seite "Zurückspielen" — das Gegenstück zu den Exporten auf der Datenseite.

function Initialize-WzRestorePage {
    $syncHash.RstBtnScan.Add_Click({ Start-WzRestoreScan })
    $syncHash.RstBtnWlan.Add_Click({ Start-WzWlanImport })
    $syncHash.RstBtnMarks.Add_Click({ Start-WzBookmarkImport })
    $syncHash.RstBtnPrinters.Add_Click({ Start-WzPrinterImport })
    $syncHash.RstBtnDrives.Add_Click({ Start-WzDriveImport })

    [void]$syncHash.RstNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'rest.noticeWrites')))
}

function Update-WzRestorePage {
    if ($syncHash.RstLoaded) { return }
    $syncHash.RstLoaded = $true
    Start-WzRestoreScan
}

function Start-WzRestoreScan {
    $syncHash.RstSourceTitle.Text = Get-WzText 'rest.searching'
    foreach ($name in @('RstSources', 'RstWlan', 'RstMarks', 'RstDevices')) {
        $syncHash[$name].Children.Clear()
    }

    Invoke-WzTask -Name (Get-WzText 'rest.taskScan') -ScriptBlock {
        Get-WzBackupSources
    } -OnComplete {
        param($sources)
        # Ohne Fund reicht Invoke-WzTask $null herein. @($null) ist zwar ein
        # einelementiges Feld, der Binder lehnt es aber als NULL ab — genau der
        # Fall auf einem frisch ausgepackten Stick, auf dem noch nichts liegt.
        if (-not $sources) { $sources = @() }
        Write-WzRestoreSources -Sources @($sources)
    }
}

function Write-WzRestoreSources {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Sources)

    $syncHash.RstSourcesList = $Sources
    $container = $syncHash.RstSources

    if ($Sources.Count -eq 0) {
        $syncHash.RstSourceTitle.Text = Get-WzText 'rest.noBackupFound'
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'rest.lblSearchedIn') `
            (Get-WzPath 'offline' 'daten') -LabelWidth 200))
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'rest.lblHint') `
            (Get-WzText 'rest.hintBackupFirst') -LabelWidth 200))
        Set-WzRestoreSelection -Source $null
        return
    }

    $syncHash.RstSourceTitle.Text = if ($Sources.Count -eq 1) {
        Get-WzText 'rest.backupFrom' @{ rechner = $Sources[0].Computer }
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
        $hint.Text = Get-WzText 'rest.hintTopSource'
        $hint.Style = $syncHash.Window.FindResource('WzHint')
        $hint.Margin = New-Object Windows.Thickness(0, 8, 0, 0)
        [void]$container.Children.Add($hint)

        $button = New-Object Windows.Controls.Button
        $button.Content = Get-WzText 'rest.btnOtherSource'
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
        if ($_.IsCurrent) { Get-WzText 'rest.choiceThisPc' @{ rechner = $_.Computer } } else { Get-WzText 'rest.choiceOtherPc' @{ rechner = $_.Computer } }
    })
    $current = @($sources | ForEach-Object { $_.Computer }).IndexOf($syncHash.RstSource.Computer)

    $answer = Show-WzConfirm -Title (Get-WzText 'rest.sourceDialogTitle') `
        -Message (Get-WzText 'rest.sourceMessage') `
        -Choices $choices -ChoiceLabel (Get-WzText 'rest.lblBackup') -ChoiceDefault ([math]::Max(0, $current)) `
        -ConfirmText (Get-WzText 'rest.btnAdopt')
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
        $syncHash.RstWlanTitle.Text = Get-WzText 'rest.noWlanInBackup'
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
            $(if ($hasKey) { Get-WzText 'rest.withKey' } else { Get-WzText 'rest.withoutKey' }) `
            -Kind $(if ($hasKey) { 'ok' } else { 'warn' }) -LabelWidth 250))
    }

    $syncHash.RstWlanTitle.Text = if ($withoutKey -gt 0) {
        Get-WzText 'rest.wlanSomeWithoutKey' @{ anzahl = $files.Count; ohne = $withoutKey }
    } else {
        Get-WzText 'rest.wlanAllWithKey' @{ anzahl = $files.Count }
    }
    $syncHash.RstBtnWlan.IsEnabled = $true
}

function Write-WzRestoreMarks {
    param($Source)

    $container = $syncHash.RstMarks
    $container.Children.Clear()
    $files = if ($Source) { @($Source.Contents.BookmarkFiles) } else { @() }

    if ($files.Count -eq 0) {
        $syncHash.RstMarksTitle.Text = Get-WzText 'rest.noMarksInBackup'
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
                (Get-WzText 'rest.canRestore') -Kind 'ok' -LabelWidth 250))
        } else {
            $label = if ($entry.BrowserName) { $entry.BrowserName } else { Split-Path -Leaf $entry.Source }
            [void]$container.Children.Add((New-WzInfoRow $label $entry.Reason -Kind 'warn' -LabelWidth 250))
        }
    }

    $syncHash.RstMarksTitle.Text = Get-WzText 'rest.marksFit' @{ passend = $usable.Count; gesamt = $files.Count }
    $syncHash.RstBtnMarks.IsEnabled = ($usable.Count -gt 0)
}

function Write-WzRestoreDevices {
    param($Source)

    $container = $syncHash.RstDevices
    $container.Children.Clear()
    $printers = if ($Source) { @($Source.Contents.Printers) } else { @() }
    $drives = if ($Source) { @($Source.Contents.NetDrives) } else { @() }

    if ($printers.Count -eq 0 -and $drives.Count -eq 0) {
        $syncHash.RstDevicesTitle.Text = Get-WzText 'rest.noDevicesInBackup'
        [void]$container.Children.Add((New-WzInfoRow (Get-WzText 'rest.lblHint') `
            (Get-WzText 'rest.hintDeviceList') -LabelWidth 250))
        $syncHash.RstBtnPrinters.IsEnabled = $false
        $syncHash.RstBtnDrives.IsEnabled = $false
        return
    }

    foreach ($printer in $printers) {
        $marker = if ($printer.standard) { Get-WzText 'rest.suffixDefault' } else { '' }
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
        return Get-WzText 'rest.foreignWarning' @{ rechner = $syncHash.RstSource.Computer }
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

    $answer = Show-WzConfirm -Title (Get-WzText 'rest.wlanTitle') `
        -Message ((Get-WzText 'rest.wlanMessage') + (Get-WzRestoreForeignWarning)) `
        -Items $names -ConfirmText (Get-WzText 'rest.btnSetUp')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'rest.taskWlan') -ArgumentList (, $files) -ScriptBlock {
        param($files)
        Import-WzWlanProfiles -Files $files
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title (Get-WzText 'rest.resultWlanTitle') -Result $result -Extras @(
            @{ Kind = 'WithoutKey'; Text = (Get-WzText 'rest.extraWithoutKey') })
        Start-WzRestoreScan
    }
}

function Start-WzBookmarkImport {
    $targets = @($syncHash.RstMarkTargets | Where-Object { $_.Target })
    if ($targets.Count -eq 0) { return }

    $running = @($targets | ForEach-Object { $_.BrowserName } | Sort-Object -Unique |
        Where-Object { Get-WzBrowserProcess -BrowserName $_ })

    $items = @($targets | ForEach-Object { "$($_.BrowserName) / $($_.ProfileName)" })
    $message = Get-WzText 'rest.marksMessage'
    if ($running.Count -gt 0) {
        $message += Get-WzText 'rest.marksRunning' @{ browser = ($running -join ' / ') }
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'rest.marksTitle') `
        -Message ($message + (Get-WzRestoreForeignWarning)) -Items $items `
        -ConfirmText (Get-WzText 'rest.btnRestore') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'rest.taskMarks') -ArgumentList (, $targets) -ScriptBlock {
        param($targets)
        Import-WzBrowserBookmarks -Targets $targets
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title (Get-WzText 'rest.resultMarksTitle') -Result $result -Extras @(
            @{ Kind = 'Blocked'; Text = (Get-WzText 'rest.extraBlocked') })
    }
}

function Start-WzPrinterImport {
    $printers = @($syncHash.RstSource.Contents.Printers)
    if ($printers.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'rest.printersTitle') `
        -Message ((Get-WzText 'rest.printersMessage') + "`n`n" +
            (Get-WzText 'rest.printersMessage2') + (Get-WzRestoreForeignWarning)) `
        -Items @($printers | ForEach-Object { Get-WzText 'rest.printerItem' @{ name = $_.name; anschluss = $_.anschluss } }) `
        -ConfirmText (Get-WzText 'rest.btnCreate')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'rest.taskPrinters') -ArgumentList (, $printers) -ScriptBlock {
        param($printers)
        Import-WzPrinters -Printers $printers
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title (Get-WzText 'rest.resultPrintersTitle') -Result $result -Extras @(
            @{ Kind = 'MissingDriver'; Text = (Get-WzText 'rest.extraMissingDriver') }
            @{ Kind = 'MissingPort'; Text = (Get-WzText 'rest.extraMissingPort') })
    }
}

function Start-WzDriveImport {
    $drives = @($syncHash.RstSource.Contents.NetDrives)
    if ($drives.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title (Get-WzText 'rest.drivesTitle') `
        -Message ((Get-WzText 'rest.drivesMessage') + (Get-WzRestoreForeignWarning)) `
        -Items @($drives | ForEach-Object { Get-WzText 'rest.driveItem' @{ buchstabe = $_.buchstabe; ziel = $_.ziel } }) `
        -ConfirmText (Get-WzText 'rest.btnConnect')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'rest.taskDrives') -ArgumentList (, $drives) -ScriptBlock {
        param($drives)
        Import-WzMappedDrives -Drives $drives
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Show-WzRestoreResult -Title (Get-WzText 'rest.resultDrivesTitle') -Result $result
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
        # Je Eintrag ein Feldname aus dem Ergebnis und der Satz dazu. Mehrzahl,
        # weil ein Drucker aus zwei verschiedenen Gründen ausfallen kann.
        [hashtable[]]$Extras = @()
    )

    $applied = @($Result.Applied)
    $failed = @($Result.Failed)
    $extraLines = @()
    $extraCount = 0
    foreach ($entry in $Extras) {
        $values = @($Result.($entry.Kind))
        if ($values.Count -eq 0) { continue }
        $extraCount += $values.Count
        $extraLines += Get-WzText 'rest.extraLine' @{ anzahl = $values.Count; text = $entry.Text; liste = ($values -join ', ') }
    }

    if ($syncHash.DryRun) {
        [void](Show-WzConfirm -Title $Title -HideCancel -ConfirmText (Get-WzText 'dialog.understood') `
            -Message (Get-WzText 'rest.dryRunMessage'))
        return
    }

    $lines = @()
    if ($applied.Count -gt 0) { $lines += Get-WzText 'rest.lineDone' @{ anzahl = $applied.Count; liste = ($applied -join ', ') } }
    $lines += $extraLines
    if ($failed.Count -gt 0) { $lines += Get-WzText 'rest.lineFailed' @{ anzahl = $failed.Count; liste = ($failed -join ', ') } }
    if ($lines.Count -eq 0) { $lines += Get-WzText 'rest.nothingToDo' }

    $message = if ($failed.Count -gt 0) {
        Get-WzText 'rest.msgPartial'
    } elseif ($extraCount -gt 0) {
        Get-WzText 'rest.msgWithLimits'
    } else {
        Get-WzText 'rest.msgDone'
    }

    [void](Show-WzConfirm -Title $Title -Message $message -Items $lines `
        -HideCancel -ConfirmText (Get-WzText 'dialog.understood'))
}
