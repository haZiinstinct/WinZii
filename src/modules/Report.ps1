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
