import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../utils/blur_utils.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../tiling/tile_viewport_scope.dart';
import '../user/avatar_with_status.dart';
import 'animated_ellipsis_text.dart';

// --- НАСТРОЙКИ СТИЛЯ ПАНЕЛИ ---
/// Высота панели без учета отступов и статус-бара (Apple HIG standard).
const double _kAppBarHeight = 44.0;
/// Радиус скругления капсул панели (44 / 2 = 22) — идеальный стадион / круг.
const double _kAppBarBorderRadius = 22.0;
/// Внешний горизонтальный отступ панели от краев экрана.
const double _kAppBarHorizontalPadding = 8.0;
/// Внешний вертикальный отступ панели от статус-бара.
const double _kAppBarVerticalPadding = 8.0;
/// Расстояние между частями панели.
const double _kPillSpacing = 8.0;

/// Ширина левой плашки (кнопка "Назад").
const double _kBackPillWidth = 44.0;

/// Ширина правой плашки в канале (только три точки).
const double _kRightPillChannelWidth = 44.0;
/// Ширина правой плашки в чате (звонок + три точки, сближены на пару пикселей).
const double _kRightPillChatWidth = 80.0;

/// Полная высота плавающей панели со стандартным верхним отступом: 44.0 + 8.0 = 52.0.
const double kFloatingAppBarTotalHeight = _kAppBarHeight + _kAppBarVerticalPadding;

/// Ширина выпадающего морф-меню действий.
const double _kMenuWidth = 250.0;
/// Высота выпадающего морф-меню действий (5 пунктов по 42pt + padding 24pt = 234pt).
const double _kMenuHeight = 234.0;

/// Кинематика морфинга меню действий чата.
/// Использует plain-режим (единая линза без разделения на два блоба, исключающая любые прыжки).
const LiquidGlassMorphMotion _kChatMenuMotion = LiquidGlassMorphMotion.fluid;

/// Размер шрифта имени в заголовке.
const double _kTitleFontSize = 16.0;
/// Размер шрифта статуса (в сети / был недавно).
const double _kStatusFontSize = 12.5;

/// Радиус аватарки в центральной плашке (диаметр 40px).
const double _kCenterAvatarRadius = 20.0;
/// Размер иконок действий (звонок, меню).
const double _kActionIconSize = 20.0;

// ------------------------------

/// Floating AppBar split into 3 distinct glass/matte pills:
/// 1. Left circular pill: Back button (44x44).
/// 2. Center capsule pill: Chat name & status text.
/// 3. Right capsule pill: Calls & avatar, which fluidly morphs into the actions menu.
class FloatingGlassAppBar extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? statusText;
  final Color? statusColor;
  final bool? isConnected;
  final Widget? titleWidget;
  final Widget? avatarWidget;
  final VoidCallback onBack;
  final VoidCallback onTitleTap;
  final VoidCallback? onAvatarTap;
  final bool isChannel;
  final bool isMuted;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onSearch;
  final VoidCallback? onToggleMute;
  final VoidCallback? onClearHistory;
  final VoidCallback? onReport;
  final VoidCallback? onViewProfile;
  final WidgetBuilder? profileScreenBuilder;
  final String? heroTag;
  final bool isSelectionMode;
  final int selectedCount;
  final VoidCallback? onCancelSelection;
  final VoidCallback? onCopySelected;
  final VoidCallback? onForwardSelected;
  final VoidCallback? onDeleteSelected;

  const FloatingGlassAppBar({
    Key? key,
    this.avatarUrl,
    required this.name,
    required this.isOnline,
    this.lastSeen,
    this.statusText,
    this.statusColor,
    this.isConnected,
    this.titleWidget,
    this.avatarWidget,
    required this.onBack,
    required this.onTitleTap,
    this.onAvatarTap,
    this.isChannel = false,
    this.isMuted = false,
    this.onVoiceCall,
    this.onVideoCall,
    this.onSearch,
    this.onToggleMute,
    this.onClearHistory,
    this.onReport,
    this.onViewProfile,
    this.profileScreenBuilder,
    this.heroTag,
    this.isSelectionMode = false,
    this.selectedCount = 0,
    this.onCancelSelection,
    this.onCopySelected,
    this.onForwardSelected,
    this.onDeleteSelected,
  }) : super(key: key);

  @override
  State<FloatingGlassAppBar> createState() => _FloatingGlassAppBarState();
}

class _FloatingGlassAppBarState extends State<FloatingGlassAppBar> {
  bool _isMenuOpen = false;
  String? _registeredTileId;

  // Состояние перетаскивания тайла чата за центральную плашку
  Offset? _dragStartGlobal;
  bool _isDraggingTile = false;

