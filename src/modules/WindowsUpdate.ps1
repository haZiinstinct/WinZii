# WindowsUpdate — ausstehende Updates finden und einspielen.
#
# Über die COM-Schnittstelle von Windows (Microsoft.Update.Session). Sie gehört
# zum System, es muss also kein Modul nachinstalliert werden — genau richtig für
# ein Werkzeug, das auf fremden Rechnern ohne Internet startet.
#
# Zwei Dinge sind hier anders als im übrigen Programm:
#
#   1. COM-Objekte überleben den Faden nicht, in dem sie entstanden sind. Die
#      Suche gibt deshalb nur einfache Daten zurück, und das Einspielen sucht im
#      selben Hintergrundlauf noch einmal über die Kennung. Das kostet ein paar
#      Sekunden und erspart das Weiterreichen von COM zwischen den Fäden — das
#      schlägt sonst mit einer Ausnahme fehl, die niemand deuten kann.
#
#   2. Treiber werden getrennt geführt und nie vorausgewählt. Windows Update
#      bietet dort gern ältere Herstellerstände an, die einen neueren Treiber
#      überschreiben. Beim Kunden ist genau das der häufigste Rückschritt nach
#      einem "einmal alles aktualisieren".

function Get-WzUpdateState {
    <#
    .SYNOPSIS
        Zustand des Update-Dienstes, ohne im Netz zu suchen.
    .DESCRIPTION
        Läuft in unter einer Sekunde und beantwortet die Frage, die vor jeder
        Suche steht: Kann dieser PC überhaupt Updates beziehen? Ein
        abgeschalteter Dienst ist der häufigste Grund dafür, dass ein Kunde seit
        Monaten nichts mehr bekommen hat.
    #>
    [CmdletBinding()]
    param()

    $state = [ordered]@{
        ServiceRunning = $false
        ServiceStartup = ''
        ServiceOk      = $false
        Managed        = $false
        LastInstall    = $null
        RebootPending  = $false
    }

    $service = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($service) {
        $state.ServiceRunning = ($service.Status -eq 'Running')
        try {
            $wmi = Get-CimInstance -Query "SELECT StartMode FROM Win32_Service WHERE Name='wuauserv'" -ErrorAction Stop
            $state.ServiceStartup = [string]$wmi.StartMode
        } catch { }
        # »Disabled« ist die einzige Stellung, in der nichts mehr geht. Der
        # Dienst startet sonst bei Bedarf von selbst — er muss nicht laufen.
        $state.ServiceOk = ($state.ServiceStartup -ne 'Disabled')
    }

    # Wird Windows Update per Richtlinie gesteuert, entscheidet die Verwaltung,
    # was ankommt. Das gehört auf das Übergabeblatt, nicht in eine Fehlermeldung.
    #
    # Auf das blosse Vorhandensein des Schlüssels darf man sich dabei NICHT
    # verlassen: Windows legt beide Zweige auch auf einem völlig unverwalteten
    # PC an, nur ohne Werte. Die erste Fassung meldete deshalb auf dem
    # Entwicklungsrechner eine Gruppenrichtlinie, die es dort nicht gibt.
    foreach ($pfad in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU')) {
        $werte = Get-ItemProperty -LiteralPath $pfad -ErrorAction SilentlyContinue
        if (-not $werte) { continue }
        $echte = @($werte.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
        if ($echte.Count -gt 0) { $state.Managed = $true }
    }

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $count = $searcher.GetTotalHistoryCount()
        if ($count -gt 0) {
            $letzte = $searcher.QueryHistory(0, 1)
            if ($letzte.Count -gt 0) { $state.LastInstall = $letzte.Item(0).Date }
        }
    } catch { }

    $state.RebootPending = [bool](Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

    return [pscustomobject]$state
}

function Find-WzUpdates {
    <#
    .SYNOPSIS
        Sucht ausstehende Updates und gibt einfache Daten zurück.
    .DESCRIPTION
        Läuft im Hintergrund und braucht auf langsamen Verbindungen ein bis zwei
        Minuten — die Suche fragt beim Server nach, welche der tausenden Updates
        auf genau diesen PC passen.

        Zurück kommen bewusst keine COM-Objekte, sondern gewöhnliche Objekte.
        Alles, was das Einspielen später braucht, steckt in der Kennung.
    .OUTPUTS
        Objekt mit Ok, Updates, Error.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{
        Ok      = $false
        Updates = @()
        Error   = ''
        Code    = ''
    }

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # ServerSelection bleibt auf der Voreinstellung: Ist ein WSUS
        # eingetragen, wird der gefragt — das ist auf Firmengeräten richtig so.
        $found = $searcher.Search('IsInstalled=0 and IsHidden=0')

        $liste = @()
        foreach ($update in $found.Updates) {
            $kb = @($update.KBArticleIDs) | Select-Object -First 1
            $liste += [pscustomobject]@{
                Id             = $update.Identity.UpdateID
                Title          = $update.Title
                KB             = if ($kb) { "KB$kb" } else { '' }
                # MaxDownloadSize ist eine OBERGRENZE, keine Vorhersage: Sie gilt
                # fuer die groesste Variante des Pakets. Das taegliche
                # Defender-Signaturupdate meldet hier 1,4 GB und laedt rund 100 MB.
                # Deshalb steht in der Anzeige »bis zu« davor — eine nackte Zahl
                # wuerde einen Techniker vom Einspielen abhalten.
                SizeBytes      = [int64]$update.MaxDownloadSize
                # UpdateType 2 ist ein Treiber
                IsDriver       = ([int]$update.Type -eq 2)
                IsDownloaded   = [bool]$update.IsDownloaded
                IsMandatory    = [bool]$update.IsMandatory
                Severity       = [string]$update.MsrcSeverity
                RebootRequired = ([int]$update.InstallationBehavior.RebootBehavior -ne 0)
            }
        }
        $result.Updates = @($liste)
        $result.Ok = $true
    } catch {
        $result.Code = Get-WzUpdateHResult $_
        $result.Error = (Get-WzUpdateCodeText -Code $result.Code).Text
    }

    return $result
}

