# Uninstall — installierte Programme auflisten und entfernen.
#
# Der Blick auf einen Kundenrechner: vorinstallierte Herstellersoftware,
# abgelaufene Virenscanner-Testversionen, Werkzeugleisten. WinZii konnte
# bisher installieren, aber nichts wieder loswerden.

function Get-WzInstalledPrograms {
    <#
    .SYNOPSIS
        Alle Programme aus der Registry, wie sie auch die Systemsteuerung zeigt.
    .PARAMETER Filter
        Suchtext für Name oder Herausgeber.
    .NOTES
        Drei Zweige, weil 32-Bit-Programme unter WOW6432Node liegen und
        benutzerbezogene Installationen unter HKCU. Ausgeblendet werden
        Systembestandteile, Updates und Einträge ohne Namen — genau das, was
        auch die Systemsteuerung verbirgt.
    #>
    [CmdletBinding()]
    param([string]$Filter)

    # Der HKCU-Zweig wird aufgelöst: Beantwortet der Techniker die
    # Rechteanforderung mit dem eigenen Konto, zeigt HKCU auf dessen Profil —
    # aufgelistet würden dann seine Programme, nicht die des Kunden.
    $userBranch = Resolve-WzRegistryPath 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'

    $roots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = (Get-WzText 'unin.scopeAllUsers') }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = (Get-WzText 'unin.scopeAllUsers32') }
        @{ Path = "$userBranch\*"; Scope = (Get-WzText 'unin.scopeThisUser') }
    )

    $programs = @()
    foreach ($root in $roots) {
        $entries = @()
        try { $entries = @(Get-ItemProperty -Path $root.Path -ErrorAction SilentlyContinue) } catch { }

        foreach ($entry in $entries) {
            if (-not $entry.DisplayName) { continue }
            if ($entry.SystemComponent -eq 1) { continue }
            if ($entry.ParentKeyName) { continue }
            if ($entry.ReleaseType -in @('Security Update', 'Update Rollup', 'Hotfix')) { continue }
            if (-not $entry.UninstallString -and -not $entry.QuietUninstallString) { continue }

            $sizeBytes = [int64]0
            if ($entry.EstimatedSize) { $sizeBytes = [int64]$entry.EstimatedSize * 1KB }

            $installed = $null
            if ($entry.InstallDate -and $entry.InstallDate -match '^\d{8}$') {
                try { $installed = [datetime]::ParseExact($entry.InstallDate, 'yyyyMMdd', $null) } catch { }
            }

            $quiet = [string]$entry.QuietUninstallString
            $command = if ($quiet) { $quiet } else { [string]$entry.UninstallString }
            $productCode = if ($entry.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $entry.PSChildName } else { '' }

            $programs += [pscustomobject]@{
                Name            = $entry.DisplayName.Trim()
                Version         = [string]$entry.DisplayVersion
                Publisher       = [string]$entry.Publisher
                SizeBytes       = $sizeBytes
                Installed       = $installed
                Scope           = $root.Scope
                Command         = $command
                IsQuiet         = [bool]$quiet
                ProductCode     = $productCode
                # Nur MSI und Programme mit eigenem stillen Schalter lassen sich
                # ohne Rückfragen entfernen; alles andere öffnet ein Fenster.
                CanSilent       = ([bool]$quiet -or [bool]$productCode)
                RegistryKey     = $entry.PSChildName
                # Für die Restesuche nach dem Entfernen
                InstallLocation = ([string]$entry.InstallLocation).Trim().Trim('"').TrimEnd('\')
                RegistryPath    = (($root.Path -replace '\\\*$', '') + '\' + $entry.PSChildName)
            }
        }
    }

    # Gleiche Programme stehen mitunter in mehreren Zweigen
    $programs = @($programs | Sort-Object Name, Version -Unique)

    if ($Filter) {
        $needle = $Filter.Trim()
        $programs = @($programs | Where-Object {
            $_.Name -like "*$needle*" -or $_.Publisher -like "*$needle*"
        })
    }

    return @($programs | Sort-Object Name)
}

function Uninstall-WzPrograms {
    <#
    .SYNOPSIS
        Entfernt die übergebenen Programme.
    .DESCRIPTION
        MSI-Pakete über msiexec /x /qn, Programme mit eigenem stillen Schalter
        über diesen. Alles andere öffnet den Assistenten des Herstellers —
        dann muss der Techniker durchklicken, und WinZii wartet.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Programs)

    $summary = [pscustomobject]@{
        Removed = 0
        Failed  = 0
        Details = @()
        # Die wirklich entfernten Programme — nur für die sucht sich danach
        # die Restesuche durch Ordner und Registry.
        RemovedPrograms = @()
    }

    foreach ($program in @($Programs)) {
        if ($syncHash.DryRun) {
            Write-WzLog (Get-WzText 'unin.logWouldRemove' @{ name = $program.Name }) -Level Test
            $summary.Details += "$($program.Name): $(Get-WzText 'unin.logTestMode')"
            continue
        }

        Write-WzLog (Get-WzText 'unin.logRemoving' @{ name = $program.Name }) -Level Action
        $result = Invoke-WzUninstallCommand -Program $program

        if ($result.Success) {
            # Erfolg behaupten ist nicht Erfolg haben: Ein Assistent, den der
            # Techniker wegklickt, meldet mitunter trotzdem Code 0. Ohne diese
            # Kontrolle stünde »entfernt« im Protokoll, und die Restesuche böte
            # gleich darauf den Deinstallationsschlüssel eines Programms an,
            # das noch installiert ist — danach wäre es gar nicht mehr zu
            # entfernen.
            #
            # Mit Nachfrist, weil die Kontrolle sonst schneller ist als der
            # Deinstallierer: Der Aufruf kehrt zurück, während dessen eigener
            # Prozess noch aufräumt. Zehn Sekunden reichen weit über das
            # gemessene Fenster hinaus und kosten nur dort Zeit, wo wirklich
            # etwas schiefgegangen ist.
            if (-not (Test-WzProgramGone -Program $program -WaitSeconds 10)) {
                $summary.Failed++
                $summary.Details += "$($program.Name): $(Get-WzText 'unin.detailStillListed')"
                Write-WzLog (Get-WzText 'unin.logStillListed' @{ name = $program.Name }) -Level Warn
                continue
            }

            $summary.Removed++
            $summary.RemovedPrograms += $program
            $summary.Details += "$($program.Name): $(Get-WzText 'unin.detailRemoved')"
            Write-WzLog (Get-WzText 'unin.logRemoved' @{ name = $program.Name }) -Level Ok
        } else {
            $summary.Failed++
            $summary.Details += "$($program.Name): $($result.Message)"
            Write-WzLog "$($program.Name): $($result.Message)" -Level Warn
        }
    }

    return $summary
}

