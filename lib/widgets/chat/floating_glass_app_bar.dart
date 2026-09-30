import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/websocket_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../user/avatar_with_status.dart';
import 'animated_ellipsis_text.dart';

// --- НАСТРОЙКИ СТИЛЯ ПАНЕЛИ ---
/// Высота панели без учета отступов и статус-бара (Apple HIG standard).
const double _kAppBarHeight = 54.0;
/// Радиус скругления капсул панели (54 / 2 = 27) — идеальный стадион / круг.
const double _kAppBarBorderRadius = 27.0;
/// Внешний горизонтальный отступ панели от краев экрана.
const double _kAppBarHorizontalPadding = 12.0;
/// Внешний вертикальный отступ панели от статус-бара.
const double _kAppBarVerticalPadding = 8.0;
/// Расстояние между частями панели.
const double _kPillSpacing = 8.0;

/// Ширина левой плашки (кнопка "Назад").
const double _kBackPillWidth = 54.0;

/// Ширина правой плашки в канале (только аватарка).
const double _kRightPillChannelWidth = 54.0;
/// Ширина правой плашки в чате (звонок + аватарка).
const double _kRightPillChatWidth = 94.0;

/// Ширина выпадающего морф-меню действий.
const double _kMenuWidth = 250.0;
/// Высота выпадающего морф-меню действий (5 пунктов по 42pt + padding 24pt = 234pt).
const double _kMenuHeight = 234.0;

/// Размер шрифта имени в заголовке.
const double _kTitleFontSize = 16.0;
/// Размер шрифта статуса (в сети / был недавно).
const double _kStatusFontSize = 12.0;

/// Радиус аватарки.
const double _kAvatarRadius = 22.0;
/// Размер иконок действий (звонок).
const double _kActionIconSize = 20.0;
// ------------------------------

/// Floating AppBar split into 3 distinct glass/matte pills:
/// 1. Left circular pill: Back button (54x54).
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
  }) : super(key: key);

  @override
  State<FloatingGlassAppBar> createState() => _FloatingGlassAppBarState();
}

class _FloatingGlassAppBarState extends State<FloatingGlassAppBar> {
  bool _isMenuOpen = false;
  bool _isMenuClosing = false;

  void _openMenu() {
    if (_isMenuOpen) return;
    HapticUtils.tap();
    setState(() {
      _isMenuOpen = true;
      _isMenuClosing = false;
    });
  }

  void _closeMenu() {
    if (!_isMenuOpen) return;
    setState(() {
      _isMenuOpen = false;
      _isMenuClosing = true;
    });
  }

