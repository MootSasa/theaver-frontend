import 'package:flutter/widgets.dart';
import '../services/chat_service.dart';

/// Result of parsing markdown text into clean text with message entities.
class ParsedMessage {
  final String cleanText;
  final List<MessageEntity> entities;

  const ParsedMessage({
    required this.cleanText,
    required this.entities,
  });
}

/// Helper representing an unshifted entity during parsing
class _RawEntity {
  final String type;
  int offset;
  int length;
  final String? url;
  final String? language;
  final bool? collapsed;

  _RawEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.url,
    this.language,
    this.collapsed,
  });

  MessageEntity toMessageEntity() => MessageEntity(
        type: type,
        offset: offset,
        length: length,
        url: url,
        language: language,
        collapsed: collapsed,
      );
}

/// Utility for parsing Markdown into Telegram-style [MessageEntity] lists and vice versa.
///
/// Ensures offsets and lengths are computed precisely in UTF-16 code units,
/// compatible with Dart strings, emoji surrogate pairs, and the Telegram Bot API standard.
class EntityParser {
  static final RegExp _urlRegex = RegExp(
    r'(?:https?:\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)'
    r'|[-a-zA-Z0-9@:%._\+~#=]{1,256}\.(?:com|org|net|ru|io|me|dev|app|ai|edu|gov|co|info|biz|tv|cc|to|tech|online|site|space|fun|store|live|club|pro|vip|top|xyz)\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    caseSensitive: false,
  );

  /// Regular expression for detecting URLs (both with scheme and bare domains).
  static RegExp get urlRegex => _urlRegex;

  /// Ensures the URL starts with http:// or https://.
  static String normalizeUrl(String raw) {
    var u = cleanUrl(raw);
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u;
  }

  /// Strip trailing punctuation and unbalanced closing parentheses from a URL.
  static String cleanUrl(String url) {
    var cleaned = url.trim();
    while (cleaned.isNotEmpty) {
      final lastChar = cleaned[cleaned.length - 1];
      if (lastChar == ')') {
        final openCount = '('.allMatches(cleaned).length;
        final closeCount = ')'.allMatches(cleaned).length;
        if (closeCount > openCount) {
          cleaned = cleaned.substring(0, cleaned.length - 1);
          continue;
        }
      } else if (lastChar == '.' ||
          lastChar == ',' ||
          lastChar == '!' ||
          lastChar == '?' ||
          lastChar == ';' ||
          lastChar == ':' ||
          lastChar == '>') {
        cleaned = cleaned.substring(0, cleaned.length - 1);
        continue;
      }
      break;
    }
    return cleaned;
  }

  /// Extract all URLs found in the text.
  static List<String> extractUrls(String text) {
    final urls = <String>[];

    // 1. Explicit markdown links: [label](url)
    final mdLinkRegex = RegExp(r'\[(?:[^\]]*)\]\(((?:https?:\/\/|www\.)?[^\s\)]+)\)');
    for (final match in mdLinkRegex.allMatches(text)) {
      final u = normalizeUrl(match.group(1)!);
      if (u.isNotEmpty && !urls.contains(u)) {
        urls.add(u);
      }
    }

    // 2. Plain URLs
    for (final match in _urlRegex.allMatches(text)) {
      final u = normalizeUrl(match.group(0)!);
      if (u.isNotEmpty && !urls.contains(u)) {
        urls.add(u);
      }
    }

    return urls;
  }

  static final RegExp _latexRegex = RegExp(
    r'\$\$[\s\S]+?\$\$|(?<!\\|\$)\$(?!\$|\s)(?:\\.|[^\\\n\$])+?(?<!\s|\\)\$(?!\$|\d)|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)',
  );

