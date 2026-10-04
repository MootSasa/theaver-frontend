import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';

/// Helper for parsing and formatting hex colors.
class TheavColorUtils {
  static Color fromHex(String hexString) {
    var hex = hexString.replaceAll('#', '').trim();
    if (hex.startsWith('rgba')) {
      // Parse rgba(r, g, b, a) format if present
      final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)').firstMatch(hexString);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        final a = match.group(4) != null ? (double.parse(match.group(4)!) * 255).round() : 255;
        return Color.fromARGB(a, r, g, b);
      }
    }
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    final intVal = int.tryParse(hex, radix: 16);
    return Color(intVal ?? 0xFF0088CC);
  }

  static String toHex(Color color, {bool includeAlpha = true}) {
    final int alphaVal = (color.a * 255.0).round().clamp(0, 255);
    if (includeAlpha && alphaVal != 255) {
      return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }
    return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// Represents a 4-point corner gradient.
class FourCornerGradient {
  final Color topLeft;
  final Color topRight;
  final Color bottomLeft;
  final Color bottomRight;

  const FourCornerGradient({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  FourCornerGradient copyWith({
    Color? topLeft,
    Color? topRight,
    Color? bottomLeft,
    Color? bottomRight,
  }) {
    return FourCornerGradient(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
      bottomRight: bottomRight ?? this.bottomRight,
    );
  }

  Map<String, dynamic> toJson() => {
        'topLeft': TheavColorUtils.toHex(topLeft),
        'topRight': TheavColorUtils.toHex(topRight),
        'bottomLeft': TheavColorUtils.toHex(bottomLeft),
        'bottomRight': TheavColorUtils.toHex(bottomRight),
      };

  factory FourCornerGradient.fromJson(Map<String, dynamic> json) {
    return FourCornerGradient(
      topLeft: TheavColorUtils.fromHex(json['topLeft'] ?? '#0088CC'),
      topRight: TheavColorUtils.fromHex(json['topRight'] ?? '#5CB8E6'),
      bottomLeft: TheavColorUtils.fromHex(json['bottomLeft'] ?? '#005580'),
      bottomRight: TheavColorUtils.fromHex(json['bottomRight'] ?? '#00A3E0'),
    );
  }

  factory FourCornerGradient.fromSingleColor(Color color) {
    return FourCornerGradient(
      topLeft: color,
      topRight: color,
      bottomLeft: color,
      bottomRight: color,
    );
  }

  static FourCornerGradient get defaultClassic => const FourCornerGradient(
        topLeft: Color(0xFFD4EBF8),
        topRight: Color(0xFFE8EEF5),
        bottomLeft: Color(0xFFCCE4F6),
        bottomRight: Color(0xFFDCEAF5),
      );

  static FourCornerGradient get defaultDark => const FourCornerGradient(
        topLeft: Color(0xFF14181E),
        topRight: Color(0xFF1C222B),
        bottomLeft: Color(0xFF101318),
        bottomRight: Color(0xFF1A2433),
      );

  static FourCornerGradient get defaultSunset => const FourCornerGradient(
        topLeft: Color(0xFF7B1FA2),
        topRight: Color(0xFFFF7043),
        bottomLeft: Color(0xFFE91E63),
        bottomRight: Color(0xFFFFD54F),
      );

  static FourCornerGradient get defaultOcean => const FourCornerGradient(
        topLeft: Color(0xFF0D47A1),
        topRight: Color(0xFF00897B),
        bottomLeft: Color(0xFF00ACC1),
        bottomRight: Color(0xFF3F51B5),
      );

  static FourCornerGradient get defaultAurora => const FourCornerGradient(
        topLeft: Color(0xFF311B92),
        topRight: Color(0xFF00BFA5),
        bottomLeft: Color(0xFF1A237E),
        bottomRight: Color(0xFF69F0AE),
      );

  static FourCornerGradient get defaultPastel => const FourCornerGradient(
        topLeft: Color(0xFFE0F7FA),
        topRight: Color(0xFFFFF3E0),
        bottomLeft: Color(0xFFF3E5F5),
        bottomRight: Color(0xFFE8F5E9),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FourCornerGradient &&
          runtimeType == other.runtimeType &&
          topLeft == other.topLeft &&
          topRight == other.topRight &&
          bottomLeft == other.bottomLeft &&
          bottomRight == other.bottomRight;

  @override
  int get hashCode =>
      topLeft.hashCode ^ topRight.hashCode ^ bottomLeft.hashCode ^ bottomRight.hashCode;
}

/// Wallpaper configuration for a theme or chat screen.
class TheavWallpaper {
  /// 'pattern', 'gradient4', 'color', 'image'
  final String type;

  /// Built-in pattern name: 'christmas', 'flowers', 'love', 'science', 'space'
  final String? patternName;

  /// Optional relative path or identifier for custom SVG
  final String? customSvgPath;

  /// Solid background or base color behind pattern
  final Color backgroundColor;

  /// Pattern tint color
  final Color patternColor;

  /// Pattern opacity [0.0 - 1.0]
  final double patternOpacity;

  /// 4-point corner gradient configuration
  final FourCornerGradient? fourCornerGradient;

  /// Path to local photo wallpaper file
  final String? imagePath;

  /// Remote URL to photo wallpaper (cloud-synced)
  final String? imageUrl;

  /// Image blur radius [0.0 - 30.0]
  final double blurRadius;

  /// Dark overlay dimming factor [0.0 - 0.8]
  final double dimming;

  /// Gyroscope motion parallax effect (active on mobile platforms)
  final bool motionEnabled;

  const TheavWallpaper({
    this.type = 'pattern',
    this.patternName = 'space',
    this.customSvgPath,
    this.backgroundColor = const Color(0xFFEAF2F8),
    this.patternColor = const Color(0xFF0088CC),
    this.patternOpacity = 0.15,
    this.fourCornerGradient,
    this.imagePath,
    this.imageUrl,
    this.blurRadius = 0.0,
    this.dimming = 0.0,
    this.motionEnabled = false,
  });

  TheavWallpaper copyWith({
    String? type,
    String? patternName,
    String? customSvgPath,
    Color? backgroundColor,
    Color? patternColor,
    double? patternOpacity,
    FourCornerGradient? fourCornerGradient,
    bool clearFourCornerGradient = false,
    String? imagePath,
    String? imageUrl,
    bool clearImageUrl = false,
    double? blurRadius,
    double? dimming,
    bool? motionEnabled,
  }) {
    return TheavWallpaper(
      type: type ?? this.type,
      patternName: patternName ?? this.patternName,
      customSvgPath: customSvgPath ?? this.customSvgPath,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      patternColor: patternColor ?? this.patternColor,
      patternOpacity: patternOpacity ?? this.patternOpacity,
      fourCornerGradient: clearFourCornerGradient ? null : (fourCornerGradient ?? this.fourCornerGradient),
      imagePath: imagePath ?? this.imagePath,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      blurRadius: blurRadius ?? this.blurRadius,
      dimming: dimming ?? this.dimming,
      motionEnabled: motionEnabled ?? this.motionEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (patternName != null) 'patternName': patternName,
        if (customSvgPath != null) 'customSvgPath': customSvgPath,
        'backgroundColor': TheavColorUtils.toHex(backgroundColor),
        'patternColor': TheavColorUtils.toHex(patternColor),
        'patternOpacity': patternOpacity,
        if (fourCornerGradient != null) 'fourCornerGradient': fourCornerGradient!.toJson(),
        if (imagePath != null) 'imagePath': imagePath,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'blurRadius': blurRadius,
        'dimming': dimming,
        'motionEnabled': motionEnabled,
      };

  factory TheavWallpaper.fromJson(Map<String, dynamic> json) {
    return TheavWallpaper(
      type: json['type'] ?? 'pattern',
      patternName: json['patternName'],
      customSvgPath: json['customSvgPath'],
      backgroundColor: TheavColorUtils.fromHex(json['backgroundColor'] ?? '#EAF2F8'),
      patternColor: TheavColorUtils.fromHex(json['patternColor'] ?? '#0088CC'),
      patternOpacity: (json['patternOpacity'] as num?)?.toDouble() ?? 0.15,
      fourCornerGradient: json['fourCornerGradient'] != null
          ? FourCornerGradient.fromJson(json['fourCornerGradient'] as Map<String, dynamic>)
          : null,
      imagePath: json['imagePath'],
      imageUrl: json['imageUrl'],
      blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 0.0,
      dimming: (json['dimming'] as num?)?.toDouble() ?? 0.0,
      motionEnabled: json['motionEnabled'] == true,
    );
  }

  /// Whether wallpaper has a valid image source (local file or remote URL)
  bool get hasImage {
    if (type != 'image') return false;
    if (imagePath != null && imagePath!.isNotEmpty && File(imagePath!).existsSync()) return true;
    if (imageUrl != null && imageUrl!.isNotEmpty) return true;
    return false;
  }

  /// Get ImageProvider for photo wallpaper, checking local file first, then fallback path, then remote cached URL.
  ImageProvider? getImageProvider({String? fallbackPath}) {
    if (imagePath != null && imagePath!.isNotEmpty && File(imagePath!).existsSync()) {
      return FileImage(File(imagePath!));
    }
    if (fallbackPath != null && fallbackPath.isNotEmpty && File(fallbackPath).existsSync()) {
      return FileImage(File(fallbackPath));
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (imageUrl!.startsWith('data:')) {
        try {
          final commaIdx = imageUrl!.indexOf(',');
          if (commaIdx != -1) {
            return MemoryImage(base64Decode(imageUrl!.substring(commaIdx + 1)));
          }
        } catch (_) {}
      }
      final validUrl = AppConfig.resolveMediaUrl(imageUrl);
      if (validUrl != null && validUrl.isNotEmpty) {
        if (validUrl.startsWith('http://') || validUrl.startsWith('https://')) {
          return CachedNetworkImageProvider(validUrl);
        } else if (File(validUrl).existsSync()) {
          return FileImage(File(validUrl));
        }
      }
    }
    return null;
  }

  /// Helper to get asset path for built-in SVG patterns
  String? get assetSvgPath {
    if (type != 'pattern' || patternName == 'none' || patternName == null) return null;
    final name = patternName!;
    switch (name) {
      case 'christmas':
        return 'assets/wallpapers/christmas/christmas_1.svg';
      case 'flowers':
        return 'assets/wallpapers/flowers/flowers_1.svg';
      case 'love':
        return 'assets/wallpapers/love/love_1.svg';
      case 'science':
        return 'assets/wallpapers/science/science_1.svg';
      case 'space':
        return 'assets/wallpapers/space/space_1.svg';
      default:
        return null;
    }
  }
}

/// Color palette definition for a TheavTheme.
class TheavPalette {
  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color chatBubbleOutgoing;
  final Color chatBubbleOutgoingText;
  final Color chatBubbleOutgoingSubtext;
  final Color chatBubbleIncoming;
  final Color chatBubbleIncomingText;
  final Color chatBubbleIncomingSubtext;
  final Color chatDateBadge;
  final Color chatDateBadgeText;

  // Extended customizable colors
  final Color? _chatBubbleOutgoingLink;
  final Color? _chatBubbleIncomingLink;
  final Color? _chatInputBackground;
  final Color? _chatInputText;
  final Color? _chatInputButtons;
  final Color? _chatSendButton;
  final Color? _unreadBadge;
  final Color? _unreadBadgeText;
  final Color? _onlineIndicator;
  final Color? _subtext;
  final Color? _divider;

  Color get chatBubbleOutgoingLink => _chatBubbleOutgoingLink ?? chatBubbleOutgoingText;
  Color get chatBubbleIncomingLink => _chatBubbleIncomingLink ?? primary;
  Color get chatInputBackground => _chatInputBackground ?? surface;
  Color get chatInputText => _chatInputText ?? onSurface;
  Color get chatInputButtons => _chatInputButtons ?? onSurface.withValues(alpha: 0.6);
  Color get chatSendButton => _chatSendButton ?? primary;
  Color get unreadBadge => _unreadBadge ?? primary;
  Color get unreadBadgeText => _unreadBadgeText ?? onPrimary;
  Color get onlineIndicator => _onlineIndicator ?? const Color(0xFF4CAF50);
  Color get subtext => _subtext ?? onSurface.withValues(alpha: 0.6);
  Color get divider => _divider ?? onSurface.withValues(alpha: 0.12);
  Color get accent => primary;

  /// Optional multi-color vertical gradient for outgoing message bubbles
  /// (viewport-anchored continuous mask). If null or < 2 colors, solid
  /// [chatBubbleOutgoing] is used.
  final List<Color>? chatBubbleOutgoingGradient;

  const TheavPalette({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.chatBubbleOutgoing,
    required this.chatBubbleOutgoingText,
    required this.chatBubbleOutgoingSubtext,
    required this.chatBubbleIncoming,
    required this.chatBubbleIncomingText,
    required this.chatBubbleIncomingSubtext,
    required this.chatDateBadge,
    required this.chatDateBadgeText,
    this.chatBubbleOutgoingGradient,
    Color? chatBubbleOutgoingLink,
    Color? chatBubbleIncomingLink,
    Color? chatInputBackground,
    Color? chatInputText,
    Color? chatInputButtons,
    Color? chatSendButton,
    Color? unreadBadge,
    Color? unreadBadgeText,
    Color? onlineIndicator,
    Color? subtext,
    Color? divider,
  })  : _chatBubbleOutgoingLink = chatBubbleOutgoingLink,
        _chatBubbleIncomingLink = chatBubbleIncomingLink,
        _chatInputBackground = chatInputBackground,
        _chatInputText = chatInputText,
        _chatInputButtons = chatInputButtons,
        _chatSendButton = chatSendButton,
        _unreadBadge = unreadBadge,
        _unreadBadgeText = unreadBadgeText,
        _onlineIndicator = onlineIndicator,
        _subtext = subtext,
        _divider = divider;

  TheavPalette copyWith({
    Color? primary,
    Color? onPrimary,
    Color? background,
    Color? surface,
    Color? onSurface,
    Color? appBarBackground,
    Color? appBarForeground,
    Color? chatBubbleOutgoing,
    Color? chatBubbleOutgoingText,
    Color? chatBubbleOutgoingSubtext,
    Color? chatBubbleIncoming,
    Color? chatBubbleIncomingText,
    Color? chatBubbleIncomingSubtext,
    Color? chatDateBadge,
    Color? chatDateBadgeText,
    List<Color>? chatBubbleOutgoingGradient,
    bool clearOutgoingGradient = false,
    Color? chatBubbleOutgoingLink,
    Color? chatBubbleIncomingLink,
    Color? chatInputBackground,
    Color? chatInputText,
    Color? chatInputButtons,
    Color? chatSendButton,
    Color? unreadBadge,
    Color? unreadBadgeText,
    Color? onlineIndicator,
    Color? subtext,
    Color? divider,
  }) {
    return TheavPalette(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      appBarBackground: appBarBackground ?? this.appBarBackground,
      appBarForeground: appBarForeground ?? this.appBarForeground,
      chatBubbleOutgoing: chatBubbleOutgoing ?? this.chatBubbleOutgoing,
      chatBubbleOutgoingText: chatBubbleOutgoingText ?? this.chatBubbleOutgoingText,
      chatBubbleOutgoingSubtext: chatBubbleOutgoingSubtext ?? this.chatBubbleOutgoingSubtext,
      chatBubbleIncoming: chatBubbleIncoming ?? this.chatBubbleIncoming,
      chatBubbleIncomingText: chatBubbleIncomingText ?? this.chatBubbleIncomingText,
      chatBubbleIncomingSubtext: chatBubbleIncomingSubtext ?? this.chatBubbleIncomingSubtext,
      chatDateBadge: chatDateBadge ?? this.chatDateBadge,
      chatDateBadgeText: chatDateBadgeText ?? this.chatDateBadgeText,
      chatBubbleOutgoingGradient: clearOutgoingGradient
          ? null
          : (chatBubbleOutgoingGradient ?? this.chatBubbleOutgoingGradient),
      chatBubbleOutgoingLink: chatBubbleOutgoingLink ?? _chatBubbleOutgoingLink,
      chatBubbleIncomingLink: chatBubbleIncomingLink ?? _chatBubbleIncomingLink,
      chatInputBackground: chatInputBackground ?? _chatInputBackground,
      chatInputText: chatInputText ?? _chatInputText,
      chatInputButtons: chatInputButtons ?? _chatInputButtons,
      chatSendButton: chatSendButton ?? _chatSendButton,
      unreadBadge: unreadBadge ?? _unreadBadge,
      unreadBadgeText: unreadBadgeText ?? _unreadBadgeText,
      onlineIndicator: onlineIndicator ?? _onlineIndicator,
      subtext: subtext ?? _subtext,
      divider: divider ?? _divider,
    );
  }

  Map<String, dynamic> toJson() => {
        'primary': TheavColorUtils.toHex(primary),
        'onPrimary': TheavColorUtils.toHex(onPrimary),
        'background': TheavColorUtils.toHex(background),
        'surface': TheavColorUtils.toHex(surface),
        'onSurface': TheavColorUtils.toHex(onSurface),
        'appBarBackground': TheavColorUtils.toHex(appBarBackground),
        'appBarForeground': TheavColorUtils.toHex(appBarForeground),
        'chatBubbleOutgoing': TheavColorUtils.toHex(chatBubbleOutgoing),
        'chatBubbleOutgoingText': TheavColorUtils.toHex(chatBubbleOutgoingText),
        'chatBubbleOutgoingSubtext': TheavColorUtils.toHex(chatBubbleOutgoingSubtext),
        'chatBubbleIncoming': TheavColorUtils.toHex(chatBubbleIncoming),
        'chatBubbleIncomingText': TheavColorUtils.toHex(chatBubbleIncomingText),
        'chatBubbleIncomingSubtext': TheavColorUtils.toHex(chatBubbleIncomingSubtext),
        'chatDateBadge': TheavColorUtils.toHex(chatDateBadge),
        'chatDateBadgeText': TheavColorUtils.toHex(chatDateBadgeText),
        if (chatBubbleOutgoingGradient != null && chatBubbleOutgoingGradient!.isNotEmpty)
          'chatBubbleOutgoingGradient':
              chatBubbleOutgoingGradient!.map((c) => TheavColorUtils.toHex(c)).toList(),
        if (_chatBubbleOutgoingLink != null)
          'chatBubbleOutgoingLink': TheavColorUtils.toHex(_chatBubbleOutgoingLink!),
        if (_chatBubbleIncomingLink != null)
          'chatBubbleIncomingLink': TheavColorUtils.toHex(_chatBubbleIncomingLink!),
        if (_chatInputBackground != null)
          'chatInputBackground': TheavColorUtils.toHex(_chatInputBackground!),
        if (_chatInputText != null)
          'chatInputText': TheavColorUtils.toHex(_chatInputText!),
        if (_chatInputButtons != null)
          'chatInputButtons': TheavColorUtils.toHex(_chatInputButtons!),
        if (_chatSendButton != null)
          'chatSendButton': TheavColorUtils.toHex(_chatSendButton!),
        if (_unreadBadge != null)
          'unreadBadge': TheavColorUtils.toHex(_unreadBadge!),
        if (_unreadBadgeText != null)
          'unreadBadgeText': TheavColorUtils.toHex(_unreadBadgeText!),
        if (_onlineIndicator != null)
          'onlineIndicator': TheavColorUtils.toHex(_onlineIndicator!),
        if (_subtext != null)
          'subtext': TheavColorUtils.toHex(_subtext!),
        if (_divider != null)
          'divider': TheavColorUtils.toHex(_divider!),
      };

  factory TheavPalette.fromJson(Map<String, dynamic> json) {
    return TheavPalette(
      primary: TheavColorUtils.fromHex(json['primary'] ?? '#0088CC'),
      onPrimary: TheavColorUtils.fromHex(json['onPrimary'] ?? '#FFFFFF'),
      background: TheavColorUtils.fromHex(json['background'] ?? '#FFFFFF'),
      surface: TheavColorUtils.fromHex(json['surface'] ?? '#F5F5F5'),
      onSurface: TheavColorUtils.fromHex(json['onSurface'] ?? '#1C1C1E'),
      appBarBackground: TheavColorUtils.fromHex(json['appBarBackground'] ?? '#FFFFFF'),
      appBarForeground: TheavColorUtils.fromHex(json['appBarForeground'] ?? '#1C1C1E'),
      chatBubbleOutgoing: TheavColorUtils.fromHex(json['chatBubbleOutgoing'] ?? '#0088CC'),
      chatBubbleOutgoingText: TheavColorUtils.fromHex(json['chatBubbleOutgoingText'] ?? '#FFFFFF'),
      chatBubbleOutgoingSubtext:
          TheavColorUtils.fromHex(json['chatBubbleOutgoingSubtext'] ?? '#B3E5FC'),
      chatBubbleIncoming: TheavColorUtils.fromHex(json['chatBubbleIncoming'] ?? '#F2F2F7'),
      chatBubbleIncomingText: TheavColorUtils.fromHex(json['chatBubbleIncomingText'] ?? '#1C1C1E'),
      chatBubbleIncomingSubtext:
          TheavColorUtils.fromHex(json['chatBubbleIncomingSubtext'] ?? '#8E8E93'),
      chatDateBadge: TheavColorUtils.fromHex(json['chatDateBadge'] ?? '#4D000000'),
      chatDateBadgeText: TheavColorUtils.fromHex(json['chatDateBadgeText'] ?? '#FFFFFF'),
      chatBubbleOutgoingGradient: json['chatBubbleOutgoingGradient'] != null
          ? (json['chatBubbleOutgoingGradient'] as List)
              .map((c) => TheavColorUtils.fromHex(c.toString()))
              .toList()
          : null,
      chatBubbleOutgoingLink: json['chatBubbleOutgoingLink'] != null
          ? TheavColorUtils.fromHex(json['chatBubbleOutgoingLink'])
          : null,
      chatBubbleIncomingLink: json['chatBubbleIncomingLink'] != null
          ? TheavColorUtils.fromHex(json['chatBubbleIncomingLink'])
          : null,
      chatInputBackground: json['chatInputBackground'] != null
          ? TheavColorUtils.fromHex(json['chatInputBackground'])
          : null,
      chatInputText: json['chatInputText'] != null
          ? TheavColorUtils.fromHex(json['chatInputText'])
          : null,
      chatInputButtons: json['chatInputButtons'] != null
          ? TheavColorUtils.fromHex(json['chatInputButtons'])
          : null,
      chatSendButton: json['chatSendButton'] != null
          ? TheavColorUtils.fromHex(json['chatSendButton'])
          : null,
      unreadBadge: json['unreadBadge'] != null
          ? TheavColorUtils.fromHex(json['unreadBadge'])
          : null,
      unreadBadgeText: json['unreadBadgeText'] != null
          ? TheavColorUtils.fromHex(json['unreadBadgeText'])
          : null,
      onlineIndicator: json['onlineIndicator'] != null
          ? TheavColorUtils.fromHex(json['onlineIndicator'])
          : null,
      subtext: json['subtext'] != null ? TheavColorUtils.fromHex(json['subtext']) : null,
      divider: json['divider'] != null ? TheavColorUtils.fromHex(json['divider']) : null,
    );
  }
}

/// Flutter ThemeExtension for accessing theme colors inside chat components.
class TheavThemeExtension extends ThemeExtension<TheavThemeExtension> {
  final TheavPalette palette;
  final TheavWallpaper wallpaper;
  final double bubbleRadius;

  const TheavThemeExtension({
    required this.palette,
    required this.wallpaper,
    required this.bubbleRadius,
  });

  @override
  ThemeExtension<TheavThemeExtension> copyWith({
    TheavPalette? palette,
    TheavWallpaper? wallpaper,
    double? bubbleRadius,
  }) {
    return TheavThemeExtension(
      palette: palette ?? this.palette,
      wallpaper: wallpaper ?? this.wallpaper,
      bubbleRadius: bubbleRadius ?? this.bubbleRadius,
    );
  }

  @override
  ThemeExtension<TheavThemeExtension> lerp(
    covariant ThemeExtension<TheavThemeExtension>? other,
    double t,
  ) {
    if (other is! TheavThemeExtension) return this;
    return TheavThemeExtension(
      palette: t < 0.5 ? palette : other.palette,
      wallpaper: t < 0.5 ? wallpaper : other.wallpaper,
      bubbleRadius: bubbleRadius + (other.bubbleRadius - bubbleRadius) * t,
    );
  }
}

/// Complete theme definition for Theaver.
class TheavTheme {
  final String id;
  final String name;
  final String author;
  final bool isDark;
  final double bubbleRadius;
  final TheavPalette palette;
  final TheavWallpaper wallpaper;
  final bool isCloudSaved;
  final bool isBuiltIn;

  const TheavTheme({
    required this.id,
    required this.name,
    required this.author,
    required this.isDark,
    this.bubbleRadius = 16.0,
    required this.palette,
    required this.wallpaper,
    this.isCloudSaved = false,
    this.isBuiltIn = false,
  });

  TheavTheme copyWith({
    String? id,
    String? name,
    String? author,
    bool? isDark,
    double? bubbleRadius,
    TheavPalette? palette,
    TheavWallpaper? wallpaper,
    bool? isCloudSaved,
    bool? isBuiltIn,
  }) {
    return TheavTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      isDark: isDark ?? this.isDark,
      bubbleRadius: bubbleRadius ?? this.bubbleRadius,
      palette: palette ?? this.palette,
      wallpaper: wallpaper ?? this.wallpaper,
      isCloudSaved: isCloudSaved ?? this.isCloudSaved,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'name': name,
        'author': author,
        'isDark': isDark,
        'bubbleRadius': bubbleRadius,
        'palette': palette.toJson(),
        'wallpaper': wallpaper.toJson(),
      };

  factory TheavTheme.fromJson(Map<String, dynamic> json, {bool isCloudSaved = false, bool isBuiltIn = false}) {
    return TheavTheme(
      id: json['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] ?? 'Custom Theme',
      author: json['author'] ?? 'Theaver User',
      isDark: json['isDark'] == true,
      bubbleRadius: (json['bubbleRadius'] as num?)?.toDouble() ?? 16.0,
      palette: TheavPalette.fromJson(json['palette'] as Map<String, dynamic>? ?? {}),
      wallpaper: TheavWallpaper.fromJson(json['wallpaper'] as Map<String, dynamic>? ?? {}),
      isCloudSaved: isCloudSaved,
      isBuiltIn: isBuiltIn,
    );
  }

  /// Converts this TheavTheme into a full Material ThemeData.
  ThemeData toThemeData() {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: palette.primary,
            secondary: palette.primary,
            surface: palette.surface,
            onSurface: palette.onSurface,
            onPrimary: palette.onPrimary,
          )
        : ColorScheme.light(
            primary: palette.primary,
            secondary: palette.primary,
            surface: palette.surface,
            onSurface: palette.onSurface,
            onPrimary: palette.onPrimary,
          );

    return ThemeData(
      brightness: brightness,
      primaryColor: palette.primary,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      cardColor: palette.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.appBarBackground,
        foregroundColor: palette.appBarForeground,
        elevation: 0,
      ),
      extensions: [
        TheavThemeExtension(
          palette: palette,
          wallpaper: wallpaper,
          bubbleRadius: bubbleRadius,
        ),
      ],
    );
  }
}
