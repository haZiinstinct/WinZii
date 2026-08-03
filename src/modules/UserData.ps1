# UserData — was muss vor einer Neuinstallation gesichert werden?
#
# Diese Seite fasst nur zusammen und exportiert Kleinkram (Lesezeichen,
# WLAN-Schlüssel, Wiederherstellungsschlüssel). Die eigentlichen Nutzdaten
# kopiert WinZii bewusst nicht — das Kopieren von einer möglicherweise
# sterbenden Platte ist ein eigenes Thema mit eigenen Fallstricken.

function Get-WzUserDataOverview {
    <#
    .SYNOPSIS
        Bestandsaufnahme: Profile, Ordnergrößen, OneDrive, Outlook, Browser,
        WLAN, Drucker, Netzlaufwerke.
    #>
    [CmdletBinding()]
    param()

    # Das Vermessen der Ordner dauert je nach Datenmenge zwanzig Sekunden und
    # mehr — die Zwischenmeldungen zeigen, dass es vorangeht.
    Write-WzLog 'Benutzerprofile werden vermessen...' -Level Info
    $profiles = Get-WzUserProfiles -IncludeSizes

    Write-WzLog 'OneDrive, Outlook und Browser werden geprüft...' -Level Info
    $oneDrive = Get-WzOneDriveState
    $outlook = Get-WzOutlookFiles
    $browsers = Get-WzBrowserProfiles

    return [pscustomobject]@{
        Profiles   = $profiles
        OneDrive   = $oneDrive
        Outlook    = $outlook
        Browsers   = $browsers
        Wlan       = Get-WzWlanProfiles
        Encrypted  = Get-WzEncryptedVolumes
        Keys       = Get-WzProductKeys
        Printers   = Get-WzPrinters
        NetDrives  = Get-WzMappedDrives
    }
}

function Get-WzUserProfiles {
    <#
    .SYNOPSIS
        Alle Benutzerprofile mit Größe der wichtigen Ordner.
    .NOTES
        Nutzt Measure-WzPathSet aus Cleanup.ps1 — dort bereits auf .NET
        umgestellt, weil Get-ChildItem -Recurse zu langsam ist.
    #>
    param([switch]$IncludeSizes)

    $profiles = @()
    $known = @(
        @{ Key = 'Desktop';   Name = 'Desktop' }
        @{ Key = 'Documents'; Name = 'Dokumente' }
        @{ Key = 'Pictures';  Name = 'Bilder' }
        @{ Key = 'Videos';    Name = 'Videos' }
        @{ Key = 'Music';     Name = 'Musik' }
        @{ Key = 'Downloads'; Name = 'Downloads' }
    )

    try {
        $entries = @(Get-CimInstance -Query 'SELECT LocalPath,SID,Special,LastUseTime FROM Win32_UserProfile' -ErrorAction Stop |
            Where-Object { -not $_.Special -and $_.LocalPath })
    } catch {
        Write-WzLog "Benutzerprofile nicht abfragbar: $($_.Exception.Message)" -Level Warn
        return @()
    }

    # Der Vergleichspunkt für »angemeldet«: bei Elevierung mit einem fremden
    # Konto das Profil des Anwenders am Bildschirm, nicht das des Technikers.
    $currentProfile = Get-WzUserFolder -Kind Profile

    foreach ($entry in $entries) {
        $path = $entry.LocalPath
        # Nur überspringen, wenn der Ordner wirklich fehlt (verwaister
        # Registry-Eintrag). »Zugriff verweigert« sieht für Test-Path genauso
        # aus — solche Profile gehören aber in die Liste, sonst fehlt auf der
        # Sicherungs-Checkliste ein ganzer Benutzer.
        if (-not (Test-WzDirectoryPresent $path)) { continue }

        $name = Split-Path -Leaf $path
        $account = $name
        try {
            $sid = New-Object Security.Principal.SecurityIdentifier($entry.SID)
            $account = $sid.Translate([Security.Principal.NTAccount]).Value
        } catch { }

        $folders = @()
        $total = [int64]0
        $accessible = $false

        if ($IncludeSizes) {
            # Bei großen Profilen dauert das Vermessen — die Zeile zeigt, dass
            # es vorangeht und welches Konto gerade dran ist
            Write-WzLog "Vermesse Profil $account..." -Level Info
            foreach ($folder in $known) {
                $folderPath = Join-Path $path $folder.Key
                if (-not (Test-Path -LiteralPath $folderPath -ErrorAction SilentlyContinue)) { continue }
                $accessible = $true
                $measure = Measure-WzPathSet -Paths @($folderPath)
                if ($measure.Items -eq 0 -and $measure.Bytes -eq 0) { continue }
                $folders += [pscustomobject]@{
                    Name  = $folder.Name
                    Path  = $folderPath
                    Bytes = $measure.Bytes
                    Items = $measure.Items
                }
                $total += $measure.Bytes
            }
        }

        $profiles += [pscustomobject]@{
            Name        = $name
            Account     = $account
            Path        = $path
            LastUse     = $entry.LastUseTime
            Folders     = $folders
            TotalBytes  = $total
            Accessible  = $accessible
            IsCurrent   = ($path -eq $currentProfile)
        }
    }

    return @($profiles | Sort-Object -Property @{ Expression = 'IsCurrent'; Descending = $true }, Name)
}

