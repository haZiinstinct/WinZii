# Dev-Werkzeug: prüft die Lesbarkeit nach WCAG 2.1.
#
# Die Farbwerte werden aus src\xaml\Theme.xaml gelesen, damit der Test nicht
# an einer eigenen Kopie der Palette vorbeiläuft. Geprüft werden die Paare,
# die in der Oberfläche tatsächlich vorkommen.
#
# Schwellen:  Text ab 4,5:1   ·   große Schrift ab 3:1   ·   Bedienelemente ab 3:1
#
# Aufruf:  powershell -NoProfile -File tools\Test-Contrast.ps1
[CmdletBinding()]
param([switch]$All)

$root = Split-Path -Parent $PSScriptRoot
$themePath = Join-Path $root 'src\xaml\Theme.xaml'

# --- Palette aus dem Design lesen ------------------------------------------
$palette = @{}
$themeText = [IO.File]::ReadAllText($themePath, [Text.Encoding]::UTF8)
foreach ($match in [regex]::Matches($themeText, '<SolidColorBrush\s+x:Key="(?<key>\w+)"\s+Color="(?<color>#[0-9A-Fa-f]{6,8})"')) {
    $palette[$match.Groups['key'].Value] = $match.Groups['color'].Value
}
if ($palette.Count -eq 0) { throw "Keine Farben in $themePath gefunden." }

# --- Farbrechnung ----------------------------------------------------------
function ConvertFrom-WzHex {
    <#
    .SYNOPSIS
        Wandelt #RRGGBB oder #AARRGGBB in Kanäle um (Alpha als 0..1).
    #>
    param([string]$Hex)
    $value = $Hex.TrimStart('#')
    if ($value.Length -eq 8) {
        return [pscustomobject]@{
            A = [Convert]::ToInt32($value.Substring(0, 2), 16) / 255
            R = [Convert]::ToInt32($value.Substring(2, 2), 16)
            G = [Convert]::ToInt32($value.Substring(4, 2), 16)
            B = [Convert]::ToInt32($value.Substring(6, 2), 16)
        }
    }
    return [pscustomobject]@{
        A = 1.0
        R = [Convert]::ToInt32($value.Substring(0, 2), 16)
        G = [Convert]::ToInt32($value.Substring(2, 2), 16)
        B = [Convert]::ToInt32($value.Substring(4, 2), 16)
    }
}

function Merge-WzColor {
    <#
    .SYNOPSIS
        Legt eine (teil-)durchsichtige Farbe über einen deckenden Untergrund.
    #>
    param($Fore, $Back)
    return [pscustomobject]@{
        A = 1.0
        R = $Fore.A * $Fore.R + (1 - $Fore.A) * $Back.R
        G = $Fore.A * $Fore.G + (1 - $Fore.A) * $Back.G
        B = $Fore.A * $Fore.B + (1 - $Fore.A) * $Back.B
    }
}

function Get-WzLuminance {
    param($Color)
    $channels = @($Color.R, $Color.G, $Color.B) | ForEach-Object {
        $c = $_ / 255
        if ($c -le 0.03928) { $c / 12.92 } else { [math]::Pow((($c + 0.055) / 1.055), 2.4) }
    }
    return 0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
}

function Get-WzContrast {
    <#
    .SYNOPSIS
        Kontrastverhältnis zweier Farben. Durchsichtige Werte werden vorher
        über den angegebenen Untergrund gelegt.
    #>
    param([string]$Foreground, [string]$Background, [string]$Behind)

    $backColor = ConvertFrom-WzHex $Background
    if ($backColor.A -lt 1.0) {
        $behindColor = ConvertFrom-WzHex $(if ($Behind) { $Behind } else { '#0A0A0F' })
        $backColor = Merge-WzColor -Fore $backColor -Back $behindColor
    }

    $foreColor = ConvertFrom-WzHex $Foreground
    if ($foreColor.A -lt 1.0) {
        $foreColor = Merge-WzColor -Fore $foreColor -Back $backColor
    }

    $l1 = Get-WzLuminance $foreColor
    $l2 = Get-WzLuminance $backColor
    if ($l1 -lt $l2) { $l1, $l2 = $l2, $l1 }
    return [math]::Round((($l1 + 0.05) / ($l2 + 0.05)), 2)
}

