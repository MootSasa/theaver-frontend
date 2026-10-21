import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../utils/emoji_utils.dart';

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

  /// Calculates the asset index (1 = rolling animation, 2..N = outcome animation)
  /// for a given dice emoji and outcome value.
  static int getOutcomeIndex(String emoji, int value) {
    final cp = EmojiUtils.diceCodepoint(emoji) ?? emoji;
    if (cp == '1f3b0' || emoji == '🎰') {
      // 🎰 Slot machine: 20 outcome files (2..21)
      if (value == 64) return 21; // 777 Jackpot
      if (value == 1) return 2;   // BAR
      if (value == 22) return 7;  // Berries
      if (value == 43) return 13; // Lemons
      return ((value - 1) % 20) + 2;
    }
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
    final outcomeIdx = getOutcomeIndex(emoji, value);
    getDiceComposition(emoji, 1); // roll start
    getDiceComposition(emoji, outcomeIdx); // outcome
  }
}
