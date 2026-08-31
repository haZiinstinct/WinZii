# Core.System — Systemdaten für Dashboard und Berichte.
#
# Zweistufig, weil einige Windows-Abfragen sehr langsam sind (gemessen):
#   SoftwareLicensingProduct ungefiltert  12.400 ms   -> per WQL gefiltert 600 ms
#   Get-NetIPConfiguration                 3.600 ms   -> Win32_NetworkAdapterConfiguration 34 ms
#   Win32_Processor (alle Felder)          1.100 ms   -> per WQL mit Feldauswahl 100 ms
#   BitLocker-/TPM-Namespace               5.000 ms   -> nur Stufe 2, läuft im Hintergrund
#
# Stufe 1 (Get-WzSystemInfo)   : unter einer Sekunde, füllt das Dashboard sofort.
# Stufe 2 (Get-WzSecurityInfo) : Lizenz, Verschlüsselung, Virenschutz, Laufwerkszustand.
# Jede Abfrage ist einzeln abgesichert: fehlt etwas, steht dort "n/v".

function Get-WzSystemInfo {
    <#
    .SYNOPSIS
        Schnelle Eckdaten des laufenden PCs (Stufe 1).
    #>
    [CmdletBinding()]
    param()

    $info = [ordered]@{}

    # --- Windows ----------------------------------------------------------
    $os = try { Get-CimInstance -Query 'SELECT Caption,OSArchitecture,InstallDate,LastBootUpTime,FreePhysicalMemory FROM Win32_OperatingSystem' -ErrorAction Stop } catch { $null }
    $cv = try { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { $null }

    $info.ComputerName = $env:COMPUTERNAME
    $info.UserName = "$env:USERDOMAIN\$env:USERNAME"
    $info.OsCaption = if ($os) { $os.Caption.Trim() } else { 'n/v' }
    $info.OsEdition = if ($cv) { $cv.EditionID } else { 'n/v' }
    $info.OsVersion = if ($cv -and $cv.DisplayVersion) {
        $cv.DisplayVersion
    } elseif ($cv -and $cv.ReleaseId) {
        $cv.ReleaseId
    } else { 'n/v' }
    $info.OsBuild = if ($cv) { "$($cv.CurrentBuild).$($cv.UBR)" } else { 'n/v' }
    $info.BuildNumber = if ($cv) { [int]$cv.CurrentBuild } else { 0 }
    $info.OsArchitecture = if ($os) { $os.OSArchitecture } else { 'n/v' }
    $info.OsLanguage = try { (Get-Culture).Name } catch { 'n/v' }
    $info.InstallDate = if ($os) { $os.InstallDate } else { $null }
    $info.LastBoot = if ($os) { $os.LastBootUpTime } else { $null }
    $info.Uptime = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }
    $info.IsWindows11 = ($info.BuildNumber -ge 22000)

    # --- System und Bauform -----------------------------------------------
    $cs = try { Get-CimInstance -Query 'SELECT Manufacturer,Model,Domain,Workgroup,PartOfDomain,TotalPhysicalMemory FROM Win32_ComputerSystem' -ErrorAction Stop } catch { $null }
    $info.Domain = if ($cs) {
        if ($cs.PartOfDomain) { $cs.Domain } else { Get-WzText 'core.workgroup' @{ name = $cs.Workgroup } }
    } else { 'n/v' }
    $info.Manufacturer = if ($cs) { $cs.Manufacturer } else { 'n/v' }
    $info.Model = if ($cs) { $cs.Model } else { 'n/v' }
    $info.IsLaptop = $false
    try {
        $chassis = (Get-CimInstance -Query 'SELECT ChassisTypes FROM Win32_SystemEnclosure' -ErrorAction Stop).ChassisTypes
        $info.IsLaptop = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) -contains ($chassis | Select-Object -First 1)
    } catch { }

    # --- Prozessor und Arbeitsspeicher ------------------------------------
    $cpu = try {
        Get-CimInstance -Query 'SELECT Name,NumberOfCores,NumberOfLogicalProcessors FROM Win32_Processor' -ErrorAction Stop |
            Select-Object -First 1
    } catch { $null }
    $info.CpuName = if ($cpu) { $cpu.Name.Trim() } else { 'n/v' }
    $info.CpuCores = if ($cpu) { $cpu.NumberOfCores } else { 0 }
    $info.CpuThreads = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 0 }

    $info.RamTotalBytes = if ($cs) { [int64]$cs.TotalPhysicalMemory } else { 0 }
    $info.RamFreeBytes = if ($os) { [int64]$os.FreePhysicalMemory * 1KB } else { 0 }
    $info.RamUsedPercent = if ($info.RamTotalBytes -gt 0) {
        [math]::Round((1 - ($info.RamFreeBytes / $info.RamTotalBytes)) * 100)
    } else { 0 }
    $info.RamModules = @()
    try {
        $info.RamModules = @(Get-CimInstance -Query 'SELECT BankLabel,DeviceLocator,Capacity,Speed,Manufacturer FROM Win32_PhysicalMemory' -ErrorAction Stop |
            ForEach-Object {
                # Der DeviceLocator wiederholt sich über die Kanäle hinweg
                # ("DIMM 0" gibt es zweimal) — erst mit dem BankLabel wird die
                # Zeile eindeutig.
                $bank = if ($_.BankLabel -and $_.BankLabel -ne $_.DeviceLocator) {
                    "$($_.BankLabel) / $($_.DeviceLocator)"
                } else { $_.DeviceLocator }
                [pscustomobject]@{
                    Bank    = $bank
                    Bytes   = [int64]$_.Capacity
                    Speed   = $_.Speed
                    Vendor  = $_.Manufacturer
                }
            })
    } catch { }

    # Steckplätze und Höchstausbau — die eigentliche Aufrüstfrage
    $info.RamSlots = 0
    $info.RamSlotsUsed = @($info.RamModules).Count
    $info.RamMaxBytes = 0
    try {
        $array = Get-CimInstance -Query 'SELECT MemoryDevices,MaxCapacityEx FROM Win32_PhysicalMemoryArray' -ErrorAction Stop |
            Select-Object -First 1
        if ($array) {
            $info.RamSlots = [int]$array.MemoryDevices
            # MaxCapacityEx steht in Kilobyte
            $info.RamMaxBytes = [int64]$array.MaxCapacityEx * 1KB
        }
    } catch { }

    # --- Grafik und Monitore ----------------------------------------------
    $info.Gpus = Get-WzGraphicsInfo
    $info.Monitors = Get-WzMonitorInfo

    # --- Firmware ---------------------------------------------------------
    $info.BiosVersion = 'n/v'
    $info.BiosVendor = 'n/v'
    $info.BiosDate = $null
    $info.SerialNumber = ''
    try {
        $bios = Get-CimInstance -Query 'SELECT SMBIOSBIOSVersion,Manufacturer,ReleaseDate,SerialNumber FROM Win32_BIOS' -ErrorAction Stop |
            Select-Object -First 1
        if ($bios) {
            if ($bios.SMBIOSBIOSVersion) { $info.BiosVersion = $bios.SMBIOSBIOSVersion.Trim() }
            if ($bios.Manufacturer) { $info.BiosVendor = $bios.Manufacturer.Trim() }
            $info.BiosDate = $bios.ReleaseDate
            $info.SerialNumber = Get-WzUsableSerial $bios.SerialNumber
        }
    } catch { }

    $info.BaseBoard = 'n/v'
    try {
        $board = Get-CimInstance -Query 'SELECT Manufacturer,Product FROM Win32_BaseBoard' -ErrorAction Stop | Select-Object -First 1
        if ($board) { $info.BaseBoard = "$($board.Manufacturer) $($board.Product)".Trim() }
    } catch { }

    # --- Akku -------------------------------------------------------------
    $info.Battery = Get-WzBatteryHealth

    # --- Laufwerke --------------------------------------------------------
    $info.Volumes = @()
    try {
        $info.Volumes = @(Get-CimInstance -Query 'SELECT DeviceID,VolumeName,FileSystem,Size,FreeSpace FROM Win32_LogicalDisk WHERE DriveType=3' -ErrorAction Stop |
            ForEach-Object {
                $free = [int64]$_.FreeSpace
                $size = [int64]$_.Size
                [pscustomobject]@{
                    Letter      = $_.DeviceID
                    Label       = $_.VolumeName
                    FileSystem  = $_.FileSystem
                    SizeBytes   = $size
                    FreeBytes   = $free
                    UsedPercent = if ($size -gt 0) { [math]::Round((1 - ($free / $size)) * 100) } else { 0 }
                }
            })
    } catch { }

    # --- Netzwerk (alte WMI-Klasse: 100-mal schneller als Get-NetIPConfiguration) --
    $info.Network = @()
    try {
        $adapters = Get-CimInstance -Query 'SELECT Description,IPAddress,DefaultIPGateway,DNSServerSearchOrder,MACAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True' -ErrorAction Stop
        foreach ($adapter in $adapters) {
            $ipv4 = @($adapter.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
            if ($ipv4.Count -eq 0) { continue }
            $gateway = @($adapter.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
            $dns = @($adapter.DNSServerSearchOrder | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
            $info.Network += [pscustomobject]@{
                Adapter = $adapter.Description
                IPv4    = ($ipv4 -join ', ')
                Gateway = ($gateway -join ', ')
                Dns     = ($dns -join ', ')
                Mac     = $adapter.MACAddress
            }
        }
    } catch { }

    $info.PendingReboot = Test-WzPendingReboot

    # --- WinZii-Umgebung --------------------------------------------------
    $volume = Get-WzVolumeInfo
    $info.StickDrive = "$($volume.DisplayName) ($($volume.FileSystem))"
    $info.StickFreeBytes = $volume.FreeBytes
    $info.StickIsFat32 = $volume.IsFat32
    $info.WingetAvailable = [bool](Resolve-WzWingetPath)

    return [pscustomobject]$info
}

function Get-WzGraphicsInfo {
    <#
    .SYNOPSIS
        Grafikkarten mit Treiberstand, Auflösung und tatsächlichem Speicher.
    .NOTES
        AdapterRAM aus WMI ist eine 32-Bit-Zahl und läuft über: eine Karte mit
        12 GB meldet dort 4 GB. Der richtige Wert steht als qwMemorySize in der
        Registry. Fehlt er, wird gar keine Größe genannt — eine falsche wäre
        schlimmer als keine.
    #>
    $result = @()
    $memoryByName = @{}
    try {
        $classPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($key in (Get-ChildItem $classPath -ErrorAction SilentlyContinue)) {
            $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }
            if (-not $properties.PSObject.Properties['DriverDesc']) { continue }
            $size = $properties.PSObject.Properties['HardwareInformation.qwMemorySize']
            if ($size -and $size.Value) { $memoryByName[[string]$properties.DriverDesc] = [int64]$size.Value }
        }
    } catch { }

    try {
        $controllers = Get-CimInstance -Query 'SELECT Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate FROM Win32_VideoController' -ErrorAction Stop
        foreach ($controller in $controllers) {
            $resolution = if ($controller.CurrentHorizontalResolution) {
                "$($controller.CurrentHorizontalResolution) × $($controller.CurrentVerticalResolution) bei $($controller.CurrentRefreshRate) Hz"
            } else { '' }
            $result += [pscustomobject]@{
                Name          = $controller.Name
                DriverVersion = $controller.DriverVersion
                Resolution    = $resolution
                MemoryBytes   = [int64]$memoryByName[[string]$controller.Name]
            }
        }
    } catch { }
    return @($result)
}

function Get-WzMonitorInfo {
    <#
    .SYNOPSIS
        Angeschlossene Bildschirme mit Größe und Baujahr.
    .NOTES
        Die Namen stehen im WMI als Zeichen-Arrays mit abschließenden Nullen.
    #>
    $result = @()
    try {
        $ids = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop)
        $sizes = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue)

        for ($index = 0; $index -lt $ids.Count; $index++) {
            $id = $ids[$index]
            $name = ConvertFrom-WzWmiString $id.UserFriendlyName
            $vendor = ConvertFrom-WzWmiString $id.ManufacturerName

            $inches = 0
            $size = $sizes | Where-Object { $_.InstanceName -eq $id.InstanceName } | Select-Object -First 1
            if (-not $size -and $index -lt $sizes.Count) { $size = $sizes[$index] }
            if ($size -and $size.MaxHorizontalImageSize -gt 0) {
                $diagonal = [math]::Sqrt(($size.MaxHorizontalImageSize * $size.MaxHorizontalImageSize) +
                                         ($size.MaxVerticalImageSize * $size.MaxVerticalImageSize))
                $inches = [math]::Round($diagonal / 2.54, 1)
            }

            $result += [pscustomobject]@{
                Name   = if ($name) { $name } else { 'Bildschirm' }
                Vendor = $vendor
                Year   = $id.YearOfManufacture
                Inches = $inches
            }
        }
    } catch { }
    return @($result)
}

