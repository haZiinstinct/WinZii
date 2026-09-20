# Seite "Einrichten" — Rechnername, Zeit und Region, Konten, Aktivierung,
# Drucker und Standardprogramme.

function Initialize-WzSetupPage {
    $syncHash.SetupBtnName.Add_Click({ Start-WzComputerRename })
    $syncHash.SetupBtnZone.Add_Click({ Start-WzTimeZoneChange })
    $syncHash.SetupBtnTimeSync.Add_Click({ Start-WzTimeSync })
    $syncHash.SetupBtnRegion.Add_Click({ Start-WzRegionChange })
    $syncHash.SetupBtnAccount.Add_Click({ Start-WzAccountCreate })
    $syncHash.SetupBtnKeyFromFirmware.Add_Click({ Copy-WzFirmwareKey })
    $syncHash.SetupBtnKey.Add_Click({ Start-WzKeyInstall })
    $syncHash.SetupBtnPrinter.Add_Click({ Start-WzPrinterAdd })

    $syncHash.SetupBtnDefaultApps.Add_Click({ [void](Open-WzSettingsPage -Page 'ms-settings:defaultapps') })
    $syncHash.SetupBtnStartupApps.Add_Click({ [void](Open-WzSettingsPage -Page 'ms-settings:powersleep') })
    $syncHash.SetupBtnWindowsUpdate.Add_Click({ [void](Open-WzSettingsPage -Page 'ms-settings:windowsupdate') })

    # Die Auswahl für Format und Tastatur: die drei deutschsprachigen Länder
    # und die englischen, die auf Kundengeräten wirklich vorkommen. Die GeoID
    # gehört zum Land, nicht zur Sprache — 94 ist Deutschland.
    foreach ($region in @(
        @{ Name = 'Deutschland — de-DE'; Culture = 'de-DE'; Geo = 94 },
        @{ Name = 'Österreich — de-AT'; Culture = 'de-AT'; Geo = 14 },
        @{ Name = 'Schweiz — de-CH'; Culture = 'de-CH'; Geo = 223 },
        @{ Name = 'United Kingdom — en-GB'; Culture = 'en-GB'; Geo = 242 },
        @{ Name = 'United States — en-US'; Culture = 'en-US'; Geo = 244 }
    )) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = $region.Name
        $item.Tag = $region
        [void]$syncHash.SetupRegionBox.Items.Add($item)
    }
    $syncHash.SetupRegionBox.SelectedIndex = 0

    [void]$syncHash.SetupNotices.Items.Add((New-WzNotice -Kind 'info' `
        -Text (Get-WzText 'setup.noticeAsksFirst')))
}

function Update-WzSetupPage {
    Invoke-WzTask -Name (Get-WzText 'setup.taskRead') -Silent -Cancelable -ScriptBlock {
        [pscustomobject]@{
            State   = Get-WzSetupState
            Zones   = Get-WzTimeZoneList
            Drivers = Get-WzPrinterDriverNames
        }
    } -OnComplete {
        param($data)
        if (-not $data) { return }
        $syncHash.SetupState = $data.State
        Write-WzSetupState -State $data.State -Zones $data.Zones -Drivers $data.Drivers
    }
}

function Write-WzSetupState {
    <#
    .SYNOPSIS
        Füllt die Karten der Seite mit dem gemessenen Zustand.
    #>
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowEmptyCollection()][array]$Zones = @(),
        [AllowEmptyCollection()][array]$Drivers = @()
    )

    # --- Rechnername -------------------------------------------------------
    $nameRows = $syncHash.SetupNameRows
    $nameRows.Children.Clear()
    [void]$nameRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowCurrentName') $State.ComputerName))
    $groupLabel = if ($State.InDomain) { Get-WzText 'setup.rowDomain' } else { Get-WzText 'setup.rowWorkgroup' }
    [void]$nameRows.Children.Add((New-WzInfoRow $groupLabel $State.Workgroup))
    if (-not $syncHash.SetupNameBox.Text) { $syncHash.SetupNameBox.Text = $State.ComputerName }

    # In einer Domäne benennt man einen Rechner nicht nebenbei um: Das
    # Computerkonto im Verzeichnis bleibt auf dem alten Namen, und danach
    # meldet sich niemand mehr an. Das ist Sache des Administrators.
    $syncHash.SetupBtnName.IsEnabled = (-not $State.InDomain)

    # --- Zeit und Region ---------------------------------------------------
    $timeRows = $syncHash.SetupTimeRows
    $timeRows.Children.Clear()
    [void]$timeRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowTime') `
        $State.SystemTime.ToString('G', (Get-WzLanguageCulture))))
    [void]$timeRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowZone') $State.TimeZoneName))
    [void]$timeRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowTimeService') `
        $(if ($State.TimeServiceOk) { Get-WzText 'setup.serviceRunning' } else { Get-WzText 'setup.serviceStopped' }) `
        -Kind $(if ($State.TimeServiceOk) { 'ok' } else { 'warn' })))
    if ($State.TimeSource) {
        [void]$timeRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowTimeSource') $State.TimeSource))
    }
    [void]$timeRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowFormat') $State.CultureName))
    $layouts = @($State.Keyboards | ForEach-Object { $_.Name })
    [void]$timeRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowKeyboard') ($layouts -join ', ')))

    if ($syncHash.SetupZoneBox.Items.Count -eq 0) {
        foreach ($zone in $Zones) {
            $item = New-Object Windows.Controls.ComboBoxItem
            $item.Content = $zone.DisplayName
            $item.Tag = $zone.Id
            [void]$syncHash.SetupZoneBox.Items.Add($item)
        }
        $syncHash.SetupZoneBox.SelectedIndex = 0
    }

    # --- Konten ------------------------------------------------------------
    $accounts = @($State.Accounts)
    $syncHash.SetupAccountTitle.Text = if ($accounts.Count -eq 1) {
        Get-WzText 'setup.accountCountOne'
    } else {
        Get-WzText 'setup.accountCount' @{ anzahl = $accounts.Count }
    }

    $accountRows = $syncHash.SetupAccountRows
    $accountRows.Children.Clear()
    foreach ($account in $accounts) {
        $parts = @()
        $parts += if ($account.IsAdmin) { Get-WzText 'setup.accountAdmin' } else { Get-WzText 'setup.accountStandard' }
        if (-not $account.Enabled) { $parts += Get-WzText 'setup.accountDisabled' }
        $parts += if ($account.LastLogon) {
            Get-WzText 'setup.accountLastLogon' @{ zeit = (Format-WzAgo $account.LastLogon) }
        } else {
            Get-WzText 'setup.accountNeverUsed'
        }
        $kind = if (-not $account.Enabled) { 'warn' } elseif ($account.IsAdmin) { 'normal' } else { 'ok' }
        [void]$accountRows.Children.Add((New-WzInfoRow $account.Name ($parts -join ' · ') -Kind $kind -LabelWidth 180))
    }

    # --- Aktivierung -------------------------------------------------------
    $activationRows = $syncHash.SetupActivationRows
    $activationRows.Children.Clear()
    $activation = $State.Activation
    if ($activation) {
        [void]$activationRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowActivation') `
            $activation.Text -Kind $(if ($activation.Ok) { 'ok' } else { 'warn' })))
    }
    [void]$activationRows.Children.Add((New-WzInfoRow (Get-WzText 'setup.rowFirmwareKey') `
        $(if ($State.OemKey) { Get-WzText 'setup.keyPresent' } else { Get-WzText 'setup.keyAbsent' }) `
        -Kind $(if ($State.OemKey) { 'ok' } else { 'normal' })))
    $syncHash.SetupBtnKeyFromFirmware.IsEnabled = [bool]$State.OemKey

    # --- Drucker -----------------------------------------------------------
    if ($syncHash.SetupPrinterDriver.Items.Count -eq 0) {
        foreach ($driver in $Drivers) {
            $item = New-Object Windows.Controls.ComboBoxItem
            $item.Content = $driver
            $item.Tag = $driver
            [void]$syncHash.SetupPrinterDriver.Items.Add($item)
        }
        if ($syncHash.SetupPrinterDriver.Items.Count -gt 0) {
            $syncHash.SetupPrinterDriver.SelectedIndex = 0
        }
    }
    $syncHash.SetupBtnPrinter.IsEnabled = ($syncHash.SetupPrinterDriver.Items.Count -gt 0)
}

