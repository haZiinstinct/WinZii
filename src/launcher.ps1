# WinZii Launcher — Elevation, Freigabe heruntergeladener Dateien, STA-Start.
[CmdletBinding()]
param(
    [switch]$DryRun,
    # Wird unverändert an main.ps1 durchgereicht (siehe dort)
    [string]$Language,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $PSScriptRoot 'main.ps1'

function Write-Boot {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host "  $Message" -ForegroundColor $Color
}

# Der Launcher laeuft, bevor irgendein Modul geladen ist — Get-WzText steht
# hier noch nicht zur Verfuegung. Deshalb eine eigene, kleine Auswahl: dieselbe
# Reihenfolge wie spaeter in Initialize-WzLanguage (Startparameter, gemerkte
# Wahl, Systemsprache), nur ohne Rueckfallkette ueber mehrere Dateien. Faellt
# irgendetwas davon aus, bleibt es bei Deutsch.
$script:BootTexts = @{}
try {
    $wanted = if ($Language) { $Language } elseif ($env:WZ_SELFTEST_LANG) { $env:WZ_SELFTEST_LANG } else { $null }
    if (-not $wanted) {
        $settingsFile = Join-Path $root 'einstellungen.json'
        if (Test-Path -LiteralPath $settingsFile) {
            $wanted = (Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json).sprache
        }
    }
    if (-not $wanted) {
        $map = @{ 0x07 = 'de'; 0x09 = 'en'; 0x0A = 'es'; 0x0C = 'fr'; 0x16 = 'pt'
                  0x19 = 'ru'; 0x04 = 'zh'; 0x11 = 'ja'; 0x01 = 'ar' }
        $primary = [int](Get-UICulture).LCID -band 0x3FF
        if ($map.ContainsKey($primary)) { $wanted = $map[$primary] }
    }
    if (-not $wanted) { $wanted = 'de' }
    $langFile = Join-Path $root "data\lang\$wanted.json"
    if (-not (Test-Path -LiteralPath $langFile)) { $langFile = Join-Path $root 'data\lang\de.json' }
    $table = Get-Content -LiteralPath $langFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $table.boot.PSObject.Properties) { $script:BootTexts[$property.Name] = $property.Value }
} catch { }

function Get-BootText {
    param([string]$Key, [hashtable]$Values)
    $text = if ($script:BootTexts.ContainsKey($Key)) { $script:BootTexts[$Key] } else { $Key }
    if ($Values) {
        foreach ($name in $Values.Keys) { $text = $text.Replace("{$name}", [string]$Values[$name]) }
    }
    return $text
}

Write-Host ''
Write-Host '  WinZii' -ForegroundColor Cyan -NoNewline
Write-Host " — $(Get-BootText 'tagline')" -ForegroundColor DarkGray
Write-Host '  // code: ' -ForegroundColor DarkGray -NoNewline
Write-Host 'haZii.org' -ForegroundColor Cyan
Write-Host ''

# --- Vorbedingungen -------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Boot (Get-BootText 'needPowerShell' @{ version = $PSVersionTable.PSVersion }) 'Red'
    Start-Sleep -Seconds 10
    exit 1
}

if (-not (Test-Path $mainScript)) {
    Write-Boot (Get-BootText 'mainMissing') 'Red'
    Start-Sleep -Seconds 10
    exit 1
}

# Ausführungsrichtlinie per Gruppenrichtlinie erzwungen? Dann greift -Bypass nicht.
try {
    $machinePolicy = Get-ExecutionPolicy -Scope MachinePolicy
    $userPolicy = Get-ExecutionPolicy -Scope UserPolicy
    if ($machinePolicy -notin @('Undefined', 'Bypass', 'Unrestricted') -or
        $userPolicy -notin @('Undefined', 'Bypass', 'Unrestricted')) {
        Write-Boot (Get-BootText 'policyNotice' @{ maschine = $machinePolicy; benutzer = $userPolicy }) 'Yellow'
        Write-Boot (Get-BootText 'policyHint') 'Yellow'
    }
} catch {
    # Richtlinienabfrage ist optional
}

# --- Downloadsperre entfernen (nur beim ersten Start relevant) -------------
# Auf FAT32- und exFAT-Sticks gibt es keine Zone-Markierung, dann passiert nichts.
try {
    $blocked = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.xaml', '*.json', '*.bat', '*.html' -ErrorAction SilentlyContinue |
        Where-Object { Get-Item $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue }
    if ($blocked) {
        Write-Boot (Get-BootText 'unblocking' @{ anzahl = $blocked.Count }) 'DarkGray'
        $blocked | Unblock-File -ErrorAction SilentlyContinue
    }
} catch {
    # Alternative Datenströme nicht verfügbar
}

# --- Administratorrechte --------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevate) {
    Write-Boot (Get-BootText 'elevating') 'DarkGray'
    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-STA'
        '-File', ('"{0}"' -f $mainScript)
    )
    if ($DryRun) { $argList += '-DryRun' }
    if ($Language) { $argList += @('-Language', $Language) }

    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -ErrorAction Stop
        exit 0
    } catch {
        Write-Boot (Get-BootText 'elevationDenied') 'Red'
        Start-Sleep -Seconds 8
        exit 1
    }
}

# --- STA sicherstellen (Pflicht für WPF) ----------------------------------
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Boot (Get-BootText 'restartSta') 'DarkGray'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $mainScript))
    if ($DryRun) { $argList += '-DryRun' }
    if ($Language) { $argList += @('-Language', $Language) }
    & (Get-Process -Id $PID).Path $argList
    exit $LASTEXITCODE
}

# --- Start ----------------------------------------------------------------
# Punktweise laden, nicht mit "&" aufrufen: Der Aufrufoperator legt einen
# eigenen Bereich an, und die Funktionen aus src\modules landen dann in einem
# Bereich, den die Ereignisbehandlungen von WPF nicht mehr sehen. Beim Tick des
# Zeitgebers scheiterte dann jeder Aufruf mit "wurde nicht als Name eines
# Cmdlet ... erkannt". Auffällig wurde das nie, weil der übliche Weg über die
# Rechteanforderung geht und dort ohnehin ein neuer Prozess mit -File startet —
# dieser Zweig greift nur, wenn WinZii bereits mit Administratorrechten läuft.
. $mainScript -DryRun:$DryRun -Language $Language
exit $LASTEXITCODE
