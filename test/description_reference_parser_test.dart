import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/description_document.dart';
import 'package:asa/core/description_reference_parser.dart';

void main() {
  test('parses wikilinks, aliases, embeds, tags, and block references', () {
    const source =
        '[[Read book]] [[Projects/Read book|open book]] ![[photo.png]] '
        '#project/asa\nA paragraph ^block-id';

    final document = parseDescriptionDocument(source);

    expect(document.references.map((reference) => reference.type), [
      DescriptionReferenceType.wikilink,
      DescriptionReferenceType.wikilink,
      DescriptionReferenceType.embed,
      DescriptionReferenceType.tag,
      DescriptionReferenceType.blockReference,
    ]);
    expect(document.references[0].target, 'Read book');
    expect(document.references[1].target, 'Projects/Read book');
    expect(document.references[1].alias, 'open book');
    expect(document.references[2].target, 'photo.png');
    expect(document.references[3].target, 'project/asa');
    expect(document.references[4].target, 'block-id');
  });

  test('parses a multiline note callout with source offsets', () {
    const source = '> [!note] Read this\n> The first line\n> The second line';

    final document = parseDescriptionDocument(source);

    expect(document.callouts, hasLength(1));
    final callout = document.callouts.single;
    expect(callout.kind, 'note');
    expect(callout.title, 'Read this');
    expect(
      source.substring(callout.bodyStart, callout.bodyEnd),
      '> The first line\n> The second line',
    );
  });

  test('ignores code, escaped syntax, and existing markdown link labels', () {
    const source =
        '`[[inline]] #inline`\n'
        '```md\n[[fenced]] #fenced\n```\n'
        r'\[[escaped]] and [visible [[label]]](https://example.com)';

    final document = parseDescriptionDocument(source);

    expect(document.references, isEmpty);
    expect(document.callouts, isEmpty);
  });

  test('uses UTF-16 offsets for non-ASCII source text', () {
    const source = '😀 [[Задача]]';

    final reference = parseDescriptionDocument(source).references.single;

    expect(reference.start, source.indexOf('[['));
    expect(reference.end, source.indexOf('[[') + '[[Задача]]'.length);
    expect(source.substring(reference.start, reference.end), '[[Задача]]');
  });

  test('leaves malformed or unclosed syntax unparsed', () {
    const source = '[[unclosed #tag-without-boundary';

    final document = parseDescriptionDocument(source);

    expect(document.references, isEmpty);
    expect(document.callouts, isEmpty);
  });

  test('does not parse references inside Markdown destinations', () {
    const source = '[visible](https://example.com/[[target]])';

    final document = parseDescriptionDocument(source);

    expect(document.references, isEmpty);
  });

  test('accepts punctuation before a tag but not a URL fragment', () {
    const source = '(#project), #asa https://example.com/#web';

    final document = parseDescriptionDocument(source);

    expect(document.references.map((reference) => reference.target), [
      'project',
      'asa',
    ]);
  });

  test('stops scanning after the parser input limit', () {
    final source = '${'x' * 10001} #ignored';

    final document = parseDescriptionDocument(source);

    expect(document.references, isEmpty);
    expect(document.source, source);
  });

  test('parses block links with a task target', () {
    const source = '[[Read book#^intro]] and ![[Read book#^summary]]';

    final refs = parseDescriptionDocument(source).references;

    expect(refs, hasLength(2));
    expect(refs[0].type, DescriptionReferenceType.wikilink);
    expect(refs[0].target, 'Read book');
    expect(refs[0].blockId, 'intro');
    expect(refs[1].type, DescriptionReferenceType.embed);
    expect(refs[1].target, 'Read book');
    expect(refs[1].blockId, 'summary');
  });

  test('parses a same-document block link with an empty target', () {
    const source = 'See [[#^details]] here';

    final ref = parseDescriptionDocument(source).references.single;

    expect(ref.type, DescriptionReferenceType.wikilink);
    expect(ref.target, '');
    expect(ref.blockId, 'details');
  });

  test('keeps standalone ^id as a blockReference without a blockId', () {
    const source = 'A paragraph ^block-id';

    final ref = parseDescriptionDocument(source).references.single;

    expect(ref.type, DescriptionReferenceType.blockReference);
    expect(ref.target, 'block-id');
    expect(ref.blockId, isNull);
  });
}
