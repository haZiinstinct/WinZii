# Seite "Reparatur" — Netzwerk, Windows Update, Drucker, Sicherung,
# vorinstallierte Apps.

function Initialize-WzToolboxPage {
    $syncHash.ToolBtnNetDiag.Add_Click({ Start-WzNetworkDiagnosis })
    $syncHash.ToolBtnScan.Add_Click({ Start-WzDefenderQuickScan })
    $syncHash.ToolBtnRenew.Add_Click({ Start-WzNetworkRenew })
    $syncHash.ToolBtnNetReset.Add_Click({ Start-WzNetworkReset })
    $syncHash.ToolBtnWuReset.Add_Click({ Start-WzUpdateReset })
    $syncHash.ToolBtnSpooler.Add_Click({ Start-WzSpoolerRepair })
    $syncHash.ToolBtnRestorePoint.Add_Click({ Start-WzRestorePoint })
    $syncHash.ToolBtnBloatScan.Add_Click({ Start-WzBloatwareScan })
    $syncHash.ToolBtnBloatRemove.Add_Click({ Start-WzBloatwareRemove })

    foreach ($pair in @(
        @('ToolBtnDnsCloudflare', 'Cloudflare'),
        @('ToolBtnDnsQuad9', 'Quad9'),
        @('ToolBtnDnsGoogle', 'Google'),
        @('ToolBtnDnsAuto', 'Auto')
    )) {
        $button = $syncHash[$pair[0]]
        $provider = $pair[1]
        $button.Add_Click({ Start-WzDnsChange -Provider $provider }.GetNewClosure())
    }

    [void]$syncHash.ToolNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text 'Alle Eingriffe hier fragen vorher nach und schreiben mit, was sie tun. Im Testmodus wird nur protokolliert.'))
}

function Update-WzToolboxPage {
    if ($syncHash.ToolLoaded) { return }
    $syncHash.ToolLoaded = $true
    Start-WzBloatwareScan
}

# --- Netzwerk prüfen -------------------------------------------------------

function Start-WzNetworkDiagnosis {
    $syncHash.NetDiagTitle.Text = 'wird geprüft...'
    $syncHash.NetDiagSteps.Children.Clear()
    $syncHash.NetDiagVerdict.Items.Clear()

    Invoke-WzTask -Name 'Verbindung prüfen' -ScriptBlock {
        Invoke-WzNetworkDiagnosis
    } -OnComplete {
        param($diagnosis)
        if (-not $diagnosis) { return }
        Write-WzNetworkDiagnosis -Diagnosis $diagnosis
    }
}

function Write-WzNetworkDiagnosis {
    param([Parameter(Mandatory = $true)]$Diagnosis)

    $failed = @($Diagnosis.Steps | Where-Object { $_.Status -eq 'fail' })
    $syncHash.NetDiagTitle.Text = if ($Diagnosis.Ok) {
        'Verbindung in Ordnung'
    } elseif ($failed.Count -gt 0) {
        "Es hängt bei: $($failed[0].Name)"
    } else {
        'Auffälligkeit gefunden'
    }

    $container = $syncHash.NetDiagSteps
    $container.Children.Clear()
    foreach ($step in $Diagnosis.Steps) {
        $kind = switch ($step.Status) {
            'ok'   { 'ok' }
            'warn' { 'warn' }
            default { 'error' }
        }
        $mark = switch ($step.Status) {
            'ok'   { '✓' }
            'warn' { '!' }
            default { '✗' }
        }
        [void]$container.Children.Add((New-WzInfoRow "$mark $($step.Name)" $step.Detail -Kind $kind))
    }

    $verdictKind = if ($Diagnosis.Ok) { 'ok' } else { 'warn' }
    [void]$syncHash.NetDiagVerdict.Items.Add((New-WzNotice -Kind $verdictKind -Text $Diagnosis.Verdict))
    [void]$syncHash.NetDiagVerdict.Items.Add((New-WzNotice -Kind 'info' -Text $Diagnosis.Recommendation))

    Write-WzLog $Diagnosis.Verdict -Level $(if ($Diagnosis.Ok) { 'Ok' } else { 'Warn' })
}

function Start-WzDefenderQuickScan {
    $answer = Show-WzConfirm -Title 'Virenschnellprüfung' `
        -Message 'Der Windows-Defender prüft die üblichen Verstecke von Schadsoftware. Das dauert je nach PC fünf bis fünfzehn Minuten; solange lässt sich WinZii nicht weiter bedienen.' `
        -ConfirmText 'Starten'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Virenschnellprüfung' -ScriptBlock {
        Start-WzDefenderScan
    } -OnComplete {
        param($scan)
        if (-not $scan) { return }
        Add-WzAction -Area 'Sicherheit' -Summary "Virenschnellprüfung durchgeführt: $($scan.Summary)"
        Show-WzInfo -Title 'Virenschnellprüfung' -Message $scan.Summary -Items @($scan.Threats)
    }
}

