# NetworkDiag — »Kein Internet« der Reihe nach eingrenzen.
#
# Die Reparatur-Seite konnte bisher nur reparieren, nicht messen. Diese
# Messkette geht den Weg vom Netzwerkanschluss bis zur Webseite ab und hält an,
# sobald sie die Ursache gefunden hat — damit aus Rateversuchen eine gezielte
# Maßnahme wird.
#
# Bewusst über .NET statt über Test-NetConnection: gemessen 29 ms gegen 970 ms
# je Ping. Die ganze Kette bleibt so unter zwei Sekunden.

function Invoke-WzNetworkDiagnosis {
    <#
    .SYNOPSIS
        Prüft der Reihe nach: Adapter, IP-Adresse, Gateway, DNS, HTTPS.
    .OUTPUTS
        PSCustomObject mit Steps (je Name/Status/Detail), Verdict, Recommendation,
        FixHint (Kennung der passenden Reparatur) und Ok.
    #>
    [CmdletBinding()]
    param([int]$TimeoutMs = 2000)

    $steps = New-Object Collections.ArrayList
    $result = [pscustomobject]@{
        Steps          = @()
        Verdict        = ''
        Recommendation = ''
        FixHint        = ''
        Ok             = $false
    }

    function Add-Step {
        param([string]$Name, [string]$Status, [string]$Detail)
        [void]$steps.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
    }

    function Complete-Diagnosis {
        param([string]$Verdict, [string]$Recommendation, [string]$FixHint, [bool]$Ok)
        $result.Steps = @($steps.ToArray())
        $result.Verdict = $Verdict
        $result.Recommendation = $Recommendation
        $result.FixHint = $FixHint
        $result.Ok = $Ok
        return $result
    }

    # --- 1. Netzwerkkarte --------------------------------------------------
    $adapters = @()
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
    } catch {
        try {
            $adapters = @(Get-CimInstance -Query 'SELECT Name,NetEnabled FROM Win32_NetworkAdapter WHERE PhysicalAdapter=True AND NetEnabled=True' -ErrorAction Stop)
        } catch { }
    }

    if ($adapters.Count -eq 0) {
        Add-Step 'Netzwerkkarte' 'fail' 'keine aktive Verbindung'
        return Complete-Diagnosis `
            -Verdict 'Es ist überhaupt keine Netzwerkverbindung aktiv — weder Kabel noch WLAN.' `
            -Recommendation 'Netzwerkkabel prüfen beziehungsweise WLAN einschalten. Ist im Geräte-Manager ein Netzwerkadapter mit Fehlerzeichen zu sehen, fehlt der Treiber — dann hilft die Seite »Treiber«.' `
            -FixHint 'adapter' -Ok $false
    }
    $adapterNames = ($adapters | ForEach-Object { $_.Name }) -join ', '
    Add-Step 'Netzwerkkarte' 'ok' "$($adapters.Count) aktiv: $adapterNames"

    # --- 2. IP-Adresse -----------------------------------------------------
    $configs = @()
    try {
        $configs = @(Get-CimInstance -Query 'SELECT Description,IPAddress,DefaultIPGateway,DNSServerSearchOrder,DHCPEnabled FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True' -ErrorAction Stop)
    } catch { }

    $addresses = @()
    $gateways = @()
    $dnsServers = @()
    foreach ($config in $configs) {
        $addresses += @($config.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
        $gateways += @($config.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
        $dnsServers += @($config.DNSServerSearchOrder | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
    }
    $addresses = @($addresses | Where-Object { $_ -ne '0.0.0.0' })

    if ($addresses.Count -eq 0) {
        Add-Step 'IP-Adresse' 'fail' 'keine zugewiesen'
        return Complete-Diagnosis `
            -Verdict 'Die Netzwerkkarte ist verbunden, hat aber keine IP-Adresse bekommen.' `
            -Recommendation 'Zuerst »IP-Adresse auffrischen« versuchen. Bleibt es dabei, vergibt der Router keine Adressen (DHCP) oder es ist eine feste Adresse falsch eingetragen.' `
            -FixHint 'renew' -Ok $false
    }

    $apipa = @($addresses | Where-Object { $_ -like '169.254.*' })
    if ($apipa.Count -eq $addresses.Count) {
        Add-Step 'IP-Adresse' 'fail' "$($apipa -join ', ') — Selbstvergabe, kein DHCP"
        return Complete-Diagnosis `
            -Verdict "Der PC hat sich mit $($apipa[0]) selbst eine Adresse gegeben — er hat vom Router keine bekommen." `
            -Recommendation 'Das ist fast immer der Router oder das Kabel: »IP-Adresse auffrischen« versuchen, sonst Router neu starten. Bei WLAN prüfen, ob überhaupt das richtige Netz verbunden ist.' `
            -FixHint 'renew' -Ok $false
    }
    Add-Step 'IP-Adresse' 'ok' ($addresses -join ', ')

    # --- 3. Standardgateway ------------------------------------------------
    if ($gateways.Count -eq 0) {
        Add-Step 'Router (Gateway)' 'fail' 'nicht eingetragen'
        return Complete-Diagnosis `
            -Verdict 'Es ist kein Standardgateway eingetragen — der PC weiß nicht, wohin er Anfragen ins Internet schicken soll.' `
            -Recommendation 'Meist eine falsch gesetzte feste IP-Konfiguration. »IP-Adresse auffrischen« stellt den Bezug über DHCP wieder her.' `
            -FixHint 'renew' -Ok $false
    }

    $gateway = $gateways[0]
    $gatewayReply = $null
    try {
        $ping = New-Object Net.NetworkInformation.Ping
        $gatewayReply = $ping.Send($gateway, $TimeoutMs)
        $ping.Dispose()
    } catch { }

    if (-not $gatewayReply -or $gatewayReply.Status -ne 'Success') {
        Add-Step 'Router (Gateway)' 'fail' "$gateway antwortet nicht"
        return Complete-Diagnosis `
            -Verdict "Der Router unter $gateway antwortet nicht." `
            -Recommendation 'Router neu starten und Kabel prüfen. Bei WLAN kann auch schlechter Empfang die Ursache sein. Manche Router beantworten grundsätzlich keine Ping-Anfragen — dann trotzdem im Browser die Router-Oberfläche aufrufen.' `
            -FixHint 'reset' -Ok $false
    }
    Add-Step 'Router (Gateway)' 'ok' "$gateway antwortet in $($gatewayReply.RoundtripTime) ms"

    # --- 4. Namensauflösung ------------------------------------------------
    if ($dnsServers.Count -eq 0) {
        Add-Step 'Namensauflösung' 'warn' 'kein DNS-Server eingetragen'
    }

    $dnsOk = $false
    $dnsDetail = ''
    try {
        $answer = Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly -ErrorAction Stop
        $records = @($answer | Where-Object { $_.IPAddress })
        if ($records.Count -gt 0) {
            $dnsOk = $true
            $dnsDetail = "über $($dnsServers -join ', ') aufgelöst"
        }
    } catch {
        $dnsDetail = $_.Exception.Message.Split([char]10)[0]
    }

    if (-not $dnsOk) {
        Add-Step 'Namensauflösung' 'fail' $dnsDetail
        return Complete-Diagnosis `
            -Verdict 'Der Router antwortet, aber Internetadressen lassen sich nicht in IP-Adressen übersetzen — das ist ein reines DNS-Problem.' `
            -Recommendation 'Unten auf »Cloudflare« oder »Quad9« umstellen. Das behebt es fast immer und ist jederzeit auf »zurück auf Router« umkehrbar.' `
            -FixHint 'dns' -Ok $false
    }
    Add-Step 'Namensauflösung' 'ok' $dnsDetail

    # --- 5. Tatsächlicher Internetzugang -----------------------------------
    $web = Test-WzInternetAccess -TimeoutMs ($TimeoutMs * 2)
    Add-Step 'Internetzugang' $web.Status $web.Detail

    switch ($web.Kind) {
        'ok' {
            return Complete-Diagnosis `
                -Verdict 'Das Netzwerk ist in Ordnung — Router, Namensauflösung und Internetzugang antworten alle.' `
                -Recommendation 'Klagt der Kunde trotzdem über »kein Internet«, liegt es an einem einzelnen Programm: Virenscanner mit eigener Firewall, VPN-Software oder ein Proxy im Browser.' `
                -FixHint '' -Ok $true
        }
        'portal' {
            return Complete-Diagnosis `
                -Verdict 'Es hängt ein Anmeldeportal dazwischen — typisch für Hotel-, Gäste- oder Firmen-WLAN.' `
                -Recommendation 'Im Browser eine beliebige Seite aufrufen; die Anmeldeseite erscheint dann von selbst.' `
                -FixHint '' -Ok $false
        }
        'certificate' {
            $timeNote = Test-WzSystemTime
            return Complete-Diagnosis `
                -Verdict "Die Verbindung steht, aber das Sicherheitszertifikat wird abgelehnt. $timeNote" `
                -Recommendation 'Zwei übliche Ursachen: Die Systemuhr geht falsch (dann stimmt kein Zertifikat mehr), oder ein mitlesender Virenscanner beziehungsweise Firmen-Proxy schaltet sich dazwischen. Ein Netzwerk-Reset hilft hier nicht.' `
                -FixHint 'time' -Ok $false
        }
        default {
            return Complete-Diagnosis `
                -Verdict 'Router und Namensauflösung arbeiten, aber es kommt keine Verbindung nach draußen zustande.' `
                -Recommendation 'Meist blockiert eine Firewall oder ein Virenscanner. Ist am Router eine Kindersicherung oder Zeitbegrenzung eingerichtet, greift die ebenfalls hier.' `
                -FixHint 'reset' -Ok $false
        }
    }
}

