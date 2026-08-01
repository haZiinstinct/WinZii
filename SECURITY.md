# Sicherheit

WinZii läuft mit Administratorrechten, schreibt in die Registry, entfernt Pakete und
löscht Dateien. Fehler an diesen Stellen haben Folgen. Deshalb dieser Hinweis, wie man
sie meldet.

## Eine Lücke melden

Bitte **kein öffentliches Issue** anlegen, wenn sich damit ein System schädigen lässt.
Stattdessen:

- über die private Meldefunktion von GitHub („Security" → „Report a vulnerability"), oder
- per Mail an die im Repository hinterlegte Adresse.

Hilfreich: welche Fassung, welches Windows, welcher Ablauf, und was im schlimmsten Fall
passieren kann. Eine Antwort kommt, sobald es die Zeit erlaubt — WinZii ist ein
Nebenprojekt, keine betreute Software mit Reaktionszusage.

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
- Verbindungen ins Internet nur, wenn ihr sie ausdrücklich anstoßt: winget-Installationen,
  Office-Download über das Bereitstellungswerkzeug von Microsoft, die Nachinstallation von
  winget selbst — und die drei Erreichbarkeitsprüfungen der Netzwerk-Diagnose.
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
