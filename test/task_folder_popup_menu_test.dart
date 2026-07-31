import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/anchored_popup_menu.dart';
import 'package:asa/core/home_widget_service.dart';
import 'package:asa/core/theme.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/features/tasks/widgets/folder_card.dart';
import 'package:asa/features/tasks/widgets/task_card.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeWidgetService.instance.debounceDelay = Duration.zero;
  });

  tearDown(() {
    HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
  });

  testWidgets('task ellipsis opens the task action menu', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: TaskRow(
          task: TaskItem(id: 'task-1', title: 'Test task'),
          enableDrag: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.more_square));
    await tester.pumpAndSettle();

    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    _expectMenuBelowAnchor(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удаление'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
  });

  testWidgets('folder ellipsis opens the folder action menu', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: FolderRow(
          folder: FolderItem(id: 'folder-1', name: 'Test folder'),
          enableDrag: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.more_square));
    await tester.pumpAndSettle();

    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    _expectMenuBelowAnchor(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удаление'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
  });
}

void _expectMenuBelowAnchor(WidgetTester tester) {
  final anchor =
      find
          .ancestor(
            of: find.byIcon(Iconsax.more_square),
            matching: find.byType(GestureDetector),
          )
          .first;
  final menu =
      find
          .ancestor(
            of: find.byType(AnchoredPopupMenuItem<String>),
            matching: find.byType(Material),
          )
          .first;
  final anchorRect = tester.getRect(anchor);
  final menuRect = tester.getRect(menu);
  expect(menuRect.top - anchorRect.bottom, closeTo(6, 0.01));
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create:
              (_) => SettingsProvider(
                deviceNameProvider: () async => 'Test Device',
              ),
        ),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: AppTheme.rowWidth, child: child)),
        ),
      ),
    );
  }
}
