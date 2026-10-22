import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../services/emoji_effect_cache_service.dart';
import '../services/emoji_haptic_service.dart';
import '../services/emoji_interaction_manager.dart';

class EmojiUtils {
  static const String _fontFamily = 'AppleEmoji';
  static const String _appleSystemFontFamily = 'Apple Color Emoji';
  static const String _assetPath = 'assets/fonts/AppleColorEmoji.ttf';

  static final ValueNotifier<bool> isFontLoading = ValueNotifier(false);
  static final ValueNotifier<bool> isFontLoaded = ValueNotifier(false);

  /// Returns true when running natively on an Apple device (iOS or macOS),
  /// where the system's native Apple Color Emoji font is already installed.
  static bool get isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Active emoji font family for the current platform:
  /// - Web: `null` (browser fallback)
  /// - iOS / macOS: native system `'Apple Color Emoji'`
  /// - Android / Windows / Linux: bundled compact `'AppleEmoji'` (`64x64`)
  static String? get effectiveFontFamily {
    if (kIsWeb) return null;
    if (isApplePlatform) return _appleSystemFontFamily;
    return _fontFamily;
  }

  /// Tracks message keys that have already auto-played so rebuilding within
  /// the 3-second freshness window does not re-trigger autoPlay repeatedly.
  static final Set<String> _autoPlayedKeys = {};

  /// Regular expression to match emojis including full ZWJ sequences,
  /// variation selectors, Fitzpatrick skin tones, and keycap sequences.
  static final RegExp emojiRegex = RegExp(
    r'(?:[\u00a9\u00ae\u203c-\u3299]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])(?:[\ufe0e\ufe0f]|\ud83c[\udffb-\udfff])?(?:\u200d(?:[\u00a9\u00ae\u203c-\u3299]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])(?:[\ufe0e\ufe0f]|\ud83c[\udffb-\udfff])?)*',
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

  /// Supported Telegram dice game emojis.
  static const Set<String> diceEmojis = {'🎲', '🎯', '🏀', '⚽', '🎳', '🎰'};

  /// Mapping from dice emoji to its hex codepoint.
  static const Map<String, String> diceEmojiToCodepointMap = {
    '🎲': '1f3b2',
    '🎯': '1f3af',
    '🏀': '1f3c0',
    '⚽': '26bd',
    '🎳': '1f3b3',
    '🎰': '1f3b0',
  };

  /// Returns true if [text] is a single standalone dice game emoji.
  static bool isDiceEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return diceEmojis.contains(trimmed) ||
        diceEmojiToCodepointMap.values.contains(trimmed.toLowerCase());
  }

  /// Converts a dice emoji or codepoint to its standard hex codepoint.
  static String? diceCodepoint(String text) {
    final trimmed = text.trim();
    if (diceEmojiToCodepointMap.containsKey(trimmed)) {
      return diceEmojiToCodepointMap[trimmed];
    }
    final lower = trimmed.toLowerCase();
    if (diceEmojiToCodepointMap.values.contains(lower)) {
      return lower;
    }
    return null;
  }

  /// Loads and caches the animated emoji [LottieComposition] from local cache or server.
  static Future<LottieComposition?> loadAnimatedEmojiComposition(String emoji) {
    return EmojiEffectCacheService.instance.getAnimatedEmojiComposition(emoji);
  }

