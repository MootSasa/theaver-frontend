import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../user/avatar_with_status.dart';

/// Полупрозрачное заблюренное мини-окно (превью чата), в которое плавно сжимается
/// перетаскиваемый тайл или чат при Drag & Drop.
class TileDragPreviewOverlay extends StatelessWidget {
  final DraggingChatPayload payload;

  const TileDragPreviewOverlay({
    super.key,
    required this.payload,
  });

  static const double _kPreviewWidth = 228.0;
  static const double _kPreviewHeight = 276.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final isGlass = glassProvider?.enabled ?? false;

    final cardChild = RepaintBoundary(
      child: _buildMiniWindowCard(
        context: context,
        isDark: isDark,
        primary: primary,
        isGlass: isGlass,
        glassProvider: glassProvider,
      ),
    );

    return ValueListenableBuilder<int>(
      valueListenable: TilingLayoutController.instance.dragFrameNotifier,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (context, t, child) {
          final scale = ui.lerpDouble(1.18, 1.0, t.clamp(0.0, 1.0)) ?? 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: cardChild,
      ),
      builder: (context, _, animatedCard) {
        final cursor = payload.currentGlobalPosition;
        final targetLeft = cursor.dx - _kPreviewWidth / 2;
        final targetTop = cursor.dy - 36.0;
        final tiltAngle = (payload.velocity.dx / 1800.0).clamp(-0.08, 0.08);

        return Positioned(
          left: targetLeft,
          top: targetTop,
          width: _kPreviewWidth,
          height: _kPreviewHeight,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: tiltAngle,
              child: animatedCard,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniWindowCard({
    required BuildContext context,
    required bool isDark,
    required Color primary,
    required bool isGlass,
    required LiquidGlassProvider? glassProvider,
  }) {
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Мини-шапка окна чата (3 капсулы как в FloatingGlassAppBar)
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.07),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.07),
                  ),
                  child: Row(
                    children: [
                      AvatarWithStatus(
                        avatarUrl: payload.avatarUrl,
                        name: payload.chatName,
                        radius: 10,
                        isOnline: false,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          payload.chatName.isNotEmpty ? payload.chatName : 'Чат',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Силуэты пузырей сообщений внутри мини-окна
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSkeletonBubble(
                    width: 128,
                    height: 28,
                    isMe: false,
                    isDark: isDark,
                    primary: primary,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildSkeletonBubble(
                    width: 144,
                    height: 36,
                    isMe: true,
                    isDark: isDark,
                    primary: primary,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSkeletonBubble(
                    width: 104,
                    height: 26,
                    isMe: false,
                    isDark: isDark,
                    primary: primary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // Мини-поле ввода внизу
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            alignment: Alignment.centerLeft,
            child: Container(
              width: 72,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ),
          ),
        ],
      ),
    );

    if (isGlass && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: 24,
        blur: 16.0,
      );
      return LiquidGlassBatch.exclude(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: LiquidGlassLens(
            style: style,
            child: content,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: isDark
                ? const Color(0xCC1E1E24)
                : const Color(0xD9FFFFFF),
            border: Border.all(
              color: primary.withValues(alpha: 0.45),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildSkeletonBubble({
    required double width,
    required double height,
    required bool isMe,
    required bool isDark,
    required Color primary,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isMe
            ? primary.withValues(alpha: isDark ? 0.42 : 0.32)
            : (isDark
                ? Colors.white.withValues(alpha: 0.13)
                : Colors.black.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isMe ? 14 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 14),
        ),
      ),
    );
  }
}

/// Заблюренная зона посадки (`Drop Placeholder`), которая появляется на месте,
/// освобождаемом соседним тайлом в реальном времени при перетаскивании.
class GlassDropPlaceholder extends StatelessWidget {
  final TilingDropSlot slot;
  final String chatName;

  const GlassDropPlaceholder({
    super.key,
    required this.slot,
    required this.chatName,
  });

  String _slotDescription() {
    switch (slot) {
      case TilingDropSlot.left:
        return 'Закрепить слева';
      case TilingDropSlot.right:
        return 'Закрепить справа';
      case TilingDropSlot.top:
        return 'Закрепить сверху';
      case TilingDropSlot.bottom:
        return 'Закрепить снизу';
      case TilingDropSlot.replace:
        return 'Открыть здесь';
    }
  }

  IconData _slotIcon() {
    switch (slot) {
      case TilingDropSlot.left:
        return Icons.vertical_split_rounded;
      case TilingDropSlot.right:
        return Icons.vertical_split_rounded;
      case TilingDropSlot.top:
        return Icons.horizontal_split_rounded;
      case TilingDropSlot.bottom:
        return Icons.horizontal_split_rounded;
      case TilingDropSlot.replace:
        return Icons.open_in_full_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: primary.withValues(alpha: isDark ? 0.16 : 0.12),
              border: Border.all(
                color: primary.withValues(alpha: 0.55),
                width: 1.8,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary.withValues(alpha: 0.22),
                    ),
                    child: Icon(
                      _slotIcon(),
                      size: 24,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _slotDescription(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (chatName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        chatName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
