# Abnahme auf fremder Hardware

Diese Datei ist die Übergabe an die Claude-Code-Sitzung auf dem Laptop. Sie steht im
Repo, damit dort ein `git pull` reicht.

**Warum es diese Datei gibt:** WinZii wurde auf **einem** Rechner entwickelt, auf dem
alles schon vorhanden war — winget im Suchpfad, der Zwischenspeicher gefüllt, das
elevierte Konto dasselbe wie das angemeldete. Jede `Test-Path`-Weiche trifft dort den
bequemen Zweig. Genau daraus sind die drei Symptome entstanden, die den Audit ausgelöst
haben. Alles unten ist der Teil, der auf dem Entwicklungsrechner **grundsätzlich nicht**
prüfbar ist.

Stand: **0.5.1** — im Quelltext, im Changelog und in beiden Readme-Dateien. Der letzte
Tag ist `v0.5.0`, das letzte Release ebenfalls: **0.5.1 ist noch nicht veröffentlicht.**
Alle neun Prüfwerkzeuge grün, Sandbox-Lauf mit dem 0.5.1-Stand bestanden, Start aus
sauberer Kopie mit leerem `offline\` geprüft.

Im Lauf zu 0.5.1 sind sechs Punkte auf einem zweiten Notebook abgearbeitet — Punkt 12
hat dabei zwei Fehler gefunden, beide behoben. Damit hier niemand nachzählen muss, was
noch aussteht, stehen **alle zwölf** Punkte in einer Tabelle. Zwei davon fehlten in der
ersten Fassung dieser Übersicht ganz — sie sind nie abgearbeitet worden, standen aber
auch nicht als offen da:

| Punkt | Stand |
| --- | --- |
| 1 — winget nach Neuanmeldung | **Erledigt** (Notebook, 0.5.1). |
| 2 — fremdes Konto | **Offen.** Es gab kein zweites Technikerkonto zum Elevieren. |
| 3 — WLAN statt Kabel | **Erledigt** (Notebook, 0.5.1): 93 MB in 32 s, Installation samt Nachprüfung. |
| 4 — leerer Stick | **Halb.** Der echte Downloadweg lief (`offline\` war leer), aber winget war schon eingerichtet — die Nachinstallation ohne Zwischenspeicher (~315 MB) steht weiter aus, ebenso Office. |
| 5 — OEM-Office | **Offen.** Auf keinem der beiden Geräte liegt ein vorinstalliertes OEM-Office; der Punkt braucht ein Kundengerät. |
| 6 — Startdauer | **Erledigt** (Notebook, 0.4.1): 57,5 s im Mittel als Referenzwert. |
| 7 — Energieplan | **Erledigt** (Notebook, 0.5.1), samt Kühlungsrichtlinie und Turbo-Verhalten. |
| 8 — kleiner Bildschirm | **Erledigt** (Entwicklungsrechner, 0.5.1). `WZ_SELFTEST_SIZE` erzwingt das Format auch auf einem großen Bildschirm — bei 1092×614 und am Mindestmaß 1000×560 angesehen: Konsole startet eingeklappt, die Seitenleiste holt »Protokoll« als vierzehnten Eintrag ins Bild, keine Worttrennung mitten im Wort. Nur das Ziehen von Hand fehlt. |
| 9 — Rubrik »Sicherheit« | **Offen.** Die neun Kennungen lösen sich über `winget show` auf, installiert wurde bis heute keine. |
| 10 — Sandbox | **Halb.** Auf dem Notebook nicht möglich, Windows Sandbox ist dort nicht eingeschaltet (`Containers-DisposableClientVM: Disabled`). Auf dem Entwicklungsrechner ist der 0.5.1-Stand gelaufen: 39 Prüfungen grün. Der Netzweg des Laptops bleibt ungeprüft. |
| 11 — Akku, BitLocker, OneDrive | **Halb.** Der Akku ist geprüft. Ein verschlüsselter Datenträger und ein OneDrive mit Platzhaltern fehlen weiterhin — beides gibt es auf keinem der zwei Geräte. |
| 12 — Restesuche | **Erledigt** (Notebook, 0.5.1) und der ergiebigste Punkt: zwei echte Fehler. |

Was davon nur ein Kundengerät klären kann: **5** (OEM-Office), **9** (Sicherheitsprogramme
wirklich installieren), **11** (BitLocker, OneDrive) und **2** (zweites Konto). **4** und
**10** ließen sich dagegen jederzeit nachholen — für 4 reicht ein leerer Stick, für 10 das
Einschalten von Windows Sandbox auf dem Notebook.

> **`main` ist weiter als der Tag.** Auf dem Entwicklungsrechner wird parallel gearbeitet.
> Vor dem ersten Commit hier immer `git pull --rebase origin main` — sonst wird der Push
> abgewiesen, und zwei Stände laufen auseinander.

---

## So anfangen

```bash
git clone git@github.com:haZiinstinct/WinZii.git && cd WinZii
```

Dann Claude Code in diesem Ordner starten und diese Datei nennen. Vor dem ersten Eingriff:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-Smoke.ps1
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
  liegen. In 0.3.0 entstand dort für **keinen** HKCU-Wert eine Sicherung — behoben in
  0.4.0, aber nur auf diesem Rechner nachgestellt, nie unter echter fremder Elevierung.
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

Der Eintrag **»Leistung am Netz, Ausdauer auf Akku«** (`perf-power-profile`, Kategorie
Geschwindigkeit) legt einen eigenen Energieplan an. Er ist **nicht vorausgewählt** — zum
Prüfen von Hand anhaken:

- Anwenden. Danach in den Windows-Energieoptionen nachsehen: gibt es den neuen Plan, ist
  er aktiv, und steht der vorherige unangetastet daneben?
- Getrennte Werte je Betriebsart prüfen — Netzteil ab, Verhalten auf Akku beobachten.
- **Zurücknehmen.** Der vorherige Plan muss wieder aktiv sein und die Kopie verschwunden.
- Zweiter Durchlauf: es darf **keine** zweite Kopie entstehen.

## 8. Die Oberfläche auf dem kleinen Bildschirm

Auf dem Entwicklungsrechner ist die Arbeitsfläche groß, das Fenster startet groß — die
Anpassungen für niedrige Bildschirme laufen dort nie an. Auf einem 1366×768-Gerät bei
125 % Skalierung sind es logisch 1092×614, knapp über dem Mindestmaß 1000×560.

Dafür gibt es die Prüfhilfe aus 0.4.1 — sie erzwingt genau dieses Format, auch auf einem
großen Bildschirm, ohne dass an der Skalierung von Windows gedreht werden muss:

```bat
cmd /c "set WZ_SELFTEST_SIZE=1092x614 && Start.bat"
```

- **Startet die Konsole eingeklappt?** Unter 700 px Fensterhöhe soll sie das. Steht in
  der Klappzeile »eingeklappt« und ist darüber die ganze Seite zu sehen — oder frisst
  die Konsole die halbe Höhe?
- **Ein Klick auf die Klappzeile** muss sie wieder aufziehen.
- **Seitenleiste:** Auf »Protokoll« oder »Reparatur« wechseln. Ist der aktive Eintrag
  sichtbar und markiert, oder bleibt die Leiste oben stehen?
- **Dashboard:** Werden Wörter mitten durchtrennt (»Systemlaufwe rk«)? Fluchten die
  Werte innerhalb einer Karte?
- Fenster von Hand kleiner ziehen bis zum Mindestmaß — bleibt alles erreichbar?

## 9. Rubrik »Sicherheit« (neu in 0.4.0, nie installiert)

Neun Einträge, alle nur auf ihre Paketkennung geprüft — installiert wurde keiner:

- **AdwCleaner** und **Emsisoft Emergency Kit** sind harmlos und schnell: einmal
  installieren, einmal starten, wieder deinstallieren.
- **OSArmor** ist der heikle: eine Verhaltenssperre, die auch harmlose Programme anhält.
  Nur auf einem Gerät ausprobieren, auf dem das egal ist — und die Beschreibung im
  Katalog daran messen, ob sie ehrlich genug ist.
- **ESET AV Remover** nur anfassen, wenn wirklich Reste eines alten Virenscanners da sind.
- Bei **Windows Firewall Control** und **simplewall** gilt dasselbe: Sie blockieren erst
  einmal alles. Nicht auf einem Gerät, das gleich beim Kunden steht.

## 10. Sandbox mit dem Netzweg dieses Geräts

`tools\Test-Sandbox.wsb` läuft auch hier — dann über die Verbindung des Laptops statt über
die des Entwicklungsrechners. Das war im Plan ausdrücklich vorgesehen, weil der Sandbox-Lauf
in diesem Projekt bisher sieben echte Fehler gefunden hat.

Vier Zeilen sind dort **erwartet** und keine Fehler. Sie stehen als `[--]` im Bericht,
werden also berichtet statt bewertet:

| Zeile | Warum |
| --- | --- |
| `winget antwortet erst nach einer Neuanmeldung` | Ein frisch registriertes Paket startet vorher nicht, und in der Sandbox lässt sich nicht neu anmelden. |
| `winget antwortet noch nicht (siehe Abschnitt 5)` | Dieselbe Ursache, im späteren Abschnitt nochmals vermerkt. |
| `7-Zip-Installation übersprungen` | Folgt aus den beiden darüber. |
| `Drucker anlegen (nur berichtet)` | Ob `Add-Printer` gelingt, entscheidet der Treiber; die Sandbox bringt keinen mit, der sich von Hand verwenden lässt. |

Der WLAN-Punkt ist dagegen ein **bestandener** Test: In der Sandbox läuft kein
WLAN-Dienst, und geprüft wird genau, dass WinZii den Fehlschlag sauber meldet statt
abzustürzen — `[ok] WLAN-Rückspielung meldet ein Ergebnis`.

Auf dem Laptop können die winget-Zeilen anders ausfallen, wenn dort vorher schon ein
App Installer eingerichtet war. Dann ist es ein `[ok]` — auch gut.

## 11. Akku, BitLocker, OneDrive

Auf dem Entwicklungsrechner gibt es davon nichts, geprüft ist nur der »nicht vorhanden«-Fall:

- Dashboard: Akkuverschleiß, BitLocker-Status, OneDrive-Platzhalter.
- Seite **Daten**: OneDrive **Alle Dateien herunterladen** — läuft es durch, meldet es
  den Fortschritt, bricht es sauber ab?
- **BitLocker-Schlüssel sichern** — der Dialog muss vorher deutlich sagen, dass die
  Schlüssel im Klartext auf dem Datenträger landen.

## 12. Restesuche nach dem Deinstallieren (neu in 0.5.0)

Der einzige Pfad in WinZii, der Ordner **endgültig** löscht — ohne Sicherung, ohne
Rücknahme. `tools\Test-Undo.ps1` Abschnitt 8 prüft die Regeln und die ganze Kette an
einem Wegwerf-Programm; was dort nicht geht, ist die Begegnung mit echten
Deinstallierern. Genau die gehört hierher.

> **Der Lauf zu 0.5.1 hat hier zwei Fehler gefunden**, beide behoben und beide in
> Abschnitt 8 des Selbsttests festgehalten: Der eingetragene Installationsordner wurde
> ungeprüft übernommen, auch wenn dort noch andere Programme wohnten (Adobe trägt für
> Audition und Premiere `C:\Program Files\Adobe` ein — 20 GB, sechs Programme). Und eine
> gelungene Deinstallation galt als gescheitert, weil der Deinstallierer eine Sekunde
> nach seinem eigenen Rückgabewert fertig wurde; die Restesuche lief dann gar nicht erst
> an. Wer den Punkt erneut abarbeitet, sollte beides gezielt gegenprüfen.

Zuerst der Blick ohne Eingriff: Seite **Deinstallieren** (seit 0.5.0 ein eigener
Eintrag in der Seitenleiste), ein beliebiges Programm auswählen und `Start.bat -DryRun`
laufen lassen. Im Testmodus wird nichts
entfernt, aber die Fundliste steht im Protokoll.

Dann drei Fälle, in dieser Reihenfolge:

1. **Ein stiller Deinstallierer, der Reste hinterlässt.** Ein kleines Programm über die
   Seite installieren, benutzen (damit es Einstellungen anlegt), dann über WinZii
   entfernen. Der Dialog muss die Funde mit Größe zeigen. **Jeden Pfad in der Liste
   einzeln ansehen, bevor bestätigt wird** — steht dort ein Ordner, der einem anderen
   Programm gehört, ist das ein Befund und die Bestätigung bleibt aus.
2. **Ein Assistent, der weggeklickt wird.** Ein Programm ohne stillen Schalter auswählen,
   den Assistenten des Herstellers öffnen lassen und **abbrechen**. WinZii muss
   »steht weiter in der Programmliste« melden und darf **keine** Reste anbieten. Das ist
   der Fall, der ein Programm unentfernbar machen würde.
3. **Elevierung mit einem anderen Konto** (wie in Abschnitt 2). Die Programmliste muss die
   Programme des angemeldeten Anwenders zeigen, nicht die des Technikerkontos — erkennbar
   an der Spalte »nur dieses Konto«. Ein Rest darf niemals im Profil des Technikers liegen.

Danach die Sicherung nachsehen: unter `backups\<rechnername>\<zeitstempel>-Programmreste`
müssen `undo.json` und je entferntem Schlüssel eine `.reg`-Datei liegen, und der Eintrag
muss auf der Seite **Rücknahme** auftauchen.

---

## Was danach passiert

Gefundene Fehler nicht sammeln, sondern einzeln beheben und committen. Nach jeder Änderung:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Repair-Encoding.ps1
```

Dann die Prüfwerkzeuge: `Test-Smoke`, `Test-Catalogs`, `Test-Pages`, `Test-Language`,
`Test-Undo`, `Test-Process`, `Test-Contrast`, `Test-Dialogs`, `Invoke-Analyzer`.

Fällt bei der Abnahme etwas auf, das Anwender betrifft, wird daraus **0.5.1**. Der
Abschnitt »Bekannte Grenzen« in beiden Readme-Dateien wird dann ehrlich nachgezogen —
was auf dem Laptop geprüft wurde, darf dort nicht mehr als ungetestet stehen.
