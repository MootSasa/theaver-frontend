import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../models/profile_customization.dart';
import 'glass_modal_sheet.dart';

/// Renders inline peer badges (`BOT` capsule, single role/achievement capsule, and `Verified` check)
/// next to a user, bot, group, or channel name.
///
/// Single-badge rule: when [isBot] is true, only `BOT` is rendered (never [badge]).
class PeerBadgesRow extends StatelessWidget {
  final bool isBot;
  final bool isVerified;
  final double iconSize;
  final double? verifiedIconSize;
  final Color? accentColor;
  final UserBadge? badge;
  final bool interactiveBadge;

  const PeerBadgesRow({
    Key? key,
    this.isBot = false,
    this.isVerified = false,
    this.iconSize = 15.0,
    this.verifiedIconSize,
    this.accentColor,
    this.badge,
    this.interactiveBadge = true,
  }) : super(key: key);

  /// Shared capsule pill builder used for both `BOT` and single role badges (`CREATOR`, `DEV`, etc.).
  static Widget buildCapsule({
    required String label,
    required Color color,
    required bool isDark,
    double scale = 1.0,
  }) {
    return Container(
      height: 16 * scale,
      padding: EdgeInsets.symmetric(
        horizontal: 5 * scale,
        vertical: 1 * scale,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(5 * scale),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
          width: (0.6 * scale).clamp(0.6, 1.4),
        ),
      ),
      child: Center(
        widthFactor: 1.0,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4 * scale,
            height: 1.0,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBadge = isBot ? null : badge;
    if (!isBot && !isVerified && effectiveBadge == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = accentColor ??
        (isDark ? const Color(0xFF5CB8E6) : const Color(0xFF0088CC));
    final effectiveVerifiedSize = verifiedIconSize ?? iconSize;

    Widget? capsuleWidget;
    if (isBot) {
      capsuleWidget = buildCapsule(
        label: 'BOT',
        color: primaryColor,
        isDark: isDark,
      );
    } else if (effectiveBadge != null) {
      final rawCapsule = buildCapsule(
        label: effectiveBadge.shortTag,
        color: effectiveBadge.accentColor,
        isDark: isDark,
      );
      capsuleWidget = interactiveBadge
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showBadgeDetailSheet(context, effectiveBadge),
              child: rawCapsule,
            )
          : rawCapsule;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVerified) ...[
          const SizedBox(width: 4),
          iconoir.BadgeCheck(
            width: effectiveVerifiedSize,
            height: effectiveVerifiedSize,
            color: primaryColor,
          ),
        ],
        if (capsuleWidget != null) ...[
          const SizedBox(width: 5),
          capsuleWidget,
        ],
      ],
    );
  }
}

/// Opens a Material 3 + Liquid Glass modal sheet explaining a single user role badge.
Future<void> showBadgeDetailSheet(BuildContext context, UserBadge badge) {
  return showTheavGlassModalSheet<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;
      final title = translateOrFallback(ctx, badge.nameKey, badge.shortTag);
      final desc = translateOrFallback(ctx, badge.descKey, '');

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PeerBadgesRow.buildCapsule(
            label: badge.shortTag,
            color: badge.accentColor,
            isDark: isDark,
            scale: 1.75,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              desc,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (badge.grantedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              translateOrFallback(
                ctx,
                'badgeGrantedAt',
                'Granted: {date}',
                {
                  'date': _formatBadgeDate(badge.grantedAt!.toLocal()),
                },
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    },
  );
}

String _formatBadgeDate(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString().padLeft(4, '0');
  return '$d.$m.$y';
}
