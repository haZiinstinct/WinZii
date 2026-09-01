# Migration — die Gegenstücke zu den Exporten auf der Datenseite, dazu der
# echte Dateiumzug und die OneDrive-Hydrierung.
#
# WinZii konnte WLAN-Netze, Lesezeichen, Drucker und Netzlaufwerke bisher nur
# herausschreiben. Nach dem Neuaufsetzen fehlte zu jedem Export das Gegenstück,
# und der Techniker tippte alles von Hand nach. Hier liegt die andere Hälfte.

# --- Dateiumzug ------------------------------------------------------------

function Get-WzMigrationVolumes {
    <#
    .SYNOPSIS
        Laufwerke, die als Ziel für einen Dateiumzug taugen.
    .DESCRIPTION
        Das Systemlaufwerk fällt heraus — eine Sicherung auf dieselbe Platte
        überlebt weder eine Neuinstallation noch einen Plattendefekt. Der
        WinZii-Datenträger bleibt in der Liste, wird aber gekennzeichnet: Auf
        einem Technikerstick liegen bereits bis zu vier Gigabyte Office-Vorrat,
        und Kundendaten haben dort nichts verloren.
    #>
    [CmdletBinding()]
    param()

    $systemLetter = ''
    if ($env:SystemDrive -match '^([A-Za-z]):') { $systemLetter = "$($Matches[1]):" }
    $ownLetter = ''
    $own = Get-WzVolumeInfo
    if ($own.DriveLetter) { $ownLetter = "$($own.DriveLetter):" }

    $volumes = @()
    try {
        $query = 'SELECT DeviceID,DriveType,VolumeName,FreeSpace,Size,FileSystem FROM Win32_LogicalDisk WHERE DriveType=2 OR DriveType=3'
        foreach ($disk in (Get-CimInstance -Query $query -ErrorAction Stop)) {
            if ($disk.DeviceID -eq $systemLetter) { continue }
            if (-not $disk.Size) { continue }
            $volumes += [pscustomobject]@{
                Letter      = $disk.DeviceID
                Label       = $(if ($disk.VolumeName) { $disk.VolumeName } else { Get-WzText 'data.volumeNoLabel' })
                FileSystem  = $disk.FileSystem
                FreeBytes   = [int64]$disk.FreeSpace
                SizeBytes   = [int64]$disk.Size
                IsRemovable = ($disk.DriveType -eq 2)
                IsWinZii    = ($disk.DeviceID -eq $ownLetter)
                # FAT32 kann keine Datei über 4 GB — bei Videos und Archiven
                # scheitert der Umzug sonst mitten im Lauf.
                IsFat32     = ($disk.FileSystem -eq 'FAT32')
            }
        }
    } catch {
        Write-WzLog (Get-WzText 'data.logVolumesUnreadable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return @($volumes | Sort-Object -Property @{ Expression = 'FreeBytes'; Descending = $true })
}

function New-WzMigrationJobs {
    <#
    .SYNOPSIS
        Aus einem Benutzerprofil wird je persönlichem Ordner ein Kopierauftrag.
    .PARAMETER UserProfile
        Ein Eintrag aus Get-WzUserProfiles — dessen Folders sind bereits
        vermessen, es wird nichts doppelt gezählt.
    .NOTES
        Der Parameter heißt bewusst nicht »Profile«: Das ist in PowerShell eine
        eingebaute Variable, und ein Parameter gleichen Namens verdeckt sie
        innerhalb der Funktion.
    #>
    param(
        [Parameter(Mandatory = $true)]$UserProfile,
        [Parameter(Mandatory = $true)][string]$Target
    )

    # Account steht als DOMÄNE\Benutzer da. Der Rechnername steht schon eine
    # Ebene höher im Pfad — sonst hieße der Ordner PC\PC-Benutzer.
    $accountName = $UserProfile.Account
    if ($accountName -match '\\([^\\]+)$') { $accountName = $Matches[1] }
    $safeAccount = ($accountName -replace '[\\/:*?"<>|]', '-')
    $base = Join-Path (Join-Path $Target 'WinZii-Daten') (Join-Path $env:COMPUTERNAME $safeAccount)

    return @($UserProfile.Folders | ForEach-Object {
        [pscustomobject]@{
            Name        = $_.Name
            Source      = $_.Path
            Destination = Join-Path $base $_.Name
            Bytes       = $_.Bytes
            Items       = $_.Items
        }
    })
}

function Invoke-WzFileMigration {
    <#
    .SYNOPSIS
        Kopiert persönliche Ordner mit robocopy auf das Ziellaufwerk.
    .DESCRIPTION
        Bewusst kopieren statt verschieben: Weder /MOVE noch /MIR noch /PURGE
        kommen vor, die Quelle bleibt vollständig erhalten. Wer löschen will,
        tut das später selbst und sieht vorher, dass die Kopie angekommen ist.

        Gezählt wird nicht über die Textausgabe von robocopy — die ist
        übersetzt und bricht bei der nächsten Windows-Sprache. Stattdessen wird
        das Ziel hinterher vermessen, und über Erfolg entscheidet der
        Rückgabewert: bis 7 ist alles in Ordnung, ab 8 gab es echte Fehler.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Jobs)

    $done = @()
    $failed = @()
    $copiedBytes = [int64]0
    $index = 0

    foreach ($job in $Jobs) {
        $index++
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'data.logCopyTest' @{ name = $job.Name; ziel = $job.Destination; groesse = (Format-WzBytes $job.Bytes) }) -Level Test
            continue
        }
        if ($syncHash.CurrentTask -and $syncHash.CurrentTask.Canceled) {
            # Zwischen zwei Ordnern aussteigen statt mitten in einem: Ein
            # halb kopierter Ordner sieht auf dem Ziel aus wie ein ganzer.
            Write-WzLog (Get-WzText 'data.logCopyCancelled') -Level Warn
            break
        }

        Write-WzLog (Get-WzText 'data.logCopying' @{ name = $job.Name; nummer = $index; gesamt = $Jobs.Count; groesse = (Format-WzBytes $job.Bytes) }) -Level Info

        # /XJ überspringt Verzweigungspunkte: In den Benutzerordnern liegen
        # Kompatibilitätsverweise, die sonst im Kreis führen.
        # /COPY:DAT ohne Berechtigungen — die passen auf einem anderen PC ohnehin nicht.
        $arguments = '"{0}" "{1}" /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:2 /NP /NFL /NDL /NJH /NJS' -f `
            $job.Source.TrimEnd('\'), $job.Destination.TrimEnd('\')
        $result = Invoke-WzProcess -FilePath 'robocopy.exe' -Arguments $arguments

        $measure = Measure-WzPathSet -Paths @($job.Destination)
        if ($result.ExitCode -ge 8 -or $null -eq $result.ExitCode) {
            $failed += Get-WzText 'data.copyFailedEntry' @{ name = $job.Name; code = $result.ExitCode }
            Write-WzLog (Get-WzText 'data.logCopyFailed' @{ name = $job.Name; code = $result.ExitCode }) -Level Err
        } else {
            $done += Get-WzText 'data.copyDoneEntry' @{ name = $job.Name; groesse = (Format-WzBytes $measure.Bytes); anzahl = $measure.Items }
            $copiedBytes += $measure.Bytes
            Write-WzLog (Get-WzText 'data.logCopiedOne' @{ name = $job.Name; groesse = (Format-WzBytes $measure.Bytes) }) -Level Ok
        }
    }

    if ($done.Count -gt 0) {
        Write-WzLog (Get-WzText 'data.logCopyDone' @{ groesse = (Format-WzBytes $copiedBytes); anzahl = $done.Count }) -Level Ok
        Add-WzAction -Area 'Datensicherung' `
            -Summary (Get-WzText 'data.actionCopied' @{ groesse = (Format-WzBytes $copiedBytes) }) -Detail $done
    }

    return [pscustomobject]@{
        Applied     = @($done)
        Failed      = @($failed)
        CopiedBytes = $copiedBytes
    }
}

