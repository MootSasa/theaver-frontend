import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Computes Telegram-style cluster corner radii for a message bubble or album.
///
/// External corners use [outerRadius] (`16dp` by default). On the author's side
/// (`right` when [isMe] is true, `left` otherwise), internal stacked corners
/// shrink to [innerRadius] (`6dp`), and the bottom author corner shrinks to
/// [tailCornerRadius] (`4dp`) when [isLastInCluster] and [hasTail] are true.
BorderRadius computeClusterBubbleBorderRadius({
  required bool isMe,
  required bool isFirstInCluster,
  required bool isLastInCluster,
  double outerRadius = 16.0,
  double innerRadius = 6.0,
  double tailCornerRadius = 4.0,
  bool hasTail = true,
}) {
  final double effOuter = math.max(0.0, outerRadius);
  final double effInner = math.min(effOuter, math.max(0.0, innerRadius));
  final double effTail = math.min(effInner, math.max(0.0, tailCornerRadius));

  final Radius outer = Radius.circular(effOuter);
  final Radius topAuthor = Radius.circular(isFirstInCluster ? effOuter : effInner);
  final Radius bottomAuthor = Radius.circular(
    isLastInCluster ? (hasTail ? effTail : effOuter) : effInner,
  );

  if (isMe) {
    return BorderRadius.only(
      topLeft: outer,
      bottomLeft: outer,
      topRight: topAuthor,
      bottomRight: bottomAuthor,
    );
  }
  return BorderRadius.only(
    topRight: outer,
    bottomRight: outer,
    topLeft: topAuthor,
    bottomLeft: bottomAuthor,
  );
}

/// Vector [CustomPainter] that draws a Telegram-style curved message tail on
/// the bottom author corner of the last bubble in a cluster.
///
/// Designed for a `10 x 16` box positioned `6dp` outside the bubble's author
/// edge (`right: -6.0` for outgoing, `left: -6.0` for incoming) at `bottom: 0.0`.
class BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isMe;
  final double cornerRadius;

  static const Size defaultSize = Size(10.0, 16.0);
  static const double horizontalOutset = 6.0;

  const BubbleTailPainter({
    required this.color,
    required this.isMe,
    this.cornerRadius = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0.0 || size.width <= 0 || size.height <= 0) return;

    canvas.save();
    if (!isMe) {
      canvas.translate(size.width, 0.0);
      canvas.scale(-1.0, 1.0);
    }

    final double sx = size.width / defaultSize.width;
    final double sy = size.height / defaultSize.height;
    canvas.scale(sx, sy);

    const double bodyX = 4.0;
    final double r = cornerRadius.clamp(0.0, 4.0);
    final bool isOpaque = color.a >= 0.99;

    final Path path = Path()
      ..moveTo(bodyX, 3.0)
      ..cubicTo(bodyX, 9.2, 5.8, 13.0, 9.25, 14.55)
      ..cubicTo(10.1, 14.95, 9.85, 16.0, 8.95, 16.0)
      ..lineTo(0.0, 16.0);

    if (isOpaque) {
      // Slight overlap behind opaque bubbles eliminates subpixel seams on
      // fractional DPR displays.
      path
        ..lineTo(0.0, 11.5)
        ..lineTo(bodyX - 0.8, 3.0);
    } else {
      // Match the outer corner fillet exactly for translucent bubbles so there
      // is no double-alpha overlap.
      if (r > 0.0) {
        path.arcToPoint(
          Offset(bodyX, 16.0 - r),
          radius: Radius.circular(r),
          clockwise: false,
        );
      }
      path.lineTo(bodyX, 3.0);
    }
    path.close();

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isMe != isMe ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}