# --- Rechnername -----------------------------------------------------------

function Start-WzComputerRename {
    $newName = $syncHash.SetupNameBox.Text.Trim()

    # Vor dem Dialog prüfen: Ein Bestätigungsdialog, der eine Eingabe absegnet,
    # die Windows danach ablehnt, führt den Techniker zweimal durch dieselbe
    # Entscheidung.
    $check = Test-WzComputerNameValid -Name $newName
    if (-not $check.Valid) {
        Show-WzInfo -Title (Get-WzText 'setup.nameDialogTitle') -Message $check.Reason
        return
    }
    if ($newName -eq $env:COMPUTERNAME) {
        Show-WzInfo -Title (Get-WzText 'setup.nameDialogTitle') -Message (Get-WzText 'setup.nameUnchanged')
        return
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'setup.nameDialogTitle') `
        -Message (Get-WzText 'setup.nameDialogMessage' @{ alt = $env:COMPUTERNAME; neu = $newName }) `
        -Items @((Get-WzText 'setup.nameDialogItem1'), (Get-WzText 'setup.nameDialogItem2')) `
        -ConfirmText (Get-WzText 'setup.btnName')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'setup.taskName') -ArgumentList @($newName) -ScriptBlock {
        param($name)
        Set-WzComputerName -NewName $name
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Einrichtung' -RebootRequired `
                -Summary (Get-WzText 'setup.actionName' @{ name = $newName })
        }
        Show-WzInfo -Title (Get-WzText 'setup.nameDialogTitle') -Message $result.Summary
        Update-WzSetupPage
    }.GetNewClosure()
}

