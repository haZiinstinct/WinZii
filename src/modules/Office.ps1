# Office — Installation über das Office Deployment Tool (ODT).
#
# Ablauf:
#   1. configuration.xml aus der Auswahl erzeugen
#   2. setup.exe von Microsoft holen (einmalig, bleibt auf dem Datenträger)
#   3. Entweder /download (Installationsdateien auf den Datenträger)
#      oder /configure (sofort installieren, auf Wunsch aus dem Zwischenspeicher)
#
# Achtung FAT32: Die Office-Pakete überschreiten die 4-GB-Dateigrenze.
# Deshalb wird das Dateisystem vor dem Herunterladen geprüft.

function Get-WzOfficeCatalog { Get-WzCatalog -Name 'office' }

function New-WzOfficeConfigXml {
    <#
    .SYNOPSIS
        Erzeugt die configuration.xml für das Office Deployment Tool.
    .PARAMETER VariantId
        m365, office2024 oder office2021.
    .PARAMETER Language
        Sprachkennung, z. B. de-de.
    .PARAMETER IncludedApps
        Kennungen der gewünschten Programme. Alles andere wird ausgeschlossen.
    .PARAMETER SourcePath
        Ordner mit bereits geladenen Installationsdateien (Offline-Installation).
    .OUTPUTS
        Pfad zur geschriebenen XML-Datei.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VariantId,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string[]]$IncludedApps,
        [string]$SourcePath,
        [string]$ProductKey,
        [ValidateSet('32', '64')][string]$Edition = '64'
    )

    $catalog = Get-WzOfficeCatalog
    $variant = $catalog.variants | Where-Object { $_.id -eq $VariantId } | Select-Object -First 1
    if (-not $variant) { throw "Unbekannte Office-Variante: $VariantId" }

    $excluded = @($catalog.apps | Where-Object { $_.id -notin $IncludedApps } | ForEach-Object { $_.id })

    $lines = New-Object Collections.ArrayList
    [void]$lines.Add('<Configuration>')

    # Alles maskieren, was in die XML wandert: Ein & im Stickpfad erzeugte
    # bisher eine Datei, die ODT nicht lesen konnte — mit einer Fehlermeldung,
    # die auf alles Mögliche hindeutete, nur nicht auf den Pfad.
    $addAttributes = "OfficeClientEdition=`"$Edition`" Channel=`"$(ConvertTo-WzXmlText $variant.channel)`""
    if ($SourcePath) {
        $addAttributes += " SourcePath=`"$(ConvertTo-WzXmlText $SourcePath)`""
        # Ohne diese Sperre lädt ODT bei Lücken im Vorrat still aus dem Netz
        # nach — obwohl der Anwender »kein Internet nötig« gelesen hat.
        $addAttributes += ' AllowCdnFallback="False"'
    }
    [void]$lines.Add("  <Add $addAttributes>")
    [void]$lines.Add("    <Product ID=`"$(ConvertTo-WzXmlText $variant.productId)`">")
    [void]$lines.Add("      <Language ID=`"$(ConvertTo-WzXmlText $Language)`" />")
    foreach ($app in $excluded) {
        [void]$lines.Add("      <ExcludeApp ID=`"$(ConvertTo-WzXmlText $app)`" />")
    }
    [void]$lines.Add('    </Product>')
    [void]$lines.Add('  </Add>')

    [void]$lines.Add('  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />')
    [void]$lines.Add('  <Property Name="AUTOACTIVATE" Value="1" />')
    [void]$lines.Add('  <Property Name="SharedComputerLicensing" Value="0" />')
    [void]$lines.Add('  <Updates Enabled="TRUE" />')
    [void]$lines.Add('  <RemoveMSI />')
    # Level="None" statt "Full": Bei einem Fehler blieb sonst ein Office-Dialog
    # stehen und wartete auf einen Klick, während WinZii bis zum Zeitlimit
    # gesperrt war. AcceptEULA wirkt laut Microsoft ohnehin nur bei None.
    [void]$lines.Add('  <Display Level="None" AcceptEULA="TRUE" />')
    # Ohne Logging schreibt ODT seine Fehlernummern nach %TEMP% des elevierten
    # Kontos — unauffindbar. Auf dem Datenträger sind sie auswertbar.
    [void]$lines.Add("  <Logging Level=`"Standard`" Path=`"$(ConvertTo-WzXmlText (Get-WzOfficeLogDir))`" />")
    [void]$lines.Add('</Configuration>')

    $workDir = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'odt')
    $outFile = Join-Path $workDir "configuration-$VariantId-$Language.xml"

    # Der Lizenzschlüssel gehört NICHT in die Datei auf dem Stick: Sie bleibt
    # dort liegen. Er wird nach dem Schreiben eingesetzt und die Datei
    # anschließend wieder bereinigt (siehe Invoke-WzOfficeInstall).
    if ($ProductKey) {
        $marker = "      <PIDKEY Value=`"$(ConvertTo-WzXmlText $ProductKey)`" />"
        $index = $lines.IndexOf("      <Language ID=`"$(ConvertTo-WzXmlText $Language)`" />")
        if ($index -ge 0) { [void]$lines.Insert($index, $marker) }
    }

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($outFile, ($lines -join [Environment]::NewLine), $utf8NoBom)
    return $outFile
}

