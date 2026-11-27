import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/image_utils.dart' show AvatarCropSpec;

/// Target visual mask shape used for previewing avatar framing.
enum AvatarShapeMask {
  circle,
  squircle,
}

extension AvatarShapeMaskX on AvatarShapeMask {
  /// Returns the rounded rectangle matching the avatar shape inside [rect].
  ///
  /// Communities use a continuous `0.30` corner radius fraction (`size * 0.30`).
  RRect shapeRRect(Rect rect) {
    final double minSide = math.min(rect.width, rect.height);
    switch (this) {
      case AvatarShapeMask.circle:
        return RRect.fromRectXY(rect, rect.width * 0.5, rect.height * 0.5);
      case AvatarShapeMask.squircle:
        return RRect.fromRectAndRadius(
          rect,
          Radius.circular(minSide * 0.30),
        );
    }
  }

  /// Returns a [Path] representing the avatar silhouette inside [rect].
  Path shapePath(Rect rect) => Path()..addRRect(shapeRRect(rect));

  /// Returns a [BorderRadius] matching [size] for UI clip widgets.
  BorderRadius borderRadiusForSize(double size) {
    switch (this) {
      case AvatarShapeMask.circle:
        return BorderRadius.circular(size * 0.5);
      case AvatarShapeMask.squircle:
        return BorderRadius.circular(size * 0.30);
    }
  }
}

/// Crop framing aspect ratio mode in the avatar studio.
enum AvatarCropAspectMode {
  square1x1,
  original,
  free,
}

/// Primary confirmation CTA label mode for the avatar studio.
enum AvatarEditorCtaMode {
  done,
  setPhoto,
  suggestPhoto,
}

/// Active tool tab in [TheavAvatarEditorScreen].
enum AvatarEditorTab {
  crop,
  adjust,
  stickers,
  markup,
}

/// Brush rendering style in the markup tool.
enum AvatarBrushStyle {
  pen,
  neon,
  highlighter,
}

/// Backdrop pill style for text overlay layers.
enum AvatarTextBackgroundMode {
  none,
  solid,
  translucent,
}

/// Color adjustment attributes editable in the Adjust tab.
enum AvatarAdjustmentAttribute {
  exposure,
  contrast,
  saturation,
  warmth,
  vignette,
  sharpen,
}

/// Final result returned by [TheavAvatarPickerSheet] and [TheavAvatarEditorScreen].
@immutable
class AvatarPickResult {
  final File? file;
  final Uint8List? bytes;
  final String fileName;
  final bool deletedCurrent;
  final AvatarShapeMask maskShape;
  final AvatarCropAspectMode aspectMode;
  final bool isFromConstructor;
  final AvatarCropSpec? miniCrop;
  final Uint8List? previewBytes;

  const AvatarPickResult({
    this.file,
    this.bytes,
    this.fileName = 'avatar.jpg',
    this.deletedCurrent = false,
    this.maskShape = AvatarShapeMask.circle,
    this.aspectMode = AvatarCropAspectMode.square1x1,
    this.isFromConstructor = false,
    this.miniCrop,
    this.previewBytes,
  });

  const AvatarPickResult.deleted({
    this.maskShape = AvatarShapeMask.circle,
  })  : file = null,
        bytes = null,
        fileName = '',
        deletedCurrent = true,
        aspectMode = AvatarCropAspectMode.square1x1,
        isFromConstructor = false,
        miniCrop = null,
        previewBytes = null;

  Uint8List? get effectivePreviewBytes => previewBytes ?? bytes;

  bool get hasMedia =>
      !deletedCurrent &&
      (file != null || (bytes != null && bytes!.isNotEmpty));
}

/// Non-destructive color grading & vignette adjustments.
@immutable
class AvatarColorAdjustments {
  final double exposure;
  final double contrast;
  final double saturation;
  final double warmth;
  final double vignette;
  final double sharpen;
  final String presetId;

  const AvatarColorAdjustments({
    this.exposure = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.warmth = 0.0,
    this.vignette = 0.0,
    this.sharpen = 0.0,
    this.presetId = 'original',
  });

  bool get isIdentity =>
      exposure.abs() <= 1e-4 &&
      contrast.abs() <= 1e-4 &&
      saturation.abs() <= 1e-4 &&
      warmth.abs() <= 1e-4 &&
      vignette.abs() <= 1e-4 &&
      sharpen.abs() <= 1e-4;

