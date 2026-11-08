import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../utils/emoji_utils.dart';
import 'auth_service.dart';
import 'emoji_effect_cache_service.dart';
import 'websocket_service.dart';

/// Real-time progress snapshot for Telegram sticker/emoji pack import or custom pack upload.
class StickerImportProgress {
  final int packId;
  final String shortName;
  final String title;
  final int current;
  final int total;
  final String phase;

  const StickerImportProgress({
    this.packId = 0,
    this.shortName = '',
    this.title = '',
    required this.current,
    required this.total,
    this.phase = 'importing',
  });

  double get fraction => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
  int get percent => (fraction * 100).round();
}

/// Represents a single sticker or custom emoji item with semantic metadata.
class StickerItem {
  final int id;
  final int packId;
  final String packShortName;
  final String packTitle;
  final String fileUrl;
  final String thumbnailUrl;
  final List<String> emojiList;
  final String effectEmoji;
  final String effectAnimationUrl;
  final String format; // 'webp', 'animated_webp', 'tgs', 'lottie'
  final int width;
  final int height;
  final int fileSize;
  final int orderIndex;
  final bool hasAlpha;
  final bool isAdaptiveTextColor;
  final String ocrText;
  final String visualDescriptionRu;
  final String visualDescriptionEn;
  final List<String> tags;

  const StickerItem({
    required this.id,
    required this.packId,
    this.packShortName = '',
    this.packTitle = '',
    required this.fileUrl,
    this.thumbnailUrl = '',
    this.emojiList = const ['😀'],
    this.effectEmoji = '',
    this.effectAnimationUrl = '',
    this.format = 'webp',
    this.width = 512,
    this.height = 512,
    this.fileSize = 0,
    this.orderIndex = 0,
    this.hasAlpha = true,
    this.isAdaptiveTextColor = false,
    this.ocrText = '',
    this.visualDescriptionRu = '',
    this.visualDescriptionEn = '',
    this.tags = const [],
  });

  List<String> get emojis => emojiList;

  bool get isVector =>
      format == 'tgs' ||
      format == 'lottie' ||
      fileUrl.endsWith('.tgs') ||
      fileUrl.endsWith('.json') ||
      fileUrl.contains('/api/animated-emojis/');

  bool get isAnimated => isVector || format == 'animated_webp';

  bool get hasPremiumEffect => effectAnimationUrl.trim().isNotEmpty;

  /// Returns the emoji that has a verified full-screen Lottie effect in
  /// [EmojiEffectCacheService] (from `/api/emoji-effects`), or `''` if the
  /// emoji is only a regular/animated emoji without a full-screen effect.
  String get resolvedEffectEmoji {
    final explicit = effectEmoji.trim();
    if (explicit.isNotEmpty &&
        EmojiEffectCacheService.instance.hasEffect(explicit)) {
      return explicit;
    }
    for (final e in emojiList) {
      final trimmed = e.trim();
      if (trimmed.isNotEmpty &&
          EmojiEffectCacheService.instance.hasEffect(trimmed)) {
        return trimmed;
      }
    }
    return '';
  }

  bool get hasAnyFullScreenEffect =>
      hasPremiumEffect || resolvedEffectEmoji.isNotEmpty;

  bool get hasFullscreenEffect => hasAnyFullScreenEffect;

