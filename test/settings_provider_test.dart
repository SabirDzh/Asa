import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/app_strings.dart';
import 'package:asa/core/theme.dart';
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

    test('uses the base color palette by default', () {
      expect(provider.colorPalette, ColorPalette.base);
      expect(provider.appPalette, AppPalette.base);
    });

    test('persists built-in ocean palette', () async {
      await provider.ready;
      await provider.setColorPalette(ColorPalette.ocean);

      expect(provider.colorPalette, ColorPalette.ocean);
      expect(provider.appPalette, AppPalette.ocean);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('colorPalette'), 'ocean');
    });

    test(
      'persists and restores a custom palette with at most three colors',
      () async {
        await provider.ready;
        await provider.setCustomPalette(const [
          Color(0xFF123456),
          Color(0xFFF0F0F0),
          Color(0xFF102030),
        ]);

        expect(provider.colorPalette, ColorPalette.custom);
        expect(provider.customPaletteColors, hasLength(3));
        expect(provider.customPaletteColors.first, const Color(0xFF123456));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('customPaletteColors'), [
          '123456',
          'F0F0F0',
          '102030',
        ]);
      },
    );

    test('restores custom palettes with one, two and three colors', () async {
      for (final colors in const [
        [Color(0xFF123456)],
        [Color(0xFF123456), Color(0xFFF0F0F0)],
        [Color(0xFF123456), Color(0xFFF0F0F0), Color(0xFF102030)],
      ]) {
        SharedPreferences.setMockInitialValues({});
        final source = SettingsProvider();
        await source.ready;
        await source.setCustomPalette(colors);

        final restored = SettingsProvider();
        await restored.ready;
        expect(restored.colorPalette, ColorPalette.custom);
        expect(restored.customPaletteColors, colors);
        expect(restored.hasCustomPalette, isTrue);
      }
    });

    test(
      'rejects empty, oversized, transparent and duplicate-independent invalid input',
      () async {
        await provider.ready;
        expect(
          () => AppPalette.fromCustomColors(const []),
          throwsArgumentError,
        );
        expect(
          () => AppPalette.fromCustomColors(const [
            Color(0xFF000001),
            Color(0xFF000002),
            Color(0xFF000003),
            Color(0xFF000004),
          ]),
          throwsArgumentError,
        );
        expect(
          () => AppPalette.fromCustomColors(const [Color(0x00123456)]),
          throwsArgumentError,
        );
        expect(
          () => AppPalette.fromCustomColors(const [
            Color(0xFF123456),
            Color(0xFF123456),
          ]),
          throwsArgumentError,
        );
        expect(AppPalette.tryParseHex('#12ABef'), const Color(0xFF12ABEF));
        expect(AppPalette.tryParseHex('#FFF'), isNull);
        expect(AppPalette.tryParseHex('#FFFFFFFF'), isNull);
      },
    );

    test(
      'falls back to base and cleans corrupted custom palette preferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'colorPalette': 'custom',
          'customPaletteColors': ['123456', '123456'],
        });
        final corrupted = SettingsProvider();
        await corrupted.ready;

        expect(corrupted.colorPalette, ColorPalette.base);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('colorPalette'), 'base');
        expect(prefs.getStringList('customPaletteColors'), isNull);
      },
    );

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

    test('removes custom animation speed and falls back when active', () async {
      await provider.addCustomAnimationSpeed(1.5);
      expect(provider.customAnimationSpeeds, contains(1.5));
      expect(provider.animationSpeed, 1.5);

      await provider.removeCustomAnimationSpeed(1.5);

      expect(provider.customAnimationSpeeds, isNot(contains(1.5)));
      expect(provider.animationSpeed, 1.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('customAnimationSpeeds'), isEmpty);
    });

    test(
      'removes a non-active custom app scale without changing active scale',
      () async {
        await provider.addCustomAppScale(1.1, 0.8, 1.3);
        await provider.addCustomAppScale(1.15, 0.8, 1.3);
        expect(provider.appScale, 1.15);

        await provider.removeCustomAppScale(1.1);

        expect(provider.customAppScales, isNot(contains(1.1)));
        expect(provider.customAppScales, contains(1.15));
        expect(provider.appScale, 1.15);
      },
    );

    test('setAvatarPath stores and clears path', () async {
      await provider.setAvatarPath('/path/to/avatar.webp');
      expect(provider.avatarPath, '/path/to/avatar.webp');

      await provider.setAvatarPath(null);
      expect(provider.avatarPath, isNull);
    });

    test('serializes concurrent avatar path updates in call order', () async {
      final first = provider.setAvatarPath('/avatars/first.webp');
      final second = provider.setAvatarPath('/avatars/second.webp');

      expect(await first, isNull);
      expect(await second, '/avatars/first.webp');
      expect(provider.avatarPath, '/avatars/second.webp');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('avatarPath'), '/avatars/second.webp');
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
