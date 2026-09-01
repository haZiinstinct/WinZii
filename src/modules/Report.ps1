# Report — HTML-Berichte im haZii-Design.
# Alle Berichte nutzen dasselbe Grundgerüst (src\templates\report.html) und
# landen unter reports\<hostname>\. Keine externen Ressourcen, damit die
# Datei auch offline und auf fremden PCs unverändert aussieht.

function Get-WzTechnicianProfile {
    <#
    .SYNOPSIS
        Firma, Name, Telefon, E-Mail und Logo des Technikers.
    .DESCRIPTION
        Steht in einstellungen.json neben der Sprache und wird einmal
        eingetragen statt bei jedem Auftrag. Das Uebergabeblatt bekommt damit
        einen eigenen Briefkopf — fuer den Kunden ist es dann ein Papier von
        seinem Techniker und nicht die Ausgabe eines Programms.
    #>
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Company    = [string](Get-WzSetting -Name 'firma')
        Technician = [string](Get-WzSetting -Name 'techniker')
        Phone      = [string](Get-WzSetting -Name 'telefon')
        Mail       = [string](Get-WzSetting -Name 'epost')
        LogoPath   = [string](Get-WzSetting -Name 'logo')
    }
}

function Get-WzLogoDataUri {
    <#
    .SYNOPSIS
        Bilddatei als eingebettete Datenadresse.
    .DESCRIPTION
        Berichte muessen auch dann noch aussehen wie am ersten Tag, wenn sie
        per E-Mail weitergereicht werden und der Stick laengst weg ist.
        Deshalb wird das Logo in die Datei hineingeschrieben statt verlinkt.

        Faellt irgendetwas aus — Datei fehlt, unbekanntes Format, zu gross —
        bleibt der Briefkopf einfach ohne Bild. Ein Bericht ohne Logo ist
        brauchbar, ein Bericht mit einem kaputten Bildplatzhalter nicht.
    #>
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $datei = Get-Item -LiteralPath $Path -ErrorAction Stop
        # Ueber ein Megabyte blaeht jede Berichtsdatei unnoetig auf
        if ($datei.Length -gt 1MB) {
            Write-WzLog (Get-WzText 'rep.logoTooBig' @{ datei = $datei.Name }) -Level Warn
            return ''
        }
        $typ = switch ($datei.Extension.ToLower()) {
            '.png'  { 'image/png' }
            '.jpg'  { 'image/jpeg' }
            '.jpeg' { 'image/jpeg' }
            '.gif'  { 'image/gif' }
            '.svg'  { 'image/svg+xml' }
            default { '' }
        }
        if (-not $typ) {
            Write-WzLog (Get-WzText 'rep.logoUnknownType' @{ datei = $datei.Name }) -Level Warn
            return ''
        }
        $bytes = [IO.File]::ReadAllBytes($datei.FullName)
        return "data:$typ;base64,$([Convert]::ToBase64String($bytes))"
    } catch {
        Write-WzLog (Get-WzText 'rep.logoFailed' @{ grund = $_.Exception.Message }) -Level Warn
        return ''
    }
}

function New-WzSenderBlock {
    <#
    .SYNOPSIS
        Der Briefkopf des Technikers als HTML — leer, wenn nichts hinterlegt ist.
    #>
    param($Profile)

    if (-not $Profile) { return '' }
    $zeilen = @()
    foreach ($wert in @($Profile.Technician, $Profile.Phone, $Profile.Mail)) {
        if ($wert) { $zeilen += ConvertTo-WzHtmlText $wert }
    }
    $logo = Get-WzLogoDataUri -Path $Profile.LogoPath
    if (-not $Profile.Company -and $zeilen.Count -eq 0 -and -not $logo) { return '' }

    $bild = if ($logo) { '<img class="sender-logo" src="' + $logo + '" alt="" />' } else { '' }
    $firma = if ($Profile.Company) { '<strong>' + (ConvertTo-WzHtmlText $Profile.Company) + '</strong>' } else { '' }
    $rest = if ($zeilen.Count -gt 0) { '<span>' + ($zeilen -join ' &middot; ') + '</span>' } else { '' }
    return "<div class=`"sender`">$bild<div class=`"sender-text`">$firma$rest</div></div>"
}

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
        [string]$Eyebrow = (Get-WzText 'rep.eyebrowDefault'),
        [string]$Subtitle = '',
        [string[]]$Meta = @(),
        [string]$FileName
    )

    $templatePath = Join-Path (Get-WzTemplateDir) 'report.html'
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw (Get-WzText 'rep.templateMissing' @{ pfad = $templatePath })
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
        Replace('{{LANG}}', $syncHash.Language).
        Replace('{{TITLE}}', (ConvertTo-WzHtmlText $Title)).
        Replace('{{EYEBROW}}', (ConvertTo-WzHtmlText $Eyebrow)).
        Replace('{{SUBTITLE}}', (ConvertTo-WzHtmlText $Subtitle)).
        Replace('{{META}}', $metaHtml).
        Replace('{{SENDER}}', (New-WzSenderBlock -Profile (Get-WzTechnicianProfile))).
        Replace('{{CONTENT}}', $Content).
        Replace('{{VERSION}}', $syncHash.Version).
        Replace('{{CREATED}}', (Get-WzText 'rep.footerCreated' @{ zeit = (Get-Date).ToString('g', (Get-WzLanguageCulture)) })).
        Replace('{{CODELABEL}}', (ConvertTo-WzHtmlText (Get-WzText 'rep.codeLink')))

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
        [string]$EmptyText = (Get-WzText 'rep.tableEmpty')
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