# --- Zeit und Region -------------------------------------------------------

function Start-WzTimeZoneChange {
    $selected = $syncHash.SetupZoneBox.SelectedItem
    if (-not $selected) { return }
    $zoneId = $selected.Tag
    $zoneName = $selected.Content

    Invoke-WzTask -Name (Get-WzText 'setup.taskZone') -ArgumentList @($zoneId) -ScriptBlock {
        param($id)
        Set-WzTimeZone -Id $id
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Einrichtung' -Summary (Get-WzText 'setup.actionZone' @{ zone = $zoneName })
        }
        Show-WzInfo -Title (Get-WzText 'setup.zoneDialogTitle') -Message $result.Summary
        Update-WzSetupPage
    }.GetNewClosure()
}

function Start-WzTimeSync {
    Invoke-WzTask -Name (Get-WzText 'setup.taskTimeSync') -ScriptBlock {
        Sync-WzSystemTime
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Einrichtung' -Summary (Get-WzText 'setup.actionTimeSync')
        }
        Show-WzInfo -Title (Get-WzText 'setup.timeDialogTitle') -Message $result.Summary
        Update-WzSetupPage
    }
}

function Start-WzRegionChange {
    $selected = $syncHash.SetupRegionBox.SelectedItem
    if (-not $selected) { return }
    $region = $selected.Tag

    $answer = Show-WzConfirm -Title (Get-WzText 'setup.regionDialogTitle') `
        -Message (Get-WzText 'setup.regionDialogMessage' @{ land = $selected.Content }) `
        -Items @(
            (Get-WzText 'setup.regionItemFormat' @{ kultur = $region.Culture }),
            (Get-WzText 'setup.regionItemLocation'),
            (Get-WzText 'setup.regionItemKeyboard' @{ sprache = $region.Culture })
        ) `
        -ConfirmText (Get-WzText 'setup.btnRegion')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'setup.taskRegion') -ArgumentList @($region.Culture, [int]$region.Geo) -ScriptBlock {
        param($culture, $geo)
        Set-WzRegionalSettings -Culture $culture -HomeLocation $geo -KeyboardTag $culture
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Einrichtung' -Summary (Get-WzText 'setup.actionRegion' @{ land = $selected.Content }) `
                -Detail @($result.Changed)
        }
        Show-WzInfo -Title (Get-WzText 'setup.regionDialogTitle') -Message $result.Summary -Items @($result.Changed)
        Update-WzSetupPage
    }.GetNewClosure()
}

