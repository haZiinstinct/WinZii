# Aufgabenliste zum Audit 2026-10

Abhakliste zu [AUDIT-2026-10.md](AUDIT-2026-10.md). Dort steht zu jedem Punkt das Szenario und die Begründung; hier steht nur, was zu tun ist und woran man erkennt, dass es erledigt ist. Die Kennungen (K1, H4, M20 …) sind in beiden Dateien gleich.

Reihenfolge: Stufe 1 vor dem nächsten Kundeneinsatz, Stufe 2 vor 0.8.0, Stufe 3 CI und Release, Stufe 4 Dokumentation, Stufe 5 Gegenprüfen mit Herstellerdoku. Innerhalb einer Stufe ist die Reihenfolge frei.

Jeder Punkt: `- [ ] **Kennung** Datei:Zeile. Aufgabe. → Erledigt wenn …`

---

## Stufe 1: Vor dem nächsten Kundeneinsatz

- [x] **K1** `src/modules/Core.Backup.ps1:313-399` (`Restore-WzUndoSession`). Am Anfang bei `$syncHash.DryRun` je Eintrag nur mit Level Test protokollieren, `Skipped` zählen, nichts schreiben. In `src/pages/TweakList.ps1:335-393` Dialogtext nach Testmodus umschalten. → Erledigt wenn `Test-Undo.ps1` einen Rücknahme-Durchlauf im Testmodus enthält, der prüft, dass der Registry-Wert unverändert bleibt.
- [x] **K2** `src/modules/Cleanup.ps1:305, 414`, `src/modules/Uninstall.ps1:591-593`. Vor jedem `Remove-Item -Recurse` die Einträge selbst durchlaufen; alles mit `Attributes -band ReparsePoint` nur als Link entfernen, ohne Rekursion. Für Windows.old alternativ `cmd /c rd /s /q`. → Erledigt wenn ein Testfall in `Test-Undo.ps1` eine Junction in einem Wegwerf-Ordner anlegt, den Ordner löschen lässt und prüft, dass das Junction-Ziel noch voll ist.
- [x] **H8** `src/modules/Migration.ps1:138`. `-Level Err` zu `-Level Error`. → Erledigt wenn `Test-Smoke.ps1` alle `-Level`-Argumente im Baum gegen das ValidateSet aus `Core.Logging.ps1:47` prüft.
- [x] **H5** `src/modules/Drivers.ps1:320-341, 661`. Katalog-Downloads nach `offline\katalogtreiber\` legen oder in `Get-WzDriverBackups` alles ausschließen, was keine Sicherung ist (Markerdatei je Export). → Erledigt wenn nach einem Katalog-Download die Rückspiel-Auswahl keinen Eintrag »katalog« zeigt.
- [x] **H1** `src/main.ps1:242-243`, `src/modules/Core.Palette.ps1:69-74`, `src/modules/Core.Runspace.ps1` (`Set-WzBusy`). `DryRunToggle.IsEnabled = -not $isBusy` in `Set-WzBusy`; DryRun beim Taskstart einmal einfrieren und als Argument in den Runspace geben, Handler lesen den Parameter statt `$syncHash.DryRun`. → Erledigt wenn der Schalter während einer laufenden Aufgabe grau ist und Strg+K den Zustand nicht umschaltet. Umgesetzt über die Sperre; DryRun wird nicht als Argument eingefroren, weil sich der Wert während eines Vorgangs nicht mehr ändern kann.

## Stufe 2: Vor 0.8.0

### Eingriffe und Rücknahme

- [x] **H2** `src/modules/Uninstall.ps1:286-308, 466-470, 502-508`. Namenskandidaten nur zulassen, wenn kein anderer installierter Eintrag (über `Get-WzInstalledPrograms`) denselben Basisnamen hat. `%APPDATA%`/`%LOCALAPPDATA%`-Treffer im Dialog als »Benutzerdaten, keine Sicherung« kennzeichnen oder vorher als ZIP in den Sitzungsordner packen. → Erledigt wenn bei zwei installierten Python-Versionen nach Deinstallation einer davon `HKLM:\SOFTWARE\Python` nicht als Rest angeboten wird.
- [x] **H3** `src/pages/TweakList.ps1:257-333`, `src/modules/Optimizer.ps1:229`, `src/modules/Core.Backup.ps1:86-87`. Vor dem Anwenden `Test-WzWritableRoot` prüfen und mit Hinweis abbrechen (oder Sicherung nach `%ProgramData%\WinZii` ausweichen). `Complete-WzUndoSession` in try/catch, Summary mit `UndoFile=$null` und Meldung trotzdem zurückgeben. → Erledigt wenn auf schreibgeschütztem Stick kein Tweak angewendet wird und ein Dialog den Grund nennt.
- [x] **M1** `src/pages/TweakList.ps1:326-328`, `src/pages/Uninstall.ps1:428-430`, `src/pages/Cleanup.ps1:300-302`. Module geben die tatsächlich angewendeten Namen zurück; `-Detail` daraus bauen, Fehlschläge mit Präfix. → Erledigt wenn ein absichtlich fehlschlagender Tweak im Übergabeblatt als fehlgeschlagen steht.
- [x] **M2** `src/modules/Optimizer.ps1:216-224, 279-282, 332-335, 362-365`, `src/modules/AiRemoval.ps1:142-145`. Handler liefern `Changed/Skipped`; Tweak ohne einzige Änderung zählt als »nicht zutreffend«. → Erledigt wenn `ai-tasks-off` auf einem Gerät ohne Recall-Aufgaben nicht als »angewendet« gezählt wird.
- [x] **M4** `data/tweaks.json:1037-1055` (`sec-defender-network`). `defaultChecked: false`, `risk: medium`, Beschreibung um Cloud-Voraussetzung ergänzen. Alle Defender-Policy-Einträge (Z. 923, 1010, 1037, 1112, 1139): Hinweis »sperrt die Einstellung in der Windows-Sicherheit«. → Erledigt wenn `Test-Catalogs` durchläuft und die Texte in `kataloge.en.json` nachgezogen sind.
- [x] **M5** `src/modules/Autostart.ps1:298-299, 312, 391-406`. Startordner über `Get-WzUserFolder -Kind RoamingAppData` bilden, `Resolve-WzRegistryPath` auch auf die StartupApproved-Pfade anwenden. → Erledigt wenn bei Elevierung mit Technikerkonto der Startordner des Kunden gezeigt wird.
- [x] **M6** `src/modules/Core.Backup.ps1:337-341`. `if ($previous.state -ne 'Disabled') { Enable } else { Disable }`. → Erledigt wenn Testfall mit Zustand `Queued` in `Test-Undo.ps1`.
- [x] **M7** `src/modules/Cleanup.ps1:126-133, 225-276, 319-331`. Bei `Blocked` die Kategorie überspringen und melden; im Papierkorb-Catch `Failed=1` statt `0`; `data/cleanup.json:34` korrigieren (nur eigener Papierkorb). → Erledigt wenn ein laufender Edge die Cache-Kategorie als übersprungen meldet.
- [x] **N** `src/modules/Core.Backup.ps1:322-323`, `src/modules/Optimizer.ps1:268-269`. `keyExisted` im Undo-Eintrag speichern; bei `false` den Schlüssel nach der Rücknahme löschen, wenn er leer ist.
- [x] **N** `src/modules/Core.Backup.ps1:323`. `Remove-ItemProperty -ErrorAction Stop`, catch nur für »Wert fehlt«; `Restored++` nur bei Wirkung.
- [x] **N** `src/modules/Cleanup.ps1:165, 302`. Festen Pfadteil mit `[WildcardPattern]::Escape()` schützen, nur den Katalog-Platzhalter roh anhängen.
- [x] **N** `src/modules/Uninstall.ps1:53-55, 166-195`. GUID per Regex aus `MsiExec /I{GUID}` ziehen und wie ProductCode behandeln (`/x … /qn`).
- [x] **N** `src/modules/AiRemoval.ps1:174-181, 186-204`. `ActionFailed` bei Fehlschlag der Bereitstellungs-Entfernung setzen; EndOfLife-Schlüssel in `previous` festhalten und im Undo-Hinweis nennen.
- [x] **N** `src/modules/Optimizer.ps1:70, 247`. »Schon gesetzt« zusätzlich gegen `$current.Type -eq $Action.valueType` prüfen.
- [x] **N** `src/modules/Optimizer.ps1:182`. Sicherungsordner erst in `Complete-WzUndoSession` oder beim ersten Export anlegen, nicht im Testmodus.
- [x] **N** `data/tweaks.json:970-988` (`sec-llmnr-off`): NetBIOS aus dem Namen nehmen oder Schlüssel ergänzen. `:151-176` (`perf-animations-off`): `VisualFXSetting=2` begründen oder UserPreferencesMask setzen. `:1318-1357` (`ai-apps-policy`): Snipping Tool aus der Beschreibung oder Schlüssel ergänzen.
- [x] **N** `src/modules/Uninstall.ps1:530-616`, `src/modules/Core.Backup.ps1:392-398`. Aktionstyp `leftoverCleanup` im Restore behandeln, `.reg`-Dateien aus `exportedKeys` importieren.
- [x] **N** `src/modules/Autostart.ps1:366-414`. Hinweistext der Seite: Umschaltungen stehen nicht unter »Rücknahme«, nur im Übergabeblatt.

### Beschaffung und Ausführung

- [x] **H4** `data/wingetcodes.json`, `src/modules/Apps.ps1:469-474`. Katalog aus `AppInstallerErrors.h` neu ableiten, Hex-Wert je Eintrag mitführen (wie `updatecodes.json`). Ergänzen: 0x8A150109 (reboot), 0x8A15010D (skip, bereits installiert), 0x8A15010E (skip, höhere Version), 0x8A150101/0102 (retry, in Benutzung). Korrigieren: 0x8A150104, 0x8A15002C, 0x8A150011, 0x8A150017, 0x8A150016, 0x8A150015, 0x8A150001, 0x8A150002, 0x8A150107, 0x8A150056/59/5C/5E/61. Im `reboot`-Zweig `Test-WzAppInstalled` aufrufen. → Erledigt wenn `Test-Catalogs` oder ein neues Werkzeug Hex ↔ Dezimal ↔ Outcome gegenprüft und 0x8A150104 nicht mehr als Erfolg zählt. Abweichung: 0x8A150101/0102 stehen auf fail mit Handlungshinweis, nicht auf retry — »retry« heißt in WinZii »Benutzerbereich statt systemweit« und hilft bei einem laufenden Programm nicht.
- [ ] **H6** `src/modules/Apps.ps1:400-413, 433-434, 573-593`. Vor der Vorrat-Installation `winget settings --enable LocalManifestFiles` ausführen und protokollieren (Systemänderung, DryRun beachten), oder bei Fehlschlag auf Online-Installation zurückfallen. Offline-Pfad einmal auf einem Gerät ohne Netz abnehmen (nutzt `install --manifest` die Datei neben dem Manifest?). → Erledigt wenn ABNAHME.md einen bestandenen Offline-Durchlauf nennt. Stand: Code umgesetzt (LocalManifestFiles wird geprüft und bei Bedarf gesetzt, Online-Rückfall bei Fehlschlag aus dem Vorrat). Offen bleibt die Abnahme auf einem Gerät ohne Netz.
- [x] **M8** `src/modules/Office.ps1:197-198, 210-213, 427`. Vor Ausführung von `offline\odt\setup.exe` `Get-AuthenticodeSignature` mit Status `Valid` und Subject »Microsoft Corporation« verlangen, sonst verwerfen und neu laden. Vorrat-Installer (`offline\installers\*`) zumindest auf Signaturstatus prüfen. → Erledigt wenn eine manipulierte `setup.exe` abgelehnt wird (Testfall mit beliebiger unsignierter EXE).
- [x] **M9** `src/modules/Drivers.ps1:615-620`. Download-URL gegen `^https://[^/]*\.(windowsupdate|microsoft)\.com/` prüfen, sonst verwerfen.
- [x] **M10** `src/modules/Drivers.ps1:308`. pnputil: 0, 3010, 1641 als Erfolg (3010/1641 mit `RebootRequired`), 259 als »nichts eingespielt«. → Erledigt wenn `Test-Parsers` 3010 als Erfolg prüft.
- [x] **M12** `src/modules/Office.ps1:226, 229-299, 326, 404-405`. Edition in Cache-Pfad und `Test-WzOfficeCache` (stream.x86 vs stream.x64) einbeziehen; bei fehlender Bitness im Vorrat online installieren und das im Dialog sagen. → Erledigt wenn `Test-Office.ps1` Fall 10 zwischen x86 und x64 unterscheidet.
- [x] **M13** `src/pages/Office.ps1:214, 278, 362`. `-Cancelable` von Install, Remove und LibreOffice entfernen (oder `-KillOnCancel` mit Warnung).
- [x] **M14** `src/pages/Updates.ps1:212-213`. `Start-WzUpdateScan` im `OnComplete` von `Write-WzUpdateState` starten. → Erledigt wenn nach einer Installation die Liste ohne »beschäftigt«-Dialog neu geladen wird.
- [x] **M15** `src/modules/Core.Runspace.ps1:152-157`. Bei leerem Ergebnis `@()` statt `$null` an `OnComplete` übergeben. Gegenprobe in `src/pages/Drivers.ps1:486` und `src/pages/Toolbox.ps1:242`. → Erledigt wenn eine Katalogsuche ohne Treffer »keine Treffer« meldet.
- [x] **M16** `src/pages/Drivers.ps1:396-400`, `src/modules/Apps.ps1:400, 430`. Pseudo-App-Objekt mit `id` versehen oder `Get-WzOfflineInstallerPath` bei fehlender `id` `$null` liefern lassen.
- [x] **M17** `src/pages/Office.ps1:275`. `New-WzRestorePoint` in den Remove-Task vor Stufe 1 verlagern.
- [x] **M18** `src/modules/Setup.ps1:667-676`, `src/modules/Migration.ps1:451-455, 530`, `src/pages/Setup.ps1:402`. DryRun-Ergebnis aus `Import-WzPrinters` durchreichen; `Add-WzAction` nur an einer Stelle.
- [x] **N** `src/modules/Core.Version.ps1:30`. `SecurityProtocol = SecurityProtocol -bor Tls12` wie in `Apps.ps1:236`.
- [x] **N** `src/modules/WindowsUpdate.ps1:231-236`. Bei Einzel-HResult 0 auf `$Result.HResult` zurückfallen.
- [x] **N** `src/modules/Office.ps1:601-614`. ExitCode von `setup.exe` nach Stufe 1 prüfen und bei ≠ 0 als Warnung protokollieren.
- [x] **N** `src/modules/Office.ps1:527`. `${env:ProgramFiles(x86)}` vor `Join-Path` auf `$null` prüfen.
- [x] **N** `src/modules/Drivers.ps1:238-242`, `src/pages/Drivers.ps1:219-229`. Eigener Testmodus-Text statt »0 Pakete, 0 B gesichert«.
- [x] **N** `src/pages/Office.ps1:325`, `src/pages/Apps.ps1:192`. Office-Download und Vorabladen `-Cancelable` machen (Module haben `-KillOnCancel` vorbereitet).
- [x] **N** `src/modules/Drivers.ps1:555-556, 612-613`. `Invoke-WebRequest` mit `-UseDefaultCredentials` oder Proxy-Credentials wie in `Get-WzDownload`.
- [x] **N** `src/pages/Toolbox.ps1:90`. `-ConfirmText 'Starten'` über `Get-WzText`.

