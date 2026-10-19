import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

class EmojiUtils {
  static const String _fontFamily = 'AppleEmoji';
  static const String _assetPath = 'assets/fonts/AppleColorEmoji.ttf';

  static final ValueNotifier<bool> isFontLoading = ValueNotifier(false);
  static final ValueNotifier<bool> isFontLoaded = ValueNotifier(false);

  /// Regular expression to match emojis, safe for Dart.
  static final RegExp emojiRegex = RegExp(
    r'(\u00a9|\u00ae|[\u2600-\u27bf]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
    unicode: false,
  );

  /// Converts an emoji string to its codepoint representation used in filenames.
  static String emojiToCodepoint(String emoji) {
    return emoji.runes.map((r) => r.toRadixString(16).toLowerCase()).join('-');
  }

  /// Loads and registers the Apple Emoji font from assets.
  static Future<void> loadAppleEmojiFont() async {
    if (kIsWeb) {
      // Skip downloading the 44 MB AppleColorEmoji.ttf into WebAssembly memory on Web
      return;
    }
    debugPrint('DEBUG: EmojiUtils.loadAppleEmojiFont() started from assets');
    if (isFontLoaded.value || isFontLoading.value) {
      return;
    }
    
    try {
      isFontLoading.value = true;
      
      final fontData = await rootBundle.load(_assetPath);
      final fontLoader = FontLoader(_fontFamily);
      fontLoader.addFont(Future.value(fontData));
      await fontLoader.load();
      
      isFontLoaded.value = true;
      debugPrint('DEBUG: Apple Emoji font registered successfully from $_assetPath');
    } catch (e, stack) {
      debugPrint('DEBUG: Error loading Apple Emoji font: $e');
      debugPrint('DEBUG: Stack trace: $stack');
    } finally {
      isFontLoading.value = false;
    }
  }

  /// The font family name to use in TextStyle.fontFamilyFallback
  static List<String> get fontFallbacks => kIsWeb ? const [] : [_fontFamily];

  /// Returns the top 7 most frequent emojis for reactions.
  static List<String> getFrequentEmojis() {
    return ['❤️', '👍', '😱', '😂', '😢', '🔥', '👏'];
  }

  /// Returns the asset path for a Lottie animated emoji if it likely exists.
  static String? getAnimatedEmojiPath(String emoji) {
    final codepoint = emojiToCodepoint(emoji);
    return 'assets/animated_emojis/$codepoint.json';
  }

  /// Returns the asset path for a full-screen Lottie effect if it exists.
  static String? getEmojiEffectPath(String emoji) {
    final codepoint = emojiToCodepoint(emoji);
    return 'assets/emoji_effects/$codepoint.json';
  }

  /// Helper widget to display a single Apple emoji using the font.
  static Widget appleEmoji(String emoji, {double size = 24.0, TextStyle? fallbackStyle}) {
    return Text(
      emoji,
      style: (fallbackStyle ?? const TextStyle()).copyWith(
        fontSize: size,
        fontFamily: kIsWeb ? null : _fontFamily,
      ),
    );
  }

  /// Builds a [TextSpan] where emojis use the Apple Emoji font.
  static TextSpan buildEmojiTextSpan(String text, {required TextStyle style}) {
    final List<InlineSpan> children = [];
    
    try {
      text.splitMapJoin(
        emojiRegex,
        onMatch: (match) {
          final emoji = match.group(0)!;
          children.add(
            TextSpan(
              text: emoji,
              style: style.copyWith(
                fontFamily: kIsWeb ? null : _fontFamily,
                fontSize: (style.fontSize ?? 14.0),
              ),
            ),
          );
          return '';
        },
        onNonMatch: (nonEmoji) {
          if (nonEmoji.isNotEmpty) {
            children.add(TextSpan(text: nonEmoji, style: style));
          }
          return '';
        },
      );
    } catch (e) {
      children.add(TextSpan(text: text, style: style));
    }

    return TextSpan(children: children);
  }
}

/// A widget that displays a Lottie animated emoji.
class LottieEmoji extends StatefulWidget {
  final String assetPath;
  final String emoji;
  final double width;
  final double height;
  final TextStyle? style;
  final VoidCallback? onTap;
  final bool autoPlay;
  final bool isMe;

