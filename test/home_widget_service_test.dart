import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/home_widget_service.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

void main() {
  late TaskProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = TaskProvider();
    HomeWidgetService.instance.debounceDelay = Duration.zero;
  });

  tearDown(() async {
    await HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
  });

  test(
    'coalesces a widget update queued during an active native update',
    () async {
      final firstUpdateStarted = Completer<void>();
      final releaseFirstUpdate = Completer<void>();
      var updateCount = 0;

      HomeWidgetService.instance.updateOverride = () async {
        updateCount++;
        if (updateCount == 1) {
          firstUpdateStarted.complete();
          await releaseFirstUpdate.future;
        }
      };

      HomeWidgetService.updateData(provider);
      await firstUpdateStarted.future;

      provider.addTask('Latest task state');
      HomeWidgetService.updateData(provider);
      releaseFirstUpdate.complete();

      await _waitFor(() => updateCount == 2);
      expect(updateCount, 2);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
