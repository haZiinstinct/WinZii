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

    # Startordner
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup'); Scope = (Get-WzText 'auto.scopeThisUser'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Scope = (Get-WzText 'auto.scopeAllUsers'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )

    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $folder.Path -File -ErrorAction SilentlyContinue)) {
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
            $approvedPath = $Item.ApprovedPath
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
