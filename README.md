# Klinker

![Klinker, erste Runde](bilder/spiel.png)

Klinker ist ein Breakout für den Mac. Es läuft nativ, mit eigenen Bildern und eigenem Ton. 208 feste Runden, nach jeder vierten eine Bonusrunde. Im Startmenü gibt es Spielerprofile und die Stufen Kinder, Leicht, Mittel und Schwer.

Ab macOS 13.

## Herunterladen

Die Apps liegen unter [Releases](https://github.com/msebastian100/Klinker/releases).

- **Klinker (M-Serie)** für Apple Silicon
- **Klinker (Intel)** für Intel-Macs
- **Klinker** als Universal-App für beide

Beim ersten Öffnen: Rechtsklick auf die App, dann Öffnen.

## Steuerung

| Taste | Wirkung |
| --- | --- |
| Leertaste, Enter oder Klick | Ball starten |
| Maus | Schläger, wenn Maus gewählt ist |
| Pfeile links und rechts, oder A und D | Schläger, wenn Tasten gewählt sind |
| P oder Escape | Pause |
| M | Ton an oder aus |
| F | Vollbild |
| Befehl-E | Spielerauswahl |
| Befehl-N | Neues Spiel |
| N im Startmenü | Neues Spiel für den gewählten Spieler |
| Escape im Startmenü | Zurück zur laufenden Runde |

Maus oder Tasten stellst du im Spiel an der Seite um. Ein Controller geht zusätzlich. Der Stand wird beim Schließen und zwischendurch gespeichert.

## Bauen

Xcode-Befehlszeilenwerkzeuge und Python 3.

```bash
bash build.sh
```

Danach liegen die drei Apps in `dist/`.
