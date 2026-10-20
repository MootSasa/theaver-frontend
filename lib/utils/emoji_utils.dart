import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../services/emoji_effect_cache_service.dart';

class EmojiUtils {
  static const String _fontFamily = 'AppleEmoji';
  static const String _assetPath = 'assets/fonts/AppleColorEmoji.ttf';

  static final ValueNotifier<bool> isFontLoading = ValueNotifier(false);
  static final ValueNotifier<bool> isFontLoaded = ValueNotifier(false);

  /// Tracks message keys that have already auto-played so rebuilding within
  /// the 3-second freshness window does not re-trigger autoPlay repeatedly.
  static final Set<String> _autoPlayedKeys = {};

  /// Regular expression to match emojis across UTF-16 surrogates and BMP symbol ranges.
  static final RegExp emojiRegex = RegExp(
    r'(\u00a9|\u00ae|[\u203c-\u3299]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
    unicode: false,
  );

  /// Converts an emoji string to its hex codepoint representation used in filenames.
  static String emojiToCodepoint(String emoji) {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.runes.map((r) => r.toRadixString(16).toLowerCase()).join('-');
  }

  /// Returns candidate codepoint strings for asset/effect lookup:
  /// 1. Exact codepoint (e.g. `2764-fe0f`)
  /// 2. Codepoint with `-fe0f` variation selectors stripped (e.g. `2764`)
  /// 3. Codepoint with `-fe0f` appended (for single-codepoint BMP emojis)
  static List<String> codepointCandidates(String emoji) {
    final cp = emojiToCodepoint(emoji);
    if (cp.isEmpty) return const [];

    final candidates = <String>[cp];
    var stripped = cp.replaceAll('-fe0f-', '-');
    if (stripped.endsWith('-fe0f')) {
      stripped = stripped.substring(0, stripped.length - 5);
    }
    if (stripped.startsWith('fe0f-')) {
      stripped = stripped.substring(5);
    }
    if (stripped.isNotEmpty && stripped != cp) {
      candidates.add(stripped);
    }
    if (!cp.contains('fe0f') && !cp.contains('-')) {
      candidates.add('$cp-fe0f');
    }
    return candidates;
  }

