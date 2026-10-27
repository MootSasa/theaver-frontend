import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/emoji_utils.dart';

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
  final TextEditingController controller;
  final VoidCallback onBackspace;
  final VoidCallback onClose;
  final double height;
  final bool isVisible;

  const EmojiStickerPanel({
    Key? key,
    required this.controller,
    required this.onBackspace,
    required this.onClose,
    this.height = _kPanelHeight,
    this.isVisible = true,
  }) : super(key: key);

  @override
  State<EmojiStickerPanel> createState() => _EmojiStickerPanelState();
}

class _EmojiStickerPanelState extends State<EmojiStickerPanel> with SingleTickerProviderStateMixin {
  PanelTab _currentTab = PanelTab.emoji;
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _gifScrollController = ScrollController();
  final ScrollController _stickerScrollController = ScrollController();
  final PageController _pageController = PageController();
  
  late final AnimationController _searchCollapseController;
  
  final TextEditingController _emojiSearchController = TextEditingController();
  final TextEditingController _gifSearchController = TextEditingController();
  final TextEditingController _stickerSearchController = TextEditingController();
  
  final FocusNode _emojiSearchFocusNode = FocusNode();
  final FocusNode _gifSearchFocusNode = FocusNode();
  final FocusNode _stickerSearchFocusNode = FocusNode();
  
  String _emojiSearchQuery = '';
  String _gifSearchQuery = '';
  String _stickerSearchQuery = '';
  List<Emoji> _recentEmojis = [];
  List<Emoji> _displayedRecentEmojis = [];
  
  List<CustomEmojiPack> _customPacks = [];
  Map<String, int> _packUsageStats = {};
  Map<String, int> _displayedPackUsageStats = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  double? _lastHapticPixels;

  // Lazy loading state for GIFs / Stickers
  int _loadedGifsCount = 14;
  int _loadedStickersCount = 24;
  bool _isLoadingMoreGifs = false;
  bool _isLoadingMoreStickers = false;
  int _lastEmojiColumns = 8;

  static int _computeEmojiColumns(double panelWidth) {
    final available = math.max(160.0, panelWidth - 24.0);
    return ((available + 8.0) / (36.0 + 8.0)).floor().clamp(5, 24);
  }

  static int _computeGifColumns(double panelWidth) {
    final available = math.max(160.0, panelWidth - 16.0);
    return ((available + 8.0) / (156.0 + 8.0)).floor().clamp(2, 8);
  }

  static int _computeStickerColumns(double panelWidth) {
    final available = math.max(160.0, panelWidth - 16.0);
    return ((available + 12.0) / (76.0 + 12.0)).floor().clamp(3, 12);
  }

  @override
  void initState() {
    super.initState();
    _searchCollapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _gridScrollController.addListener(_onScroll);
    _gifScrollController.addListener(_onGifScroll);
    _stickerScrollController.addListener(_onStickerScroll);
    _initMockPacks();
    _loadRecentEmojis();
    _loadPackUsageStats();
  }

  @override
  void didUpdateWidget(covariant EmojiStickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh displayed recent emojis and pack usage order only when reopening the panel,
    // preventing the emoji grid from jumping under the user's finger on tap.
    if (!oldWidget.isVisible && widget.isVisible) {
      _displayedRecentEmojis = List<Emoji>.from(_recentEmojis);
      _displayedPackUsageStats = Map<String, int>.from(_packUsageStats);
    }
  }

  void _onScroll() {
    if (_currentTab == PanelTab.emoji && _gridScrollController.hasClients) {
      final double offset = _gridScrollController.offset;
      // Collapse exactly by the search bar height (48px)
      final double targetCollapse = (offset / 48.0).clamp(0.0, 1.0);
      if ((_searchCollapseController.value - targetCollapse).abs() > 0.001) {
        _searchCollapseController.value = targetCollapse;
      }

      // Haptic feedback logic: trigger slightly before reaching boundaries (3px threshold)
      // for a more "snappy" feel, especially since the animation tail is slow.
      final bool isNearOpen = offset <= 3.0;
      final bool isNearClosed = (offset - 48.0).abs() <= 3.0;

      if (isNearOpen) {
        if (_lastHapticPixels != 0.0) {
          HapticUtils.selection();
          _lastHapticPixels = 0.0;
        }
      } else if (isNearClosed) {
        // Mark as reached closed state to prevent re-triggering open haptic
        // without moving away, but do NOT vibrate here.
        _lastHapticPixels = 48.0;
      } else {
        // Reset when moving away from boundaries to allow re-triggering
        _lastHapticPixels = null;
      }
    }
  }