  /// Loads and registers the compact Apple Emoji font from assets on non-Apple native platforms.
  /// On Apple devices (iOS/macOS), uses the native system Apple Color Emoji font directly.
  static Future<void> loadAppleEmojiFont() async {
    if (kIsWeb || isApplePlatform) {
      isFontLoaded.value = true;
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
  static List<String> get fontFallbacks {
    if (kIsWeb) return const [];
    if (isApplePlatform) return const [_appleSystemFontFamily];
    return const [_fontFamily];
  }

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

  /// Helper widget to display a single compact Apple emoji using the local/bundled font
  /// (used in the emoji picker panel, reaction bar, inline previews, etc.).
  static Widget appleEmoji(String emoji, {double size = 24.0, TextStyle? fallbackStyle}) {
    return Text(
      emoji.trim(),
      style: (fallbackStyle ?? const TextStyle()).copyWith(
        fontSize: size,
        fontFamily: effectiveFontFamily,
      ),
    );
  }

  /// Helper widget to display multiple large emojis (2–9 emoji-only message).
  /// - On Apple devices (iOS/macOS), uses the native local 'Apple Color Emoji' font directly.
  /// - On non-Apple native devices, loads the high-resolution 160x160 PNGs from the server
  ///   with a Telegram-style silhouette shimmer while downloading.
  static Widget emojiOnlyText(
    String text, {
    required double fontSize,
    TextStyle? fallbackStyle,
    TextAlign textAlign = TextAlign.start,
  }) {
    final trimmed = text.trim();
    if (kIsWeb || isApplePlatform) {
      return Text(
        trimmed,
        textAlign: textAlign,
        style: (fallbackStyle ?? const TextStyle()).copyWith(
          fontSize: fontSize,
          height: 1.25,
          fontFamily: effectiveFontFamily,
        ),
      );
    }

    final List<InlineSpan> spans = [];
    for (final cluster in trimmed.characters) {
      if (cluster.trim().isEmpty) {
        spans.add(
          TextSpan(
            text: cluster,
            style: (fallbackStyle ?? const TextStyle()).copyWith(
              fontSize: fontSize * 0.45,
              height: 1.25,
            ),
          ),
        );
      } else if (isEmojiGrapheme(cluster)) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2.0),
              child: HighResStaticEmoji(
                emoji: cluster,
                size: fontSize,
                fallbackStyle: fallbackStyle,
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: cluster,
            style: (fallbackStyle ?? const TextStyle()).copyWith(
              fontSize: fontSize,
              height: 1.25,
              fontFamily: effectiveFontFamily,
            ),
          ),
        );
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
    );
  }