  String get primaryEmoji => emojiList.isNotEmpty ? emojiList.first : '😀';

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    final rawEmojis = json['emoji_list'] ?? json['emojis'];
    final List<String> parsedEmojis = [];
    if (rawEmojis is List) {
      for (final e in rawEmojis) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) parsedEmojis.add(s);
      }
    }
    if (parsedEmojis.isEmpty) {
      final single = json['emoji']?.toString().trim() ?? '';
      if (single.isNotEmpty) {
        parsedEmojis.add(single);
      } else {
        parsedEmojis.add('😀');
      }
    }

    final rawTags = json['tags'];
    final List<String> parsedTags = [];
    if (rawTags is List) {
      for (final t in rawTags) {
        final s = t?.toString().trim() ?? '';
        if (s.isNotEmpty) parsedTags.add(s);
      }
    }

    final fileUrl = json['file_url']?.toString() ?? '';
    final thumbUrl = json['thumbnail_url']?.toString() ?? '';

    final rawEffectEmoji = json['effect_emoji']?.toString().trim() ?? '';
    final verifiedEffectEmoji = rawEffectEmoji.isNotEmpty &&
            EmojiEffectCacheService.instance.hasEffect(rawEffectEmoji)
        ? rawEffectEmoji
        : '';

    return StickerItem(
      id: (json['id'] as num?)?.toInt() ??
          int.tryParse(json['id']?.toString() ?? '') ??
          0,
      packId: (json['pack_id'] as num?)?.toInt() ??
          int.tryParse(json['pack_id']?.toString() ?? '') ??
          0,
      packShortName: json['pack_short_name']?.toString() ?? '',
      packTitle: json['pack_title']?.toString() ?? '',
      fileUrl: fileUrl,
      thumbnailUrl: thumbUrl.isNotEmpty ? thumbUrl : fileUrl,
      emojiList: parsedEmojis,
      effectEmoji: verifiedEffectEmoji,
      effectAnimationUrl: json['effect_animation_url']?.toString() ?? '',
      format: json['format']?.toString() ?? 'webp',
      width: (json['width'] as num?)?.toInt() ?? 512,
      height: (json['height'] as num?)?.toInt() ?? 512,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
      hasAlpha: json['has_alpha'] != false,
      isAdaptiveTextColor: json['is_adaptive_text_color'] == true,
      ocrText: json['ocr_text']?.toString() ?? '',
      visualDescriptionRu: json['visual_description_ru']?.toString() ?? '',
      visualDescriptionEn: json['visual_description_en']?.toString() ?? '',
      tags: parsedTags,
    );
  }

  Map<String, dynamic> toMediaPayload() => {
        'sticker_id': id,
        'pack_id': packId,
        if (packShortName.isNotEmpty) 'pack_short_name': packShortName,
        if (packTitle.isNotEmpty) 'pack_title': packTitle,
        'file_url': fileUrl,
        'thumbnail_url': thumbnailUrl,
        'emoji': primaryEmoji,
        'emoji_list': emojiList,
        if (effectEmoji.isNotEmpty) 'effect_emoji': effectEmoji,
        if (effectAnimationUrl.isNotEmpty)
          'effect_animation_url': effectAnimationUrl,
        'format': format,
        'width': width,
        'height': height,
        'has_alpha': hasAlpha,
      };

  /// Matches query against local multilingual descriptions, OCR, tags, pack title, and emojis across all languages.
  bool matchesLocalQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (EmojiUtils.matchesAnyEmojiInList(emojiList, q)) return true;
    if (ocrText.toLowerCase().contains(q)) return true;
    if (visualDescriptionRu.toLowerCase().contains(q)) return true;
    if (visualDescriptionEn.toLowerCase().contains(q)) return true;
    if (packTitle.toLowerCase().contains(q)) return true;
    if (packShortName.toLowerCase().contains(q)) return true;
    for (final t in tags) {
      if (t.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// Represents a sticker pack or custom emoji pack (always expanded in UI).
class StickerPack {
  final int id;
  final int? ownerId;
  final String shortName;
  final String title;
  final bool isAnimated;
  final bool isCustomEmoji;
  final bool isOfficial;
  final bool isInstalled;
  final String thumbnailUrl;
  final int stickersCount;
  final int installedCount;
  final List<StickerItem> stickers;

  const StickerPack({
    required this.id,
    this.ownerId,
    required this.shortName,
    required this.title,
    this.isAnimated = false,
    this.isCustomEmoji = false,
    this.isOfficial = false,
    this.isInstalled = false,
    this.thumbnailUrl = '',
    this.stickersCount = 0,
    this.installedCount = 0,
    this.stickers = const [],
  });

  List<StickerItem> get items => stickers;
  String get coverUrl => thumbnailUrl;
  int get stickerCount => stickersCount;

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    final rawStickers = json['stickers'];
    final List<StickerItem> parsedStickers = [];
    if (rawStickers is List) {
      for (final item in rawStickers) {
        if (item is Map) {
          parsedStickers.add(
            StickerItem.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    String thumb = json['thumbnail_url']?.toString() ?? '';
    if (thumb.isEmpty && parsedStickers.isNotEmpty) {
      thumb = parsedStickers.first.thumbnailUrl;
    }

    return StickerPack(
      id: (json['id'] as num?)?.toInt() ??
          int.tryParse(json['id']?.toString() ?? '') ??
          0,
      ownerId: (json['owner_id'] as num?)?.toInt(),
      shortName: json['short_name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      isAnimated: json['is_animated'] == true,
      isCustomEmoji: json['is_custom_emoji'] == true,
      isOfficial: json['is_official'] == true,
      isInstalled: json['is_installed'] == true,
      thumbnailUrl: thumb,
      stickersCount: (json['stickers_count'] as num?)?.toInt() ??
          parsedStickers.length,
      installedCount: (json['installed_count'] as num?)?.toInt() ?? 0,
      stickers: parsedStickers,
    );
  }

  StickerPack copyWith({
    bool? isInstalled,
    List<StickerItem>? stickers,
  }) {
    return StickerPack(
      id: id,
      ownerId: ownerId,
      shortName: shortName,
      title: title,
      isAnimated: isAnimated,
      isCustomEmoji: isCustomEmoji,
      isOfficial: isOfficial,
      isInstalled: isInstalled ?? this.isInstalled,
      thumbnailUrl: thumbnailUrl,
      stickersCount: stickers?.length ?? stickersCount,
      installedCount: installedCount,
      stickers: stickers ?? this.stickers,
    );
  }
}

/// Represents a GIF item from Tenor, GIPHY, or the user's Saved GIFs collection.
class GifItemModel {
  final String id;
  final String provider;
  final String title;
  final String url;
  final String previewUrl;
  final String mp4Url;
  final int width;
  final int height;
  final int duration;
  final int useCount;
  final bool isSaved;

  const GifItemModel({
    required this.id,
    this.provider = 'tenor',
    this.title = '',
    required this.url,
    required this.previewUrl,
    this.mp4Url = '',
    this.width = 320,
    this.height = 240,
    this.duration = 0,
    this.useCount = 1,
    this.isSaved = false,
  });

  factory GifItemModel.fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    final prev = json['preview_url']?.toString() ?? '';
    return GifItemModel(
      id: json['id']?.toString() ?? json['gif_id']?.toString() ?? url,
      provider: json['provider']?.toString() ?? 'tenor',
      title: json['title']?.toString() ?? '',
      url: url,
      previewUrl: prev.isNotEmpty ? prev : url,
      mp4Url: json['mp4_url']?.toString() ?? '',
      width: (json['width'] as num?)?.toInt() ?? 320,
      height: (json['height'] as num?)?.toInt() ?? 240,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      useCount: (json['use_count'] as num?)?.toInt() ?? 1,
      isSaved: json['is_saved'] == true,
    );
  }

  Map<String, dynamic> toMediaPayload() => {
        'gif_id': id,
        'provider': provider,
        if (title.isNotEmpty) 'title': title,
        'url': url,
        'preview_url': previewUrl,
        if (mp4Url.isNotEmpty) 'mp4_url': mp4Url,
        'width': width,
        'height': height,
        if (duration > 0) 'duration': duration,
      };
}

/// Active chat input binding for multi-window tiling sidecar routing.
class ChatStickerInputTarget {
  final String chatId;
  final String chatName;
  final String? chatAvatarUrl;
  final TextEditingController? controller;
  final Future<void> Function(StickerItem sticker) onSendSticker;
  final Future<void> Function(GifItemModel gif) onSendGif;
  final void Function(StickerItem customEmoji) onInsertCustomEmoji;
  final void Function(String unicodeEmoji) onInsertUnicodeEmoji;
  final void Function(String unicodeEmoji) onInsertEmoji;
  final VoidCallback onBackspace;

  static Future<void> _noopSticker(StickerItem _) async {}
  static Future<void> _noopGif(GifItemModel _) async {}
  static void _noopCustomEmoji(StickerItem _) {}
  static void _noopString(String _) {}
  static void _noopVoid() {}

  ChatStickerInputTarget({
    required this.chatId,
    String? chatName,
    String? chatTitle,
    String? chatAvatarUrl,
    String? avatarUrl,
    this.controller,
    Future<void> Function(StickerItem sticker)? onSendSticker,
    Future<void> Function(GifItemModel gif)? onSendGif,
    void Function(StickerItem customEmoji)? onInsertCustomEmoji,
    void Function(String unicodeEmoji)? onInsertUnicodeEmoji,
    void Function(String unicodeEmoji)? onInsertEmoji,
    VoidCallback? onBackspace,
  })  : chatName = chatName ?? chatTitle ?? '',
        chatAvatarUrl = chatAvatarUrl ?? avatarUrl,
        onSendSticker = onSendSticker ?? _noopSticker,
        onSendGif = onSendGif ?? _noopGif,
        onInsertCustomEmoji = onInsertCustomEmoji ?? _noopCustomEmoji,
        onInsertUnicodeEmoji =
            onInsertUnicodeEmoji ?? onInsertEmoji ?? _noopString,
        onInsertEmoji = onInsertEmoji ?? onInsertUnicodeEmoji ?? _noopString,
        onBackspace = onBackspace ?? _noopVoid;
}

/// Central client service for Stickers, Custom Emojis, GIFs, TGS/Lottie caching, and multi-pane target routing.
class StickerService extends ChangeNotifier {
  StickerService._internal();
  static final StickerService instance = StickerService._internal();

  List<StickerPack> _installedStickerPacks = [];
  List<StickerPack> _featuredStickerPacks = [];
  List<StickerPack> _installedEmojiPacks = [];
  List<StickerPack> _featuredEmojiPacks = [];

  List<StickerItem> _favoriteStickers = [];
  List<StickerItem> _recentStickers = [];
  List<GifItemModel> _savedGifs = [];
  List<GifItemModel> _trendingGifs = [];

  final Map<int, StickerItem> _stickerByIdCache = {};
  final Map<String, StickerItem> _stickerByFileUrlCache = {};
  final Map<int, Future<StickerItem?>> _inFlightStickerById = {};

  final Map<String, LottieComposition> _lottieCompositionCache = {};
  final Map<String, Future<LottieComposition?>> _inFlightLottieLoads = {};
  final Map<String, ui.Image> _bakedFrameCache = {};
  final Map<String, File> _rasterFileCache = {};
  final Map<String, Future<File?>> _inFlightRasterDownloads = {};

  final Map<String, ChatStickerInputTarget> _chatTargetsByChatId = {};
  ChatStickerInputTarget? _activeInputTarget;
  bool _initialized = false;
  StreamSubscription<WebSocketEvent>? _wsProgressSub;
  final ValueNotifier<StickerImportProgress?> importProgressNotifier =
      ValueNotifier<StickerImportProgress?>(null);

  void _ensureWsProgressSubscription() {
    if (_wsProgressSub != null) return;
    _wsProgressSub = WebSocketService().eventStream.listen((event) {
      if (event.rawType == 'sticker_import_progress') {
        final d = event.data;
        final current = int.tryParse(d['current']?.toString() ?? '') ?? 0;
        final total = int.tryParse(d['total']?.toString() ?? '') ?? 0;
        final packId = int.tryParse(d['pack_id']?.toString() ?? '') ?? 0;
        final shortName = d['short_name']?.toString() ?? '';
        final title = d['title']?.toString() ?? '';
        final phase = d['phase']?.toString() ?? 'importing';
        if (total > 0) {
          importProgressNotifier.value = StickerImportProgress(
            packId: packId,
            shortName: shortName,
            title: title,
            current: current,
            total: total,
            phase: phase,
          );
        }
      }
    });
  }

  List<StickerPack> get installedStickerPacks => _installedStickerPacks;
  List<StickerPack> get featuredStickerPacks => _featuredStickerPacks;
  List<StickerPack> get installedEmojiPacks => _installedEmojiPacks;
  List<StickerPack> get featuredEmojiPacks => _featuredEmojiPacks;
  List<StickerPack> get featuredPacks => [
        ..._featuredStickerPacks,
        ..._featuredEmojiPacks,
      ];
  List<StickerItem> get favoriteStickers => _favoriteStickers;
  List<StickerItem> get recentStickers => _recentStickers;
  List<GifItemModel> get savedGifs => _savedGifs;
  List<GifItemModel> get trendingGifs => _trendingGifs;
  ChatStickerInputTarget? get activeInputTarget => _activeInputTarget;

  void registerChatTarget(ChatStickerInputTarget target) {
    _chatTargetsByChatId[target.chatId] = target;
    _activeInputTarget = target;
    Future.microtask(notifyListeners);
  }

  void registerInputTarget(ChatStickerInputTarget target) {
    registerChatTarget(target);
  }

  void unregisterChatTarget(String chatId) {
    if (_chatTargetsByChatId.remove(chatId) != null) {
      if (_activeInputTarget?.chatId == chatId) {
        _activeInputTarget = _chatTargetsByChatId.values.isNotEmpty
            ? _chatTargetsByChatId.values.last
            : null;
      }
      Future.microtask(notifyListeners);
    }
  }

  void unregisterInputTarget(ChatStickerInputTarget target) {
    unregisterChatTarget(target.chatId);
  }

  ChatStickerInputTarget? getTargetForChat(String? chatId) {
    if (chatId == null || chatId.isEmpty) return _activeInputTarget;
    return _chatTargetsByChatId[chatId] ?? _activeInputTarget;
  }

  /// Resolves relative backend URLs (e.g. `/api/stickers/media/...`) into full HTTP URLs.
  static String resolveUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = AppConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
    if (trimmed.startsWith('/')) {
      return '$base$trimmed';
    }
    return '$base/$trimmed';
  }

  bool isFavorite(Object stickerId) {
    final id = stickerId is int
        ? stickerId
        : int.tryParse(stickerId.toString()) ?? 0;
    return _favoriteStickers.any((s) => s.id == id);
  }

  bool isGifSaved(String gifIdOrUrl, [String? fallbackUrl]) {
    return _savedGifs.any(
      (g) =>
          g.id == gifIdOrUrl ||
          g.url == gifIdOrUrl ||
          (fallbackUrl != null &&
              fallbackUrl.isNotEmpty &&
              (g.id == fallbackUrl || g.url == fallbackUrl)),
    );
  }

  StickerItem? getCachedStickerById(int id) => _stickerByIdCache[id];

  StickerItem? getStickerByIdSync(Object? id) {
    if (id == null) return null;
    final parsed = id is int ? id : int.tryParse(id.toString()) ?? 0;
    return _stickerByIdCache[parsed];
  }

  StickerItem? getStickerByUrlSync(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final full = resolveUrl(rawUrl);
    return _stickerByFileUrlCache[full];
  }

  /// Resolves a distinct static single-frame `.webp` thumbnail URL for [rawFileUrl]
  /// if available (either from [explicitThumbnailUrl] or from the cached [StickerItem]),
  /// so paused/off-screen `animated_webp` stickers never instantiate multi-frame codecs.
  String? resolveStaticThumbnailUrl(
    String rawFileUrl, {
    String? explicitThumbnailUrl,
    Object? stickerId,
  }) {
    final fullFile = resolveUrl(rawFileUrl);
    if (fullFile.isEmpty) return null;
    if (explicitThumbnailUrl != null && explicitThumbnailUrl.trim().isNotEmpty) {
      final fullThumb = resolveUrl(explicitThumbnailUrl);
      if (fullThumb.isNotEmpty &&
          fullThumb != fullFile &&
          !fullThumb.toLowerCase().endsWith('.tgs')) {
        return fullThumb;
      }
    }
    final item = getStickerByIdSync(stickerId) ?? getStickerByUrlSync(fullFile);
    if (item != null && item.thumbnailUrl.trim().isNotEmpty) {
      final fullThumb = resolveUrl(item.thumbnailUrl);
      if (fullThumb.isNotEmpty &&
          fullThumb != fullFile &&
          !fullThumb.toLowerCase().endsWith('.tgs')) {
        return fullThumb;
      }
    }
    return null;
  }

  void _cacheStickerItem(StickerItem st) {
    if (st.id > 0) {
      _stickerByIdCache[st.id] = st;
    }
    if (st.fileUrl.isNotEmpty) {
      _stickerByFileUrlCache[resolveUrl(st.fileUrl)] = st;
    }
  }

  LottieComposition? getCachedComposition(String rawUrl) {
    final fullUrl = resolveUrl(rawUrl);
    if (fullUrl.isEmpty) return null;
    return _lottieCompositionCache[fullUrl];
  }

  Future<void> loadMyPacks() => ensureInitialized();

  Future<void> loadInstalledPacks({
    bool force = false,
    bool forceRefresh = false,
  }) =>
      ensureInitialized(forceRefresh: force || forceRefresh);

  void _indexPacksInCache(List<StickerPack> packs) {
    for (final pack in packs) {
      for (final st in pack.stickers) {
        _cacheStickerItem(st);
      }
    }
  }

  static const Set<String> _removedDefaultPackSlugs = {
    'theaver_reactions',
    'theaver_animals',
    'theaver_emoji_status',
    'theaver_emoji_pets',
  };

  Future<void> ensureInitialized({bool forceRefresh = false}) async {
    if (_initialized && !forceRefresh) {
      if (_trendingGifs.isEmpty) {
        refreshSavedAndTrendingGifs();
      }
      return;
    }
    _initialized = true;
    await Future.wait([
      refreshStickerPacks(notify: false),
      refreshCustomEmojiPacks(notify: false),
      refreshFavoritesAndRecents(notify: false),
      refreshSavedAndTrendingGifs(notify: false),
    ]);
    notifyListeners();
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> refreshStickerPacks({bool notify = true}) async {
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs?custom_emoji=false'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['success'] == true) {
          _installedStickerPacks = (data['installed'] as List? ?? [])
              .whereType<Map>()
              .map((m) => StickerPack.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => !_removedDefaultPackSlugs.contains(p.shortName))
              .toList();
          _featuredStickerPacks = (data['featured'] as List? ?? [])
              .whereType<Map>()
              .map((m) => StickerPack.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => !_removedDefaultPackSlugs.contains(p.shortName))
              .toList();
          _indexPacksInCache(_installedStickerPacks);
          _indexPacksInCache(_featuredStickerPacks);
          if (notify) notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('StickerService.refreshStickerPacks error: $e');
    }
  }

  Future<void> refreshCustomEmojiPacks({bool notify = true}) async {
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs?custom_emoji=true'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['success'] == true) {
          _installedEmojiPacks = (data['installed'] as List? ?? [])
              .whereType<Map>()
              .map((m) => StickerPack.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => !_removedDefaultPackSlugs.contains(p.shortName))
              .toList();
          _featuredEmojiPacks = (data['featured'] as List? ?? [])
              .whereType<Map>()
              .map((m) => StickerPack.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => !_removedDefaultPackSlugs.contains(p.shortName))
              .toList();
          _indexPacksInCache(_installedEmojiPacks);
          _indexPacksInCache(_featuredEmojiPacks);
          if (notify) notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('StickerService.refreshCustomEmojiPacks error: $e');
    }
  }

  Future<void> refreshFavoritesAndRecents({bool notify = true}) async {
    try {
      final headers = await _authHeaders();
      final results = await Future.wait([
        http.get(
          Uri.parse('${AppConfig.baseUrl}/api/stickers/favorites'),
          headers: headers,
        ),
        http.get(
          Uri.parse('${AppConfig.baseUrl}/api/stickers/recent'),
          headers: headers,
        ),
      ]);
      if (results[0].statusCode == 200) {
        final d = jsonDecode(results[0].body);
        if (d is Map && d['stickers'] is List) {
          _favoriteStickers = (d['stickers'] as List)
              .whereType<Map>()
              .map((m) => StickerItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          for (final s in _favoriteStickers) {
            _cacheStickerItem(s);
          }
        }
      }
      if (results[1].statusCode == 200) {
        final d = jsonDecode(results[1].body);
        if (d is Map && d['stickers'] is List) {
          _recentStickers = (d['stickers'] as List)
              .whereType<Map>()
              .map((m) => StickerItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          for (final s in _recentStickers) {
            _cacheStickerItem(s);
          }
        }
      }
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('StickerService.refreshFavoritesAndRecents error: $e');
    }
  }

  Future<void> refreshSavedAndTrendingGifs({bool notify = true}) async {
    try {
      final headers = await _authHeaders();
      final results = await Future.wait([
        http.get(
          Uri.parse('${AppConfig.baseUrl}/api/gifs/saved'),
          headers: headers,
        ),
        http.get(
          Uri.parse('${AppConfig.baseUrl}/api/gifs/trending?limit=30'),
          headers: headers,
        ),
      ]);
      if (results[0].statusCode == 200) {
        final d = jsonDecode(results[0].body);
        if (d is Map && d['items'] is List) {
          _savedGifs = (d['items'] as List)
              .whereType<Map>()
              .map((m) => GifItemModel.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
      if (results[1].statusCode == 200) {
        final d = jsonDecode(results[1].body);
        if (d is Map && d['items'] is List) {
          _trendingGifs = (d['items'] as List)
              .whereType<Map>()
              .map((m) => GifItemModel.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('StickerService.refreshSavedAndTrendingGifs error: $e');
    }
  }

  Future<List<GifItemModel>> searchGifs(String query, {String pos = ''}) async {
    try {
      final headers = await _authHeaders();
      final uri = Uri.parse('${AppConfig.baseUrl}/api/gifs/search').replace(
        queryParameters: {
          'q': query.trim(),
          'limit': '30',
          if (pos.isNotEmpty) 'pos': pos,
        },
      );
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d is Map && d['items'] is List) {
          return (d['items'] as List)
              .whereType<Map>()
              .map((m) => GifItemModel.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('StickerService.searchGifs error: $e');
    }
    return [];
  }

  Future<List<StickerItem>> searchStickers(
    String query, {
    bool? isCustomEmoji,
    String? packType,
  }) async {
    final effectiveCustomEmoji =
        isCustomEmoji ?? (packType == 'custom_emoji');
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // 1. Local matches from installed packs
    final packs =
        effectiveCustomEmoji ? _installedEmojiPacks : _installedStickerPacks;
    final Map<int, StickerItem> merged = {};
    for (final p in packs) {
      for (final st in p.stickers) {
        if (st.matchesLocalQuery(trimmed)) {
          merged[st.id] = st;
        }
      }
    }

    // 2. Server hybrid multilingual semantic search (tsvector + pg_trgm + OCR + visual tags)
    try {
      final headers = await _authHeaders();
      final uri = Uri.parse('${AppConfig.baseUrl}/api/stickers/search').replace(
        queryParameters: {
          'q': trimmed,
          'custom_emoji': effectiveCustomEmoji ? 'true' : 'false',
        },
      );
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d is Map && d['stickers'] is List) {
          for (final item in (d['stickers'] as List).whereType<Map>()) {
            final parsed = StickerItem.fromJson(Map<String, dynamic>.from(item));
            _stickerByIdCache[parsed.id] = parsed;
            merged[parsed.id] = parsed;
          }
        }
      }
    } catch (e) {
      debugPrint('StickerService.searchStickers error: $e');
    }

    return merged.values.toList();
  }

  Future<StickerItem?> getStickerById(Object rawId) async {
    final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;
    if (id <= 0) return null;
    final cached = _stickerByIdCache[id];
    if (cached != null) return cached;

    if (_inFlightStickerById.containsKey(id)) {
      return _inFlightStickerById[id];
    }

    final future = _fetchStickerById(id);
    _inFlightStickerById[id] = future;
    try {
      return await future;
    } finally {
      _inFlightStickerById.remove(id);
    }
  }

  Future<StickerItem?> _fetchStickerById(int id) async {
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/item/$id'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d is Map && d['sticker'] is Map) {
          final st = StickerItem.fromJson(
            Map<String, dynamic>.from(d['sticker'] as Map),
          );
          _stickerByIdCache[st.id] = st;
          return st;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<StickerPack?> getPackBySlugOrId(String slugOrId) async {
    final trimmed = slugOrId.trim();
    if (trimmed.isEmpty) return null;
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs/${Uri.encodeComponent(trimmed)}'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d is Map && d['pack'] is Map) {
          final pack = StickerPack.fromJson(
            Map<String, dynamic>.from(d['pack'] as Map),
          );
          _indexPacksInCache([pack]);
          return pack;
        }
      }
    } catch (e) {
      debugPrint('StickerService.getPackBySlugOrId error: $e');
    }
    return null;
  }

  Future<StickerPack?> getPackByIdOrSlug(Object slugOrId) =>
      getPackBySlugOrId(slugOrId.toString());

  Future<bool> installPack(Object packOrId) async {
    final int packId;
    final bool? isCustomEmoji;
    if (packOrId is StickerPack) {
      packId = packOrId.id;
      isCustomEmoji = packOrId.isCustomEmoji;
    } else if (packOrId is int) {
      packId = packOrId;
      isCustomEmoji = null;
    } else {
      packId = int.tryParse(packOrId.toString()) ?? 0;
      isCustomEmoji = null;
    }
    if (packId <= 0) return false;
    try {
      final headers = await _authHeaders();
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs/$packId/install'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        if (isCustomEmoji == true) {
          await refreshCustomEmojiPacks();
        } else if (isCustomEmoji == false) {
          await refreshStickerPacks();
        } else {
          await Future.wait([
            refreshStickerPacks(),
            refreshCustomEmojiPacks(),
          ]);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> uninstallPack(Object packOrId) async {
    final int packId;
    final bool? isCustomEmoji;
    if (packOrId is StickerPack) {
      packId = packOrId.id;
      isCustomEmoji = packOrId.isCustomEmoji;
    } else if (packOrId is int) {
      packId = packOrId;
      isCustomEmoji = null;
    } else {
      packId = int.tryParse(packOrId.toString()) ?? 0;
      isCustomEmoji = null;
    }
    if (packId <= 0) return false;
    try {
      final headers = await _authHeaders();
      final resp = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs/$packId/install'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        if (isCustomEmoji == true) {
          await refreshCustomEmojiPacks();
        } else if (isCustomEmoji == false) {
          await refreshStickerPacks();
        } else {
          await Future.wait([
            refreshStickerPacks(),
            refreshCustomEmojiPacks(),
          ]);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> toggleFavoriteSticker(StickerItem item) async {
    final currentlyFav = isFavorite(item.id);
    if (currentlyFav) {
      _favoriteStickers.removeWhere((s) => s.id == item.id);
    } else {
      _favoriteStickers.insert(0, item);
    }
    notifyListeners();

    try {
      final headers = await _authHeaders();
      final uri = Uri.parse('${AppConfig.baseUrl}/api/stickers/favorites/${item.id}');
      if (currentlyFav) {
        await http.delete(uri, headers: headers);
      } else {
        await http.post(uri, headers: headers);
      }
    } catch (_) {}
    return !currentlyFav;
  }

  Future<bool> toggleFavorite(Object itemOrId) async {
    if (itemOrId is StickerItem) {
      return await toggleFavoriteSticker(itemOrId);
    }
    final id = itemOrId is int
        ? itemOrId
        : int.tryParse(itemOrId.toString()) ?? 0;
    if (id <= 0) return false;
    final item = _stickerByIdCache[id] ?? await getStickerById(id);
    if (item != null) {
      return await toggleFavoriteSticker(item);
    }
    return isFavorite(id);
  }

  Future<void> recordRecentSticker(StickerItem item) async {
    _recentStickers.removeWhere((s) => s.id == item.id);
    _recentStickers.insert(0, item);
    if (_recentStickers.length > 32) {
      _recentStickers = _recentStickers.sublist(0, 32);
    }
    notifyListeners();

    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/recent/${item.id}'),
        headers: headers,
      );
    } catch (_) {}
  }

  Future<void> recordStickerSent(Object itemOrId) async {
    if (itemOrId is StickerItem) {
      await recordRecentSticker(itemOrId);
      return;
    }
    final id = itemOrId is int
        ? itemOrId
        : int.tryParse(itemOrId.toString()) ?? 0;
    if (id <= 0) return;
    final item = _stickerByIdCache[id] ?? await getStickerById(id);
    if (item != null) {
      await recordRecentSticker(item);
    }
  }

  Future<void> saveGif(
    Object gifOrId, [
    String? url,
    String? previewUrl,
    int? width,
    int? height,
  ]) async {
    if (gifOrId is GifItemModel) {
      await saveOrUseGif(gifOrId);
      return;
    }
    final idStr = gifOrId.toString();
    final effectiveUrl = url ?? idStr;
    await saveOrUseGif(
      GifItemModel(
        id: idStr,
        url: effectiveUrl,
        previewUrl: previewUrl ?? effectiveUrl,
        width: width ?? 320,
        height: height ?? 240,
        isSaved: true,
      ),
    );
  }

  Future<void> saveOrUseGif(GifItemModel gif) async {
    _savedGifs.removeWhere((g) => g.id == gif.id || g.url == gif.url);
    _savedGifs.insert(
      0,
      GifItemModel(
        id: gif.id,
        provider: gif.provider,
        title: gif.title,
        url: gif.url,
        previewUrl: gif.previewUrl,
        mp4Url: gif.mp4Url,
        width: gif.width,
        height: gif.height,
        duration: gif.duration,
        useCount: gif.useCount + 1,
        isSaved: true,
      ),
    );
    notifyListeners();

    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/gifs/saved'),
        headers: headers,
        body: jsonEncode(gif.toMediaPayload()),
      );
    } catch (_) {}
  }

  Future<void> removeSavedGif(String gifId, [String? fallbackUrl]) async {
    _savedGifs.removeWhere(
      (g) =>
          g.id == gifId ||
          g.url == gifId ||
          (fallbackUrl != null &&
              fallbackUrl.isNotEmpty &&
              (g.id == fallbackUrl || g.url == fallbackUrl)),
    );
    notifyListeners();
    try {
      final headers = await _authHeaders();
      await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/gifs/saved/${Uri.encodeComponent(gifId)}'),
        headers: headers,
      );
    } catch (_) {}
  }

  Future<bool> checkSlugAvailable(String slug) async {
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/check-slug?slug=${Uri.encodeComponent(slug.trim())}'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        return d is Map && d['available'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<StickerPack?> createPack({
    required String title,
    required String shortName,
    bool? isCustomEmoji,
    String? packType,
  }) async {
    final effectiveCustomEmoji =
        isCustomEmoji ?? (packType == 'custom_emoji');
    try {
      final headers = await _authHeaders();
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs'),
        headers: headers,
        body: jsonEncode({
          'title': title.trim(),
          'short_name': shortName.trim(),
          'is_custom_emoji': effectiveCustomEmoji,
        }),
      );
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d is Map && d['pack'] is Map) {
          final pack = StickerPack.fromJson(
            Map<String, dynamic>.from(d['pack'] as Map),
          );
          if (effectiveCustomEmoji) {
            await refreshCustomEmojiPacks();
          } else {
            await refreshStickerPacks();
          }
          return pack;
        }
      }
    } catch (e) {
      debugPrint('StickerService.createPack error: $e');
    }
    return null;
  }

  Future<StickerItem?> uploadStickerToPack({
    required Object packId,
    Uint8List? fileBytes,
    Uint8List? bytes,
    required String fileName,
    required List<String> emojis,
    String tags = '',
    List<String>? keywords,
    bool isAdaptiveTextColor = false,
    Uint8List? effectFileBytes,
    Uint8List? effectBytes,
    String? effectFileName,
    int? orderIndex,
  }) async {
    final effectiveBytes = fileBytes ?? bytes;
    if (effectiveBytes == null || effectiveBytes.isEmpty) return null;
    final effectiveEffectBytes = effectFileBytes ?? effectBytes;
    final effectiveTags = tags.trim().isNotEmpty
        ? tags.trim()
        : (keywords != null && keywords.isNotEmpty ? keywords.join(', ') : '');
    try {
      final token = await AuthService.getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/stickers/packs/$packId/items'),
      );
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.fields['emojis'] = jsonEncode(emojis);
      if (effectiveTags.isNotEmpty) {
        req.fields['tags'] = effectiveTags;
      }
      if (isAdaptiveTextColor) {
        req.fields['is_adaptive_text_color'] = 'true';
      }
      if (orderIndex != null && orderIndex >= 0) {
        req.fields['order_index'] = orderIndex.toString();
      }
      req.files.add(
        http.MultipartFile.fromBytes('file', effectiveBytes, filename: fileName),
      );
      if (effectiveEffectBytes != null && effectiveEffectBytes.isNotEmpty) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'effect_file',
            effectiveEffectBytes,
            filename: effectFileName ?? 'effect.tgs',
          ),
        );
      }

      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 201 || streamed.statusCode == 200) {
        final d = jsonDecode(body);
        if (d is Map && d['sticker'] is Map) {
          final st = StickerItem.fromJson(
            Map<String, dynamic>.from(d['sticker'] as Map),
          );
          _cacheStickerItem(st);
          return st;
        }
      }
    } catch (e) {
      debugPrint('StickerService.uploadStickerToPack error: $e');
    }
    return null;
  }

  /// Imports a ready-made sticker pack or custom emoji pack from Telegram by link or short_name.
  Future<StickerPack?> importTelegramPack(
    String urlOrSlug, {
    String? botToken,
  }) async {
    _ensureWsProgressSubscription();
    importProgressNotifier.value = const StickerImportProgress(
      current: 0,
      total: 0,
      phase: 'connecting',
    );
    try {
      final headers = await _authHeaders();
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/stickers/import-telegram'),
        headers: headers,
        body: jsonEncode({
          'url': urlOrSlug.trim(),
          if (botToken != null && botToken.trim().isNotEmpty)
            'bot_token': botToken.trim(),
        }),
      );
      final d = jsonDecode(resp.body);
      if ((resp.statusCode == 200 || resp.statusCode == 201) &&
          d is Map &&
          d['success'] == true &&
          d['pack'] is Map) {
        final pack = StickerPack.fromJson(
          Map<String, dynamic>.from(d['pack'] as Map),
        );
        importProgressNotifier.value = StickerImportProgress(
          packId: pack.id,
          shortName: pack.shortName,
          title: pack.title,
          current: pack.stickers.length,
          total: pack.stickers.isNotEmpty ? pack.stickers.length : 1,
          phase: 'done',
        );
        _indexPacksInCache([pack]);
        if (pack.isCustomEmoji) {
          await refreshCustomEmojiPacks();
        } else {
          await refreshStickerPacks();
        }
        return pack;
      }
    } catch (e) {
      debugPrint('StickerService.importTelegramPack error: $e');
    } finally {
      importProgressNotifier.value = null;
    }
    return null;
  }

  /// Loads and decompresses a .tgs (gzipped Lottie) or .json Lottie composition with RAM + Disk caching.
  Future<LottieComposition?> getLottieComposition(String rawUrl) async {
    final fullUrl = resolveUrl(rawUrl);
    if (fullUrl.isEmpty) return null;

    final cached = _lottieCompositionCache[fullUrl];
    if (cached != null) return cached;

    if (_inFlightLottieLoads.containsKey(fullUrl)) {
      return _inFlightLottieLoads[fullUrl];
    }

    final future = _loadLottieCompositionInternal(fullUrl);
    _inFlightLottieLoads[fullUrl] = future;
    try {
      return await future;
    } finally {
      _inFlightLottieLoads.remove(fullUrl);
    }
  }

  Future<Directory?>? _lottieCacheDirFuture;
  int _activeLottieLoads = 0;
  final List<Completer<void>> _lottieLoadWaiters = [];
  static const int _kMaxConcurrentLottieLoads = 12;

  static Uint8List _decompressGzipBytesIsolate(Uint8List raw) {
    final decompressed = GZipDecoder().decodeBytes(raw);
    return Uint8List.fromList(decompressed);
  }

  Future<Directory?> _getLottieCacheDir() {
    if (kIsWeb) return Future.value(null);
    return _lottieCacheDirFuture ??= () async {
      try {
        final dir = await getApplicationSupportDirectory();
        final cacheDir = Directory(p.join(dir.path, 'sticker_lottie_cache'));
        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }
        return cacheDir;
      } catch (_) {
        return null;
      }
    }();
  }

  Future<LottieComposition?> _loadLottieCompositionInternal(
      String fullUrl) async {
    if (_activeLottieLoads >= _kMaxConcurrentLottieLoads) {
      final waiter = Completer<void>();
      _lottieLoadWaiters.add(waiter);
      await waiter.future;
    }
    _activeLottieLoads++;
    try {
      Uint8List? bytes;
      File? cacheFile;

      if (!kIsWeb) {
        try {
          final cacheDir = await _getLottieCacheDir();
          if (cacheDir != null) {
            final safeKey = base64Url
                .encode(utf8.encode(fullUrl))
                .replaceAll('=', '');
            cacheFile = File(p.join(cacheDir.path, '$safeKey.json'));
            if (await cacheFile.exists()) {
              bytes = await cacheFile.readAsBytes();
            }
          }
        } catch (_) {}
      }

      if (bytes == null || bytes.isEmpty) {
        final resp = await http.get(Uri.parse(fullUrl));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          return null;
        }
        final Uint8List raw = resp.bodyBytes;
        // Decompress gzip if .tgs (magic bytes 0x1f 0x8b) in background isolate
        final Uint8List decoded =
            (raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b)
                ? await compute(_decompressGzipBytesIsolate, raw)
                : raw;
        if (cacheFile != null && decoded.isNotEmpty) {
          unawaited(cacheFile.writeAsBytes(decoded));
        }
        bytes = decoded;
      }

      final comp = await LottieComposition.fromBytes(bytes);
      _lottieCompositionCache[fullUrl] = comp;
      return comp;
    } catch (e) {
      debugPrint('StickerService.getLottieComposition error ($fullUrl): $e');
      return null;
    } finally {
      _activeLottieLoads--;
      if (_lottieLoadWaiters.isNotEmpty) {
        _lottieLoadWaiters.removeLast().complete();
      }
    }
  }

  /// Bakes the first frame of a vector sticker/custom-emoji into a GPU texture so idle stickers consume 0% CPU.
  Future<ui.Image?> getBakedFirstFrame(
    String rawUrl, {
    LottieComposition? composition,
    int? targetPx,
    num? size,
  }) async {
    final int px = (targetPx ?? (size != null ? (size * 2).round() : 128)).clamp(32, 512);
    final key = '${resolveUrl(rawUrl)}@$px';
    final cached = _bakedFrameCache[key];
    if (cached != null) return cached;

    final comp = composition ?? await getLottieComposition(rawUrl);
    if (comp == null) return null;

    final img = await EmojiUtils.bakeLottieFrame(
      cacheKey: key,
      composition: comp,
      progress: 0.0,
      targetPx: px,
    );
    if (img != null) {
      _bakedFrameCache[key] = img;
    }
    return img;
  }

  Future<Directory?>? _rasterCacheDirFuture;
  int _activeRasterDownloads = 0;
  final List<Completer<void>> _rasterDownloadWaiters = [];
  static const int _kMaxConcurrentRasterDownloads = 12;

  Future<Directory?> _getRasterCacheDir() {
    if (kIsWeb) return Future.value(null);
    return _rasterCacheDirFuture ??= () async {
      try {
        final dir = await getApplicationSupportDirectory();
        final cacheDir = Directory(p.join(dir.path, 'sticker_raster_cache_v2'));
        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }
        return cacheDir;
      } catch (_) {
        return null;
      }
    }();
  }

  /// Synchronous lookup of a locally cached raster sticker/GIF file (`FileImage`).
  File? getCachedRasterFileSync(String rawUrl) {
    if (kIsWeb) return null;
    final fullUrl = resolveUrl(rawUrl);
    if (fullUrl.isEmpty) return null;
    return _rasterFileCache[fullUrl];
  }

  /// Downloads and caches a raster sticker or GIF file on disk so scrolling never re-fetches over HTTP.
  Future<File?> getOrDownloadRasterFile(String rawUrl) async {
    if (kIsWeb) return null;
    final fullUrl = resolveUrl(rawUrl);
    if (fullUrl.isEmpty) return null;

    final memCached = _rasterFileCache[fullUrl];
    if (memCached != null) return memCached;

    final inFlight = _inFlightRasterDownloads[fullUrl];
    if (inFlight != null) return inFlight;

    final future = _downloadRasterFileInternal(fullUrl);
    _inFlightRasterDownloads[fullUrl] = future;
    try {
      return await future;
    } finally {
      _inFlightRasterDownloads.remove(fullUrl);
    }
  }

  Future<File?> _downloadRasterFileInternal(String fullUrl) async {
    try {
      final cacheDir = await _getRasterCacheDir();
      if (cacheDir == null) return null;

      final safeKey = base64Url.encode(utf8.encode(fullUrl)).replaceAll('=', '');
      final ext = fullUrl.toLowerCase().contains('.gif') ? '.gif' : '.webp';
      final file = File(p.join(cacheDir.path, '$safeKey$ext'));
      if (await file.exists() && await file.length() > 16) {
        _rasterFileCache[fullUrl] = file;
        return file;
      }

      if (_activeRasterDownloads >= _kMaxConcurrentRasterDownloads) {
        final waiter = Completer<void>();
        _rasterDownloadWaiters.add(waiter);
        await waiter.future;
      }
      _activeRasterDownloads++;
      try {
        final resp = await http.get(Uri.parse(fullUrl));
        if (resp.statusCode == 200 && resp.bodyBytes.length > 16) {
          await file.writeAsBytes(resp.bodyBytes, flush: false);
          _rasterFileCache[fullUrl] = file;
          return file;
        }
      } finally {
        _activeRasterDownloads--;
        if (_rasterDownloadWaiters.isNotEmpty) {
          _rasterDownloadWaiters.removeLast().complete();
        }
      }
    } catch (_) {}
    return null;
  }
}