function ConvertTo-WzXmlText {
    <#
    .SYNOPSIS
        Maskiert einen Wert für ein XML-Attribut.
    #>
    param([AllowNull()][string]$Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function Get-WzOfficeLogDir {
    <#
    .SYNOPSIS
        Ablage für die Protokolle des Bereitstellungswerkzeugs.
    #>
    New-WzDirectory (Join-Path (Get-WzOfflineDir) 'odt\logs')
}

function Get-WzOdtLogVerdict {
    <#
    .SYNOPSIS
        Liest die zuletzt geschriebenen ODT-Protokolle und sucht nach echten
        Fehlern.
    .DESCRIPTION
        Das Bereitstellungswerkzeug liefert notorisch den Rückgabewert 0, auch
        wenn die Installation abgebrochen ist — die Wahrheit steht nur im Log.
        Genau deshalb meldete WinZii »Office wurde installiert«, ohne dass
        Office da war.

        Gesucht wird nach den Fehlernummern der Bauart 30015-1039, nicht nach
        übersetztem Text: Die Nummern sind sprachunabhängig.
    .OUTPUTS
        PSCustomObject mit HasError, Codes, LogFile
    #>
    [CmdletBinding()]
    param([datetime]$Since = ([datetime]::Now.AddHours(-3)))

    $result = [pscustomobject]@{ HasError = $false; Codes = @(); LogFile = $null }
    $dir = Get-WzOfficeLogDir
    if (-not (Test-Path -LiteralPath $dir)) { return $result }

    $log = @(Get-ChildItem -LiteralPath $dir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since } |
        Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1)
    if ($log.Count -eq 0) { return $result }

    $result.LogFile = $log[0].FullName
    try {
        $text = [IO.File]::ReadAllText($log[0].FullName)
    } catch {
        return $result
    }

    # ODT-Fehlernummern: fünf Ziffern, Bindestrich, vier Ziffern
    $codes = @([regex]::Matches($text, '\b(30\d{3}-\d{4})\b') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($codes.Count -gt 0) {
        $result.HasError = $true
        $result.Codes = $codes
    }
    return $result
}

function Test-WzOfficeTarget {
    <#
    .SYNOPSIS
        Taugt der Datenträger für die Office-Dateien?
    .NOTES
        Seite und Modul prüften dasselbe mit zwei verschiedenen Wortlauten.
        Jetzt steht der Satz an einer Stelle.
    .OUTPUTS
        PSCustomObject mit Ok, Message, Volume
    #>
    [CmdletBinding()]
    param()

    $volume = Get-WzVolumeInfo
    $result = [pscustomobject]@{ Ok = $true; Message = ''; Volume = $volume }
    if ($volume.IsFat32) {
        $result.Ok = $false
        $result.Message = Get-WzText 'off.fat32Message'
    }
    return $result
}

function Get-WzOdtSetup {
    <#
    .SYNOPSIS
        Liefert den Pfad zu setup.exe des Office Deployment Tools.
        Beim ersten Mal wird es von Microsoft geladen und bleibt danach
        auf dem Datenträger.
    #>
    [CmdletBinding()]
    param()

    $odtDir = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'odt')
    $setupPath = Join-Path $odtDir 'setup.exe'

    # Eine abgebrochene oder abgefangene Übertragung hinterließ hier bisher eine
    # Datei, die für immer wiederverwendet wurde — setup.exe ist rund 7 MB groß.
    if (Test-Path -LiteralPath $setupPath) {
        if ((Get-Item -LiteralPath $setupPath).Length -gt 1MB) { return $setupPath }
        Write-WzLog (Get-WzText 'off.logSetupTooSmall') -Level Warn
        try { Remove-Item -LiteralPath $setupPath -Force -ErrorAction Stop } catch { }
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'off.logOdtTest') -Level Test
        return $null
    }

    $catalog = Get-WzOfficeCatalog
    Write-WzLog (Get-WzText 'off.logOdtDownload') -Level Action
    if (Get-WzDownload -Url $catalog.odtSetupUrl -TargetPath $setupPath) {
        Write-WzLog (Get-WzText 'off.logOdtReady') -Level Ok
        return $setupPath
    }
    return $null
}

