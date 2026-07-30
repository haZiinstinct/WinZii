# Core.Json — Kataloge aus data\ laden und prüfen.

function Get-WzCatalog {
    <#
    .SYNOPSIS
        Lädt einen JSON-Katalog aus data\ (UTF-8, mit Zwischenspeicher).
    .PARAMETER Name
        Dateiname ohne Endung, z. B. 'tweaks'.
    .PARAMETER Force
        Zwischenspeicher umgehen und neu einlesen.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Force
    )

    if (-not $script:WzCatalogCache) { $script:WzCatalogCache = @{} }
    if (-not $Force -and $script:WzCatalogCache.ContainsKey($Name)) {
        return $script:WzCatalogCache[$Name]
    }

    $path = Join-Path (Get-WzDataDir) "$Name.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Katalog '$Name' nicht gefunden: $path"
    }

    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        $catalog = $raw | ConvertFrom-Json
    } catch {
        throw "Katalog '$Name' ist fehlerhaft: $($_.Exception.Message)"
    }

    $script:WzCatalogCache[$Name] = $catalog
    return $catalog
}

function Save-WzJson {
    <#
    .SYNOPSIS
        Objekt als UTF-8-JSON speichern (ohne BOM, damit die Datei portabel bleibt).
    #>
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8
    )
    $json = $InputObject | ConvertTo-Json -Depth $Depth
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $json, $utf8NoBom)
    return $Path
}

function Read-WzJson {
    <#
    .SYNOPSIS
        Beliebige JSON-Datei einlesen (z. B. undo.json aus einem Backup).
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        Write-WzLog "JSON konnte nicht gelesen werden: $Path" -Level Warn
        return $null
    }
}
