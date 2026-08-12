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

    # Der Rückgabewert MUSS geprüft werden: Native Programme werfen in
    # PowerShell keine Ausnahme. Startet nur der Alias-Stub, ohne dass das
    # Paket für dieses Konto registriert ist, kommt weder Ausgabe noch Fehler —
    # winget galt dann als »verfügbar«, die Oberfläche zeigte eine leere
    # Version, und jede folgende Installation lief ins Leere.
    try {
        $version = (& $path --version 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $version -match '\d') {
            $result.Available = $true
            $result.Version = $version
        } else {
            Write-WzLog "winget gefunden, antwortet aber nicht (Code $LASTEXITCODE): $path" -Level Warn
        }
    } catch {
        Write-WzLog "winget nicht ausführbar: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
    }
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
        # Früher stand hier eine feste Liste einzelner Adressen als Rückfall.
        # Sie half nie: Wer das Sammelpaket nicht erreicht, erreicht auch die
        # Einzeladressen nicht — beide liegen bei GitHub. Schaden konnte sie
        # dagegen, weil die fest eingetragene UI.Xaml-Fassung mit der Zeit
        # älter wird als die, die der App Installer verlangt.
        Write-WzLog 'Keine Abhängigkeiten zur Hand. Sind sie auf diesem PC bereits vorhanden, klappt es trotzdem — sonst nennt die Fehlermeldung gleich das fehlende Paket.' -Level Warn
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
            # »Schon vorhanden« und »kaputtes Paket« sahen bisher gleich aus.
            # 0x80073D06 heißt: dieselbe oder eine neuere Fassung ist da.
            $message = $_.Exception.Message.Split([char]10)[0]
            if ($message -match '0x80073D06|höhere Version|higher version|already installed') {
                Write-WzLog "$($package.Name) war bereits vorhanden" -Level Info
            } else {
                Write-WzLog "$($package.Name) ließ sich nicht einrichten: $message" -Level Error
            }
        }

        # Add-AppxPackage richtet NUR für das gerade angemeldete Konto ein —
        # bei Elevierung mit einem Technikerkonto also nicht für den Kunden.
        # Nach dem Abziehen des Sticks hätte der Kunde kein winget. Die
        # Bereitstellung sorgt dafür, dass jedes Konto es bekommt.
        if ($package.File -like '*.msixbundle') {
            try {
                Add-AppxProvisionedPackage -Online -PackagePath $package.File -SkipLicense -ErrorAction Stop | Out-Null
                Write-WzLog 'App Installer für alle Benutzer dieses PCs bereitgestellt' -Level Ok
            } catch {
                Write-WzLog "Bereitstellung für alle Benutzer nicht möglich: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
            }
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
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [int]$MinimumBytes = 4096
    )

    $client = $null
    try {
        # Verodern statt Zuweisen: Eine Zuweisung würde ein bereits aktives
        # TLS 1.3 wieder abschalten.
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $client = New-Object Net.WebClient
        $client.Headers.Add('User-Agent', 'WinZii')
        # In Firmennetzen mit anmeldepflichtigem Proxy endete der Download sonst
        # in einem 407, den niemand zuordnen konnte.
        if ($client.Proxy) { $client.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials }
        $client.DownloadFile($Url, $TargetPath)
    } catch {
        Write-WzLog "Download fehlgeschlagen: $($_.Exception.Message.Split([char]10)[0])" -Level Error
        Remove-WzFailedDownload -Path $TargetPath
        return $false
    } finally {
        if ($client) { $client.Dispose() }
    }

    # Ein Anmeldeportal antwortet mit HTTP 200 und einer HTML-Seite — ohne
    # Ausnahme. Ungeprüft landete die als »AppInstaller.msixbundle« im
    # Zwischenspeicher und blockierte jeden weiteren Versuch dauerhaft, weil
    # der Code danach nur noch Test-Path fragt.
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-WzLog 'Download beendet, aber es kam keine Datei an.' -Level Error
        return $false
    }
    $file = Get-Item -LiteralPath $TargetPath
    if ($file.Length -lt $MinimumBytes) {
        Write-WzLog "Die geladene Datei ist mit $(Format-WzBytes $file.Length) zu klein — vermutlich eine Fehlerseite statt des Pakets." -Level Error
        Remove-WzFailedDownload -Path $TargetPath
        return $false
    }
    if (Test-WzHtmlFile -Path $TargetPath) {
        Write-WzLog 'Es kam eine Webseite statt der Datei an — meist ein Anmeldeportal im WLAN.' -Level Error
        Remove-WzFailedDownload -Path $TargetPath
        return $false
    }
    return $true
}