function Invoke-WzUninstallCommand {
    <#
    .SYNOPSIS
        Führt die Deinstallation eines einzelnen Programms aus.
    #>
    param([Parameter(Mandatory = $true)]$Program)

    $result = [pscustomobject]@{ Success = $false; Message = '' }

    try {
        if ($Program.ProductCode) {
            # MSI: der zuverlässigste Weg, ganz ohne Fenster
            $process = Invoke-WzProcess -FilePath 'msiexec.exe' `
                -Arguments "/x $($Program.ProductCode) /qn /norestart" -TimeoutSeconds 900
            # 3010 heißt "erledigt, Neustart nötig", 1605 "war gar nicht installiert"
            if ($process.ExitCode -in @(0, 3010)) {
                $result.Success = $true
            } elseif ($process.ExitCode -eq 1605) {
                $result.Success = $true
                $result.Message = Get-WzText 'unin.msgAlreadyGone'
            } else {
                $result.Message = Get-WzText 'unin.msgMsiexecCode' @{ code = $process.ExitCode }
            }
            return $result
        }

        $filePath, $arguments = Split-WzCommandLine $Program.Command
        if (-not $filePath) {
            $result.Message = Get-WzText 'unin.msgNoCommand'
            return $result
        }

        $process = Invoke-WzProcess -FilePath $filePath -Arguments $arguments -TimeoutSeconds 1800
        if ($process.TimedOut) {
            $result.Message = Get-WzText 'unin.msgTimeout'
        } elseif ($process.ExitCode -in @(0, 3010)) {
            $result.Success = $true
        } else {
            $result.Message = Get-WzText 'unin.msgWizardCode' @{ code = $process.ExitCode }
        }
    } catch {
        $result.Message = $_.Exception.Message.Split([char]10)[0]
    }

    return $result
}

function Test-WzProgramGone {
    <#
    .SYNOPSIS
        Ist das Programm nach dem Deinstallieren wirklich aus der Liste
        verschwunden?
    .NOTES
        Gefragt wird die Stelle, aus der die Liste stammt: der eigene
        Deinstallationsschlüssel. Steht dort noch ein Anzeigename, ist das
        Programm noch da. Ohne Schlüsselpfad — etwa bei einem von Hand
        gebauten Eintrag — gilt es als entfernt, sonst bliebe die Prüfung ein
        Hindernis ohne Aussage.
    .PARAMETER WaitSeconds
        Nachfrist. Viele Deinstallierer kehren zurück, bevor sie fertig sind:
        Auf dem Abnahmelaptop meldete SumatraPDF nach 0,38 s Erfolg, der
        Registry-Eintrag verschwand erst eine Sekunde später. Ohne Frist fiel
        die Prüfung in dieses Fenster, das Programm galt als »steht weiter in
        der Programmliste« — und weil es damit nicht als entfernt zählte, lief
        die Restesuche gar nicht erst an. Der Rest blieb liegen.

        Der weggeklickte Assistent wird davon nicht verdeckt: Sein Eintrag
        steht auch nach der Frist noch da, die Meldung kommt nur später.
    #>
    param(
        [Parameter(Mandatory = $true)]$Program,
        [int]$WaitSeconds = 0
    )

    if (-not $Program.RegistryPath) { return $true }

    $frist = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $weg = $false
        try {
            $entry = Get-ItemProperty -LiteralPath (Resolve-WzRegistryPath $Program.RegistryPath) -ErrorAction Stop
            $weg = -not $entry.DisplayName
        } catch {
            $weg = $true
        }

        if ($weg) { return $true }
        if ($frist.Elapsed.TotalSeconds -ge $WaitSeconds) { return $false }
        Start-Sleep -Milliseconds 500
    }
}

function Split-WzCommandLine {
    <#
    .SYNOPSIS
        Zerlegt einen Registry-Deinstallationsbefehl in Programm und Argumente.
    .NOTES
        Die Einträge sind uneinheitlich: mal in Anführungszeichen, mal mit
        Leerzeichen im Pfad und ohne. Rückgabe ist ein Paar aus Pfad und
        Argumentzeile.
    #>
    param([string]$CommandLine)

    if (-not $CommandLine) { return @($null, '') }
    $line = $CommandLine.Trim()

    if ($line.StartsWith('"')) {
        $end = $line.IndexOf('"', 1)
        if ($end -gt 1) {
            return @($line.Substring(1, $end - 1), $line.Substring($end + 1).Trim())
        }
        return @($line.Trim('"'), '')
    }

    # Ohne Anführungszeichen: bis zur ersten .exe suchen, damit Pfade mit
    # Leerzeichen nicht mitten im Ordnernamen abgeschnitten werden
    if ($line -match '^(?<path>.+?\.exe)(?<rest>\s.*)?$') {
        return @($Matches['path'], $(if ($Matches['rest']) { $Matches['rest'].Trim() } else { '' }))
    }

    $parts = $line -split '\s+', 2
    return @($parts[0], $(if ($parts.Count -gt 1) { $parts[1] } else { '' }))
}

# --- Restesuche ------------------------------------------------------------
#
# Deinstallierer lassen gern etwas liegen: den Installationsordner, Einträge
# im Startmenü, eigene Registry-Schlüssel. »Restlos« heißt: nach dem Entfernen
# nachsehen und die Reste mit Ansage wegräumen.

function Get-WzLeftoverNameCandidates {
    <#
    .SYNOPSIS
        Ordner- und Schlüsselnamen, unter denen ein Programm seine Reste ablegt.
    .NOTES
        Bewusst nur der Anzeigename und eine Variante ohne Versions- und
        Klammerzusatz (»Mozilla Firefox 128.0 (x64 de)« → »Mozilla Firefox«).
        Herausgebernamen wären zu breit — unter »Google« oder »Adobe« wohnen
        mehrere Programme.
    #>
    param([Parameter(Mandatory = $true)]$Program)

    $names = @()
    $base = $Program.Name.Trim()
    if ($base) { $names += $base }

    $trimmed = ($base -replace '\s*\([^)]*\)\s*$', '' -replace '\s+v?\d[\d.]*$', '').Trim()
    if ($trimmed -and $trimmed -ne $base) { $names += $trimmed }

    # Zu kurze Namen treffen zu leicht den falschen Ordner; Zeichen, die in
    # Pfaden nichts verloren haben, fliegen gleich mit raus.
    return @($names | Where-Object { $_.Length -ge 4 -and $_ -notmatch '[\\/:*?"<>|]' })
}

function Get-WzForeignInstallLocations {
    <#
    .SYNOPSIS
        Installationsordner aller Programme außer den übergebenen.
    .NOTES
        Die feste Liste der Sammelordner reicht nicht. Auf dem Abnahmelaptop
        tragen »Adobe Audition 2025« und »Adobe Premiere Pro 2025« beide
        »C:\Program Files\Adobe« als Installationsordner ein — den Ordner, unter
        dem auch Photoshop, Illustrator, Dreamweaver und Acrobat liegen. Die
        Restesuche hätte ihn nach dem Entfernen eines der beiden zum Löschen
        angeboten: 20 GB, endgültig, ohne Sicherung.

        Deshalb wird nicht mehr geraten, welche Ordner geteilt sind, sondern
        nachgesehen, wer sonst noch dort wohnt.
    #>
    [CmdletBinding()]
    param($Excluding)

    $eigene = @{}
    foreach ($program in @($Excluding | Where-Object { $_ })) {
        if ($program.Name) { $eigene[[string]$program.Name] = $true }
    }

    $orte = @()
    foreach ($program in @(Get-WzInstalledPrograms)) {
        if ($eigene.ContainsKey($program.Name)) { continue }
        if (-not $program.InstallLocation) { continue }
        $orte += $program.InstallLocation.TrimEnd('\')
    }

    return @($orte | Sort-Object -Unique)
}

function Test-WzLeftoverPathSafe {
    <#
    .SYNOPSIS
        Darf dieser Ordner überhaupt als Rest gelten?
    .NOTES
        Nur unterhalb der bekannten Programm- und Datenwurzeln, nie die Wurzel
        selbst und nie ein bekannter Sammelordner wie »Common Files« — dort
        wohnen viele Programme gleichzeitig.

        Und nie ein Ordner, in dem noch ein anderes Programm wohnt: Manche
        Hersteller tragen als Installationsordner den Sammelordner der ganzen
        Programmfamilie ein. Welche das sind, weiß nur die Programmliste selbst,
        deshalb kommt sie über $ForeignLocations herein.
    #>
    param([string]$Path, [string[]]$ForeignLocations = @())

    if (-not $Path) { return $false }
    if ($Path -notmatch '^[A-Za-z]:\\') { return $false }

    $sauber = $Path.TrimEnd('\')
    foreach ($fremd in @($ForeignLocations | Where-Object { $_ })) {
        $fremd = $fremd.TrimEnd('\')
        # Gleich der Ordner eines anderen Programms — oder ein Ordner, unter dem
        # ein anderes Programm liegt. Der umgekehrte Fall bleibt erlaubt: der
        # eigene Unterordner darf weg, auch wenn der Elternordner geteilt ist.
        if ($fremd -eq $sauber) { return $false }
        if ($fremd.StartsWith($sauber + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }

    $roots = @(
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:ProgramData
        (Get-WzUserFolder -Kind 'LocalAppData')
        (Get-WzUserFolder -Kind 'RoamingAppData')
    ) | Where-Object { $_ }

    foreach ($root in $roots) {
        $prefix = $root.TrimEnd('\') + '\'
        if ($Path.Length -le $prefix.Length) { continue }
        if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }

        $firstSegment = ($Path.Substring($prefix.Length) -split '\\')[0]

        # Store-Apps und Zwischenspeicher sind samt allem darunter tabu. Dort
        # lässt kein Deinstallierer etwas liegen, wohl aber liegt dort
        # Windows-Eigenes — und in »WindowsApps« hängen Rechte daran, die sich
        # nach einem Löschversuch nicht wiederherstellen lassen.
        if ($firstSegment -in @('WindowsApps', 'Packages', 'Temp')) { return $false }

        # Sammelordner selbst nie; die Programmordner darunter schon. »Programs«
        # steht mit in der Liste, weil unter %LocalAppData%\Programs ganze
        # Programmfamilien wohnen.
        if ($firstSegment -in @('Common Files', 'Microsoft', 'Microsoft Shared',
            'Windows', 'Programs', 'Application Data')) {
            if ($Path.TrimEnd('\') -eq ($prefix + $firstSegment)) { return $false }
        }
        return $true
    }
    return $false
}

function Test-WzLeftoverKeySafe {
    <#
    .SYNOPSIS
        Darf dieser Registry-Schlüssel überhaupt als Rest gelten?
    .NOTES
        Das Gegenstück zu Test-WzLeftoverPathSafe für die Registry: nur
        unterhalb von SOFTWARE, und nie der Zweig selbst. Geprüft wird die
        aufgelöste Schreibweise mit, denn unter fremdem Konto steht dort
        »Registry::HKEY_USERS\<SID>\…«.
    #>
    param([string]$Path)

    if (-not $Path) { return $false }

    $rest = $Path -replace '^Registry::', ''
    $rest = $rest -replace '^HKEY_USERS\\[^\\]+\\', ''
    $rest = $rest -replace '^(HKLM|HKCU|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER):?\\', ''
    $segments = @(($rest -split '\\') | Where-Object { $_ })

    if ($segments.Count -lt 2) { return $false }
    if ($segments[0] -ne 'SOFTWARE') { return $false }
    # »SOFTWARE\WOW6432Node« ist die 32-Bit-Ausgabe desselben Zweigs, also
    # ebenfalls eine Wurzel und keine Beute.
    if ($segments.Count -eq 2 -and $segments[1] -eq 'WOW6432Node') { return $false }

    return $true
}

function Find-WzUninstallLeftovers {
    <#
    .SYNOPSIS
        Sucht nach dem Entfernen zurückgebliebene Ordner, Startmenü-Einträge
        und Registry-Schlüssel der übergebenen Programme.
    .NOTES
        Die Suche ist bewusst eng: der eingetragene Installationsordner und
        exakt nach dem Programm benannte Ordner und Schlüssel. Lieber einen
        Rest übersehen als den falschen Ordner anfassen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Programs)

    $leftovers = @()
    $seen = @{}

    # Fehlt eine dieser Wurzeln, entfällt der zugehörige Zweig. Join-Path wirft
    # bei $null, und ein Fund weniger ist besser als ein Abbruch mitten in der
    # Suche.
    $localApp = Get-WzUserFolder -Kind 'LocalAppData'
    $roamingApp = Get-WzUserFolder -Kind 'RoamingAppData'
    $startMenus = @()
    if ($env:ProgramData) { $startMenus += (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs') }
    if ($roamingApp) { $startMenus += (Join-Path $roamingApp 'Microsoft\Windows\Start Menu\Programs') }

    # Einmal für den ganzen Lauf: Wo wohnen die Programme, die bleiben sollen?
    $foreignLocations = @(Get-WzForeignInstallLocations -Excluding $Programs)

    foreach ($program in @($Programs | Where-Object { $_ })) {
        $names = @(Get-WzLeftoverNameCandidates -Program $program)

        $folderCandidates = @()
        if ($program.InstallLocation) { $folderCandidates += $program.InstallLocation }
        foreach ($name in $names) {
            if ($env:ProgramData) { $folderCandidates += Join-Path $env:ProgramData $name }
            if ($localApp) { $folderCandidates += Join-Path $localApp $name }
            if ($roamingApp) { $folderCandidates += Join-Path $roamingApp $name }
            foreach ($menu in $startMenus) { $folderCandidates += Join-Path $menu $name }
        }

        foreach ($folder in $folderCandidates) {
            $folder = $folder.TrimEnd('\')
            if ($seen.ContainsKey($folder.ToLowerInvariant())) { continue }
            if (-not (Test-WzLeftoverPathSafe -Path $folder -ForeignLocations $foreignLocations)) { continue }
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            $seen[$folder.ToLowerInvariant()] = $true

            $bytes = [int64]0
            try {
                $sum = (Get-ChildItem -LiteralPath $folder -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                if ($sum) { $bytes = [int64]$sum }
            } catch { }

            $leftovers += [pscustomobject]@{
                # Kind steuert den Loeschweg und bleibt deshalb fest —
                # uebersetzt wird erst in der Anzeige der Fundliste.
                Kind       = 'Ordner'
                Path       = $folder
                TargetPath = $folder
                SizeBytes  = $bytes
                Program    = $program.Name
            }
        }

        # Registry: der eigene Deinstallationsschlüssel und exakt benannte
        # Software-Schlüssel. Herausgeber-Wurzeln bleiben unangetastet.
        $keyCandidates = @()
        if ($program.RegistryPath) { $keyCandidates += $program.RegistryPath }
        foreach ($name in $names) {
            if ($name -in @('Microsoft', 'Windows', 'Google', 'Mozilla', 'Adobe',
                'Apple', 'Intel', 'NVIDIA', 'Oracle', 'Policies', 'Classes', 'Clients')) { continue }
            $keyCandidates += "HKLM:\SOFTWARE\$name"
            $keyCandidates += "HKLM:\SOFTWARE\WOW6432Node\$name"
            $keyCandidates += "HKCU:\Software\$name"
        }

        foreach ($key in $keyCandidates) {
            $resolved = Resolve-WzRegistryPath $key
            if ($seen.ContainsKey($resolved.ToLowerInvariant())) { continue }
            if (-not (Test-WzLeftoverKeySafe -Path $resolved)) { continue }
            if (-not (Test-Path -LiteralPath $resolved)) { continue }
            $seen[$resolved.ToLowerInvariant()] = $true

            $leftovers += [pscustomobject]@{
                Kind       = 'Registry'
                Path       = $key
                TargetPath = $resolved
                SizeBytes  = [int64]0
                Program    = $program.Name
            }
        }
    }

    return @($leftovers)
}

function Remove-WzUninstallLeftovers {
    <#
    .SYNOPSIS
        Entfernt die gefundenen Reste.
    .DESCRIPTION
        Registry-Schlüssel werden vorher als .reg-Datei in den Sicherungsordner
        exportiert. Für Ordner gibt es keine Sicherung — das sagt der
        Bestätigungsdialog vorher deutlich.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Leftovers)

    $summary = [pscustomobject]@{
        Removed  = 0
        Failed   = 0
        Bytes    = [int64]0
        Details  = @()
        # Wo die .reg-Sicherungen liegen — dieselbe Angabe wie bei den Tweaks,
        # damit sich der Weg zur Rücknahme auch im Protokoll nachlesen lässt.
        UndoFile = $null
    }

    if ($syncHash.DryRun) {
        foreach ($leftover in @($Leftovers | Where-Object { $_ })) {
            Write-WzLog (Get-WzText 'unin.logLeftoverWould' @{ pfad = $leftover.Path }) -Level Test
            $summary.Details += "$($leftover.Path): $(Get-WzText 'unin.logTestMode')"
        }
        return $summary
    }

    $session = New-WzUndoSession -Scope 'Programmreste'
    $removedPaths = New-Object Collections.ArrayList

    # Dieselbe Frage wie in der Suche, aber jetzt zählt sie: Wer wohnt sonst
    # noch dort? Die Programme, deren Reste hier stehen, sind ausgenommen —
    # bleibt ihr Eintrag stehen, wäre der eigene Ordner sonst geschützt.
    $foreignLocations = @(Get-WzForeignInstallLocations -Excluding @(
        @($Leftovers | Where-Object { $_ -and $_.Program } |
            Select-Object -ExpandProperty Program -Unique) |
            ForEach-Object { [pscustomobject]@{ Name = $_ } }))

    foreach ($leftover in @($Leftovers | Where-Object { $_ })) {
        # Zwischen Suchen und Löschen liegt ein Dialog. Was gleich mit
        # »-Recurse -Force« verschwindet, wird deshalb unmittelbar davor noch
        # einmal gegen dieselben Regeln gehalten — die Liste kommt aus einem
        # Hintergrundlauf, das Löschen ist endgültig.
        $safe = if ($leftover.Kind -eq 'Registry') {
            Test-WzLeftoverKeySafe -Path $leftover.TargetPath
        } else {
            Test-WzLeftoverPathSafe -Path $leftover.TargetPath -ForeignLocations $foreignLocations
        }
        if (-not $safe) {
            $summary.Failed++
            $summary.Details += "$($leftover.Path): $(Get-WzText 'unin.detailOutside')"
            Write-WzLog (Get-WzText 'unin.logOutside' @{ pfad = $leftover.TargetPath }) -Level Warn
            continue
        }

        try {
            if ($leftover.Kind -eq 'Registry') {
                Export-WzRegistryKey -Session $session -Path $leftover.TargetPath
                Remove-Item -LiteralPath $leftover.TargetPath -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $leftover.TargetPath -Recurse -Force -ErrorAction Stop
                $summary.Bytes += $leftover.SizeBytes
            }
            $summary.Removed++
            [void]$removedPaths.Add($leftover.Path)
            $summary.Details += "$($leftover.Path): $(Get-WzText 'unin.detailRemoved')"
            Write-WzLog (Get-WzText 'unin.logLeftoverRemoved' @{ pfad = $leftover.Path }) -Level Ok
        } catch {
            $summary.Failed++
            $message = $_.Exception.Message.Split([char]10)[0]
            $summary.Details += "$($leftover.Path): $message"
            Write-WzLog (Get-WzText 'unin.logLeftoverFailed' @{ pfad = $leftover.Path; grund = $message }) -Level Warn
        }
    }

    if ($removedPaths.Count -gt 0) {
        # Damit die Sicherung auf der Seite »Rücknahme« auftaucht. Automatisch
        # zurückholen lässt sich davon nichts — der Hinweis sagt, was geht.
        Save-WzUndoState -Session $session -ItemId 'uninstall-leftovers' `
            -ItemName (Get-WzText 'unin.undoItemName') `
            -Action @{ type = 'leftoverCleanup'; undo = @{
                hint = (Get-WzText 'unin.undoHint') } } `
            -Previous @{ paths = @($removedPaths) }
        $summary.UndoFile = Complete-WzUndoSession -Session $session
    } else {
        # Kein Rest entfernt: den leeren Sicherungsordner nicht stehen lassen.
        try { Remove-Item -LiteralPath $session.Directory -Recurse -Force -ErrorAction Stop } catch { }
    }

    return $summary
}
