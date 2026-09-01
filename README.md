<div align="center">

<img src="docs/banner.svg" alt="WinZii" width="100%">

# WinZii

**Portables Windows-Werkzeug für die tägliche Technikerarbeit.**
Vom USB-Stick starten, aufräumen, optimieren, einrichten — ohne Installation, ohne Konto, ohne Telemetrie.

**Deutsch** · [English](README.en.md)

<sub>A Windows maintenance toolkit for IT technicians. Fully bilingual German/English — interface, dialogs, log, reports and handover sheet.</sub>

![Version](https://img.shields.io/badge/Version-0.5.2-00d4ff?labelColor=0a0a0f&style=flat-square)
[![Prüfung](https://github.com/haZiinstinct/WinZii/actions/workflows/pruefung.yml/badge.svg)](https://github.com/haZiinstinct/WinZii/actions/workflows/pruefung.yml)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-00d4ff?labelColor=0a0a0f&style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-00d4ff?labelColor=0a0a0f&style=flat-square)
![Installation](https://img.shields.io/badge/Installation-keine-00d4ff?labelColor=0a0a0f&style=flat-square)

[Loslegen](#-loslegen) · [Funktionen](#-funktionen) · [Sicherheit](#-sicherheit) · [Grenzen](#-bekannte-grenzen) · [Aufbau](#-aufbau) · [Erweitern](#-erweitern)

</div>

---

## ✨ Funktionen

| Bereich | Was es tut |
| --- | --- |
| **Dashboard** | Windows-Version, Hardware, Grafik, Bildschirme, BIOS, RAM-Steckplätze und Akkuverschleiß, dazu Aktivierung, BitLocker, Virenschutz, Datenträger und Netzwerk — alles auf einen Blick beim Aufsetzen des PCs. |
| **Diagnose** | Wertet die Ereignisprotokolle aus und übersetzt sie in Klartext: was passiert ist, was es bedeutet, was zu tun ist. Dazu Bluescreen-Stoppcodes, Datenträgerzustand und die Werkzeuge sfc, DISM und chkdsk. |
| **Updates** | Zeigt, was Windows noch nachzuholen hat, und spielt es ein. Treiber stehen getrennt und sind nie vorausgewählt — Windows Update bietet dort gern ältere Herstellerstände an, die einen neueren Treiber überschreiben. Eingespielt wird eines nach dem anderen, damit im Protokoll steht, wo es hängt; neu gestartet wird nie von selbst. |
| **Optimierung** | 41 Eingriffe für Geschwindigkeit, Telemetrie, Datenschutz und Sicherheit. Jeder mit Begründung, jeder einzeln zurücknehmbar. |
| **KI-Entfernung** | Findet Copilot, Recall und Click to Do — sperrt sie per Richtlinie oder entfernt sie ganz. Die Sperren wirken auch vorbeugend gegen Funktionsupdates. |
| **Bereinigung** | Zeigt erst, wo wie viel Platz liegt (Zwischenspeicher, Update-Reste, Browser-Caches, Windows.old), dann wird gezielt gelöscht. Persönliche Dateien sind ausgeschlossen. |
| **Programme** | 59 Programme über winget, darunter eine Rubrik **Sicherheit** (Zweitmeinung, Aufräumen nach einem Befall, Schutz danach), mit Nachinstallation von winget selbst für LTSC-Systeme. Installationsdateien lassen sich auf den Stick laden. |
| **Deinstallieren** | Installierte Programme suchen und entfernen, still wo möglich — und danach die Reste, die der Deinstallierer liegen lässt: Installationsordner, Startmenü-Einträge, eigene Registry-Schlüssel. Die Funde stehen mit Größe im Dialog, entfernt wird erst nach Bestätigung, Schlüssel vorher als `.reg` gesichert. |
| **Office** | Microsoft 365, Office LTSC 2024 und 2021 über das offizielle Bereitstellungswerkzeug — auf Wunsch komplett offline vom Stick. Dazu LibreOffice. |
| **Daten** | Beantwortet vor der Neuinstallation: Was muss gesichert werden? Profilgrößen je Konto, wann ein Konto zuletzt benutzt wurde, Outlook-Dateien, Browser-Profile, Drucker, Netzlaufwerke, Produktschlüssel. Warnt nicht nur vor OneDrive-Platzhaltern, die im Explorer wie Dateien aussehen und leer sind, sondern lädt sie auf Wunsch herunter und wartet auf den Abschluss. Exportiert Lesezeichen, WLAN-Zugänge, Geräteliste und BitLocker-Schlüssel — und kopiert die persönlichen Ordner mit robocopy auf eine externe Platte, ohne an der Quelle etwas zu löschen. |
| **Zurückspielen** | Die andere Hälfte des Datenumzugs: WLAN-Netze, Lesezeichen, Drucker und Netzlaufwerke aus einer Sicherung wieder anlegen — auch aus der eines anderen Rechners. Zeigt vorher, was passt und was nicht: fehlende Druckertreiber, Browser-Profile, die es hier nicht gibt, und WLAN-Netze, die ohne Schlüssel gesichert wurden. |
| **Treiber** | Geräte mit Fehlercode im Klartext statt als Nummer. Treiberbestand nach Alter sortiert — bei Bluescreens der schnellste Weg zum Verdächtigen. Treiber auf den Stick sichern und nach dem Neuaufsetzen in einem Rutsch zurückspielen. |
| **Autostart** | Zeigt alles, was beim Anmelden mitstartet, samt Herausgeber. Abschalten statt löschen, jederzeit umkehrbar. |
| **Reparatur** | Misst erst, wo es klemmt (Netzwerkkarte, IP, Router, Namensauflösung, Internet), und benennt dann die passende Maßnahme. Dazu Windows-Update-Zwischenspeicher leeren, Druckwarteschlange befreien, Virenschnellprüfung, vorinstallierte Apps entfernen. |
| **Protokoll** | Jeder Schritt wird mitgeschrieben. Zwei Ausgaben: das technische Protokoll und das **Übergabeblatt** — was gemacht wurde, wie viel Platz gewonnen wurde, wie der PC ausgestattet ist und was noch ansteht, in Kundensprache und mit Feldern für Techniker, Kunde und Auftragsnummer. |

---

## 🚀 Loslegen

1. Aktuelles ZIP aus den [Releases](https://github.com/haZiinstinct/WinZii/releases) laden und auf einen USB-Stick entpacken (**exFAT oder NTFS**, nicht FAT32 — sonst passen die Office-Pakete nicht drauf).
2. `Start.bat` doppelklicken.
3. Die Abfrage der Administratorrechte bestätigen.

Das war alles. WinZii braucht keine Installation, keine Laufzeitumgebung und keinen bestimmten Laufwerksbuchstaben. Der Ordner darf heißen, wie er will, und an jeder Stelle liegen — auch in einem Pfad mit Leerzeichen.

> **Windows meldet sich mit einem blauen Hinweis?**
> Auf »Weitere Informationen« und dann »Trotzdem ausführen« klicken. Der Hinweis erscheint bei jeder Datei aus dem Internet, die nicht kostenpflichtig signiert wurde. Zu jedem Release gehört eine SHA256-Prüfsumme — damit lässt sich das Archiv vor dem Entpacken abgleichen:
> ```powershell
> Get-FileHash .\WinZii-0.5.2.zip -Algorithm SHA256
> ```

**Voraussetzungen:** Windows 10 oder 11 mit Administratorrechten. PowerShell 5.1 und .NET Framework sind in Windows enthalten.

**Erster Start empfohlen im Testmodus:** Der Schalter unten rechts protokolliert alle Änderungen, ohne sie auszuführen. So lässt sich jede Aktion vorher ansehen. `Start.bat` reicht Schalter durch — `Start.bat -DryRun` startet gleich im Testmodus, `Start.bat -NoElevate` ohne Rechteanforderung.

---

## 🛡 Sicherheit

Ein Werkzeug, das tief ins System eingreift, muss den Weg zurück kennen:

- **Wiederherstellungspunkt** vor jedem größeren Eingriff (auf Wunsch, standardmäßig an).
- **Registry-Export** jedes berührten Schlüssels als `.reg`-Datei.
- **Undo-Datei** mit dem exakten Zustand vor jeder Einzelaktion — der Knopf »Änderungen zurücknehmen« stellt ihn wieder her.
- **Testmodus**, der nur protokolliert.
- **Nachfrage vor jedem Eingriff**, mit genauer Auflistung, was passiert.

Alles landet unter `backups\<Computername>\<Zeitstempel>\`.

Was **nicht** passiert: keine Telemetrie, keine Verbindung nach außen außer für ausdrücklich angestoßene Downloads (winget, Office, LibreOffice), kein Löschen persönlicher Dateien. Der Download-Ordner wird nur ausgewertet, nie geleert.

Zwei Ausgaben schreiben absichtlich Geheimnisse im Klartext auf den Datenträger, jeweils hinter einer eigenen Bestätigung: der **WLAN-Export mit Schlüsseln** und die **BitLocker-Wiederherstellungsschlüssel**. Der Stick gehört danach nicht in fremde Hände. Einzelheiten in [SECURITY.md](SECURITY.md).

> **Ohne Gewähr.** WinZii greift tief in Windows ein. Die Nutzung erfolgt auf eigene Verantwortung — erst im Testmodus ansehen, vor größeren Eingriffen einen Wiederherstellungspunkt anlegen lassen, und bei Kundendaten vorher sichern.

---

## ⚠ Bekannte Grenzen

Ehrlich gesagt, damit niemand böse überrascht wird: WinZii wurde auf **einem** Rechner entwickelt — Windows 11 Enterprise, deutschsprachig, Desktop ohne Akku, ohne WLAN, ohne BitLocker, ohne OneDrive. Seit 0.4.1 kommt ein zweites Gerät dazu: ein Notebook mit Akku und WLAN, auf dem die Abnahme aus [docs/ABNAHME.md](docs/ABNAHME.md) läuft. Was dort geprüft ist, steht unten als geprüft.

| Bereich | Stand |
| --- | --- |
| **Windows 10** | Die Versionsweiche greift (33 Einträge für beide Systeme, 7 nur für Windows 11, 1 nur für Windows 10), aber es lief dort nie ein vollständiger Durchlauf. |
| **Nicht-deutsches Windows** | Seit 0.5.2 laufen alle Prüfwerkzeuge bei jedem Push auf einem **englischen** Windows-Server, und die Oberfläche wird dort in beiden Sprachen gestartet. Ungeprüft bleibt, was echte Windows-Werkzeuge zurückgeben: `sfc`, `DISM`, `chkdsk` und `manage-bde` antworten dort englisch, und WinZii wertet das aus. Dafür ist Punkt 13 der Abnahme da. |
| **Akku** | Auf dem Notebook geprüft: Verschleiß wird gemessen und im Dashboard angezeigt. Bis 0.4.0 meldete dasselbe Gerät »kein Akku vorhanden«, weil die Erkennung an einer einzigen WMI-Klasse hing. |
| **WLAN** | Verbindungsprüfung, Internetzugang und seit 0.5.1 auch Downloads über WLAN geprüft, ohne Kabel im Gerät: 93 MB in 32 s, eine Installation über winget mitsamt Nachprüfung, und ein Fehlschlag lässt nichts Halbfertiges liegen. |
| **BitLocker, OneDrive** | Der »nicht vorhanden«-Pfad ist geprüft und meldet sauber, auf dem Notebook zusätzlich gegen `manage-bde` gegengehalten. Ein verschlüsselter Datenträger und ein OneDrive mit Platzhaltern fehlen weiterhin. |
| **Energieplan** | Anlegen, aktivieren, zweiter Durchlauf ohne Doppelkopie und Zurücknehmen sind auf dem Notebook durchgespielt. Was Netz und Akku unterscheidet, sind Kühlungsrichtlinie und Turbo-Verhalten — viele Hersteller blenden beide aus der Energieoberfläche aus. Setzen lassen sie sich trotzdem, nachsehen kann man sie dort dann aber nicht. Kann ein Gerät sie gar nicht setzen, sagt WinZii im Protokoll, dass der Plan nichts bewirkt. |
| **Office auf den Datenträger laden** | Der Abbruch beendet das Bereitstellungswerkzeug, **nicht** den Download: Geladen wird vom Click-to-Run-Dienst von Windows, und der macht im Hintergrund weiter. Im Abnahmelauf wuchs der Ordner nach dem Abbruch von 39 MB auf 2,5 GB. WinZii sagt das im Protokoll und nennt den Ordner zum Löschen; ein angefangener Vorrat gilt seit 0.4.1 zuverlässig als unvollständig. |
| **Restesuche nach dem Deinstallieren** | Die Regeln und die ganze Kette — finden, sichern, entfernen — sind in `tools\Test-Undo.ps1` mit 46 Prüfungen abgedeckt. Seit 0.5.1 ist sie auch gegen echte Deinstallierer gelaufen, auf einem Gerät mit 53 gewachsen installierten Programmen; der Lauf hat zwei Fehler gefunden, beide behoben (siehe [CHANGELOG](CHANGELOG.md)). Zwei Dinge gelten dauerhaft: **Gelöschte Ordner sind endgültig weg** — gesichert werden nur Registry-Schlüssel —, und die Suche ist absichtlich eng. Sie übersieht lieber einen Rest, als den Ordner eines anderen Programms anzufassen; seit 0.5.1 auch dann nicht, wenn der Hersteller selbst den Sammelordner der ganzen Familie als Installationsordner einträgt. |
| **Treibersicherung und Office** | Nur lesend geprüft, nie vollständig durchgeführt. |
| **Drucker zurückspielen** | In der Sandbox vollständig durchlaufen: Treiber aus dem Treiberspeicher nachziehen, Netzwerkanschluss anlegen, Drucker einrichten, beim zweiten Lauf nichts doppeln. Ungeprüft bleibt ein Drucker an echter Hardware — USB-Anschlüsse entstehen erst mit dem Gerät und werden bewusst übersprungen. |
| **WLAN zurückspielen** | Die Profildateien werden richtig gelesen und ein Fehlschlag sauber gemeldet. Ein Profil wirklich einzurichten konnte nie geprüft werden — weder der Entwicklungsrechner noch die Sandbox hat einen WLAN-Adapter. |
| **Kleine Bildschirme** | Das Fenster braucht mindestens 1000 × 560 Punkte und verkleinert sich beim Start selbst auf die Arbeitsfläche. Bei 1092 × 614 — einem 1366er-Laptop bei 125 % — ist alles geprüft: Konsole startet eingeklappt, die Seitenleiste holt den aktiven Eintrag ins Bild, nichts liegt außerhalb. Seit 0.5.0 bricht auch genau am Mindestmaß kein Wort mehr mitten in der Karte. |

**In der Windows Sandbox geprüft** (`tools\Test-Sandbox.wsb`, ein frisches Windows 11 24H2 ohne winget): Start über den Launcher, echte Optimierungen anwenden und wieder zurücknehmen, Netzwerk-Diagnose, die winget-Nachinstallation, das Finden und Lesen einer Sicherung, das Anlegen eines Netzwerkdruckers samt Treiber sowie ein echter Dateiumzug mit Unterordnern — alles auf einem System, das nichts von diesem Projekt weiß.

Rückmeldungen von anderen Systemen sind ausdrücklich willkommen — besonders von Windows 10 und von nicht-deutschen Installationen.

---

## 🖼️ Oberfläche

Dunkles Design im haZii-Stil, deutsch oder englisch, mit mitlaufender Konsole: Jede Aktion ist sichtbar, während sie läuft. Lange Vorgänge blockieren die Oberfläche nicht.

<img src="docs/screenshot-dashboard.png" alt="Dashboard von WinZii" width="100%">

Zwölf Seiten in fünf Gruppen:

```
// SYSTEM        Dashboard · Diagnose
// OPTIMIEREN    Optimierung · KI-Entfernung · Bereinigung · Autostart
// INSTALLIEREN  Programme · Office
// ÜBERNEHMEN    Daten · Treiber
// WERKZEUGE     Reparatur · Protokoll
```

---

## 🛠 Aufbau

```
WinZii/
├─ Start.bat              Einstieg per Doppelklick
├─ src/
│  ├─ launcher.ps1        Administratorrechte, Downloadsperre, STA-Start
│  ├─ main.ps1            Aufbau von Fenster, Navigation und Modulen
│  ├─ modules/            Logik (Optimizer, Cleanup, Apps, Office, Diagnostics …)
│  ├─ pages/              Bedienlogik je Seite
│  ├─ xaml/               Oberfläche: Theme.xaml + eine Datei je Seite
│  └─ templates/          Vorlage für die HTML-Berichte
├─ data/                  Kataloge als JSON — hier wird erweitert
├─ assets/fonts/          JetBrains Mono und Inter (SIL OFL 1.1, siehe unten)
├─ tools/                 Prüfwerkzeuge und Release-Bauskript
├─ docs/                  Banner und Bildschirmfoto für dieses README
├─ offline/               Zwischenspeicher für Installationsdateien
├─ logs/ backups/ reports/  Ergebnisse je Computer
```

**Technik:** PowerShell 5.1 mit WPF. Kein Kompilieren, keine Abhängigkeiten — der Code ist lesbar und lässt sich direkt anpassen. Lange Vorgänge laufen in eigenen Runspaces, damit die Oberfläche antwortet.

---

## 🔧 Erweitern

Alle Inhalte stehen in `data/` als JSON. Für neue Einträge ist keine Zeile Code nötig.

**Programm hinzufügen** (`data/apps.json`):
```json
{
  "id": "beispiel",
  "name": "Beispielprogramm",
  "category": "technik",
  "wingetId": "Hersteller.Programm",
  "description": "Wofür es gut ist.",
  "defaultChecked": false
}
```

**Optimierung hinzufügen** (`data/tweaks.json`):
```json
{
  "id": "beispiel-tweak",
  "category": "privacy",
  "level": "soft",
  "risk": "low",
  "name": "Kurzer Titel",
  "description": "Was es bewirkt und warum das sinnvoll ist.",
  "defaultChecked": true,
  "appliesTo": "all",
  "requiresReboot": false,
  "actions": [
    { "type": "registry", "path": "HKCU:\\Software\\...", "name": "Wert", "valueType": "DWord", "value": 0 }
  ]
}
```

Aktionstypen: `registry`, `service`, `scheduledTask`, `feature`, `appx`, `capability`, `command`.

**Ereignis deuten** (`data/eventmap.json`): Quelle, Kennung, Titel, Erklärung und Empfehlung eintragen — die Diagnose übernimmt den Rest.

Nach jeder Änderung prüfen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Catalogs.ps1
```

---

## 🧪 Entwicklung

| Werkzeug | Zweck |
| --- | --- |
| `tools\Test-Smoke.ps1` | Syntax, XAML, Kataloge und Encoding in einem Durchlauf |
| `tools\Test-Catalogs.ps1` | Kataloge auf Pflichtfelder und Konsistenz prüfen |
| `tools\Test-Pages.ps1` | Jede Seite laden und auf Verdrahtungsfehler prüfen |
| `tools\Test-Contrast.ps1` | Schrift- und Flächenkontraste gegen WCAG 2.1 rechnen |
| `tools\Test-Dialogs.ps1` | Prüft, dass sich jeder Dialog auf allen vier Wegen schließen lässt |
| `tools\Test-Process.ps1` | Rückgabewerte externer Programme, auch im Hintergrund-Runspace |
| `tools\Test-Undo.ps1` | Sicherung und Rücknahme an einem eigenen Registry-Schlüssel durchspielen |
| `tools\Test-Language.ps1` | Sprachdateien auf gleiche Schlüssel, Platzhalter und Kulturen prüfen |
| `tools\Test-LanguageSwitch.ps1` | Startet WinZii, schaltet im Betrieb um und prüft, ob auch die gemessenen Texte mitgehen |
| `tools\Test-Parsers.ps1` | Deutungen von sfc-, pnputil- und winget-Ausgaben gegen deutsche **und** englische Wortlaute |
| `tools\Invoke-Analyzer.ps1` | PSScriptAnalyzer mit Zielversion PowerShell 5.1 |
| `tools\Repair-Encoding.ps1` | UTF-8 mit BOM erzwingen (Pflicht bei PowerShell 5.1 und Umlauten) |
| `tools\New-Release.ps1` | Release-ZIP bauen und SHA256-Prüfsumme ausgeben |
| `tools\WinZii.wsb` | Windows Sandbox zum gefahrlosen Ausprobieren (schreibgeschützt) |
| `tools\WinZii-Schreibend.wsb` | Dasselbe mit Schreibrecht — für Treibersicherung und Berichte |
| `tools\Test-Sandbox.wsb` | Selbsttest in der Sandbox: läuft automatisch los und legt Bericht und Abbild unter `sandbox-ergebnis\` ab |

Die Sandbox muss einmalig freigeschaltet werden, danach ist ein Neustart nötig:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

Alle `.ps1`- und `.xaml`-Dateien müssen **UTF-8 mit BOM** sein, sonst liest PowerShell 5.1 sie als ANSI und zerstört die Umlaute. Einzelheiten und die Prüfliste vor dem Commit stehen in [CONTRIBUTING.md](CONTRIBUTING.md).

Was sich zwischen den Fassungen geändert hat: [CHANGELOG.md](CHANGELOG.md).

---

## 📄 Lizenz

**WinZii** steht unter der MIT-Lizenz — siehe [LICENSE](LICENSE).

**Die mitgelieferten Schriften nicht.** [Inter](https://github.com/rsms/inter) und [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) unter `assets/fonts/` stehen unter der **SIL Open Font License 1.1**; die Lizenztexte liegen als `OFL-Inter.txt` und `OFL-JetBrainsMono.txt` daneben.

Die Techniken zur KI-Entfernung orientieren sich an [zoicware/RemoveWindowsAI](https://github.com/zoicware/RemoveWindowsAI), der Aufbau als portables Werkzeug an [Chris Titus WinUtil](https://github.com/christitustech/winutil).

---

<div align="center">

Gebaut von haZii · `// code:` [**haZii.org**](https://hazii.org)

</div>
