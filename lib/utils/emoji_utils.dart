import 'dart:math' as math;
import 'package:flutter/foundation.dart' show SynchronousFuture, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../services/emoji_effect_cache_service.dart';

class EmojiUtils {
  static const String _fontFamily = 'AppleEmoji';
  static const String _assetPath = 'assets/fonts/AppleColorEmoji.ttf';

  static final ValueNotifier<bool> isFontLoading = ValueNotifier(false);
  static final ValueNotifier<bool> isFontLoaded = ValueNotifier(false);

  /// In-memory cache of loaded animated emoji Lottie compositions.
  static final Map<String, LottieComposition> _animatedEmojiCache = {};
  static final Set<String> _missingAnimatedEmojis = {};
  static final Map<String, Future<LottieComposition?>> _loadingAnimatedEmojis = {};

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

  /// Loads and caches the animated emoji [LottieComposition] from bundled assets,
  /// trying all codepoint candidates (with and without `-fe0f`).
  static Future<LottieComposition?> loadAnimatedEmojiComposition(String emoji) {
    final candidates = codepointCandidates(emoji);
    if (candidates.isEmpty) return SynchronousFuture<LottieComposition?>(null);

    final primaryKey = candidates.first;
    final cached = _animatedEmojiCache[primaryKey];
    if (cached != null) {
      return SynchronousFuture<LottieComposition?>(cached);
    }
    if (_missingAnimatedEmojis.contains(primaryKey)) {
      return SynchronousFuture<LottieComposition?>(null);
    }

    return _loadingAnimatedEmojis.putIfAbsent(primaryKey, () async {
      try {
        for (final candidate in candidates) {
          if (_animatedEmojiCache.containsKey(candidate)) {
            final comp = _animatedEmojiCache[candidate]!;
            _animatedEmojiCache[primaryKey] = comp;
            return comp;
          }
          try {
            final comp = await AssetLottie('assets/animated_emojis/$candidate.json').load();
            _animatedEmojiCache[candidate] = comp;
            _animatedEmojiCache[primaryKey] = comp;
            return comp;
          } catch (_) {
            // Try next candidate
          }
        }
        _missingAnimatedEmojis.add(primaryKey);
        return null;
      } finally {
        _loadingAnimatedEmojis.remove(primaryKey);
      }
    });
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

  /// Returns the primary asset path for a Lottie animated emoji.
  static String? getAnimatedEmojiPath(String emoji) {
    final codepoint = emojiToCodepoint(emoji);
    if (codepoint.isEmpty) return null;
    return 'assets/animated_emojis/$codepoint.json';
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

/// A widget that displays a Lottie animated emoji with interactive tap & auto-play effects.
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
  bool _hasTriggeredAutoPlay = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    EmojiEffectCacheService.instance.prefetchEffect(widget.emoji);
    _loadComposition();
  }

  @override
  void didUpdateWidget(covariant LottieEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji.trim() != widget.emoji.trim()) {
      _composition = null;
      EmojiEffectCacheService.instance.prefetchEffect(widget.emoji);
      _loadComposition();
    }
  }

  Future<void> _loadComposition() async {
    final comp = await EmojiUtils.loadAnimatedEmojiComposition(widget.emoji);
    if (!mounted) return;
    if (comp != null) {
      _controller.duration = comp.duration;
      setState(() {
        _composition = comp;
      });
      _checkAutoPlay();
    } else if (widget.autoPlay) {
      // Even if there is no animated emoji asset, trigger effect if one exists
      _checkAutoPlay();
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

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: comp != null ? widget.width : staticSize + 12.0,
        height: comp != null ? widget.height : staticSize + 12.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onTap?.call();
            _playAnimation();
          },
          child: Center(
            child: comp != null
                ? Lottie(
                    composition: comp,
                    controller: _controller,
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.contain,
                    repeat: false,
                    addRepaintBoundary: true,
                  )
                : EmojiUtils.appleEmoji(
                    widget.emoji,
                    size: staticSize,
                    fallbackStyle: widget.style,
                  ),
          ),
        ),
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
      builder: (context) => _EmojiEffectWidget(
        composition: composition,
        layerLink: layerLink,
        emojiSize: emojiSize,
        isMe: isMe,
        jitterOffset: randomOffset,
        onComplete: safeRemove,
      ),
    );

    overlay.insert(entry);
  }
}

class _EmojiEffectWidget extends StatefulWidget {
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
    const double effectSize = 256.0;

    final double hShift = widget.isMe
        ? (widget.emojiSize / 2 - effectSize / 2 - 32.0)
        : (effectSize / 2 - widget.emojiSize / 2 + 32.0);

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
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
