import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/browser_reader_mode_script.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../design_system/theav_design_system.dart';

const List<String> _kSerifFallback = <String>[
  'Georgia',
  'Times New Roman',
  'Noto Serif',
  'serif',
];

const List<String> _kMonoFallback = <String>[
  'JetBrains Mono',
  'Menlo',
  'Consolas',
  'Courier New',
  'monospace',
];

/// Color palette resolved for Safari Reader Mode across the 4 built-in themes
/// (`light`, `sepia`, `dark`, `oled`).
class SafariReaderThemeColors {
  final String id;
  final Color background;
  final Color text;
  final Color secondary;
  final Color quoteBg;
  final Color codeBg;
  final Color accent;
  final Color divider;
  final bool isDark;

  const SafariReaderThemeColors({
    required this.id,
    required this.background,
    required this.text,
    required this.secondary,
    required this.quoteBg,
    required this.codeBg,
    required this.accent,
    required this.divider,
    required this.isDark,
  });

  factory SafariReaderThemeColors.resolve(
    String themeId,
    TheavPalette palette,
  ) {
    switch (themeId) {
      case 'sepia':
        return SafariReaderThemeColors(
          id: 'sepia',
          background: const Color(0xFFF4ECD8),
          text: const Color(0xFF3D3122),
          secondary: const Color(0xFF7A6A55),
          quoteBg: const Color(0xFFEAE0C8),
          codeBg: const Color(0xFFEAE0C8),
          accent: palette.primary,
          divider: const Color(0xFF3D3122).withValues(alpha: 0.14),
          isDark: false,
        );
      case 'dark':
        return SafariReaderThemeColors(
          id: 'dark',
          background: const Color(0xFF1C1C1E),
          text: const Color(0xFFE5E5EA),
          secondary: const Color(0xFF8E8E93),
          quoteBg: const Color(0xFF2C2C2E),
          codeBg: const Color(0xFF2C2C2E),
          accent: palette.primary,
          divider: const Color(0xFFE5E5EA).withValues(alpha: 0.14),
          isDark: true,
        );
      case 'oled':
        return SafariReaderThemeColors(
          id: 'oled',
          background: const Color(0xFF000000),
          text: const Color(0xFFE5E5EA),
          secondary: const Color(0xFF8E8E93),
          quoteBg: const Color(0xFF161618),
          codeBg: const Color(0xFF161618),
          accent: palette.primary,
          divider: const Color(0xFFE5E5EA).withValues(alpha: 0.14),
          isDark: true,
        );
      case 'light':
      default:
        return SafariReaderThemeColors(
          id: 'light',
          background: const Color(0xFFFAF9F6),
          text: const Color(0xFF1C1C1E),
          secondary: const Color(0xFF636366),
          quoteBg: const Color(0xFFEFECE6),
          codeBg: const Color(0xFFEFECE6),
          accent: palette.primary,
          divider: const Color(0xFF1C1C1E).withValues(alpha: 0.12),
          isDark: false,
        );
    }
  }
}

String _cleanReaderStr(Object? value) =>
    value == null ? '' : value.toString().trim();

int _parsePositiveInt(Object? value) {
  if (value is int) return value > 0 ? value : 0;
  if (value is num) {
    final v = value.round();
    return v > 0 ? v : 0;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    return (parsed != null && parsed > 0) ? parsed : 0;
  }
  return 0;
}

int _parseHeadingLevel(Object? value) {
  final int raw = _parsePositiveInt(value);
  if (raw <= 0) return 2;
  return raw.clamp(1, 4);
}

