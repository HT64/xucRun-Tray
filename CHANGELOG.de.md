# Änderungsprotokoll

**Sprache:** [English](CHANGELOG.md) | Deutsch

Dieses Änderungsprotokoll beschreibt ausschließlich Änderungen, die für Anwender von xucRun Tray
relevant sind. Interne Entwicklungs- und Veröffentlichungsabläufe werden nicht aufgeführt.

## [Unveröffentlicht]

## [0.9.1.1] - 2026-11-01

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.1
  aktualisiert.

## [0.9.1.0] - 2026-11-01

### Hinzugefügt

- Kontobezogene Funktionen aktivieren, reparieren, deaktivieren und prüfen jetzt die nicht erhöhte
  Windows-Anmeldeaufgabe. Dieselben Funktionen stehen über `/enable-autostart`,
  `/disable-autostart` und `/autostart-status` zur Verfügung.
- Tray-spezifische Ansichten für `/info` und `/help` wurden ergänzt. Die Untermenüs Hilfe und
  Informationen bieten jetzt getrennte Einträge für xucRun und xucRun Tray.
- Eine neue Aktion unter Protokolle öffnet das Windows-Anwendungsereignisprotokoll ohne
  Rechteerhöhung und filtert die Ansicht vorübergehend auf die Quelle `xucRunBroker`.

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.0
  aktualisiert.
- Das Untermenü Protokolle zeigt jetzt die Anzahl löschbarer Clientprotokolldateien. Das Tray liest
  die Clientprotokollierungskonfiguration bei jedem Öffnen seines Kontextmenüs neu ein und ermittelt
  die vorhandenen Protokolldateien, sodass Konfigurationsänderungen und neue Dateien ohne Neustart
  des Trays verfügbar werden.
- Die Laufzeitinformationen des Trays verwenden jetzt das gemeinsame Core-Format für Angaben zu
  Programmidentität, Sprache, Signatur, Konto, Konfiguration und Protokollierung und ergänzen den
  Zustand der Windows-Anmeldeaufgabe des aktuellen Benutzers.

## [0.9.0.3] - 2026-10-29

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.0.3
  aktualisiert.
- Das Tray liest die Client-Logging-Konfiguration jetzt bei jedem Öffnen seines Kontextmenüs neu
  ein, sodass geänderte Logverzeichnisse und neu angelegte Logdateien ohne Neustart des Trays
  verfügbar werden.
- Das Tray prüft extern geänderte Spracheinstellungen jetzt vor seinem Neustart in der neuen Sprache
  und bleibt bei einem ungültigen Wert oder einer ungültigen Ressource in der bisherigen Sprache
  aktiv.
- Der Tooltip des Symbols nennt jetzt Traykonto und Erhöhungszustand, wenn mehrere Trayinstanzen
  vorhanden sind, das Traykonto vom interaktiv angemeldeten Benutzer abweicht oder die Identität
  nicht zuverlässig bestimmt werden kann.

## [0.9.0.2] - 2026-10-23

### Hinweis

- Dies ist die erste öffentliche Veröffentlichung von xucRun Tray.

[Unveröffentlicht]: https://github.com/HT64/xucRun-Tray/compare/v0.9.1.1...HEAD
[0.9.1.1]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.1
[0.9.1.0]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.0
[0.9.0.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.3
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
