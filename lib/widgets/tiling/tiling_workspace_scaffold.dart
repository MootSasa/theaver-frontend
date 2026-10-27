import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/chat/channel_screen.dart';
import '../../screens/chat/group_chat_screen.dart';
import '../../screens/chat/private_chat_screen.dart';
import '../../screens/chat/system_notifications_screen.dart';
import '../../screens/chat/user_profile_screen.dart';
import '../../screens/main/main_screen.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/swipe_back_route.dart';
import '../chat/chat_scaffold.dart';
import 'static_tile_cache_boundary.dart';
import 'tile_drag_preview_overlay.dart';
import 'tile_resize_divider.dart';
import 'tile_viewport_scope.dart';

/// Корневой виджет адаптивного тайлингового (многооконного) рабочего пространства.
///
/// - На экранах `>= 640px` отображает слева закреплённый тайл [MainScreen] (`320..480px`),
///   а справа — рабочую область чатов [ChatWorkspaceArea] (от 0 до 2 тайлов чатов
///   в горизонтальном или вертикальном сплите).
/// - На экранах `< 640px` плавно переходит в однооконный режим, сохраняя состояние
///   открытых чатов и вложенных `Navigator` с помощью стабильных `GlobalKey`.
class TilingWorkspaceScaffold extends StatefulWidget {
  const TilingWorkspaceScaffold({super.key});

  @override
  State<TilingWorkspaceScaffold> createState() =>
      _TilingWorkspaceScaffoldState();
}

