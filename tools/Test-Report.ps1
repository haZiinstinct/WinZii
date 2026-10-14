# Dev-Werkzeug: prüft, dass fremder Text im Bericht Text bleibt.
#
# Das Übergabeblatt zeigt Werte, die WinZii nicht selbst schreibt: SSIDs,
# Druckernamen, Freigabepfade, Programmnamen, Ereignistexte. Eine SSID darf
# beliebige 32 Byte enthalten. Bis 0.7.0 zerschnitt ein »|« darin die
# Kartenzeile und landete unmaskiert als CSS-Klasse, und ein Programmname, der
# mit »<span« begann, ging ungeprüft als HTML durch (Audit 2026-10, M20, M21).
#
# Geprüft werden die Bausteine des Berichts mit Injektionsmustern. Angefasst
# wird nichts, es entsteht keine Datei.
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Report.ps1
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
$global:WzRootPath = $root
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.DryRun = $false
$syncHash.Language = 'de'

foreach ($modul in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.I18n', 'Report') {
    . (Join-Path $root "src\modules\$modul.ps1")
}
[void](Import-WzLanguage)

$script:fehler = 0
function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $farbe = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-50} {2}" -f $symbol, $Name, $Detail) -ForegroundColor $farbe
    if (-not $Ok) { $script:fehler++ }
}

Write-Host ''
Write-Host '  WinZii Bericht: fremder Text bleibt Text' -ForegroundColor Cyan
Write-Host ''

# --- Karten ------------------------------------------------------------------
Write-Host '1. Kartenzeilen' -ForegroundColor White
$ssid = 'Gast|" onmouseover="alert(1)'
$karte = New-WzHtmlCard -Title 'Test' -Rows @("WLAN|$ssid")
Write-Check 'SSID mit »|« bleibt ganz' ($karte -match [regex]::Escape('Gast|&quot; onmouseover=&quot;alert(1)'))
Write-Check 'kein rohes Anführungszeichen im Attribut' ($karte -notmatch 'onmouseover="')
Write-Check 'keine Klasse aus dem Wert' ($karte -notmatch 'tag-')

$karte = New-WzHtmlCard -Title 'Test' -Rows @('Zustand|in Ordnung|ok')
Write-Check 'bekannte Art wird Abzeichen' ($karte -match 'class="tag tag-ok">in Ordnung<')

$karte = New-WzHtmlCard -Title 'Test' -Rows @('Drucker|Büro|x" onclick="y')
Write-Check 'unbekannte Art bleibt Text' ($karte -notmatch 'tag-x' -and $karte -match 'Büro\|x&quot; onclick=&quot;y')

$karte = New-WzHtmlCard -Title 'Test' -Rows @('Pfad|\\server\<script>|warn')
Write-Check 'Spitze Klammern im Wert maskiert' ($karte -match '&lt;script&gt;' -and $karte -notmatch '<script>')

# --- Tabellen ----------------------------------------------------------------
Write-Host ''
Write-Host '2. Tabellenzellen' -ForegroundColor White
$zeilen = @(
    [pscustomobject]@{ Name = '<span onclick=x>Fake</span>'; Zustand = 'ok' }
    [pscustomobject]@{ Name = '<a href="javascript:x">Link</a>'; Zustand = (New-WzHtmlTag -Text 'gut' -Kind 'ok') }
)
$tabelle = New-WzHtmlTable -Data $zeilen -Columns @('Name|Name', 'Zustand|Zustand')
Write-Check 'Programmname mit <span> maskiert' ($tabelle -match '&lt;span onclick=x&gt;' -and $tabelle -notmatch '<span onclick')
Write-Check 'Programmname mit <a> maskiert' ($tabelle -notmatch '<a href')
Write-Check 'New-WzHtmlTag kommt als Abzeichen durch' ($tabelle -match '<span class="tag tag-ok">gut</span>')

$tag = New-WzHtmlTag -Text '<b>fett</b>' -Kind 'warn'
Write-Check 'New-WzHtmlTag maskiert seinen Text' ($tag.WzHtml -match '&lt;b&gt;fett&lt;/b&gt;')
$abgelehnt = $false
try { [void](New-WzHtmlTag -Text 'x' -Kind 'x" onclick="y') } catch { $abgelehnt = $true }
Write-Check 'New-WzHtmlTag nimmt nur bekannte Arten' $abgelehnt

Write-Host ''
if ($script:fehler -eq 0) {
    Write-Host '  Ergebnis: alle Prüfungen bestanden.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $($script:fehler) Prüfung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
