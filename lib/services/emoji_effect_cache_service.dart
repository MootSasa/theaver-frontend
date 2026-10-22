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
/// of both vector animated emojis (`/api/animated-emojis`) and full-screen
/// Lottie emoji effects (`/api/emoji-effects`) from the backend server (Telegram-style).
class EmojiEffectCacheService {
  static final EmojiEffectCacheService instance = EmojiEffectCacheService._internal();
  EmojiEffectCacheService._internal() {
    _rebuildEffectLookup();
    _rebuildAnimatedLookup();
  }

  static const String _prefsEffectsIndexKey = 'cached_emoji_effects_index_v1';
  static const String _prefsAnimatedIndexKey = 'cached_animated_emojis_index_v1';

  /// Built-in default index of server emoji effect codepoints.
  static const Set<String> _defaultEffects = {
    '1f192', '1f31a', '1f32d', '1f346', '1f34c', '1f351', '1f353', '1f37e',
    '1f382', '1f383', '1f384', '1f385', '1f386', '1f388', '1f389', '1f38a',
    '1f3c6', '1f3f4-200d-2620', '1f433', '1f43e', '1f440', '1f445', '1f44b', '1f44c',
    '1f44d', '1f44e', '1f44f', '1f451', '1f468-200d-1f4bb', '1f46e-200d-2642', '1f47b', '1f47e',
    '1f483', '1f485', '1f48a', '1f48b', '1f48e', '1f490', '1f494', '1f498',
    '1f4a5', '1f4a9', '1f4af', '1f4b8', '1f51d', '1f51e', '1f525', '1f54a',
    '1f57a', '1f595', '1f596', '1f5ff', '1f601', '1f602', '1f607', '1f608',
    '1f60a', '1f60d', '1f60e', '1f610', '1f618', '1f621', '1f622', '1f628',
    '1f62b', '1f62d', '1f631', '1f634', '1f635-200d-1f4ab', '1f648', '1f649', '1f64a',
    '1f64f', '1f90c', '1f90d', '1f90e', '1f911', '1f912', '1f913', '1f914',
    '1f915', '1f917', '1f918', '1f91d', '1f921', '1f923', '1f925', '1f926',
    '1f926-200d-2640', '1f926-200d-2642', '1f928', '1f929', '1f92a', '1f92c', '1f92d', '1f92e',
    '1f92f', '1f937', '1f937-200d-2640', '1f937-200d-2642', '1f970', '1f971', '1f973', '1f974',
    '1f975', '1f976', '1f984', '1faa9', '1fae0', '1fae1', '1fae6', '1fae8',
    '1faf5', '1faf6', '2603', '261d', '26a1', '2705', '270c', '270d',
    '2728', '2744', '2764', '2764-200d-1f525', '31-20e3',
  };