function Resolve-WzColor {
    <#
    .SYNOPSIS
        Nimmt einen Ressourcennamen oder direkt einen Hex-Wert.
    #>
    param([string]$Value)
    if ($Value -like '#*') { return $Value }
    if ($palette.ContainsKey($Value)) { return $palette[$Value] }
    throw "Unbekannte Farbe: $Value"
}

# --- Prüfliste -------------------------------------------------------------
# Kind: text (4,5) · large (3,0) · ui (3,0)
$checks = @(
    # Fließtext auf den drei Flächen
    @{ Was = 'Fließtext auf Karte';            Fg = 'WzText';      Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Fließtext auf Seite';            Fg = 'WzText';      Bg = 'WzBgPage';   Kind = 'text' }
    @{ Was = 'Fließtext auf Seitenleiste';     Fg = 'WzText';      Bg = 'WzBgDarker'; Kind = 'text' }
    @{ Was = 'Zweitschrift auf Karte';         Fg = 'WzTextDim';   Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Zweitschrift auf Seite';         Fg = 'WzTextDim';   Bg = 'WzBgPage';   Kind = 'text' }
    @{ Was = 'Zweitschrift beim Überfahren';   Fg = 'WzTextDim';   Bg = 'WzBgCardHover'; Kind = 'text' }

    # Die Farbe, die vorher überall durchgefallen ist
    @{ Was = 'Hinweistext auf Karte';          Fg = 'WzTextFaint'; Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Hinweistext auf Seite';          Fg = 'WzTextFaint'; Bg = 'WzBgPage';   Kind = 'text' }
    @{ Was = 'Hinweistext auf Seitenleiste';   Fg = 'WzTextFaint'; Bg = 'WzBgDarker'; Kind = 'text' }
    @{ Was = 'Hinweistext beim Überfahren';    Fg = 'WzTextFaint'; Bg = 'WzBgCardHover'; Kind = 'text' }

    # Akzent und Status als Schrift
    @{ Was = 'Eyebrow cyan auf Karte';         Fg = 'WzCyan';      Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Eyebrow cyan auf Seitenleiste';  Fg = 'WzCyan';      Bg = 'WzBgDarker'; Kind = 'text' }
    @{ Was = 'Statusfarbe grün';               Fg = 'WzGreen';     Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Statusfarbe gelb';               Fg = 'WzAmber';     Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Statusfarbe rot als Schrift';    Fg = 'WzRedText';   Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Rot auf Gefahr-Knopf';           Fg = 'WzRedText';   Bg = '#1FEF4444';  Behind = 'WzBgCard'; Kind = 'text' }
    @{ Was = 'Rot auf Gefahr-Knopf (Maus)';    Fg = 'WzRedText';   Bg = '#33EF4444';  Behind = 'WzBgCard'; Kind = 'text' }
    @{ Was = 'Rot in der Konsole';             Fg = '#FCA5A5';     Bg = 'WzBgDarker'; Kind = 'text' }

    # Knöpfe
    @{ Was = 'Primärknopf';                    Fg = '#0A0A0F';     Bg = 'WzCyan';     Kind = 'text' }
    @{ Was = 'Primärknopf gedrückt';           Fg = '#0A0A0F';     Bg = 'WzCyanDim';  Kind = 'text' }
    @{ Was = 'Sekundärknopf';                  Fg = 'WzTextDim';   Bg = 'WzBgCard';   Kind = 'text' }
    @{ Was = 'Sekundärknopf beim Überfahren';  Fg = 'WzCyan';      Bg = 'WzBgCardHover'; Kind = 'text' }
    @{ Was = 'Navigation aktiv';               Fg = 'WzCyan';      Bg = '#1A00D4FF';  Behind = 'WzBgDarker'; Kind = 'text' }

    # Deaktiviert — vorher der schlimmste Fehler (1,5:1)
    @{ Was = 'Primärknopf deaktiviert';        Fg = 'WzDisabledTextCyan'; Bg = 'WzDisabledFillCyan'; Kind = 'text' }
    @{ Was = 'Sekundärknopf deaktiviert';      Fg = 'WzDisabledText';     Bg = 'WzDisabledFill';     Kind = 'text' }
    @{ Was = 'Gefahrknopf deaktiviert';        Fg = 'WzDisabledText';     Bg = 'WzDisabledFill';     Kind = 'text' }
    @{ Was = 'Auswahlkästchen deaktiviert';    Fg = 'WzDisabledText';     Bg = 'WzBgCard';           Kind = 'text' }

    # Dialoge
    @{ Was = 'Dialog-Titel';                   Fg = 'WzTextBright'; Bg = 'WzBgCard';  Kind = 'large' }
    @{ Was = 'Dialog-Nachricht';               Fg = 'WzTextDim';    Bg = 'WzBgCard';  Kind = 'text' }
    @{ Was = 'Dialog-Aufzählung';              Fg = 'WzText';       Bg = 'WzBgDarker'; Kind = 'text' }
    @{ Was = 'Dialog-Eyebrow Achtung';         Fg = 'WzRedText';    Bg = 'WzBgCard';  Kind = 'text' }

    # Mouseover-Hinweise
    @{ Was = 'Tooltip-Schrift';                Fg = 'WzText';      Bg = 'WzBgCard';   Kind = 'text' }

    # Große Schrift
    @{ Was = 'Seitenüberschrift';              Fg = 'WzTextBright'; Bg = 'WzBgPage';  Kind = 'large' }
    @{ Was = 'Große Kennzahl';                 Fg = 'WzCyan';       Bg = 'WzBgCard';  Kind = 'large' }
    @{ Was = 'Wortmarke';                      Fg = 'WzCyan';       Bg = 'WzBgDarker'; Kind = 'large' }

    # Bedienelemente — müssen erkennbar sein, auch wenn leer
    @{ Was = 'Auswahlkästchen (leer)';         Fg = 'WzBorderControl'; Bg = 'WzBgCard';    Kind = 'ui' }
    @{ Was = 'Schalter-Spur';                  Fg = 'WzBorderControl'; Bg = 'WzBgCard';    Kind = 'ui' }
    @{ Was = 'Balken-Spur';                    Fg = 'WzBorderControl'; Bg = 'WzBgCard';    Kind = 'ui' }
    @{ Was = 'Scrollbalken';                   Fg = '#66FFFFFF';       Bg = 'WzBgPage';    Behind = 'WzBgPage'; Kind = 'ui' }
    @{ Was = 'Auswahlkästchen angehakt';       Fg = 'WzCyan';          Bg = 'WzBgCard';    Kind = 'ui' }
    @{ Was = 'Schalter-Knopf (aus)';           Fg = 'WzTextDim';       Bg = 'WzBgCardHover'; Kind = 'ui' }
)

# --- Prüfen ----------------------------------------------------------------
Write-Host ''
Write-Host '  WinZii Kontrast-Prüfung (WCAG 2.1)' -ForegroundColor Cyan
Write-Host ''

$failed = 0
$rows = @()

foreach ($check in $checks) {
    $threshold = if ($check.Kind -eq 'text') { 4.5 } else { 3.0 }
    $behind = if ($check.ContainsKey('Behind')) { Resolve-WzColor $check.Behind } else { $null }
    $ratio = Get-WzContrast -Foreground (Resolve-WzColor $check.Fg) `
                            -Background (Resolve-WzColor $check.Bg) -Behind $behind

    $ok = ($ratio -ge $threshold)
    if (-not $ok) { $failed++ }

    $rows += [pscustomobject]@{
        Was       = $check.Was
        Art       = $check.Kind
        Verhaeltnis = $ratio
        Ziel      = $threshold
        Ok        = $ok
    }
}

foreach ($row in ($rows | Sort-Object Verhaeltnis)) {
    if ($row.Ok -and -not $All) { continue }
    $symbol = if ($row.Ok) { '[ok]  ' } else { '[FEHL]' }
    $color = if ($row.Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-32} {2,6}:1   nötig {3}:1   ({4})" -f `
        $symbol, $row.Was, $row.Verhaeltnis, $row.Ziel, $row.Art) -ForegroundColor $color
}

$worst = ($rows | Sort-Object Verhaeltnis | Select-Object -First 1)
Write-Host ''
if ($failed -eq 0) {
    Write-Host "  Ergebnis: alle $($rows.Count) Paare bestehen. Schwächstes: $($worst.Was) mit $($worst.Verhaeltnis):1." -ForegroundColor Green
    if (-not $All) { Write-Host '  Alle Werte anzeigen mit -All' -ForegroundColor DarkGray }
    exit 0
}
Write-Host "  Ergebnis: $failed von $($rows.Count) Paaren unter der Schwelle." -ForegroundColor Red
exit 1