function Test-WzInternetAccess {
    <#
    .SYNOPSIS
        Ruft die Prüfseite von Microsoft ab und unterscheidet die Fälle:
        erreichbar, Anmeldeportal, Zertifikatsproblem, blockiert.
    #>
    param([int]$TimeoutMs = 4000)

    $result = [pscustomobject]@{ Kind = 'blocked'; Status = 'fail'; Detail = '' }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $request = [Net.HttpWebRequest]::Create('https://www.msftconnecttest.com/connecttest.txt')
        $request.Timeout = $TimeoutMs
        $request.UserAgent = 'WinZii'
        $request.AllowAutoRedirect = $false

        $response = $request.GetResponse()
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        $body = $reader.ReadToEnd()
        $status = [int]$response.StatusCode
        $reader.Close()
        $response.Close()

        if ($status -ge 300 -and $status -lt 400) {
            $result.Kind = 'portal'
            $result.Status = 'warn'
            $result.Detail = "Umleitung auf eine Anmeldeseite (HTTP $status)"
        } elseif ($body.Trim() -eq 'Microsoft Connect Test') {
            $result.Kind = 'ok'
            $result.Status = 'ok'
            $result.Detail = 'Prüfseite korrekt abgerufen'
        } else {
            $result.Kind = 'portal'
            $result.Status = 'warn'
            $result.Detail = 'unerwartete Antwort — vermutlich ein Anmeldeportal'
        }
    } catch [Net.WebException] {
        $message = $_.Exception.Message
        if ($message -match 'SSL|TLS|Vertrauensstellung|Zertifikat|trust') {
            $result.Kind = 'certificate'
            $result.Status = 'fail'
            $result.Detail = 'Sicherheitszertifikat abgelehnt'
        } elseif ($_.Exception.Status -eq 'Timeout') {
            $result.Kind = 'blocked'
            $result.Status = 'fail'
            $result.Detail = 'Zeitüberschreitung'
        } else {
            $result.Kind = 'blocked'
            $result.Status = 'fail'
            $result.Detail = $message.Split([char]10)[0]
        }
    } catch {
        $result.Detail = $_.Exception.Message.Split([char]10)[0]
    }

    return $result
}

