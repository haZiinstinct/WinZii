# Report — HTML-Berichte im haZii-Design.
# Alle Berichte nutzen dasselbe Grundgerüst (src\templates\report.html) und
# landen unter reports\<hostname>\. Keine externen Ressourcen, damit die
# Datei auch offline und auf fremden PCs unverändert aussieht.

function New-WzHtmlReport {
    <#
    .SYNOPSIS
        Setzt einen Bericht aus dem Grundgerüst und einem Inhaltsblock zusammen.
    .PARAMETER Content
        Fertiges HTML für den Hauptbereich.
    .PARAMETER Meta
        Zeilen für die Kopfleiste, jeweils "Bezeichnung|Wert".
    .OUTPUTS
        Pfad der geschriebenen Datei.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Content,
        [string]$Eyebrow = 'BERICHT',
        [string]$Subtitle = '',
        [string[]]$Meta = @(),
        [string]$FileName
    )

    $templatePath = Join-Path (Get-WzTemplateDir) 'report.html'
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Berichtsvorlage fehlt: $templatePath"
    }
    $template = [IO.File]::ReadAllText($templatePath, [Text.Encoding]::UTF8)

    $metaHtml = ($Meta | ForEach-Object {
        $parts = $_ -split '\|', 2
        if ($parts.Count -eq 2) {
            '<span class="pill">{0} <strong>{1}</strong></span>' -f
                (ConvertTo-WzHtmlText $parts[0]), (ConvertTo-WzHtmlText $parts[1])
        } else {
            '<span class="pill">{0}</span>' -f (ConvertTo-WzHtmlText $_)
        }
    }) -join "`n      "

    $html = $template.
        Replace('{{TITLE}}', (ConvertTo-WzHtmlText $Title)).
        Replace('{{EYEBROW}}', (ConvertTo-WzHtmlText $Eyebrow)).
        Replace('{{SUBTITLE}}', (ConvertTo-WzHtmlText $Subtitle)).
        Replace('{{META}}', $metaHtml).
        Replace('{{CONTENT}}', $Content).
        Replace('{{VERSION}}', $syncHash.Version).
        Replace('{{CREATED}}', (Get-Date -Format 'dd.MM.yyyy HH:mm'))

    if (-not $FileName) {
        $slug = ($Title -replace '[^\w]+', '-').Trim('-').ToLower()
        $FileName = "$slug-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    }
    $outFile = Join-Path (Get-WzReportDir) $FileName

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($outFile, $html, $utf8NoBom)
    return $outFile
}

function ConvertTo-WzHtmlText {
    <#
    .SYNOPSIS
        Maskiert Text für die Ausgabe in HTML.
    #>
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function New-WzHtmlCard {
    <#
    .SYNOPSIS
        Karte mit Definitionsliste.
    .PARAMETER Rows
        Zeilen als "Bezeichnung|Wert" oder "Bezeichnung|Wert|ok|warn|err".
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string[]]$Rows
    )

    $items = foreach ($row in $Rows) {
        $parts = $row -split '\|'
        $label = ConvertTo-WzHtmlText $parts[0]
        $value = if ($parts.Count -gt 1) { ConvertTo-WzHtmlText $parts[1] } else { '' }
        $kind = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        if ($kind) {
            "<dt>$label</dt><dd><span class=`"tag tag-$kind`">$value</span></dd>"
        } else {
            "<dt>$label</dt><dd>$value</dd>"
        }
    }

    return @"
<div class="card">
  <h3>$(ConvertTo-WzHtmlText $Title)</h3>
  <dl>
    $($items -join "`n    ")
  </dl>
</div>
"@
}

function New-WzHtmlTable {
    <#
    .SYNOPSIS
        Tabelle aus Objekten.
    .PARAMETER Columns
        Spalten als "Eigenschaft|Überschrift" oder "Eigenschaft|Überschrift|num".
    #>
    param(
        [Parameter(Mandatory = $true)]$Data,
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [string]$EmptyText = 'Keine Einträge.'
    )

    $rows = @($Data)
    if ($rows.Count -eq 0) {
        return "<p class=`"explain`">$(ConvertTo-WzHtmlText $EmptyText)</p>"
    }

    $definitions = foreach ($column in $Columns) {
        $parts = $column -split '\|'
        [pscustomobject]@{
            Property = $parts[0]
            Header   = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
            Class    = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        }
    }

    $head = ($definitions | ForEach-Object { "<th>$(ConvertTo-WzHtmlText $_.Header)</th>" }) -join ''
    $body = foreach ($row in $rows) {
        $cells = foreach ($definition in $definitions) {
            $value = $row.$($definition.Property)
            $class = if ($definition.Class) { " class=`"$($definition.Class)`"" } else { '' }
            # Bereits fertiges HTML (z. B. Abzeichen) wird nicht erneut maskiert
            $text = if ($value -is [string] -and $value -match '^<(span|a|strong|em)\b') {
                $value
            } else {
                ConvertTo-WzHtmlText ([string]$value)
            }
            "<td$class>$text</td>"
        }
        "<tr>$($cells -join '')</tr>"
    }

    return @"
<div class="card">
  <div class="table-scroll">
    <table>
      <thead><tr>$head</tr></thead>
      <tbody>
        $($body -join "`n        ")
      </tbody>
    </table>
  </div>
</div>
"@
}

