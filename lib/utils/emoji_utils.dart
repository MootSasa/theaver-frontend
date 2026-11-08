import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../services/chat_service.dart';
import '../services/emoji_effect_cache_service.dart';
import '../services/emoji_haptic_service.dart';
import '../services/emoji_interaction_manager.dart';
import '../services/sticker_service.dart';
import '../widgets/chat/sticker_item_widget.dart';

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

  /// Applies the platform Apple Color Emoji font family / fallback to [base] or creates a [TextStyle].
  static TextStyle emojiTextStyle({
    TextStyle? base,
    double? fontSize,
    double? height,
    Color? color,
  }) {
    final effectiveBase = base ??
        TextStyle(
          fontSize: fontSize,
          height: height,
          color: color,
        );
    final fam = effectiveFontFamily;
    if (fam == null) return effectiveBase;
    return effectiveBase.copyWith(
      fontFamily: fam,
      fontSize: fontSize ?? effectiveBase.fontSize,
      height: height ?? effectiveBase.height,
      color: color ?? effectiveBase.color,
      fontFamilyFallback: <String>[
        fam,
        ...?effectiveBase.fontFamilyFallback,
      ],
    );
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

  static const int _kMaxEmojiCountCacheSize = 512;
  static final Map<String, int> _emojiOnlyCountCache = <String, int>{};

  static bool _isPotentialEmojiCodeUnit(int cu) {
    return cu >= 0x2000 || cu == 0x00A9 || cu == 0x00AE;
  }

  /// Fast O(N) code-unit check that returns false in <1us for normal Latin/Cyrillic text
  /// without allocating grapheme cluster iterators or running regular expressions.
  static bool hasPotentialEmoji(String text) {
    final len = text.length;
    for (int i = 0; i < len; i++) {
      if (_isPotentialEmojiCodeUnit(text.codeUnitAt(i))) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if [text] (trimmed) consists of exactly 1 emoji grapheme cluster.
  static bool isSingleEmoji(String text) {
    return countEmojiOnly(text) == 1;
  }

  /// Returns the rendered size for an emoji-only message across 7 size tiers (1 to 7+ emojis):
  /// - 1 emoji: 115.2px (64.0 * 1.8)
  /// - 2 emojis: 56.0px
  /// - 3 emojis: 46.0px
  /// - 4 emojis: 38.0px
  /// - 5 emojis: 32.0px
  /// - 6 emojis: 26.0px
  /// - 7+ emojis: 20.0px (small standard size)
  static double emojiTierSize(int totalCount) {
    switch (totalCount) {
      case 1:
        return 115.2;
      case 2:
        return 56.0;
      case 3:
        return 46.0;
      case 4:
        return 38.0;
      case 5:
        return 32.0;
      case 6:
        return 26.0;
      default:
        return 20.0;
    }
  }

  /// If [text] consists ONLY of emojis (and optional whitespace/newlines),
  /// returns the total number of emoji grapheme clusters (> 0).
  /// Returns 0 if [text] is empty or contains any non-emoji character.
  static int countEmojiOnly(String text) {
    if (text.isEmpty) return 0;
    final bool canCache = text.length <= 256;
    if (canCache) {
      final cached = _emojiOnlyCountCache[text];
      if (cached != null) return cached;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;

    // Fast O(1) bailout on first code unit for normal text (Latin/Cyrillic/punctuation)
    final firstCu = trimmed.codeUnitAt(0);
    final isKeycapStart =
        (firstCu >= 0x30 && firstCu <= 0x39) || firstCu == 0x23 || firstCu == 0x2A;
    if (!_isPotentialEmojiCodeUnit(firstCu) && !isKeycapStart) {
      return 0;
    }

    int count = 0;
    for (final cluster in trimmed.characters) {
      if (cluster.trim().isEmpty) {
        continue;
      }
      if (!isEmojiGrapheme(cluster)) {
        count = 0;
        break;
      }
      count++;
    }

    if (canCache) {
      if (_emojiOnlyCountCache.length >= _kMaxEmojiCountCacheSize) {
        _emojiOnlyCountCache.remove(_emojiOnlyCountCache.keys.first);
      }
      _emojiOnlyCountCache[text] = count;
    }
    return count;
  }

  /// Returns the total emoji count (Unicode + custom_emoji) if [text] and [entities]
  /// consist strictly of emojis (and optional whitespace/newlines).
  /// Returns 0 if empty, if any non-custom_emoji entity is present, or if any non-emoji text exists.
  static int countTotalEmojiOnly(String text, List<MessageEntity> entities) {
    if (text.trim().isEmpty) return 0;
    if (entities.isEmpty) {
      return countEmojiOnly(text);
    }

    for (final e in entities) {
      if (e.type != 'custom_emoji') {
        return 0;
      }
    }

    final sorted = List<MessageEntity>.from(entities)
      ..sort((a, b) => a.offset.compareTo(b.offset));

    int totalCount = 0;
    int pos = 0;
    final int len = text.length;

    for (final ent in sorted) {
      final int start = ent.offset.clamp(0, len);
      final int end = (ent.offset + ent.length).clamp(start, len);
      if (start < pos) continue;

      if (start > pos) {
        final segment = text.substring(pos, start);
        for (final cluster in segment.characters) {
          if (cluster.trim().isEmpty) continue;
          if (!isEmojiGrapheme(cluster)) {
            return 0;
          }
          totalCount++;
        }
      }

      if (end > start) {
        totalCount++;
        pos = end;
      }
    }

    if (pos < len) {
      final tail = text.substring(pos);
      for (final cluster in tail.characters) {
        if (cluster.trim().isEmpty) continue;
        if (!isEmojiGrapheme(cluster)) {
          return 0;
        }
        totalCount++;
      }
    }

    return totalCount;
  }

  /// Returns true if [text] contains at least one emoji and no non-emoji text.
  static bool isEmojiOnly(String text) => countEmojiOnly(text) > 0;

  static const int _kMaxSettledLottieCacheSize = 160;
  static final Map<String, ui.Image> _settledLottieFrameCache = <String, ui.Image>{};
  static final Map<String, Future<ui.Image?>> _settledLottieInFlight =
      <String, Future<ui.Image?>>{};

  /// Synchronous lookup of a pre-baked static [ui.Image] frame for a Lottie composition.
  static ui.Image? getBakedLottieFrameSync(String cacheKey) {
    return _settledLottieFrameCache[cacheKey];
  }

  /// Pre-bakes a single frame ([progress] in 0.0..1.0) of [composition] at [targetPx]x[targetPx]
  /// into a GPU-backed [ui.Image] texture so stopped animated emojis / dice don't re-rasterize
  /// hundreds of vector paths on every scroll frame.
  static Future<ui.Image?> bakeLottieFrame({
    required String cacheKey,
    required LottieComposition composition,
    required double progress,
    required int targetPx,
  }) {
    final existing = _settledLottieFrameCache[cacheKey];
    if (existing != null) return Future<ui.Image?>.value(existing);
    final inFlight = _settledLottieInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _doBakeLottieFrame(
      cacheKey: cacheKey,
      composition: composition,
      progress: progress,
      targetPx: targetPx.clamp(32, 512),
    );
    _settledLottieInFlight[cacheKey] = future;
    return future;
  }

  static Future<ui.Image?> _doBakeLottieFrame({
    required String cacheKey,
    required LottieComposition composition,
    required double progress,
    required int targetPx,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final rect = Rect.fromLTWH(0, 0, targetPx.toDouble(), targetPx.toDouble());
      final canvas = Canvas(recorder, rect);
      final drawable = LottieDrawable(composition)..setProgress(progress.clamp(0.0, 1.0));
      drawable.draw(canvas, rect, fit: BoxFit.contain);
      final picture = recorder.endRecording();
      final image = await picture.toImage(targetPx, targetPx);
      picture.dispose();

      if (_settledLottieFrameCache.length >= _kMaxSettledLottieCacheSize) {
        final oldestKey = _settledLottieFrameCache.keys.first;
        _settledLottieFrameCache.remove(oldestKey);
      }
      _settledLottieFrameCache[cacheKey] = image;
      return image;
    } catch (_) {
      return null;
    } finally {
      _settledLottieInFlight.remove(cacheKey);
    }
  }

  /// Pre-bakes multiple stacked Lottie layers (e.g., SlotMachineWidget's 5 layers)
  /// at their respective settled progresses into a single composite [ui.Image] texture.
  static Future<ui.Image?> bakeCompositeLottieFrames({
    required String cacheKey,
    required List<(LottieComposition, double)> layers,
    required int targetPx,
  }) {
    final existing = _settledLottieFrameCache[cacheKey];
    if (existing != null) return Future<ui.Image?>.value(existing);
    final inFlight = _settledLottieInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _doBakeCompositeLottieFrames(
      cacheKey: cacheKey,
      layers: layers,
      targetPx: targetPx.clamp(32, 512),
    );
    _settledLottieInFlight[cacheKey] = future;
    return future;
  }

  static Future<ui.Image?> _doBakeCompositeLottieFrames({
    required String cacheKey,
    required List<(LottieComposition, double)> layers,
    required int targetPx,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final rect = Rect.fromLTWH(0, 0, targetPx.toDouble(), targetPx.toDouble());
      final canvas = Canvas(recorder, rect);
      for (final (comp, progress) in layers) {
        final drawable = LottieDrawable(comp)..setProgress(progress.clamp(0.0, 1.0));
        drawable.draw(canvas, rect, fit: BoxFit.contain);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(targetPx, targetPx);
      picture.dispose();

      if (_settledLottieFrameCache.length >= _kMaxSettledLottieCacheSize) {
        final oldestKey = _settledLottieFrameCache.keys.first;
        _settledLottieFrameCache.remove(oldestKey);
      }
      _settledLottieFrameCache[cacheKey] = image;
      return image;
    } catch (_) {
      return null;
    } finally {
      _settledLottieInFlight.remove(cacheKey);
    }
  }

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
    if (trimmed.isEmpty || trimmed.length > 16) return false;
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

      _appleEmojiStyleCache.clear();
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

  static final Map<double, TextStyle> _appleEmojiStyleCache = {};

  /// Helper widget to display a single compact Apple emoji using the local/bundled font
  /// (used in the emoji picker panel, reaction bar, inline previews, etc.).
  static Widget appleEmoji(String emoji, {double size = 24.0, TextStyle? fallbackStyle}) {
    final TextStyle style;
    if (fallbackStyle == null) {
      style = _appleEmojiStyleCache.putIfAbsent(
        size,
        () => TextStyle(
          fontSize: size,
          fontFamily: effectiveFontFamily,
        ),
      );
    } else {
      style = fallbackStyle.copyWith(
        fontSize: size,
        fontFamily: effectiveFontFamily,
      );
    }
    return Text(
      emoji,
      style: style,
    );
  }

  /// Multilingual keywords mapped directly by Unicode emoji (without FE0F) covering
  /// Russian, English, Ukrainian, Spanish, French, German, Italian, Turkish, Polish, Kazakh, Arabic, Chinese, Japanese, Korean.
  static const Map<String, String> _multilingualEmojiKeywords = {
    '😀': 'улыбка радость веселый счастье привет посмішка радість smile happy grinning joy sonrisa feliz sourire heureux lächeln glücklich mutlu ابتسامة 笑 开心 笑顔 웃음 행복',
    '😃': 'улыбка радость веселый счастливый ура посмішка радість smiley smile happy joy feliz heureux glücklich mutlu 开心 嬉しい 행복',
    '😄': 'смех улыбка радость веселье счастье хаха сміх радість smile happy laugh joy risa feliz rire lachen kahkaha ضحك 笑 嬉しい 웃음',
    '😁': 'улыбка зубы довольный рад счастье посмішка beaming grin smile happy sonrisa sourire grinsen 呲牙 ニヤリ 씨익',
    '😆': 'смех ржет хохот хаха лол угар сміх laughing xd haha lol funny risa jaja rire lachen kahkaha ضحك 大笑 爆笑 웃음 ㅋㅋ',
    '😅': 'неловко фух пот нервный смех упс ніяково sweat awkward phew relief sudor gêne schwitz 汗 苦笑 식은땀',
    '😂': 'смех смеется ржет ржака до слез угар хаха лол веселье шутка сміх сміється laugh laughing tears of joy lol lmao rofl funny haha risa jaja rire mdr lachen kahkaha śmiech ضحك 笑哭 爆笑 웃음 ㅋㅋㅋ',
    '🤣': 'катается со смеху истерика ржет смех до слез ор ору хахаха угар сміх істерика rofl lmao hysterical laughing funny risa carcajada mdr totlachen kahkaha ضحك 笑死 爆笑 빵터짐',
    '🥲': 'улыбка со слезой грустная улыбка трогательно жиза боль сльоза smiling tear bittersweet touched 含泪微笑 泣き笑い 웃프다',
    '☺': 'мило улыбка приятно стесняется смущение нежность добрый тепло ніжність smiling blush warm cute sweet shy tierno lindo mignon süß tatlı لطيف 微笑 かわいい 귀여움',
    '😊': 'улыбка румянец мило смущение приятно спасибо радость добрый посмішка blush smiling happy shy cute sweet sonrisa sourire lächeln süß tatlı ابتسامة 微笑 嬉しい 미소',
    '😇': 'ангел нимб святой невинный добрый ангел angel halo innocent ángel ange engel melek ملاك 天使 천사',
    '🙂': 'улыбка хорошо нормально ладно спокойствие посмішка slightly smiling smile fine okay calm sonrisa sourire lächeln 微笑 미소',
    '🙃': 'вверх ногами сарказм ирония перевернутый upside down sarcasm irony silly sarcasmo ironie 倒脸 逆さま 거꾸로',
    '😉': 'подмигивает намек флирт шутка секрет підморгує wink winking flirt hint joke guiño clin zwinkern göz kırpma غمزة 眨眼 ウインク 윙크',
    '😌': 'облегчение спокойствие дзен отдых спокій relieved calm peace zen alivio calme entspannt huzur راحة 安心 ホッ 안도',
    '😍': 'влюблен глаза сердечки красота восхищение обожаю супер милота любовь закоханий кохання heart eyes in love adore beautiful crush lovely amor amoureux verliebt aşık عشق حب 花痴 好き 사랑 반함',
    '🥰': 'любовь влюблен сердечки нежность обожаю милота счастье обнимашки кохання ніжність hearts in love adore affection cute sweet amor cariño amour liebe amore sevgi aşk حب 喜欢 愛 大好き 사랑 애정',
    '😘': 'поцелуй чмок целую любовь флирт воздушный поцелуй поцілунок цілую kiss blowing kiss muah love flirt beso bisou kuss bacio öpücük pocałunek قبلة بوسة 飞吻 キス 뽀뽀 키스',
    '😗': 'поцелуй чмок целую поцілунок kiss smooch beso bisou kuss bacio öpücük قبلة 亲亲 キス 뽀뽀',
    '😙': 'поцелуй чмок улыбка поцілунок kiss smooch beso bisou kuss bacio öpücük قبلة 亲亲 キス 뽀뽀',
    '😚': 'поцелуй чмок нежность целую поцілунок kiss blush sweet beso bisou kuss bacio öpücük قبلة 亲亲 キス 뽀뽀',
    '😋': 'вкусно вкусняшка ням аппетитно еда язык смачно yummy delicious tasty food tongue rico delicioso miam lecker lezzetli لذيذ 好吃 美味 美味しい 맛있다 냠냠',
    '😛': 'язык дразнится шутка прикол язик tongue tease silly playful lengua langue zunge dil لسان 吐舌 ベー 메롱',
    '😜': 'язык подмигивает прикол шутка шалость дурачится веселье жарт язик winking tongue crazy playful joke silly fun broma loco blague verrückt şaka مزحة 调皮 鬼脸 お茶目 장난 메롱',
    '🤪': 'сумасшедший безумие псих дурачится угар божевільний zany crazy goofy wild silly loco fou verrückt deli مجنون 滑稽 疯 変顔 미친 장난',
    '😝': 'язык дразнится смешно прикол язик squinting tongue silly tease xd lengua langue zunge dil 吐舌 ベー 메롱',
    '🤑': 'деньги богатый баксы доллары зарплата кэш гроші багатий money rich cash dollar wealth dinero rico argent riche geld reich para zengin مال غني 钱 发财 お金 돈 부자',
    '🤗': 'обнимашки объятия обнимаю тепло привет поддержка обійми обіймаю hug hugging embrace warm cuddle abrazo câlin umarmung abbraccio sarılma عناق حضن 拥抱 抱抱 ハグ 포옹 안아줘',
    '🤭': 'хихикает упс ой секрет стесняется хіхі giggle oops shy secret risita kichern 偷笑 クスクス 생긋',
    '🤫': 'тихо тсс секрет молчи тайна тишина shh quiet secret silence hush silencio secreto chut leise sus صمت سر 嘘 秘密 シー 쉿 비밀',
    '🤔': 'думает задумался размышление хм сомнение вопрос подозрение мысли думає питання thinking hmm pondering wondering doubt question pensando duda penser réfléchir denken düşünme تفكير 思考 想 考える 생각 흠',
    '🫡': 'честь так точно принял выполняю уважение салют повага salute respect yes sir roger saludo salut respekt selam تحية احترام 敬礼 了解 충성 경례',
    '🤨': 'подозрение бровь скептик серьезно сомнение підозра raised eyebrow skeptical suspicious doubt sus sospecha sceptique skeptisch şüphe شك 挑眉 怀疑 疑い 의심',
    '🧐': 'монокль изучает проверка инспекция умный monocle inspect examine smart detective інспекція 观察 관찰',
    '🤓': 'ботаник умник очки зануда учеба гений розумник окуляри nerd geek glasses smart study empollón intello streber inek ذكي 书呆子 学霸 オタク 너드 공부',
    '😎': 'крутой в очках босс уверенный стиль четко чилл крутий окуляри cool sunglasses boss chill confident swag genial lässig havalı رائع 酷 墨镜 かっこいい 멋짐 선글라스',
    '🤩': 'восторг звезды в глазах вау супер восхищение захват star struck excited wow amazed awesome fascinado ébloui begeistert harika مذهول 崇拜 星星眼 キラキラ 감탄 와우',
    '🥳': 'тусовка день рождения праздник веселье ура отмечаем поздравляю свято день народження party celebrate birthday fun congrats fiesta cumpleaños fête anniversaire geburtstag kutlama حفلة عيد ميلاد 派对 生日 お祝い 파티 생일',
    '😏': 'ухмылка хитрый флирт намек хитрий smirk flirt sly cocky sonrisa pícara narquois schmunzeln sinsi مكر 得意 坏笑 ニヤリ 능글',
    '😒': 'недоволен скучно обида раздражение незадоволений unamused annoyed bored whatever aburrido blasé genervt bıkkın ملل 不屑 시큰둥',
    '😐': 'без эмоций серьезно молчание покерфейс нейтрально байдуже neutral poker face blank serio neutre محايد 无语 無表情 무표정',
    '😑': 'устал без комментариев надоело покерфейс набридло expressionless done annoyed bruh sin palabras genervt 无语 呆れる 할말하않',
    '😶': 'молчу без слов тишина мовчу no mouth speechless silent quiet muet sprachlos sessiz صامت 沉默 無言 침묵',
    '🫠': 'тает жарко стыдно неловко устал тане спека melting hot awkward embarrassed derritiendo fondre schmelzen erime ذوبان 融化 溶ける 녹아내림',
    '🙄': 'закатил глаза раздражение сарказм достали очі eye roll rolling eyes whatever annoyed sarcasm ojos en blanco yeux au ciel augenrollen göz devirme ملل 翻白眼 やれやれ 한심',
    '😬': 'неловко кринж ой напряжение зубы упс ніяково крінж grimacing awkward cringe yikes oops incómodo grimace peinlich حرج 尴尬 気まずい 민망',
    '🥺': 'умоляю пожалуйста милые глазки щенячьи глазки няшка жалость стесняется прошу будь ласка благаю pleading puppy eyes please cute begging shy uwu por favor tierno bitte süß lütfen أرجوك 求求 委屈 お願い うるうる 부탁 제발',
    '🥹': 'слезы счастья трогательно мило благодарность гордость зворушливо сльози holding back tears touched emotional proud grateful emocionado ému gerührt duygusal متأثر 感动 うるうる 감동 울컥',
    '😞': 'грусть разочарование печаль расстроен жаль уныние обидно сум розчарування disappointed sad upset down unhappy sorry triste decepcionado déçu traurig enttäuscht üzgün حزين 失望 难过 がっかり 실망 슬픔',
    '😔': 'задумчивый грустно печаль сожаление тоска сумно pensive sad regret lonely down triste traurig üzgün حزين 难过 しょんぼり 우울',
    '😟': 'беспокойство волнение тревога переживаю хвилювання worried concerned anxious nervous preocupado inquiet besorgt endişeli قلق 担心 心配 걱정',
    '😕': 'озадачен не понял странно растерянность сомнение збентежений confused puzzled unsure doubt confundido confus verwirrt şaşkın مرتبك 困惑 困った 당황',
    '🙁': 'грустный печально недоволен сумний frowning sad unhappy triste traurig üzgün حزين 不开心 悲しい 슬픔',
    '☹': 'грусть печаль плохо расстроен сум frowning sad unhappy triste traurig üzgün حزين 难过 悲しい 슬픔',
    '😣': 'терпение тяжело боль усилие страдание важко persevering struggling pain suffering dolor souffrance schmerz acı ألم 痛苦 我慢 고통',
    '😖': 'отчаяние плохо боль стресс відчай confounded frustrated upset stress frustrado frustré gestresst stres إحباط 抓狂 悔しい 짜증',
    '😫': 'устал измотан нет сил тяжело втомився tired exhausted weary cansado agotado fatigué müde erschöpft yorgun متعب 累 疲れた 피곤 지침',
    '😩': 'усталость отчаяние нет сил страдание втома weary exhausted tired agotado épuisé erschöpft bitkin مرهق 心累 うんざり 지침',
    '😢': 'грусть слеза печально плачет жалко расстроен сум сльоза плаче sad tear crying unhappy upset sorry triste lágrima llorar pleurer weinen traurig piangere ağlama حزين دمعة 哭 悲しい 泣く 눈물 슬픔',
    '😭': 'плачет рыдает слезы плач грустно горе печаль обидно ревет плаче ридає сльози crying sobbing tears sad weeping upset cry llorando lágrimas pleurer larmes weinen tränen piangere ağlamak gözyaşı płacz بكاء دموع 大哭 流泪 号泣 泣く 오열 울음 눈물',
    '😤': 'пар из носа злой раздражен гордый бесит злий дратує huffing frustrated annoyed proud mad enojado énervé wütend kızgın غاضب 傲娇 生气 ふん 씩씩 화남',
    '😠': 'злой сердитый недовольный хмурый злость злий сердитий angry mad grumpy annoyed enfadado enojado fâché colère wütend sauer arrabbiato kızgın zły غاضب 生气 怒る 화남 짜증',
    '😡': 'злой злость бесит ярость гнев ненавижу возмущение лють злість angry mad rage furious hate furioso ira rabia furieux colère wütend zorn furia öfke kızgın غضب 愤怒 生气 激怒 怒り 분노 열받음',
    '🤬': 'ругается мат ярость бешенство цензура очень злой лайка лють swearing cursing furious rage maldición insulto jurer fluchen küfür شتم 骂人 暴怒 暴言 욕 극대노',
    '🤯': 'взрыв мозга шок невероятно офигеть гениально вибух мозку mind blown exploding head shocked amazed wow increíble incroyable unglaublich şok مذهل 脑洞大开 震惊 衝撃 충격 대박',
    '😳': 'смущение шок покраснел неловко удивление збентеження flushed blushing shocked embarrassed shy surprised sonrojado rougir verlegen utangaç خجل 脸红 惊呆 赤面 당황 부끄',
    '🥵': 'жарко горячо пот душно огонь спекотно гаряче hot sweating heat spicy calor caliente chaud heiß caldo sıcak حار 热 暑い 더움 핫',
    '🥶': 'холодно мороз замерз лед зима дрожит cold freezing ice frozen winter frío congelado froid kalt freddo soğuk بارد 冷 寒い 추움',
    '😱': 'шок испуг страх ужас крик кошмар о боже жах scream shock scared fear panic omg terrified miedo susto grito peur choc angst schock paura korku şok خوف صدمة 惊恐 吓死 恐怖 パニック 공포 기절 헉',
    '😨': 'страх испуг боюсь тревога кошмар паника ужас ляк fearful scared afraid fear panic worried miedo asustado peur effrayé angst paura korku خوف 害怕 恐惧 怖い 무서움 두려움',
    '😰': 'паника холодный пот страх нервы стресс тревога паніка нерви anxious cold sweat nervous panic stress nervioso ansiedad anxieux nervös stres توتر 紧张 冷汗 焦り 초조 진땀',
    '😮': 'удивление ого вау шок здивування surprised wow amazed sorpresa surpris überrascht şaşkın مندهش 惊讶 びっくり 놀람 오',
    '😲': 'изумление шок ого удивлен подив astonished shocked amazed wow asombrado étonné erstaunt şaşkın مذهول 震惊 驚き 깜짝',
    '🥱': 'зевает скучно спать устал сон позіхає нудно yawning yawn bored sleepy tired bostezo aburrido bâiller gähnen esneme تثاؤب 打哈欠 あくび 하품 졸림',
    '😴': 'спит сон устал спокойной ночи скучно спать спить добраніч sleep sleeping tired goodnight zzz bored dormir sueño buenas noches sommeil schlafen müde dormire uyku iyi geceler sen نوم 睡觉 晚安 寝る おやすみ 잠 졸림 굿밤',
    '🤤': 'слюнки вкусно хочу мечтаю слинки смачно drooling yummy hungry craving babeando baver sabbern salya لذيذ 流口水 よだれ 침흘림',
    '🥴': 'пьяный поплыл странный устал тусовка woozy drunk tipsy dizzy borracho ivre betrunken sarhoş سكران 微醺 醉 酔っ払い 취함 헤롱',
    '🤢': 'тошнит фу отвращение гадость болею нудить nauseated sick disgusted gross yuck ew asco dégoût ekel übel iğrenç قرف 恶心 気持ち悪い 구역질 극혐',
    '🤮': 'рвота тошнит фу отвращение мерзость болею блювота vomiting puke throw up sick disgusting gross vómito vomir kotzen kusma قيء 呕吐 吐く 토함 우웩',
    '🤧': 'чихает простуда болею насморк аллергия чхає застуда sneezing sick cold allergy estornudo resfriado éternuer niesen hapşırık عطس 打喷嚏 感冒 くしゃみ 재채기 감기',
    '😷': 'маска болею карантин вирус врач хворий mask sick doctor virus mascarilla enfermo masque krank hasta كمامة 口罩 マスク 마스크',
    '🤒': 'температура градусник болею жар простуда хворий thermometer fever sick ill flu fiebre fièvre fieber ateş hasta حمى 发烧 生病 熱 風邪 열 감기 아픔',
    '😈': 'дьявол чертик коварный шалость злодей диявол чортик devil evil naughty horns mischief demon diablo diable teufel diavolo şeytan شيطان 恶魔 坏笑 悪魔 악마',
    '🤡': 'клоун цирк шут кринж смешной ирония clown circus joker fool meme silly payaso palyaço błazen مهرج 小丑 ピエロ 광대',
    '💩': 'какашка дерьмо отстой прикол жиза poop poo crap shit funny caca mierda kacke scheiße cacca kaka 便便 屎 うんち 똥',
    '👻': 'призрак привидение бу хэллоуин страшилка привид ghost boo spooky halloween fantasma fantôme geist gespenst hayalet duch شبح 鬼 幽灵 おばけ 유령',
    '💀': 'череп умер со смеху кринж мертв скелет конец рип skull dead dying rip skeleton bruh calavera muerto crâne mort totenkopf tot teschio kurukafa czaszka جمجمة 骷髅 死 ドクロ 해골',
    '👽': 'пришелец инопланетянин нло космос прибулець alien ufo space alienígena extraterrestre außerirdischer uzaylı فضائي 外星人 宇宙人 외계인',
    '🤖': 'робот бот киборг ии нейросеть машина robot bot ai cyborg android robô roboter روبوت 机器人 ロボット 로봇',
    '🤦': 'фейспалм рукалицо стыд испанский стыд кринж тупость провал сором крінж facepalm cringe disappointed shame fail vergüenza honte peinlich rezillik خجل 捂脸 无语 呆れる 페이스팜 답답',
    '🤷': 'не знаю пожимает плечами хз без понятия все равно shrug idk whatever no sé aucune idée keine ahnung bilmiyorum لا أعرف 摊手 不知道 わからない 몰라 글쎄',
    '👍': 'лайк класс супер ок хорошо одобряю согласен палец вверх отлично да клас добре так thumbs up like ok good approve agree nice great yes bien sí super gut ja bene tamam evet harika ممتاز نعم 赞 好 棒 いいね 좋아요 오케이 굿',
    '👎': 'дизлайк плохо отстой против не нравится палец вниз фу нет погано ні thumbs down dislike bad no disapprove mal mauvais non schlecht nein male kötü hayır سيء لا 差评 不好 ダメ 싫어요 별로',
    '👏': 'аплодисменты хлопает браво молодец уважение поздравляю оплески молодець clap clapping applause bravo well done congrats aplausos applaudir applaus alkış tebrikler brawa تصفيق برافو 鼓掌 拍手 박수 짝짝',
    '🙏': 'спасибо благодарю пожалуйста молитва прошу надежда дякую будь ласка thank you thanks please pray grateful hope gracias por favor merci danke bitte grazie teşekkürler lütfen dziękuję شكرا دعاء 谢谢 拜托 ありがとう お願い 감사 제발 기도',
    '🤝': 'рукопожатие договорились сделка дружба согласие партнеры рукостискання домовились handshake deal agree friends trato acuerdo accord anlaşma اتفاق 握手 合作 악수 합의',
    '💪': 'сила мышцы сильный спорт качок мощь держись сильний muscle strong power gym workout flex fuerza fuerte fort stark kraft forte güç güçlü siła قوة قوي 加油 强壮 筋肉 強い 힘 근육 화이팅',
    '👋': 'привет пока машет рукой здравствуйте до свидания привіт бувай wave hello hi bye goodbye hola adiós salut bonjour hallo tschüss ciao merhaba hoşçakal cześć مرحبا وداعا 你好 再见 こんにちは バイバイ 안녕',
    '👌': 'ок окей отлично идеально хорошо супер чудово ok okay perfect fine good nice perfecto bien parfait perfekt tamam ممتاز تمام 没问题 オッケー 오케이 완벽',
    '✌': 'победа мир два пис привет перемога peace victory two paz victoria paix victoire frieden barış سلام نصر 胜利 耶 ピース 브이 평화',
    '🤞': 'удача надежда скрестил пальцы повезет надія crossed fingers luck good luck hope suerte chance glück fortuna şans حظ 好运 祈る 행운',
    '🫶': 'сердечко руками любовь спасибо обожаю мило кохання heart hands love care sweet amor corazón amour liebe sevgi kalp حب 比心 爱你 ハート 하트 사랑해',
    '👀': 'глаза смотрит взгляд наблюдаю интересно палит шпион очі дивиться eyes looking staring watching curious ojos mirando yeux regarder augen occhi gözler bakmak عيون نظرة 看 盯 目 見る 눈 지켜봄',
    '❤': 'сердце сердечко любовь люблю обожаю милота нежность романтика серце кохання мысық жүрек махаббат heart red heart love lovely adore romance cute corazón amor te amo cœur amour herz liebe cuore amore kalp aşk seviyorum serce miłość قلب حب प्यार 心 爱 爱心 ハート 愛 好き 하트 사랑',
    '🧡': 'оранжевое сердце сердечко любовь серце кохання orange heart love corazón cœur herz kalp قلب 心 ハート 하트',
    '💛': 'желтое сердце сердечко любовь дружба серце yellow heart love friendship corazón cœur herz kalp قلب 心 ハート 하트',
    '💚': 'зеленое сердце сердечко любовь природа серце green heart love nature corazón cœur herz kalp قلب 心 ハート 하트',
    '💙': 'синее сердце сердечко любовь серце blue heart love corazón cœur herz kalp قلب 心 ハート 하트',
    '💜': 'фиолетовое сердце сердечко любовь серце purple heart love corazón cœur herz kalp قلب 心 ハート 하트',
    '🖤': 'черное сердце сердечко любовь стиль чорне серце black heart love dark corazón cœur herz kalp قلب 黑心 ハート 하트',
    '🤍': 'белое сердце сердечко любовь чистота біле серце white heart love pure corazón cœur herz kalp قلب 白心 ハート 하트',
    '💔': 'разбитое сердце боль грусть расставание печаль обида розбите серце біль broken heart heartbreak sad pain hurt breakup corazón roto dolor cœur brisé gebrochenes herz kırık kalp قلب مكسور 心碎 失恋 상처 실연',
    '💕': 'два сердца сердечки любовь нежность романтика сердечка кохання two hearts love romance cute corazones amor cœurs herzen kalpler قلوب 爱心 ハート 하트',
    '💖': 'сверкающее сердце сердечко любовь красота милота кохання sparkling heart love cute corazón amor cœur herz kalp قلب 爱心 ハート 하트',
    '🔥': 'огонь огонек пожар горит жара топ круто пушка имба горячо вогонь гаряче fire flame lit hot burn awesome epic fuego llama caliente feu flamme feuer heiß fuoco ateş alev ogień نار حريق 火 厉害 炎 アツい 불 화끈 대박',
    '✨': 'искры блеск магия красота волшебство звездочки іскри магія блиск sparkles magic shine glitter stars chispas magia brillo étincelles glitzer funkeln ışıltı سحر بريق 闪耀 魔法 キラキラ 반짝 마법',
    '⭐': 'звезда звездочка рейтинг лучший успех топ зірка star gold star best favorite rating estrella étoile stern stella yıldız gwiazda نجمة 星 スター 별',
    '💯': 'сто процентов сотка идеально база правда согласен топ ідіально hundred 100 perfect facts true cien perfecto cent parfait hundert perfekt yüz مئة 满分 百 完璧 백점 완벽',
    '🎉': 'праздник вечеринка поздравляю ура день рождения хлопушка победа свято вітаю party celebration congrats birthday hooray fiesta felicidades fête félicitations feier glückwunsch festa kutlama tebrikler حفلة مبروك 庆祝 恭喜 お祝い おめでとう 축하 파티',
    '🐱': 'кот кошка котик котенок киса мяу пушистый кіт кішка кошеня мысық cat kitty kitten meow feline pet gato gatito michi chat chaton katze kätzchen gatto gattino kedi yavru kedi kot kotek قط قطة बिल्ली 猫 猫咪 小猫 喵 ねこ 子猫 고양이 냥이 야옹 kucing mèo',
    '🐈': 'кот кошка котик питомец кіт кішка мысық cat kitty pet gato chat katze gatto kedi kot قط 猫 ねこ 고양이',
    '😺': 'кот котик улыбка радостный кот кіт cat happy cat gato chat katze kedi قط 猫 ねこ 고양이',
    '😹': 'кот смеется котик смех ржет кіт сміх laughing cat joy cat gato chat katze kedi قط 猫 ねこ 고양이',
    '😻': 'влюбленный кот котик любовь сердечки кіт кохання heart eyes cat love cat gato chat katze kedi قط 猫 ねこ 고양이',
    '😿': 'плачущий кот грустный кот котик плачет слезы кіт плаче crying cat sad cat gato chat katze kedi قط 猫 ねこ 고양이',
    '🐶': 'собака пес щенок песик гав собачка друг цуценя ит dog puppy doggo pupper bark woof pet perro perrito cachorro chien chiot hund welpe cane cucciolo köpek pies piesek كلب कुत्ता 狗 小狗 狗狗 汪 犬 いぬ 子犬 강아지 개 멍멍이 anjing chó',
    '🐕': 'собака пес песик питомец dog hound pet perro chien hund cane köpek pies كلب 狗 犬 강아지 개',
    '🐷': 'свинья хрюшка поросенок свинка хрю кабан пятачок свиня порося шошқа pig piggy piglet hog oink boar swine cerdo chancho puerco cerdito cochon porc schwein ferkel maiale porcellino domuz świnia prosiaczek خنزير सूअर 猪 小猪 猪猪 豚 ぶた 돼지 꿀꿀이 babi heo lợn',
    '🐽': 'пятачок свинья хрюшка нос свиня pig nose snout oink cerdo cochon schwein maiale domuz خنزير 猪鼻 豚 돼지코',
    '🐸': 'лягушка жаба пепе ква мем бақа frog toad pepe ribbit meme rana sapo grenouille frosch kröte kurbağa żaba ضفدع 青蛙 蛙 カエル 개구리 페페',
    '🦊': 'лиса лисичка лис хитрый рыжий лисиця түлкі fox clever ginger vixen zorro raposa renard fuchs volpe tilki lis ثعلب 狐狸 狐 きつね 여우',
    '🐻': 'медведь мишка косолапый плюшевый ведмідь ведмедик аю bear teddy grizzly oso osito urso ours ourson bär orso ayı niedźwiedź miś دب 熊 小熊 くま 곰 곰돌이',
    '🐼': 'панда бамбук мишка милый panda bear cute باندا 熊猫 パンダ 판다',
    '🐰': 'кролик заяц зайчик зайка ушки пушистый заєць қоян rabbit bunny hare cute conejo conejito coelho lapin kaninchen hase coniglio tavşan królik أرنب 兔子 兔兔 うさぎ 토끼',
    '🐹': 'хомяк хомячок щечки грызун милый хом’як hamster cheeks cute pet hámster criceto 仓鼠 ハムスター 햄스터',
    '🐭': 'мышь мышка мышонок сыр миша тышқан mouse mice rat squeak ratón rato souris maus topo fare mysz فأر 老鼠 鼠 ねずみ 쥐 생쥐',
    '🐯': 'тигр тигренок хищник полосатый жолбарыс tiger roar wild tigre kaplan tygrys نمر 老虎 虎 トラ 호랑이',
    '🦁': 'лев царь зверей грива сильный арыстан lion king roar león leão löwe leone aslan lew أسد 狮子 ライオン 사자',
    '🐮': 'корова коровка му молоко бык сиыр cow moo cattle milk vaca vache kuh mucca inek krowa بقرة 牛 奶牛 うし 소 젖소',
    '🐵': 'обезьяна мартышка макака примат мавпа маймыл monkey ape chimp mono macaco singe affe scimmia maymun małpa قرد 猴子 猴 さる 猿 원숭이',
    '🙈': 'не вижу стыдно обезьянка закрыла глаза ой кринж соромно мавпа see no evil monkey shy oops mono singe affe maymun قرد 害羞 見ざる 안봐 부끄',
    '🦆': 'утка уточка утенок кря гусь качка качечка үйрек duck duckling quack bird pato canard ente anatra ördek kaczka بطة 鸭 鸭子 アヒル カモ 오리 꽥꽥',
    '🐧': 'пингвин птица лед антарктида пінгвін penguin bird arctic pingüino pingouin pinguin penguen بطريق 企鹅 ペンギン 펭귄',
    '🦉': 'сова филин ночь мудрость уху owl night wise bird búho hibou eule gufo baykuş sowa بومة 猫头鹰 フクロウ 부엉이 올빼미',
    '🐺': 'волк воет стая хищник ауф вовк қасқыр wolf howl pack wild lobo loup lupo kurt wilk ذئب 狼 オオカミ 늑대',
    '🦄': 'единорог магия сказка радуга чудо єдиноріг unicorn magic fantasy rainbow unicornio licorne einhorn unicorno 유니콘 独角兽 ユニコーン',
    '☕': 'кофе чай чашка утро перерыв бодрость капучино кава ранок coffee tea cup mug morning espresso break café té mañana matin kaffee tee morgen caffè kahve çay kawa قهوة شاي 咖啡 茶 コーヒー お茶 커피 차 모닝커피',
    '🍺': 'пиво кружка бар пятница выходные отдых beer cheers drink pub friday bar cerveza bière bier birra bira piwo بيرة 啤酒 ビール 맥주',
    '🍕': 'пицца еда вкусно голодный перекус піца їжа pizza food slice hungry yummy comida essen yemek بيتزا طعام 披萨 美食 ピザ 피자',
    '🎂': 'торт день рождения праздник свечи сладкое день народження birthday cake party sweet celebrate pastel tarta cumpleaños gâteau kuchen torte torta pasta كعكة عيد ميلاد 蛋糕 生日 ケーキ 케이크 생일',
    '💻': 'работа ноутбук компьютер программист код дедлайн офис робота laptop computer work coding developer office deadline trabajo ordenador computadora travail ordinateur arbeit lavoro iş bilgisayar praca عمل حاسوب 工作 电脑 编程 パソコン 仕事 노트북 컴퓨터 일 코딩',
    '🚀': 'ракета космос поехали взлет стартап быстро вперед rocket space launch moon fast boost cohete espacio fusée rakete razzo roket rakieta صاروخ فضاء 火箭 起飞 ロケット 로켓 가즈아',
    '👑': 'корона король королева босс лучший царь crown king queen royal boss vip corona rey reina couronne roi krone könig taç kral تاج ملك 皇冠 王 王冠 왕관 킹',
    '💎': 'бриллиант алмаз драгоценность роскошь богатство діамант diamond gem jewel luxury rich diamante joya diamant elmas ألماس 钻石 ダイヤモンド 다이아몬드 보석',
    '💸': 'деньги траты расходы зарплата дорого гроші витрати money spending expensive cash dinero gasto argent geld para مال 花钱 お金 돈',
  };

  /// English category/concept stems mapped to multilingual terms so ALL ~1,800 standard emojis in `defaultEmojiSet`
  /// are searchable in Russian, Ukrainian, Spanish, French, German, Turkish, Chinese, Japanese, Korean, Arabic, etc.
  static const Map<String, String> _englishStemMultilingual = {
    'face': 'лицо мордочка смайл смайлик обличчя cara visage gesicht yüz وجه 脸 顔 얼굴',
    'smile': 'улыбка радость посмішка радість sonrisa feliz sourire lächeln mutlu ابتسامة 笑 笑顔 미소',
    'grin': 'улыбка смех радость посмішка sonrisa sourire grinsen 笑 ニヤリ 웃음',
    'laugh': 'смех ржет хаха лол сміх risa rire lachen kahkaha ضحك 笑 웃음',
    'joy': 'радость счастье смех радість щастя alegría joie freude sevinç فرح 喜 喜び 기쁨',
    'kiss': 'поцелуй чмок целую поцілунок beso bisou kuss bacio öpücük قبلة 吻 キス 뽀뽀 키스',
    'love': 'любовь влюблен обожаю кохання amor amour liebe amore aşk حب 爱 愛 사랑',
    'heart': 'сердце сердечко любовь серце кохання corazón cœur herz cuore kalp serce قلب 心 ハート 하트',
    'sad': 'грусть грустный печаль сум сумно triste traurig üzgün حزين 难过 悲しい 슬픔',
    'cry': 'плач плачет слезы рыдает плаче сльози llorar pleurer weinen ağlama بكاء 哭 泣く 울음 눈물',
    'tear': 'слеза слезы плачет сльоза lágrima larme träne gözyaşı دمعة 泪 涙 눈물',
    'angry': 'злой злость сердитый бесит злий enojado furioso colère wütend kızgın غاضب 生气 怒り 화남',
    'rage': 'ярость гнев бешенство лють ira furia zorn öfke غضب 愤怒 激怒 분노',
    'fear': 'страх испуг ужас боюсь жах miedo peur angst paura korku خوف 害怕 恐怖 공포 무서움',
    'scared': 'испуг страх боюсь asustado effrayé angst korku خائف 害怕 怖い 무서움',
    'sleep': 'сон спит спать устал спить dormir sommeil schlafen uyku نوم 睡觉 寝る 잠',
    'tired': 'устал утомлен втома cansado fatigué müde yorgun متعب 累 疲れた 피곤',
    'sick': 'болею болезнь тошнит простуда хворий enfermo malade krank hasta مريض 生病 病気 아픔',
    'cold': 'холод холодно мороз зима frío froid kalt soğuk بارد 冷 寒い 추움',
    'hot': 'жарко горячо спека calor caliente chaud heiß sıcak حار 热 暑い 더움',
    'party': 'праздник вечеринка тусовка свято fiesta fête feier kutlama حفلة 派对 パーティー 파티',
    'star': 'звезда звездочка зірка estrella étoile stern yıldız نجمة 星 スター 별',
    'fire': 'огонь пожар горит вогонь fuego feu feuer ateş نار 火 炎 불',
    'hand': 'рука ладонь жест рука mano main hand el يد 手 손',
    'thumb': 'палец лайк ок великий палець pulgar pouce daumen başparmak إبهام 拇指 親指 엄지',
    'eye': 'глаз глаза взгляд око очі ojo œil auge göz عين 眼 目 눈',
    'cat': 'кот кошка котик мяу кіт кішка мысық gato chat katze gatto kedi kot قط 猫 ねこ 고양이',
    'dog': 'собака пес щенок гав цуценя ит perro chien hund cane köpek pies كلب 狗 犬 강아지 개',
    'pig': 'свинья хрюшка поросенок хрю свиня порося cerdo cochon schwein maiale domuz świnia خنزير 猪 豚 돼지',
    'frog': 'лягушка жаба ква rana grenouille frosch kurbağa ضفدع 青蛙 カエル 개구리',
    'monkey': 'обезьяна мартышка мавпа mono singe affe maymun قرد 猴子 さる 원숭이',
    'bear': 'медведь мишка ведмідь oso ours bär ayı دب 熊 くま 곰',
    'rabbit': 'кролик заяц зайчик заєць conejo lapin kaninchen hase tavşan أرنب 兔子 うさぎ 토끼',
    'fox': 'лиса лисичка лис лисиця zorro renard fuchs tilki ثعلب 狐狸 きつね 여우',
    'bird': 'птица птичка птах pájaro oiseau vogel kuş طائر 鸟 鳥 새',
    'duck': 'утка уточка кря качка pato canard ente ördek بطة 鸭 アヒル 오리',
    'fish': 'рыба рыбка риба pez poisson fisch balık سمكة 鱼 魚 물고기',
    'horse': 'лошадь конь кінь caballo cheval pferd at حصان 马 馬 말',
    'cow': 'корова бык му vaca vache kuh inek بقرة 牛 うし 소',
    'mouse': 'мышь мышка миша ratón souris maus fare فأر 老鼠 ねずみ 쥐',
    'tiger': 'тигр тигренок tigre tiger kaplan نمر 老虎 トラ 호랑이',
    'lion': 'лев царь зверей león lion löwe aslan أسد 狮子 ライオン 사자',
    'flower': 'цветок цветы букет квітка flor fleur blume çiçek زهرة 花 꽃',
    'rose': 'роза цветок троянда rosa rose gül وردة 玫瑰 バラ 장미',
    'tree': 'дерево лес природа дерево árbol arbre baum ağaç شجرة 树 木 나무',
    'sun': 'солнце солнышко сонце sol soleil sonne güneş شمس 太阳 太陽 해 태양',
    'moon': 'луна месяц ночь місяць ніч luna lune mond ay قمر 月亮 月 달',
    'rain': 'дождь туча ливень дощ lluvia pluie regen yağmur مطر 雨 비',
    'snow': 'снег снежинка зима сніг nieve neige schnee kar ثلج 雪 눈',
    'food': 'еда вкусно кушать їжа смачно comida nourriture essen yemek طعام 食物 食べ物 음식',
    'apple': 'яблоко фрукт яблуко manzana pomme apfel elma تفاحة 苹果 りんご 사과',
    'pizza': 'пицца еда піца pizza بيتزا 披萨 ピザ 피자',
    'cake': 'торт пирожное сладкое праздник pastel gâteau kuchen pasta كعكة 蛋糕 ケーキ 케이크',
    'coffee': 'кофе чай чашка утро кава café kaffee kahve قهوة 咖啡 コーヒー 커피',
    'beer': 'пиво кружка бар cerveza bière bier bira بيرة 啤酒 ビール 맥주',
    'car': 'машина авто автомобиль авто coche auto voiture wagen araba سيارة 车 車 자동차',
    'rocket': 'ракета космос взлет cohete fusée rakete roket صاروخ 火箭 ロケット 로켓',
    'house': 'дом домик здание дім casa maison haus ev منزل 家 집',
    'money': 'деньги доллар богатый гроші dinero argent geld para مال 钱 お金 돈',
    'crown': 'корона король королева corona couronne krone taç تاج 皇冠 王冠 왕관',
    'book': 'книга учеба чтение книга libro livre buch kitap كتاب 书 本 책',
    'music': 'музыка песня ноты музика música musique musik müzik موسيقى 音乐 音楽 음악',
    'game': 'игра геймер джойстик гра juego jeu spiel oyun لعبة 游戏 ゲーム 게임',
    'flag': 'флаг страна прапор bandera drapeau flagge bayrak علم 旗 깃발',
  };

  static String _stripVariationSelector(String s) =>
      s.replaceAll('\ufe0f', '').replaceAll('\ufe0e', '');

  /// Checks if a standard Unicode emoji (with English CLDR [englishName]) matches [rawQuery]
  /// in ANY supported language (Russian, English, Ukrainian, Spanish, French, German, Turkish, Chinese, Japanese, Korean, Arabic, etc.).
  static bool matchesEmojiSearch(String emojiChar, String englishName, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (emojiChar.contains(q)) return true;

    final lowerName = englishName.toLowerCase();
    if (lowerName.contains(q)) return true;

    final baseEmoji = _stripVariationSelector(emojiChar.trim());
    final directKeywords = _multilingualEmojiKeywords[baseEmoji] ??
        _multilingualEmojiKeywords[emojiChar.trim()];
    if (directKeywords != null && directKeywords.contains(q)) {
      return true;
    }

    // Check English name stems against multilingual concept table
    for (final entry in _englishStemMultilingual.entries) {
      if (lowerName.contains(entry.key) && entry.value.contains(q)) {
        return true;
      }
    }
    return false;
  }

  /// Checks if any emoji in [emojis] matches [rawQuery] across all languages.
  static bool matchesAnyEmojiInList(List<String> emojis, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final e in emojis) {
      if (e.contains(q)) return true;
      final base = _stripVariationSelector(e.trim());
      final kw = _multilingualEmojiKeywords[base] ?? _multilingualEmojiKeywords[e.trim()];
      if (kw != null && kw.contains(q)) {
        return true;
      }
    }
    return false;
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

  /// Renders a frameless emoji-only message (2+ emojis, or mixed Unicode + custom emojis)
  /// at the given [fontSize] tier, supporting wrapping, whitespace, high-res Unicode emojis,
  /// and interactive custom emojis.
  static Widget buildEmojiOnlyMessageWidget(
    String text, {
    required double fontSize,
    List<MessageEntity> entities = const [],
    bool isMe = true,
    TextStyle? fallbackStyle,
    TextAlign textAlign = TextAlign.start,
  }) {
    final customEntities = entities
        .where((e) =>
            e.type == 'custom_emoji' &&
            e.customEmojiId != null &&
            e.customEmojiId!.isNotEmpty)
        .toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    if (customEntities.isEmpty) {
      return emojiOnlyText(
        text,
        fontSize: fontSize,
        fallbackStyle: fallbackStyle,
        textAlign: textAlign,
      );
    }

    final List<InlineSpan> spans = [];
    final int len = text.length;
    int pos = 0;

    void appendUnicodeSegment(String segment) {
      for (final cluster in segment.characters) {
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
        } else if (kIsWeb || isApplePlatform || !isEmojiGrapheme(cluster)) {
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
        } else {
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
        }
      }
    }

    for (final ent in customEntities) {
      final int start = ent.offset.clamp(0, len);
      final int end = (ent.offset + ent.length).clamp(start, len);
      if (start < pos) continue;

      if (start > pos) {
        appendUnicodeSegment(text.substring(pos, start));
      }

      if (end > start) {
        final fallback = text.substring(start, end);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2.0),
              child: InlineCustomEmojiWidget(
                customEmojiId: ent.customEmojiId!,
                directUrl: ent.documentUrl,
                directFormat: ent.format,
                fallbackEmoji: fallback,
                size: fontSize,
                isMe: isMe,
                enableTapEffect: true,
              ),
            ),
          ),
        );
        pos = end;
      }
    }

    if (pos < len) {
      appendUnicodeSegment(text.substring(pos));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
    );
  }

  /// Builds an [InlineSpan] for single-line chat list previews (drafts and last messages)
  /// that renders both Apple Unicode emojis and inline custom emojis (`InlineCustomEmojiWidget`).
  static InlineSpan buildPreviewWithCustomEmojis(
    String text, {
    required TextStyle style,
    List<MessageEntity> entities = const [],
    double emojiSize = 16.0,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    // Replace CR/LF 1-for-1 with spaces so single-line previews don't break
    // and UTF-16 entity offsets remain 100% aligned.
    final String singleLine =
        text.replaceAll('\r', ' ').replaceAll('\n', ' ');

    final customEntities = entities
        .where((e) =>
            e.type == 'custom_emoji' &&
            e.customEmojiId != null &&
            e.customEmojiId!.isNotEmpty)
        .toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    if (customEntities.isEmpty) {
      return buildEmojiTextSpan(singleLine, style: style);
    }

    final List<InlineSpan> children = [];
    final int len = singleLine.length;
    int pos = 0;

    for (final ent in customEntities) {
      final int start = ent.offset.clamp(0, len);
      final int end = (ent.offset + ent.length).clamp(start, len);
      if (start < pos) continue;

      if (start > pos) {
        children.add(
          buildEmojiTextSpan(
            singleLine.substring(pos, start),
            style: style,
          ),
        );
      }

      if (end > start) {
        final fallback = singleLine.substring(start, end);
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              child: InlineCustomEmojiWidget(
                customEmojiId: ent.customEmojiId!,
                directUrl: ent.documentUrl,
                directFormat: ent.format,
                fallbackEmoji: fallback,
                size: emojiSize,
                enableTapEffect: false,
              ),
            ),
          ),
        );
        pos = end;
      }
    }

    if (pos < len) {
      children.add(
        buildEmojiTextSpan(
          singleLine.substring(pos),
          style: style,
        ),
      );
    }

    return TextSpan(style: style, children: children);
  }

  /// Builds a [TextSpan] where inline emojis use the local/compact Apple Emoji font.
  static TextSpan buildEmojiTextSpan(
    String text, {
    required TextStyle style,
    GestureRecognizer? recognizer,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: style, recognizer: recognizer);
    }
    // Fast path: if text has no code units >= 0x2000 (and no ©/®), return a single TextSpan
    // without allocating grapheme cluster iterators or child lists.
    if (!hasPotentialEmoji(text)) {
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }

    final emojiStyle = style.copyWith(
      fontFamily: effectiveFontFamily,
      fontSize: (style.fontSize ?? 14.0),
      height: 1.0,
    );
    final List<InlineSpan> children = [];
    final buffer = StringBuffer();

    try {
      for (final cluster in text.characters) {
        if (_isPotentialEmojiCodeUnit(cluster.codeUnitAt(0)) && isEmojiGrapheme(cluster)) {
          if (buffer.isNotEmpty) {
            children.add(TextSpan(
              text: buffer.toString(),
              style: style,
              recognizer: recognizer,
            ));
            buffer.clear();
          }
          children.add(TextSpan(
            text: cluster,
            style: emojiStyle,
            recognizer: recognizer,
          ));
        } else if (cluster.length > 1 && isEmojiGrapheme(cluster)) {
          if (buffer.isNotEmpty) {
            children.add(TextSpan(
              text: buffer.toString(),
              style: style,
              recognizer: recognizer,
            ));
            buffer.clear();
          }
          children.add(TextSpan(
            text: cluster,
            style: emojiStyle,
            recognizer: recognizer,
          ));
        } else {
          buffer.write(cluster);
        }
      }
      if (children.isEmpty) {
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }
      if (buffer.isNotEmpty) {
        children.add(TextSpan(
          text: buffer.toString(),
          style: style,
          recognizer: recognizer,
        ));
      }
    } catch (e) {
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }

    return TextSpan(style: style, children: children, recognizer: recognizer);
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
  ui.Image? _settledFrame;
  bool _isAnimating = false;
  bool _isLoadingAnimated = false;
  bool _hasTriggeredAutoPlay = false;
  bool _pendingTapPlay = false;

  void _onAnimationStatusChanged(AnimationStatus status) {
    final animating =
        status == AnimationStatus.forward || status == AnimationStatus.reverse;
    if (!animating) {
      _hapticBinding?.dispose();
      _hapticBinding = null;
    }
    if (_isAnimating != animating && mounted) {
      setState(() {
        _isAnimating = animating;
      });
    }
  }

  void _ensureSettledFrame(LottieComposition comp) {
    final int targetPx = (widget.width * 2.0).round().clamp(64, 320);
    final String cacheKey = 'emoji_${widget.emoji.trim()}_$targetPx';
    final syncImg = EmojiUtils.getBakedLottieFrameSync(cacheKey);
    if (syncImg != null) {
      _settledFrame = syncImg;
      return;
    }
    EmojiUtils.bakeLottieFrame(
      cacheKey: cacheKey,
      composition: comp,
      progress: 0.0,
      targetPx: targetPx,
    ).then((img) {
      if (mounted && img != null && _composition == comp) {
        setState(() {
          _settledFrame = img;
        });
      }
    });
  }

  bool _isVisibleOnScreen() {
    if (!mounted) return false;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return false;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
    final view = View.maybeOf(context);
    final screenSize = view != null && view.devicePixelRatio > 0
        ? (view.physicalSize / view.devicePixelRatio)
        : (MediaQuery.maybeOf(context)?.size ?? const Size(1920, 1080));
    final screenRect = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    return rect.overlaps(screenRect);
  }

  void _registerPlayer() {
    final targetId = widget.messageId ?? widget.autoPlayId;
    if (targetId != null && targetId.isNotEmpty) {
      EmojiInteractionManager.instance.registerPlayer(
        messageId: targetId,
        owner: this,
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
      EmojiInteractionManager.instance.unregisterPlayer(targetId, owner: this);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_onAnimationStatusChanged);
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
      _settledFrame = null;
      _isAnimating = false;
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
      _ensureSettledFrame(syncComp);
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
      _ensureSettledFrame(comp);
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
      setState(() {
        _isAnimating = true;
      });
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
    final bool isAnimatedEmoji = comp != null ||
        _isLoadingAnimated ||
        EmojiEffectCacheService.instance.hasAnimatedEmoji(widget.emoji);
    final bool useFullBox = comp != null || _isLoadingAnimated;

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: useFullBox ? widget.width : staticSize + 12.0,
        height: useFullBox ? widget.height : staticSize + 12.0,
        child: GestureDetector(
          behavior: isAnimatedEmoji
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTap: isAnimatedEmoji
              ? () {
                  widget.onTap?.call();
                  if (_isLoadingAnimated && comp == null) {
                    _pendingTapPlay = true;
                    EmojiHapticService.instance
                        .playInteractiveEmojiHaptic(widget.emoji);
                    _triggerEffect();
                  } else {
                    _playAnimation();
                  }
                }
              : null,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: comp != null
                  ? KeyedSubtree(
                      key: const ValueKey('lottie_loaded'),
                      child: (!_isAnimating && _settledFrame != null)
                          ? RawImage(
                              image: _settledFrame,
                              width: widget.width,
                              height: widget.height,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.low,
                            )
                          : Lottie(
                              composition: comp,
                              controller: _controller,
                              width: widget.width,
                              height: widget.height,
                              fit: BoxFit.contain,
                              repeat: false,
                              addRepaintBoundary: true,
                            ),
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

/// Overlay manager for anchored emoji and sticker effects loaded from server & local cache.
class EmojiEffectOverlay {
  static final Set<LayerLink> _activeStickerEffectLinks = <LayerLink>{};

  static bool isStickerEffectActive(LayerLink layerLink) =>
      _activeStickerEffectLinks.contains(layerLink);

  static Future<void> show({
    required BuildContext context,
    required String emoji,
    required LayerLink layerLink,
    required double emojiSize,
    required bool isMe,
  }) async {
    final composition = await EmojiEffectCacheService.instance.getEffectComposition(emoji);
    if (composition == null || !context.mounted) return;
    _insertEffectOverlay(
      context: context,
      emoji: emoji,
      composition: composition,
      layerLink: layerLink,
      emojiSize: emojiSize,
      isMe: isMe,
      effectSize: _EmojiEffectWidget.defaultEffectSize,
      enableRandomJitter: true,
    );
  }

  /// Displays a full-screen Telegram-compatible effect anchored to a sticker or custom emoji.
  /// Uses [effectUrl] (`.tgs` or `.json` 512x512 composition) if non-empty, otherwise falls back
  /// to the standard emoji effect for [fallbackEmoji] if available.
  /// Guarantees at most 1 active effect per [layerLink] at any moment and zero random offset.
  static Future<void> showStickerEffect({
    required BuildContext context,
    String? effectUrl,
    String? fallbackEmoji,
    required LayerLink layerLink,
    required double stickerSize,
    required bool isMe,
  }) async {
    if (_activeStickerEffectLinks.contains(layerLink)) {
      return;
    }
    _activeStickerEffectLinks.add(layerLink);

    LottieComposition? composition;
    try {
      if (effectUrl != null && effectUrl.trim().isNotEmpty) {
        composition =
            await StickerService.instance.getLottieComposition(effectUrl.trim());
      }
      if (composition == null &&
          fallbackEmoji != null &&
          fallbackEmoji.trim().isNotEmpty) {
        composition = await EmojiEffectCacheService.instance
            .getEffectComposition(fallbackEmoji.trim());
      }
    } catch (_) {
      _activeStickerEffectLinks.remove(layerLink);
      return;
    }

    if (composition == null || !context.mounted) {
      _activeStickerEffectLinks.remove(layerLink);
      return;
    }

    final double computedEffectSize = (stickerSize * 2.4).clamp(384.0, 512.0);
    final inserted = _insertEffectOverlay(
      context: context,
      emoji: fallbackEmoji ?? '',
      composition: composition,
      layerLink: layerLink,
      emojiSize: stickerSize,
      isMe: isMe,
      effectSize: computedEffectSize,
      enableRandomJitter: false,
      onRemoved: () => _activeStickerEffectLinks.remove(layerLink),
    );
    if (!inserted) {
      _activeStickerEffectLinks.remove(layerLink);
    }
  }

  static bool _insertEffectOverlay({
    required BuildContext context,
    required String emoji,
    required LottieComposition composition,
    required LayerLink layerLink,
    required double emojiSize,
    required bool isMe,
    required double effectSize,
    bool enableRandomJitter = true,
    VoidCallback? onRemoved,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return false;

    late OverlayEntry entry;
    bool removed = false;
    void safeRemove() {
      if (!removed) {
        removed = true;
        onRemoved?.call();
        try {
          entry.remove();
        } catch (_) {}
      }
    }

    final Offset jitterOffset;
    if (enableRandomJitter) {
      final random = math.Random();
      final dx = (random.nextDouble() * 8 + 8) * (random.nextBool() ? 1 : -1);
      final dy = (random.nextDouble() * 8 + 8) * (random.nextBool() ? 1 : -1);
      jitterOffset = Offset(dx, dy);
    } else {
      jitterOffset = Offset.zero;
    }

    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        top: 0,
        width: effectSize,
        height: effectSize,
        child: _EmojiEffectWidget(
          emoji: emoji,
          composition: composition,
          layerLink: layerLink,
          emojiSize: emojiSize,
          customEffectSize: effectSize,
          isMe: isMe,
          jitterOffset: jitterOffset,
          onComplete: safeRemove,
        ),
      ),
    );

    overlay.insert(entry);
    return true;
  }
}

class _EmojiEffectWidget extends StatefulWidget {
  static const double defaultEffectSize = 384.0;

  final String emoji;
  final LottieComposition composition;
  final LayerLink layerLink;
  final double emojiSize;
  final double customEffectSize;
  final bool isMe;
  final Offset jitterOffset;
  final VoidCallback onComplete;

  const _EmojiEffectWidget({
    required this.emoji,
    required this.composition,
    required this.layerLink,
    required this.emojiSize,
    this.customEffectSize = defaultEffectSize,
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
    if (widget.emoji.isNotEmpty) {
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
    widget.onComplete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double effectSize = widget.customEffectSize;

    // In Telegram's 512x512 emoji & premium sticker effect compositions, the emitter origin sits
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

