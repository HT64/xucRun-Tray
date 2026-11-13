# Änderungsprotokoll

**Sprache:** [English](CHANGELOG.md) | Deutsch

Dieses Änderungsprotokoll beschreibt ausschließlich Änderungen, die für Anwender von xucRun Tray
relevant sind. Interne Entwicklungs- und Veröffentlichungsabläufe werden nicht aufgeführt.

## [Unveröffentlicht]

## [0.9.1.7] - 2026-11-13

### Geändert

- Hinweise zu Lizenzbedingungen, Sicherheit und Projektstatus in Installer und Dokumentation aktualisiert;
  die Hinweise von Tray an xucRun angeglichen.
- Der Installer legt die Lizenz- und Urheberhinweise im Unterverzeichnis `Licenses` ab.
- Der grafische Installer zeigt Lizenztext, Urheberhinweise sowie Status- und Sicherheitshinweise
  offline auf eigenen Registerkarten an und verlangt bei jeder Installation oder Aktualisierung
  deren Bestätigung.
- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.7
  aktualisiert.

### Behoben

- Die anfängliche Sprache des Tray-Installers folgt jetzt den Windows-Sprachpräferenzen des
  interaktiv angemeldeten Benutzers.

## [0.9.1.6] - 2026-11-10

Diese Version enthält sicherheitsrelevante Korrekturen, die alle früheren Versionen betreffen.
Die behobenen Schwächen wurden bei einer internen Sicherheitsüberprüfung gefunden; Angriffe sind
nicht bekannt. Sie lassen sich nur von Schadcode ausnutzen, der bereits auf demselben Rechner
ausgeführt wird. Eine Aktualisierung von xucRun und xucRun Tray auf diese Version wird empfohlen.

### Sicherheit

- Die temporären Arbeitskopien des Skripts zum Signieren eines Tray-Pakets sind jetzt nur noch
  für Administratoren und SYSTEM zugänglich.
- xucRun Tray und sein Installer wurden zusätzlich gegen manipulierte lokale Umgebungen
  gehärtet.

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.6
  aktualisiert.

## [0.9.1.5] - 2026-11-09

### Hinzugefügt

- Solange mindestens ein verfolgter Prozess als `LocalSystem` oder mit der
  TrustedInstaller-Identität läuft, beginnt jeder Eintrag unter **Erhöhte Prozesse** mit seiner
  vom Broker validierten Identität: `[ADM]` und dem Kontonamen für einen erhöhten
  Administrator, `[SYS] SYSTEM` für `LocalSystem` oder `[TI] TrustedInstaller`. Andernfalls
  bleiben die Einträge kompakt; nur Prozessen eines anderen Kontos als dem des angemeldeten
  Benutzers wird dessen Kontoname vorangestellt.
- Solange ein verfolgter Prozess mit TrustedInstaller-Identität ein sichtbares Hauptfenster
  besitzt, pulsiert das rote Warnsymbol einmal pro Sekunde. Gewöhnliche erhöhte und
  `LocalSystem`-Fenster halten das Symbol durchgehend rot.

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.5
  aktualisiert.
- Die Dokumentation erklärt jetzt, welche Prozesse die Liste **Erhöhte Prozesse** enthält, dass
  sie keine systemweite Übersicht aller erhöhten oder SYSTEM-Prozesse ist und dass Prozesse ohne
  geeignetes sichtbares Fenster als ausgegraute Einträge mit dem Zusatz `kein Fenster`
  erscheinen.

## [0.9.1.4] - 2026-11-07

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.4
  aktualisiert.

## [0.9.1.3] - 2026-11-04

### Geändert

- Die Kompatibilitätsanforderung des Tray-Pakets und -Installers wurde auf xucRun Core 0.9.1.3
  aktualisiert.
- Der Titel der Tray-Laufzeitinformationen enthält jetzt den Computernamen; die Dokumentation
  zeigt die aktuelle Laufzeitinformationsansicht.
- Die Dokumentation stellt jetzt klar, dass xucRun ohne Tray funktioniert, und beschreibt das
  Deaktivieren beziehungsweise erneute Aktivieren des Tray-Starts bei der Windows-Anmeldung sowie
  das manuelle Beenden und erneute Starten des Trays.

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

[Unveröffentlicht]: https://github.com/HT64/xucRun-Tray/compare/v0.9.1.7...HEAD
[0.9.1.7]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.7
[0.9.1.6]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.6
[0.9.1.5]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.5
[0.9.1.4]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.4
[0.9.1.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.3
[0.9.1.1]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.1
[0.9.1.0]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.1.0
[0.9.0.3]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.3
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
