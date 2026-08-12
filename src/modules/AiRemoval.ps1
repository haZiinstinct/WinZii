# AiRemoval — KI-Bestandteile von Windows finden und entfernen.
#
# Zwei Stufen, beide über den Tweak-Katalog (Kategorie "ai"):
#   soft = per Richtlinie abschalten. Umkehrbar, überlebt Funktionsupdates
#          meist und wirkt auch vorbeugend, wenn eine Komponente noch gar
#          nicht installiert ist.
#   hard = Pakete wirklich entfernen. Nicht automatisch umkehrbar.
#
# Paketnamen ändern sich zwischen Windows-Builds, deshalb wird ausschließlich
# mit Suchmustern zur Laufzeit gearbeitet und nie mit festen Namen.

function Get-WzAiStatus {
    <#
    .SYNOPSIS
        Bestandsaufnahme aller KI-Bestandteile dieses PCs.
    .OUTPUTS
        PSCustomObject mit Packages, Capabilities, Features, Tasks und Summary.
    #>
    [CmdletBinding()]
    param()

    $status = [ordered]@{
        Packages     = @()
        Capabilities = @()
        Features     = @()
        Tasks        = @()
        Summary      = ''
    }

    $packagePatterns = @(
        'Microsoft.Copilot*', 'Microsoft.Windows.Copilot*', 'Microsoft.MicrosoftOfficeHub*Copilot*',
        '*Ai.Copilot*', '*Client.AIX*', '*Client.CoPilot*', 'MicrosoftWindows.Client.AIX*',
        'Microsoft.Windows.Ai*', 'MicrosoftWindows.Client.Recall*', '*Recall*'
    )

    try {
        foreach ($package in (Get-WzAllAppxPackages)) {
            foreach ($pattern in $packagePatterns) {
                if ($package.Name -like $pattern) {
                    $status.Packages += [pscustomobject]@{
                        Name        = $package.Name
                        FullName    = $package.PackageFullName
                        Version     = [string]$package.Version
                        NonRemovable = [bool]$package.NonRemovable
                    }
                    break
                }
            }
        }
    } catch {
        Write-WzLog "App-Pakete nicht abfragbar: $($_.Exception.Message)" -Level Warn
    }

    try {
        $status.Capabilities = @(Get-WindowsCapability -Online -ErrorAction Stop |
            Where-Object { $_.Name -match 'Recall|Copilot' -and $_.State -eq 'Installed' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; State = [string]$_.State } })
    } catch { }

    try {
        $status.Features = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop |
            Where-Object { $_.FeatureName -match 'Recall|Copilot' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.FeatureName; State = [string]$_.State } })
    } catch { }

    try {
        $status.Tasks = @(Get-ScheduledTask -ErrorAction Stop |
            Where-Object { $_.TaskName -match 'Copilot|Recall' -or $_.TaskPath -match 'Copilot|Recall|WindowsAI' } |
            ForEach-Object { [pscustomobject]@{ Path = $_.TaskPath; Name = $_.TaskName; State = [string]$_.State } })
    } catch { }

    $found = $status.Packages.Count + $status.Capabilities.Count + $status.Tasks.Count +
             @($status.Features | Where-Object { $_.State -eq 'Enabled' }).Count

    $status.Summary = if ($found -eq 0) {
        'Auf diesem PC sind keine KI-Bestandteile installiert. Die Sperren wirken vorbeugend, damit nach Funktionsupdates nichts nachrutscht.'
    } else {
        "$found KI-Bestandteil(e) gefunden: $($status.Packages.Count) App-Paket(e), $($status.Capabilities.Count) Systemfunktion(en), $($status.Tasks.Count) geplante Aufgabe(n)."
    }

    return [pscustomobject]$status
}

function Get-WzAllAppxPackages {
    <#
    .SYNOPSIS
        Alle App-Pakete aller Benutzer, zwischengespeichert.
        Die Abfrage dauert mehrere Sekunden und wird oft gebraucht.
    #>
    if ($script:WzAppxCache) { return $script:WzAppxCache }

    $packages = @()
    try {
        $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    } catch {
        # Ohne Administratorrechte geht nur das eigene Profil — das gehört
        # gesagt, sonst wirkt die Liste vollständig, obwohl sie es nicht ist.
        Write-WzLog 'App-Pakete: ohne Administratorrechte ist nur das eigene Konto sichtbar — bei anderen Benutzern kann mehr installiert sein.' -Level Warn
        try { $packages = @(Get-AppxPackage -ErrorAction Stop) } catch { }
    }
    $script:WzAppxCache = $packages
    return $packages
}

function Get-WzAppxMatches {
    <#
    .SYNOPSIS
        Findet installierte Pakete zu einer Musterliste.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Patterns)

    $found = foreach ($package in (Get-WzAllAppxPackages)) {
        foreach ($pattern in $Patterns) {
            if ($package.Name -like $pattern) {
                $package
                break
            }
        }
    }
    return @($found)
}

