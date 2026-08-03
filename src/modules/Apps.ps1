# Apps — Programme über winget installieren.
#
# Zwei Besonderheiten, die im Technikeralltag ständig auftreten:
#   1. winget fehlt (LTSC, ältere Windows-10-Stände, frische Installationen)
#      -> Bootstrap über das App-Installer-Paket, wenn möglich aus offline\.
#   2. winget liegt im elevierten Kontext nicht im Suchpfad
#      -> Resolve-WzWingetPath sucht zusätzlich direkt im WindowsApps-Ordner.

function Get-WzApps {
    <#
    .SYNOPSIS
        Programmkatalog, optional nach Kategorie gefiltert.
    #>
    param([string]$Category)

    $catalog = Get-WzCatalog -Name 'apps'
    if ($Category) {
        return @($catalog.apps | Where-Object { $_.category -eq $Category })
    }
    return @($catalog.apps)
}

function Get-WzAppCategories {
    $catalog = Get-WzCatalog -Name 'apps'
    return @($catalog.categories)
}

function Test-WzWinget {
    <#
    .SYNOPSIS
        Prüft, ob winget einsatzbereit ist.
    .OUTPUTS
        PSCustomObject mit Available, Path, Version
    #>
    $path = Resolve-WzWingetPath
    $result = [pscustomobject]@{ Available = $false; Path = $path; Version = $null }
    if (-not $path) { return $result }

    try {
        $version = & $path --version 2>$null
        $result.Available = $true
        $result.Version = ($version | Select-Object -First 1)
    } catch { }
    return $result
}

function Install-WzWingetBootstrap {
    <#
    .SYNOPSIS
        Installiert den App-Installer (winget) samt Abhängigkeiten.
        Bevorzugt Dateien aus offline\winget\, lädt sonst herunter.
    #>
    [CmdletBinding()]
    param()

    $catalog = Get-WzCatalog -Name 'apps'
    $bootstrap = $catalog.wingetBootstrap
    $cacheDir = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'winget')

    if ($syncHash.DryRun) {
        Write-WzLog '[Test] winget würde nachinstalliert werden.' -Level Test
        return $false
    }

    # Abhängigkeiten bevorzugt als versionsgleiches Paket aus demselben
    # GitHub-Release wie der App Installer selbst. Der Sandbox-Test hat
    # gezeigt, warum die feste Liste nicht reicht: VCLibs und UI.Xaml liefen
    # sauber durch, und dann fehlte die inzwischen zusätzlich verlangte
    # WindowsAppRuntime. Jede künftige neue Abhängigkeit würde die Liste
    # erneut veralten lassen — das Paket wächst automatisch mit.
    $dependencyFiles = @()
    if ($bootstrap.dependenciesZipUrl) {
        $zipFile = Join-Path $cacheDir 'DesktopAppInstaller_Dependencies.zip'
        if (-not (Test-Path -LiteralPath $zipFile)) {
            Write-WzLog 'Lade Abhängigkeitspaket zum App Installer...' -Level Info
            [void](Get-WzDownload -Url $bootstrap.dependenciesZipUrl -TargetPath $zipFile)
        } else {
            Write-WzLog 'Abhängigkeitspaket aus dem Zwischenspeicher auf dem Datenträger' -Level Info
        }
        if (Test-Path -LiteralPath $zipFile) {
            $extractDir = Join-Path $cacheDir 'dependencies'
            try {
                if (Test-Path -LiteralPath $extractDir) {
                    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction Stop
                }
                Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop
                $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
                    'ARM64' { 'arm64' }
                    'x86'   { 'x86' }
                    default { 'x64' }
                }
                $archDir = Get-ChildItem -Path $extractDir -Recurse -Directory |
                    Where-Object { $_.Name -eq $arch } | Select-Object -First 1
                if ($archDir) {
                    $dependencyFiles = @(Get-ChildItem -Path $archDir.FullName -Recurse -File |
                        Where-Object { $_.Extension -in @('.appx', '.msix') })
                }
            } catch {
                Write-WzLog "Abhängigkeitspaket nicht nutzbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
            }
        }
    }

    $packages = @()
    if ($dependencyFiles.Count -gt 0) {
        Write-WzLog "$($dependencyFiles.Count) Abhängigkeit(en) aus dem versionsgleichen Paket" -Level Info
        foreach ($file in $dependencyFiles) {
            $packages += [pscustomobject]@{ Name = $file.BaseName; Url = ''; File = $file.FullName }
        }
    } else {
        # Rückfall auf die feste Liste, falls das Paket nicht zu bekommen war
        foreach ($dependency in $bootstrap.dependencies) {
            $packages += [pscustomobject]@{
                Name = $dependency.name
                Url  = $dependency.url
                File = Join-Path $cacheDir "$($dependency.name).appx"
            }
        }
    }
    $packages += [pscustomobject]@{
        Name = 'App Installer'
        Url  = $bootstrap.msixbundleUrl
        File = Join-Path $cacheDir 'AppInstaller.msixbundle'
    }

    foreach ($package in $packages) {
        if (-not (Test-Path -LiteralPath $package.File)) {
            if (-not $package.Url) { continue }
            Write-WzLog "Lade $($package.Name)..." -Level Info
            if (-not (Get-WzDownload -Url $package.Url -TargetPath $package.File)) {
                Write-WzLog "$($package.Name) konnte nicht geladen werden — ohne Internet geht es hier nicht weiter." -Level Error
                return $false
            }
        } elseif ($package.Url) {
            Write-WzLog "$($package.Name) aus dem Zwischenspeicher auf dem Datenträger" -Level Info
        }

        try {
            Add-AppxPackage -Path $package.File -ErrorAction Stop
            Write-WzLog "$($package.Name) eingerichtet" -Level Ok
        } catch {
            # Bereits vorhandene oder neuere Versionen sind kein Fehler
            Write-WzLog "$($package.Name): $($_.Exception.Message)" -Level Warn
        }
    }

    $check = Test-WzWinget
    if ($check.Available) {
        Write-WzLog "winget ist einsatzbereit ($($check.Version))" -Level Ok
        return $true
    }
    Write-WzLog 'winget ist trotz Einrichtung nicht erreichbar. Nach einem Neustart erneut versuchen.' -Level Warn
    return $false
}

