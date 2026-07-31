# Drivers — Geräte mit Problemen finden, Treiber sichern und zurückspielen.
#
# Vor einer Neuinstallation ist die Treibersicherung die halbe Miete, gerade
# bei Notebooks mit Sonderhardware, für die es keine Downloads mehr gibt.

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
        1  = @{ Text = 'Das Gerät ist nicht richtig eingerichtet.'; Fix = 'Treiber neu installieren.' }
        3  = @{ Text = 'Der Treiber ist beschädigt oder der Speicher reicht nicht.'; Fix = 'Treiber neu installieren, danach Arbeitsspeicher prüfen.' }
        10 = @{ Text = 'Das Gerät lässt sich nicht starten.'; Fix = 'Meist ein falscher oder veralteter Treiber. Neueren Treiber vom Hersteller einspielen.' }
        12 = @{ Text = 'Es sind nicht genügend freie Ressourcen vorhanden.'; Fix = 'Eine andere Steckkarte entfernen oder im BIOS Ressourcen freigeben.' }
        14 = @{ Text = 'Das Gerät arbeitet erst nach einem Neustart richtig.'; Fix = 'PC neu starten.' }
        18 = @{ Text = 'Die Treiber müssen neu installiert werden.'; Fix = 'Treiber entfernen und neu einspielen.' }
        19 = @{ Text = 'Die Konfiguration in der Registry ist beschädigt.'; Fix = 'Gerät deinstallieren und neu erkennen lassen.' }
        22 = @{ Text = 'Das Gerät ist abgeschaltet.'; Fix = 'Im Geräte-Manager aktivieren.' }
        28 = @{ Text = 'Für dieses Gerät ist kein Treiber installiert.'; Fix = 'Das ist der Klassiker nach einer Neuinstallation — Treiber vom Hersteller oder aus der Sicherung einspielen.' }
        31 = @{ Text = 'Windows kann die nötigen Treiber nicht laden.'; Fix = 'Treiber neu installieren.' }
        37 = @{ Text = 'Der Treiber ließ sich nicht starten.'; Fix = 'Anderen Treiberstand versuchen.' }
        39 = @{ Text = 'Der Treiber fehlt oder ist beschädigt.'; Fix = 'Treiber neu installieren.' }
        43 = @{ Text = 'Windows hat das Gerät wegen eines gemeldeten Fehlers angehalten.'; Fix = 'Häufig ein Hardwaredefekt oder ein fehlerhafter Treiberstand. Bei USB-Geräten zuerst einen anderen Anschluss versuchen.' }
        45 = @{ Text = 'Das Gerät ist zurzeit nicht angeschlossen.'; Fix = 'Nur ein Hinweis auf ein früher genutztes Gerät — kein Fehler.' }
        52 = @{ Text = 'Die Signatur des Treibers lässt sich nicht prüfen.'; Fix = 'Unsignierter Treiber. Nur vom Hersteller nachladen.' }
    }

    $devices = @()
    try {
        $all = @(Get-CimInstance -Query 'SELECT Name,DeviceID,ConfigManagerErrorCode,PNPClass,Manufacturer,Status FROM Win32_PnPEntity' -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })

        foreach ($device in $all) {
            $code = [int]$device.ConfigManagerErrorCode
            $info = $meanings[$code]
            $devices += [pscustomobject]@{
                Name         = if ($device.Name) { $device.Name } else { 'Unbekanntes Gerät' }
                Class        = if ($device.PNPClass) { $device.PNPClass } else { 'ohne Kategorie' }
                Manufacturer = $device.Manufacturer
                Code         = $code
                Meaning      = if ($info) { $info.Text } else { "Fehlercode $code" }
                Fix          = if ($info) { $info.Fix } else { 'Im Geräte-Manager nachsehen und den Treiber erneuern.' }
                DeviceId     = $device.DeviceID
                # Code 45 heißt nur "gerade nicht angesteckt" und ist harmlos
                IsCritical   = ($code -ne 45)
            }
        }
    } catch {
        Write-WzLog "Geräteliste nicht abfragbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
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
                Class       = $driver.DeviceClass
                InfName     = $driver.InfName
                IsMicrosoft = $isMicrosoft
            }
        }
    } catch {
        Write-WzLog "Treiberliste nicht abfragbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
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

    $target = New-WzDirectory (Get-WzPath 'offline' 'treiber' $env:COMPUTERNAME)
    $result = [pscustomobject]@{ Success = $false; Path = $target; Packages = 0; Bytes = 0 }

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] Treiber würden nach $target gesichert" -Level Test
        $result.Success = $true
        return $result
    }

    Write-WzLog 'Treiber werden gesichert — das dauert je nach Umfang einige Minuten...' -Level Action

    if ($ThirdPartyOnly) {
        # Export-WindowsDriver liefert genau die Fremdtreiber
        try {
            $exported = @(Export-WindowsDriver -Online -Destination $target -ErrorAction Stop)
            $result.Packages = $exported.Count
            $result.Success = ($exported.Count -gt 0)
        } catch {
            Write-WzLog "Treibersicherung fehlgeschlagen: $($_.Exception.Message.Split([char]10)[0])" -Level Error
            return $result
        }
    } else {
        $process = Invoke-WzProcess -FilePath 'pnputil.exe' `
            -Arguments "/export-driver * `"$target`"" -TimeoutSeconds 1800
        if ($process.ExitCode -ne 0) {
            Write-WzLog "Treibersicherung endete mit Code $($process.ExitCode)" -Level Warn
        }
        $result.Packages = @(Get-ChildItem -LiteralPath $target -Directory -ErrorAction SilentlyContinue).Count
        $result.Success = ($result.Packages -gt 0)
    }

    $bytes = (Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $result.Bytes = [int64]$bytes

    if ($result.Success) {
        Write-WzLog "$($result.Packages) Treiberpaket(e) gesichert ($(Format-WzBytes $result.Bytes)) nach $target" -Level Ok
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
        $result.Summary = "Der Ordner $Path ist nicht vorhanden."
        return $result
    }

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] Treiber aus $Path würden eingespielt" -Level Test
        $result.Success = $true
        $result.Summary = 'Testmodus'
        return $result
    }

    Write-WzLog 'Treiber werden eingespielt...' -Level Action
    $process = Invoke-WzProcess -FilePath 'pnputil.exe' `
        -Arguments "/add-driver `"$Path\*.inf`" /subdirs /install" -TimeoutSeconds 1800 -LogOutput

    # pnputil meldet auch dann Erfolg, wenn einzelne Pakete übersprungen wurden
    $added = 0
    if ($process.StdOut -match '(?m)^\s*(?:Hinzugefügte Treiberpakete|Total driver packages added)\s*:\s*(\d+)') {
        $added = [int]$Matches[1]
    }

    $result.Success = ($process.ExitCode -eq 0)
    $result.Summary = if ($result.Success) {
        if ($added -gt 0) { "$added Treiberpaket(e) eingespielt. Ein Neustart wird empfohlen." }
        else { 'Der Vorgang lief durch. Es waren offenbar keine neuen Treiber dabei.' }
    } else {
        "Das Einspielen endete mit Code $($process.ExitCode)."
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
