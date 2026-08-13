import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/description_document.dart';

void main() {
  test('splits source around the paragraph defining a block', () {
    const source =
        'First paragraph.\n\nMiddle paragraph ^key\n\nLast paragraph.';

    final parts = splitDescriptionAroundBlock(source, 'key');

    expect(parts, isNotNull);
    expect(parts!.before, 'First paragraph.');
    expect(parts.block, 'Middle paragraph ^key');
    expect(parts.after, 'Last paragraph.');
  });

  test('returns null when the block id is not present', () {
    expect(splitDescriptionAroundBlock('No block here.', 'missing'), isNull);
  });
}