  /// Checks whether a single grapheme cluster (`Characters`) is a valid emoji.
  static bool isEmojiGrapheme(String cluster) {
    if (cluster.isEmpty) return false;
    final runes = cluster.runes.toList();
    if (runes.isEmpty) return false;

    final first = runes.first;
    // Keycap sequences: [0-9#*] + optional FE0F + 20E3
    if ((first >= 0x30 && first <= 0x39) || first == 0x23 || first == 0x2A) {
      return runes.contains(0x20E3);
    }

    for (final r in runes) {
      if ((r >= 0x1F000 && r <= 0x1FAFF) ||
          (r >= 0x2600 && r <= 0x27BF) ||
          (r >= 0x2300 && r <= 0x23FF) ||
          (r >= 0x2B50 && r <= 0x2B55) ||
          (r >= 0x2194 && r <= 0x21AA) ||
          (r >= 0x25AA && r <= 0x25FE) ||
          (r >= 0x2934 && r <= 0x2935) ||
          r == 0x203C ||
          r == 0x2049 ||
          r == 0x2122 ||
          r == 0x2139 ||
          r == 0x3030 ||
          r == 0x303D ||
          r == 0x3297 ||
          r == 0x3299 ||
          r == 0x00A9 ||
          r == 0x00AE) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if [text] (trimmed) consists of exactly 1 emoji grapheme cluster.
  static bool isSingleEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final chars = trimmed.characters;
    if (chars.length != 1) return false;
    return isEmojiGrapheme(chars.first);
  }

  /// If [text] consists ONLY of emojis (and optional whitespace/newlines),
  /// returns the total number of emoji grapheme clusters (> 0).
  /// Returns 0 if [text] is empty or contains any non-emoji character.
  static int countEmojiOnly(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;

    int count = 0;
    for (final cluster in trimmed.characters) {
      if (cluster.trim().isEmpty) {
        continue;
      }
      if (!isEmojiGrapheme(cluster)) {
        return 0;
      }
      count++;
    }
    return count;
  }

  /// Returns true if [text] contains at least one emoji and no non-emoji text.
  static bool isEmojiOnly(String text) => countEmojiOnly(text) > 0;

  /// Loads and caches the animated emoji [LottieComposition] from local cache or server.
  static Future<LottieComposition?> loadAnimatedEmojiComposition(String emoji) {
    return EmojiEffectCacheService.instance.getAnimatedEmojiComposition(emoji);
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

  /// Returns the server codepoint for a vector Lottie animated emoji if it exists.
  static String? getAnimatedEmojiPath(String emoji) {
    return EmojiEffectCacheService.instance.resolveAnimatedEmojiCodepoint(emoji);
  }

  /// Returns the server codepoint for a full-screen Lottie effect if it exists.
  static String? getEmojiEffectPath(String emoji) {
    return EmojiEffectCacheService.instance.resolveEffectCodepoint(emoji);
  }

  /// Helper widget to display a single Apple emoji using the font.
  static Widget appleEmoji(String emoji, {double size = 24.0, TextStyle? fallbackStyle}) {
    return Text(
      emoji.trim(),
      style: (fallbackStyle ?? const TextStyle()).copyWith(
        fontSize: size,
        fontFamily: kIsWeb ? null : _fontFamily,
      ),
    );
  }

  /// Helper widget to display multiple emojis (emoji-only message) with Apple Emoji font.
  static Widget emojiOnlyText(
    String text, {
    required double fontSize,
    TextStyle? fallbackStyle,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Text(
      text.trim(),
      textAlign: textAlign,
      style: (fallbackStyle ?? const TextStyle()).copyWith(
        fontSize: fontSize,
        height: 1.25,
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

    return TextSpan(style: style, children: children);
  }
}

/// A widget that displays a Lottie animated emoji with interactive tap & auto-play effects,
/// showing a Telegram-style silhouette + moving shimmer while downloading from the server.
class LottieEmoji extends StatefulWidget {
  final String? assetPath;
  final String emoji;
  final double width;
  final double height;
  final TextStyle? style;
  final VoidCallback? onTap;
  final bool autoPlay;
  final bool isMe;
  final String? autoPlayId;

  const LottieEmoji({
    Key? key,
    this.assetPath,
    required this.emoji,
    required this.width,
    required this.height,
    this.style,
    this.onTap,
    this.autoPlay = false,
    this.isMe = true,
    this.autoPlayId,
  }) : super(key: key);

  @override
  State<LottieEmoji> createState() => _LottieEmojiState();
}

class _LottieEmojiState extends State<LottieEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final LayerLink _layerLink = LayerLink();
  LottieComposition? _composition;
  bool _isLoadingAnimated = false;
  bool _hasTriggeredAutoPlay = false;
  bool _pendingTapPlay = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    EmojiEffectCacheService.instance.prefetchEffect(widget.emoji);
    _initOrLoadComposition();
  }

  @override
  void didUpdateWidget(covariant LottieEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji.trim() != widget.emoji.trim()) {
      _composition = null;
      _isLoadingAnimated = false;
      _pendingTapPlay = false;
      EmojiEffectCacheService.instance.prefetchEffect(widget.emoji);
      _initOrLoadComposition();
    }
  }

  void _initOrLoadComposition() {
    final cacheService = EmojiEffectCacheService.instance;
    if (!cacheService.hasAnimatedEmoji(widget.emoji)) {
      _isLoadingAnimated = false;
      if (widget.autoPlay) {
        _checkAutoPlay();
      }
      return;
    }

    final syncComp = cacheService.getCachedAnimatedEmojiSync(widget.emoji);
    if (syncComp != null) {
      _composition = syncComp;
      _controller.duration = syncComp.duration;
      _isLoadingAnimated = false;
      _checkAutoPlay();
      return;
    }

    _isLoadingAnimated = true;
    _loadCompositionAsync();
  }

  Future<void> _loadCompositionAsync() async {
    final targetEmoji = widget.emoji.trim();
    final comp = await EmojiUtils.loadAnimatedEmojiComposition(widget.emoji);
    if (!mounted || widget.emoji.trim() != targetEmoji) return;

    if (comp != null) {
      _controller.duration = comp.duration;
      setState(() {
        _composition = comp;
        _isLoadingAnimated = false;
      });
      if (_pendingTapPlay) {
        _pendingTapPlay = false;
        _playAnimation();
      } else {
        _checkAutoPlay();
      }
    } else {
      setState(() {
        _isLoadingAnimated = false;
      });
      if (widget.autoPlay) {
        _checkAutoPlay();
      }
    }
  }

  void _checkAutoPlay() {
    if (!widget.autoPlay || _hasTriggeredAutoPlay) return;
    final id = widget.autoPlayId;
    if (id != null && EmojiUtils._autoPlayedKeys.contains(id)) {
      return;
    }
    _hasTriggeredAutoPlay = true;
    if (id != null) {
      EmojiUtils._autoPlayedKeys.add(id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playAnimation();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playAnimation() {
    _triggerEffect();

    if (_composition != null && !_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  void _triggerEffect() {
    if (!EmojiEffectCacheService.instance.hasEffect(widget.emoji)) return;
    EmojiEffectOverlay.show(
      context: context,
      emoji: widget.emoji,
      layerLink: _layerLink,
      emojiSize: widget.width,
      isMe: widget.isMe,
    );
  }

  @override
  Widget build(BuildContext context) {
    final comp = _composition;
    final double staticSize = widget.width / 1.8;
    final bool useFullBox = comp != null || _isLoadingAnimated;

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: useFullBox ? widget.width : staticSize + 12.0,
        height: useFullBox ? widget.height : staticSize + 12.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onTap?.call();
            if (_isLoadingAnimated && comp == null) {
              _pendingTapPlay = true;
              _triggerEffect();
            } else {
              _playAnimation();
            }
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: comp != null
                  ? Lottie(
                      key: const ValueKey('lottie_loaded'),
                      composition: comp,
                      controller: _controller,
                      width: widget.width,
                      height: widget.height,
                      fit: BoxFit.contain,
                      repeat: false,
                      addRepaintBoundary: true,
                    )
                  : _isLoadingAnimated
                      ? _EmojiSilhouetteShimmer(
                          key: const ValueKey('lottie_shimmer'),
                          emoji: widget.emoji,
                          size: widget.width * 0.72,
                          fallbackStyle: widget.style,
                        )
                      : EmojiUtils.appleEmoji(
                          widget.emoji,
                          size: staticSize,
                          fallbackStyle: widget.style,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the exact silhouette of [emoji] with a smooth moving diagonal shimmer/glare
/// while the vector Lottie emoji is being downloaded from the server (Telegram-style).
class _EmojiSilhouetteShimmer extends StatefulWidget {
  final String emoji;
  final double size;
  final TextStyle? fallbackStyle;

  const _EmojiSilhouetteShimmer({
    Key? key,
    required this.emoji,
    required this.size,
    this.fallbackStyle,
  }) : super(key: key);

  @override
  State<_EmojiSilhouetteShimmer> createState() => _EmojiSilhouetteShimmerState();
}

class _EmojiSilhouetteShimmerState extends State<_EmojiSilhouetteShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color baseColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFF758296).withValues(alpha: 0.20);
    final Color midColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : const Color(0xFF8C9BB0).withValues(alpha: 0.32);
    final Color highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.44)
        : const Color(0xFFB4C2D6).withValues(alpha: 0.48);

    final Widget glyph = EmojiUtils.appleEmoji(
      widget.emoji,
      size: widget.size,
      fallbackStyle: widget.fallbackStyle,
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmerController,
        child: glyph,
        builder: (context, child) {
          final double t = _shimmerController.value;
          final double slide = -2.2 + 4.4 * t;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment(slide - 0.9, -0.5),
                end: Alignment(slide + 0.9, 0.5),
                colors: [
                  baseColor,
                  midColor,
                  highlightColor,
                  midColor,
                  baseColor,
                ],
                stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              ).createShader(bounds);
            },
            child: child,
          );
        },
      ),
    );
  }
}

/// Overlay manager for anchored emoji effects loaded from server & local cache.
class EmojiEffectOverlay {
  static Future<void> show({
    required BuildContext context,
    required String emoji,
    required LayerLink layerLink,
    required double emojiSize,
    required bool isMe,
  }) async {
    final composition = await EmojiEffectCacheService.instance.getEffectComposition(emoji);
    if (composition == null || !context.mounted) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    bool removed = false;
    void safeRemove() {
      if (!removed) {
        removed = true;
        try {
          entry.remove();
        } catch (_) {}
      }
    }

    // Generate random jitter offset (8px to 16px in any direction)
    final random = math.Random();
    final dx = (random.nextDouble() * 8 + 8) * (random.nextBool() ? 1 : -1);
    final dy = (random.nextDouble() * 8 + 8) * (random.nextBool() ? 1 : -1);
    final randomOffset = Offset(dx, dy);

    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        top: 0,
        width: _EmojiEffectWidget.effectSize,
        height: _EmojiEffectWidget.effectSize,
        child: _EmojiEffectWidget(
          composition: composition,
          layerLink: layerLink,
          emojiSize: emojiSize,
          isMe: isMe,
          jitterOffset: randomOffset,
          onComplete: safeRemove,
        ),
      ),
    );

    overlay.insert(entry);
  }
}

