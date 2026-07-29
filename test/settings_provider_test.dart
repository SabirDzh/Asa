import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/app_strings.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';

void main() {
  group('SettingsProvider', () {
    late SettingsProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = SettingsProvider();
    });

    test('uses system theme by default', () {
      expect(provider.themeMode, ThemeMode.system);
    });

    test('uses Russian locale by default', () {
      expect(provider.languageCode, 'ru');
    });

    test('uses normal animation speed by default', () {
      expect(provider.animationSpeed, 1.0);
    });

    test('has no avatar by default', () {
      expect(provider.avatarPath, isNull);
    });

    test('setThemeMode switches between light, dark and system', () {
      provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isDarkMode, false);

      provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, true);

      provider.setThemeMode(ThemeMode.system);
      expect(provider.themeMode, ThemeMode.system);
    });

    test('toggleNotifications updates value', () {
      provider.toggleNotifications(false);
      expect(provider.notificationsEnabled, false);

      provider.toggleNotifications(true);
      expect(provider.notificationsEnabled, true);
    });

    test('setLanguage changes language and ignores invalid codes', () {
      provider.setLanguage('en');
      expect(provider.languageCode, 'en');

      provider.setLanguage('fr');
      expect(provider.languageCode, 'en');
    });

    test('setAnimationSpeed changes speed', () {
      provider.setAnimationSpeed(0.5);
      expect(provider.animationSpeed, 0.5);

      provider.setAnimationSpeed(2.0);
      expect(provider.animationSpeed, 2.0);
    });

    test('setAvatarPath stores and clears path', () {
      provider.setAvatarPath('/path/to/avatar.webp');
      expect(provider.avatarPath, '/path/to/avatar.webp');

      provider.setAvatarPath(null);
      expect(provider.avatarPath, isNull);
    });

    test('tr returns Russian text for ru locale', () {
      expect(provider.tr('search'), 'Поиск');
      expect(provider.tr('delete'), 'Удалить');
    });

    test('tr returns English text for en locale', () {
      provider.setLanguage('en');
      expect(provider.tr('search'), 'Search');
      expect(provider.tr('delete'), 'Delete');
    });

    test('tr returns key for missing translation', () {
      expect(provider.tr('nonexistent_key'), 'nonexistent_key');
    });

    test('ensureSyncDeviceId persists and reuses the same ID', () async {
      await provider.ready;
      final id = await provider.ensureSyncDeviceId();
      expect(id, isNotEmpty);
      expect(provider.syncDeviceId, id);

      final id2 = await provider.ensureSyncDeviceId();
      expect(id2, id);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('syncDeviceId'), id);

      final other = SettingsProvider();
      await other.ready;
      final id3 = await other.ensureSyncDeviceId();
      expect(id3, id);

      // Concurrent calls before the ID is loaded should return the same
      // in-flight future.
      final fresh = SettingsProvider();
      final f1 = fresh.ensureSyncDeviceId();
      final f2 = fresh.ensureSyncDeviceId();
      expect(identical(f1, f2), isTrue);
      await fresh.ready;
      expect(await f1, equals(await f2));
    });
  });

  group('AppStrings', () {
    test('get returns Russian value by default', () {
      expect(AppStrings.get('search', 'ru'), 'Поиск');
    });

    test('get returns English value for en', () {
      expect(AppStrings.get('search', 'en'), 'Search');
    });

    test('get falls back to Russian for unsupported language', () {
      expect(AppStrings.get('search', 'fr'), 'Поиск');
    });

    test('get returns key when translation is missing', () {
      expect(AppStrings.get('missing_key', 'ru'), 'missing_key');
    });
  });
}
