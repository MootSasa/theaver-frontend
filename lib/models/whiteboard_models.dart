import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Available tools on the Miro-style Interactive Whiteboard.
enum WhiteboardTool {
  pan,
  select,
  pen,
  highlighter,
  laser,
  sticky,
  rectangle,
  ellipse,
  diamond,
  triangle,
  line,
  arrow,
  text,
  eraser,
}

/// Canvas background grid style.
enum WhiteboardGridStyle {
  dots,
  lines,
  none,
}

/// Resize handle identifier for interactive manipulation in `Select` mode.
enum WhiteboardResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  lineStart,
  lineEnd,
}

/// A single vector or card element on the collaborative whiteboard.
class WhiteboardElement {
  final String id;
  final String
      type; // 'stroke' | 'highlighter' | 'sticky' | 'rectangle' | 'ellipse' | 'diamond' | 'triangle' | 'line' | 'arrow' | 'text'
  final String authorId;
  final String authorName;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<Offset> points;
  final int colorValue;
  final double strokeWidth;
  final String strokeStyle; // 'solid' | 'dashed' | 'dotted'
  final String fillStyle; // 'translucent' | 'solid' | 'none'
  final double fontSize;
  final double opacity;
  final String text;
  final int updatedAt;

  const WhiteboardElement({
    required this.id,
    required this.type,
    required this.authorId,
    required this.authorName,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.points = const [],
    this.colorValue = 0xFF2979FF,
    this.strokeWidth = 4.0,
    this.strokeStyle = 'solid',
    this.fillStyle = 'translucent',
    this.fontSize = 16.0,
    this.opacity = 1.0,
    this.text = '',
    this.updatedAt = 0,
  });

  Color get color => Color(colorValue);

  bool get isStroke => type == 'stroke' || type == 'highlighter';
  bool get isSticky => type == 'sticky';
  bool get isText => type == 'text';
  bool get isLineOrArrow => type == 'arrow' || type == 'line';
  bool get isShape =>
      type == 'rectangle' ||
      type == 'ellipse' ||
      type == 'diamond' ||
      type == 'triangle' ||
      type == 'line' ||
      type == 'arrow';

