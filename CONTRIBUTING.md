# Mitarbeiten

Beiträge sind willkommen. Ein paar Dinge, die man vorher wissen sollte — vor allem die
erste.

## Die eine Regel, die alles kaputt macht

**Alle `.ps1`- und `.xaml`-Dateien müssen UTF-8 *mit BOM* sein.**

PowerShell 5.1 liest eine Datei ohne BOM als ANSI. Aus `Größe` wird dann `GrÃ¶ÃŸe`, und
weil im Projekt an mehreren Stellen deutschsprachige Windows-Ausgaben ausgewertet werden,
greift danach kein Muster mehr. Der Fehler fällt nicht beim Speichern auf, sondern
irgendwann zur Laufzeit an einer ganz anderen Stelle.

Viele Editoren entfernen die BOM stillschweigend. Deshalb:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Repair-Encoding.ps1
```

Das Skript setzt die BOM überall dort, wo sie hingehört. Es läuft gefahrlos beliebig oft.
Die mitgelieferte `.editorconfig` weist Editoren zusätzlich an, die Codierung zu behalten
— verlassen sollte man sich darauf nicht.

Bewusst **ohne** BOM: `data/*.json`, `src/templates/report.html` und `Start.bat`. Die
Kataloge werden in `Core.Json.ps1` ausdrücklich als UTF-8 eingelesen.

## Vor jedem Commit

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Repair-Encoding.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Test-Catalogs.ps1
powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Test-Pages.ps1
```

Die weiteren Prüfwerkzeuge lohnen sich, wenn du in dem jeweiligen Bereich gearbeitet hast
— die CI lässt sie ohnehin alle bei jedem Push laufen, auf einem englischen Windows:

| Werkzeug | Wofür |
| --- | --- |
| `tools\Test-Language.ps1` | Texte in `data\lang\*.json` geändert — jeder Schlüssel in beiden Sprachen, Platzhalter gleich |
| `tools\Test-LanguageSwitch.ps1` | am Sprachwechsel oder an gemessenen Texten (Dashboard-Sicherheitskarte) gearbeitet |
| `tools\Test-Parsers.ps1` | eine Windows-Ausgabe neu gedeutet (`sfc`, `DISM`, `winget`, Sicherheitscenter …) — Muster gegen die echten deutschen **und** englischen Wortlaute |
| `tools\Test-Undo.ps1` | an Sicherung, Rücknahme, Energieplan oder Restesuche gearbeitet |
| `tools\Test-Office.ps1` | am Office-Vorrat oder der Bereitstellungskonfiguration gearbeitet |
| `tools\Test-Layout.ps1` | an XAML-Seiten oder Karten gearbeitet — fährt jede Seite bei 1000×560 an und misst, ob ein Wort mitten durchbricht |
| `tools\Test-Contrast.ps1` | Farben in `Theme.xaml` geändert |
| `tools\Test-Dialogs.ps1` | an `Show-WzConfirm` gearbeitet |
| `tools\Test-Process.ps1` | an `Invoke-WzProcess` gearbeitet |
| `tools\Invoke-Analyzer.ps1` | allgemeine Codeprüfung, Ziel ist PowerShell 5.1 |

Was keines der Werkzeuge kann, steht in [docs/ABNAHME.md](docs/ABNAHME.md): die Prüfung auf
fremder Hardware, Punkt für Punkt, mit dem Stand, was davon schon gelaufen ist.

`Test-Pages.ps1` öffnet jede Seite in einem echten Fenster und prüft zusätzlich den Start
über den Launcher. Es findet Verdrahtungsfehler, die eine reine Syntaxprüfung nicht sieht.

## Inhalte statt Code

Für neue Programme, Optimierungen, Ereignisdeutungen oder Bereinigungspfade ist **keine
Zeile Code** nötig — alles steht in `data/*.json`. Der Aufbau ist im README beschrieben.
`Test-Catalogs.ps1` prüft Pflichtfelder, Verweise und das Format von winget-Kennungen.

Neue winget-Kennungen bitte vorher einzeln bestätigen:

```powershell
winget show --id Hersteller.Programm --exact
```

## Grundsätze im Code

- **Deutsch**, in ganzen Sätzen — Oberfläche, Kommentare, Protokollmeldungen. Der Text im
  Programm richtet sich an Techniker und deren Kunden, nicht an Entwickler.
- **Kommentare erklären das Warum**, nicht das Was. Besonders bei den Umwegen um die
  Eigenheiten von PowerShell 5.1 — davon gibt es einige, und ohne Begründung sieht jeder
  davon nach unnötiger Umständlichkeit aus.
- **Kein Eingriff ohne Rückfrage und ohne Rückweg.** Was die Registry ändert, gehört über
  `Invoke-WzTweaks` mit Undo-Sitzung und `.reg`-Export. Was sich nicht zurücknehmen lässt,
  muss das im Dialog sagen — und der Dialog darf nichts versprechen, was der Code nicht
  hält.
- **Nichts erfinden.** Kann eine Angabe nicht ermittelt werden, gehört „nicht ermittelbar"
  in die Oberfläche, keine Schätzung.
- Länger laufende Arbeit gehört in `Invoke-WzTask`, damit die Oberfläche bedienbar bleibt.

## Fehlerberichte

Hilfreich sind: Windows-Ausgabe und Build (steht auf dem Dashboard), Sprache des Systems,
was du getan hast, und der betreffende Ausschnitt aus `logs\<Rechnername>\…\session.log`.
Bitte vorher durchsehen — das Protokoll enthält Rechnernamen und Pfade.