function Remove-WzFailedDownload {
    <#
    .SYNOPSIS
        Räumt eine unbrauchbare Teildatei weg, damit der nächste Versuch neu lädt.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Test-WzHtmlFile {
    <#
    .SYNOPSIS
        Beginnt die Datei wie eine HTML-Seite? Erkennt Anmeldeportale, die eine
        Fehlerseite mit HTTP 200 ausliefern.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] 512
            $read = $stream.Read($buffer, 0, $buffer.Length)
        } finally { $stream.Close() }
        if ($read -le 0) { return $false }
        $head = [Text.Encoding]::ASCII.GetString($buffer, 0, $read).TrimStart([char]0xEF, [char]0xBB, [char]0xBF, ' ', "`t", "`r", "`n")
        return ($head -match '^(?i)<(!doctype\s+html|html|head|meta)\b')
    } catch {
        return $false
    }
}

function Get-WzWingetOutcome {
    <#
    .SYNOPSIS
        Übersetzt einen winget-Rückgabewert in Klartext und eine Wertung.
    .DESCRIPTION
        Bis dahin kannte der Code drei von rund vierzig Werten. Alles andere
        galt als Fehlschlag — auch »Neustart erforderlich«, was der normale
        Ausgang vieler MSI-Installationen ist. Deshalb meldete WinZii
        »lief nicht durch«, obwohl das Programm längst installiert war.
    .OUTPUTS
        PSCustomObject mit Outcome (ok|skip|reboot|retry|fail), Text, RequiresReboot
    #>
    param([Parameter(Mandatory = $true)][AllowNull()]$ExitCode)

    $result = [pscustomobject]@{
        Outcome        = 'fail'
        Text           = "unbekannter Rückgabewert $ExitCode"
        RequiresReboot = $false
    }
    if ($null -eq $ExitCode) {
        $result.Text = 'der Vorgang lieferte kein Ergebnis'
        return $result
    }

    try {
        $catalog = Get-WzCatalog -Name 'wingetcodes'
        $entry = @($catalog.codes | Where-Object { [int]$_.code -eq [int]$ExitCode })[0]
        if ($entry) {
            $result.Outcome = $entry.outcome
            $result.Text = $entry.text
            $result.RequiresReboot = [bool]$entry.requiresReboot
        }
    } catch {
        # Ohne Katalog bleibt die Zahl — besser als ein Absturz
    }
    return $result
}