function Test-WzDirectoryPresent {
    <#
    .SYNOPSIS
        Gibt es diesen Ordner — auch dann richtig beantwortet, wenn der Zugriff
        verweigert wird?
    .NOTES
        Test-Path liefert bei »Zugriff verweigert« dasselbe $false wie bei
        »fehlt«. Das Elternverzeichnis (C:\Users) ist mit Administratorrechten
        aber lesbar — dort lässt sich nachsehen, ob der Ordner existiert.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) { return $true }

    # GetAttributes unterscheidet die beiden Fälle sauber: bei »fehlt« kommt
    # eine (File|Directory)NotFoundException, bei »Zugriff verweigert« eine
    # UnauthorizedAccessException — und Letztere beweist gerade, dass es den
    # Ordner gibt.
    try {
        [void][IO.File]::GetAttributes($Path)
        return $true
    } catch [UnauthorizedAccessException] {
        return $true
    } catch { }

    # Letzte Instanz: im Elternverzeichnis nachsehen
    try {
        $parent = Split-Path -Parent $Path
        $leaf = Split-Path -Leaf $Path
        if (-not $parent -or -not $leaf) { return $false }
        foreach ($directory in [IO.Directory]::EnumerateDirectories($parent)) {
            if ([IO.Path]::GetFileName($directory) -ieq $leaf) { return $true }
        }
    } catch { }
    return $false
}

