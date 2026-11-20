import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

/// Represents a single bot command (`/start`, `/help`, etc.).
class BotCommand {
  final String command;
  final String description;

  const BotCommand({
    required this.command,
    required this.description,
  });

  /// Normalized command with leading slash (e.g. `/start`).
  String get slashCommand =>
      command.startsWith('/') ? command : '/$command';

  /// Alias for [slashCommand] with leading slash.
  String get normalizedCommand => slashCommand;

  factory BotCommand.fromJson(Map<String, dynamic> json) {
    final rawCmd = (json['command'] ?? '').toString().trim();
    final cleanCmd = rawCmd.startsWith('/') ? rawCmd.substring(1) : rawCmd;
    return BotCommand(
      command: cleanCmd,
      description: (json['description'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        'description': description,
      };
}

/// Telegram Bot API MenuButton configuration (`default` | `commands` | `web_app`).
class BotMenuButton {
  final String type;
  final String text;
  final String? webAppUrl;

  const BotMenuButton({
    this.type = 'default',
    this.text = '',
    this.webAppUrl,
  });

  bool get isWebApp =>
      type == 'web_app' && (webAppUrl != null && webAppUrl!.isNotEmpty);
  bool get isCommands => type == 'commands';

  factory BotMenuButton.fromJson(dynamic json) {
    if (json is! Map) return const BotMenuButton();
    final map = Map<String, dynamic>.from(json);
    final rawType = (map['type'] ?? 'default').toString().toLowerCase().trim();
    final rawText = (map['text'] ?? '').toString().trim();
    String? url;
    if (map['web_app'] is Map && map['web_app']['url'] != null) {
      url = map['web_app']['url'].toString().trim();
    } else if (map['url'] != null) {
      url = map['url'].toString().trim();
    }
    if (url != null && url.isEmpty) url = null;
    return BotMenuButton(
      type: rawType.isEmpty ? 'default' : rawType,
      text: rawText,
      webAppUrl: url,
    );
  }
}

/// Named Mini App registered with a bot via `@BotMother` or `/api/bots/:botId/apps`.
class BotWebAppInfo {
  final String shortName;
  final String title;
  final String description;
  final String url;
  final String photoUrl;

  const BotWebAppInfo({
    required this.shortName,
    required this.title,
    this.description = '',
    required this.url,
    this.photoUrl = '',
  });

  factory BotWebAppInfo.fromJson(Map<String, dynamic> json) {
    return BotWebAppInfo(
      shortName: (json['short_name'] ?? '').toString().trim(),
      title: (json['title'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      url: (json['url'] ?? '').toString().trim(),
      photoUrl: (json['photo_url'] ?? '').toString().trim(),
    );
  }
}

/// Signed payload returned by `POST /api/bots/:botId/webapp/launch`.
class MiniAppLaunchData {
  final String url;
  final String initData;
  final Map<String, dynamic> initDataUnsafe;
  final String queryId;
  final String version;
  final String botId;
  final String botUsername;
  final String botDisplayName;
  final String botAvatarUrl;
  final bool botIsVerified;

  const MiniAppLaunchData({
    required this.url,
    required this.initData,
    this.initDataUnsafe = const {},
    this.queryId = '',
    this.version = '7.10',
    this.botId = '',
    this.botUsername = '',
    this.botDisplayName = '',
    this.botAvatarUrl = '',
    this.botIsVerified = false,
  });

  factory MiniAppLaunchData.fromJson(Map<String, dynamic> json) {
    final bot = json['bot'] is Map
        ? Map<String, dynamic>.from(json['bot'] as Map)
        : const <String, dynamic>{};
    final unsafe = json['init_data_unsafe'] is Map
        ? Map<String, dynamic>.from(json['init_data_unsafe'] as Map)
        : const <String, dynamic>{};
    return MiniAppLaunchData(
      url: (json['url'] ?? '').toString().trim(),
      initData: (json['init_data'] ?? '').toString(),
      initDataUnsafe: unsafe,
      queryId: (json['query_id'] ?? '').toString(),
      version: (json['version'] ?? '7.10').toString(),
      botId: (bot['id'] ?? '').toString(),
      botUsername: (bot['username'] ?? '').toString(),
      botDisplayName: (bot['display_name'] ?? '').toString(),
      botAvatarUrl: (bot['avatar_url'] ?? '').toString(),
      botIsVerified: bot['is_verified'] == true,
    );
  }
}

/// Button displayed above inline query results (e.g. switch to PM / WebApp).
class BotInlineResultsButton {
  final String text;
  final String? startParameter;
  final String? webAppUrl;

  const BotInlineResultsButton({
    required this.text,
    this.startParameter,
    this.webAppUrl,
  });

  factory BotInlineResultsButton.fromJson(Map<String, dynamic> json) {
    String? waUrl;
    if (json['web_app'] is Map && json['web_app']['url'] != null) {
      waUrl = json['web_app']['url'].toString().trim();
    }
    if (waUrl != null && waUrl.isEmpty) waUrl = null;
    final sp = json['start_parameter']?.toString().trim();
    return BotInlineResultsButton(
      text: (json['text'] ?? '').toString().trim(),
      startParameter: (sp == null || sp.isEmpty) ? null : sp,
      webAppUrl: waUrl,
    );
  }
}

/// Single `InlineQueryResult` returned by an inline bot.
class BotInlineResult {
  final String id;
  final String type;
  final String title;
  final String description;
  final String? thumbUrl;
  final String? photoUrl;
  final String? gifUrl;
  final String? videoUrl;
  final String? audioUrl;
  final String? documentUrl;
  final String caption;
  final String messageText;
  final String? parseMode;
  final Map<String, dynamic>? replyMarkup;
  final Map<String, dynamic> raw;

  const BotInlineResult({
    required this.id,
    required this.type,
    this.title = '',
    this.description = '',
    this.thumbUrl,
    this.photoUrl,
    this.gifUrl,
    this.videoUrl,
    this.audioUrl,
    this.documentUrl,
    this.caption = '',
    this.messageText = '',
    this.parseMode,
    this.replyMarkup,
    this.raw = const {},
  });

  String? get previewImageUrl {
    for (final candidate in [thumbUrl, photoUrl, gifUrl]) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return null;
  }

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (caption.isNotEmpty) return caption;
    if (messageText.isNotEmpty) return messageText;
    return type;
  }

  String get displaySubtitle {
    if (description.isNotEmpty) return description;
    if (title.isNotEmpty && messageText.isNotEmpty) return messageText;
    if (title.isNotEmpty && caption.isNotEmpty) return caption;
    return '';
  }

  bool get isVisualTile =>
      type == 'photo' ||
      type == 'gif' ||
      type == 'mpeg4_gif' ||
      type == 'sticker';

  String get resolvedMessageType {
    switch (type) {
      case 'photo':
        return 'image';
      case 'gif':
      case 'mpeg4_gif':
        return 'gif';
      case 'video':
        return 'video';
      case 'audio':
        return 'audio';
      case 'voice':
        return 'voice';
      case 'document':
        return 'file';
      case 'sticker':
        return 'sticker';
      default:
        return 'text';
    }
  }

  String get resolvedContent {
    if (messageText.isNotEmpty) return messageText;
    if (caption.isNotEmpty) return caption;
    if (resolvedMessageType == 'text') {
      final parts = [title, description].where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return '';
  }

  String get resolvedFileUrl {
    for (final candidate in [
      photoUrl,
      gifUrl,
      videoUrl,
      audioUrl,
      documentUrl,
      raw['voice_url']?.toString(),
      raw['sticker_file_id']?.toString(),
    ]) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  factory BotInlineResult.fromJson(Map<String, dynamic> json) {
    final imc = json['input_message_content'] is Map
        ? Map<String, dynamic>.from(json['input_message_content'] as Map)
        : const <String, dynamic>{};
    final rm = json['reply_markup'] is Map
        ? Map<String, dynamic>.from(json['reply_markup'] as Map)
        : null;
    String? nonEmpty(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return BotInlineResult(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'article').toString().toLowerCase(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      thumbUrl: nonEmpty(json['thumbnail_url'] ?? json['thumb_url']),
      photoUrl: nonEmpty(json['photo_url']),
      gifUrl: nonEmpty(json['gif_url'] ?? json['mpeg4_gif_url']),
      videoUrl: nonEmpty(json['video_url']),
      audioUrl: nonEmpty(json['audio_url']),
      documentUrl: nonEmpty(json['document_url']),
      caption: (json['caption'] ?? '').toString(),
      messageText: (imc['message_text'] ?? '').toString(),
      parseMode: nonEmpty(imc['parse_mode'] ?? json['parse_mode']),
      replyMarkup: rm,
      raw: json,
    );
  }
}

/// Response wrapper for `GET /api/bots/:botId/inline`.
class BotInlineQueryResponse {
  final String inlineQueryId;
  final List<BotInlineResult> results;
  final String nextOffset;
  final BotInlineResultsButton? button;
  final String botId;
  final String? errorCode;
  final String? errorMessage;

  const BotInlineQueryResponse({
    this.inlineQueryId = '',
    this.results = const [],
    this.nextOffset = '',
    this.button,
    this.botId = '',
    this.errorCode,
    this.errorMessage,
  });

  factory BotInlineQueryResponse.fromJson(
    Map<String, dynamic> json, {
    String botId = '',
  }) {
    final rawResults = json['results'];
    final parsedResults = <BotInlineResult>[];
    if (rawResults is List) {
      for (final item in rawResults) {
        if (item is Map) {
          parsedResults.add(
            BotInlineResult.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    BotInlineResultsButton? btn;
    if (json['button'] is Map) {
      btn = BotInlineResultsButton.fromJson(
        Map<String, dynamic>.from(json['button'] as Map),
      );
      if (btn.text.isEmpty) btn = null;
    }
    return BotInlineQueryResponse(
      inlineQueryId: (json['inline_query_id'] ?? '').toString(),
      results: parsedResults,
      nextOffset: (json['next_offset'] ?? '').toString(),
      button: btn,
      botId: (json['bot_id'] ?? botId).toString(),
    );
  }
}

/// Public metadata for a bot user returned by `GET /api/users/:userId/bot-info`.
class BotInfo {
  final String userId;
  final String? username;
  final String displayName;
  final String? avatarUrl;
  final String description;
  final String about;
  final List<BotCommand> commands;
  final bool canJoinGroups;
  final bool canReadAllGroupMessages;
  final bool supportsInlineQueries;
  final String? inlinePlaceholder;
  final BotMenuButton menuButton;
  final String mainAppUrl;
  final bool hasMainWebApp;
  final bool supportsInlineFeedback;
  final String shortName;
  final List<BotWebAppInfo> webApps;
  final bool isVerified;
  final bool isOwned;
  final String? token;
  final String? webhookUrl;

  const BotInfo({
    required this.userId,
    this.username,
    this.displayName = '',
    this.avatarUrl,
    this.description = '',
    this.about = '',
    this.commands = const [],
    this.canJoinGroups = true,
    this.canReadAllGroupMessages = false,
    this.supportsInlineQueries = false,
    this.inlinePlaceholder,
    this.menuButton = const BotMenuButton(),
    this.mainAppUrl = '',
    this.hasMainWebApp = false,
    this.supportsInlineFeedback = false,
    this.shortName = '',
    this.webApps = const [],
    this.isVerified = false,
    this.isOwned = false,
    this.token,
    this.webhookUrl,
  });

  /// Convenience getter returning [about] if non-empty, otherwise [description].
  String? get aboutText => about.trim().isNotEmpty
      ? about
      : (description.trim().isNotEmpty ? description : null);

  /// Resolves the primary Mini App URL (Menu Button `web_app` URL first, then `main_app_url`).
  String? get effectiveWebAppUrl {
    if (menuButton.isWebApp) return menuButton.webAppUrl;
    if (mainAppUrl.trim().isNotEmpty) return mainAppUrl.trim();
    return null;
  }

  /// Whether this bot has a main/menu Mini App URL or at least one registered named Mini App.
  bool get hasAnyWebApp =>
      (effectiveWebAppUrl != null && effectiveWebAppUrl!.isNotEmpty) ||
      webApps.isNotEmpty;

  factory BotInfo.fromJson(
    Map<String, dynamic> json, {
    String fallbackUserId = '',
  }) {
    final map = json['bot_info'] is Map<String, dynamic>
        ? json['bot_info'] as Map<String, dynamic>
        : (json['bot_info'] is Map
            ? Map<String, dynamic>.from(json['bot_info'] as Map)
            : json);
    final rawCmds = map['commands'];
    final parsedCmds = <BotCommand>[];
    if (rawCmds is List) {
      for (final item in rawCmds) {
        if (item is Map) {
          final cmd = BotCommand.fromJson(Map<String, dynamic>.from(item));
          if (cmd.command.isNotEmpty) {
            parsedCmds.add(cmd);
          }
        }
      }
    }

    final parsedApps = <BotWebAppInfo>[];
    if (map['web_apps'] is List) {
      for (final item in map['web_apps'] as List) {
        if (item is Map) {
          final app = BotWebAppInfo.fromJson(Map<String, dynamic>.from(item));
          if (app.url.isNotEmpty) {
            parsedApps.add(app);
          }
        }
      }
    }

    return BotInfo(
      userId: (map['id'] ?? map['user_id'] ?? map['bot_id'] ?? fallbackUserId)
          .toString(),
      username: map['username']?.toString(),
      displayName: (map['display_name'] ?? '').toString(),
      avatarUrl: map['avatar_url']?.toString(),
      description: (map['description'] ?? '').toString(),
      about: (map['about_text'] ?? map['about'] ?? map['short_description'] ?? '')
          .toString(),
      commands: parsedCmds,
      canJoinGroups: map['can_join_groups'] != false,
      canReadAllGroupMessages: map['can_read_all_group_messages'] == true,
      supportsInlineQueries:
          map['supports_inline_queries'] == true || map['is_inline'] == true,
      inlinePlaceholder: map['inline_placeholder']?.toString(),
      menuButton: BotMenuButton.fromJson(map['menu_button']),
      mainAppUrl: (map['main_app_url'] ?? '').toString().trim(),
      hasMainWebApp: map['has_main_web_app'] == true,
      supportsInlineFeedback: map['supports_inline_feedback'] == true,
      shortName: (map['short_name'] ?? '').toString().trim(),
      webApps: parsedApps,
      isVerified: map['is_verified'] == true,
      isOwned: map['is_owned'] == true,
      token: map['token']?.toString(),
      webhookUrl: map['webhook_url']?.toString(),
    );
  }
}

/// Service for interacting with Theaver Bots (`@BotMother`, Bot API v7+ & Mini Apps).
class BotService {
  static final Map<String, BotInfo> _botInfoCache = {};
  static final Map<String, ({List<BotInfo> items, DateTime fetchedAt})>
      _directoryCache = {};
  static const Duration _directoryCacheTtl = Duration(seconds: 30);
  static final RegExp _inlinePattern =
      RegExp(r'^@([a-zA-Z][a-zA-Z0-9_]{3,31})\s([\s\S]*)$');

  /// Invalidates cached metadata for [userId] and clears directory cache.
  static void invalidateBotInfo(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isNotEmpty) {
      _botInfoCache.removeWhere(
        (k, _) => k == trimmed || k.startsWith('${trimmed}_'),
      );
    }
    _directoryCache.clear();
  }

  /// Parses an active `@mention` prefix right before [cursorOffset].
  ///
  /// Returns `start` (index of `@`), `end` (`cursorOffset`), `query` (text after `@`),
  /// and `isAtMessageStart` (`start == 0`), or `null` if the cursor is not on a mention token
  /// (e.g. inside an email like `user@mail.com`).
  static ({int start, int end, String query, bool isAtMessageStart})?
      parseActiveMentionToken(String text, int cursorOffset) {
    if (text.isEmpty) return null;
    final clampedCursor =
        cursorOffset < 0 ? text.length : cursorOffset.clamp(0, text.length);
    if (clampedCursor == 0) return null;

    int scan = clampedCursor - 1;
    while (scan >= 0) {
      final cu = text.codeUnitAt(scan);
      if (cu == 0x40 /* '@' */) {
        break;
      }
      final isWordChar = (cu >= 0x30 && cu <= 0x39) || // 0-9
          (cu >= 0x41 && cu <= 0x5A) || // A-Z
          (cu >= 0x61 && cu <= 0x7A) || // a-z
          cu == 0x5F; // _
      if (!isWordChar) {
        return null;
      }
      scan--;
    }

    if (scan < 0 || text.codeUnitAt(scan) != 0x40) return null;
    if (clampedCursor - scan - 1 > 32) return null;

    if (scan > 0) {
      final prev = text.codeUnitAt(scan - 1);
      final isEmailOrDomainPrev = (prev >= 0x30 && prev <= 0x39) ||
          (prev >= 0x41 && prev <= 0x5A) ||
          (prev >= 0x61 && prev <= 0x7A) ||
          prev == 0x5F ||
          prev == 0x2E; // '.'
      if (isEmailOrDomainPrev) {
        return null;
      }
    }

    final query = text.substring(scan + 1, clampedCursor);
    return (
      start: scan,
      end: clampedCursor,
      query: query,
      isAtMessageStart: scan == 0,
    );
  }

  /// Parses `@botusername query` from a chat input string.
  static ({String botUsername, String query})? parseInlineBotInput(String text) {
    final match = _inlinePattern.firstMatch(text);
    if (match == null) return null;
    final uname = match.group(1) ?? '';
    final q = match.group(2) ?? '';
    if (uname.isEmpty) return null;
    return (botUsername: uname, query: q);
  }

  /// Returns cached [BotInfo] if available.
  static BotInfo? getCachedBotInfo(String userId, {String? chatId}) =>
      _botInfoCache['${userId}_${chatId ?? ''}'] ?? _botInfoCache[userId];

  /// Fetches bot info (`description`, `about_text`, `commands`, `menu_button`, `web_apps`)
  /// from `GET /api/users/:userId/bot-info`.
  static Future<BotInfo?> getBotInfo(
    String userId, {
    String? chatId,
    String? lang,
    bool forceRefresh = false,
  }) async {
    if (userId.isEmpty) return null;
    final cacheKey = '${userId}_${chatId ?? ''}';
    if (!forceRefresh && _botInfoCache.containsKey(cacheKey)) {
      return _botInfoCache[cacheKey];
    }

    try {
      final token = await AuthService.getToken();
      if (token == null) return null;

      final uri = Uri.parse('${AppConfig.baseUrl}/api/users/$userId/bot-info')
          .replace(queryParameters: {
        if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        if (lang != null && lang.isNotEmpty) 'lang': lang,
      });

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> &&
            (data['success'] == true ||
                data.containsKey('commands') ||
                data.containsKey('bot_info'))) {
          final info = BotInfo.fromJson(data, fallbackUserId: userId);
          _botInfoCache[cacheKey] = info;
          if (chatId == null || chatId.isEmpty) {
            _botInfoCache[userId] = info;
          }
          return info;
        }
      }
    } catch (e) {
      debugPrint('BotService.getBotInfo error: $e');
    }
    return null;
  }

  /// Launches a Mini App via `POST /api/bots/:botId/webapp/launch`,
  /// receiving signed `initData` and resolved WebView URL.
  static Future<MiniAppLaunchData?> launchWebApp({
    required String botId,
    String? url,
    String? appShortName,
    String? chatId,
    String mode = 'menu',
    String? startParam,
    Map<String, dynamic>? themeParams,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/launch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          if (url != null && url.isNotEmpty) 'url': url,
          if (appShortName != null && appShortName.isNotEmpty)
            'app_short_name': appShortName,
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
          'mode': mode,
          if (startParam != null && startParam.isNotEmpty)
            'start_param': startParam,
          if (themeParams != null) 'theme_params': themeParams,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['success'] == true) {
          return MiniAppLaunchData.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint('BotService.launchWebApp error: $e');
    }
    return null;
  }

  /// Sends `Telegram.WebApp.sendData(data)` from a Keyboard Mini App (`POST /api/bots/:botId/webapp/data`).
  static Future<Map<String, dynamic>> sendWebAppData({
    required String botId,
    required String data,
    String buttonText = '',
    String? chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/data'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'data': data,
          'button_text': buttonText,
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        }),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.sendWebAppData error: $e');
    }
    return {'success': false, 'message': 'Failed to send Mini App data'};
  }

  /// Persists `requestWriteAccess` decision (`POST /api/bots/:botId/webapp/write-access`).
  static Future<bool> setWriteAccess({
    required String botId,
    required bool allowed,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/write-access'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'allowed': allowed}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded is Map && decoded['success'] == true;
      }
    } catch (e) {
      debugPrint('BotService.setWriteAccess error: $e');
    }
    return false;
  }

  /// Lists CloudStorage keys for a Mini App (`GET /api/bots/:botId/webapp/storage/keys`).
  static Future<List<String>?> cloudStorageKeys(String botId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return null;
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/storage/keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['keys'] is List) {
          return (decoded['keys'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('BotService.cloudStorageKeys error: $e');
    }
    return null;
  }

  /// Reads CloudStorage items for a Mini App (`POST /api/bots/:botId/webapp/storage/get`).
  static Future<Map<String, String>?> cloudStorageGet(
    String botId,
    List<String> keys,
  ) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return null;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/storage/get'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'keys': keys}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final rawItems = decoded is Map
            ? (decoded['items'] is Map ? decoded['items'] : decoded['values'])
            : null;
        if (rawItems is Map) {
          final items = <String, String>{};
          rawItems.forEach((k, v) {
            items[k.toString()] = v?.toString() ?? '';
          });
          return items;
        }
      }
    } catch (e) {
      debugPrint('BotService.cloudStorageGet error: $e');
    }
    return null;
  }

  /// Writes a CloudStorage key-value item (`POST /api/bots/:botId/webapp/storage/set`).
  static Future<bool> cloudStorageSet(
    String botId,
    String key,
    String value,
  ) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/storage/set'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'key': key, 'value': value}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('BotService.cloudStorageSet error: $e');
    }
    return false;
  }

  /// Deletes CloudStorage keys (`POST /api/bots/:botId/webapp/storage/remove`).
  static Future<bool> cloudStorageRemove(
    String botId,
    List<String> keys,
  ) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/webapp/storage/remove'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'keys': keys}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('BotService.cloudStorageRemove error: $e');
    }
    return false;
  }

  /// Lists registered named Mini Apps for a bot (`GET /api/bots/:botId/apps`).
  static Future<List<BotWebAppInfo>> listBotWebApps(String botId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return const [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/apps'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['apps'] is List) {
          return (decoded['apps'] as List)
              .whereType<Map>()
              .map((m) => BotWebAppInfo.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('BotService.listBotWebApps error: $e');
    }
    return const [];
  }

  /// Sends an inline keyboard button callback query (`callback_data`) to the bot.
  /// Tries WebSocket RPC `callback_query` first when connected, falling back to
  /// `POST /api/chats/:chatId/messages/:messageId/callback`.
  static Future<Map<String, dynamic>> sendCallbackQuery({
    required String chatId,
    required String messageId,
    required String callbackData,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      if (WebSocketService().isConnected) {
        try {
          final rpcRes = await WebSocketService().sendRpc(
            'callback_query',
            {
              'chat_id': int.tryParse(chatId) ?? chatId,
              'message_id': int.tryParse(messageId) ?? messageId,
              'callback_data': callbackData,
            },
          );
          return {
            'success': true,
            ...rpcRes,
          };
        } on WsRpcException catch (e) {
          if (e.statusCode != 503 &&
              e.statusCode != 504 &&
              e.statusCode != 400) {
            return {
              'success': false,
              'message': e.description,
            };
          }
        } catch (_) {}
      }

      final response = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/callback'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'callback_data': callbackData,
          'data': callbackData,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': data['success'] ?? true,
          ...data,
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['description'] ?? data['message'] ?? 'Ошибка кнопки')
                .toString()
            : 'Ошибка кнопки',
      };
    } catch (e) {
      debugPrint('BotService.sendCallbackQuery error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Queries an inline bot (`GET /api/bots/:botId/inline`), returning structured results,
  /// pagination offset, and optional header button.
  static Future<BotInlineQueryResponse?> queryInlineBotDetailed({
    required String botId,
    required String query,
    String? chatId,
    String? chatType,
    String offset = '',
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return null;

      final uri = Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/inline')
          .replace(queryParameters: {
        'query': query,
        if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        if (chatType != null && chatType.isNotEmpty) 'chat_type': chatType,
        if (offset.isNotEmpty) 'offset': offset,
      });

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return BotInlineQueryResponse.fromJson(data, botId: botId);
      }
      if (data is Map) {
        return BotInlineQueryResponse(
          botId: botId,
          errorCode: (data['error_code'] ?? data['code'])?.toString(),
          errorMessage: (data['message'] ?? data['error'])?.toString(),
        );
      }
    } catch (e) {
      debugPrint('BotService.queryInlineBotDetailed error: $e');
    }
    return null;
  }

  /// Legacy helper returning raw result maps from [queryInlineBotDetailed].
  static Future<List<Map<String, dynamic>>> queryInlineBot({
    required String botId,
    required String query,
    String? chatId,
    String offset = '',
  }) async {
    final detailed = await queryInlineBotDetailed(
      botId: botId,
      query: query,
      chatId: chatId,
      offset: offset,
    );
    if (detailed == null) return const [];
    return detailed.results.map((r) => r.raw).toList();
  }

  /// Posts a chosen inline result into a chat (`POST /api/chats/:chatId/send-inline-result`)
  /// tagged with `via_bot_id` and triggering `chosen_inline_result` when enabled.
  static Future<Map<String, dynamic>> sendInlineResult({
    required String chatId,
    required String botId,
    required BotInlineResult result,
    required String query,
    String? inlineQueryId,
    String? replyToMessageId,
    int? topicId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final fileUrl = result.resolvedFileUrl;
      final fileName =
          fileUrl.isNotEmpty ? (Uri.tryParse(fileUrl)?.pathSegments.last ?? '') : '';

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/send-inline-result'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bot_id': botId,
          if (inlineQueryId != null && inlineQueryId.isNotEmpty)
            'inline_query_id': inlineQueryId,
          'result_id': result.id,
          'query': query,
          'message_type': result.resolvedMessageType,
          'content': result.resolvedContent,
          if (fileUrl.isNotEmpty) 'file_url': fileUrl,
          if (fileName.isNotEmpty) 'file_name': fileName,
          if (fileUrl.isNotEmpty)
            'media_payload': {
              'file_url': fileUrl,
              if (fileName.isNotEmpty) 'file_name': fileName,
            },
          if (result.replyMarkup != null) 'reply_markup': result.replyMarkup,
          if (replyToMessageId != null && replyToMessageId.isNotEmpty)
            'reply_to_message_id': replyToMessageId,
          if (topicId != null && topicId > 0) 'topic_id': topicId,
          if (result.parseMode != null && result.parseMode!.isNotEmpty)
            'parse_mode': result.parseMode,
        }),
      );

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.sendInlineResult error: $e');
    }
    return {'success': false, 'message': 'Failed to send inline result'};
  }

  /// Lists discoverable active bots, inline bots, and bots with Mini Apps (`GET /api/bots/directory`).
  static Future<List<BotInfo>> getBotsDirectory({
    String query = '',
    bool inlineOnly = false,
    bool appsOnly = false,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    final trimmedQuery = query.trim();
    final cacheKey = '${trimmedQuery}_${inlineOnly}_${appsOnly}_$limit';
    if (!forceRefresh) {
      final cached = _directoryCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _directoryCacheTtl) {
        return cached.items;
      }
    }

    try {
      final token = await AuthService.getToken();
      if (token == null) return const [];

      final uri = Uri.parse('${AppConfig.baseUrl}/api/bots/directory')
          .replace(queryParameters: {
        if (trimmedQuery.isNotEmpty) 'q': trimmedQuery,
        if (inlineOnly) 'inline_only': 'true',
        if (appsOnly) 'apps_only': 'true',
        'limit': '$limit',
      });

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['bots'] is List) {
          final items = <BotInfo>[];
          for (final raw in decoded['bots'] as List) {
            if (raw is Map) {
              items.add(BotInfo.fromJson(Map<String, dynamic>.from(raw)));
            }
          }
          _directoryCache[cacheKey] = (
            items: items,
            fetchedAt: DateTime.now(),
          );
          return items;
        }
      }
    } catch (e) {
      debugPrint('BotService.getBotsDirectory error: $e');
    }
    return const [];
  }

  /// Lists bots owned by the authenticated user (`GET /api/bots`).
  static Future<List<BotInfo>> getMyBots() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return const [];
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/bots'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['bots'] is List) {
          return (decoded['bots'] as List)
              .whereType<Map>()
              .map(
                (raw) => BotInfo.fromJson({
                  ...Map<String, dynamic>.from(raw),
                  'is_owned': true,
                }),
              )
              .toList();
        }
      }
    } catch (e) {
      debugPrint('BotService.getMyBots error: $e');
    }
    return const [];
  }

  /// Creates a new bot via `POST /api/bots`.
  static Future<Map<String, dynamic>> createBot({
    required String displayName,
    required String username,
    String description = '',
    String aboutText = '',
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'display_name': displayName.trim(),
          'username': username.trim().replaceFirst(RegExp(r'^@+'), ''),
          'description': description.trim(),
          'about_text': aboutText.trim(),
        }),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == true) {
          _directoryCache.clear();
        }
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.createBot error: $e');
    }
    return {'success': false, 'message': 'Не удалось создать бота'};
  }

  /// Updates bot settings (`PUT /api/bots/:botId`) and invalidates cached info.
  static Future<Map<String, dynamic>> updateBot(
    String botId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(updates),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == true) {
          invalidateBotInfo(botId);
        }
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.updateBot error: $e');
    }
    return {'success': false, 'message': 'Не удалось обновить настройки бота'};
  }

  /// Creates or updates a named Mini App for an owned bot (`POST /api/bots/:botId/apps`).
  static Future<Map<String, dynamic>> upsertBotWebApp({
    required String botId,
    required String shortName,
    required String title,
    required String url,
    String description = '',
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/apps'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'short_name': shortName.trim(),
          'title': title.trim(),
          'url': url.trim(),
          'description': description.trim(),
        }),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == true) {
          invalidateBotInfo(botId);
        }
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.upsertBotWebApp error: $e');
    }
    return {'success': false, 'message': 'Не удалось сохранить Mini App'};
  }

  /// Deletes a named Mini App for an owned bot (`DELETE /api/bots/:botId/apps/:shortName`).
  static Future<Map<String, dynamic>> deleteBotWebApp({
    required String botId,
    required String shortName,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/apps/$shortName'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == true) {
          invalidateBotInfo(botId);
        }
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.deleteBotWebApp error: $e');
    }
    return {'success': false, 'message': 'Не удалось удалить Mini App'};
  }

  /// Fetches THV invoice details and caller's current THV balance (`GET /api/invoices/:slug`).
  static Future<Map<String, dynamic>> getInvoice(String slug) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final cleanSlug = Uri.encodeComponent(slug.trim());
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/$cleanSlug'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.getInvoice error: $e');
    }
    return {'success': false, 'message': 'Не удалось загрузить счёт'};
  }

  /// Pays a THV invoice atomically (`POST /api/invoices/:slug/pay`).
  static Future<Map<String, dynamic>> payInvoice(String slug) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }
      final cleanSlug = Uri.encodeComponent(slug.trim());
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/invoices/$cleanSlug/pay'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: '{}',
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('BotService.payInvoice error: $e');
    }
    return {'success': false, 'message': 'Не удалось оплатить счёт'};
  }
}