List<String> _extractBlockItems(Object? rawItems) {
  if (rawItems is! Iterable) return const <String>[];
  return rawItems
      .map(_cleanReaderStr)
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

({String? family, List<String>? fallback}) _resolveReaderFont(
  String fontFamilyId,
) {
  switch (fontFamilyId) {
    case 'serif':
      return (family: 'serif', fallback: _kSerifFallback);
    case 'mono':
      return (family: 'monospace', fallback: _kMonoFallback);
    case 'sans':
    default:
      return (family: null, fallback: null);
  }
}

/// Full-bleed Safari-style Reader Mode surface rendering an extracted
/// [BrowserReaderArticle] with configurable theme, font family, and text scale.
class SafariReaderModeView extends StatelessWidget {
  final BrowserReaderArticle article;
  final String themeId;
  final String fontFamilyId;
  final double fontScale;
  final double topClearance;
  final double bottomClearance;
  final VoidCallback onExitReader;
  final ScrollController? scrollController;

  const SafariReaderModeView({
    super.key,
    required this.article,
    this.themeId = 'light',
    this.fontFamilyId = 'sans',
    this.fontScale = 1.0,
    this.topClearance = 0.0,
    this.bottomClearance = 0.0,
    required this.onExitReader,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final colors = SafariReaderThemeColors.resolve(themeId, palette);
    final double scale = fontScale.clamp(0.85, 1.50).toDouble();
    final fontSpec = _resolveReaderFont(fontFamilyId);

    final String title = _cleanReaderStr(article.title);
    final String byline = _cleanReaderStr(article.byline);
    final String publishedTime = _cleanReaderStr(article.publishedTime);
    final String rawSiteName = _cleanReaderStr(article.siteName);
    final String fallbackHost =
        SafariUrlSafetyAnalyzer.analyzeUrl(_cleanReaderStr(article.url))
            .displayHost;
    final String siteLabel =
        rawSiteName.isNotEmpty ? rawSiteName : fallbackHost;
    final int readMinutes = _parsePositiveInt(article.estimatedReadMinutes);

    final List<String> metaParts = <String>[
      if (byline.isNotEmpty) byline,
      if (publishedTime.isNotEmpty) publishedTime,
    ];

    TextStyle articleStyle({
      required double fontSize,
      required Color color,
      FontWeight fontWeight = FontWeight.w400,
      double height = 1.5,
      double? letterSpacing,
      FontStyle fontStyle = FontStyle.normal,
    }) {
      return TextStyle(
        fontFamily: fontSpec.family,
        fontFamilyFallback: fontSpec.fallback,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        fontStyle: fontStyle,
        color: color,
      );
    }

    return ColoredBox(
      key: const ValueKey('safari_reader_mode_view'),
      color: colors.background,
      child: SelectionArea(
        child: SingleChildScrollView(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            20,
            topClearance + 18,
            20,
            bottomClearance + 28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (siteLabel.isNotEmpty)
                              Text(
                                siteLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.15,
                                  color: colors.secondary,
                                ),
                              ),
                            if (readMinutes > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.quoteBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 13,
                                      color: colors.secondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      context.trOr(
                                        'browser_reader_read_time',
                                        '~{minutes} мин',
                                        <String, String>{
                                          'minutes': '$readMinutes',
                                        },
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: colors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SelectionContainer.disabled(
                        child: Material(
                          color: colors.quoteBg,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: const ValueKey('safari_reader_exit_btn'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              HapticUtils.tap();
                              onExitReader();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: colors.secondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.trOr(
                                      'browser_reader_exit',
                                      'Выйти',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: articleStyle(
                        fontSize: 26 * scale,
                        fontWeight: FontWeight.w800,
                        height: 1.24,
                        letterSpacing: -0.35,
                        color: colors.text,
                      ),
                    ),
                  ],
                  if (metaParts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      metaParts.join(' • '),
                      style: articleStyle(
                        fontSize: 13.5 * scale,
                        fontWeight: FontWeight.w500,
                        height: 1.38,
                        color: colors.secondary,
                      ),
                    ),
                  ],
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 18),
                    color: colors.divider,
                  ),
                  for (final block in article.blocks)
                    _buildBlock(context, block, colors, scale, articleStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(
    BuildContext context,
    BrowserReaderBlock block,
    SafariReaderThemeColors colors,
    double scale,
    TextStyle Function({
      required double fontSize,
      required Color color,
      FontWeight fontWeight,
      double height,
      double? letterSpacing,
      FontStyle fontStyle,
    }) articleStyle,
  ) {
    final String text = _cleanReaderStr(block.text);

    switch (block.type) {
      case BrowserReaderBlockType.heading:
        if (text.isEmpty) return const SizedBox.shrink();
        final int level = _parseHeadingLevel(block.headingLevel);
        final double baseSize = switch (level) {
          1 => 22.0,
          2 => 19.5,
          3 => 17.5,
          _ => 16.0,
        };
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            text,
            style: articleStyle(
              fontSize: baseSize * scale,
              fontWeight: level <= 3 ? FontWeight.w700 : FontWeight.w600,
              height: 1.3,
              letterSpacing: -0.2,
              color: colors.text,
            ),
          ),
        );

      case BrowserReaderBlockType.paragraph:
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            text,
            style: articleStyle(
              fontSize: 17 * scale,
              height: 1.62,
              color: colors.text,
            ),
          ),
        );

      case BrowserReaderBlockType.quote:
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: colors.quoteBg,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: colors.accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Text(
                          text,
                          style: articleStyle(
                            fontSize: 16.5 * scale,
                            height: 1.56,
                            fontStyle: FontStyle.italic,
                            color: colors.text.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

      case BrowserReaderBlockType.code:
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.codeBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.divider, width: 0.8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: _kMonoFallback,
                  fontSize: 14 * scale,
                  height: 1.5,
                  color: colors.text,
                ),
              ),
            ),
          ),
        );

      case BrowserReaderBlockType.list:
        final List<String> rawItems = _extractBlockItems(block.items);
        final List<String> items = rawItems.isNotEmpty
            ? rawItems
            : (text.isNotEmpty ? <String>[text] : const <String>[]);
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i < items.length - 1 ? 8 : 0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1, right: 10),
                        child: Text(
                          '•',
                          style: TextStyle(
                            fontSize: 17 * scale,
                            fontWeight: FontWeight.w700,
                            height: 1.56,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          items[i],
                          style: articleStyle(
                            fontSize: 16.5 * scale,
                            height: 1.56,
                            color: colors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case BrowserReaderBlockType.image:
        final String imageUrl = _cleanReaderStr(block.imageUrl);
        final String caption = _cleanReaderStr(block.caption);
        final Uri? parsedUri = imageUrl.isNotEmpty ? Uri.tryParse(imageUrl) : null;
        final bool isHttpImage = parsedUri != null &&
            (parsedUri.scheme.toLowerCase() == 'http' ||
                parsedUri.scheme.toLowerCase() == 'https');
        if (!isHttpImage && caption.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isHttpImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        _ReaderImageFallback(colors: colors),
                  ),
                ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: articleStyle(
                    fontSize: 13 * scale,
                    height: 1.4,
                    color: colors.secondary,
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }
}

class _ReaderImageFallback extends StatelessWidget {
  final SafariReaderThemeColors colors;

  const _ReaderImageFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colors.quoteBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider, width: 0.8),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        size: 28,
        color: colors.secondary,
      ),
    );
  }
}