### Kundendaten, Umzug, Berichte, Diagnose

- [x] **H9** `src/modules/Migration.ps1:119-133`, `src/pages/UserData.ps1:422`. robocopy mit `-KillOnCancel` starten oder Abbruch in `Invoke-WzFileMigration` selbst behandeln (Flag abfragen, Prozess beenden, Ergebnis »abgebrochen bei Ordner X« zurückgeben). → Erledigt wenn nach »Abbrechen« kein `robocopy.exe` mehr läuft und der Ergebnisdialog erscheint.
- [x] **H10** `src/modules/UserData.ps1:51-58, 95-108`, `src/modules/Migration.ps1:80-88`. Known-Folder-Ziele aus `HKCU\…\User Shell Folders` (Desktop, Personal, My Pictures, My Video, My Music, `{374DE290-…}`) auflösen; OneDrive-Ordner als eigenen Kopierauftrag anbieten; vor dem Kopieren bei Platzhaltern warnen. → Erledigt wenn auf einem Win11 mit Ordnersicherung die Bestandsaufnahme die richtigen Größen zeigt. Stand: Ziele aus dem Registry-Zweig des Profils (nur geladene Profile, nur lokale Pfade), Warnung im Kopierdialog. Abnahme auf einem Gerät mit aktiver Ordnersicherung steht aus (Fragenkatalog).
- [x] **M20** `src/modules/Report.ps1:173-182` (`New-WzHtmlCard`). Zeilen als Objekte `@{Label;Value;Kind}` übergeben statt `|`-Strings; `$kind` gegen Whitelist `ok|warn|err|info`; mindestens `-split '\|', 3`. Aufrufer: `:347-348, 354-355, 625-628, 635, 654-655, 663-664, 900, 913, 916`. → Erledigt wenn eine SSID `Gast|" onmouseover="x` im Bericht als Text erscheint. Umgesetzt im Parser von New-WzHtmlCard (Art nur als letzter Teil und nur aus der Liste, Wert darf »|« enthalten) statt durch Umbau aller Aufrufer auf Objekte.
- [x] **M21** `src/modules/Report.ps1:228-232` (`New-WzHtmlTable`). Heuristik `^<(span|a|strong|em)\b` entfernen; fertiges HTML nur über eigenen Marker (z. B. `[pscustomobject]@{Html=…}` oder Spaltenklasse `raw`), alles andere immer maskieren. → Erledigt wenn ein Prüfwerkzeug `Report.ps1` mit einem Programmnamen `<span onclick=x>` lädt und das Ergebnis maskiert ist.
- [x] **M23** `src/modules/Migration.ps1:406-417`. `Test-WzWlanProfileHasKey`: zusätzlich `sharedKey.protected -ne 'true'`. → Erledigt wenn ein Profil mit DPAPI-Blob als »ohne Schlüssel« gelistet wird.
- [x] **M24** `src/modules/Migration.ps1:478, 570`. Netzlaufwerke und Druckerverbindungen im Kontext des angemeldeten Anwenders anlegen (geplante Aufgabe als interaktiver Benutzer oder Benutzer-Token); mindestens Warnung im Dialog und Ergebnis, wenn `Get-WzInteractiveProfile` ein fremdes Konto erkennt. `rest.drivesMessage` entsprechend anpassen. Umgesetzt über eine einmalige geplante Aufgabe im Konto des Anwenders (Invoke-WzAsInteractiveUser).
- [x] **M25** `src/modules/UserData.ps1:216-240`, `src/modules/Migration.ps1:270-279`, `src/modules/Cleanup.ps1` (`Measure-WzPathSet`). Eigene rekursive Enumeration mit try/catch je Verzeichnis, Reparsepunkte überspringen, abgebrochene Zweige zählen und als »unvollständig« melden. → Erledigt wenn `Documents` mit den Kompatibilitäts-Junctions eine plausible Größe liefert.
- [x] **M26** `src/modules/UserData.ps1:379-380, 508-524`, `src/modules/Migration.ps1:283-313`, `src/pages/Restore.ps1`. Nach erfolgreichem Rückspielen »Sicherung von diesem Stick löschen« anbieten; Zurückspielen-Seite zeigt standardmäßig nur den eigenen Rechner, fremde hinter einer Warnung. Optional: Export mit Techniker-Passphrase (AES). Umgesetzt: Nach dem WLAN-Import fragt WinZii, ob die Klartext-Schlüssel vom Stick gelöscht werden. Abweichung: fremde Rechner bleiben sichtbar (Fragenkatalog F1).
- [x] **M27** `src/modules/HealthCheck.ps1:56-172`, `src/pages/Diagnostics.ps1:383`. Task `-Cancelable`, Flag in der Messschleife prüfen, `$worker.Shell.Stop()` vor `EndInvoke`. → Erledigt wenn »Abbrechen« den Belastungstest innerhalb von 2 s beendet.
- [x] **N** `src/modules/Report.ps1:1096, 1124-1125`. `ArbeitsspeicherGB` über `Format-WzNumber` als Text oder ganzzahlig in MB.
- [x] **N** `src/modules/Report.ps1:1082-1108`. Werte, die mit `=`, `+`, `-`, `@` beginnen, mit `'` voranstellen (CSV-Formel-Injektion).
- [x] **N** `src/modules/Diagnostics.ps1:28-46`, `data/eventmap.json`. Exakter Vergleich gegen `ProviderName` mit Aliasliste; Level 3 für kartierte Provider/IDs mitholen oder die `warning`-Einträge streichen; »DCOM« gegen `Microsoft-Windows-DistributedCOM`.
- [x] **N** `src/modules/Diagnostics.ps1:256-267`. `ValidDump` (Bytes 4-8) auf `DU64` prüfen, sonst Offset 0x28.
- [x] **N** `src/modules/Diagnostics.ps1:453-477`. chkdsk-Texte für Code 2 und 3 korrigieren, Dateisystem vor `/scan` prüfen.
- [x] **N** `src/modules/Report.ps1:287-301, 1020-1021, 1030`, `src/modules/Diagnostics.ps1:294-298, 348, 351`, `src/modules/Core.System.ps1:285, 325`, `src/modules/UserData.ps1:519`, `src/pages/Dashboard.ps1:310`. Typ- und Bereichs-Codes sprachneutral halten (`crash`, `report`, `setup`, `check`), erst bei Anzeige übersetzen; Zahlen über `Format-WzSeconds`/`Format-WzNumber`; `-like '*neu gestartet*'` durch Code-Vergleich ersetzen. → Erledigt wenn `Test-Language` Einzelwort-Literale in `-Area`, `-ConfirmText`, `-Title` streng prüft.
- [x] **N** `src/modules/UserData.ps1:352`. netsh-Profilliste sprachneutral parsen (Text nach dem letzten Doppelpunkt je Zeile).
- [x] **N** `src/modules/HealthCheck.ps1:306-308, 352`. Ordner `WinZii-Tempo` entfernen, vorher `FreeSpace` prüfen, Pfad auf `$env:SystemDrive` ableiten.
- [x] **N** `src/modules/NetworkDiag.ps1:235-244`. `$request.ReadWriteTimeout = $TimeoutMs`.
- [x] **N** `src/modules/UserData.ps1:323-325, 636-644`. `Get-WzBrowserProcess` vor dem Lesezeichen-Export prüfen oder zusätzlich `bookmarkbackups\*.jsonlz4` sichern.
- [x] **N** `src/modules/UserData.ps1:372, 627`, `src/pages/Diagnostics.ps1:461`. DryRun-Abfrage vor die Ordneranlage ziehen; `mdsched.exe` im Testmodus nur protokollieren.
- [x] **N** `src/modules/Migration.ps1:212`. `attrib` zusätzlich mit `"$Path\*"`; Dialog `data.hydrateMessage2` nennt die bleibende Einstellung »Immer auf diesem Gerät behalten«.
- [x] **N** `src/modules/Core.System.ps1:866-869`. `PendingFileRenameOperations` nur mit nicht-leeren Zielpfaden werten oder nur CBS/WU-Schlüssel.

