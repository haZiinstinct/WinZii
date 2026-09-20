# Setup — die Handgriffe direkt nach der Neuinstallation.
#
# Bis hierher konnte WinZii einen PC aufräumen, aber nicht einrichten: Name,
# Konto, Zeitzone, Tastatur und Aktivierung musste der Techniker in den
# Windows-Einstellungen erledigen — also außerhalb des Werkzeugs, ohne
# Protokoll und ohne Zeile im Übergabeblatt. Genau diese Lücke schließt dieses
# Modul.

function Get-WzSetupState {
    <#
    .SYNOPSIS
        Der Ist-Zustand aller Einstellungen dieser Seite auf einen Blick.
    .DESCRIPTION
        Eine einzige Abfrage für die ganze Seite: Sie läuft im Hintergrund,
        und die Seite füllt daraus jede Karte. Getrennte Abfragen je Karte
        hätten fünf Runspaces gekostet und die Seite in Stufen aufgebaut.
    #>
    [CmdletBinding()]
    param()

    $state = [pscustomobject]@{
        ComputerName    = $env:COMPUTERNAME
        Workgroup       = ''
        InDomain        = $false
        TimeZoneId      = ''
        TimeZoneName    = ''
        SystemTime      = Get-Date
        TimeServiceOk   = $false
        TimeSource      = ''
        Culture         = ''
        CultureName     = ''
        HomeLocation    = ''
        Keyboards       = @()
        Activation      = $null
        OemKey          = ''
        Accounts        = @()
        AdminGroupName  = ''
    }

    try {
        $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $state.ComputerName = $system.Name
        $state.Workgroup = if ($system.Workgroup) { $system.Workgroup } else { $system.Domain }
        $state.InDomain = [bool]$system.PartOfDomain
    } catch { }

    try {
        $zone = Get-TimeZone -ErrorAction Stop
        $state.TimeZoneId = $zone.Id
        $state.TimeZoneName = $zone.DisplayName
    } catch { }

    # Der Zeitdienst ist der häufigste Grund für »Zertifikat ungültig« und für
    # Anmeldungen, die im Netz abgelehnt werden. Läuft er nicht, steht die Uhr
    # nach ein paar Wochen daneben, ohne dass es jemandem auffällt.
    try {
        $service = Get-Service -Name 'W32Time' -ErrorAction Stop
        $state.TimeServiceOk = ($service.Status -eq 'Running')
    } catch { }

    try {
        $source = Invoke-WzProcess -FilePath 'w32tm.exe' -Arguments '/query /source' -TimeoutSeconds 20
        if ($source.ExitCode -eq 0 -and $source.StdOut) {
            $state.TimeSource = $source.StdOut.Trim()
        }
    } catch { }

    try {
        $culture = Get-Culture -ErrorAction Stop
        $state.Culture = $culture.Name
        $state.CultureName = $culture.DisplayName
    } catch { }

    try {
        $location = Get-WinHomeLocation -ErrorAction Stop
        $state.HomeLocation = $location.HomeLocation
    } catch { }

    try {
        $list = @(Get-WinUserLanguageList -ErrorAction Stop)
        $state.Keyboards = @($list | ForEach-Object {
            [pscustomobject]@{
                Tag     = $_.LanguageTag
                Name    = $_.LocalizedName
                Layouts = @($_.InputMethodTips)
            }
        })
    } catch { }

    $state.Activation = Get-WzActivationStatus
    $state.OemKey = Get-WzOemProductKey
    $state.AdminGroupName = Get-WzLocalGroupName -Sid 'S-1-5-32-544'
    $state.Accounts = Get-WzLocalAccounts

    return $state
}

function Get-WzLocalGroupName {
    <#
    .SYNOPSIS
        Der Name einer eingebauten Gruppe, ermittelt über ihre SID.
    .NOTES
        »Administratoren« heißt auf einem englischen Windows »Administrators«
        und auf einem französischen »Administrateurs«. Der Name ist deshalb als
        Vergleichswert unbrauchbar — die SID ist auf jedem Windows dieselbe.
    #>
    param([Parameter(Mandatory = $true)][string]$Sid)

    try {
        $group = Get-LocalGroup -SID $Sid -ErrorAction Stop
        return $group.Name
    } catch {
        return ''
    }
}

