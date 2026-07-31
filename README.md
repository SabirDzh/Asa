# ASA

ASA is an offline-first Flutter task manager with folders, drag-and-drop organization, time periods and timers, calendar integration, local notifications, Android home-screen widgets, export/import, and optional nearby-device sync.

## Supported platforms

The shared Flutter codebase targets Android, iOS, macOS, Windows, and Linux. Android home-screen widgets and some calendar/notification capabilities are platform-specific; see [`docs/DEVELOPER.md`](docs/DEVELOPER.md) before changing native integrations.

## Development

Requirements: Flutter 3.44+ and Dart 3.7+.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

For Android validation:

```bash
cd android
./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon
cd ..
flutter build apk --debug
```

For a distributable Android artifact, configure release signing through the ignored `android/key.properties` file or the `ANDROID_*` environment variables documented in [`docs/DEVELOPER.md`](docs/DEVELOPER.md). Never commit keystores or credentials.

## Documentation

- [`docs/DEVELOPER.md`](docs/DEVELOPER.md) — architecture, persistence, platform contracts, release signing, and troubleshooting.
- [`pubspec.yaml`](pubspec.yaml) — dependency constraints and app version.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