# --- OneDrive ---------------------------------------------------------------

function Invoke-WzOneDriveHydration {
    <#
    .SYNOPSIS
        Löst »Immer auf diesem Gerät behalten« aus und wartet auf den Abschluss.
    .DESCRIPTION
        Bisher warnte WinZii nur vor Platzhaltern. Der Griff dazu ist
        attrib +P -U: Das setzt das Kennzeichen »angeheftet« und löscht
        »nicht angeheftet«, woraufhin OneDrive die Dateien herunterlädt.

        Das Herunterladen selbst macht OneDrive im eigenen Tempo — deshalb wird
        anschließend gezählt, wie viele Platzhalter noch übrig sind, und ehrlich
        gemeldet, wenn das Zeitbudget vor dem Abschluss abläuft. Ohne laufenden
        OneDrive-Dienst passiert gar nichts; auch das steht im Ergebnis.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 900
    )

    $result = [pscustomobject]@{
        Path      = $Path
        Started   = $false
        Complete  = $false
        Remaining = 0
        Reason    = ''
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Reason = Get-WzText 'data.reasonNoFolder'
        return $result
    }
    if (-not (Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)) {
        $result.Reason = Get-WzText 'data.reasonNotRunning'
        return $result
    }
    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'data.logHydrateTest' @{ pfad = $Path }) -Level Test
        $result.Reason = Get-WzText 'data.reasonDryRun'
        return $result
    }

    $before = Get-WzPlaceholderCount -Path $Path
    if ($before -eq 0) {
        $result.Started = $true
        $result.Complete = $true
        $result.Reason = Get-WzText 'data.reasonAlreadyLocal'
        return $result
    }

    Write-WzLog (Get-WzText 'data.logPlaceholdersFound' @{ anzahl = $before }) -Level Action
    $attrib = Invoke-WzProcess -FilePath 'attrib.exe' -Arguments "+P -U /s /d `"$Path`"" -TimeoutSeconds 120
    if ($attrib.ExitCode -ne 0) {
        $result.Reason = Get-WzText 'data.reasonAttribFailed' @{ code = $attrib.ExitCode }
        return $result
    }
    $result.Started = $true

    # Warten und mitzählen. Bleibt die Zahl über mehrere Runden stehen, lädt
    # nichts mehr — dann ist Warten sinnlos und Weiterlaufen eine Lüge.
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $remaining = $before
    $stalled = 0
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 10
        if ($syncHash.CurrentTask -and $syncHash.CurrentTask.Canceled) {
            $result.Reason = Get-WzText 'data.reasonCancelled'
            break
        }
        $now = Get-WzPlaceholderCount -Path $Path
        if ($now -eq 0) {
            $result.Complete = $true
            break
        }
        if ($now -ge $remaining) { $stalled++ } else { $stalled = 0 }
        $remaining = $now
        Write-WzLog (Get-WzText 'data.logRemaining' @{ rest = $remaining
            geladen = (Format-WzNumber ($before - $remaining) (Get-WzText 'data.unitFiles') -Decimals 0) }) -Level Info

        if ($stalled -ge 6) {
            $result.Reason = Get-WzText 'data.reasonStalled'
            break
        }
    }

    $result.Remaining = if ($result.Complete) { 0 } else { Get-WzPlaceholderCount -Path $Path }
    if ($result.Complete) {
        Write-WzLog (Get-WzText 'data.logHydrateDone') -Level Ok
        Add-WzAction -Area 'Datensicherung' -Summary (Get-WzText 'data.actionHydrated' @{ anzahl = $before })
    } elseif (-not $result.Reason) {
        $result.Reason = Get-WzText 'data.reasonTimeout' @{ minuten = [int]($TimeoutSeconds / 60) }
    }

    return $result
}

function Get-WzPlaceholderCount {
    <#
    .SYNOPSIS
        Zählt die Dateien, die nur in der Cloud liegen.
    .NOTES
        Dieselbe Erkennung wie in Get-WzOneDriveState: Offline oder
        RECALL_ON_DATA_ACCESS (0x00400000).
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $recallOnDataAccess = 0x00400000
    $count = 0
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            try {
                $attributes = [int][IO.File]::GetAttributes($file)
                if (($attributes -band [int][IO.FileAttributes]::Offline) -ne 0 -or
                    ($attributes -band $recallOnDataAccess) -ne 0) {
                    $count++
                }
            } catch { }
        }
    } catch { }
    return $count
}

function Get-WzBackupSources {
    <#
    .SYNOPSIS
        Alle Sicherungen unter offline\daten — die dieses Rechners und die
        fremder Rechner.
    .DESCRIPTION
        Bewusst auch fremde: Genau dafür ist der Stick gedacht. Der Aufrufer
        bekommt mit IsCurrent gesagt, welche vom Rechner selbst stammt, und
        warnt entsprechend.
    #>
    [CmdletBinding()]
    param()

    $root = Get-WzPath 'offline' 'daten'
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $sources = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $contents = Get-WzBackupContents -Path $dir.FullName
        if ($contents.Total -eq 0) { continue }
        $sources += [pscustomobject]@{
            Computer  = $dir.Name
            Path      = $dir.FullName
            IsCurrent = ($dir.Name -eq $env:COMPUTERNAME)
            Saved     = $dir.LastWriteTime
            Contents  = $contents
        }
    }

    return @($sources | Sort-Object -Property @{ Expression = 'IsCurrent'; Descending = $true }, Computer)
}

function Get-WzBackupContents {
    <#
    .SYNOPSIS
        Was in einer Sicherung tatsächlich liegt.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $wlanDir = Join-Path $Path 'wlan'
    $markDir = Join-Path $Path 'lesezeichen'
    $deviceFile = Join-Path $Path 'geraete.json'

    $wlan = @(Get-ChildItem -LiteralPath $wlanDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    $marks = @(Get-ChildItem -LiteralPath $markDir -File -ErrorAction SilentlyContinue)

    $printers = @()
    $drives = @()
    $devices = Read-WzJson $deviceFile
    if ($devices) {
        $printers = @($devices.drucker)
        $drives = @($devices.laufwerke)
    }

    return [pscustomobject]@{
        WlanFiles     = @($wlan | ForEach-Object { $_.FullName })
        BookmarkFiles = @($marks | ForEach-Object { $_.FullName })
        Printers      = $printers
        NetDrives     = $drives
        DeviceFile    = $(if ($devices) { $deviceFile } else { $null })
        Total         = $wlan.Count + $marks.Count + $printers.Count + $drives.Count
    }
}

function Import-WzWlanProfiles {
    <#
    .SYNOPSIS
        Spielt gesicherte WLAN-Netze über netsh zurück.
    .DESCRIPTION
        Ein Profil ohne Schlüssel wird angelegt, verbindet sich aber nicht —
        das steht im Ergebnis, damit die Rückmeldung nicht mehr verspricht als
        tatsächlich passiert ist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files)

    $applied = @()
    $failed = @()
    $withoutKey = @()

    foreach ($file in $Files) {
        # netsh benennt die Dateien "WLAN-Schnittstelle-<SSID>.xml"; im Ergebnis
        # soll die SSID stehen, nicht der Dateiname.
        $name = Get-WzWlanProfileName -Path $file
        if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($file) }

        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'rest.logWlanTest' @{ name = $name }) -Level Test
            continue
        }

        $result = Invoke-WzProcess -FilePath 'netsh.exe' `
            -Arguments "wlan add profile filename=`"$file`" user=all" -TimeoutSeconds 30
        if ($result.ExitCode -eq 0) {
            $applied += $name
            if (-not (Test-WzWlanProfileHasKey -Path $file)) { $withoutKey += $name }
        } else {
            $failed += $name
            $reason = "$($result.StdOut)$($result.StdErr)".Split([char]10)[0].Trim()
            Write-WzLog (Get-WzText 'rest.logWlanFailed' @{ name = $name; grund = $reason }) -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog (Get-WzText 'rest.logWlanDone' @{ anzahl = $applied.Count }) -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary (Get-WzText 'rest.actionWlan' @{ anzahl = $applied.Count }) -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed); WithoutKey = @($withoutKey) }
}

function Get-WzWlanProfileName {
    <#
    .SYNOPSIS
        SSID aus einer von netsh geschriebenen Profildatei.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $xml = [xml][IO.File]::ReadAllText($Path)
        return $xml.WLANProfile.SSIDConfig.SSID.name
    } catch { return $null }
}

function Test-WzWlanProfileHasKey {
    <#
    .SYNOPSIS
        Steht in der Profildatei ein Schlüssel, oder wurde ohne key=clear
        gesichert?
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $xml = [xml][IO.File]::ReadAllText($Path)
        return [bool]$xml.WLANProfile.MSM.security.sharedKey.keyMaterial
    } catch { return $false }
}

function Import-WzPrinters {
    <#
    .SYNOPSIS
        Legt gesicherte Drucker wieder an.
    .DESCRIPTION
        Ohne passenden Treiber geht nichts — Add-Printer beschafft keinen.
        Vorher wird aber versucht, ihn aus dem Treiberspeicher zu holen: Viele
        Treiber liegen dort einsatzbereit, ohne installiert zu sein, darunter
        die von Windows mitgelieferten. Genau das ist die Lage nach einer
        Neuinstallation. Erst wenn auch das scheitert, wird der Drucker
        übersprungen und im Ergebnis benannt.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Printers)

    $applied = @()
    $failed = @()
    $missingDriver = @()
    $missingPort = @()

    $installed = @()
    try { $installed = @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }
    $existing = @()
    try { $existing = @(Get-Printer -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }

    foreach ($printer in $Printers) {
        if ($existing -contains $printer.name) {
            Write-WzLog (Get-WzText 'rest.logPrinterExists' @{ name = $printer.name }) -Level Info
            continue
        }
        $driverMissing = ($installed.Count -gt 0 -and $installed -notcontains $printer.treiber)

        if ($syncHash.DryRun) {
            $note = if ($driverMissing) { Get-WzText 'rest.noteDriverNeeded' } else { '' }
            Write-WzLog (Get-WzText 'rest.logPrinterTest' @{ name = $printer.name; anschluss = $printer.anschluss; zusatz = $note }) -Level Test
            continue
        }

        if ($driverMissing) {
            # Aus dem Treiberspeicher nachziehen, bevor aufgegeben wird
            try {
                Add-PrinterDriver -Name $printer.treiber -ErrorAction Stop
                $installed += $printer.treiber
                Write-WzLog (Get-WzText 'rest.logDriverInstalled' @{ name = $printer.treiber }) -Level Ok
            } catch {
                # Den Grund nennen statt nur »fehlt«: Ohne ihn weiß niemand, ob
                # der Treiber nachinstalliert werden muss oder der Name nicht stimmt.
                $reason = $_.Exception.Message.Split([char]10)[0].Trim()
                Write-WzLog (Get-WzText 'rest.logDriverUnavailable' @{ name = $printer.treiber; grund = $reason }) -Level Warn
                $missingDriver += Get-WzText 'rest.driverMissingItem' @{ name = $printer.name; treiber = $printer.treiber }
                continue
            }
        }

        $createdPort = $null
        try {
            # Netzwerkdrucker hängen an einem freigegebenen Pfad, lokale an einem
            # Anschluss — Add-Printer verlangt dafür verschiedene Parameter.
            if ($printer.netzwerk -and $printer.anschluss -like '\\*') {
                Add-Printer -ConnectionName $printer.anschluss -ErrorAction Stop
            } else {
                if (-not (Get-PrinterPort -Name $printer.anschluss -ErrorAction SilentlyContinue)) {
                    # Nur Netzwerkanschlüsse lassen sich anlegen. USB001,
                    # PORTPROMPT: oder DOT4_001 entstehen erst, wenn das Gerät
                    # angeschlossen wird beziehungsweise seine Software
                    # installiert ist — Add-PrinterPort scheitert dort mit einer
                    # nichtssagenden Meldung.
                    # Oktette bewusst auf 0-255 geprüft: »10.0.0.300« sieht aus
                    # wie eine Adresse, und Windows legte daraus sonst klaglos
                    # einen Anschluss auf einen Rechnernamen an, den es nicht gibt.
                    $octet = '(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
                    if ($printer.anschluss -match "^(?:IP_)?($octet(?:\.$octet){3})$") {
                        Add-PrinterPort -Name $printer.anschluss -PrinterHostAddress $Matches[1] -ErrorAction Stop
                        $createdPort = $printer.anschluss
                        Write-WzLog (Get-WzText 'rest.logPortCreated' @{ anschluss = $printer.anschluss }) -Level Ok
                    } else {
                        $missingPort += Get-WzText 'rest.portMissingItem' @{ name = $printer.name; anschluss = $printer.anschluss }
                        continue
                    }
                }
                Add-Printer -Name $printer.name -DriverName $printer.treiber `
                    -PortName $printer.anschluss -ErrorAction Stop
            }
            $applied += $printer.name
        } catch {
            $failed += $printer.name
            Write-WzLog (Get-WzText 'rest.logPrinterFailed' @{ name = $printer.name; grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
            # Den eben angelegten Anschluss wieder abräumen. Sonst bliebe nach
            # einem gescheiterten Versuch ein verwaister Eintrag zurück, den
            # später niemand mehr zuordnen kann. Der Spooler hält ihn direkt
            # nach dem Fehlschlag noch kurz fest — deshalb ein zweiter Versuch.
            if ($createdPort) {
                $removed = $false
                foreach ($attempt in 1, 2) {
                    try {
                        Remove-PrinterPort -Name $createdPort -ErrorAction Stop
                        $removed = $true
                        break
                    } catch {
                        if ($attempt -eq 1) { Start-Sleep -Seconds 2 }
                    }
                }
                if (-not $removed) {
                    Write-WzLog (Get-WzText 'rest.logPortLeftOver' @{ name = $createdPort }) -Level Warn
                }
            }
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog (Get-WzText 'rest.logPrintersDone' @{ anzahl = $applied.Count }) -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary (Get-WzText 'rest.actionPrinters' @{ anzahl = $applied.Count }) -Detail $applied
    }

    return [pscustomobject]@{
        Applied       = @($applied)
        Failed        = @($failed)
        MissingDriver = @($missingDriver)
        MissingPort   = @($missingPort)
    }
}

function Import-WzMappedDrives {
    <#
    .SYNOPSIS
        Verbindet gesicherte Netzlaufwerke wieder.
    .DESCRIPTION
        Ohne Anmeldedaten scheitert eine geschützte Freigabe. WinZii fragt
        bewusst keine Kennwörter ab — es meldet den Fehlschlag und überlässt die
        Anmeldung dem Explorer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Drives)

    $applied = @()
    $failed = @()

    foreach ($drive in $Drives) {
        $letter = ([string]$drive.buchstabe).TrimEnd(':')
        if (-not $letter -or -not $drive.ziel) { continue }

        if (Test-Path -LiteralPath "${letter}:") {
            Write-WzLog (Get-WzText 'rest.logDriveTaken' @{ buchstabe = $letter }) -Level Info
            continue
        }
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'rest.logDriveTest' @{ buchstabe = $letter; ziel = $drive.ziel }) -Level Test
            continue
        }

        try {
            New-SmbMapping -LocalPath "${letter}:" -RemotePath $drive.ziel -Persistent $true -ErrorAction Stop | Out-Null
            $applied += Get-WzText 'rest.driveEntry' @{ buchstabe = $letter; ziel = $drive.ziel }
        } catch {
            $failed += Get-WzText 'rest.driveEntry' @{ buchstabe = $letter; ziel = $drive.ziel }
            Write-WzLog (Get-WzText 'rest.logDriveFailed' @{ buchstabe = $letter; grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog (Get-WzText 'rest.logDrivesDone' @{ anzahl = $applied.Count }) -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary (Get-WzText 'rest.actionDrives' @{ anzahl = $applied.Count }) -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed) }
}

