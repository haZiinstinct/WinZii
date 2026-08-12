# Änderungen

Alle nennenswerten Änderungen an WinZii. Die Fassungen folgen
[Semantic Versioning](https://semver.org/lang/de/).

## [Unveröffentlicht]

Ein vollständiger Audit, ausgelöst von drei Beobachtungen auf einem Laptop: Programme
ließen sich nicht installieren, Office nicht einrichten, und nach der Optimierung fühlte
sich das Gerät **langsamer** an. Alle drei haben dieselbe Wurzel — WinZii wurde auf genau
einem Rechner entwickelt, auf dem alles schon vorhanden war. Der winget-Zwischenspeicher
gefüllt, winget im Suchpfad, das elevierte Konto dasselbe wie das angemeldete. Jede
`Test-Path`-Weiche trifft dort den bequemen Zweig; die eigentliche Download- und
Installationslogik lief nie.

### Behoben — Programme

- **winget wurde unter fremder Elevierung nicht gefunden.** Die Auflösung kennt jetzt drei
  Wege (Suchpfad, Appx-Paket über alle Benutzer, Ordnersuche ohne feste Architektur) und
  probiert sie der Reihe nach durch, bis einer wirklich antwortet. Direkt nach der
  Einrichtung liegt im Suchpfad ein Alias, der noch gar nicht startet — daran blieb die
  Suche vorher hängen.
- **»winget gefunden« ohne jede Prüfung.** `Test-WzWinget` setzte den Zustand, ohne den
  Rückgabewert anzusehen. Native Programme werfen in PowerShell keine Ausnahme, der
  `try/catch` allein prüfte also nichts.
- **Rückgabewerte von winget** stehen jetzt als Katalog in `data\wingetcodes.json`: Erfolg,
  »schon vorhanden«, »Neustart nötig« (**das ist Erfolg**, galt bisher als Fehlschlag),
  Quellenfehler, Abbruch. Von rund vierzig Werten waren drei bekannt.
- **Nach der Installation wird nachgesehen** (`winget list --id --exact`), statt dem
  Rückgabewert zu glauben. Erst dann zählt ein Programm als installiert und erscheint im
  Übergabeblatt.
- **Klicks werden nicht mehr stumm verworfen.** Wer während des Startscans auf
  »Installieren« drückte, bekam nur eine Protokollzeile. Jetzt sagt ein Dialog, was gerade
  läuft — und die Knöpfe sind bis zum Ende des Scans deaktiviert.
- **Der Download-Weg ist gehärtet**: Größenprüfung, Erkennung von HTML-Fehlerseiten,
  Löschen der Teildatei bei Fehlschlag, Proxy-Anmeldung mit den Windows-Zugangsdaten.
- **Der Kunde bekommt winget mit.** `Add-AppxPackage` richtet nur für das gerade angemeldete
  Konto ein — nach der Übergabe stand der Kunde ohne da.

### Behoben — Office

- **Die Erfolgsmeldung war eine Behauptung.** Das Bereitstellungswerkzeug liefert notorisch
  Rückgabewert 0, auch wenn nichts installiert wurde, und schreibt die Wahrheit nur ins
  Protokoll — das nie gelesen wurde. Jetzt wird protokolliert (auf den Datenträger, nicht
  in `%TEMP%` des elevierten Kontos), das Protokoll auf die bekannten Fehlernummern geprüft
  und zusätzlich nachgesehen, ob Office wirklich da ist.
- **Microsoft 365 Single/Family** als Variante ergänzt. Privatkunden konnten die bisher
  installierte Unternehmensfassung **nie** aktivieren — Office blieb im Lesemodus. Das ist
  der wahrscheinlichste Grund, warum Office »nicht funktionierte«, obwohl es installiert war.
- **Bitness-Konflikt statt Abbruch.** Vorhandenes 32-Bit-OEM-Office blockiert eine
  64-Bit-Installation. Die vorhandene Bitness wird jetzt gelesen, angezeigt, und der Dialog
  bietet die Wahl: ebenfalls 32-Bit installieren oder das vorhandene zuerst entfernen.
- **Office entfernen, gestuft** — neuer Knopf. Stufe 1 sanft über dasselbe
  Bereitstellungswerkzeug (`<Remove All>` samt MSI-Altinstallationen), Stufe 2 brachial mit
  Store-Fassung, Produktschlüsseln und Ordnerresten, mit Wiederherstellungspunkt und
  doppelter Bestätigung.
- **Volumenlizenz-Schlüssel** lässt sich eingeben. Er wird erst unmittelbar vor dem Start
  eingesetzt und danach wieder aus der Datei entfernt — auf dem Datenträger bleibt er nicht.
- **Der Vorrat wird ehrlich bewertet.** Bisher galt er ab 500 MB als vollständig; ein voller
  Satz hat 2 bis 4 GB. Geprüft wird jetzt, ob die Datenablage von Office wirklich da ist.
- Maskierung für XML-Sonderzeichen (ein `&` im Pfad erzeugte unlesbares XML),
  `AllowCdnFallback="False"` gegen stilles Nachladen, Platzprüfung auf dem Systemlaufwerk,
  und die winget-Verfügbarkeit wird **vor** dem LibreOffice-Dialog geprüft.

### Behoben — die Optimierung, die bremste

- **Zwei vorausgewählte Einträge machten den Rechner langsamer** und galten als »geringes
  Risiko«. Beide sind jetzt abgewählt, als mittleres Risiko eingestuft und benennen ihren
  Preis: Ohne Schnellstart dauert jeder Kaltstart zehn bis dreißig Sekunden länger; ohne die
  Autostart-Verzögerung startet auf schwacher Hardware alles gleichzeitig mit dem Desktop.
- **Die Energieeinstellung kannte keinen Unterschied zwischen Netzteil und Akku.**
  `perf-power-high` schaltete stur auf »Höchstleistung«, und zwar für beide Betriebsarten
  gemeinsam — auf einem Notebook kostet das Laufzeit, weshalb der Eintrag abgewählt blieb und
  praktisch nie zum Einsatz kam. Dazu scheiterte er ausgerechnet dort, wo er gebraucht wird:
  Er rief `powercfg /setactive` auf eine GUID auf, die `powercfg /list` auf vielen Geräten gar
  nicht aufführt. Auf dem Testgerät liegt der Höchstleistungsplan zwar in der Registry, wählbar
  ist aber nur »Ausbalanciert«. Der Hinweis schob den Fehlschlag auf modernen Standby; dort
  traf das nicht zu, `powercfg /a` meldet klassisches S3.

  An seine Stelle tritt **»Leistung am Netz, Ausdauer auf Akku«** mit dem neuen Aktionstyp
  `powerplan`. WinZii legt einen eigenen Energieplan an und setzt darin getrennte Werte je
  Betriebsart: Am Netzteil darf der Lüfter hochdrehen, statt den Takt zu senken, und der Turbo
  greift ohne Zurückhaltung; auf Akku umgekehrt. Der vorhandene Plan wird nicht angefasst — die
  Rücknahme schaltet zurück und löscht die Kopie, in dieser Reihenfolge, weil sich ein aktiver
  Plan nicht löschen lässt. Ein zweiter Durchlauf erkennt den Plan am Namen wieder, statt eine
  weitere Kopie anzulegen. Alles läuft über GUIDs und einen selbst vergebenen Namen, damit
  nichts an der übersetzten powercfg-Ausgabe hängt: »Wechselstromeinstellung« hier,
  »AC Power Setting Index« auf einem englischen Kundengerät. Was der Eintrag **nicht** tut,
  steht ebenfalls in seiner Beschreibung — der Spitzentakt am Netz steigt nicht, der war nie
  gedeckelt.
- **Kommando-Aktionen hatten keinen ablesbaren Zustand.** `Test-WzTweakState` kannte den Typ
  `command` nicht, die Zahl prüfbarer Aktionen blieb null und die Seite meldete »unbekannt«.
  Der Katalog kann jetzt eine Prüfvorschrift (`state`) nennen, deren Ausgabe gegen ein Muster
  gehalten wird; fehlt sie, bleibt der Zustand offen, statt einen zu behaupten, der nie
  gemessen wurde. Dieselbe Prüfung trägt den neuen Energieplan-Eintrag. Kommando-Aktionen
  kennen außerdem einen `fallback`, der nach einem Fehlschlag die fehlende Voraussetzung
  schafft und den Befehl ein zweites Mal versucht.
- **Ein vorausgewählter Eintrag stand dauerhaft auf »teilweise«.** Bei `ai-copilot-policy`
  stimmten fünf von sechs Werten; den sechsten, `CopilotDisabledReason`, schreibt Windows mit
  seinem eigenen Grund um. Der Eintrag wirkte, sah in der Oberfläche aber nach halber Arbeit
  aus. Solche Werte lassen sich jetzt mit `verify: false` kennzeichnen: gesetzt werden sie
  weiterhin, als Nachweis taugen sie nicht.
- **Erfolg wurde behauptet, wo nichts geschah.** Drei Handler fangen ihre Fehler selbst ab —
  ein Eintrag, bei dem kein einziges Paket entfernt wurde, erschien trotzdem als erledigt.
- **Ohne `.reg`-Sicherung im Technikerfall.** Bei Elevierung mit einem fremden Konto lieferte
  die Pfadumschreibung `$null`, und der Export stieg kommentarlos aus — für **jeden**
  HKCU-Wert entstand keine Sicherung, während die Seite das Gegenteil versprach.
- `perf-animations-off` schrieb »Benutzerdefiniert« statt »Beste Leistung« und meldete
  trotzdem AKTIV. `Stop-Service` lief ohne Erfolgsprüfung. `requiresReboot` wurde auch bei
  fehlgeschlagenen Einträgen gesetzt.
- `Get-WzRoot` griff im Notfall eine Ebene zu tief und suchte die Kataloge unter `src\data\`,
  sobald ein Prüfwerkzeug einzelne Module einbindet statt `main.ps1` zu starten — maßgeblich
  ist jetzt der Ort der Moduldatei. Die Zustandsprüfung für App-Pakete zählt nur noch mit,
  wenn `Get-WzAppxMatches` überhaupt geladen ist, statt hart zu scheitern. `Test-Undo.ps1`
  lässt keinen leeren Ordner mit dem Rechnernamen mehr zurück.
- **Der Wiederherstellungspunkt sagt jetzt, was er kostet**: Ist der Systemschutz aus — auf
  OEM-Geräten der Normalfall —, schaltet WinZii ihn dauerhaft ein.
- Der Bestätigungsdialog zeigt, **welche** Werte und Dienste angefasst werden.

### Neu — Rubrik »Sicherheit« im Programmkatalog

Neun Einträge, jede Paketkennung gegen die winget-Quellen geprüft: **AdwCleaner**
und **Malwarebytes** (aus den Techniker-Werkzeugen herübergezogen), **Emsisoft
Emergency Kit** als tragbarer Zweitscanner, **ESET AV Remover** für die Reste alter
Virenscanner, **OSArmor** als Verhaltenssperre, **DefenderUI** für die
Defender-Einstellungen hinter den Gruppenrichtlinien, **Windows Firewall Control**
und **simplewall** für ausgehende Verbindungen, **VeraCrypt** für Geräte ohne
BitLocker.

Nichts davon ist vorausgewählt, und jede Beschreibung nennt den Preis: dass
Malwarebytes als Premium-Testversion startet und 14 Tage lang ein zweiter Wächter
mitläuft, dass OSArmor auch harmlose Programme anhält, dass die Firewall-Werkzeuge
erst einmal alles blockieren.

### Behoben — sporadisch »winget nicht gefunden«

`Test-WzWinget` hängte `| Select-Object -First 1` an den Versionsaufruf. Die Auswahl
beendet die Pipeline, sobald sie ihre Zeile hat, und reißt winget mitten im Lauf ab —
der Rückgabewert ist dann -1 statt 0, je nach Zeitverhalten mal so und mal so. Die
Programmseite meldete deshalb sporadisch, winget sei nicht vorhanden, obwohl es lief.

### Behoben — Netzwerkprüfung

- **Ein Fehlalarm blockierte jede Installation.** Die Internetprüfung lief über HTTPS gegen
  die Prüfseite von Windows, die für Klartext-HTTP gedacht ist. Ergebnis: »Sicherheitszertifikat
  abgelehnt«, während im selben Lauf Dateien von Microsoft geladen wurden. Jetzt zwei Schritte:
  HTTP für die Erkennung von Anmeldeportalen, HTTPS für das, was Downloads brauchen.

### Zweisprachig

- **Die Oberfläche schaltet zwischen Deutsch und Englisch um**, sofort und ohne Neustart.
  Der Sprachknopf sitzt unten in der Seitenleiste; die Wahl liegt auf dem Datenträger, nicht
  im Benutzerprofil. Rahmen und alle dreizehn Seiten sind übersetzt — Messwerte, Dialoge und
  Protokoll folgen. Sieben weitere Sprachen sind vorbereitet.

### Schlanker

- Der nie benutzte Aktionstyp `cbsPackage` samt Handler, die feste
  Abhängigkeitsliste im winget-Bootstrap, drei tote Funktionen und vier XAML-Namen ohne
  Verweis sind entfernt. Die FAT32-Prüfung, die XML-Erzeugung und der Katalogzugriff standen
  doppelt da und sind zusammengelegt.

### Prüfwerkzeuge

- **`tools\Test-Undo.ps1`** spielt Sicherung und Rücknahme an einem eigenen
  Registry-Schlüssel durch — setzen, `.reg`-Sicherung, `undo.json`, zurücknehmen,
  Ausgangszustand. Dazu die Kommando-Aktionen an einer Wegwerfdatei statt an einer
  Systemeinstellung: Der Hauptbefehl gelingt nur, wenn der Fallback vorher die Marke
  angelegt hat — und ohne Fallback bleibt ein Fehlschlag ein Fehlschlag, damit der neue
  Zweig keine echten Fehler verschluckt. Zuletzt der Energieplan, als einziger Abschnitt mit
  einem echten Eingriff: anlegen, aktivieren, ein zweiter Durchlauf ohne weitere Kopie,
  zurücknehmen — und der vorherige Plan muss wieder aktiv, die Kopie verschwunden sein. Ohne
  Administratorrechte wird dieser Teil übersprungen statt zu scheitern. 45 Prüfungen, davon
  sieben nur mit Administratorrechten.
- **Der Sandbox-Test** deckt fünf weitere Wege ab: winget-Auffindung ohne Suchpfad, echte
  Installation samt Nachprüfung, die Rückgabewert-Tabelle gegen erfundene Codes, das Laden
  des Office-Bereitstellungswerkzeugs, und die Office-Entfernung auf einem System ohne
  Office. Er hat in diesem Durchgang zwei Fehler gefunden, die kein Standbild zeigt.

## [0.3.0] — 2026-08-04

Zwei Halbfertiges zu Ende gebaut. Zum einen war der Datenumzug nur zur Hälfte da:
WLAN-Netze, Lesezeichen, Drucker und Netzlaufwerke wanderten heraus, aber zu keinem
Export gab es ein Gegenstück. Zum anderen sammelte WinZii an mehreren Stellen Daten
ein, die anschließend niemand las.

### Neu

- **Seite »Zurückspielen«** — die fehlende Hälfte. Sie findet die Sicherungen unter
  `offline\daten`, richtet WLAN-Netze wieder ein, spielt Lesezeichen in das passende
  Browser-Profil zurück, legt Drucker an und verbindet Netzlaufwerke. Auch die Sicherung
  eines **anderen** Rechners lässt sich einspielen; sie ist in jedem Dialog ausdrücklich
  als solche benannt.

  Die Seite sagt vorher, was nicht gehen wird, statt es hinterher zu melden: fehlende
  Druckertreiber, Browser-Profile, die es auf diesem PC nicht gibt, WLAN-Netze, die ohne
  Schlüssel gesichert wurden, und ein laufender Browser, der zurückgespielte Lesezeichen
  beim Beenden wieder überschreiben würde. Eine vorhandene Lesezeichen-Datei wird vor dem
  Ersetzen als `.winzii-vorher` daneben gelegt.
- **Geräteliste sichern** auf der Datenseite. Drucker und Netzlaufwerke wurden bisher nur
  angezeigt — ohne diesen Export gab es zum Zurückspielen überhaupt keine Daten.
- **Dateiumzug** — kopiert die persönlichen Ordner eines Kontos mit `robocopy` auf ein
  anderes Laufwerk. Das Systemlaufwerk fällt als Ziel weg, denn eine Sicherung auf dieselbe
  Platte überlebt weder eine Neuinstallation noch einen Plattendefekt. Gekennzeichnet wird,
  was schiefgehen kann: zu wenig Platz, FAT32 mit seiner 4-GB-Grenze, und der
  WinZii-Datenträger selbst, auf den Kundendaten nicht gehören. Weder `/MOVE` noch `/MIR`
  noch `/PURGE` kommen vor — die Quelle bleibt vollständig erhalten.
- **OneDrive herunterladen.** Bisher warnte WinZii nur vor Platzhaltern. Jetzt löst es
  »Immer auf diesem Gerät behalten« aus und wartet auf den Abschluss. Ohne laufenden
  OneDrive-Dienst passiert nichts, und genau das steht dann da; bleibt die Zahl der
  Platzhalter eine Minute lang stehen, wird das gemeldet statt weiter gewartet.

### Sichtbar gemacht, was schon gemessen wurde

- **Das Dashboard kennt jetzt die eigenen Empfehlungen.** Platte über 90 % voll,
  Virenschutz veraltet, Windows nicht aktiviert, Datenträger meldet einen Fehler,
  Notebook unverschlüsselt, Akku verschlissen — diese Sätze entstanden bisher nur beim
  Drucken des Übergabeblatts.
- **Startdauer im Diagnosebericht**: Durchschnitt, die letzten Startvorgänge aufgeteilt in
  Windows selbst und Autostart, und die Bremser mit Namen und Sekunden.
- **Zuverlässigkeitsverlauf** — Abstürze, Programmfehler und Installationen als Zeitleiste.
  Beantwortet die Frage, ob ein Problem mit einer Installation zusammenfällt. Die Funktion
  dafür war fertig gebaut und hatte null Aufrufer.
- **Einzelposten im Übergabeblatt**: nicht mehr nur »14 Programme entfernt«, sondern
  welche.
- **90-Tage-Aufteilung** bei jeder Bereinigungskategorie: »339 Datei(en), davon 125 älter
  als 90 Tage (2,8 GB)«.
- **Zuletzt benutzt** bei fremden Benutzerprofilen, ab einem Jahr als Warnung — damit keine
  40 GB Karteileichen mitkopiert werden.
- Kleinteile aus denselben Abfragen: MAC-Adresse im Geräteblatt, Druckertreiber neben dem
  Anschluss, Gerätekategorie vor jedem Treiber (aus »irgendein Treiber ist neun Jahre alt«
  wird »der **Grafik**treiber«), Balken für Akkuverschleiß und SSD-Abnutzung, und eine
  Aufrüst-Empfehlung, wenn keine SSD verbaut ist oder weniger als 8 GB Arbeitsspeicher
  stecken.

### Behoben

- **Kommazahlen erschienen mit Punkt.** »74.2 s« stand direkt neben »13,1 GB« — das sah
  nach zwei verschiedenen Programmen aus. Betroffen waren Startdauer, Treiberalter,
  BIOS-Alter, Bildschirmdiagonale, Betriebsstunden und die Dauer jeder Aufgabe.
- **`Format-WzAgo` rechnete über verstrichene Stunden** und nannte gestern 23:50 Uhr
  »heute«. Jetzt zählen Kalendertage.
- **Der Seitentest führte eine fest eingetragene Liste** und übersprang die neue Seite
  stillschweigend — er meldete weiter »alles in Ordnung«. Die Liste kommt jetzt aus dem
  Verzeichnis, in der Reihenfolge der Navigation.
- **Gerätekategorien standen in Großbuchstaben und auf Englisch** (`HIDCLASS`, `MEDIA`),
  wie eine Registry-Ausgabe. Eine Tabelle übersetzt die geläufigen; Unbekanntes wird
  durchgereicht statt geraten.
- **README**: 41 statt 40 Eingriffe, 33/7/1 statt 34/6/1 (beide Sprachfassungen).

### Vom Sandbox-Lauf und vom ausgepackten Archiv gefunden

Diese drei standen nie im Quelltext auf, sondern erst beim Probieren auf einem fremden
System und beim Start aus dem fertigen ZIP:

- **Die Seite »Zurückspielen« lief auf einen Fehler, wenn noch nichts gesichert war** —
  also beim allerersten Start von einem frisch ausgepackten Stick. `@($null)` ist ein
  einelementiges Feld, aber PowerShell lehnt es an einem Pflichtparameter als NULL ab.
  Dieselbe Falle steckte in der Programmseite, wenn kein Programm gefunden wurde.
- **Drucker ließen sich nicht anlegen, wenn ihr Treiber noch nicht eingerichtet war** —
  der Normalfall nach einer Neuinstallation. WinZii holt ihn jetzt aus dem Treiberspeicher
  von Windows, bevor es aufgibt, und nennt bei einem Fehlschlag den Grund.
- **`Add-PrinterPort` wurde auf Anschlüsse angesetzt, die sich gar nicht anlegen lassen.**
  `USB001`, `PORTPROMPT:` oder `DOT4_001` entstehen mit dem Gerät, nicht auf Zuruf; der
  Versuch endete in einer nichtssagenden Windows-Meldung. Netzwerkdrucker über eine
  IP-Adresse legt WinZii vollständig an, alles andere wird übersprungen und im Ergebnis
  ausdrücklich benannt. Scheitert das Anlegen danach doch, wird der eben erzeugte
  Anschluss wieder entfernt statt als Karteileiche zurückzubleiben.

### Aufgeräumt

- `New-WzCard` war gebaut und hatte null Aufrufe — Optimierung, Bereinigung und Programme
  bauten dieselbe Karte je von Hand.
- Der Sandbox-Selbsttest prüft jetzt auch das Zurückspielen: Sicherung finden, WLAN-Profil
  lesen, einen Netzwerkdrucker anlegen und beim zweiten Lauf nicht doppelt, einen
  USB-Anschluss ehrlich ablehnen, und einen echten robocopy-Durchlauf samt Unterordnern.
- `README.en.md` fehlte im Release-Archiv — wer das ZIP auspackte, fand nur die deutsche
  Fassung.

## [0.2.2] — 2026-08-03

Erster Testlauf in der Windows Sandbox — auf einem frisch aufgesetzten Windows, das
nichts von diesem Projekt weiß. Er hat auf Anhieb zwei echte Fehler gefunden.

### Behoben

- **Die winget-Nachinstallation scheiterte** — genau der Fall, für den sie da ist. Der
  App Installer verlangt inzwischen zusätzlich die **WindowsAppRuntime**, die in der fest
  eingetragenen Abhängigkeitsliste fehlte; die Installation brach mit `0x80073CF3` ab.
  Die Abhängigkeiten kommen jetzt als versionsgleiches Paket aus demselben Release wie
  der App Installer selbst und wachsen damit automatisch mit. Die alte Liste bleibt als
  Rückfall. In der Sandbox nachgewiesen: winget v1.29.280 läuft danach.
- **Die Netzwerk-Diagnose blieb am Router hängen**, wenn dieser keine Ping-Anfragen
  beantwortet — bei Firmen-Gateways und virtuellen Netzen der Normalfall. Sie meldete
  »Es hängt bei: Router«, während daneben Downloads liefen. Ein stummer Router ist jetzt
  nur noch ein Hinweis; ob wirklich etwas klemmt, entscheiden Namensauflösung und
  Internetzugang. Schlagen beide fehl, wird der Router weiterhin benannt.

### Neu

- **`tools\Test-Sandbox.wsb`** — Selbsttest, der beim Öffnen der Sandbox von selbst
  losläuft: Smoke-Test, Start über den Launcher mit Bildschirmabbild, echte Optimierungen
  anwenden, Registry nachlesen und zurücknehmen, Netzwerk-Diagnose und
  winget-Nachinstallation. Bericht und Abbild landen unter `sandbox-ergebnis\<Zeit>\` und
  überleben das Schließen der Sandbox.

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
