# Fragenkatalog zum Audit 2026-10

Entscheidungen, die beim Abarbeiten von [AUDIT-2026-10-AUFGABEN.md](AUDIT-2026-10-AUFGABEN.md) ohne Rückfrage getroffen wurden, weil der Auftraggeber unterwegs war. Zu jeder Frage steht die **gewählte Annahme**, nach der umgesetzt wurde. Wer anders entscheidet, schreibt die Antwort darunter; die Kennung zeigt, wo im Code nachzuziehen ist.

Dazu die Punkte, die sich nicht vom Schreibtisch aus erledigen lassen (»Selbst zu tun«).

---

## Offene Fragen

### F1 — M26: Fremde Rechner auf der Zurückspielen-Seite

Das Audit schlug vor, standardmäßig nur die Sicherung des eigenen Rechners zu zeigen. Das würde den Hauptzweck brechen: alter PC sichern, neuer PC (mit anderem Namen) zurückspielen.

**Annahme:** Fremde Rechner bleiben sichtbar, die vorhandene Warnung bleibt. Gegen das eigentliche Risiko — Klartext-Schlüssel, die zum nächsten Kunden mitwandern — fragt WinZii nach dem WLAN-Import, ob die Schlüssel vom Stick gelöscht werden. Die BitLocker-Schlüsseldatei (`backups\<PC>\…-bitlocker`) bleibt unangetastet, weil sie bis zur Rückgabe des Geräts gebraucht werden kann. Offen: Soll es eine Verschlüsselung mit Techniker-Passphrase geben?

### F2 — Aufbewahrung alter Protokolle

Das Audit wollte Sitzungsordner »älter als N Tage« beim Start aufräumen, ohne N festzulegen.

**Annahme:** 90 Tage, für alle Rechner auf dem Stick, mit einer Protokollzeile über die Anzahl. Wer Protokolle als Nachweis länger braucht, ändert `Remove-WzOldLogSessions -Days` in `src\modules\Core.Logging.ps1` oder sagt Bescheid.

### F3 — H6: Der Programme-Vorrat funktioniert nicht offline