function Get-WzBookmarkTargets {
    <#
    .SYNOPSIS
        Ordnet gesicherte Lesezeichen-Dateien den hier vorhandenen
        Browser-Profilen zu.
    .DESCRIPTION
        Export-WzBrowserBookmarks legt sie als »<Browser>-<Profil>-<Datei>« ab.
        Aus diesem Namen lässt sich das Ziel zurückrechnen; ohne passenden
        Browser bleibt Target leer und die Zeile wird als nicht zurückspielbar
        gezeigt statt stillschweigend übergangen.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files)

    $browsers = @{}
    foreach ($browser in (Get-WzBrowserProfiles)) {
        $browsers[($browser.Name -replace '[^\w]', '-')] = $browser
    }

    $targets = @()
    foreach ($file in $Files) {
        $leaf = Split-Path -Leaf $file
        $entry = [pscustomobject]@{
            Source      = $file
            BrowserName = ''
            ProfileName = ''
            Target      = ''
            Reason      = ''
        }

        $match = @($browsers.Keys | Where-Object { $leaf -like "$_-*" } |
            Sort-Object -Property Length -Descending) | Select-Object -First 1
        if (-not $match) {
            $entry.Reason = Get-WzText 'rest.reasonNoBrowser'
            $targets += $entry
            continue
        }

        $browser = $browsers[$match]
        $entry.BrowserName = $browser.Name
        $rest = $leaf.Substring($match.Length + 1)

        # Der Dateiname am Ende steht je Browserart fest, dazwischen der Profilname
        $fileName = if ($browser.Kind -eq 'chromium') { 'Bookmarks' } else { 'places.sqlite' }
        if ($rest -notlike "*-$fileName") {
            $entry.Reason = Get-WzText 'rest.reasonWrongFile'
            $targets += $entry
            continue
        }
        $entry.ProfileName = $rest.Substring(0, $rest.Length - $fileName.Length - 1)

        $profileDir = Join-Path $browser.Path $entry.ProfileName
        if (-not (Test-Path -LiteralPath $profileDir)) {
            $entry.Reason = Get-WzText 'rest.reasonNoProfile' @{ name = $entry.ProfileName }
            $targets += $entry
            continue
        }

        $entry.Target = Join-Path $profileDir $fileName
        $targets += $entry
    }

    return @($targets)
}