  void _onGifScroll() {
    if (_gifScrollController.position.pixels > _gifScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreGifs && _loadedGifsCount < 100) {
        _loadMoreGifs();
      }
    }
  }

  Future<void> _loadMoreGifs() async {
    setState(() => _isLoadingMoreGifs = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _loadedGifsCount += 10;
        _isLoadingMoreGifs = false;
      });
    }
  }

  void _onStickerScroll() {
    if (_stickerScrollController.position.pixels > _stickerScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreStickers && _loadedStickersCount < 120) {
        _loadMoreStickers();
      }
    }
  }

  Future<void> _loadMoreStickers() async {
    setState(() => _isLoadingMoreStickers = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _loadedStickersCount += 16;
        _isLoadingMoreStickers = false;
      });
    }
  }

  // _snapSearchPanel is now handled by _EmojiScrollPhysics for better inertia

  void _initMockPacks() {
    _customPacks = [
      CustomEmojiPack(
        id: 'premium_stars',
        name: 'Premium Stars',
        emojis: [
          const Emoji('⭐', 'star'),
          const Emoji('🌟', 'glowing star'),
          const Emoji('✨', 'sparkles'),
          const Emoji('💫', 'dizzy'),
          const Emoji('🌠', 'shooting star'),
        ],
      ),
      CustomEmojiPack(
        id: 'cool_faces',
        name: 'Cool Faces',
        emojis: [
          const Emoji('😎', 'sunglasses'),
          const Emoji('😏', 'smirking'),
          const Emoji('🥵', 'hot'),
          const Emoji('🥶', 'cold'),
          const Emoji('🥸', 'disguise'),
        ],
      ),
      CustomEmojiPack(
        id: 'animal_party',
        name: 'Animal Party',
        emojis: [
          const Emoji('🥳', 'party face'),
          const Emoji('🦁', 'lion'),
          const Emoji('🐯', 'tiger'),
          const Emoji('🦒', 'giraffe'),
          const Emoji('🦊', 'fox'),
        ],
      ),
    ];
    
    _sectionKeys['recent'] = GlobalKey();
    _sectionKeys['standard'] = GlobalKey();
    for (var pack in _customPacks) {
      _sectionKeys[pack.id] = GlobalKey();
    }
  }

  @override
  void dispose() {
    _gridScrollController.removeListener(_onScroll);
    _gridScrollController.dispose();
    _gifScrollController.dispose();
    _stickerScrollController.dispose();
    _pageController.dispose();
    _searchCollapseController.dispose();
    
    _emojiSearchController.dispose();
    _gifSearchController.dispose();
    _stickerSearchController.dispose();
    
    _emojiSearchFocusNode.dispose();
    _gifSearchFocusNode.dispose();
    _stickerSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayHeight = widget.height;
    if (!widget.isVisible || displayHeight <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();

    return SizedBox(
      height: displayHeight,
      child: Stack(
        children: [
          // 1. Background layer
          Positioned.fill(
            child: glassProvider.enabled
                ? LiquidGlassLens(
                    style: glassProvider.createStyle(
                      context: context,
                      cornerRadius: 0,
                      borderWidth: 0,
                      refractionIndex: 1.02,
                      refractionWidth: 24,
                    ),
                    child: const SizedBox.expand(),
                  )
                : ClipRect(
                    child: BackdropFilter(
                      filter: BlurUtils.createDownsampledBlur(15),
                      child: Container(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.65)
                            : Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
          ),
          // 2. Content layer
          Positioned.fill(
            child: _buildPanelContent(false),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelContent(bool isSearching) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
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
    // Header remains but tabs are moved to floating nav
    return Container(
      height: 8, // Smaller header or just spacing
    );
  }

  Widget _buildSearch(String hint, TextEditingController controller, String query, ValueChanged<String> onChanged, FocusNode focusNode, {bool isGrouped = false, double opacity = 1.0}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();

    if (!glassProvider.enabled && opacity <= 0) return const SizedBox.shrink();

    final Widget searchContent = Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: IgnorePointer(
        ignoring: opacity <= 0.1,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              Icons.search,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              size: 20,
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
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            if (query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                  // Keep focus so user can type again
                  if (!focusNode.hasFocus) {
                    focusNode.requestFocus();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.close,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    size: 18,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );

    final boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.1 * opacity),
        width: 0.5,
      ),
      color: isDark
          ? const Color(0xFF2C2C2E).withOpacity(0.7 * opacity)
          : Colors.white.withOpacity(0.7 * opacity),
    );

    final searchStyle = glassProvider.createStyle(
      context: context,
      cornerRadius: 24,
      refractionWidth: 24,
    );

    return Container(
      height: 40 + 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: glassProvider.enabled
          ? LiquidGlassLens(
              style: searchStyle,
              child: SizedBox(
                height: 40,
                child: searchContent,
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: BlurUtils.createDownsampledBlur(15),
                child: Container(
                  height: 40,
                  decoration: boxDecoration,
                  child: searchContent,
                ),
              ),
            ),
    );
  }

  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final emojiColumns = _computeEmojiColumns(panelWidth);
        final gifColumns = _computeGifColumns(panelWidth);
        final stickerColumns = _computeStickerColumns(panelWidth);
        _lastEmojiColumns = emojiColumns;

        return PageView(
          controller: _pageController,
          physics: const ClampingScrollPhysics(), // Prevent horizontal stretch effect
          onPageChanged: (index) {
            setState(() {
              _currentTab = PanelTab.values[index];
              if (_currentTab != PanelTab.emoji) {
                _searchCollapseController.value = 0.0;
              } else {
                _onScroll();
              }
            });
          },
          children: [
            // Tab 1: Emoji
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
            // Tab 2: GIF
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
                    (v) => setState(() => _gifSearchQuery = v),
                    _gifSearchFocusNode,
                  ),
                ),
              ],
            ),
            // Tab 3: Stickers
            Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _buildStickerGrid(stickerColumns),
                  ),
                ),
                RepaintBoundary(
                  child: _buildSearch(
                    'Поиск стикеров',
                    _stickerSearchController,
                    _stickerSearchQuery,
                    (v) => setState(() => _stickerSearchQuery = v),
                    _stickerSearchFocusNode,
                  ),
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
        final collapse = _searchCollapseController.value;
        final textOpacity = Curves.easeOut.transform((1.0 - collapse * 1.5).clamp(0.0, 1.0));
        final fallbackOpacity = (1.0 - collapse).clamp(0.0, 1.0);
        final blendSmoothness = math.sin(collapse * math.pi) * 28.0;

        final searchWidget = Positioned(
          top: _kEmojiSelectorHeight,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(0, -collapse * _kEmojiSelectorHeight),
            child: Transform.scale(
              scale: 1.0 - (collapse * 0.15),
              child: _buildSearch(
                'Поиск эмодзи',
                _emojiSearchController,
                _emojiSearchQuery,
                (v) => setState(() => _emojiSearchQuery = v),
                _emojiSearchFocusNode,
                isGrouped: true,
                opacity: glassProvider.enabled ? textOpacity : fallbackOpacity,
              ),
            ),
          ),
        );

        if (glassProvider.enabled && sharedStyle != null) {
          return SizedBox(
            height: _kEmojiSelectorHeight + _kSearchHeight,
            child: LiquidGlassBlender(
              smoothness: blendSmoothness,
              style: sharedStyle,
              child: Stack(
                children: [
                  searchWidget,
                  selectorWidget!,
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: _kEmojiSelectorHeight + _kSearchHeight,
          child: Stack(
            children: [
              searchWidget,
              selectorWidget!,
            ],
          ),
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
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, emoji.emoji);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.emoji.length),
    );
  }

  Widget _buildVerticalEmojiList(int emojiColumns) {
    List<CategoryEmoji> categories = [...defaultEmojiSet];

    if (_displayedRecentEmojis.isNotEmpty) {
      categories.insert(0, CategoryEmoji(Category.RECENT, _displayedRecentEmojis));
    }

    final bool isSearching = _emojiSearchQuery.isNotEmpty;
    if (isSearching) {
      final query = _emojiSearchQuery.toLowerCase();
      categories = categories.map((cat) {
        return CategoryEmoji(
          cat.category,
          cat.emoji.where((e) => e.emoji.contains(query) || e.name.toLowerCase().contains(query)).toList(),
        );
      }).where((cat) => cat.emoji.isNotEmpty).toList();
    }

    return CustomScrollView(
      controller: _gridScrollController,
      physics: const _EmojiScrollPhysics(parent: ClampingScrollPhysics()),
      cacheExtent: 500,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _kEmojiHeaderHeight)),
        for (var categoryEmoji in categories)
          ..._buildCategorySlivers(
            categoryEmoji,
            _getSectionKeyForCategory(categoryEmoji.category),
            emojiColumns: emojiColumns,
            skipFilter: isSearching,
          ),
        if (!isSearching)
          for (var pack in _customPacks)
            ..._buildCustomPackSlivers(pack, emojiColumns: emojiColumns),
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
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
    if (!skipFilter && _emojiSearchQuery.isNotEmpty) {
      final query = _emojiSearchQuery.toLowerCase();
      final filteredEmojis = categoryEmoji.emoji.where((e) => e.emoji.contains(query) || e.name.toLowerCase().contains(query)).toList();
      if (filteredEmojis.isEmpty) return [];
      categoryEmoji = CategoryEmoji(categoryEmoji.category, filteredEmojis);
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          key: key,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _getCategoryName(categoryEmoji.category),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
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
    return [
      SliverToBoxAdapter(
        child: Padding(
          key: _sectionKeys[pack.id],
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            pack.name.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
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
            childCount: pack.emojis.length,
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
    ];
  }

  Widget _buildEmojiSetSelector({bool isGrouped = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();

    final sortedPacks = List<CustomEmojiPack>.from(_customPacks)
      ..sort((a, b) {
        int countA = _displayedPackUsageStats[a.id] ?? 0;
        int countB = _displayedPackUsageStats[b.id] ?? 0;
        return countB.compareTo(countA);
      });

    final selectorContent = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(width: 4),
          // Recent
          if (_displayedRecentEmojis.isNotEmpty)
            _buildSelectorIcon(Icons.access_time_rounded, () => _scrollToSection(_sectionKeys['recent'])),
          
          // Standard
          _buildSelectorIcon(Icons.emoji_emotions_outlined, () => _scrollToSection(_sectionKeys['standard'])),
          
          // Custom Packs
          for (var pack in sortedPacks)
            _buildSelectorPackIcon(pack),
          const SizedBox(width: 4),
        ],
      ),
    );

    final boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: isDark ? Colors.white10 : Colors.black12,
        width: 0.5,
      ),
      color: isDark
          ? const Color(0xFF2C2C2E).withOpacity(0.7)
          : Colors.white.withOpacity(0.7),
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
          : ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: BlurUtils.createDownsampledBlur(15),
                child: Container(
                  height: 40,
                  width: double.infinity,
                  decoration: boxDecoration,
                  child: selectorContent,
                ),
              ),
            ),
    );
  }

  Widget _buildSelectorIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(icon, color: Colors.white.withOpacity(0.6), size: 26),
      ),
    );
  }

  Widget _buildSelectorPackIcon(CustomEmojiPack pack) {
    return GestureDetector(
      onTap: () {
        HapticUtils.tap();
        _scrollToSection(_sectionKeys[pack.id]);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Center(
          child: EmojiUtils.appleEmoji(pack.emojis.first.emoji, size: 20),
        ),
      ),
    );
  }

  void _scrollToSection(GlobalKey? key) {
    // Total height of the floating clouds (Selector + Search)
    const double topOffset = _kEmojiSelectorHeight + _kSearchHeight;

    if (key == _sectionKeys['recent']) {
      _gridScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (key == null) return;

    final context = key.currentContext;
    if (context != null) {
      _animateToKey(key, topOffset + 8.0); // +8 for the extra padding we have in the list
    } else {
      // Fallback if context is not available (off-screen sliver)
      double offset = topOffset + 8.0; // Starting point (top padding)
      
      if (_displayedRecentEmojis.isNotEmpty) {
        final cols = _lastEmojiColumns > 0 ? _lastEmojiColumns : 8;
        final rows = (_displayedRecentEmojis.length / cols).ceil();
        // Approx height of Recent section: header(40) + grid(rows * 42 approx)
        offset += 40.0 + rows * 42.0;
      }

      if (key == _sectionKeys['standard']) {
        _gridScrollController.animateTo(
          offset - topOffset - 8.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // Custom packs are now at the end. Since the standard list is huge, 
        // we'll jump to the bottom for the fallback.
        _gridScrollController.animateTo(
          _gridScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _animateToKey(GlobalKey key, double topOffset) {
    final context = key.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Find the scrollable viewport (the CustomScrollView)
    final scrollable = Scrollable.of(context);
    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    if (viewport == null) return;

    // Get position of the item relative to the viewport
    final position = renderBox.localToGlobal(Offset.zero, ancestor: viewport);
    
    // We want position.dy to be topOffset. 
    // Currently position.dy is relative to the viewport top.
    // So we need to shift the scroll by (position.dy - topOffset).
    final targetOffset = _gridScrollController.offset + position.dy - topOffset;

    _gridScrollController.animateTo(
      targetOffset.clamp(0, _gridScrollController.position.maxScrollExtent),
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
    final effectiveCount = math.max(_loadedGifsCount, gifColumns * 4);
    return GridView.builder(
      controller: _gifScrollController,
      padding: const EdgeInsets.fromLTRB(8, _kSearchHeight + 12, 8, 80),
      physics: const ClampingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gifColumns,
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: effectiveCount + (_isLoadingMoreGifs ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= effectiveCount) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text('GIF $index', style: const TextStyle(color: Colors.white24))),
        );
      },
    );
  }

  Widget _buildStickerGrid(int stickerColumns) {
    final effectiveCount = math.max(_loadedStickersCount, stickerColumns * 5);
    return GridView.builder(
      controller: _stickerScrollController,
      padding: const EdgeInsets.fromLTRB(8, _kSearchHeight + 12, 8, 80),
      physics: const ClampingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: stickerColumns,
        childAspectRatio: 1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: effectiveCount + (_isLoadingMoreStickers ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= effectiveCount) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(child: Icon(Icons.style_outlined, color: Colors.white24, size: 32)),
        );
      },
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
              // Centered Tabs
              SizedBox(
                width: 220,
                child: _buildClassicNav(isDark, theme),
              ),
              // Backspace anchored to the right side
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
                  ? const Color(0xFF2C2C2E).withOpacity(0.7)
                  : Colors.white.withOpacity(0.7),
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
          // Sliding indicator matching ClassicBottomBar
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
          // Tabs
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
                    ? const Color(0xFF2C2C2E).withOpacity(0.7)
                    : Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
        child: Icon(
          Icons.backspace_outlined,
          color: isDark ? Colors.white70 : Colors.black87,
          size: 20,
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
        touch: const LiquidGlassTouch.flexing(LiquidGlassFlex(
          stretch: 4,
          squeeze: 0.8,
          lean: 0.2,
        )),
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
    _recentEmojis.removeWhere((e) => e.emoji == emoji.emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 45) {
      _recentEmojis = _recentEmojis.sublist(0, 45);
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
  const _EmojiScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  _EmojiScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _EmojiScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Snap only if the scroll would naturally come to rest inside the header collapse zone (0 to 48px)
    const double snapTarget = 48.0;
    final Simulation? parentSim = super.createBallisticSimulation(position, velocity);
    final double naturalEnd =
        parentSim != null ? parentSim.x(double.infinity) : position.pixels;

    if (naturalEnd >= snapTarget) {
      return parentSim;
    }

    if (naturalEnd > 0.0 && naturalEnd < snapTarget) {
      double target = naturalEnd > snapTarget / 2 ? snapTarget : 0.0;

      // If there's clear velocity, follow the direction regardless of half-way point
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
