import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/description_markdown.dart';
import 'package:asa/core/description_render_context.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/services/description_link_resolver.dart';

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

  test('prepares Wikilinks, tags, and local embeds without touching code', () {
    const attachment = TaskAttachment(
      id: 'notes-1',
      type: TaskAttachmentType.file,
      name: 'notes.txt',
      value: '/private/task_attachments/notes.txt',
    );
    final prepared = prepareDescriptionMarkdown(
      '[[Read book|open]] #project ![[notes.txt]] `[[literal]]`',
      const [attachment],
    );

    expect(prepared, contains('asa-wikilink://link?value=Read+book'));
    expect(prepared, contains('asa-tag://link?value=project'));
    expect(prepared, contains('![notes.txt](attachment://notes-1)'));
    expect(prepared, contains('`[[literal]]`'));
    expect(prepared, isNot(contains('[[Read book|open]]')));
  });

  testWidgets('renders safe Wikilinks, tags, callouts, and embeds', (
    tester,
  ) async {
    var wikilinkTapped = false;
    var tagTapped = false;
    var embedTapped = false;
    const attachment = TaskAttachment(
      id: 'notes-1',
      type: TaskAttachmentType.file,
      name: 'notes.txt',
      value: '/private/task_attachments/notes.txt',
    );
    final target = TaskItem(id: 'read-book', title: 'Read book');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBody(
            text:
                '[[Read book]] #project\n\n> [!warning] Care\n> Be careful with [[Care plan]] and #inside.\n\n![[notes.txt]]',
            format: DescriptionFormat.markdown,
            attachments: const [attachment],
            onAttachmentTap: (_) {},
            onExternalLinkTap: null,
            renderContext: DescriptionRenderContext(
              resolveLink:
                  (value) => DescriptionLinkResolution(
                    target: value,
                    task: target,
                    candidates: [target],
                  ),
              onWikilinkTap: (_) => wikilinkTapped = true,
              onTagTap: (_) => tagTapped = true,
              onAttachmentEmbedTap: (_) async => embedTapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('markdown-wikilink-Read book')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('markdown-wikilink-Care plan')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('markdown-tag-project')), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-tag-inside')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('description-callout-warning')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('markdown-embed-notes-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('markdown-wikilink-Read book')));
    await tester.tap(find.byKey(const ValueKey('markdown-wikilink-Care plan')));
    await tester.tap(find.byKey(const ValueKey('markdown-tag-project')));
    await tester.tap(find.byKey(const ValueKey('markdown-tag-inside')));
    await tester.tap(find.byKey(const ValueKey('markdown-embed-notes-1')));
    expect(wikilinkTapped, isTrue);
    expect(tagTapped, isTrue);
    expect(embedTapped, isTrue);
  });

  testWidgets('embeds stay adaptive and reload when the source changes', (
    tester,
  ) async {
    const first = TaskAttachment(
      id: 'first-attachment',
      type: TaskAttachmentType.file,
      name: 'first.txt',
      value: '/private/task_attachments/first.txt',
    );
    const second = TaskAttachment(
      id: 'second-attachment',
      type: TaskAttachmentType.file,
      name: 'second.txt',
      value: '/private/task_attachments/second.txt',
    );

    Widget body(String source) {
      return MediaQuery(
        data: const MediaQueryData(size: Size(320, 640)),
        child: SizedBox(
          width: 320,
          height: 300,
          child: Scaffold(
            body: DescriptionBody(
              text: source,
              format: DescriptionFormat.markdown,
              attachments: const [first, second],
              onAttachmentTap: (_) {},
              onExternalLinkTap: null,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(MaterialApp(home: body('![[first.txt]]')));
    expect(
      find.byKey(const ValueKey('markdown-embed-first-attachment')),
      findsOneWidget,
    );

    await tester.pumpWidget(MaterialApp(home: body('![[second.txt]]')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('markdown-embed-second-attachment')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

  test('prepares block references, block links, and task embeds', () {
    final prepared = prepareDescriptionMarkdown(
      '^key-point [[Read book#^intro]] [[#^same]] ![[Read book]] '
      '![[Read book#^note]]',
      const [],
    );

    expect(prepared, contains('asa-block://link?value=key-point'));
    expect(prepared, contains('asa-block://link?value=Read+book&block=intro'));
    expect(prepared, contains('asa-block://link?value=&block=same'));
    expect(prepared, contains('asa-embed://link?value=Read+book'));
    expect(
      prepared,
      contains('asa-embed-block://link?value=Read+book&block=note'),
    );
  });

  testWidgets('renders a tappable block chip and block link', (tester) async {
    String? tappedBlock;
    String? tappedBlockLink;
    final target = TaskItem(id: 'read-book', title: 'Read book');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBody(
            text: '^key-point and [[Read book#^intro]]',
            format: DescriptionFormat.markdown,
            attachments: const [],
            onAttachmentTap: (_) {},
            onExternalLinkTap: null,
            renderContext: DescriptionRenderContext(
              resolveLink:
                  (value) => DescriptionLinkResolution(
                    target: value,
                    task: target,
                    candidates: [target],
                  ),
              onBlockTap: (id) => tappedBlock = id,
              onBlockLinkTap: (resolution, id) => tappedBlockLink = id,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('markdown-block-key-point')));
    expect(tappedBlock, 'key-point');
    await tester.tap(find.byKey(const ValueKey('markdown-block-link-intro')));
    expect(tappedBlockLink, 'intro');
  });
}

void _ignoreAttachment(TaskAttachment attachment) {}