function Import-WzBrowserBookmarks {
    <#
    .SYNOPSIS
        Spielt gesicherte Lesezeichen in die passenden Browser-Profile zurück.
    .DESCRIPTION
        Überschreibt die vorhandene Datei — deshalb wird sie vorher als
        ».winzii-vorher« zur Seite gelegt. Der Browser muss geschlossen sein,
        sonst schreibt er sie beim Beenden aus dem Speicher wieder zurück.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Targets)

    $applied = @()
    $failed = @()
    $blocked = @()

    foreach ($entry in $Targets) {
        if (-not $entry.Target) { continue }

        if (Get-WzBrowserProcess -BrowserName $entry.BrowserName) {
            $blocked += Get-WzText 'rest.blockedRunning' @{ name = $entry.BrowserName }
            continue
        }
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'rest.logMarksTest' @{ browser = $entry.BrowserName; profil = $entry.ProfileName }) -Level Test
            continue
        }

        try {
            if (Test-Path -LiteralPath $entry.Target) {
                Copy-Item -LiteralPath $entry.Target -Destination "$($entry.Target).winzii-vorher" `
                    -Force -ErrorAction Stop
            }
            Copy-Item -LiteralPath $entry.Source -Destination $entry.Target -Force -ErrorAction Stop
            $applied += "$($entry.BrowserName) / $($entry.ProfileName)"
        } catch {
            $failed += "$($entry.BrowserName) / $($entry.ProfileName)"
            Write-WzLog (Get-WzText 'rest.logMarksFailed' @{ browser = $entry.BrowserName; grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog (Get-WzText 'rest.logMarksDone' @{ anzahl = $applied.Count }) -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary (Get-WzText 'rest.actionMarks' @{ anzahl = $applied.Count }) -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed); Blocked = @($blocked) }
}

function Get-WzBrowserProcess {
    <#
    .SYNOPSIS
        Läuft der Browser gerade? Solange er läuft, ist ein Zurückspielen
        wirkungslos.
    #>
    param([Parameter(Mandatory = $true)][string]$BrowserName)

    $processes = @{
        'Microsoft Edge'  = 'msedge'
        'Google Chrome'   = 'chrome'
        'Brave'           = 'brave'
        'Mozilla Firefox' = 'firefox'
    }
    if (-not $processes.ContainsKey($BrowserName)) { return $null }
    return @(Get-Process -Name $processes[$BrowserName] -ErrorAction SilentlyContinue) | Select-Object -First 1
}
