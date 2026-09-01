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
        Add-Step (Get-WzText 'tool.stepAdapter') 'fail' (Get-WzText 'tool.detailNoConnection')
        return Complete-Diagnosis `
            -Verdict (Get-WzText 'tool.verdictNoAdapter') `
            -Recommendation (Get-WzText 'tool.recNoAdapter') `
            -FixHint 'adapter' -Ok $false
    }
    $adapterNames = ($adapters | ForEach-Object { $_.Name }) -join ', '
    Add-Step (Get-WzText 'tool.stepAdapter') 'ok' (Get-WzText 'tool.detailAdaptersActive' @{ anzahl = $adapters.Count; namen = $adapterNames })

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
        Add-Step (Get-WzText 'tool.stepIp') 'fail' (Get-WzText 'tool.detailNoIp')
        return Complete-Diagnosis `
            -Verdict (Get-WzText 'tool.verdictNoIp') `
            -Recommendation (Get-WzText 'tool.recNoIp') `
            -FixHint 'renew' -Ok $false
    }

    $apipa = @($addresses | Where-Object { $_ -like '169.254.*' })
    if ($apipa.Count -eq $addresses.Count) {
        Add-Step (Get-WzText 'tool.stepIp') 'fail' (Get-WzText 'tool.detailApipa' @{ adressen = ($apipa -join ', ') })
        return Complete-Diagnosis `
            -Verdict (Get-WzText 'tool.verdictApipa' @{ adresse = $apipa[0] }) `
            -Recommendation (Get-WzText 'tool.recApipa') `
            -FixHint 'renew' -Ok $false
    }
    Add-Step (Get-WzText 'tool.stepIp') 'ok' ($addresses -join ', ')

    # --- 3. Standardgateway ------------------------------------------------
    if ($gateways.Count -eq 0) {
        Add-Step (Get-WzText 'tool.stepGateway') 'fail' (Get-WzText 'tool.detailNoGateway')
        return Complete-Diagnosis `
            -Verdict (Get-WzText 'tool.verdictNoGateway') `
            -Recommendation (Get-WzText 'tool.recNoGateway') `
            -FixHint 'renew' -Ok $false
    }

    $gateway = $gateways[0]
    $gatewayReply = $null
    try {
        $ping = New-Object Net.NetworkInformation.Ping
        $gatewayReply = $ping.Send($gateway, $TimeoutMs)
        $ping.Dispose()
    } catch { }

    # Ein verweigerter Ping beendet die Kette nicht mehr: Manche Router und
    # praktisch jedes Firmen- oder VM-Gateway blocken Ping grundsätzlich. Im
    # Sandbox-Test meldete die Kette deshalb »Es hängt beim Router«, während
    # nebenan Downloads liefen. Ob wirklich etwas klemmt, entscheiden erst
    # Namensauflösung und Internetzugang.
    $gatewayAnswered = ($gatewayReply -and $gatewayReply.Status -eq 'Success')
    if ($gatewayAnswered) {
        Add-Step (Get-WzText 'tool.stepGateway') 'ok' (Get-WzText 'tool.detailGatewayOk' @{ adresse = $gateway; ms = $gatewayReply.RoundtripTime })
    } else {
        Add-Step (Get-WzText 'tool.stepGateway') 'warn' (Get-WzText 'tool.detailGatewayNoPing' @{ adresse = $gateway })
    }

    # --- 4. Namensauflösung ------------------------------------------------
    if ($dnsServers.Count -eq 0) {
        Add-Step (Get-WzText 'tool.stepDns') 'warn' (Get-WzText 'tool.detailNoDnsServer')
    }

    $dnsOk = $false
    $dnsDetail = ''
    try {
        $answer = Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly -ErrorAction Stop
        $records = @($answer | Where-Object { $_.IPAddress })
        if ($records.Count -gt 0) {
            $dnsOk = $true
            $dnsDetail = Get-WzText 'tool.detailDnsResolved' @{ server = ($dnsServers -join ', ') }
        }
    } catch {
        $dnsDetail = $_.Exception.Message.Split([char]10)[0]
    }

    if (-not $dnsOk) {
        Add-Step (Get-WzText 'tool.stepDns') 'fail' $dnsDetail
        if (-not $gatewayAnswered) {
            # Router stumm UND keine Namensauflösung: jetzt ist der Router der
            # wahrscheinlichste Schuldige.
            return Complete-Diagnosis `
                -Verdict (Get-WzText 'tool.verdictRouterAndDns' @{ adresse = $gateway }) `
                -Recommendation (Get-WzText 'tool.recRouterAndDns') `
                -FixHint 'reset' -Ok $false
        }
        return Complete-Diagnosis `
            -Verdict (Get-WzText 'tool.verdictDnsOnly') `
            -Recommendation (Get-WzText 'tool.recDnsOnly') `
            -FixHint 'dns' -Ok $false
    }
    Add-Step (Get-WzText 'tool.stepDns') 'ok' $dnsDetail

    # --- 5. Tatsächlicher Internetzugang -----------------------------------
    $web = Test-WzInternetAccess -TimeoutMs ($TimeoutMs * 2)
    Add-Step (Get-WzText 'tool.stepInternet') $web.Status $web.Detail

    switch ($web.Kind) {
        'ok' {
            $verdict = Get-WzText 'tool.verdictOk'
            if ($gatewayAnswered) {
                $verdict = Get-WzText 'tool.verdictOkAll'
            } else {
                $verdict += Get-WzText 'tool.verdictOkNoPing' @{ adresse = $gateway }
            }
            return Complete-Diagnosis `
                -Verdict $verdict `
                -Recommendation (Get-WzText 'tool.recOk') `
                -FixHint '' -Ok $true
        }
        'portal' {
            return Complete-Diagnosis `
                -Verdict (Get-WzText 'tool.verdictPortal') `
                -Recommendation (Get-WzText 'tool.recPortal') `
                -FixHint '' -Ok $false
        }
        'certificate' {
            $timeNote = Test-WzSystemTime
            return Complete-Diagnosis `
                -Verdict (Get-WzText 'tool.verdictCertificate' @{ zeithinweis = $timeNote }) `
                -Recommendation (Get-WzText 'tool.recCertificate') `
                -FixHint 'time' -Ok $false
        }
        default {
            return Complete-Diagnosis `
                -Verdict (Get-WzText 'tool.verdictNoInternet') `
                -Recommendation (Get-WzText 'tool.recNoInternet') `
                -FixHint 'reset' -Ok $false
        }
    }
}