  const LottieEmoji({
    Key? key,
    required this.assetPath,
    required this.emoji,
    required this.width,
    required this.height,
    this.style,
    this.onTap,
    this.autoPlay = false,
    this.isMe = true,
  }) : super(key: key);

  @override
  State<LottieEmoji> createState() => _LottieEmojiState();
}

class _LottieEmojiState extends State<LottieEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final LayerLink _layerLink = LayerLink();
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playAnimation() {
    // Always trigger effect on tap, regardless of emoji animation state
    _triggerEffect();

    if (_controller.isAnimating) return;
    _controller.forward(from: 0);
  }

  void _triggerEffect() {
    final effectPath = EmojiUtils.getEmojiEffectPath(widget.emoji);
    if (effectPath != null) {
      EmojiEffectOverlay.show(context, effectPath, _layerLink, widget.width, widget.isMe);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: GestureDetector(
          onTap: () {
            widget.onTap?.call();
            _playAnimation();
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!_isLoaded)
                EmojiUtils.appleEmoji(widget.emoji, size: widget.width * 0.8, fallbackStyle: widget.style),
              
              Lottie.asset(
                widget.assetPath,
                controller: _controller,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.contain,
                repeat: false,
                addRepaintBoundary: true,
                onLoaded: (composition) {
                  _controller.duration = composition.duration;
                  if (mounted) setState(() => _isLoaded = true);
                  if (widget.autoPlay) {
                    _playAnimation();
                  }
                },
                errorBuilder: (context, error, stackTrace) {
                  return EmojiUtils.appleEmoji(widget.emoji, size: widget.width * 0.8, fallbackStyle: widget.style);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay manager for anchored emoji effects
class EmojiEffectOverlay {
  static void show(BuildContext context, String assetPath, LayerLink layerLink, double emojiSize, bool isMe) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    
    // Generate random jitter offset (8px to 16px in any direction)
    final random = math.Random();
    final dx = (random.nextDouble() * 8 + 8) * (random.nextBool() ? 1 : -1);
    final dy = (random.nextDouble() * 8 + 8) * (random.nextBool() ? 1 : -1);
    final randomOffset = Offset(dx, dy);
    
    entry = OverlayEntry(
      builder: (context) => _EmojiEffectWidget(
        assetPath: assetPath,
        layerLink: layerLink,
        emojiSize: emojiSize,
        isMe: isMe,
        jitterOffset: randomOffset,
        onComplete: () => entry.remove(),
      ),
    );
    
    overlay.insert(entry);
  }
}

class _EmojiEffectWidget extends StatefulWidget {
  final String assetPath;
  final LayerLink layerLink;
  final double emojiSize;
  final bool isMe;
  final Offset jitterOffset;
  final VoidCallback onComplete;

  const _EmojiEffectWidget({
    required this.assetPath,
    required this.layerLink,
    required this.emojiSize,
    required this.isMe,
    required this.jitterOffset,
    required this.onComplete,
  });

  @override
  State<_EmojiEffectWidget> createState() => _EmojiEffectWidgetState();
}

class _EmojiEffectWidgetState extends State<_EmojiEffectWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double effectSize = 256.0;
    
    // We align the centers by default to fix the "shifted down" issue.
    // Then we apply a horizontal offset to align the requested edges.
    final double hShift = widget.isMe 
        ? (widget.emojiSize / 2 - effectSize / 2 - 32.0) 
        : (effectSize / 2 - widget.emojiSize / 2 + 32.0);

    return IgnorePointer(
      child: CompositedTransformFollower(
        link: widget.layerLink,
        showWhenUnlinked: false,
        followerAnchor: Alignment.center,
        targetAnchor: Alignment.center,
        // Apply base shift + jitter offset
        offset: Offset(hShift + widget.jitterOffset.dx, widget.jitterOffset.dy),
        child: SizedBox(
          width: effectSize,
          height: effectSize,
          child: Transform.scale(
            scaleX: widget.isMe ? 1.0 : -1.0,
            alignment: Alignment.center,
            child: Lottie.asset(
              widget.assetPath,
              controller: _controller,
              fit: BoxFit.contain,
              onLoaded: (composition) {
                _controller.duration = composition.duration;
                _controller.forward().then((_) => widget.onComplete());
              },
              errorBuilder: (context, error, stackTrace) {
                widget.onComplete();
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}
