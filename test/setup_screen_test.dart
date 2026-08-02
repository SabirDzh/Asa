import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/features/splash/setup_screen.dart';

void main() {
  group('SetupScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('shouldShow returns true when not yet completed', () async {
      expect(await SetupScreen.shouldShow(), isTrue);
    });

    test('shouldShow returns false after markCompleted', () async {
      await SetupScreen.markCompleted();
      expect(await SetupScreen.shouldShow(), isFalse);
    });

    test('markCompleted is idempotent — stays false on second call', () async {
      await SetupScreen.markCompleted();
      await SetupScreen.markCompleted();
      expect(await SetupScreen.shouldShow(), isFalse);
    });

    test('shouldShow returns false when key is already set', () async {
      SharedPreferences.setMockInitialValues({'asa_setup_completed': true});
      expect(await SetupScreen.shouldShow(), isFalse);
    });

    test('shouldShow returns true when key is explicitly false', () async {
      SharedPreferences.setMockInitialValues({'asa_setup_completed': false});
      expect(await SetupScreen.shouldShow(), isTrue);
    });
  });
}