# --- Netzwerk reparieren ---------------------------------------------------

function Start-WzNetworkRenew {
    Invoke-WzTask -Name 'IP-Adresse auffrischen' -ScriptBlock {
        Repair-WzNetworkAdapter
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' -Summary 'Netzwerkverbindung aufgefrischt'
        Show-WzInfo -Title 'Netzwerk aufgefrischt' `
            -Message "$($result.Done) Schritt(e) ausgeführt. Prüfe, ob die Verbindung jetzt steht — sonst hilft der vollständige Reset."
    }
}

function Start-WzNetworkReset {
    $answer = Show-WzConfirm -Title 'Netzwerk zurücksetzen' `
        -Message 'Winsock und der IP-Stapel werden auf die Werkseinstellung zurückgesetzt, der DNS-Zwischenspeicher geleert und der Proxy entfernt. Danach ist ein Neustart nötig. VPN-Programme müssen ihre Treiber danach eventuell neu einrichten.' `
        -Items @('Winsock zurücksetzen', 'IPv4 und IPv6 zurücksetzen', 'DNS-Zwischenspeicher leeren', 'Proxy zurücksetzen') `
        -ConfirmText 'Zurücksetzen' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Netzwerk zurücksetzen' -ScriptBlock {
        Invoke-WzNetworkReset -Winsock -IpStack -FlushDns -ResetProxy
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' -RebootRequired `
            -Summary 'Netzwerkeinstellungen auf den Auslieferungszustand zurückgesetzt'
        Show-WzInfo -Title 'Netzwerk zurückgesetzt' `
            -Message "$($result.Done) Schritt(e) erledigt. Der PC muss neu gestartet werden, damit die Änderungen greifen."
    }
}

function Start-WzDnsChange {
    param([string]$Provider)

    $description = switch ($Provider) {
        'Cloudflare' { '1.1.1.1 — schnell, keine Protokollierung der Anfragen' }
        'Quad9'      { '9.9.9.9 — blockiert bekannte Schadseiten, Betrieb in der Schweiz' }
        'Google'     { '8.8.8.8 — sehr zuverlässig erreichbar' }
        default      { 'Die Einstellungen kommen wieder vom Router' }
    }

    # Bewusst genau formuliert: »zurück auf Router« stellt auf DHCP um und ist
    # nicht dasselbe wie ein von Hand eingetragener Server. Die bisherigen Werte
    # landen deshalb vorher als Datei im Sicherungsordner.
    $answer = Show-WzConfirm -Title "DNS auf $Provider umstellen" `
        -Message ("$description`n`nDie Änderung gilt für alle aktiven Netzwerkkarten. Die bisherigen " +
            "Einstellungen werden vorher unter backups\ abgelegt — bei einem PC mit fest eingetragenem " +
            'Server (Firmennetz, eigener Router) ist das der einzige Weg zurück, denn »zurück auf Router« ' +
            'bedeutet nur: wieder automatisch beziehen.') `
        -ConfirmText 'Umstellen'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name "DNS auf $Provider" -ArgumentList @($Provider) -ScriptBlock {
        param($provider)
        Set-WzDnsServers -Provider $provider
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' -Summary "Namensauflösung auf $Provider umgestellt" `
            -Detail @($result.Adapters)
        $message = "$($result.Changed) Netzwerkkarte(n) geändert."
        if ($result.BackupFile) { $message += ' Die bisherigen Einstellungen liegen als Datei bereit.' }
        Show-WzInfo -Title 'DNS umgestellt' -Message $message `
            -Items @(@($result.Adapters) + @($result.BackupFile | Where-Object { $_ }))
    }.GetNewClosure()
}

# --- Windows Update und Drucker -------------------------------------------

function Start-WzUpdateReset {
    $answer = Show-WzConfirm -Title 'Update-Zwischenspeicher zurücksetzen' `
        -Message 'Die Update-Dienste werden angehalten, die Ordner SoftwareDistribution und catroot2 umbenannt und die Dienste wieder gestartet. Windows legt beide Ordner beim nächsten Update neu an. Bereits geladene Updates werden erneut heruntergeladen.' `
        -ConfirmText 'Zurücksetzen' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Windows Update zurücksetzen' -ScriptBlock {
        Repair-WzWindowsUpdate
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        $message = if ($result.Success) {
            'Der Zwischenspeicher wurde zurückgesetzt. Jetzt in den Einstellungen erneut nach Updates suchen.'
        } else {
            'Es konnte nichts umbenannt werden — die Ordner waren gesperrt. Nach einem Neustart erneut versuchen.'
        }
        if ($result.Success) {
            Add-WzAction -Area 'Reparatur' -Summary 'Zwischenspeicher von Windows Update zurückgesetzt'
        }
        Show-WzInfo -Title 'Windows Update' -Message $message -Items @($result.Messages)
    }
}

function Start-WzSpoolerRepair {
    $answer = Show-WzConfirm -Title 'Druckwarteschlange leeren' `
        -Message 'Alle wartenden Druckaufträge werden verworfen und der Druckdienst neu gestartet. Installierte Drucker bleiben erhalten.' `
        -ConfirmText 'Leeren'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Druckwarteschlange leeren' -ScriptBlock {
        Repair-WzSpooler
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Reparatur' `
            -Summary "Druckwarteschlange geleert ($($result.Removed) Auftrag/Aufträge)"
        Show-WzInfo -Title 'Druckwarteschlange' `
            -Message "$($result.Removed) Auftrag/Aufträge entfernt, Dienst neu gestartet."
    }
}

function Start-WzRestorePoint {
    $answer = Show-WzConfirm -Title 'Wiederherstellungspunkt anlegen' `
        -Message 'Windows legt einen Systemwiederherstellungspunkt an. Das dauert bis zu einer Minute und braucht etwas Speicherplatz. Ist der Systemschutz für C: ausgeschaltet, wird er dafür eingeschaltet und bleibt an.' `
        -ConfirmText 'Anlegen'
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Wiederherstellungspunkt anlegen' -ScriptBlock {
        New-WzRestorePoint -Description 'WinZii — manuell angelegt'
    } -OnComplete {
        param($ok)
        if ($ok) { Add-WzAction -Area 'Sicherung' -Summary 'Systemwiederherstellungspunkt angelegt' }
        $message = if ($ok) {
            'Der Wiederherstellungspunkt wurde angelegt.'
        } else {
            'Der Punkt konnte nicht angelegt werden. Häufigste Ursache: Der Systemschutz ist für das Laufwerk C: abgeschaltet.'
        }
        Show-WzInfo -Title 'Wiederherstellungspunkt' -Message $message
    }
}

# --- Vorinstallierte Apps --------------------------------------------------

function Start-WzBloatwareScan {
    $syncHash.ToolBloatTitle.Text = 'wird geprüft...'
    $syncHash.ToolBloatList.Children.Clear()

    Invoke-WzTask -Name 'Vorinstallierte Apps suchen' -Silent -ScriptBlock {
        Get-WzBloatwareList -Level 'extended'
    } -OnComplete {
        param($packages)
        $packages = @($packages)
        $syncHash.ToolBloatPackages = $packages

        $syncHash.ToolBloatTitle.Text = if ($packages.Count -eq 0) {
            'Nichts gefunden — der PC ist bereits aufgeräumt'
        } else {
            "$($packages.Count) App(s) gefunden"
        }

        $container = $syncHash.ToolBloatList
        $container.Children.Clear()
        $syncHash.ToolBloatBoxes = @()

        foreach ($package in $packages) {
            $item = [pscustomobject]@{
                name        = $package.DisplayName
                description = $package.Description
            }
            $row = New-WzCheckRow -Item $item -IsChecked $false
            $row.CheckBox.Tag = $package
            $row.CheckBox.Add_Click({ Update-WzBloatwareSelection })
            [void]$container.Children.Add($row.Row)
            $syncHash.ToolBloatBoxes += $row.CheckBox
        }

        Update-WzBloatwareSelection
        if ($packages.Count -gt 0) {
            Write-WzLog "$($packages.Count) vorinstallierte App(s) gefunden, die entfernt werden können." -Level Info
        }
    }
}

function Update-WzBloatwareSelection {
    $count = @($syncHash.ToolBloatBoxes | Where-Object { $_.IsChecked }).Count
    $syncHash.ToolBtnBloatRemove.IsEnabled = ($count -gt 0)
}

function Start-WzBloatwareRemove {
    $selected = @($syncHash.ToolBloatBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    $answer = Show-WzConfirm -Title 'Apps entfernen' `
        -Message "$($selected.Count) App(s) werden für alle Benutzer entfernt und auch für neu angelegte Konten nicht mehr bereitgestellt. Über den Microsoft Store lassen sie sich bei Bedarf wieder installieren." `
        -Items @($selected | ForEach-Object { $_.DisplayName }) `
        -ConfirmText 'Entfernen' -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name 'Apps entfernen' -ArgumentList (, $selected) -ScriptBlock {
        param($packages)
        Remove-WzBloatware -Packages $packages
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        Add-WzAction -Area 'Vorinstallierte Apps' `
            -Summary "$($result.Removed) mitgelieferte App(s) entfernt" `
            -Detail @($selected | ForEach-Object { $_.DisplayName })

        $message = "$($result.Removed) App(s) entfernt, $($result.Failed) fehlgeschlagen."
        if ($result.RecordFile) { $message += ' Was entfernt wurde, steht in der Liste darunter.' }
        Show-WzInfo -Title 'Fertig' -Message $message `
            -Items @($result.RecordFile | Where-Object { $_ })
        Start-WzBloatwareScan
    }.GetNewClosure()
}