function Format-WzUpdateCode {
    <#
    .SYNOPSIS
        Windows-Fehlercode als »0x80240044«.
    .NOTES
        Ohne Maske und ohne [uint32]: »-band 0xFFFFFFFF« liefert in PowerShell
        nicht das, was man erwartet, und der Guss nach uint32 warf bei jedem
        negativen HResult eine Ausnahme — die den ganzen Einspielvorgang mit
        sich riss. .NET formatiert einen negativen Int32 mit »X8« ohnehin im
        Zweierkomplement, also genau so, wie Windows den Code nennt.
    #>
    param($Value)

    if ($null -eq $Value) { return '' }
    return ('0x{0:X8}' -f [int]$Value)
}

function Get-WzUpdateHResult {
    <#
    .SYNOPSIS
        Holt den Windows-Fehlercode aus einer Ausnahme, als »0x8024402C«.
    .NOTES
        Die COM-Schnittstelle wirft gewöhnliche Ausnahmen; die eigentliche
        Ursache steckt weiter innen. Die äußere Ausnahme trägt nur den
        Sammelcode von PowerShell (0x80131501), mit dem niemand etwas anfangen
        kann — deshalb wird die Kette bis zur innersten Ursache verfolgt.
    #>
    param($ErrorRecord)

    $wert = $null
    try {
        $ausnahme = $ErrorRecord.Exception
        while ($ausnahme) {
            $wert = $ausnahme.HResult
            $ausnahme = $ausnahme.InnerException
        }
    } catch { }
    return Format-WzUpdateCode $wert
}

function Get-WzUpdateCodeText {
    <#
    .SYNOPSIS
        Übersetzt einen Update-Fehlercode in einen Satz.
    .OUTPUTS
        Objekt mit Outcome (ok, skip, fail) und Text.
    #>
    param([string]$Code)

    $result = [pscustomobject]@{
        Outcome = 'fail'
        Text    = if ($Code) { Get-WzText 'upd.codeUnknown' @{ code = $Code } } else { Get-WzText 'upd.codeNone' }
    }
    if (-not $Code) { return $result }

    try {
        $catalog = Get-WzCatalog -Name 'updatecodes'
        $entry = @($catalog.codes | Where-Object { $_.code -eq $Code })[0]
        if ($entry) {
            $result.Outcome = $entry.outcome
            $result.Text = $entry.text
        }
    } catch {
        # Ohne Katalog bleibt die Zahl — besser als ein Absturz
    }
    return $result
}

function Get-WzUpdateResultCode {
    <#
    .SYNOPSIS
        Der aussagekräftige Fehlercode eines Lade- oder Einspielergebnisses.
    .DESCRIPTION
        Das Sammelergebnis meldet bei jedem Fehlschlag nur »0x80240022 — alle
        Updates fehlgeschlagen«. Das steht auf keinem Zettel, den ein Techniker
        gebrauchen kann. Der eigentliche Grund liegt eine Ebene tiefer, beim
        einzelnen Update: dort stand im ersten echten Versuch »0x80240044 —
        Administratorrechte fehlen«, und damit war die Sache klar.

        Da immer genau ein Update in der Sammlung liegt, ist das Feld 0 das
        richtige. Fehlt es, bleibt der Sammelcode.
    #>
    param($Result)

    try {
        $einzeln = $Result.GetUpdateResult(0)
        if ($einzeln -and [int]$einzeln.HResult -ne 0) { return Format-WzUpdateCode $einzeln.HResult }
        if ($einzeln) { return Format-WzUpdateCode $einzeln.HResult }
    } catch { }
    return Format-WzUpdateCode $Result.HResult
}

