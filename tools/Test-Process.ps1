# Prüft Invoke-WzProcess: Rückgabewerte, Ausgabe, Zeitbegrenzung — und ob es
# auch in einem Hintergrund-Runspace funktioniert (dort läuft es im Betrieb).
Add-Type -AssemblyName PresentationFramework
$src = 'C:\Users\haZii\Documents\GitHub\WinZii\src'
$global:WzRootPath = Split-Path -Parent $src
$global:syncHash = [hashtable]::Synchronized(@{})
$syncHash.LogEntries = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$syncHash.Version = '0.2.0'
foreach ($m in 'Core.Paths', 'Core.Logging', 'Core.Json', 'Core.Runspace') {
    . (Join-Path $src "modules\$m.ps1")
}

$fehler = 0
function Assert-Wz {
    param([string]$Was, [bool]$Ok, [string]$Detail = '')
    $symbol = if ($Ok) { '[ok]  ' } else { '[FEHL]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-38} {2}" -f $symbol, $Was, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:fehler++ }
}

Write-Host ''
Write-Host '  Invoke-WzProcess' -ForegroundColor Cyan
Write-Host ''

$r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c exit 0'
Assert-Wz 'Erfolg liefert 0' ($r.ExitCode -eq 0) "ExitCode=$($r.ExitCode)"

$r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c exit 5'
Assert-Wz 'Fehlercode wird durchgereicht' ($r.ExitCode -eq 5) "ExitCode=$($r.ExitCode)"

$r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c echo hallo-winzii'
Assert-Wz 'Standardausgabe wird gelesen' ($r.StdOut -match 'hallo-winzii') "'$($r.StdOut.Trim())'"

$r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c echo problem 1>&2'
Assert-Wz 'Fehlerausgabe wird gelesen' ($r.StdErr -match 'problem') "'$($r.StdErr.Trim())'"

# Viel Ausgabe: der alte Weg konnte hier haengen bleiben
$r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c for /L %i in (1,1,3000) do @echo Zeile-%i'
$zeilen = @($r.StdOut -split "`r?`n" | Where-Object { $_ -match 'Zeile-' }).Count
Assert-Wz 'Viel Ausgabe ohne Haenger' ($zeilen -ge 3000 -and $r.ExitCode -eq 0) "$zeilen Zeilen"

# Zeitbegrenzung
$dauer = Measure-Command { $r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c ping -n 20 127.0.0.1 >nul' -TimeoutSeconds 2 }
Assert-Wz 'Zeitbegrenzung greift' ($r.TimedOut -and $dauer.TotalSeconds -lt 8) "$([math]::Round($dauer.TotalSeconds,1)) s, TimedOut=$($r.TimedOut)"

# Arbeitsverzeichnis
$r = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c cd' -WorkingDirectory $env:SystemRoot
Assert-Wz 'Arbeitsverzeichnis wird gesetzt' ($r.StdOut -match 'Windows') "'$($r.StdOut.Trim())'"

# Nicht vorhandenes Programm darf nicht abstuerzen
$r = Invoke-WzProcess -FilePath 'gibtesnicht-winzii.exe' -Arguments '/x'
Assert-Wz 'Fehlendes Programm faengt sauber ab' ($r.ExitCode -eq -1) "ExitCode=$($r.ExitCode)"

Write-Host ''
Write-Host '  Im Hintergrund-Runspace (so laeuft es im Betrieb)' -ForegroundColor Cyan
Write-Host ''

# Runspace-Umgebung wie Initialize-WzRunspacePool sie baut
$iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
foreach ($f in Get-ChildItem Function:\ | Where-Object { $_.Name -like '*-Wz*' }) {
    $iss.Commands.Add((New-Object Management.Automation.Runspaces.SessionStateFunctionEntry($f.Name, $f.Definition)))
}
$iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry('syncHash', $syncHash, '')))
$iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry('WzRootPath', $global:WzRootPath, '')))

$rs = [runspacefactory]::CreateRunspace($iss)
$rs.ApartmentState = 'MTA'
$rs.Open()
$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript({
    $a = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c exit 3'
    $b = Invoke-WzProcess -FilePath 'cmd.exe' -Arguments '/c echo aus-dem-runspace'
    [pscustomobject]@{ Code = $a.ExitCode; Text = $b.StdOut }
})
$res = $ps.Invoke()
$ps.Dispose(); $rs.Close(); $rs.Dispose()

Assert-Wz 'Rueckgabewert im Runspace' ($res[0].Code -eq 3) "ExitCode=$($res[0].Code)"
Assert-Wz 'Ausgabe im Runspace' ($res[0].Text -match 'aus-dem-runspace') "'$($res[0].Text.Trim())'"

Write-Host ''
if ($fehler -eq 0) {
    Write-Host '  Ergebnis: alle Pruefungen bestanden.' -ForegroundColor Green
    exit 0
}
Write-Host "  Ergebnis: $fehler Pruefung(en) fehlgeschlagen." -ForegroundColor Red
exit 1
