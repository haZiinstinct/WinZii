# Uninstall — installierte Programme auflisten und entfernen.
#
# Der Blick auf einen Kundenrechner: vorinstallierte Herstellersoftware,
# abgelaufene Virenscanner-Testversionen, Werkzeugleisten. WinZii konnte
# bisher installieren, aber nichts wieder loswerden.

function Get-WzInstalledPrograms {
    <#
    .SYNOPSIS
        Alle Programme aus der Registry, wie sie auch die Systemsteuerung zeigt.
    .PARAMETER Filter
        Suchtext für Name oder Herausgeber.
    .NOTES
        Drei Zweige, weil 32-Bit-Programme unter WOW6432Node liegen und
        benutzerbezogene Installationen unter HKCU. Ausgeblendet werden
        Systembestandteile, Updates und Einträge ohne Namen — genau das, was
        auch die Systemsteuerung verbirgt.
    #>
    [CmdletBinding()]
    param([string]$Filter)

    $roots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'alle Benutzer' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'alle Benutzer (32 Bit)' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'nur dieses Konto' }
    )

    $programs = @()
    foreach ($root in $roots) {
        $entries = @()
        try { $entries = @(Get-ItemProperty -Path $root.Path -ErrorAction SilentlyContinue) } catch { }

        foreach ($entry in $entries) {
            if (-not $entry.DisplayName) { continue }
            if ($entry.SystemComponent -eq 1) { continue }
            if ($entry.ParentKeyName) { continue }
            if ($entry.ReleaseType -in @('Security Update', 'Update Rollup', 'Hotfix')) { continue }
            if (-not $entry.UninstallString -and -not $entry.QuietUninstallString) { continue }

            $sizeBytes = [int64]0
            if ($entry.EstimatedSize) { $sizeBytes = [int64]$entry.EstimatedSize * 1KB }

            $installed = $null
            if ($entry.InstallDate -and $entry.InstallDate -match '^\d{8}$') {
                try { $installed = [datetime]::ParseExact($entry.InstallDate, 'yyyyMMdd', $null) } catch { }
            }

            $quiet = [string]$entry.QuietUninstallString
            $command = if ($quiet) { $quiet } else { [string]$entry.UninstallString }
            $productCode = if ($entry.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $entry.PSChildName } else { '' }

            $programs += [pscustomobject]@{
                Name            = $entry.DisplayName.Trim()
                Version         = [string]$entry.DisplayVersion
                Publisher       = [string]$entry.Publisher
                SizeBytes       = $sizeBytes
                Installed       = $installed
                Scope           = $root.Scope
                Command         = $command
                IsQuiet         = [bool]$quiet
                ProductCode     = $productCode
                # Nur MSI und Programme mit eigenem stillen Schalter lassen sich
                # ohne Rückfragen entfernen; alles andere öffnet ein Fenster.
                CanSilent       = ([bool]$quiet -or [bool]$productCode)
                RegistryKey     = $entry.PSChildName
                # Für die Restesuche nach dem Entfernen
                InstallLocation = ([string]$entry.InstallLocation).Trim().Trim('"').TrimEnd('\')
                RegistryPath    = (($root.Path -replace '\\\*$', '') + '\' + $entry.PSChildName)
            }
        }
    }

    # Gleiche Programme stehen mitunter in mehreren Zweigen
    $programs = @($programs | Sort-Object Name, Version -Unique)

    if ($Filter) {
        $needle = $Filter.Trim()
        $programs = @($programs | Where-Object {
            $_.Name -like "*$needle*" -or $_.Publisher -like "*$needle*"
        })
    }

    return @($programs | Sort-Object Name)
}

function Uninstall-WzPrograms {
    <#
    .SYNOPSIS
        Entfernt die übergebenen Programme.
    .DESCRIPTION
        MSI-Pakete über msiexec /x /qn, Programme mit eigenem stillen Schalter
        über diesen. Alles andere öffnet den Assistenten des Herstellers —
        dann muss der Techniker durchklicken, und WinZii wartet.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Programs)

    $summary = [pscustomobject]@{
        Removed = 0
        Failed  = 0
        Details = @()
        # Die wirklich entfernten Programme — nur für die sucht sich danach
        # die Restesuche durch Ordner und Registry.
        RemovedPrograms = @()
    }

    foreach ($program in @($Programs)) {
        if ($syncHash.DryRun) {
            Write-WzLog "[Test] $($program.Name) würde entfernt" -Level Test
            $summary.Details += "$($program.Name): Testmodus"
            continue
        }

        Write-WzLog "Entferne $($program.Name)..." -Level Action
        $result = Invoke-WzUninstallCommand -Program $program

        if ($result.Success) {
            $summary.Removed++
            $summary.RemovedPrograms += $program
            $summary.Details += "$($program.Name): entfernt"
            Write-WzLog "$($program.Name) entfernt." -Level Ok
        } else {
            $summary.Failed++
            $summary.Details += "$($program.Name): $($result.Message)"
            Write-WzLog "$($program.Name): $($result.Message)" -Level Warn
        }
    }

    return $summary
}