function Test-WzAppInstalled {
    <#
    .SYNOPSIS
        Ist das Programm nach dem Lauf wirklich da?
    .DESCRIPTION
        Der Rückgabewert allein genügt nicht: Auf Geräten mit Gruppenrichtlinie
        oder gesperrtem Store meldete winget Erfolg, ohne etwas zu installieren.
        »winget list« fragt den tatsächlichen Zustand ab.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $result = Invoke-WzProcess -FilePath $WingetPath `
        -Arguments "list --id $Id --exact --accept-source-agreements --disable-interactivity" `
        -TimeoutSeconds 120
    # winget liefert 0, wenn etwas gefunden wurde, und -1978335212 wenn nicht.
    # Die Textausgabe wird bewusst nicht gelesen — sie ist übersetzt.
    return ($result.ExitCode -eq 0)
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
        Installed      = 0
        Skipped        = 0
        Failed         = 0
        Details        = @()
        # Namen der wirklich eingerichteten Programme — das Übergabeblatt trug
        # bisher alle ausgewählten ein, auch die gescheiterten.
        InstalledNames = @()
        RebootRequired = $false
    }

    $wingetPath = Resolve-WzWingetPath
    if (-not $wingetPath -and -not $syncHash.DryRun) {
        Write-WzLog 'winget ist nicht verfügbar. Bitte zuerst nachinstallieren.' -Level Error
        $summary.Details += 'winget wurde auf diesem PC nicht gefunden.'
        return $summary
    }

    # Ohne Internet scheitert jede einzelne Installation mit einer anderen,
    # nichtssagenden Meldung. Einmal vorher fragen ist ehrlicher — aber nur,
    # wenn überhaupt etwas aus dem Netz geholt werden muss. Liegt alles im
    # Vorrat auf dem Stick, ist der Netzzugang gleichgültig.
    $needsNet = @($Apps | Where-Object { -not (Get-WzOfflineInstallerPath -App $_) }).Count -gt 0
    if (-not $syncHash.DryRun -and $needsNet) {
        $net = Test-WzInternetAccess
        if ($net.Kind -ne 'ok') {
            $reason = switch ($net.Kind) {
                'portal'      { 'Das Netz verlangt eine Anmeldung im Browser (Hotel- oder Gäste-WLAN).' }
                'certificate' { 'Das Sicherheitszertifikat wird abgelehnt — meist ein Firmen-Proxy oder eine falsche Systemuhr.' }
                default       { 'Kein Internetzugang.' }
            }
            Write-WzLog "$reason ($($net.Detail))" -Level Error
            $summary.Details += $reason
            return $summary
        }
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

        # Liegt das Programm im Stick-Vorrat, wird von dort installiert — genau
        # das versprach die Oberfläche bisher, ohne dass ein Codepfad es je tat.
        # »winget install --manifest« braucht das Manifest, das »winget download«
        # neben die Installationsdatei legt.
        $vault = Get-WzOfflineInstallerPath -App $app
        if ($vault) {
            Write-WzLog '  aus dem Vorrat auf dem Datenträger' -Level Info
            $base = "install --manifest `"$vault`" --silent " +
                    '--accept-package-agreements --disable-interactivity'
        } else {
            # --source winget pinnt die Quelle: Ohne den Pin durchsucht winget auch
            # den Store, dessen Quelle unter einem frisch elevierten Konto nicht
            # eingerichtet ist und eine Rückfrage bräuchte — die --disable-interactivity
            # gerade verbietet.
            $base = "install --id $($app.wingetId) --exact --silent --source winget " +
                    '--accept-source-agreements --accept-package-agreements --disable-interactivity'
        }
        $result = Invoke-WzProcess -FilePath $wingetPath -Arguments "$base --scope machine" -TimeoutSeconds 1800
        $outcome = Get-WzWingetOutcome -ExitCode $result.ExitCode

        # Nicht jedes Programm lässt sich systemweit einrichten. Früher hing
        # dieser Rückfall an der Textausgabe ('scope|Bereich') — winget schreibt
        # dort aber »kein anwendbares Installationsprogramm«, der Rückfall griff
        # also nie. Jetzt entscheidet der Rückgabewert.
        if ($outcome.Outcome -eq 'retry') {
            Write-WzLog '  systemweit nicht möglich, versuche benutzerbezogen...' -Level Info
            $result = Invoke-WzProcess -FilePath $wingetPath -Arguments $base -TimeoutSeconds 1800
            $outcome = Get-WzWingetOutcome -ExitCode $result.ExitCode
        }

        switch ($outcome.Outcome) {
            'ok' {
                # Dem Rückgabewert allein wird nicht mehr geglaubt
                if (Test-WzAppInstalled -WingetPath $wingetPath -Id $app.wingetId) {
                    $summary.Installed++
                    $summary.InstalledNames += $app.name
                    Write-WzLog '  installiert' -Level Ok
                } else {
                    $summary.Failed++
                    $summary.Details += "$($app.name): winget meldete Erfolg, das Programm ist aber nicht auffindbar"
                    Write-WzLog '  winget meldete Erfolg — das Programm ist trotzdem nicht da' -Level Warn
                }
            }
            'reboot' {
                $summary.Installed++
                $summary.InstalledNames += $app.name
                $summary.RebootRequired = $true
                Write-WzLog "  $($outcome.Text)" -Level Ok
            }
            'skip' {
                $summary.Skipped++
                Write-WzLog "  $($outcome.Text)" -Level Info
            }
            default {
                $summary.Failed++
                $summary.Details += "$($app.name): $($outcome.Text)"
                Write-WzLog "  $($outcome.Text)" -Level Warn
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

    $summary = [pscustomobject]@{ Saved = 0; Failed = 0; Bytes = [int64]0; Details = @() }

    $wingetPath = Resolve-WzWingetPath
    if (-not $wingetPath) {
        Write-WzLog 'Ohne winget lassen sich keine Installationsdateien vorab laden.' -Level Error
        $summary.Details += 'winget wurde auf diesem PC nicht gefunden.'
        return $summary
    }

    if (-not $syncHash.DryRun -and -not (Test-WzWingetDownloadSupport -WingetPath $wingetPath)) {
        Write-WzLog 'Dieses winget kennt den Befehl »download« noch nicht — er kam erst mit Fassung 1.6.' -Level Error
        $summary.Details += 'winget ist zu alt für das Vorabladen. Über »winget einrichten« lässt sich eine neuere Fassung holen.'
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

        $arguments = "download --id $($app.wingetId) --exact --source winget --accept-source-agreements " +
                     "--accept-package-agreements --disable-interactivity --download-directory `"$appDir`""
        $result = Invoke-WzProcess -FilePath $wingetPath -Arguments $arguments -TimeoutSeconds 1800

        # Der Rückgabewert allein genügt nicht: Bei einem leeren Ordner meldete
        # WinZii früher »gespeichert (0 B)«.
        $size = [int64](Get-ChildItem -LiteralPath $appDir -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum

        if ($result.ExitCode -eq 0 -and $size -gt 0) {
            $summary.Saved++
            $summary.Bytes += $size
            Write-WzLog "  gespeichert ($(Format-WzBytes $size))" -Level Ok
        } else {
            $summary.Failed++
            $outcome = Get-WzWingetOutcome -ExitCode $result.ExitCode
            $reason = if ($result.ExitCode -eq 0) {
                'winget meldete Erfolg, es kam aber keine Datei an'
            } else {
                $outcome.Text
            }
            $summary.Details += "$($app.name): $reason"
            Write-WzLog "  $reason" -Level Warn
        }
    }

    return $summary
}

function Test-WzWingetDownloadSupport {
    <#
    .SYNOPSIS
        Beherrscht das vorhandene winget den Befehl »download«?
    .NOTES
        Es gibt ihn erst ab winget 1.6. Ältere Fassungen antworten mit einem
        Argumentfehler, den der Anwender bisher als nackte Zahl sah.
    #>
    param([Parameter(Mandatory = $true)][string]$WingetPath)

    try {
        $check = Invoke-WzProcess -FilePath $WingetPath -Arguments 'download --help' -TimeoutSeconds 60
        return ($check.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Get-WzOfflineInstallerPath {
    <#
    .SYNOPSIS
        Ordner im Stick-Vorrat für ein Programm — oder $null.
    .DESCRIPTION
        »winget download« legt neben der Installationsdatei auch das Manifest
        ab. Genau das braucht »winget install --manifest«, um ohne Internet zu
        installieren. Ohne Manifest ist der Ordner unbrauchbar.
    #>
    param([Parameter(Mandatory = $true)]$App)

    $dir = Join-Path (Join-Path (Get-WzOfflineDir) 'installers') $App.id
    if (-not (Test-Path -LiteralPath $dir)) { return $null }

    $manifest = @(Get-ChildItem -LiteralPath $dir -Filter '*.yaml' -File -ErrorAction SilentlyContinue)
    $installer = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.exe', '.msi', '.msix', '.msixbundle', '.appx', '.appxbundle', '.zip') })
    if ($manifest.Count -eq 0 -or $installer.Count -eq 0) { return $null }

    return $dir
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
