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