function Test-WzInternetAccess {
    <#
    .SYNOPSIS
        Ruft die Prüfseite von Microsoft ab und unterscheidet die Fälle:
        erreichbar, Anmeldeportal, Zertifikatsproblem, blockiert.
    .DESCRIPTION
        Zwei Schritte, weil zwei verschiedene Dinge geprüft werden müssen:

        1. Die Prüfseite von Windows über KLARTEXT-HTTP. Genau dafür ist sie
           gedacht — nur unverschlüsselt kann ein Anmeldeportal überhaupt
           dazwischenfunken und sich zeigen.
        2. Eine echte HTTPS-Adresse, weil jeder Download über HTTPS läuft.

        Bis hierher lief Schritt 1 über HTTPS. Die Prüfseite beantwortet das
        aber nicht verlässlich, und der Sandbox-Lauf hat gezeigt, wohin das
        führt: »Sicherheitszertifikat abgelehnt«, obwohl unmittelbar danach
        7 MB von Microsoft geladen wurden. Seit Etappe A hängt an dieser
        Auskunft jede Installation — ein Fehlalarm blockiert also alles.
    .OUTPUTS
        PSCustomObject mit Kind (ok|portal|certificate|blocked), Status, Detail
    #>
    param([int]$TimeoutMs = 4000)

    $result = [pscustomobject]@{ Kind = 'blocked'; Status = 'fail'; Detail = '' }

    # Verodern statt Zuweisen: Eine Zuweisung würde ein bereits ausgehandeltes
    # TLS 1.3 prozessweit wieder abschalten — auch für alle Downloads danach.
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $abrufen = {
        param([string]$Url, [bool]$Redirects)
        $request = [Net.HttpWebRequest]::Create($Url)
        $request.Timeout = $TimeoutMs
        $request.UserAgent = 'WinZii'
        $request.AllowAutoRedirect = $Redirects
        $response = $request.GetResponse()
        try {
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            try { $body = $reader.ReadToEnd() } finally { $reader.Close() }
            [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $body }
        } finally { $response.Close() }
    }

    # --- Schritt 1: Anmeldeportal? -----------------------------------------
    try {
        $probe = & $abrufen 'http://www.msftconnecttest.com/connecttest.txt' $false
        if ($probe.Status -ge 300 -and $probe.Status -lt 400) {
            $result.Kind = 'portal'
            $result.Status = 'warn'
            $result.Detail = Get-WzText 'tool.detailRedirect' @{ status = $probe.Status }
            return $result
        }
        if ($probe.Body.Trim() -ne 'Microsoft Connect Test') {
            $result.Kind = 'portal'
            $result.Status = 'warn'
            $result.Detail = Get-WzText 'tool.detailPortal'
            return $result
        }
    } catch [Net.WebException] {
        # Ein Fehlschlag hier ist noch kein Urteil: Manche Netze sperren gezielt
        # die Prüfseite von Microsoft, während sonst alles erreichbar ist.
        # Entschieden wird deshalb in Schritt 2.
        $result.Detail = $_.Exception.Message.Split([char]10)[0]
    } catch {
        $result.Detail = $_.Exception.Message.Split([char]10)[0]
    }

    # --- Schritt 2: läuft HTTPS? -------------------------------------------
    try {
        [void](& $abrufen 'https://aka.ms/' $true)
        $result.Kind = 'ok'
        $result.Status = 'ok'
        $result.Detail = Get-WzText 'tool.detailProbeOk'
    } catch [Net.WebException] {
        $message = $_.Exception.Message
        if ($_.Exception.Status -eq 'ProtocolError') {
            # Es kam eine HTTP-Antwort zurück — 404 oder 403 spielt keine Rolle,
            # die verschlüsselte Verbindung stand. Genau darauf kommt es an.
            $result.Kind = 'ok'
            $result.Status = 'ok'
            $result.Detail = Get-WzText 'tool.detailHttpsOk'
        } elseif ($message -match 'SSL|TLS|Vertrauensstellung|Zertifikat|trust') {
            $result.Kind = 'certificate'
            $result.Status = 'fail'
            $result.Detail = Get-WzText 'tool.detailCertRejected'
        } elseif ($_.Exception.Status -eq 'Timeout') {
            $result.Kind = 'blocked'
            $result.Status = 'fail'
            $result.Detail = Get-WzText 'tool.detailTimeout'
        } else {
            $result.Kind = 'blocked'
            $result.Status = 'fail'
            $result.Detail = $message.Split([char]10)[0]
        }
    } catch {
        $result.Kind = 'blocked'
        $result.Status = 'fail'
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
                return Get-WzText 'tool.clockBeforeInstall' @{ datum = $now.ToString('d', (Get-WzLanguageCulture)) }
            }
        }
    } catch { }

    if ($now.Year -lt 2024 -or $now.Year -gt 2100) {
        return Get-WzText 'tool.clockWrong' @{ datum = $now.ToString('d', (Get-WzLanguageCulture)) }
    }
    return Get-WzText 'tool.clockPlausible' @{ datum = $now.ToString('g', (Get-WzLanguageCulture)) }
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
        $result.Summary = Get-WzText 'tool.scanDryRun'
        Write-WzLog (Get-WzText 'tool.logScanTest') -Level Test
        return $result
    }

    try {
        Write-WzLog (Get-WzText 'tool.logScanRunning') -Level Action
        Start-MpScan -ScanType QuickScan -ErrorAction Stop

        $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddMinutes(-30) })

        $result.Success = $true
        if ($threats.Count -eq 0) {
            $result.Summary = Get-WzText 'tool.scanClean'
            Write-WzLog $result.Summary -Level Ok
        } else {
            $names = @($threats | ForEach-Object {
                (Get-MpThreat -ThreatID $_.ThreatID -ErrorAction SilentlyContinue).ThreatName
            } | Where-Object { $_ } | Select-Object -Unique)
            $result.Threats = $names
            $result.Summary = Get-WzText 'tool.scanFound' @{ anzahl = $threats.Count }
            Write-WzLog $result.Summary -Level Warn
        }
    } catch {
        $result.Summary = Get-WzText 'tool.scanFailed' @{ grund = $_.Exception.Message.Split([char]10)[0] }
        Write-WzLog $result.Summary -Level Error
    }

    return $result
}
