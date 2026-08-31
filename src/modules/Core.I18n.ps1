# Core.I18n — Oberflächensprache.
#
# Aufbau nach dem Vorbild von VoZii: eine Tabelle je Sprache, punktnotierte
# Schlüssel nach Bereich gruppiert, und eine dreistufige Rückfallkette, die nie
# wirft und nie leer liefert.
#
# Die Oberfläche selbst greift NICHT über Get-WzText zu, sondern über ein
# ResourceDictionary und {DynamicResource L.<schlüssel>} im XAML. Wird das
# Wörterbuch getauscht, aktualisiert WPF jedes Element von selbst — auch in
# Seiten, die längst geladen und zwischengespeichert sind. Get-WzText ist für
# alles da, was der Code zur Laufzeit zusammensetzt.

# Die Sprachen und ihre Eigennamen. Der Wert ist zugleich die Beschriftung im
# Auswahlfeld — ein Franzose sucht »Français«, nicht »Französisch«.
$script:WzLanguages = [ordered]@{
    de = 'Deutsch'
    en = 'English'
    es = 'Español'
    fr = 'Français'
    pt = 'Português'
    ru = 'Русский'
    zh = '中文'
    ja = '日本語'
    ar = 'العربية'
}

# Rechtsläufige Sprachen. Wird in Etappe 8 für $window.FlowDirection benutzt.
$script:WzRtlLanguages = @('ar')

function Get-WzLanguageList {
    <#
    .SYNOPSIS
        Alle vorgesehenen Sprachen mit Code, Eigenname und Verfügbarkeit.
    .DESCRIPTION
        Vorgesehen sind neun; gefüllt sind zunächst nur die, für die eine Datei
        unter data\lang liegt. Der Aufrufer entscheidet, ob er die übrigen
        anzeigt (ausgegraut) oder weglässt.
    #>
    [CmdletBinding()]
    param()

    $dir = Get-WzLanguageDir
    return @($script:WzLanguages.Keys | ForEach-Object {
        [pscustomobject]@{
            Code      = $_
            Name      = $script:WzLanguages[$_]
            IsRtl     = ($script:WzRtlLanguages -contains $_)
            Available = (Test-Path -LiteralPath (Join-Path $dir "$_.json"))
        }
    })
}

function Get-WzLanguageDir { Get-WzPath 'data' 'lang' }

function Get-WzSystemLanguage {
    <#
    .SYNOPSIS
        Die Windows-Oberflächensprache, auf eine der vorgesehenen Sprachen
        abgebildet. Rückfall: Deutsch.
    .NOTES
        Über die Primärsprache der LCID (die unteren 10 Bit). Damit trifft
        de-AT und de-CH genauso wie de-DE, und pt-BR wie pt-PT — die
        Unterscheidung nach Land brächte hier nichts.
    #>
    [CmdletBinding()]
    param()

    try {
        $lcid = [int](Get-UICulture).LCID
        $primary = $lcid -band 0x3FF
        $map = @{
            0x07 = 'de'; 0x09 = 'en'; 0x0A = 'es'; 0x0C = 'fr'; 0x16 = 'pt'
            0x19 = 'ru'; 0x04 = 'zh'; 0x11 = 'ja'; 0x01 = 'ar'
        }
        if ($map.ContainsKey($primary)) { return $map[$primary] }
    } catch { }
    return 'de'
}

function Import-WzLanguage {
    <#
    .SYNOPSIS
        Lädt alle vorhandenen Sprachdateien nach $syncHash.Lang.
    .DESCRIPTION
        Bewusst alle auf einmal und in den $syncHash: Die Rückfallkette braucht
        Englisch und Deutsch jederzeit, und Hintergrund-Runspaces sehen nur,
        was im $syncHash steht — ein $script:-Zwischenspeicher wäre dort leer.
        Die Dateien sind zusammen wenige hundert Kilobyte.
    #>
    [CmdletBinding()]
    param()

    $tables = @{}
    $dir = Get-WzLanguageDir
    if (Test-Path -LiteralPath $dir) {
        foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            # kataloge.<code>.json gehört zu Etappe 4 und ist keine Oberflächensprache
            if ($file.BaseName -notmatch '^[a-z]{2}$') { continue }
            try {
                $raw = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
                $json = $raw | ConvertFrom-Json
                $flat = @{}
                Expand-WzLanguageNode -Node $json -Prefix '' -Target $flat
                $tables[$file.BaseName] = $flat
            } catch {
                # Laeuft waehrend des Ladens der Sprachtabelle — Get-WzText gaebe es hier noch nicht.
                Write-Warning "Sprachdatei '$($file.Name)' ist fehlerhaft: $($_.Exception.Message)"  # lang-ok
            }
        }
    }

    $syncHash.Lang = $tables
    return $tables.Keys.Count
}

