# Änderungsprotokoll

**Sprache:** [English](CHANGELOG.md) | Deutsch

Dieses Änderungsprotokoll beschreibt ausschließlich Änderungen, die für Anwender von xucRun Tray
relevant sind. Interne Entwicklungs- und Veröffentlichungsabläufe werden nicht aufgeführt.

## [Unveröffentlicht]

## [0.9.0.2] - 2026-10-21

### Hinweis

- Dies ist die erste öffentliche Veröffentlichung von xucRun Tray.

### Geändert

- Der Installer passt Versionen, Zertifikatsangaben, Benutzerauswahl, Erläuterungen, Status und
  Schaltflächen nun an den tatsächlichen Inhalt an und nutzt den verfügbaren Platz kompakter.
- Die Deinstallation über Installierte Apps blendet nun das PowerShell-Fenster aus. Fehler bleiben
  in einem lokalisierten Dialog mit konkretem Diagnoseprotokoll und Ordner-Schaltfläche sichtbar.
- Eine neue deutsch- und englischsprachige Anleitung zur manuellen Entfernung inventarisiert alle
  Tray-eigenen Dateien, Prozesse, geplanten Aufgaben, Registry-Einträge und Reste abgebrochener
  Installationen und bewahrt dabei ausdrücklich den xucRun Core.
- Bei einer vorhandenen Tray-Installation zeigt der Installer nun deren registrierte Version und
  den Zeitpunkt der Installation beziehungsweise letzten Aktualisierung an.
- Der Installer prüft die installierte xucRun-Version, Signatur und Brokerbindung jetzt vor dem
  Öffnen der Oberfläche und zeigt die erfolgreich geprüfte xucRun-Version an.
- Beide Tray-Sprach-DLLs enthalten nun vollständige Windows-Dateidetails mit Beschreibung,
  Produktversion und Originaldateiname.
- Oberfläche und Erfolgsbestätigung des Installers zeigen nun Name, Gültigkeitszeitraum und
  Fingerabdruck des Core-Zertifikats, mit dem die Tray-Dateien signiert werden.

### Behoben

- Die Installation signiert unsignierte Dateien aus einem öffentlichen Tray-Paket nun mit dem
  installierten xucRun-Zertifikat, statt sie bereits vor der Signierung abzulehnen.
- Die Paketprüfung lehnt inkonsistente Signaturen von Installer und Payload nun ab.
- xucRun Tray aktualisiert seinen Brokerstatus nach einer Core-Installation beziehungsweise einer
  Neuerstellung des Brokerdienstes wieder automatisch.
- Bei der Einrichtung eines weiteren Benutzers werden zuvor laufende Tray-Instanzen nach dem
  erforderlichen Dateiaustausch wieder gestartet.
- Die Tray-Deinstallation zeigt nun eine lokalisierte Erfolgsbestätigung mit den entfernten und
  den ausdrücklich unveränderten Core-, Zertifikats- und Benutzerdaten.

[Unveröffentlicht]: https://github.com/HT64/xucRun-Tray/compare/v0.9.0.2...HEAD
[0.9.0.2]: https://github.com/HT64/xucRun-Tray/releases/tag/v0.9.0.2
