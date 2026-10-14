# Fragenkatalog zum Audit 2026-10

Entscheidungen, die beim Abarbeiten von [AUDIT-2026-10-AUFGABEN.md](AUDIT-2026-10-AUFGABEN.md) ohne Rückfrage getroffen wurden, weil der Auftraggeber unterwegs war. Zu jeder Frage steht die **gewählte Annahme**, nach der umgesetzt wurde. Wer anders entscheidet, schreibt die Antwort darunter; die Kennung zeigt, wo im Code nachzuziehen ist.

Dazu die Punkte, die sich nicht vom Schreibtisch aus erledigen lassen (»Selbst zu tun«).

---

## Offene Fragen

### F1 — M26: Fremde Rechner auf der Zurückspielen-Seite

Das Audit schlug vor, standardmäßig nur die Sicherung des eigenen Rechners zu zeigen. Das würde den Hauptzweck brechen: alter PC sichern, neuer PC (mit anderem Namen) zurückspielen.

**Annahme:** Fremde Rechner bleiben sichtbar, die vorhandene Warnung bleibt. Gegen das eigentliche Risiko — Klartext-Schlüssel, die zum nächsten Kunden mitwandern — fragt WinZii nach dem WLAN-Import, ob die Schlüssel vom Stick gelöscht werden. Die BitLocker-Schlüsseldatei (`backups\<PC>\…-bitlocker`) bleibt unangetastet, weil sie bis zur Rückgabe des Geräts gebraucht werden kann. Offen: Soll es eine Verschlüsselung mit Techniker-Passphrase geben?

## Selbst zu tun

- **M24 — Abnahme Netzlaufwerke im Benutzerkontext.** WinZii mit einem Technikerkonto erhöhen, eine Sicherung mit Netzlaufwerk und Druckerverbindung zurückspielen: Laufwerk und Drucker müssen im Explorer des Kunden erscheinen, nicht beim Techniker. Kurz blitzt dabei kein Fenster auf (versteckte Aufgabe), sonst bitte melden.
- **H10 — Abnahme mit OneDrive-Ordnersicherung.** Auf einem Windows 11 mit aktiver Ordnersicherung die Bestandsaufnahme der Benutzerdaten öffnen: Desktop, Dokumente und Bilder müssen die OneDrive-Pfade und echte Größen zeigen, der Kopierdialog die OneDrive-Warnung. Profile anderer, nicht angemeldeter Konten zeigen weiter die Standardpfade (deren Registry-Zweig ist nicht geladen).
- **H6 — Offline-Abnahme des Programme-Vorrats.** Auf einem Gerät ohne Netz einmal ein Programm aus dem Stick-Vorrat installieren und prüfen, ob `winget install --manifest` die Datei neben dem Manifest nutzt. Ergebnis in `docs/ABNAHME.md` eintragen, dann H6 in der Abhakliste schließen.
- **M8 — Aussteller nachtragen.** Nur 15 Programme haben einen hinterlegten Aussteller (`signers` in `data/apps.json`). Für die übrigen installiert WinZii nicht aus dem Vorrat, sondern online. Nachtragen: auf dem eigenen Rechner vorabladen, `tools\Get-VaultSigners.ps1` ausführen, vorgeschlagene Zeilen übernehmen.