function ConvertFrom-WzWmiString {
    <#
    .SYNOPSIS
        Wandelt ein WMI-Zeichenarray in Text (ohne die Nullen am Ende).
    #>
    param($Characters)
    if (-not $Characters) { return '' }
    return (-join ($Characters | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })).Trim()
}

function Get-WzUsableSerial {
    <#
    .SYNOPSIS
        Seriennummer, sofern der Hersteller überhaupt eine eingetragen hat.
    .NOTES
        Selbstbau-Mainboards melden hier Platzhalter wie "Default string" oder
        lauter Nullen. Die im Bericht als Seriennummer zu führen, wäre irreführend.
    #>
    param([string]$Value)
    if (-not $Value) { return '' }
    $trimmed = $Value.Trim()
    if ($trimmed -match '^(To be filled by O\.E\.M\.|System Serial Number|Default string|None|0+|\.+)$') { return '' }
    if ($trimmed.Length -lt 3) { return '' }
    return $trimmed
}

function Get-WzBatteryHealth {
    <#
    .SYNOPSIS
        Akkuverschleiß in Prozent — die eine Zahl, die zählt.
    .DESCRIPTION
        Verschleiß = 1 - (heutige volle Ladung / Auslegungskapazität). Der
        powercfg-Bericht enthält dieselbe Angabe, aber vergraben in mehreren
        Bildschirmseiten HTML.

        Gefragt werden drei Quellen, weil keine für sich verlässlich ist:
        BatteryStaticData steigt auf diesem MSI-Notebook mit einem
        WMI-Providerfehler aus (»Allgemeiner Fehler«), Win32_Battery lässt
        DesignCapacity dort leer, und BatteryFullChargedCapacity kennt die
        Auslegung gar nicht. Bis 0.4.0 hing die ganze Erkennung allein an
        BatteryStaticData: Ein Notebook mit gesundem Akku meldete »kein Akku
        vorhanden«, und die Akkuzeile des Dashboards fiel ersatzlos weg.
    #>
    $result = [pscustomobject]@{
        Present      = $false
        WearPercent  = $null
        DesignmWh    = 0
        FullmWh      = 0
        ChargePercent = $null
        Verdict      = 'kein Akku vorhanden'
    }

    $static = @()
    $full = @()
    try { $static = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop) } catch { }
    try { $full = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop) } catch { }

    $battery = $null
    try {
        $battery = Get-CimInstance -Query 'SELECT EstimatedChargeRemaining FROM Win32_Battery' -ErrorAction Stop |
            Select-Object -First 1
    } catch { }

    # Kein Akku ist nur dann kein Akku, wenn ihn keine der drei Quellen kennt.
    if ($static.Count -eq 0 -and $full.Count -eq 0 -and -not $battery) { return $result }

    $result.Present = $true
    if ($battery) { $result.ChargePercent = [int]$battery.EstimatedChargeRemaining }
    if ($static.Count -gt 0) { $result.DesignmWh = [int]($static | Measure-Object -Property DesignedCapacity -Sum).Sum }
    if ($full.Count -gt 0) { $result.FullmWh = [int]($full | Measure-Object -Property FullChargedCapacity -Sum).Sum }

    # Fehlt eine der beiden Zahlen, steht sie im powercfg-Bericht.
    if ($result.DesignmWh -le 0 -or $result.FullmWh -le 0) {
        $report = Get-WzBatteryReportCapacities
        if ($report) {
            if ($result.DesignmWh -le 0) { $result.DesignmWh = $report.DesignmWh }
            if ($result.FullmWh -le 0) { $result.FullmWh = $report.FullmWh }
        }
    }

    if ($result.DesignmWh -gt 0 -and $result.FullmWh -gt 0) {
        # Neue Akkus melden gern mehr als die Auslegungskapazität — ein
        # negativer Verschleiß wäre Unsinn, also bei 0 abschneiden.
        $result.WearPercent = [math]::Max(0, [math]::Round((1 - ($result.FullmWh / $result.DesignmWh)) * 100))
        $result.Verdict = if ($result.WearPercent -lt 20) {
            Get-WzText 'core.wearOk' @{ prozent = $result.WearPercent }
        } elseif ($result.WearPercent -lt 40) {
            Get-WzText 'core.wearWeak' @{ prozent = $result.WearPercent }
        } else {
            Get-WzText 'core.wearReplace' @{ prozent = $result.WearPercent }
        }
    } else {
        $result.Verdict = Get-WzText 'core.wearUnknown'
    }

    return $result
}

