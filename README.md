<div align="center">

<img src="docs/banner.svg" alt="WinZii" width="100%">

# WinZii

**Portables Windows-Werkzeug für die tägliche Technikerarbeit.**
Vom USB-Stick starten, aufräumen, optimieren, einrichten — ohne Installation, ohne Konto, ohne Telemetrie.

<sub>A German-language Windows maintenance toolkit for IT technicians. Interface and documentation are German only.</sub>

![Version](https://img.shields.io/badge/Version-0.2.0-00d4ff?labelColor=0a0a0f&style=flat-square)
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
| **Optimierung** | 40 Eingriffe für Geschwindigkeit, Telemetrie, Datenschutz und Sicherheit. Jeder mit Begründung, jeder einzeln zurücknehmbar. |
| **KI-Entfernung** | Findet Copilot, Recall und Click to Do — sperrt sie per Richtlinie oder entfernt sie ganz. Die Sperren wirken auch vorbeugend gegen Funktionsupdates. |
| **Bereinigung** | Zeigt erst, wo wie viel Platz liegt (Zwischenspeicher, Update-Reste, Browser-Caches, Windows.old), dann wird gezielt gelöscht. Persönliche Dateien sind ausgeschlossen. |
| **Programme** | 52 Programme über winget, mit Nachinstallation von winget selbst für LTSC-Systeme. Installationsdateien lassen sich auf den Stick laden. Zweiter Bereich: installierte Programme suchen und entfernen, still wo möglich. |
| **Office** | Microsoft 365, Office LTSC 2024 und 2021 über das offizielle Bereitstellungswerkzeug — auf Wunsch komplett offline vom Stick. Dazu LibreOffice. |
| **Daten** | Beantwortet vor der Neuinstallation: Was muss gesichert werden? Profilgrößen je Konto, Outlook-Dateien, Browser-Profile, Drucker, Netzlaufwerke, Produktschlüssel. Warnt vor OneDrive-Platzhaltern, die im Explorer wie Dateien aussehen, aber leer sind. Exportiert Lesezeichen, WLAN-Zugänge und BitLocker-Wiederherstellungsschlüssel. |
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
> Get-FileHash .\WinZii-0.2.0.zip -Algorithm SHA256
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

Ehrlich gesagt, damit niemand böse überrascht wird: WinZii wurde auf **einem** Rechner entwickelt und geprüft — Windows 11 Enterprise, deutschsprachig, Desktop ohne Akku, ohne WLAN, ohne BitLocker, ohne OneDrive.

| Bereich | Stand |
| --- | --- |
| **Windows 10** | Die Versionsweiche greift (34 Einträge für beide Systeme, 6 nur für Windows 11, 1 nur für Windows 10), aber es lief dort nie ein vollständiger Durchlauf. |
| **Nicht-deutsches Windows** | Die Stellen, die Windows-Ausgaben auswerten, kennen Deutsch und Englisch; `takeown` fragt die Oberflächensprache ab. Geprüft wurde nur die deutsche Seite. |
| **Akku, WLAN, BitLocker, OneDrive** | Die »nicht vorhanden«-Pfade sind geprüft und melden sauber. Der jeweilige Positiv-Fall ist mangels Hardware ungetestet. |
| **Treibersicherung, Office, winget-Nachinstallation** | Nur lesend geprüft, nie vollständig durchgeführt. |
| **Windows Sandbox** | Die beiden `.wsb`-Dateien sind ungetestet. |
| **Kleine Bildschirme** | Das Fenster verlangt mindestens 1060 × 640 Punkte. Auf 1366 × 768 bei 125 % Skalierung wird es eng. |

Rückmeldungen von anderen Systemen sind ausdrücklich willkommen — besonders von Windows 10 und von nicht-deutschen Installationen.

---

## 🖼️ Oberfläche

Dunkles Design im haZii-Stil, deutschsprachig, mit mitlaufender Konsole: Jede Aktion ist sichtbar, während sie läuft. Lange Vorgänge blockieren die Oberfläche nicht.

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

Aktionstypen: `registry`, `service`, `scheduledTask`, `feature`, `appx`, `capability`, `cbsPackage`, `command`.

**Ereignis deuten** (`data/eventmap.json`): Quelle, Kennung, Titel, Erklärung und Empfehlung eintragen — die Diagnose übernimmt den Rest.

Nach jeder Änderung prüfen:

```powershell
powershell -NoProfile -File tools\Test-Catalogs.ps1
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
| `tools\Invoke-Analyzer.ps1` | PSScriptAnalyzer mit Zielversion PowerShell 5.1 |
| `tools\Repair-Encoding.ps1` | UTF-8 mit BOM erzwingen (Pflicht bei PowerShell 5.1 und Umlauten) |
| `tools\New-Release.ps1` | Release-ZIP bauen und SHA256-Prüfsumme ausgeben |
| `tools\WinZii.wsb` | Windows Sandbox zum gefahrlosen Ausprobieren (schreibgeschützt) |
| `tools\WinZii-Schreibend.wsb` | Dasselbe mit Schreibrecht — für Treibersicherung und Berichte |

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
