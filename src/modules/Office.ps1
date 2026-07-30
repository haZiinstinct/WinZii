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
        [string]$OutFile
    )

    $catalog = Get-WzOfficeCatalog
    $variant = $catalog.variants | Where-Object { $_.id -eq $VariantId } | Select-Object -First 1
    if (-not $variant) { throw "Unbekannte Office-Variante: $VariantId" }

    $excluded = @($catalog.apps | Where-Object { $_.id -notin $IncludedApps } | ForEach-Object { $_.id })

    $lines = New-Object Collections.ArrayList
    [void]$lines.Add('<Configuration>')

    $addAttributes = "OfficeClientEdition=`"64`" Channel=`"$($variant.channel)`""
    if ($SourcePath) { $addAttributes += " SourcePath=`"$SourcePath`"" }
    [void]$lines.Add("  <Add $addAttributes>")
    [void]$lines.Add("    <Product ID=`"$($variant.productId)`">")
    [void]$lines.Add("      <Language ID=`"$Language`" />")
    foreach ($app in $excluded) {
        [void]$lines.Add("      <ExcludeApp ID=`"$app`" />")
    }
    [void]$lines.Add('    </Product>')
    [void]$lines.Add('  </Add>')

    [void]$lines.Add('  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />')
    [void]$lines.Add('  <Property Name="AUTOACTIVATE" Value="1" />')
    [void]$lines.Add('  <Property Name="SharedComputerLicensing" Value="0" />')
    [void]$lines.Add('  <Updates Enabled="TRUE" />')
    [void]$lines.Add('  <RemoveMSI />')
    [void]$lines.Add('  <Display Level="Full" AcceptEULA="TRUE" />')
    [void]$lines.Add('</Configuration>')

    if (-not $OutFile) {
        $workDir = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'odt')
        $OutFile = Join-Path $workDir "configuration-$VariantId-$Language.xml"
    }

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($OutFile, ($lines -join [Environment]::NewLine), $utf8NoBom)
    return $OutFile
}

function Get-WzOdtSetup {
    <#
    .SYNOPSIS
        Liefert den Pfad zu setup.exe des Office Deployment Tools.
        Beim ersten Mal wird es von Microsoft geladen und bleibt danach
        auf dem Datenträger.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $odtDir = New-WzDirectory (Join-Path (Get-WzOfflineDir) 'odt')
    $setupPath = Join-Path $odtDir 'setup.exe'

    if ((Test-Path -LiteralPath $setupPath) -and -not $Force) {
        return $setupPath
    }

    if ($syncHash.DryRun) {
        Write-WzLog '[Test] Office Deployment Tool würde geladen.' -Level Test
        return $null
    }

    $catalog = Get-WzOfficeCatalog
    Write-WzLog 'Lade das Office Deployment Tool von Microsoft...' -Level Action
    if (Get-WzDownload -Url $catalog.odtSetupUrl -TargetPath $setupPath) {
        Write-WzLog 'Office Deployment Tool bereit' -Level Ok
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
    $result = [pscustomobject]@{ Available = $false; Path = $path; Bytes = [int64]0 }
    if (-not (Test-Path -LiteralPath $path)) { return $result }

    $bytes = (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $result.Bytes = [int64]$bytes
    # Ein vollständiger Satz liegt deutlich über einem Gigabyte
    $result.Available = ($bytes -gt 500MB)
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

    $volume = Get-WzVolumeInfo
    if ($volume.IsFat32) {
        Write-WzLog 'Der Datenträger ist mit FAT32 formatiert. Office-Pakete überschreiten die dortige 4-GB-Dateigrenze — bitte exFAT oder NTFS verwenden.' -Level Error
        return $false
    }
    if ($volume.FreeBytes -gt 0 -and $volume.FreeBytes -lt 6GB) {
        Write-WzLog "Nur $(Format-WzBytes $volume.FreeBytes) frei. Für Office werden etwa 4 bis 6 GB gebraucht." -Level Warn
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

    Write-WzLog 'Office wird geladen — das dauert je nach Verbindung 10 bis 30 Minuten...' -Level Action
    $result = Invoke-WzProcess -FilePath $setup -Arguments "/download `"$configFile`"" `
        -WorkingDirectory (Split-Path -Parent $configFile) -TimeoutSeconds 7200

    if ($result.ExitCode -eq 0) {
        $cache = Test-WzOfficeCache -VariantId $VariantId -Language $Language
        Write-WzLog "Office liegt jetzt auf dem Datenträger ($(Format-WzBytes $cache.Bytes))" -Level Ok
        return $true
    }
    Write-WzLog "Herunterladen fehlgeschlagen (Code $($result.ExitCode))" -Level Error
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
        [Parameter(Mandatory = $true)][string[]]$IncludedApps
    )

    $setup = Get-WzOdtSetup
    if (-not $setup) { return $false }

    $cache = Test-WzOfficeCache -VariantId $VariantId -Language $Language
    $sourcePath = if ($cache.Available) { $cache.Path } else { $null }

    if ($sourcePath) {
        Write-WzLog "Installation vom Datenträger ($(Format-WzBytes $cache.Bytes)) — kein Internet nötig." -Level Info
    } else {
        Write-WzLog 'Keine Dateien auf dem Datenträger — Office wird direkt von Microsoft geladen.' -Level Info
    }

    $configFile = New-WzOfficeConfigXml -VariantId $VariantId -Language $Language `
        -IncludedApps $IncludedApps -SourcePath $sourcePath

    if ($syncHash.DryRun) {
        Write-WzLog "[Test] setup.exe /configure `"$configFile`"" -Level Test
        return $true
    }

    Write-WzLog 'Office wird installiert — das dauert einige Minuten...' -Level Action
    $result = Invoke-WzProcess -FilePath $setup -Arguments "/configure `"$configFile`"" `
        -WorkingDirectory (Split-Path -Parent $configFile) -TimeoutSeconds 7200

    if ($result.ExitCode -eq 0) {
        Write-WzLog 'Office wurde installiert' -Level Ok
        return $true
    }
    Write-WzLog "Installation fehlgeschlagen (Code $($result.ExitCode))" -Level Error
    return $false
}

function Install-WzLibreOffice {
    <#
    .SYNOPSIS
        Installiert LibreOffice über winget.
    #>
    $catalog = Get-WzOfficeCatalog
    $app = [pscustomobject]@{
        id       = 'libreoffice'
        name     = $catalog.libreOffice.name
        wingetId = $catalog.libreOffice.wingetId
    }
    return Install-WzApps -Apps @($app)
}

function Get-WzInstalledOffice {
    <#
    .SYNOPSIS
        Welche Office-Version ist bereits installiert?
    #>
    $result = [pscustomobject]@{ Installed = $false; Name = 'nicht installiert'; Version = ''; Details = '' }

    try {
        $config = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop
        $result.Installed = $true
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
        $result.Details = "$($config.ClientCulture) · Kanal $($config.CDNBaseUrl -replace '.*/', '')"
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
            $result.Details = 'ältere MSI-Installation'
        }
    } catch { }

    return $result
}