function Get-WzBatteryReportCapacities {
    <#
    .SYNOPSIS
        Auslegungs- und Ladekapazität aus dem powercfg-Akkubericht.
    .NOTES
        Ausweichweg für Geräte, deren WMI die Auslegungskapazität verschweigt.
        Der Bericht kostet eine knappe Sekunde, wird aber vom Dashboard und vom
        Übergabeblatt angefordert — deshalb einmal je Sitzung.
    .OUTPUTS
        PSCustomObject mit DesignmWh und FullmWh, oder $null
    #>
    if ($script:WzBatteryReportChecked) { return $script:WzBatteryReportCapacities }
    $script:WzBatteryReportChecked = $true
    $script:WzBatteryReportCapacities = $null

    $file = Join-Path ([IO.Path]::GetTempPath()) "winzii-akku-$PID.html"
    try {
        $run = Invoke-WzProcess -FilePath 'powercfg.exe' `
            -Arguments "/batteryreport /output `"$file`"" -TimeoutSeconds 30
        if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $file)) { return $null }

        $html = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
        $design = Read-WzBatteryReportValue -Html $html -Labels @(
            'DESIGN CAPACITY', 'KONSTRUKTIONSKAPAZITÄT', 'ENTWURFSKAPAZITÄT')
        $charged = Read-WzBatteryReportValue -Html $html -Labels @(
            'FULL CHARGE CAPACITY', 'VOLLLADUNGSKAPAZITÄT')

        if ($design -gt 0 -or $charged -gt 0) {
            $script:WzBatteryReportCapacities = [pscustomobject]@{
                DesignmWh = $design
                FullmWh   = $charged
            }
        }
    } catch {
        Write-WzLog (Get-WzText 'core.logBatteryReport' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Info
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }

    return $script:WzBatteryReportCapacities
}

