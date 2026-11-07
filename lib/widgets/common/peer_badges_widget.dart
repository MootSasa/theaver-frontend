import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

/// Renders inline peer badges (`BOT` capsule badge and `Verified` check badge)
/// next to a user, bot, group, or channel name.
class PeerBadgesRow extends StatelessWidget {
  final bool isBot;
  final bool isVerified;
  final double iconSize;
  final double? verifiedIconSize;
  final Color? accentColor;

  const PeerBadgesRow({
    Key? key,
    this.isBot = false,
    this.isVerified = false,
    this.iconSize = 15.0,
    this.verifiedIconSize,
    this.accentColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isBot && !isVerified) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = accentColor ??
        (isDark ? const Color(0xFF5CB8E6) : const Color(0xFF0088CC));
    final effectiveVerifiedSize = verifiedIconSize ?? iconSize;

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
        if (isBot) ...[
          const SizedBox(width: 5),
          Container(
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.45),
                width: 0.6,
              ),
            ),
            child: Center(
              widthFactor: 1.0,
              child: Text(
                'BOT',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  height: 1.0,
                  color: primaryColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
