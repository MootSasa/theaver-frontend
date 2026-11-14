import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profile_customization.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/sticker_service.dart';
import '../../utils/blur_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../chat/sticker_item_widget.dart';
import '../common/glass_modal_sheet.dart';
import '../settings/settings_floating_header.dart';

const String _kRecentEmojisPrefsKey = 'recent_emojis';
const int _kMaxRecentEmojis = 28;
const int _kGridColumns = 7;
const double _kGridHorizontalPadding = 10.0;
const double _kGridSpacing = 2.0;
const double _kSectionHeaderHeight = 28.0;
const double _kTopBarHeight = 42.0;
const double _kAnchorGap = 18.0;

const List<Emoji> _kFallbackQuickEmojis = <Emoji>[
  Emoji('😀', 'grinning face'),
  Emoji('😎', 'smiling face with sunglasses'),
  Emoji('🔥', 'fire'),
  Emoji('❤️', 'red heart'),
  Emoji('🥳', 'partying face'),
  Emoji('😴', 'sleeping face'),
  Emoji('🤯', 'exploding head'),
  Emoji('🤩', 'star-struck'),
  Emoji('😇', 'smiling face with halo'),
  Emoji('🚀', 'rocket'),
  Emoji('💻', 'laptop'),
  Emoji('🎮', 'video game'),
  Emoji('☕', 'hot beverage'),
  Emoji('🎵', 'musical note'),
  Emoji('🌙', 'crescent moon'),
  Emoji('⚡', 'high voltage'),
  Emoji('💎', 'gem stone'),
  Emoji('👑', 'crown'),
  Emoji('🫶', 'heart hands'),
  Emoji('✨', 'sparkles'),
];

/// Показывает компактное плавающее меню выбора эмодзи-статуса в стиле Telegram,
/// привязанное к [anchorRect] или [anchorKey], с поддержкой Liquid Glass и автопозиционированием.
Future<void> showFloatingEmojiStatusMenu({
  required BuildContext context,
  Rect? anchorRect,
  GlobalKey? anchorKey,
  Duration? selectedDuration,
  required Future<void> Function(String emoji) onEmojiSelected,
  required Future<void> Function(StickerItem sticker) onCustomEmojiSelected,
  required Future<void> Function(Duration? duration) onDurationSelected,
  required Future<void> Function() onClearStatus,
  Color? accentColor,
}) async {
  Rect? resolvedAnchor = anchorRect;
  final anchorCtx = anchorKey?.currentContext;
  if (resolvedAnchor == null && anchorCtx != null) {
    final renderObject = anchorCtx.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.attached) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      resolvedAnchor = topLeft & renderObject.size;
    }
  }

  ProfileThemeProvider? capturedThemeProvider;
  try {
    capturedThemeProvider = context.read<ProfileThemeProvider>();
  } catch (_) {
    capturedThemeProvider = null;
  }
  final capturedGlassProvider =
      maybeLiquidGlassProvider(context, listen: false);
  final resolvedAccent = accentColor ?? Theme.of(context).colorScheme.primary;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogCtx, _, __) {
      return _FloatingEmojiStatusOverlay(
        anchorRect: resolvedAnchor,
        themeProvider: capturedThemeProvider,
        glassProvider: capturedGlassProvider,
        selectedDuration: selectedDuration,
        onEmojiSelected: onEmojiSelected,
        onCustomEmojiSelected: onCustomEmojiSelected,
        onDurationSelected: onDurationSelected,
        onClearStatus: onClearStatus,
        accentColor: resolvedAccent,
      );
    },
    transitionBuilder: (dialogCtx, animation, _, child) {
      return child;
    },
  );
}

class _FloatingEmojiStatusOverlay extends StatelessWidget {
  final Rect? anchorRect;
  final ProfileThemeProvider? themeProvider;
  final LiquidGlassProvider? glassProvider;
  final Duration? selectedDuration;
  final Future<void> Function(String emoji) onEmojiSelected;
  final Future<void> Function(StickerItem sticker) onCustomEmojiSelected;
  final Future<void> Function(Duration? duration) onDurationSelected;
  final Future<void> Function() onClearStatus;
  final Color accentColor;

