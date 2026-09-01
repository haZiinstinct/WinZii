# Abnahme auf fremder Hardware

Diese Datei ist die Übergabe an die Claude-Code-Sitzung auf dem Laptop. Sie steht im
Repo, damit dort ein `git pull` reicht.

**Warum es diese Datei gibt:** WinZii wurde auf **einem** Rechner entwickelt, auf dem
alles schon vorhanden war — winget im Suchpfad, der Zwischenspeicher gefüllt, das
elevierte Konto dasselbe wie das angemeldete. Jede `Test-Path`-Weiche trifft dort den
bequemen Zweig. Genau daraus sind die drei Symptome entstanden, die den Audit ausgelöst
haben. Alles unten ist der Teil, der auf dem Entwicklungsrechner **grundsätzlich nicht**
prüfbar ist.

Stand: **0.5.2**, veröffentlicht am 01.09.2026. Alle neun Prüfwerkzeuge grün, Sandbox-Lauf mit dem
0.5.1-Stand bestanden, Start aus sauberer Kopie mit leerem `offline\` geprüft.

> **Was die CI seither abnimmt.** Seit `.github/workflows/pruefung.yml` laufen die neun
> Werkzeuge bei jedem Push auf einem **englischen** Windows-Server, und die Oberfläche
> wird dort in beiden Sprachen gestartet und abgebildet. Damit ist der statische Teil
> von »nicht-deutsches Windows« dauerhaft gedeckt — Zahlen- und Datumsformate,
> Sprachtabellen, Kataloge, Seitenaufbau. **Was die CI nicht kann:** echte
> Windows-Werkzeuge laufen lassen. `sfc`, `DISM`, `chkdsk`, `manage-bde` und `takeown`
> geben auf einem englischen System englischen Text zurück, und WinZii wertet ihn aus.
> Genau dafür ist Punkt 13 unten da.

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
| 4 — leerer Stick | **Halb.** Start aus dem entpackten 0.5.2-Archiv geprüft (01.09.): startet, `offline\` enthält nur `.gitkeep`, kein Rechnername im Archiv, winget wird gefunden. Offen bleibt die winget-Nachinstallation **ohne** Zwischenspeicher (~315 MB) und Office. |
| 5 — OEM-Office | **Offen.** Auf keinem der beiden Geräte liegt ein vorinstalliertes OEM-Office; der Punkt braucht ein Kundengerät. |
| 6 — Startdauer | **Erledigt** (Notebook, 0.4.1): 57,5 s im Mittel als Referenzwert. |
| 7 — Energieplan | **Erledigt** (Notebook, 0.5.1), samt Kühlungsrichtlinie und Turbo-Verhalten. |
| 8 — kleiner Bildschirm | **Erledigt** (Entwicklungsrechner, 0.5.1). `WZ_SELFTEST_SIZE` erzwingt das Format auch auf einem großen Bildschirm — bei 1092×614 und am Mindestmaß 1000×560 angesehen: Konsole startet eingeklappt, die Seitenleiste holt »Protokoll« als vierzehnten Eintrag ins Bild, keine Worttrennung mitten im Wort. Nur das Ziehen von Hand fehlt. |
| 9 — Rubrik »Sicherheit« | **Offen.** Die neun Kennungen lösen sich über `winget show` auf, installiert wurde bis heute keine. |
| 10 — Sandbox | **Halb.** Mit 0.5.2 gelaufen (01.09.): **39 Prüfungen, kein Fehler.** Diesmal war winget in der Sandbox vorhanden, deshalb wurde 7-Zip wirklich über winget installiert — von den vier erwarteten `[--]`-Zeilen bleibt nur der Drucker. Der Netzweg des Laptops bleibt ungeprüft (Sandbox dort abgeschaltet). |
| 11 — Akku, BitLocker, OneDrive | **Halb.** Der Akku ist geprüft. Ein verschlüsselter Datenträger und ein OneDrive mit Platzhaltern fehlen weiterhin — beides gibt es auf keinem der zwei Geräte. |
| 12 — Restesuche | **Erledigt** (Notebook, 0.5.1) und der ergiebigste Punkt: zwei echte Fehler. |
| 13 — englisches Windows | **Halb.** Die CI deckt den statischen Teil bei jedem Push. Dazu prüft `tools\Test-Parsers.ps1` alle neun Stellen, die Windows-Ausgaben deuten, gegen die **echten** deutschen und englischen Wortlaute — alle treffen. `DISM` und `chkdsk` werten gar keinen Text aus, sondern Rückgabewerte, und können dort nicht brechen. Offen bleibt der Lauf auf einem wirklich englischen System. |
| 14 — Sprachwechsel im Betrieb | **Erledigt** (01.09.) — **mit Befund.** `Update-WzMeasuredTexts` bewirkte nichts: zwei Hintergrundaufgaben gleichzeitig angestoßen, die zweite abgewiesen. Behoben, und `tools\Test-LanguageSwitch.ps1` prüft es seither bei jedem Push. |
| 15 — Windows 10 | **Offen.** Steht seit der ersten Fassung als Grenze im README, ein vollständiger Durchlauf fehlt. |
| 16 — schreibgeschützter Stick, FAT32 | **Halb, mit Befund.** Schreibschutz geprüft (01.09.): WinZii startet, meldet es in Konsole und auf der Protokollseite, legt nichts an. Befund: Die Ausgabeknöpfe luden weiter zum Klicken ein — jetzt abgeschaltet, wenn nichts geschrieben werden kann. FAT32 nur im Code geprüft (alle vier Zweige da, Texte in beiden Sprachen); ein FAT32-Datenträger fehlt. |
| 17 — Domänen-PC mit Richtlinien | **Offen.** Der Launcher warnt davor, geprüft ist es nie. Firmenkunden sind der Normalfall. |
| 18 — Start ohne Rechte | **Erledigt** (01.09.) — **mit Befund.** Alle fünfzehn Seiten laden sauber, aber WinZii merkte gar nicht, dass ihm die Rechte fehlen. Der Hinweis steht jetzt in den ersten Protokollzeilen, mit der Liste der betroffenen Seiten. |
| 19 — langsames Gerät | **Offen.** Alle Zeitlimits sind auf schneller Hardware gemessen. |
| 20 — fremder Virenscanner | **Offen.** Auf Neugeräten immer da, hier nie. |
| 21 — hohe Skalierung, zweiter Monitor | **Halb, ohne Befund.** 1920×1080 (200 % auf 4K), das Mindestmaß 1000×560 und ein sehr breites 2560×720 sitzen alle (01.09.). Ein zweiter Monitor mit abweichender Skalierung fehlt. |
| 22 — ARM64 | **Offen.** An zwei Stellen im Code berücksichtigt, nie auf einem Gerät gesehen. |

Was davon nur ein Kundengerät klären kann: **5** (OEM-Office), **9** (Sicherheitsprogramme
wirklich installieren), **11** (BitLocker, OneDrive), **2** (zweites Konto), **17**
(Domäne), **20** (fremder Virenscanner) und **22** (ARM64). **4** und **10** ließen sich
jederzeit nachholen — für 4 reicht ein leerer Stick, für 10 das Einschalten von Windows
Sandbox auf dem Notebook.

> **Abnahmelauf vom 01.09.2026 auf dem Entwicklungsrechner.** Abgearbeitet wurde alles,
> was ohne fremdes Gerät geht: **4** (saubere Kopie), **10** (Sandbox), **13** (Deutung
> der Werkzeugausgaben), **14**, **16** (Schreibschutz), **18** und **21**. Drei davon
> haben einen Fehler gefunden — Punkt 14, 16 und 18 —, alle drei sind behoben.
>
> Nicht möglich waren: ein wirklich englisches Windows, ein FAT32-Datenträger (dafür
> braucht es Administratorrechte für eine virtuelle Platte) und ein zweiter Monitor.

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

## 13. Englisches Windows (neu, erst seit der Mehrsprachigkeit prüfbar)

Die CI prüft bei jedem Push auf einem englischen Windows-Server, was sich ohne Eingriff
prüfen lässt. Was dort nicht geht: die **Windows-Werkzeuge wirklich laufen lassen**.
Genau dort liegt die Fehlerklasse, die in den drei Übersetzungsetappen dreimal
aufgetaucht ist — ein Vergleich gegen ein deutsches Wort, das auf Englisch nie zutrifft.

Auf einem englischen Windows, WinZii auf Englisch gestellt:

- **Diagnose → Systemdateien prüfen (sfc).** WinZii liest die Ausgabe und entscheidet
  daran, ob repariert wurde. Steht danach ein sinnvolles Urteil da, oder »unbekannt«?
- **Diagnose → Abbild prüfen (DISM)** und **chkdsk**: dasselbe.
- **Dashboard:** Aktivierung, BitLocker, Secure Boot, TPM, Datenträgerzustand. Alle fünf
  entstehen aus WMI-Werten und werden zu Sätzen — sind sie englisch und stimmen sie?
- **Reparatur → Verbindung prüfen:** Das Urteil kommt aus einer Auswertung mehrerer
  Messungen. Plausibel?
- **Deinstallieren:** Die Programmliste kommt aus der Registry und enthält englische
  Namen. Die Restesuche darf davon nicht abhängen.
- **Übergabeblatt schreiben** und ganz lesen. Kein deutsches Wort, keine deutschen
  Zahlen- oder Datumsformate.

**Worauf achten:** Ein Wert, der »n/a« zeigt, wo auf Deutsch etwas stand, ist ein Befund —
dann hat eine Abfrage eine übersetzte Zeichenkette erwartet.

## 14. Sprachwechsel mitten in der Sitzung (neu)

Aktivierung, BitLocker und Virenschutz sind fertige Sätze aus einer Messung. Sie
entstehen in der Sprache, die beim Messen galt — ein Wörterbuchtausch erreicht sie nicht.
Dafür gibt es seit 0.5.2 `Update-WzMeasuredTexts`, das nach einem Wechsel im Hintergrund
neu misst. Auf einem echten Gerät ist das nie gelaufen.

1. WinZii auf Deutsch starten, Dashboard abwarten, bis die Sicherheitskarte gefüllt ist.
2. Unten links auf Englisch umstellen.
3. Die Sicherheitskarte ansehen: Innerhalb weniger Sekunden müssen **alle fünf Zeilen**
   englisch sein — nicht nur die Beschriftungen, auch die Werte.
4. Ein Übergabeblatt schreiben und den Abschnitt »Security and disks« lesen.
5. Zurück auf Deutsch, dasselbe.

**Worauf achten:** Bleibt eine Zeile deutsch, ist das Nachziehen nicht angelaufen. Und:
Die Protokollzeilen von **vorher** bleiben in ihrer Sprache — das ist gewollt, ein
Protokoll ist ein Verlauf.

## 15. Windows 10, vollständiger Durchlauf

Die Versionsweiche greift (33 Einträge für beide Systeme, 7 nur für 11, 1 nur für 10),
aber es lief dort nie ein ganzer Ablauf. Auf einem Windows-10-Gerät einmal alles:
Dashboard, Diagnose, Optimierung anwenden **und zurücknehmen**, Bereinigung, Autostart,
Übergabeblatt.

**Worauf achten:** `priv-newsinterests-win10` ist der einzige Eintrag nur für Windows 10 —
er muss dort erscheinen und wirken. Die sieben Windows-11-Einträge dürfen **nicht**
erscheinen.

## 16. Schreibgeschützter Stick und FAT32

Beide Fälle sind im Code vorgesehen und nie ausgelöst worden.

- **Schreibschutz:** Einen Stick mit Schreibschutzschalter benutzen, oder den Ordner
  schreibgeschützt machen. WinZii muss starten, im Protokoll »der Datenträger ist
  schreibgeschützt« melden und das Protokoll im Speicher führen. Die Sprachwahl darf
  nicht abstürzen, wenn `einstellungen.json` nicht schreibbar ist.
- **FAT32:** Ein FAT32-Stick. Der Hinweis auf die 4-GB-Grenze muss kommen, bevor jemand
  Office darauf lädt — nicht erst, wenn die Datei abbricht.

## 17. Domänen-PC mit Gruppenrichtlinien

Der Launcher warnt, wenn die Ausführungsrichtlinie per Richtlinie gesetzt ist. Geprüft
wurde das nie, und Firmenkunden sind der Normalfall.

- Startet WinZii überhaupt, oder greift `-Bypass` nicht?
- **Optimierung:** Ein per Richtlinie verwalteter Wert lässt sich zwar setzen, wird aber
  bei der nächsten Richtlinienaktualisierung überschrieben. Sagt WinZii das, oder meldet
  es Erfolg?
- **Telemetrie:** `tele-diagtrack` bricht auf verwalteten Geräten die Synchronisierung
  mit Intune. Das steht in der Beschreibung — steht es deutlich genug da?
- Das Dashboard muss die Domäne statt einer Arbeitsgruppe zeigen.

## 18. Start ohne Administratorrechte

`-NoElevate` gibt es für den Selbsttest. Als Anwenderfall ist es nie betrachtet worden —
dabei landet dort jeder, der die Rechteabfrage wegklickt.

- `Start.bat -NoElevate` starten. Läuft die Oberfläche?
- Auf jede der vierzehn Seiten wechseln. Keine darf mit einer Ausnahme abbrechen.
- Etwas anstoßen, das Rechte braucht (Optimierung, Bereinigung). WinZii muss **sagen**,
  dass die Rechte fehlen — nicht stumm nichts tun und nicht »erledigt« melden.

**Worauf achten:** Genau hier lohnt sich das Auffangnetz aus 0.5.2. Fliegt etwas, muss es
im Protokoll stehen und als Dialog kommen.

## 19. Langsames Gerät: Festplatte, wenig Arbeitsspeicher

Alle Zeitlimits sind auf einem Ryzen 9 mit NVMe gemessen. Auf einem alten Gerät mit
Festplatte und 4 GB:

- Wie lange dauert es vom Doppelklick bis zum Dashboard?
- Die Bestandsaufnahme im Hintergrund: Läuft sie durch, oder greift ein Zeitlimit?
- **Deinstallieren:** Die Programmliste auf einem gewachsenen System. Wie lange?
- **Daten:** Die Profilgrößen. Auf einer Festplatte mit einem großen Profil ist das die
  langsamste Messung im ganzen Programm.

**Worauf achten:** Reagiert die Oberfläche währenddessen? Lässt sich die Bestandsaufnahme
abbrechen, oder hängt der Abbruch-Knopf?

## 20. Fremder Virenscanner

Auf Neugeräten liegt fast immer eine Norton- oder McAfee-Testfassung. Die greifen tief
ein und mögen Skripte nicht.

- Startet WinZii, oder hält der Scanner die PowerShell an?
- Die Bereinigung fasst Zwischenspeicher an, die der Scanner beobachtet.
- Das Dashboard muss den **fremden** Scanner erkennen und nicht »Defender ist aus« melden.

## 21. Hohe Skalierung und zweiter Monitor

Geprüft ist klein bei 125 %. Der andere Rand fehlt.

- **200 % Skalierung** auf einem 4K-Bildschirm: Passt das Fenster noch auf die
  Arbeitsfläche, oder wird es größer als der Bildschirm?
- Das Fenster auf einen **zweiten Monitor mit anderer Skalierung** ziehen. WPF rechnet
  dabei neu — bleiben Schriften und Abstände stimmig?
- Skalierung während des Betriebs ändern.

## 22. ARM64

An zwei Stellen ist die Architektur berücksichtigt (`Apps.ps1` beim Nachinstallieren von
winget, `Core.System.ps1` beim Paketnamen). Ein Gerät gab es nie.

- Auf einem Surface oder einem Snapdragon-Notebook: Startet WinZii unter der
  x86-Emulation?
- **winget nachinstallieren:** Wird das ARM64-Paket geholt, nicht das x64?
- **Office:** Das Bereitstellungswerkzeug hat eine eigene ARM-Fassung.


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