function Get-WzLocalAccounts {
    <#
    .SYNOPSIS
        Die lokalen Konten mit Typ, Zustand und letzter Anmeldung.
    #>
    [CmdletBinding()]
    param()

    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop |
            ForEach-Object { $_.SID.Value })
    } catch { }

    $accounts = @()
    try {
        foreach ($user in (Get-LocalUser -ErrorAction Stop)) {
            # Die eingebauten Konten (Gast, Standardkonto, WDAG) gehören nicht
            # in die Liste: Sie sind abgeschaltet und sollen es bleiben. Sie
            # tragen alle eine SID, die auf -501 bis -504 endet.
            if ($user.SID.Value -match '-50[1-4]$') { continue }
            $accounts += [pscustomobject]@{
                Name      = $user.Name
                FullName  = $user.FullName
                Enabled   = $user.Enabled
                IsAdmin   = ($admins -contains $user.SID.Value)
                LastLogon = $user.LastLogon
                Sid       = $user.SID.Value
            }
        }
    } catch {
        Write-WzLog (Get-WzText 'setup.logAccountsUnreadable' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    return @($accounts | Sort-Object -Property @{ Expression = 'IsAdmin'; Descending = $true }, Name)
}

function Test-WzComputerNameValid {
    <#
    .SYNOPSIS
        Prüft einen Rechnernamen gegen die Regeln von NetBIOS.
    .NOTES
        Windows nimmt über Rename-Computer auch Namen an, die es später selbst
        nicht mehr auflösen kann — Unterstriche etwa. Erlaubt sind Buchstaben,
        Ziffern und der Bindestrich, höchstens 15 Zeichen, nicht nur Ziffern.
    #>
    param([string]$Name)

    $result = [pscustomobject]@{ Valid = $false; Reason = '' }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $result.Reason = Get-WzText 'setup.nameEmpty'
        return $result
    }
    if ($Name.Length -gt 15) {
        $result.Reason = Get-WzText 'setup.nameTooLong'
        return $result
    }
    if ($Name -notmatch '^[A-Za-z0-9-]+$') {
        $result.Reason = Get-WzText 'setup.nameBadChars'
        return $result
    }
    if ($Name -match '^[0-9]+$') {
        $result.Reason = Get-WzText 'setup.nameOnlyDigits'
        return $result
    }
    if ($Name.StartsWith('-') -or $Name.EndsWith('-')) {
        $result.Reason = Get-WzText 'setup.nameBadDash'
        return $result
    }

    $result.Valid = $true
    return $result
}

function Set-WzComputerName {
    <#
    .SYNOPSIS
        Benennt den Rechner um. Wirksam erst nach dem Neustart.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$NewName)

    $result = [pscustomobject]@{ Success = $false; Summary = ''; RebootRequired = $true }

    $check = Test-WzComputerNameValid -Name $NewName
    if (-not $check.Valid) {
        $result.Summary = $check.Reason
        return $result
    }

    if ($NewName -eq $env:COMPUTERNAME) {
        $result.Summary = Get-WzText 'setup.nameUnchanged'
        return $result
    }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'setup.logNameTest' @{ name = $NewName }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    try {
        Rename-Computer -NewName $NewName -Force -ErrorAction Stop
        $result.Success = $true
        $result.Summary = Get-WzText 'setup.nameChanged' @{ alt = $env:COMPUTERNAME; neu = $NewName }
        Write-WzLog $result.Summary -Level Ok
    } catch {
        $result.Summary = Get-WzText 'setup.nameFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }
        Write-WzLog $result.Summary -Level Error
    }

    return $result
}

