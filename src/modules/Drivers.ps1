# Drivers — Geräte mit Problemen finden, Treiber sichern und zurückspielen.
#
# Vor einer Neuinstallation ist die Treibersicherung die halbe Miete, gerade
# bei Notebooks mit Sonderhardware, für die es keine Downloads mehr gibt.

function Get-WzDeviceClassName {
    <#
    .SYNOPSIS
        Übersetzt die Geräteklasse aus WMI in den Namen, den der Geräte-Manager
        anzeigt.
    .NOTES
        Win32_PnPSignedDriver liefert sie in Großbuchstaben und auf Englisch
        (»HIDCLASS«, »MEDIA«). So gedruckt sieht die Treiberliste aus wie eine
        Registry-Ausgabe. Unbekanntes wird durchgereicht statt geraten — lieber
        ein englischer Klassenname als ein falscher deutscher.
    #>
    param([string]$Class)

    if (-not $Class) { return '' }

    $names = @{
        'display'          = (Get-WzText 'drv.classDisplay')
        'net'              = (Get-WzText 'drv.classNet')
        'media'            = (Get-WzText 'drv.classAudio')
        'audioendpoint'    = (Get-WzText 'drv.classAudio')
        'hidclass'         = (Get-WzText 'drv.classInput')
        'mouse'            = (Get-WzText 'drv.classMouse')
        'keyboard'         = (Get-WzText 'drv.classKeyboard')
        'usb'              = (Get-WzText 'drv.classUsb')
        'system'           = (Get-WzText 'drv.classSystem')
        'printer'          = (Get-WzText 'drv.classPrinter')
        'diskdrive'        = (Get-WzText 'drv.classDisk')
        'scsiadapter'      = (Get-WzText 'drv.classStorageController')
        'hdc'              = (Get-WzText 'drv.classStorageController')
        'bluetooth'        = (Get-WzText 'drv.classBluetooth')
        'image'            = (Get-WzText 'drv.classImaging')
        'monitor'          = (Get-WzText 'drv.classMonitor')
        'firmware'         = (Get-WzText 'drv.classFirmware')
        'securitydevices'  = (Get-WzText 'drv.classSecurity')
        'battery'          = (Get-WzText 'drv.classBattery')
        'ports'            = (Get-WzText 'drv.classPorts')
        'smartcardreader'  = (Get-WzText 'drv.classCardReader')
        'camera'           = (Get-WzText 'drv.classCamera')
        'volume'           = (Get-WzText 'drv.classVolume')
        'computer'         = (Get-WzText 'drv.classComputer')
        'processor'        = (Get-WzText 'drv.classProcessor')
        'sensor'           = (Get-WzText 'drv.classSensor')
        'softwarecomponent' = (Get-WzText 'drv.classVendorSoftware')
        'softwaredevice'   = (Get-WzText 'drv.classSoftwareDevice')
    }

    $key = $Class.ToLowerInvariant()
    if ($names.ContainsKey($key)) { return $names[$key] }
    return $Class
}

