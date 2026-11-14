import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/profile_customization.dart';
import '../chat/sticker_item_widget.dart';
import '../common/glass_modal_sheet.dart';

/// Displays a user's active emoji status (Unicode or custom animated sticker emoji)
/// next to their display name and automatically hides itself when [status.expiresAt] elapses.
class EmojiStatusBadge extends StatefulWidget {
  final EmojiStatusData? status;
  final double size;
  final bool animate;
  final bool interactive;
  final Color? fallbackColor;

  const EmojiStatusBadge({
    super.key,
    required this.status,
    this.size = 18.0,
    this.animate = true,
    this.interactive = true,
    this.fallbackColor,
  });

  @override
  State<EmojiStatusBadge> createState() => _EmojiStatusBadgeState();
}

class _EmojiStatusBadgeState extends State<EmojiStatusBadge> {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _scheduleExpiryTimer();
  }

  @override
  void didUpdateWidget(covariant EmojiStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _scheduleExpiryTimer();
    }
  }

  void _scheduleExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;

    final expiresAt = widget.status?.expiresAt;
    if (expiresAt == null) return;

    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return;

    // Clamp overly long waits (e.g. >7 days) so Dart Timer duration limits never overflow.
    const maxStep = Duration(days: 7);
    final wait = remaining > maxStep
        ? maxStep
        : remaining + const Duration(milliseconds: 50);

    _expiryTimer = Timer(wait, () {
      if (!mounted) return;
      if (widget.status?.isExpired ?? true) {
        setState(() {});
      } else {
        _scheduleExpiryTimer();
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.status?.activeOrNull;
    if (active == null) return const SizedBox.shrink();

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldAnimate = widget.animate &&
        !reduceMotion &&
        !Scrollable.recommendDeferredLoadingForContext(context);

    Widget glyph;
    if (active.type == 'sticker' && (active.stickerUrl?.isNotEmpty ?? false)) {
      glyph = StickerMediaView(
        fileUrl: active.stickerUrl!,
        thumbnailUrl: active.thumbnailUrl,
        stickerId: active.stickerId,
        format: active.stickerFormat ?? 'webp',
        width: widget.size,
        height: widget.size,
        animate: shouldAnimate,
        adaptiveTintColor: widget.fallbackColor,
        fit: BoxFit.contain,
      );
    } else if (active.emoji != null && active.emoji!.isNotEmpty) {
      glyph = Text(
        active.emoji!,
        style: TextStyle(
          fontSize: widget.size * 0.88,
          height: 1.05,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }

    final badgeBox = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(child: glyph),
    );

    if (!widget.interactive) {
      return badgeBox;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showEmojiStatusDetailSheet(context, active),
      child: badgeBox,
    );
  }
}

/// Opens a Material 3 + Liquid Glass modal sheet showing full details for an emoji status.
Future<void> showEmojiStatusDetailSheet(
  BuildContext context,
  EmojiStatusData status,
) {
  final active = status.activeOrNull;
  if (active == null) return Future.value();

  return showTheavGlassModalSheet<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final title = translateOrFallback(ctx, 'emojiStatusTitle', 'Emoji Status');
      final expiresLabel = active.expiresAt != null
          ? translateOrFallback(
              ctx,
              'emojiStatusExpiresIn',
              'Expires in {time}',
              {'time': _formatRemaining(ctx, active.expiresAt!)},
            )
          : translateOrFallback(ctx, 'emojiStatusExpiryNever', 'Forever');

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmojiStatusBadge(
            status: active,
            size: 52,
            animate: true,
            interactive: false,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          if (active.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                active.note,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            expiresLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    },
  );
}

String _formatRemaining(BuildContext context, DateTime expiresAtUtc) {
  final diff = expiresAtUtc.difference(DateTime.now().toUtc());
  if (diff <= Duration.zero) {
    return '0m';
  }
  if (diff.inDays >= 1) {
    final local = expiresAtUtc.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }
  if (diff.inHours >= 1) {
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
  final mins = diff.inMinutes.clamp(1, 59);
  return '${mins}m';
}