  const _FloatingEmojiStatusOverlay({
    required this.anchorRect,
    required this.themeProvider,
    required this.glassProvider,
    required this.selectedDuration,
    required this.onEmojiSelected,
    required this.onCustomEmojiSelected,
    required this.onDurationSelected,
    required this.onClearStatus,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1.0);
    final mq = MediaQuery.of(context);
    final safeTop = mq.padding.top + 8.0;
    final safeBottom = math.max(mq.padding.bottom, mq.viewInsets.bottom) + 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize =
            constraints.hasBoundedWidth && constraints.hasBoundedHeight
                ? constraints.biggest
                : mq.size;
        final maxViewportHeight =
            math.max(160.0, screenSize.height - safeTop - safeBottom);

        final menuWidth =
            math.min(340.0, math.max(240.0, screenSize.width - 20.0));
        final fallbackAnchor = Rect.fromCenter(
          center: Offset(screenSize.width / 2, screenSize.height * 0.28),
          width: 24,
          height: 24,
        );
        final effectiveAnchor = anchorRect ?? fallbackAnchor;

        final spaceBelow = (screenSize.height - safeBottom) -
            (effectiveAnchor.bottom + _kAnchorGap);
        final spaceAbove = (effectiveAnchor.top - _kAnchorGap) - safeTop;
        final openBelow = spaceBelow >= 240.0 || spaceBelow >= spaceAbove;
        final availableSideHeight =
            (openBelow ? spaceBelow : spaceAbove).clamp(160.0, 368.0);
        final menuHeight = math.min(
          348.0,
          math.min(maxViewportHeight, availableSideHeight),
        );

        final maxLeft = math.max(10.0, screenSize.width - menuWidth - 10.0);
        final left =
            (effectiveAnchor.center.dx - menuWidth / 2).clamp(10.0, maxLeft);

        final maxTop =
            math.max(safeTop, screenSize.height - safeBottom - menuHeight);
        final rawTop = openBelow
            ? effectiveAnchor.bottom + _kAnchorGap
            : effectiveAnchor.top - _kAnchorGap - menuHeight;
        final top = rawTop.clamp(safeTop, maxTop);

        final relX =
            (((effectiveAnchor.center.dx - left) / menuWidth) * 2.0 - 1.0)
                .clamp(-0.9, 0.9);
        final scaleAlignment = Alignment(relX, openBelow ? -1.0 : 1.0);

        final showConnectorDots = anchorRect != null &&
            (openBelow
                ? (top - effectiveAnchor.bottom) >= 15.0
                : (effectiveAnchor.top - (top + menuHeight)) >= 15.0);
        final dotCenterX = effectiveAnchor.center.dx
            .clamp(left + 20.0, left + menuWidth - 20.0);

        final providers = <ChangeNotifierProvider<ChangeNotifier>>[];
        if (themeProvider != null) {
          providers.add(
            ChangeNotifierProvider<ProfileThemeProvider>.value(
              value: themeProvider!,
            ),
          );
        }
        if (glassProvider != null) {
          providers.add(
            ChangeNotifierProvider<LiquidGlassProvider>.value(
              value: glassProvider!,
            ),
          );
        }

        Widget menuCard = FloatingEmojiStatusMenu(
          width: menuWidth,
          height: menuHeight,
          selectedDuration: selectedDuration,
          onEmojiSelected: onEmojiSelected,
          onCustomEmojiSelected: onCustomEmojiSelected,
          onDurationSelected: onDurationSelected,
          onClearStatus: onClearStatus,
          accentColor: accentColor,
        );

        if (providers.isNotEmpty) {
          menuCard = MultiProvider(
            providers: providers,
            child: menuCard,
          );
        }

        final scaleAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        final fadeAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final dotColor = isDark
            ? const Color(0xEB23282C)
            : const Color(0xF2FFFFFF);
        final dotBorder = isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08);