  @visibleForTesting
  bool get isMenuOpen => _isMenuOpen;
  @visibleForTesting
  bool get isMorphing => false;
  @visibleForTesting
  bool get isMenuWide => _isMenuOpen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tileId = TileViewportScope.maybeTileIdOf(context);
    if (_registeredTileId != tileId) {
      if (_registeredTileId != null) {
        TilingLayoutController.instance.unregisterTileBackHandler(
          _registeredTileId!,
          _handleBackForTile,
        );
      }
      _registeredTileId = tileId;
      if (_registeredTileId != null) {
        TilingLayoutController.instance.registerTileBackHandler(
          _registeredTileId!,
          _handleBackForTile,
        );
      }
    }
  }

  @override
  void dispose() {
    if (_registeredTileId != null) {
      TilingLayoutController.instance.unregisterTileBackHandler(
        _registeredTileId!,
        _handleBackForTile,
      );
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FloatingGlassAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelectionMode && _isMenuOpen) {
      _isMenuOpen = false;
    }
  }

  bool _handleBackForTile() {
    if (widget.isSelectionMode) {
      widget.onCancelSelection?.call();
      return true;
    }
    if (_isMenuOpen) {
      _closeMenu();
      return true;
    }
    return false;
  }

  void _openMenu() {
    if (_isMenuOpen || widget.isSelectionMode) return;
    HapticUtils.tap();
    setState(() {
      _isMenuOpen = true;
    });
  }

  void _closeMenu() {
    if (!_isMenuOpen) return;
    setState(() {
      _isMenuOpen = false;
    });
  }

  void _toggleMenu() {
    if (_isMenuOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  bool _canDragChatTile() {
    final controller = TilingLayoutController.instance;
    if (!controller.isWorkspaceMounted) return false;
    if (controller.windowSize.width < TilingLayoutController.kTwoColumnBreakpoint) {
      return false;
    }
    final tileId = _registeredTileId ?? TileViewportScope.maybeTileIdOf(context);
    if (tileId == null || tileId == TilingLayoutController.kLeftTileId) {
      return false;
    }
    // Dragging an already-open tile makes sense when 2 chat tiles are open (to swap/re-orient)
    return controller.chatTiles.length >= 2 &&
        controller.chatTiles.any((t) => t.tileId == tileId);
  }

  void _onCenterPillPanStart(DragStartDetails details) {
    if (!_canDragChatTile()) {
      _dragStartGlobal = null;
      _isDraggingTile = false;
      return;
    }
    _dragStartGlobal = details.globalPosition;
    _isDraggingTile = false;
  }

  void _onCenterPillPanUpdate(DragUpdateDetails details) {
    if (_dragStartGlobal == null) return;
    final controller = TilingLayoutController.instance;

    if (!_isDraggingTile) {
      final delta = (details.globalPosition - _dragStartGlobal!).distance;
      if (delta < 8.0) return;

      final tileId = _registeredTileId ?? TileViewportScope.maybeTileIdOf(context);
      if (tileId == null) return;

      final idx = controller.chatTiles.indexWhere((t) => t.tileId == tileId);
      if (idx == -1) return;
      final descriptor = controller.chatTiles[idx];

      if (_isMenuOpen) {
        _closeMenu();
      }

      Rect initialRect = Rect.fromCenter(
        center: _dragStartGlobal!,
        width: 360,
        height: 480,
      );
      final navContext = descriptor.navigatorKey.currentContext;
      final renderBox = navContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final topLeft = renderBox.localToGlobal(Offset.zero);
        initialRect = topLeft & renderBox.size;
      }

      _isDraggingTile = true;
      HapticUtils.selection();
      controller.startDraggingChat(
        DraggingChatPayload(
          chatId: descriptor.chatId,
          chatType: descriptor.chatType,
          chatName: descriptor.chatName,
          avatarUrl: descriptor.avatarUrl,
          isOnline: descriptor.isOnline,
          lastSeen: descriptor.lastSeen,
          otherUserId: descriptor.otherUserId,
          sourceTileId: descriptor.tileId,
          initialGlobalRect: initialRect,
          currentGlobalPosition: details.globalPosition,
          velocity: details.delta,
        ),
      );
      controller.updateDraggingChat(
        details.globalPosition,
        velocity: details.delta,
      );
      return;
    }

    controller.updateDraggingChat(
      details.globalPosition,
      velocity: details.delta,
    );
  }

  void _onCenterPillPanEnd(DragEndDetails details) {
    _dragStartGlobal = null;
    if (_isDraggingTile) {
      _isDraggingTile = false;
      TilingLayoutController.instance.endDraggingChat();
    }
  }

  void _onCenterPillPanCancel() {
    _dragStartGlobal = null;
    if (_isDraggingTile) {
      _isDraggingTile = false;
      TilingLayoutController.instance.cancelDraggingChat();
    }
  }

  double _calculateSelectionRightPillWidth() {
    int count = 0;
    if (widget.onCopySelected != null) count++;
    if (widget.onForwardSelected != null) count++;
    if (widget.onDeleteSelected != null) count++;
    if (count <= 1) return _kRightPillChannelWidth;
    if (count == 2) return _kRightPillChatWidth;
    return 128.0;
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlassEnabled = glassProvider.enabled;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    final bool hasCall = !widget.isChannel && widget.onVoiceCall != null;
    final double rightCollapsedWidth = widget.isSelectionMode
        ? _calculateSelectionRightPillWidth()
        : (hasCall ? _kRightPillChatWidth : _kRightPillChannelWidth);
    final double adaptiveMenuWidth = _calculateAdaptiveMenuWidth(context);

    final pillStyle = glassProvider.createStyle(
      context: context,
      cornerRadius: _kAppBarBorderRadius,
      refractionIndex: 1.1,
      refractionWidth: 24,
    );

    final morphStyle = glassProvider.createStyle(
      context: context,
      cornerRadius: _kAppBarBorderRadius,
      refractionIndex: 1.1,
      refractionWidth: 24,
    );

    final normalHeight = statusBarHeight + _kAppBarVerticalPadding + _kAppBarHeight;
    final tileHeight = TileViewportScope.heightOf(context);

    final Widget stackWidget = Stack(
          clipBehavior: Clip.none,
          children: [
            // Fullscreen backdrop to dismiss menu on outside tap
            Positioned.fill(
              key: const ValueKey<String>('chat_appbar_backdrop'),
              child: IgnorePointer(
                ignoring: !_isMenuOpen,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                ),
              ),
            ),

            // 1. Left Pill: Circular Back Button (44x44)
            Positioned(
              key: const ValueKey<String>('chat_appbar_left_pill'),
              top: statusBarHeight + _kAppBarVerticalPadding,
              left: _kAppBarHorizontalPadding,
              width: _kBackPillWidth,
              height: _kAppBarHeight,
              child: isGlassEnabled
                  ? LiquidGlassLens(
                      style: pillStyle,
                      touch: const LiquidGlassTouch.flexing(LiquidGlassFlex(
                        stretch: 6,
                        squeeze: 0.65,
                        lean: 0.3,
                        grip: 0.5,
                      )),
                      child: _buildBackButton(context, isDark),
                    )
                  : _buildMattePill(
                      isDark: isDark,
                      child: _buildBackButton(context, isDark),
                    ),
            ),

            // 2. Center Pill: Avatar + Name & Status Pill (Telegram Style + Drag Handle for Tile)
            Positioned(
              key: const ValueKey<String>('chat_appbar_center_pill'),
              top: statusBarHeight + _kAppBarVerticalPadding,
              left: _kAppBarHorizontalPadding + _kBackPillWidth + _kPillSpacing,
              right: _kAppBarHorizontalPadding + rightCollapsedWidth + _kPillSpacing,
              height: _kAppBarHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.isSelectionMode ? null : _handleCenterPillTap,
                onPanStart: _onCenterPillPanStart,
                onPanUpdate: _onCenterPillPanUpdate,
                onPanEnd: _onCenterPillPanEnd,
                onPanCancel: _onCenterPillPanCancel,
                child: isGlassEnabled
                    ? LiquidGlassLens(
                        style: pillStyle,
                        child: RepaintBoundary(
                          child: _buildCenterPillContent(context, isDark, theme),
                        ),
                      )
                    : _buildMattePill(
                        isDark: isDark,
                        child: RepaintBoundary(
                          child: _buildCenterPillContent(context, isDark, theme),
                        ),
                      ),
              ),
            ),

            // 3. Right Pill: Actions (Call + Three Dots), fluidly morphing into the menu directly in Stack
            Positioned(
              key: const ValueKey<String>('chat_appbar_right_pill'),
              top: statusBarHeight + _kAppBarVerticalPadding,
              right: _kAppBarHorizontalPadding,
              child: widget.isSelectionMode
                  ? SizedBox(
                      width: rightCollapsedWidth,
                      height: _kAppBarHeight,
                      child: isGlassEnabled
                          ? LiquidGlassLens(
                              style: pillStyle,
                              child: _SelectionRightPillContent(
                                key: const ValueKey<String>('chat_selection_right_pill_content'),
                                width: rightCollapsedWidth,
                                onCopy: widget.onCopySelected,
                                onForward: widget.onForwardSelected,
                                onDelete: widget.onDeleteSelected,
                              ),
                            )
                          : _buildMattePill(
                              isDark: isDark,
                              child: _SelectionRightPillContent(
                                key: const ValueKey<String>('chat_selection_right_pill_matte_content'),
                                width: rightCollapsedWidth,
                                onCopy: widget.onCopySelected,
                                onForward: widget.onForwardSelected,
                                onDelete: widget.onDeleteSelected,
                              ),
                            ),
                    )
                  : isGlassEnabled
                      ? SizedBox(
                          width: adaptiveMenuWidth,
                          height: _kMenuHeight,
                          child: LiquidGlassMorph(
                            key: const ValueKey<String>('chat_right_morph'),
                            alignment: Alignment.topRight,
                            motion: _kChatMenuMotion,
                            smoothness: 28,
                            style: morphStyle,
                            child: _isMenuOpen
                                ? _ChatActionsMorphMenu(
                                    key: const ValueKey<String>('chat_actions_menu'),
                                    width: adaptiveMenuWidth,
                                    isMuted: widget.isMuted,
                                    onViewProfile: () { _closeMenu(); widget.onViewProfile?.call(); },
                                    onSearch: () { _closeMenu(); widget.onSearch?.call(); },
                                    onToggleMute: () { _closeMenu(); widget.onToggleMute?.call(); },
                                    onClearHistory: () { _closeMenu(); widget.onClearHistory?.call(); },
                                    onReport: () { _closeMenu(); widget.onReport?.call(); },
                                  )
                                : _RightPillContent(
                                    key: const ValueKey<String>('chat_right_pill_content'),
                                    width: rightCollapsedWidth,
                                    hasCall: hasCall,
                                    onVoiceCall: widget.onVoiceCall,
                                    onThreeDotsTap: _toggleMenu,
                                  ),
                          ),
                        )
                      : AnimatedContainer(
                          key: const ValueKey<String>('chat_right_matte_container'),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          width: _isMenuOpen ? adaptiveMenuWidth : rightCollapsedWidth,
                          height: _isMenuOpen ? _kMenuHeight : _kAppBarHeight,
                          alignment: Alignment.topRight,
                          child: _buildMattePill(
                            isDark: isDark,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _isMenuOpen
                                  ? _ChatActionsMorphMenu(
                                      key: const ValueKey<String>('chat_actions_menu_matte'),
                                      width: adaptiveMenuWidth,
                                      isMuted: widget.isMuted,
                                      onViewProfile: () { _closeMenu(); widget.onViewProfile?.call(); },
                                      onSearch: () { _closeMenu(); widget.onSearch?.call(); },
                                      onToggleMute: () { _closeMenu(); widget.onToggleMute?.call(); },
                                      onClearHistory: () { _closeMenu(); widget.onClearHistory?.call(); },
                                      onReport: () { _closeMenu(); widget.onReport?.call(); },
                                    )
                                  : _RightPillContent(
                                      key: const ValueKey<String>('chat_right_pill_matte_content'),
                                      width: rightCollapsedWidth,
                                      hasCall: hasCall,
                                      onVoiceCall: widget.onVoiceCall,
                                      onThreeDotsTap: _toggleMenu,
                                    ),
                            ),
                          ),
                        ),
            ),
          ],
    );

    return PopScope(
      canPop: !_isMenuOpen && !widget.isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (widget.isSelectionMode) {
            widget.onCancelSelection?.call();
          } else if (_isMenuOpen) {
            _closeMenu();
          }
        }
      },
      child: SizedBox(
        width: double.infinity,
        height: _isMenuOpen ? tileHeight : normalHeight,
        child: isGlassEnabled
            ? LiquidGlassBlender(
                smoothness: 0,
                style: pillStyle,
                child: stackWidget,
              )
            : BackdropGroup(
                child: stackWidget,
              ),
      ),
    );
  }

  double _calculateAdaptiveMenuWidth(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final textStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
    );

    final labels = [
      l10n.translate('chat_menu_profile'),
      l10n.translate('chat_menu_search_messages'),
      widget.isMuted ? l10n.translate('chat_menu_unmute') : l10n.translate('chat_menu_mute'),
      l10n.translate('chat_menu_clear_history'),
      l10n.translate('chat_menu_report'),
    ];

    double maxTextWidth = 0.0;
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      if (painter.width > maxTextWidth) {
        maxTextWidth = painter.width;
      }
    }

    // 16 (left padding) + 22 (icon) + 12 (gap) + 16 (right padding) + 18 (safe curve margin) = 84.0
    final computedWidth = (maxTextWidth + 84.0).ceilToDouble();
    final screenWidth = TileViewportScope.widthOf(context);
    final maxAvailableWidth = screenWidth - (_kAppBarHorizontalPadding * 2);

    return computedWidth.clamp(200.0, maxAvailableWidth);
  }

  Widget _buildBackButton(BuildContext context, bool isDark) {
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final primaryTextColor = themeExt?.palette.appBarForeground ?? (isDark ? Colors.white : const Color(0xFF1C1C1E));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.tap();
        if (widget.isSelectionMode) {
          widget.onCancelSelection?.call();
          return;
        }
        if (_isMenuOpen) {
          _closeMenu();
          return;
        }
        final tileId = _registeredTileId ?? TileViewportScope.maybeTileIdOf(context);
        if (tileId != null &&
            tileId != TilingLayoutController.kLeftTileId &&
            TilingLayoutController.instance.isWorkspaceMounted &&
            !Navigator.of(context).canPop()) {
          TilingLayoutController.instance.handleBackAction(forTileId: tileId);
        } else {
          widget.onBack();
        }
      },
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: widget.isSelectionMode
              ? iconoir.Xmark(
                  key: const ValueKey<String>('selection_cancel_icon'),
                  width: 22.0,
                  height: 22.0,
                  color: primaryTextColor,
                )
              : iconoir.NavArrowLeft(
                  key: const ValueKey<String>('back_arrow_icon'),
                  width: 22.0,
                  height: 22.0,
                  color: primaryTextColor,
                ),
        ),
      ),
    );
  }

  void _handleCenterPillTap() {
    if (_isDraggingTile) return;
    if (_isMenuOpen) {
      _closeMenu();
      return;
    }
    if (widget.profileScreenBuilder != null) {
      Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: widget.profileScreenBuilder!,
        ),
      );
    } else {
      widget.onTitleTap();
    }
  }

  Widget _avatarFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final targetWidget = flightDirection == HeroFlightDirection.push
        ? toHeroContext.widget
        : fromHeroContext.widget;
    return ClipOval(
      child: Material(
        type: MaterialType.transparency,
        child: FittedBox(
          fit: BoxFit.cover,
          child: targetWidget,
        ),
      ),
    );
  }

  Widget _textHeroFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final targetWidget = flightDirection == HeroFlightDirection.push
        ? toHeroContext.widget
        : fromHeroContext.widget;
    return Material(
      type: MaterialType.transparency,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: targetWidget,
      ),
    );
  }

  Widget _buildCenterPillContent(BuildContext context, bool isDark, ThemeData theme) {
    final themeExt = theme.extension<TheavThemeExtension>();
    final primaryTextColor = themeExt?.palette.appBarForeground ?? (isDark ? Colors.white : const Color(0xFF1C1C1E));
    final secondaryTextColor = themeExt?.palette.subtext ??
        (isDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF4A4A4C));

    if (widget.isSelectionMode) {
      return Center(
        key: const ValueKey<String>('chat_selection_counter'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Text(
            context.l10n.translate(
              'chat_selected_count',
              {'count': '${widget.selectedCount}'},
            ),
            style: TextStyle(
              fontSize: _kTitleFontSize,
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
              fontFamily: theme.textTheme.bodyMedium?.fontFamily,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final heroKey = widget.heroTag ?? widget.name;

    return Padding(
      padding: const EdgeInsets.only(left: 2.0, right: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (widget.onAvatarTap != null && widget.profileScreenBuilder == null)
                ? () {
                    if (_isMenuOpen) {
                      _closeMenu();
                    } else {
                      widget.onAvatarTap!();
                    }
                  }
                : null,
            child: Hero(
              tag: 'profile_avatar_$heroKey',
              flightShuttleBuilder: _avatarFlightShuttleBuilder,
              child: widget.avatarWidget ??
                  AvatarWithStatus(
                    avatarUrl: widget.avatarUrl,
                    name: widget.name,
                    radius: _kCenterAvatarRadius,
                    isOnline: false,
                  ),
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: 'profile_name_$heroKey',
                  flightShuttleBuilder: _textHeroFlightShuttleBuilder,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _MarqueeScrollWrapper(
                      child: widget.titleWidget ??
                          Text(
                            widget.name,
                            style: TextStyle(
                              fontSize: _kTitleFontSize,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                              fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                            ),
                            maxLines: 1,
                            textAlign: TextAlign.left,
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 1.0),
                Hero(
                  tag: 'profile_status_$heroKey',
                  flightShuttleBuilder: _textHeroFlightShuttleBuilder,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _MarqueeScrollWrapper(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: WebSocketService().isConnectedNotifier,
                        builder: (context, wsConnected, _) {
                          final bool serverAvailable = widget.isConnected ?? wsConnected;
                          if (!serverAvailable) {
                            return AnimatedEllipsisText(
                              text: context.l10n.translate('chat_status_connecting'),
                              style: TextStyle(
                                fontSize: _kStatusFontSize,
                                color: secondaryTextColor,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          }
                          if (widget.statusText != null) {
                            final isHardcodedGrey = widget.statusColor == Colors.grey[600] ||
                                widget.statusColor == Colors.grey;
                            final defaultAccent = isDark
                                ? const Color(0xFF5CB8E6)
                                : theme.colorScheme.primary;
                            final effectiveColor = (widget.statusColor == null || isHardcodedGrey)
                                ? secondaryTextColor
                                : (widget.statusColor == theme.colorScheme.primary ? defaultAccent : widget.statusColor);
                            return AnimatedEllipsisText(
                              text: widget.statusText!,
                              style: TextStyle(
                                fontSize: _kStatusFontSize,
                                color: effectiveColor,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          }
                          return _AutoRefreshingLastSeenText(
                            isOnline: widget.isOnline,
                            lastSeen: widget.lastSeen,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMattePill({required bool isDark, required Widget child}) {
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final defaultBg = isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.65);
    final pillBg = themeExt?.palette.appBarBackground ?? defaultBg;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: Container(
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}


/// Content of the collapsed right pill:
/// - In channel: single "three dots" button (54x54)
/// - In chat with voice call: [ Phone | Three Dots ] (88x54)
class _RightPillContent extends StatelessWidget {
  final double width;
  final bool hasCall;
  final VoidCallback? onVoiceCall;
  final VoidCallback onThreeDotsTap;

  const _RightPillContent({
    super.key,
    required this.width,
    required this.hasCall,
    this.onVoiceCall,
    required this.onThreeDotsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = themeExt?.palette.appBarForeground ?? (isDark ? Colors.white : const Color(0xFF1C1C1E));

    final Widget content;
    if (!hasCall) {
      content = SizedBox(
        width: width,
        height: _kAppBarHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onThreeDotsTap,
          child: Center(
            child: iconoir.MoreVert(
              width: 22.0,
              height: 22.0,
              color: primaryTextColor,
            ),
          ),
        ),
      );
    } else {
      content = SizedBox(
        width: width,
        height: _kAppBarHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                onVoiceCall?.call();
              },
              child: SizedBox(
                width: 40,
                height: _kAppBarHeight,
                child: Center(
                  child: iconoir.PhoneSolid(
                    width: _kActionIconSize,
                    height: _kActionIconSize,
                    color: primaryTextColor,
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onThreeDotsTap,
              child: SizedBox(
                width: 40,
                height: _kAppBarHeight,
                child: Center(
                  child: iconoir.MoreVert(
                    width: 22.0,
                    height: 22.0,
                    color: primaryTextColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: width,
      height: _kAppBarHeight,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: _kAppBarHeight,
        maxHeight: _kAppBarHeight,
        alignment: Alignment.centerRight,
        child: content,
      ),
    );
  }
}

/// Content of the right pill when multi-message selection mode is active:
/// [ Copy | Forward | Delete ]
class _SelectionRightPillContent extends StatelessWidget {
  final double width;
  final VoidCallback? onCopy;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  const _SelectionRightPillContent({
    super.key,
    required this.width,
    this.onCopy,
    this.onForward,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = themeExt?.palette.appBarForeground ??
        (isDark ? Colors.white : const Color(0xFF1C1C1E));
    final deleteColor = themeExt?.palette.error ?? const Color(0xFFFF3B30);

    return SizedBox(
      width: width,
      height: _kAppBarHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onCopy != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                onCopy!();
              },
              child: SizedBox(
                width: 38,
                height: _kAppBarHeight,
                child: Center(
                  child: iconoir.Copy(
                    width: 20.0,
                    height: 20.0,
                    color: primaryTextColor,
                  ),
                ),
              ),
            ),
          if (onForward != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                onForward!();
              },
              child: SizedBox(
                width: 38,
                height: _kAppBarHeight,
                child: Center(
                  child: iconoir.ForwardMessage(
                    width: 20.0,
                    height: 20.0,
                    color: primaryTextColor,
                  ),
                ),
              ),
            ),
          if (onDelete != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                onDelete!();
              },
              child: SizedBox(
                width: 38,
                height: _kAppBarHeight,
                child: Center(
                  child: iconoir.Trash(
                    width: 20.0,
                    height: 20.0,
                    color: deleteColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Content of the expanded actions menu morphed from the right pill.
class _ChatActionsMorphMenu extends StatelessWidget {
  final double width;
  final bool isMuted;
  final VoidCallback onViewProfile;
  final VoidCallback onSearch;
  final VoidCallback onToggleMute;
  final VoidCallback onClearHistory;
  final VoidCallback onReport;

  const _ChatActionsMorphMenu({
    super.key,
    required this.width,
    required this.isMuted,
    required this.onViewProfile,
    required this.onSearch,
    required this.onToggleMute,
    required this.onClearHistory,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SizedBox(
      width: width,
      height: _kMenuHeight,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: _kMenuHeight,
        maxHeight: _kMenuHeight,
        alignment: Alignment.topRight,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _menuItem(
                    context,
                    l10n.translate('chat_menu_profile'),
                    onViewProfile,
                    iconBuilder: (c) => iconoir.User(color: c, width: 20, height: 20),
                  ),
                  _menuItem(
                    context,
                    l10n.translate('chat_menu_search_messages'),
                    onSearch,
                    iconBuilder: (c) => iconoir.Search(color: c, width: 20, height: 20),
                  ),
                  _menuItem(
                    context,
                    isMuted ? l10n.translate('chat_menu_unmute') : l10n.translate('chat_menu_mute'),
                    onToggleMute,
                    iconBuilder: (c) => isMuted
                        ? iconoir.BellOff(color: c, width: 20, height: 20)
                        : iconoir.Bell(color: c, width: 20, height: 20),
                  ),
                  _menuItem(
                    context,
                    l10n.translate('chat_menu_clear_history'),
                    onClearHistory,
                    iconBuilder: (c) => iconoir.Trash(color: c, width: 20, height: 20),
                    isDestructive: true,
                  ),
                  _menuItem(
                    context,
                    l10n.translate('chat_menu_report'),
                    onReport,
                    iconBuilder: (c) => iconoir.WarningTriangle(color: c, width: 20, height: 20),
                    isDestructive: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    required Widget Function(Color color) iconBuilder,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final destructiveColor = isDark ? const Color(0xFFFF453A) : const Color(0xFFD32F2F);
    final color = isDestructive ? destructiveColor : primaryTextColor;

    return InkWell(
      onTap: () {
        if (isDestructive) {
          HapticUtils.heavy();
        } else {
          HapticUtils.selection();
        }
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      highlightColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.04),
      splashColor: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.08),
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: iconBuilder(color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: color,
                    fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// A widget that automatically and reactively updates the last seen status
/// (e.g. from "just now" -> "1m ago" -> "2m ago") without requiring a page reload.
class _AutoRefreshingLastSeenText extends StatefulWidget {
  final bool isOnline;
  final DateTime? lastSeen;

  const _AutoRefreshingLastSeenText({
    Key? key,
    required this.isOnline,
    this.lastSeen,
  }) : super(key: key);

  @override
  State<_AutoRefreshingLastSeenText> createState() =>
      _AutoRefreshingLastSeenTextState();
}

class _AutoRefreshingLastSeenTextState
    extends State<_AutoRefreshingLastSeenText> {
  Timer? _timer;
  String _currentStatus = '';

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStatus(rebuild: false);
  }

  @override
  void didUpdateWidget(covariant _AutoRefreshingLastSeenText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOnline != widget.isOnline ||
        oldWidget.lastSeen != widget.lastSeen) {
      _startTimerIfNeeded();
      _updateStatus(rebuild: true);
    }
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    _timer = null;
    if (!widget.isOnline && widget.lastSeen != null) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        _updateStatus(rebuild: true);
      });
    }
  }

  void _updateStatus({required bool rebuild}) {
    if (!mounted) return;
    final newStatus = widget.isOnline
        ? context.l10n.translate('chat_status_online')
        : DateTimeUtils.formatLastSeen(widget.lastSeen, context);

    if (newStatus != _currentStatus) {
      if (rebuild) {
        setState(() {
          _currentStatus = newStatus;
        });
      } else {
        _currentStatus = newStatus;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final onlineColor = themeExt?.palette.onlineIndicator ?? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32));
    final offlineColor = themeExt?.palette.subtext ??
        (isDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF4A4A4C));

    final status = _currentStatus.isNotEmpty
        ? _currentStatus
        : (widget.isOnline
            ? context.l10n.translate('chat_status_online')
            : DateTimeUtils.formatLastSeen(widget.lastSeen, context));

    return AnimatedEllipsisText(
      text: status,
      style: TextStyle(
        fontSize: _kStatusFontSize,
        color: widget.isOnline ? onlineColor : offlineColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  Size? _oldSize;
  ValueChanged<Size> onChange;

  _MeasureSizeRenderObject(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChange(newSize);
      });
    }
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const _MeasureSize({
    Key? key,
    required this.onChange,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
      BuildContext context, covariant _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

/// Горизонтальная обёртка с плавной бесконечной циклической автопрокруткой (бегущая строка)
/// для текста заголовка и статуса. Ручная прокрутка отключена, строки независимы,
/// прокрутка происходит слева направо (в направлении чтения) с паузой только после полного круга.
class _MarqueeScrollWrapper extends StatefulWidget {
  final Widget child;

  const _MarqueeScrollWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<_MarqueeScrollWrapper> createState() => _MarqueeScrollWrapperState();
}

class _MarqueeScrollWrapperState extends State<_MarqueeScrollWrapper> {
  static const double _kMarqueeGap = 36.0;
  final ScrollController _controller = ScrollController();
  Timer? _timer;
  bool _loopRunning = false;
  bool _shouldScroll = false;
  double _childWidth = 0.0;
  double _viewportWidth = 0.0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChildSizeChanged(Size size) {
    if (!mounted) return;
    final width = size.width;
    if ((width - _childWidth).abs() > 0.5) {
      _childWidth = width;
      _evaluateScroll();
    }
  }

  void _evaluateScroll() {
    if (!mounted) return;
    final needsScroll = _childWidth > _viewportWidth && _viewportWidth > 0;
    if (needsScroll != _shouldScroll) {
      setState(() {
        _shouldScroll = needsScroll;
      });
    }
    if (!needsScroll) {
      _stopLoop();
    } else if (!_loopRunning) {
      _startLoop();
    }
  }

  void _stopLoop() {
    _timer?.cancel();
    _timer = null;
    _loopRunning = false;
    if (_controller.hasClients && _controller.offset != 0.0) {
      _controller.jumpTo(0.0);
    }
  }

  void _startLoop() {
    if (_loopRunning || !mounted || !_controller.hasClients || !_shouldScroll) return;
    _loopRunning = true;
    _runLoopIteration();
  }

  void _runLoopIteration() {
    _timer?.cancel();
    // Останавливаться они могут только после полного круга (на позиции 0.0)
    _timer = Timer(const Duration(milliseconds: 2000), () async {
      if (!mounted || !_controller.hasClients || !_shouldScroll) {
        _loopRunning = false;
        return;
      }
      final loopDistance = _childWidth + _kMarqueeGap;
      // Скорость чтения ~32 px/сек
      final durationMs = ((loopDistance / 32.0) * 1000).clamp(2500, 15000).round();

      try {
        await _controller.animateTo(
          loopDistance,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.linear,
        );
        if (!mounted || !_controller.hasClients || !_shouldScroll) {
          _loopRunning = false;
          return;
        }
        // Бесшовный возврат на исходную позицию (копия в loopDistance визуально идентична 0.0)
        _controller.jumpTo(0.0);
        // Запускаем следующий цикл с паузой только в начале полного круга
        _runLoopIteration();
      } catch (_) {
        _loopRunning = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant _MarqueeScrollWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.runtimeType != widget.child.runtimeType ||
        oldWidget.child.key != widget.child.key) {
      _stopLoop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _evaluateScroll();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newViewportWidth = constraints.maxWidth;
        if ((newViewportWidth - _viewportWidth).abs() > 0.5) {
          _viewportWidth = newViewportWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _evaluateScroll();
          });
        }

        return RepaintBoundary(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MeasureSize(
                  onChange: _onChildSizeChanged,
                  child: widget.child,
                ),
                if (_shouldScroll) ...[
                  const SizedBox(width: _kMarqueeGap),
                  widget.child,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A beautiful glass menu for the chat avatar actions.
class GlassChatMenu extends StatefulWidget {
  final BuildContext chatContext;
  final bool isMuted;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;
  final VoidCallback onSearch;
  final VoidCallback onToggleMute;
  final VoidCallback onClearHistory;
  final VoidCallback onReport;
  final VoidCallback onViewProfile;

  const GlassChatMenu({
    Key? key,
    required this.chatContext,
    required this.isMuted,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onSearch,
    required this.onToggleMute,
    required this.onClearHistory,
    required this.onReport,
    required this.onViewProfile,
  }) : super(key: key);

  static void show(
    BuildContext context, {
    required bool isMuted,
    required VoidCallback onVoiceCall,
    required VoidCallback onVideoCall,
    required VoidCallback onSearch,
    required VoidCallback onToggleMute,
    required VoidCallback onClearHistory,
    required VoidCallback onReport,
    required VoidCallback onViewProfile,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GlassChatMenu(
          chatContext: context,
          isMuted: isMuted,
          onVoiceCall: () { Navigator.pop(context); onVoiceCall(); },
          onVideoCall: () { Navigator.pop(context); onVideoCall(); },
          onSearch: () { Navigator.pop(context); onSearch(); },
          onToggleMute: () { Navigator.pop(context); onToggleMute(); },
          onClearHistory: () { Navigator.pop(context); onClearHistory(); },
          onReport: () { Navigator.pop(context); onReport(); },
          onViewProfile: () { Navigator.pop(context); onViewProfile(); },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
    );
  }

  @override
  State<GlassChatMenu> createState() => _GlassChatMenuState();
}

class _GlassChatMenuState extends State<GlassChatMenu> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = Provider.of<LiquidGlassProvider>(context, listen: false);
    final isGlassEnabled = glassProvider.enabled;

    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Positioned(
          top: statusBarHeight + _kAppBarHeight + 16, // Just below the floating app bar
          right: 12, // Align with the right edge of the app bar
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMenuWidth),
              child: IntrinsicWidth(
                child: isGlassEnabled
                    ? _buildGlassMenu(isDark, theme)
                    : _buildMatteMenu(isDark, theme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassMenu(bool isDark, ThemeData theme) {
    final glassProvider = Provider.of<LiquidGlassProvider>(context, listen: false);

    final style = glassProvider.createStyle(
      context: context,
      cornerRadius: _kAppBarBorderRadius,
      color: isDark ? const Color(0x44202025) : const Color(0x9EFFFFFF),
      refractionIndex: 1.1,
      refractionWidth: 24,
    );

    return LiquidGlassLens(
      style: style,
      child: _buildMenuItems(theme),
    );
  }

  Widget _buildMatteMenu(bool isDark, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
      child: BackdropFilter(
        filter: BlurUtils.createDownsampledBlur(15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: _buildMenuItems(theme),
        ),
      ),
    );
  }

  Widget _buildMenuItems(ThemeData theme) {
    final l10n = widget.chatContext.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _menuItem(
            l10n.translate('chat_menu_profile'),
            widget.onViewProfile,
            iconBuilder: (c) => iconoir.User(color: c, width: 22, height: 22),
          ),
          _menuItem(
            l10n.translate('chat_menu_voice_call'),
            widget.onVoiceCall,
            iconBuilder: (c) => iconoir.Phone(color: c, width: 22, height: 22),
          ),
          _menuItem(
            l10n.translate('chat_menu_video_call'),
            widget.onVideoCall,
            iconBuilder: (c) => iconoir.VideoCamera(color: c, width: 22, height: 22),
          ),
          _menuItem(
            l10n.translate('chat_menu_search_messages'),
            widget.onSearch,
            iconBuilder: (c) => iconoir.Search(color: c, width: 22, height: 22),
          ),
          _menuItem(
            widget.isMuted ? l10n.translate('chat_menu_unmute') : l10n.translate('chat_menu_mute'),
            widget.onToggleMute,
            iconBuilder: (c) => widget.isMuted
                ? iconoir.BellOff(color: c, width: 22, height: 22)
                : iconoir.Bell(color: c, width: 22, height: 22),
          ),
          _menuItem(
            l10n.translate('chat_menu_clear_history'),
            widget.onClearHistory,
            iconBuilder: (c) => iconoir.Trash(color: c, width: 22, height: 22),
            isDestructive: true,
          ),
          _menuItem(
            l10n.translate('chat_menu_report'),
            widget.onReport,
            iconBuilder: (c) => iconoir.WarningTriangle(color: c, width: 22, height: 22),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _menuItem(
    String label,
    VoidCallback onTap, {
    IconData? icon,
    Widget Function(Color color)? iconBuilder,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(widget.chatContext).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final destructiveColor = isDark ? const Color(0xFFFF453A) : const Color(0xFFD32F2F);
    final color = isDestructive ? destructiveColor : primaryTextColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      highlightColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.04),
      splashColor: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Center(
                child: iconBuilder != null
                    ? iconBuilder(color)
                    : (icon != null
                        ? Icon(icon, size: 22, color: color)
                        : const SizedBox.shrink()),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
