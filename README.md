# Pauls Raketenwerft

Ein 3D-Raketenspiel für Kinder (Godot 4.7): Rakete bauen, in den Orbit fliegen, die ISS besuchen,
sie sicher zum Punkt Nemo bringen und einmal um den Mond und zurück. Mira von der Bodenstation
erklärt dabei Raketenwissenschaft – auf Deutsch oder Englisch.

## Selbst bauen

- Spiel am Mac starten: `Godot --path .`
- iPhone/iPad (angesteckt): `tools/build_ios.sh device`
- iOS-Simulator: `tools/build_ios.sh sim` (braucht eine selbst gebaute arm64-Simulator-Bibliothek, siehe `tools/godot-ios-simulator-metal.patch`)
- TestFlight: `BUILD=<nummer> UPLOAD=1 tools/build_ios.sh testflight`

Automatisch: Jeder Push auf `main` baut die App auf GitHub Actions und lädt sie zu TestFlight hoch
(`.github/workflows/testflight.yml`, Secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`).

## Tests

- `Godot --path . -- --autotest=orbit --speed=6` – Testpilot fliegt eine Mission (`hop`, `orbit`, `moon`, …)
- `Godot --path . -- --autotest=moon --computer` – nur der Bordcomputer fliegt
- `Godot --path . -- --touchtest` – Wischen und Tippen im Baukasten

## Herkunft

Code, 3D-Modelle (Blender-Skript `tools/make_models.py`) und Geräusche (`tools/make_sfx.py`) sind selbst erzeugt.
Miras Stimme ist eine KI-Stimme (Qwen3-TTS, per Beschreibung entworfen). Schriften: Baloo 2 und eine
Teilmenge von Noto Color Emoji, beide SIL Open Font License (`fonts/`).
