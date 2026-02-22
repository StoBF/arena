# Arena Manager Client

This is the client for the Arena Manager game, built with Godot Engine.

## Project Structure

```
client/
├─ assets/                # Graphics, fonts, sprites, icons
├─ locales/               # JSON translation files
│   ├─ en.json
│   ├─ pl.json
│   └─ uk.json
├─ scenes/                # TSCN files for each UI scene
├─ scripts/               # GDScript files
├─ autoload/              # Autoload singletons
├─ export_presets.cfg     # Export profiles
└─ project.godot          # Godot project file
```

## How to Run

1. Open the `client` folder in Godot Engine.
2. Ensure autoload singletons `Network.gd` and `Localization.gd` are enabled in Project Settings > Autoload.
3. Set the `Server IP` in `Network.gd`.
4. Run the project; the Login scene is the main entry.

## Localization

Translations are stored in `locales/{code}.json`. To add or change a locale:

1. Edit or create a new JSON file in `locales/`.
2. Use the `Localization.t(key)` method in scripts to retrieve translated text.

## Exporting

Use the `export_presets.cfg` file to export builds for Desktop and Android.

- Windows Desktop: `res://builds/windows/Arena_manager.exe`
- Linux Desktop: `res://builds/linux/Arena_manager.x86_64`
- Android: `res://builds/android/Arena_manager.apk`

For Mobile, ensure you have the Android SDK installed and configured in Godot Editor. 