  /// Built-in default index of server vector animated emoji codepoints.
  static const Set<String> _defaultAnimatedEmojis = {
    '1f192', '1f193', '1f195', '1f197', '1f199', '1f308', '1f311', '1f312',
    '1f313', '1f314', '1f315', '1f316', '1f317', '1f318', '1f31a', '1f31b',
    '1f31c', '1f31d', '1f31e', '1f31f', '1f321', '1f321-fe0f', '1f324', '1f324-fe0f',
    '1f325', '1f325-fe0f', '1f326', '1f326-fe0f', '1f327', '1f327-fe0f', '1f328', '1f328-fe0f',
    '1f329', '1f329-fe0f', '1f32d', '1f32e', '1f331', '1f332', '1f333', '1f334',
    '1f335', '1f337', '1f338', '1f339', '1f33a', '1f33c', '1f33f', '1f340',
    '1f346', '1f34c', '1f351', '1f353', '1f354', '1f355', '1f356', '1f357', '1f358',
    '1f359', '1f35f', '1f361', '1f362', '1f363', '1f365', '1f366', '1f369',
    '1f36a', '1f36b', '1f36d', '1f36e', '1f370', '1f371', '1f373', '1f377',
    '1f378', '1f379', '1f37c', '1f37d', '1f37d-fe0f', '1f37e', '1f37f', '1f382',
    '1f383', '1f384', '1f385', '1f386', '1f387', '1f388', '1f389', '1f38a',
    '1f393', '1f396', '1f396-fe0f', '1f397', '1f399', '1f399-fe0f', '1f39f', '1f39f-fe0f',
    '1f3a2', '1f3a4', '1f3a8', '1f3a9', '1f3ab', '1f3ac', '1f3ad', '1f3ae',
    '1f3b5', '1f3b6', '1f3c0', '1f3c1', '1f3c5', '1f3c6', '1f3d5', '1f3d5-fe0f',
    '1f3d6', '1f3db', '1f3db-fe0f', '1f3dd', '1f3e0', '1f3f3', '1f3f3-fe0f', '1f3f4',
    '1f3f4-200d-2620', '1f3f4-200d-2620-fe0f', '1f3f5', '1f402', '1f404', '1f405', '1f406', '1f407',
    '1f408', '1f408-200d-2b1b', '1f40c', '1f40d', '1f40e', '1f414', '1f419', '1f41b',
    '1f41c', '1f41d', '1f41e', '1f41f', '1f420', '1f422', '1f423', '1f424',
    '1f425', '1f426', '1f427', '1f428', '1f42d', '1f42f', '1f430', '1f431',
    '1f433', '1f434', '1f435', '1f436', '1f437', '1f438', '1f439', '1f43b',
    '1f43b-200d-2744', '1f43b-200d-2744-fe0f', '1f43c', '1f43d', '1f43e', '1f440', '1f441', '1f441-fe0f',
    '1f442', '1f443', '1f444', '1f445', '1f446', '1f447', '1f448', '1f449',
    '1f44a', '1f44b', '1f44c', '1f44d', '1f44e', '1f44f', '1f450', '1f451',
    '1f45b', '1f45c', '1f460', '1f463', '1f464', '1f465', '1f468-200d-1f3eb', '1f468-200d-1f469-200d-1f467-200d-1f466',
    '1f468-200d-1f4bb', '1f468-200d-2695', '1f468-200d-2695-fe0f', '1f469-200d-1f4bb', '1f469-200d-2695', '1f469-200d-2695-fe0f', '1f46e-200d-2640', '1f46e-200d-2640-fe0f',
    '1f46e-200d-2642', '1f46e-200d-2642-fe0f', '1f475', '1f476', '1f479', '1f47a', '1f47b', '1f47d',
    '1f47e', '1f47f', '1f480', '1f483', '1f484', '1f485', '1f489', '1f48a',
    '1f48b', '1f48c', '1f48e', '1f490', '1f493', '1f494', '1f495', '1f496',
    '1f497', '1f498', '1f499', '1f49a', '1f49b', '1f49c', '1f49d', '1f49e',
    '1f49f', '1f4a1', '1f4a2', '1f4a3', '1f4a4', '1f4a5', '1f4a9', '1f4aa',
    '1f4ab', '1f4ac', '1f4ad', '1f4af', '1f4b0', '1f4b1', '1f4b8', '1f4bb',
    '1f4bc', '1f4c1', '1f4c2', '1f4c6', '1f4c8', '1f4c9', '1f4ca', '1f4d6',
    '1f4da', '1f4dd', '1f4de', '1f4e3', '1f4e4', '1f4e5', '1f4e8', '1f4ec',
    '1f4ed', '1f4f0', '1f4f1', '1f4f2', '1f4fa', '1f50d', '1f50e', '1f510',
    '1f511', '1f51d', '1f51e', '1f525', '1f52c', '1f52d', '1f52e', '1f54a',
    '1f54a-fe0f', '1f577', '1f578', '1f578-fe0f', '1f57a', '1f590', '1f595', '1f596',
    '1f5a4', '1f5a8', '1f5a8-fe0f', '1f5c2', '1f5c2-fe0f', '1f5dd', '1f5e3', '1f5e3-fe0f',
    '1f5ef', '1f5ef-fe0f', '1f5f3', '1f5f3-fe0f', '1f5ff', '1f600', '1f601', '1f602',
    '1f603', '1f604', '1f605', '1f606', '1f607', '1f608', '1f609', '1f60a',
    '1f60b', '1f60c', '1f60d', '1f60e', '1f60f', '1f610', '1f611', '1f612',
    '1f613', '1f614', '1f615', '1f616', '1f617', '1f618', '1f619', '1f61a',
    '1f61b', '1f61c', '1f61d', '1f61e', '1f61f', '1f620', '1f621', '1f622',
    '1f623', '1f624', '1f625', '1f626', '1f627', '1f628', '1f629', '1f62a',
    '1f62b', '1f62c', '1f62d', '1f62e', '1f62e-200d-1f4a8', '1f62f', '1f630', '1f631',
    '1f632', '1f633', '1f634', '1f635', '1f635-200d-1f4ab', '1f636', '1f636-200d-1f32b', '1f636-200d-1f32b-fe0f',
    '1f637', '1f638', '1f639', '1f63a', '1f63b', '1f63c', '1f63d', '1f63e',
    '1f63f', '1f640', '1f641', '1f642', '1f643', '1f644', '1f648', '1f649',
    '1f64a', '1f64c', '1f64f', '1f680', '1f682', '1f691', '1f693', '1f695',
    '1f697', '1f6a9', '1f6b9', '1f6ba', '1f6bc', '1f6c2', '1f6c3', '1f6c4',
    '1f6c5', '1f6cd', '1f6cd-fe0f', '1f6d2', '1f6e5', '1f6e5-fe0f', '1f6f7', '1f90c',
    '1f90d', '1f90e', '1f90f', '1f910', '1f911', '1f912', '1f913', '1f914',
    '1f915', '1f916', '1f917', '1f918', '1f919', '1f91a', '1f91b', '1f91c',
    '1f91d', '1f91e', '1f91f', '1f920', '1f921', '1f922', '1f923', '1f924',
    '1f925', '1f926', '1f926-200d-2640', '1f926-200d-2640-fe0f', '1f926-200d-2642', '1f926-200d-2642-fe0f', '1f927', '1f928',
    '1f929', '1f92a', '1f92b', '1f92c', '1f92d', '1f92e', '1f92f', '1f930',
    '1f932', '1f936', '1f937', '1f937-200d-2640', '1f937-200d-2640-fe0f', '1f937-200d-2642', '1f937-200d-2642-fe0f', '1f942',
    '1f943', '1f947', '1f948', '1f949', '1f959', '1f95b', '1f95e', '1f964',
    '1f967', '1f968', '1f96a', '1f96b', '1f970', '1f971', '1f972', '1f973',
    '1f974', '1f975', '1f976', '1f978', '1f979', '1f97a', '1f981', '1f983',
    '1f984', '1f986', '1f987', '1f989', '1f98a', '1f98b', '1f98c', '1f98d',
    '1f990', '1f991', '1f992', '1f993', '1f994', '1f995', '1f996', '1f997',
    '1f998', '1f999', '1f99c', '1f99d', '1f99e', '1f99f', '1f9a0', '1f9a2',
    '1f9a9', '1f9ac', '1f9ad', '1f9b4', '1f9b5', '1f9b6', '1f9b7', '1f9bb',
    '1f9be', '1f9bf', '1f9c1', '1f9c3', '1f9c9', '1f9cb', '1f9d0', '1f9d1-200d-1f384',
    '1f9d1-200d-1f4bb', '1f9db', '1f9db-200d-2640', '1f9db-200d-2640-fe0f', '1f9db-200d-2642', '1f9db-200d-2642-fe0f', '1f9df', '1f9df-200d-2640',
    '1f9df-200d-2640-fe0f', '1f9df-200d-2642', '1f9df-200d-2642-fe0f', '1f9e1', '1f9e8', '1f9ea', '1f9ed', '1f9ee',
    '1f9f0', '1f9f3', '1f9fb', '1f9fc', '1f9fd', '1fa75', '1fa76', '1fa77',
    '1fa7a', '1fa84', '1fa96', '1fa99', '1faa9', '1faaa', '1fab2', '1fab3',
    '1fac2', '1fad7', '1fae0', '1fae1', '1fae2', '1fae3', '1fae4', '1fae5',
    '1fae6', '1fae8', '1faf0', '1faf1', '1faf2', '1faf3', '1faf4', '1faf5',
    '1faf6', '1faf7', '1faf8', '203c', '203c-fe0f', '2049', '2049-fe0f', '231b',
    '2328', '2328-fe0f', '23f3', '2600', '2600-fe0f', '2601', '2601-fe0f', '2603',
    '2603-fe0f', '260e', '260e-fe0f', '2611', '2611-fe0f', '2615', '2618', '2618-fe0f',
    '261d', '261d-fe0f', '2620', '2620-fe0f', '2639', '2639-fe0f', '263a', '263a-fe0f',
    '2648', '2649', '264a', '264b', '264c', '264d', '264e', '264f',
    '2650', '2651', '2652', '2653', '2668', '2668-fe0f', '26a1', '26a1-fe0f',
    '26b0', '26b0-fe0f', '26bd', '26c4', '26c4-fe0f', '26c5', '26c8', '26ce',
    '2705', '2708', '2708-fe0f', '270a', '270b', '270c', '270c-fe0f', '270d',
    '270d-fe0f', '270f', '270f-fe0f', '2714', '2714-fe0f', '2728', '2744', '2744-fe0f',
    '274c', '2753', '2754', '2755', '2757', '2757-fe0f', '2763', '2763-fe0f',
    '2764', '2764-200d-1f525', '2764-200d-1fa79', '2764-fe0f', '2764-fe0f-200d-1f525', '2764-fe0f-200d-1fa79', '2b50', '2b50-fe0f',
  };

