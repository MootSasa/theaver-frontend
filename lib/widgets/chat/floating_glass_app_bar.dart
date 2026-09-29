import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../user/avatar_with_status.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import 'animated_ellipsis_text.dart';
import '../../utils/date_time_utils.dart';

// --- НАСТРОЙКИ СТИЛЯ ПАНЕЛИ ---
/// Радиус скругления "облака" панели (AppBar).
const double _kAppBarBorderRadius = 27.0;
/// Высота панели без учета отступов и статус-бара.
const double _kAppBarHeight = 54.0;
/// Внешний горизонтальный отступ панели от краев экрана.
const double _kAppBarHorizontalPadding = 12.0;
/// Внешний вертикальный отступ панели от статус-бара.
const double _kAppBarVerticalPadding = 8.0;

/// Размер шрифта имени пользователя в заголовке.
const double _kTitleFontSize = 17.0;
/// Размер шрифта статуса (в сети / был недавно).
const double _kStatusFontSize = 12.0;

/// Радиус аватарки в панели.
const double _kAvatarRadius = 22.0;

/// Размер иконки внутри кнопок действий.
const double _kCircularIconSize = 18.0;

/// Максимальная ширина выпадающего меню.
const double _kMenuMaxWidth = 260.0;
/// Радиус скругления выпадающего меню.
const double _kMenuBorderRadius = 28.0;
// ------------------------------

/// Floating AppBar with glass/matte "cloud" design, matching the input field.
class FloatingGlassAppBar extends StatelessWidget {
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
  final VoidCallback onAvatarTap;

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
    required this.onAvatarTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlassEnabled = glassProvider.enabled;
    final isLite = glassProvider.isLite;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);

    final statusBarHeight = MediaQuery.of(context).padding.top;

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

    return Container(
      padding: EdgeInsets.only(
        top: statusBarHeight + _kAppBarVerticalPadding,
        left: _kAppBarHorizontalPadding,
        right: _kAppBarHorizontalPadding,
      ),
      child: isGlassEnabled
          ? _buildGlassCloud(context, style, _kAppBarHeight)
          : _buildMatteCloud(context, isDark, _kAppBarHeight),
    );
  }

  Widget _buildGlassCloud(BuildContext context, LiquidGlassStyle style, double height) {
    return SizedBox(
      height: height,
      child: LiquidGlassLens(
        style: style,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildMatteCloud(BuildContext context, bool isDark, double height) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: height,
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
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 4),
        _buildCircularButton(
          context,
          iconWidget: iconoir.NavArrowLeft(
            width: _kCircularIconSize,
            height: _kCircularIconSize,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onTap: onBack,
          iconSize: _kCircularIconSize,
        ),
        Expanded(
          child: GestureDetector(
            onTap: onTitleTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (titleWidget != null)
                  titleWidget!
                else
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: _kTitleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: WebSocketService().isConnectedNotifier,
                  builder: (context, wsConnected, _) {
                    final bool serverAvailable = isConnected ?? wsConnected;
                    if (!serverAvailable) {
                      return AnimatedEllipsisText(
                        text: context.l10n.translate('chat_status_connecting'),
                        style: TextStyle(
                          fontSize: _kStatusFontSize,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                    if (statusText != null) {
                      return AnimatedEllipsisText(
                        text: statusText!,
                        style: TextStyle(
                          fontSize: _kStatusFontSize,
                          color: statusColor ?? Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                    return _buildStatusText(context);
                  },
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
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

  Widget _buildStatusText(BuildContext context) {
    return _AutoRefreshingLastSeenText(
      isOnline: isOnline,
      lastSeen: lastSeen,
    );
  }

  Widget _buildCircularButton(
    BuildContext context, {
    IconData? icon,
    Widget? iconWidget,
    required VoidCallback onTap,
    double iconSize = 20,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: iconWidget ??
          (icon != null
              ? Icon(
                  icon,
                  size: iconSize,
                  color: Theme.of(context).colorScheme.onSurface,
                )
              : const SizedBox.shrink()),
      splashRadius: 24,
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
    final status = _currentStatus.isNotEmpty
        ? _currentStatus
        : (widget.isOnline
            ? context.l10n.translate('chat_status_online')
            : DateTimeUtils.formatLastSeen(widget.lastSeen, context));

    return AnimatedEllipsisText(
      text: status,
      style: TextStyle(
        fontSize: _kStatusFontSize,
        color: widget.isOnline ? Colors.green : Colors.grey[600],
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
              constraints: const BoxConstraints(maxWidth: _kMenuMaxWidth),
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
      cornerRadius: _kMenuBorderRadius,
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
      borderRadius: BorderRadius.circular(_kMenuBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(_kMenuBorderRadius),
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
    final theme = Theme.of(widget.chatContext);
    final color = isDestructive ? Colors.redAccent : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
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
                  color: isDestructive ? Colors.redAccent : null,
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
