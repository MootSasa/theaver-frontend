import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../utils/emoji_utils.dart';

/// Resolved asset indices for the 5 composited layers of the Telegram slot machine (1f3b0).
class SlotReelIndices {
  final int backgroundIndex; // 1 (idle) or 2 (win)
  final int leverIndex; // 3 (front-pull)
  final int leftSpinIndex; // 9 (left_spinload)
  final int leftOutcomeIndex; // 4..8
  final int centerSpinIndex; // 15 (middle_spinload)
  final int centerOutcomeIndex; // 10..14
  final int rightSpinIndex; // 21 (right_spinload)
  final int rightOutcomeIndex; // 16..20
  final bool isWin;
  final bool is777;

  const SlotReelIndices({
    required this.backgroundIndex,
    required this.leverIndex,
    required this.leftSpinIndex,
    required this.leftOutcomeIndex,
    required this.centerSpinIndex,
    required this.centerOutcomeIndex,
    required this.rightSpinIndex,
    required this.rightOutcomeIndex,
    required this.isWin,
    required this.is777,
  });
}

/// Service managing client-side disk & RAM caching of interactive Telegram dice
/// animations (🎲, 🎯, 🏀, ⚽, 🎳, 🎰) fetched on-demand from the backend server.
class DiceCacheService {
  static final DiceCacheService instance = DiceCacheService._internal();
  DiceCacheService._internal();

  final Map<String, LottieComposition> _memoryCache = {};
  final Map<String, Future<LottieComposition?>> _inFlight = {};
  Directory? _diskCacheDir;

  Dio get _dio => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.bytes,
        ),
      );

  Future<Directory> _getCacheDirectory() async {
    if (_diskCacheDir != null) return _diskCacheDir!;
    if (kIsWeb) {
      throw UnsupportedError('File disk cache is not supported on Web');
    }
    final appCache = await getApplicationCacheDirectory();
    final dir = Directory(path.join(appCache.path, 'dice_emojis'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _diskCacheDir = dir;
    return dir;
  }

  /// Calculates the asset indices for the 5 layers of the Telegram slot machine (🎰).
  /// [value] is in the range 1..64.
  static SlotReelIndices getSlotIndices(int value) {
    final int raw = (value - 1).clamp(0, 63);
    final int leftRaw = raw & 3;
    final int centerRaw = (raw >> 2) & 3;
    final int rightRaw = (raw >> 4) & 3;

    final bool is777 = (leftRaw == 3 && centerRaw == 3 && rightRaw == 3);
    final bool isWin = (leftRaw == centerRaw && centerRaw == rightRaw);

    // Left reel: 0=BAR(6), 1=BERRIES(7), 2=LEMON(8), 3=SEVEN(4 if 777 else 5)
    int leftOutcome;
    switch (leftRaw) {
      case 0: leftOutcome = 6; break;
      case 1: leftOutcome = 7; break;
      case 2: leftOutcome = 8; break;
      case 3:
      default:
        leftOutcome = is777 ? 4 : 5;
        break;
    }

    // Center reel: 0=BAR(12), 1=BERRIES(13), 2=LEMON(14), 3=SEVEN(10 if 777 else 11)
    int centerOutcome;
    switch (centerRaw) {
      case 0: centerOutcome = 12; break;
      case 1: centerOutcome = 13; break;
      case 2: centerOutcome = 14; break;
      case 3:
      default:
        centerOutcome = is777 ? 10 : 11;
        break;
    }

    // Right reel: 0=BAR(18), 1=BERRIES(19), 2=LEMON(20), 3=SEVEN(16 if 777 else 17)
    int rightOutcome;
    switch (rightRaw) {
      case 0: rightOutcome = 18; break;
      case 1: rightOutcome = 19; break;
      case 2: rightOutcome = 20; break;
      case 3:
      default:
        rightOutcome = is777 ? 16 : 17;
        break;
    }

    return SlotReelIndices(
      backgroundIndex: isWin ? 2 : 1,
      leverIndex: 3,
      leftSpinIndex: 9,
      leftOutcomeIndex: leftOutcome,
      centerSpinIndex: 15,
      centerOutcomeIndex: centerOutcome,
      rightSpinIndex: 21,
      rightOutcomeIndex: rightOutcome,
      isWin: isWin,
      is777: is777,
    );
  }

  /// Calculates the asset index (1 = rolling animation, 2..N = outcome animation)
  /// for a given dice emoji and outcome value.
  static int getOutcomeIndex(String emoji, int value) {
    // Standard dice: 🎲, 🎯, 🏀, ⚽, 🎳
    // value 1..N maps to index 2..(N+1)
    return value + 1;
  }

  /// Returns cached [LottieComposition] from RAM or disk, or downloads it from the server.
  /// [index]: 1 for rolling loop, >= 2 for specific outcome.
  Future<LottieComposition?> getDiceComposition(String emoji, int index) async {
    final cp = EmojiUtils.diceCodepoint(emoji);
    if (cp == null) return null;

    final key = '${cp}_$index';

    // 1. Memory Cache
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    // 2. In-flight request deduplication
    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _loadOrFetchComposition(cp, index, key);
    _inFlight[key] = future;
    try {
      final comp = await future;
      if (comp != null) {
        _memoryCache[key] = comp;
      }
      return comp;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<LottieComposition?> _loadOrFetchComposition(
    String codepoint,
    int index,
    String key,
  ) async {
    // 3. Disk Cache (Non-Web)
    if (!kIsWeb) {
      try {
        final cacheDir = await _getCacheDirectory();
        final file = File(path.join(cacheDir.path, '$key.json'));
        if (await file.exists() && (await file.length()) > 0) {
          final bytes = await file.readAsBytes();
          final comp = await LottieComposition.fromBytes(bytes);
          return comp;
        }
      } catch (e) {
        debugPrint('DiceCacheService: Error reading disk cache for $key: $e');
      }
    }

    // 4. Download from Backend Server
    final baseUrl = AppConfig.baseUrl;
    final url = '$baseUrl/api/dice-emojis/$codepoint/$index';

    try {
      final response = await _dio.get<List<int>>(url);
      if (response.statusCode == 200 && response.data != null) {
        final bytes = Uint8List.fromList(response.data!);
        final comp = await LottieComposition.fromBytes(bytes);

        // Save to disk asynchronously
        if (!kIsWeb) {
          _saveToDisk(key, bytes);
        }
        return comp;
      }
    } catch (e) {
      debugPrint('DiceCacheService: Failed to fetch dice asset from $url: $e');
    }

    return null;
  }

  void _saveToDisk(String key, Uint8List bytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File(path.join(cacheDir.path, '$key.json'));
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('DiceCacheService: Failed to write disk cache for $key: $e');
    }
  }

  /// Silently prefetches rolling animation and outcome animation for a dice message.
  void prefetchDice(String emoji, int value) {
    final cp = EmojiUtils.diceCodepoint(emoji);
    if (cp == null) return;
    if (cp == '1f3b0') {
      final indices = getSlotIndices(value);
      getDiceComposition(cp, indices.backgroundIndex);
      getDiceComposition(cp, indices.leverIndex);
      getDiceComposition(cp, indices.leftOutcomeIndex);
      getDiceComposition(cp, indices.centerOutcomeIndex);
      getDiceComposition(cp, indices.rightOutcomeIndex);
      return;
    }
    final outcomeIdx = getOutcomeIndex(emoji, value);
    getDiceComposition(emoji, 1); // roll start
    getDiceComposition(emoji, outcomeIdx); // outcome
  }
}