function Get-WzOfficeCachePath {
    <#
    .SYNOPSIS
        Ablageort der heruntergeladenen Office-Dateien für eine Variante.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VariantId,
        [Parameter(Mandatory = $true)][string]$Language
    )
    return Join-Path (Get-WzOfflineDir) "office\$VariantId-$Language"
}

function Test-WzOfficeCache {
    <#
    .SYNOPSIS
        Prüft, ob für eine Variante bereits Installationsdateien vorliegen.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VariantId,
        [Parameter(Mandatory = $true)][string]$Language
    )

    $path = Get-WzOfficeCachePath -VariantId $VariantId -Language $Language
    $result = [pscustomobject]@{ Available = $false; Path = $path; Bytes = [int64]0; Detail = '' }
    if (-not (Test-Path -LiteralPath $path)) {
        $result.Detail = 'noch nichts geladen'
        return $result
    }

    $bytes = (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $result.Bytes = [int64]$bytes

    # Reihenfolge der Prüfungen entspricht der Reihenfolge, in der ODT die
    # Dateien anlegt — von »gleich zu Beginn da« bis »kommt zum Schluss«.
    $dataDir = Join-Path $path 'Office\Data'
    if (-not (Test-Path -LiteralPath $dataDir)) {
        $result.Detail = Get-WzText 'off.cacheNoData'
        return $result
    }
    $cab = @(Get-ChildItem -LiteralPath $dataDir -Filter 'v*.cab' -File -ErrorAction SilentlyContinue)
    if ($cab.Count -eq 0) {
        $result.Detail = Get-WzText 'off.cacheNoCatalog'
        return $result
    }

    # Bis hierher reichte die Prüfung bis 0.4.1 — und das war zu wenig. Im
    # Abnahmelauf wurde ein Download nach 75 Sekunden abgebrochen: Katalogdatei
    # und Paket-Cabs lagen längst da, `stream.x64.x-none.dat` hatte 0 Byte, und
    # WinZii meldete 39 MB als »vollständig«. Beim Kunden ohne Netz ist das die
    # Installation, die nicht startet.
    #
    # Die Masse steckt in den stream-Dateien: die neutrale mit rund 1,9 GB und
    # die der Sprache mit einigen hundert MB. Beide wachsen bis zuletzt, also
    # werden sie geprüft. Feste Untergrenzen bleiben eine Schätzung — sie sind
    # bewusst so niedrig gewählt, dass ein vollständiger Satz sie nie reißt.
    # Falsch abgelehnt heißt: noch einmal laden. Falsch angenommen heißt: beim
    # Kunden stehen.
    $streams = @(Get-ChildItem -LiteralPath $dataDir -Recurse -Filter 'stream.*.dat' -File -ErrorAction SilentlyContinue)
    $neutral = @($streams | Where-Object { $_.Name -like '*x-none*' })
    $inSprache = @($streams | Where-Object { $_.Name -like "*$Language*" })

    if ($neutral.Count -eq 0) {
        $result.Detail = Get-WzText 'off.cacheNoProgram'
        return $result
    }
    if (($neutral | Measure-Object -Property Length -Maximum).Maximum -lt 1GB) {
        $result.Detail = Get-WzText 'off.cacheProgramStarted'
        return $result
    }
    if ($inSprache.Count -eq 0 -or ($inSprache | Measure-Object -Property Length -Maximum).Maximum -lt 50MB) {
        $result.Detail = Get-WzText 'off.cacheNoLanguage' @{ sprache = $Language }
        return $result
    }
    if ($result.Bytes -lt 2GB) {
        $result.Detail = Get-WzText 'off.cacheTooSmall'
        return $result
    }

    $result.Available = $true
    $result.Detail = Get-WzText 'off.cacheComplete'
    return $result
}

