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
        $toggleAll.Content = Get-WzText 'opt.btnToggleAll'
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

    # Die Einträge selbst mitgeben statt nur ihre Kennungen: Der
    # Hintergrund-Runspace las sonst den Katalog ein zweites Mal ein und lief
    # dann über alle 41 Einträge, um die paar gesuchten herauszufiltern.
    $tweaks = @($Rows | ForEach-Object { $_.Tweak })
    if ($tweaks.Count -eq 0) { return }

    if ($HintTarget) { $HintTarget.Text = Get-WzText 'opt.checkingState' }

    Invoke-WzTask -Name (Get-WzText 'opt.taskCheckState') -Silent -ArgumentList (, $tweaks) -ScriptBlock {
        param($tweaks)
        Clear-WzStateCache
        $states = @{}
        foreach ($tweak in $tweaks) {
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
                'Applied'    { (Get-WzText 'opt.badgeActive'), 'ok' }
                'Partial'    { (Get-WzText 'opt.badgePartial'), 'warn' }
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
            $HintTarget.Text = Get-WzText 'opt.appliedOf' @{ aktiv = $applied; gesamt = $Rows.Count }
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
        Show-WzInfo -Title (Get-WzText 'opt.nothingSelectedTitle') -Message (Get-WzText 'opt.nothingSelectedMessage')
        return
    }

    $riskyCount = @($selected | Where-Object { $_.risk -in @('medium', 'high') }).Count
    $rebootCount = @($selected | Where-Object { $_.requiresReboot }).Count

    # Statt nur der Namen auch, WAS jeder Eintrag anfasst. Get-WzTweakActionSummary
    # war dafür gebaut und wurde nie aufgerufen — der Anwender bestätigte bisher
    # eine Liste von Überschriften.
    $items = foreach ($tweak in $selected) {
        $suffix = if ($tweak.risk -ne 'low') { " [$($tweak.risk)]" } else { '' }
        $what = Get-WzTweakActionSummary -Tweak $tweak
        if ($what) { Get-WzText 'opt.itemWithWhat' @{ name = $tweak.name; risiko = $suffix; was = $what } } else { "$($tweak.name)$suffix" }
    }

    $message = Get-WzText 'opt.confirmCount' @{ anzahl = $selected.Count }
    if ($riskyCount -gt 0) { $message += Get-WzText 'opt.confirmRisky' @{ anzahl = $riskyCount } }
    if ($rebootCount -gt 0) { $message += Get-WzText 'opt.confirmReboot' @{ anzahl = $rebootCount } }
    if ($syncHash.DryRun) { $message = Get-WzText 'opt.confirmDryRun' @{ rest = $message } }

    # War der Systemschutz aus, bleibt er nach dem Wiederherstellungspunkt an —
    # sonst wäre der Punkt sofort wieder weg. Das kostet dauerhaft Platz und
    # Hintergrundarbeit und ist damit selbst eine Bremse. Also vorher sagen.
    $optionText = Get-WzText 'opt.optionRestorePoint'
    if (-not (Test-WzSystemProtectionOn)) {
        $optionText += Get-WzText 'opt.optionProtectionOff'
    }

    $answer = Show-WzConfirm -Title $Title -Message $message -Items $items `
        -OptionText $optionText `
        -OptionDefault (-not $syncHash.DryRun) `
        -ConfirmText $(if ($syncHash.DryRun) { Get-WzText 'opt.btnDryRun' } else { Get-WzText 'opt.btnApplyGo' }) `
        -Danger:($riskyCount -gt 0)

    if (-not $answer.Confirmed) {
        Write-WzLog (Get-WzText 'opt.logCancelled') -Level Info
        return
    }

    $createRestorePoint = ($answer.OptionChecked -and -not $syncHash.DryRun)

    Invoke-WzTask -Name $Title -ArgumentList @($selected, $Scope, $createRestorePoint) -ScriptBlock {
        param($tweaks, $scope, $restorePoint)
        Invoke-WzTweaks -Tweaks $tweaks -Scope $scope -CreateRestorePoint:$restorePoint
    } -OnComplete {
        param($summary)
        if (-not $summary) { return }

        $lines = @(Get-WzText 'opt.lineApplied' @{ anzahl = $summary.Applied })
        if ($summary.Failed -gt 0) { $lines += Get-WzText 'opt.lineFailed' @{ anzahl = $summary.Failed } }
        if ($summary.RebootRequired) { $lines += Get-WzText 'opt.lineReboot' }
        if ($summary.UndoFile) { $lines += Get-WzText 'opt.lineBackup' @{ pfad = (Split-Path -Parent $summary.UndoFile) } }

        Add-WzAction -Area $Title -RebootRequired:([bool]$summary.RebootRequired) `
            -Summary ((Get-WzText 'opt.actionApplied' @{ anzahl = $summary.Applied }) + $(if ($summary.Failed -gt 0) { Get-WzText 'opt.actionFailedSuffix' @{ anzahl = $summary.Failed } })) `
            -Detail @($selected | ForEach-Object { $_.name })

        Show-WzInfo -Title (Get-WzText 'opt.doneTitle') -Message ($lines -join ' ') -Items @()
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
        Show-WzInfo -Title (Get-WzText 'opt.noBackupsTitle') `
            -Message (Get-WzText 'opt.noBackupsMessage')
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
            Get-WzText 'opt.suffixReverted'
        } else {
            ''
        }
        Get-WzText 'opt.sessionChoice' @{ zeit = $session.Created.ToString('g', (Get-WzLanguageCulture))
            bereich = $session.Scope; anzahl = $session.ActionCount; zusatz = $suffix }
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'opt.undoTitle') `
        -Message (Get-WzText 'opt.undoMessage') `
        -Choices @($choices) -ChoiceLabel (Get-WzText 'opt.lblBackup') -ChoiceDefault $preselect `
        -ConfirmText (Get-WzText 'opt.btnUndoGo') -Danger

    if (-not $answer.Confirmed) { return }

    $selected = $available[$answer.SelectedIndex]
    Write-WzLog (Get-WzText 'opt.logUndoing' @{ zeit = $selected.Created.ToString('g', (Get-WzLanguageCulture)); bereich = $selected.Scope }) -Level Action

    Invoke-WzTask -Name (Get-WzText 'opt.taskUndo') -ArgumentList @($selected.UndoFile) -ScriptBlock {
        param($undoFile)
        Restore-WzUndoSession -UndoFile $undoFile
    } -OnComplete {
        param($result)
        if (-not $result) { return }

        $lines = @(Get-WzText 'opt.lineRestored' @{ anzahl = $result.Restored })
        if ($result.Failed -gt 0) { $lines += Get-WzText 'opt.lineUndoFailed' @{ anzahl = $result.Failed } }
        if ($result.Skipped -gt 0) { $lines += Get-WzText 'opt.lineSkipped' @{ anzahl = $result.Skipped } }

        Add-WzAction -Area 'Rücknahme' -Summary (Get-WzText 'opt.actionUndo' @{ anzahl = $result.Restored })

        Show-WzInfo -Title (Get-WzText 'opt.undoneTitle') -Message ($lines -join ' ') -Items @($result.Notes)
        if ($OnDone) { & $OnDone }
    }.GetNewClosure()
}