  /// Whether the 4x5 color matrix differs from identity.
  bool get hasColorMatrixEffect =>
      exposure.abs() > 1e-4 ||
      contrast.abs() > 1e-4 ||
      saturation.abs() > 1e-4 ||
      warmth.abs() > 1e-4 ||
      sharpen.abs() > 1e-4;

  AvatarColorAdjustments copyWith({
    double? exposure,
    double? contrast,
    double? saturation,
    double? warmth,
    double? vignette,
    double? sharpen,
    String? presetId,
  }) {
    return AvatarColorAdjustments(
      exposure: (exposure ?? this.exposure).clamp(-1.0, 1.0).toDouble(),
      contrast: (contrast ?? this.contrast).clamp(-1.0, 1.0).toDouble(),
      saturation: (saturation ?? this.saturation).clamp(-1.0, 1.0).toDouble(),
      warmth: (warmth ?? this.warmth).clamp(-1.0, 1.0).toDouble(),
      vignette: (vignette ?? this.vignette).clamp(0.0, 1.0).toDouble(),
      sharpen: (sharpen ?? this.sharpen).clamp(0.0, 1.0).toDouble(),
      presetId: presetId ?? this.presetId,
    );
  }

  /// Computes a 20-element row-major 4x5 color matrix for [ColorFilter.matrix].
  List<double> toColorMatrix() {
    if (!hasColorMatrixEffect) {
      return const <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
    }

    // Saturation matrix (Rec.709 luminance weights).
    final double sat = (1.0 + saturation).clamp(0.0, 2.0).toDouble();
    final double invSat = 1.0 - sat;
    final double rLum = 0.2126 * invSat;
    final double gLum = 0.7152 * invSat;
    final double bLum = 0.0722 * invSat;

    final double sr0 = rLum + sat;
    final double sr1 = gLum;
    final double sr2 = bLum;

    final double sg0 = rLum;
    final double sg1 = gLum + sat;
    final double sg2 = bLum;

    final double sb0 = rLum;
    final double sb1 = gLum;
    final double sb2 = bLum + sat;

    // Contrast + clarity boost from sharpen + exposure gain/offset.
    final double c =
        (1.0 + contrast * 0.72) * (1.0 + sharpen * 0.14);
    final double expScale = math.pow(2.0, exposure * 0.85).toDouble();
    final double gain = c * expScale;
    final double baseBias = 128.0 * (1.0 - c) + exposure * 28.0;

    // Warmth shifts R/B balance and subtle warmth bias.
    final double w = warmth.clamp(-1.0, 1.0).toDouble();
    final double rScale = gain * (1.0 + 0.14 * w);
    final double gScale = gain * (1.0 + 0.02 * w);
    final double bScale = gain * (1.0 - 0.14 * w);

    final double rBias = baseBias + 10.0 * w;
    final double gBias = baseBias + 1.5 * w;
    final double bBias = baseBias - 10.0 * w;

    return <double>[
      sr0 * rScale, sr1 * rScale, sr2 * rScale, 0, rBias,
      sg0 * gScale, sg1 * gScale, sg2 * gScale, 0, gBias,
      sb0 * bScale, sb1 * bScale, sb2 * bScale, 0, bBias,
      0, 0, 0, 1, 0,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarColorAdjustments &&
          runtimeType == other.runtimeType &&
          exposure == other.exposure &&
          contrast == other.contrast &&
          saturation == other.saturation &&
          warmth == other.warmth &&
          vignette == other.vignette &&
          sharpen == other.sharpen &&
          presetId == other.presetId;

  @override
  int get hashCode => Object.hash(
        exposure,
        contrast,
        saturation,
        warmth,
        vignette,
        sharpen,
        presetId,
      );
}

/// Built-in filter preset descriptor.
@immutable
class AvatarFilterPreset {
  final String id;
  final String labelKey;
  final String fallbackLabel;
  final AvatarColorAdjustments adjustments;

  const AvatarFilterPreset({
    required this.id,
    required this.labelKey,
    required this.fallbackLabel,
    required this.adjustments,
  });

  static const List<AvatarFilterPreset> presets = <AvatarFilterPreset>[
    AvatarFilterPreset(
      id: 'original',
      labelKey: 'avatar_editor_preset_original',
      fallbackLabel: 'Оригинал',
      adjustments: AvatarColorAdjustments(presetId: 'original'),
    ),
    AvatarFilterPreset(
      id: 'vivid',
      labelKey: 'avatar_editor_preset_vivid',
      fallbackLabel: 'Яркий',
      adjustments: AvatarColorAdjustments(
        exposure: 0.06,
        contrast: 0.16,
        saturation: 0.34,
        sharpen: 0.18,
        presetId: 'vivid',
      ),
    ),
    AvatarFilterPreset(
      id: 'warm',
      labelKey: 'avatar_editor_preset_warm',
      fallbackLabel: 'Тёплый',
      adjustments: AvatarColorAdjustments(
        warmth: 0.36,
        contrast: 0.06,
        saturation: 0.10,
        presetId: 'warm',
      ),
    ),
    AvatarFilterPreset(
      id: 'cool',
      labelKey: 'avatar_editor_preset_cool',
      fallbackLabel: 'Холодный',
      adjustments: AvatarColorAdjustments(
        warmth: -0.36,
        contrast: 0.08,
        saturation: -0.05,
        presetId: 'cool',
      ),
    ),
    AvatarFilterPreset(
      id: 'portrait',
      labelKey: 'avatar_editor_preset_portrait',
      fallbackLabel: 'Портрет',
      adjustments: AvatarColorAdjustments(
        exposure: 0.10,
        contrast: -0.04,
        saturation: 0.06,
        warmth: 0.12,
        vignette: 0.18,
        presetId: 'portrait',
      ),
    ),
    AvatarFilterPreset(
      id: 'drama',
      labelKey: 'avatar_editor_preset_drama',
      fallbackLabel: 'Драма',
      adjustments: AvatarColorAdjustments(
        exposure: -0.05,
        contrast: 0.34,
        saturation: -0.22,
        vignette: 0.38,
        sharpen: 0.20,
        presetId: 'drama',
      ),
    ),
    AvatarFilterPreset(
      id: 'mono',
      labelKey: 'avatar_editor_preset_mono',
      fallbackLabel: 'Ч/Б',
      adjustments: AvatarColorAdjustments(
        saturation: -1.0,
        contrast: 0.18,
        vignette: 0.20,
        presetId: 'mono',
      ),
    ),
    AvatarFilterPreset(
      id: 'cinema',
      labelKey: 'avatar_editor_preset_cinema',
      fallbackLabel: 'Кино',
      adjustments: AvatarColorAdjustments(
        exposure: -0.04,
        contrast: 0.22,
        saturation: -0.14,
        warmth: 0.14,
        vignette: 0.32,
        presetId: 'cinema',
      ),
    ),
  ];
}

/// Freehand brush stroke normalized in `[0..1] x [0..1]` crop viewport space.
@immutable
class AvatarBrushStroke {
  final String id;
  final List<Offset> points;
  final Color color;
  final double strokeWidthFraction;
  final AvatarBrushStyle style;

  const AvatarBrushStroke({
    this.id = '',
    required this.points,
    required this.color,
    this.strokeWidthFraction = 0.018,
    this.style = AvatarBrushStyle.pen,
  });

  AvatarBrushStroke copyWith({
    String? id,
    List<Offset>? points,
    Color? color,
    double? strokeWidthFraction,
    AvatarBrushStyle? style,
  }) {
    return AvatarBrushStroke(
      id: id ?? this.id,
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidthFraction: strokeWidthFraction ?? this.strokeWidthFraction,
      style: style ?? this.style,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AvatarBrushStroke ||
        id != other.id ||
        color != other.color ||
        strokeWidthFraction != other.strokeWidthFraction ||
        style != other.style ||
        points.length != other.points.length) {
      return false;
    }
    for (int i = 0; i < points.length; i++) {
      if (points[i] != other.points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        color,
        strokeWidthFraction,
        style,
        Object.hashAll(points),
      );
}

/// Placed emoji or sticker overlay normalized in `[0..1] x [0..1]` crop space.
@immutable
class AvatarStickerLayer {
  final String id;
  final String? emoji;
  final String? stickerUrl;
  final String stickerFormat;
  final double normX;
  final double normY;
  final double scale;
  final double rotation;

  const AvatarStickerLayer({
    required this.id,
    this.emoji,
    this.stickerUrl,
    this.stickerFormat = 'webp',
    this.normX = 0.5,
    this.normY = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  AvatarStickerLayer copyWith({
    String? id,
    String? emoji,
    String? stickerUrl,
    String? stickerFormat,
    double? normX,
    double? normY,
    double? scale,
    double? rotation,
  }) {
    return AvatarStickerLayer(
      id: id ?? this.id,
      emoji: emoji ?? this.emoji,
      stickerUrl: stickerUrl ?? this.stickerUrl,
      stickerFormat: stickerFormat ?? this.stickerFormat,
      normX: normX ?? this.normX,
      normY: normY ?? this.normY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarStickerLayer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          emoji == other.emoji &&
          stickerUrl == other.stickerUrl &&
          stickerFormat == other.stickerFormat &&
          normX == other.normX &&
          normY == other.normY &&
          scale == other.scale &&
          rotation == other.rotation;

  @override
  int get hashCode => Object.hash(
        id,
        emoji,
        stickerUrl,
        stickerFormat,
        normX,
        normY,
        scale,
        rotation,
      );
}

/// Placed text capsule overlay normalized in `[0..1] x [0..1]` crop space.
@immutable
class AvatarTextLayer {
  final String id;
  final String text;
  final Color color;
  final AvatarTextBackgroundMode backgroundMode;
  final bool bold;
  final double normX;
  final double normY;
  final double scale;
  final double rotation;

  const AvatarTextLayer({
    required this.id,
    required this.text,
    this.color = Colors.white,
    this.backgroundMode = AvatarTextBackgroundMode.solid,
    this.bold = true,
    this.normX = 0.5,
    this.normY = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  AvatarTextLayer copyWith({
    String? id,
    String? text,
    Color? color,
    AvatarTextBackgroundMode? backgroundMode,
    bool? bold,
    double? normX,
    double? normY,
    double? scale,
    double? rotation,
  }) {
    return AvatarTextLayer(
      id: id ?? this.id,
      text: text ?? this.text,
      color: color ?? this.color,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      bold: bold ?? this.bold,
      normX: normX ?? this.normX,
      normY: normY ?? this.normY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarTextLayer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          color == other.color &&
          backgroundMode == other.backgroundMode &&
          bold == other.bold &&
          normX == other.normX &&
          normY == other.normY &&
          scale == other.scale &&
          rotation == other.rotation;

  @override
  int get hashCode => Object.hash(
        id,
        text,
        color,
        backgroundMode,
        bold,
        normX,
        normY,
        scale,
        rotation,
      );
}

/// Configuration for the Emoji / Sticker / Monogram Avatar Constructor.
@immutable
class AvatarEmojiConstructorConfig {
  final String? emoji;
  final String? stickerUrl;
  final String stickerFormat;
  final String? monogramText;
  final double foregroundScale;
  final List<Color> gradientColors;
  final bool isRadial;

  const AvatarEmojiConstructorConfig({
    this.emoji = '😎',
    this.stickerUrl,
    this.stickerFormat = 'webp',
    this.monogramText,
    this.foregroundScale = 0.68,
    this.gradientColors = const <Color>[
      Color(0xFF4FACFE),
      Color(0xFF00F2FE),
    ],
    this.isRadial = false,
  });

  /// 12 modern gradients curated for avatar constructor backgrounds.
  static const List<List<Color>> presetGradients = <List<Color>>[
    <Color>[Color(0xFF4FACFE), Color(0xFF00F2FE)], // Ocean Cyan
    <Color>[Color(0xFF2B82C9), Color(0xFF1D4ED8)], // Telegram Azure
    <Color>[Color(0xFF667EEA), Color(0xFF764BA2)], // Twilight Violet
    <Color>[Color(0xFFA18CD1), Color(0xFFFBC2EB)], // Lavender Bloom
    <Color>[Color(0xFFFF758C), Color(0xFFFF7EB3)], // Coral Rose
    <Color>[Color(0xFFFA709A), Color(0xFFFEE140)], // Peach Sunset
    <Color>[Color(0xFFFF9A44), Color(0xFFFC6076)], // Tangerine Flame
    <Color>[Color(0xFF43E97B), Color(0xFF38F9D7)], // Mint Emerald
    <Color>[Color(0xFF11998E), Color(0xFF38EF7D)], // Forest Jade
    <Color>[Color(0xFF30CFD0), Color(0xFF330867)], // Deep Aurora
    <Color>[Color(0xFF232526), Color(0xFF414345)], // Graphite Slate
    <Color>[Color(0xFF0F2027), Color(0xFF2C5364)], // Midnight Petrol
  ];

  AvatarEmojiConstructorConfig copyWith({
    String? emoji,
    bool clearEmoji = false,
    String? stickerUrl,
    bool clearStickerUrl = false,
    String? stickerFormat,
    String? monogramText,
    bool clearMonogramText = false,
    double? foregroundScale,
    List<Color>? gradientColors,
    bool? isRadial,
  }) {
    return AvatarEmojiConstructorConfig(
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
      stickerUrl: clearStickerUrl ? null : (stickerUrl ?? this.stickerUrl),
      stickerFormat: stickerFormat ?? this.stickerFormat,
      monogramText:
          clearMonogramText ? null : (monogramText ?? this.monogramText),
      foregroundScale:
          (foregroundScale ?? this.foregroundScale).clamp(0.45, 0.95).toDouble(),
      gradientColors: gradientColors ?? this.gradientColors,
      isRadial: isRadial ?? this.isRadial,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AvatarEmojiConstructorConfig ||
        emoji != other.emoji ||
        stickerUrl != other.stickerUrl ||
        stickerFormat != other.stickerFormat ||
        monogramText != other.monogramText ||
        foregroundScale != other.foregroundScale ||
        isRadial != other.isRadial ||
        gradientColors.length != other.gradientColors.length) {
      return false;
    }
    for (int i = 0; i < gradientColors.length; i++) {
      if (gradientColors[i] != other.gradientColors[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        emoji,
        stickerUrl,
        stickerFormat,
        monogramText,
        foregroundScale,
        isRadial,
        Object.hashAll(gradientColors),
      );
}

/// Complete non-destructive edit state for the Avatar Studio.
@immutable
class AvatarStudioState {
  static const Rect fullRect = Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
  static const Offset defaultMiniCenter = Offset(0.5, 0.5);
  static const double minMiniSizeFraction = 0.18;
  static const double maxScale = 8.0;

  final AvatarCropAspectMode aspectMode;
  final double scale;
  final Offset panOffset;
  final int quarterTurns;
  final double fineAngleDegrees;
  final bool flipHorizontal;
  final Rect freeRectNormalized;
  final Offset miniCenterNorm;
  final double miniSizeFrac;
  final AvatarColorAdjustments adjustments;
  final List<AvatarBrushStroke> strokes;
  final List<AvatarStickerLayer> stickers;
  final List<AvatarTextLayer> textLayers;

  const AvatarStudioState({
    this.aspectMode = AvatarCropAspectMode.square1x1,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
    this.quarterTurns = 0,
    this.fineAngleDegrees = 0.0,
    this.flipHorizontal = false,
    this.freeRectNormalized = fullRect,
    this.miniCenterNorm = defaultMiniCenter,
    this.miniSizeFrac = 1.0,
    this.adjustments = const AvatarColorAdjustments(),
    this.strokes = const <AvatarBrushStroke>[],
    this.stickers = const <AvatarStickerLayer>[],
    this.textLayers = const <AvatarTextLayer>[],
  });

  bool get isGeometryIdentity =>
      (scale - 1.0).abs() <= 1e-3 &&
      panOffset.distance <= 1e-3 &&
      (quarterTurns % 4) == 0 &&
      fineAngleDegrees.abs() <= 0.05 &&
      !flipHorizontal &&
      _rectsNearlyEqual(freeRectNormalized, fullRect) &&
      (miniCenterNorm - defaultMiniCenter).distance <= 1e-3 &&
      (miniSizeFrac - 1.0).abs() <= 1e-3;

  bool get isModified =>
      aspectMode != AvatarCropAspectMode.square1x1 ||
      !isGeometryIdentity ||
      !adjustments.isIdentity ||
      strokes.isNotEmpty ||
      stickers.isNotEmpty ||
      textLayers.isNotEmpty;

  /// Returns `true` when edits require rasterizing animated GIF/WebP frames.
  ///
  /// When `false`, the original animated bytes can be preserved verbatim (even
  /// if the user moved or resized the independent `#acrop=...` miniature circle).
  bool get hasEditsForAnimationPreservation =>
      (scale - 1.0).abs() > 1e-3 ||
      panOffset.distance > 1e-3 ||
      (quarterTurns % 4) != 0 ||
      fineAngleDegrees.abs() > 0.05 ||
      flipHorizontal ||
      (aspectMode == AvatarCropAspectMode.free &&
          !_rectsNearlyEqual(freeRectNormalized, fullRect)) ||
      !adjustments.isIdentity ||
      strokes.isNotEmpty ||
      stickers.isNotEmpty ||
      textLayers.isNotEmpty;

  AvatarStudioState resetGeometry({AvatarCropAspectMode? keepAspectMode}) {
    return copyWith(
      aspectMode: keepAspectMode ?? AvatarCropAspectMode.square1x1,
      scale: 1.0,
      panOffset: Offset.zero,
      quarterTurns: 0,
      fineAngleDegrees: 0.0,
      flipHorizontal: false,
      freeRectNormalized: fullRect,
      miniCenterNorm: defaultMiniCenter,
      miniSizeFrac: 1.0,
    );
  }

  AvatarStudioState resetAll({
    AvatarCropAspectMode aspectMode = AvatarCropAspectMode.square1x1,
  }) {
    return AvatarStudioState(aspectMode: aspectMode);
  }

  AvatarStudioState copyWith({
    AvatarCropAspectMode? aspectMode,
    double? scale,
    Offset? panOffset,
    int? quarterTurns,
    double? fineAngleDegrees,
    bool? flipHorizontal,
    Rect? freeRectNormalized,
    Offset? miniCenterNorm,
    double? miniSizeFrac,
    AvatarColorAdjustments? adjustments,
    List<AvatarBrushStroke>? strokes,
    List<AvatarStickerLayer>? stickers,
    List<AvatarTextLayer>? textLayers,
  }) {
    return AvatarStudioState(
      aspectMode: aspectMode ?? this.aspectMode,
      scale: (scale ?? this.scale).clamp(1.0, maxScale).toDouble(),
      panOffset: panOffset ?? this.panOffset,
      quarterTurns: ((quarterTurns ?? this.quarterTurns) % 4 + 4) % 4,
      fineAngleDegrees:
          (fineAngleDegrees ?? this.fineAngleDegrees).clamp(-45.0, 45.0).toDouble(),
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      freeRectNormalized: freeRectNormalized ?? this.freeRectNormalized,
      miniCenterNorm: miniCenterNorm ?? this.miniCenterNorm,
      miniSizeFrac:
          (miniSizeFrac ?? this.miniSizeFrac).clamp(minMiniSizeFraction, 1.0).toDouble(),
      adjustments: adjustments ?? this.adjustments,
      strokes: strokes ?? this.strokes,
      stickers: stickers ?? this.stickers,
      textLayers: textLayers ?? this.textLayers,
    );
  }

  static bool _rectsNearlyEqual(Rect a, Rect b) {
    return (a.left - b.left).abs() < 1e-3 &&
        (a.top - b.top).abs() < 1e-3 &&
        (a.width - b.width).abs() < 1e-3 &&
        (a.height - b.height).abs() < 1e-3;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AvatarStudioState ||
        aspectMode != other.aspectMode ||
        scale != other.scale ||
        panOffset != other.panOffset ||
        quarterTurns != other.quarterTurns ||
        fineAngleDegrees != other.fineAngleDegrees ||
        flipHorizontal != other.flipHorizontal ||
        freeRectNormalized != other.freeRectNormalized ||
        miniCenterNorm != other.miniCenterNorm ||
        miniSizeFrac != other.miniSizeFrac ||
        adjustments != other.adjustments ||
        strokes.length != other.strokes.length ||
        stickers.length != other.stickers.length ||
        textLayers.length != other.textLayers.length) {
      return false;
    }
    for (int i = 0; i < strokes.length; i++) {
      if (strokes[i] != other.strokes[i]) return false;
    }
    for (int i = 0; i < stickers.length; i++) {
      if (stickers[i] != other.stickers[i]) return false;
    }
    for (int i = 0; i < textLayers.length; i++) {
      if (textLayers[i] != other.textLayers[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        aspectMode,
        scale,
        panOffset,
        quarterTurns,
        fineAngleDegrees,
        flipHorizontal,
        freeRectNormalized,
        miniCenterNorm,
        miniSizeFrac,
        adjustments,
        Object.hashAll(strokes),
        Object.hashAll(stickers),
        Object.hashAll(textLayers),
      );
}