function Get-WzOneDriveState {
    <#
    .SYNOPSIS
        Ist OneDrive eingerichtet, und wie viel liegt wirklich auf der Platte?
    .DESCRIPTION
        Die entscheidende Frage vor jeder Datensicherung. Bei »Dateien bei
        Bedarf« zeigt der Explorer die volle Größe, auf der Platte liegen aber
        nur Platzhalter. Wer die kopiert, sichert leere Hüllen.
        Erkannt wird das am Dateiattribut Offline beziehungsweise am
        Windows-eigenen RECALL_ON_DATA_ACCESS (0x00400000).
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{
        Configured    = $false
        Folders       = @()
        PlaceholderWarning = ''
    }

    $accounts = @()
    try {
        # HKCU über Resolve-WzRegistryPath: bei Elevierung mit einem fremden
        # Konto zeigt HKCU sonst auf den Techniker — und die Seite meldete
        # »OneDrive nicht eingerichtet«, obwohl der Kunde eines hat.
        $accountsKey = Resolve-WzRegistryPath 'HKCU:\Software\Microsoft\OneDrive\Accounts'
        $accounts = @(Get-ItemProperty "$accountsKey\*" -ErrorAction Stop |
            Where-Object { $_.UserFolder })
    } catch { }

    if ($accounts.Count -eq 0) {
        return $result
    }
    $result.Configured = $true

    $recallOnDataAccess = 0x00400000
    $folders = @()
    $anyPlaceholder = $false

    $anyIncomplete = $false

    foreach ($account in $accounts) {
        $path = $account.UserFolder
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $localBytes = [int64]0
        $cloudOnly = 0
        $localFiles = 0
        $incomplete = $false
        # Zeitbudget: Bei sechsstelligen Dateizahlen dauert die Zählung Minuten
        # und sieht aus wie ein Absturz. Lieber ehrlich abbrechen und das sagen.
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            foreach ($file in [IO.Directory]::EnumerateFiles($path, '*', [IO.SearchOption]::AllDirectories)) {
                try {
                    $info = New-Object IO.FileInfo($file)
                    $attributes = [int]$info.Attributes
                    if (($attributes -band [int][IO.FileAttributes]::Offline) -ne 0 -or
                        ($attributes -band $recallOnDataAccess) -ne 0) {
                        $cloudOnly++
                    } else {
                        $localBytes += $info.Length
                        $localFiles++
                    }
                } catch { }

                $count = $localFiles + $cloudOnly
                if (($count % 20000) -eq 0 -and $count -gt 0) {
                    Write-WzLog "OneDrive: $count Datei(en) geprüft..." -Level Info
                }
                if ($watch.Elapsed.TotalSeconds -gt 45) {
                    $incomplete = $true
                    $anyIncomplete = $true
                    Write-WzLog "OneDrive-Ordner sehr groß — Zählung nach 45 s abgebrochen ($count Datei(en) geprüft)." -Level Warn
                    break
                }
            }
        } catch { }

        if ($cloudOnly -gt 0) { $anyPlaceholder = $true }

        $folders += [pscustomobject]@{
            Path       = $path
            Account    = $(if ($account.UserEmail) { $account.UserEmail } else { 'unbekannt' })
            LocalBytes = $localBytes
            LocalFiles = $localFiles
            CloudOnly  = $cloudOnly
            Incomplete = $incomplete
        }
    }

    $result.Folders = @($folders)
    if ($anyIncomplete) {
        # Eine halbe Zählung darf nicht beruhigend klingen — die eigentliche
        # Empfehlung gilt dann erst recht.
        $result.PlaceholderWarning = 'Der OneDrive-Ordner ist so groß, dass die Prüfung abgebrochen wurde — die Zahlen sind unvollständig. ' +
            'Vor dem Kopieren in OneDrive »Immer auf diesem Gerät behalten« wählen und das Herunterladen abwarten.'
    } elseif ($anyPlaceholder) {
        $total = ($folders | Measure-Object -Property CloudOnly -Sum).Sum
        $result.PlaceholderWarning = "Achtung: $total Datei(en) liegen nur in der Cloud und nicht auf dieser Platte. " +
            'Wer den OneDrive-Ordner einfach kopiert, sichert leere Platzhalter. Vorher in OneDrive ' +
            '»Immer auf diesem Gerät behalten« wählen und das Herunterladen abwarten.'
    }

    return $result
}

function Get-WzOutlookFiles {
    <#
    .SYNOPSIS
        Outlook-Datendateien. PST enthält die einzigen Kopien lokaler Ordner,
        OST ist nur ein Zwischenspeicher des Postfachs.
    #>
    $files = @()
    # Über Get-WzUserFolder statt $env: — sonst wird bei Elevierung mit einem
    # fremden Konto im Profil des Technikers gesucht.
    $localAppData = Get-WzUserFolder -Kind LocalAppData
    $userProfile = Get-WzUserFolder -Kind Profile
    $roots = @(
        (Join-Path $localAppData 'Microsoft\Outlook')
        (Join-Path $userProfile 'Documents\Outlook-Dateien')
        (Join-Path $userProfile 'Documents\Outlook Files')
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            foreach ($file in (Get-ChildItem -LiteralPath $root -Include '*.pst', '*.ost' -File -Recurse -ErrorAction SilentlyContinue)) {
                $files += [pscustomobject]@{
                    Name     = $file.Name
                    Path     = $file.FullName
                    Bytes    = $file.Length
                    Kind     = if ($file.Extension -eq '.pst') { 'PST — enthält eigene Daten, unbedingt sichern' }
                               else { 'OST — nur Zwischenspeicher, wird neu aufgebaut' }
                    Modified = $file.LastWriteTime
                }
            }
        } catch { }
    }

    return @($files | Sort-Object Bytes -Descending)
}