function New-WzHtmlNote {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet('info', 'warn', 'err', 'ok')][string]$Kind = 'info'
    )
    return "<p class=`"note note-$Kind`">$(ConvertTo-WzHtmlText $Text)</p>"
}

function New-WzHtmlSection {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Lead,
        [Parameter(Mandatory = $true)][string]$Body
    )
    $leadHtml = if ($Lead) { "<p class=`"section-lead`">$(ConvertTo-WzHtmlText $Lead)</p>" } else { '' }
    return "<h2>$(ConvertTo-WzHtmlText $Title)</h2>$leadHtml$Body"
}

function New-WzDiagReport {
    <#
    .SYNOPSIS
        Erstellt den Diagnosebericht aus dem Ergebnis der Analyse.
    .OUTPUTS
        Pfad der Datei.
    #>
    param([Parameter(Mandatory = $true)]$Result)

    $info = $syncHash.SystemInfo
    $security = $syncHash.SecurityInfo
    $events = @($Result.Events)
    $dumps = @($Result.Dumps)
    $disks = @($Result.Disks)

    $critical = @($events | Where-Object { $_.Severity -eq 'critical' })
    $diskProblems = @($disks | Where-Object { $_.Assessment -ne 'unauffällig' })

    # --- Gesamteinschätzung -----------------------------------------------
    $verdict = if ($dumps.Count -gt 0 -or $diskProblems.Count -gt 0) {
        @{ Kind = 'err'; Text = 'Es gibt ernsthafte Auffälligkeiten, die geprüft werden sollten. Die Einzelheiten stehen weiter unten.' }
    } elseif ($critical.Count -gt 0) {
        @{ Kind = 'warn'; Text = 'Es wurden kritische Ereignisse gefunden. Sie deuten nicht zwingend auf einen Defekt hin, sollten aber angesehen werden.' }
    } elseif ($events.Count -gt 0) {
        @{ Kind = 'info'; Text = 'Es gibt einzelne Fehlermeldungen, aber keine kritischen Vorfälle. Für ein laufendes System ist das normal.' }
    } else {
        @{ Kind = 'ok'; Text = 'Im geprüften Zeitraum wurden keine Fehler aufgezeichnet.' }
    }

    $content = New-WzHtmlSection -Title 'Einschätzung' `
        -Body ((New-WzHtmlNote -Text $verdict.Text -Kind $verdict.Kind) + (New-WzHtmlCard -Title 'Auf einen Blick' -Rows @(
            "Ereignisse|$($events.Count) Auffälligkeit(en), davon $($critical.Count) kritisch"
            "Abstürze|$($dumps.Count) Bluescreen-Abbild(er) in den letzten 90 Tagen"
            "Datenträger|$($disks.Count) geprüft, $($diskProblems.Count) auffällig"
            "Zeitraum|letzte $($Result.Days) Tage"
        )))

    # --- System -----------------------------------------------------------
    if ($info) {
        $systemRows = @(
            "Computer|$($info.ComputerName)"
            "Windows|$($info.OsCaption) $($info.OsVersion) (Build $($info.OsBuild))"
            "Gerät|$($info.Manufacturer) $($info.Model)"
            "Prozessor|$($info.CpuName)"
            "Arbeitsspeicher|$(Format-WzBytes $info.RamTotalBytes) ($($info.RamUsedPercent) % belegt)"
            "Laufzeit|$(Format-WzUptime $info.Uptime)"
        )
        if ($security) {
            $activationKind = if ($security.Activation -like 'aktiviert*') { 'ok' } else { 'warn' }
            $systemRows += "Aktivierung|$($security.Activation)|$activationKind"
            $systemRows += "Virenschutz|$($security.Defender)|$(if ($security.DefenderOk) { 'ok' } else { 'warn' })"
        }
        if ($info.PendingReboot) {
            $systemRows += "Neustart|steht aus ($($info.PendingReboot))|warn"
        }
        $content += New-WzHtmlSection -Title 'System' -Body (New-WzHtmlCard -Title 'Eckdaten' -Rows $systemRows)
    }

    # --- Ereignisse -------------------------------------------------------
    $eventBody = if ($events.Count -eq 0) {
        New-WzHtmlNote -Text 'Keine Fehler oder kritischen Ereignisse im geprüften Zeitraum.' -Kind 'ok'
    } else {
        $rows = foreach ($event in $events) {
            $tagClass = switch ($event.Severity) {
                'critical' { 'tag-err' }
                'error'    { 'tag-warn' }
                default    { 'tag-info' }
            }
            $label = switch ($event.Severity) {
                'critical' { 'kritisch' }
                'error'    { 'Fehler' }
                default    { 'Hinweis' }
            }
            [pscustomobject]@{
                Stufe    = "<span class=`"tag $tagClass`">$label</span>"
                Titel    = $event.Title
                Anzahl   = $event.Count
                Zuletzt  = $event.Last.ToString('dd.MM.yy HH:mm')
                Deutung  = if ($event.Explanation) { "$($event.Explanation) $($event.Recommendation)" } else { $event.Sample }
                Quelle   = "$($event.Provider) / $($event.Id)"
            }
        }
        New-WzHtmlTable -Data $rows -Columns @(
            'Stufe|Stufe', 'Titel|Ereignis', 'Anzahl|Anzahl|num', 'Zuletzt|Zuletzt|num',
            'Deutung|Bedeutung und Empfehlung', 'Quelle|Quelle|mono'
        )
    }
    $content += New-WzHtmlSection -Title 'Ereignisse' `
        -Lead "Fehler und kritische Meldungen der letzten $($Result.Days) Tage, nach Häufigkeit zusammengefasst." `
        -Body $eventBody

    # --- Abstürze ---------------------------------------------------------
    $dumpBody = if ($dumps.Count -eq 0) {
        New-WzHtmlNote -Text 'Keine Bluescreen-Abbilder vorhanden — in den letzten 90 Tagen gab es keine Systemabstürze.' -Kind 'ok'
    } else {
        $rows = foreach ($dump in $dumps) {
            [pscustomobject]@{
                Zeit    = $dump.Time.ToString('dd.MM.yy HH:mm')
                Code    = $dump.Code
                Name    = $dump.Name
                Ursache = "$($dump.Cause) $($dump.Recommendation)"
                Datei   = $dump.File
            }
        }
        New-WzHtmlTable -Data $rows -Columns @(
            'Zeit|Zeitpunkt|num', 'Code|Stoppcode|mono', 'Name|Bezeichnung|mono',
            'Ursache|Ursache und Empfehlung', 'Datei|Abbild|mono'
        )
    }
    $content += New-WzHtmlSection -Title 'Systemabstürze' `
        -Lead 'Bluescreens der letzten 90 Tage mit übersetztem Stoppcode.' -Body $dumpBody

    # --- Startdauer -------------------------------------------------------
    # Die Werte wurden schon immer erhoben und in den Bericht hineingereicht,
    # kamen dort aber nie an. »74 s Start, davon 48 s Dropbox« ist das Argument,
    # das den Kunden zum Aufräumen bewegt.
    $boot = $Result.Boot
    $bootBody = if (-not $boot -or @($boot.Runs).Count -eq 0) {
        New-WzHtmlNote -Kind 'info' -Text $(if ($boot -and $boot.Hint) { $boot.Hint } else { 'Keine Startdaten verfügbar.' })
    } else {
        $bootKind = if ($boot.AverageSeconds -lt 30) { 'ok' } elseif ($boot.AverageSeconds -lt 60) { 'warn' } else { 'err' }
        $bootHtml = New-WzHtmlNote -Kind $bootKind -Text "Durchschnittlich $(Format-WzSeconds $boot.AverageSeconds -Unit 'Sekunden') bis zum benutzbaren Desktop. $($boot.Hint)"

        $bootRows = @(foreach ($run in @($boot.Runs)) {
            [pscustomobject]@{
                Zeit    = $run.Time.ToString('dd.MM.yy HH:mm')
                Gesamt  = Format-WzSeconds $run.TotalSeconds
                Windows = Format-WzSeconds ($run.MainPathMs / 1000)
                Danach  = Format-WzSeconds ([int]$run.DegradedBy / 1000)
            }
        })
        $bootHtml += New-WzHtmlTable -Data $bootRows -Columns @(
            'Zeit|Startvorgang|num', 'Gesamt|Gesamt|num',
            'Windows|davon Windows selbst|num', 'Danach|davon Autostart|num'
        )

        if (@($boot.Worst).Count -gt 0) {
            $culpritRows = @(foreach ($culprit in @($boot.Worst)) {
                [pscustomobject]@{
                    Name       = $culprit.Name
                    Verzoegert = Format-WzSeconds $culprit.DelaySeconds
                    Zeit       = $culprit.Time.ToString('dd.MM.yy HH:mm')
                }
            })
            $bootHtml += New-WzHtmlTable -Data $culpritRows -Columns @(
                'Name|Bremst den Start', 'Verzoegert|Verzögerung|num', 'Zeit|Gemessen am|num'
            )
        }
        $bootHtml
    }
    $content += New-WzHtmlSection -Title 'Startdauer' `
        -Lead 'Wie lange der PC vom Einschalten bis zum benutzbaren Desktop braucht — und was ihn dabei aufhält.' `
        -Body $bootBody

    # --- Zuverlässigkeit --------------------------------------------------
    # Beantwortet die Frage, die die Ereignisliste nicht beantworten kann:
    # Was wurde an dem Tag installiert, an dem die Probleme anfingen?
    $reliability = @($Result.Reliability)
    if ($reliability.Count -gt 0) {
        $reliabilityRows = @(foreach ($record in $reliability) {
            [pscustomobject]@{
                Zeit    = $record.Time.ToString('dd.MM.yy HH:mm')
                Art     = $record.Type
                Was     = $record.Source
                Details = $record.Message
            }
        })
        $content += New-WzHtmlSection -Title 'Zuverlässigkeitsverlauf' `
            -Lead 'Abstürze, Programmfehler und Installationen der letzten 30 Tage in einer Zeitleiste — hier zeigt sich, ob ein Problem mit einer Installation zusammenfällt.' `
            -Body (New-WzHtmlTable -Data $reliabilityRows -Columns @(
                'Zeit|Zeitpunkt|num', 'Art|Art', 'Was|Quelle', 'Details|Einzelheiten'
            ))
    }

    # --- Datenträger ------------------------------------------------------
    $diskBody = if ($disks.Count -eq 0) {
        New-WzHtmlNote -Text 'Keine Datenträgerdaten verfügbar.' -Kind 'info'
    } else {
        $rows = foreach ($disk in $disks) {
            $tag = if ($disk.Assessment -eq 'unauffällig') { 'tag-ok' } else { 'tag-warn' }
            [pscustomobject]@{
                Modell      = $disk.Model
                Art         = $disk.MediaType
                Groesse     = Format-WzBytes $disk.SizeBytes
                Betrieb     = $disk.PowerOnHours
                Temperatur  = $disk.Temperature
                Abnutzung   = $disk.Wear
                Zustand     = "<span class=`"tag $tag`">$($disk.Assessment)</span>"
            }
        }
        New-WzHtmlTable -Data $rows -Columns @(
            'Modell|Modell', 'Art|Art', 'Groesse|Größe|num', 'Betrieb|Betriebszeit',
            'Temperatur|Temperatur|num', 'Abnutzung|Abnutzung|num', 'Zustand|Zustand'
        )
    }
    $content += New-WzHtmlSection -Title 'Datenträger' `
        -Lead 'Zustandswerte aus der Selbstüberwachung der Laufwerke. USB-Gehäuse geben diese Werte oft nicht weiter.' `
        -Body $diskBody

    $meta = @(
        "Computer|$env:COMPUTERNAME"
        "Datum|$(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        "Zeitraum|$($Result.Days) Tage"
        "Befunde|$($events.Count)"
    )

    $file = New-WzHtmlReport -Title 'Diagnosebericht' -Eyebrow 'DIAGNOSE' `
        -Subtitle "Auswertung der Ereignisprotokolle, Abstürze und Datenträger von $env:COMPUTERNAME." `
        -Meta $meta -Content $content `
        -FileName "diagnose-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog "Diagnosebericht gespeichert: $file" -Level Ok
    return $file
}

function New-WzHandoverReport {
    <#
    .SYNOPSIS
        Übergabeblatt: was gemacht wurde, wie der PC jetzt dasteht, was noch
        ansteht — in Kundensprache und zum Ausdrucken.
    .PARAMETER Technician
        Wer die Arbeit gemacht hat.
    .PARAMETER Customer
        Für wen.
    .PARAMETER OrderNumber
        Auftragsnummer, falls vorhanden.
    .OUTPUTS
        Pfad der Datei.
    #>
    param(
        [string]$Technician,
        [string]$Customer,
        [string]$OrderNumber
    )

    $actions = @(Get-WzActions)
    $before = $syncHash.SessionStartInfo
    # Frisch abfragen: der freie Platz hat sich durch die Arbeit verändert
    $after = Get-WzSystemInfo
    $security = $syncHash.SecurityInfo

    # --- Was wurde gemacht -------------------------------------------------
    $content = ''
    if ($actions.Count -eq 0) {
        $content += New-WzHtmlNote -Kind 'info' -Text (
            'In dieser Sitzung wurde nichts am PC verändert. Das Blatt hält nur den Zustand fest.')
    } elseif (@($actions | Where-Object { $_.IsTest }).Count -eq $actions.Count) {
        $content += New-WzHtmlNote -Kind 'warn' -Text (
            'Alle Schritte liefen im Testmodus — am PC wurde tatsächlich nichts geändert.')
    }

    $groups = $actions | Group-Object Area
    $workBody = if ($actions.Count -eq 0) {
        New-WzHtmlNote -Kind 'info' -Text 'Keine Änderungen.'
    } else {
        $rows = @(foreach ($group in $groups) {
            $summaries = @($group.Group | ForEach-Object {
                if ($_.IsTest) { "$($_.Summary) (nur Testlauf)" } else { $_.Summary }
            })
            # Add-WzAction sammelt seit jeher die Einzelposten mit ein — bisher
            # landeten sie nirgends. Der Kunde soll sehen, WELCHE Programme
            # entfernt wurden, nicht nur wie viele.
            $details = @($group.Group | ForEach-Object { $_.Detail } | Where-Object { $_ })
            [pscustomobject]@{
                Bereich    = $group.Name
                Anzahl     = $group.Count
                Was        = $summaries -join ' · '
                Einzelnes  = if ($details.Count -gt 0) { $details -join ', ' } else { '—' }
            }
        })
        New-WzHtmlTable -Data $rows -Columns @(
            'Bereich|Bereich', 'Anzahl|Schritte|num', 'Was|Was gemacht wurde', 'Einzelnes|Einzelposten'
        )
    }
    $content += New-WzHtmlSection -Title 'Durchgeführte Arbeiten' `
        -Lead 'Alles, was in dieser Sitzung am PC verändert wurde.' -Body $workBody

    # --- Vorher und nachher ------------------------------------------------
    if ($before) {
        $diskRows = @(foreach ($volume in $after.Volumes) {
            $old = $before.Volumes | Where-Object { $_.Letter -eq $volume.Letter } | Select-Object -First 1
            $gained = if ($old) { $volume.FreeBytes - $old.FreeBytes } else { 0 }
            $change = if (-not $old) {
                'kein Vergleichswert'
            } elseif ($gained -gt 0) {
                "<span class=`"tag tag-ok`">+$(Format-WzBytes $gained)</span>"
            } elseif ($gained -lt 0) {
                "-$(Format-WzBytes ([math]::Abs($gained)))"
            } else { 'unverändert' }

            [pscustomobject]@{
                Laufwerk = "$($volume.Letter) $($volume.Label)".Trim()
                Vorher   = if ($old) { Format-WzBytes $old.FreeBytes } else { 'n/v' }
                Nachher  = Format-WzBytes $volume.FreeBytes
                Aenderung = $change
                Belegt   = "$($volume.UsedPercent) %"
            }
        })
        $content += New-WzHtmlSection -Title 'Speicherplatz vorher und nachher' `
            -Lead 'Freier Platz zu Beginn der Sitzung im Vergleich zu jetzt.' `
            -Body (New-WzHtmlTable -Data $diskRows -Columns @(
                'Laufwerk|Laufwerk', 'Vorher|Vorher|num', 'Nachher|Nachher|num',
                'Aenderung|Gewonnen', 'Belegt|Belegt|num'
            ))
    }

    # --- Geräteblatt -------------------------------------------------------
    $deviceRows = @(
        "Computer|$($after.ComputerName)"
        "Gerät|$($after.Manufacturer) $($after.Model) ($(if ($after.IsLaptop) { 'Notebook' } else { 'Desktop' }))"
        "Windows|$($after.OsCaption) $($after.OsVersion), Build $($after.OsBuild)"
        "Sprache|$($after.OsLanguage)"
        "Prozessor|$($after.CpuName)"
        "Arbeitsspeicher|$(Format-WzBytes $after.RamTotalBytes) · $($after.RamSlotsUsed) von $($after.RamSlots) Steckplätzen belegt · max. $(Format-WzBytes $after.RamMaxBytes)"
    )
    if ($after.InstallDate) { $deviceRows += "Windows installiert am|$($after.InstallDate.ToString('dd.MM.yyyy'))" }
    if (@($after.Gpus).Count -gt 0) { $deviceRows += "Grafik|$(@($after.Gpus)[0].Name)" }
    if (@($after.Monitors).Count -gt 0) {
        $deviceRows += "Bildschirme|$((@($after.Monitors) | ForEach-Object { "$($_.Vendor) $($_.Name)".Trim() }) -join ', ')"
    }
    $deviceRows += "BIOS|$($after.BiosVersion)$(if ($after.BiosDate) { " vom $($after.BiosDate.ToString('dd.MM.yyyy'))" })"
    if ($after.SerialNumber) { $deviceRows += "Seriennummer|$($after.SerialNumber)" }
    if ($after.Battery.Present) { $deviceRows += "Akku|$($after.Battery.Verdict)" }
    # Die MAC-Adresse steht schon in der Abfrage und wird nirgends gezeigt —
    # dabei braucht sie jeder, der den PC in einem verwalteten Netz freischalten
    # oder eine feste Adresse im Router hinterlegen soll.
    foreach ($adapter in $after.Network) {
        $line = "$($adapter.Adapter): $($adapter.IPv4)"
        if ($adapter.Mac) { $line += " · MAC $($adapter.Mac)" }
        $deviceRows += "Netzwerk|$line"
    }

    $securityRows = @()
    if ($security) {
        $securityRows += "Aktivierung|$($security.Activation)|$(if ($security.Activation -like 'aktiviert*') { 'ok' } else { 'warn' })"
        $securityRows += "Virenschutz|$($security.Defender)|$(if ($security.DefenderOk) { 'ok' } else { 'warn' })"
        $securityRows += "BitLocker|$($security.BitLocker)"
        $securityRows += "Secure Boot|$($security.SecureBoot)"
        $securityRows += "TPM|$($security.Tpm)"
        foreach ($disk in $security.PhysicalDisks) {
            $health = if ($disk.Health -eq 'Healthy') { 'in Ordnung' } else { $disk.Health }
            $securityRows += "$($disk.MediaType)|$($disk.Model) · $(Format-WzBytes $disk.SizeBytes) · $health|$(if ($disk.Health -eq 'Healthy') { 'ok' } else { 'warn' })"
        }
    } else {
        $securityRows += 'Hinweis|Der Sicherheitsstatus wurde in dieser Sitzung nicht abgefragt.'
    }

    $content += New-WzHtmlSection -Title 'Geräteblatt' `
        -Lead 'Die Eckdaten dieses PCs zum Zeitpunkt der Übergabe.' `
        -Body ((New-WzHtmlCard -Title 'Ausstattung' -Rows $deviceRows) +
               (New-WzHtmlCard -Title 'Sicherheit und Datenträger' -Rows $securityRows))

    # --- Empfehlungen ------------------------------------------------------
    $recommendations = Get-WzHandoverRecommendations -Info $after -Security $security -Actions $actions
    $recommendationBody = if ($recommendations.Count -eq 0) {
        New-WzHtmlNote -Kind 'ok' -Text 'Es steht nichts weiter an — der PC ist einsatzbereit.'
    } else {
        ($recommendations | ForEach-Object { New-WzHtmlNote -Kind $_.Kind -Text $_.Text }) -join "`n"
    }
    $content += New-WzHtmlSection -Title 'Was noch ansteht' `
        -Lead 'Punkte, die der Kunde wissen sollte.' -Body $recommendationBody

    # --- Kopfdaten ---------------------------------------------------------
    $meta = @("Computer|$env:COMPUTERNAME", "Datum|$(Get-Date -Format 'dd.MM.yyyy HH:mm')")
    if ($Technician) { $meta += "Techniker|$Technician" }
    if ($Customer) { $meta += "Kunde|$Customer" }
    if ($OrderNumber) { $meta += "Auftrag|$OrderNumber" }
    $meta += "Schritte|$($actions.Count)"

    $file = New-WzHtmlReport -Title 'Übergabeblatt' -Eyebrow 'ÜBERGABE' `
        -Subtitle "Was an $env:COMPUTERNAME gemacht wurde und wie der PC jetzt dasteht." `
        -Meta $meta -Content $content `
        -FileName "uebergabe-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog "Übergabeblatt gespeichert: $file" -Level Ok
    return $file
}

function Get-WzHandoverRecommendations {
    <#
    .SYNOPSIS
        Formt die vorhandenen Befunde in Sätze um, die dem Kunden etwas sagen.
    #>
    param($Info, $Security, $Actions)

    $result = @()

    if ($Info.PendingReboot -or @($Actions | Where-Object { $_.RebootRequired }).Count -gt 0) {
        $result += @{ Kind = 'warn'; Text = 'Der PC muss noch einmal neu gestartet werden. Erst danach greifen alle Änderungen.' }
    }

    foreach ($volume in $Info.Volumes) {
        if ($volume.UsedPercent -ge 90) {
            $result += @{ Kind = 'warn'; Text = "Laufwerk $($volume.Letter) ist zu $($volume.UsedPercent) % voll. Windows wird langsam, wenn weniger als ein Zehntel frei bleibt." }
        }
    }

    if ($Security) {
        if (-not $Security.DefenderOk) {
            $result += @{ Kind = 'warn'; Text = "Der Virenschutz ist nicht auf dem aktuellen Stand: $($Security.Defender)." }
        }
        if ($Security.Activation -notlike 'aktiviert*') {
            $result += @{ Kind = 'warn'; Text = "Windows ist nicht aktiviert ($($Security.Activation)). Dafür wird ein gültiger Lizenzschlüssel gebraucht." }
        }
        foreach ($disk in @($Security.PhysicalDisks)) {
            if ($disk.Health -ne 'Healthy') {
                $result += @{ Kind = 'err'; Text = "Der Datenträger $($disk.Model) meldet »$($disk.Health)«. Bitte zeitnah sichern und tauschen lassen." }
            }
        }
        if ($Info.IsLaptop -and $Security.BitLocker -like '*nicht*') {
            $result += @{ Kind = 'info'; Text = 'Dieses Notebook ist nicht verschlüsselt. Bei Verlust kann jeder die Daten auslesen — BitLocker wäre einen Gedanken wert.' }
        }
    }

    if ($Info.Battery.Present -and $null -ne $Info.Battery.WearPercent -and $Info.Battery.WearPercent -ge 40) {
        $result += @{ Kind = 'warn'; Text = "Der Akku hat $($Info.Battery.WearPercent) % seiner Kapazität verloren. Ein Austausch bringt die Laufzeit zurück." }
    }

    # Aufrüsten: Beide Zahlen liegen längst vor. Nur wenn gar keine SSD verbaut
    # ist, läuft Windows sicher von einer Festplatte — eine zusätzliche Daten-HDD
    # neben einer SSD ist völlig in Ordnung und darf hier nichts auslösen.
    $disks = if ($Security) { @($Security.PhysicalDisks) } else { @() }
    if ($disks.Count -gt 0 -and -not ($disks | Where-Object { $_.MediaType -eq 'SSD' })) {
        $result += @{ Kind = 'info'; Text = 'In diesem PC steckt keine SSD. Der Umstieg von Festplatte auf SSD bringt beim Arbeitstempo mehr als jede andere einzelne Maßnahme.' }
    }
    if ($Info.RamTotalBytes -gt 0 -and $Info.RamTotalBytes -lt 8GB) {
        $free = $Info.RamSlots - $Info.RamSlotsUsed
        $where = if ($free -gt 0) {
            "$free Steckplatz/Steckplätze sind noch frei"
        } else {
            "alle $($Info.RamSlots) Steckplätze sind belegt, die Riegel müssten getauscht werden"
        }
        $result += @{ Kind = 'info'; Text = "Mit $(Format-WzBytes $Info.RamTotalBytes) Arbeitsspeicher wird es bei mehreren offenen Programmen eng — $where." }
    }

    return @($result)
}

function New-WzUserDataReport {
    <#
    .SYNOPSIS
        Übernahme-Bericht: die Abhakliste vor dem Neuaufsetzen.
    .OUTPUTS
        Pfad der Datei.
    #>
    param([Parameter(Mandatory = $true)]$Overview)

    $profiles = @($Overview.Profiles)
    $outlook = @($Overview.Outlook)
    $browsers = @($Overview.Browsers)
    $wlan = @($Overview.Wlan)
    $encrypted = @($Overview.Encrypted)
    $printers = @($Overview.Printers)
    $netDrives = @($Overview.NetDrives)
    $totalBytes = [int64](($profiles | Measure-Object -Property TotalBytes -Sum).Sum)

    # --- Was zuerst schiefgehen kann --------------------------------------
    $content = ''
    if ($Overview.OneDrive.PlaceholderWarning) {
        $content += New-WzHtmlNote -Text $Overview.OneDrive.PlaceholderWarning -Kind 'warn'
    }
    if ($encrypted.Count -gt 0) {
        $content += New-WzHtmlNote -Kind 'warn' -Text (
            "BitLocker ist auf $($encrypted -join ', ') aktiv. Ohne gesicherten Wiederherstellungsschlüssel " +
            'ist das Laufwerk nach einem Mainboardtausch oder BIOS-Update nicht mehr zu öffnen.')
    }

    $content += New-WzHtmlSection -Title 'Umfang' `
        -Lead 'Was gesichert werden muss, bevor der PC neu aufgesetzt wird.' `
        -Body (New-WzHtmlCard -Title 'Auf einen Blick' -Rows @(
            "Persönliche Daten|$(Format-WzBytes $totalBytes) in $($profiles.Count) Benutzerkonto/-konten"
            "Outlook|$($outlook.Count) Datendatei(en)"
            "Browser|$($browsers.Count) Profil(e) gefunden"
            "WLAN-Netze|$($wlan.Count) gespeichert"
            "Drucker|$($printers.Count)"
            "Netzlaufwerke|$($netDrives.Count)"
        ))

    # --- Benutzerprofile ---------------------------------------------------
    # Die Tabellen brauchen immer ein Feld — ein leeres foreach liefert $null,
    # und New-WzHtmlTable lehnt das ab.
    $profileRows = @(foreach ($profileEntry in $profiles) {
        $folders = @($profileEntry.Folders | ForEach-Object { "$($_.Name) $(Format-WzBytes $_.Bytes)" })
        $breakdown = if ($folders.Count -gt 0) {
            $folders -join ' · '
        } elseif ($profileEntry.Accessible) {
            'vorhanden, aber leer'
        } else {
            'kein Zugriff'
        }
        [pscustomobject]@{
            Konto   = $profileEntry.Account
            Pfad    = $profileEntry.Path
            Groesse = Format-WzBytes $profileEntry.TotalBytes
            Ordner  = $breakdown
        }
    })
    $content += New-WzHtmlSection -Title 'Benutzerdaten' `
        -Lead 'Größe der persönlichen Ordner je Konto.' `
        -Body (New-WzHtmlTable -Data $profileRows -Columns @(
            'Konto|Konto', 'Pfad|Ordner|mono', 'Groesse|Größe|num', 'Ordner|Aufteilung'
        ) -EmptyText 'Keine Benutzerprofile gefunden.')

    # --- OneDrive ----------------------------------------------------------
    $oneDriveBody = if (-not $Overview.OneDrive.Configured) {
        New-WzHtmlNote -Text 'OneDrive ist auf diesem PC nicht eingerichtet.' -Kind 'info'
    } else {
        $rows = @(foreach ($folder in $Overview.OneDrive.Folders) {
            [pscustomobject]@{
                Konto  = $folder.Account
                Pfad   = $folder.Path
                Lokal  = "$(Format-WzBytes $folder.LocalBytes) · $($folder.LocalFiles) Datei(en)"
                Cloud  = if ($folder.CloudOnly -gt 0) {
                    "<span class=`"tag tag-warn`">$($folder.CloudOnly) nur online</span>"
                } else { 'keine' }
            }
        })
        New-WzHtmlTable -Data $rows -Columns @(
            'Konto|Konto', 'Pfad|Ordner|mono', 'Lokal|Auf der Platte', 'Cloud|Platzhalter'
        )
    }
    $content += New-WzHtmlSection -Title 'OneDrive' `
        -Lead 'Platzhalter sehen im Explorer aus wie Dateien, enthalten aber nichts. Vor dem Kopieren herunterladen.' `
        -Body $oneDriveBody

    # --- Outlook und Browser ----------------------------------------------
    $outlookRows = @(foreach ($file in $outlook) {
        [pscustomobject]@{
            Datei   = $file.Name
            Pfad    = $file.Path
            Groesse = Format-WzBytes $file.Bytes
            Art     = $file.Kind
        }
    })
    $content += New-WzHtmlSection -Title 'Outlook' `
        -Lead 'PST-Dateien enthalten Daten, die es nur auf diesem PC gibt.' `
        -Body (New-WzHtmlTable -Data $outlookRows -Columns @(
            'Datei|Datei|mono', 'Pfad|Pfad|mono', 'Groesse|Größe|num', 'Art|Bedeutung'
        ) -EmptyText 'Keine Outlook-Datendateien gefunden.')

    $browserRows = @(foreach ($browser in $browsers) {
        [pscustomobject]@{
            Browser     = $browser.Name
            Pfad        = $browser.Path
            Groesse     = Format-WzBytes $browser.Bytes
            Lesezeichen = "$(@($browser.BookmarkFiles).Count) Profil(e)"
        }
    })
    $content += New-WzHtmlSection -Title 'Browser' `
        -Lead 'Gespeicherte Passwörter sind an den PC gebunden und lassen sich nicht mitnehmen.' `
        -Body (New-WzHtmlTable -Data $browserRows -Columns @(
            'Browser|Browser', 'Pfad|Profilordner|mono', 'Groesse|Größe|num', 'Lesezeichen|Lesezeichen'
        ) -EmptyText 'Keine Browser-Profile gefunden.')

    # --- Zugänge und Geräte ------------------------------------------------
    $keyRows = @()
    $keys = $Overview.Keys
    $keyRows += if ($keys.FirmwareKey) {
        'Windows-Schlüssel im UEFI|vorhanden und auslesbar|ok'
    } else {
        'Windows-Schlüssel im UEFI|keiner hinterlegt (Volumen- oder Kontolizenz)'
    }
    if ($keys.Channel) { $keyRows += "Lizenzart|$($keys.Channel), endet auf $($keys.PartialKey)" }
    foreach ($office in @($keys.Office)) { $keyRows += "Office|$($office.Name) ($($office.Channel))" }
    $keyRows += if ($wlan.Count -gt 0) { "WLAN-Netze|$($wlan -join ', ')" } else { 'WLAN-Netze|keine gespeichert' }
    $keyRows += if ($encrypted.Count -gt 0) {
        "BitLocker|aktiv auf $($encrypted -join ', ')|warn"
    } else {
        'BitLocker|nicht aktiv'
    }

    $deviceRows = @()
    foreach ($printer in $printers) {
        $marker = if ($printer.IsDefault) { ' (Standard)' } else { '' }
        $deviceRows += "Drucker$marker|$($printer.Name) an $($printer.Port)"
    }
    foreach ($drive in $netDrives) { $deviceRows += "Laufwerk $($drive.Letter)|$($drive.Target)" }
    if ($deviceRows.Count -eq 0) { $deviceRows += 'Geräte|kein Drucker, kein Netzlaufwerk eingerichtet' }

    $content += New-WzHtmlSection -Title 'Zugänge und Geräte' `
        -Lead 'Damit der PC nach dem Neuaufsetzen wieder so arbeitet wie vorher.' `
        -Body ((New-WzHtmlCard -Title 'Schlüssel und Zugänge' -Rows $keyRows) +
               (New-WzHtmlCard -Title 'Drucker und Netzlaufwerke' -Rows $deviceRows))

    $meta = @(
        "Computer|$env:COMPUTERNAME"
        "Datum|$(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        "Umfang|$(Format-WzBytes $totalBytes)"
        "Konten|$($profiles.Count)"
    )

    $file = New-WzHtmlReport -Title 'Übernahme-Bericht' -Eyebrow 'ÜBERNAHME' `
        -Subtitle "Bestandsaufnahme der Daten auf $env:COMPUTERNAME vor der Neuinstallation." `
        -Meta $meta -Content $content `
        -FileName "uebernahme-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog "Übernahme-Bericht gespeichert: $file" -Level Ok
    return $file
}

function Export-WzProtocol {
    <#
    .SYNOPSIS
        Schreibt das Sitzungsprotokoll als HTML-Bericht.
    .OUTPUTS
        Pfad der Datei.
    #>
    [CmdletBinding()]
    param([switch]$Open)

    $entries = Get-WzLogEntries
    $info = $syncHash.SystemInfo

    $logLines = foreach ($entry in $entries) {
        $class = 'lvl-' + $entry.Level.ToLower()
        '<div class="{0}">{1}  {2}</div>' -f $class, $entry.Time, (ConvertTo-WzHtmlText $entry.Message)
    }

    $counts = $entries | Group-Object Level | ForEach-Object { "$($_.Name): $($_.Count)" }
    $duration = if ($syncHash.SessionStart) {
        Format-WzUptime ((Get-Date) - $syncHash.SessionStart)
    } else { 'n/v' }

    $summaryRows = @(
        "Computer|$env:COMPUTERNAME"
        "Benutzer|$env:USERDOMAIN\$env:USERNAME"
        "Beginn|$(if ($syncHash.SessionStart) { $syncHash.SessionStart.ToString('dd.MM.yyyy HH:mm:ss') } else { 'n/v' })"
        "Dauer|$duration"
        "Einträge|$($entries.Count)  ($($counts -join ', '))"
    )
    if ($info) {
        $summaryRows += "Windows|$($info.OsCaption) $($info.OsVersion) (Build $($info.OsBuild))"
        $summaryRows += "Gerät|$($info.Manufacturer) $($info.Model)"
    }
    if ($syncHash.DryRun) {
        $summaryRows += 'Modus|Testmodus — keine Änderungen ausgeführt|warn'
    }

    $content = New-WzHtmlSection -Title 'Zusammenfassung' `
        -Body (New-WzHtmlCard -Title 'Sitzung' -Rows $summaryRows)

    $content += New-WzHtmlSection -Title 'Verlauf' `
        -Lead 'Alle Schritte dieser Sitzung in zeitlicher Reihenfolge.' `
        -Body ("<div class=`"card log`">`n  $($logLines -join "`n  ")`n</div>")

    $meta = @(
        "Computer|$env:COMPUTERNAME"
        "Datum|$(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        "Schritte|$($entries.Count)"
    )

    $file = New-WzHtmlReport -Title 'Sitzungsprotokoll' -Eyebrow 'PROTOKOLL' `
        -Subtitle "Dokumentation aller Arbeitsschritte auf $env:COMPUTERNAME." `
        -Meta $meta -Content $content `
        -FileName "protokoll-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog "Protokoll gespeichert: $file" -Level Ok
    if ($Open) { Start-Process $file }
    return $file
}
