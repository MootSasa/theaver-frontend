import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/sticker_service.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../chat/sticker_item_widget.dart';
import '../common/glass_modal_sheet.dart';
import '../settings/settings_floating_header.dart';

const String _kRecentReplyEmojiIdsPrefsKey =
    'floating_reply_emoji_recent_ids_v1';
const int _kMaxRecentReplyEmojis = 23;
const int _kGridColumns = 8;
const double _kGridHorizontalPadding = 10.0;
const double _kGridSpacing = 2.0;
const double _kSectionHeaderHeight = 28.0;
const double _kTopBarHeight = 42.0;
const double _kAnchorGap = 18.0;

/// Shows a Telegram-style Liquid Glass floating picker for monotone (adaptive)
/// custom emojis used as reply background watermarks.
Future<void> showFloatingReplyEmojiMenu({
  required BuildContext context,
  Rect? anchorRect,
  GlobalKey? anchorKey,
  int? selectedStickerId,
  Color? accentColor,
  required Future<void> Function(StickerItem sticker) onEmojiSelected,
  required Future<void> Function() onClear,
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
      return _FloatingReplyEmojiOverlay(
        anchorRect: resolvedAnchor,
        themeProvider: capturedThemeProvider,
        glassProvider: capturedGlassProvider,
        selectedStickerId: selectedStickerId,
        accentColor: resolvedAccent,
        onEmojiSelected: onEmojiSelected,
        onClear: onClear,
      );
    },
    transitionBuilder: (dialogCtx, animation, _, child) => child,
  );
}

class _FloatingReplyEmojiOverlay extends StatelessWidget {
  final Rect? anchorRect;
  final ProfileThemeProvider? themeProvider;
  final LiquidGlassProvider? glassProvider;
  final int? selectedStickerId;
  final Color accentColor;
  final Future<void> Function(StickerItem sticker) onEmojiSelected;
  final Future<void> Function() onClear;