### Oberfläche und Laufzeit

- [x] **H11** `src/modules/Core.I18n.ps1:420-422`. Merker `AppsChecked`, `OffChecked`, `AiStatesChecked`, `OptStatesChecked`, `CleanScanned` beim Sprachwechsel zurücksetzen (oder alle auf `*Loaded` umbenennen). → Erledigt wenn `Test-LanguageSwitch` einen Apps-Durchlauf enthält und der Installieren-Knopf nach dem Wechsel aktiv ist.
- [x] **H12** `src/main.ps1:205-213`. `$window.Add_Closing({ if ($syncHash.Busy) { Rückfrage; $e.Cancel = -not $answer.Confirmed } })`; `BtnClose` ruft nur noch `Close()`. → Erledigt wenn Alt+F4 während einer Aufgabe die Rückfrage zeigt.
- [x] **M28** `src/modules/Core.Runspace.ps1:107-137`. Abholung in `try/finally` mit `CurrentTask=$null; Set-WzBusy -Off` im `finally`.
- [x] **M29** `src/modules/Core.Ui.ps1:178-184`. Bei Fehler im Initializer `$syncHash.Pages.Remove($Id)`.
- [x] **M31** `src/modules/Core.I18n.ps1:68-77, 511-515`, `src/launcher.ps1:34-41`. Nicht-deutsche Primärsprache ohne eigene Datei auf `en` statt `de`. → Erledigt wenn `Test-Language` Abschnitt 8 die Funktion `Get-WzSystemLanguage` wirklich aufruft (siehe auch Stufe 3).
- [x] **N** `src/modules/Core.Ui.ps1:372, 471, 473`. `'Auswahl'`, `'// ACHTUNG'`, `'// HINWEIS'` über `Get-WzText`.
- [x] **N** `src/launcher.ps1:130-134`, `tools/Test-Pages.ps1:68`, `tools/Test-LanguageSwitch.ps1:165`. Im `&`-Zweig `$mainScript` ohne eigene Anführungszeichen übergeben; einmal mit Pfad mit Leerzeichen prüfen.
- [x] **N** `src/pages/Protocol.ps1:58`. `-ArgumentList ('"{0}"' -f $syncHash.LogFile)`.
- [x] **N** `src/modules/Core.Runspace.ps1:180`, `src/modules/Core.Ui.ps1:256-262`, `src/main.ps1:191-192`. In `Update-WzLanguageUi` `Set-WzBusy -Off`, `Set-WzConsoleCollapsed` und Statuszeile nachziehen.
- [x] **N** `src/launcher.ps1:90-99`. Unblock-Scan auf `src`, `data`, `tools`, `assets`, `Start.bat` beschränken.
- [x] **N** `src/modules/Core.Palette.ps1:134-136`. `[WildcardPattern]::Escape($needle)` oder `IndexOf(…, OrdinalIgnoreCase)`.
- [x] **N** `src/modules/Core.Logging.ps1:46`. `[AllowEmptyString()]` und leere Meldung ignorieren. Aufrufer: `Drivers.ps1:316, 487, 656, 677, 683`, `Diagnostics.ps1:421, 449, 476`, `pages/AiRemoval.ps1:70`, `pages/Toolbox.ps1:84`.
- [x] **N** `src/modules/Core.Logging.ps1:71-77`. Schreibzugriff mit Retry oder Lock; `src/modules/Core.Paths.ps1:51-60` Sitzungsordner älter als N Tage beim Start aufräumen (mit Hinweis).
- [x] **N** `src/modules/Core.Ui.ps1:67-73, 119-121`, `src/modules/Core.I18n.ps1:417`. In `Update-WzLanguageUi` `CardGrids.Clear()` und `$script:WzCardWidths` leeren.
- [x] **N** `src/modules/Core.I18n.ps1:452-459, 485-492`. Defekte `einstellungen.json` als `.bak` sichern und Warnzeile; in temp schreiben und `Move-Item -Force`.
- [x] **N** `src/modules/Core.Paths.ps1:107-114`. Ergebnis von `Test-WzWritableRoot` einmal je Sitzung merken.
- [x] **N** `src/modules/Core.Paths.ps1:146`. UNC-Wurzel: freien Platz über `GetDiskFreeSpaceEx` ermitteln.
- [x] **N** `src/modules/Core.Ui.ps1:47, 55`. Dublette in `Register-WzNames` als Fehler werfen.
- [x] **N** `src/xaml/MainWindow.xaml:169, 222-227, 238`. Klappzeile und Credit per Tastatur erreichbar, Chrome-Knöpfe mit `AutomationProperties.Name`; 31 hart kodierte Farben auf Theme-Pinsel.
- [x] **N** `src/main.ps1:112`. Schrift-URI mit `[Uri]::EscapeUriString` bilden.
- [x] **N** `src/main.ps1:337-340`. `WZ_SELFTEST_ACTION` in CONTRIBUTING.md als Entwicklerpfad dokumentieren.

