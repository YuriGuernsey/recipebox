# Godot Launchpad

Godot Launchpad is a desktop version manager for Godot. It checks the latest
stable Godot releases, installs the selected version in the background, keeps a
managed install folder, and launches Godot without sending the user through a
browser download flow.

## Highlights

- Auto-detects current stable Godot releases from `godotengine/godot`.
- Installs and extracts Godot inside the app.
- Remembers the default install folder, launch arguments, and installed versions.
- Launches managed Godot installs directly.
- Supports desktop builds for macOS, Windows, and Linux.

## Development

```sh
flutter test test/widget_test.dart
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 flutter build macos --debug
```
