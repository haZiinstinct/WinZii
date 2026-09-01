# Core.Json — Kataloge aus data\ laden und prüfen.

function Get-WzCatalogIdentity {
    <#
    .SYNOPSIS
        Welches Feld einen Katalogeintrag eindeutig macht — je Katalog und Liste.
    .DESCRIPTION
        Die Uebersetzung liegt in data\lang\kataloge.<code>.json und wird ueber
        diese Kennung zugeordnet, nicht ueber die Reihenfolge: Eine neue Zeile
        mitten im Katalog wuerde sonst alles darunter verschieben.
    #>
    return @{
        apps        = @{ categories = 'id'; apps = 'id' }
        bloatware   = @{ safe = 'pattern'; extended = 'pattern' }
        bugcheckmap = @{ entries = 'code' }
        cleanup     = @{ groups = 'id'; categories = 'id' }
        eventmap    = @{ entries = 'provider+id' }
        office      = @{ variants = 'id'; languages = 'id'; apps = 'id' }
        tweaks      = @{ categories = 'id'; tweaks = 'id' }
        wingetcodes = @{ codes = 'code' }
    }
}

function Get-WzCatalogSingles {
    <#
    .SYNOPSIS
        Katalogfelder, die kein Listeneintrag sind, sondern direkt am Objekt
        haengen — die winget-Notiz und LibreOffice.
    #>
    return @{
        apps   = @('wingetBootstrap')
        office = @('libreOffice')
    }
}

function Get-WzCatalogEntryKey {
    <#
    .SYNOPSIS
        Kennung eines Eintrags, passend zur Angabe aus Get-WzCatalogIdentity.
    #>
    param($Entry, [string]$Field)
    if ($Field -eq 'provider+id') { return "$($Entry.provider)/$($Entry.id)" }
    return [string]$Entry.$Field
}

function Merge-WzCatalogTranslation {
    <#
    .SYNOPSIS
        Legt die uebersetzten Felder ueber einen frisch gelesenen Katalog.
    .DESCRIPTION
        Ueberlagert wird nur, was in der Sprachdatei steht. Fehlt ein Eintrag
        oder ein Feld, bleibt der deutsche Text stehen — sichtbar, statt leer.
        Das ist Absicht: Eine Luecke faellt beim Hinsehen auf, ein leeres Feld
        sieht aus wie ein Fehler im Programm.
    #>
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Translation
    )

    $listen = (Get-WzCatalogIdentity)[$Name]
    if ($listen) {
        foreach ($liste in $listen.Keys) {
            $uebersetzt = $Translation.$liste
            if (-not $uebersetzt -or -not $Catalog.$liste) { continue }
            $feld = $listen[$liste]
            foreach ($eintrag in $Catalog.$liste) {
                $kennung = Get-WzCatalogEntryKey -Entry $eintrag -Field $feld
                $neu = $uebersetzt.$kennung
                if (-not $neu) { continue }
                foreach ($eigenschaft in $neu.PSObject.Properties) {
                    $eintrag.($eigenschaft.Name) = $eigenschaft.Value
                }
            }
        }
    }

    foreach ($einzeln in @((Get-WzCatalogSingles)[$Name])) {
        if (-not $einzeln) { continue }
        $neu = $Translation.$einzeln
        if (-not $neu -or -not $Catalog.$einzeln) { continue }
        foreach ($eigenschaft in $neu.PSObject.Properties) {
            $Catalog.$einzeln.($eigenschaft.Name) = $eigenschaft.Value
        }
    }

    return $Catalog
}

function Get-WzCatalogTranslation {
    <#
    .SYNOPSIS
        Die Uebersetzungsdatei zur eingestellten Sprache, mit Zwischenspeicher.
        Fehlt sie, wird nichts ueberlagert.
    #>
    param([string]$Code)

    if (-not $script:WzCatalogLangCache) { $script:WzCatalogLangCache = @{} }
    if ($script:WzCatalogLangCache.ContainsKey($Code)) { return $script:WzCatalogLangCache[$Code] }

    $tabelle = $null
    $pfad = Join-Path (Get-WzLanguageDir) "kataloge.$Code.json"
    if (Test-Path -LiteralPath $pfad) {
        try {
            $tabelle = [IO.File]::ReadAllText($pfad, [Text.Encoding]::UTF8) | ConvertFrom-Json
        } catch {
            Write-WzLog (Get-WzText 'core.catalogLangBroken' @{ code = $Code; grund = $_.Exception.Message }) -Level Warn
        }
    }
    $script:WzCatalogLangCache[$Code] = $tabelle
    return $tabelle
}

function Get-WzCatalog {
    <#
    .SYNOPSIS
        Laedt einen JSON-Katalog aus data\ (UTF-8, mit Zwischenspeicher).
    .DESCRIPTION
        Die Katalogdateien sind deutsch. Steht die Oberflaeche auf einer anderen
        Sprache, werden die Anzeigefelder aus data\lang\kataloge.<code>.json
        darueber gelegt. Der Zwischenspeicher haengt deshalb an Name UND Sprache
        — sonst haette ein Sprachwechsel den alten Stand weitergereicht.
    .PARAMETER Name
        Dateiname ohne Endung, z. B. 'tweaks'.
    .PARAMETER Force
        Zwischenspeicher umgehen und neu einlesen.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Force
    )

    $sprache = if ($syncHash.Language) { $syncHash.Language } else { 'de' }
    $schluessel = "$Name|$sprache"

    if (-not $script:WzCatalogCache) { $script:WzCatalogCache = @{} }
    if (-not $Force -and $script:WzCatalogCache.ContainsKey($schluessel)) {
        return $script:WzCatalogCache[$schluessel]
    }

    $path = Join-Path (Get-WzDataDir) "$Name.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw (Get-WzText 'core.catalogNotFound' @{ name = $Name; pfad = $path })
    }

    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        $catalog = $raw | ConvertFrom-Json
    } catch {
        throw (Get-WzText 'core.catalogBroken' @{ name = $Name; grund = $_.Exception.Message })
    }

    if ($sprache -ne 'de') {
        $uebersetzung = Get-WzCatalogTranslation -Code $sprache
        if ($uebersetzung -and $uebersetzung.$Name) {
            $catalog = Merge-WzCatalogTranslation -Catalog $catalog -Name $Name -Translation $uebersetzung.$Name
        }
    }

    $script:WzCatalogCache[$schluessel] = $catalog
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
        Write-WzLog (Get-WzText 'core.jsonUnreadable' @{ pfad = $Path }) -Level Warn
        return $null
    }
}