function Read-WzBatteryReportValue {
    <#
    .SYNOPSIS
        Eine Kapazitätsangabe aus dem HTML des Akkuberichts.
    .NOTES
        Die Beschriftung ist je nach Windows-Sprache deutsch oder englisch, die
        Zahl je nach Kultur mit Punkt oder Komma gruppiert (»80.256 mWh«) —
        deshalb bleibt vom Zellinhalt nur die Ziffernfolge übrig.

        Der Anker <span class="label"> ist wichtig: Dieselben Wörter stehen
        weiter unten noch einmal als Spaltenüberschriften der Verlaufstabelle,
        dort aber ohne diese Auszeichnung.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Html,
        [Parameter(Mandatory = $true)][string[]]$Labels
    )

    foreach ($label in $Labels) {
        $pattern = '<span class="label">\s*' + [regex]::Escape($label) + '\s*</span>\s*</td>\s*<td[^>]*>([^<]*)'
        $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { continue }

        $digits = $match.Groups[1].Value -replace '[^\d]', ''
        if ($digits) { return [int]$digits }
    }
    return 0
}

function Get-WzSecurityInfo {
    <#
    .SYNOPSIS
        Langsame Abfragen (Stufe 2): Lizenz, Verschlüsselung, Virenschutz,
        Laufwerkszustand. Wird nach dem Dashboard-Aufbau nachgeladen.
    #>
    [CmdletBinding()]
    param()

    $info = [ordered]@{}
    # Text UND sprachneutraler Zustand: Ob Windows aktiviert ist, wurde vorher
    # am deutschen Wort »aktiviert« erkannt. Sobald die Oberflaeche Englisch
    # spricht, traf der Vergleich nie mehr — das Dashboard meldete auf einem
    # aktivierten Rechner »Bitte pruefen«.
    $activation = Get-WzActivationStatus
    $info.Activation = $activation.Text
    $info.ActivationOk = $activation.Ok
    $info.BitLocker = Get-WzBitLockerStatus

    $info.SecureBoot = try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { Get-WzText 'core.secureBootOn' } else { Get-WzText 'core.secureBootOff' }
    } catch { Get-WzText 'core.secureBootNa' }

    $info.Tpm = Get-WzTpmStatus

    $info.Defender = 'n/v'
    $info.DefenderOk = $true
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $parts = @()
        # Weiches Trennzeichen (U+00AD): Am Fenster-Mindestmaß ist die Karte
        # schmaler als das Wort, und WPF trennte mitten drin (»Echtzeitschut z«).
        # So wird daraus bei Platznot »Echtzeit-schutz«, sonst bleibt es unsichtbar.
        if ($mp.RealTimeProtectionEnabled) {
            $parts += Get-WzText 'core.defenderRtOn'
        } else {
            $parts += Get-WzText 'core.defenderRtOff'
            $info.DefenderOk = $false
        }
        if ($null -ne $mp.AntivirusSignatureAge) {
            $parts += Get-WzText 'core.defenderSignatures' @{ tage = $mp.AntivirusSignatureAge }
            if ($mp.AntivirusSignatureAge -gt 7) { $info.DefenderOk = $false }
        }
        $info.Defender = $parts -join ' · '
    } catch {
        $info.Defender = Get-WzText 'core.defenderThirdParty'
    }

    $info.PhysicalDisks = @()
    try {
        $info.PhysicalDisks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Number    = $_.DeviceId
                Model     = $_.FriendlyName
                MediaType = if ($_.MediaType) { $_.MediaType } else { Get-WzText 'core.diskGeneric' }
                BusType   = $_.BusType
                SizeBytes = [int64]$_.Size
                Health    = $_.HealthStatus
            }
        })
    } catch { }

    return [pscustomobject]$info
}

