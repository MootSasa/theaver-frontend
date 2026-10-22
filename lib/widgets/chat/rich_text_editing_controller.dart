import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/chat_service.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/entity_parser.dart';

/// Span representing rich text formatting without markdown delimiters.
class RichSpan {
  int start;
  int end;
  final String type; // bold, italic, strikethrough, underline, code, spoiler, blockquote, collapse, text_link
  final String? url;
  final String? language;

  RichSpan({
    required this.start,
    required this.end,
    required this.type,
    this.url,
    this.language,
  });

  RichSpan copyWith({int? start, int? end}) => RichSpan(
        start: start ?? this.start,
        end: end ?? this.end,
        type: type,
        url: url,
        language: language,
      );

  MessageEntity toMessageEntity() => MessageEntity(
        type: (type == 'collapse' || type == 'quote')
            ? 'blockquote'
            : (type == 'link' ? 'text_link' : type),
        offset: start,
        length: end - start,
        url: url,
        language: language,
        collapsed: type == 'collapse' ? true : (type == 'blockquote' || type == 'quote' ? false : null),
      );
}

/// Rich text editing controller that formats text in-place without inserting raw markdown characters.
///
/// Supports:
/// - Selecting text and applying formatting directly.
/// - Toggling active formatting when no text is selected (changing cursor appearance).
/// - Dynamic cursor appearance based on [activeFormat].
/// - Exporting clean text and entities for sending.
class RichTextEditingController extends TextEditingController {
  final List<RichSpan> _spans = [];
  final Set<String> _activeFormats = <String>{};
  String _lastText = '';

  /// Returns unmodifiable list of rich text spans.
  List<RichSpan> get spans => List.unmodifiable(_spans);

  /// Returns unmodifiable set of currently active formats for newly typed text.
  Set<String> get activeFormats => Set.unmodifiable(_activeFormats);

  RichTextEditingController({String? text, List<MessageEntity>? initialEntities})
      : super(text: text ?? '') {
    _lastText = this.text;
    if (initialEntities != null && initialEntities.isNotEmpty) {
      for (final e in initialEntities) {
        _spans.add(RichSpan(
          start: e.offset,
          end: e.offset + e.length,
          type: e.type == 'blockquote' && e.collapsed == true ? 'collapse' : e.type,
          url: e.url,
          language: e.language,
        ));
      }
    }
  }

  static String _normalizeType(String formatType) {
    if (formatType == 'link') return 'text_link';
    if (formatType == 'quote') return 'blockquote';
    return formatType;
  }

  static bool _matchesType(String spanType, String normalizedTarget) {
    if (normalizedTarget == 'text_link') {
      return spanType == 'text_link' || spanType == 'link';
    }
    if (normalizedTarget == 'blockquote') {
      return spanType == 'blockquote' || spanType == 'quote';
    }
    return spanType == normalizedTarget;
  }

  /// Loads message content and its entities for editing in-place without markdown delimiters.
  void loadMessage(String content, [List<MessageEntity>? initialEntities]) {
    _spans.clear();
    _activeFormats.clear();

    if (initialEntities != null && initialEntities.isNotEmpty) {
      value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
      for (final e in initialEntities) {
        final start = e.offset.clamp(0, content.length);
        final end = (e.offset + e.length).clamp(start, content.length);
        if (start < end) {
          _spans.add(RichSpan(
            start: start,
            end: end,
            type: e.type == 'blockquote' && e.collapsed == true
                ? 'collapse'
                : (e.type == 'link' ? 'text_link' : e.type),
            url: e.url,
            language: e.language,
          ));
        }
      }
      _mergeSpans();
    } else {
      final parsed = EntityParser.parseMarkdown(content);
      if (parsed.entities.isNotEmpty) {
        value = TextEditingValue(
          text: parsed.cleanText,
          selection: TextSelection.collapsed(offset: parsed.cleanText.length),
        );
        for (final e in parsed.entities) {
          final start = e.offset.clamp(0, parsed.cleanText.length);
          final end = (e.offset + e.length).clamp(start, parsed.cleanText.length);
          if (start < end) {
            _spans.add(RichSpan(
              start: start,
              end: end,
              type: e.type == 'blockquote' && e.collapsed == true
                  ? 'collapse'
                  : (e.type == 'link' ? 'text_link' : e.type),
              url: e.url,
              language: e.language,
            ));
          }
        }
        _mergeSpans();
      } else {
        value = TextEditingValue(
          text: content,
          selection: TextSelection.collapsed(offset: content.length),
        );
      }
    }

    _lastText = text;
    notifyListeners();
  }