function Get-WzBrowserProfiles {
    <#
    .SYNOPSIS
        Gefundene Browser-Profile mit Größe.
    #>
    $localAppData = Get-WzUserFolder -Kind LocalAppData
    $roamingAppData = Get-WzUserFolder -Kind RoamingAppData
    $browsers = @(
        @{ Name = 'Microsoft Edge'; Path = (Join-Path $localAppData 'Microsoft\Edge\User Data'); Kind = 'chromium' }
        @{ Name = 'Google Chrome';  Path = (Join-Path $localAppData 'Google\Chrome\User Data'); Kind = 'chromium' }
        @{ Name = 'Brave';          Path = (Join-Path $localAppData 'BraveSoftware\Brave-Browser\User Data'); Kind = 'chromium' }
        @{ Name = 'Mozilla Firefox'; Path = (Join-Path $roamingAppData 'Mozilla\Firefox\Profiles'); Kind = 'firefox' }
    )

    $found = @()
    foreach ($browser in $browsers) {
        if (-not (Test-Path -LiteralPath $browser.Path)) { continue }

        $bookmarks = @()
        if ($browser.Kind -eq 'chromium') {
            $bookmarks = @(Get-ChildItem -LiteralPath $browser.Path -Filter 'Bookmarks' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)
        } else {
            $bookmarks = @(Get-ChildItem -LiteralPath $browser.Path -Filter 'places.sqlite' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)
        }

        $measure = Measure-WzPathSet -Paths @($browser.Path)
        $found += [pscustomobject]@{
            Name          = $browser.Name
            Path          = $browser.Path
            Kind          = $browser.Kind
            Bytes         = $measure.Bytes
            BookmarkFiles = @($bookmarks | ForEach-Object { $_.FullName })
        }
    }

    return @($found)
}

function Get-WzWlanProfiles {
    <#
    .SYNOPSIS
        Namen der gespeicherten WLAN-Netze.
    #>
    $profiles = @()
    $result = Invoke-WzProcess -FilePath 'netsh.exe' -Arguments 'wlan show profiles' -TimeoutSeconds 30
    if ($result.ExitCode -ne 0) { return @() }

    foreach ($line in ($result.StdOut -split "`r?`n")) {
        # Deutsch: "Alle Benutzerprofile : Name" · Englisch: "All User Profile : Name"
        if ($line -match '^\s*(?:Alle Benutzerprofile|All User Profile)\s*:\s*(.+)$') {
            $name = $Matches[1].Trim()
            if ($name) { $profiles += $name }
        }
    }
    return @($profiles)
}

function Export-WzWlanProfiles {
    <#
    .SYNOPSIS
        Sichert die WLAN-Netze samt Schlüssel auf den Datenträger.
    .DESCRIPTION
        Die Schlüssel stehen dabei im Klartext in den XML-Dateien. Das ist
        gewollt — ohne sie kommt der PC nach dem Neuaufsetzen nicht ins Netz.
        Der Aufrufer muss das ausdrücklich bestätigen.
    #>
    [CmdletBinding()]
    param([switch]$IncludeKeys)

    $target = New-WzDirectory (Join-Path (Get-WzUserDataDir) 'wlan')

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] WLAN-Netze würden nach $target gesichert" -Level Test
        return [pscustomobject]@{ Count = 0; Path = $target }
    }

    $arguments = "wlan export profile folder=`"$target`""
    if ($IncludeKeys) { $arguments += ' key=clear' }

    $result = Invoke-WzProcess -FilePath 'netsh.exe' -Arguments $arguments -TimeoutSeconds 60
    $files = @(Get-ChildItem -LiteralPath $target -Filter '*.xml' -File -ErrorAction SilentlyContinue)

    if ($files.Count -gt 0) {
        $note = if ($IncludeKeys) { ' samt Schlüsseln — bitte vertraulich behandeln' } else { ' ohne Schlüssel' }
        Write-WzLog "$($files.Count) WLAN-Netz(e) gesichert$note" -Level Ok
    } else {
        Write-WzLog "Keine WLAN-Netze gesichert (Code $($result.ExitCode))" -Level Warn
    }

    return [pscustomobject]@{ Count = $files.Count; Path = $target }
}

function Get-WzProductKeys {
    <#
    .SYNOPSIS
        Windows-Schlüssel aus der Firmware und der aktive Installationsschlüssel.
    .DESCRIPTION
        Der Firmware-Schlüssel (OA3) steckt bei vorinstallierten Rechnern im
        UEFI und ist der, den man nach einer Neuinstallation braucht.
    #>
    $result = [pscustomobject]@{
        FirmwareKey = ''
        Edition     = ''
        Channel     = ''
        PartialKey  = ''
        Office      = @()
    }

    try {
        $service = Get-CimInstance -Query 'SELECT OA3xOriginalProductKey FROM SoftwareLicensingService' -ErrorAction Stop
        if ($service.OA3xOriginalProductKey) { $result.FirmwareKey = $service.OA3xOriginalProductKey }
    } catch { }

    try {
        $query = "SELECT LicenseStatus,ProductKeyChannel,PartialProductKey,Name FROM SoftwareLicensingProduct " +
                 "WHERE PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'"
        $product = Get-CimInstance -Query $query -ErrorAction Stop | Select-Object -First 1
        if ($product) {
            $result.Channel = $product.ProductKeyChannel
            $result.PartialKey = $product.PartialProductKey
            $result.Edition = $product.Name
        }
    } catch { }

    try {
        $officeQuery = "SELECT Name,PartialProductKey,ProductKeyChannel FROM SoftwareLicensingProduct " +
                       "WHERE PartialProductKey IS NOT NULL AND ApplicationID='0ff1ce15-a989-479d-af46-f275c6370663'"
        $result.Office = @(Get-CimInstance -Query $officeQuery -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Name       = $_.Name
                PartialKey = $_.PartialProductKey
                Channel    = $_.ProductKeyChannel
            }
        })
    } catch { }

    return $result
}

function Get-WzEncryptedVolumes {
    <#
    .SYNOPSIS
        Laufwerke mit eingeschalteter BitLocker-Verschlüsselung.
    .NOTES
        Bewusst getrennt von Get-WzBitLockerKeys: Für die Anzeige reicht die
        Anzahl. Die Schlüssel selbst werden erst im Moment des Exports geholt
        und danach nicht weiter herumgereicht.
    #>
    try {
        return @(Get-CimInstance -Namespace 'root\cimv2\security\microsoftvolumeencryption' `
                -ClassName Win32_EncryptableVolume -ErrorAction Stop |
            Where-Object { $_.ProtectionStatus -eq 1 } |
            ForEach-Object { $_.DriveLetter })
    } catch { return @() }
}