function Get-WzTimeZoneList {
    <#
    .SYNOPSIS
        Alle Zeitzonen, die passende zuerst.
    .NOTES
        Über 140 Einträge sind für ein Auswahlfeld zu viele. Die aktuelle und
        die mitteleuropäischen stehen deshalb oben — in der Praxis ist es
        immer eine davon.
    #>
    [CmdletBinding()]
    param()

    $preferred = @('W. Europe Standard Time', 'Central European Standard Time',
                   'Romance Standard Time', 'GMT Standard Time', 'UTC')
    $current = ''
    try { $current = (Get-TimeZone -ErrorAction Stop).Id } catch { }

    $all = @()
    try { $all = @(Get-TimeZone -ListAvailable -ErrorAction Stop) } catch { return @() }

    $order = @()
    if ($current) { $order += $current }
    foreach ($id in $preferred) { if ($order -notcontains $id) { $order += $id } }

    $sorted = @()
    foreach ($id in $order) {
        $zone = $all | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($zone) { $sorted += $zone }
    }
    $sorted += @($all | Where-Object { $order -notcontains $_.Id } | Sort-Object BaseUtcOffset, Id)

    return @($sorted)
}

function Set-WzTimeZone {
    <#
    .SYNOPSIS
        Setzt die Zeitzone.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Id)

    $result = [pscustomobject]@{ Success = $false; Summary = '' }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'setup.logZoneTest' @{ zone = $Id }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    try {
        Set-TimeZone -Id $Id -ErrorAction Stop
        $zone = Get-TimeZone -ErrorAction SilentlyContinue
        $result.Success = $true
        $result.Summary = Get-WzText 'setup.zoneSet' @{ zone = $(if ($zone) { $zone.DisplayName } else { $Id }) }
        Write-WzLog $result.Summary -Level Ok
    } catch {
        $result.Summary = Get-WzText 'setup.zoneFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }
        Write-WzLog $result.Summary -Level Error
    }

    return $result
}