function Expand-WzLanguageNode {
    <#
    .SYNOPSIS
        Macht aus der verschachtelten JSON-Struktur eine flache Tabelle
        »bereich.unterbereich.schlüssel« → Text.
    .NOTES
        Verschachtelt geschrieben, flach benutzt: In der Datei bleiben die
        Bereiche als Blöcke lesbar, im Zugriff kostet es keine Rekursion.
    #>
    param(
        [Parameter(Mandatory = $true)]$Node,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prefix,
        [Parameter(Mandatory = $true)][hashtable]$Target
    )

    foreach ($property in $Node.PSObject.Properties) {
        $key = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
        if ($property.Value -is [string]) {
            $Target[$key] = $property.Value
        } elseif ($null -ne $property.Value -and $property.Value.PSObject.Properties.Count -gt 0) {
            Expand-WzLanguageNode -Node $property.Value -Prefix $key -Target $Target
        }
    }
}

function Set-WzLanguage {
    <#
    .SYNOPSIS
        Wechselt die Oberflächensprache.
    .DESCRIPTION
        Setzt die aktive Sprache, tauscht das Ressourcen-Wörterbuch im Fenster
        und speichert die Wahl. Alle XAML-Texte schalten dadurch von selbst um;
        was der Code gesetzt hat, holt der Aufrufer über den Seitenneuaufbau
        nach (siehe Update-WzLanguageUi).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [switch]$NoSave
    )

    if (-not $syncHash.Lang -or -not $syncHash.Lang.ContainsKey($Code)) { $Code = 'de' }
    if ($syncHash.Language -eq $Code) { return $Code }

    $syncHash.Language = $Code
    $syncHash.LanguageIsRtl = ($script:WzRtlLanguages -contains $Code)
    # Die Kultur für Zahlen und Datumsangaben hängt an der Sprache, nicht am
    # System: Wer die Oberfläche auf English stellt, will auch »13.1 GB«.
    $syncHash.LanguageCulture = Get-WzLanguageCulture -Code $Code

    if ($syncHash.Window) { Update-WzLanguageResources }
    if (-not $NoSave) { Save-WzSetting -Name 'sprache' -Value $Code }
    return $Code
}

function Get-WzLanguageCulture {
    <#
    .SYNOPSIS
        Die .NET-Kultur zu einem Sprachcode, für Zahlen- und Datumsformate.
    #>
    param([string]$Code)

    # Ohne Angabe die gerade eingestellte Sprache: Die Zahlen- und
    # Datumsformate im Code fragen nicht nach einem Code, sie wollen einfach
    # die Kultur, in der die Oberflaeche gerade spricht.
    if (-not $Code) { $Code = $syncHash.Language }
    if (-not $Code) { $Code = 'de' }

    $map = @{
        de = 'de-DE'; en = 'en-GB'; es = 'es-ES'; fr = 'fr-FR'; pt = 'pt-PT'
        ru = 'ru-RU'; zh = 'zh-CN'; ja = 'ja-JP'; ar = 'ar-EG'
    }
    # en-GB statt en-US: Datum als 14/02/2026 statt 2/14/2026 — für einen
    # europäischen Kunden auf dem Übergabeblatt weniger verwechselbar.
    #
    # ar-EG statt ar-SA: ar-SA rechnet im Umm-al-Qura-Kalender. Aus dem
    # 14.02.2026 würde dort »26/08/47« — auf einem Kundenbericht schlicht falsch.
    # ar-EG ist gregorianisch. Aus demselben Grund prüft Test-Language, dass
    # jede Kultur einen gregorianischen Kalender führt.
    $name = if ($map.ContainsKey($Code)) { $map[$Code] } else { 'de-DE' }
    try { return [Globalization.CultureInfo]::GetCultureInfo($name) }
    catch { return [Globalization.CultureInfo]::GetCultureInfo('de-DE') }
}