function Get-WzProblemDevices {
    <#
    .SYNOPSIS
        Geräte, die Windows nicht sauber betreiben kann — mit Klartext zum
        Fehlercode statt nur der Nummer.
    #>
    [CmdletBinding()]
    param()

    # Die Fehlercodes des Geräte-Managers, die im Alltag wirklich vorkommen
    $meanings = @{
        1  = @{ Text = (Get-WzText 'drv.err1Text'); Fix = (Get-WzText 'drv.err1Fix') }
        3  = @{ Text = (Get-WzText 'drv.err3Text'); Fix = (Get-WzText 'drv.err3Fix') }
        10 = @{ Text = (Get-WzText 'drv.err10Text'); Fix = (Get-WzText 'drv.err10Fix') }
        12 = @{ Text = (Get-WzText 'drv.err12Text'); Fix = (Get-WzText 'drv.err12Fix') }
        14 = @{ Text = (Get-WzText 'drv.err14Text'); Fix = (Get-WzText 'drv.err14Fix') }
        18 = @{ Text = (Get-WzText 'drv.err18Text'); Fix = (Get-WzText 'drv.err18Fix') }
        19 = @{ Text = (Get-WzText 'drv.err19Text'); Fix = (Get-WzText 'drv.err19Fix') }
        22 = @{ Text = (Get-WzText 'drv.err22Text'); Fix = (Get-WzText 'drv.err22Fix') }
        28 = @{ Text = (Get-WzText 'drv.err28Text'); Fix = (Get-WzText 'drv.err28Fix') }
        31 = @{ Text = (Get-WzText 'drv.err31Text'); Fix = (Get-WzText 'drv.err31Fix') }
        37 = @{ Text = (Get-WzText 'drv.err37Text'); Fix = (Get-WzText 'drv.err37Fix') }
        39 = @{ Text = (Get-WzText 'drv.err39Text'); Fix = (Get-WzText 'drv.err39Fix') }
        43 = @{ Text = (Get-WzText 'drv.err43Text'); Fix = (Get-WzText 'drv.err43Fix') }
        45 = @{ Text = (Get-WzText 'drv.err45Text'); Fix = (Get-WzText 'drv.err45Fix') }
        52 = @{ Text = (Get-WzText 'drv.err52Text'); Fix = (Get-WzText 'drv.err52Fix') }
    }

    $devices = @()
    try {
        $all = @(Get-CimInstance -Query 'SELECT Name,DeviceID,ConfigManagerErrorCode,PNPClass,Manufacturer,Status FROM Win32_PnPEntity' -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })

        foreach ($device in $all) {
            $code = [int]$device.ConfigManagerErrorCode
            $info = $meanings[$code]
            $devices += [pscustomobject]@{
                Name         = if ($device.Name) { $device.Name } else { Get-WzText 'drv.unknownDevice' }
                Class        = if ($device.PNPClass) { Get-WzDeviceClassName $device.PNPClass } else { Get-WzText 'drv.noCategory' }
                Manufacturer = $device.Manufacturer
                Code         = $code
                Meaning      = if ($info) { $info.Text } else { Get-WzText 'drv.errCodeGeneric' @{ code = $code } }
                Fix          = if ($info) { $info.Fix } else { Get-WzText 'drv.fixGeneric' }
                DeviceId     = $device.DeviceID
                # Code 45 heißt nur "gerade nicht angesteckt" und ist harmlos
                IsCritical   = ($code -ne 45)
            }
        }
    } catch {
        Write-WzLog (Get-WzText 'drv.logDevicesUnreadable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return @($devices | Sort-Object -Property @{ Expression = 'IsCritical'; Descending = $true }, Name)
}

function Get-WzDriverInventory {
    <#
    .SYNOPSIS
        Installierte Treiber. Standardmäßig nur Fremdhersteller.
    .DESCRIPTION
        Auf einem üblichen PC sind rund 230 Treiber installiert, davon über 180
        von Microsoft und meist Jahre alt — das ist völlig normal. Eine Warnung
        nach Alter allein wäre reines Rauschen, deshalb liegt der Blick auf den
        rund 50 Treibern der Gerätehersteller.
    #>
    param([switch]$IncludeMicrosoft)

    $drivers = @()
    try {
        $all = @(Get-CimInstance -Query 'SELECT DeviceName,DriverVersion,DriverDate,Manufacturer,DriverProviderName,DeviceClass,InfName FROM Win32_PnPSignedDriver' -ErrorAction Stop)

        foreach ($driver in $all) {
            $provider = if ($driver.DriverProviderName) { $driver.DriverProviderName } else { $driver.Manufacturer }
            $isMicrosoft = ($provider -match '^(Microsoft|Standard|\(Standard)')
            if ($isMicrosoft -and -not $IncludeMicrosoft) { continue }
            if (-not $driver.DeviceName) { continue }

            $date = $null
            try { if ($driver.DriverDate) { $date = [Management.ManagementDateTimeConverter]::ToDateTime($driver.DriverDate) } } catch { }
            if (-not $date -and $driver.DriverDate -is [datetime]) { $date = $driver.DriverDate }

            $ageYears = if ($date) { [math]::Round(((Get-Date) - $date).TotalDays / 365.25, 1) } else { $null }

            $drivers += [pscustomobject]@{
                Device      = $driver.DeviceName
                Provider    = $provider
                Version     = $driver.DriverVersion
                Date        = $date
                AgeYears    = $ageYears
                Class       = Get-WzDeviceClassName $driver.DeviceClass
                InfName     = $driver.InfName
                IsMicrosoft = $isMicrosoft
            }
        }
    } catch {
        Write-WzLog (Get-WzText 'drv.logDriversUnreadable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return @($drivers | Sort-Object -Property @{ Expression = { $_.Date }; Ascending = $true })
}

function Get-WzDriverStoreSize {
    <#
    .SYNOPSIS
        Wie viel Platz eine Treibersicherung braucht — einmal für alles,
        einmal nur für die Treiber der Gerätehersteller.
    .NOTES
        Die Fremdtreiber lassen sich nicht am Ordnernamen erkennen: Windows
        legt eigene und fremde Pakete nebeneinander im selben Speicher ab.
        Get-WindowsDriver -Online nennt genau die Pakete, die auch
        Export-WindowsDriver sichern würde, und liefert ihren Ordner gleich mit.
        Ohne Administratorrechte gibt es diese Auskunft nicht — dann bleibt
        ThirdPartyKnown falsch, statt eine Zahl zu erfinden.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{
        TotalBytes         = [int64]0
        TotalPackages      = 0
        ThirdPartyBytes    = [int64]0
        ThirdPartyPackages = 0
        ThirdPartyKnown    = $false
    }

    $store = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
    if (-not (Test-Path -LiteralPath $store)) { return $result }

    try {
        foreach ($folder in [IO.Directory]::EnumerateDirectories($store)) {
            $result.TotalPackages++
            $result.TotalBytes += Get-WzFolderBytes -Path $folder
        }
    } catch { }

    try {
        $folders = @(Get-WindowsDriver -Online -ErrorAction Stop |
            ForEach-Object { Split-Path -Parent $_.OriginalFileName } |
            Sort-Object -Unique)
        $result.ThirdPartyPackages = $folders.Count
        foreach ($folder in $folders) {
            if (Test-Path -LiteralPath $folder) { $result.ThirdPartyBytes += Get-WzFolderBytes -Path $folder }
        }
        $result.ThirdPartyKnown = $true
    } catch { }

    return $result
}

function Get-WzFolderBytes {
    <#
    .SYNOPSIS
        Summiert die Dateigrößen unterhalb eines Ordners.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [int64]0
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            try { $bytes += (New-Object IO.FileInfo($file)).Length } catch { }
        }
    } catch { }
    return $bytes
}

function Export-WzDrivers {
    <#
    .SYNOPSIS
        Sichert die Treiber auf den Datenträger.
    .PARAMETER ThirdPartyOnly
        Nur Treiber der Gerätehersteller. Die Windows-eigenen bringt jede
        Neuinstallation ohnehin mit.
    #>
    [CmdletBinding()]
    param([switch]$ThirdPartyOnly)

    # »treiber« ist der Ordnername auf dem Datentraeger, keine Anzeige — er
    # bleibt fest, sonst finden aeltere Sticks ihre Sicherungen nicht mehr.
    $target = New-WzDirectory (Get-WzPath 'offline' 'treiber' $env:COMPUTERNAME)
    $result = [pscustomobject]@{ Success = $false; Path = $target; Packages = 0; Bytes = 0 }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'drv.logExportTest' @{ ziel = $target }) -Level Test
        $result.Success = $true
        return $result
    }

    Write-WzLog (Get-WzText 'drv.logExportRunning') -Level Action

    if ($ThirdPartyOnly) {
        # Export-WindowsDriver liefert genau die Fremdtreiber
        try {
            $exported = @(Export-WindowsDriver -Online -Destination $target -ErrorAction Stop)
            $result.Packages = $exported.Count
            $result.Success = ($exported.Count -gt 0)
        } catch {
            Write-WzLog (Get-WzText 'drv.logExportFailedReason' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Error
            return $result
        }
    } else {
        $process = Invoke-WzProcess -FilePath 'pnputil.exe' `
            -Arguments "/export-driver * `"$target`"" -TimeoutSeconds 1800
        if ($process.ExitCode -ne 0) {
            Write-WzLog (Get-WzText 'drv.logExportCode' @{ code = $process.ExitCode }) -Level Warn
        }
        $result.Packages = @(Get-ChildItem -LiteralPath $target -Directory -ErrorAction SilentlyContinue).Count
        $result.Success = ($result.Packages -gt 0)
    }

    $bytes = (Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $result.Bytes = [int64]$bytes

    if ($result.Success) {
        Write-WzLog (Get-WzText 'drv.logExportOk' @{ anzahl = $result.Packages; groesse = (Format-WzBytes $result.Bytes); ziel = $target }) -Level Ok
    }
    return $result
}

function Import-WzDrivers {
    <#
    .SYNOPSIS
        Spielt eine Treibersicherung wieder ein.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = [pscustomobject]@{ Success = $false; Summary = '' }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Summary = Get-WzText 'drv.summaryNoFolder' @{ pfad = $Path }
        return $result
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'drv.logImportTest' @{ pfad = $Path }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    Write-WzLog (Get-WzText 'drv.logImportRunning') -Level Action
    $process = Invoke-WzProcess -FilePath 'pnputil.exe' `
        -Arguments "/add-driver `"$Path\*.inf`" /subdirs /install" -TimeoutSeconds 1800 -LogOutput

    # pnputil meldet auch dann Erfolg, wenn einzelne Pakete übersprungen wurden
    $added = 0
    if ($process.StdOut -match '(?m)^\s*(?:Hinzugefügte Treiberpakete|Total driver packages added)\s*:\s*(\d+)') {
        $added = [int]$Matches[1]
    }

    $result.Success = ($process.ExitCode -eq 0)
    $result.Summary = if ($result.Success) {
        if ($added -gt 0) { Get-WzText 'drv.importedCount' @{ anzahl = $added } }
        else { Get-WzText 'drv.importedNone' }
    } else {
        Get-WzText 'drv.importFailed' @{ code = $process.ExitCode }
    }

    Write-WzLog $result.Summary -Level $(if ($result.Success) { 'Ok' } else { 'Warn' })
    return $result
}

function Get-WzDriverBackups {
    <#
    .SYNOPSIS
        Vorhandene Treibersicherungen auf dem Datenträger.
    #>
    $root = Get-WzPath 'offline' 'treiber'
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $backups = foreach ($folder in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $packages = @(Get-ChildItem -LiteralPath $folder.FullName -Directory -ErrorAction SilentlyContinue).Count
        if ($packages -eq 0) { continue }
        $bytes = (Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        [pscustomobject]@{
            Host     = $folder.Name
            Path     = $folder.FullName
            Packages = $packages
            Bytes    = [int64]$bytes
            Created  = $folder.CreationTime
        }
    }
    return @($backups | Sort-Object Created -Descending)
}

# ===========================================================================
# Treiber beschaffen — in Stufen, von der sichersten zur brüchigsten.
#
# Eine allgemeine, saubere Lösung gibt es nicht: Kein Hersteller bietet eine
# öffentliche Schnittstelle für seine Treiber an. Was es gibt, sind vier
# Wege von unterschiedlicher Verlässlichkeit, und WinZii benennt sie als
# solche, statt einen davon als »automatische Treibersuche« zu verkaufen:
#
#   1. Sicherung        — zuerst, immer. Ein Herstellertreiber, der schlechter
#                         läuft als der alte, ist ein realer Fall.
#   2. Windows Update   — sicher, aber oft älter als der Herstellerstand.
#                         Liegt auf der Updates-Seite.
#   3. Werkzeug des Herstellers — der eigentliche Gewinn, aber nur für Dell,
#                         Lenovo und HP mit stiller Kommandozeile.
#   4. Update-Katalog   — für einzelne Geräte, die nach allem noch ohne
#                         Treiber dastehen. Über die Hardware-Kennung.
# ===========================================================================

function Get-WzOemDriverTools {
    <#
    .SYNOPSIS
        Die Werkzeuge der Gerätehersteller, passend zu diesem Gerät zuerst.
    .DESCRIPTION
        Erkannt wird über den Hersteller aus der Firmware. Intel steht ohne
        Erkennungsmuster im Katalog und gilt deshalb für jedes Gerät — die
        Chipsatz- und WLAN-Treiber kommen unabhängig vom Gehäuse von Intel.
    .OUTPUTS
        Liste mit Tool, Matches, Installed, ExecutablePath
    #>
    [CmdletBinding()]
    param()

    $manufacturer = ''
    $model = ''
    try {
        $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $manufacturer = "$($system.Manufacturer)".Trim()
        $model = "$($system.Model)".Trim()
    } catch { }

    $catalog = $null
    try { $catalog = Get-WzCatalog -Name 'oemtools' } catch {
        Write-WzLog (Get-WzText 'drv.logOemCatalogMissing') -Level Warn
        return @()
    }

    $entries = @()
    foreach ($tool in $catalog.tools) {
        $passt = if ($tool.match) { ("$manufacturer $model" -match $tool.match) } else { $false }
        $path = Resolve-WzOemToolPath -Tool $tool
        $entries += [pscustomobject]@{
            Tool           = $tool
            Matches        = $passt
            Installed      = [bool]$path
            ExecutablePath = $path
        }
    }

    return @($entries | Sort-Object -Property @{ Expression = 'Matches'; Descending = $true }, @{ Expression = { $_.Tool.name } })
}

function Resolve-WzOemToolPath {
    <#
    .SYNOPSIS
        Der erste Pfad aus dem Katalog, den es auf diesem Gerät wirklich gibt.
    .NOTES
        Die Hersteller verschieben ihre Werkzeuge zwischen den Fassungen. Ein
        fester Pfad wäre in einem Jahr falsch, ohne dass es jemand merkt —
        deshalb eine Liste von Kandidaten und die ehrliche Auskunft »nicht
        gefunden«, wenn keiner trifft.
    #>
    param([Parameter(Mandatory = $true)]$Tool)

    foreach ($candidate in @($Tool.paths)) {
        if (-not $candidate) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return ''
}

function Invoke-WzOemDriverUpdate {
    <#
    .SYNOPSIS
        Lässt das Werkzeug des Herstellers nach Treibern suchen und sie
        einspielen.
    .PARAMETER Entry
        Ein Eintrag aus Get-WzOemDriverTools.
    .PARAMETER ApplyUpdates
        Ohne diesen Schalter wird nur gesucht.
    .NOTES
        Neu gestartet wird nie von selbst — die Argumente im Katalog verbieten
        es ausdrücklich. Ein Werkzeug, das den PC eines Kunden mitten in der
        Arbeit neu startet, wäre unbrauchbar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [switch]$ApplyUpdates
    )

    $result = [pscustomobject]@{ Success = $false; Summary = ''; ExitCode = -1; RebootRequired = $false }
    $tool = $Entry.Tool

    if (-not $tool.silent) {
        $result.Summary = Get-WzText 'drv.oemNoCommandLine' @{ name = $tool.name }
        return $result
    }
    if (-not $Entry.ExecutablePath) {
        $result.Summary = Get-WzText 'drv.oemNotFound' @{ name = $tool.name }
        return $result
    }

    $arguments = if ($ApplyUpdates) { $tool.applyArgs } else { $tool.scanArgs }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'drv.logOemTest' @{ name = $tool.name; args = $arguments }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    Write-WzLog (Get-WzText 'drv.logOemRunning' @{ name = $tool.name }) -Level Action
    $process = Invoke-WzProcess -FilePath $Entry.ExecutablePath -Arguments $arguments `
        -TimeoutSeconds 3600 -LogOutput -KillOnCancel
    $result.ExitCode = $process.ExitCode

    # Die Rückgabewerte sind je Hersteller andere, und keiner davon ist
    # dokumentiert genug, um daraus mehr zu lesen als »lief durch« oder
    # »lief nicht durch«. Das steht so im Protokoll, statt eine Genauigkeit
    # vorzutäuschen, die es nicht gibt.
    $result.Success = ($process.ExitCode -eq 0)
    $result.Summary = if ($result.Success) {
        if ($ApplyUpdates) {
            Get-WzText 'drv.oemApplied' @{ name = $tool.name }
        } else {
            Get-WzText 'drv.oemScanned' @{ name = $tool.name }
        }
    } else {
        Get-WzText 'drv.oemFailed' @{ name = $tool.name; code = $process.ExitCode }
    }
    $result.RebootRequired = $ApplyUpdates

    Write-WzLog $result.Summary -Level $(if ($result.Success) { 'Ok' } else { 'Warn' })
    return $result
}

function Get-WzDriverlessDevices {
    <#
    .SYNOPSIS
        Geräte, für die überhaupt kein Treiber vorhanden ist, samt ihren
        Hardware-Kennungen.
    .DESCRIPTION
        Fehlercode 28 heißt »kein Treiber installiert« — das sind die gelben
        Ausrufezeichen im Geräte-Manager nach einer Neuinstallation. Für sie
        ist die Suche im Update-Katalog gedacht, und nur für sie: Ein Gerät,
        das läuft, bekommt keinen Treiber aus dem Netz nachgeworfen.
    #>
    [CmdletBinding()]
    param()

    $devices = @()
    try {
        $query = 'SELECT Name,DeviceID,HardwareID,ConfigManagerErrorCode,PNPClass FROM Win32_PnPEntity ' +
                 'WHERE ConfigManagerErrorCode = 28'
        foreach ($device in (Get-CimInstance -Query $query -ErrorAction Stop)) {
            # Die erste Kennung ist die genaueste (mit Revision), die letzte die
            # allgemeinste. Gesucht wird mit der zweiten, wenn es sie gibt:
            # Auf die Revision genau findet der Katalog meist nichts.
            $ids = @($device.HardwareID | Where-Object { $_ })
            if ($ids.Count -eq 0) { continue }
            $search = if ($ids.Count -gt 1) { $ids[1] } else { $ids[0] }
            $devices += [pscustomobject]@{
                Name        = if ($device.Name) { $device.Name } else { Get-WzText 'drv.unknownDevice' }
                Class       = if ($device.PNPClass) { Get-WzDeviceClassName $device.PNPClass } else { Get-WzText 'drv.noCategory' }
                DeviceId    = $device.DeviceID
                HardwareIds = $ids
                SearchId    = $search
            }
        }
    } catch {
        Write-WzLog (Get-WzText 'drv.logDevicesUnreadable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return @($devices)
}

function Find-WzCatalogDrivers {
    <#
    .SYNOPSIS
        Sucht im Microsoft Update-Katalog nach einem Treiber für eine
        Hardware-Kennung.
    .DESCRIPTION
        Der Katalog hat keine Schnittstelle — gelesen wird die Suchseite.
        Das ist der brüchigste Teil von WinZii: Ändert Microsoft den Aufbau
        der Seite, findet diese Funktion nichts mehr. Sie ist deshalb so
        gebaut, dass sie in diesem Fall sauber leer ausgeht statt falsch zu
        raten, und sie wird nur für Geräte aufgerufen, die ohne Treiber
        dastehen.
    .OUTPUTS
        Liste mit Title, UpdateId, Product, Date, SizeText
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$HardwareId)

    $found = @()
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $query = [Uri]::EscapeDataString($HardwareId)
        $response = Invoke-WebRequest -Uri "https://www.catalog.update.microsoft.com/Search.aspx?q=$query" `
            -UseBasicParsing -TimeoutSec 60 -UserAgent 'WinZii'
        $html = $response.Content
    } catch {
        Write-WzLog (Get-WzText 'drv.logCatalogUnreachable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        return @()
    }

    # Jede Trefferzeile trägt die Kennung des Updates im Namen ihrer Verweise.
    foreach ($row in [regex]::Matches($html, '(?s)<tr[^>]*id="([0-9a-fA-F-]{36})_R\d+"(.*?)</tr>')) {
        $updateId = $row.Groups[1].Value
        $cells = @([regex]::Matches($row.Groups[2].Value, '(?s)<td[^>]*>(.*?)</td>') |
            ForEach-Object { ConvertFrom-WzHtmlCell -Html $_.Groups[1].Value })
        if ($cells.Count -lt 7) { continue }

        $found += [pscustomobject]@{
            Title    = $cells[1]
            Product  = $cells[2]
            Date     = $cells[4]
            SizeText = $cells[6]
            UpdateId = $updateId
        }
    }

    Write-WzLog (Get-WzText 'drv.logCatalogFound' @{ anzahl = $found.Count; kennung = $HardwareId }) -Level Info
    return @($found)
}

function ConvertFrom-WzHtmlCell {
    <#
    .SYNOPSIS
        Macht aus einer Tabellenzelle des Katalogs lesbaren Text.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Html)

    $text = [regex]::Replace($Html, '(?s)<[^>]+>', '')
    $text = [Net.WebUtility]::HtmlDecode($text)
    return ($text -replace '\s+', ' ').Trim()
}

function Get-WzCatalogDownloadUrl {
    <#
    .SYNOPSIS
        Die eigentliche Datei-Adresse zu einem Katalogeintrag.
    .NOTES
        Der Katalog gibt sie nur über einen zweiten Aufruf heraus, der die
        Kennung als JSON im Formularfeld erwartet. Die Antwort ist eine
        Skriptseite, in der die Adresse als Zeichenkette steht.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$UpdateId)

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $body = @{ updateIDs = "[{`"size`":0,`"languages`":`"`",`"uidInfo`":`"$UpdateId`",`"updateID`":`"$UpdateId`"}]" }
        $response = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' `
            -Method Post -Body $body -UseBasicParsing -TimeoutSec 60 -UserAgent 'WinZii'

        $match = [regex]::Match($response.Content, "downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']+)'")
        if ($match.Success) { return $match.Groups[1].Value }

        # Zweite Schreibweise, die der Katalog je nach Eintrag benutzt
        $match = [regex]::Match($response.Content, "'(https://[^']*download\.windowsupdate\.com/[^']+)'")
        if ($match.Success) { return $match.Groups[1].Value }
    } catch {
        Write-WzLog (Get-WzText 'drv.logCatalogUnreachable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return ''
}

function Install-WzCatalogDriver {
    <#
    .SYNOPSIS
        Lädt einen Treiber aus dem Update-Katalog und spielt ihn ein.
    .DESCRIPTION
        Der Katalog liefert .cab-Dateien. Sie werden auf den Datenträger
        entpackt und mit pnputil eingespielt — derselbe Weg, den auch das
        Zurückspielen einer Sicherung nimmt. Die Datei bleibt liegen: Steht
        derselbe PC in einem Monat wieder auf dem Tisch, ist sie schon da.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$DeviceName
    )

    $result = [pscustomobject]@{ Success = $false; Summary = ''; Path = '' }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'drv.logCatalogTest' @{ titel = $Entry.Title }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    $url = Get-WzCatalogDownloadUrl -UpdateId $Entry.UpdateId
    if (-not $url) {
        $result.Summary = Get-WzText 'drv.catalogNoUrl'
        Write-WzLog $result.Summary -Level Warn
        return $result
    }

    # »katalog« ist ein Ordnername auf dem Datenträger, keine Anzeige.
    $target = New-WzDirectory (Get-WzPath 'offline' 'treiber' 'katalog' $Entry.UpdateId)
    $fileName = [IO.Path]::GetFileName(($url -split '\?')[0])
    if (-not $fileName) { $fileName = "$($Entry.UpdateId).cab" }
    $file = Join-Path $target $fileName

    Write-WzLog (Get-WzText 'drv.logCatalogDownloading' @{ titel = $Entry.Title }) -Level Action
    if (-not (Get-WzDownload -Url $url -TargetPath $file)) {
        $result.Summary = Get-WzText 'drv.catalogDownloadFailed'
        return $result
    }

    $unpacked = New-WzDirectory (Join-Path $target 'inhalt')
    if ([IO.Path]::GetExtension($file) -eq '.cab') {
        $expand = Invoke-WzProcess -FilePath 'expand.exe' -Arguments "`"$file`" -F:* `"$unpacked`"" -TimeoutSeconds 600
        if ($expand.ExitCode -ne 0) {
            $result.Summary = Get-WzText 'drv.catalogUnpackFailed' @{ code = $expand.ExitCode }
            Write-WzLog $result.Summary -Level Warn
            return $result
        }
    } else {
        # Manche Einträge sind .msu — die spielt wusa ein, nicht pnputil.
        $result.Summary = Get-WzText 'drv.catalogNotACab' @{ datei = $fileName; ordner = $target }
        Write-WzLog $result.Summary -Level Warn
        $result.Path = $target
        return $result
    }

    $import = Import-WzDrivers -Path $unpacked
    $result.Success = $import.Success
    $result.Path = $target
    $result.Summary = if ($import.Success) {
        Get-WzText 'drv.catalogInstalled' @{ geraet = $DeviceName }
    } else {
        $import.Summary
    }

    return $result
}