  final Set<String> _availableEffects = {..._defaultEffects};
  final Map<String, String> _effectLookup = {};
  final Map<String, LottieComposition> _effectsMemoryCache = {};
  final Map<String, Future<LottieComposition?>> _effectsInFlight = {};

  final Set<String> _availableAnimatedEmojis = {..._defaultAnimatedEmojis};
  final Map<String, String> _animatedLookup = {};
  final Map<String, LottieComposition> _animatedMemoryCache = {};
  final Map<String, Future<LottieComposition?>> _animatedInFlight = {};

  final Map<String, Uint8List> _staticEmojiMemoryCache = {};
  final Map<String, Future<Uint8List?>> _staticEmojiInFlight = {};
  final Set<String> _missingStaticEmojis = {};

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  bool _indexSynced = false;
  Directory? _effectsCacheDir;
  Directory? _animatedCacheDir;
  Directory? _staticCacheDir;

  static String _stripFe0f(String cp) {
    var s = cp.replaceAll('-fe0f-', '-');
    if (s.endsWith('-fe0f')) s = s.substring(0, s.length - 5);
    if (s.startsWith('fe0f-')) s = s.substring(5);
    return s;
  }

  void _rebuildEffectLookup() {
    _effectLookup.clear();
    for (final cp in _availableEffects) {
      _effectLookup[cp] = cp;
      final stripped = _stripFe0f(cp);
      if (stripped.isNotEmpty) {
        _effectLookup.putIfAbsent(stripped, () => cp);
      }
    }
  }