function Get-WzText {
    <#
    .SYNOPSIS
        Übersetzten Text zu einem Schlüssel holen.
    .DESCRIPTION
        Rückfallkette: aktive Sprache → English → Deutsch → der Schlüssel selbst.
        Wirft nie und liefert nie leer. Steht im schlimmsten Fall der Schlüssel
        in der Oberfläche, fällt das sofort auf — besser als ein leeres Feld.
    .PARAMETER Values
        Benannte Platzhalter, z. B. @{ anzahl = 5 } für "{anzahl} Datei(en)".
        Bewusst benannt statt positionell wie bei -f: Im Japanischen und
        Arabischen dreht sich die Wortstellung, und eine feste Reihenfolge der
        Argumente wäre dann eine Fehlerquelle.
    .EXAMPLE
        Get-WzText 'daten.wlan.gesichert' @{ anzahl = 5 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Key,
        [Parameter(Position = 1)][hashtable]$Values
    )

    $text = $null
    $tables = $syncHash.Lang
    if ($tables) {
        foreach ($code in @($syncHash.Language, 'en', 'de')) {
            if (-not $code -or -not $tables.ContainsKey($code)) { continue }
            if ($tables[$code].ContainsKey($Key)) {
                $text = $tables[$code][$Key]
                break
            }
        }
    }
    if ($null -eq $text) { return $Key }

    if ($Values -and $Values.Count -gt 0) {
        foreach ($name in $Values.Keys) {
            $text = $text.Replace("{$name}", [string]$Values[$name])
        }
    }
    return $text
}

function New-WzLanguageResources {
    <#
    .SYNOPSIS
        Baut aus der aktiven Sprache ein ResourceDictionary mit Schlüsseln
        »L.<schlüssel>« für {DynamicResource} im XAML.
    .NOTES
        Es werden ALLE Schlüssel aufgenommen, auch die für den Code — das kostet
        nichts und erspart die Frage, welcher Schlüssel wo benutzt wird. Die
        Rückfallkette wird beim Bauen aufgelöst, damit im Wörterbuch nie ein
        Loch entsteht.
    #>
    [CmdletBinding()]
    param()

    $dict = New-Object Windows.ResourceDictionary
    $tables = $syncHash.Lang
    if (-not $tables) { return $dict }

    # Rückwärts durch die Kette: erst Deutsch als Grundlage, dann Englisch
    # darüber, zuletzt die aktive Sprache. So gewinnt immer die speziellste.
    foreach ($code in @('de', 'en', $syncHash.Language)) {
        if (-not $code -or -not $tables.ContainsKey($code)) { continue }
        foreach ($key in $tables[$code].Keys) {
            $dict["L.$key"] = $tables[$code][$key]
        }
    }
    return $dict
}

function Update-WzLanguageResources {
    <#
    .SYNOPSIS
        Tauscht das Sprachwörterbuch im Fenster aus.
    .NOTES
        An Ort und Stelle ersetzen, nicht entfernen und neu anhängen: Letzteres
        löst zwei Durchläufe über den Visual Tree aus und verschiebt den Eintrag
        ans Ende der Liste — bei überlappenden Schlüsseln gewönne dann plötzlich
        ein anderes Wörterbuch. Das Design (Theme.xaml) bleibt unberührt.
    #>
    [CmdletBinding()]
    param()

    if (-not $syncHash.Window) { return }
    $merged = $syncHash.Window.Resources.MergedDictionaries
    $fresh = New-WzLanguageResources

    $index = -1
    if ($syncHash.LangResources) { $index = $merged.IndexOf($syncHash.LangResources) }
    if ($index -ge 0) { $merged[$index] = $fresh } else { $merged.Add($fresh) }
    $syncHash.LangResources = $fresh

    # Rechtsläufige Sprachen spiegeln das ganze Fenster. Der Pfad wird schon
    # jetzt durchlaufen, obwohl de und en linksläufig sind — so ist er bei jedem
    # Seitentest mit dabei und nicht erst beim Anschalten von Arabisch neu.
    $syncHash.Window.FlowDirection = if ($syncHash.LanguageIsRtl) {
        [Windows.FlowDirection]::RightToLeft
    } else {
        [Windows.FlowDirection]::LeftToRight
    }
    # Die Konsole bleibt immer linksläufig: Dort stehen Zeitstempel, Pfade und
    # durchgereichte Ausgaben fremder Programme, die kein Bidi-Algorithmus
    # sinnvoll umsortieren kann.
    if ($syncHash.LogConsole) {
        $syncHash.LogConsole.FlowDirection = [Windows.FlowDirection]::LeftToRight
    }
}