  void _toggleMenu() {
    if (_isMenuOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _handleAvatarTap() {
    final hasMenuCallbacks = widget.onViewProfile != null ||
        widget.onSearch != null ||
        widget.onToggleMute != null ||
        widget.onClearHistory != null ||
        widget.onReport != null;

    if (hasMenuCallbacks) {
      _toggleMenu();
    } else if (widget.onAvatarTap != null) {
      widget.onAvatarTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlassEnabled = glassProvider.enabled;
    final isLite = glassProvider.isLite;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final screenSize = MediaQuery.sizeOf(context);

    final rightCollapsedWidth =
        widget.isChannel ? _kRightPillChannelWidth : _kRightPillChatWidth;

    final morphShape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: _kAppBarBorderRadius,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: isDark ? 0.7 : 0.95,
      lightDirection: lightAngle,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final morphStyle = LiquidGlassStyle(
      shape: morphShape,
      appearance: LiquidGlassAppearance(
        color: isDark ? const Color(0x33202025) : const Color(0x8FFFFFFF),
        blur: glassProvider.blurEffect,
        shadow: LiquidGlassShadow(
          blur: 16,
          opacity: isDark ? 0.40 : 0.18,
          offset: const Offset(0, 4),
          color: Colors.black,
        ),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.06,
        distortionWidth: 26,
      ),
      liteGlass: isLite ? LiquidGlassLitePickup.backdrop : null,
    );

    final normalHeight = statusBarHeight + _kAppBarVerticalPadding + _kAppBarHeight;
    final isExpanded = _isMenuOpen || _isMenuClosing;
    final currentHeight = isExpanded ? screenSize.height : normalHeight;

    return PopScope(
      canPop: !_isMenuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isMenuOpen) {
          _closeMenu();
        }
      },
      child: SizedBox(
        width: double.infinity,
        height: currentHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Fullscreen backdrop to dismiss menu on outside tap
            if (_isMenuOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                ),
              ),

            // 1. Left Pill: Circular Back Button (54x54)
            Positioned(
              top: statusBarHeight + _kAppBarVerticalPadding,
              left: _kAppBarHorizontalPadding,
              width: _kBackPillWidth,
              height: _kAppBarHeight,
              child: isGlassEnabled
                  ? LiquidGlassLens(
                      style: morphStyle,
                      child: _buildBackButton(context, isDark),
                    )
                  : _buildMattePill(
                      isDark: isDark,
                      child: _buildBackButton(context, isDark),
                    ),
            ),

            // 2. Center Pill: Name & Status Pill
            Positioned(
              top: statusBarHeight + _kAppBarVerticalPadding,
              left: _kAppBarHorizontalPadding + _kBackPillWidth + _kPillSpacing,
              right: _kAppBarHorizontalPadding + rightCollapsedWidth + _kPillSpacing,
              height: _kAppBarHeight,
              child: isGlassEnabled
                  ? LiquidGlassLens(
                      style: morphStyle,
                      child: _buildCenterPillContent(context, isDark, theme),
                    )
                  : _buildMattePill(
                      isDark: isDark,
                      child: _buildCenterPillContent(context, isDark, theme),
                    ),
            ),

            // 3. Right Pill: Actions + Avatar, morphing to Menu
            if (isGlassEnabled)
              Positioned(
                top: statusBarHeight + _kAppBarVerticalPadding,
                right: _kAppBarHorizontalPadding,
                width: _kMenuWidth,
                height: _kMenuHeight,
                child: _MorphHitTestBoundary(
                  isMenuOpen: _isMenuOpen || _isMenuClosing,
                  collapsedWidth: rightCollapsedWidth,
                  collapsedHeight: _kAppBarHeight,
                  child: LiquidGlassMorph(
                    alignment: Alignment.topRight,
                    motion: LiquidGlassMorphMotion.fluid,
                    smoothness: 28,
                    style: morphStyle,
                    onEnd: () {
                      if (_isMenuClosing) {
                        setState(() => _isMenuClosing = false);
                      }
                    },
                    child: _isMenuOpen
                        ? _ChatActionsMorphMenu(
                            key: const ValueKey<String>('chat_actions_menu'),
                            isMuted: widget.isMuted,
                            onViewProfile: () { _closeMenu(); widget.onViewProfile?.call(); },
                            onSearch: () { _closeMenu(); widget.onSearch?.call(); },
                            onToggleMute: () { _closeMenu(); widget.onToggleMute?.call(); },
                            onClearHistory: () { _closeMenu(); widget.onClearHistory?.call(); },
                            onReport: () { _closeMenu(); widget.onReport?.call(); },
                          )
                        : _RightPillContent(
                            key: const ValueKey<String>('chat_right_pill'),
                            isChannel: widget.isChannel,
                            name: widget.name,
                            avatarUrl: widget.avatarUrl,
                            isOnline: widget.isOnline,
                            avatarWidget: widget.avatarWidget,
                            onVoiceCall: widget.onVoiceCall,
                            onAvatarTap: _handleAvatarTap,
                          ),
                  ),
                ),
              )
            else
              Positioned(
                top: statusBarHeight + _kAppBarVerticalPadding,
                right: _kAppBarHorizontalPadding,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: _isMenuOpen ? _kMenuWidth : rightCollapsedWidth,
                  height: _isMenuOpen ? _kMenuHeight : _kAppBarHeight,
                  onEnd: () {
                    if (_isMenuClosing) {
                      setState(() => _isMenuClosing = false);
                    }
                  },
                  child: _buildMattePill(
                    isDark: isDark,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _isMenuOpen
                          ? _ChatActionsMorphMenu(
                              key: const ValueKey<String>('chat_actions_menu_matte'),
                              isMuted: widget.isMuted,
                              onViewProfile: () { _closeMenu(); widget.onViewProfile?.call(); },
                              onSearch: () { _closeMenu(); widget.onSearch?.call(); },
                              onToggleMute: () { _closeMenu(); widget.onToggleMute?.call(); },
                              onClearHistory: () { _closeMenu(); widget.onClearHistory?.call(); },
                              onReport: () { _closeMenu(); widget.onReport?.call(); },
                            )
                          : _RightPillContent(
                              key: const ValueKey<String>('chat_right_pill_matte'),
                              isChannel: widget.isChannel,
                              name: widget.name,
                              avatarUrl: widget.avatarUrl,
                              isOnline: widget.isOnline,
                              avatarWidget: widget.avatarWidget,
                              onVoiceCall: widget.onVoiceCall,
                              onAvatarTap: _handleAvatarTap,
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, bool isDark) {
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.tap();
        widget.onBack();
      },
      child: Center(
        child: iconoir.NavArrowLeft(
          width: 22.0,
          height: 22.0,
          color: primaryTextColor,
        ),
      ),
    );
  }

  Widget _buildCenterPillContent(BuildContext context, bool isDark, ThemeData theme) {
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF4A4A4C);

    return GestureDetector(
      onTap: widget.onTitleTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.titleWidget != null)
              widget.titleWidget!
            else
              Text(
                widget.name,
                style: TextStyle(
                  fontSize: _kTitleFontSize,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                  fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 1.0),
            ValueListenableBuilder<bool>(
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
          ],
        ),
      ),
    );
  }