function Get-WzBitLockerKeys {
    <#
    .SYNOPSIS
        Wiederherstellungsschlüssel aller verschlüsselten Laufwerke.
    .DESCRIPTION
        Ohne diesen Schlüssel ist ein verschlüsseltes Laufwerk nach einem
        Mainboardtausch oder BIOS-Update unwiederbringlich zu. WinZii hat den
        Zustand bisher nur angezeigt, aber nie gesichert.
    #>
    $keys = @()
    try {
        $volumes = Get-CimInstance -Namespace 'root\cimv2\security\microsoftvolumeencryption' `
            -ClassName Win32_EncryptableVolume -ErrorAction Stop

        foreach ($volume in $volumes) {
            if ($volume.ProtectionStatus -ne 1) { continue }

            $protectors = $volume | Invoke-CimMethod -MethodName GetKeyProtectors -Arguments @{ KeyProtectorType = 3 } -ErrorAction SilentlyContinue
            foreach ($id in $protectors.VolumeKeyProtectorID) {
                $password = $volume | Invoke-CimMethod -MethodName GetKeyProtectorNumericalPassword `
                    -Arguments @{ VolumeKeyProtectorID = $id } -ErrorAction SilentlyContinue
                if ($password.NumericalPassword) {
                    $keys += [pscustomobject]@{
                        Drive       = $volume.DriveLetter
                        ProtectorId = $id
                        Key         = $password.NumericalPassword
                    }
                }
            }
        }
    } catch {
        Write-WzLog "BitLocker-Schlüssel nicht abfragbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
    }
    return @($keys)
}

function Save-WzBitLockerKeys {
    <#
    .SYNOPSIS
        Schreibt die Wiederherstellungsschlüssel in den Sicherungsordner.
    #>
    param([Parameter(Mandatory = $true)]$Keys)

    if ($Keys.Count -eq 0) { return $null }
    if ($syncHash.DryRun) {
        Write-WzLog '[Test] BitLocker-Schlüssel würden gesichert' -Level Test
        return $null
    }

    $target = Join-Path (Get-WzBackupDir -Stamp "$(Get-Date -Format 'yyyy-MM-dd_HHmmss')-bitlocker") 'bitlocker-schluessel.txt'
    $lines = @(
        'BitLocker-Wiederherstellungsschlüssel'
        "Computer: $env:COMPUTERNAME"
        "Gesichert am: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        ''
        'Diese Schlüssel öffnen die verschlüsselten Laufwerke dieses PCs.'
        'Bitte sicher aufbewahren und nicht offen herumliegen lassen.'
        ''
    )
    foreach ($key in $Keys) {
        $lines += "Laufwerk $($key.Drive)"
        $lines += "  $($key.Key)"
        $lines += ''
    }

    [IO.File]::WriteAllText($target, ($lines -join [Environment]::NewLine), [Text.Encoding]::UTF8)
    Write-WzLog "BitLocker-Schlüssel gesichert: $target" -Level Ok
    return $target
}

