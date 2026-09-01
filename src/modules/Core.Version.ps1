# Core.Version — sieht nach, ob es eine neuere Fassung von WinZii gibt.
#
# Der Stick liegt zwischen zwei Einsätzen Wochen in der Tasche. Ohne diesen
# Blick läuft beim Kunden eine Fassung, deren Fehler längst behoben sind — und
# niemand merkt es, weil WinZii nie etwas sagt.
#
# **Erst wird gefragt.** WinZii läuft auf fremden Rechnern. Eine Verbindung
# nach draußen, die der Techniker nicht angeordnet hat, gehört dort nicht hin,
# auch wenn sie harmlos ist. Die Frage kommt genau einmal, die Antwort wird
# gemerkt, und ohne Antwort passiert nichts.

function Get-WzLatestVersion {
    <#
    .SYNOPSIS
        Fragt die neueste veröffentlichte Fassung bei GitHub ab.
    .DESCRIPTION
        Ein einziger Aufruf mit kurzem Zeitlimit. Schlägt er fehl — kein Netz,
        Proxy, GitHub nicht erreichbar —, ist das kein Fehler, sondern der
        Normalfall auf einem Kundengerät ohne Internet. Dann bleibt es still.
    .OUTPUTS
        Objekt mit Ok, Version, Url.
    #>
    [CmdletBinding()]
    param([int]$TimeoutSeconds = 6)

    $result = [pscustomobject]@{ Ok = $false; Version = ''; Url = '' }
    try {
        # PowerShell 5.1 spricht ohne diese Zeile noch TLS 1.0, und GitHub
        # lehnt das ab. Der Fehler sähe aus wie »Verbindung geschlossen«.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $anfrage = [Net.HttpWebRequest]::Create('https://api.github.com/repos/haZiinstinct/WinZii/releases/latest')
        $anfrage.Method = 'GET'
        $anfrage.Timeout = $TimeoutSeconds * 1000
        $anfrage.ReadWriteTimeout = $TimeoutSeconds * 1000
        # GitHub verlangt eine Kennung und weist Anfragen ohne sie ab
        $anfrage.UserAgent = "WinZii/$($syncHash.Version)"
        $anfrage.Accept = 'application/vnd.github+json'

        $antwort = $anfrage.GetResponse()
        try {
            $leser = New-Object IO.StreamReader($antwort.GetResponseStream())
            $roh = $leser.ReadToEnd()
            $leser.Close()
        } finally {
            $antwort.Close()
        }

        $daten = $roh | ConvertFrom-Json
        $result.Version = ([string]$daten.tag_name).TrimStart('v', 'V')
        $result.Url = [string]$daten.html_url
        $result.Ok = [bool]$result.Version
    } catch {
        # Ohne Netz ist Stille die richtige Antwort
    }
    return $result
}

function Test-WzVersionNewer {
    <#
    .SYNOPSIS
        Ist $Candidate neuer als $Current?
    .NOTES
        Über [version] statt über einen Textvergleich: »0.10.0« ist neuer als
        »0.9.0«, als Zeichenkette aber kleiner.
    #>
    param([string]$Current, [string]$Candidate)

    if (-not $Current -or -not $Candidate) { return $false }
    try {
        return ([version]$Candidate -gt [version]$Current)
    } catch {
        return $false
    }
}

function Start-WzVersionCheck {
    <#
    .SYNOPSIS
        Fragt einmalig um Erlaubnis und sieht danach bei jedem Start nach.
    .DESCRIPTION
        Läuft verzögert und im Hintergrund: Beim Start ist die Oberfläche mit
        der Bestandsaufnahme beschäftigt, und Invoke-WzTask weist jeden
        weiteren Auftrag ab, solange einer läuft. Der Zeitgeber wartet
        deshalb, bis der erste Durchgang fertig ist.
    #>
    [CmdletBinding()]
    param()

    if (-not $syncHash.Window) { return }

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(3)
    $timer.Add_Tick({
        if ($syncHash.Busy) { return }
        $timer.Stop()

        $erlaubt = Get-WzSetting -Name 'versionshinweis'
        if ($null -eq $erlaubt -or '' -eq "$erlaubt") {
            # Die Frage kommt genau einmal. Wer ablehnt, wird nie wieder gefragt.
            $antwort = Show-WzConfirm -Title (Get-WzText 'start.checkTitle') `
                -Message (Get-WzText 'start.checkMessage') `
                -Items @((Get-WzText 'start.checkDetail')) `
                -ConfirmText (Get-WzText 'start.checkYes')
            $erlaubt = [bool]$antwort.Confirmed
            Save-WzSetting -Name 'versionshinweis' -Value $erlaubt
            if (-not $erlaubt) {
                Write-WzLog (Get-WzText 'start.checkDeclined') -Level Info
                return
            }
        }
        if (-not [bool]$erlaubt) { return }

        Invoke-WzTask -Name (Get-WzText 'start.checkTask') -Silent -ScriptBlock {
            Get-WzLatestVersion
        } -OnComplete {
            param($neueste)
            if (-not $neueste -or -not $neueste.Ok) { return }
            if (Test-WzVersionNewer -Current $syncHash.Version -Candidate $neueste.Version) {
                Write-WzLog (Get-WzText 'start.checkNewer' @{
                    version = $neueste.Version; hier = $syncHash.Version }) -Level Warn
                Write-WzLog (Get-WzText 'start.checkWhere' @{ adresse = $neueste.Url }) -Level Info
            } else {
                Write-WzLog (Get-WzText 'start.checkCurrent') -Level Ok
            }
        }
    }.GetNewClosure())
    $timer.Start()
}