function Invoke-WzOfficeDownload {
    <#
    .SYNOPSIS
        Lädt die Office-Installationsdateien auf den Datenträger.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VariantId,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string[]]$IncludedApps
    )

    $target = Test-WzOfficeTarget
    if (-not $target.Ok) {
        Write-WzLog $target.Message -Level Error
        return $false
    }
    $volume = $target.Volume
    if ($volume.FreeBytes -gt 0 -and $volume.FreeBytes -lt 6GB) {
        Write-WzLog (Get-WzText 'off.logLittleSpace' @{ frei = (Format-WzBytes $volume.FreeBytes) }) -Level Warn
    }

    $setup = Get-WzOdtSetup
    if (-not $setup) { return $false }

    $cachePath = New-WzDirectory (Get-WzOfficeCachePath -VariantId $VariantId -Language $Language)
    $configFile = New-WzOfficeConfigXml -VariantId $VariantId -Language $Language `
        -IncludedApps $IncludedApps -SourcePath $cachePath

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] setup.exe /download `"$configFile`"" -Level Test
        return $true
    }

    Write-WzLog (Get-WzText 'off.logDownloading') -Level Action
    $started = Get-Date
    # -KillOnCancel: Ein reiner Download darf mitten im Wort abgebrochen werden.
    # Das Bereitstellungswerkzeug setzt beim nächsten Lauf auf dem Vorhandenen
    # auf, und Test-WzOfficeCache erkennt einen unvollständigen Vorrat ohnehin.
    $result = Invoke-WzProcess -FilePath $setup -Arguments "/download `"$configFile`"" `
        -WorkingDirectory (Split-Path -Parent $configFile) -TimeoutSeconds 7200 -KillOnCancel

    # Dem Rückgabewert allein wird nicht mehr geglaubt: Das Ergebnis muss
    # vollständig sein, sonst hilft es beim Kunden ohne Netz gar nichts.
    $cache = Test-WzOfficeCache -VariantId $VariantId -Language $Language
    $log = Get-WzOdtLogVerdict -Since $started

    if ($result.TimedOut) {
        Write-WzLog (Get-WzText 'off.logDownloadTimeout') -Level Error
        return $false
    }
    if ($result.Canceled) {
        # Ein Abbruch ist kein Fehlschlag, und er ist auch kein sofortiges Ende:
        # setup.exe ist nur die Vorderseite, geladen wird vom Click-to-Run-Dienst
        # von Windows. Der lässt sich nicht mitbeenden. Im Abnahmelauf wuchs der
        # Ordner nach dem Abbruch von 39 MB auf 2,5 GB weiter. Das gehört gesagt,
        # sonst wundert sich der Techniker über den vollen Datenträger.
        Write-WzLog (Get-WzText 'off.logDownloadCancelled') -Level Warn
        Write-WzLog (Get-WzText 'off.logClickToRunKeeps' @{ pfad = $cachePath }) -Level Info
        return $false
    }
    if ($result.ExitCode -eq 0 -and $cache.Available) {
        Write-WzLog (Get-WzText 'off.logDownloadOk' @{ groesse = (Format-WzBytes $cache.Bytes) }) -Level Ok
        return $true
    }
    if ($result.ExitCode -eq 0) {
        # Früher wurde hier »Office liegt jetzt auf dem Datenträger (0 B)«
        # gemeldet — der Cache wurde berechnet, aber nie abgefragt.
        Write-WzLog (Get-WzText 'off.logDownloadIncomplete' @{ grund = $cache.Detail; groesse = (Format-WzBytes $cache.Bytes) }) -Level Error
    } else {
        Write-WzLog (Get-WzText 'off.logDownloadFailed' @{ code = $result.ExitCode }) -Level Error
    }
    if ($log.HasError) {
        Write-WzLog (Get-WzText 'off.logOdtCodes' @{ codes = ($log.Codes -join ', '); pfad = $log.LogFile }) -Level Error
    }
    return $false
}

