import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform channel used by the `home_widget` plugin.
const MethodChannel _homeWidgetChannel = MethodChannel('home_widget');

/// Installs a mock for the `home_widget` platform channel.
///
/// Widget tests render screens whose providers schedule widget updates through
/// [HomeWidgetService]. Without a mock the native platform call never
/// completes in the test environment, which blocks `resetForTests()` waiting
/// on the in-flight update. This handler completes every call immediately.
void installHomeWidgetChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_homeWidgetChannel, (call) async => null);
}

/// Removes the mock installed by [installHomeWidgetChannelMock].
void removeHomeWidgetChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_homeWidgetChannel, null);
}
