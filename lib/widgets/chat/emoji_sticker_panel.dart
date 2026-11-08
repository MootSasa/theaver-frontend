import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../screens/stickers/create_sticker_pack_screen.dart';
import '../../screens/stickers/sticker_pack_detail_sheet.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/blur_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import 'rich_text_editing_controller.dart';
import 'sticker_item_widget.dart';

// --- CONSTANTS ---
const double _kPanelHeight = 280.0;
const double _kSearchHeight = 48.0;
const double _kEmojiSelectorHeight = 48.0;
const double _kEmojiHeaderHeight = _kEmojiSelectorHeight + _kSearchHeight; // 96.0
// -----------------

class CustomEmojiPack {
  final String id;
  final String name;
  final List<Emoji> emojis;

  CustomEmojiPack({
    required this.id,
    required this.name,
    required this.emojis,
  });
}

enum PanelTab { emoji, gif, sticker }

class EmojiStickerPanel extends StatefulWidget {
  final TextEditingController? controller;
  final VoidCallback onBackspace;
  final VoidCallback onClose;
  final double height;
  final bool isVisible;
  final bool expandToAvailableHeight;
  final ValueChanged<String>? onEmojiSelected;
  final ValueChanged<StickerItem>? onCustomEmojiSelected;
  final ValueChanged<StickerItem>? onStickerSelected;
  final ValueChanged<GifItemModel>? onGifSelected;

  const EmojiStickerPanel({
    super.key,
    this.controller,
    required this.onBackspace,
    required this.onClose,
    this.height = _kPanelHeight,
    this.isVisible = true,
    this.expandToAvailableHeight = false,
    this.onEmojiSelected,
    this.onCustomEmojiSelected,
    this.onStickerSelected,
    this.onGifSelected,
  });

  @override
  State<EmojiStickerPanel> createState() => _EmojiStickerPanelState();
}

