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
                Name        = $entry.DisplayName.Trim()
                Version     = [string]$entry.DisplayVersion
                Publisher   = [string]$entry.Publisher
                SizeBytes   = $sizeBytes
                Installed   = $installed
                Scope       = $root.Scope
                Command     = $command
                IsQuiet     = [bool]$quiet
                ProductCode = $productCode
                # Nur MSI und Programme mit eigenem stillen Schalter lassen sich
                # ohne Rückfragen entfernen; alles andere öffnet ein Fenster.
                CanSilent   = ([bool]$quiet -or [bool]$productCode)
                RegistryKey = $entry.PSChildName
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