function Update-WzLanguageButton {
    <#
    .SYNOPSIS
        Beschriftet den Sprachknopf mit Weltkugel und Eigenname der aktiven
        Sprache — »🌐 Deutsch«, nicht »DE«.
    .NOTES
        Der Eigenname, weil ein englischsprachiger Anwender vor einer deutschen
        Oberfläche nach »English« sucht und nicht nach »EN«.
    #>
    [CmdletBinding()]
    param()

    if (-not $syncHash.LanguagePicker) { return }
    $current = @(Get-WzLanguageList | Where-Object { $_.Code -eq $syncHash.Language })
    $name = if ($current.Count -gt 0) { $current[0].Name } else { $syncHash.Language }

    # Zwei Textblöcke statt einer Zeichenkette: Das Weltkugel-Zeichen liegt im
    # privaten Bereich von Segoe Fluent Icons. In der Textschrift des Knopfes
    # (Inter) gibt es dort keine Glyphe, und der Rückfall zeichnet irgendetwas.
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'

    $icon = New-Object Windows.Controls.TextBlock
    $icon.Text = [char]0xE774
    $icon.FontFamily = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
    $icon.FontSize = 12
    $icon.VerticalAlignment = 'Center'
    $icon.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
    [void]$row.Children.Add($icon)

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $name
    $label.VerticalAlignment = 'Center'
    [void]$row.Children.Add($label)

    $syncHash.LanguagePicker.Content = $row
}