function Get-WzPrinters {
    <#
    .SYNOPSIS
        Eingerichtete Drucker zum Wiederherstellen nach der Neuinstallation.
    #>
    try {
        return @(Get-CimInstance -Query 'SELECT Name,DriverName,PortName,Default,Network FROM Win32_Printer' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    Name      = $_.Name
                    Driver    = $_.DriverName
                    Port      = $_.PortName
                    IsDefault = [bool]$_.Default
                    IsNetwork = [bool]$_.Network
                }
            })
    } catch { return @() }
}

function Get-WzMappedDrives {
    <#
    .SYNOPSIS
        Verbundene Netzlaufwerke.
    #>
    try {
        return @(Get-CimInstance -Query 'SELECT Name,ProviderName FROM Win32_LogicalDisk WHERE DriveType=4' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{ Letter = $_.Name; Target = $_.ProviderName }
            })
    } catch { return @() }
}

function Get-WzUserDataDir {
    <#
    .SYNOPSIS
        Ablageort der Exporte auf dem Datenträger.
    #>
    New-WzDirectory (Get-WzPath 'offline' 'daten' $env:COMPUTERNAME)
}

function Export-WzDeviceList {
    <#
    .SYNOPSIS
        Schreibt Drucker und Netzlaufwerke als geraete.json auf den Datenträger.
    .DESCRIPTION
        Bisher wurden beide nur angezeigt. Nach dem Neuaufsetzen ist die Liste
        aber genau das, was fehlt — ohne sie muss der Techniker aus dem
        Gedächtnis rekonstruieren, welcher Drucker an welchem Anschluss hing.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Printers,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$NetDrives
    )

    $target = Get-WzUserDataDir
    $file = Join-Path $target 'geraete.json'

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] $($Printers.Count) Drucker und $($NetDrives.Count) Netzlaufwerk(e) würden nach $file geschrieben" -Level Test
        return [pscustomobject]@{ Count = 0; Path = $file }
    }

    $payload = [pscustomobject]@{
        computer  = $env:COMPUTERNAME
        erstellt  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        drucker   = @($Printers | ForEach-Object {
            [pscustomobject]@{
                name      = $_.Name
                treiber   = $_.Driver
                anschluss = $_.Port
                standard  = [bool]$_.IsDefault
                netzwerk  = [bool]$_.IsNetwork
            }
        })
        laufwerke = @($NetDrives | ForEach-Object {
            [pscustomobject]@{ buchstabe = $_.Letter; ziel = $_.Target }
        })
    }

    try {
        [void](Save-WzJson -InputObject $payload -Path $file)
    } catch {
        Write-WzLog "Geräteliste nicht speicherbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
        return [pscustomobject]@{ Count = 0; Path = $file }
    }

    $count = $Printers.Count + $NetDrives.Count
    Write-WzLog "$($Printers.Count) Drucker und $($NetDrives.Count) Netzlaufwerk(e) gesichert nach $file" -Level Ok
    return [pscustomobject]@{ Count = $count; Path = $file }
}

function Export-WzBrowserBookmarks {
    <#
    .SYNOPSIS
        Kopiert die Lesezeichen-Dateien der gefundenen Browser.
    #>
    param([Parameter(Mandatory = $true)]$Browsers)

    $target = New-WzDirectory (Join-Path (Get-WzUserDataDir) 'lesezeichen')
    $count = 0

    foreach ($browser in $Browsers) {
        foreach ($file in $browser.BookmarkFiles) {
            if ($syncHash.DryRun) {
                Write-WzLog "[Test] $($browser.Name): $(Split-Path -Leaf $file) würde gesichert" -Level Test
                continue
            }
            try {
                $profileName = Split-Path -Leaf (Split-Path -Parent $file)
                $safeName = ($browser.Name -replace '[^\w]', '-') + "-$profileName-" + (Split-Path -Leaf $file)
                Copy-Item -LiteralPath $file -Destination (Join-Path $target $safeName) -Force -ErrorAction Stop
                $count++
            } catch {
                Write-WzLog "Lesezeichen von $($browser.Name) nicht kopierbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
            }
        }
    }

    if ($count -gt 0) { Write-WzLog "$count Lesezeichen-Datei(en) gesichert nach $target" -Level Ok }
    return [pscustomobject]@{ Count = $count; Path = $target }
}
