# Änderungsprotokoll

**Sprache:** [English](CHANGELOG.md) | Deutsch

Dieses Änderungsprotokoll beschreibt ausschließlich Änderungen, die für Anwender von xucRun Tray
relevant sind. Interne Entwicklungs- und Veröffentlichungsabläufe werden nicht aufgeführt.

## [Unveröffentlicht]

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

[Unveröffentlicht]: https://github.com/HT64/xucRun-Tray/compare/v0.9.0.3...HEAD
[0.9.0.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.3
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