  /// Finds any link span covering [offset].
  RichSpan? getLinkSpanAt(int offset) {
    for (final s in _spans) {
      if ((s.type == 'text_link' || s.type == 'link') &&
          s.start <= offset &&
          s.end >= offset) {
        return s;
      }
    }
    return null;
  }

  /// Finds any link span intersecting [selection].
  RichSpan? getLinkSpanForSelection(TextSelection selection) {
    if (!selection.isValid) return null;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    if (start == end) {
      return getLinkSpanAt(start);
    }
    for (final s in _spans) {
      if ((s.type == 'text_link' || s.type == 'link') &&
          (s.start < end && s.end > start)) {
        return s;
      }
    }
    return null;
  }

  /// Applies or updates a link on the given range or current selection.
  void applyLinkToSelection(String url,
      {int? start, int? end, String? replacementText}) {
    int s = start ??
        (selection.isValid ? math.min(selection.start, selection.end) : 0);
    int e = end ??
        (selection.isValid ? math.max(selection.start, selection.end) : 0);

    if (replacementText != null) {
      final oldText = text;
      final newText = oldText.replaceRange(s, e, replacementText);
      e = s + replacementText.length;
      value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: e),
      );
    }

    if (s >= e) return;

    // Remove or split any overlapping link spans
    _removeTypeInRange(s, e, 'text_link');

    _spans.add(RichSpan(
      start: s,
      end: e,
      type: 'text_link',
      url: EntityParser.normalizeUrl(url),
    ));

    _mergeSpans();
    notifyListeners();
  }

  /// Removes link formatting covering the selection or range, preserving text.
  void removeLinkFromSelection({int? start, int? end}) {
    int s = start ??
        (selection.isValid ? math.min(selection.start, selection.end) : 0);
    int e = end ??
        (selection.isValid ? math.max(selection.start, selection.end) : 0);

    if (s == e && selection.isValid) {
      final link = getLinkSpanAt(s);
      if (link != null) {
        s = link.start;
        e = link.end;
      }
    }

    if (s >= e) return;

    _removeTypeInRange(s, e, 'text_link');

    _mergeSpans();
    notifyListeners();
  }

  /// Clears rich formatting on the current selection.
  void clearFormatting() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      if (_activeFormats.isNotEmpty) {
        _activeFormats.clear();
        notifyListeners();
      }
      return;
    }
    final start = math.min(sel.start, sel.end);
    final end = math.max(sel.start, sel.end);
    for (int i = _spans.length - 1; i >= 0; i--) {
      final s = _spans[i];
      if (s.start < end && s.end > start) {
        _spans.removeAt(i);
        if (s.start < start) {
          _spans.add(s.copyWith(end: start));
        }
        if (s.end > end) {
          _spans.add(s.copyWith(start: end));
        }
      }
    }
    _mergeSpans();
    notifyListeners();
  }

  /// Currently active format mode for newly typed characters (returns most recently activated format, if any).
  String? get activeFormat => _activeFormats.isEmpty ? null : _activeFormats.last;

  set activeFormat(String? format) {
    if (format == null) {
      if (_activeFormats.isNotEmpty) {
        _activeFormats.clear();
        notifyListeners();
      }
    } else {
      if (_activeFormats.length != 1 || !_activeFormats.contains(format)) {
        _activeFormats
          ..clear()
          ..add(format);
        notifyListeners();
      }
    }
  }

  /// Returns true if [format] is currently active for the selection or cursor.
  bool isFormatActive(String format) {
    final normalized = _normalizeType(format);
    if (selection.isValid && !selection.isCollapsed) {
      final start = math.min(selection.start, selection.end);
      final end = math.max(selection.start, selection.end);
      if (start < end) {
        return _isRangeCoveredByType(start, end, normalized);
      }
    }
    if (normalized == 'blockquote') {
      return _activeFormats.contains('blockquote') || _activeFormats.contains('quote');
    }
    return _activeFormats.contains(format) || _activeFormats.contains(normalized);
  }

  bool _isRangeCoveredByType(int start, int end, String normalizedType) {
    if (start >= end) return false;
    final matching = _spans
        .where((s) =>
            _matchesType(s.type, normalizedType) && s.start < end && s.end > start)
        .toList();
    if (matching.isEmpty) return false;
    matching.sort((a, b) => a.start.compareTo(b.start));
    int coveredUntil = start;
    for (final s in matching) {
      if (s.start > coveredUntil) return false;
      if (s.end > coveredUntil) coveredUntil = s.end;
      if (coveredUntil >= end) return true;
    }
    return coveredUntil >= end;
  }

  void _removeTypeInRange(int start, int end, String normalizedType) {
    for (int i = _spans.length - 1; i >= 0; i--) {
      final span = _spans[i];
      if (_matchesType(span.type, normalizedType) &&
          span.start < end &&
          span.end > start) {
        _spans.removeAt(i);
        if (span.start < start) {
          _spans.add(span.copyWith(end: start));
        }
        if (span.end > end) {
          _spans.add(span.copyWith(start: end));
        }
      }
    }
  }

  /// Returns true if the cursor should be displayed in italic (slanted) style.
  /// This is true if 'italic' is active, or if the collapsed selection
  /// is positioned strictly inside an italic span.
  bool get isCursorItalic {
    if (_activeFormats.contains('italic')) {
      return true;
    }
    if (!selection.isValid || !selection.isCollapsed) return false;
    final offset = selection.baseOffset;
    if (offset < 0) return false;
    return _spans.any((s) => s.type == 'italic' && s.start < offset && s.end > offset);
  }

  /// Toggles an active format mode when cursor is collapsed (supports stacking multiple modes).
  void toggleActiveFormat(String format) {
    if (format == 'quote' || format == 'blockquote') {
      final wasActive =
          _activeFormats.remove('quote') | _activeFormats.remove('blockquote');
      if (!wasActive) {
        _activeFormats.remove('collapse');
        _activeFormats.add(format);
      }
    } else if (format == 'collapse') {
      final wasActive = _activeFormats.remove('collapse');
      if (!wasActive) {
        _activeFormats.remove('quote');
        _activeFormats.remove('blockquote');
        _activeFormats.add('collapse');
      }
    } else {
      if (!_activeFormats.remove(format)) {
        _activeFormats.add(format);
      }
    }
    notifyListeners();
  }

  /// Applies formatting to selection or toggles active format.
  void applyFormat(String formatType, {String? url, String? language}) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      // No selection: toggle active format for cursor!
      toggleActiveFormat(formatType);
      return;
    }

    int start = math.min(sel.start, sel.end);
    int end = math.max(sel.start, sel.end);
    if (start == end) return;

    final normalizedType = _normalizeType(formatType);
    if (normalizedType == 'text_link' && url != null) {
      applyLinkToSelection(url, start: start, end: end);
      return;
    }

    // For blockquotes, trim leading/trailing newlines from the selection so
    // following lines or paragraphs are not swallowed into the quote span.
    if (normalizedType == 'blockquote' || normalizedType == 'collapse') {
      while (start < end && (text[start] == '\n' || text[start] == '\r')) {
        start++;
      }
      while (end > start && (text[end - 1] == '\n' || text[end - 1] == '\r')) {
        end--;
      }
      if (start >= end) return;
    }

    // Check if entire selection already has this format: toggle it off across the range
    if (_isRangeCoveredByType(start, end, normalizedType)) {
      _removeTypeInRange(start, end, normalizedType);
      _mergeSpans();
    } else {
      // Regular blockquote and collapsible blockquote are mutually exclusive on the same range
      if (normalizedType == 'blockquote') {
        _removeTypeInRange(start, end, 'collapse');
      } else if (normalizedType == 'collapse') {
        _removeTypeInRange(start, end, 'blockquote');
      }

      // Add formatting span (combining/stacking with any other formats on the range)
      _spans.add(RichSpan(
        start: start,
        end: end,
        type: normalizedType,
        url: url,
        language: language,
      ));
      _mergeSpans();
    }

    notifyListeners();
  }

  /// Returns clean plain text without any markdown delimiters.
  String get cleanText {
    if (_spans.isEmpty) {
      return EntityParser.parseMarkdown(text).cleanText;
    }
    return text;
  }

  /// Converts the current text and formatting entities into a markdown formatted string.
  String toMarkdown() => EntityParser.toMarkdown(cleanText, entities);

  /// Returns computed message entities matching the styled spans, plus any raw URLs.
  List<MessageEntity> get entities {
    List<MessageEntity> result = [];
    final effectiveText = cleanText;
    if (_spans.isEmpty) {
      // If user typed markdown tokens manually, fallback to parseMarkdown
      final parsed = EntityParser.parseMarkdown(text);
      result = List.from(parsed.entities);
    } else {
      result = _spans
          .where((s) => s.start < s.end && s.start < text.length)
          .map((s) => s
              .copyWith(end: math.min(s.end, text.length))
              .toMessageEntity())
          .toList();
    }

    // Also detect any raw URLs in text not covered by existing link/code entities
    for (final match in EntityParser.urlRegex.allMatches(effectiveText)) {
      final url = match.group(0)!;
      final start = match.start;
      final len = url.length;
      final bool covered = result.any((e) =>
          (e.type == 'text_link' ||
              e.type == 'link' ||
              e.type == 'url' ||
              e.type == 'code' ||
              e.type == 'pre') &&
          e.offset <= start &&
          (e.offset + e.length) >= (start + len));
      if (!covered) {
        result.add(MessageEntity(
          type: 'url',
          offset: start,
          length: len,
          url: url,
        ));
      }
    }

    result.sort((a, b) => a.offset.compareTo(b.offset));
    return result;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldText = _lastText;
    final newText = newValue.text;

    if (oldText != newText) {
      _updateSpansForTextChange(oldText, newText);
      _lastText = newText;
    }

    super.value = newValue;
  }

  void _updateSpansForTextChange(String oldText, String newText) {
    int start = 0;
    while (start < oldText.length && start < newText.length && oldText[start] == newText[start]) {
      start++;
    }

    int oldEnd = oldText.length;
    int newEnd = newText.length;
    while (oldEnd > start && newEnd > start && oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }

    final int deletedCount = oldEnd - start;
    final int insertedCount = newEnd - start;
    final int delta = insertedCount - deletedCount;

    // Adjust existing spans
    for (int i = _spans.length - 1; i >= 0; i--) {
      final span = _spans[i];

      if (span.end <= start) {
        // Change occurred at or after span end: unchanged
        // (If activeFormats contains this span's type, the inserted range will be added and merged below)
        continue;
      } else if (span.start >= oldEnd) {
        // Change occurred before span: shift
        span.start += delta;
        span.end += delta;
      } else {
        // Change overlaps with span interior
        if (deletedCount > 0) {
          final delInSpan = (math.min(span.end, oldEnd) - math.max(span.start, start)).toInt();
          if (start < span.start) {
            span.start = start;
          }
          span.end -= delInSpan;
        }
        if (insertedCount > 0 && span.start < start && start < span.end) {
          span.end += insertedCount;
        } else if (insertedCount > 0 && span.start >= start) {
          span.start += insertedCount;
          span.end += insertedCount;
        }
      }

      if (span.start >= span.end || span.start >= newText.length) {
        _spans.removeAt(i);
      }
    }

    // If user typed a blank line (\n\n) while quote mode is active, exit quote mode automatically
    final bool hasActiveQuote = _activeFormats.contains('quote') ||
        _activeFormats.contains('blockquote') ||
        _activeFormats.contains('collapse');
    if (insertedCount > 0 && hasActiveQuote) {
      final insertedStr = newText.substring(start, start + insertedCount);
      final bool isDoubleNewline = insertedStr.contains('\n\n') ||
          (insertedStr.startsWith('\n') && start > 0 && newText[start - 1] == '\n');
      if (isDoubleNewline) {
        _activeFormats.remove('quote');
        _activeFormats.remove('blockquote');
        _activeFormats.remove('collapse');
      }
    }

    // If new text was typed and activeFormats is non-empty, apply all active formats to the inserted range
    if (insertedCount > 0 && _activeFormats.isNotEmpty) {
      for (final fmt in _activeFormats) {
        _spans.add(RichSpan(
          start: start,
          end: start + insertedCount,
          type: _normalizeType(fmt),
        ));
      }
      _mergeSpans();
    }

    final bool quoteStillActive = _activeFormats.contains('quote') ||
        _activeFormats.contains('blockquote') ||
        _activeFormats.contains('collapse');

    // Clamp spans within [0, newText.length] and prevent quote spans from stretching across trailing newlines
    for (final span in _spans) {
      span.start = span.start.clamp(0, newText.length);
      span.end = span.end.clamp(span.start, newText.length);
      if (span.type == 'blockquote' ||
          span.type == 'quote' ||
          span.type == 'collapse') {
        while (span.start < span.end &&
            (newText[span.start] == '\n' || newText[span.start] == '\r')) {
          span.start++;
        }
        if (!quoteStillActive) {
          while (span.end > span.start &&
              (newText[span.end - 1] == '\n' || newText[span.end - 1] == '\r')) {
            span.end--;
          }
        }
      }
    }
    _spans.removeWhere((s) => s.start >= s.end);
  }

  void _mergeSpans() {
    _spans.sort((a, b) {
      final typeA = _normalizeType(a.type);
      final typeB = _normalizeType(b.type);
      final typeCmp = typeA.compareTo(typeB);
      if (typeCmp != 0) return typeCmp;
      final urlCmp = (a.url ?? '').compareTo(b.url ?? '');
      if (urlCmp != 0) return urlCmp;
      if (a.start != b.start) return a.start.compareTo(b.start);
      return a.end.compareTo(b.end);
    });

    for (int i = 0; i < _spans.length - 1; i++) {
      final cur = _spans[i];
      final next = _spans[i + 1];
      if (_normalizeType(cur.type) == _normalizeType(next.type) &&
          cur.url == next.url &&
          cur.end >= next.start) {
        cur.end = math.max(cur.end, next.end);
        _spans.removeAt(i + 1);
        i--;
      }
    }

    _spans.sort((a, b) {
      if (a.start != b.start) return a.start.compareTo(b.start);
      return a.end.compareTo(b.end);
    });
  }

  @override
  void clear() {
    _spans.clear();
    _activeFormats.clear();
    _lastText = '';
    super.clear();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    // Collect all boundary points
    final points = <int>{0, text.length};
    for (final s in _spans) {
      if (s.start >= 0 && s.start <= text.length) points.add(s.start);
      if (s.end >= 0 && s.end <= text.length) points.add(s.end);
    }

    final sortedPoints = points.toList()..sort();
    final children = <InlineSpan>[];

    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final segStart = sortedPoints[i];
      final segEnd = sortedPoints[i + 1];
      if (segStart >= segEnd) continue;

      final segText = text.substring(segStart, segEnd);

      // Find all spans covering this segment
      final activeSpans = _spans.where((s) => s.start <= segStart && s.end >= segEnd).toList();

      TextStyle segStyle = style ?? const TextStyle(fontSize: 17.0);

      final hasLink = activeSpans.any((s) => s.type == 'text_link' || s.type == 'link');
      final hasQuote = activeSpans.any((s) =>
          s.type == 'quote' || s.type == 'collapse' || s.type == 'blockquote');
      final hasSpoiler = activeSpans.any((s) => s.type == 'spoiler');

      // 1. Base text color (Blockquote -> Link -> Spoiler)
      if (hasQuote && !hasLink) {
        segStyle = segStyle.copyWith(
          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1C2530),
        );
      }
      if (hasLink) {
        segStyle = segStyle.copyWith(color: primaryColor);
      }
      if (hasSpoiler) {
        segStyle = segStyle.copyWith(
          backgroundColor: Colors.transparent,
          color: isDark ? Colors.white38 : Colors.black38,
        );
      }

      // 2. Combine decorations (after color is resolved so decorationColor matches)
      final hasStrike = activeSpans.any((s) => s.type == 'strikethrough');
      final hasUnderline =
          activeSpans.any((s) => s.type == 'underline') || hasLink;
      if (hasStrike && hasUnderline) {
        segStyle = segStyle.copyWith(
          decoration: TextDecoration.combine(
              [TextDecoration.lineThrough, TextDecoration.underline]),
          decorationColor: segStyle.color,
          decorationThickness: 1.5,
        );
      } else if (hasStrike) {
        segStyle = segStyle.copyWith(
          decoration: TextDecoration.lineThrough,
          decorationColor: segStyle.color,
        );
      } else if (hasUnderline) {
        segStyle = segStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: segStyle.color,
          decorationThickness: 1.5,
        );
      }

      // 3. Bold
      if (activeSpans.any((s) => s.type == 'bold')) {
        segStyle = segStyle.copyWith(fontWeight: FontWeight.bold);
      }

      // 4. Italic (only when explicitly italic, not forced by quote)
      if (activeSpans.any((s) => s.type == 'italic')) {
        segStyle = segStyle.copyWith(fontStyle: FontStyle.italic);
      }

      // 5. Monospace
      if (activeSpans.any((s) => s.type == 'code' || s.type == 'pre')) {
        segStyle = segStyle.copyWith(fontFamily: 'monospace');
      }

      // Check for emojis
      if (EmojiUtils.isFontLoaded.value && EmojiUtils.emojiRegex.hasMatch(segText)) {
        final buffer = StringBuffer();
        for (final cluster in segText.characters) {
          if (EmojiUtils.isEmojiGrapheme(cluster)) {
            if (buffer.isNotEmpty) {
              children.add(TextSpan(text: buffer.toString(), style: segStyle));
              buffer.clear();
            }
            children.add(TextSpan(
              text: cluster,
              style: segStyle.copyWith(
                fontFamily: EmojiUtils.effectiveFontFamily,
              ),
            ));
          } else {
            buffer.write(cluster);
          }
        }
        if (buffer.isNotEmpty) {
          children.add(TextSpan(text: buffer.toString(), style: segStyle));
        }
      } else {
        children.add(TextSpan(text: segText, style: segStyle));
      }
    }

    return TextSpan(style: style, children: children);
  }
}

/// Backwards-compatible alias for [RichTextEditingController].
class MarkdownTextEditingController extends RichTextEditingController {
  MarkdownTextEditingController({String? text, List<MessageEntity>? initialEntities})
      : super(text: text, initialEntities: initialEntities);
}