function Show-WzLanguageChooser {
    <#
    .SYNOPSIS
        Sprache über den gewohnten Bestätigungsdialog wählen.
    .DESCRIPTION
        Läuft gerade eine Hintergrundaufgabe, wird gar nicht erst gefragt: Der
        Wechsel wirft den Seitenbaum weg, und die laufende Aufgabe schriebe ihr
        Ergebnis danach in Elemente, die es nicht mehr gibt. Genau daran ist es
        beim ersten Anlauf abgestürzt — der Anwender hatte umgeschaltet, während
        die Systemabfrage des Dashboards noch lief.
    #>
    [CmdletBinding()]
    param()

    $languages = @(Get-WzLanguageList | Where-Object { $_.Available })
    if ($languages.Count -lt 2) { return }

    if ($syncHash.Busy) {
        [void](Show-WzConfirm -Title (Get-WzText 'dialog.languageTitle') `
            -Message (Get-WzText 'start.languageBusy' @{ name = $syncHash.BusyName }) `
            -HideCancel -ConfirmText (Get-WzText 'dialog.understood'))
        return
    }

    $current = [array]::IndexOf(@($languages | ForEach-Object { $_.Code }), $syncHash.Language)
    $answer = Show-WzConfirm -Title (Get-WzText 'dialog.languageTitle') `
        -Message (Get-WzText 'dialog.languageMessage') `
        -Choices @($languages | ForEach-Object { $_.Name }) `
        -ChoiceLabel (Get-WzText 'dialog.languageLabel') `
        -ChoiceDefault ([math]::Max(0, $current)) `
        -ConfirmText (Get-WzText 'dialog.languageConfirm')
    if (-not $answer.Confirmed) { return }

    $chosen = $languages[$answer.SelectedIndex]
    if ($chosen.Code -eq $syncHash.Language) { return }

    [void](Set-WzLanguage -Code $chosen.Code)
    Update-WzLanguageButton
    Write-WzLog (Get-WzText 'start.languageChanged' @{ sprache = $chosen.Name }) -Level Info
    if (-not (Test-WzWritableRoot)) {
        Write-WzLog (Get-WzText 'start.settingsReadOnly') -Level Warn
    }

    # Den Seitenneuaufbau dem Dispatcher überlassen, statt ihn im Klick-Ereignis
    # zu erledigen: Sonst wird der Baum abgerissen, während der Dialog noch
    # dabei ist, sich zu schließen.
    [void]$syncHash.Window.Dispatcher.BeginInvoke(
        [Windows.Threading.DispatcherPriority]::Background,
        [action]{ Update-WzLanguageUi })
}

function Update-WzLanguageUi {
    <#
    .SYNOPSIS
        Holt nach, was ein Wörterbuchtausch nicht erreicht.
    .DESCRIPTION
        Alle XAML-Texte schalten über {DynamicResource} von selbst um. Was der
        PowerShell-Code direkt geschrieben hat — Kartentitel, Infozeilen,
        Hinweise — bleibt dagegen stehen. Deshalb wird der Seiten-Zwischenspeicher
        verworfen und die aktive Seite neu aufgebaut. Die Messergebnisse liegen
        im $syncHash und überleben das; es wird nichts neu gemessen.
    #>
    [CmdletBinding()]
    param()

    if (-not $syncHash.Window) { return }

    $current = $syncHash.CurrentPage
    $syncHash.Pages.Clear()
    # Die »Geladen«-Merker der Seiten mit zurücksetzen, sonst überspringt
    # Update-Wz<X>Page die Neubefüllung.
    foreach ($flag in @($syncHash.Keys | Where-Object { $_ -like '*Loaded' })) {
        $syncHash[$flag] = $false
    }
    if ($current) { Show-WzPage -Id $current }
}

# --- Einstellungen ---------------------------------------------------------
# WinZii kannte bisher keine gespeicherten Einstellungen. Die Sprachwahl ist
# die erste — und sie gehört auf den Stick, nicht in das Benutzerprofil des
# Kunden: Das Werkzeug ist portabel und soll keine Spuren hinterlassen.

function Get-WzSettingsPath { Get-WzPath 'einstellungen.json' }

function Get-WzSetting {
    <#
    .SYNOPSIS
        Einen gespeicherten Wert lesen. Fehlt die Datei, kommt der Vorgabewert.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if (-not $script:WzSettings) {
        $script:WzSettings = @{}
        $path = Get-WzSettingsPath
        if (Test-Path -LiteralPath $path) {
            try {
                $json = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
                foreach ($property in $json.PSObject.Properties) {
                    $script:WzSettings[$property.Name] = $property.Value
                }
            } catch {
                # Eine kaputte Einstellungsdatei darf den Start nicht aufhalten
            }
        }
    }

    if ($script:WzSettings.ContainsKey($Name)) { return $script:WzSettings[$Name] }
    return $Default
}

function Save-WzSetting {
    <#
    .SYNOPSIS
        Einen Wert dauerhaft merken.
    .NOTES
        Auf einem schreibgeschützten Datenträger scheitert das lautlos — die
        Wahl gilt dann für die Sitzung. Die Oberfläche sagt das über den
        vorhandenen Schreibschutz-Hinweis, hier wäre eine zweite Meldung nur
        Lärm.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    [void](Get-WzSetting -Name $Name)   # sorgt dafür, dass die Datei gelesen ist
    $script:WzSettings[$Name] = $Value

    try {
        $object = [pscustomobject]$script:WzSettings
        $json = $object | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText((Get-WzSettingsPath), $json, (New-Object Text.UTF8Encoding($false)))
        return $true
    } catch {
        return $false
    }
}

function Initialize-WzLanguage {
    <#
    .SYNOPSIS
        Sprache beim Start festlegen: gespeicherte Wahl, sonst Systemsprache.
    .PARAMETER Preferred
        Ausdrücklich verlangte Sprache (Startparameter -Language oder
        WZ_SELFTEST_LANG). Schlägt alles andere.
    #>
    [CmdletBinding()]
    param([string]$Preferred)

    [void](Import-WzLanguage)
    # Reihenfolge: ausdrücklich verlangt (Startparameter, Selbsttest) →
    # gemerkte Wahl → Systemsprache. Der Startparameter ist der einzige Weg,
    # die englische Fassung auf einem deutschen Rechner zu sehen.
    $saved = Get-WzSetting -Name 'sprache'
    $code = if ($Preferred -and $syncHash.Lang.ContainsKey($Preferred)) { $Preferred }
        elseif ($saved -and $syncHash.Lang.ContainsKey($saved)) { $saved }
        else { Get-WzSystemLanguage }
    # Ist die erkannte Sprache noch nicht übersetzt, bleibt es bei Deutsch
    if (-not $syncHash.Lang.ContainsKey($code)) { $code = 'de' }

    $syncHash.Language = $null       # erzwingt das Setzen in Set-WzLanguage
    # Nicht speichern: Ein Selbsttest-Lauf auf Englisch soll die Wahl des
    # Anwenders nicht überschreiben.
    return (Set-WzLanguage -Code $code -NoSave)
}