# --- Konto -----------------------------------------------------------------

function Start-WzAccountCreate {
    $name = $syncHash.SetupAccountName.Text.Trim()
    $password = $syncHash.SetupAccountPassword.SecurePassword
    $repeat = $syncHash.SetupAccountRepeat.SecurePassword
    $isAdmin = [bool]$syncHash.SetupAccountAdmin.IsChecked
    $neverExpires = [bool]$syncHash.SetupAccountNeverExpires.IsChecked

    if (-not $name) {
        Show-WzInfo -Title (Get-WzText 'setup.accountDialogTitle') -Message (Get-WzText 'setup.accountNoName')
        return
    }

    # Die beiden Felder werden verglichen, ohne das Kennwort je im Klartext in
    # einer Variablen zu halten: Die Zeichenketten leben nur innerhalb dieser
    # Prüfung und werden gleich danach aus dem Speicher geräumt.
    if (-not (Test-WzSecureStringsEqual -First $password -Second $repeat)) {
        Show-WzInfo -Title (Get-WzText 'setup.accountDialogTitle') -Message (Get-WzText 'setup.accountMismatch')
        return
    }

    $items = @()
    $items += if ($isAdmin) { Get-WzText 'setup.accountItemAdmin' } else { Get-WzText 'setup.accountItemStandard' }
    $items += if ($password.Length -gt 0) { Get-WzText 'setup.accountItemPassword' } else { Get-WzText 'setup.accountItemNoPassword' }
    if ($neverExpires) { $items += Get-WzText 'setup.accountItemNeverExpires' }

    $answer = Show-WzConfirm -Title (Get-WzText 'setup.accountDialogTitle') `
        -Message (Get-WzText 'setup.accountDialogMessage' @{ name = $name }) `
        -Items $items -ConfirmText (Get-WzText 'setup.btnAccount') -Danger:$isAdmin
    if (-not $answer.Confirmed) { return }

    # Ohne Kennwort wird kein SecureString übergeben — New-LocalUser braucht
    # dann seinen eigenen Schalter dafür.
    $secure = if ($password.Length -gt 0) { $password } else { $null }

    Invoke-WzTask -Name (Get-WzText 'setup.taskAccount') -ArgumentList @($name, $secure, $isAdmin, $neverExpires) -ScriptBlock {
        param($accountName, $secret, $admin, $never)
        New-WzLocalAccount -Name $accountName -Password $secret -IsAdmin:$admin -PasswordNeverExpires:$never
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            # Das Kennwort steht bewusst nirgends — weder im Protokoll noch im
            # Übergabeblatt. Der Techniker sagt es dem Kunden.
            Add-WzAction -Area 'Einrichtung' -Summary (Get-WzText 'setup.actionAccount' @{ name = $name })
            $syncHash.SetupAccountName.Text = ''
            $syncHash.SetupAccountPassword.Clear()
            $syncHash.SetupAccountRepeat.Clear()
        }
        Show-WzInfo -Title (Get-WzText 'setup.accountDialogTitle') -Message $result.Summary
        Update-WzSetupPage
    }.GetNewClosure()
}

