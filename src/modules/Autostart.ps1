# Autostart — Programme, die beim Anmelden mitstarten.
#
# Deaktivieren funktioniert wie im Task-Manager: Der Eintrag bleibt erhalten,
# nur ein Schaltbyte unter StartupApproved wird gesetzt. Es wird nie ein
# Autostart-Eintrag gelöscht.

function Get-WzAutostartItems {
    <#
    .SYNOPSIS
        Alle Autostart-Einträge aus Registry, Startordnern und Aufgabenplanung.
    #>
    [CmdletBinding()]
    param()

    $items = New-Object Collections.ArrayList

    $registryLocations = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Scope = (Get-WzText 'auto.scopeAllUsers'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope = (Get-WzText 'auto.scopeAllUsers32'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = (Get-WzText 'auto.scopeThisUser'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    )

    foreach ($location in $registryLocations) {
        $path = Resolve-WzRegistryPath $location.Path
        $approvedPath = Resolve-WzRegistryPath $location.Approved
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $key = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $key) { continue }

        foreach ($name in $key.GetValueNames()) {
            if (-not $name) { continue }
            $command = $key.GetValue($name)
            [void]$items.Add([pscustomobject]@{
                Name       = $name
                Command    = [string]$command
                Publisher  = Get-WzFilePublisher -Command $command
                Source     = 'Registry'
                Scope      = $location.Scope
                Enabled    = Test-WzStartupApproved -ApprovedPath $approvedPath -Name $name
                Path       = $path
                ApprovedPath = $approvedPath
                TaskPath   = $null
            })
        }
    }

    # Startordner. Der eigene wird wie die Run-Schlüssel auf den angemeldeten
    # Anwender aufgelöst: Bei Elevierung mit einem Technikerkonto zeigte
    # GetFolderPath('Startup') sonst dessen Ordner, und das Umschalten schrieb
    # in dessen HKCU (Audit 2026-10, M5).
    # Ein umgeleiteter Startordner (Gruppenrichtlinie, Profil auf Server)
    # steht unter »User Shell Folders«; der feste Pfad ist nur der Rückfall.
    $userStartup = $null
    try {
        $shellFolders = Resolve-WzRegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        # Unaufgelöst lesen: Get-ItemProperty setzte für %USERPROFILE% das
        # Profil des laufenden Kontos ein, nicht das des Anwenders.
        $eingetragen = (Get-Item -LiteralPath $shellFolders -ErrorAction Stop).GetValue('Startup', $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($eingetragen) {
            # Der Wert liegt in HKCU und ist vom Anwender beschreibbar. Nur ein
            # lokaler Laufwerkspfad wird übernommen: Ein UNC-Pfad ließe den
            # elevierten Prozess sich mit seinen Anmeldedaten an einem
            # beliebigen Server melden. Ein umgeleiteter Ordner auf einer
            # Freigabe fällt damit auf den Standardpfad zurück.
            $kandidat = Expand-WzUserPath $eingetragen
            if ($kandidat -match '^[A-Za-z]:\\' -and $kandidat -notmatch '[\x00-\x1F]') { $userStartup = $kandidat }
        }
    } catch { }
    if (-not $userStartup) {
        $roaming = Get-WzUserFolder -Kind 'RoamingAppData'
        if ($roaming) { $userStartup = Join-Path $roaming 'Microsoft\Windows\Start Menu\Programs\Startup' }
    }
    $folders = @(
        @{ Path = $userStartup; Scope = (Get-WzText 'auto.scopeThisUser'); Approved = (Resolve-WzRegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder') }
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Scope = (Get-WzText 'auto.scopeAllUsers'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )

    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
        # -Force: Versteckte Dateien starten genauso mit — und sind der
        # naheliegende Weg, sich vor genau dieser Liste zu verbergen.
        foreach ($file in (Get-ChildItem -LiteralPath $folder.Path -File -Force -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq 'desktop.ini') { continue }
            [void]$items.Add([pscustomobject]@{
                Name       = $file.BaseName
                Command    = $file.FullName
                Publisher  = ''
                Source     = 'Startordner'
                Scope      = $folder.Scope
                Enabled    = Test-WzStartupApproved -ApprovedPath $folder.Approved -Name $file.Name
                Path       = $folder.Path
                ApprovedPath = $folder.Approved
                TaskPath   = $null
            })
        }
    }

    # Geplante Aufgaben mit Anmelde-Auslöser
    try {
        foreach ($task in (Get-ScheduledTask -ErrorAction Stop)) {
            if ($task.TaskPath -like '\Microsoft\*') { continue }
            $hasLogonTrigger = @($task.Triggers | Where-Object {
                $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -or
                $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger'
            }).Count -gt 0
            if (-not $hasLogonTrigger) { continue }

            $action = @($task.Actions | Where-Object { $_.Execute }) | Select-Object -First 1
            [void]$items.Add([pscustomobject]@{
                Name       = $task.TaskName
                Command    = if ($action) { "$($action.Execute) $($action.Arguments)".Trim() } else { '' }
                Publisher  = $task.Author
                Source     = 'Aufgabenplanung'
                Scope      = Get-WzText 'auto.scopeAllUsers'
                Enabled    = ($task.State -ne 'Disabled')
                Path       = $task.TaskPath
                ApprovedPath = $null
                TaskPath   = $task.TaskPath
            })
        }
    } catch { }

    return @($items | Sort-Object @{ Expression = 'Enabled'; Descending = $true }, Name)
}

function Test-WzStartupApproved {
    <#
    .SYNOPSIS
        Liest das Schaltbyte, mit dem Windows Autostart-Einträge ein- und
        ausschaltet. Erstes Byte gerade = aktiv, ungerade = deaktiviert.
    #>
    param([string]$ApprovedPath, [string]$Name)

    if (-not $ApprovedPath -or -not (Test-Path -LiteralPath $ApprovedPath)) { return $true }
    try {
        $value = (Get-ItemProperty -LiteralPath $ApprovedPath -Name $Name -ErrorAction Stop).$Name
        if ($null -eq $value) { return $true }
        return (($value[0] % 2) -eq 0)
    } catch {
        return $true
    }
}

function Set-WzAutostartItem {
    <#
    .SYNOPSIS
        Schaltet einen Autostart-Eintrag ein oder aus — ohne ihn zu entfernen.
    #>
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )

    $action = if ($Enabled) { Get-WzText 'auto.actionEnabled' } else { Get-WzText 'auto.actionDisabled' }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'auto.logToggleTest' @{ name = $Item.Name; aktion = $action }) -Level Test
        return $true
    }

    try {
        if ($Item.TaskPath) {
            if ($Enabled) {
                Enable-ScheduledTask -TaskPath $Item.TaskPath -TaskName $Item.Name -ErrorAction Stop | Out-Null
            } else {
                Disable-ScheduledTask -TaskPath $Item.TaskPath -TaskName $Item.Name -ErrorAction Stop | Out-Null
            }
        } else {
            # Geschrieben wird nur unter einem der drei StartupApproved-
            # Schlüssel und nur ein schlichter Wertname. Das Eintragsobjekt
            # kommt aus der Oberfläche zurück; was dort drinsteht, wird hier
            # nicht blind übernommen.
            $approvedPath = [string]$Item.ApprovedPath
            $erlaubt = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
                (Resolve-WzRegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run')
                (Resolve-WzRegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder')
            )
            if ($erlaubt -notcontains $approvedPath) {
                throw (Get-WzText 'auto.errApprovedPath' @{ pfad = $approvedPath })
            }
            if (-not (Test-Path -LiteralPath $approvedPath)) {
                [void](New-Item -Path $approvedPath -Force -ErrorAction Stop)
            }
            # Windows nutzt zwölf Byte; nur das erste entscheidet
            $bytes = if ($Enabled) {
                [byte[]]@(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            } else {
                [byte[]]@(3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            }
            $name = if ($Item.Source -eq 'Startordner') {
                [IO.Path]::GetFileName($Item.Command)
            } else {
                $Item.Name
            }
            Set-ItemProperty -LiteralPath $approvedPath -Name $name -Value $bytes -Type Binary -ErrorAction Stop
        }
        Write-WzLog (Get-WzText 'auto.logToggled' @{ name = $Item.Name; aktion = $action }) -Level Ok
        return $true
    } catch {
        Write-WzLog (Get-WzText 'auto.logToggleFailed' @{ name = $Item.Name; aktion = $action; grund = $_.Exception.Message }) -Level Warn
        return $false
    }
}

function Get-WzFilePublisher {
    <#
    .SYNOPSIS
        Herausgeber aus der Signatur oder den Dateiangaben einer Startdatei.
        Hilft, Fremdprogramme von Systembestandteilen zu unterscheiden.
    #>
    param([string]$Command)

    if (-not $Command) { return '' }
    try {
        # Pfad aus der Befehlszeile herauslösen
        $path = if ($Command -match '^"([^"]+)"') {
            $Matches[1]
        } elseif ($Command -match '^(\S+\.exe)') {
            $Matches[1]
        } else {
            $Command
        }
        $path = [Environment]::ExpandEnvironmentVariables($path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }

        $info = (Get-Item -LiteralPath $path -ErrorAction Stop).VersionInfo
        if ($info.CompanyName) { return $info.CompanyName }
        return ''
    } catch {
        return ''
    }
}