class _EmojiStickerPanelState extends State<EmojiStickerPanel>
    with TickerProviderStateMixin {
  static PanelTab _lastSelectedTab = PanelTab.emoji;

  PanelTab _currentTab = _lastSelectedTab;
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _gifScrollController = ScrollController();
  final ScrollController _stickerScrollController = ScrollController();
  late PageController _pageController = PageController(
    initialPage: _currentTab.index,
  );

  late final AnimationController _searchCollapseController;
  late final AnimationController _stickerCollapseController;

  final TextEditingController _emojiSearchController = TextEditingController();
  final TextEditingController _gifSearchController = TextEditingController();
  final TextEditingController _stickerSearchController = TextEditingController();

  final FocusNode _emojiSearchFocusNode = FocusNode();
  final FocusNode _gifSearchFocusNode = FocusNode();
  final FocusNode _stickerSearchFocusNode = FocusNode();

  String _emojiSearchQuery = '';
  String _gifSearchQuery = '';
  String _stickerSearchQuery = '';

  Timer? _emojiSearchDebounce;
  Timer? _gifSearchDebounce;
  Timer? _stickerSearchDebounce;

  List<StickerItem> _remoteSearchedCustomEmojis = [];
  List<StickerItem> _remoteSearchedStickers = [];
  List<GifItemModel> _remoteSearchedGifs = [];
  bool _isSearchingGifs = false;
  bool _isSearchingStickers = false;

  List<Emoji> _recentEmojis = [];
  List<Emoji> _displayedRecentEmojis = [];

  List<CustomEmojiPack> _customPacks = [];
  Map<String, int> _packUsageStats = {};
  Map<String, int> _displayedPackUsageStats = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  final Map<String, GlobalKey> _stickerSectionKeys = {};
  final Map<String, double> _emojiSectionOffsets = {};
  final Map<String, double> _stickerSectionOffsets = {};
  double _lastPanelWidth = 360.0;
  double? _lastHapticPixels;
  double? _lastStickerHapticPixels;

  static int _computeEmojiColumns(double panelWidth) {
    final available = math.max(160.0, panelWidth - 24.0);
    return ((available + 8.0) / (36.0 + 8.0)).floor().clamp(5, 24);
  }

  static int _computeGifColumns(double panelWidth) {
    final available = math.max(160.0, panelWidth - 16.0);
    return ((available + 8.0) / (140.0 + 8.0)).floor().clamp(2, 8);
  }

  static int _computeStickerColumns(double panelWidth) {
    final available = math.max(160.0, panelWidth - 16.0);
    return ((available + 10.0) / (68.0 + 10.0)).floor().clamp(4, 12);
  }

  @override
  void initState() {
    super.initState();
    _searchCollapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _stickerCollapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _gridScrollController.addListener(_onScroll);
    _stickerScrollController.addListener(_onStickerScroll);
    _initMockPacks();
    _loadRecentEmojis();
    _loadPackUsageStats();

    StickerService.instance.addListener(_onStickerServiceChanged);
    StickerService.instance.ensureInitialized();
  }

  void _onStickerServiceChanged() {
    if (!mounted) return;
    _ensureStickerSectionKeys();
    setState(() {});
  }

  void _ensureStickerSectionKeys() {
    _stickerSectionKeys.putIfAbsent('recent', () => GlobalKey());
    _stickerSectionKeys.putIfAbsent('favorites', () => GlobalKey());
    for (final pack in StickerService.instance.installedStickerPacks) {
      _stickerSectionKeys.putIfAbsent(pack.id.toString(), () => GlobalKey());
    }
    for (final pack in StickerService.instance.installedEmojiPacks) {
      _sectionKeys.putIfAbsent('srv_${pack.id}', () => GlobalKey());
    }
  }

  @override
  void didUpdateWidget(covariant EmojiStickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) {
      _currentTab = _lastSelectedTab;
      if (!_pageController.hasClients) {
        _pageController.dispose();
        _pageController = PageController(initialPage: _currentTab.index);
      } else if (_pageController.page?.round() != _currentTab.index) {
        _pageController.jumpToPage(_currentTab.index);
      }
      if (!_gridScrollController.hasClients) {
        _searchCollapseController.value = 0.0;
      }
      if (!_stickerScrollController.hasClients) {
        _stickerCollapseController.value = 0.0;
      }
      _displayedRecentEmojis = List<Emoji>.from(_recentEmojis);
      _displayedPackUsageStats = Map<String, int>.from(_packUsageStats);
      StickerService.instance.ensureInitialized();
    }
  }

  void _onScroll() {
    if (_currentTab == PanelTab.emoji && _gridScrollController.hasClients) {
      final double offset = _gridScrollController.offset;
      final double targetCollapse = (offset / 48.0).clamp(0.0, 1.0);
      if ((_searchCollapseController.value - targetCollapse).abs() > 0.001) {
        _searchCollapseController.value = targetCollapse;
      }

      final bool isNearOpen = offset <= 3.0;
      final bool isNearClosed = (offset - 48.0).abs() <= 3.0;

      if (isNearOpen) {
        if (_lastHapticPixels != 0.0) {
          HapticUtils.selection();
          _lastHapticPixels = 0.0;
        }
      } else if (isNearClosed) {
        _lastHapticPixels = 48.0;
      } else {
        _lastHapticPixels = null;
      }
    }
  }

  void _onStickerScroll() {
    if (_currentTab == PanelTab.sticker && _stickerScrollController.hasClients) {
      final double offset = _stickerScrollController.offset;
      final double targetCollapse = (offset / 48.0).clamp(0.0, 1.0);
      if ((_stickerCollapseController.value - targetCollapse).abs() > 0.001) {
        _stickerCollapseController.value = targetCollapse;
      }

      final bool isNearOpen = offset <= 3.0;
      final bool isNearClosed = (offset - 48.0).abs() <= 3.0;

      if (isNearOpen) {
        if (_lastStickerHapticPixels != 0.0) {
          HapticUtils.selection();
          _lastStickerHapticPixels = 0.0;
        }
      } else if (isNearClosed) {
        _lastStickerHapticPixels = 48.0;
      } else {
        _lastStickerHapticPixels = null;
      }
    }
  }

  void _initMockPacks() {
    _customPacks = [];
    _sectionKeys['recent'] = GlobalKey();
    _sectionKeys['standard'] = GlobalKey();
    _ensureStickerSectionKeys();
  }

  @override
  void dispose() {
    StickerService.instance.removeListener(_onStickerServiceChanged);
    _emojiSearchDebounce?.cancel();
    _gifSearchDebounce?.cancel();
    _stickerSearchDebounce?.cancel();

    _gridScrollController.removeListener(_onScroll);
    _stickerScrollController.removeListener(_onStickerScroll);
    _gridScrollController.dispose();
    _gifScrollController.dispose();
    _stickerScrollController.dispose();
    _pageController.dispose();
    _searchCollapseController.dispose();
    _stickerCollapseController.dispose();

    _emojiSearchController.dispose();
    _gifSearchController.dispose();
    _stickerSearchController.dispose();

    _emojiSearchFocusNode.dispose();
    _gifSearchFocusNode.dispose();
    _stickerSearchFocusNode.dispose();
    super.dispose();
  }

  void _onEmojiQueryChanged(String value) {
    setState(() => _emojiSearchQuery = value);
    _emojiSearchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() => _remoteSearchedCustomEmojis = []);
      return;
    }
    _emojiSearchDebounce = Timer(const Duration(milliseconds: 180), () async {
      final results = await StickerService.instance.searchStickers(
        q,
        packType: 'custom_emoji',
      );
      if (mounted && _emojiSearchQuery.trim() == q) {
        setState(() => _remoteSearchedCustomEmojis = results);
      }
    });
  }

  void _onGifQueryChanged(String value) {
    setState(() => _gifSearchQuery = value);
    _gifSearchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _remoteSearchedGifs = [];
        _isSearchingGifs = false;
      });
      return;
    }
    setState(() => _isSearchingGifs = true);
    _gifSearchDebounce = Timer(const Duration(milliseconds: 220), () async {
      final results = await StickerService.instance.searchGifs(q);
      if (mounted && _gifSearchQuery.trim() == q) {
        setState(() {
          _remoteSearchedGifs = results;
          _isSearchingGifs = false;
        });
      }
    });
  }

  void _onStickerQueryChanged(String value) {
    setState(() => _stickerSearchQuery = value);
    _stickerSearchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _remoteSearchedStickers = [];
        _isSearchingStickers = false;
      });
      return;
    }
    setState(() => _isSearchingStickers = true);
    _stickerSearchDebounce = Timer(const Duration(milliseconds: 180), () async {
      final results = await StickerService.instance.searchStickers(
        q,
        packType: 'sticker',
      );
      if (mounted && _stickerSearchQuery.trim() == q) {
        setState(() {
          _remoteSearchedStickers = results;
          _isSearchingStickers = false;
        });
      }
    });
  }

  bool _isTelegramPackLink(String query) {
    final q = query.trim().toLowerCase();
    return q.contains('t.me/addstickers/') ||
        q.contains('t.me/addemoji/') ||
        q.startsWith('tg://addstickers');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }
    if (!widget.expandToAvailableHeight && widget.height <= 0) {
      return const SizedBox.shrink();
    }

    final theavTheme = TheavTheme.of(context);

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: theavTheme.secondaryBg.withValues(alpha: 1.0),
        border: Border(
          top: BorderSide(
            color: theavTheme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: _buildPanelContent(false),
    );

    if (widget.expandToAvailableHeight) {
      return SizedBox.expand(child: content);
    }
    return SizedBox(
      height: widget.height,
      child: content,
    );
  }

  Widget _buildPanelContent(bool isSearching) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: widget.expandToAvailableHeight
          ? null
          : (details) {
              if ((details.primaryVelocity ?? 0) > 300) {
                widget.onClose();
              }
            },
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildMainGrid()),
            ],
          ),
          if (!isSearching) _buildFloatingNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox(height: 8);
  }

  Widget _buildSearch(
    String hint,
    TextEditingController controller,
    String query,
    ValueChanged<String> onChanged,
    FocusNode focusNode, {
    bool isGrouped = false,
    double opacity = 1.0,
    bool lensVisible = true,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final clampedOpacity = opacity.clamp(0.0, 1.0);

    if (!isGrouped && clampedOpacity <= 0.01) {
      return const SizedBox.shrink();
    }

    final Widget searchContent = Opacity(
      opacity: clampedOpacity,
      child: IgnorePointer(
        ignoring: clampedOpacity <= 0.1 || !lensVisible,
        child: Row(
          children: [
            const SizedBox(width: 12),
            iconoir.Search(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              width: 18,
              height: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                cursorColor: theme.colorScheme.primary,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                  if (!focusNode.hasFocus) {
                    focusNode.requestFocus();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: iconoir.Xmark(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    width: 16,
                    height: 16,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );

    if (glassProvider.enabled) {
      final searchStyle = glassProvider.createStyle(
        context: context,
        cornerRadius: 24,
        refractionWidth: 24,
      );

      return Container(
        height: 40 + 8,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: LiquidGlassLens(
          visibility: lensVisible,
          style: searchStyle,
          child: SizedBox(
            height: 40,
            child: searchContent,
          ),
        ),
      );
    }

    if (clampedOpacity <= 0.01) {
      return const SizedBox.shrink();
    }

    final boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: (isDark ? Colors.white : Colors.black)
            .withValues(alpha: 0.1 * clampedOpacity),
        width: 0.5,
      ),
      color: isDark
          ? const Color(0xFF2C2C2E).withValues(alpha: 0.92 * clampedOpacity)
          : Colors.white.withValues(alpha: 0.92 * clampedOpacity),
    );

    return Container(
      height: 40 + 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 40,
        decoration: boxDecoration,
        child: searchContent,
      ),
    );
  }

  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        _lastPanelWidth = panelWidth;
        final emojiColumns = _computeEmojiColumns(panelWidth);
        final gifColumns = _computeGifColumns(panelWidth);
        final stickerColumns = _computeStickerColumns(panelWidth);

        return PageView(
          controller: _pageController,
          physics: const ClampingScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _currentTab = PanelTab.values[index];
              _lastSelectedTab = _currentTab;
              if (_currentTab == PanelTab.emoji) {
                _onScroll();
              } else if (_currentTab == PanelTab.sticker) {
                _onStickerScroll();
              }
            });
          },
          children: [
            // Tab 1: Emoji (Standard + Custom Emoji Packs 100% Expanded)
            Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _buildVerticalEmojiList(emojiColumns),
                  ),
                ),
                RepaintBoundary(child: _buildEmojiTopControls()),
              ],
            ),
            // Tab 2: GIF (Saved GIFs + Trending / Search)
            Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _buildGifGrid(gifColumns),
                  ),
                ),
                RepaintBoundary(
                  child: _buildSearch(
                    'Поиск GIF',
                    _gifSearchController,
                    _gifSearchQuery,
                    _onGifQueryChanged,
                    _gifSearchFocusNode,
                  ),
                ),
              ],
            ),
            // Tab 3: Stickers (Recent + Favorites + All Installed Packs 100% Expanded)
            Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _buildStickerGrid(stickerColumns),
                  ),
                ),
                RepaintBoundary(
                  child: _buildStickerTopControls(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmojiTopControls() {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final sharedStyle = glassProvider.enabled
        ? glassProvider.createStyle(
            context: context,
            cornerRadius: 24,
            refractionWidth: 24,
          )
        : null;

    return AnimatedBuilder(
      animation: _searchCollapseController,
      child: _buildEmojiSetSelector(isGrouped: true),
      builder: (context, selectorWidget) {
        final collapse = _searchCollapseController.value.clamp(0.0, 1.0);
        final bool isSearchLensVisible = collapse < 0.99;
        final double textOpacity = (1.0 - collapse * 1.2).clamp(0.0, 1.0);
        final double fallbackOpacity = (1.0 - collapse).clamp(0.0, 1.0);
        final double blendSmoothness =
            (collapse <= 0.005 || collapse >= 0.99)
                ? 0.0
                : math.sin(collapse * math.pi) * 26.0;

        final searchWidget = Positioned(
          top: _kEmojiSelectorHeight,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: collapse > 0.2,
            child: Transform.translate(
              offset: Offset(0, -collapse * _kEmojiSelectorHeight),
              child: Transform.scale(
                scaleX: 1.0 - (collapse * 0.12),
                scaleY: 1.0 - (collapse * 0.25),
                child: _buildSearch(
                  'Поиск эмодзи',
                  _emojiSearchController,
                  _emojiSearchQuery,
                  _onEmojiQueryChanged,
                  _emojiSearchFocusNode,
                  isGrouped: true,
                  opacity: glassProvider.enabled ? textOpacity : fallbackOpacity,
                  lensVisible: isSearchLensVisible,
                ),
              ),
            ),
          ),
        );

        final stack = Stack(
          clipBehavior: Clip.none,
          children: [
            searchWidget,
            selectorWidget!,
          ],
        );

        if (glassProvider.enabled && sharedStyle != null) {
          return SizedBox(
            height: _kEmojiSelectorHeight + _kSearchHeight,
            child: LiquidGlassBlender(
              smoothness: blendSmoothness,
              style: sharedStyle,
              child: stack,
            ),
          );
        }

        return SizedBox(
          height: _kEmojiSelectorHeight + _kSearchHeight,
          child: stack,
        );
      },
    );
  }

  Widget _buildStickerTopControls() {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final sharedStyle = glassProvider.enabled
        ? glassProvider.createStyle(
            context: context,
            cornerRadius: 24,
            refractionWidth: 24,
          )
        : null;

    return AnimatedBuilder(
      animation: _stickerCollapseController,
      child: _buildStickerSetSelector(),
      builder: (context, selectorWidget) {
        final collapse = _stickerCollapseController.value.clamp(0.0, 1.0);
        final bool isSearchLensVisible = collapse < 0.99;
        final double textOpacity = (1.0 - collapse * 1.2).clamp(0.0, 1.0);
        final double fallbackOpacity = (1.0 - collapse).clamp(0.0, 1.0);
        final double blendSmoothness =
            (collapse <= 0.005 || collapse >= 0.99)
                ? 0.0
                : math.sin(collapse * math.pi) * 26.0;

        final searchWidget = Positioned(
          top: _kEmojiSelectorHeight,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: collapse > 0.2,
            child: Transform.translate(
              offset: Offset(0, -collapse * _kEmojiSelectorHeight),
              child: Transform.scale(
                scaleX: 1.0 - (collapse * 0.12),
                scaleY: 1.0 - (collapse * 0.25),
                child: _buildSearch(
                  'Поиск стикеров',
                  _stickerSearchController,
                  _stickerSearchQuery,
                  _onStickerQueryChanged,
                  _stickerSearchFocusNode,
                  isGrouped: true,
                  opacity: glassProvider.enabled ? textOpacity : fallbackOpacity,
                  lensVisible: isSearchLensVisible,
                ),
              ),
            ),
          ),
        );

        final stack = Stack(
          clipBehavior: Clip.none,
          children: [
            searchWidget,
            selectorWidget!,
          ],
        );

        if (glassProvider.enabled && sharedStyle != null) {
          return SizedBox(
            height: _kEmojiSelectorHeight + _kSearchHeight,
            child: LiquidGlassBlender(
              smoothness: blendSmoothness,
              style: sharedStyle,
              child: stack,
            ),
          );
        }

        return SizedBox(
          height: _kEmojiSelectorHeight + _kSearchHeight,
          child: stack,
        );
      },
    );
  }

  void _onEmojiSelected(Emoji emoji, {String? packId}) {
    HapticUtils.tap();
    _updateRecentEmojis(emoji);
    if (packId != null) {
      _updatePackUsage(packId);
    }

    if (widget.onEmojiSelected != null) {
      widget.onEmojiSelected!(emoji.emoji);
      return;
    }

    final ctrl = widget.controller;
    if (ctrl != null) {
      final text = ctrl.text;
      final selection = ctrl.selection;

      int start = selection.start;
      int end = selection.end;
      if (start < 0 || end < 0) {
        start = text.length;
        end = text.length;
      }

      final newText = text.replaceRange(start, end, emoji.emoji);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + emoji.emoji.length),
      );
      return;
    }

    StickerService.instance.activeInputTarget?.onInsertEmoji(emoji.emoji);
  }

  void _onCustomEmojiItemTapped(StickerItem item) {
    HapticUtils.tap();
    _updatePackUsage(item.packId.toString());
    if (widget.onCustomEmojiSelected != null) {
      widget.onCustomEmojiSelected!(item);
      return;
    }
    final ctrl = widget.controller;
    if (ctrl is RichTextEditingController) {
      ctrl.insertCustomEmoji(item);
      return;
    }
    if (StickerService.instance.activeInputTarget != null) {
      StickerService.instance.activeInputTarget!.onInsertCustomEmoji(item);
      return;
    }
    final fallback = item.emojis.isNotEmpty ? item.emojis.first : '😀';
    _onEmojiSelected(Emoji(fallback, fallback), packId: item.packId.toString());
  }

  void _onStickerItemTapped(StickerItem item) {
    HapticUtils.tap();
    StickerService.instance.recordStickerSent(item);
    if (widget.onStickerSelected != null) {
      widget.onStickerSelected!(item);
      return;
    }
    StickerService.instance.activeInputTarget?.onSendSticker(item);
  }

  void _onGifItemTapped(GifItemModel gif) {
    HapticUtils.tap();
    if (StickerService.instance.isGifSaved(gif.id, gif.url)) {
      StickerService.instance.saveGif(gif);
    }
    if (widget.onGifSelected != null) {
      widget.onGifSelected!(gif);
      return;
    }
    StickerService.instance.activeInputTarget?.onSendGif(gif);
  }

  Widget _buildVerticalEmojiList(int emojiColumns) {
    _ensureStickerSectionKeys();
    List<CategoryEmoji> categories = [...defaultEmojiSet];

    final installedEmojiPacks = StickerService.instance.installedEmojiPacks;
    final bool isSearching = _emojiSearchQuery.trim().isNotEmpty;

    if (!isSearching) {
      _emojiSectionOffsets.clear();
      double cursorY = _kEmojiHeaderHeight;
      final double cellSize =
          ((_lastPanelWidth - 24.0 - (emojiColumns - 1) * 8.0) / emojiColumns)
              .clamp(24.0, 120.0);
      double sectionHeight(int count) {
        if (count <= 0) return 0.0;
        final rows = (count + emojiColumns - 1) ~/ emojiColumns;
        return 38.0 + rows * cellSize + (rows - 1) * 8.0;
      }

      if (_displayedRecentEmojis.isNotEmpty) {
        _emojiSectionOffsets['recent'] = cursorY;
        cursorY += sectionHeight(_displayedRecentEmojis.length);
      }
      for (final pack in installedEmojiPacks) {
        if (pack.items.isNotEmpty) {
          _emojiSectionOffsets['srv_${pack.id}'] = cursorY;
          cursorY += sectionHeight(pack.items.length);
        }
      }
      for (final pack in _customPacks) {
        _emojiSectionOffsets[pack.id] = cursorY;
        cursorY += sectionHeight(pack.emojis.length);
      }
      for (final cat in categories) {
        if (cat.category == Category.SMILEYS) {
          _emojiSectionOffsets['standard'] = cursorY;
        }
        cursorY += sectionHeight(cat.emoji.length);
      }
    }

    List<StickerItem> matchingCustomEmojiItems = [];
    if (isSearching) {
      if (_displayedRecentEmojis.isNotEmpty) {
        categories.insert(
          0,
          CategoryEmoji(Category.RECENT, _displayedRecentEmojis),
        );
      }
      final query = _emojiSearchQuery.trim();
      categories = categories
          .map((cat) {
            return CategoryEmoji(
              cat.category,
              cat.emoji
                  .where((e) => EmojiUtils.matchesEmojiSearch(
                        e.emoji,
                        e.name,
                        query,
                      ))
                  .toList(),
            );
          })
          .where((cat) => cat.emoji.isNotEmpty)
          .toList();

      final seenIds = <int>{};
      for (final pack in installedEmojiPacks) {
        for (final item in pack.items) {
          if (item.matchesLocalQuery(query) && seenIds.add(item.id)) {
            matchingCustomEmojiItems.add(item);
          }
        }
      }
      for (final item in _remoteSearchedCustomEmojis) {
        if (seenIds.add(item.id)) {
          matchingCustomEmojiItems.add(item);
        }
      }
    }

    return CustomScrollView(
      controller: _gridScrollController,
      physics: const _EmojiScrollPhysics(parent: ClampingScrollPhysics()),
      cacheExtent: 180,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _kEmojiHeaderHeight)),
        if (isSearching && _isTelegramPackLink(_emojiSearchQuery))
          SliverToBoxAdapter(
            child: _buildTelegramImportPromptBanner(_emojiSearchQuery.trim()),
          ),
        if (isSearching && matchingCustomEmojiItems.isNotEmpty)
          ..._buildServerCustomEmojiSlivers(
            title: 'НАЙДЕННЫЕ КАСТОМНЫЕ ЭМОДЗИ',
            items: matchingCustomEmojiItems,
            emojiColumns: emojiColumns,
          ),
        if (!isSearching) ...[
          if (_displayedRecentEmojis.isNotEmpty)
            ..._buildCategorySlivers(
              CategoryEmoji(Category.RECENT, _displayedRecentEmojis),
              _sectionKeys['recent'],
              emojiColumns: emojiColumns,
              skipFilter: true,
            ),
          // All installed server Custom Emoji packs rendered 100% expanded by default
          for (final pack in installedEmojiPacks)
            if (pack.items.isNotEmpty)
              ..._buildServerCustomEmojiSlivers(
                title: pack.title.toUpperCase(),
                items: pack.items,
                emojiColumns: emojiColumns,
                sectionKey: _sectionKeys['srv_${pack.id}'],
                pack: pack,
              ),
          for (var pack in _customPacks)
            ..._buildCustomPackSlivers(pack, emojiColumns: emojiColumns),
        ],
        for (var categoryEmoji in categories)
          ..._buildCategorySlivers(
            categoryEmoji,
            _getSectionKeyForCategory(categoryEmoji.category),
            emojiColumns: emojiColumns,
            skipFilter: isSearching,
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  List<Widget> _buildServerCustomEmojiSlivers({
    required String title,
    required List<StickerItem> items,
    required int emojiColumns,
    GlobalKey? sectionKey,
    StickerPack? pack,
  }) {
    final theme = TheavTheme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          key: sectionKey,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (pack != null)
                GestureDetector(
                  onTap: () => StickerPackDetailSheet.show(
                    context,
                    packIdOrSlug: pack.id,
                    initialPack: pack,
                    onSelectSticker: _onCustomEmojiItemTapped,
                  ),
                  child: Text(
                    'Набор',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: emojiColumns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => _onCustomEmojiItemTapped(item),
                onLongPress: () {
                  StickerPeekPopOverlay.show(
                    context: context,
                    sticker: item,
                    onSend: () => _onCustomEmojiItemTapped(item),
                    onOpenPack: item.packId > 0
                        ? () => StickerPackDetailSheet.show(
                              context,
                              packIdOrSlug: item.packId,
                            )
                        : null,
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: StickerMediaView(
                    key: ValueKey('ce_${item.id}'),
                    fileUrl: item.fileUrl,
                    thumbnailUrl: item.thumbnailUrl,
                    stickerId: item.id,
                    format: item.format,
                    width: 30,
                    height: 30,
                    animate: _currentTab == PanelTab.emoji && widget.isVisible,
                  ),
                ),
              );
            },
            childCount: items.length, // 100% expanded in full
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  GlobalKey? _getSectionKeyForCategory(Category category) {
    if (category == Category.RECENT) return _sectionKeys['recent'];
    if (category == Category.SMILEYS) return _sectionKeys['standard'];
    return null;
  }

  List<Widget> _buildCategorySlivers(
    CategoryEmoji categoryEmoji,
    GlobalKey? key, {
    required int emojiColumns,
    bool skipFilter = false,
  }) {
    final theme = TheavTheme.of(context);
    if (!skipFilter && _emojiSearchQuery.isNotEmpty) {
      final query = _emojiSearchQuery.trim();
      final filteredEmojis = categoryEmoji.emoji
          .where((e) => EmojiUtils.matchesEmojiSearch(e.emoji, e.name, query))
          .toList();
      if (filteredEmojis.isEmpty) return [];
      categoryEmoji = CategoryEmoji(categoryEmoji.category, filteredEmojis);
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          key: key,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            _getCategoryName(categoryEmoji.category),
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: emojiColumns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final emoji = categoryEmoji.emoji[index];
              return GestureDetector(
                onTap: () => _onEmojiSelected(emoji),
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: EmojiUtils.appleEmoji(emoji.emoji, size: 26),
                ),
              );
            },
            childCount: categoryEmoji.emoji.length,
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildCustomPackSlivers(
    CustomEmojiPack pack, {
    required int emojiColumns,
  }) {
    final theme = TheavTheme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          key: _sectionKeys[pack.id],
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            pack.name.toUpperCase(),
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: emojiColumns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final emoji = pack.emojis[index];
              return GestureDetector(
                onTap: () => _onEmojiSelected(emoji, packId: pack.id),
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: EmojiUtils.appleEmoji(emoji.emoji, size: 26),
                ),
              );
            },
            childCount: pack.emojis.length, // 100% expanded
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  Widget _buildEmojiSetSelector({bool isGrouped = false}) {
    _ensureStickerSectionKeys();
    final theme = Theme.of(context);
    final theavTheme = TheavTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();

    final sortedPacks = List<CustomEmojiPack>.from(_customPacks)
      ..sort((a, b) {
        int countA = _displayedPackUsageStats[a.id] ?? 0;
        int countB = _displayedPackUsageStats[b.id] ?? 0;
        return countB.compareTo(countA);
      });
    final installedEmojiPacks = StickerService.instance.installedEmojiPacks;

    final selectorContent = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(width: 6),
          if (_displayedRecentEmojis.isNotEmpty)
            _buildVectorSelectorButton(
              iconoir.Clock(
                width: 20,
                height: 20,
                color: theavTheme.textSecondary,
              ),
              () => _scrollToEmojiSectionById('recent'),
            ),
          for (final srvPack in installedEmojiPacks)
            _buildServerPackSelectorIcon(
              srvPack,
              () => _scrollToEmojiSectionById('srv_${srvPack.id}'),
            ),
          for (var pack in sortedPacks) _buildSelectorPackIcon(pack),
          _buildVectorSelectorButton(
            iconoir.Emoji(
              width: 20,
              height: 20,
              color: theavTheme.textSecondary,
            ),
            () => _scrollToEmojiSectionById('standard'),
          ),
          _buildVectorSelectorButton(
            iconoir.Plus(
              width: 20,
              height: 20,
              color: theavTheme.textSecondary,
            ),
            () => CreateStickerPackScreen.showModal(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );

    return _wrapCapsuleSelector(isDark, glassProvider, selectorContent);
  }

  Widget _buildStickerSetSelector() {
    _ensureStickerSectionKeys();
    final theme = Theme.of(context);
    final theavTheme = TheavTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final installedStickerPacks = StickerService.instance.installedStickerPacks;

    final selectorContent = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(width: 6),
          if (StickerService.instance.recentStickers.isNotEmpty)
            _buildVectorSelectorButton(
              iconoir.Clock(
                width: 20,
                height: 20,
                color: theavTheme.textSecondary,
              ),
              () => _scrollToStickerSectionById('recent'),
            ),
          if (StickerService.instance.favoriteStickers.isNotEmpty)
            _buildVectorSelectorButton(
              iconoir.Star(
                width: 20,
                height: 20,
                color: theavTheme.textSecondary,
              ),
              () => _scrollToStickerSectionById('favorites'),
            ),
          for (final pack in installedStickerPacks)
            _buildServerPackSelectorIcon(
              pack,
              () => _scrollToStickerSectionById(pack.id.toString()),
            ),
          _buildVectorSelectorButton(
            iconoir.Plus(
              width: 20,
              height: 20,
              color: theavTheme.textSecondary,
            ),
            () => CreateStickerPackScreen.showModal(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );

    return _wrapCapsuleSelector(isDark, glassProvider, selectorContent);
  }

  Widget _wrapCapsuleSelector(
    bool isDark,
    LiquidGlassProvider glassProvider,
    Widget selectorContent,
  ) {
    final boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: isDark ? Colors.white10 : Colors.black12,
        width: 0.5,
      ),
      color: isDark
          ? const Color(0xFF2C2C2E).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.92),
    );

    final selectorStyle = glassProvider.createStyle(
      context: context,
      cornerRadius: 24,
      refractionWidth: 24,
    );

    return Container(
      height: 40 + 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: glassProvider.enabled
          ? LiquidGlassLens(
              style: selectorStyle,
              child: SizedBox(
                height: 40,
                width: double.infinity,
                child: selectorContent,
              ),
            )
          : Container(
              height: 40,
              width: double.infinity,
              decoration: boxDecoration,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: selectorContent,
              ),
            ),
    );
  }

  Widget _buildVectorSelectorButton(Widget icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildServerPackSelectorIcon(StickerPack pack, VoidCallback onTap) {
    final firstItem = pack.items.isNotEmpty ? pack.items.first : null;
    final coverUrl = pack.coverUrl.isNotEmpty
        ? pack.coverUrl
        : (firstItem?.fileUrl ?? '');
    final thumbUrl = firstItem?.thumbnailUrl.isNotEmpty == true
        ? firstItem!.thumbnailUrl
        : pack.thumbnailUrl;
    final format = firstItem?.format ?? 'webp';
    return GestureDetector(
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: coverUrl.isNotEmpty
              ? StickerMediaView(
                  fileUrl: coverUrl,
                  thumbnailUrl: thumbUrl,
                  stickerId: firstItem?.id,
                  format: format,
                  width: 24,
                  height: 24,
                  animate: false,
                )
              : Text(
                  pack.title.isNotEmpty ? pack.title[0].toUpperCase() : '#',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSelectorPackIcon(CustomEmojiPack pack) {
    return GestureDetector(
      onTap: () {
        HapticUtils.tap();
        _scrollToEmojiSectionById(pack.id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Center(
          child: EmojiUtils.appleEmoji(pack.emojis.first.emoji, size: 20),
        ),
      ),
    );
  }

  Future<void> _scrollToEmojiSectionById(String keyId) async {
    _ensureStickerSectionKeys();
    if (!_gridScrollController.hasClients) return;
    if (_emojiSearchQuery.isNotEmpty) {
      _emojiSearchController.clear();
      _onEmojiQueryChanged('');
      await WidgetsBinding.instance.endOfFrame;
    }

    final key = _sectionKeys[keyId];
    final precomputedY = _emojiSectionOffsets[keyId];
    if (precomputedY != null && precomputedY <= _kEmojiHeaderHeight + 2.0) {
      await _gridScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    const double collapsedTopOffset = _kEmojiSelectorHeight + 4.0;
    if (key?.currentContext != null) {
      _animateToKey(key!, _gridScrollController, collapsedTopOffset);
      return;
    }

    if (precomputedY != null) {
      final target = (precomputedY - collapsedTopOffset)
          .clamp(0.0, _gridScrollController.position.maxScrollExtent);
      await _gridScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      if (mounted && key?.currentContext != null) {
        _animateToKey(key!, _gridScrollController, collapsedTopOffset);
      }
    }
  }

  Future<void> _scrollToStickerSectionById(String keyId) async {
    _ensureStickerSectionKeys();
    if (!_stickerScrollController.hasClients) return;
    if (_stickerSearchQuery.isNotEmpty) {
      _stickerSearchController.clear();
      _onStickerQueryChanged('');
      await WidgetsBinding.instance.endOfFrame;
    }

    final key = _stickerSectionKeys[keyId];
    final precomputedY = _stickerSectionOffsets[keyId];
    if (keyId == 'recent' ||
        (precomputedY != null && precomputedY <= _kEmojiHeaderHeight + 2.0)) {
      await _stickerScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    const double collapsedTopOffset = _kEmojiSelectorHeight + 4.0;
    if (key?.currentContext != null) {
      _animateToKey(key!, _stickerScrollController, collapsedTopOffset);
      return;
    }

    if (precomputedY != null) {
      final target = (precomputedY - collapsedTopOffset)
          .clamp(0.0, _stickerScrollController.position.maxScrollExtent);
      await _stickerScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      if (mounted && key?.currentContext != null) {
        _animateToKey(key!, _stickerScrollController, collapsedTopOffset);
      }
    }
  }

  void _animateToKey(
    GlobalKey key,
    ScrollController scrollController,
    double topOffset,
  ) {
    final context = key.currentContext;
    if (context == null || !scrollController.hasClients) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final scrollable = Scrollable.of(context);
    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    if (viewport == null) return;

    final position = renderBox.localToGlobal(Offset.zero, ancestor: viewport);
    final targetOffset = scrollController.offset + position.dy - topOffset;

    scrollController.animateTo(
      targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _updatePackUsage(String packId) {
    _packUsageStats[packId] = (_packUsageStats[packId] ?? 0) + 1;
    _savePackUsageStats();
  }

  Future<void> _loadPackUsageStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? statsJson = prefs.getString('pack_usage_stats');
      if (statsJson != null) {
        final loaded = Map<String, int>.from(jsonDecode(statsJson));
        if (mounted) {
          setState(() {
            _packUsageStats = loaded;
            _displayedPackUsageStats = Map<String, int>.from(loaded);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading pack usage stats: $e');
    }
  }

  Future<void> _savePackUsageStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pack_usage_stats', jsonEncode(_packUsageStats));
    } catch (e) {
      debugPrint('Error saving pack usage stats: $e');
    }
  }

  String _getCategoryName(Category category) {
    switch (category) {
      case Category.RECENT:
        return 'НЕДАВНИЕ';
      case Category.SMILEYS:
        return 'СМАЙЛЫ И ЛЮДИ';
      case Category.ANIMALS:
        return 'ЖИВОТНЫЕ И ПРИРОДА';
      case Category.FOODS:
        return 'ЕДА И НАПИТКИ';
      case Category.ACTIVITIES:
        return 'АКТИВНОСТЬ';
      case Category.TRAVEL:
        return 'ПУТЕШЕСТВИЯ';
      case Category.OBJECTS:
        return 'ОБЪЕКТЫ';
      case Category.SYMBOLS:
        return 'СИМВОЛЫ';
      case Category.FLAGS:
        return 'ФЛАГИ';
    }
  }

  Widget _buildGifGrid(int gifColumns) {
    final theme = TheavTheme.of(context);
    final isSearching = _gifSearchQuery.trim().isNotEmpty;
    final savedGifs = StickerService.instance.savedGifs;
    final trendingGifs = isSearching
        ? _remoteSearchedGifs
        : StickerService.instance.trendingGifs;

    return CustomScrollView(
      controller: _gifScrollController,
      physics: const ClampingScrollPhysics(),
      cacheExtent: 180,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _kSearchHeight + 8)),
        if (!isSearching && savedGifs.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(
                'СОХРАНЁННЫЕ GIF',
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: _buildGifSliverGrid(
              items: savedGifs,
              columns: gifColumns,
              theme: theme,
              isSavedSection: true,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              isSearching ? 'РЕЗУЛЬТАТЫ ПОИСКА' : 'ПОПУЛЯРНЫЕ',
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        if (_isSearchingGifs)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.accent,
                  ),
                ),
              ),
            ),
          )
        else if (trendingGifs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  isSearching
                      ? 'По вашему запросу GIF не найдены'
                      : 'Популярные GIF появятся здесь',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textSecondary,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: _buildGifSliverGrid(
              items: trendingGifs,
              columns: gifColumns,
              theme: theme,
              isSavedSection: false,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  Widget _buildGifSliverGrid({
    required List<GifItemModel> items,
    required int columns,
    required TheavThemeData theme,
    required bool isSavedSection,
  }) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 1.45,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final gif = items[index];
          final preview = gif.previewUrl.isNotEmpty ? gif.previewUrl : gif.url;
          final resolvedUrl = StickerService.resolveUrl(preview);
          return GestureDetector(
            onTap: () => _onGifItemTapped(gif),
            onLongPress: () {
              HapticUtils.selection();
              if (isSavedSection) {
                StickerService.instance.removeSavedGif(gif.id);
              } else {
                StickerService.instance.saveGif(gif);
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: theme.inputBg,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: ControlledAnimatedNetworkImage(
                        url: resolvedUrl,
                        isAnimatedWebpOrGif: true,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        animate: _currentTab == PanelTab.gif && widget.isVisible,
                        errorBuilder: (_) => Center(
                          child: Text(
                            'GIF',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isSavedSection)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const iconoir.BookmarkSolid(
                            width: 12,
                            height: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        childCount: items.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  Widget _buildTelegramImportPromptBanner(String rawLink) {
    final theme = TheavTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: GestureDetector(
        onTap: () => CreateStickerPackScreen.showModal(
          context,
          initialModeIndex: 0,
          initialTelegramLink: rawLink,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.accent, width: 1),
          ),
          child: Row(
            children: [
              iconoir.Download(width: 18, height: 18, color: theme.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Импортировать этот набор из Telegram',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.accent,
                  ),
                ),
              ),
              iconoir.NavArrowRight(width: 18, height: 18, color: theme.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickerGrid(int stickerColumns) {
    _ensureStickerSectionKeys();
    final theme = TheavTheme.of(context);
    final isSearching = _stickerSearchQuery.trim().isNotEmpty;
    final recentStickers = StickerService.instance.recentStickers;
    final favoriteStickers = StickerService.instance.favoriteStickers;
    final installedPacks = StickerService.instance.installedStickerPacks;
    final featuredPacks = StickerService.instance.featuredPacks
        .where((p) =>
            !p.isCustomEmoji &&
            !installedPacks.any((inst) => inst.id == p.id))
        .toList();

    if (!isSearching) {
      _stickerSectionOffsets.clear();
      double cursorY = _kEmojiHeaderHeight;
      final double cellSize =
          ((_lastPanelWidth - 20.0 - (stickerColumns - 1) * 10.0) /
                  stickerColumns)
              .clamp(32.0, 160.0);
      double sectionHeight(int count) {
        if (count <= 0) return 0.0;
        final rows = (count + stickerColumns - 1) ~/ stickerColumns;
        return 38.0 + rows * cellSize + (rows - 1) * 10.0;
      }

      if (recentStickers.isNotEmpty) {
        _stickerSectionOffsets['recent'] = cursorY;
        cursorY += sectionHeight(recentStickers.length);
      }
      if (favoriteStickers.isNotEmpty) {
        _stickerSectionOffsets['favorites'] = cursorY;
        cursorY += sectionHeight(favoriteStickers.length);
      }
      for (final pack in installedPacks) {
        if (pack.items.isNotEmpty) {
          _stickerSectionOffsets[pack.id.toString()] = cursorY;
          cursorY += sectionHeight(pack.items.length);
        }
      }
    }

    List<StickerItem> searchResults = [];
    if (isSearching) {
      final q = _stickerSearchQuery.trim();
      final seen = <int>{};
      for (final pack in installedPacks) {
        for (final item in pack.items) {
          if (item.matchesLocalQuery(q) && seen.add(item.id)) {
            searchResults.add(item);
          }
        }
      }
      for (final item in _remoteSearchedStickers) {
        if (seen.add(item.id)) {
          searchResults.add(item);
        }
      }
    }

    return CustomScrollView(
      controller: _stickerScrollController,
      physics: const _EmojiScrollPhysics(parent: ClampingScrollPhysics()),
      cacheExtent: 180,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _kEmojiHeaderHeight)),
        if (isSearching && _isTelegramPackLink(_stickerSearchQuery))
          SliverToBoxAdapter(
            child: _buildTelegramImportPromptBanner(_stickerSearchQuery.trim()),
          ),
        if (isSearching) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'РЕЗУЛЬТАТЫ ПОИСКА',
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          if (_isSearchingStickers && searchResults.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.accent,
                    ),
                  ),
                ),
              ),
            )
          else if (searchResults.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Стикеры не найдены',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            ..._buildStickerSectionSlivers(
              title: null,
              items: searchResults,
              columns: stickerColumns,
            ),
        ] else ...[
          if (recentStickers.isNotEmpty)
            ..._buildStickerSectionSlivers(
              title: 'НЕДАВНИЕ',
              sectionKey: _stickerSectionKeys['recent'],
              items: recentStickers,
              columns: stickerColumns,
            ),
          if (favoriteStickers.isNotEmpty)
            ..._buildStickerSectionSlivers(
              title: 'ИЗБРАННЫЕ',
              sectionKey: _stickerSectionKeys['favorites'],
              items: favoriteStickers,
              columns: stickerColumns,
            ),
          // All installed sticker packs rendered 100% expanded in full
          for (final pack in installedPacks)
            if (pack.items.isNotEmpty)
              ..._buildStickerSectionSlivers(
                title: pack.title.toUpperCase(),
                sectionKey: _stickerSectionKeys[pack.id.toString()],
                items: pack.items,
                columns: stickerColumns,
                pack: pack,
              ),
          if (installedPacks.isEmpty &&
              recentStickers.isEmpty &&
              favoriteStickers.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: GestureDetector(
                  onTap: () => CreateStickerPackScreen.showModal(context),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.inputBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.dividerColor,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        iconoir.Plus(
                          width: 22,
                          height: 22,
                          color: theme.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Импортировать из Telegram или создать набор',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Поддерживаются прозрачные .webp, .tgs, .webm и полноэкранные эффекты',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (featuredPacks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'ПОПУЛЯРНЫЕ НАБОРЫ',
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final pack = featuredPacks[index];
                  return _buildFeaturedPackCard(pack, theme);
                },
                childCount: featuredPacks.length,
              ),
            ),
          ],
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  List<Widget> _buildStickerSectionSlivers({
    required String? title,
    GlobalKey? sectionKey,
    required List<StickerItem> items,
    required int columns,
    StickerPack? pack,
  }) {
    final theme = TheavTheme.of(context);
    return [
      if (title != null)
        SliverToBoxAdapter(
          child: Padding(
            key: sectionKey,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (pack != null)
                  GestureDetector(
                    onTap: () => StickerPackDetailSheet.show(
                      context,
                      packIdOrSlug: pack.id,
                      initialPack: pack,
                      onSelectSticker: _onStickerItemTapped,
                    ),
                    child: Text(
                      'Набор',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 1.0,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => _onStickerItemTapped(item),
                onLongPress: () {
                  StickerPeekPopOverlay.show(
                    context: context,
                    sticker: item,
                    onSend: () => _onStickerItemTapped(item),
                    onOpenPack: item.packId > 0
                        ? () => StickerPackDetailSheet.show(
                              context,
                              packIdOrSlug: item.packId,
                              onSelectSticker: _onStickerItemTapped,
                            )
                        : null,
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    StickerMediaView(
                      fileUrl: item.fileUrl,
                      thumbnailUrl: item.thumbnailUrl,
                      stickerId: item.id,
                      format: item.format,
                      width: 68,
                      height: 68,
                      animate: _currentTab == PanelTab.sticker && widget.isVisible,
                    ),
                    if (item.hasFullscreenEffect)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: iconoir.Sparks(
                          width: 11,
                          height: 11,
                          color: theme.accent,
                        ),
                      ),
                  ],
                ),
              );
            },
            childCount: items.length, // 100% expanded in full
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  Widget _buildFeaturedPackCard(StickerPack pack, TheavThemeData theme) {
    final firstItem = pack.items.isNotEmpty ? pack.items.first : null;
    final cover = pack.coverUrl.isNotEmpty
        ? pack.coverUrl
        : (firstItem?.fileUrl ?? '');
    final thumbUrl = firstItem?.thumbnailUrl.isNotEmpty == true
        ? firstItem!.thumbnailUrl
        : pack.thumbnailUrl;
    final format = firstItem?.format ?? 'webp';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GestureDetector(
        onTap: () => StickerPackDetailSheet.show(
          context,
          packIdOrSlug: pack.id,
          initialPack: pack,
          onSelectSticker: _onStickerItemTapped,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor, width: 0.5),
          ),
          child: Row(
            children: [
              if (cover.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: StickerMediaView(
                    fileUrl: cover,
                    thumbnailUrl: thumbUrl,
                    stickerId: firstItem?.id,
                    format: format,
                    width: 40,
                    height: 40,
                    animate: false,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    Text(
                      '${pack.stickerCount} стикеров',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => StickerService.instance.installPack(pack.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Добавить',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingNav() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      height: 40,
      child: RepaintBoundary(
        child: BackdropGroup(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 220,
                child: _buildClassicNav(isDark, theme),
              ),
              Positioned(
                right: 16,
                child: _buildBackspaceButton(isDark, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassicNav(bool isDark, ThemeData theme) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final indicatorColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);

    final navContent = Container(
      height: 40,
      decoration: glassProvider.enabled
          ? null
          : BoxDecoration(
              color: isDark
                  ? const Color(0xFF2C2C2E).withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _pageController,
            builder: (context, child) {
              double offset = 0;
              try {
                offset = _pageController.hasClients
                    ? (_pageController.page ?? _currentTab.index.toDouble())
                    : _currentTab.index.toDouble();
              } catch (_) {
                offset = _currentTab.index.toDouble();
              }
              return Align(
                alignment: Alignment(
                  (offset / (PanelTab.values.length - 1) * 2) - 1,
                  0,
                ),
                child: child!,
              );
            },
            child: FractionallySizedBox(
              widthFactor: 1 / PanelTab.values.length,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    borderRadius: BorderRadius.circular(64),
                    border: Border.all(color: indicatorColor, width: 0.2),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var tab in PanelTab.values)
                Expanded(
                  child: _NavTab(
                    label: _getTabLabel(tab),
                    selected: _currentTab == tab,
                    onTap: () {
                      if (_currentTab != tab) {
                        HapticUtils.selection();
                        _lastSelectedTab = tab;
                        _pageController.animateToPage(
                          tab.index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                        );
                      }
                    },
                    isDark: isDark,
                    isGlass: false,
                    theme: theme,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (glassProvider.enabled) {
      final navStyle = glassProvider.createStyle(
        context: context,
        cornerRadius: 32,
        refractionWidth: 24,
      );

      return LiquidGlassLens(
        style: navStyle,
        child: SizedBox(
          height: 40,
          child: navContent,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: navContent,
      ),
    );
  }

  Widget _buildBackspaceButton(bool isDark, ThemeData theme) {
    final glassProvider = context.watch<LiquidGlassProvider>();

    final backspaceContent = GestureDetector(
      onTap: () {
        HapticUtils.tap();
        widget.onBackspace();
      },
      onLongPress: _startContinuousDelete,
      onLongPressUp: _stopContinuousDelete,
      onLongPressEnd: (_) => _stopContinuousDelete(),
      child: Container(
        width: 40,
        height: 40,
        decoration: glassProvider.enabled
            ? null
            : BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E).withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
        child: Center(
          child: Icon(
            Icons.backspace_outlined,
            color: isDark ? Colors.white70 : Colors.black87,
            size: 20,
          ),
        ),
      ),
    );

    if (glassProvider.enabled) {
      final buttonStyle = glassProvider.createStyle(
        context: context,
        cornerRadius: 20,
        refractionWidth: 24,
      );

      return LiquidGlassLens(
        style: buttonStyle,
        touch: const LiquidGlassTouch.flexing(
          LiquidGlassFlex(
            stretch: 4,
            squeeze: 0.8,
            lean: 0.2,
          ),
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: backspaceContent,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: backspaceContent,
      ),
    );
  }

  String _getTabLabel(PanelTab tab) {
    switch (tab) {
      case PanelTab.emoji:
        return 'Эмодзи';
      case PanelTab.gif:
        return 'GIF';
      case PanelTab.sticker:
        return 'Стикеры';
    }
  }

  bool _isDeleting = false;
  void _startContinuousDelete() {
    if (_isDeleting) return;
    _isDeleting = true;
    Future.doWhile(() async {
      if (!mounted || !_isDeleting) return false;
      HapticUtils.tap();
      widget.onBackspace();
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    });
  }

  void _stopContinuousDelete() {
    _isDeleting = false;
  }

  Future<void> _loadRecentEmojis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? recent = prefs.getStringList('recent_emojis');
      if (recent != null) {
        final loaded = recent.map((e) {
          final data = jsonDecode(e);
          return Emoji(data['emoji'], data['name']);
        }).toList();
        if (mounted) {
          setState(() {
            _recentEmojis = loaded;
            _displayedRecentEmojis = List<Emoji>.from(loaded);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recent emojis: $e');
    }
  }

  void _updateRecentEmojis(Emoji emoji) {
    final wasEmpty = _displayedRecentEmojis.isEmpty;
    _recentEmojis.removeWhere((e) => e.emoji == emoji.emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 45) {
      _recentEmojis = _recentEmojis.sublist(0, 45);
    }
    if (wasEmpty && mounted) {
      setState(() {
        _displayedRecentEmojis = List<Emoji>.from(_recentEmojis);
      });
    }
    _saveRecentEmojis();
  }

  Future<void> _saveRecentEmojis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> recent = _recentEmojis
          .map((e) => jsonEncode({'emoji': e.emoji, 'name': e.name}))
          .toList();
      await prefs.setStringList('recent_emojis', recent);
    } catch (e) {
      debugPrint('Error saving recent emojis: $e');
    }
  }
}

class _EmojiScrollPhysics extends ScrollPhysics {
  const _EmojiScrollPhysics({super.parent});

  @override
  _EmojiScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _EmojiScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    const double snapTarget = 48.0;
    final Simulation? parentSim =
        super.createBallisticSimulation(position, velocity);
    final double naturalEnd =
        parentSim != null ? parentSim.x(double.infinity) : position.pixels;

    if (naturalEnd >= snapTarget) {
      return parentSim;
    }

    if (naturalEnd > 0.0 && naturalEnd < snapTarget) {
      double target = naturalEnd > snapTarget / 2 ? snapTarget : 0.0;

      if (velocity < -100) {
        target = 0.0;
      } else if (velocity > 100) {
        target = snapTarget;
      }

      if ((target - position.pixels).abs() > 0.5) {
        return ScrollSpringSimulation(
          spring,
          position.pixels,
          target,
          velocity,
          tolerance: toleranceFor(position),
        );
      }
    }
    return parentSim;
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    required this.isGlass,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final bool isGlass;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? theme.colorScheme.primary
        : (isDark ? Colors.white54 : Colors.black54);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: label,
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