function Test-WzSystemTime {
    <#
    .SYNOPSIS
        Grobe Plausibilitätsprüfung der Systemuhr. Eine falsch gestellte Uhr
        ist die häufigste Ursache für abgelehnte Zertifikate.
    #>
    $now = Get-Date
    try {
        $build = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        if ($build.InstallDate) {
            $installed = [DateTimeOffset]::FromUnixTimeSeconds([int64]$build.InstallDate).LocalDateTime
            if ($now -lt $installed) {
                return "Achtung: Die Systemuhr steht auf $($now.ToString('dd.MM.yyyy')) und damit vor dem Installationsdatum von Windows — sie geht falsch."
            }
        }
    } catch { }

    if ($now.Year -lt 2024 -or $now.Year -gt 2100) {
        return "Achtung: Die Systemuhr steht auf $($now.ToString('dd.MM.yyyy')) und ist damit offensichtlich falsch."
    }
    return "Die Systemuhr steht auf $($now.ToString('dd.MM.yyyy HH:mm')) und wirkt plausibel."
}

function Start-WzDefenderScan {
    <#
    .SYNOPSIS
        Schnellprüfung des Windows-Virenschutzes.
    .OUTPUTS
        PSCustomObject mit Success, Summary, Threats
    #>
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ Success = $false; Summary = ''; Threats = @() }

    if ($syncHash.DryRun) {
        $result.Success = $true
        $result.Summary = 'Testmodus — es wurde nicht geprüft.'
        Write-WzLog '[Test] Virenschnellprüfung würde gestartet' -Level Test
        return $result
    }

    try {
        Write-WzLog 'Virenschnellprüfung läuft — das dauert einige Minuten...' -Level Action
        Start-MpScan -ScanType QuickScan -ErrorAction Stop

        $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddMinutes(-30) })

        $result.Success = $true
        if ($threats.Count -eq 0) {
            $result.Summary = 'Die Schnellprüfung hat nichts gefunden.'
            Write-WzLog $result.Summary -Level Ok
        } else {
            $names = @($threats | ForEach-Object {
                (Get-MpThreat -ThreatID $_.ThreatID -ErrorAction SilentlyContinue).ThreatName
            } | Where-Object { $_ } | Select-Object -Unique)
            $result.Threats = $names
            $result.Summary = "$($threats.Count) Fund(e). Der Defender hat sie in Quarantäne verschoben."
            Write-WzLog $result.Summary -Level Warn
        }
    } catch {
        $result.Summary = "Die Prüfung ließ sich nicht starten: $($_.Exception.Message.Split([char]10)[0])"
        Write-WzLog $result.Summary -Level Error
    }

    return $result
}
