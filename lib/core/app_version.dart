/// Единственный источник версии приложения в Dart-коде.
///
/// Вся сборка (см. `scripts/build.sh` и `scripts/release.sh`) передаёт версию
/// через `--dart-define=APP_VERSION`, а [appVersion] — единственное место,
/// где версия задаётся по умолчанию. Значение здесь должно совпадать с
/// `version:` в `pubspec.yaml`; при релизе его обновляет `scripts/release.sh`.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.2.7',
);