function Test-WzSecureStringsEqual {
    <#
    .SYNOPSIS
        Vergleicht zwei Kennworteingaben, ohne sie länger als nötig im
        Klartext zu halten.
    .NOTES
        Der Klartext liegt in unverwaltetem Speicher und wird in jedem Fall
        wieder freigegeben — auch wenn der Vergleich mittendrin scheitert.
    #>
    param([securestring]$First, [securestring]$Second)

    if ($null -eq $First -or $null -eq $Second) { return $false }
    if ($First.Length -ne $Second.Length) { return $false }
    if ($First.Length -eq 0) { return $true }

    $firstPointer = [IntPtr]::Zero
    $secondPointer = [IntPtr]::Zero
    try {
        $firstPointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($First)
        $secondPointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Second)
        return ([Runtime.InteropServices.Marshal]::PtrToStringUni($firstPointer) -ceq
                [Runtime.InteropServices.Marshal]::PtrToStringUni($secondPointer))
    } finally {
        if ($firstPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($firstPointer) }
        if ($secondPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($secondPointer) }
    }
}

# --- Aktivierung -----------------------------------------------------------

function Copy-WzFirmwareKey {
    $state = $syncHash.SetupState
    if (-not $state -or -not $state.OemKey) { return }
    $syncHash.SetupKeyBox.Text = $state.OemKey
    Write-WzLog (Get-WzText 'setup.logKeyFromFirmware') -Level Info
}

function Start-WzKeyInstall {
    $key = $syncHash.SetupKeyBox.Text.Trim()

    if (-not (Test-WzProductKeyFormat -Key $key)) {
        Show-WzInfo -Title (Get-WzText 'setup.keyDialogTitle') -Message (Get-WzText 'setup.keyBadFormat')
        return
    }

    $answer = Show-WzConfirm -Title (Get-WzText 'setup.keyDialogTitle') `
        -Message (Get-WzText 'setup.keyDialogMessage') `
        -Items @((Get-WzText 'setup.keyDialogItem1'), (Get-WzText 'setup.keyDialogItem2')) `
        -ConfirmText (Get-WzText 'setup.btnKey') -Danger
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'setup.taskKey') -ArgumentList @($key) -ScriptBlock {
        param($productKey)
        Install-WzProductKey -Key $productKey
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Einrichtung' -Summary $result.Summary
        }
        Show-WzInfo -Title (Get-WzText 'setup.keyDialogTitle') -Message $result.Summary
        Update-WzSetupPage
    }
}

# --- Drucker ---------------------------------------------------------------

function Start-WzPrinterAdd {
    $name = $syncHash.SetupPrinterName.Text.Trim()
    $address = $syncHash.SetupPrinterAddress.Text.Trim()
    $selected = $syncHash.SetupPrinterDriver.SelectedItem
    if (-not $selected) { return }
    $driver = $selected.Tag

    $answer = Show-WzConfirm -Title (Get-WzText 'setup.printerDialogTitle') `
        -Message (Get-WzText 'setup.printerDialogMessage' @{ name = $name; adresse = $address }) `
        -Items @((Get-WzText 'setup.printerDialogItem' @{ treiber = $driver })) `
        -ConfirmText (Get-WzText 'setup.btnPrinter')
    if (-not $answer.Confirmed) { return }

    Invoke-WzTask -Name (Get-WzText 'setup.taskPrinter') -ArgumentList @($name, $address, $driver) -ScriptBlock {
        param($printerName, $printerAddress, $driverName)
        Add-WzIpPrinter -Name $printerName -Address $printerAddress -DriverName $driverName
    } -OnComplete {
        param($result)
        if (-not $result) { return }
        if ($result.Success) {
            Add-WzAction -Area 'Einrichtung' -Summary (Get-WzText 'setup.actionPrinter' @{ name = $name })
            $syncHash.SetupPrinterName.Text = ''
            $syncHash.SetupPrinterAddress.Text = ''
        }
        Show-WzInfo -Title (Get-WzText 'setup.printerDialogTitle') -Message $result.Summary
    }.GetNewClosure()
}
