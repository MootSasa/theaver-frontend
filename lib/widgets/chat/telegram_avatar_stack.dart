import 'package:flutter/material.dart';
import '../../utils/image_utils.dart';

/// Telegram-style overlapping avatar stack using true boolean crescent cutouts
/// (`PathOperation.difference`) so the gap between avatars is genuinely
/// transparent rather than painted with a solid border color.
class TelegramAvatarStack extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final int maxCount;
  final double size;
  final double? step;
  final double gap;

  const TelegramAvatarStack({
    Key? key,
    required this.users,
    this.maxCount = 3,
    this.size = 22.0,
    this.step,
    this.gap = 2.0,
  }) : super(key: key);

  static const List<Color> _fallbackColors = [
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];

  @override
  Widget build(BuildContext context) {
    final displayUsers = users.take(maxCount).toList();
    if (displayUsers.isEmpty) return const SizedBox.shrink();

    final double effectiveStep = step ?? (size * 0.6363636);
    final double totalWidth =
        size + (displayUsers.length - 1) * effectiveStep;

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = displayUsers.length - 1; i >= 0; i--)
            Positioned(
              left: i * effectiveStep,
              top: 0,
              child: ClipPath(
                clipper: _TelegramAvatarCrescentClipper(
                  hasLeftNeighbor: i > 0,
                  step: effectiveStep,
                  gap: gap,
                ),
                child: _buildSingleAvatar(displayUsers[i], i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleAvatar(Map<String, dynamic> user, int index) {
    final rawAvatar = user['avatar_url']?.toString();
    final validAvatar = getValidAvatarUrl(rawAvatar);
    final imgProvider =
        validAvatar != null ? avatarImageProvider(validAvatar) : null;
    final name = (user['display_name'] ?? user['username'] ?? '?')
        .toString()
        .trim();
    final initial =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final uidHash = (user['user_id'] ?? user['id'] ?? index).hashCode.abs();
    final fallbackColor = _fallbackColors[uidHash % _fallbackColors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor,
        image: imgProvider != null
            ? DecorationImage(
                image: imgProvider,
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: imgProvider == null
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.46,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            )
          : null,
    );
  }
}

class _TelegramAvatarCrescentClipper extends CustomClipper<Path> {
  final bool hasLeftNeighbor;
  final double step;
  final double gap;

  const _TelegramAvatarCrescentClipper({
    required this.hasLeftNeighbor,
    required this.step,
    this.gap = 2.0,
  });

  @override
  Path getClip(Size size) {
    final double r = size.width / 2.0;
    final Offset center = Offset(r, r);
    final Path ownCircle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: r));

    if (!hasLeftNeighbor) {
      return ownCircle;
    }

    final Path leftCutout = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(r - step, r),
          radius: r + gap,
        ),
      );

    return Path.combine(PathOperation.difference, ownCircle, leftCutout);
  }

  @override
  bool shouldReclip(covariant _TelegramAvatarCrescentClipper oldClipper) {
    return oldClipper.hasLeftNeighbor != hasLeftNeighbor ||
        oldClipper.step != step ||
        oldClipper.gap != gap;
  }
}
