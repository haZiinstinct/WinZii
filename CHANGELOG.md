# Änderungen

Alle nennenswerten Änderungen an WinZii. Die Fassungen folgen
[Semantic Versioning](https://semver.org/lang/de/).

## [0.2.1] — 2026-08-02

Robustheit auf fremden Rechnern — die offenen Funde der Veröffentlichungs-Prüfung.

### Behoben

- **Elevierung mit einem fremden Konto:** Beantwortet ein Techniker die
  Rechteanforderung mit seinem eigenen Konto, zeigten `HKCU:` und die
  Benutzerpfade auf dessen Profil. Die Seite »Daten« meldete dann »OneDrive nicht
  eingerichtet« und fand keine Browser-Profile, und die Bereinigung räumte das
  falsche Profil auf. OneDrive, Outlook, Browser, Bereinigung und die
  »angemeldet«-Kennung arbeiten jetzt mit dem Profil des Anwenders am Bildschirm —
  im Normalfall (gleiches Konto) ändert sich nichts.
- **Benutzerprofile ohne Lesezugriff** wurden ganz aus der Sicherungs-Checkliste
  gelassen, weil »Zugriff verweigert« wie »fehlt« aussah. Sie erscheinen jetzt mit
  dem Hinweis, dass sie nicht lesbar sind.
- **Energiesparplan:** Die Rücknahme stellte stur auf »Ausbalanciert« und verwarf
  damit den vorher aktiven Plan (etwa einen Herstellerplan oder »Ultimative
  Leistung«). Der aktive Plan wird jetzt vor der Umstellung eingefangen und bei der
  Rücknahme exakt wiederhergestellt. Auf Geräten ohne Höchstleistungsplan gibt es
  statt eines rohen Fehlercodes eine erklärte Meldung.
- **Office-Installation** beendet laufende Office-Programme ohne eigene Nachfrage
  (`FORCEAPPSHUTDOWN`). Der Dialog nennt jetzt ausdrücklich, welche Programme
  gerade laufen und dass ungespeicherte Dokumente verloren gehen.
- **Ohne Adminrechte** meldete die App-Suche still nur das eigene Konto; jetzt
  steht der Hinweis im Protokoll.

### Neu

- **Abbrechen-Knopf** in der Statusleiste für die Bestandsaufnahmen (Daten,
  Geräte, Speicherplatz-Analyse, Programmliste). Eingriffe bleiben bewusst nicht
  abbrechbar.
- **Fortschritt und Zeitbudget** bei der Daten-Aufnahme: je Konto eine
  Protokollzeile, bei OneDrive alle 20 000 Dateien eine Zwischenmeldung. Bricht
  die Zählung nach 45 Sekunden ab, sagt die Seite »Prüfung unvollständig« statt
  eine beruhigende, aber halbe Zahl zu zeigen.
- **Englisches README** (`README.en.md`) — die Oberfläche bleibt deutsch.

### Geändert

- Das Fenster passt sich beim Start an die Arbeitsfläche an und kommt mit
  1000 × 560 Punkten aus (vorher mindestens 1060 × 640 — zu groß für 1366 × 768
  bei 125 % Skalierung).
- Wird der Systemschutz für den Wiederherstellungspunkt erst eingeschaltet, steht
  das jetzt im Protokoll und im Dialog.
- Die Auswahl beim Treiber-Zurückspielen markiert Sicherungen **anderer Rechner**
  deutlich.
- Entfernte mitgelieferte Apps: Meldung »nicht verfügbar (Windows Home)« beim
  BitLocker-Dienst korrigiert (Home hat den Dienst ebenfalls); Akkuverschleiß
  kann nicht mehr negativ werden.

## [0.2.0] — 2026-08-01

Schwerpunkt: WinZii war stark darin, einen PC zu *verändern*, und schwach darin, ihn zu
*verstehen* und zu *dokumentieren*, was es getan hat. Diese Fassung schließt beides.

### Neu

- **Seite „Daten"** — beantwortet vor jeder Neuinstallation, was gesichert werden muss:
  Profilgrößen je Konto, Outlook-Datendateien, Browser-Profile, Drucker, Netzlaufwerke,
  Produktschlüssel. Warnt vor **OneDrive-Platzhaltern**, die im Explorer wie Dateien
  aussehen, aber nichts enthalten — wer die kopiert, sichert leere Hüllen. Exportiert
  Lesezeichen, WLAN-Zugänge und BitLocker-Wiederherstellungsschlüssel.
- **Seite „Treiber"** — Geräte mit Fehlercode im Klartext statt als Nummer,
  Treiberbestand nach Alter sortiert, Sicherung auf den Datenträger und Rückspielung
  per `pnputil`.
- **Übergabeblatt** — fasst in Kundensprache zusammen, was gemacht wurde, wie viel Platz
  gewonnen wurde, wie der PC ausgestattet ist und was noch ansteht. Mit Feldern für
  Techniker, Kunde und Auftragsnummer.
- **Programme deinstallieren** als zweiter Bereich auf der Seite „Programme": dieselbe
  Liste wie in der Systemsteuerung, mit Suchfeld. Still, wo das Programm es zulässt.
- **Netzwerk-Diagnose** — misst der Reihe nach Netzwerkkarte, IP-Adresse, Router,
  Namensauflösung und Internetzugang und benennt die passende Maßnahme, statt zu raten.
  Unterscheidet dabei „kein Internet" von Anmeldeseite, Zertifikatsfehler und Sperre.
- **Virenschnellprüfung** und **Startdauer** aus dem Leistungsprotokoll.
- **Geräteblatt auf dem Dashboard** — Grafikkarte, Bildschirme, BIOS-Stand,
  RAM-Steckplätze samt Höchstausbau und Akkuverschleiß in Prozent.
- **52 statt 28 Programme** im Katalog, mit den neuen Bereichen Datenrettung und
  Sicherung, Belastungstest und Laufzeitumgebungen.

### Behoben

- **`Invoke-WzProcess` lieferte immer `ExitCode = $null`.** `Start-Process -PassThru`
  ohne `-Wait` füllt den Wert unter PowerShell 5.1 nicht. Damit meldete jedes externe
  Werkzeug einen Fehlschlag — und die Dateisystemprüfung meldete umgekehrt *immer*
  „keine Fehler gefunden".
- **Meldungen aus Hintergrundarbeiten erreichten die Konsole nie.** Der Dispatcher kann
  keinen Skriptblock ausführen, der zu einem anderen Runspace gehört; der Aufruf schlug
  kommentarlos fehl.
- **Der Start über den Launcher scheiterte bei bereits erhöhten Rechten.** `main.ps1`
  wurde mit dem Aufrufoperator geladen, wodurch die Module in einem Bereich landeten, den
  die Ereignisbehandlungen von WPF nicht sehen.
- **`takeown` war fest auf die deutsche Antwort verdrahtet** (`/d j`). Auf jedem
  nicht-deutschen Windows scheiterte damit die Besitzübernahme, und `Windows.old` blieb
  liegen.
- **WinZii stürzte ab, bevor ein Fenster erschien**, wenn der Datenträger
  schreibgeschützt war oder von einem Netzwerkpfad gestartet wurde.
- **DNS-Umstellung ohne Rückweg.** Die bisherigen Server werden jetzt vor der Änderung
  gesichert; der Dialog verspricht keine Umkehrbarkeit mehr, die es nicht gab.
- **Widgets abschalten meldete auf Windows 10 Erfolg, ohne zu wirken** — der Eintrag
  schrieb Windows-11-Schlüssel. Jetzt zwei getrennte Einträge.
- Entfernte mitgelieferte Apps werden protokolliert; vorher gab es dazu keinerlei
  Aufzeichnung.
- Der Datenträgerzustand konnte den Befund des vorherigen Laufwerks übernehmen, wenn ein
  Laufwerk keine Zustandswerte lieferte.
- Lesbarkeit: alle Schrift- und Flächenkontraste erfüllen jetzt WCAG 2.1 AA. Dialoge
  lassen sich auf vier Wegen schließen (Schließkreuz, Escape, Klick daneben, Abbrechen).

### Geändert

- Systemabfrage von 29 s auf 0,7 s, Bereinigungsanalyse von 72 s auf 4 s.
- Der Credit lautet jetzt `// code: haZii.org` statt `// webdesign:` — WinZii ist ein
  Werkzeug, keine Webseite.

## [0.1.0] — 2026-07-30

Erste Fassung. Zehn Seiten: Dashboard, Diagnose, Optimierung, KI-Entfernung, Bereinigung,
Programme, Office, Autostart, Reparatur, Protokoll. Portabel vom USB-Stick, ohne
Installation, mit Wiederherstellungspunkt, Registry-Export, Undo-Datei und Testmodus.