function Get-WzAreaLabel {
    <#
    .SYNOPSIS
        Uebersetzt den Bereichsnamen einer Aktion fuer die Anzeige.
    .DESCRIPTION
        Add-WzAction bekommt den Bereich als festen deutschen Bezeichner
        uebergeben — er dient dem Gruppieren und darf sich mit der Sprache
        nicht aendern. Uebersetzt wird deshalb erst hier, beim Ausgeben.

        Die Zweige stehen einzeln da, damit Test-Language die Schluessel im
        Code findet; ein zusammengesetzter Schluessel waere fuer die Pruefung
        unsichtbar. Ein unbekannter Bereich geht unveraendert durch: die
        Optimierungsseite reicht den bereits uebersetzten Kategorienamen
        durch.
    #>
    param([string]$Area)

    switch ($Area) {
        'Autostart'           { return Get-WzText 'rep.areaAutostart' }
        'Datensicherung'      { return Get-WzText 'rep.areaBackup' }
        'Office'              { return Get-WzText 'rep.areaOffice' }
        'Programme'           { return Get-WzText 'rep.areaPrograms' }
        'Reparatur'           { return Get-WzText 'rep.areaRepair' }
        'Rücknahme'           { return Get-WzText 'rep.areaUndo' }
        'Sicherheit'          { return Get-WzText 'rep.areaSecurity' }
        'Sicherung'           { return Get-WzText 'rep.areaRestorePoint' }
        'Speicherplatz'       { return Get-WzText 'rep.areaDiskSpace' }
        'Treiber'             { return Get-WzText 'rep.areaDrivers' }
        'Updates'             { return Get-WzText 'rep.areaUpdates' }
        'Vorinstallierte Apps' { return Get-WzText 'rep.areaPreinstalled' }
        'Zurückspielen'       { return Get-WzText 'rep.areaRestore' }
        default               { return $Area }
    }
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
    $diskProblems = @($disks | Where-Object { -not $_.AssessmentOk })

    # --- Gesamteinschätzung -----------------------------------------------
    $verdict = if ($dumps.Count -gt 0 -or $diskProblems.Count -gt 0) {
        @{ Kind = 'err'; Text = (Get-WzText 'rep.diagVerdictErr') }
    } elseif ($critical.Count -gt 0) {
        @{ Kind = 'warn'; Text = (Get-WzText 'rep.diagVerdictWarn') }
    } elseif ($events.Count -gt 0) {
        @{ Kind = 'info'; Text = (Get-WzText 'rep.diagVerdictInfo') }
    } else {
        @{ Kind = 'ok'; Text = (Get-WzText 'rep.diagVerdictOk') }
    }

    $content = New-WzHtmlSection -Title (Get-WzText 'rep.secAssessment') `
        -Body ((New-WzHtmlNote -Text $verdict.Text -Kind $verdict.Kind) + (New-WzHtmlCard -Title (Get-WzText 'rep.cardGlance') -Rows @(
            "$(Get-WzText 'rep.rowEvents')|$(Get-WzText 'rep.valEvents' @{ anzahl = $events.Count; kritisch = $critical.Count })"
            "$(Get-WzText 'rep.rowCrashes')|$(Get-WzText 'rep.valCrashes' @{ anzahl = $dumps.Count })"
            "$(Get-WzText 'rep.rowDisks')|$(Get-WzText 'rep.valDisks' @{ anzahl = $disks.Count; auffaellig = $diskProblems.Count })"
            "$(Get-WzText 'rep.rowPeriod')|$(Get-WzText 'rep.valPeriodDays' @{ tage = $Result.Days })"
        )))

    # --- System -----------------------------------------------------------
    if ($info) {
        $systemRows = @(
            "$(Get-WzText 'rep.rowComputer')|$($info.ComputerName)"
            "$(Get-WzText 'rep.rowWindows')|$(Get-WzText 'rep.valWindows' @{ name = $info.OsCaption; version = $info.OsVersion; build = $info.OsBuild })"
            "$(Get-WzText 'rep.rowDevice')|$($info.Manufacturer) $($info.Model)"
            "$(Get-WzText 'rep.rowCpu')|$($info.CpuName)"
            "$(Get-WzText 'rep.rowRam')|$(Get-WzText 'rep.valRam' @{ groesse = (Format-WzBytes $info.RamTotalBytes); prozent = $info.RamUsedPercent })"
            "$(Get-WzText 'rep.rowUptime')|$(Format-WzUptime $info.Uptime)"
        )
        if ($security) {
            $activationKind = if ($security.ActivationOk) { 'ok' } else { 'warn' }
            $systemRows += "$(Get-WzText 'rep.rowActivation')|$($security.Activation)|$activationKind"
            $systemRows += "$(Get-WzText 'rep.rowDefender')|$($security.Defender)|$(if ($security.DefenderOk) { 'ok' } else { 'warn' })"
        }
        if ($info.PendingReboot) {
            $systemRows += "$(Get-WzText 'rep.rowReboot')|$(Get-WzText 'rep.valRebootPending' @{ grund = $info.PendingReboot })|warn"
        }
        $content += New-WzHtmlSection -Title (Get-WzText 'rep.secSystem') -Body (New-WzHtmlCard -Title (Get-WzText 'rep.cardSpecs') -Rows $systemRows)
    }

    # --- Ereignisse -------------------------------------------------------
    $eventBody = if ($events.Count -eq 0) {
        New-WzHtmlNote -Text (Get-WzText 'rep.diagNoEvents') -Kind 'ok'
    } else {
        $rows = foreach ($event in $events) {
            $tagClass = switch ($event.Severity) {
                'critical' { 'tag-err' }
                'error'    { 'tag-warn' }
                default    { 'tag-info' }
            }
            $label = switch ($event.Severity) {
                'critical' { Get-WzText 'rep.sevCritical' }
                'error'    { Get-WzText 'rep.sevError' }
                default    { Get-WzText 'rep.sevNotice' }
            }
            [pscustomobject]@{
                Stufe    = "<span class=`"tag $tagClass`">$label</span>"
                Titel    = $event.Title
                Anzahl   = $event.Count
                Zuletzt  = $event.Last.ToString('g', (Get-WzLanguageCulture))
                Deutung  = if ($event.Explanation) { "$($event.Explanation) $($event.Recommendation)" } else { $event.Sample }
                Quelle   = "$($event.Provider) / $($event.Id)"
            }
        }
        New-WzHtmlTable -Data $rows -Columns @(
            "Stufe|$(Get-WzText 'rep.colLevel')", "Titel|$(Get-WzText 'rep.colEvent')",
            "Anzahl|$(Get-WzText 'rep.colCount')|num", "Zuletzt|$(Get-WzText 'rep.colLast')|num",
            "Deutung|$(Get-WzText 'rep.colMeaning')", "Quelle|$(Get-WzText 'rep.colSource')|mono"
        )
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secEvents') `
        -Lead (Get-WzText 'rep.leadEvents' @{ tage = $Result.Days }) `
        -Body $eventBody

    # --- Abstürze ---------------------------------------------------------
    $dumpBody = if ($dumps.Count -eq 0) {
        New-WzHtmlNote -Text (Get-WzText 'rep.diagNoDumps') -Kind 'ok'
    } else {
        $rows = foreach ($dump in $dumps) {
            [pscustomobject]@{
                Zeit    = $dump.Time.ToString('g', (Get-WzLanguageCulture))
                Code    = $dump.Code
                Name    = $dump.Name
                Ursache = "$($dump.Cause) $($dump.Recommendation)"
                Datei   = $dump.File
            }
        }
        New-WzHtmlTable -Data $rows -Columns @(
            "Zeit|$(Get-WzText 'rep.colTime')|num", "Code|$(Get-WzText 'rep.colStopCode')|mono",
            "Name|$(Get-WzText 'rep.colName')|mono", "Ursache|$(Get-WzText 'rep.colCauseRec')",
            "Datei|$(Get-WzText 'rep.colDump')|mono"
        )
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secCrashes') `
        -Lead (Get-WzText 'rep.leadCrashes') -Body $dumpBody

    # --- Startdauer -------------------------------------------------------
    # Die Werte wurden schon immer erhoben und in den Bericht hineingereicht,
    # kamen dort aber nie an. »74 s Start, davon 48 s Dropbox« ist das Argument,
    # das den Kunden zum Aufräumen bewegt.
    $boot = $Result.Boot
    $bootBody = if (-not $boot -or @($boot.Runs).Count -eq 0) {
        New-WzHtmlNote -Kind 'info' -Text $(if ($boot -and $boot.Hint) { $boot.Hint } else { Get-WzText 'rep.bootNone' })
    } else {
        $bootKind = if ($boot.AverageSeconds -lt 30) { 'ok' } elseif ($boot.AverageSeconds -lt 60) { 'warn' } else { 'err' }
        $bootHtml = New-WzHtmlNote -Kind $bootKind -Text (Get-WzText 'rep.bootAverage' @{
            dauer = (Format-WzSeconds $boot.AverageSeconds -Unit (Get-WzText 'diag.unitSeconds')); hinweis = $boot.Hint })

        $bootRows = @(foreach ($run in @($boot.Runs)) {
            [pscustomobject]@{
                Zeit    = $run.Time.ToString('g', (Get-WzLanguageCulture))
                Gesamt  = Format-WzSeconds $run.TotalSeconds
                Windows = Format-WzSeconds ($run.MainPathMs / 1000)
                Danach  = Format-WzSeconds ([int]$run.DegradedBy / 1000)
            }
        })
        $bootHtml += New-WzHtmlTable -Data $bootRows -Columns @(
            "Zeit|$(Get-WzText 'rep.colBootRun')|num", "Gesamt|$(Get-WzText 'rep.colTotal')|num",
            "Windows|$(Get-WzText 'rep.colWindowsShare')|num", "Danach|$(Get-WzText 'rep.colAutostartShare')|num"
        )

        if (@($boot.Worst).Count -gt 0) {
            $culpritRows = @(foreach ($culprit in @($boot.Worst)) {
                [pscustomobject]@{
                    Name       = $culprit.Name
                    Verzoegert = Format-WzSeconds $culprit.DelaySeconds
                    Zeit       = $culprit.Time.ToString('g', (Get-WzLanguageCulture))
                }
            })
            $bootHtml += New-WzHtmlTable -Data $culpritRows -Columns @(
                "Name|$(Get-WzText 'rep.colSlowsStart')", "Verzoegert|$(Get-WzText 'rep.colDelay')|num",
                "Zeit|$(Get-WzText 'rep.colMeasured')|num"
            )
        }
        $bootHtml
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secBoot') `
        -Lead (Get-WzText 'rep.leadBoot') `
        -Body $bootBody

    # --- Zuverlässigkeit --------------------------------------------------
    # Beantwortet die Frage, die die Ereignisliste nicht beantworten kann:
    # Was wurde an dem Tag installiert, an dem die Probleme anfingen?
    $reliability = @($Result.Reliability)
    if ($reliability.Count -gt 0) {
        $reliabilityRows = @(foreach ($record in $reliability) {
            [pscustomobject]@{
                Zeit    = $record.Time.ToString('g', (Get-WzLanguageCulture))
                Art     = $record.Type
                Was     = $record.Source
                Details = $record.Message
            }
        })
        $content += New-WzHtmlSection -Title (Get-WzText 'rep.secReliability') `
            -Lead (Get-WzText 'rep.leadReliability') `
            -Body (New-WzHtmlTable -Data $reliabilityRows -Columns @(
                "Zeit|$(Get-WzText 'rep.colTime')|num", "Art|$(Get-WzText 'rep.colKind')",
                "Was|$(Get-WzText 'rep.colSource')", "Details|$(Get-WzText 'rep.colDetails')"
            ))
    }

    # --- Datenträger ------------------------------------------------------
    $diskBody = if ($disks.Count -eq 0) {
        New-WzHtmlNote -Text (Get-WzText 'rep.diagNoDisks') -Kind 'info'
    } else {
        $rows = foreach ($disk in $disks) {
            $tag = if ($disk.AssessmentOk) { 'tag-ok' } else { 'tag-warn' }
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
            "Modell|$(Get-WzText 'rep.colModel')", "Art|$(Get-WzText 'rep.colKind')",
            "Groesse|$(Get-WzText 'rep.colSize')|num", "Betrieb|$(Get-WzText 'rep.colPowerOn')",
            "Temperatur|$(Get-WzText 'rep.colTemperature')|num", "Abnutzung|$(Get-WzText 'rep.colWear')|num",
            "Zustand|$(Get-WzText 'rep.colHealth')"
        )
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secDisks') `
        -Lead (Get-WzText 'rep.leadDisks') `
        -Body $diskBody

    $meta = @(
        "$(Get-WzText 'rep.rowComputer')|$env:COMPUTERNAME"
        "$(Get-WzText 'rep.metaDate')|$((Get-Date).ToString('g', (Get-WzLanguageCulture)))"
        "$(Get-WzText 'rep.rowPeriod')|$(Get-WzText 'rep.valPeriodDays' @{ tage = $Result.Days })"
        "$(Get-WzText 'rep.metaFindings')|$($events.Count)"
    )

    $file = New-WzHtmlReport -Title (Get-WzText 'rep.diagTitle') -Eyebrow (Get-WzText 'rep.diagEyebrow') `
        -Subtitle (Get-WzText 'rep.diagSubtitle' @{ pc = $env:COMPUTERNAME }) `
        -Meta $meta -Content $content `
        -FileName "$(Get-WzText 'rep.diagFile')-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog (Get-WzText 'rep.logDiagSaved' @{ datei = $file }) -Level Ok
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
        $content += New-WzHtmlNote -Kind 'info' -Text (Get-WzText 'rep.hoNothingChanged')
    } elseif (@($actions | Where-Object { $_.IsTest }).Count -eq $actions.Count) {
        $content += New-WzHtmlNote -Kind 'warn' -Text (Get-WzText 'rep.hoAllDryRun')
    }

    $groups = $actions | Group-Object Area
    $workBody = if ($actions.Count -eq 0) {
        New-WzHtmlNote -Kind 'info' -Text (Get-WzText 'rep.hoNoWork')
    } else {
        $rows = @(foreach ($group in $groups) {
            $summaries = @($group.Group | ForEach-Object {
                if ($_.IsTest) { Get-WzText 'rep.hoDryRunItem' @{ text = $_.Summary } } else { $_.Summary }
            })
            # Add-WzAction sammelt seit jeher die Einzelposten mit ein — bisher
            # landeten sie nirgends. Der Kunde soll sehen, WELCHE Programme
            # entfernt wurden, nicht nur wie viele.
            $details = @($group.Group | ForEach-Object { $_.Detail } | Where-Object { $_ })
            [pscustomobject]@{
                Bereich    = Get-WzAreaLabel $group.Name
                Anzahl     = $group.Count
                Was        = $summaries -join ' · '
                Einzelnes  = if ($details.Count -gt 0) { $details -join ', ' } else { '—' }
            }
        })
        New-WzHtmlTable -Data $rows -Columns @(
            "Bereich|$(Get-WzText 'rep.colArea')", "Anzahl|$(Get-WzText 'rep.colSteps')|num",
            "Was|$(Get-WzText 'rep.colWhat')", "Einzelnes|$(Get-WzText 'rep.colItems')"
        )
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secWork') `
        -Lead (Get-WzText 'rep.leadWork') -Body $workBody

    # --- Vorher und nachher ------------------------------------------------
    if ($before) {
        $diskRows = @(foreach ($volume in $after.Volumes) {
            $old = $before.Volumes | Where-Object { $_.Letter -eq $volume.Letter } | Select-Object -First 1
            $gained = if ($old) { $volume.FreeBytes - $old.FreeBytes } else { 0 }
            $change = if (-not $old) {
                Get-WzText 'rep.noBaseline'
            } elseif ($gained -gt 0) {
                "<span class=`"tag tag-ok`">+$(Format-WzBytes $gained)</span>"
            } elseif ($gained -lt 0) {
                "-$(Format-WzBytes ([math]::Abs($gained)))"
            } else { Get-WzText 'rep.unchanged' }

            [pscustomobject]@{
                Laufwerk = "$($volume.Letter) $($volume.Label)".Trim()
                Vorher   = if ($old) { Format-WzBytes $old.FreeBytes } else { Get-WzText 'core.na' }
                Nachher  = Format-WzBytes $volume.FreeBytes
                Aenderung = $change
                Belegt   = "$($volume.UsedPercent) %"
            }
        })
        $content += New-WzHtmlSection -Title (Get-WzText 'rep.secSpace') `
            -Lead (Get-WzText 'rep.leadSpace') `
            -Body (New-WzHtmlTable -Data $diskRows -Columns @(
                "Laufwerk|$(Get-WzText 'rep.colDrive')", "Vorher|$(Get-WzText 'rep.colBefore')|num",
                "Nachher|$(Get-WzText 'rep.colAfter')|num", "Aenderung|$(Get-WzText 'rep.colGained')",
                "Belegt|$(Get-WzText 'rep.colUsed')|num"
            ))
    }

    # --- Geräteblatt -------------------------------------------------------
    $chassis = if ($after.IsLaptop) { Get-WzText 'dash.chassisNotebook' } else { Get-WzText 'dash.chassisDesktop' }
    $bios = if ($after.BiosDate) {
        Get-WzText 'rep.valBiosDated' @{ version = $after.BiosVersion; datum = $after.BiosDate.ToString('d', (Get-WzLanguageCulture)) }
    } else { $after.BiosVersion }
    $deviceRows = @(
        "$(Get-WzText 'rep.rowComputer')|$($after.ComputerName)"
        "$(Get-WzText 'rep.rowDevice')|$(Get-WzText 'rep.valDevice' @{ hersteller = $after.Manufacturer; modell = $after.Model; bauform = $chassis })"
        "$(Get-WzText 'rep.rowWindows')|$(Get-WzText 'rep.valWindows' @{ name = $after.OsCaption; version = $after.OsVersion; build = $after.OsBuild })"
        "$(Get-WzText 'rep.rowLanguage')|$($after.OsLanguage)"
        "$(Get-WzText 'rep.rowCpu')|$($after.CpuName)"
        "$(Get-WzText 'rep.rowRam')|$(Get-WzText 'rep.valRamSlots' @{ groesse = (Format-WzBytes $after.RamTotalBytes)
            belegt = $after.RamSlotsUsed; slots = $after.RamSlots; max = (Format-WzBytes $after.RamMaxBytes) })"
    )
    if ($after.InstallDate) { $deviceRows += "$(Get-WzText 'rep.rowInstalledOn')|$($after.InstallDate.ToString('d', (Get-WzLanguageCulture)))" }
    if (@($after.Gpus).Count -gt 0) { $deviceRows += "$(Get-WzText 'rep.rowGraphics')|$(@($after.Gpus)[0].Name)" }
    if (@($after.Monitors).Count -gt 0) {
        $deviceRows += "$(Get-WzText 'rep.rowMonitors')|$((@($after.Monitors) | ForEach-Object { "$($_.Vendor) $($_.Name)".Trim() }) -join ', ')"
    }
    $deviceRows += "$(Get-WzText 'rep.rowBios')|$bios"
    if ($after.SerialNumber) { $deviceRows += "$(Get-WzText 'rep.rowSerial')|$($after.SerialNumber)" }
    if ($after.Battery.Present) { $deviceRows += "$(Get-WzText 'rep.rowBattery')|$($after.Battery.Verdict)" }
    # Die MAC-Adresse steht schon in der Abfrage und wird nirgends gezeigt —
    # dabei braucht sie jeder, der den PC in einem verwalteten Netz freischalten
    # oder eine feste Adresse im Router hinterlegen soll.
    foreach ($adapter in $after.Network) {
        $line = if ($adapter.Mac) {
            Get-WzText 'rep.valNetworkMac' @{ adapter = $adapter.Adapter; ip = $adapter.IPv4; mac = $adapter.Mac }
        } else {
            Get-WzText 'rep.valNetwork' @{ adapter = $adapter.Adapter; ip = $adapter.IPv4 }
        }
        $deviceRows += "$(Get-WzText 'rep.rowNetwork')|$line"
    }

    $securityRows = @()
    if ($security) {
        $securityRows += "$(Get-WzText 'rep.rowActivation')|$($security.Activation)|$(if ($security.ActivationOk) { 'ok' } else { 'warn' })"
        $securityRows += "$(Get-WzText 'rep.rowDefender')|$($security.Defender)|$(if ($security.DefenderOk) { 'ok' } else { 'warn' })"
        $securityRows += "$(Get-WzText 'rep.rowBitLocker')|$($security.BitLocker)"
        $securityRows += "$(Get-WzText 'rep.rowSecureBoot')|$($security.SecureBoot)"
        $securityRows += "$(Get-WzText 'rep.rowTpm')|$($security.Tpm)"
        foreach ($disk in $security.PhysicalDisks) {
            # »Healthy« kommt so aus Windows und bleibt ein Vergleichswert,
            # angezeigt wird die uebersetzte Fassung.
            $health = if ($disk.Health -eq 'Healthy') { Get-WzText 'dash.diskHealthy' } else { $disk.Health }
            $line = Get-WzText 'rep.valDiskLine' @{ modell = $disk.Model; groesse = (Format-WzBytes $disk.SizeBytes); zustand = $health }
            $securityRows += "$($disk.MediaType)|$line|$(if ($disk.Health -eq 'Healthy') { 'ok' } else { 'warn' })"
        }
    } else {
        $securityRows += "$(Get-WzText 'rep.rowNote')|$(Get-WzText 'rep.hoNoSecurity')"
    }

    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secDevice') `
        -Lead (Get-WzText 'rep.leadDevice') `
        -Body ((New-WzHtmlCard -Title (Get-WzText 'rep.cardEquipment') -Rows $deviceRows) +
               (New-WzHtmlCard -Title (Get-WzText 'rep.cardSecurity') -Rows $securityRows))

    # --- Empfehlungen ------------------------------------------------------
    $recommendations = Get-WzHandoverRecommendations -Info $after -Security $security -Actions $actions
    $recommendationBody = if ($recommendations.Count -eq 0) {
        New-WzHtmlNote -Kind 'ok' -Text (Get-WzText 'rep.recNothing')
    } else {
        ($recommendations | ForEach-Object { New-WzHtmlNote -Kind $_.Kind -Text $_.Text }) -join "`n"
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secTodo') `
        -Lead (Get-WzText 'rep.leadTodo') -Body $recommendationBody

    # --- Kopfdaten ---------------------------------------------------------
    $meta = @("$(Get-WzText 'rep.rowComputer')|$env:COMPUTERNAME",
              "$(Get-WzText 'rep.metaDate')|$((Get-Date).ToString('g', (Get-WzLanguageCulture)))")
    if ($Technician) { $meta += "$(Get-WzText 'rep.metaTechnician')|$Technician" }
    if ($Customer) { $meta += "$(Get-WzText 'rep.metaCustomer')|$Customer" }
    if ($OrderNumber) { $meta += "$(Get-WzText 'rep.metaOrder')|$OrderNumber" }
    $meta += "$(Get-WzText 'rep.metaSteps')|$($actions.Count)"

    $file = New-WzHtmlReport -Title (Get-WzText 'rep.hoTitle') -Eyebrow (Get-WzText 'rep.hoEyebrow') `
        -Subtitle (Get-WzText 'rep.hoSubtitle' @{ pc = $env:COMPUTERNAME }) `
        -Meta $meta -Content $content `
        -FileName "$(Get-WzText 'rep.hoFile')-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog (Get-WzText 'rep.logHoSaved' @{ datei = $file }) -Level Ok
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
        $result += @{ Kind = 'warn'; Text = (Get-WzText 'rep.recReboot') }
    }

    foreach ($volume in $Info.Volumes) {
        if ($volume.UsedPercent -ge 90) {
            $result += @{ Kind = 'warn'; Text = (Get-WzText 'rep.recDiskFull' @{ laufwerk = $volume.Letter; prozent = $volume.UsedPercent }) }
        }
    }

    if ($Security) {
        if (-not $Security.DefenderOk) {
            $result += @{ Kind = 'warn'; Text = (Get-WzText 'rep.recDefender' @{ status = $Security.Defender }) }
        }
        if (-not $Security.ActivationOk) {
            $result += @{ Kind = 'warn'; Text = (Get-WzText 'rep.recActivation' @{ status = $Security.Activation }) }
        }
        foreach ($disk in @($Security.PhysicalDisks)) {
            if ($disk.Health -ne 'Healthy') {
                $result += @{ Kind = 'err'; Text = (Get-WzText 'rep.recDiskHealth' @{ modell = $disk.Model; zustand = $disk.Health }) }
            }
        }
        if ($Info.IsLaptop -and -not $Security.BitLockerOn) {
            $result += @{ Kind = 'info'; Text = (Get-WzText 'rep.recBitLocker') }
        }
    }

    if ($Info.Battery.Present -and $null -ne $Info.Battery.WearPercent -and $Info.Battery.WearPercent -ge 40) {
        $result += @{ Kind = 'warn'; Text = (Get-WzText 'rep.recBattery' @{ prozent = $Info.Battery.WearPercent }) }
    }

    # Aufrüsten: Beide Zahlen liegen längst vor. Nur wenn gar keine SSD verbaut
    # ist, läuft Windows sicher von einer Festplatte — eine zusätzliche Daten-HDD
    # neben einer SSD ist völlig in Ordnung und darf hier nichts auslösen.
    $disks = if ($Security) { @($Security.PhysicalDisks) } else { @() }
    if ($disks.Count -gt 0 -and -not ($disks | Where-Object { $_.MediaType -eq 'SSD' })) {
        $result += @{ Kind = 'info'; Text = (Get-WzText 'rep.recNoSsd') }
    }
    if ($Info.RamTotalBytes -gt 0 -and $Info.RamTotalBytes -lt 8GB) {
        $free = $Info.RamSlots - $Info.RamSlotsUsed
        $where = if ($free -gt 0) {
            Get-WzText 'rep.recRamFree' @{ anzahl = $free }
        } else {
            Get-WzText 'rep.recRamAllUsed' @{ anzahl = $Info.RamSlots }
        }
        $result += @{ Kind = 'info'; Text = (Get-WzText 'rep.recRam' @{ groesse = (Format-WzBytes $Info.RamTotalBytes); wo = $where }) }
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
            Get-WzText 'rep.udEncrypted' @{ laufwerke = ($encrypted -join ', ') })
    }

    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secScope') `
        -Lead (Get-WzText 'rep.leadScope') `
        -Body (New-WzHtmlCard -Title (Get-WzText 'rep.cardGlance') -Rows @(
            "$(Get-WzText 'rep.rowPersonalData')|$(Get-WzText 'rep.valPersonalData' @{ groesse = (Format-WzBytes $totalBytes); anzahl = $profiles.Count })"
            "$(Get-WzText 'rep.rowOutlook')|$(Get-WzText 'rep.valOutlookFiles' @{ anzahl = $outlook.Count })"
            "$(Get-WzText 'rep.rowBrowsers')|$(Get-WzText 'rep.valBrowserProfiles' @{ anzahl = $browsers.Count })"
            "$(Get-WzText 'rep.rowWlan')|$(Get-WzText 'rep.valWlanSaved' @{ anzahl = $wlan.Count })"
            "$(Get-WzText 'rep.rowPrinters')|$($printers.Count)"
            "$(Get-WzText 'rep.rowNetDrives')|$($netDrives.Count)"
        ))

    # --- Benutzerprofile ---------------------------------------------------
    # Die Tabellen brauchen immer ein Feld — ein leeres foreach liefert $null,
    # und New-WzHtmlTable lehnt das ab.
    $profileRows = @(foreach ($profileEntry in $profiles) {
        $folders = @($profileEntry.Folders | ForEach-Object { "$($_.Name) $(Format-WzBytes $_.Bytes)" })
        $breakdown = if ($folders.Count -gt 0) {
            $folders -join ' · '
        } elseif ($profileEntry.Accessible) {
            Get-WzText 'rep.udFolderEmpty'
        } else {
            Get-WzText 'rep.udNoAccess'
        }
        [pscustomobject]@{
            Konto   = $profileEntry.Account
            Pfad    = $profileEntry.Path
            Groesse = Format-WzBytes $profileEntry.TotalBytes
            Ordner  = $breakdown
        }
    })
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secUserData') `
        -Lead (Get-WzText 'rep.leadUserData') `
        -Body (New-WzHtmlTable -Data $profileRows -Columns @(
            "Konto|$(Get-WzText 'rep.colAccount')", "Pfad|$(Get-WzText 'rep.colFolder')|mono",
            "Groesse|$(Get-WzText 'rep.colSize')|num", "Ordner|$(Get-WzText 'rep.colBreakdown')"
        ) -EmptyText (Get-WzText 'rep.udNoProfiles'))

    # --- OneDrive ----------------------------------------------------------
    $oneDriveBody = if (-not $Overview.OneDrive.Configured) {
        New-WzHtmlNote -Text (Get-WzText 'rep.udNoOneDrive') -Kind 'info'
    } else {
        $rows = @(foreach ($folder in $Overview.OneDrive.Folders) {
            [pscustomobject]@{
                Konto  = $folder.Account
                Pfad   = $folder.Path
                Lokal  = Get-WzText 'rep.udOneDriveLocal' @{ groesse = (Format-WzBytes $folder.LocalBytes); anzahl = $folder.LocalFiles }
                Cloud  = if ($folder.CloudOnly -gt 0) {
                    "<span class=`"tag tag-warn`">$(Get-WzText 'rep.udCloudOnly' @{ anzahl = $folder.CloudOnly })</span>"
                } else { Get-WzText 'rep.udNoPlaceholders' }
            }
        })
        New-WzHtmlTable -Data $rows -Columns @(
            "Konto|$(Get-WzText 'rep.colAccount')", "Pfad|$(Get-WzText 'rep.colFolder')|mono",
            "Lokal|$(Get-WzText 'rep.colOnDisk')", "Cloud|$(Get-WzText 'rep.colPlaceholders')"
        )
    }
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secOneDrive') `
        -Lead (Get-WzText 'rep.leadOneDrive') `
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
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.rowOutlook') `
        -Lead (Get-WzText 'rep.leadOutlook') `
        -Body (New-WzHtmlTable -Data $outlookRows -Columns @(
            "Datei|$(Get-WzText 'rep.colFile')|mono", "Pfad|$(Get-WzText 'rep.colPath')|mono",
            "Groesse|$(Get-WzText 'rep.colSize')|num", "Art|$(Get-WzText 'rep.colMeaning2')"
        ) -EmptyText (Get-WzText 'rep.udNoOutlook'))

    $browserRows = @(foreach ($browser in $browsers) {
        [pscustomobject]@{
            Browser     = $browser.Name
            Pfad        = $browser.Path
            Groesse     = Format-WzBytes $browser.Bytes
            Lesezeichen = Get-WzText 'rep.udProfiles' @{ anzahl = @($browser.BookmarkFiles).Count }
        }
    })
    $content += New-WzHtmlSection -Title (Get-WzText 'rep.rowBrowsers') `
        -Lead (Get-WzText 'rep.leadBrowsers') `
        -Body (New-WzHtmlTable -Data $browserRows -Columns @(
            "Browser|$(Get-WzText 'rep.colBrowser')", "Pfad|$(Get-WzText 'rep.colProfileDir')|mono",
            "Groesse|$(Get-WzText 'rep.colSize')|num", "Lesezeichen|$(Get-WzText 'rep.colBookmarks')"
        ) -EmptyText (Get-WzText 'rep.udNoBrowsers'))

    # --- Zugänge und Geräte ------------------------------------------------
    $keyRows = @()
    $keys = $Overview.Keys
    $keyRows += if ($keys.FirmwareKey) {
        "$(Get-WzText 'rep.udKeyUefi')|$(Get-WzText 'rep.udKeyPresent')|ok"
    } else {
        "$(Get-WzText 'rep.udKeyUefi')|$(Get-WzText 'rep.udKeyNone')"
    }
    if ($keys.Channel) {
        $keyRows += "$(Get-WzText 'rep.udLicenseKind')|$(Get-WzText 'rep.udLicenseValue' @{ kanal = $keys.Channel; rest = $keys.PartialKey })"
    }
    foreach ($office in @($keys.Office)) {
        $keyRows += "$(Get-WzText 'rep.rowOffice')|$(Get-WzText 'rep.udOfficeValue' @{ name = $office.Name; kanal = $office.Channel })"
    }
    $keyRows += if ($wlan.Count -gt 0) {
        "$(Get-WzText 'rep.rowWlan')|$($wlan -join ', ')"
    } else {
        "$(Get-WzText 'rep.rowWlan')|$(Get-WzText 'rep.udWlanNone')"
    }
    $keyRows += if ($encrypted.Count -gt 0) {
        "$(Get-WzText 'rep.rowBitLocker')|$(Get-WzText 'rep.udBitlockerOn' @{ laufwerke = ($encrypted -join ', ') })|warn"
    } else {
        "$(Get-WzText 'rep.rowBitLocker')|$(Get-WzText 'rep.udBitlockerOff')"
    }

    $deviceRows = @()
    foreach ($printer in $printers) {
        $label = if ($printer.IsDefault) { Get-WzText 'rep.udPrinterDefault' } else { Get-WzText 'rep.udPrinterPlain' }
        $deviceRows += "$label|$(Get-WzText 'rep.udPrinterValue' @{ name = $printer.Name; anschluss = $printer.Port })"
    }
    foreach ($drive in $netDrives) {
        $deviceRows += "$(Get-WzText 'rep.udDriveLabel' @{ buchstabe = $drive.Letter })|$($drive.Target)"
    }
    if ($deviceRows.Count -eq 0) { $deviceRows += "$(Get-WzText 'rep.udDevices')|$(Get-WzText 'rep.udNoDevices')" }

    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secAccess') `
        -Lead (Get-WzText 'rep.leadAccess') `
        -Body ((New-WzHtmlCard -Title (Get-WzText 'rep.cardKeys') -Rows $keyRows) +
               (New-WzHtmlCard -Title (Get-WzText 'rep.cardDevices') -Rows $deviceRows))

    $meta = @(
        "$(Get-WzText 'rep.rowComputer')|$env:COMPUTERNAME"
        "$(Get-WzText 'rep.metaDate')|$((Get-Date).ToString('g', (Get-WzLanguageCulture)))"
        "$(Get-WzText 'rep.metaScope')|$(Format-WzBytes $totalBytes)"
        "$(Get-WzText 'rep.metaAccounts')|$($profiles.Count)"
    )

    $file = New-WzHtmlReport -Title (Get-WzText 'rep.udTitle') -Eyebrow (Get-WzText 'rep.udEyebrow') `
        -Subtitle (Get-WzText 'rep.udSubtitle' @{ pc = $env:COMPUTERNAME }) `
        -Meta $meta -Content $content `
        -FileName "$(Get-WzText 'rep.udFile')-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog (Get-WzText 'rep.logUdSaved' @{ datei = $file }) -Level Ok
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
    } else { Get-WzText 'core.na' }

    $summaryRows = @(
        "$(Get-WzText 'rep.rowComputer')|$env:COMPUTERNAME"
        "$(Get-WzText 'rep.rowUser')|$env:USERDOMAIN\$env:USERNAME"
        "$(Get-WzText 'rep.rowStart')|$(if ($syncHash.SessionStart) { $syncHash.SessionStart.ToString('G', (Get-WzLanguageCulture)) } else { Get-WzText 'core.na' })"
        "$(Get-WzText 'rep.rowDuration')|$duration"
        "$(Get-WzText 'rep.rowEntries')|$(Get-WzText 'rep.valEntries' @{ anzahl = $entries.Count; verteilung = ($counts -join ', ') })"
    )
    if ($info) {
        $summaryRows += "$(Get-WzText 'rep.rowWindows')|$(Get-WzText 'rep.valWindows' @{ name = $info.OsCaption; version = $info.OsVersion; build = $info.OsBuild })"
        $summaryRows += "$(Get-WzText 'rep.rowDevice')|$($info.Manufacturer) $($info.Model)"
    }
    if ($syncHash.DryRun) {
        $summaryRows += "$(Get-WzText 'rep.rowMode')|$(Get-WzText 'rep.protoDryRun')|warn"
    }

    $content = New-WzHtmlSection -Title (Get-WzText 'rep.secSummary') `
        -Body (New-WzHtmlCard -Title (Get-WzText 'rep.cardSession') -Rows $summaryRows)

    $content += New-WzHtmlSection -Title (Get-WzText 'rep.secHistory') `
        -Lead (Get-WzText 'rep.leadHistory') `
        -Body ("<div class=`"card log`">`n  $($logLines -join "`n  ")`n</div>")

    $meta = @(
        "$(Get-WzText 'rep.rowComputer')|$env:COMPUTERNAME"
        "$(Get-WzText 'rep.metaDate')|$((Get-Date).ToString('g', (Get-WzLanguageCulture)))"
        "$(Get-WzText 'rep.metaSteps')|$($entries.Count)"
    )

    $file = New-WzHtmlReport -Title (Get-WzText 'rep.protoTitle') -Eyebrow (Get-WzText 'rep.protoEyebrow') `
        -Subtitle (Get-WzText 'rep.protoSubtitle' @{ pc = $env:COMPUTERNAME }) `
        -Meta $meta -Content $content `
        -FileName "$(Get-WzText 'rep.protoFile')-$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"

    Write-WzLog (Get-WzText 'rep.logProtoSaved' @{ datei = $file }) -Level Ok
    if ($Open) { Start-Process $file }
    return $file
}
