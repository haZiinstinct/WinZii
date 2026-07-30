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
