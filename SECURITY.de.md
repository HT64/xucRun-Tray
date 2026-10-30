<!--
Purpose: Definiert unterstützte Versionen und den vertraulichen Meldeweg für Schwachstellen.
Approach: Trennt öffentliche Versionsunterstützung von privaten Meldeschritten und Reaktionshinweisen.
-->
# Sicherheitsrichtlinie

**Sprache:** [English](SECURITY.md) | Deutsch

## Unterstützte Versionen

Nach der ersten öffentlichen xucRun-Tray-Veröffentlichung wird ausschließlich die neueste
veröffentlichte Version unterstützt.

Vor der ersten Veröffentlichung wird keine öffentliche Version unterstützt.

## Schwachstelle melden

Ungepatchte oder vermutete Schwachstellen dürfen nicht in einem öffentlichen Issue, einer
Discussion, einem Pull Request oder einem anderen öffentlichen Kanal gemeldet werden.

Verwende GitHub Private Vulnerability Reporting für `HT64/xucRun-Tray`:

1. Öffne im Repository den Bereich **Security**.
2. Wähle **Report a vulnerability**.
3. Beschreibe die betroffene Version oder den Commit, Reproduktionsschritte, erwartete Auswirkungen
   und bekannte Gegenmaßnahmen.

Wenn das Problem die Verbindung zwischen xucRun Tray und dem xucRun-Hauptprogramm oder Broker
betrifft und die verursachende Komponente noch unklar ist, kann es vertraulich über
`HT64/xucRun-Tray` gemeldet werden. Sicherheitsprobleme, die nachweislich ausschließlich das
xucRun-Hauptprogramm oder den Broker betreffen, sollten über das Private Vulnerability Reporting
von `HT64/xucRun` gemeldet werden.

Übermittle nur sensible Daten, die zum Verständnis erforderlich sind. Reale Kennwörter, private
Schlüssel, Zugriffstoken und nicht betroffene personenbezogene Daten dürfen nicht eingereicht
werden.

Reaktions- und Behebungszeiten hängen von Reproduzierbarkeit, Schwere und Implementierungsrisiko
ab. Diese Richtlinie verspricht weder ein festes Serviceniveau noch eine
Schwachstellenprämie.

## Geltungsbereich

Diese Richtlinie gilt für Quellcode und veröffentlichte Pakete aus `HT64/xucRun-Tray`. Das
xucRun-Hauptprogramm, Software Dritter und veränderte Builds liegen außerhalb des
Unterstützungsumfangs dieses Repositorys. Die vom Tray verwendete, eingeschränkte
Broker-Schnittstelle gehört zum Geltungsbereich, soweit das gemeldete Verhalten durch das Tray
oder seine Verwendung dieser Schnittstelle verursacht wird.