function Sync-WzSystemTime {
    <#
    .SYNOPSIS
        Startet den Zeitdienst und holt die Uhrzeit vom Zeitserver.
    .DESCRIPTION
        Drei Schritte, weil ein einzelner Abgleich auf einem frisch
        aufgesetzten PC fast immer scheitert: Der Dienst steht auf manuellem
        Start und läuft nicht. Erst Starttyp, dann starten, dann abgleichen.
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ Success = $false; Summary = ''; Source = ''; Time = $null }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'setup.logTimeTest') -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    Write-WzLog (Get-WzText 'setup.logTimeRunning') -Level Action

    try {
        Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction Stop
        Start-Service -Name 'W32Time' -ErrorAction Stop
    } catch {
        Write-WzLog (Get-WzText 'setup.logTimeService' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    # Mit Zwang, weil der Dienst einen Abgleich sonst ablehnt, wenn er meint,
    # er habe erst vor Kurzem einen gemacht — auf einem neuen PC ist das nie wahr.
    $resync = Invoke-WzProcess -FilePath 'w32tm.exe' -Arguments '/resync /force' -TimeoutSeconds 60 -LogOutput
    $result.Success = ($resync.ExitCode -eq 0)

    $source = Invoke-WzProcess -FilePath 'w32tm.exe' -Arguments '/query /source' -TimeoutSeconds 20
    if ($source.ExitCode -eq 0 -and $source.StdOut) { $result.Source = $source.StdOut.Trim() }

    $result.Time = Get-Date
    $result.Summary = if ($result.Success) {
        Get-WzText 'setup.timeSynced' @{ zeit = $result.Time.ToString('G', (Get-WzLanguageCulture)); quelle = $result.Source }
    } else {
        Get-WzText 'setup.timeFailed' @{ code = $resync.ExitCode }
    }

    Write-WzLog $result.Summary -Level $(if ($result.Success) { 'Ok' } else { 'Warn' })
    return $result
}

function Set-WzRegionalSettings {
    <#
    .SYNOPSIS
        Setzt Zahlen- und Datumsformat, Standort und Tastaturlayout.
    .DESCRIPTION
        Der häufigste Fall nach einer Neuinstallation von einem englischen
        Abbild: Windows spricht deutsch, rechnet aber in Punkt statt Komma und
        schreibt das Datum amerikanisch. Das fällt erst beim Kunden auf, in
        Excel.
    .PARAMETER Culture
        Zahlen- und Datumsformat, z. B. de-DE.
    .PARAMETER HomeLocation
        Standort als GeoID, z. B. 94 für Deutschland.
    .PARAMETER KeyboardTag
        Sprachkennung für das Tastaturlayout, z. B. de-DE.
    .NOTES
        Wirkt nur für das angemeldete Konto. Für neue Konten kopiert Windows
        die Einstellungen aus dem Standardprofil — dafür gibt es in der
        Systemsteuerung »Einstellungen kopieren«, das ein Abmelden verlangt
        und deshalb hier nicht angefasst wird.
    #>
    [CmdletBinding()]
    param(
        [string]$Culture,
        [int]$HomeLocation = 0,
        [string]$KeyboardTag
    )

    $result = [pscustomobject]@{ Success = $false; Changed = @(); Summary = '' }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'setup.logRegionTest' @{ kultur = $Culture }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    if ($Culture) {
        try {
            Set-Culture -CultureInfo $Culture -ErrorAction Stop
            $result.Changed += Get-WzText 'setup.regionFormat' @{ kultur = $Culture }
        } catch {
            Write-WzLog (Get-WzText 'setup.logCultureFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        }
    }

    if ($HomeLocation -gt 0) {
        try {
            Set-WinHomeLocation -GeoId $HomeLocation -ErrorAction Stop
            $result.Changed += Get-WzText 'setup.regionLocation' @{ id = $HomeLocation }
        } catch {
            Write-WzLog (Get-WzText 'setup.logLocationFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        }
    }

    if ($KeyboardTag) {
        try {
            # Die vorhandene Liste wird ergänzt, nicht ersetzt: Wer sein
            # englisches Layout behalten will, behält es. Vorn steht danach
            # aber das neue — das ist die Vorgabe beim Anmelden.
            $list = Get-WinUserLanguageList -ErrorAction Stop
            if (@($list | Where-Object { $_.LanguageTag -eq $KeyboardTag }).Count -eq 0) {
                $list.Add($KeyboardTag)
            }
            $wanted = @($list | Where-Object { $_.LanguageTag -eq $KeyboardTag })
            $others = @($list | Where-Object { $_.LanguageTag -ne $KeyboardTag })
            Set-WinUserLanguageList -LanguageList (@($wanted) + @($others)) -Force -ErrorAction Stop
            $result.Changed += Get-WzText 'setup.regionKeyboard' @{ sprache = $KeyboardTag }
        } catch {
            Write-WzLog (Get-WzText 'setup.logKeyboardFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        }
    }

    $result.Success = ($result.Changed.Count -gt 0)
    $result.Summary = if ($result.Success) {
        Get-WzText 'setup.regionDone' @{ anzahl = $result.Changed.Count }
    } else {
        Get-WzText 'setup.regionNothing'
    }
    Write-WzLog $result.Summary -Level $(if ($result.Success) { 'Ok' } else { 'Warn' })

    return $result
}

function New-WzLocalAccount {
    <#
    .SYNOPSIS
        Legt ein lokales Konto an und nimmt es in die passende Gruppe auf.
    .PARAMETER Password
        Als SecureString. Das Kennwort wird nirgends protokolliert, nicht in
        die Sicherung geschrieben und nicht im Übergabeblatt genannt.
    .PARAMETER IsAdmin
        In die Administratorengruppe aufnehmen. Ohne das wird es ein
        Standardkonto — die richtige Wahl für den Alltag des Kunden.
    .NOTES
        Die Gruppen werden über ihre SID angesprochen, nicht über den Namen:
        »Benutzer« heißt auf einem englischen Windows »Users«.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [securestring]$Password,
        [string]$FullName,
        [switch]$IsAdmin,
        [switch]$PasswordNeverExpires
    )

    $result = [pscustomobject]@{ Success = $false; Summary = ''; Name = $Name; IsAdmin = $IsAdmin.IsPresent }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $result.Summary = Get-WzText 'setup.accountNoName'
        return $result
    }

    # Windows lehnt diese Zeichen ab, meldet das aber erst nach dem Anlegen
    # als nichtssagenden Fehler.
    if ($Name -match '["/\\\[\]:;|=,+*?<>@]') {
        $result.Summary = Get-WzText 'setup.accountBadChars'
        return $result
    }

    $existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        $result.Summary = Get-WzText 'setup.accountExists' @{ name = $Name }
        return $result
    }

    $kind = if ($IsAdmin) { Get-WzText 'setup.accountAdmin' } else { Get-WzText 'setup.accountStandard' }

    if ($syncHash.DryRun) {
        Write-WzLog (Get-WzText 'setup.logAccountTest' @{ name = $Name; art = $kind }) -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    try {
        $parameters = @{ Name = $Name; ErrorAction = 'Stop' }
        if ($FullName) { $parameters.FullName = $FullName }
        if ($Password) {
            $parameters.Password = $Password
        } else {
            # Ein Konto ohne Kennwort ist eine bewusste Entscheidung des
            # Technikers — Windows verlangt dafür diesen Schalter.
            $parameters.NoPassword = $true
        }
        if ($PasswordNeverExpires) { $parameters.PasswordNeverExpires = $true }

        [void](New-LocalUser @parameters)
    } catch {
        $result.Summary = Get-WzText 'setup.accountFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }
        Write-WzLog $result.Summary -Level Error
        return $result
    }

    $groupSid = if ($IsAdmin) { 'S-1-5-32-544' } else { 'S-1-5-32-545' }
    try {
        Add-LocalGroupMember -SID $groupSid -Member $Name -ErrorAction Stop
    } catch {
        # Das Konto steht schon, nur die Gruppe fehlt. Das ist kein Fehlschlag,
        # muss aber gesagt werden — sonst fehlen dem Kunden später die Rechte.
        Write-WzLog (Get-WzText 'setup.logGroupFailed' @{ name = $Name; grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
    }

    $result.Success = $true
    $result.Summary = Get-WzText 'setup.accountCreated' @{ name = $Name; art = $kind }
    Write-WzLog $result.Summary -Level Ok

    return $result
}

function Get-WzOemProductKey {
    <#
    .SYNOPSIS
        Der Windows-Schlüssel aus der Firmware, falls das Gerät einen hat.
    .DESCRIPTION
        Seit Windows 8 brennen die Hersteller den Schlüssel in die Firmware.
        Nach einer Neuinstallation vom falschen Abbild — Home statt Pro oder
        umgekehrt — aktiviert Windows nicht von selbst, und dieser Schlüssel
        ist der Weg zurück. Er steht auf keinem Aufkleber mehr.
    #>
    [CmdletBinding()]
    param()

    try {
        $service = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
        if ($service.OA3xOriginalProductKey) { return $service.OA3xOriginalProductKey }
    } catch { }
    return ''
}

function Test-WzProductKeyFormat {
    <#
    .SYNOPSIS
        Prüft einen Produktschlüssel auf die Form fünfmal fünf Zeichen.
    #>
    param([string]$Key)

    if (-not $Key) { return $false }
    $clean = ($Key -replace '[^A-Za-z0-9]', '')
    return ($clean.Length -eq 25)
}

function Install-WzProductKey {
    <#
    .SYNOPSIS
        Trägt einen Windows-Schlüssel ein und aktiviert anschließend.
    .DESCRIPTION
        Zwei getrennte Schritte: eintragen und aktivieren. Der zweite braucht
        Internet und scheitert ohne — deshalb wird er einzeln bewertet, sonst
        stünde »fehlgeschlagen« da, obwohl der Schlüssel richtig eingetragen
        wurde.
    .NOTES
        Aufgerufen wird slmgr über cscript. Ohne cscript meldet sich das Skript
        mit Fenstern, die niemand wegklickt, wenn der Aufruf im Hintergrund läuft.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Key)

    $result = [pscustomobject]@{ Success = $false; Installed = $false; Activated = $false; Summary = '' }

    $clean = ($Key -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
    if ($clean.Length -ne 25) {
        $result.Summary = Get-WzText 'setup.keyBadFormat'
        return $result
    }
    $formatted = (0..4 | ForEach-Object { $clean.Substring($_ * 5, 5) }) -join '-'

    if ($syncHash.DryRun) {
        # Der Schlüssel selbst gehört nicht ins Protokoll — es wandert als
        # Datei auf den Stick und geht durch fremde Hände.
        Write-WzLog (Get-WzText 'setup.logKeyTest') -Level Test
        $result.Success = $true
        $result.Summary = Get-WzText 'core.dryRunSummary'
        return $result
    }

    $slmgr = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
    Write-WzLog (Get-WzText 'setup.logKeyInstalling') -Level Action

    $install = Invoke-WzProcess -FilePath 'cscript.exe' `
        -Arguments "//nologo `"$slmgr`" /ipk $formatted" -TimeoutSeconds 180
    $result.Installed = ($install.ExitCode -eq 0)

    if (-not $result.Installed) {
        $result.Summary = Get-WzText 'setup.keyInstallFailed' @{ code = $install.ExitCode }
        Write-WzLog $result.Summary -Level Error
        return $result
    }

    Write-WzLog (Get-WzText 'setup.logKeyActivating') -Level Action
    $activate = Invoke-WzProcess -FilePath 'cscript.exe' `
        -Arguments "//nologo `"$slmgr`" /ato" -TimeoutSeconds 300

    $status = Get-WzActivationStatus
    $result.Activated = (($activate.ExitCode -eq 0) -and $status.Ok)
    $result.Success = $result.Installed

    $result.Summary = if ($result.Activated) {
        Get-WzText 'setup.keyActivated'
    } else {
        Get-WzText 'setup.keyInstalledNotActive' @{ status = $status.Text }
    }
    Write-WzLog $result.Summary -Level $(if ($result.Activated) { 'Ok' } else { 'Warn' })

    return $result
}

function Get-WzPrinterDriverNames {
    <#
    .SYNOPSIS
        Die Druckertreiber, die auf diesem PC schon einsatzbereit sind.
    #>
    [CmdletBinding()]
    param()

    try {
        return @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { $_.Name } | Sort-Object)
    } catch {
        return @()
    }
}

function Add-WzIpPrinter {
    <#
    .SYNOPSIS
        Legt einen Netzwerkdrucker über seine IP-Adresse an.
    .DESCRIPTION
        Baut denselben Datensatz, den auch eine Sicherung liefert, und übergibt
        ihn an Import-WzPrinters. Damit gibt es für das Anlegen eines Druckers
        genau einen Weg — samt Nachziehen des Treibers aus dem Treiberspeicher
        und Aufräumen des Anschlusses, wenn es schiefgeht.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Address,
        [Parameter(Mandatory = $true)][string]$DriverName
    )

    $result = [pscustomobject]@{ Success = $false; Summary = '' }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $result.Summary = Get-WzText 'setup.printerNoName'
        return $result
    }

    $octet = '(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
    if ($Address -notmatch "^$octet(\.$octet){3}$") {
        $result.Summary = Get-WzText 'setup.printerBadAddress' @{ adresse = $Address }
        return $result
    }

    $printer = [pscustomobject]@{
        name      = $Name
        treiber   = $DriverName
        anschluss = "IP_$Address"
        netzwerk  = $false
    }

    $import = Import-WzPrinters -Printers @($printer)

    $result.Success = (@($import.Applied).Count -gt 0)
    $result.Summary = if ($result.Success) {
        Get-WzText 'setup.printerAdded' @{ name = $Name; adresse = $Address }
    } elseif (@($import.MissingDriver).Count -gt 0) {
        Get-WzText 'setup.printerNoDriver' @{ treiber = $DriverName }
    } else {
        Get-WzText 'setup.printerFailed' @{ name = $Name }
    }

    return $result
}

function Open-WzSettingsPage {
    <#
    .SYNOPSIS
        Öffnet eine Seite der Windows-Einstellungen.
    .DESCRIPTION
        Für das, was Windows 11 nicht mehr von außen setzen lässt. Die
        Standardprogramme sind der bekannteste Fall: Seit Windows 10 prüft
        Windows die Zuordnung mit einer Prüfsumme, und ein von außen gesetzter
        Eintrag wird beim nächsten Start still zurückgedreht. Ein Werkzeug, das
        etwas anderes verspricht, täuscht — deshalb führt WinZii an die
        richtige Stelle, statt so zu tun.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Page)

    try {
        Start-Process $Page -ErrorAction Stop
        Write-WzLog (Get-WzText 'setup.logSettingsOpened' @{ seite = $Page }) -Level Info
        return $true
    } catch {
        Write-WzLog (Get-WzText 'setup.logSettingsFailed' @{ seite = $Page; grund = $_.Exception.Message.Split([char]10)[0] }) -Level Warn
        return $false
    }
}
