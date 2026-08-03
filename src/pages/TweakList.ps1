# Gemeinsame Bausteine für alle Seiten, die den Tweak-Katalog anzeigen
# (Optimierung und KI-Entfernung). Der Zustand jedes Eintrags wird im
# Hintergrund ermittelt, damit die Liste sofort steht.

function New-WzTweakList {
    <#
    .SYNOPSIS
        Baut Kategoriekarten mit Checkbox-Zeilen in einen Container.
    .PARAMETER Container
        StackPanel, das gefüllt wird.
    .PARAMETER Categories
        Kategorien aus tweaks.json, die angezeigt werden sollen.
    .OUTPUTS
        Liste von Zeilen-Objekten mit Tweak, CheckBox und StatusBadge.
    #>
    param(
        [Parameter(Mandatory = $true)]$Container,
        [Parameter(Mandatory = $true)][string[]]$Categories,
        [scriptblock]$OnSelectionChanged
    )

    $Container.Children.Clear()
    $rows = New-Object Collections.ArrayList
    $allCategories = Get-WzTweakCategories

    foreach ($categoryId in $Categories) {
        $tweaks = @(Get-WzTweaks -Category $categoryId)
        if ($tweaks.Count -eq 0) { continue }

        $meta = $allCategories | Where-Object { $_.id -eq $categoryId } | Select-Object -First 1
        $title = if ($meta) { $meta.name } else { $categoryId }
        $lead = if ($meta) { $meta.description } else { '' }

        $card = New-WzCard -Eyebrow "// $($title.ToUpper())" -Static
        $stack = $card.Content

        $header = New-Object Windows.Controls.Grid
        $headerTitle = New-Object Windows.Controls.TextBlock
        $headerTitle.Text = $lead
        $headerTitle.Style = $syncHash.Window.FindResource('WzLabel')
        $headerTitle.TextWrapping = 'Wrap'
        $headerTitle.Margin = New-Object Windows.Thickness(0, 0, 90, 12)
        [void]$header.Children.Add($headerTitle)

        $toggleAll = New-Object Windows.Controls.Button
        $toggleAll.Content = 'umschalten'
        $toggleAll.Style = $syncHash.Window.FindResource('WzBtnGhost')
        $toggleAll.HorizontalAlignment = 'Right'
        $toggleAll.VerticalAlignment = 'Top'
        [void]$header.Children.Add($toggleAll)
        [void]$stack.Children.Add($header)

        $categoryRows = New-Object Collections.ArrayList
        foreach ($tweak in $tweaks) {
            $row = New-WzCheckRow -Item $tweak -IsChecked ([bool]$tweak.defaultChecked)
            [void]$stack.Children.Add($row.Row)

            $entry = [pscustomobject]@{
                Tweak    = $tweak
                CheckBox = $row.CheckBox
                Row      = $row.Row
                Badge    = $null
            }
            [void]$rows.Add($entry)
            [void]$categoryRows.Add($entry)

            if ($OnSelectionChanged) {
                $row.CheckBox.Add_Click($OnSelectionChanged)
            }
        }

        $toggleAll.Add_Click({
            $anyUnchecked = @($categoryRows | Where-Object { -not $_.CheckBox.IsChecked }).Count -gt 0
            foreach ($entry in $categoryRows) { $entry.CheckBox.IsChecked = $anyUnchecked }
            if ($OnSelectionChanged) { & $OnSelectionChanged }
        }.GetNewClosure())

        [void]$Container.Children.Add($card.Card)
    }

    return $rows
}

