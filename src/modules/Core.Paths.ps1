# Core.Paths — alle Pfade relativ zum Stick-Wurzelverzeichnis.
# Der Laufwerksbuchstabe des Sticks ändert sich von PC zu PC, deshalb wird
# niemals ein absoluter Pfad hart verdrahtet.

# Beim Einlesen festgehalten: $PSScriptRoot zeigt hier verlässlich auf
# src\modules, gleich wer die Datei später einbindet.
$script:WzPathsDir = $PSScriptRoot

function Get-WzRoot {
    <#
    .SYNOPSIS
        Wurzelverzeichnis von WinZii (der Ordner mit Start.bat).
        Die globale Variable wird von main.ps1 gesetzt, damit auch
        Hintergrund-Runspaces den Pfad kennen ($PSCommandPath ist dort leer).
    #>
    if ($global:WzRootPath) { return $global:WzRootPath }

    # Notnagel, wenn main.ps1 die Variable nicht gesetzt hat — etwa weil ein
    # Testwerkzeug nur einzelne Module einbindet. Maßgeblich ist der Ort dieser
    # Datei, nicht $PSCommandPath: das zeigt auf das gerade laufende Skript und
    # landet je nach Aufrufer eine Ebene daneben, worauf die Kataloge dann unter
    # src\data\ gesucht werden.
    if ($script:WzPathsDir) {
        $global:WzRootPath = Split-Path -Parent (Split-Path -Parent $script:WzPathsDir)
    } else {
        $global:WzRootPath = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    }
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
    .NOTES
        Wirft bewusst nicht. main.ps1 läuft mit $ErrorActionPreference = 'Stop', und
        die erste Anlage passiert über Start-WzSession — bevor überhaupt ein Fenster
        steht. Auf einem schreibgeschützten Stick oder unter der Gruppenrichtlinie
        »Wechseldatenträger: Schreibzugriff verweigern« brach WinZii dadurch
        kommentarlos ab, ohne dass der Anwender je etwas zu sehen bekam.
        Die Aufrufer schreiben ohnehin abgesichert; wer wissen will, ob überhaupt
        etwas ankommt, fragt Test-WzWritableRoot.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            [void](New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop)
        } catch {
            if ($syncHash) { $syncHash.WriteBlocked = $true }
        }
    }
    return $Path
}

function Remove-WzTree {
    <#
    .SYNOPSIS
        Löscht eine Datei oder einen Ordner samt Inhalt, ohne Junctions und
        symbolischen Links zu folgen. Wirft beim ersten Fehler.
    .NOTES
        Windows PowerShell 5.1 steigt bei »Remove-Item -Recurse« in Junctions
        hinein und löscht den Inhalt des Ziels. Windows.old\Users\<Name> enthält
        »Application Data« & Co. mit absoluten Zielen ins lebende Profil — der
        Fallback der Windows.old-Bereinigung hätte so AppData des Kunden geleert
        (Audit 2026-10, K2). Hier wird jeder Reparsepunkt nur als Link entfernt;
        DirectoryInfo.Delete() ohne Rekursion ruft RemoveDirectory, und das
        nimmt bei einer Junction nur den Verweis weg.
        Iterativ statt rekursiv, damit tiefe Bäume nicht an der Aufruftiefe
        scheitern. Ordner werden in umgekehrter Fundreihenfolge gelöscht, also
        immer die Kinder vor dem Elternordner.
    #>
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $root = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    $dirs = New-Object System.Collections.Generic.List[IO.DirectoryInfo]
    $stack = New-Object System.Collections.Generic.Stack[IO.FileSystemInfo]
    $stack.Push($root)

    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        if ($item.Attributes -band [IO.FileAttributes]::ReadOnly) {
            $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
        }
        $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($item -is [IO.DirectoryInfo] -and -not $isLink) {
            $dirs.Add($item)
            foreach ($child in $item.EnumerateFileSystemInfos()) { $stack.Push($child) }
        } else {
            $item.Delete()
        }
    }

    for ($i = $dirs.Count - 1; $i -ge 0; $i--) { $dirs[$i].Delete() }
}

function Test-WzFileSignature {
    <#
    .SYNOPSIS
        Trägt die Datei eine gültige Authenticode-Signatur — auf Wunsch von
        Microsoft?
    .NOTES
        Der Stick wandert beschreibbar zwischen Kundenrechnern. Schadsoftware
        auf PC A kann eine EXE im Vorrat ersetzen, die auf PC B eleviert
        startet. Für Appx und Treiber prüft Windows selbst; für EXE und MSI
        tat es bisher niemand (Audit 2026-10, M8).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$RequireMicrosoft
    )

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    } catch {
        return $false
    }
    if ($signature.Status -ne 'Valid') { return $false }
    if ($RequireMicrosoft) {
        $subject = [string]$signature.SignerCertificate.Subject
        if ($subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { return $false }
    }
    return $true
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

    # Split-Path -Qualifier wirft bei UNC-Pfaden (\\server\freigabe\WinZii) einen
    # ParsePathFormatError. Das stand früher außerhalb jeder Absicherung und beendete
    # den Start, bevor das Fenster kam. Deshalb hier von Hand zerlegt.
    $driveLetter = ''
    $displayName = $rootPath
    if ($rootPath -match '^([A-Za-z]):') {
        $driveLetter = $Matches[1]
        $displayName = "$($Matches[1]):"
    } elseif ($rootPath -match '^(\\\\[^\\]+\\[^\\]+)') {
        $displayName = $Matches[1]
    }

    $result = [pscustomobject]@{
        DriveLetter = $driveLetter
        DisplayName = $displayName
        FileSystem  = Get-WzText 'core.unknown'
        FreeBytes   = 0
        SizeBytes   = 0
        IsFat32     = $false
        IsRemovable = $false
    }
    if (-not $driveLetter) { return $result }

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