function Invoke-WzAppxAction {
    <#
    .SYNOPSIS
        Entfernt App-Pakete nach Mustern, samt Bereitstellung für neue Benutzer.
    #>
    param($Action, $Session, $Tweak)

    $found = Get-WzAppxMatches -Patterns $Action.patterns
    $provisioned = @()
    if ($Action.removeProvisioned) {
        try {
            $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
                $name = $_.DisplayName
                @($Action.patterns | Where-Object { $name -like $_ }).Count -gt 0
            })
        } catch { }
    }

    if ($found.Count -eq 0 -and $provisioned.Count -eq 0) {
        Write-WzLog "  keine passenden Pakete installiert ($($Action.patterns -join ', '))" -Level Info
        return
    }

    if ($syncHash.DryRun) {
        foreach ($package in $found) { Write-WzLog "  [Test] App entfernen: $($package.Name)" -Level Test }
        foreach ($package in $provisioned) { Write-WzLog "  [Test] Bereitstellung entfernen: $($package.DisplayName)" -Level Test }
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        packages = @($found | ForEach-Object { $_.PackageFullName })
        note     = 'App-Pakete lassen sich nur über den Microsoft Store neu installieren'
    }

    foreach ($package in $found) {
        try {
            if ($package.NonRemovable -and $Action.forceNonRemovable) {
                Set-WzAppxEndOfLife -PackageFullName $package.PackageFullName
            }
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            Write-WzLog "  entfernt: $($package.Name)" -Level Ok
        } catch {
            # Der Fehler wird hier abgefangen, damit die Reihe weiterläuft —
            # aber er muss zurückgemeldet werden, sonst zählt der Eintrag als
            # erledigt, obwohl nichts entfernt wurde.
            if ($Session) { $Session.ActionFailed = $true }
            Write-WzLog "  konnte nicht entfernt werden: $($package.Name) — $($_.Exception.Message)" -Level Warn
        }
    }

    foreach ($package in $provisioned) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            Write-WzLog "  Bereitstellung entfernt: $($package.DisplayName)" -Level Ok
        } catch {
            Write-WzLog "  Bereitstellung blieb bestehen: $($package.DisplayName)" -Level Warn
        }
    }

    $script:WzAppxCache = $null
}

function Set-WzAppxEndOfLife {
    <#
    .SYNOPSIS
        Markiert ein als "nicht entfernbar" gekennzeichnetes Paket als abgelaufen.
        Erst danach lässt es sich deinstallieren.
    .NOTES
        Technik aus zoicware/RemoveWindowsAI. Nur für Einträge mit hohem Risiko.
    #>
    param([Parameter(Mandatory = $true)][string]$PackageFullName)

    $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$PackageFullName"
    try {
        if (-not (Test-Path -LiteralPath $path)) { [void](New-Item -Path $path -Force -ErrorAction Stop) }
        Set-ItemProperty -Path $path -Name 'EndOfLife' -Value 1 -Type DWord -ErrorAction Stop
        Write-WzLog "  Paket als abgelaufen markiert: $PackageFullName" -Level Info
    } catch {
        Write-WzLog "  Markierung fehlgeschlagen: $($_.Exception.Message)" -Level Warn
    }
}

function Invoke-WzCbsAction {
    <#
    .SYNOPSIS
        Entfernt Systempakete (Component Based Servicing) nach Mustern.
        Das ist der tiefste Eingriff und lässt sich nur über ein
        Funktionsupdate oder eine Neuinstallation rückgängig machen.
    #>
    param($Action, $Session, $Tweak)

    $packages = @()
    try {
        $packages = @(Get-WindowsPackage -Online -ErrorAction Stop | Where-Object {
            $name = $_.PackageName
            @($Action.patterns | Where-Object { $name -like $_ }).Count -gt 0
        })
    } catch {
        Write-WzLog "  Systempakete nicht abfragbar: $($_.Exception.Message)" -Level Warn
        return
    }

    if ($packages.Count -eq 0) {
        Write-WzLog "  keine passenden Systempakete vorhanden" -Level Info
        return
    }

    if ($syncHash.DryRun) {
        foreach ($package in $packages) { Write-WzLog "  [Test] Systempaket entfernen: $($package.PackageName)" -Level Test }
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        packages = @($packages | ForEach-Object { $_.PackageName })
        note     = 'Systempakete kommen nur über ein Funktionsupdate zurück'
    }

    foreach ($package in $packages) {
        try {
            Remove-WindowsPackage -Online -PackageName $package.PackageName -NoRestart -ErrorAction Stop | Out-Null
            Write-WzLog "  Systempaket entfernt: $($package.PackageName)" -Level Ok
        } catch {
            if ($Session) { $Session.ActionFailed = $true }
            Write-WzLog "  Systempaket blieb bestehen: $($package.PackageName)" -Level Warn
        }
    }
}

function Invoke-WzCapabilityAction {
    <#
    .SYNOPSIS
        Entfernt optionale Systemfunktionen (z. B. Recall).
    #>
    param($Action, $Session, $Tweak)

    $capabilities = @()
    try {
        $capabilities = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object {
            $name = $_.Name
            $_.State -eq 'Installed' -and @($Action.patterns | Where-Object { $name -like $_ }).Count -gt 0
        })
    } catch {
        Write-WzLog "  Systemfunktionen nicht abfragbar: $($_.Exception.Message)" -Level Warn
        return
    }

    if ($capabilities.Count -eq 0) {
        Write-WzLog '  keine passende Systemfunktion installiert' -Level Info
        return
    }

    if ($syncHash.DryRun) {
        foreach ($capability in $capabilities) { Write-WzLog "  [Test] Funktion entfernen: $($capability.Name)" -Level Test }
        return
    }

    Save-WzUndoState -Session $Session -ItemId $Tweak.id -ItemName $Tweak.name -Action $Action -Previous @{
        capabilities = @($capabilities | ForEach-Object { $_.Name })
        note         = 'Über Einstellungen > Optionale Features wieder installierbar'
    }

    foreach ($capability in $capabilities) {
        try {
            Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
            Write-WzLog "  Funktion entfernt: $($capability.Name)" -Level Ok
        } catch {
            if ($Session) { $Session.ActionFailed = $true }
            Write-WzLog "  Funktion blieb bestehen: $($capability.Name)" -Level Warn
        }
    }
}
