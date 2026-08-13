import 'description_document.dart';

const int kMaxParsedDescriptionReferences = 256;

/// Parses Obsidian-like metadata without changing the original Markdown.
///
/// The scanner deliberately ignores inline/fenced code and Markdown link
/// labels, so ordinary code examples and existing links remain literal text.
DescriptionDocument parseDescriptionDocument(String source) {
  final originalSource = source;
  source = _boundedSource(source);
  final references = <DescriptionReference>[];
  final callouts = _parseCallouts(source);
  var inlineCodeDelimiter = '';
  var fencedChar = '';
  var fencedLength = 0;
  var linkLabelDepth = 0;
  var lineStart = true;
  var index = 0;

  while (index < source.length &&
      references.length < kMaxParsedDescriptionReferences) {
    if (lineStart) {
      final lineEnd = source.indexOf('\n', index);
      final end = lineEnd == -1 ? source.length : lineEnd;
      final line = source.substring(index, end);
      final fence = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
      if (fencedChar.isNotEmpty) {
        if (fence != null &&
            fence.group(1)!.startsWith(fencedChar) &&
            fence.group(1)!.length >= fencedLength) {
          fencedChar = '';
          fencedLength = 0;
        }
        index = lineEnd == -1 ? source.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
      if (fence != null) {
        fencedChar = fence.group(1)![0];
        fencedLength = fence.group(1)!.length;
        index = lineEnd == -1 ? source.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
    }

    final character = source[index];
    if (character == '\n') {
      index++;
      lineStart = true;
      continue;
    }

    if (character == '`' && _isUnescaped(source, index)) {
      var runLength = 1;
      while (index + runLength < source.length &&
          source[index + runLength] == '`') {
        runLength++;
      }
      final delimiter = '`' * runLength;
      if (inlineCodeDelimiter.isEmpty) {
        inlineCodeDelimiter = delimiter;
      } else if (inlineCodeDelimiter == delimiter) {
        inlineCodeDelimiter = '';
      }
      index += runLength;
      lineStart = false;
      continue;
    }

    if (inlineCodeDelimiter.isNotEmpty) {
      index++;
      lineStart = false;
      continue;
    }

    if (character == '[' &&
        _isUnescaped(source, index) &&
        !_startsWith(source, index, '[[')) {
      linkLabelDepth++;
      index++;
      lineStart = false;
      continue;
    }
    if (character == ']' && linkLabelDepth > 0) {
      linkLabelDepth--;
      index++;
      if (linkLabelDepth == 0 &&
          index < source.length &&
          source[index] == '(') {
        index = _consumeLinkDestination(source, index);
      }
      lineStart = false;
      continue;
    }
    if (linkLabelDepth > 0) {
      index++;
      lineStart = false;
      continue;
    }

    final isEmbed =
        character == '!' &&
        _isUnescaped(source, index) &&
        _startsWith(source, index + 1, '[[');
    final linkStart = isEmbed ? index + 1 : index;
    if ((character == '[' || isEmbed) &&
        _isUnescaped(source, linkStart) &&
        _startsWith(source, linkStart, '[[')) {
      final close = source.indexOf(']]', linkStart + 2);
      if (close != -1) {
        final content = source.substring(linkStart + 2, close);
        final parts = content.split('|');
        final rawTarget = parts.first.trim();
        final hashIndex = rawTarget.indexOf('#^');
        final target =
            hashIndex == -1
                ? rawTarget
                : rawTarget.substring(0, hashIndex).trim();
        final blockId =
            hashIndex == -1 ? null : rawTarget.substring(hashIndex + 2).trim();
        final hasValidBlockId =
            blockId != null &&
            blockId.isNotEmpty &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(blockId);
        if ((target.isNotEmpty || hasValidBlockId) &&
            !rawTarget.contains('\n') &&
            !rawTarget.contains('[[') &&
            !rawTarget.contains('`')) {
          final rawStart = isEmbed ? index : linkStart;
          references.add(
            DescriptionReference(
              type:
                  isEmbed
                      ? DescriptionReferenceType.embed
                      : DescriptionReferenceType.wikilink,
              raw: source.substring(rawStart, close + 2),
              target: target,
              alias:
                  parts.length > 1 && parts[1].trim().isNotEmpty
                      ? parts.sublist(1).join('|').trim()
                      : null,
              blockId: hasValidBlockId ? blockId : null,
              start: rawStart,
              end: close + 2,
            ),
          );
          index = close + 2;
          lineStart = false;
          continue;
        } else if (close != -1) {
          // Consume malformed nested/code-like link content as literal text
          // so a tag inside it is not promoted to a real reference.
          index = close + 2;
          lineStart = false;
          continue;
        }
      }
    }

    if (character == '#' &&
        _isTagBoundary(source, index) &&
        _isUnescaped(source, index)) {
      final end = _consumeToken(source, index + 1, _isTagCharacter);
      if (end > index + 1) {
        references.add(
          DescriptionReference(
            type: DescriptionReferenceType.tag,
            raw: source.substring(index, end),
            target: source.substring(index + 1, end),
            alias: null,
            start: index,
            end: end,
          ),
        );
        index = end;
        lineStart = false;
        continue;
      }
    }

    if (character == '^' &&
        _isTokenBoundary(source, index) &&
        _isUnescaped(source, index)) {
      final end = _consumeToken(source, index + 1, _isBlockCharacter);
      if (end > index + 1) {
        references.add(
          DescriptionReference(
            type: DescriptionReferenceType.blockReference,
            raw: source.substring(index, end),
            target: source.substring(index + 1, end),
            alias: null,
            start: index,
            end: end,
          ),
        );
        index = end;
        lineStart = false;
        continue;
      }
    }

    index++;
    lineStart = false;
  }

  return DescriptionDocument(
    source: originalSource,
    references: List.unmodifiable(references),
    callouts: List.unmodifiable(callouts),
  );
}

List<DescriptionCallout> _parseCallouts(String source) {
  final callouts = <DescriptionCallout>[];
  var offset = 0;
  var inFence = false;
  var fenceChar = '';
  var fenceLength = 0;

  while (offset <= source.length) {
    final lineEnd = source.indexOf('\n', offset);
    final end = lineEnd == -1 ? source.length : lineEnd;
    final line = source.substring(offset, end);
    final fence = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      if (!inFence) {
        inFence = true;
        fenceChar = marker[0];
        fenceLength = marker.length;
      } else if (marker.startsWith(fenceChar) && marker.length >= fenceLength) {
        inFence = false;
        fenceChar = '';
        fenceLength = 0;
      }
    } else if (!inFence) {
      final match = RegExp(
        r'^\s*>\s*\[!([A-Za-z0-9_-]+)\](?:\s+(.*))?\s*$',
      ).firstMatch(line);
      if (match != null) {
        var bodyStart = lineEnd == -1 ? source.length : lineEnd + 1;
        var bodyEnd = bodyStart;
        var nextOffset = bodyStart;
        while (nextOffset < source.length) {
          final nextLineEnd = source.indexOf('\n', nextOffset);
          final nextEnd = nextLineEnd == -1 ? source.length : nextLineEnd;
          final nextLine = source.substring(nextOffset, nextEnd);
          if (!RegExp(r'^\s*>').hasMatch(nextLine)) break;
          bodyEnd = nextEnd;
          nextOffset = nextLineEnd == -1 ? source.length : nextLineEnd + 1;
        }
        callouts.add(
          DescriptionCallout(
            kind: match.group(1)!.toLowerCase(),
            title: match.group(2)?.trim() ?? '',
            start: offset,
            end: bodyEnd,
            bodyStart: bodyStart,
            bodyEnd: bodyEnd,
          ),
        );
      }
    }

    if (lineEnd == -1) break;
    offset = lineEnd + 1;
  }
  return callouts;
}

bool _startsWith(String value, int index, String pattern) {
  return index >= 0 &&
      index + pattern.length <= value.length &&
      value.startsWith(pattern, index);
}

bool _isUnescaped(String value, int index) {
  var slashCount = 0;
  for (var i = index - 1; i >= 0 && value[i] == '\\'; i--) {
    slashCount++;
  }
  return slashCount.isEven;
}

bool _isTokenBoundary(String value, int index) {
  return index == 0 || value[index - 1].trim().isEmpty;
}

bool _isTagBoundary(String value, int index) {
  if (index == 0) return index + 1 < value.length && value[index + 1] != ' ';
  final previous = value[index - 1];
  final hasBoundary =
      previous.trim().isEmpty || RegExp(r'[([{,;]').hasMatch(previous);
  return hasBoundary && index + 1 < value.length && value[index + 1] != ' ';
}

int _consumeLinkDestination(String source, int index) {
  var depth = 0;
  var cursor = index;
  while (cursor < source.length) {
    if (source[cursor] == '\\' && cursor + 1 < source.length) {
      cursor += 2;
      continue;
    }
    if (source[cursor] == '(') depth++;
    if (source[cursor] == ')') {
      depth--;
      if (depth == 0) return cursor + 1;
    }
    cursor++;
  }
  return source.length;
}

int _consumeToken(String source, int index, bool Function(String) predicate) {
  var end = index;
  while (end < source.length && predicate(source[end])) {
    end++;
  }
  return end;
}

String _boundedSource(String source) {
  if (source.runes.length <= 10000) return source;
  var codePoints = 0;
  var codeUnits = 0;
  while (codeUnits < source.length && codePoints < 10000) {
    final unit = source.codeUnitAt(codeUnits);
    codeUnits += unit > 0xFFFF ? 2 : 1;
    codePoints++;
  }
  return source.substring(0, codeUnits);
}

bool _isTagCharacter(String value) {
  return RegExp(r'[A-Za-z0-9_/-]').hasMatch(value);
}

bool _isBlockCharacter(String value) {
  return RegExp(r'[A-Za-z0-9_-]').hasMatch(value);
}
