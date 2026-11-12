import 'package:flutter/material.dart';
import '../../services/deep_link_service.dart';

/// Баннер информирования о синхронизации, появляющийся внизу экрана.
///
/// Показывается поверх контента через корневой [Overlay], автоматически
/// скрывается по истечении [duration] или по нажатию на крестик.
class SyncBanner {
  SyncBanner._();

  static OverlayEntry? _activeOverlay;

  /// Показывает баннер синхронизации внизу экрана.
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    Duration duration = const Duration(seconds: 5),
  }) {
    final overlayState = DeepLinkService().navigatorKey.currentState?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _activeOverlay?.remove();
    _activeOverlay = null;

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
            child: _SyncBannerWidget(
              title: title,
              message: message,
              duration: duration,
              onDismiss: () {
                overlayEntry.remove();
                if (_activeOverlay == overlayEntry) {
                  _activeOverlay = null;
                }
              },
            ),
          ),
        );
      },
    );

    _activeOverlay = overlayEntry;
    overlayState.insert(overlayEntry);
  }
}

class _SyncBannerWidget extends StatefulWidget {
  final String title;
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;

  const _SyncBannerWidget({
    required this.title,
    required this.message,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_SyncBannerWidget> createState() => _SyncBannerWidgetState();
}

class _SyncBannerWidgetState extends State<_SyncBannerWidget>
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
    const secondaryTextColor = Color(0xFF8E8E93);

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
                      style: const TextStyle(
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
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
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