/// Opens Safari's `Aa` typography & Reader Mode settings modal sheet.
Future<void> showSafariTypographySheet(
  BuildContext context, {
  double fontScale = 1.0,
  String themeId = 'light',
  String fontFamilyId = 'sans',
  bool isReaderMode = false,
  bool readerAvailable = false,
  required ValueChanged<double> onFontScaleChanged,
  required ValueChanged<String> onThemeChanged,
  required ValueChanged<String> onFontFamilyChanged,
  VoidCallback? onToggleReaderMode,
}) {
  return showTheavModalSheet<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.62,
    title: context.trOr('browser_typography_title', 'Вид и размер текста'),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
    builder: (_) => SafariTypographySheetBody(
      fontScale: fontScale,
      themeId: themeId,
      fontFamilyId: fontFamilyId,
      isReaderMode: isReaderMode,
      readerAvailable: readerAvailable,
      onFontScaleChanged: onFontScaleChanged,
      onThemeChanged: onThemeChanged,
      onFontFamilyChanged: onFontFamilyChanged,
      onToggleReaderMode: onToggleReaderMode,
    ),
  );
}

/// Interactive body for Safari's `Aa` typography, zoom scale, and Reader Mode
/// settings sheet.
class SafariTypographySheetBody extends StatefulWidget {
  final double fontScale;
  final String themeId;
  final String fontFamilyId;
  final bool isReaderMode;
  final bool readerAvailable;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final VoidCallback? onToggleReaderMode;

