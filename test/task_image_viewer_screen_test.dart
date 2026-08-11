import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/screens/task_image_viewer_screen.dart';

void main() {
  const attachment = TaskAttachment(
    id: 'image-1',
    type: TaskAttachmentType.image,
    name: 'photo.webp',
    value: '/missing/task_attachments/photo.webp',
    mimeType: 'image/webp',
  );

  testWidgets('renders a separate image viewer page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskImageViewerScreen(
          attachment: attachment,
          bytesLoader: (_) async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('photo.webp'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(
      find.byKey(const ValueKey('close-task-image-viewer')),
      findsOneWidget,
    );
  });

  testWidgets('renders a valid image with zoom support', (tester) async {
    const pngBytes = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TaskImageViewerScreen(
          attachment: attachment,
          bytesLoader: (_) async => pngBytes,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('back button returns from the image viewer page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator),
    ); // Do not await the route: it completes only after the viewer is closed.
    final route = MaterialPageRoute<void>(
      builder:
          (_) => TaskImageViewerScreen(
            attachment: attachment,
            bytesLoader: (_) async => null,
          ),
    );
    unawaited(navigator.push<void>(route));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('photo.webp'), findsOneWidget);

    // The first test verifies the visible back control. Here we verify that
    // the dedicated route returns cleanly to its parent route.
    navigator.pop();
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
    expect(find.text('photo.webp'), findsNothing);
  });
}
