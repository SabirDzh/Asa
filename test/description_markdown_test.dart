import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/description_markdown.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';

void main() {
  group('description preview', () {
    test('keeps exactly 150 code points without an ellipsis', () {
      final source = 'a' * 150;

      expect(descriptionPreview(source), source);
      expect(descriptionPreview(source).runes.length, 150);
    });

    test('truncates after 150 Unicode code points and adds an ellipsis', () {
      final preview = descriptionPreview('😀' * 151);

      expect(preview.runes.length, 151);
      expect(preview.endsWith('…'), isTrue);
      expect(preview.replaceAll('…', '').runes.length, 150);
    });

    test('trims whitespace without truncating short content', () {
      expect(descriptionPreview('  hello  '), 'hello');
    });
  });

  group('description links and mentions', () {
    test('allows only normalized http and https links', () {
      expect(isSafeDescriptionHref('https://example.com/path'), isTrue);
      expect(isSafeDescriptionHref('HTTP://EXAMPLE.COM'), isTrue);
      expect(isSafeDescriptionHref('javascript:alert(1)'), isFalse);
      expect(isSafeDescriptionHref('file:///private/secret'), isFalse);
      expect(isSafeDescriptionHref('attachment://file-1'), isFalse);
    });

    test('extracts a safe attachment mention id from the URI host', () {
      final mention = extractAttachmentMention(
        'attachment://file-1',
        'contract.pdf',
      );

      expect(mention?.id, 'file-1');
      expect(mention?.label, 'contract.pdf');
      expect(extractAttachmentMention('attachment://../secret', 'bad'), isNull);
      expect(extractAttachmentMention('javascript://file-1', 'bad'), isNull);
    });

    test('finds and replaces an @ trigger with safe Markdown', () {
      const attachment = TaskAttachment(
        id: 'file-1',
        type: TaskAttachmentType.file,
        name: 'contract.pdf',
        value: '/app/task_attachments/contract.pdf',
      );
      final trigger = findMentionTrigger('Review @con', 11);

      expect(trigger, const MentionTrigger(start: 7, end: 11, query: 'con'));
      final value = replaceMentionTrigger(
        const TextEditingValue(text: 'Review @con'),
        trigger!,
        attachment,
      );

      expect(value.text, 'Review [@contract.pdf](attachment://file-1) ');
      expect(value.selection.baseOffset, value.text.length);
      expect(findMentionTrigger('mail@test.com', 13), isNull);
    });
  });

  testWidgets('Markdown images are rendered as safe text placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBody(
            text: '![remote](https://example.com/image.png)',
            format: DescriptionFormat.markdown,
            attachments: const [],
            onAttachmentTap: _ignoreAttachment,
            onExternalLinkTap: null,
          ),
        ),
      ),
    );

    expect(find.text('[remote]'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

void _ignoreAttachment(TaskAttachment attachment) {}
