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

Write-Host ''
Write-Host '  WinZii' -ForegroundColor Cyan -NoNewline
Write-Host ' — portables Windows-Werkzeug' -ForegroundColor DarkGray
Write-Host '  // code: ' -ForegroundColor DarkGray -NoNewline
Write-Host 'haZii.org' -ForegroundColor Cyan
Write-Host ''

# --- Vorbedingungen -------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Boot "PowerShell 5.1 oder neuer wird benötigt (gefunden: $($PSVersionTable.PSVersion))." 'Red'
    Start-Sleep -Seconds 10
    exit 1
}

if (-not (Test-Path $mainScript)) {
    Write-Boot 'main.ps1 nicht gefunden. Ist der Stick vollständig kopiert?' 'Red'
    Start-Sleep -Seconds 10
    exit 1
}

# Ausführungsrichtlinie per Gruppenrichtlinie erzwungen? Dann greift -Bypass nicht.
try {
    $machinePolicy = Get-ExecutionPolicy -Scope MachinePolicy
    $userPolicy = Get-ExecutionPolicy -Scope UserPolicy
    if ($machinePolicy -notin @('Undefined', 'Bypass', 'Unrestricted') -or
        $userPolicy -notin @('Undefined', 'Bypass', 'Unrestricted')) {
        Write-Boot "Hinweis: Die Ausführungsrichtlinie ist per Gruppenrichtlinie gesetzt ($machinePolicy/$userPolicy)." 'Yellow'
        Write-Boot 'Falls WinZii nicht startet, muss die Richtlinie vorübergehend gelockert werden.' 'Yellow'
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
        Write-Boot "Entferne Windows-Downloadsperre von $($blocked.Count) Datei(en)..." 'DarkGray'
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
    Write-Boot 'Fordere Administratorrechte an...' 'DarkGray'
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
        Write-Boot 'Die Rechteanforderung wurde abgebrochen. WinZii benötigt Administratorrechte.' 'Red'
        Start-Sleep -Seconds 8
        exit 1
    }
}

# --- STA sicherstellen (Pflicht für WPF) ----------------------------------
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Boot 'Starte im STA-Modus neu...' 'DarkGray'
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
