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
        if ($cs.PartOfDomain) { $cs.Domain } else { "Arbeitsgruppe $($cs.Workgroup)" }
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
        $info.RamModules = @(Get-CimInstance -Query 'SELECT DeviceLocator,Capacity,Speed FROM Win32_PhysicalMemory' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{ Bank = $_.DeviceLocator; Bytes = [int64]$_.Capacity; Speed = $_.Speed }
            })
    } catch { }

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
    $info.StickDrive = "$($volume.DriveLetter): ($($volume.FileSystem))"
    $info.StickFreeBytes = $volume.FreeBytes
    $info.StickIsFat32 = $volume.IsFat32
    $info.WingetAvailable = [bool](Resolve-WzWingetPath)

    return [pscustomobject]$info
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
    $info.Activation = Get-WzActivationStatus
    $info.BitLocker = Get-WzBitLockerStatus

    $info.SecureBoot = try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'aktiv' } else { 'aus' }
    } catch { 'n/v (kein UEFI oder gesperrt)' }

    $info.Tpm = Get-WzTpmStatus

    $info.Defender = 'n/v'
    $info.DefenderOk = $true
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $parts = @()
        if ($mp.RealTimeProtectionEnabled) {
            $parts += 'Echtzeitschutz an'
        } else {
            $parts += 'Echtzeitschutz AUS'
            $info.DefenderOk = $false
        }
        if ($null -ne $mp.AntivirusSignatureAge) {
            $parts += "Signaturen $($mp.AntivirusSignatureAge) Tag(e) alt"
            if ($mp.AntivirusSignatureAge -gt 7) { $info.DefenderOk = $false }
        }
        $info.Defender = $parts -join ' · '
    } catch {
        $info.Defender = 'Drittanbieter-Virenschutz oder nicht abfragbar'
    }

    $info.PhysicalDisks = @()
    try {
        $info.PhysicalDisks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Number    = $_.DeviceId
                Model     = $_.FriendlyName
                MediaType = if ($_.MediaType) { $_.MediaType } else { 'Datenträger' }
                BusType   = $_.BusType
                SizeBytes = [int64]$_.Size
                Health    = $_.HealthStatus
            }
        })
    } catch { }

    return [pscustomobject]$info
}

function Resolve-WzWingetPath {
    <#
    .SYNOPSIS
        Vollständiger Pfad zu winget.exe oder $null.
        Im elevierten Kontext liegt winget häufig nicht im PATH, deshalb wird
        zusätzlich direkt im WindowsApps-Ordner gesucht.
    #>
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $pattern = Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $candidate = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }

    return $null
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
        if (-not $product) { return 'nicht ermittelbar' }

        $state = switch ($product.LicenseStatus) {
            0 { 'nicht lizenziert' }
            1 { 'aktiviert' }
            2 { 'Karenzzeit' }
            3 { 'Karenzzeit außerhalb der Toleranz' }
            4 { 'unlizenzierte Karenzzeit' }
            5 { 'Benachrichtigung — nicht aktiviert' }
            6 { 'zusätzliche Karenzzeit' }
            default { "Status $($product.LicenseStatus)" }
        }
        $channel = if ($product.ProductKeyChannel) { " · $($product.ProductKeyChannel)" } else { '' }
        return "$state$channel"
    } catch {
        return 'nicht ermittelbar'
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

    if (-not $service) { return 'nicht verfügbar (Windows Home)' }
    if ($bootStatus -eq 0 -and $service.Status -ne 'Running') {
        return 'Systemlaufwerk nicht verschlüsselt'
    }

    try {
        $volumes = Get-CimInstance -Namespace 'root\cimv2\security\microsoftvolumeencryption' `
            -Query 'SELECT DriveLetter,ProtectionStatus FROM Win32_EncryptableVolume' -ErrorAction Stop
        if (-not $volumes) { return 'nicht eingerichtet' }

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
        if ($parts.Count -eq 0) { return 'nicht eingerichtet' }
        return ($parts -join ' · ')
    } catch {
        return 'nicht abfragbar'
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
    if (-not $enum -or [int]$enum.Count -lt 1) { return 'nicht vorhanden' }

    $service = Get-Service TPM -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') { return 'vorhanden und aktiv' }
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
    if (-not $TimeSpan) { return 'n/v' }
    $parts = @()
    if ($TimeSpan.Days -gt 0) { $parts += "$($TimeSpan.Days) T" }
    if ($TimeSpan.Hours -gt 0) { $parts += "$($TimeSpan.Hours) Std" }
    $parts += "$($TimeSpan.Minutes) Min"
    return ($parts -join ' ')
}