  /// Normalized bounding box in canvas coordinates.
  Rect get bounds {
    if (isStroke && points.isNotEmpty) {
      double minX = points.first.dx;
      double maxX = points.first.dx;
      double minY = points.first.dy;
      double maxY = points.first.dy;
      for (final p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      final pad = math.max(strokeWidth, 8.0);
      return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    }
    if (isLineOrArrow) {
      final minX = math.min(x, x + width);
      final maxX = math.max(x, x + width);
      final minY = math.min(y, y + height);
      final maxY = math.max(y, y + height);
      return Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);
    }
    final left = width >= 0 ? x : x + width;
    final top = height >= 0 ? y : y + height;
    final w = width.abs().clamp(24.0, 4000.0);
    final h = height.abs().clamp(24.0, 4000.0);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Checks whether a point in canvas coordinates hits one of the resize handles.
  WhiteboardResizeHandle? hitTestHandle(Offset p, {double radius = 14.0}) {
    if (isStroke) return null;
    if (isLineOrArrow) {
      final start = Offset(x, y);
      final end = Offset(x + width, y + height);
      if ((p - start).distance <= radius) {
        return WhiteboardResizeHandle.lineStart;
      }
      if ((p - end).distance <= radius) {
        return WhiteboardResizeHandle.lineEnd;
      }
      return null;
    }
    final inflated = bounds.inflate(6);
    if ((p - inflated.topLeft).distance <= radius) {
      return WhiteboardResizeHandle.topLeft;
    }
    if ((p - inflated.topRight).distance <= radius) {
      return WhiteboardResizeHandle.topRight;
    }
    if ((p - inflated.bottomLeft).distance <= radius) {
      return WhiteboardResizeHandle.bottomLeft;
    }
    if ((p - inflated.bottomRight).distance <= radius) {
      return WhiteboardResizeHandle.bottomRight;
    }
    return null;
  }

  /// Returns a resized copy of this element when dragging `handle` to `scenePoint`.
  WhiteboardElement resizedByHandle(
    WhiteboardResizeHandle handle,
    Offset scenePoint,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (isLineOrArrow) {
      final start = Offset(x, y);
      final end = Offset(x + width, y + height);
      if (handle == WhiteboardResizeHandle.lineStart) {
        return copyWith(
          x: scenePoint.dx,
          y: scenePoint.dy,
          width: end.dx - scenePoint.dx,
          height: end.dy - scenePoint.dy,
          updatedAt: now,
        );
      } else {
        return copyWith(
          width: scenePoint.dx - start.dx,
          height: scenePoint.dy - start.dy,
          updatedAt: now,
        );
      }
    }

    final b = bounds;
    double left = b.left;
    double top = b.top;
    double right = b.right;
    double bottom = b.bottom;
    const minSize = 36.0;

    switch (handle) {
      case WhiteboardResizeHandle.topLeft:
        left = math.min(scenePoint.dx, right - minSize);
        top = math.min(scenePoint.dy, bottom - minSize);
        break;
      case WhiteboardResizeHandle.topRight:
        right = math.max(scenePoint.dx, left + minSize);
        top = math.min(scenePoint.dy, bottom - minSize);
        break;
      case WhiteboardResizeHandle.bottomLeft:
        left = math.min(scenePoint.dx, right - minSize);
        bottom = math.max(scenePoint.dy, top + minSize);
        break;
      case WhiteboardResizeHandle.bottomRight:
        right = math.max(scenePoint.dx, left + minSize);
        bottom = math.max(scenePoint.dy, top + minSize);
        break;
      default:
        break;
    }

    return copyWith(
      x: left,
      y: top,
      width: (right - left).clamp(minSize, 3200.0),
      height: (bottom - top).clamp(minSize, 3200.0),
      updatedAt: now,
    );
  }

  /// Checks whether a point in canvas coordinates hits this element.
  bool containsPoint(Offset p, {double tolerance = 14.0}) {
    if (isStroke) {
      if (!bounds.inflate(tolerance).contains(p)) return false;
      for (int i = 0; i < points.length; i++) {
        if ((points[i] - p).distance <= strokeWidth / 2 + tolerance) {
          return true;
        }
        if (i + 1 < points.length) {
          final d = _distanceToSegment(p, points[i], points[i + 1]);
          if (d <= strokeWidth / 2 + tolerance) return true;
        }
      }
      return false;
    }
    if (isLineOrArrow) {
      final start = Offset(x, y);
      final end = Offset(x + width, y + height);
      return _distanceToSegment(p, start, end) <= tolerance + strokeWidth;
    }
    return bounds.inflate(tolerance * 0.5).contains(p);
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }

  /// Returns a translated copy of this element by `(dx, dy)`.
  WhiteboardElement translated(double dx, double dy) {
    if (isStroke) {
      return copyWith(
        points: points.map((pt) => Offset(pt.dx + dx, pt.dy + dy)).toList(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return copyWith(
      x: x + dx,
      y: y + dy,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  WhiteboardElement copyWith({
    String? id,
    String? type,
    String? authorId,
    String? authorName,
    double? x,
    double? y,
    double? width,
    double? height,
    List<Offset>? points,
    int? colorValue,
    double? strokeWidth,
    String? strokeStyle,
    String? fillStyle,
    double? fontSize,
    double? opacity,
    String? text,
    int? updatedAt,
  }) {
    return WhiteboardElement(
      id: id ?? this.id,
      type: type ?? this.type,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      points: points ?? this.points,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      fillStyle: fillStyle ?? this.fillStyle,
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      text: text ?? this.text,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory WhiteboardElement.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    final parsedPoints = <Offset>[];
    if (rawPoints is List) {
      for (final item in rawPoints) {
        if (item is Map) {
          final px = (item['x'] as num?)?.toDouble() ?? 0.0;
          final py = (item['y'] as num?)?.toDouble() ?? 0.0;
          parsedPoints.add(Offset(px, py));
        } else if (item is List && item.length >= 2) {
          final px = (item[0] as num?)?.toDouble() ?? 0.0;
          final py = (item[1] as num?)?.toDouble() ?? 0.0;
          parsedPoints.add(Offset(px, py));
        }
      }
    }

    return WhiteboardElement(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'stroke').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'Участник').toString(),
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 0.0,
      height: (json['height'] as num?)?.toDouble() ?? 0.0,
      points: parsedPoints,
      colorValue: (json['color'] as num?)?.toInt() ?? 0xFF2979FF,
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 4.0,
      strokeStyle: (json['stroke_style'] ?? 'solid').toString(),
      fillStyle: (json['fill_style'] ?? 'translucent').toString(),
      fontSize: (json['font_size'] as num?)?.toDouble() ?? 16.0,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.1, 1.0),
      text: (json['text'] ?? '').toString(),
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'author_id': authorId,
        'author_name': authorName,
        'x': (x * 10).roundToDouble() / 10,
        'y': (y * 10).roundToDouble() / 10,
        'width': (width * 10).roundToDouble() / 10,
        'height': (height * 10).roundToDouble() / 10,
        if (points.isNotEmpty)
          'points': points
              .map((p) => [
                    (p.dx * 10).roundToDouble() / 10,
                    (p.dy * 10).roundToDouble() / 10,
                  ])
              .toList(),
        'color': colorValue,
        'stroke_width': strokeWidth,
        if (strokeStyle != 'solid') 'stroke_style': strokeStyle,
        if (fillStyle != 'translucent') 'fill_style': fillStyle,
        if (fontSize != 16.0) 'font_size': fontSize,
        if (opacity < 0.99) 'opacity': (opacity * 100).roundToDouble() / 100,
        if (text.isNotEmpty) 'text': text,
        'updated_at': updatedAt,
      };
}

/// Ephemeral laser trail point with timestamp for smooth fade-out.
class LaserTrailPoint {
  final Offset point;
  final int timestampMs;

  const LaserTrailPoint({
    required this.point,
    required this.timestampMs,
  });
}

/// Real-time remote participant cursor & laser pointer state.
class WhiteboardRemoteCursor {
  final String userId;
  final String userName;
  final int colorValue;
  final Offset position;
  final bool isLaser;
  final List<LaserTrailPoint> laserTrail;
  final int lastSeenMs;

  const WhiteboardRemoteCursor({
    required this.userId,
    required this.userName,
    required this.colorValue,
    required this.position,
    this.isLaser = false,
    this.laserTrail = const [],
    required this.lastSeenMs,
  });

  Color get color => Color(colorValue);

  WhiteboardRemoteCursor copyWith({
    String? userName,
    int? colorValue,
    Offset? position,
    bool? isLaser,
    List<LaserTrailPoint>? laserTrail,
    int? lastSeenMs,
  }) {
    return WhiteboardRemoteCursor(
      userId: userId,
      userName: userName ?? this.userName,
      colorValue: colorValue ?? this.colorValue,
      position: position ?? this.position,
      isLaser: isLaser ?? this.isLaser,
      laserTrail: laserTrail ?? this.laserTrail,
      lastSeenMs: lastSeenMs ?? this.lastSeenMs,
    );
  }
}