function Invoke-WzOfficeInstall {
    <#
    .SYNOPSIS
        Installiert Office. Wenn Installationsdateien auf dem Datenträger
        liegen, werden sie genutzt — dann geht es auch ohne Internet.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VariantId,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string[]]$IncludedApps,
        [string]$ProductKey,
        [ValidateSet('32', '64')][string]$Edition = '64'
    )

    $setup = Get-WzOdtSetup
    if (-not $setup) { return $false }

    # Auf dem Systemlaufwerk braucht Office rund 4 GB. Bisher wurde nur der
    # Platz auf dem Stick geprüft — der ist beim Installieren gleichgültig.
    try {
        $system = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
        if ([int64]$system.FreeSpace -lt 5GB) {
            Write-WzLog (Get-WzText 'off.logSystemSpace' @{ laufwerk = $env:SystemDrive; frei = (Format-WzBytes ([int64]$system.FreeSpace)) }) -Level Warn
        }
    } catch { }

    $cache = Test-WzOfficeCache -VariantId $VariantId -Language $Language
    $sourcePath = if ($cache.Available) { $cache.Path } else { $null }

    if ($sourcePath) {
        Write-WzLog (Get-WzText 'off.logInstallFromDrive' @{ groesse = (Format-WzBytes $cache.Bytes) }) -Level Info
    } elseif ($cache.Bytes -gt 0) {
        Write-WzLog (Get-WzText 'off.logCacheIncomplete' @{ grund = $cache.Detail }) -Level Warn
    } else {
        Write-WzLog (Get-WzText 'off.logNoCache') -Level Info
    }

    $configFile = New-WzOfficeConfigXml -VariantId $VariantId -Language $Language `
        -IncludedApps $IncludedApps -SourcePath $sourcePath -ProductKey $ProductKey -Edition $Edition

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] setup.exe /configure `"$configFile`"" -Level Test
        if ($ProductKey) { Remove-WzOfficeKeyFromConfig -Path $configFile }
        return $false
    }

    Write-WzLog (Get-WzText 'off.logInstalling') -Level Action
    $started = Get-Date
    try {
        $result = Invoke-WzProcess -FilePath $setup -Arguments "/configure `"$configFile`"" `
            -WorkingDirectory (Split-Path -Parent $configFile) -TimeoutSeconds 7200
    } finally {
        # Der Lizenzschlüssel darf nicht auf dem Stick liegen bleiben
        if ($ProductKey) { Remove-WzOfficeKeyFromConfig -Path $configFile }
    }

    if ($result.TimedOut) {
        Write-WzLog (Get-WzText 'off.logInstallTimeout') -Level Error
        return $false
    }

    # Der Rückgabewert allein genügt nicht: Das Bereitstellungswerkzeug liefert
    # notorisch 0, auch wenn nichts installiert wurde, und schreibt die Wahrheit
    # nur ins Protokoll. Genau deshalb meldete WinZii Erfolg ohne Wirkung.
    $log = Get-WzOdtLogVerdict -Since $started
    $installed = Get-WzInstalledOffice
    $reallyThere = ($installed -and $installed.Installed)

    if ($result.ExitCode -eq 0 -and $reallyThere -and -not $log.HasError) {
        Write-WzLog (Get-WzText 'off.logInstalledOk' @{ name = $installed.Name }) -Level Ok
        return $true
    }

    if ($result.ExitCode -ne 0) {
        Write-WzLog (Get-WzText 'off.logInstallFailed' @{ code = $result.ExitCode }) -Level Error
    } elseif (-not $reallyThere) {
        Write-WzLog (Get-WzText 'off.logInstallNotFound') -Level Error
    }
    if ($log.HasError) {
        Write-WzLog (Get-WzText 'off.logOdtCodes' @{ codes = ($log.Codes -join ', '); pfad = $log.LogFile }) -Level Error
    }
    return $false
}