class _EmojiEffectWidget extends StatefulWidget {
  static const double effectSize = 384.0;

  final LottieComposition composition;
  final LayerLink layerLink;
  final double emojiSize;
  final bool isMe;
  final Offset jitterOffset;
  final VoidCallback onComplete;

  const _EmojiEffectWidget({
    required this.composition,
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
    _controller = AnimationController(
      vsync: this,
      duration: widget.composition.duration,
    );
    _controller.forward().whenComplete(() {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double effectSize = _EmojiEffectWidget.effectSize;

    // In Telegram's 512x512 emoji effect compositions, the emitter origin sits
    // at x ≈ 392 (+0.265 * effectSize from horizontal center) and y = 256 (center).
    final double hShift = widget.isMe
        ? -effectSize * 0.265
        : effectSize * 0.265;

    return IgnorePointer(
      child: CompositedTransformFollower(
        link: widget.layerLink,
        showWhenUnlinked: false,
        followerAnchor: Alignment.center,
        targetAnchor: Alignment.center,
        offset: Offset(hShift + widget.jitterOffset.dx, widget.jitterOffset.dy),
        child: SizedBox(
          width: effectSize,
          height: effectSize,
          child: Transform.scale(
            scaleX: widget.isMe ? 1.0 : -1.0,
            alignment: Alignment.center,
            child: Lottie(
              composition: widget.composition,
              controller: _controller,
              width: effectSize,
              height: effectSize,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