function Get-WzDownload {
    <#
    .SYNOPSIS
        Lädt eine Datei herunter. Nutzt den schnelleren .NET-Weg statt
        Invoke-WebRequest (dessen Fortschrittsanzeige bremst stark).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $client = New-Object Net.WebClient
        $client.Headers.Add('User-Agent', 'WinZii')
        $client.DownloadFile($Url, $TargetPath)
        $client.Dispose()
        return $true
    } catch {
        Write-WzLog "Download fehlgeschlagen: $($_.Exception.Message)" -Level Error
        if (Test-Path -LiteralPath $TargetPath) {
            Remove-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function Get-WzInstalledAppIds {
    <#
    .SYNOPSIS
        Liste der bereits über winget installierten Kennungen.
        Ein einziger Aufruf statt einer Abfrage pro Programm.
    #>
    $wingetPath = Resolve-WzWingetPath
    if (-not $wingetPath) { return @() }

    try {
        $output = & $wingetPath list --accept-source-agreements --disable-interactivity 2>$null
        return @($output)
    } catch {
        return @()
    }
}

function Install-WzApps {
    <#
    .SYNOPSIS
        Installiert die übergebenen Programme nacheinander.
        Ein Fehlschlag beendet die Reihe nicht.
    .OUTPUTS
        PSCustomObject mit Installed, Skipped, Failed, Details
    #>
    param([Parameter(Mandatory = $true)]$Apps)

    $summary = [pscustomobject]@{
        Installed = 0
        Skipped   = 0
        Failed    = 0
        Details   = @()
    }

    $wingetPath = Resolve-WzWingetPath
    if (-not $wingetPath -and -not $syncHash.DryRun) {
        Write-WzLog 'winget ist nicht verfügbar. Bitte zuerst nachinstallieren.' -Level Error
        return $summary
    }

    $index = 0
    foreach ($app in $Apps) {
        $index++
        Write-WzLog "[$index/$(@($Apps).Count)] $($app.name)" -Level Action

        if ($syncHash.DryRun) {
            Write-WzLog "  [Test] winget install --id $($app.wingetId)" -Level Test
            $summary.Skipped++
            continue
        }

        $arguments = "install --id $($app.wingetId) --exact --silent --accept-source-agreements " +
                     '--accept-package-agreements --disable-interactivity --scope machine'
        $result = Invoke-WzProcess -FilePath $wingetPath -Arguments $arguments -TimeoutSeconds 1800

        # Manche Programme lassen sich nicht systemweit installieren
        if ($result.ExitCode -ne 0 -and $result.StdOut -match 'scope|Bereich') {
            Write-WzLog '  systemweite Installation nicht möglich, versuche benutzerbezogen...' -Level Info
            $arguments = $arguments -replace ' --scope machine', ''
            $result = Invoke-WzProcess -FilePath $wingetPath -Arguments $arguments -TimeoutSeconds 1800
        }

        switch ($result.ExitCode) {
            0 {
                $summary.Installed++
                Write-WzLog "  installiert" -Level Ok
            }
            -1978335189 {
                # Bereits in aktueller Version vorhanden
                $summary.Skipped++
                Write-WzLog '  bereits installiert' -Level Info
            }
            -1978335212 {
                $summary.Failed++
                $summary.Details += "$($app.name): im Katalog von winget nicht gefunden"
                Write-WzLog '  in den winget-Quellen nicht gefunden' -Level Warn
            }
            default {
                $summary.Failed++
                $summary.Details += "$($app.name): Fehlercode $($result.ExitCode)"
                Write-WzLog "  fehlgeschlagen (Code $($result.ExitCode))" -Level Warn
            }
        }
    }

    return $summary
}

function Save-WzOfflineInstallers {
    <#
    .SYNOPSIS
        Lädt die Installationsdateien auf den Datenträger, damit sie später
        ohne Internet zur Verfügung stehen.
    #>
    param([Parameter(Mandatory = $true)]$Apps)

    $summary = [pscustomobject]@{ Saved = 0; Failed = 0; Bytes = [int64]0 }

    $wingetPath = Resolve-WzWingetPath
    if (-not $wingetPath) {
        Write-WzLog 'Ohne winget lassen sich keine Installationsdateien vorab laden.' -Level Error
        return $summary
    }

    $targetRoot = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'installers')

    foreach ($app in $Apps) {
        if ($syncHash.DryRun) {
            Write-WzLog "  [Test] $($app.name) würde auf den Datenträger geladen" -Level Test
            continue
        }

        $appDir = New-WzDirectory (Join-Path $targetRoot $app.id)
        Write-WzLog "Lade $($app.name)..." -Level Action

        $arguments = "download --id $($app.wingetId) --exact --accept-source-agreements " +
                     "--accept-package-agreements --disable-interactivity --download-directory `"$appDir`""
        $result = Invoke-WzProcess -FilePath $wingetPath -Arguments $arguments -TimeoutSeconds 1800

        if ($result.ExitCode -eq 0) {
            $size = (Get-ChildItem -LiteralPath $appDir -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $summary.Saved++
            $summary.Bytes += [int64]$size
            Write-WzLog "  gespeichert ($(Format-WzBytes $size))" -Level Ok
        } else {
            $summary.Failed++
            Write-WzLog "  fehlgeschlagen (Code $($result.ExitCode))" -Level Warn
        }
    }

    return $summary
}

function Get-WzOfflineInstallerInfo {
    <#
    .SYNOPSIS
        Was liegt bereits als Installationsdatei auf dem Datenträger?
    #>
    $root = Join-Path (Get-WzOfflineDir) 'installers'
    if (-not (Test-Path -LiteralPath $root)) {
        return [pscustomobject]@{ Count = 0; Bytes = [int64]0; Ids = @() }
    }

    $ids = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue).Count -gt 0 } |
        Select-Object -ExpandProperty Name)
    $bytes = (Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum

    return [pscustomobject]@{
        Count = $ids.Count
        Bytes = [int64]$bytes
        Ids   = $ids
    }
}
