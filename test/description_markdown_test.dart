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

      expect(value.text, 'Review @contract.pdf ');
      expect(value.selection.baseOffset, value.text.length);
      expect(findMentionTrigger('mail@test.com', 13), isNull);
    });

    test('mention labels expose only the attachment basename', () {
      const attachment = TaskAttachment(
        id: 'photo-1',
        type: TaskAttachmentType.image,
        name: '/private/user/task_attachments/holiday/photo.png',
        value: '/private/user/task_attachments/holiday/photo.png',
      );

      expect(
        attachmentMentionMarkdown(attachment),
        '[photo.png](attachment://photo-1)',
      );
      expect(
        expandAttachmentMentions('See @photo.png now', const [attachment]),
        'See [photo.png](attachment://photo-1) now',
      );
    });

    test('supports attachment paths in internal mention ids', () {
      const attachment = TaskAttachment(
        id: '/private/task_attachments/photo.png',
        type: TaskAttachmentType.image,
        name: 'photo.png',
        value: '/private/task_attachments/photo.png',
      );
      final markdown = attachmentMentionMarkdown(attachment);

      expect(markdown, startsWith('[photo.png](attachment:///b64_'));
      final href = markdown.substring(markdown.indexOf('attachment://'));
      final mention = extractAttachmentMention(
        href.substring(0, href.length - 1),
        'photo.png',
      );
      expect(mention?.id, attachment.id);
    });

    test('does not rewrite code or an existing Markdown link label', () {
      const attachment = TaskAttachment(
        id: 'photo-1',
        type: TaskAttachmentType.image,
        name: 'photo.png',
        value: '/private/task_attachments/photo.png',
      );

      expect(
        expandAttachmentMentions(
          '`@photo.png` and [@photo.png](attachment://photo-1)',
          const [attachment],
        ),
        '`@photo.png` and [@photo.png](attachment://photo-1)',
      );
    });

    test('does not rewrite fenced code or spaced Markdown labels', () {
      const attachment = TaskAttachment(
        id: 'photo-1',
        type: TaskAttachmentType.image,
        name: 'photo.png',
        value: '/private/task_attachments/photo.png',
      );
      const source =
          '```md\n@photo.png\n```\n[ @photo.png ](attachment://photo-1)';

      expect(expandAttachmentMentions(source, const [attachment]), source);
    });
  });

  testWidgets('attachment mentions show only the name and remain tappable', (
    tester,
  ) async {
    var tapped = false;
    const attachment = TaskAttachment(
      id: 'photo-1',
      type: TaskAttachmentType.image,
      name: '/private/user/task_attachments/holiday/photo.png',
      value: '/private/user/task_attachments/holiday/photo.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBody(
            text: 'See [@photo.png](attachment://photo-1)',
            format: DescriptionFormat.markdown,
            attachments: const [attachment],
            onAttachmentTap: (_) => tapped = true,
            onExternalLinkTap: null,
          ),
        ),
      ),
    );

    expect(find.text('photo.png'), findsOneWidget);
    expect(find.textContaining('/private/user'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('markdown-attachment-photo-1')));
    expect(tapped, isTrue);
  });

  testWidgets('all attachment mention types remain clickable', (tester) async {
    final tapped = <TaskAttachmentType>[];
    const attachments = [
      TaskAttachment(
        id: 'link-1',
        type: TaskAttachmentType.link,
        name: 'docs.example.com',
        value: 'https://example.com/docs',
      ),
      TaskAttachment(
        id: 'image-1',
        type: TaskAttachmentType.image,
        name: 'photo.png',
        value: '/private/task_attachments/photo.png',
      ),
      TaskAttachment(
        id: 'file-1',
        type: TaskAttachmentType.file,
        name: 'notes.txt',
        value: '/private/task_attachments/notes.txt',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBody(
            text: '@docs.example.com @photo.png @notes.txt',
            format: DescriptionFormat.markdown,
            attachments: attachments,
            onAttachmentTap: (attachment) => tapped.add(attachment.type),
            onExternalLinkTap: null,
          ),
        ),
      ),
    );

    for (final attachment in attachments) {
      await tester.tap(
        find.byKey(ValueKey('markdown-attachment-${attachment.id}')),
      );
    }
    expect(tapped, [
      TaskAttachmentType.link,
      TaskAttachmentType.image,
      TaskAttachmentType.file,
    ]);
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
