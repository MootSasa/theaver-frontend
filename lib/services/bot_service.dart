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

/// Public metadata for a bot user returned by `GET /api/users/:userId/bot-info`.
class BotInfo {
  final String userId;
  final String? username;
  final String description;
  final String about;
  final List<BotCommand> commands;
  final bool canJoinGroups;
  final bool canReadAllGroupMessages;
  final bool supportsInlineQueries;
  final String? inlinePlaceholder;

  const BotInfo({
    required this.userId,
    this.username,
    this.description = '',
    this.about = '',
    this.commands = const [],
    this.canJoinGroups = true,
    this.canReadAllGroupMessages = false,
    this.supportsInlineQueries = false,
    this.inlinePlaceholder,
  });

  /// Convenience getter returning [about] if non-empty, otherwise [description].
  String? get aboutText =>
      about.trim().isNotEmpty ? about : (description.trim().isNotEmpty ? description : null);

  factory BotInfo.fromJson(Map<String, dynamic> json, {String fallbackUserId = ''}) {
    final map = json['bot_info'] is Map<String, dynamic>
        ? json['bot_info'] as Map<String, dynamic>
        : json;
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

    return BotInfo(
      userId: (map['user_id'] ?? map['bot_id'] ?? fallbackUserId).toString(),
      username: map['username']?.toString(),
      description: (map['description'] ?? '').toString(),
      about: (map['about'] ?? map['short_description'] ?? '').toString(),
      commands: parsedCmds,
      canJoinGroups: map['can_join_groups'] != false,
      canReadAllGroupMessages: map['can_read_all_group_messages'] == true,
      supportsInlineQueries:
          map['supports_inline_queries'] == true || map['is_inline'] == true,
      inlinePlaceholder: map['inline_placeholder']?.toString(),
    );
  }
}

/// Service for interacting with Theaver Bots (`@BotMother` & Bot API v7).
class BotService {
  static final Map<String, BotInfo> _botInfoCache = {};

  /// Returns cached [BotInfo] if available.
  static BotInfo? getCachedBotInfo(String userId) => _botInfoCache[userId];

  /// Fetches bot info (`description`, `about`, `commands`) from
  /// `GET /api/users/:userId/bot-info`.
  static Future<BotInfo?> getBotInfo(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (userId.isEmpty) return null;
    if (!forceRefresh && _botInfoCache.containsKey(userId)) {
      return _botInfoCache[userId];
    }

    try {
      final token = await AuthService.getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/users/$userId/bot-info'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> &&
            (data['success'] == true || data.containsKey('commands') || data.containsKey('bot_info'))) {
          final info = BotInfo.fromJson(data, fallbackUserId: userId);
          _botInfoCache[userId] = info;
          return info;
        }
      }
    } catch (e) {
      debugPrint('BotService.getBotInfo error: $e');
    }
    return null;
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
          if (e.statusCode != 503 && e.statusCode != 504 && e.statusCode != 400) {
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

  /// Queries an inline bot (`GET /api/bots/:botId/inline`).
  static Future<List<Map<String, dynamic>>> queryInlineBot({
    required String botId,
    required String query,
    String? chatId,
    String offset = '',
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return [];

      final uri = Uri.parse('${AppConfig.baseUrl}/api/bots/$botId/inline')
          .replace(queryParameters: {
        'query': query,
        if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        if (offset.isNotEmpty) 'offset': offset,
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
        if (data is Map && data['results'] is List) {
          return (data['results'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('BotService.queryInlineBot error: $e');
    }
    return [];
  }
}