Nachgelesen (winget-cli #4358, #4361, #4500): `winget install --manifest` lädt den Installer **immer** von der `InstallerUrl` im Manifest und nimmt die Datei daneben nicht. Der Vorrat hat offline also nie funktioniert; online lädt winget dieselbe Datei neu. Dafür schaltet WinZii vorübergehend die geräteweite Einstellung `LocalManifestFiles` ein.

**Sofort umgesetzt (ohne Designänderung):** Die Netzprüfung läuft auch, wenn alles im Vorrat liegt; Oberfläche und README versprechen keine Installation ohne Internet mehr.

**Offen, deine Entscheidung:**
1. *Direkt installieren* — die signierte Datei vom Stick mit festen Schaltern je Installer-Typ aus WinZii (MSI `/qn /norestart`, Inno `/VERYSILENT …`, NSIS `/S`, Burn `/quiet`), nicht aus dem Manifest; andere Typen online. Hält das Offline-Versprechen, startet aber Dateien vom beschreibbaren Stick eleviert — die Signatur-/Ausstellerprüfung (M8) wird dann zur einzigen Schutzschicht. Ein erster Anlauf dazu wurde in dieser Sitzung vom Sicherheitsfilter angehalten; ohne dein Ja baue ich das nicht.
2. *Vorrat zurückbauen* — `--manifest`, `LocalManifestFiles` und die Manifestprüfung entfernen, alles online über winget. Am einfachsten und ehrlich, der Stick-Vorrat für Programme entfällt (Office-Vorrat bleibt, der funktioniert offline).
3. *So lassen* — wie jetzt: Vorrat bringt nichts, schadet aber auch nicht mehr, weil nichts mehr Offline verspricht.

**Annahme bis zur Antwort:** 3.

### F4 — M3: Bereits gesetzter LSA-Schutz mit UEFI-Sperre

Bis 0.7.0 setzte WinZii `RunAsPPL=1`. Auf Geräten mit Secure Boot legt Windows dabei eine UEFI-Variable an; die Rücknahme über die Registry hebt den Schutz dann **nicht** auf, das geht nur mit Microsofts »LSA Protected Process Opt-out«-Werkzeug (EFI-Start). Neu wird Wert 2 gesetzt, nur ab Windows 11 22H2; Windows 10 bietet den Eintrag nicht mehr an.

**Annahme:** Keine automatische Behandlung alter Kundengeräte. Offen: Soll die Rücknahme einen Hinweis zeigen, wenn sie `RunAsPPL=1` vorfindet?

## Selbst zu tun

- **M24 — Abnahme Netzlaufwerke im Benutzerkontext.** WinZii mit einem Technikerkonto erhöhen, eine Sicherung mit Netzlaufwerk und Druckerverbindung zurückspielen: Laufwerk und Drucker müssen im Explorer des Kunden erscheinen, nicht beim Techniker. Kurz blitzt dabei kein Fenster auf (versteckte Aufgabe), sonst bitte melden.
- **H10 — Abnahme mit OneDrive-Ordnersicherung.** Auf einem Windows 11 mit aktiver Ordnersicherung die Bestandsaufnahme der Benutzerdaten öffnen: Desktop, Dokumente und Bilder müssen die OneDrive-Pfade und echte Größen zeigen, der Kopierdialog die OneDrive-Warnung. Profile anderer, nicht angemeldeter Konten zeigen weiter die Standardpfade (deren Registry-Zweig ist nicht geladen).
- **H6 — Offline-Abnahme des Programme-Vorrats.** Auf einem Gerät ohne Netz einmal ein Programm aus dem Stick-Vorrat installieren und prüfen, ob `winget install --manifest` die Datei neben dem Manifest nutzt. Ergebnis in `docs/ABNAHME.md` eintragen, dann H6 in der Abhakliste schließen.
- **M8 — Aussteller nachtragen.** Nur 15 Programme haben einen hinterlegten Aussteller (`signers` in `data/apps.json`). Für die übrigen installiert WinZii nicht aus dem Vorrat, sondern online. Nachtragen: auf dem eigenen Rechner vorabladen, `tools\Get-VaultSigners.ps1` ausführen, vorgeschlagene Zeilen übernehmen.
- **SECURITY — Private Vulnerability Reporting einschalten.** `SECURITY.md` nennt jetzt nur noch diesen Meldeweg (es gab keine hinterlegte Mail-Adresse), im Repo ist er aber aus. Einschalten unter Settings → Code security → Private vulnerability reporting, oder:
  `gh api -X PUT repos/haZiinstinct/WinZii/private-vulnerability-reporting`
  Nicht selbst geschaltet, weil es eine Repo-Einstellung ist.
- **M39 — Sandbox-Test neu anstoßen.** Der Selbsttest läuft jetzt über `tools\Start-SandboxTest.ps1` (Kopie unter `sandbox-staging\` statt Arbeitsordner). Einmal laufen lassen und prüfen, dass die Sandbox mit dem relativen `HostFolder` `..\sandbox-staging` startet; lehnt Windows ihn ab, den vollständigen Pfad in `tools\Test-Sandbox.wsb` eintragen.
- **Stufe 5 — Abnahme auf echter Hardware.** Die Nachprüfung stützt sich auf Herstellerdoku, nicht auf einen Lauf:
  - Dell, Lenovo, HP: Herstellerwerkzeug auf einem Gerät der Marke laufen lassen (ABNAHME Punkt 24) — stimmt die Wertung der Rückgabewerte, startet Lenovo ohne Typ-1-Pakete wirklich nicht neu? Bei HP gibt es laut Doku keinen Schalter gegen den Neustart; falls HPIA doch selbst neu startet, bitte melden.
  - LTSC: winget-Nachinstallation mit Bereitstellung (`-DependencyPackagePath`) auf einem LTSC ohne Store.
  - Papierkorb unter Technikerkonto leeren: Kunde hat Dateien im Papierkorb, WinZii mit anderem Konto erhöht.
