# Abnahme auf fremder Hardware

Diese Datei ist die Übergabe an die Claude-Code-Sitzung auf dem Laptop. Sie steht im
Repo, damit dort ein `git pull` reicht.

**Warum es diese Datei gibt:** WinZii wurde auf **einem** Rechner entwickelt, auf dem
alles schon vorhanden war — winget im Suchpfad, der Zwischenspeicher gefüllt, das
elevierte Konto dasselbe wie das angemeldete. Jede `Test-Path`-Weiche trifft dort den
bequemen Zweig. Genau daraus sind die drei Symptome entstanden, die den Audit ausgelöst
haben. Alles unten ist der Teil, der auf dem Entwicklungsrechner **grundsätzlich nicht**
prüfbar ist.

Stand: **0.4.0**, Tag `v0.4.0`. Alle acht Prüfwerkzeuge grün, Sandbox-Lauf bestanden,
Start aus sauberer Kopie mit leerem `offline\` geprüft.

---

## So anfangen

```bash
git clone git@github.com:haZiinstinct/WinZii.git
```

Dann Claude Code im Ordner starten und diese Datei nennen. Vor dem ersten Eingriff:

```bash
powershell -NoProfile -File tools\Test-Smoke.ps1
```

**Alles zuerst im Testmodus.** `Start.bat -DryRun` protokolliert jede Änderung, ohne sie
auszuführen.

---

## 1. winget nach echter Neuanmeldung

Der Fall, der in der Sandbox nicht prüfbar war: Ein frisch registriertes App-Installer-Paket
startet vor einer Neuanmeldung nicht, und in der Sandbox kann man sich nicht neu anmelden.

- Seite **Programme** öffnen. Steht in der Konsole `winget gefunden: v…`?
- Falls nicht: **winget nachinstallieren**, dann abmelden und wieder anmelden, WinZii neu
  starten. Jetzt muss es gefunden werden.
- Ein kleines Paket wirklich installieren (7-Zip). Danach muss die Nachprüfung greifen —
  im Protokoll steht dann nicht nur »installiert«, sondern das Programm ist über
  `winget list` auffindbar.

**Worauf achten:** Meldet die Seite sporadisch »winget nicht gefunden«, obwohl es läuft?
Das war ein Fehler in 0.3.0 (`Select-Object` riss den Aufruf ab) und ist in 0.4.0 behoben.
Wenn es wiederkommt, ist die Ursache eine andere.

## 2. Elevierung mit einem anderen Konto

Wenn du dich mit einem eigenen Admin-Konto elevierst, während ein anderes Konto am
Bildschirm angemeldet ist:

- Werden die Benutzereinstellungen für den **angemeldeten** Anwender gesetzt? Das Protokoll
  sagt es: »Angemeldet ist '…', WinZii läuft als '…'«.
- Nach einer Optimierung nachsehen, ob unter `backups\<Rechner>\<Zeit>\` `.reg`-Dateien
  liegen. Bis 0.4.0 entstand dort für **keinen** HKCU-Wert eine Sicherung.
- Seite **Daten**: werden die Profilgrößen des richtigen Kontos gemessen?

## 3. WLAN statt Kabel

Alles, was mit Downloads zu tun hat, lief bisher nur über Kabel:

- Seite **Reparatur** → **Verbindung prüfen**. Urteil plausibel?
- Ein Programm über WLAN installieren. Zeitlimits, Fortschritt, Abbruch.
- **Office auf den Datenträger laden** anstoßen und nach einer Minute abbrechen — bricht
  es sauber ab, oder bleibt etwas Halbfertiges liegen?

**Worauf achten:** Meldet die Internetprüfung »Sicherheitszertifikat abgelehnt«, obwohl
Downloads funktionieren? Das war ein Fehlalarm in 0.3.0, der jede Installation blockierte.

## 4. Leerer Stick

Das Release-ZIP auf einen Stick entpacken, `offline\` bleibt leer. Dann:

- Programme installieren — läuft der echte Download-Weg?
- **winget nachinstallieren** ohne vorgefüllten Zwischenspeicher (lädt ~315 MB).
- Office laden und installieren.

## 5. OEM-Office

Der wahrscheinlichste Grund, warum Office beim ersten Versuch nicht lief:

- Seite **Office**: Wird das vorinstallierte Office erkannt? Steht die **Bitness** dabei?
- Bei 32-Bit-OEM-Office muss der Dialog »Vorhandenes Office steht im Weg« kommen und die
  Wahl anbieten: ebenfalls 32-Bit installieren oder erst entfernen.
- **Office entfernen**, Stufe 1. Danach nachsehen, ob wirklich nichts mehr da ist.
- Bei einem Privatkunden-Abo: **Microsoft 365 Single / Family** wählen, nicht die
  Unternehmensfassung. Genau daran scheiterte die Aktivierung bisher.

## 6. Die Zahl für das »langsamer«-Gefühl

Der Punkt, der den ganzen Audit ausgelöst hat:

1. **Vor** der Optimierung: Seite **Diagnose** → Analyse starten. Die Karte
   »Startdauer« notieren (Durchschnitt und die letzten Startvorgänge).
2. Optimierung anwenden, neu starten, ein paar Kaltstarts machen.
3. Wieder messen. Die Zahl muss gleich bleiben oder besser werden.

`perf-fast-startup-off` und `perf-startup-delay` sind in 0.4.0 **abgewählt**. Wenn du sie
bewusst anhakst, kostet der erste Punkt zehn bis dreißig Sekunden pro Kaltstart — das
steht so in der Beschreibung.

## 7. Energieplan (neu in 0.4.0, auf einem Notebook noch nie gelaufen)

Der Eintrag **»Leistung am Netz, Ausdauer auf Akku«** legt einen eigenen Energieplan an:

- Anwenden. Danach in den Windows-Energieoptionen nachsehen: gibt es den neuen Plan, ist
  er aktiv, und steht der vorherige unangetastet daneben?
- Getrennte Werte je Betriebsart prüfen — Netzteil ab, Verhalten auf Akku beobachten.
- **Zurücknehmen.** Der vorherige Plan muss wieder aktiv sein und die Kopie verschwunden.
- Zweiter Durchlauf: es darf **keine** zweite Kopie entstehen.

## 8. Akku, BitLocker, OneDrive

Auf dem Entwicklungsrechner gibt es davon nichts, geprüft ist nur der »nicht vorhanden«-Fall:

- Dashboard: Akkuverschleiß, BitLocker-Status, OneDrive-Platzhalter.
- Seite **Daten**: OneDrive **Alle Dateien herunterladen** — läuft es durch, meldet es
  den Fortschritt, bricht es sauber ab?
- **BitLocker-Schlüssel sichern** — der Dialog muss vorher deutlich sagen, dass die
  Schlüssel im Klartext auf dem Datenträger landen.

---

## Was danach passiert

Gefundene Fehler nicht sammeln, sondern einzeln beheben und committen. Nach jeder Änderung:

```bash
powershell -NoProfile -File tools\Repair-Encoding.ps1
```

Dann die Prüfwerkzeuge: `Test-Smoke`, `Test-Catalogs`, `Test-Pages`, `Test-Language`,
`Test-Undo`, `Test-Process`, `Test-Contrast`, `Test-Dialogs`, `Invoke-Analyzer`.

Fällt bei der Abnahme etwas auf, das Anwender betrifft, wird daraus **0.4.1**. Der
Abschnitt »Bekannte Grenzen« in beiden Readme-Dateien wird dann ehrlich nachgezogen —
was auf dem Laptop geprüft wurde, darf dort nicht mehr als ungetestet stehen.
