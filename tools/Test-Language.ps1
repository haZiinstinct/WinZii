# Dev-Werkzeug: prüft die Sprachdateien unter data\lang.
#
# Nach dem Vorbild von VoZiis tests\test_i18n.py — dort ist genau dieser Test
# der Grund, warum 100 Schlüssel über neun Sprachen konsistent bleiben. Bei
# WinZii sind es deutlich mehr, entsprechend weniger geht ohne ihn.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Language.ps1
[CmdletBinding()]
param([switch]$All)

$root = Split-Path -Parent $PSScriptRoot
$langDir = Join-Path $root 'data\lang'

$script:failed = 0
$script:warned = 0
function Pruefe {
    param([string]$Was, [bool]$Ok, [string]$Detail = '')
    $mark = if ($Ok) { '[ok]  ' } else { $script:failed++; '[FEHL]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-46} {2}" -f $mark, $Was, $Detail) -ForegroundColor $color
}
function Warne {
    param([string]$Was, [string]$Detail = '')
    $script:warned++
    Write-Host ("  [warn] {0,-46} {1}" -f $Was, $Detail) -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  WinZii Sprachtest' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-Path -LiteralPath $langDir)) {
    Write-Host "  [FEHL] Kein Sprachverzeichnis: $langDir" -ForegroundColor Red
    exit 1
}

# --- 1. Dateien lesbar und wirklich UTF-8 ----------------------------------
# throwOnInvalidBytes ist der eigentliche Punkt: Eine versehentlich als ANSI
# gespeicherte Datei würde sonst still zu »Gr??e« und fiele erst beim Kunden
# auf. Die BOM-Prüfung von Test-Smoke erfasst nur .ps1 und .xaml.
Write-Host '1. Dateien lesbar und gültiges UTF-8'
$tables = @{}
$strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
foreach ($file in (Get-ChildItem -LiteralPath $langDir -Filter '*.json' -File | Sort-Object Name)) {
    if ($file.BaseName -notmatch '^[a-z]{2}$') { continue }
    $ok = $true
    $detail = ''
    try {
        $raw = [IO.File]::ReadAllText($file.FullName, $strictUtf8)
        $json = $raw | ConvertFrom-Json
        $flat = @{}
        $stack = [Collections.Stack]::new()
        $stack.Push(@{ Node = $json; Prefix = '' })
        while ($stack.Count -gt 0) {
            $item = $stack.Pop()
            foreach ($property in $item.Node.PSObject.Properties) {
                $key = if ($item.Prefix) { "$($item.Prefix).$($property.Name)" } else { $property.Name }
                if ($property.Value -is [string]) {
                    $flat[$key] = $property.Value
                } elseif ($null -ne $property.Value) {
                    $stack.Push(@{ Node = $property.Value; Prefix = $key })
                }
            }
        }
        $tables[$file.BaseName] = $flat
        $detail = "$($flat.Count) Schlüssel"
    } catch {
        $ok = $false
        $detail = $_.Exception.Message.Split([char]10)[0]
    }
    Pruefe $file.Name $ok $detail
}

if (-not $tables.ContainsKey('de')) {
    Write-Host '  [FEHL] de.json fehlt — sie ist die Referenz.' -ForegroundColor Red
    exit 1
}
$reference = $tables['de']

# --- 2. Gleiche Schlüsselmenge --------------------------------------------
Write-Host ''
Write-Host '2. Gleiche Schlüsselmenge wie Deutsch'
foreach ($code in ($tables.Keys | Sort-Object)) {
    if ($code -eq 'de') { continue }
    $missing = @($reference.Keys | Where-Object { -not $tables[$code].ContainsKey($_) })
    $extra = @($tables[$code].Keys | Where-Object { -not $reference.ContainsKey($_) })
    $detail = ''
    if ($missing.Count -gt 0) { $detail += "$($missing.Count) fehlen" }
    if ($extra.Count -gt 0) { $detail += "$(if ($detail) { ', ' })$($extra.Count) überzählig" }
    Pruefe $code (($missing.Count + $extra.Count) -eq 0) $detail
    if ($All) {
        foreach ($key in ($missing | Select-Object -First 12)) { Write-Host "         fehlt:      $key" -ForegroundColor DarkGray }
        foreach ($key in ($extra | Select-Object -First 12)) { Write-Host "         überzählig: $key" -ForegroundColor DarkGray }
    }
}

# --- 3. Keine leeren Werte -------------------------------------------------
Write-Host ''
Write-Host '3. Keine leeren Übersetzungen'
foreach ($code in ($tables.Keys | Sort-Object)) {
    $empty = @($tables[$code].Keys | Where-Object { [string]::IsNullOrWhiteSpace($tables[$code][$_]) })
    Pruefe $code ($empty.Count -eq 0) $(if ($empty.Count) { "$($empty.Count): $($empty[0])" })
}

# --- 4. Gleiche Platzhalter je Schlüssel -----------------------------------
# Der wertvollste Block: Wird aus {anzahl} in einer Sprache {count}, bleibt der
# Platzhalter zur Laufzeit stehen und der Nutzer liest »{count} Dateien«.
Write-Host ''
Write-Host '4. Gleiche Platzhalter je Schlüssel'
foreach ($code in ($tables.Keys | Sort-Object)) {
    if ($code -eq 'de') { continue }
    $wrong = @()
    foreach ($key in $reference.Keys) {
        if (-not $tables[$code].ContainsKey($key)) { continue }
        $want = @([regex]::Matches($reference[$key], '\{(\w+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $got = @([regex]::Matches($tables[$code][$key], '\{(\w+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        if (($want -join ',') -ne ($got -join ',')) {
            $wrong += "$key (de: $($want -join '+') / ${code}: $($got -join '+'))"
        }
    }
    Pruefe $code ($wrong.Count -eq 0) $(if ($wrong.Count) { $wrong[0] })
    if ($All) { foreach ($w in $wrong) { Write-Host "         $w" -ForegroundColor DarkGray } }
}

# --- 5. Kultur gültig und gregorianisch ------------------------------------
# ar-SA rechnet im Umm-al-Qura-Kalender: aus dem 14.02.2026 würde »26/08/47«.
# Dasselbe gälte für th-TH (buddhistisch) und fa-IR (persisch).
Write-Host ''
Write-Host '5. Kultur gültig und gregorianisch'
foreach ($code in ($tables.Keys | Sort-Object)) {
    $name = $tables[$code]['_meta.culture']
    if (-not $name) { Pruefe $code $false 'keine _meta.culture'; continue }
    try {
        $culture = [Globalization.CultureInfo]::GetCultureInfo($name)
        $gregorian = $culture.Calendar -is [Globalization.GregorianCalendar]
        Pruefe $code $gregorian "$name · $($culture.Calendar.GetType().Name)"
    } catch {
        Pruefe $code $false "$name ist keine gültige Kultur"
    }
}

# --- 6. Eigenname vorhanden ------------------------------------------------
Write-Host ''
Write-Host '6. Eigenname gesetzt'
foreach ($code in ($tables.Keys | Sort-Object)) {
    $name = $tables[$code]['_meta.name']
    Pruefe $code ([bool]$name -and $name -ne $code) $name
}

# --- 7. Benutzte gegen definierte Schlüssel --------------------------------
# Ein Tippfehler in {DynamicResource L.nav.dashbord} erzeugt eine LEERE
# Beschriftung, ganz ohne Fehlermeldung — weder Test-Smoke noch Test-Pages
# sehen das. Nur dieser Abgleich findet es.
Write-Host ''
Write-Host '7. Benutzte gegen definierte Schlüssel'
$used = @{}
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root 'src\xaml') -Filter '*.xaml' -File -Recurse)) {
    $raw = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    foreach ($match in [regex]::Matches($raw, '\{DynamicResource\s+L\.([^}\s]+)\}')) {
        $used[$match.Groups[1].Value] = "$($file.Name)"
    }
}
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' -File -Recurse)) {
    $raw = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    # Hilfe-Kommentare vorher entfernen: Ein .EXAMPLE mit erfundenem Schlüssel
    # ist keine Verwendung. Sonst meldet der Test die eigene Dokumentation.
    $code = [regex]::Replace($raw, '(?s)<#.*?#>', '')
    $code = [regex]::Replace($code, '(?m)^\s*#.*$', '')
    foreach ($match in [regex]::Matches($code, "Get-WzText\s+(?:-Key\s+)?'([^']+)'")) {
        $used[$match.Groups[1].Value] = "$($file.Name)"
    }
    # Der Launcher laeuft vor allen Modulen und hat deshalb eine eigene, winzige
    # Textauswahl (Get-BootText). Ohne diese Zeile gaelten seine Schluessel als
    # tot — und das erste, was der Anwender sieht, waere nicht abgesichert.
    foreach ($match in [regex]::Matches($code, "Get-BootText\s+'([^']+)'")) {
        $used["boot.$($match.Groups[1].Value)"] = "$($file.Name)"
    }
}

$undefined = @($used.Keys | Where-Object { -not $reference.ContainsKey($_) } | Sort-Object)
Pruefe 'jeder benutzte Schlüssel ist definiert' ($undefined.Count -eq 0) "$($used.Count) benutzt"
foreach ($key in ($undefined | Select-Object -First 15)) {
    Write-Host "         fehlt in de.json: $key   ($($used[$key]))" -ForegroundColor Red
}

# Tote Schlüssel sind nur eine Warnung: Manche werden bewusst zur Laufzeit
# zusammengesetzt und tauchen im Quelltext nie wörtlich auf.
$dead = @($reference.Keys | Where-Object { $_ -notlike '_meta*' -and -not $used.ContainsKey($_) } | Sort-Object)
if ($dead.Count -gt 0) {
    Warne 'nirgends benutzte Schlüssel' "$($dead.Count) Stück"
    if ($All) { foreach ($key in $dead) { Write-Host "         $key" -ForegroundColor DarkGray } }
} else {
    Pruefe 'keine toten Schlüssel' $true
}

# --- 8. Spracherkennung ----------------------------------------------------
# Der einzige Weg, die LCID-Zuordnung auf einem deutschen Rechner zu prüfen:
# Get-WzSystemLanguage liefert hier immer 'de'.
Write-Host ''
Write-Host '8. LCID-Zuordnung'
$lcidMap = @{
    0x0407 = 'de'; 0x0C07 = 'de'; 0x0409 = 'en'; 0x0809 = 'en'; 0x0C0A = 'es'
    0x040C = 'fr'; 0x0416 = 'pt'; 0x0816 = 'pt'; 0x0419 = 'ru'; 0x0804 = 'zh'
    0x0411 = 'ja'; 0x0401 = 'ar'; 0x041F = 'de'   # Türkisch ist nicht vorgesehen -> Rückfall
}
$primaryMap = @{
    0x07 = 'de'; 0x09 = 'en'; 0x0A = 'es'; 0x0C = 'fr'; 0x16 = 'pt'
    0x19 = 'ru'; 0x04 = 'zh'; 0x11 = 'ja'; 0x01 = 'ar'
}
$wrong = @()
foreach ($lcid in $lcidMap.Keys) {
    $primary = $lcid -band 0x3FF
    $got = if ($primaryMap.ContainsKey($primary)) { $primaryMap[$primary] } else { 'de' }
    if ($got -ne $lcidMap[$lcid]) { $wrong += ('0x{0:X4} -> {1}, erwartet {2}' -f $lcid, $got, $lcidMap[$lcid]) }
}
Pruefe 'alle geprüften LCIDs treffen' ($wrong.Count -eq 0) $(if ($wrong.Count) { $wrong[0] } else { "$($lcidMap.Count) geprüft" })

Write-Host ''
Write-Host '9. Kein fester Anzeigetext im Code'

# Etappe 1 hat alle Oberflaechentexte nach data\lang\ verlegt. Damit sie dort
# bleiben, wird hier NICHT nach deutschen Woertern geraten — das uebersieht
# jeden Text ohne Umlaut. Geprueft werden die Stellen, an denen Anzeigetext
# steht: Titel, Meldungen, Hinweise, Vorgangsnamen, Protokollzeilen,
# Knopfbeschriftungen und die Beschriftung einer Infozeile. Steht dort ein
# Zeichenkettenliteral statt Get-WzText, ist es ein Fund.
#
# Ausnahmen tragen »# lang-ok« in derselben Zeile und damit eine Begruendung.
$codeDirs = @((Join-Path $root 'src\modules'), (Join-Path $root 'src\pages'))
$stellen = @(
    '-Title'; '-Message'; '-Text'; '-Summary'; '-ConfirmText'; '-ChoiceLabel'
    '-OptionText'; '-Recommendation'; '-Verdict'; '-Caption'; '-Detail'; '-Hint'
)
# Ein einzelner regulaerer Ausdruck je Aufrufstelle, beide Anfuehrungsarten.
# In "..." wird die Einsetzung ($var, $(...)) vorher herausgeschnitten: was
# danach an Buchstaben uebrig bleibt, ist fest verdrahteter Anzeigetext.
function Get-FesterText {
    param(
        [string]$Zeile,
        [string]$Vorspann,
        [string]$Trenner = '\s+'
    )
    foreach ($anfuehrung in @("'([^']{2,})'", '"([^"]{2,})"')) {
        if ($Zeile -match ($Vorspann + $Trenner + $anfuehrung)) { return $Matches[1] }
    }
    return $null
}

function Test-Anzeigetext {
    param([string]$Wert, [switch]$Streng)
    $rest = $Wert -replace '\$\([^)]*\)', '' -replace '\$\w+(\.\w+)*', ''
    if ($rest -notmatch '[A-Za-zÄÖÜäöüß]{3,}') { return $false }
    # Ein Wert ohne Leerzeichen ist meist eine Kennung, kein Satz — ausser bei
    # einem Anzeigeelement, dort ist auch ein einzelnes Wort Text: »AKTIV«,
    # »umschalten«, »Aufgabe«. Genau die sind in Etappe 1 durchgerutscht.
    if (-not $Streng -and $rest -notmatch ' ') { return $false }
    return $true
}

# Anzeigeelemente werden streng geprueft, alles andere mit Leerzeichenregel.
$streng = @('New-WzBadge -Text', 'New-WzInfoRow', '\.Text =', '\.Content =')
$locker = @('Invoke-WzTask -Name', 'Write-WzLog')

$fund = @()
foreach ($dir in $codeDirs) {
    foreach ($datei in (Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
        $zeilen = [IO.File]::ReadAllLines($datei.FullName, [Text.Encoding]::UTF8)
        for ($i = 0; $i -lt $zeilen.Count; $i++) {
            $zeile = $zeilen[$i]
            if ($zeile.TrimStart().StartsWith('#')) { continue }
            if ($zeile -match '#\s*lang-ok') { continue }

            $treffer = $null
            $istStreng = $false
            foreach ($stelle in $streng) {
                $treffer = Get-FesterText -Zeile $zeile -Vorspann $stelle -Trenner '\s*'
                if ($treffer) { $istStreng = $true; break }
            }
            if (-not $treffer) {
                foreach ($stelle in ($stellen + $locker)) {
                    $treffer = Get-FesterText -Zeile $zeile -Vorspann ([regex]::Escape($stelle))
                    if ($treffer) { break }
                }
            }
            if (-not $treffer) { continue }
            if (-not (Test-Anzeigetext -Wert $treffer -Streng:$istStreng)) { continue }
            $fund += ('{0}:{1}  {2}' -f $datei.Name, ($i + 1), $treffer.Substring(0, [Math]::Min(58, $treffer.Length)))
        }
    }
}
Pruefe 'kein fester Anzeigetext im Code' ($fund.Count -eq 0) `
    $(if ($fund.Count) { "$($fund.Count) Fund(e), erster: $($fund[0])" } else { 'Titel, Meldungen, Vorgaenge und Protokoll geprueft' })
if ($fund.Count -gt 0 -and $All) {
    foreach ($eintrag in $fund) { Write-Host "         $eintrag" -ForegroundColor DarkYellow }
}

# --- Abschluss -------------------------------------------------------------
Write-Host ''
$sprachen = @($tables.Keys | Sort-Object) -join ', '
if ($script:failed -eq 0) {
    Write-Host "  Ergebnis: $($tables.Count) Sprache(n) ($sprachen), $($reference.Count) Schlüssel, keine Fehler." -ForegroundColor Green
    if ($script:warned -gt 0) { Write-Host "            $($script:warned) Warnung(en) — mit -All im Einzelnen." -ForegroundColor Yellow }
    exit 0
}
Write-Host "  Ergebnis: $($script:failed) Fehler in $($tables.Count) Sprachdatei(en)." -ForegroundColor Red
exit 1
