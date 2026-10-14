# Sicherheit

WinZii läuft mit Administratorrechten, schreibt in die Registry, entfernt Pakete und
löscht Dateien. Fehler an diesen Stellen haben Folgen. Deshalb dieser Hinweis, wie man
sie meldet.

## Eine Lücke melden

Bitte **kein öffentliches Issue** anlegen, wenn sich damit ein System schädigen lässt.
Stattdessen:

über die private Meldefunktion von GitHub (Private Vulnerability Reporting:
„Security" → „Report a vulnerability"). Andere Wege gibt es nicht.

Hilfreich: welche Fassung, welches Windows, welcher Ablauf, und was im schlimmsten Fall
passieren kann. Eine Antwort kommt, sobald es die Zeit erlaubt — WinZii ist ein
Nebenprojekt, keine betreute Software mit Reaktionszusage.

## Unterstützte Fassungen

Unterstützt wird die jeweils neueste veröffentlichte Fassung. Korrekturen erscheinen
als neue Fassung, ältere werden nicht nachgebessert.

## Was **kein** Sicherheitsproblem ist

- **Der Virenscanner schlägt an.** Ein unsigniertes Skript, das mit Administratorrechten
  Registry-Schlüssel setzt, Dienste anhält und Pakete entfernt, sieht für einen Scanner
  wie Schadsoftware aus. Das ist erwartbar. Wer nachsehen will, was passiert: der Code
  liegt vollständig offen, und der **Testmodus** protokolliert jeden Schritt, ohne ihn
  auszuführen.
- **SmartScreen warnt beim ersten Start.** Die Dateien sind nicht signiert; eine
  Code-Signatur kostet Geld. Prüft bitte stattdessen die im Release veröffentlichte
  SHA256-Prüfsumme des ZIP-Archivs.
- **Ein Eingriff hat etwas kaputt gemacht, das ihr bestätigt habt.** Dafür gibt es
  Wiederherstellungspunkt, `.reg`-Export und die Rücknahme-Funktion. Ein Fehlerbericht
  ist trotzdem willkommen — nur eben als normales Issue.

## Was WinZii nach außen tut

Damit man es nicht selbst nachlesen muss:

- **Keine Telemetrie**, keine Nutzungszählung, kein Aufruf nach Hause.
- Verbindungen ins Internet nur, wenn ihr sie ausdrücklich anstoßt:
  - winget-Installationen und -Aktualisierungen, die Nachinstallation von winget selbst
    und die Herstellerwerkzeuge für Treiber (Dell, Lenovo, HP, Intel), die über winget
    kommen und danach selbst beim Hersteller suchen,
  - Office-Download über das Bereitstellungswerkzeug von Microsoft,
  - Treibersuche und -download im Microsoft Update-Katalog
    (`catalog.update.microsoft.com`, Downloads nur über HTTPS von Microsoft),
  - Windows Update über die Windows-Update-Schnittstelle (COM) — die Verbindung baut
    Windows selbst auf,
  - die Erreichbarkeitsprüfungen der Netzwerk-Diagnose.
- **Eine Ausnahme mit Zustimmung:** Die Versionsprüfung fragt beim ersten Start einmal,
  ob sie bei GitHub (`api.github.com`) nach einer neueren Fassung sehen darf. Nur nach
  einem Ja geht bei jedem Start eine einzelne Anfrage dorthin; wer ablehnt, wird nie
  wieder gefragt.
- Alles, was WinZii schreibt, landet unterhalb des eigenen Ordners in `logs\`,
  `backups\`, `reports\` und `offline\`.

## Vorsicht bei diesen Ausgaben

Zwei Funktionen schreiben absichtlich Geheimnisse im Klartext auf den Datenträger, jeweils
hinter einer eigenen Bestätigung:

- **WLAN-Export mit Schlüsseln** — die Passwörter stehen unverschlüsselt in den
  XML-Dateien.
- **BitLocker-Wiederherstellungsschlüssel** — damit lässt sich das Laufwerk öffnen.

Der Datenträger gehört danach nicht in fremde Hände. Auch die Protokolle unter `logs\` und
die Berichte unter `reports\` enthalten Rechnernamen, Benutzernamen und Pfade — vor dem
Weitergeben durchsehen.