function Update-WzTweakStates {
    <#
    .SYNOPSIS
        Ermittelt im Hintergrund, welche Einträge bereits angewendet sind, und
        setzt die Abzeichen. Bereits angewendete Einträge werden abgewählt.
    #>
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Windows.Controls.TextBlock]$HintTarget,
        [scriptblock]$OnDone
    )

    $tweakIds = @($Rows | ForEach-Object { $_.Tweak.id })
    if ($tweakIds.Count -eq 0) { return }

    if ($HintTarget) { $HintTarget.Text = 'Zustand wird geprüft...' }

    Invoke-WzTask -Name 'Zustand prüfen' -Silent -ArgumentList (, $tweakIds) -ScriptBlock {
        param($ids)
        Clear-WzStateCache
        $states = @{}
        foreach ($tweak in Get-WzTweaks) {
            if ($ids -notcontains $tweak.id) { continue }
            $states[$tweak.id] = Test-WzTweakState -Tweak $tweak
        }
        $states
    } -OnComplete {
        param($states)
        if (-not $states) { return }

        $applied = 0
        foreach ($entry in $Rows) {
            if (-not $states.ContainsKey($entry.Tweak.id)) { continue }
            $state = $states[$entry.Tweak.id]

            $badgeText, $badgeKind = switch ($state) {
                'Applied'    { 'AKTIV', 'ok' }
                'Partial'    { 'TEILWEISE', 'warn' }
                'NotApplied' { $null, $null }
                default      { $null, $null }
            }

            # Vorheriges Abzeichen entfernen
            if ($entry.Badge) {
                $headerRow = $entry.Badge.Parent
                if ($headerRow) { $headerRow.Children.Remove($entry.Badge) }
                $entry.Badge = $null
            }

            if ($badgeText) {
                $textStack = $entry.Row.Children[1]
                $headerRow = $textStack.Children[0]
                $badge = New-WzBadge -Text $badgeText -Kind $badgeKind
                [void]$headerRow.Children.Add($badge)
                $entry.Badge = $badge
            }

            if ($state -eq 'Applied') {
                $entry.CheckBox.IsChecked = $false
                $applied++
            }
        }

        if ($HintTarget) {
            $HintTarget.Text = "$applied von $($Rows.Count) bereits aktiv"
        }
        if ($OnDone) { & $OnDone }
    }.GetNewClosure()
}

function Invoke-WzTweakSelection {
    <#
    .SYNOPSIS
        Gemeinsamer Ablauf für "Auswahl anwenden": Bestätigung, Sicherung,
        Ausführung, Abschlussmeldung.
    #>
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Title,
        [scriptblock]$OnDone
    )

    $selected = @($Rows | Where-Object { $_.CheckBox.IsChecked } | ForEach-Object { $_.Tweak })
    if ($selected.Count -eq 0) {
        Show-WzInfo -Title 'Nichts ausgewählt' -Message 'Bitte zuerst mindestens einen Eintrag anhaken.'
        return
    }

    $riskyCount = @($selected | Where-Object { $_.risk -in @('medium', 'high') }).Count
    $rebootCount = @($selected | Where-Object { $_.requiresReboot }).Count

    $items = foreach ($tweak in $selected) {
        $suffix = if ($tweak.risk -ne 'low') { " [$($tweak.risk)]" } else { '' }
        "$($tweak.name)$suffix"
    }

    $message = "$($selected.Count) Änderung(en) werden angewendet."
    if ($riskyCount -gt 0) { $message += " Davon $riskyCount mit erhöhtem Risiko." }
    if ($rebootCount -gt 0) { $message += " $rebootCount davon wirken erst nach einem Neustart." }
    if ($syncHash.DryRun) { $message = "Testmodus: Es wird nur protokolliert, was passieren würde. $message" }

    $answer = Show-WzConfirm -Title $Title -Message $message -Items $items `
        -OptionText 'Vorher einen Systemwiederherstellungspunkt anlegen (empfohlen)' `
        -OptionDefault (-not $syncHash.DryRun) `
        -ConfirmText $(if ($syncHash.DryRun) { 'Testlauf starten' } else { 'Anwenden' }) `
        -Danger:($riskyCount -gt 0)

    if (-not $answer.Confirmed) {
        Write-WzLog 'Vorgang abgebrochen.' -Level Info
        return
    }

    $createRestorePoint = ($answer.OptionChecked -and -not $syncHash.DryRun)

    Invoke-WzTask -Name $Title -ArgumentList @($selected, $Scope, $createRestorePoint) -ScriptBlock {
        param($tweaks, $scope, $restorePoint)
        Invoke-WzTweaks -Tweaks $tweaks -Scope $scope -CreateRestorePoint:$restorePoint
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        $lines = @("$($summary.Applied) Änderung(en) durchgeführt.")
        if ($summary.Failed -gt 0) { $lines += "$($summary.Failed) mit Fehlern — Einzelheiten im Protokoll." }
        if ($summary.RebootRequired) { $lines += 'Ein Neustart ist nötig, damit alles greift.' }
        if ($summary.UndoFile) { $lines += "Sicherung: $(Split-Path -Parent $summary.UndoFile)" }

        Add-WzAction -Area $Title -RebootRequired:([bool]$summary.RebootRequired) `
            -Summary "$($summary.Applied) Einstellung(en) angepasst$(if ($summary.Failed -gt 0) { ", $($summary.Failed) davon ohne Erfolg" })" `
            -Detail @($selected | ForEach-Object { $_.name })

        Show-WzInfo -Title 'Fertig' -Message ($lines -join ' ') -Items @()
        if ($OnDone) { & $OnDone }
    }.GetNewClosure()
}

