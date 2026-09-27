import '../../utils/image_utils.dart';
import 'package:flutter/material.dart';
import '../../services/liquid_glass_provider.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Модель данных для in-app баннера уведомления
class InAppNotificationData {
  final String chatId;
  final String chatName;
  final String senderName;
  final String messageText;
  final String? avatarUrl;
  final bool isGroup;
  final DateTime timestamp;

  const InAppNotificationData({
    required this.chatId,
    required this.chatName,
    required this.senderName,
    required this.messageText,
    this.avatarUrl,
    this.isGroup = false,
    required this.timestamp,
  });
}

/// In-App баннер уведомления, отображаемый поверх контента.
///
/// Вверху экрана появляется карточка с аватаром и текстом.
/// Поддерживает Liquid Glass и Classic режимы.
/// Автоматически скрывается через 4 секунды.
/// Свайп вверх для закрытия.
/// Нажатие → переход к чату.
class InAppNotificationBanner extends StatefulWidget {
  final InAppNotificationData data;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const InAppNotificationBanner({
    Key? key,
    required this.data,
    this.onTap,
    this.onDismiss,
  }) : super(key: key);

  /// Показывает баннер нового сообщения вверху экрана
  static OverlayEntry? _activeTopBannerOverlay;

  static void showTopBanner(
    BuildContext context, {
    required InAppNotificationData data,
    VoidCallback? onTap,
    VoidCallback? onDismiss,
  }) {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _activeTopBannerOverlay?.remove();
    _activeTopBannerOverlay = null;

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return Positioned(
          top: 10 + mediaQuery.padding.top,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: InAppNotificationBanner(
              data: data,
              onTap: () {
                overlayEntry.remove();
                if (_activeTopBannerOverlay == overlayEntry) {
                  _activeTopBannerOverlay = null;
                }
                onTap?.call();
              },
              onDismiss: () {
                overlayEntry.remove();
                if (_activeTopBannerOverlay == overlayEntry) {
                  _activeTopBannerOverlay = null;
                }
                onDismiss?.call();
              },
            ),
          ),
        );
      },
    );

    _activeTopBannerOverlay = overlayEntry;
    overlayState.insert(overlayEntry);
  }

  static void dismissTopBanner() {
    _activeTopBannerOverlay?.remove();
    _activeTopBannerOverlay = null;
  }

  /// Показывает баннер информирования о синхронизации внизу экрана
  static OverlayEntry? _activeBottomSyncOverlay;

  static void showBottomSyncBanner(
    BuildContext context, {
    required String title,
    required String message,
    Duration duration = const Duration(seconds: 5),
  }) {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _activeBottomSyncOverlay?.remove();
    _activeBottomSyncOverlay = null;

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return Positioned(
          left: 16,
          right: 16,
          bottom: 20 + mediaQuery.padding.bottom,
          child: Material(
            color: Colors.transparent,
            child: _BottomSyncBannerWidget(
              title: title,
              message: message,
              duration: duration,
              onDismiss: () {
                overlayEntry.remove();
                if (_activeBottomSyncOverlay == overlayEntry) {
                  _activeBottomSyncOverlay = null;
                }
              },
            ),
          ),
        );
      },
    );

    _activeBottomSyncOverlay = overlayEntry;
    overlayState.insert(overlayEntry);
  }

  @override
  State<InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;

  double _swipeOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Анимация появления
    _controller.forward();

    // Автоскрытие через 4 секунды
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  void _handleTap() {
    widget.onTap?.call();
    _dismiss();
  }

  void _handleSwipeUpdate(DragUpdateDetails details) {
    setState(() {
      _swipeOffset += details.delta.dy;
      if (_swipeOffset > 0) _swipeOffset = 0; // Только вверх
    });
  }

  void _handleSwipeEnd(DragEndDetails details) {
    if (_swipeOffset < -50) {
      _dismiss();
    } else {
      setState(() {
        _swipeOffset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        return GestureDetector(
          onVerticalDragUpdate: _handleSwipeUpdate,
          onVerticalDragEnd: _handleSwipeEnd,
          onTap: _handleTap,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final yOffset = _slideAnimation.value * 80 + _swipeOffset;
              return Transform.translate(
                offset: Offset(0, yOffset),
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: child,
                ),
              );
            },
            child: glassProvider.enabled
                ? _buildGlassBanner(context)
                : _buildClassicBanner(context),
          ),
        );
      },
    );
  }

  Widget _buildGlassBanner(BuildContext context) {
    return LiquidGlass.withOwnLayer(
      settings: const LiquidGlassSettings(
        thickness: 15,
        blur: 10,
        refractiveIndex: 1.15,
      ),
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: _buildBannerContent(context),
      ),
    );
  }

  Widget _buildClassicBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _buildBannerContent(context),
    );
  }

  Widget _buildBannerContent(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // Аватар
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFF0088CC),
          backgroundImage: avatarImageProvider(widget.data.avatarUrl),
          onBackgroundImageError: (_, __) {},
          child: widget.data.avatarUrl == null
              ? Text(
                  widget.data.chatName.isNotEmpty
                      ? widget.data.chatName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                )
              : null,
        ),
        const SizedBox(width: 12),

        // Текст
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.data.chatName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatTime(widget.data.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.data.isGroup
                    ? '${widget.data.senderName}: ${widget.data.messageText}'
                    : widget.data.messageText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Кнопка закрытия
        GestureDetector(
          onTap: () {
            _dismiss();
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.close, size: 18, color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _BottomSyncBannerWidget extends StatefulWidget {
  final String title;
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;

  const _BottomSyncBannerWidget({
    Key? key,
    required this.title,
    required this.message,
    required this.duration,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<_BottomSyncBannerWidget> createState() => _BottomSyncBannerWidgetState();
}

class _BottomSyncBannerWidgetState extends State<_BottomSyncBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E272E) : Colors.white;
    final primaryTextColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93);

    return SlideTransition(
      position: _offsetAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0088CC).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: Color(0xFF0088CC),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.message,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _dismiss,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: secondaryTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
