# Fragenkatalog zum Audit 2026-10

Entscheidungen, die beim Abarbeiten von [AUDIT-2026-10-AUFGABEN.md](AUDIT-2026-10-AUFGABEN.md) ohne Rückfrage getroffen wurden, weil der Auftraggeber unterwegs war. Zu jeder Frage steht die **gewählte Annahme**, nach der umgesetzt wurde. Wer anders entscheidet, schreibt die Antwort darunter; die Kennung zeigt, wo im Code nachzuziehen ist.

Dazu die Punkte, die sich nicht vom Schreibtisch aus erledigen lassen (»Selbst zu tun«).

---

## Offene Fragen

## Selbst zu tun

- **H6 — Offline-Abnahme des Programme-Vorrats.** Auf einem Gerät ohne Netz einmal ein Programm aus dem Stick-Vorrat installieren und prüfen, ob `winget install --manifest` die Datei neben dem Manifest nutzt. Ergebnis in `docs/ABNAHME.md` eintragen, dann H6 in der Abhakliste schließen.
- **M8 — Aussteller nachtragen.** Nur 15 Programme haben einen hinterlegten Aussteller (`signers` in `data/apps.json`). Für die übrigen installiert WinZii nicht aus dem Vorrat, sondern online. Nachtragen: auf dem eigenen Rechner vorabladen, `tools\Get-VaultSigners.ps1` ausführen, vorgeschlagene Zeilen übernehmen.
