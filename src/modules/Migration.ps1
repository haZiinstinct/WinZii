# Migration — die Gegenstücke zu den Exporten auf der Datenseite.
#
# WinZii konnte WLAN-Netze, Lesezeichen, Drucker und Netzlaufwerke bisher nur
# herausschreiben. Nach dem Neuaufsetzen fehlte zu jedem Export das Gegenstück,
# und der Techniker tippte alles von Hand nach. Hier liegt die andere Hälfte.

function Get-WzBackupSources {
    <#
    .SYNOPSIS
        Alle Sicherungen unter offline\daten — die dieses Rechners und die
        fremder Rechner.
    .DESCRIPTION
        Bewusst auch fremde: Genau dafür ist der Stick gedacht. Der Aufrufer
        bekommt mit IsCurrent gesagt, welche vom Rechner selbst stammt, und
        warnt entsprechend.
    #>
    [CmdletBinding()]
    param()

    $root = Get-WzPath 'offline' 'daten'
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $sources = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $contents = Get-WzBackupContents -Path $dir.FullName
        if ($contents.Total -eq 0) { continue }
        $sources += [pscustomobject]@{
            Computer  = $dir.Name
            Path      = $dir.FullName
            IsCurrent = ($dir.Name -eq $env:COMPUTERNAME)
            Saved     = $dir.LastWriteTime
            Contents  = $contents
        }
    }

    return @($sources | Sort-Object -Property @{ Expression = 'IsCurrent'; Descending = $true }, Computer)
}

function Get-WzBackupContents {
    <#
    .SYNOPSIS
        Was in einer Sicherung tatsächlich liegt.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $wlanDir = Join-Path $Path 'wlan'
    $markDir = Join-Path $Path 'lesezeichen'
    $deviceFile = Join-Path $Path 'geraete.json'

    $wlan = @(Get-ChildItem -LiteralPath $wlanDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    $marks = @(Get-ChildItem -LiteralPath $markDir -File -ErrorAction SilentlyContinue)

    $printers = @()
    $drives = @()
    $devices = Read-WzJson $deviceFile
    if ($devices) {
        $printers = @($devices.drucker)
        $drives = @($devices.laufwerke)
    }

    return [pscustomobject]@{
        WlanFiles     = @($wlan | ForEach-Object { $_.FullName })
        BookmarkFiles = @($marks | ForEach-Object { $_.FullName })
        Printers      = $printers
        NetDrives     = $drives
        DeviceFile    = $(if ($devices) { $deviceFile } else { $null })
        Total         = $wlan.Count + $marks.Count + $printers.Count + $drives.Count
    }
}

function Import-WzWlanProfiles {
    <#
    .SYNOPSIS
        Spielt gesicherte WLAN-Netze über netsh zurück.
    .DESCRIPTION
        Ein Profil ohne Schlüssel wird angelegt, verbindet sich aber nicht —
        das steht im Ergebnis, damit die Rückmeldung nicht mehr verspricht als
        tatsächlich passiert ist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files)

    $applied = @()
    $failed = @()
    $withoutKey = @()

    foreach ($file in $Files) {
        # netsh benennt die Dateien "WLAN-Schnittstelle-<SSID>.xml"; im Ergebnis
        # soll die SSID stehen, nicht der Dateiname.
        $name = Get-WzWlanProfileName -Path $file
        if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($file) }

        if ($syncHash.DryRun) {
            Write-WzLog "[Test] WLAN-Netz $name würde angelegt" -Level Test
            continue
        }

        $result = Invoke-WzProcess -FilePath 'netsh.exe' `
            -Arguments "wlan add profile filename=`"$file`" user=all" -TimeoutSeconds 30
        if ($result.ExitCode -eq 0) {
            $applied += $name
            if (-not (Test-WzWlanProfileHasKey -Path $file)) { $withoutKey += $name }
        } else {
            $failed += $name
            $reason = "$($result.StdOut)$($result.StdErr)".Split([char]10)[0].Trim()
            Write-WzLog "WLAN-Netz $name nicht angelegt: $reason" -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog "$($applied.Count) WLAN-Netz(e) zurückgespielt" -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary "$($applied.Count) WLAN-Netz(e) wieder eingerichtet" -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed); WithoutKey = @($withoutKey) }
}

function Get-WzWlanProfileName {
    <#
    .SYNOPSIS
        SSID aus einer von netsh geschriebenen Profildatei.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $xml = [xml][IO.File]::ReadAllText($Path)
        return $xml.WLANProfile.SSIDConfig.SSID.name
    } catch { return $null }
}