        return Stack(
          children: [
            if (showConnectorDots) ...[
              Positioned(
                left: dotCenterX - 2.5,
                top: openBelow
                    ? effectiveAnchor.bottom + 2.0
                    : effectiveAnchor.top - 7.0,
                child: FadeTransition(
                  opacity: fadeAnim,
                  child: Container(
                    width: 5.0,
                    height: 5.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(color: dotBorder, width: 0.6),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: dotCenterX - 4.0,
                top: openBelow
                    ? top - 9.5
                    : (top + menuHeight) + 1.5,
                child: FadeTransition(
                  opacity: fadeAnim,
                  child: Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(color: dotBorder, width: 0.7),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              height: menuHeight,
              child: FadeTransition(
                opacity: fadeAnim,
                child: ScaleTransition(
                  scale: scaleAnim,
                  alignment: scaleAlignment,
                  child: menuCard,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLayoutEntry {
  final String key;
  final String title;
  final double startOffset;
  final StickerPack? customPack;
  final CategoryEmoji? unicodeCategory;

  const _SectionLayoutEntry({
    required this.key,
    required this.title,
    required this.startOffset,
    this.customPack,
    this.unicodeCategory,
  });
}

/// Плавающее всплывающее меню выбора эмодзи-статуса в стиле Telegram:
/// - Компактная верхняя панель с поиском, иконками категорий/паков и сроком действия статуса
/// - Верхняя сетка 3×7 («Недавние» с кнопкой сброса `⊝` в первой ячейке)
/// - Кастомные серверные эмодзи-паки в оригинальных цветах и стандартные Apple-эмодзи
class FloatingEmojiStatusMenu extends StatefulWidget {
  final double width;
  final double height;
  final Duration? selectedDuration;
  final Future<void> Function(String emoji) onEmojiSelected;
  final Future<void> Function(StickerItem sticker) onCustomEmojiSelected;
  final Future<void> Function(Duration? duration) onDurationSelected;
  final Future<void> Function() onClearStatus;
  final Color accentColor;

  const FloatingEmojiStatusMenu({
    super.key,
    this.width = 340.0,
    this.height = 348.0,
    this.selectedDuration,
    required this.onEmojiSelected,
    required this.onCustomEmojiSelected,
    required this.onDurationSelected,
    required this.onClearStatus,
    required this.accentColor,
  });

  @override
  State<FloatingEmojiStatusMenu> createState() =>
      _FloatingEmojiStatusMenuState();
}

class _FloatingEmojiStatusMenuState extends State<FloatingEmojiStatusMenu> {
  final ScrollController _gridScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Emoji> _recentEmojis = const [];
  String _activeCategoryKey = 'recent';
  bool _searchExpanded = false;
  String _searchQuery = '';
  Duration? _localDuration;
  bool _isClosing = false;
  List<_SectionLayoutEntry> _currentSections = const [];

  @override
  void initState() {
    super.initState();
    _localDuration = widget.selectedDuration;
    if (!EmojiUtils.isFontLoaded.value) {
      unawaited(
        EmojiUtils.loadAppleEmojiFont().then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    unawaited(_loadRecentEmojis());
    StickerService.instance.addListener(_onStickersChanged);
    if (StickerService.instance.installedEmojiPacks.isEmpty) {
      unawaited(StickerService.instance.ensureInitialized());
    }
    _gridScrollController.addListener(_handleGridScroll);
  }

  @override
  void dispose() {
    StickerService.instance.removeListener(_onStickersChanged);
    _gridScrollController.removeListener(_handleGridScroll);
    _gridScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onStickersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecentEmojis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRecentEmojisPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <Emoji>[];
      for (final item in decoded) {
        if (item is Map) {
          final emoji = item['emoji']?.toString() ?? '';
          final name = item['name']?.toString() ?? '';
          if (emoji.isNotEmpty) {
            loaded.add(Emoji(emoji, name));
          }
        }
      }
      if (mounted && loaded.isNotEmpty) {
        setState(() => _recentEmojis = loaded);
      }
    } catch (_) {}
  }

  Future<void> _recordRecentEmoji(String emojiChar, String name) async {
    try {
      final updated = <Emoji>[
        Emoji(emojiChar, name),
        ..._recentEmojis.where((e) => e.emoji != emojiChar),
      ];
      if (updated.length > _kMaxRecentEmojis) {
        updated.removeRange(_kMaxRecentEmojis, updated.length);
      }
      if (mounted) {
        setState(() => _recentEmojis = updated);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kRecentEmojisPrefsKey,
        jsonEncode(
          updated
              .map((e) => {'emoji': e.emoji, 'name': e.name})
              .toList(growable: false),
        ),
      );
    } catch (_) {}
  }

  List<Emoji> _buildTopTwentyEmojis() {
    final seen = <String>{};
    final result = <Emoji>[];
    for (final e in _recentEmojis) {
      if (result.length >= 20) break;
      if (seen.add(e.emoji)) {
        result.add(e);
      }
    }
    for (final fallback in _kFallbackQuickEmojis) {
      if (result.length >= 20) break;
      if (seen.add(fallback.emoji)) {
        result.add(fallback);
      }
    }
    return result;
  }

  double get _cellExtent {
    final innerWidth = math.max(
      140.0,
      widget.width - _kGridHorizontalPadding * 2,
    );
    return (innerWidth - (_kGridColumns - 1) * _kGridSpacing) / _kGridColumns;
  }

  double _gridHeightForCount(int itemCount) {
    if (itemCount <= 0) return 0.0;
    final rows = (itemCount / _kGridColumns).ceil();
    return rows * _cellExtent + (rows - 1) * _kGridSpacing + 6.0;
  }

  void _handleGridScroll() {
    if (_searchQuery.trim().isNotEmpty || _currentSections.isEmpty) return;
    final offset = _gridScrollController.offset + 12.0;
    String nextKey = _currentSections.first.key;
    for (final section in _currentSections) {
      if (offset >= section.startOffset) {
        nextKey = section.key;
      } else {
        break;
      }
    }
    if (nextKey != _activeCategoryKey && mounted) {
      setState(() => _activeCategoryKey = nextKey);
    }
  }

  void _jumpToSection(String key) {
    HapticUtils.selection();
    setState(() => _activeCategoryKey = key);
    if (!_gridScrollController.hasClients) return;
    final target = _currentSections.cast<_SectionLayoutEntry?>().firstWhere(
          (s) => s?.key == key,
          orElse: () => null,
        );
    if (target == null) return;
    final maxExtent = _gridScrollController.position.maxScrollExtent;
    final dest = target.startOffset.clamp(0.0, maxExtent);
    unawaited(
      _gridScrollController.animateTo(
        dest,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _pickClearStatus() {
    if (_isClosing) return;
    _isClosing = true;
    unawaited(widget.onClearStatus());
    Navigator.of(context).pop();
  }

  void _pickUnicodeEmoji(Emoji e) {
    if (_isClosing) return;
    _isClosing = true;
    unawaited(_recordRecentEmoji(e.emoji, e.name));
    unawaited(widget.onEmojiSelected(e.emoji));
    Navigator.of(context).pop();
  }

  void _pickCustomEmoji(StickerItem sticker) {
    if (_isClosing) return;
    _isClosing = true;
    unawaited(widget.onCustomEmojiSelected(sticker));
    Navigator.of(context).pop();
  }

  String _shortDurationBadge(Duration? duration) {
    if (duration == null) return '';
    if (duration.inDays >= 7) return '7d';
    if (duration.inHours >= 24) return '24h';
    if (duration.inHours >= 4) return '4h';
    if (duration.inHours >= 1) return '1h';
    return '';
  }

  String _categoryLabel(BuildContext context, Category category) {
    final isRu = Localizations.maybeLocaleOf(context)?.languageCode == 'ru';
    switch (category) {
      case Category.RECENT:
        return isRu ? 'Недавние' : 'Recent';
      case Category.SMILEYS:
        return isRu ? 'Смайлы и люди' : 'Smileys & People';
      case Category.ANIMALS:
        return isRu ? 'Животные и природа' : 'Animals & Nature';
      case Category.FOODS:
        return isRu ? 'Еда и напитки' : 'Food & Drink';
      case Category.ACTIVITIES:
        return isRu ? 'Активность' : 'Activity';
      case Category.TRAVEL:
        return isRu ? 'Путешествия' : 'Travel & Places';
      case Category.OBJECTS:
        return isRu ? 'Объекты' : 'Objects';
      case Category.SYMBOLS:
        return isRu ? 'Символы' : 'Symbols';
      case Category.FLAGS:
        return isRu ? 'Флаги' : 'Flags';
    }
  }

  IconData _categoryIcon(Category category) {
    switch (category) {
      case Category.RECENT:
        return Icons.access_time_rounded;
      case Category.SMILEYS:
        return Icons.sentiment_satisfied_alt_rounded;
      case Category.ANIMALS:
        return Icons.pets_rounded;
      case Category.FOODS:
        return Icons.local_cafe_rounded;
      case Category.ACTIVITIES:
        return Icons.sports_esports_rounded;
      case Category.TRAVEL:
        return Icons.flight_takeoff_rounded;
      case Category.OBJECTS:
        return Icons.lightbulb_outline_rounded;
      case Category.SYMBOLS:
        return Icons.tag_rounded;
      case Category.FLAGS:
        return Icons.outlined_flag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    ProfileThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ProfileThemeProvider>(context);
    } catch (_) {
      themeProvider = null;
    }
    final activeStatus = themeProvider?.currentEmojiStatus;

    final glassProvider = maybeLiquidGlassProvider(context);
    final useGlass = glassProvider != null && glassProvider.enabled;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor;

    final primaryText = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF14181F);
    final secondaryText = isDark
        ? Colors.white.withValues(alpha: 0.56)
        : Colors.black.withValues(alpha: 0.54);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    final installedPacks = StickerService.instance.installedEmojiPacks
        .where((p) => p.stickers.isNotEmpty)
        .toList(growable: false);
    final standardCategories = defaultEmojiSet
        .where((c) => c.category != Category.RECENT && c.emoji.isNotEmpty)
        .toList(growable: false);

    // Детерминированные смещения для точной прокрутки по тапу на категорию
    final sections = <_SectionLayoutEntry>[];
    double cursorY = 6.0;
    sections.add(
      _SectionLayoutEntry(
        key: 'recent',
        title: _categoryLabel(context, Category.RECENT),
        startOffset: 0.0,
      ),
    );
    cursorY += _gridHeightForCount(21);

    for (final pack in installedPacks) {
      sections.add(
        _SectionLayoutEntry(
          key: 'pack_${pack.id}',
          title: pack.title,
          startOffset: cursorY,
          customPack: pack,
        ),
      );
      cursorY += _kSectionHeaderHeight + _gridHeightForCount(pack.stickers.length);
    }

    for (final cat in standardCategories) {
      sections.add(
        _SectionLayoutEntry(
          key: 'cat_${cat.category.name}',
          title: _categoryLabel(context, cat.category),
          startOffset: cursorY,
          unicodeCategory: cat,
        ),
      );
      cursorY += _kSectionHeaderHeight + _gridHeightForCount(cat.emoji.length);
    }
    _currentSections = sections;

    final cardBody = Column(
      children: [
        _buildTopStrip(
          context: context,
          isDark: isDark,
          accent: accent,
          primaryText: primaryText,
          secondaryText: secondaryText,
          installedPacks: installedPacks,
          standardCategories: standardCategories,
        ),
        Divider(height: 0.5, thickness: 0.5, color: dividerColor),
        Expanded(
          child: _searchQuery.trim().isNotEmpty
              ? _buildSearchGrid(
                  context: context,
                  accent: accent,
                  secondaryText: secondaryText,
                  installedPacks: installedPacks,
                  standardCategories: standardCategories,
                  activeStatus: activeStatus,
                )
              : _buildBrowseGrid(
                  context: context,
                  accent: accent,
                  secondaryText: secondaryText,
                  installedPacks: installedPacks,
                  standardCategories: standardCategories,
                  activeStatus: activeStatus,
                ),
        ),
      ],
    );

    final surfaceColor = isDark
        ? const Color(0xEB23282C)
        : const Color(0xF2FFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    final Widget surface;
    if (useGlass) {
      final glassStyle = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDark,
        cornerRadius: 20.0,
        color: isDark ? const Color(0xC823282C) : const Color(0xCCF7F8FA),
        refractionIndex: 1.08,
        refractionWidth: 16.0,
      );
      surface = LiquidGlassLens(
        style: glassStyle,
        child: Material(
          type: MaterialType.transparency,
          child: cardBody,
        ),
      );
    } else {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: cardBody,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: surface,
    );
  }

  Widget _buildTopStrip({
    required BuildContext context,
    required bool isDark,
    required Color accent,
    required Color primaryText,
    required Color secondaryText,
    required List<StickerPack> installedPacks,
    required List<CategoryEmoji> standardCategories,
  }) {
    final activePillColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    if (_searchExpanded) {
      return SizedBox(
        height: _kTopBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              iconoir.Search(width: 17, height: 17, color: secondaryText),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>(
                    'floating_emoji_status_search_field',
                  ),
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: primaryText),
                  cursorColor: accent,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: translateOrFallback(
                      context,
                      'common_search',
                      'Search',
                    ),
                    hintStyle: TextStyle(fontSize: 14, color: secondaryText),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  setState(() {
                    _searchExpanded = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                icon: iconoir.Xmark(width: 17, height: 17, color: secondaryText),
              ),
            ],
          ),
        ),
      );
    }

    final durationOptions = <(Duration?, String)>[
      (null, translateOrFallback(context, 'emojiStatusExpiryNever', 'Forever')),
      (
        const Duration(hours: 1),
        translateOrFallback(context, 'emojiStatusExpiry1h', '1 hour'),
      ),
      (
        const Duration(hours: 4),
        translateOrFallback(context, 'emojiStatusExpiry4h', '4 hours'),
      ),
      (
        const Duration(hours: 24),
        translateOrFallback(context, 'emojiStatusExpiry24h', '24 hours'),
      ),
      (
        const Duration(days: 7),
        translateOrFallback(context, 'emojiStatusExpiry7d', '7 days'),
      ),
    ];

    int selectedDurationIdx = 0;
    for (int i = 0; i < durationOptions.length; i++) {
      if (durationOptions[i].$1 == _localDuration) {
        selectedDurationIdx = i;
        break;
      }
    }
    final shortBadge = _shortDurationBadge(_localDuration);

    return SizedBox(
      height: _kTopBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Tooltip(
              message: translateOrFallback(context, 'common_search', 'Search'),
              child: InkWell(
                key: const ValueKey<String>('floating_emoji_status_search_btn'),
                borderRadius: BorderRadius.circular(15),
                onTap: () {
                  HapticUtils.selection();
                  setState(() => _searchExpanded = true);
                },
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: iconoir.Search(
                      width: 17,
                      height: 17,
                      color: secondaryText,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _CategoryIconButton(
                    isActive: _activeCategoryKey == 'recent',
                    activeColor: activePillColor,
                    onTap: () => _jumpToSection('recent'),
                    child: iconoir.Clock(
                      width: 18,
                      height: 18,
                      color: _activeCategoryKey == 'recent'
                          ? primaryText
                          : secondaryText,
                    ),
                  ),
                  for (final pack in installedPacks)
                    _CategoryIconButton(
                      isActive: _activeCategoryKey == 'pack_${pack.id}',
                      activeColor: activePillColor,
                      onTap: () => _jumpToSection('pack_${pack.id}'),
                      child: StickerMediaView(
                        fileUrl: pack.stickers.first.thumbnailUrl.isNotEmpty
                            ? pack.stickers.first.thumbnailUrl
                            : pack.stickers.first.fileUrl,
                        thumbnailUrl: pack.stickers.first.thumbnailUrl,
                        stickerId: pack.stickers.first.id,
                        format: pack.stickers.first.format,
                        width: 22,
                        height: 22,
                        animate: false,
                        repeat: false,
                      ),
                    ),
                  for (final cat in standardCategories)
                    _CategoryIconButton(
                      isActive: _activeCategoryKey == 'cat_${cat.category.name}',
                      activeColor: activePillColor,
                      onTap: () => _jumpToSection('cat_${cat.category.name}'),
                      child: Icon(
                        _categoryIcon(cat.category),
                        size: 18,
                        color: _activeCategoryKey == 'cat_${cat.category.name}'
                            ? primaryText
                            : secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            PopupMenuButton<int>(
              key: const ValueKey<String>('floating_emoji_status_duration_btn'),
              tooltip: translateOrFallback(
                context,
                'emojiStatusExpiryLabel',
                'Duration',
              ),
              onSelected: (idx) {
                final chosen = durationOptions[idx].$1;
                setState(() => _localDuration = chosen);
                unawaited(widget.onDurationSelected(chosen));
              },
              itemBuilder: (menuCtx) => [
                for (int i = 0; i < durationOptions.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    child: Row(
                      children: [
                        Expanded(child: Text(durationOptions[i].$2)),
                        if (i == selectedDurationIdx)
                          iconoir.Check(width: 17, height: 17, color: accent),
                      ],
                    ),
                  ),
              ],
              child: Container(
                height: 28,
                padding: EdgeInsets.symmetric(
                  horizontal: shortBadge.isNotEmpty ? 8 : 6,
                ),
                decoration: BoxDecoration(
                  color: _localDuration != null
                      ? accent.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconoir.Timer(
                      width: 17,
                      height: 17,
                      color: _localDuration != null ? accent : secondaryText,
                    ),
                    if (shortBadge.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        shortBadge,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowseGrid({
    required BuildContext context,
    required Color accent,
    required Color secondaryText,
    required List<StickerPack> installedPacks,
    required List<CategoryEmoji> standardCategories,
    required EmojiStatusData? activeStatus,
  }) {
    final topTwenty = _buildTopTwentyEmojis();
    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _kGridColumns,
      mainAxisSpacing: _kGridSpacing,
      crossAxisSpacing: _kGridSpacing,
      childAspectRatio: 1.0,
    );

    return CustomScrollView(
      controller: _gridScrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(
            left: _kGridHorizontalPadding,
            right: _kGridHorizontalPadding,
            top: 6.0,
            bottom: 6.0,
          ),
          sliver: SliverGrid(
            gridDelegate: gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (ctx, index) {
                if (index == 0) {
                  return _ClearStatusCell(
                    accent: accent,
                    secondaryText: secondaryText,
                    hasActiveStatus: activeStatus != null,
                    onTap: _pickClearStatus,
                  );
                }
                final e = topTwenty[index - 1];
                final isSelected = activeStatus?.type == 'unicode' &&
                    activeStatus?.emoji == e.emoji;
                return _UnicodeEmojiCell(
                  emoji: e.emoji,
                  isSelected: isSelected,
                  accent: accent,
                  onTap: () => _pickUnicodeEmoji(e),
                );
              },
              childCount: 21,
            ),
          ),
        ),
        for (final pack in installedPacks) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: pack.title,
              color: secondaryText,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(
              left: _kGridHorizontalPadding,
              right: _kGridHorizontalPadding,
              bottom: 6.0,
            ),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (ctx, index) {
                  final sticker = pack.stickers[index];
                  final isSelected = activeStatus?.type == 'sticker' &&
                      activeStatus?.stickerId == sticker.id;
                  return _CustomEmojiCell(
                    sticker: sticker,
                    isSelected: isSelected,
                    accent: accent,
                    onTap: () => _pickCustomEmoji(sticker),
                  );
                },
                childCount: pack.stickers.length,
              ),
            ),
          ),
        ],
        for (final cat in standardCategories) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: _categoryLabel(context, cat.category),
              color: secondaryText,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(
              left: _kGridHorizontalPadding,
              right: _kGridHorizontalPadding,
              bottom: 6.0,
            ),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (ctx, index) {
                  final e = cat.emoji[index];
                  final isSelected = activeStatus?.type == 'unicode' &&
                      activeStatus?.emoji == e.emoji;
                  return _UnicodeEmojiCell(
                    emoji: e.emoji,
                    isSelected: isSelected,
                    accent: accent,
                    onTap: () => _pickUnicodeEmoji(e),
                  );
                },
                childCount: cat.emoji.length,
              ),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 8.0)),
      ],
    );
  }

  Widget _buildSearchGrid({
    required BuildContext context,
    required Color accent,
    required Color secondaryText,
    required List<StickerPack> installedPacks,
    required List<CategoryEmoji> standardCategories,
    required EmojiStatusData? activeStatus,
  }) {
    final query = _searchQuery.trim();
    final matchedStickers = <StickerItem>[];
    for (final pack in installedPacks) {
      for (final item in pack.stickers) {
        if (item.matchesLocalQuery(query)) {
          matchedStickers.add(item);
        }
      }
    }

    final seenEmojiChars = <String>{};
    final matchedEmojis = <Emoji>[];
    for (final cat in standardCategories) {
      for (final e in cat.emoji) {
        if (seenEmojiChars.contains(e.emoji)) continue;
        if (EmojiUtils.matchesEmojiSearch(e.emoji, e.name, query)) {
          seenEmojiChars.add(e.emoji);
          matchedEmojis.add(e);
        }
      }
    }

    final totalCount = matchedStickers.length + matchedEmojis.length;
    if (totalCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Emoji(width: 28, height: 28, color: secondaryText),
            const SizedBox(height: 6),
            Text(
              translateOrFallback(
                context,
                'common_nothing_found',
                'Nothing found',
              ),
              style: TextStyle(fontSize: 13, color: secondaryText),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: _kGridHorizontalPadding,
        vertical: 8.0,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _kGridColumns,
        mainAxisSpacing: _kGridSpacing,
        crossAxisSpacing: _kGridSpacing,
        childAspectRatio: 1.0,
      ),
      itemCount: totalCount,
      itemBuilder: (ctx, index) {
        if (index < matchedStickers.length) {
          final sticker = matchedStickers[index];
          final isSelected = activeStatus?.type == 'sticker' &&
              activeStatus?.stickerId == sticker.id;
          return _CustomEmojiCell(
            sticker: sticker,
            isSelected: isSelected,
            accent: accent,
            onTap: () => _pickCustomEmoji(sticker),
          );
        }
        final e = matchedEmojis[index - matchedStickers.length];
        final isSelected = activeStatus?.type == 'unicode' &&
            activeStatus?.emoji == e.emoji;
        return _UnicodeEmojiCell(
          emoji: e.emoji,
          isSelected: isSelected,
          accent: accent,
          onTap: () => _pickUnicodeEmoji(e),
        );
      },
    );
  }
}

class _CategoryIconButton extends StatelessWidget {
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  final Widget child;

  const _CategoryIconButton({
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kSectionHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearStatusCell extends StatelessWidget {
  final Color accent;
  final Color secondaryText;
  final bool hasActiveStatus;
  final VoidCallback onTap;

  const _ClearStatusCell({
    required this.accent,
    required this.secondaryText,
    required this.hasActiveStatus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: translateOrFallback(context, 'emojiStatusClear', 'Clear Status'),
      child: InkWell(
        key: const ValueKey<String>('floating_emoji_status_clear'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Icon(
            Icons.remove_circle_rounded,
            size: 25,
            color: hasActiveStatus ? accent : secondaryText,
          ),
        ),
      ),
    );
  }
}

class _UnicodeEmojiCell extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  const _UnicodeEmojiCell({
    required this.emoji,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 1.0,
                ),
              )
            : null,
        child: Center(
          child: EmojiUtils.appleEmoji(emoji, size: 25),
        ),
      ),
    );
  }
}

class _CustomEmojiCell extends StatelessWidget {
  final StickerItem sticker;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  const _CustomEmojiCell({
    required this.sticker,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 1.0,
                ),
              )
            : null,
        child: Center(
          child: StickerMediaView(
            fileUrl: sticker.fileUrl,
            thumbnailUrl: sticker.thumbnailUrl,
            stickerId: sticker.id,
            format: sticker.format,
            width: 28,
            height: 28,
            animate: true,
            repeat: true,
          ),
        ),
      ),
    );
  }
}