function Show-WzUndoDialog {
    <#
    .SYNOPSIS
        Listet vorhandene Sicherungen und nimmt die gewählte zurück.
    #>
    param([scriptblock]$OnDone)

    $sessions = Get-WzUndoSessions
    if ($sessions.Count -eq 0) {
        Show-WzInfo -Title 'Keine Sicherungen' `
            -Message 'Auf diesem PC hat WinZii noch keine Änderungen vorgenommen, die sich zurücknehmen ließen.'
        return
    }

    $available = @($sessions | Select-Object -First 12)

    # Vorauswahl: die neueste, die noch nicht zurückgenommen wurde
    $preselect = 0
    for ($i = 0; $i -lt $available.Count; $i++) {
        if (-not $available[$i].Restored) { $preselect = $i; break }
    }

    $choices = foreach ($session in $available) {
        $suffix = if ($session.Restored) {
            ' — bereits zurückgenommen'
        } else {
            ''
        }
        "{0}  ·  {1}  ·  {2} Änderung(en){3}" -f `
            $session.Created.ToString('dd.MM.yyyy HH:mm'), $session.Scope, $session.ActionCount, $suffix
    }

    $answer = Show-WzConfirm -Title 'Änderungen zurücknehmen' `
        -Message 'Wähle die Sicherung, die zurückgespielt werden soll. Jede Sicherung enthält den Zustand vor genau einem Durchlauf; bereits zurückgenommene sind gekennzeichnet.' `
        -Choices @($choices) -ChoiceLabel 'Sicherung' -ChoiceDefault $preselect `
        -ConfirmText 'Zurücknehmen' -Danger

    if (-not $answer.Confirmed) { return }

    $selected = $available[$answer.SelectedIndex]
    Write-WzLog "Sicherung vom $($selected.Created.ToString('dd.MM.yyyy HH:mm')) ($($selected.Scope)) wird zurückgenommen." -Level Action

    Invoke-WzTask -Name 'Änderungen zurücknehmen' -ArgumentList @($selected.UndoFile) -ScriptBlock {
        param($undoFile)
        Restore-WzUndoSession -UndoFile $undoFile
    } -OnComplete {
        param($result)
        if (-not $result) { return }

        $lines = @("$($result.Restored) Einstellung(en) zurückgesetzt.")
        if ($result.Failed -gt 0) { $lines += "$($result.Failed) fehlgeschlagen." }
        if ($result.Skipped -gt 0) { $lines += "$($result.Skipped) nicht automatisch umkehrbar." }

        Add-WzAction -Area 'Rücknahme' -Summary "$($result.Restored) Einstellung(en) auf den vorherigen Stand zurückgesetzt"

        Show-WzInfo -Title 'Zurückgenommen' -Message ($lines -join ' ') -Items @($result.Notes)
        if ($OnDone) { & $OnDone }
    }.GetNewClosure()
}
