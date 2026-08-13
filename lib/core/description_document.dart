/// The Obsidian-like reference forms understood by ASA descriptions.
enum DescriptionReferenceType { wikilink, embed, tag, blockReference }

/// A source-level reference found in a description.
///
/// [start] and [end] are UTF-16 offsets into [DescriptionDocument.source],
/// matching Dart's String indexing and TextEditingValue selection offsets.
class DescriptionReference {
  final DescriptionReferenceType type;
  final String raw;
  final String target;
  final String? alias;
  final String? blockId;
  final int start;
  final int end;

  const DescriptionReference({
    required this.type,
    required this.raw,
    required this.target,
    required this.alias,
    this.blockId,
    required this.start,
    required this.end,
  });

  bool get isInternalLink => type == DescriptionReferenceType.wikilink;
}

/// A block-style callout found in a description.
class DescriptionCallout {
  final String kind;
  final String title;
  final int start;
  final int end;
  final int bodyStart;
  final int bodyEnd;

  const DescriptionCallout({
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    required this.bodyStart,
    required this.bodyEnd,
  });
}

/// Parsed metadata for a description. The original source remains unchanged.
class DescriptionDocument {
  final String source;
  final List<DescriptionReference> references;
  final List<DescriptionCallout> callouts;

  const DescriptionDocument({
    required this.source,
    required this.references,
    required this.callouts,
  });
}

/// Splits [source] around the blank-line-delimited paragraph whose last line
/// ends with `^blockId`. Returns null when the block is not present.
({String before, String block, String after})? splitDescriptionAroundBlock(
  String source,
  String blockId,
) {
  final marker = RegExp.escape('^$blockId');
  final match = RegExp(
    r'^(.*' + marker + r'[ \t]*)$',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) return null;
  final separatorStart = source.lastIndexOf('\n\n', match.start);
  final blockStart = separatorStart == -1 ? 0 : separatorStart + 2;
  final separatorEnd = source.indexOf('\n\n', match.end);
  final blockEnd = separatorEnd == -1 ? source.length : separatorEnd;
  final afterStart = separatorEnd == -1 ? source.length : separatorEnd + 2;
  return (
    before: source.substring(0, separatorStart == -1 ? 0 : separatorStart),
    block: source.substring(blockStart, blockEnd),
    after: source.substring(afterStart),
  );
}