  void _rebuildAnimatedLookup() {
    _animatedLookup.clear();
    for (final cp in _availableAnimatedEmojis) {
      _animatedLookup[cp] = cp;
      final stripped = _stripFe0f(cp);
      if (stripped.isNotEmpty) {
        _animatedLookup.putIfAbsent(stripped, () => cp);
      }
    }
  }

  /// Synchronizes the available emoji effects and animated emojis indices with the server in background.
  Future<void> ensureIndexSynced() async {
    if (_indexSynced) return;
    _indexSynced = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEffects = prefs.getStringList(_prefsEffectsIndexKey);
      if (savedEffects != null && savedEffects.isNotEmpty) {
        _availableEffects.addAll(savedEffects);
        _rebuildEffectLookup();
      }
      final savedAnimated = prefs.getStringList(_prefsAnimatedIndexKey);
      if (savedAnimated != null && savedAnimated.isNotEmpty) {
        _availableAnimatedEmojis.addAll(savedAnimated);
        _rebuildAnimatedLookup();
      }

      // Sync emoji effects index
      try {
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
            _rebuildEffectLookup();
            await prefs.setStringList(_prefsEffectsIndexKey, _availableEffects.toList());
          }
        }
      } catch (e) {
        debugPrint('EmojiEffectCacheService: effects index sync skipped: $e');
      }

      // Sync animated emojis index
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '${AppConfig.baseUrl}/api/animated-emojis',
        );
        final data = response.data;
        if (data != null && data['success'] == true && data['emojis'] is List) {
          final emojis = (data['emojis'] as List)
              .map((e) => e.toString().toLowerCase().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (emojis.isNotEmpty) {
            _availableAnimatedEmojis
              ..clear()
              ..addAll(_defaultAnimatedEmojis)
              ..addAll(emojis);
            _rebuildAnimatedLookup();
            await prefs.setStringList(_prefsAnimatedIndexKey, _availableAnimatedEmojis.toList());
          }
        }
      } catch (e) {
        debugPrint('EmojiEffectCacheService: animated emojis index sync skipped: $e');
      }
    } catch (e) {
      debugPrint('EmojiEffectCacheService: index sync failed: $e');
    }
  }

  /// Resolves the canonical server codepoint for an emoji effect if one exists.
  String? resolveEffectCodepoint(String emoji) {
    final lower = emoji.trim().toLowerCase();
    if (_effectLookup.containsKey(lower)) {
      return _effectLookup[lower];
    }
    for (final candidate in EmojiUtils.codepointCandidates(emoji)) {
      final found = _effectLookup[candidate];
      if (found != null) return found;
    }
    return null;
  }

  /// Resolves the canonical server codepoint for a vector animated emoji if one exists.
  String? resolveAnimatedEmojiCodepoint(String emoji) {
    final lower = emoji.trim().toLowerCase();
    if (_animatedLookup.containsKey(lower)) {
      return _animatedLookup[lower];
    }
    for (final candidate in EmojiUtils.codepointCandidates(emoji)) {
      final found = _animatedLookup[candidate];
      if (found != null) return found;
    }
    return null;
  }

  /// Returns true if the given emoji has an interactive effect animation on the server.
  bool hasEffect(String emoji) => resolveEffectCodepoint(emoji) != null;

  /// Returns true if the given emoji has a vector animated emoji on the server.
  bool hasAnimatedEmoji(String emoji) => resolveAnimatedEmojiCodepoint(emoji) != null;

  /// Returns the already-loaded effect [LottieComposition] from RAM if available.
  LottieComposition? getCachedCompositionSync(String emoji) {
    final cp = resolveEffectCodepoint(emoji);
    if (cp == null) return null;
    return _effectsMemoryCache[cp];
  }

  /// Returns the already-loaded animated emoji [LottieComposition] from RAM if available.
  LottieComposition? getCachedAnimatedEmojiSync(String emoji) {
    final cp = resolveAnimatedEmojiCodepoint(emoji);
    if (cp == null) return null;
    return _animatedMemoryCache[cp];
  }

  /// Returns the already-loaded high-res static emoji PNG bytes from RAM if available.
  Uint8List? getCachedStaticEmojiSync(String emoji) {
    for (final candidate in EmojiUtils.codepointCandidates(emoji)) {
      final bytes = _staticEmojiMemoryCache[candidate];
      if (bytes != null) return bytes;
    }
    return null;
  }

  /// Returns true if the server returned 404 for this static emoji during the current session.
  bool isStaticEmojiMissing(String emoji) {
    final cp = EmojiUtils.emojiToCodepoint(emoji);
    return cp.isEmpty || _missingStaticEmojis.contains(cp);
  }

  /// Warms up the local disk and memory cache for the given emoji's effect in background.
  void prefetchEffect(String emoji) {
    final cp = resolveEffectCodepoint(emoji);
    if (cp == null || _effectsMemoryCache.containsKey(cp)) return;
    getEffectComposition(emoji);
  }

  /// Warms up the local disk and memory cache for the given vector animated emoji in background.
  void prefetchAnimatedEmoji(String emoji) {
    final cp = resolveAnimatedEmojiCodepoint(emoji);
    if (cp == null || _animatedMemoryCache.containsKey(cp)) return;
    getAnimatedEmojiComposition(emoji);
  }

  /// Gets the high-res 160x160 static emoji PNG bytes for [emoji], checking RAM cache first,
  /// then local disk cache, and finally downloading from `/api/static-emojis/:codepoint`.
  Future<Uint8List?> getStaticEmojiBytes(String emoji) {
    final candidates = EmojiUtils.codepointCandidates(emoji);
    if (candidates.isEmpty) return SynchronousFuture<Uint8List?>(null);

    final primaryCp = candidates.first;
    if (_missingStaticEmojis.contains(primaryCp)) {
      return SynchronousFuture<Uint8List?>(null);
    }

    final cached = getCachedStaticEmojiSync(emoji);
    if (cached != null) {
      return SynchronousFuture<Uint8List?>(cached);
    }

    return _staticEmojiInFlight.putIfAbsent(primaryCp, () async {
      try {
        return await _loadOrDownloadStaticEmoji(primaryCp, candidates);
      } finally {
        _staticEmojiInFlight.remove(primaryCp);
      }
    });
  }

  /// Gets the effect [LottieComposition] for [emoji], checking RAM cache first,
  /// then local disk cache, and finally downloading from `/api/emoji-effects/:codepoint`.
  Future<LottieComposition?> getEffectComposition(String emoji) {
    ensureIndexSynced();
    final cp = resolveEffectCodepoint(emoji);
    if (cp == null) return SynchronousFuture<LottieComposition?>(null);

    final cached = _effectsMemoryCache[cp];
    if (cached != null) {
      return SynchronousFuture<LottieComposition?>(cached);
    }

    return _effectsInFlight.putIfAbsent(cp, () async {
      try {
        return await _loadOrDownload(
          codepoint: cp,
          endpointPrefix: '/api/emoji-effects',
          getCacheDir: _getEffectsCacheDirectory,
          memoryCache: _effectsMemoryCache,
        );
      } finally {
        _effectsInFlight.remove(cp);
      }
    });
  }

  /// Gets the vector animated emoji [LottieComposition] for [emoji], checking RAM cache first,
  /// then local disk cache, and finally downloading from `/api/animated-emojis/:codepoint`.
  Future<LottieComposition?> getAnimatedEmojiComposition(String emoji) {
    ensureIndexSynced();
    final cp = resolveAnimatedEmojiCodepoint(emoji);
    if (cp == null) return SynchronousFuture<LottieComposition?>(null);

    final cached = _animatedMemoryCache[cp];
    if (cached != null) {
      return SynchronousFuture<LottieComposition?>(cached);
    }

    return _animatedInFlight.putIfAbsent(cp, () async {
      try {
        return await _loadOrDownload(
          codepoint: cp,
          endpointPrefix: '/api/animated-emojis',
          getCacheDir: _getAnimatedCacheDirectory,
          memoryCache: _animatedMemoryCache,
        );
      } finally {
        _animatedInFlight.remove(cp);
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

  Future<Directory> _getAnimatedCacheDirectory() async {
    if (_animatedCacheDir != null && await _animatedCacheDir!.exists()) {
      return _animatedCacheDir!;
    }
    final appCache = await getApplicationCacheDirectory();
    final dir = Directory(path.join(appCache.path, 'animated_emojis'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _animatedCacheDir = dir;
    return dir;
  }

  Future<Directory> _getStaticCacheDirectory() async {
    if (_staticCacheDir != null && await _staticCacheDir!.exists()) {
      return _staticCacheDir!;
    }
    final appCache = await getApplicationCacheDirectory();
    final dir = Directory(path.join(appCache.path, 'static_emojis'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _staticCacheDir = dir;
    return dir;
  }

  Future<Uint8List?> _loadOrDownloadStaticEmoji(
    String primaryCp,
    List<String> candidates,
  ) async {
    File? diskFile;
    if (!kIsWeb) {
      try {
        final dir = await _getStaticCacheDirectory();
        for (final candidate in candidates) {
          final f = File(path.join(dir.path, '$candidate.png'));
          if (await f.exists()) {
            final length = await f.length();
            if (length > 0) {
              final bytes = await f.readAsBytes();
              for (final c in candidates) {
                _staticEmojiMemoryCache[c] = bytes;
              }
              return bytes;
            } else {
              await f.delete();
            }
          }
        }
        diskFile = File(path.join(dir.path, '$primaryCp.png'));
      } catch (e) {
        debugPrint('EmojiEffectCacheService: static emoji disk cache read error for $primaryCp: $e');
      }
    }

    try {
      final url = '${AppConfig.baseUrl}/api/static-emojis/$primaryCp';
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        return null;
      }

      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      for (final c in candidates) {
        _staticEmojiMemoryCache[c] = bytes;
      }

      if (!kIsWeb && diskFile != null) {
        try {
          final tempFile = File('${diskFile.path}.tmp');
          await tempFile.writeAsBytes(bytes, flush: true);
          await tempFile.rename(diskFile.path);
        } catch (e) {
          debugPrint('EmojiEffectCacheService: failed to save static emoji $primaryCp to disk: $e');
        }
      }

      return bytes;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _missingStaticEmojis.add(primaryCp);
      } else {
        debugPrint('EmojiEffectCacheService: failed to download static emoji $primaryCp: $e');
      }
      return null;
    } catch (e) {
      debugPrint('EmojiEffectCacheService: failed to download static emoji $primaryCp: $e');
      return null;
    }
  }

  Future<LottieComposition?> _loadOrDownload({
    required String codepoint,
    required String endpointPrefix,
    required Future<Directory> Function() getCacheDir,
    required Map<String, LottieComposition> memoryCache,
  }) async {
    // 1. Check local disk cache on native platforms
    File? diskFile;
    if (!kIsWeb) {
      try {
        final dir = await getCacheDir();
        diskFile = File(path.join(dir.path, '$codepoint.json'));
        if (await diskFile.exists()) {
          final length = await diskFile.length();
          if (length > 0) {
            final bytes = await diskFile.readAsBytes();
            final composition = await LottieComposition.fromBytes(bytes);
            memoryCache[codepoint] = composition;
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
      final url = '${AppConfig.baseUrl}$endpointPrefix/$codepoint';
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
      memoryCache[codepoint] = composition;

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
      debugPrint('EmojiEffectCacheService: failed to download $endpointPrefix/$codepoint: $e');
      return null;
    }
  }

  /// Clears in-memory cached compositions and static PNGs (called when user clears cache).
  void clearMemoryCache() {
    _effectsMemoryCache.clear();
    _animatedMemoryCache.clear();
    _staticEmojiMemoryCache.clear();
    _missingStaticEmojis.clear();
  }
}