  const _FloatingReplyEmojiOverlay({
    required this.anchorRect,
    required this.themeProvider,
    required this.glassProvider,
    required this.selectedStickerId,
    required this.accentColor,
    required this.onEmojiSelected,
    required this.onClear,
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
          center: Offset(screenSize.width / 2, screenSize.height * 0.48),
          width: 24,
          height: 24,
        );
        final effectiveAnchor = anchorRect ?? fallbackAnchor;

        final spaceBelow = (screenSize.height - safeBottom) -
            (effectiveAnchor.bottom + _kAnchorGap);
        final spaceAbove = (effectiveAnchor.top - _kAnchorGap) - safeTop;
        final openBelow = spaceBelow >= 260.0 || spaceBelow >= spaceAbove;
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

        Widget menuCard = FloatingReplyEmojiMenu(
          width: menuWidth,
          height: menuHeight,
          selectedStickerId: selectedStickerId,
          accentColor: accentColor,
          onEmojiSelected: onEmojiSelected,
          onClear: onClear,
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

class _PackSectionEntry {
  final String key;
  final double startOffset;
  final StickerPack? pack;
  final List<StickerItem> stickers;

  const _PackSectionEntry({
    required this.key,
    required this.startOffset,
    this.pack,
    required this.stickers,
  });
}

/// Floating Liquid Glass picker that shows strictly monotone (adaptive) custom
/// emoji packs for choosing a reply background watermark.
class FloatingReplyEmojiMenu extends StatefulWidget {
  final double width;
  final double height;
  final int? selectedStickerId;
  final Color accentColor;
  final Future<void> Function(StickerItem sticker) onEmojiSelected;
  final Future<void> Function() onClear;

  const FloatingReplyEmojiMenu({
    super.key,
    required this.width,
    required this.height,
    this.selectedStickerId,
    required this.accentColor,
    required this.onEmojiSelected,
    required this.onClear,
  });

  @override
  State<FloatingReplyEmojiMenu> createState() => _FloatingReplyEmojiMenuState();
}

class _FloatingReplyEmojiMenuState extends State<FloatingReplyEmojiMenu> {
  final ScrollController _gridScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<int> _recentStickerIds = <int>[];
  List<_PackSectionEntry> _currentSections = const [];
  String _activeCategoryKey = 'recent';
  bool _searchExpanded = false;
  String _searchQuery = '';
  bool _isClosing = false;
  bool _isRemoteSearching = false;
  bool _isInitializing = true;
  List<StickerItem> _remoteSearchResults = const [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _gridScrollController.addListener(_handleGridScroll);
    StickerService.instance.addListener(_onStickerServiceChanged);
    unawaited(
      StickerService.instance.ensureInitialized().whenComplete(() {
        if (mounted) {
          setState(() => _isInitializing = false);
        }
      }),
    );
    _loadRecentIds();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    StickerService.instance.removeListener(_onStickerServiceChanged);
    _gridScrollController.removeListener(_handleGridScroll);
    _gridScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onStickerServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadRecentIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRecentReplyEmojiIdsPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final ids = decoded
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((id) => id > 0)
          .take(_kMaxRecentReplyEmojis)
          .toList(growable: false);
      if (mounted && ids.isNotEmpty) {
        setState(() => _recentStickerIds = ids);
      }
    } catch (_) {}
  }

  Future<void> _recordRecentSticker(int stickerId) async {
    if (stickerId <= 0) return;
    try {
      final updated = <int>[
        stickerId,
        ..._recentStickerIds.where((id) => id != stickerId),
      ];
      if (updated.length > _kMaxRecentReplyEmojis) {
        updated.removeRange(_kMaxRecentReplyEmojis, updated.length);
      }
      if (mounted) {
        setState(() => _recentStickerIds = updated);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRecentReplyEmojiIdsPrefsKey, jsonEncode(updated));
    } catch (_) {}
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
    final target = _currentSections.cast<_PackSectionEntry?>().firstWhere(
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

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isRemoteSearching = false;
        _remoteSearchResults = const [];
      });
      return;
    }

    setState(() => _isRemoteSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 260), () async {
      final results = await StickerService.instance.searchStickers(
        trimmed,
        isCustomEmoji: true,
        adaptiveOnly: true,
      );
      if (!mounted || _searchQuery.trim() != trimmed) return;
      setState(() {
        _remoteSearchResults = results
            .where((s) => s.isAdaptiveTextColor)
            .toList(growable: false);
        _isRemoteSearching = false;
      });
    });
  }

  void _pickClear() {
    if (_isClosing) return;
    _isClosing = true;
    HapticUtils.tap();
    Navigator.of(context).pop();
    unawaited(widget.onClear());
  }

  void _pickSticker(StickerItem sticker) {
    if (_isClosing || !sticker.isAdaptiveTextColor) return;
    _isClosing = true;
    HapticUtils.tap();
    unawaited(_recordRecentSticker(sticker.id));
    Navigator.of(context).pop();
    unawaited(widget.onEmojiSelected(sticker));
  }

  List<StickerItem> _resolveRecentAdaptiveStickers(List<StickerPack> packs) {
    final byId = <int, StickerItem>{};
    for (final pack in packs) {
      for (final s in pack.stickers) {
        if (s.isAdaptiveTextColor) {
          byId[s.id] = s;
        }
      }
    }

    final resolved = <StickerItem>[];
    final seen = <int>{};
    for (final id in _recentStickerIds) {
      if (!seen.add(id)) continue;
      final found =
          byId[id] ?? StickerService.instance.getStickerByIdSync(id);
      if (found != null && found.isAdaptiveTextColor) {
        resolved.add(found);
      }
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryText = isDark ? Colors.white : const Color(0xFF141619);
    final secondaryText = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF141619).withValues(alpha: 0.60);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final rawAdaptivePacks = StickerService.instance.adaptiveEmojiPacks;
    final adaptivePacks = rawAdaptivePacks
        .where((p) => p.stickers.any((s) => s.isAdaptiveTextColor))
        .toList(growable: false);
    final recentStickers = _resolveRecentAdaptiveStickers(adaptivePacks);

    final sections = <_PackSectionEntry>[];
    double cursorY = 6.0;
    sections.add(
      _PackSectionEntry(
        key: 'recent',
        startOffset: 0.0,
        stickers: recentStickers,
      ),
    );
    cursorY += _gridHeightForCount(1 + recentStickers.length);

    for (final pack in adaptivePacks) {
      final adaptiveItems = pack.stickers
          .where((s) => s.isAdaptiveTextColor)
          .toList(growable: false);
      if (adaptiveItems.isEmpty) continue;
      sections.add(
        _PackSectionEntry(
          key: 'pack_${pack.id}',
          startOffset: cursorY,
          pack: pack,
          stickers: adaptiveItems,
        ),
      );
      cursorY +=
          _kSectionHeaderHeight + _gridHeightForCount(adaptiveItems.length);
    }
    _currentSections = sections;

    final cardBody = Column(
      children: [
        _buildTopStrip(
          context: context,
          isDark: isDark,
          primaryText: primaryText,
          secondaryText: secondaryText,
          sections: sections,
        ),
        Divider(height: 0.5, thickness: 0.5, color: dividerColor),
        Expanded(
          child: _searchQuery.trim().isNotEmpty
              ? _buildSearchGrid(
                  context: context,
                  isDark: isDark,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  sections: sections,
                )
              : _buildBrowseGrid(
                  context: context,
                  isDark: isDark,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  recentStickers: recentStickers,
                  sections: sections,
                ),
        ),
      ],
    );

    final surfaceColor =
        isDark ? const Color(0xEB23282C) : const Color(0xF2FFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    final Widget surface = ClipRRect(
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
    required Color primaryText,
    required Color secondaryText,
    required List<_PackSectionEntry> sections,
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
                    'floating_reply_emoji_search_field',
                  ),
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: primaryText),
                  cursorColor: primaryText,
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
                  onChanged: _onSearchChanged,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  _searchDebounce?.cancel();
                  setState(() {
                    _searchExpanded = false;
                    _searchQuery = '';
                    _remoteSearchResults = const [];
                    _isRemoteSearching = false;
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

    final packSections = sections.where((s) => s.pack != null);

    return SizedBox(
      height: _kTopBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Tooltip(
              message: translateOrFallback(context, 'common_search', 'Search'),
              child: InkWell(
                key: const ValueKey<String>('floating_reply_emoji_search_btn'),
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
                  for (final section in packSections) ...[
                    Builder(
                      builder: (_) {
                        final firstSticker = section.stickers.first;
                        final isSectionActive =
                            _activeCategoryKey == section.key;
                        return _CategoryIconButton(
                          isActive: isSectionActive,
                          activeColor: activePillColor,
                          onTap: () => _jumpToSection(section.key),
                          child: StickerMediaView(
                            fileUrl: firstSticker.fileUrl.isNotEmpty
                                ? firstSticker.fileUrl
                                : firstSticker.thumbnailUrl,
                            thumbnailUrl: firstSticker.thumbnailUrl,
                            stickerId: firstSticker.id,
                            format: firstSticker.format,
                            width: 22,
                            height: 22,
                            animate: false,
                            repeat: false,
                            isAdaptiveOverride: true,
                            adaptiveTintColor: isSectionActive
                                ? primaryText
                                : primaryText.withValues(alpha: 0.78),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowseGrid({
    required BuildContext context,
    required bool isDark,
    required Color primaryText,
    required Color secondaryText,
    required List<StickerItem> recentStickers,
    required List<_PackSectionEntry> sections,
  }) {
    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _kGridColumns,
      mainAxisSpacing: _kGridSpacing,
      crossAxisSpacing: _kGridSpacing,
      childAspectRatio: 1.0,
    );

    final packSections =
        sections.where((s) => s.pack != null).toList(growable: false);
    final hasAnySelected =
        widget.selectedStickerId != null && widget.selectedStickerId! > 0;

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
                  return _ClearReplyEmojiCell(
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    hasActiveEmoji: hasAnySelected,
                    onTap: _pickClear,
                  );
                }
                final sticker = recentStickers[index - 1];
                return _AdaptiveEmojiCell(
                  sticker: sticker,
                  isSelected: widget.selectedStickerId == sticker.id,
                  isDark: isDark,
                  primaryText: primaryText,
                  onTap: () => _pickSticker(sticker),
                );
              },
              childCount: 1 + recentStickers.length,
            ),
          ),
        ),
        if (packSections.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Center(
                child: _isInitializing
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryText,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconoir.Emoji(
                            width: 28,
                            height: 28,
                            color: secondaryText,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            translateOrFallback(
                              context,
                              'customizationReplyEmojiEmptyTitle',
                              'No monotone emoji yet',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: secondaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            translateOrFallback(
                              context,
                              'customizationReplyEmojiEmptyHint',
                              'Install or create an adaptive custom emoji pack to use it in reply backgrounds.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryText.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          )
        else ...[
          for (final section in packSections) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: section.pack!.title,
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
                    final sticker = section.stickers[index];
                    return _AdaptiveEmojiCell(
                      sticker: sticker,
                      isSelected: widget.selectedStickerId == sticker.id,
                      isDark: isDark,
                      primaryText: primaryText,
                      onTap: () => _pickSticker(sticker),
                    );
                  },
                  childCount: section.stickers.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ],
      ],
    );
  }

  Widget _buildSearchGrid({
    required BuildContext context,
    required bool isDark,
    required Color primaryText,
    required Color secondaryText,
    required List<_PackSectionEntry> sections,
  }) {
    final q = _searchQuery.trim().toLowerCase();
    final matched = <StickerItem>[];
    final seenIds = <int>{};

    bool matchesSticker(StickerItem s, String packTitle, String packShort) {
      if (s.emojiList.any((e) => e.toLowerCase().contains(q))) return true;
      if (s.visualDescriptionRu.toLowerCase().contains(q)) return true;
      if (s.visualDescriptionEn.toLowerCase().contains(q)) return true;
      if (s.ocrText.toLowerCase().contains(q)) return true;
      if (s.tags.any((t) => t.toLowerCase().contains(q))) return true;
      if (packTitle.toLowerCase().contains(q)) return true;
      if (packShort.toLowerCase().contains(q)) return true;
      return false;
    }

    for (final section in sections) {
      if (section.pack == null) continue;
      final title = section.pack!.title;
      final shortName = section.pack!.shortName;
      for (final s in section.stickers) {
        if (!s.isAdaptiveTextColor) continue;
        if (matchesSticker(s, title, shortName) && seenIds.add(s.id)) {
          matched.add(s);
        }
      }
    }

    for (final s in _remoteSearchResults) {
      if (s.isAdaptiveTextColor && seenIds.add(s.id)) {
        matched.add(s);
      }
    }

    if (matched.isEmpty) {
      if (_isRemoteSearching) {
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primaryText,
            ),
          ),
        );
      }
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
      itemCount: matched.length,
      itemBuilder: (ctx, index) {
        final sticker = matched[index];
        return _AdaptiveEmojiCell(
          sticker: sticker,
          isSelected: widget.selectedStickerId == sticker.id,
          isDark: isDark,
          primaryText: primaryText,
          onTap: () => _pickSticker(sticker),
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

class _ClearReplyEmojiCell extends StatelessWidget {
  final Color primaryText;
  final Color secondaryText;
  final bool hasActiveEmoji;
  final VoidCallback onTap;

  const _ClearReplyEmojiCell({
    required this.primaryText,
    required this.secondaryText,
    required this.hasActiveEmoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: translateOrFallback(context, 'emojiStatusClear', 'Remove'),
      child: InkWell(
        key: const ValueKey<String>('floating_reply_emoji_clear'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Icon(
            Icons.remove_circle_rounded,
            size: 25,
            color: hasActiveEmoji ? primaryText : secondaryText,
          ),
        ),
      ),
    );
  }
}

class _AdaptiveEmojiCell extends StatelessWidget {
  final StickerItem sticker;
  final bool isSelected;
  final bool isDark;
  final Color primaryText;
  final VoidCallback onTap;

  const _AdaptiveEmojiCell({
    required this.sticker,
    required this.isSelected,
    required this.isDark,
    required this.primaryText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey<String>('floating_reply_emoji_${sticker.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: primaryText.withValues(alpha: isDark ? 0.55 : 0.45),
                  width: 1.2,
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
            isAdaptiveOverride: true,
            adaptiveTintColor: primaryText,
          ),
        ),
      ),
    );
  }
}