  Widget _buildMattePill({required bool isDark, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
          child: child,
        ),
      ),
    );
  }
}

/// Bounding widget that restricts touch hit testing to ONLY the collapsed pill area
/// when the menu is closed, and allows full menu hit testing when the menu is open/animating.
/// This allows the parent [Positioned] to stay at a constant size (_kMenuWidth x _kMenuHeight)
/// so that LiquidGlassMorph never snaps or jerks upon opening or closing.
class _MorphHitTestBoundary extends SingleChildRenderObjectWidget {
  final bool isMenuOpen;
  final double collapsedWidth;
  final double collapsedHeight;

  const _MorphHitTestBoundary({
    required this.isMenuOpen,
    required this.collapsedWidth,
    required this.collapsedHeight,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMorphHitTestBoundary(
      isMenuOpen: isMenuOpen,
      collapsedWidth: collapsedWidth,
      collapsedHeight: collapsedHeight,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMorphHitTestBoundary renderObject,
  ) {
    renderObject
      ..isMenuOpen = isMenuOpen
      ..collapsedWidth = collapsedWidth
      ..collapsedHeight = collapsedHeight;
  }
}

class _RenderMorphHitTestBoundary extends RenderProxyBox {
  bool _isMenuOpen;
  double _collapsedWidth;
  double _collapsedHeight;

  _RenderMorphHitTestBoundary({
    required bool isMenuOpen,
    required double collapsedWidth,
    required double collapsedHeight,
  })  : _isMenuOpen = isMenuOpen,
        _collapsedWidth = collapsedWidth,
        _collapsedHeight = collapsedHeight;

  set isMenuOpen(bool value) {
    if (_isMenuOpen == value) return;
    _isMenuOpen = value;
  }

  set collapsedWidth(double value) {
    if (_collapsedWidth == value) return;
    _collapsedWidth = value;
  }

  set collapsedHeight(double value) {
    if (_collapsedHeight == value) return;
    _collapsedHeight = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_isMenuOpen) {
      final pillRect = Rect.fromLTWH(
        size.width - _collapsedWidth,
        0,
        _collapsedWidth,
        _collapsedHeight,
      );
      if (!pillRect.contains(position)) {
        return false;
      }
    }
    return super.hitTest(result, position: position);
  }
}

/// Content of the collapsed right pill:
/// - In channel: only avatar centered
/// - In private / group chat: [ Phone | Avatar ]
class _RightPillContent extends StatelessWidget {
  final bool isChannel;
  final String name;
  final String? avatarUrl;
  final bool isOnline;
  final Widget? avatarWidget;
  final VoidCallback? onVoiceCall;
  final VoidCallback onAvatarTap;

  const _RightPillContent({
    super.key,
    required this.isChannel,
    required this.name,
    this.avatarUrl,
    required this.isOnline,
    this.avatarWidget,
    this.onVoiceCall,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    if (isChannel) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onAvatarTap,
        child: Center(
          child: avatarWidget ??
              AvatarWithStatus(
                avatarUrl: avatarUrl,
                name: name,
                radius: _kAvatarRadius,
                isOnline: isOnline,
              ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 7),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticUtils.tap();
            onVoiceCall?.call();
          },
          child: SizedBox(
            width: 34,
            height: _kAppBarHeight,
            child: Center(
              child: iconoir.Phone(
                width: _kActionIconSize,
                height: _kActionIconSize,
                color: primaryTextColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAvatarTap,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: avatarWidget ??
                AvatarWithStatus(
                  avatarUrl: avatarUrl,
                  name: name,
                  radius: _kAvatarRadius,
                  isOnline: isOnline,
                ),
          ),
        ),
      ],
    );
  }
}

/// Content of the expanded actions menu morphed from the right pill.
class _ChatActionsMorphMenu extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onViewProfile;
  final VoidCallback onSearch;
  final VoidCallback onToggleMute;
  final VoidCallback onClearHistory;
  final VoidCallback onReport;

  const _ChatActionsMorphMenu({
    super.key,
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

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onlineColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32);
    final offlineColor = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF4A4A4C);

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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);

    final shape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: _kAppBarBorderRadius,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: isDark ? 0.7 : 0.95,
      lightDirection: lightAngle,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final style = LiquidGlassStyle(
      shape: shape,
      appearance: LiquidGlassAppearance(
        color: isDark ? const Color(0x44202025) : const Color(0x9EFFFFFF),
        blur: glassProvider.blurEffect,
        shadow: LiquidGlassShadow(
          blur: 20,
          opacity: isDark ? 0.45 : 0.22,
          offset: const Offset(0, 6),
          color: Colors.black,
        ),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.08,
        distortionWidth: 24,
      ),
      liteGlass: glassProvider.isLite ? LiquidGlassLitePickup.backdrop : null,
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
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
