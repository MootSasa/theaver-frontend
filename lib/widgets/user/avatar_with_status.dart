import 'package:flutter/material.dart';
import '../../models/theav_theme.dart';
import '../../utils/image_utils.dart';

/// A widget that displays a user avatar with an online status indicator.
/// Shows an online status circle in the bottom-right corner when the user is online.
class AvatarWithStatus extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final double radius;
  final bool isOnline;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const AvatarWithStatus({
    Key? key,
    required this.avatarUrl,
    required this.name,
    this.radius = 22,
    this.isOnline = false,
    this.backgroundColor,
    this.onTap,
  }) : super(key: key);

  @override
  State<AvatarWithStatus> createState() => _AvatarWithStatusState();
}

class _AvatarWithStatusState extends State<AvatarWithStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.isOnline ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant AvatarWithStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOnline != widget.isOnline) {
      if (widget.isOnline) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = avatarImageProvider(widget.avatarUrl);
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final bgColor = widget.backgroundColor ??
        themeExt?.palette.primary ??
        const Color(0xFF0088CC);
    final textColor = themeExt?.palette.onPrimary ?? Colors.white;
    final onlineColor =
        themeExt?.palette.onlineIndicator ?? const Color(0xFF4CAF50);

    final size = widget.radius * 2;

    final avatar = SizedBox(
      width: size,
      height: size,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: bgColor,
        backgroundImage: provider,
        onBackgroundImageError: provider != null ? (_, __) {} : null,
        child: provider == null
            ? Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: textColor,
                  fontSize: widget.radius * 0.8,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
    );

    Widget content = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final progress = _animation.value;
          if (progress <= 0.0) {
            return avatar;
          }

          final indicatorDiameter = (widget.radius * 0.55).clamp(8.0, 16.0);
          final indicatorRadius = indicatorDiameter / 2;
          final gap = (indicatorDiameter * 0.2).clamp(1.8, 2.8);
          final indicatorCenter =
              Offset(size - indicatorRadius, size - indicatorRadius);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipPath(
                clipper: _AvatarCutoutClipper(
                  center: indicatorCenter,
                  cutoutRadius: (indicatorRadius + gap) * progress,
                ),
                child: avatar,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Transform.scale(
                  scale: progress,
                  alignment: Alignment.center,
                  child: Container(
                    width: indicatorDiameter,
                    height: indicatorDiameter,
                    decoration: BoxDecoration(
                      color: onlineColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: widget.onTap,
        child: content,
      );
    }

    return content;
  }
}

class _AvatarCutoutClipper extends CustomClipper<Path> {
  final Offset center;
  final double cutoutRadius;

  const _AvatarCutoutClipper({
    required this.center,
    required this.cutoutRadius,
  });

  @override
  Path getClip(Size size) {
    final avatarPath = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    if (cutoutRadius <= 0) return avatarPath;

    final cutoutPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: cutoutRadius));
    return Path.combine(PathOperation.difference, avatarPath, cutoutPath);
  }

  @override
  bool shouldReclip(covariant _AvatarCutoutClipper oldClipper) {
    return oldClipper.center != center || oldClipper.cutoutRadius != cutoutRadius;
  }
}