function Get-WzWingetCandidates {
    <#
    .SYNOPSIS
        Alle in Frage kommenden Pfade zu winget.exe, in der Reihenfolge, in der
        sie ausprobiert werden sollen.
    .DESCRIPTION
        Drei Wege, weil jeder einzelne unter Elevierung ausfallen kann:

        1. PATH — greift nur, wenn der App-Installer-Alias für das ELEVIERTE
           Konto registriert ist. Meldet sich der Techniker mit einem eigenen
           Admin-Konto an, gehört %LOCALAPPDATA%\...\WindowsApps einem anderen
           Profil, und winget scheint zu fehlen, obwohl es da ist.
        2. Das Appx-Paket selbst, ausdrücklich über alle Benutzer. Das ist der
           verlässliche Weg im Technikerfall und braucht keine Ordnerrechte.
        3. Ordnersuche als letzter Ausweg. Bewusst OHNE feste Architektur —
           »_x64__« traf auf ARM64-Geräten nie zu.

        Es wird eine LISTE geliefert, nicht der erste Treffer: Der Sandbox-Lauf
        hat gezeigt, dass Weg 1 direkt nach der Einrichtung einen Alias findet,
        der noch gar nicht startet (Rückgabewert -1). Wer dort stehen bleibt,
        meldet »winget nicht verfügbar«, obwohl das Paket daneben liegt und
        einwandfrei läuft.
    #>
    [CmdletBinding()]
    param()

    $candidates = New-Object Collections.ArrayList

    # Ein Pfad, der sich schon als lauffähig erwiesen hat, steht vorn.
    if ($syncHash -and $syncHash.WingetPath) { [void]$candidates.Add($syncHash.WingetPath) }

    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) { [void]$candidates.Add($command.Source) }

    # Die Alias-Ablage direkt, ohne Befehlssuche: Im Hintergrund-Runspace findet
    # Get-Command winget.exe NICHTS — die Runspaces werden aus einem eigenen
    # InitialSessionState aufgebaut, in dem die Suche nach ausführbaren Dateien
    # ins Leere läuft. Die Oberfläche meldete deshalb »winget nicht gefunden«,
    # während dasselbe Get-Command im Hauptthread den Pfad lieferte.
    $bases = @($env:LOCALAPPDATA)
    # Bei Elevierung mit einem Technikerkonto liegt der Alias im Profil des
    # angemeldeten Anwenders, nicht im eigenen.
    try { $bases += (Get-WzUserFolder -Kind 'LocalAppData') } catch { }
    foreach ($base in $bases) {
        if (-not $base) { continue }
        $alias = Join-Path $base 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $alias) { [void]$candidates.Add($alias) }
    }

    try {
        $package = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -AllUsers -ErrorAction Stop |
            Sort-Object -Property Version -Descending | Select-Object -First 1
        if ($package -and $package.InstallLocation) {
            $candidate = Join-Path $package.InstallLocation 'winget.exe'
            if (Test-Path -LiteralPath $candidate) { [void]$candidates.Add($candidate) }
        }
    } catch {
        # -AllUsers verlangt Adminrechte; ohne sie bleibt Weg 3
    }

    $pattern = Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe'
    try {
        $candidate = Get-ChildItem -Path $pattern -Directory -ErrorAction Stop |
            ForEach-Object { Join-Path $_.FullName 'winget.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Sort-Object -Descending | Select-Object -First 1
        if ($candidate) { [void]$candidates.Add($candidate) }
    } catch {
        # Der Ordner ist per Rechtevergabe auch für Administratoren gesperrt.
        # Früher verschluckte -ErrorAction SilentlyContinue genau das und
        # ließ winget als »nicht vorhanden« erscheinen.
        Write-WzLog (Get-WzText 'core.logWindowsApps' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Info
    }

    return @($candidates | Select-Object -Unique)
}

function Resolve-WzWingetPath {
    <#
    .SYNOPSIS
        Vollständiger Pfad zu winget.exe oder $null.
    .NOTES
        Liefert den Pfad, der sich in Test-WzWinget als lauffähig erwiesen hat,
        sonst den ersten Kandidaten. Das Ergebnis wird gemerkt: Die Auflösung
        lief bis zu fünfmal pro Vorgang, jedes Mal mit einer Suche über einen
        Ordner, dessen Rechte selbst Administratoren aussperren.
    #>
    if ($syncHash -and $syncHash.WingetPath) { return $syncHash.WingetPath }

    $found = @(Get-WzWingetCandidates)[0]
    if ($found -and $syncHash) { $syncHash.WingetPath = $found }
    return $found
}

function Get-WzActivationStatus {
    <#
    .SYNOPSIS
        Aktivierungsstatus von Windows im Klartext.
        WQL-Filter ist Pflicht: ungefiltert dauert die Abfrage über 12 Sekunden.
    #>
    try {
        $query = "SELECT LicenseStatus,ProductKeyChannel FROM SoftwareLicensingProduct " +
                 "WHERE PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'"
        $product = Get-CimInstance -Query $query -ErrorAction Stop | Select-Object -First 1
        if (-not $product) { return [pscustomobject]@{ Text = (Get-WzText 'core.actNotDeterminable'); Ok = $false } }

        $state = switch ($product.LicenseStatus) {
            0 { Get-WzText 'core.actUnlicensed' }
            1 { Get-WzText 'core.actActivated' }
            2 { Get-WzText 'core.actGrace' }
            3 { Get-WzText 'core.actGraceOut' }
            4 { Get-WzText 'core.actUnlicensedGrace' }
            5 { Get-WzText 'core.actNotification' }
            6 { Get-WzText 'core.actExtraGrace' }
            default { Get-WzText 'core.actStatus' @{ code = $product.LicenseStatus } }
        }
        $channel = if ($product.ProductKeyChannel) { " · $($product.ProductKeyChannel)" } else { '' }
        return [pscustomobject]@{ Text = "$state$channel"; Ok = ([int]$product.LicenseStatus -eq 1) }
    } catch {
        return [pscustomobject]@{ Text = (Get-WzText 'core.actNotDeterminable'); Ok = $false }
    }
}

function Get-WzBitLockerStatus {
    <#
    .SYNOPSIS
        BitLocker-Zustand als kurzer Text.
        Erst eine Registry-Schnellprüfung (15 ms): ist das Systemlaufwerk gar
        nicht verschlüsselt, wird der teure WMI-Namespace (5 s) übersprungen.
    #>
    $bootStatus = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLockerStatus' -ErrorAction SilentlyContinue).BootStatus
    $service = Get-Service BDESVC -ErrorAction SilentlyContinue

    # Kein pauschales »Windows Home«: Home hat den Dienst ebenfalls, nur die
    # Verwaltungsoberfläche fehlt dort.
    if (-not $service) { return Get-WzText 'core.bdeNoService' }
    if ($bootStatus -eq 0 -and $service.Status -ne 'Running') {
        # Laufwerksbuchstabe statt »Systemlaufwerk« — wie die WMI-Ausgabe unten
        # (»C: an · D: aus«). Das lange Wort brach am Fenster-Mindestmaß mitten
        # in der Dashboard-Karte um: »Systemlaufwer k«.
        return Get-WzText 'core.bdeNotEncrypted' @{ laufwerk = $env:SystemDrive }
    }

    try {
        $volumes = Get-CimInstance -Namespace 'root\cimv2\security\microsoftvolumeencryption' `
            -Query 'SELECT DriveLetter,ProtectionStatus FROM Win32_EncryptableVolume' -ErrorAction Stop
        if (-not $volumes) { return Get-WzText 'core.bdeNotSetup' }

        $parts = @()
        foreach ($volume in $volumes) {
            if (-not $volume.DriveLetter) { continue }
            $state = switch ($volume.ProtectionStatus) {
                0 { 'aus' }
                1 { 'an' }
                2 { 'unbekannt' }
                default { '?' }
            }
            $parts += "$($volume.DriveLetter) $state"
        }
        if ($parts.Count -eq 0) { return Get-WzText 'core.bdeNotSetup' }
        return ($parts -join ' · ')
    } catch {
        return Get-WzText 'core.bdeNotQueryable'
    }
}

function Get-WzTpmStatus {
    <#
    .SYNOPSIS
        TPM-Zustand über Geräteliste und Dienst statt über den WMI-Namespace.
        Der Namespace root\cimv2\security\microsofttpm braucht bis zu 5 Sekunden
        und liefert auf manchen Systemen trotz vorhandenem TPM nichts.
    #>
    $enum = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\TPM\Enum' -ErrorAction SilentlyContinue
    if (-not $enum -or [int]$enum.Count -lt 1) { return Get-WzText 'core.tpmNone' }

    $service = Get-Service TPM -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') { return Get-WzText 'core.tpmActive' }
    return 'vorhanden, Dienst gestoppt'
}

function Test-WzPendingReboot {
    <#
    .SYNOPSIS
        Prüft die üblichen Stellen, an denen Windows einen Neustart vormerkt.
    #>
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons += 'Komponentenwartung'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons += 'Windows Update'
    }
    $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
        $reasons += 'ausstehende Dateiumbenennungen'
    }
    if ($reasons.Count -eq 0) { return $null }
    return ($reasons -join ', ')
}

function Format-WzUptime {
    <#
    .SYNOPSIS
        TimeSpan als "3 T 4 Std 12 Min".
    #>
    param($TimeSpan)
    if (-not $TimeSpan) { return Get-WzText 'core.uptimeNa' }
    $parts = @()
    if ($TimeSpan.Days -gt 0) { $parts += Get-WzText 'core.uptimeDays' @{ tage = $TimeSpan.Days } }
    if ($TimeSpan.Hours -gt 0) { $parts += Get-WzText 'core.uptimeHours' @{ stunden = $TimeSpan.Hours } }
    $parts += Get-WzText 'core.uptimeMinutes' @{ minuten = $TimeSpan.Minutes }
    return ($parts -join ' ')
}

function Get-WzInteractiveProfile {
    <#
    .SYNOPSIS
        Profilordner des am Bildschirm angemeldeten Anwenders — aber nur, wenn
        WinZii unter einem anderen Konto läuft. Sonst $null.
    .DESCRIPTION
        Das Gegenstück zu Resolve-WzRegistryPath für das Dateisystem: Wird die
        Rechteanforderung mit einem Technikerkonto beantwortet, zeigen
        $env:USERPROFILE und Verwandte auf dessen Profil. Die Seite »Daten«
        würde dann »kein OneDrive« melden, obwohl der Kunde eines hat, und die
        Bereinigung würde das falsche Profil aufräumen.
    #>
    if ($script:WzInteractiveProfileChecked) { return $script:WzInteractiveProfile }
    $script:WzInteractiveProfileChecked = $true
    $script:WzInteractiveProfile = $null

    $sid = Get-WzInteractiveUserSid
    if (-not $sid) { return $null }

    try {
        $entry = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop
        $profilePath = [Environment]::ExpandEnvironmentVariables([string]$entry.ProfileImagePath)
        if ($profilePath -and (Test-Path -LiteralPath $profilePath -ErrorAction SilentlyContinue)) {
            $script:WzInteractiveProfile = [pscustomobject]@{
                Sid  = $sid
                Path = $profilePath
            }
        }
    } catch { }
    return $script:WzInteractiveProfile
}

function Expand-WzUserPath {
    <#
    .SYNOPSIS
        Löst Umgebungsvariablen auf — benutzerbezogene aber auf das Profil des
        angemeldeten Anwenders statt auf das Konto, unter dem WinZii läuft.
    .NOTES
        Läuft WinZii unter dem Konto des Anwenders (der Normalfall), ist das
        Ergebnis identisch mit ExpandEnvironmentVariables.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $interactive = Get-WzInteractiveProfile
    if ($interactive) {
        $userRoot = $interactive.Path
        $replacements = @(
            @('%USERPROFILE%', $userRoot),
            @('%LOCALAPPDATA%', (Join-Path $userRoot 'AppData\Local')),
            @('%APPDATA%', (Join-Path $userRoot 'AppData\Roaming')),
            @('%TEMP%', (Join-Path $userRoot 'AppData\Local\Temp')),
            @('%TMP%', (Join-Path $userRoot 'AppData\Local\Temp'))
        )
        foreach ($pair in $replacements) {
            # -replace ist in PowerShell ohnehin schreibungsunabhängig; im
            # Ersatztext ist nur $ besonders und wird verdoppelt.
            $Path = $Path -replace [regex]::Escape($pair[0]), $pair[1].Replace('$', '$$')
        }
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-WzUserFolder {
    <#
    .SYNOPSIS
        Benutzerordner des angemeldeten Anwenders (LocalAppData, RoamingAppData,
        Profile) — fällt auf die Umgebung des laufenden Kontos zurück.
    #>
    param([ValidateSet('Profile', 'LocalAppData', 'RoamingAppData')][string]$Kind = 'Profile')

    $interactive = Get-WzInteractiveProfile
    if ($interactive) {
        switch ($Kind) {
            'LocalAppData'   { return Join-Path $interactive.Path 'AppData\Local' }
            'RoamingAppData' { return Join-Path $interactive.Path 'AppData\Roaming' }
            default          { return $interactive.Path }
        }
    }
    switch ($Kind) {
        'LocalAppData'   { return $env:LOCALAPPDATA }
        'RoamingAppData' { return $env:APPDATA }
        default          { return $env:USERPROFILE }
    }
}