function Remove-WzOfficeKeyFromConfig {
    <#
    .SYNOPSIS
        Entfernt den Lizenzschlüssel wieder aus der Konfigurationsdatei.
    .NOTES
        Die Datei bleibt auf dem Datenträger liegen und reist mit zum nächsten
        Kunden. Ein fremder Volumenlizenz-Schlüssel hat darauf nichts zu suchen.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $text = [IO.File]::ReadAllText($Path)
        $clean = [regex]::Replace($text, '(?m)^\s*<PIDKEY[^>]*/>\s*\r?\n', '')
        [IO.File]::WriteAllText($Path, $clean, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Get-WzOfficeChannelName {
    <#
    .SYNOPSIS
        Übersetzt die Kanal-GUID aus der Registry in einen lesbaren Namen.
    #>
    param([AllowNull()][string]$CdnBaseUrl)

    if (-not $CdnBaseUrl) { return Get-WzText 'off.channelUnknown' }
    $guid = ($CdnBaseUrl -replace '.*/', '')
    $names = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = (Get-WzText 'off.channelCurrent')
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = (Get-WzText 'off.channelSemiAnnual')
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = (Get-WzText 'off.channelCurrentPreview')
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = (Get-WzText 'off.channelMonthlyEnterprise')
        '5030841d-c919-4594-8d2d-84ae4f96e58e' = (Get-WzText 'off.channelSemiAnnualPreview')
        '2e148de9-61c8-4051-b103-4af54baffbb4' = (Get-WzText 'off.channelBeta')
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'LTSC 2019'
        '5462eee5-1e97-495b-9370-853cd873bb07' = 'LTSC 2021'
        '7983bac0-e531-40cf-be00-fd24fe66619c' = 'LTSC 2024'
    }
    if ($names.ContainsKey($guid)) { return $names[$guid] }
    return 'Kanal unbekannt'
}

function Get-WzOfficeRemnants {
    <#
    .SYNOPSIS
        Was von Office bleibt, wenn das Bereitstellungswerkzeug fertig ist.
    .DESCRIPTION
        Nur lesen und aufzählen — entfernt wird erst in Stufe 2, und auch dann
        nur, was hier gefunden wurde. So sieht der Techniker vorher, worauf er
        sich einlässt.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ StoreApps = @(); Folders = @(); Items = @() }

    # Die Store-Fassung von Office kennt das Bereitstellungswerkzeug nicht
    try {
        $result.StoreApps = @(Get-AppxPackage -AllUsers -ErrorAction Stop |
            Where-Object { $_.Name -like 'Microsoft.Office.Desktop*' -or $_.Name -eq 'Microsoft.MicrosoftOfficeHub' })
    } catch { }

    foreach ($folder in @(
        (Join-Path $env:ProgramFiles 'Microsoft Office'),
        (Join-Path $env:ProgramFiles 'Microsoft Office 15'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office'),
        (Join-Path $env:ProgramData 'Microsoft\ClickToRun')
    )) {
        if ($folder -and (Test-Path -LiteralPath $folder)) { $result.Folders += $folder }
    }

    foreach ($app in $result.StoreApps) { $result.Items += "Store-Fassung: $($app.Name)" }
    foreach ($folder in $result.Folders) { $result.Items += "Ordner: $folder" }
    return $result
}

function Remove-WzOffice {
    <#
    .SYNOPSIS
        Entfernt Office — gestuft.
    .DESCRIPTION
        Stufe 1 (sanft): über dasselbe Bereitstellungswerkzeug, das auch
        installiert, mit <Remove All="TRUE" />. Das erfasst Click-to-Run und
        über <RemoveMSI /> auch ältere MSI-Installationen. Umkehrbar durch eine
        neue Installation.

        Stufe 2 (gründlich): zusätzlich die Store-Fassung und die Ordnerreste,
        die das Werkzeug stehen lässt. Nicht umkehrbar — der Aufrufer muss das
        ausdrücklich bestätigt haben.

        Gedacht vor allem für den Fall, der die Installation sonst blockiert:
        ein vorinstalliertes OEM-Office in der falschen Bitness.
    .OUTPUTS
        PSCustomObject mit Ok, Steps, Details
    #>
    [CmdletBinding()]
    param([switch]$Thorough)

    $summary = [pscustomobject]@{ Ok = $false; Steps = @(); Details = @() }

    $before = Get-WzInstalledOffice
    $remnants = Get-WzOfficeRemnants
    if (-not $before.Installed -and $remnants.Items.Count -eq 0) {
        $summary.Ok = $true
        $summary.Details += Get-WzText 'off.detailNothingToDo'
        Write-WzLog (Get-WzText 'off.logNothingToRemove') -Level Info
        return $summary
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'off.logRemoveTest' @{ name = $before.Name }) -Level Test
        foreach ($item in $remnants.Items) { Write-WzLog (Get-WzText 'off.logRemoveItemTest' @{ name = $item }) -Level Test }
        $summary.Details += Get-WzText 'off.detailDryRun'
        return $summary
    }

    # --- Stufe 1: das offizielle Werkzeug ---------------------------------
    if ($before.Installed) {
        $setup = Get-WzOdtSetup
        if (-not $setup) {
            $summary.Details += Get-WzText 'off.detailNoOdt'
            return $summary
        }

        $workDir = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'odt')
        $configFile = Join-Path $workDir 'remove-all.xml'
        $lines = @(
            '<Configuration>'
            '  <Remove All="TRUE" />'
            '  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />'
            '  <RemoveMSI />'
            '  <Display Level="None" AcceptEULA="TRUE" />'
            "  <Logging Level=`"Standard`" Path=`"$(ConvertTo-WzXmlText (Get-WzOfficeLogDir))`" />"
            '</Configuration>'
        )
        [IO.File]::WriteAllText($configFile, ($lines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))

        Write-WzLog (Get-WzText 'off.logRemoving' @{ name = $before.Name }) -Level Action
        $started = Get-Date
        $result = Invoke-WzProcess -FilePath $setup -Arguments "/configure `"$configFile`"" `
            -WorkingDirectory $workDir -TimeoutSeconds 3600

        if ($result.TimedOut) {
            $summary.Details += Get-WzText 'off.removeTimeout'
            Write-WzLog (Get-WzText 'off.removeTimeout') -Level Error
            return $summary
        }
        $log = Get-WzOdtLogVerdict -Since $started
        if ($log.HasError) {
            Write-WzLog (Get-WzText 'off.logOdtCodesShort' @{ codes = ($log.Codes -join ', ') }) -Level Warn
        }
        $summary.Steps += "Office entfernt: $($before.Name)"
        Write-WzLog (Get-WzText 'off.logOdtDone') -Level Ok
    }

    # --- Stufe 2: die Reste ------------------------------------------------
    if ($Thorough) {
        # Frisch nachsehen: Stufe 1 hat das meiste schon abgeräumt. Die Liste
        # von vorhin würde Ordner löschen wollen, die es nicht mehr gibt — und
        # schlimmer: welche, die inzwischen zu etwas anderem gehören.
        $remnants = Get-WzOfficeRemnants
        foreach ($app in $remnants.StoreApps) {
            try {
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
                $summary.Steps += "Store-Fassung entfernt: $($app.Name)"
                Write-WzLog "Store-Fassung entfernt: $($app.Name)" -Level Ok
            } catch {
                $summary.Details += "$($app.Name): $($_.Exception.Message.Split([char]10)[0])"
                Write-WzLog (Get-WzText 'off.logAppRemoveFailed' @{ name = $app.Name; grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
            }
        }
        foreach ($folder in $remnants.Folders) {
            try {
                Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
                $summary.Steps += "Ordner entfernt: $folder"
                Write-WzLog "Ordner entfernt: $folder" -Level Ok
            } catch {
                $summary.Details += "$folder blieb liegen: $($_.Exception.Message.Split([char]10)[0])"
                Write-WzLog (Get-WzText 'off.logFolderRemoveFailed' @{ pfad = $folder }) -Level Warn
            }
        }
    }

    # Nachprüfen statt glauben
    $after = Get-WzInstalledOffice
    $summary.Ok = -not $after.Installed
    if ($summary.Ok) {
        Write-WzLog (Get-WzText 'off.logRemoved') -Level Ok
        if ($summary.Steps.Count -gt 0) {
            Add-WzAction -Area 'Office' -Summary "Office entfernt: $($before.Name)" `
                -Detail $summary.Steps -RebootRequired
        }
    } else {
        $summary.Details += Get-WzText 'off.detailStillFound' @{ name = $after.Name }
        Write-WzLog (Get-WzText 'off.logStillFound' @{ name = $after.Name }) -Level Warn
    }
    return $summary
}

function Install-WzLibreOffice {
    <#
    .SYNOPSIS
        Installiert LibreOffice über winget.
    #>
    # Der Katalogeintrag bringt id, name und wingetId schon mit — ein
    # nachgebautes Objekt daneben lief nur Gefahr, auseinanderzulaufen.
    return Install-WzApps -Apps @((Get-WzOfficeCatalog).libreOffice)
}

function Get-WzInstalledOffice {
    <#
    .SYNOPSIS
        Welche Office-Version ist bereits installiert?
    #>
    $result = [pscustomobject]@{
        Installed = $false; Name = (Get-WzText 'off.notInstalled'); Version = ''; Details = ''
        Bitness = $null; IsClickToRun = $false
    }

    try {
        $config = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop
        $result.Installed = $true
        $result.IsClickToRun = $true
        $result.Version = $config.VersionToReport
        $productIds = $config.ProductReleaseIds
        $result.Name = switch -Wildcard ($productIds) {
            '*O365ProPlus*'     { 'Microsoft 365 Apps for Enterprise'; break }
            '*O365Business*'    { 'Microsoft 365 Apps for Business'; break }
            '*ProPlus2024*'     { 'Office LTSC Professional Plus 2024'; break }
            '*Standard2024*'    { 'Office LTSC Standard 2024'; break }
            '*ProPlus2021*'     { 'Office LTSC Professional Plus 2021'; break }
            '*Standard2021*'    { 'Office LTSC Standard 2021'; break }
            '*ProPlus2019*'     { 'Office Professional Plus 2019'; break }
            '*Standard2019*'    { 'Office Standard 2019'; break }
            '*HomeBusiness*'    { 'Office Home & Business'; break }
            '*HomeStudent*'     { 'Office Home & Student'; break }
            '*Personal*'        { 'Microsoft 365 Single'; break }
            default             { "Office ($productIds)" }
        }
        # Bitness gehört dazu: Sie entscheidet, ob sich eine neue Installation
        # überhaupt darüberlegen lässt.
        $result.Bitness = if ($config.Platform -eq 'x86') { '32' } elseif ($config.Platform -eq 'x64') { '64' } else { $null }
        $bits = if ($result.Bitness) { "$($result.Bitness)-Bit · " } else { '' }
        # Der Kanal stand bisher als nackte GUID da — die sagt niemandem etwas.
        $result.Details = "$bits$($config.ClientCulture) · $(Get-WzOfficeChannelName $config.CDNBaseUrl)"
        return $result
    } catch { }

    # Ältere MSI-Installationen
    try {
        $msi = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction Stop |
            Where-Object { $_.DisplayName -match '^Microsoft Office (Professional|Standard|Home)' } |
            Select-Object -First 1
        if ($msi) {
            $result.Installed = $true
            $result.Name = $msi.DisplayName
            $result.Version = $msi.DisplayVersion
            $result.Details = Get-WzText 'off.detailOldMsi'
        }
    } catch { }

    return $result
}
