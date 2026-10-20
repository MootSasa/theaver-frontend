import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/emoji_utils.dart';

/// Service that manages downloading, local disk caching, and in-memory caching
/// of full-screen Lottie emoji effects from the backend server (Telegram-style).
class EmojiEffectCacheService {
  static final EmojiEffectCacheService instance = EmojiEffectCacheService._internal();
  EmojiEffectCacheService._internal();

  static const String _prefsIndexKey = 'cached_emoji_effects_index_v1';

  /// Built-in default index of server emoji effect codepoints so the client
  /// immediately knows which emojis have effects even before the first network sync.
  static const Set<String> _defaultEffects = {
    '1f192', '1f31a', '1f32d', '1f346', '1f34c', '1f351', '1f353', '1f37e',
    '1f382', '1f383', '1f384', '1f385', '1f386', '1f388', '1f389', '1f38a',
    '1f3c6', '1f3f4-200d-2620', '1f433', '1f43e', '1f440', '1f445', '1f44b',
    '1f44c', '1f44d', '1f44e', '1f44f', '1f451', '1f468-200d-1f4bb',
    '1f46e-200d-2642', '1f47b', '1f47e', '1f483', '1f485', '1f48a', '1f48b',
    '1f48e', '1f490', '1f494', '1f498', '1f4a5', '1f4a9', '1f4af', '1f4b8',
    '1f51d', '1f51e', '1f525', '1f54a', '1f57a', '1f595', '1f596', '1f5ff',
    '1f601', '1f602', '1f607', '1f608', '1f60a', '1f60d', '1f60e', '1f610',
    '1f618', '1f621', '1f622', '1f628', '1f62b', '1f62d', '1f631', '1f634',
    '1f635-200d-1f4ab', '1f648', '1f649', '1f64a', '1f64f', '1f90c', '1f90d',
    '1f90e', '1f911', '1f912', '1f913', '1f914', '1f915', '1f917', '1f918',
    '1f91d', '1f921', '1f923', '1f925', '1f926-200d-2642', '1f928', '1f929',
    '1f92a', '1f92c', '1f92d', '1f92e', '1f92f', '1f937-200d-2640',
    '1f937-200d-2642', '1f937', '1f970', '1f971', '1f973', '1f974', '1f975',
    '1f976', '1f984', '1faa9', '1fae0', '1fae1', '1fae6', '1fae8', '1faf5',
    '1faf6', '2603', '261d', '26a1', '2705', '270c', '270d', '2728', '2744',
    '2764-200d-1f525', '2764',
  };

  final Set<String> _availableEffects = {..._defaultEffects};
  final Map<String, LottieComposition> _memoryCache = {};
  final Map<String, Future<LottieComposition?>> _inFlight = {};

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  bool _indexSynced = false;
  Directory? _effectsCacheDir;

  /// Synchronizes the available emoji effects index with the server in background.
  Future<void> ensureIndexSynced() async {
    if (_indexSynced) return;
    _indexSynced = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedList = prefs.getStringList(_prefsIndexKey);
      if (savedList != null && savedList.isNotEmpty) {
        _availableEffects.addAll(savedList);
      }

      final response = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.baseUrl}/api/emoji-effects',
      );
      final data = response.data;
      if (data != null && data['success'] == true && data['effects'] is List) {
        final effects = (data['effects'] as List)
            .map((e) => e.toString().toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (effects.isNotEmpty) {
          _availableEffects
            ..clear()
            ..addAll(_defaultEffects)
            ..addAll(effects);
          await prefs.setStringList(_prefsIndexKey, _availableEffects.toList());
        }
      }
    } catch (e) {
      debugPrint('EmojiEffectCacheService: index sync skipped/failed: $e');
    }
  }

  /// Resolves the canonical server codepoint for an emoji if an effect exists.
  String? resolveEffectCodepoint(String emoji) {
    final candidates = EmojiUtils.codepointCandidates(emoji);
    for (final candidate in candidates) {
      if (_availableEffects.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// Returns true if the given emoji has an interactive effect animation.
  bool hasEffect(String emoji) => resolveEffectCodepoint(emoji) != null;

  /// Returns the already-loaded [LottieComposition] from RAM if available.
  LottieComposition? getCachedCompositionSync(String emoji) {
    final cp = resolveEffectCodepoint(emoji);
    if (cp == null) return null;
    return _memoryCache[cp];
  }

  /// Warms up the local disk and memory cache for the given emoji in background.
  void prefetchEffect(String emoji) {
    final cp = resolveEffectCodepoint(emoji);
    if (cp == null || _memoryCache.containsKey(cp)) return;
    getEffectComposition(emoji);
  }

  /// Gets the [LottieComposition] for [emoji], checking RAM cache first,
  /// then local disk cache, and finally downloading from the backend server.
  Future<LottieComposition?> getEffectComposition(String emoji) {
    ensureIndexSynced();
    final cp = resolveEffectCodepoint(emoji);
    if (cp == null) return SynchronousFuture<LottieComposition?>(null);

    final cached = _memoryCache[cp];
    if (cached != null) {
      return SynchronousFuture<LottieComposition?>(cached);
    }

    return _inFlight.putIfAbsent(cp, () async {
      try {
        return await _loadOrDownload(cp);
      } finally {
        _inFlight.remove(cp);
      }
    });
  }

  Future<Directory> _getEffectsCacheDirectory() async {
    if (_effectsCacheDir != null && await _effectsCacheDir!.exists()) {
      return _effectsCacheDir!;
    }
    final appCache = await getApplicationCacheDirectory();
    final dir = Directory(path.join(appCache.path, 'emoji_effects'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _effectsCacheDir = dir;
    return dir;
  }

  Future<LottieComposition?> _loadOrDownload(String codepoint) async {
    // 1. Check local disk cache on native platforms
    File? diskFile;
    if (!kIsWeb) {
      try {
        final dir = await _getEffectsCacheDirectory();
        diskFile = File(path.join(dir.path, '$codepoint.json'));
        if (await diskFile.exists()) {
          final length = await diskFile.length();
          if (length > 0) {
            final bytes = await diskFile.readAsBytes();
            final composition = await LottieComposition.fromBytes(bytes);
            _memoryCache[codepoint] = composition;
            return composition;
          } else {
            await diskFile.delete();
          }
        }
      } catch (e) {
        debugPrint('EmojiEffectCacheService: corrupt disk cache for $codepoint, re-downloading: $e');
        try {
          if (diskFile != null && await diskFile.exists()) {
            await diskFile.delete();
          }
        } catch (_) {}
      }
    }

    // 2. Download from backend server
    try {
      final url = '${AppConfig.baseUrl}/api/emoji-effects/$codepoint';
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        return null;
      }

      final bytes = data is Uint8List ? data : Uint8List.fromList(data);

      // Validate that it's JSON and parse LottieComposition
      final composition = await LottieComposition.fromBytes(bytes);
      _memoryCache[codepoint] = composition;

      // 3. Persist to local disk cache atomically on native platforms
      if (!kIsWeb && diskFile != null) {
        try {
          final tempFile = File('${diskFile.path}.tmp');
          await tempFile.writeAsBytes(bytes, flush: true);
          await tempFile.rename(diskFile.path);
        } catch (e) {
          debugPrint('EmojiEffectCacheService: failed to save $codepoint to disk cache: $e');
        }
      }

      return composition;
    } catch (e) {
      debugPrint('EmojiEffectCacheService: failed to download effect $codepoint: $e');
      return null;
    }
  }

  /// Clears in-memory cached compositions (called when user clears cache).
  void clearMemoryCache() {
    _memoryCache.clear();
  }
}