  /// Builds a [TextSpan] where inline emojis use the local/compact Apple Emoji font.
  static TextSpan buildEmojiTextSpan(String text, {required TextStyle style}) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: style);
    }
    final List<InlineSpan> children = [];
    final buffer = StringBuffer();

    try {
      for (final cluster in text.characters) {
        if (isEmojiGrapheme(cluster)) {
          if (buffer.isNotEmpty) {
            children.add(TextSpan(text: buffer.toString(), style: style));
            buffer.clear();
          }
          children.add(
            TextSpan(
              text: cluster,
              style: style.copyWith(
                fontFamily: effectiveFontFamily,
                fontSize: (style.fontSize ?? 14.0),
              ),
            ),
          );
        } else {
          buffer.write(cluster);
        }
      }
      if (buffer.isNotEmpty) {
        children.add(TextSpan(text: buffer.toString(), style: style));
      }
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
  final String? messageId;

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
    this.messageId,
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

  bool _isVisibleOnScreen() {
    if (!mounted) return false;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return false;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenSize = mediaQuery?.size ?? const Size(1000, 2000);
    final screenRect = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    return rect.overlaps(screenRect);
  }

  void _registerPlayer() {
    final targetId = widget.messageId ?? widget.autoPlayId;
    if (targetId != null && targetId.isNotEmpty) {
      EmojiInteractionManager.instance.registerPlayer(
        messageId: targetId,
        isVisible: _isVisibleOnScreen,
        play: () {
          if (_isLoadingAnimated && _composition == null) {
            _pendingTapPlay = true;
            EmojiHapticService.instance.playInteractiveEmojiHaptic(widget.emoji);
            _triggerEffect();
          } else {
            _playAnimation();
          }
        },
      );
    }
  }

  void _unregisterPlayer([String? id]) {
    final targetId = id ?? widget.messageId ?? widget.autoPlayId;
    if (targetId != null && targetId.isNotEmpty) {
      EmojiInteractionManager.instance.unregisterPlayer(targetId);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    EmojiEffectCacheService.instance.prefetchEffect(widget.emoji);
    _registerPlayer();
    _initOrLoadComposition();
  }

  @override
  void didUpdateWidget(covariant LottieEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.messageId ?? oldWidget.autoPlayId;
    final newId = widget.messageId ?? widget.autoPlayId;
    if (oldId != newId) {
      _unregisterPlayer(oldId);
      _registerPlayer();
    }
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

  HapticBinding? _hapticBinding;

  @override
  void dispose() {
    _unregisterPlayer();
    _hapticBinding?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _playAnimation() {
    final comp = _composition;
    if (comp != null) {
      _hapticBinding?.dispose();
      final totalFrames = (comp.endFrame - comp.startFrame).round();
      _hapticBinding = EmojiHapticService.instance.attachInteractiveEmoji(
        _controller,
        widget.emoji,
        totalFrames: totalFrames > 0 ? totalFrames : 180,
      );
    } else {
      EmojiHapticService.instance.playInteractiveEmojiHaptic(widget.emoji);
    }
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
              EmojiHapticService.instance.playInteractiveEmojiHaptic(widget.emoji);
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
                          : HighResStaticEmoji(
                              key: const ValueKey('lottie_static_fallback'),
                              emoji: widget.emoji,
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

/// Renders a large static emoji in messages:
/// - On Apple devices (iOS/macOS), uses the local system 'Apple Color Emoji' font directly.
/// - On non-Apple native devices, loads the original 160x160 PNG from the server
///   (`/api/static-emojis/:codepoint`) with disk + RAM caching, displaying the
///   Telegram-style silhouette + moving shimmer (`_EmojiSilhouetteShimmer`) while loading,
///   and falling back to the compact bundled font if offline.
class HighResStaticEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final TextStyle? fallbackStyle;

  const HighResStaticEmoji({
    Key? key,
    required this.emoji,
    required this.size,
    this.fallbackStyle,
  }) : super(key: key);

  @override
  State<HighResStaticEmoji> createState() => _HighResStaticEmojiState();
}

class _HighResStaticEmojiState extends State<HighResStaticEmoji> {
  Uint8List? _bytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initOrLoadStatic();
  }

  @override
  void didUpdateWidget(covariant HighResStaticEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji.trim() != widget.emoji.trim()) {
      _bytes = null;
      _isLoading = false;
      _initOrLoadStatic();
    }
  }

  void _initOrLoadStatic() {
    if (kIsWeb || EmojiUtils.isApplePlatform) {
      return;
    }
    final cacheService = EmojiEffectCacheService.instance;
    final syncBytes = cacheService.getCachedStaticEmojiSync(widget.emoji);
    if (syncBytes != null) {
      _bytes = syncBytes;
      _isLoading = false;
      return;
    }
    if (cacheService.isStaticEmojiMissing(widget.emoji)) {
      _isLoading = false;
      return;
    }
    _isLoading = true;
    _loadStaticAsync();
  }

  Future<void> _loadStaticAsync() async {
    final targetEmoji = widget.emoji.trim();
    final bytes = await EmojiEffectCacheService.instance.getStaticEmojiBytes(widget.emoji);
    if (!mounted || widget.emoji.trim() != targetEmoji) return;
    setState(() {
      _bytes = bytes;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || EmojiUtils.isApplePlatform) {
      return EmojiUtils.appleEmoji(
        widget.emoji,
        size: widget.size,
        fallbackStyle: widget.fallbackStyle,
      );
    }

    // In AppleColorEmoji.ttf, a 160x160 glyph bitmap corresponds to ppem=137 (160/137 ≈ 1.168).
    final double boxSize = widget.size * 1.168;
    final bytes = _bytes;

    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: bytes != null
              ? Image.memory(
                  bytes,
                  key: const ValueKey('static_highres_loaded'),
                  width: boxSize,
                  height: boxSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                )
              : _isLoading
                  ? _EmojiSilhouetteShimmer(
                      key: const ValueKey('static_highres_shimmer'),
                      emoji: widget.emoji,
                      size: widget.size,
                      fallbackStyle: widget.fallbackStyle,
                    )
                  : EmojiUtils.appleEmoji(
                      widget.emoji,
                      size: widget.size,
                      fallbackStyle: widget.fallbackStyle,
                    ),
        ),
      ),
    );
  }
}

/// Renders the exact silhouette of [emoji] with a smooth moving diagonal shimmer/glare
/// while the vector Lottie emoji or high-res static emoji is being downloaded from the server.
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
          emoji: emoji,
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

  final String emoji;
  final LottieComposition composition;
  final LayerLink layerLink;
  final double emojiSize;
  final bool isMe;
  final Offset jitterOffset;
  final VoidCallback onComplete;

  const _EmojiEffectWidget({
    required this.emoji,
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
  HapticBinding? _hapticBinding;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.composition.duration,
    );
    final effectCodepoint =
        EmojiEffectCacheService.instance.resolveEffectCodepoint(widget.emoji);
    if (effectCodepoint != null) {
      final totalFrames =
          (widget.composition.endFrame - widget.composition.startFrame).round();
      _hapticBinding = EmojiHapticService.instance.attachEmojiEffect(
        _controller,
        effectCodepoint,
        totalFrames: totalFrames > 0 ? totalFrames : 180,
      );
    }
    _controller.forward().whenComplete(() {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _hapticBinding?.dispose();
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