  static bool _overlapsEntityTypes(
    int start,
    int end,
    List<_RawEntity> entities,
    Set<String> types,
  ) {
    for (final e in entities) {
      if (types.contains(e.type)) {
        final eEnd = e.offset + e.length;
        if (start < eEnd && end > e.offset) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns the end offset of a protected span ('pre', 'code', or LaTeX) if the
  /// candidate delimiter match is blocked by it, or -1 if the match is allowed.
  static int _getBlockingProtectedEnd({
    required int prefixStart,
    required int prefixLen,
    required int suffixStart,
    required int suffixLen,
    required List<_RawEntity> entities,
    required String text,
    bool checkLatex = true,
  }) {
    final int matchEnd = suffixStart + suffixLen;
    // Never match anything overlapping a fenced code block ('pre')
    for (final e in entities) {
      if (e.type == 'pre') {
        final eEnd = e.offset + e.length;
        if (prefixStart < eEnd && matchEnd > e.offset) {
          return eEnd;
        }
      }
    }

    final int openStart = prefixStart;
    final int openEnd = prefixStart + (prefixLen > 0 ? prefixLen : (matchEnd - prefixStart));
    final int closeStart = suffixLen > 0 ? suffixStart : prefixStart;
    final int closeEnd = matchEnd;

    // Never allow opening or closing delimiters to fall inside an inline 'code' entity
    for (final e in entities) {
      if (e.type == 'code') {
        final eEnd = e.offset + e.length;
        final openInside = openStart < eEnd && openEnd > e.offset;
        final closeInside = closeStart < eEnd && closeEnd > e.offset;
        if (openInside || closeInside) {
          return eEnd;
        }
      }
    }

    if (checkLatex) {
      for (final m in _latexRegex.allMatches(text)) {
        // Ignore LaTeX matches that are themselves inside a 'pre' or 'code' entity
        if (_overlapsEntityTypes(m.start, m.end, entities, const {'pre', 'code'})) {
          continue;
        }
        final openInside = openStart < m.end && openEnd > m.start;
        final closeInside = closeStart < m.end && closeEnd > m.start;
        if (openInside || closeInside) {
          return m.end;
        }
      }
    }

    return -1;
  }

  /// Parses markdown tokens in [rawText] into clean plain text and a list of [MessageEntity].
  static ParsedMessage parseMarkdown(String rawText) {
    if (rawText.isEmpty) {
      return const ParsedMessage(cleanText: '', entities: []);
    }

    String currentText = rawText.replaceAll('\r\n', '\n');
    final List<_RawEntity> entities = [];

    // 1. Code blocks: ```[language]\ncode\n```
    final codeBlockRegex = RegExp(r'```([a-zA-Z0-9_-]*)\r?\n([\s\S]*?)```');
    while (true) {
      final match = codeBlockRegex.firstMatch(currentText);
      if (match == null) break;

      final fullMatch = match.group(0)!;
      final lang = match.group(1)?.trim();
      var codeContent = match.group(2) ?? '';
      if (codeContent.endsWith('\n')) {
        codeContent = codeContent.substring(0, codeContent.length - 1);
        if (codeContent.endsWith('\r')) {
          codeContent = codeContent.substring(0, codeContent.length - 1);
        }
      }
      final startIndex = match.start;

      currentText = currentText.replaceRange(
        startIndex,
        startIndex + fullMatch.length,
        codeContent,
      );

      final prefixLen = fullMatch.indexOf(codeContent);
      final suffixLen = fullMatch.length - prefixLen - codeContent.length;

      _adjustEntitiesForDelimiter(
        entities: entities,
        prefixStart: startIndex,
        prefixLen: prefixLen,
        innerLen: codeContent.length,
        suffixLen: suffixLen,
      );

      entities.add(_RawEntity(
        type: 'pre',
        offset: startIndex,
        length: codeContent.length,
        language: (lang != null && lang.isNotEmpty) ? lang : null,
      ));
    }

    // 2. Collapsible blockquote: lines starting with **> (continuation lines may start with **> or >)
    final collapsibleQuoteRegex =
        RegExp(r'(?:^|\n)\*\*>\s?([^\n]+(?:\n(?:\*\*)?>\s?[^\n]+)*)');
    while (true) {
      RegExpMatch? match;
      for (final m in collapsibleQuoteRegex.allMatches(currentText)) {
        final leadingNewline = m.group(0)!.startsWith('\n') ? 1 : 0;
        final s = m.start + leadingNewline;
        final e = m.start + m.group(0)!.length;
        if (!_overlapsEntityTypes(s, e, entities, const {'pre', 'blockquote'})) {
          match = m;
          break;
        }
      }
      if (match == null) break;

      final fullMatch = match.group(0)!;
      final leadingNewline = fullMatch.startsWith('\n') ? 1 : 0;
      final startIndex = match.start + leadingNewline;
      final replaceEnd = match.start + fullMatch.length;
      final blockRaw = currentText.substring(startIndex, replaceEnd);
      final rawLines = blockRaw.split('\n');
      final prefixRegex = RegExp(r'^(?:\*\*)?>\s?');

      int lineOffset = startIndex;
      final cleanedLinesList = <String>[];
      for (final rawLine in rawLines) {
        final pMatch = prefixRegex.firstMatch(rawLine);
        final pLen = pMatch?.group(0)?.length ?? 0;
        final cleanLine = rawLine.substring(pLen);
        cleanedLinesList.add(cleanLine);
        _adjustEntitiesForDelimiter(
          entities: entities,
          prefixStart: lineOffset,
          prefixLen: pLen,
          innerLen: cleanLine.length,
          suffixLen: 0,
        );
        lineOffset += cleanLine.length + 1;
      }

      final cleanedLines = cleanedLinesList.join('\n');
      currentText = currentText.replaceRange(startIndex, replaceEnd, cleanedLines);

      entities.add(_RawEntity(
        type: 'blockquote',
        offset: startIndex,
        length: cleanedLines.length,
        collapsed: true,
      ));
    }

    // 3. Regular blockquote: lines starting with >
    final blockquoteRegex = RegExp(r'(?:^|\n)>\s?([^\n]+(?:\n>\s?[^\n]+)*)');
    while (true) {
      RegExpMatch? match;
      for (final m in blockquoteRegex.allMatches(currentText)) {
        final leadingNewline = m.group(0)!.startsWith('\n') ? 1 : 0;
        final s = m.start + leadingNewline;
        final e = m.start + m.group(0)!.length;
        if (!_overlapsEntityTypes(s, e, entities, const {'pre', 'blockquote'})) {
          match = m;
          break;
        }
      }
      if (match == null) break;

      final fullMatch = match.group(0)!;
      final leadingNewline = fullMatch.startsWith('\n') ? 1 : 0;
      final startIndex = match.start + leadingNewline;
      final replaceEnd = match.start + fullMatch.length;
      final blockRaw = currentText.substring(startIndex, replaceEnd);
      final rawLines = blockRaw.split('\n');
      final prefixRegex = RegExp(r'^>\s?');

      int lineOffset = startIndex;
      final cleanedLinesList = <String>[];
      for (final rawLine in rawLines) {
        final pMatch = prefixRegex.firstMatch(rawLine);
        final pLen = pMatch?.group(0)?.length ?? 0;
        final cleanLine = rawLine.substring(pLen);
        cleanedLinesList.add(cleanLine);
        _adjustEntitiesForDelimiter(
          entities: entities,
          prefixStart: lineOffset,
          prefixLen: pLen,
          innerLen: cleanLine.length,
          suffixLen: 0,
        );
        lineOffset += cleanLine.length + 1;
      }

      final cleanedLines = cleanedLinesList.join('\n');
      currentText = currentText.replaceRange(startIndex, replaceEnd, cleanedLines);

      entities.add(_RawEntity(
        type: 'blockquote',
        offset: startIndex,
        length: cleanedLines.length,
        collapsed: false,
      ));
    }

    // 4. Inline code: `text` (parsed early so its contents are protected from other inline rules)
    _parseInlineDelimiter(
      pattern: RegExp(r'`([^`\n]+?)`'),
      type: 'code',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );

    // 5. Links: [label](url)
    final linkRegex = RegExp(r'\[([^\]]+)\]\(([^\s\)]+)\)');
    while (true) {
      RegExpMatch? match;
      int searchPos = 0;
      while (searchPos < currentText.length) {
        final m = linkRegex.allMatches(currentText, searchPos).firstOrNull;
        if (m == null) break;

        final fullMatch = m.group(0)!;
        final label = m.group(1)!;
        final prefixStart = m.start;
        const prefixLen = 1;
        final suffixStart = prefixStart + prefixLen + label.length;
        final suffixLen = fullMatch.length - prefixLen - label.length;
        final blockingEnd = _getBlockingProtectedEnd(
          prefixStart: prefixStart,
          prefixLen: prefixLen,
          suffixStart: suffixStart,
          suffixLen: suffixLen,
          entities: entities,
          text: currentText,
        );
        if (blockingEnd == -1) {
          match = m;
          break;
        }
        searchPos = blockingEnd > searchPos ? blockingEnd : m.start + 1;
      }
      if (match == null) break;

      final fullMatch = match.group(0)!;
      final label = match.group(1)!;
      final rawUrl = match.group(2)!;
      final url = normalizeUrl(rawUrl);
      final startIndex = match.start;

      currentText = currentText.replaceRange(
        startIndex,
        startIndex + fullMatch.length,
        label,
      );

      _adjustEntitiesForDelimiter(
        entities: entities,
        prefixStart: startIndex,
        prefixLen: 1, // '['
        innerLen: label.length,
        suffixLen: fullMatch.length - 1 - label.length, // '](url)'
      );

      entities.add(_RawEntity(
        type: 'text_link',
        offset: startIndex,
        length: label.length,
        url: url,
      ));
    }

    // 6. Spoilers: ||text||
    _parseInlineDelimiter(
      pattern: RegExp(r'\|\|((?:[^|\n]|\|(?!\|))+?)\|\|'),
      type: 'spoiler',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );

    // 7. Bold: **text** (supports nested single-asterisk *italic* inside **bold**)
    _parseInlineDelimiter(
      pattern: RegExp(r'\*\*(?!\s)((?:\*(?!\s)[^\*\n]+?(?<!\s)\*|[^\*\n])+?)(?<!\s)\*\*'),
      type: 'bold',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );

    // 8. Strikethrough: ~~text~~
    _parseInlineDelimiter(
      pattern: RegExp(r'~~([^~\n]+?)~~'),
      type: 'strikethrough',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );

    // 9. Underline: __text__ or <u>text</u>
    _parseInlineDelimiter(
      pattern: RegExp(
        r'(?<![a-zA-Z0-9_])__(?!\s|_)((?:(?!__)[^\n])+?)(?<!\s|_)__(?![a-zA-Z0-9_])|<u>([\s\S]+?)<\/u>',
      ),
      type: 'underline',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );

    // 10. Italic: *text* (avoiding **) and _text_ (protecting snake_case)
    _parseInlineDelimiter(
      pattern: RegExp(r'(?<!\*)\*(?!\s)([^\*\n]+?)(?<!\s)\*(?!\*)'),
      type: 'italic',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );
    _parseInlineDelimiter(
      pattern: RegExp(r'(?<![a-zA-Z0-9_])_(?!\s)([^\n_]+?)(?<!\s)_(?![a-zA-Z0-9_])'),
      type: 'italic',
      textRef: () => currentText,
      onReplace: (newText) => currentText = newText,
      entities: entities,
    );

    // 11. Raw URLs in remaining clean text that are not yet covered by a link/code/latex
    for (final match in _urlRegex.allMatches(currentText)) {
      final url = match.group(0)!;
      final start = match.start;
      final len = url.length;

      final bool alreadyCovered = _overlapsEntityTypes(
            start,
            start + len,
            entities,
            const {'text_link', 'link', 'url', 'pre', 'code'},
          ) ||
          _getBlockingProtectedEnd(
                prefixStart: start,
                prefixLen: len,
                suffixStart: start + len,
                suffixLen: 0,
                entities: entities,
                text: currentText,
              ) !=
              -1;

      if (!alreadyCovered) {
        entities.add(_RawEntity(
          type: 'url',
          offset: start,
          length: len,
          url: url,
        ));
      }
    }

    // Sort entities primarily by offset ascending, secondarily by length descending (outer first)
    entities.sort((a, b) {
      if (a.offset != b.offset) return a.offset.compareTo(b.offset);
      if (a.length != b.length) return b.length.compareTo(a.length);
      return _entityPriority(a.type).compareTo(_entityPriority(b.type));
    });

    return ParsedMessage(
      cleanText: currentText,
      entities: entities.map((e) => e.toMessageEntity()).toList(),
    );
  }

  static int _entityPriority(String type) {
    switch (type) {
      case 'pre':
      case 'blockquote':
      case 'quote':
      case 'collapse':
      case 'expandable_blockquote':
        return 0;
      case 'spoiler':
        return 1;
      case 'underline':
        return 2;
      case 'text_link':
      case 'link':
      case 'url':
        return 3;
      case 'strikethrough':
        return 4;
      case 'bold':
        return 5;
      case 'italic':
        return 6;
      case 'code':
        return 7;
      default:
        return 8;
    }
  }

  static int _inlineTier(String type) {
    switch (type) {
      case 'spoiler':
        return 0;
      case 'underline':
        return 1;
      case 'text_link':
      case 'link':
      case 'url':
        return 2;
      case 'strikethrough':
        return 3;
      case 'bold':
        return 4;
      case 'italic':
        return 5;
      case 'code':
        return 6;
      default:
        return 7;
    }
  }

  static bool _isBlockType(String type) {
    return type == 'pre' ||
        type == 'blockquote' ||
        type == 'quote' ||
        type == 'collapse' ||
        type == 'expandable_blockquote';
  }

  static bool _isQuoteType(String type) {
    return type == 'blockquote' ||
        type == 'quote' ||
        type == 'collapse' ||
        type == 'expandable_blockquote';
  }

  static void _parseInlineDelimiter({
    required RegExp pattern,
    required String type,
    required String Function() textRef,
    required void Function(String) onReplace,
    required List<_RawEntity> entities,
  }) {
    while (true) {
      final text = textRef();
      RegExpMatch? selectedMatch;
      String innerContent = '';
      int prefixLen = 0;
      int suffixLen = 0;

      int searchPos = 0;
      while (searchPos < text.length) {
        final match = pattern.allMatches(text, searchPos).firstOrNull;
        if (match == null) break;

        final fullMatch = match.group(0)!;
        String candidateInner = '';
        for (int g = 1; g <= match.groupCount; g++) {
          final val = match.group(g);
          if (val != null) {
            candidateInner = val;
            break;
          }
        }
        final pLen = fullMatch.indexOf(candidateInner);
        final sLen = fullMatch.length - pLen - candidateInner.length;
        final sStart = match.start + pLen + candidateInner.length;

        final blockingEnd = _getBlockingProtectedEnd(
          prefixStart: match.start,
          prefixLen: pLen,
          suffixStart: sStart,
          suffixLen: sLen,
          entities: entities,
          text: text,
        );

        if (blockingEnd == -1) {
          selectedMatch = match;
          innerContent = candidateInner;
          prefixLen = pLen;
          suffixLen = sLen;
          break;
        }
        searchPos = blockingEnd > searchPos ? blockingEnd : match.start + 1;
      }

      if (selectedMatch == null) break;

      final fullMatch = selectedMatch.group(0)!;
      final startIndex = selectedMatch.start;
      final matchEnd = startIndex + fullMatch.length;

      final newText = text.replaceRange(startIndex, matchEnd, innerContent);
      onReplace(newText);

      _adjustEntitiesForDelimiter(
        entities: entities,
        prefixStart: startIndex,
        prefixLen: prefixLen,
        innerLen: innerContent.length,
        suffixLen: suffixLen,
      );

      entities.add(_RawEntity(
        type: type,
        offset: startIndex,
        length: innerContent.length,
      ));
    }
  }

  static void _adjustEntitiesForDelimiter({
    required List<_RawEntity> entities,
    required int prefixStart,
    required int prefixLen,
    required int innerLen,
    required int suffixLen,
  }) {
    final prefixEnd = prefixStart + prefixLen;
    final suffixStart = prefixEnd + innerLen;
    final suffixEnd = suffixStart + suffixLen;
    final totalRemoved = prefixLen + suffixLen;

    for (final entity in entities) {
      final entityEnd = entity.offset + entity.length;

      // 1. Entity is completely before the delimiter pair: no change
      if (entityEnd <= prefixStart) {
        continue;
      }

      // 2. Entity is completely after the delimiter pair: shift backwards by total removed
      if (entity.offset >= suffixEnd) {
        entity.offset -= totalRemoved;
        continue;
      }

      // 3. Entity is inside the inner content: shift backwards by prefixLen
      if (entity.offset >= prefixEnd && entityEnd <= suffixStart) {
        entity.offset -= prefixLen;
        continue;
      }

      // 4. Entity completely encloses this delimiter pair: reduce length by total removed
      if (entity.offset <= prefixStart && entityEnd >= suffixEnd) {
        entity.length -= totalRemoved;
        continue;
      }

      // 5. Overlapping boundary edge cases: clamp to inner bounds
      if (entity.offset < prefixEnd && entityEnd > prefixEnd) {
        entity.offset = prefixStart;
        entity.length = (entity.length - prefixLen).clamp(0, innerLen);
      }
    }
  }

  /// Converts clean text and a list of entities back to Markdown syntax.
  ///
  /// Handles:
  /// - Mid-line blockquotes and code blocks (inserting `\n` at start/end as needed).
  /// - Multi-line inline spans (closing before `\n` and reopening on the next line after `> `).
  /// - Partial overlaps (intersections) and arbitrary nesting of inline formatting modes
  ///   by segmenting higher-tier spans at lower-tier boundaries and trimming flanking spaces.
  static String toMarkdown(String cleanText, List<MessageEntity> entities) {
    if (entities.isEmpty || cleanText.isEmpty) {
      return cleanText;
    }

    final validEntities = entities.where((e) {
      return e.offset >= 0 && e.length > 0 && e.offset < cleanText.length;
    }).toList();

    if (validEntities.isEmpty) {
      return cleanText;
    }

    // 1. Normalize and separate block vs inline entities
    final blockEntities = <MessageEntity>[];
    final rawInlineEntities = <MessageEntity>[];

    for (final e in validEntities) {
      int start = e.offset.clamp(0, cleanText.length);
      int end = (e.offset + e.length).clamp(start, cleanText.length);
      if (start >= end) continue;

      if (_isBlockType(e.type)) {
        // Trim leading/trailing newlines so block delimiters align with line content
        while (start < end && cleanText[start] == '\n') {
          start++;
        }
        while (end > start && cleanText[end - 1] == '\n') {
          end--;
        }
        if (start >= end) continue;

        final isQuote = _isQuoteType(e.type);
        final isCollapsed = e.collapsed == true ||
            e.type == 'collapse' ||
            e.type == 'expandable_blockquote';
        blockEntities.add(MessageEntity(
          type: isQuote ? 'blockquote' : 'pre',
          offset: start,
          length: end - start,
          language: e.language,
          collapsed: isQuote ? isCollapsed : null,
        ));
      } else {
        final normalizedType = e.type == 'link' ? 'text_link' : e.type;
        rawInlineEntities.add(MessageEntity(
          type: normalizedType,
          offset: start,
          length: end - start,
          url: e.url,
          language: e.language,
        ));
      }
    }

    // Deduplicate/merge overlapping block entities of the same kind
    blockEntities.sort((a, b) {
      if (a.offset != b.offset) return a.offset.compareTo(b.offset);
      return b.length.compareTo(a.length);
    });
    final mergedBlocks = <MessageEntity>[];
    for (final b in blockEntities) {
      if (mergedBlocks.isNotEmpty) {
        final prev = mergedBlocks.last;
        final prevEnd = prev.offset + prev.length;
        if (prev.type == b.type && b.offset <= prevEnd) {
          final newEnd = (b.offset + b.length) > prevEnd ? (b.offset + b.length) : prevEnd;
          mergedBlocks[mergedBlocks.length - 1] = MessageEntity(
            type: prev.type,
            offset: prev.offset,
            length: newEnd - prev.offset,
            language: prev.language ?? b.language,
            collapsed: (prev.collapsed == true || b.collapsed == true)
                ? true
                : prev.collapsed,
          );
          continue;
        }
      }
      mergedBlocks.add(b);
    }

    // 2. Collect base cut-points for inline entities: all '\n' indices and block boundaries
    final baseCuts = <int>{0, cleanText.length};
    for (int i = 0; i < cleanText.length; i++) {
      if (cleanText[i] == '\n') {
        baseCuts.add(i);
        if (i + 1 <= cleanText.length) baseCuts.add(i + 1);
      }
    }
    for (final b in mergedBlocks) {
      baseCuts.add(b.offset);
      baseCuts.add(b.offset + b.length);
    }

    // Helper to check if a segment [s, e) is inside a 'pre' block
    bool isInsidePre(int s, int e) {
      return mergedBlocks.any(
        (b) => b.type == 'pre' && b.offset <= s && (b.offset + b.length) >= e,
      );
    }

    // 3. Process inline entities tier by tier (0..6) so higher tiers split at lower-tier boundaries
    final segmentedInline = <MessageEntity>[];
    final cumulativeCuts = Set<int>.from(baseCuts);

    // First merge overlapping inline entities of identical (type, url)
    rawInlineEntities.sort((a, b) {
      final tierCmp = _inlineTier(a.type).compareTo(_inlineTier(b.type));
      if (tierCmp != 0) return tierCmp;
      if (a.type != b.type) return a.type.compareTo(b.type);
      final urlCmp = (a.url ?? '').compareTo(b.url ?? '');
      if (urlCmp != 0) return urlCmp;
      if (a.offset != b.offset) return a.offset.compareTo(b.offset);
      return b.length.compareTo(a.length);
    });

    final mergedRawInline = <MessageEntity>[];
    for (final e in rawInlineEntities) {
      if (mergedRawInline.isNotEmpty) {
        final prev = mergedRawInline.last;
        final prevEnd = prev.offset + prev.length;
        if (prev.type == e.type && prev.url == e.url && e.offset <= prevEnd) {
          final newEnd = (e.offset + e.length) > prevEnd ? (e.offset + e.length) : prevEnd;
          mergedRawInline[mergedRawInline.length - 1] = MessageEntity(
            type: prev.type,
            offset: prev.offset,
            length: newEnd - prev.offset,
            url: prev.url,
            language: prev.language,
          );
          continue;
        }
      }
      mergedRawInline.add(e);
    }

    for (int tier = 0; tier <= 6; tier++) {
      final tierEntities =
          mergedRawInline.where((e) => _inlineTier(e.type) == tier).toList();
      if (tierEntities.isEmpty) continue;

      final sortedCuts = cumulativeCuts.toList()..sort();
      final nextCuts = <int>[];

      for (final e in tierEntities) {
        final eStart = e.offset;
        final eEnd = e.offset + e.length;

        // Find all cut points strictly within [eStart, eEnd]
        final points = <int>[eStart];
        for (final c in sortedCuts) {
          if (c > eStart && c < eEnd) {
            points.add(c);
          }
        }
        points.add(eEnd);

        for (int p = 0; p < points.length - 1; p++) {
          int segStart = points[p];
          int segEnd = points[p + 1];
          if (segStart >= segEnd) continue;

          // Skip newline characters
          while (segStart < segEnd && cleanText[segStart] == '\n') {
            segStart++;
          }
          while (segEnd > segStart && cleanText[segEnd - 1] == '\n') {
            segEnd--;
          }
          if (segStart >= segEnd) continue;

          // Skip inline formatting inside 'pre' code blocks
          if (isInsidePre(segStart, segEnd)) continue;

          // Trim flanking horizontal whitespace for emphasis/spoiler/underline/strikethrough
          // so CommonMark flanking rules are always satisfied.
          if (e.type == 'bold' ||
              e.type == 'italic' ||
              e.type == 'strikethrough' ||
              e.type == 'underline' ||
              e.type == 'spoiler') {
            while (segStart < segEnd &&
                (cleanText[segStart] == ' ' || cleanText[segStart] == '\t')) {
              segStart++;
            }
            while (segEnd > segStart &&
                (cleanText[segEnd - 1] == ' ' ||
                    cleanText[segEnd - 1] == '\t')) {
              segEnd--;
            }
          }
          if (segStart >= segEnd) continue;

          final sub = MessageEntity(
            type: e.type,
            offset: segStart,
            length: segEnd - segStart,
            url: e.url,
            language: e.language,
          );
          segmentedInline.add(sub);
          nextCuts.add(segStart);
          nextCuts.add(segEnd);
        }
      }

      cumulativeCuts.addAll(nextCuts);
    }

    // 4. Build opening and closing maps for blocks and inline segments
    final blockOpenings = <int, List<MessageEntity>>{};
    final blockClosings = <int, List<MessageEntity>>{};
    for (final b in mergedBlocks) {
      blockOpenings.putIfAbsent(b.offset, () => []).add(b);
      blockClosings.putIfAbsent(b.offset + b.length, () => []).add(b);
    }

    final inlineOpenings = <int, List<MessageEntity>>{};
    final inlineClosings = <int, List<MessageEntity>>{};
    final orderMap = <MessageEntity, int>{};
    for (int i = 0; i < segmentedInline.length; i++) {
      final e = segmentedInline[i];
      orderMap[e] = i;
      inlineOpenings.putIfAbsent(e.offset, () => []).add(e);
      inlineClosings.putIfAbsent(e.offset + e.length, () => []).add(e);
    }

    // Outer inline opens first: lower tier -> longer length -> earlier index
    for (final list in inlineOpenings.values) {
      list.sort((a, b) {
        final tierCmp = _inlineTier(a.type).compareTo(_inlineTier(b.type));
        if (tierCmp != 0) return tierCmp;
        if (a.length != b.length) return b.length.compareTo(a.length);
        return orderMap[a]!.compareTo(orderMap[b]!);
      });
    }

    // Inner inline closes first: higher tier -> shorter length -> reverse index (LIFO)
    for (final list in inlineClosings.values) {
      list.sort((a, b) {
        final tierCmp = _inlineTier(b.type).compareTo(_inlineTier(a.type));
        if (tierCmp != 0) return tierCmp;
        if (a.length != b.length) return a.length.compareTo(b.length);
        return orderMap[b]!.compareTo(orderMap[a]!);
      });
    }

    final buffer = StringBuffer();
    final activeBlockquotes = <MessageEntity>[];

    for (int i = 0; i <= cleanText.length; i++) {
      // 1. Close inline entities ending at index i
      if (inlineClosings.containsKey(i)) {
        for (final entity in inlineClosings[i]!) {
          buffer.write(_getClosingTag(entity, cleanText));
        }
      }

      // 2. Close block entities ending at index i
      if (blockClosings.containsKey(i)) {
        for (final entity in blockClosings[i]!) {
          if (entity.type == 'blockquote') {
            activeBlockquotes.remove(entity);
            // If blockquote ends mid-line, emit a newline so following text is not swallowed into the quote
            if (i < cleanText.length && cleanText[i] != '\n') {
              buffer.write('\n');
            }
          } else {
            buffer.write(_getClosingTag(entity, cleanText));
            if (i < cleanText.length && cleanText[i] != '\n') {
              buffer.write('\n');
            }
          }
        }
      }

      // 3. Open block entities starting at index i
      if (blockOpenings.containsKey(i)) {
        for (final entity in blockOpenings[i]!) {
          // If block starts mid-line, emit a newline first so '>' or '```' starts at column 0
          if (i > 0 && cleanText[i - 1] != '\n') {
            buffer.write('\n');
          }
          if (entity.type == 'blockquote') {
            activeBlockquotes.add(entity);
          }
          buffer.write(_getOpeningTag(entity));
        }
      }

      // 4. Open inline entities starting at index i
      if (inlineOpenings.containsKey(i)) {
        for (final entity in inlineOpenings[i]!) {
          buffer.write(_getOpeningTag(entity));
        }
      }

      // 5. Write character at index i (if before end)
      if (i < cleanText.length) {
        final char = cleanText[i];
        buffer.write(char);
        // If character was a newline and we are still inside a blockquote on the next character, prefix the new line
        if (char == '\n' && activeBlockquotes.isNotEmpty) {
          final bq = activeBlockquotes.last;
          if (i + 1 < bq.offset + bq.length) {
            buffer.write(bq.collapsed == true ? '**> ' : '> ');
          }
        }
      }
    }

    return buffer.toString();
  }

  static String _getOpeningTag(MessageEntity entity) {
    switch (entity.type) {
      case 'bold':
        return '**';
      case 'italic':
        return '*';
      case 'strikethrough':
        return '~~';
      case 'underline':
        return '__';
      case 'code':
        return '`';
      case 'pre':
        final lang = entity.language ?? '';
        return '```$lang\n';
      case 'spoiler':
        return '||';
      case 'blockquote':
      case 'quote':
      case 'collapse':
      case 'expandable_blockquote':
        return (entity.collapsed == true ||
                entity.type == 'collapse' ||
                entity.type == 'expandable_blockquote')
            ? '**> '
            : '> ';
      case 'url':
      case 'text_link':
      case 'link':
        return '[';
      default:
        return '';
    }
  }

  static String _getClosingTag(MessageEntity entity, String cleanText) {
    switch (entity.type) {
      case 'bold':
        return '**';
      case 'italic':
        return '*';
      case 'strikethrough':
        return '~~';
      case 'underline':
        return '__';
      case 'code':
        return '`';
      case 'pre':
        return '\n```';
      case 'spoiler':
        return '||';
      case 'blockquote':
      case 'quote':
      case 'collapse':
      case 'expandable_blockquote':
        return '';
      case 'url':
      case 'text_link':
      case 'link':
        final rawUrl = entity.url ??
            (entity.offset + entity.length <= cleanText.length
                ? cleanText.substring(entity.offset, entity.offset + entity.length)
                : '');
        final targetUrl = normalizeUrl(rawUrl);
        return ']($targetUrl)';
      default:
        return '';
    }
  }

  /// Applies formatting tokens around the user's current selection.
  static void applyFormatting({
    required TextEditingController controller,
    required String formatType,
    String? url,
    String? language,
  }) {
    final selection = controller.selection;
    final text = controller.text;
    final int start;
    final int end;
    final String selectedText;

    if (!selection.isValid) {
      start = text.length;
      end = text.length;
      selectedText = '';
    } else if (selection.isCollapsed) {
      start = selection.baseOffset.clamp(0, text.length);
      end = start;
      selectedText = '';
    } else {
      start = selection.start;
      end = selection.end;
      selectedText = text.substring(start, end);
    }

    String prefix = '';
    String suffix = '';

    switch (formatType) {
      case 'bold':
        prefix = '**';
        suffix = '**';
        break;
      case 'italic':
        prefix = '*';
        suffix = '*';
        break;
      case 'strikethrough':
        prefix = '~~';
        suffix = '~~';
        break;
      case 'underline':
        prefix = '__';
        suffix = '__';
        break;
      case 'code':
        prefix = '`';
        suffix = '`';
        break;
      case 'pre':
        final lang = language ?? '';
        prefix = '```$lang\n';
        suffix = '\n```';
        break;
      case 'spoiler':
        prefix = '||';
        suffix = '||';
        break;
      case 'quote':
        prefix = '> ';
        suffix = '';
        break;
      case 'collapse':
      case 'collapsible_quote':
        prefix = '**> ';
        suffix = '';
        break;
      case 'link':
        final targetUrl = url ?? 'https://';
        prefix = '[';
        suffix = ']($targetUrl)';
        break;
      case 'clear':
        if (selectedText.isEmpty) return;
        final cleaned = selectedText
            .replaceAll(RegExp(r'^\*\*|\*\*$'), '')
            .replaceAll(RegExp(r'^\*|\*$'), '')
            .replaceAll(RegExp(r'^`|`$'), '')
            .replaceAll(RegExp(r'^\|\||\|\|$'), '')
            .replaceAll(RegExp(r'^~~|~~$'), '')
            .replaceAll(RegExp(r'^__|^--|__$|--$'), '')
            .replaceAll(RegExp(r'^<u>|</u>$'), '')
            .replaceAll(RegExp(r'^\*\*>\s?'), '')
            .replaceAll(RegExp(r'^>\s?'), '');
        final newText = text.replaceRange(start, end, cleaned);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + cleaned.length,
          ),
        );
        return;
      default:
        return;
    }

    final formatted = '$prefix$selectedText$suffix';
    final newText = text.replaceRange(start, end, formatted);
    final newSelectionStart = start + prefix.length;
    final newSelectionEnd = selectedText.isEmpty
        ? newSelectionStart
        : newSelectionStart + selectedText.length;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: newSelectionStart,
        extentOffset: newSelectionEnd,
      ),
    );
  }
}