## Stufe 3: CI, Prüfwerkzeuge, Release

- [x] **H13** `tools/Invoke-Analyzer.ps1:44-45, 54, 77`, `.github/workflows/pruefung.yml:118`. `-ErrorAction Stop`; `ParseError` mitzählen; in der CI `-IncludeWarnings` und mindestens `PSPossibleIncorrectComparisonWithNull`, `PSUseDeclaredVarsMoreThanAssignments` als Fehlschlag werten. → Erledigt wenn ein absichtlicher `$x -eq $null` die CI rot macht.
- [x] **M30** `tools/Test-Pages.ps1:48-59`, `src/main.ps1:323-368`. Im Selbsttest-Zweig vor dem Schließen alle `LogEntries` mit Level Error nach stdout schreiben und Exit-Code ≠ 0 setzen. → Erledigt wenn ein absichtlich geworfener Fehler in `Initialize-WzAppsPage` den Test rot macht.
- [x] **M32** Neuer Workflow `on: push: tags: ['v*']`: Prüfwerkzeuge, `New-Release.ps1`, Tag gegen `$WzVersion`, README-Badge und CHANGELOG-Kopf vergleichen, `WinZii-<v>.zip`, `WinZii.zip` und `.sha256` ans Release hängen. `tools/New-Release.ps1`: sauberen Arbeitsbaum und leeren `[Unveröffentlicht]`-Abschnitt prüfen. → Erledigt wenn das nächste Release ohne Handarbeit eine Prüfsumme trägt.
- [x] **M33** `.github/workflows/pruefung.yml`. `timeout-minutes: 30` je Job, `permissions: contents: read`, `concurrency` mit `cancel-in-progress`.
- [x] **M34** `.github/workflows/pruefung.yml:32, 44, 125`. Actions per SHA pinnen (Versionskommentar), `Install-Module PSScriptAnalyzer -RequiredVersion`, `.github/dependabot.yml` für `github-actions`.
- [x] **M36** `tools/Test-Undo.ps1:244-347, 408-535`. Abschnitte 7 und 8 in `try/finally` mit garantierter Rückschaltung des Energieplans und Löschung der Testschlüssel. README Z. 220 und CONTRIBUTING Z. 45: Hinweis »ändert kurzzeitig den aktiven Energieplan, braucht Admin«.
- [x] **M37** BOM entfernen aus `data/apps.json`, `data/tweaks.json`, `data/updatecodes.json`, `data/lang/de.json`, `data/lang/en.json`, `data/lang/kataloge.en.json`, `README.md`, `README.en.md`, `CHANGELOG.md`, `docs/ABNAHME.md`. `Test-Smoke.ps1:86` um »JSON/MD/HTML ohne BOM« erweitern, `Repair-Encoding.ps1` entsprechend. → Erledigt wenn `python3 -c "import json; json.load(open('data/tweaks.json'))"` ohne `utf-8-sig` durchläuft.
- [x] **M39** `tools/Test-Sandbox.wsb:21-23`, `tools/WinZii-Schreibend.wsb:23-25`, `tools/Test-Sandbox.ps1:172-191, 236, 368`. Nur einen Staging-Ordner (`New-Release.ps1 -KeepStaging`) einbinden; am Ende `offline\daten\<Sandbox-PC>\` entfernen; `.wsb`-Kommentar auf `backups\` hinweisen.
- [x] **M40** `tools/Test-Smoke.ps1:28`. Auch `tools\` parsen; `Test-Layout` als CI-Schritt; `New-Release.ps1 -OutputDir $env:RUNNER_TEMP` als Trockenlauf.
- [ ] **Neue Prüfwerkzeuge** für die neun Module ohne funktionale Aussage, in dieser Reihenfolge: Report (HTML-Escaping mit Injektions-Mustern, CSV), Setup (Validierung Rechnername/Konto/Schlüssel), WindowsUpdate (HResult-Kette, Get-WzUpdateResultCode), Toolbox, AiRemoval, Autostart, HealthCheck, Snapshot, Core.Version (Test-WzVersionNewer). → Erledigt wenn die Tabelle »Testabdeckung je Modul« im Audit keine Zeile »keines« mehr hat.
- [x] **N** `tools/New-Release.ps1:98-105`. Zweite Zeile mit `WinZii.zip` in die `.sha256`.
- [x] **N** `.gitattributes:27-31`. `.github/ export-ignore`.
- [x] **N** `.gitignore`. `/selftest.png`, `/abbilder/`.
- [x] **N** `.editorconfig:9`. `[*.{yml,yaml,txt,gitattributes,gitignore,editorconfig}] end_of_line = lf`.
- [x] **N** `tools/Test-Language.ps1:201-216`. `Core.I18n.ps1` dot-sourcen und `Get-WzSystemLanguage` mit umgebogener `Get-UICulture` aufrufen; Z. 259: Einzelwort-Literale in `-ConfirmText`, `-Title`, `-Area` prüfen.
- [ ] **N** `tools/Test-Pages.ps1:51, 71`, `tools/Test-Layout.ps1:229`, `tools/Test-Sandbox.ps1:51, 63`. Zusätzlich `$LASTEXITCODE -ne 0` als Fehlschlag.
- [ ] **N** `tools/Test-Process.ps1:88`. PID des gestarteten Kindprozesses prüfen statt aller `ping`-Prozesse.
- [ ] **N** `tools/Test-Catalogs.ps1:272, 278-279`. Strukturprüfung für `oemtools.json`, `updatecodes.json`, `wingetcodes.json` (Pflichtfelder, Hex ↔ Dezimal).

## Stufe 4: Dokumentation

- [ ] **M35** `README.md:96`, `CONTRIBUTING.md:38`, `docs/ABNAHME.md:22`. »bei jedem Push« durch »bei jedem Push auf main und jedem PR« ersetzen, oder Workflow auf `branches: ['**']`.
- [ ] **M38** `SECURITY.md:37-40`, `README.md:81`. Netzverbindungen ergänzen: `api.github.com` (Versionsprüfung, nur nach Zustimmung), `catalog.update.microsoft.com` (Treibersuche und -download), Windows-Update-COM, Herstellerwerkzeuge über winget.
- [ ] **M41** `README.md:95`, `README.en.md:95`, `docs/ABNAHME.md:354-356`. »33 für beide« → 41 (oder Zahl aus dem Katalog erzeugen).
- [ ] **N** `README.md:104` (»46 Prüfungen« → aus Test-Undo zählen), `:198` (`powerplan` in die Aktionstypen), `:212-229` (`Test-Office`, `Test-Layout`, `New-Icon` in die Werkzeugtabelle), `:218` (»drei Wegen« oder Abbrechen-Knopf in Test-Dialogs ergänzen), Startparameter `-Language`.
- [ ] **N** `README.en.md`. Abschnitt »Entwicklung« mit Werkzeugtabelle nachziehen.
- [ ] **N** `docs/ABNAHME.md:13-17, 33, 54, ~394`. Kopf auf 0.7.0-Inhalt, Kapitel 23-29 anlegen oder Tabelle als vollständige Quelle kennzeichnen, »sechzehn Seiten«.
- [ ] **N** `SECURITY.md:13`. Mail-Adresse eintragen oder Satz streichen und auf GitHub Private Vulnerability Reporting verweisen; Satz »unterstützt wird die jeweils neueste Fassung«.
- [ ] **N** `CHANGELOG.md`. Vergleichs-Links am Ende (Keep a Changelog).
- [x] **N** `data/cleanup.json:34`. »auch der von anderen Benutzerkonten« streichen (siehe M7).

## Stufe 5: Gegen Herstellerdoku prüfen

Diese Punkte sind im Audit als Vermutung gekennzeichnet. Erst nachlesen, dann entscheiden.

- [ ] **H7** `data/oemtools.json:31`. Lenovo Thin Installer: Bedeutet Reboot-Typ 1 »Reboot forced« und unterdrückt `-noreboot` nur Typ 3? Dann `-includerebootpackages 3`. Dasselbe für HPIA `/Action:Install` belegen.
- [ ] **M3** `data/tweaks.json:1179-1197`. LSA: Ist `RunAsPPL=1` die Variante mit UEFI-Sperre und `2` ohne (Win11 22H2+)? Dann Wert 2 mit `minBuild: 22621`, auf älteren Builds als nicht rücknehmbar kennzeichnen.
- [ ] **M11** `src/modules/Drivers.ps1:475-485`, `data/oemtools.json:15-16`. Dell Command Update: Exit 1 = Erfolg mit Neustart, 500 = keine Updates? Dann Exit-Code-Tabelle je Werkzeug im Katalog.
- [ ] **M19** `src/modules/Apps.ps1:192`. Braucht `Add-AppxProvisionedPackage` auf LTSC `-DependencyPackagePath`? Dann die entpackten Abhängigkeiten mitgeben und Fehlschlag deutlich melden.
- [ ] **M22** `src/modules/Report.ps1:1176-1191`. Erzeugt Edge headless bei laufendem Edge mit demselben Profil kein PDF? Dann `--user-data-dir="$env:TEMP\winzii-edge"` und danach löschen.
- [ ] **N** `src/modules/HealthCheck.ps1:47-51, 149-152`. Liefert `Win32_Processor.CurrentClockSpeed` den Ist-Takt? Sonst `\Processor Information(_Total)\% Processor Performance`.
- [ ] **N** `src/modules/Setup.ps1:587-595`. Liefert `slmgr /ipk` bei Fehlern einen Exit-Code ≠ 0? Sonst StdOut auf `0x[0-9A-F]{8}` prüfen.
- [ ] **N** `src/modules/Cleanup.ps1:319-331`. Leert `Clear-RecycleBin` nur den Papierkorb des aufrufenden Kontos?
- [ ] **N** `src/modules/Apps.ps1:433-434`. Nutzt `winget install --manifest` die Datei neben dem Manifest oder lädt es die InstallerUrl neu? (Teil von H6.)