function Install-WzUpdates {
    <#
    .SYNOPSIS
        Spielt die ausgewählten Updates ein, eines nach dem anderen.
    .DESCRIPTION
        Einzeln statt in einem Rutsch, weil ein Techniker sehen will, wo es
        hängt. Ein Paket mit fünfzehn Updates, das nach vierzig Minuten
        »fehlgeschlagen« meldet, sagt nichts; fünfzehn Zeilen sagen alles.

        Neu gestartet wird nie von hier aus. Ob und wann ein PC neu startet,
        entscheidet der Techniker — mitten in einer Datensicherung wäre ein
        selbsttätiger Neustart das Schlimmste, was passieren kann.
    .PARAMETER UpdateIds
        Kennungen aus Find-WzUpdates.
    .OUTPUTS
        Objekt mit Installed, Skipped, Failed, RebootRequired, Details.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$UpdateIds)

    $summary = [pscustomobject]@{
        Installed      = 0
        Skipped        = 0
        Failed         = 0
        RebootRequired = $false
        Details        = @()
        Error          = ''
    }

    if ($syncHash.DryRun) {
        foreach ($id in $UpdateIds) {
            Write-WzLog (Get-WzText 'upd.logTestInstall' @{ kennung = $id }) -Level Test
        }
        $summary.Skipped = $UpdateIds.Count
        return $summary
    }

    $session = $null
    $found = $null
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found = $searcher.Search('IsInstalled=0 and IsHidden=0')
    } catch {
        $code = Get-WzUpdateHResult $_
        $summary.Error = (Get-WzUpdateCodeText -Code $code).Text
        Write-WzLog (Get-WzText 'upd.logSearchFailed' @{ grund = $summary.Error }) -Level Error
        return $summary
    }

    foreach ($id in $UpdateIds) {
        $update = $null
        foreach ($kandidat in $found.Updates) {
            if ($kandidat.Identity.UpdateID -eq $id) { $update = $kandidat; break }
        }
        if (-not $update) {
            # Zwischen Suche und Einspielen kann Windows selbst etwas erledigt
            # haben. Das ist kein Fehlschlag.
            $summary.Skipped++
            continue
        }

        Write-WzLog (Get-WzText 'upd.logInstalling' @{ name = $update.Title }) -Level Action
        try {
            if (-not $update.EulaAccepted) { $update.AcceptEula() }

            $collection = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$collection.Add($update)

            if (-not $update.IsDownloaded) {
                $downloader = $session.CreateUpdateDownloader()
                $downloader.Updates = $collection
                $ladeErgebnis = $downloader.Download()
                # Ein fehlgeschlagener Download macht das Einspielen sinnlos —
                # und meldet einen anderen, nützlicheren Grund als der
                # Installierer, der danach nur noch »nichts da« sagen kann.
                if ([int]$ladeErgebnis.ResultCode -notin @(2, 3)) {
                    $deutung = Get-WzUpdateCodeText -Code (Get-WzUpdateResultCode $ladeErgebnis)
                    $summary.Failed++
                    $summary.Details += Get-WzText 'upd.detailFailed' @{ name = $update.Title; grund = $deutung.Text }
                    Write-WzLog (Get-WzText 'upd.logDownloadFailed' @{ name = $update.Title; grund = $deutung.Text }) -Level Error
                    continue
                }
            }

            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $collection
            $ergebnis = $installer.Install()

            $deutung = Get-WzUpdateCodeText -Code (Get-WzUpdateResultCode $ergebnis)

            # ResultCode 2 = erfolgreich, 3 = erfolgreich mit Anmerkungen.
            # Der HResult allein reicht nicht: Er ist auch bei 3 gleich null.
            if ([int]$ergebnis.ResultCode -in @(2, 3)) {
                $summary.Installed++
                $summary.Details += Get-WzText 'upd.detailInstalled' @{ name = $update.Title }
                Write-WzLog (Get-WzText 'upd.logInstalled' @{ name = $update.Title }) -Level Ok
                if ($ergebnis.RebootRequired) { $summary.RebootRequired = $true }
            } elseif ($deutung.Outcome -eq 'skip') {
                $summary.Skipped++
                Write-WzLog (Get-WzText 'upd.logSkipped' @{ name = $update.Title; grund = $deutung.Text }) -Level Info
            } else {
                $summary.Failed++
                $summary.Details += Get-WzText 'upd.detailFailed' @{ name = $update.Title; grund = $deutung.Text }
                Write-WzLog (Get-WzText 'upd.logFailed' @{ name = $update.Title; grund = $deutung.Text }) -Level Error
            }
        } catch {
            $code = Get-WzUpdateHResult $_
            $deutung = Get-WzUpdateCodeText -Code $code
            $summary.Failed++
            $summary.Details += Get-WzText 'upd.detailFailed' @{ name = $update.Title; grund = $deutung.Text }
            Write-WzLog (Get-WzText 'upd.logFailed' @{ name = $update.Title; grund = $deutung.Text }) -Level Error
        }
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $summary.RebootRequired = $true
    }
    return $summary
}