  const SafariTypographySheetBody({
    super.key,
    this.fontScale = 1.0,
    this.themeId = 'light',
    this.fontFamilyId = 'sans',
    this.isReaderMode = false,
    this.readerAvailable = false,
    required this.onFontScaleChanged,
    required this.onThemeChanged,
    required this.onFontFamilyChanged,
    this.onToggleReaderMode,
  });

  @override
  State<SafariTypographySheetBody> createState() =>
      _SafariTypographySheetBodyState();
}

class _SafariTypographySheetBodyState extends State<SafariTypographySheetBody> {
  static const double _minScale = 0.85;
  static const double _maxScale = 1.50;
  static const double _stepScale = 0.05;

  late double _fontScale;
  late String _themeId;
  late String _fontFamilyId;
  late bool _isReaderMode;

  @override
  void initState() {
    super.initState();
    _fontScale = _normalizeScale(widget.fontScale);
    _themeId = widget.themeId;
    _fontFamilyId = widget.fontFamilyId;
    _isReaderMode = widget.isReaderMode;
  }

  @override
  void didUpdateWidget(covariant SafariTypographySheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontScale != widget.fontScale) {
      _fontScale = _normalizeScale(widget.fontScale);
    }
    if (oldWidget.themeId != widget.themeId) {
      _themeId = widget.themeId;
    }
    if (oldWidget.fontFamilyId != widget.fontFamilyId) {
      _fontFamilyId = widget.fontFamilyId;
    }
    if (oldWidget.isReaderMode != widget.isReaderMode) {
      _isReaderMode = widget.isReaderMode;
    }
  }

  static double _normalizeScale(double raw) {
    final clamped = raw.clamp(_minScale, _maxScale).toDouble();
    return ((clamped * 20).round() / 20.0).clamp(_minScale, _maxScale);
  }

  void _updateScale(double next) {
    final normalized = _normalizeScale(next);
    if ((normalized - _fontScale).abs() < 0.001) return;
    HapticUtils.selection();
    setState(() => _fontScale = normalized);
    widget.onFontScaleChanged(normalized);
  }

  void _selectTheme(String id) {
    if (_themeId == id) return;
    HapticUtils.selection();
    setState(() => _themeId = id);
    widget.onThemeChanged(id);
  }

  void _selectFont(String id) {
    if (_fontFamilyId == id) return;
    HapticUtils.selection();
    setState(() => _fontFamilyId = id);
    widget.onFontFamilyChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final int percent = (_fontScale * 100).round();
    final bool canDecrease = _fontScale > _minScale + 0.005;
    final bool canIncrease = _fontScale < _maxScale - 0.005;
    final bool readerEnabled =
        widget.readerAvailable && widget.onToggleReaderMode != null;

    final List<({String id, String label})> themeItems = [
      (
        id: 'light',
        label: context.trOr('browser_reader_theme_light', 'Светлая'),
      ),
      (
        id: 'sepia',
        label: context.trOr('browser_reader_theme_sepia', 'Сепия'),
      ),
      (
        id: 'dark',
        label: context.trOr('browser_reader_theme_dark', 'Тёмная'),
      ),
      (
        id: 'oled',
        label: context.trOr('browser_reader_theme_oled', 'OLED'),
      ),
    ];

    const List<({String id, String label})> fontItems = [
      (id: 'sans', label: 'Sans'),
      (id: 'serif', label: 'Serif'),
      (id: 'mono', label: 'Mono'),
    ];

    return SingleChildScrollView(
      key: const ValueKey('safari_typography_sheet'),
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            showBorder: false,
            showShadow: false,
            children: [
              TheavListRow(
                key: const ValueKey('safari_typography_reader_toggle_btn'),
                enabled: readerEnabled,
                leading: Icon(
                  _isReaderMode
                      ? Icons.article_rounded
                      : Icons.chrome_reader_mode_outlined,
                ),
                title: _isReaderMode
                    ? context.trOr(
                        'browser_reader_exit_mode',
                        'Выйти из режима чтения',
                      )
                    : context.trOr(
                        'browser_reader_enter_mode',
                        'Режим чтения',
                      ),
                subtitle: !widget.readerAvailable
                    ? context.trOr(
                        'browser_reader_unavailable',
                        'Недоступен для этой страницы',
                      )
                    : null,
                trailing: _isReaderMode
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(
                            alpha: style.isDark ? 0.24 : 0.14,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          context.trOr('browser_reader_active_badge', 'Вкл'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: palette.primary,
                          ),
                        ),
                      )
                    : null,
                showChevron: widget.readerAvailable && !_isReaderMode,
                onTap: readerEnabled
                    ? () {
                        setState(() => _isReaderMode = !_isReaderMode);
                        widget.onToggleReaderMode!();
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            header: context.trOr('browser_typography_text_size', 'Размер текста'),
            showBorder: false,
            showShadow: false,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ScaleStepButton(
                            key: const ValueKey('safari_typography_decrease_btn'),
                            label: 'A-',
                            fontSize: 15,
                            enabled: canDecrease,
                            onTap: () => _updateScale(_fontScale - _stepScale),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: palette.primary.withValues(
                            alpha: style.isDark ? 0.20 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: const ValueKey('safari_typography_reset_btn'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _updateScale(1.0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              child: Text(
                                '$percent%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: palette.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ScaleStepButton(
                            key: const ValueKey('safari_typography_increase_btn'),
                            label: 'A+',
                            fontSize: 18,
                            enabled: canIncrease,
                            onTap: () => _updateScale(_fontScale + _stepScale),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: palette.primary,
                        inactiveTrackColor:
                            palette.onSurface.withValues(alpha: 0.14),
                        thumbColor: palette.primary,
                        overlayColor: palette.primary.withValues(alpha: 0.12),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _fontScale,
                        min: _minScale,
                        max: _maxScale,
                        divisions: 13,
                        onChanged: _updateScale,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            header: context.trOr(
              'browser_reader_theme_title',
              'Тема режима чтения',
            ),
            showBorder: false,
            showShadow: false,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final item in themeItems)
                      _ThemeSwatchChip(
                        key: ValueKey('safari_typography_theme_${item.id}'),
                        colors:
                            SafariReaderThemeColors.resolve(item.id, palette),
                        label: item.label,
                        selected: _themeId == item.id,
                        onTap: () => _selectTheme(item.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            header: context.trOr('browser_reader_font_title', 'Шрифт'),
            showBorder: false,
            showShadow: false,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    for (int i = 0; i < fontItems.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _FontFamilyPill(
                          key: ValueKey(
                            'safari_typography_font_${fontItems[i].id}',
                          ),
                          id: fontItems[i].id,
                          label: fontItems[i].label,
                          selected: _fontFamilyId == fontItems[i].id,
                          onTap: () => _selectFont(fontItems[i].id),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScaleStepButton extends StatelessWidget {
  final String label;
  final double fontSize;
  final bool enabled;
  final VoidCallback onTap;

  const _ScaleStepButton({
    super.key,
    required this.label,
    required this.fontSize,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    return SizedBox(
      height: 40,
      child: Material(
        color: palette.onSurface.withValues(alpha: style.isDark ? 0.09 : 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: enabled
                    ? palette.onSurface
                    : palette.onSurface.withValues(alpha: 0.32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatchChip extends StatelessWidget {
  final SafariReaderThemeColors colors;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatchChip({
    super.key,
    required this.colors,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? palette.primary : palette.divider,
                  width: selected ? 2.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Aa',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? palette.primary : palette.subtext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontFamilyPill extends StatelessWidget {
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FontFamilyPill({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final fontSpec = _resolveReaderFont(id);

    return Material(
      color: selected
          ? palette.primary.withValues(alpha: style.isDark ? 0.24 : 0.14)
          : palette.onSurface.withValues(alpha: style.isDark ? 0.08 : 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.primary : palette.divider,
              width: selected ? 1.5 : 0.6,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Aa',
                style: TextStyle(
                  fontFamily: fontSpec.family,
                  fontFamilyFallback: fontSpec.fallback,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: selected ? palette.primary : palette.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? palette.primary : palette.subtext,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