function Invoke-WzUninstallCommand {
    <#
    .SYNOPSIS
        Führt die Deinstallation eines einzelnen Programms aus.
    #>
    param([Parameter(Mandatory = $true)]$Program)

    $result = [pscustomobject]@{ Success = $false; Message = '' }

    try {
        if ($Program.ProductCode) {
            # MSI: der zuverlässigste Weg, ganz ohne Fenster
            $process = Invoke-WzProcess -FilePath 'msiexec.exe' `
                -Arguments "/x $($Program.ProductCode) /qn /norestart" -TimeoutSeconds 900
            # 3010 heißt "erledigt, Neustart nötig", 1605 "war gar nicht installiert"
            if ($process.ExitCode -in @(0, 3010)) {
                $result.Success = $true
            } elseif ($process.ExitCode -eq 1605) {
                $result.Success = $true
                $result.Message = 'war bereits entfernt'
            } else {
                $result.Message = "msiexec meldet Code $($process.ExitCode)"
            }
            return $result
        }

        $filePath, $arguments = Split-WzCommandLine $Program.Command
        if (-not $filePath) {
            $result.Message = 'kein verwertbarer Deinstallationsbefehl hinterlegt'
            return $result
        }

        $process = Invoke-WzProcess -FilePath $filePath -Arguments $arguments -TimeoutSeconds 1800
        if ($process.TimedOut) {
            $result.Message = 'der Assistent lief in eine Zeitüberschreitung'
        } elseif ($process.ExitCode -in @(0, 3010)) {
            $result.Success = $true
        } else {
            $result.Message = "der Assistent meldet Code $($process.ExitCode)"
        }
    } catch {
        $result.Message = $_.Exception.Message.Split([char]10)[0]
    }

    return $result
}

function Split-WzCommandLine {
    <#
    .SYNOPSIS
        Zerlegt einen Registry-Deinstallationsbefehl in Programm und Argumente.
    .NOTES
        Die Einträge sind uneinheitlich: mal in Anführungszeichen, mal mit
        Leerzeichen im Pfad und ohne. Rückgabe ist ein Paar aus Pfad und
        Argumentzeile.
    #>
    param([string]$CommandLine)

    if (-not $CommandLine) { return @($null, '') }
    $line = $CommandLine.Trim()

    if ($line.StartsWith('"')) {
        $end = $line.IndexOf('"', 1)
        if ($end -gt 1) {
            return @($line.Substring(1, $end - 1), $line.Substring($end + 1).Trim())
        }
        return @($line.Trim('"'), '')
    }

    # Ohne Anführungszeichen: bis zur ersten .exe suchen, damit Pfade mit
    # Leerzeichen nicht mitten im Ordnernamen abgeschnitten werden
    if ($line -match '^(?<path>.+?\.exe)(?<rest>\s.*)?$') {
        return @($Matches['path'], $(if ($Matches['rest']) { $Matches['rest'].Trim() } else { '' }))
    }

    $parts = $line -split '\s+', 2
    return @($parts[0], $(if ($parts.Count -gt 1) { $parts[1] } else { '' }))
}

# --- Restesuche ------------------------------------------------------------
#
# Deinstallierer lassen gern etwas liegen: den Installationsordner, Einträge
# im Startmenü, eigene Registry-Schlüssel. »Restlos« heißt: nach dem Entfernen
# nachsehen und die Reste mit Ansage wegräumen.

function Get-WzLeftoverNameCandidates {
    <#
    .SYNOPSIS
        Ordner- und Schlüsselnamen, unter denen ein Programm seine Reste ablegt.
    .NOTES
        Bewusst nur der Anzeigename und eine Variante ohne Versions- und
        Klammerzusatz (»Mozilla Firefox 128.0 (x64 de)« → »Mozilla Firefox«).
        Herausgebernamen wären zu breit — unter »Google« oder »Adobe« wohnen
        mehrere Programme.
    #>
    param([Parameter(Mandatory = $true)]$Program)

    $names = @()
    $base = $Program.Name.Trim()
    if ($base) { $names += $base }

    $trimmed = ($base -replace '\s*\([^)]*\)\s*$', '' -replace '\s+v?\d[\d.]*$', '').Trim()
    if ($trimmed -and $trimmed -ne $base) { $names += $trimmed }

    # Zu kurze Namen treffen zu leicht den falschen Ordner; Zeichen, die in
    # Pfaden nichts verloren haben, fliegen gleich mit raus.
    return @($names | Where-Object { $_.Length -ge 4 -and $_ -notmatch '[\\/:*?"<>|]' })
}

function Test-WzLeftoverPathSafe {
    <#
    .SYNOPSIS
        Darf dieser Ordner überhaupt als Rest gelten?
    .NOTES
        Nur unterhalb der bekannten Programm- und Datenwurzeln, nie die Wurzel
        selbst und nie ein bekannter Sammelordner wie »Common Files« — dort
        wohnen viele Programme gleichzeitig.
    #>
    param([string]$Path)

    if (-not $Path) { return $false }
    if ($Path -notmatch '^[A-Za-z]:\\') { return $false }

    $roots = @(
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:ProgramData
        (Get-WzUserFolder -Kind 'LocalAppData')
        (Get-WzUserFolder -Kind 'RoamingAppData')
    ) | Where-Object { $_ }

    foreach ($root in $roots) {
        $prefix = $root.TrimEnd('\') + '\'
        if ($Path.Length -le $prefix.Length) { continue }
        if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }

        # Unmittelbar unter der Wurzel darf kein Sammelordner getroffen werden
        $firstSegment = ($Path.Substring($prefix.Length) -split '\\')[0]
        if ($firstSegment -in @('Common Files', 'Microsoft', 'Microsoft Shared',
            'WindowsApps', 'Packages', 'Temp', 'Windows')) {
            if ($Path.TrimEnd('\') -eq ($prefix + $firstSegment)) { return $false }
        }
        return $true
    }
    return $false
}

function Find-WzUninstallLeftovers {
    <#
    .SYNOPSIS
        Sucht nach dem Entfernen zurückgebliebene Ordner, Startmenü-Einträge
        und Registry-Schlüssel der übergebenen Programme.
    .NOTES
        Die Suche ist bewusst eng: der eingetragene Installationsordner und
        exakt nach dem Programm benannte Ordner und Schlüssel. Lieber einen
        Rest übersehen als den falschen Ordner anfassen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Programs)

    $leftovers = @()
    $seen = @{}

    $localApp = Get-WzUserFolder -Kind 'LocalAppData'
    $roamingApp = Get-WzUserFolder -Kind 'RoamingAppData'
    $startMenus = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $roamingApp 'Microsoft\Windows\Start Menu\Programs')
    )

    foreach ($program in @($Programs)) {
        $names = @(Get-WzLeftoverNameCandidates -Program $program)

        $folderCandidates = @()
        if ($program.InstallLocation) { $folderCandidates += $program.InstallLocation }
        foreach ($name in $names) {
            $folderCandidates += Join-Path $env:ProgramData $name
            $folderCandidates += Join-Path $localApp $name
            $folderCandidates += Join-Path $roamingApp $name
            foreach ($menu in $startMenus) { $folderCandidates += Join-Path $menu $name }
        }

        foreach ($folder in $folderCandidates) {
            $folder = $folder.TrimEnd('\')
            if ($seen.ContainsKey($folder.ToLowerInvariant())) { continue }
            if (-not (Test-WzLeftoverPathSafe -Path $folder)) { continue }
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            $seen[$folder.ToLowerInvariant()] = $true

            $bytes = [int64]0
            try {
                $sum = (Get-ChildItem -LiteralPath $folder -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                if ($sum) { $bytes = [int64]$sum }
            } catch { }

            $leftovers += [pscustomobject]@{
                Kind       = 'Ordner'
                Path       = $folder
                TargetPath = $folder
                SizeBytes  = $bytes
                Program    = $program.Name
            }
        }

        # Registry: der eigene Deinstallationsschlüssel und exakt benannte
        # Software-Schlüssel. Herausgeber-Wurzeln bleiben unangetastet.
        $keyCandidates = @()
        if ($program.RegistryPath) { $keyCandidates += $program.RegistryPath }
        foreach ($name in $names) {
            if ($name -in @('Microsoft', 'Windows', 'Google', 'Mozilla', 'Adobe',
                'Apple', 'Intel', 'NVIDIA', 'Oracle', 'Policies', 'Classes', 'Clients')) { continue }
            $keyCandidates += "HKLM:\SOFTWARE\$name"
            $keyCandidates += "HKLM:\SOFTWARE\WOW6432Node\$name"
            $keyCandidates += "HKCU:\Software\$name"
        }

        foreach ($key in $keyCandidates) {
            $resolved = Resolve-WzRegistryPath $key
            if ($seen.ContainsKey($resolved.ToLowerInvariant())) { continue }
            if (-not (Test-Path -LiteralPath $resolved)) { continue }
            $seen[$resolved.ToLowerInvariant()] = $true

            $leftovers += [pscustomobject]@{
                Kind       = 'Registry'
                Path       = $key
                TargetPath = $resolved
                SizeBytes  = [int64]0
                Program    = $program.Name
            }
        }
    }

    return @($leftovers)
}

function Remove-WzUninstallLeftovers {
    <#
    .SYNOPSIS
        Entfernt die gefundenen Reste.
    .DESCRIPTION
        Registry-Schlüssel werden vorher als .reg-Datei in den Sicherungsordner
        exportiert. Für Ordner gibt es keine Sicherung — das sagt der
        Bestätigungsdialog vorher deutlich.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Leftovers)

    $summary = [pscustomobject]@{
        Removed = 0
        Failed  = 0
        Bytes   = [int64]0
        Details = @()
    }

    if ($syncHash.DryRun) {
        foreach ($leftover in @($Leftovers)) {
            Write-WzLog "[Test] Rest würde entfernt: $($leftover.Path)" -Level Test
            $summary.Details += "$($leftover.Path): Testmodus"
        }
        return $summary
    }

    $session = New-WzUndoSession -Scope 'Programmreste'
    $removedPaths = New-Object Collections.ArrayList

    foreach ($leftover in @($Leftovers)) {
        try {
            if ($leftover.Kind -eq 'Registry') {
                Export-WzRegistryKey -Session $session -Path $leftover.TargetPath
                Remove-Item -LiteralPath $leftover.TargetPath -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $leftover.TargetPath -Recurse -Force -ErrorAction Stop
                $summary.Bytes += $leftover.SizeBytes
            }
            $summary.Removed++
            [void]$removedPaths.Add($leftover.Path)
            $summary.Details += "$($leftover.Path): entfernt"
            Write-WzLog "Rest entfernt: $($leftover.Path)" -Level Ok
        } catch {
            $summary.Failed++
            $message = $_.Exception.Message.Split([char]10)[0]
            $summary.Details += "$($leftover.Path): $message"
            Write-WzLog "Rest nicht entfernt: $($leftover.Path) — $message" -Level Warn
        }
    }

    if ($removedPaths.Count -gt 0) {
        # Damit die Sicherung auf der Seite »Rücknahme« auftaucht. Automatisch
        # zurückholen lässt sich davon nichts — der Hinweis sagt, was geht.
        Save-WzUndoState -Session $session -ItemId 'uninstall-leftovers' `
            -ItemName 'Programmreste entfernt' `
            -Action @{ type = 'leftoverCleanup'; undo = @{
                hint = 'Ordner sind endgültig gelöscht; entfernte Registry-Schlüssel liegen als .reg-Datei im Sicherungsordner.' } } `
            -Previous @{ paths = @($removedPaths) }
        [void](Complete-WzUndoSession -Session $session)
    }

    return $summary
}