class _TilingWorkspaceScaffoldState extends State<TilingWorkspaceScaffold>
    with SingleTickerProviderStateMixin {
  final TilingLayoutController _controller = TilingLayoutController.instance;
  final GlobalKey _rightWorkspaceKey = GlobalKey(debugLabel: 'RightChatWorkspace');
  final GlobalKey _leftTileSubtreeKey = GlobalKey(debugLabel: 'LeftMainTileSubtree');
  final Map<String, GlobalKey> _chatTileSubtreeKeys = {};
  late final HeroController _leftHeroController =
      MaterialApp.createMaterialHeroController();
  final Map<String, HeroController> _chatTileHeroControllers = {};

  late final AnimationController _singlePaneChatController;
  bool _wasShowingSinglePaneChat = false;
  bool _isSinglePaneInteractiveDrag = false;
  bool _isClosingSinglePaneAnimated = false;

  Offset? _lastPointerPos;
  int? _lastPointerTimeMs;
  Size? _lastReportedWindowSize;
  bool _windowMetricsUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _wasShowingSinglePaneChat = _controller.singlePaneShowingChat;
    _singlePaneChatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 250),
      value: _wasShowingSinglePaneChat ? 1.0 : 0.0,
    );
    _controller.rightWorkspaceRectResolver = _getRightWorkspaceGlobalRect;
    _controller.onRequestAnimatedSinglePaneClose = _animateCloseSinglePaneChat;
    _controller.setWorkspaceMounted(true);
    _controller.addListener(_onControllerChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _controller.removeListener(_onControllerChanged);
    if (_controller.rightWorkspaceRectResolver == _getRightWorkspaceGlobalRect) {
      _controller.rightWorkspaceRectResolver = null;
    }
    if (_controller.onRequestAnimatedSinglePaneClose ==
        _animateCloseSinglePaneChat) {
      _controller.onRequestAnimatedSinglePaneClose = null;
    }
    _controller.setWorkspaceMounted(false);
    _singlePaneChatController.dispose();
    _leftHeroController.dispose();
    for (final ctrl in _chatTileHeroControllers.values) {
      ctrl.dispose();
    }
    _chatTileHeroControllers.clear();
    super.dispose();
  }

  bool _isCurrentlySinglePaneMode() {
    final double w =
        _lastReportedWindowSize?.width ?? _controller.windowSize.width;
    return w < TilingLayoutController.kTwoColumnBreakpoint &&
        _controller.chatTiles.length < 2;
  }

  Future<void> _animateCloseSinglePaneChat(String tileId) async {
    if (!mounted) return;
    if (!_isCurrentlySinglePaneMode()) return;
    if (_singlePaneChatController.value <= 0.0) return;
    _isClosingSinglePaneAnimated = true;
    _isSinglePaneInteractiveDrag = false;
    try {
      await _singlePaneChatController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isClosingSinglePaneAnimated = false;
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Очищаем ключи и HeroController'ы удалённых тайлов
    final currentIds = _controller.chatTiles.map((t) => t.tileId).toSet();
    _chatTileSubtreeKeys.removeWhere((id, _) => !currentIds.contains(id));
    final removedHeroIds = _chatTileHeroControllers.keys
        .where((id) => !currentIds.contains(id))
        .toList();
    for (final id in removedHeroIds) {
      _chatTileHeroControllers.remove(id)?.dispose();
    }

    final bool nowShowingChat =
        _controller.singlePaneShowingChat && _controller.focusedChatTile != null;
    if (nowShowingChat && !_wasShowingSinglePaneChat) {
      _isClosingSinglePaneAnimated = false;
      _isSinglePaneInteractiveDrag = false;
      if (_isCurrentlySinglePaneMode()) {
        _singlePaneChatController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _singlePaneChatController.value = 1.0;
      }
    } else if (!nowShowingChat && _wasShowingSinglePaneChat) {
      _isSinglePaneInteractiveDrag = false;
      if (!_isClosingSinglePaneAnimated) {
        _singlePaneChatController.value = 0.0;
      }
    }
    _wasShowingSinglePaneChat = nowShowingChat;

    setState(() {});
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.browserBack ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      final rootNav = Navigator.maybeOf(context, rootNavigator: true);
      _controller.handleBackAction(rootNavigator: rootNav);
      return true;
    }
    return false;
  }

  Rect? _getRightWorkspaceGlobalRect() {
    final renderBox =
        _rightWorkspaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final topLeft = renderBox.localToGlobal(Offset.zero);
    return topLeft & renderBox.size;
  }

  void _onGlobalPointerMove(PointerMoveEvent event) {
    if (!_controller.isDragging) return;
    final now = event.timeStamp.inMilliseconds;
    Offset velocity = Offset.zero;
    if (_lastPointerPos != null && _lastPointerTimeMs != null) {
      final dt = math.max(1, now - _lastPointerTimeMs!);
      velocity = (event.position - _lastPointerPos!) * (1000.0 / dt);
    }
    _lastPointerPos = event.position;
    _lastPointerTimeMs = now;

    _controller.updateDraggingChat(
      event.position,
      velocity: velocity,
      rightWorkspaceGlobalRect: _getRightWorkspaceGlobalRect(),
    );
  }

  void _onGlobalPointerUp(PointerUpEvent event) {
    if (!_controller.isDragging) return;
    _lastPointerPos = null;
    _lastPointerTimeMs = null;
    _controller.endDraggingChat();
  }

  void _onGlobalPointerCancel(PointerCancelEvent event) {
    if (!_controller.isDragging) return;
    _lastPointerPos = null;
    _lastPointerTimeMs = null;
    _controller.cancelDraggingChat();
  }

  Route<dynamic>? _onGenerateSubRoute(RouteSettings settings) {
    if (settings.name == '/profile') {
      final args = settings.arguments as Map<String, dynamic>? ?? {};
      final userId = args['userId']?.toString() ?? '';
      final name = args['name']?.toString();
      final avatarUrl = args['avatarUrl']?.toString();
      return SwipeBackPageRoute(
        builder: (_) => UserProfileScreen(
          userId: userId,
          initialName: name,
          initialAvatarUrl: avatarUrl,
        ),
        settings: settings,
      );
    }
    return null;
  }

  bool get _shouldCacheStationaryTiles {
    if (_controller.isDragging) return false;
    final double w =
        _lastReportedWindowSize?.width ?? _controller.windowSize.width;
    return w >= TilingLayoutController.kTwoColumnBreakpoint ||
        _controller.chatTiles.length >= 2;
  }

  Widget _buildLeftMainTile() {
    return KeyedSubtree(
      key: _leftTileSubtreeKey,
      child: StaticTileCacheBoundary(
        enabled: _shouldCacheStationaryTiles,
        child: TileViewportScope(
          tileId: TilingLayoutController.kLeftTileId,
          isChatTile: false,
          child: HeroControllerScope(
            controller: _leftHeroController,
            child: Navigator(
              key: _controller.leftTileNavigatorKey,
              onGenerateRoute: (settings) {
                final sub = _onGenerateSubRoute(settings);
                if (sub != null) return sub;
                return MaterialPageRoute(
                  builder: (_) => const MainScreen(),
                  settings: settings,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTileWidget(
    ChatTileDescriptor descriptor, {
    bool hasTopNeighbor = false,
    bool hasBottomNeighbor = false,
  }) {
    final subtreeKey = _chatTileSubtreeKeys.putIfAbsent(
      descriptor.tileId,
      () => GlobalKey(debugLabel: 'ChatTileSubtree_${descriptor.tileId}'),
    );
    final heroController = _chatTileHeroControllers.putIfAbsent(
      descriptor.tileId,
      () => MaterialApp.createMaterialHeroController(),
    );

    return KeyedSubtree(
      key: subtreeKey,
      child: StaticTileCacheBoundary(
        enabled: _shouldCacheStationaryTiles,
        child: TileViewportScope(
          tileId: descriptor.tileId,
          isChatTile: true,
          hasTopNeighbor: hasTopNeighbor,
          hasBottomNeighbor: hasBottomNeighbor,
          child: HeroControllerScope(
            controller: heroController,
            child: Navigator(
              key: descriptor.navigatorKey,
              onGenerateRoute: (settings) {
                final sub = _onGenerateSubRoute(settings);
                if (sub != null) return sub;
                final route = MaterialPageRoute(
                  builder: (_) => KeyedSubtree(
                    key: descriptor.contentKey,
                    child: _buildChatRootScreen(descriptor),
                  ),
                  settings: settings,
                );
                descriptor.rootRoute = route;
                return route;
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatRootScreen(ChatTileDescriptor descriptor) {
    switch (descriptor.chatType) {
      case 'group':
        return GroupChatScreen(
          chatId: descriptor.chatId,
          groupName: descriptor.chatName,
          groupAvatar: descriptor.avatarUrl,
          initialMessageId: descriptor.initialMessageId,
        );
      case 'channel':
        return ChannelScreen(
          channelId: descriptor.chatId,
          channelName: descriptor.chatName,
          channelAvatar: descriptor.avatarUrl,
          highlightMessageId: descriptor.initialMessageId,
        );
      case 'system':
        return SystemNotificationsScreen(
          chatId: descriptor.chatId,
          chatName: descriptor.chatName,
        );
      case 'saved':
      case 'private':
      default:
        return PrivateChatScreen(
          chatId: descriptor.chatId,
          otherUserName: descriptor.chatName,
          otherUserAvatar: descriptor.avatarUrl,
          otherUserOnline: descriptor.isOnline,
          otherUserLastSeen: descriptor.lastSeen,
          otherUserId: descriptor.otherUserId,
          initialMessageId: descriptor.initialMessageId,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          final rootNav = Navigator.maybeOf(context, rootNavigator: true);
          _controller.handleBackAction(rootNavigator: rootNav);
        }
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: _onGlobalPointerMove,
        onPointerUp: _onGlobalPointerUp,
        onPointerCancel: _onGlobalPointerCancel,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowWidth = constraints.maxWidth;
            final windowHeight = constraints.maxHeight;
            final currentSize = Size(windowWidth, windowHeight);

            if (_lastReportedWindowSize != currentSize) {
              _lastReportedWindowSize = currentSize;
              if (!_windowMetricsUpdateScheduled) {
                _windowMetricsUpdateScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _windowMetricsUpdateScheduled = false;
                  if (mounted && _lastReportedWindowSize != null) {
                    _controller.updateWindowMetrics(_lastReportedWindowSize!);
                  }
                });
              }
            }

            final bool isSinglePaneMode =
                windowWidth < TilingLayoutController.kTwoColumnBreakpoint &&
                _controller.chatTiles.length < 2;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (isSinglePaneMode)
                  _buildSinglePaneLayout(currentSize)
                else
                  _buildMultiPaneLayout(windowWidth, windowHeight),

                // Слой плавающего заблюренного мини-окна при перетаскивании
                if (_controller.activeDrag != null)
                  TileDragPreviewOverlay(
                    payload: _controller.activeDrag!,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _canSinglePaneSwipeBack(ChatTileDescriptor activeChat) {
    if (!mounted) return false;
    if (!_isCurrentlySinglePaneMode()) return false;
    if (!_controller.singlePaneShowingChat) return false;
    if (_isClosingSinglePaneAnimated) return false;
    if (_singlePaneChatController.isAnimating) return false;
    if (_singlePaneChatController.value < 0.99) return false;

    final rootModal = ModalRoute.of(context);
    if (rootModal != null && !rootModal.isCurrent) return false;

    final chatNav = activeChat.navigatorKey.currentState;
    if (chatNav != null && chatNav.canPop()) return false;
    if (activeChat.rootRoute != null && !activeChat.rootRoute!.isCurrent) {
      return false;
    }

    return true;
  }

  /// Однооконный режим для узкого окна (`< 640px` при `<= 1` открытом чате):
  /// Показывает либо список чатов (`MainScreen`), либо открытый активный чат
  /// с плавной анимацией и интерактивным 1:1 жестом свайпа «Назад» (с параллаксом и пружинной физикой).
  Widget _buildSinglePaneLayout(Size viewportSize) {
    final activeChat = _controller.focusedChatTile;
    final showChat = _controller.singlePaneShowingChat && activeChat != null;
    final leftMainTile = _buildLeftMainTile();
    final chatTileWidget =
        activeChat != null ? _buildChatTileWidget(activeChat) : null;

    return AnimatedBuilder(
      animation: _singlePaneChatController,
      builder: (context, _) {
        final double t = _singlePaneChatController.value.clamp(0.0, 1.0);
        final bool hideMain =
            showChat && t >= 1.0 && !_isSinglePaneInteractiveDrag;
        final bool hideChat = !showChat && t <= 0.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: hideMain,
              child: FractionalTranslation(
                translation: Offset(-0.3 * t, 0.0),
                child: leftMainTile,
              ),
            ),
            if (t > 0.0 && !hideMain)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.4 * t),
                ),
              ),
            if (activeChat != null && chatTileWidget != null)
              Offstage(
                offstage: hideChat,
                child: FractionalTranslation(
                  translation: Offset(1.0 - t, 0.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: t > 0.0 && t < 1.0
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15 * t),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(-5, 0),
                              ),
                            ]
                          : const [],
                    ),
                    child: InteractiveSwipeBackGestureDetector(
                      animationController: _singlePaneChatController,
                      viewportSizeOverride: viewportSize,
                      canSwipeBack: () => _canSinglePaneSwipeBack(activeChat),
                      isPopBlocked: () =>
                          activeChat.rootRoute?.popDisposition ==
                          RoutePopDisposition.doNotPop,
                      onDragStart: () {
                        if (!_isSinglePaneInteractiveDrag) {
                          setState(() => _isSinglePaneInteractiveDrag = true);
                        }
                      },
                      onRestored: () {
                        if (_isSinglePaneInteractiveDrag) {
                          setState(() => _isSinglePaneInteractiveDrag = false);
                        }
                      },
                      onDismissed: () {
                        _isSinglePaneInteractiveDrag = false;
                        _controller.closeChatTile(activeChat.tileId);
                      },
                      child: chatTileWidget,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Многооконный тайлинговый режим (`>= 640px`):
  /// `[MainScreen (320..480px) | Divider | ChatWorkspaceArea]`.
  Widget _buildMultiPaneLayout(double totalWidth, double totalHeight) {
    const seamThickness = TileResizeDivider.kSeamThickness;
    const overlaySpan = TileResizeDivider.kOverlaySpan;

    final minRightRequired = (_controller.chatTiles.length == 2 &&
            _controller.effectiveSplitAxis == Axis.horizontal)
        ? TilingLayoutController.kMinTileWidth * 2
        : TilingLayoutController.kMinTileWidth;

    final maxAllowedLeft = math.min(
      TilingLayoutController.kMaxLeftTileWidth,
      math.max(
        TilingLayoutController.kMinTileWidth,
        totalWidth - minRightRequired - seamThickness,
      ),
    );
    final leftWidth = _controller.leftTileWidth.clamp(
      TilingLayoutController.kMinTileWidth,
      maxAllowedLeft,
    );
    final rightLeft = leftWidth + seamThickness;
    final rightWidth = math.max(0.0, totalWidth - rightLeft);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: leftWidth,
          height: totalHeight,
          child: _buildLeftMainTile(),
        ),
        Positioned(
          left: rightLeft,
          top: 0,
          width: rightWidth,
          height: totalHeight,
          child: Container(
            key: _rightWorkspaceKey,
            child: _buildRightChatWorkspace(),
          ),
        ),
        Positioned(
          left: leftWidth + (seamThickness - overlaySpan) * 0.5,
          top: 0,
          width: overlaySpan,
          height: totalHeight,
          child: TileResizeDivider(
            lineAxis: Axis.vertical,
            onDelta: (dx) => _controller.updateLeftTileWidth(dx),
            onDoubleTap: () {
              final diff = TilingLayoutController.kDefaultLeftTileWidth -
                  _controller.leftTileWidth;
              _controller.updateLeftTileWidth(diff);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRightChatWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaW = constraints.maxWidth;
        final areaH = constraints.maxHeight;
        final tiles = _controller.chatTiles;
        final drag = _controller.activeDrag;
        final dropSlot = _controller.hoveredDropSlot;

        // 1. Ни один чат не открыт -> обои темы + «Выберите чат»
        if (tiles.isEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildEmptyChatPlaceholder(context),
              if (drag != null && dropSlot != null)
                Positioned.fill(
                  child: GlassDropPlaceholder(
                    slot: TilingDropSlot.replace,
                    chatName: drag.chatName,
                  ),
                ),
            ],
          );
        }

        // 2. Режим живого сдвига соседних тайлов во время перетаскивания (Live Reflow)
        final bool isDraggingExistingTile =
            drag != null && drag.sourceTileId != null;

        // Если открыт 1 тайл и пользователь перетаскивает второй чат из списка
        if (tiles.length == 1 && !isDraggingExistingTile && drag != null && dropSlot != null) {
          return _buildLiveReflowWithOneRemainingTile(
            remainingTile: tiles.first,
            drag: drag,
            dropSlot: dropSlot,
            areaW: areaW,
            areaH: areaH,
          );
        }

        // Если открыто 2 тайла и пользователь перетаскивает один из них за шапку
        if (tiles.length == 2 && isDraggingExistingTile && dropSlot != null) {
          final remaining = tiles.firstWhere(
            (t) => t.tileId != drag.sourceTileId,
            orElse: () => tiles.first,
          );
          return _buildLiveReflowWithOneRemainingTile(
            remainingTile: remaining,
            drag: drag,
            dropSlot: dropSlot,
            areaW: areaW,
            areaH: areaH,
          );
        }

        // 3. Стандартное отображение 1 открытого тайла чата
        if (tiles.length == 1) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: _buildChatTileWidget(tiles.first),
              ),
              if (drag != null && dropSlot == TilingDropSlot.replace)
                Positioned.fill(
                  child: GlassDropPlaceholder(
                    slot: TilingDropSlot.replace,
                    chatName: drag.chatName,
                  ),
                ),
            ],
          );
        }

        // 4. Стандартное отображение 2 открытых тайлов чатов (Горизонтально или Вертикально)
        final axis = _controller.effectiveSplitAxis;
        const seamThickness = TileResizeDivider.kSeamThickness;
        const overlaySpan = TileResizeDivider.kOverlaySpan;

        if (axis == Axis.horizontal) {
          final usableW = math.max(0.0, areaW - seamThickness);
          final minTileW = math.min(TilingLayoutController.kMinTileWidth, usableW * 0.5);
          final maxTileW = math.max(minTileW, math.min(TilingLayoutController.kMaxChatTileWidth, usableW - minTileW));
          final firstW = (usableW * _controller.chatSplitRatio).clamp(minTileW, maxTileW);
          final secondW = math.max(0.0, usableW - firstW);
          final bool showFullReplaceOverlay = drag != null &&
              dropSlot == TilingDropSlot.replace &&
              _controller.hoveredTargetTileId == null;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                key: ValueKey('tile_pos_${tiles[0].tileId}'),
                left: 0,
                top: 0,
                width: firstW,
                height: areaH,
                child: _buildChatTileWithDropOverlay(tiles[0], drag, dropSlot),
              ),
              Positioned(
                key: ValueKey('tile_pos_${tiles[1].tileId}'),
                left: firstW + seamThickness,
                top: 0,
                width: secondW,
                height: areaH,
                child: _buildChatTileWithDropOverlay(tiles[1], drag, dropSlot),
              ),
              Positioned(
                left: firstW + (seamThickness - overlaySpan) * 0.5,
                top: 0,
                width: overlaySpan,
                height: areaH,
                child: TileResizeDivider(
                  lineAxis: Axis.vertical,
                  onDelta: (dx) => _controller.updateChatSplitRatio(dx, usableW),
                  onDoubleTap: () {
                    HapticFeedback.selectionClick();
                    _controller.swapChatTiles();
                  },
                ),
              ),
              if (showFullReplaceOverlay)
                Positioned.fill(
                  child: GlassDropPlaceholder(
                    slot: TilingDropSlot.replace,
                    chatName: drag.chatName,
                  ),
                ),
            ],
          );
        } else {
          // Вертикальный сплит: [Chat 1 сверху / Chat 2 снизу]
          final usableH = math.max(0.0, areaH - seamThickness);
          final minTileH = math.min(
            TilingLayoutController.kMinVerticalSplitTileHeight,
            usableH * 0.5,
          );
          final maxTileH = math.max(minTileH, usableH - minTileH);
          final firstH = (usableH * _controller.chatSplitRatio).clamp(minTileH, maxTileH);
          final secondH = math.max(0.0, usableH - firstH);
          final bool showFullReplaceOverlay = drag != null &&
              dropSlot == TilingDropSlot.replace &&
              _controller.hoveredTargetTileId == null;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                key: ValueKey('tile_pos_${tiles[0].tileId}'),
                left: 0,
                top: 0,
                width: areaW,
                height: firstH,
                child: _buildChatTileWithDropOverlay(
                  tiles[0],
                  drag,
                  dropSlot,
                  hasBottomNeighbor: true,
                ),
              ),
              Positioned(
                key: ValueKey('tile_pos_${tiles[1].tileId}'),
                left: 0,
                top: firstH + seamThickness,
                width: areaW,
                height: secondH,
                child: _buildChatTileWithDropOverlay(
                  tiles[1],
                  drag,
                  dropSlot,
                  hasTopNeighbor: true,
                ),
              ),
              Positioned(
                left: 0,
                top: firstH + (seamThickness - overlaySpan) * 0.5,
                width: areaW,
                height: overlaySpan,
                child: TileResizeDivider(
                  lineAxis: Axis.horizontal,
                  onDelta: (dy) => _controller.updateChatSplitRatio(dy, usableH),
                  onDoubleTap: () {
                    HapticFeedback.selectionClick();
                    _controller.swapChatTiles();
                  },
                ),
              ),
              if (showFullReplaceOverlay)
                Positioned.fill(
                  child: GlassDropPlaceholder(
                    slot: TilingDropSlot.replace,
                    chatName: drag.chatName,
                  ),
                ),
            ],
          );
        }
      },
    );
  }

  /// Отрисовывает реальный сдвиг оставшегося тайла (`AnimatedPositioned`), освобождающего
  /// половину пространства под перетаскиваемое окно.
  Widget _buildLiveReflowWithOneRemainingTile({
    required ChatTileDescriptor remainingTile,
    required DraggingChatPayload drag,
    required TilingDropSlot dropSlot,
    required double areaW,
    required double areaH,
  }) {
    Rect remainingRect;
    Rect placeholderRect;

    switch (dropSlot) {
      case TilingDropSlot.left:
        placeholderRect = Rect.fromLTWH(0, 0, areaW * 0.5, areaH);
        remainingRect = Rect.fromLTWH(areaW * 0.5, 0, areaW * 0.5, areaH);
        break;
      case TilingDropSlot.right:
        remainingRect = Rect.fromLTWH(0, 0, areaW * 0.5, areaH);
        placeholderRect = Rect.fromLTWH(areaW * 0.5, 0, areaW * 0.5, areaH);
        break;
      case TilingDropSlot.top:
        placeholderRect = Rect.fromLTWH(0, 0, areaW, areaH * 0.5);
        remainingRect = Rect.fromLTWH(0, areaH * 0.5, areaW, areaH * 0.5);
        break;
      case TilingDropSlot.bottom:
        remainingRect = Rect.fromLTWH(0, 0, areaW, areaH * 0.5);
        placeholderRect = Rect.fromLTWH(0, areaH * 0.5, areaW, areaH * 0.5);
        break;
      case TilingDropSlot.replace:
        remainingRect = Rect.fromLTWH(0, 0, areaW, areaH);
        placeholderRect = Rect.fromLTWH(0, 0, areaW, areaH);
        break;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: remainingRect.left,
          top: remainingRect.top,
          width: remainingRect.width,
          height: remainingRect.height,
          child: _buildChatTileWidget(
            remainingTile,
            hasTopNeighbor: dropSlot == TilingDropSlot.top,
            hasBottomNeighbor: dropSlot == TilingDropSlot.bottom,
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: placeholderRect.left,
          top: placeholderRect.top,
          width: placeholderRect.width,
          height: placeholderRect.height,
          child: GlassDropPlaceholder(
            slot: dropSlot,
            chatName: drag.chatName,
          ),
        ),
      ],
    );
  }

  Widget _buildChatTileWithDropOverlay(
    ChatTileDescriptor tile,
    DraggingChatPayload? drag,
    TilingDropSlot? dropSlot, {
    bool hasTopNeighbor = false,
    bool hasBottomNeighbor = false,
  }) {
    final bool showReplaceOverlay = drag != null &&
        dropSlot != null &&
        _controller.hoveredTargetTileId == tile.tileId &&
        drag.sourceTileId != tile.tileId;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildChatTileWidget(
          tile,
          hasTopNeighbor: hasTopNeighbor,
          hasBottomNeighbor: hasBottomNeighbor,
        ),
        if (showReplaceOverlay)
          Positioned.fill(
            child: GlassDropPlaceholder(
              slot: dropSlot,
              chatName: drag.chatName,
            ),
          ),
      ],
    );
  }

  /// Пустое состояние правой области (когда ни один чат не открыт):
  /// Показывает фон выбранной в настройках темы и подсказку «Выберите чат».
  Widget _buildEmptyChatPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final isGlass = glassProvider?.enabled ?? false;
    final l10n = AppLocalizations.of(context);
    final label = l10n?.translate('select_chat_prompt') != null &&
            l10n?.translate('select_chat_prompt') != 'select_chat_prompt'
        ? l10n!.translate('select_chat_prompt')
        : 'Выберите чат';

    final badgeContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 18,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );

    return ChatScaffold(
      enableStatusBarBlur: false,
      enableBottomScrollEdge: false,
      body: Center(
        child: isGlass && glassProvider != null
            ? IntrinsicWidth(
                child: IntrinsicHeight(
                  child: LiquidGlassLens(
                    style: glassProvider.createStyle(
                      context: context,
                      cornerRadius: 24,
                    ),
                    child: badgeContent,
                  ),
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.42)
                      : Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: badgeContent,
              ),
      ),
    );
  }
}