function Test-WzWlanProfileHasKey {
    <#
    .SYNOPSIS
        Steht in der Profildatei ein Schlüssel, oder wurde ohne key=clear
        gesichert?
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $xml = [xml][IO.File]::ReadAllText($Path)
        return [bool]$xml.WLANProfile.MSM.security.sharedKey.keyMaterial
    } catch { return $false }
}

function Import-WzPrinters {
    <#
    .SYNOPSIS
        Legt gesicherte Drucker wieder an.
    .DESCRIPTION
        Ohne passenden Treiber geht nichts — Add-Printer kann keinen Treiber
        beschaffen. Fehlt er, sagt das Ergebnis genau das, statt einen nackten
        Fehlercode zu melden.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Printers)

    $applied = @()
    $failed = @()
    $missingDriver = @()

    $installed = @()
    try { $installed = @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }
    $existing = @()
    try { $existing = @(Get-Printer -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { }

    foreach ($printer in $Printers) {
        if ($existing -contains $printer.name) {
            Write-WzLog "Drucker $($printer.name) ist bereits eingerichtet — übersprungen" -Level Info
            continue
        }
        if ($installed.Count -gt 0 -and $installed -notcontains $printer.treiber) {
            $missingDriver += "$($printer.name) (Treiber »$($printer.treiber)«)"
            continue
        }

        if ($syncHash.DryRun) {
            Write-WzLog "[Test] Drucker $($printer.name) würde an $($printer.anschluss) angelegt" -Level Test
            continue
        }

        try {
            # Netzwerkdrucker hängen an einem freigegebenen Pfad, lokale an einem
            # Anschluss — Add-Printer verlangt dafür verschiedene Parameter.
            if ($printer.netzwerk -and $printer.anschluss -like '\\*') {
                Add-Printer -ConnectionName $printer.anschluss -ErrorAction Stop
            } else {
                if (-not (Get-PrinterPort -Name $printer.anschluss -ErrorAction SilentlyContinue)) {
                    Add-PrinterPort -Name $printer.anschluss -ErrorAction Stop
                }
                Add-Printer -Name $printer.name -DriverName $printer.treiber `
                    -PortName $printer.anschluss -ErrorAction Stop
            }
            $applied += $printer.name
        } catch {
            $failed += $printer.name
            Write-WzLog "Drucker $($printer.name) nicht angelegt: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog "$($applied.Count) Drucker wieder eingerichtet" -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary "$($applied.Count) Drucker wieder eingerichtet" -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed); MissingDriver = @($missingDriver) }
}

function Import-WzMappedDrives {
    <#
    .SYNOPSIS
        Verbindet gesicherte Netzlaufwerke wieder.
    .DESCRIPTION
        Ohne Anmeldedaten scheitert eine geschützte Freigabe. WinZii fragt
        bewusst keine Kennwörter ab — es meldet den Fehlschlag und überlässt die
        Anmeldung dem Explorer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Drives)

    $applied = @()
    $failed = @()

    foreach ($drive in $Drives) {
        $letter = ([string]$drive.buchstabe).TrimEnd(':')
        if (-not $letter -or -not $drive.ziel) { continue }

        if (Test-Path -LiteralPath "${letter}:") {
            Write-WzLog "Laufwerk ${letter}: ist bereits belegt — übersprungen" -Level Info
            continue
        }
        if ($syncHash.DryRun) {
            Write-WzLog "[Test] ${letter}: würde mit $($drive.ziel) verbunden" -Level Test
            continue
        }

        try {
            New-SmbMapping -LocalPath "${letter}:" -RemotePath $drive.ziel -Persistent $true -ErrorAction Stop | Out-Null
            $applied += "${letter}: auf $($drive.ziel)"
        } catch {
            $failed += "${letter}: auf $($drive.ziel)"
            Write-WzLog "Netzlaufwerk ${letter}: nicht verbunden: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog "$($applied.Count) Netzlaufwerk(e) wieder verbunden" -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary "$($applied.Count) Netzlaufwerk(e) wieder verbunden" -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed) }
}

function Get-WzBookmarkTargets {
    <#
    .SYNOPSIS
        Ordnet gesicherte Lesezeichen-Dateien den hier vorhandenen
        Browser-Profilen zu.
    .DESCRIPTION
        Export-WzBrowserBookmarks legt sie als »<Browser>-<Profil>-<Datei>« ab.
        Aus diesem Namen lässt sich das Ziel zurückrechnen; ohne passenden
        Browser bleibt Target leer und die Zeile wird als nicht zurückspielbar
        gezeigt statt stillschweigend übergangen.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files)

    $browsers = @{}
    foreach ($browser in (Get-WzBrowserProfiles)) {
        $browsers[($browser.Name -replace '[^\w]', '-')] = $browser
    }

    $targets = @()
    foreach ($file in $Files) {
        $leaf = Split-Path -Leaf $file
        $entry = [pscustomobject]@{
            Source      = $file
            BrowserName = ''
            ProfileName = ''
            Target      = ''
            Reason      = ''
        }

        $match = @($browsers.Keys | Where-Object { $leaf -like "$_-*" } |
            Sort-Object -Property Length -Descending) | Select-Object -First 1
        if (-not $match) {
            $entry.Reason = 'kein passender Browser auf diesem PC'
            $targets += $entry
            continue
        }

        $browser = $browsers[$match]
        $entry.BrowserName = $browser.Name
        $rest = $leaf.Substring($match.Length + 1)

        # Der Dateiname am Ende steht je Browserart fest, dazwischen der Profilname
        $fileName = if ($browser.Kind -eq 'chromium') { 'Bookmarks' } else { 'places.sqlite' }
        if ($rest -notlike "*-$fileName") {
            $entry.Reason = 'Dateiname passt nicht zu diesem Browser'
            $targets += $entry
            continue
        }
        $entry.ProfileName = $rest.Substring(0, $rest.Length - $fileName.Length - 1)

        $profileDir = Join-Path $browser.Path $entry.ProfileName
        if (-not (Test-Path -LiteralPath $profileDir)) {
            $entry.Reason = "Profil »$($entry.ProfileName)« gibt es auf diesem PC nicht"
            $targets += $entry
            continue
        }

        $entry.Target = Join-Path $profileDir $fileName
        $targets += $entry
    }

    return @($targets)
}

function Import-WzBrowserBookmarks {
    <#
    .SYNOPSIS
        Spielt gesicherte Lesezeichen in die passenden Browser-Profile zurück.
    .DESCRIPTION
        Überschreibt die vorhandene Datei — deshalb wird sie vorher als
        ».winzii-vorher« zur Seite gelegt. Der Browser muss geschlossen sein,
        sonst schreibt er sie beim Beenden aus dem Speicher wieder zurück.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Targets)

    $applied = @()
    $failed = @()
    $blocked = @()

    foreach ($entry in $Targets) {
        if (-not $entry.Target) { continue }

        if (Get-WzBrowserProcess -BrowserName $entry.BrowserName) {
            $blocked += "$($entry.BrowserName) läuft noch"
            continue
        }
        if ($syncHash.DryRun) {
            Write-WzLog "[Test] Lesezeichen für $($entry.BrowserName) / $($entry.ProfileName) würden zurückgespielt" -Level Test
            continue
        }

        try {
            if (Test-Path -LiteralPath $entry.Target) {
                Copy-Item -LiteralPath $entry.Target -Destination "$($entry.Target).winzii-vorher" `
                    -Force -ErrorAction Stop
            }
            Copy-Item -LiteralPath $entry.Source -Destination $entry.Target -Force -ErrorAction Stop
            $applied += "$($entry.BrowserName) / $($entry.ProfileName)"
        } catch {
            $failed += "$($entry.BrowserName) / $($entry.ProfileName)"
            Write-WzLog "Lesezeichen für $($entry.BrowserName) nicht zurückgespielt: $($_.Exception.Message.Split([char]10)[0])" -Level Warn
        }
    }

    if ($applied.Count -gt 0) {
        Write-WzLog "$($applied.Count) Lesezeichen-Datei(en) zurückgespielt" -Level Ok
        Add-WzAction -Area 'Zurückspielen' -Summary "$($applied.Count) Lesezeichen-Sammlung(en) wiederhergestellt" -Detail $applied
    }

    return [pscustomobject]@{ Applied = @($applied); Failed = @($failed); Blocked = @($blocked) }
}

function Get-WzBrowserProcess {
    <#
    .SYNOPSIS
        Läuft der Browser gerade? Solange er läuft, ist ein Zurückspielen
        wirkungslos.
    #>
    param([Parameter(Mandatory = $true)][string]$BrowserName)

    $processes = @{
        'Microsoft Edge'  = 'msedge'
        'Google Chrome'   = 'chrome'
        'Brave'           = 'brave'
        'Mozilla Firefox' = 'firefox'
    }
    if (-not $processes.ContainsKey($BrowserName)) { return $null }
    return @(Get-Process -Name $processes[$BrowserName] -ErrorAction SilentlyContinue) | Select-Object -First 1
}
