# Core.Paths — alle Pfade relativ zum Stick-Wurzelverzeichnis.
# Der Laufwerksbuchstabe des Sticks ändert sich von PC zu PC, deshalb wird
# niemals ein absoluter Pfad hart verdrahtet.

function Get-WzRoot {
    <#
    .SYNOPSIS
        Wurzelverzeichnis von WinZii (der Ordner mit Start.bat).
        Die globale Variable wird von main.ps1 gesetzt, damit auch
        Hintergrund-Runspaces den Pfad kennen ($PSCommandPath ist dort leer).
    #>
    if ($global:WzRootPath) { return $global:WzRootPath }
    $global:WzRootPath = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    return $global:WzRootPath
}

function Get-WzPath {
    <#
    .SYNOPSIS
        Pfad unterhalb des WinZii-Wurzelverzeichnisses zusammensetzen.
    .EXAMPLE
        Get-WzPath 'data' 'tweaks.json'
    #>
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Segments)
    $path = Get-WzRoot
    foreach ($segment in $Segments) { $path = Join-Path $path $segment }
    return $path
}

function Get-WzDataDir { Get-WzPath 'data' }
function Get-WzXamlDir { Get-WzPath 'src' 'xaml' }
function Get-WzTemplateDir { Get-WzPath 'src' 'templates' }
function Get-WzAssetDir { Get-WzPath 'assets' }
function Get-WzFontDir { Get-WzPath 'assets' 'fonts' }
function Get-WzOfflineDir { New-WzDirectory (Get-WzPath 'offline') }

function Get-WzLogDir {
    <#
    .SYNOPSIS
        Log-Verzeichnis der aktuellen Sitzung: logs\<hostname>\<zeitstempel>\
    #>
    if (-not $global:WzSessionStamp) {
        $global:WzSessionStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    }
    New-WzDirectory (Get-WzPath 'logs' $env:COMPUTERNAME $global:WzSessionStamp)
}

function Get-WzBackupDir {
    <#
    .SYNOPSIS
        Backup-Verzeichnis für Registry-Exporte und Undo-Daten.
    .PARAMETER Stamp
        Zeitstempel des Backup-Laufs. Ohne Angabe wird ein neuer erzeugt.
    #>
    param([string]$Stamp)
    if (-not $Stamp) { $Stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss' }
    New-WzDirectory (Get-WzPath 'backups' $env:COMPUTERNAME $Stamp)
}

function Get-WzBackupRoot { Get-WzPath 'backups' $env:COMPUTERNAME }

function Get-WzReportDir { New-WzDirectory (Get-WzPath 'reports' $env:COMPUTERNAME) }

function New-WzDirectory {
    <#
    .SYNOPSIS
        Verzeichnis anlegen (falls nötig) und Pfad zurückgeben.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
    return $Path
}

function Test-WzWritableRoot {
    <#
    .SYNOPSIS
        Prüft, ob auf den Stick geschrieben werden kann (Protokolle, Berichte, Cache).
    #>
    $probe = Join-Path (Get-WzRoot) '.wz-write-test'
    try {
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Get-WzVolumeInfo {
    <#
    .SYNOPSIS
        Dateisystem und freier Platz des Datenträgers, auf dem WinZii liegt.
        Wichtig für die 4-GB-Dateigrenze von FAT32 beim Office-Download.
    #>
    $rootPath = Get-WzRoot
    $driveLetter = (Split-Path -Qualifier $rootPath).TrimEnd(':')
    $result = [pscustomobject]@{
        DriveLetter = $driveLetter
        FileSystem  = 'unbekannt'
        FreeBytes   = 0
        SizeBytes   = 0
        IsFat32     = $false
        IsRemovable = $false
    }
    try {
        $volume = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$driveLetter`:'" -ErrorAction Stop
        $result.FileSystem = $volume.FileSystem
        $result.FreeBytes = [int64]$volume.FreeSpace
        $result.SizeBytes = [int64]$volume.Size
        $result.IsFat32 = ($volume.FileSystem -eq 'FAT32')
        $result.IsRemovable = ($volume.DriveType -eq 2)
    } catch {
        # Netzlaufwerk oder Sonderfall — Standardwerte behalten
    }
    return $result
}
