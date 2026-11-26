import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_service.dart';
import 'chat_service.dart';
import 'notification_settings_provider.dart';
import 'privacy_settings_provider.dart';
import 'search_service.dart';
import 'settings_service.dart';
import 'account_manager.dart';
import 'bot_service.dart';
import 'draft_service.dart';
import 'tiling_layout_controller.dart';
import 'websocket_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/bot/mini_app_webview_sheet.dart';
import '../widgets/bot/thv_invoice_sheet.dart';
import '../widgets/profile/user_profile_popup.dart';
import '../widgets/tiling/tiling_workspace_scaffold.dart';
import '../screens/chat/private_chat_screen.dart';
import '../screens/chat/group_chat_screen.dart';
import '../screens/chat/channel_screen.dart';
import '../screens/settings/theme_preview_screen.dart';
import '../utils/swipe_back_route.dart';

/// Supported types of deep links
enum DeepLinkType {
  userProfile,
  groupInvite,
  channel,
  addTheme,
  qrLogin,
  qrGrant,
  miniApp,
  invoice,
  oauthCallback,
}

/// Event emitted when `theaver://oauth-callback` returns from an external browser.
class OAuthCallbackEvent {
  final String sessionId;
  final String? provider;
  final String? error;

  const OAuthCallbackEvent({
    required this.sessionId,
    this.provider,
    this.error,
  });
}

/// Parsed deep link metadata
class ParsedDeepLink {
  final DeepLinkType type;
  final String identifier;
  final String? botUsername;
  final String? appShortName;
  final String? startParam;
  final String? invoiceSlug;
  final String? startChatParam;

  const ParsedDeepLink(
    this.type,
    this.identifier, {
    this.botUsername,
    this.appShortName,
    this.startParam,
    this.invoiceSlug,
    this.startChatParam,
  });
}

/// DeepLinkService handles deep link routing for user profiles, invite links, and channels.
///
/// Supported URL formats:
/// - Profiles:
///   `https://theaver.app/u/{userId}`
///   `http://<ip-or-domain>[:port]/u/{userId}`
///   `http://<ip-or-domain>[:port]/#/u/{userId}`
///   `theaver://u/{userId}`
///
/// - Group / Channel Invites:
///   `https://theaver.app/join/{inviteCode}`
///   `http://<ip-or-domain>[:port]/join/{inviteCode}`
///   `http://<ip-or-domain>[:port]/#/join/{inviteCode}`
///   `theaver://join/{inviteCode}`
///
/// - Channels:
///   `https://theaver.app/c/{channelName}`
///   `http://<ip-or-domain>[:port]/c/{channelName}`
///   `http://<ip-or-domain>[:port]/#/c/{channelName}`
///   `theaver://c/{channelName}`
class DeepLinkService with WidgetsBindingObserver {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;

  /// Global navigator key to access current context
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool _observerAdded = false;

  final StreamController<OAuthCallbackEvent> _oauthCallbackController =
      StreamController<OAuthCallbackEvent>.broadcast();

  /// Broadcast stream of OAuth callback events (`theaver://oauth-callback`).
  Stream<OAuthCallbackEvent> get oauthCallbacks =>
      _oauthCallbackController.stream;

  ParsedDeepLink? parseUriWithDetails(Uri uri) => parseUri(uri);

  void _emitOAuthUri(Uri uri) {
    final sessionId = (uri.queryParameters['session_id'] ?? '').trim();
    final provider = (uri.queryParameters['provider'] ?? '').trim();
    final err = (uri.queryParameters['error'] ?? '').trim();
    if (sessionId.isNotEmpty || err.isNotEmpty) {
      _oauthCallbackController.add(
        OAuthCallbackEvent(
          sessionId: sessionId,
          provider: provider.isNotEmpty ? provider : null,
          error: err.isNotEmpty ? err : null,
        ),
      );
    }
  }

  /// Initializes deep link handling and processes initial link on Web & native platforms.
  Future<void> init() async {
    debugPrint('DeepLinkService: initialized');
    if (!_observerAdded) {
      WidgetsBinding.instance.addObserver(this);
      _observerAdded = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Uri? initialUri;
        if (kIsWeb) {
          initialUri = Uri.base;
        } else {
          final route =
              WidgetsBinding.instance.platformDispatcher.defaultRouteName;
          if (route.isNotEmpty && route != '/') {
            initialUri = Uri.tryParse(route);
          }
        }
        if (initialUri != null && parseUri(initialUri) != null) {
          handleLink(initialUri);
        }
      } catch (e) {
        debugPrint('DeepLinkService: initial link error: $e');
      }
    });
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
    if (parseUri(uri) != null) {
      unawaited(handleLink(uri));
      return true;
    }
    return false;
  }

  /// Pending `@bot query` prefill queued for cross-chat `switch_inline_query`.
  static final ValueNotifier<({String chatId, String text, int seq})?>
      pendingInlinePrefill =
      ValueNotifier<({String chatId, String text, int seq})?>(null);

  /// Saves an immediate draft and notifies any mounted chat screen for [chatId]
  /// to prefill its composer with [text] and open inline results.
  static void queueInlinePrefill(String chatId, String text) {
    final trimmedChatId = chatId.trim();
    if (trimmedChatId.isEmpty) return;
    DraftService().saveDraft(trimmedChatId, text: text, immediate: true);
    pendingInlinePrefill.value = (
      chatId: trimmedChatId,
      text: text,
      seq: (pendingInlinePrefill.value?.seq ?? 0) + 1,
    );
  }

  /// Consumes a queued inline prefill if it targets [chatId].
  static String? consumeInlinePrefill(String chatId) {
    final pending = pendingInlinePrefill.value;
    if (pending != null && pending.chatId == chatId) {
      final txt = pending.text;
      pendingInlinePrefill.value = null;
      return txt;
    }
    return null;
  }

  /// Parses allowed peer chat-type flags from either a top-level prepared-message
  /// map (`allow_user_chats`, `allow_bot_chats`, `allow_group_chats`,
  /// `allow_channel_chats`), a nested `chat_types` map, or a `chat_types` string
  /// list (`['users', 'bots', 'groups', 'channels']`).
  static ({
    bool allowUsers,
    bool allowBots,
    bool allowGroups,
    bool allowChannels,
  }) resolveAllowedChatTypes(dynamic source) {
    bool allowUsers = true;
    bool allowBots = true;
    bool allowGroups = true;
    bool allowChannels = true;

    if (source is Map) {
      final nested = source['chat_types'];
      if (nested is Map || (nested is List && nested.isNotEmpty)) {
        return resolveAllowedChatTypes(nested);
      }
      if (source.containsKey('allow_user_chats')) {
        allowUsers = source['allow_user_chats'] == true;
      }
      if (source.containsKey('allow_bot_chats')) {
        allowBots = source['allow_bot_chats'] == true;
      }
      if (source.containsKey('allow_group_chats')) {
        allowGroups = source['allow_group_chats'] == true;
      }
      if (source.containsKey('allow_channel_chats')) {
        allowChannels = source['allow_channel_chats'] == true;
      }
    } else if (source is List && source.isNotEmpty) {
      final set = source.map((e) => e.toString().trim().toLowerCase()).toSet();
      allowUsers = set.contains('users') || set.contains('user');
      allowBots = set.contains('bots') || set.contains('bot');
      allowGroups = set.contains('groups') || set.contains('group');
      allowChannels = set.contains('channels') || set.contains('channel');
    }

    return (
      allowUsers: allowUsers,
      allowBots: allowBots,
      allowGroups: allowGroups,
      allowChannels: allowChannels,
    );
  }

  /// Queues [prefillText] and navigates to [targetChatId] so inline results open immediately.
  static Future<void> navigateToChatWithInlinePrefill(
    BuildContext context, {
    required String targetChatId,
    required String prefillText,
  }) async {
    queueInlinePrefill(targetChatId, prefillText);

    String chatType = 'private';
    String chatName = '';
    String? avatarUrl;
    String? otherUserId;
    try {
      final res = await ChatService.getChat(targetChatId);
      if (res['success'] == true && res['chat'] is ChatDetails) {
        final details = res['chat'] as ChatDetails;
        chatType = details.chatType;
        chatName = details.name;
        avatarUrl = details.avatarUrl;
        if (chatType == 'private' && details.participants.isNotEmpty) {
          otherUserId = details.participants.first.id;
        }
      }
    } catch (_) {}

    if (!context.mounted) return;
    if (TilingLayoutController.instance.isWorkspaceMounted) {
      TilingLayoutController.instance.openChatInActiveTile(
        chatId: targetChatId,
        chatType: chatType,
        chatName: chatName,
        avatarUrl: avatarUrl,
        otherUserId: otherUserId,
      );
      return;
    }

    if (chatType == 'channel') {
      await Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => ChannelScreen(
            channelId: targetChatId,
            channelName: chatName.isNotEmpty ? chatName : null,
            channelAvatar: avatarUrl,
          ),
        ),
      );
    } else if (chatType == 'group') {
      await Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => GroupChatScreen(
            chatId: targetChatId,
            groupName: chatName.isNotEmpty ? chatName : null,
            groupAvatar: avatarUrl,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: targetChatId,
            otherUserId: otherUserId,
            otherUserName: chatName.isNotEmpty ? chatName : null,
            otherUserAvatar: avatarUrl,
          ),
        ),
      );
    }
  }

  static const Set<String> _botLinkHosts = {
    't.me',
    'www.t.me',
    'telegram.me',
    'www.telegram.me',
    'theaver.app',
    'www.theaver.app',
  };

  static const Set<String> _reservedBotPaths = {
    'u',
    'user',
    'join',
    'invite',
    'c',
    'channel',
    'addtheme',
    'theme',
    'qr-login',
    'qrlogin',
    'invoice',
    'invoices',
    'resolve',
    'joinchat',
    's',
    'addstickers',
    'addemoji',
    'share',
    'iv',
    'proxy',
    'socks',
    'setlanguage',
    'addlist',
    'boost',
    'giftcode',
    'login',
    'api',
  };

  static ParsedDeepLink? _parseQrLink(
    Map<String, String> query, {
    String? fallbackSegment,
  }) {
    final tok = (query['token'] ?? fallbackSegment ?? '').trim();
    if (tok.isEmpty) return null;
    final mode = (query['mode'] ?? '').trim().toLowerCase();
    return ParsedDeepLink(
      mode == 'grant' ? DeepLinkType.qrGrant : DeepLinkType.qrLogin,
      tok,
    );
  }

  static ParsedDeepLink? _parseResolveQuery(Map<String, String> query) {
    final domain = (query['domain'] ?? '')
        .trim()
        .replaceFirst(RegExp(r'^@+'), '');
    if (domain.isEmpty) return null;
    final appName = (query['appname'] ?? '').trim();
    final hasStartAppKey = query.containsKey('startapp');
    final startApp = (query['startapp'] ?? '').trim();
    final start = (query['start'] ?? '').trim();

    if (appName.isNotEmpty || hasStartAppKey) {
      final id = appName.isNotEmpty ? '$domain/$appName' : domain;
      return ParsedDeepLink(
        DeepLinkType.miniApp,
        id,
        botUsername: domain,
        appShortName: appName.isNotEmpty ? appName : null,
        startParam: startApp.isNotEmpty ? startApp : null,
        startChatParam: start.isNotEmpty ? start : null,
      );
    }

    return ParsedDeepLink(
      DeepLinkType.userProfile,
      domain,
      botUsername: domain,
      startChatParam: start.isNotEmpty ? start : null,
    );
  }

  /// Parses an incoming URI into a structured ParsedDeepLink or null if unrecognized.
  static ParsedDeepLink? parseUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    // 1. Check fragment first (for Web hash routing e.g. /#/u/123 or /#/join/code)
    if (uri.fragment.isNotEmpty) {
      final fragmentPath =
          uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}';
      try {
        final fragmentUri = Uri.parse('app://local$fragmentPath');
        final fromFragment = _extractFromSegments(
          fragmentUri.pathSegments,
          fragmentUri.queryParameters,
          host: host,
        );
        if (fromFragment != null) return fromFragment;
      } catch (_) {}
    }

    // 2. Check custom schemes: tg:// and theaver://
    if (scheme == 'tg') {
      if (host == 'resolve') {
        return _parseResolveQuery(uri.queryParameters);
      }
      if (host == 'invoice' || host == 'invoices') {
        final slug = (uri.queryParameters['slug'] ??
                (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : ''))
            .trim();
        if (slug.isNotEmpty) {
          return ParsedDeepLink(
            DeepLinkType.invoice,
            slug,
            invoiceSlug: slug,
          );
        }
      }
      return null;
    }

    if (scheme == 'theaver') {
      if (host == 'resolve') {
        return _parseResolveQuery(uri.queryParameters);
      }
      if (host == 'invoice' || host == 'invoices') {
        final slug = (uri.pathSegments.isNotEmpty
                ? uri.pathSegments.first
                : (uri.queryParameters['slug'] ?? ''))
            .trim();
        if (slug.isNotEmpty) {
          return ParsedDeepLink(
            DeepLinkType.invoice,
            slug,
            invoiceSlug: slug,
          );
        }
      }
      if (host == 'u' || host == 'user') {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) return ParsedDeepLink(DeepLinkType.userProfile, id);
      } else if (host == 'join' || host == 'invite') {
        final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.queryParameters['code'];
        if (code != null && code.isNotEmpty) return ParsedDeepLink(DeepLinkType.groupInvite, code);
      } else if (host == 'c' || host == 'channel') {
        final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.queryParameters['name'];
        if (name != null && name.isNotEmpty) return ParsedDeepLink(DeepLinkType.channel, name);
      } else if (host == 'addtheme' || host == 'theme') {
        final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.queryParameters['code'];
        if (code != null && code.isNotEmpty) return ParsedDeepLink(DeepLinkType.addTheme, code);
      } else if (host == 'qr-login' || host == 'qrlogin') {
        final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        final qr = _parseQrLink(uri.queryParameters, fallbackSegment: seg);
        if (qr != null) return qr;
      } else if (host == 'oauth-callback') {
        final sid = (uri.queryParameters['session_id'] ?? '').trim();
        return ParsedDeepLink(
          DeepLinkType.oauthCallback,
          sid,
          botUsername: uri.queryParameters['provider']?.trim(),
          startParam: uri.queryParameters['error']?.trim(),
        );
      }
    }

    // 3. Check regular path segments for any domain or IP
    return _extractFromSegments(uri.pathSegments, uri.queryParameters, host: host);
  }

  static ParsedDeepLink? _extractFromSegments(
    List<String> segments,
    Map<String, String> query, {
    String host = '',
  }) {
    final cleanSegments = segments.where((s) => s.trim().isNotEmpty).toList();
    if (cleanSegments.isEmpty) return null;

    final firstRaw = cleanSegments.first.trim();
    final first = firstRaw.toLowerCase();
    if ((first == 'u' || first == 'user') && cleanSegments.length >= 2) {
      final id = cleanSegments[1].trim();
      if (id.isNotEmpty) return ParsedDeepLink(DeepLinkType.userProfile, id);
    }
    if ((first == 'join' || first == 'invite') && cleanSegments.length >= 2) {
      final code = cleanSegments[1].trim();
      if (code.isNotEmpty) return ParsedDeepLink(DeepLinkType.groupInvite, code);
    }
    if ((first == 'c' || first == 'channel') && cleanSegments.length >= 2) {
      final name = cleanSegments[1].trim();
      if (name.isNotEmpty) return ParsedDeepLink(DeepLinkType.channel, name);
    }
    if ((first == 'addtheme' || first == 'theme') && cleanSegments.length >= 2) {
      final code = cleanSegments[1].trim();
      if (code.isNotEmpty) return ParsedDeepLink(DeepLinkType.addTheme, code);
    }
    if (first == 'qr-login' || first == 'qrlogin') {
      final seg = cleanSegments.length >= 2 ? cleanSegments[1] : null;
      final qr = _parseQrLink(query, fallbackSegment: seg);
      if (qr != null) return qr;
    }
    if (first == 'oauth-callback') {
      final sid = (query['session_id'] ?? '').trim();
      return ParsedDeepLink(
        DeepLinkType.oauthCallback,
        sid,
        botUsername: query['provider']?.trim(),
        startParam: query['error']?.trim(),
      );
    }
    if (first == 'invoice' || first == 'invoices') {
      final slug = cleanSegments.length >= 2
          ? cleanSegments[1].trim()
          : (query['slug'] ?? '').trim();
      if (slug.isNotEmpty) {
        return ParsedDeepLink(
          DeepLinkType.invoice,
          slug,
          invoiceSlug: slug,
        );
      }
    }
    if (first == 'resolve') {
      final resolved = _parseResolveQuery(query);
      if (resolved != null) return resolved;
    }

    if (_botLinkHosts.contains(host) &&
        !_reservedBotPaths.contains(first) &&
        !firstRaw.startsWith('+')) {
      final botUsername = firstRaw.replaceFirst(RegExp(r'^@+'), '');
      if (botUsername.isEmpty) return null;
      final hasStartAppKey = query.containsKey('startapp');
      final startApp = (query['startapp'] ?? '').trim();
      final start = (query['start'] ?? '').trim();

      if (cleanSegments.length >= 2) {
        final secondRaw = cleanSegments[1].trim();
        final isPostNumericId = RegExp(r'^\d+$').hasMatch(secondRaw);
        if (secondRaw.isNotEmpty &&
            !secondRaw.startsWith('+') &&
            (!isPostNumericId || hasStartAppKey)) {
          return ParsedDeepLink(
            DeepLinkType.miniApp,
            '$botUsername/$secondRaw',
            botUsername: botUsername,
            appShortName: secondRaw,
            startParam: startApp.isNotEmpty ? startApp : null,
            startChatParam: start.isNotEmpty ? start : null,
          );
        }
      }

      if (cleanSegments.length == 1 && hasStartAppKey) {
        return ParsedDeepLink(
          DeepLinkType.miniApp,
          botUsername,
          botUsername: botUsername,
          startParam: startApp.isNotEmpty ? startApp : null,
          startChatParam: start.isNotEmpty ? start : null,
        );
      }

      if (cleanSegments.length == 1 && query.containsKey('start')) {
        return ParsedDeepLink(
          DeepLinkType.userProfile,
          botUsername,
          botUsername: botUsername,
          startChatParam: start.isNotEmpty ? start : null,
        );
      }
    }

    return null;
  }

  /// Processes an incoming deep link URI.
  Future<void> handleLink(Uri uri) async {
    debugPrint('DeepLink: received $uri');

    final parsed = parseUri(uri);
    if (parsed == null) {
      debugPrint('DeepLink: unsupported or non-deep-link URI: $uri');
      return;
    }

    switch (parsed.type) {
      case DeepLinkType.userProfile:
        await _handleUserProfile(
          parsed.identifier,
          usernameHint: parsed.botUsername,
          startParam: parsed.startChatParam,
        );
        break;
      case DeepLinkType.groupInvite:
        await _handleGroupInvite(parsed.identifier);
        break;
      case DeepLinkType.channel:
        await _handleChannel(parsed.identifier);
        break;
      case DeepLinkType.addTheme:
        await _handleThemeLink(parsed.identifier);
        break;
      case DeepLinkType.qrLogin:
        await _handleQrLogin(parsed.identifier);
        break;
      case DeepLinkType.qrGrant:
        await _handleQrGrant(parsed.identifier);
        break;
      case DeepLinkType.miniApp:
        await _handleMiniApp(parsed);
        break;
      case DeepLinkType.invoice:
        await _handleInvoice(parsed);
        break;
      case DeepLinkType.oauthCallback:
        _emitOAuthUri(uri);
        break;
    }
  }

  /// Handles Mini App deep link (`t.me/<bot>/<short_name>?startapp=...`, `tg://resolve?...`).
  Future<void> _handleMiniApp(ParsedDeepLink parsed) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      debugPrint('DeepLink: no navigator context for Mini App');
      return;
    }
    final botUsername = (parsed.botUsername ?? parsed.identifier).trim();
    if (botUsername.isEmpty) return;

    await openMiniAppSheet(
      context,
      botId: botUsername,
      botUsername: botUsername,
      appShortName: parsed.appShortName,
      startParam: parsed.startParam,
      mode: 'compact',
    );
  }

  /// Handles THV invoice deep link (`theaver.app/invoice/<slug>`, `tg://invoice?slug=<slug>`).
  Future<void> _handleInvoice(ParsedDeepLink parsed) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      debugPrint('DeepLink: no navigator context for invoice');
      return;
    }
    final slug = (parsed.invoiceSlug ?? parsed.identifier).trim();
    if (slug.isEmpty) return;
    await openThvInvoiceSheet(context, slugOrUrl: slug);
  }

  /// Handles theme preview deep link (`/addtheme/{code}`).
  Future<void> _handleThemeLink(String code) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('DeepLink: no navigator context for theme preview');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemePreviewScreen(themeCode: code),
      ),
    );
  }

  /// Handles user/bot profile deep link (`/u/{userId}` or `tg://resolve?domain=...`).
  Future<void> _handleUserProfile(
    String userIdOrUsername, {
    String? usernameHint,
    String? startParam,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('DeepLink: no navigator context');
      return;
    }

    String resolvedUserId = userIdOrUsername.trim();
    String? resolvedChatId;
    String? resolvedName;
    String? resolvedAvatar;

    final lookupName =
        (usernameHint ?? (int.tryParse(resolvedUserId) == null ? resolvedUserId : ''))
            .trim()
            .replaceFirst(RegExp(r'^@+'), '');
    if (lookupName.isNotEmpty && int.tryParse(resolvedUserId) == null) {
      final lower = lookupName.toLowerCase();
      try {
        final searchRes =
            await SearchService.search(query: lookupName, type: 'all', limit: 20);
        final allPeers = [...searchRes.myPeers, ...searchRes.globalPeers];
        SearchPeer? exactPeer;
        for (final p in allPeers) {
          if (p.username.toLowerCase() == lower) {
            exactPeer = p;
            break;
          }
        }
        if (exactPeer != null) {
          if (exactPeer.isChannel || exactPeer.isGroup) {
            final targetChatId = exactPeer.chatId ?? exactPeer.id;
            if (!exactPeer.isMember && exactPeer.isPublic) {
              await ChatService.joinPublicChat(targetChatId);
            }
            if (context.mounted && targetChatId.isNotEmpty) {
              _openGroupOrChannel(
                context,
                targetChatId,
                exactPeer.peerType,
                exactPeer.name,
              );
            }
            return;
          }
          resolvedUserId = exactPeer.id;
          resolvedChatId = exactPeer.chatId;
          resolvedName = exactPeer.name;
          resolvedAvatar = exactPeer.avatarUrl;
        }
      } catch (e) {
        debugPrint('DeepLink: peer lookup error: $e');
      }

      if (int.tryParse(resolvedUserId) == null) {
        final bot = await BotService.resolveBotByUsername(lookupName);
        if (bot != null && bot.userId.isNotEmpty) {
          resolvedUserId = bot.userId;
          resolvedName = bot.displayName;
          resolvedAvatar = bot.avatarUrl;
        }
      }

      if (int.tryParse(resolvedUserId) == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пользователь не найден')),
          );
        }
        return;
      }
    }

    // Ignore self-profile links
    final currentAccount = AccountManager().currentAccount;
    if (currentAccount != null && currentAccount.userId == resolvedUserId) {
      debugPrint('DeepLink: own profile, ignoring');
      return;
    }

    if (startParam != null && startParam.isNotEmpty) {
      String? targetChatId = resolvedChatId;
      if (targetChatId == null || targetChatId.isEmpty) {
        final createRes = await ChatService.createChat(
          chatType: 'private',
          participantIds: [resolvedUserId],
        );
        if (createRes['success'] == true) {
          final created = createRes['chat'];
          if (created is Chat) {
            targetChatId = created.id;
          } else {
            targetChatId = createRes['chat_id']?.toString();
          }
        }
      }
      if (targetChatId != null && targetChatId.isNotEmpty) {
        await ChatService.sendMessage(
          chatId: targetChatId,
          content: '/start $startParam',
        );
        if (context.mounted) {
          _navigateToPrivateChat(
            context,
            targetChatId,
            otherUserId: resolvedUserId,
            otherUserName: resolvedName,
            otherUserAvatar: resolvedAvatar,
          );
        }
        return;
      }
    }

    // 1. Check if private chat already exists
    final existingChatId = resolvedChatId ??
        await _findPrivateChatWithUser(resolvedUserId);

    if (existingChatId != null &&
        existingChatId.isNotEmpty &&
        context.mounted) {
      _navigateToPrivateChat(
        context,
        existingChatId,
        otherUserId: resolvedUserId,
        otherUserName: resolvedName,
        otherUserAvatar: resolvedAvatar,
      );
    } else if (context.mounted) {
      _showUserProfilePopup(context, resolvedUserId);
    }
  }

  /// Handles group / channel invite deep link (`/join/{inviteCode}`).
  Future<void> _handleGroupInvite(String inviteCode) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('DeepLink: no navigator context');
      return;
    }

    final previewRes = await ChatService.checkInviteLink(inviteCode);
    if (!context.mounted) return;

    final l10n = context.l10n;
    final preview = previewRes['success'] == true
        ? (previewRes['chat'] as Map<String, dynamic>? ?? previewRes)
        : null;

    final chatName = preview?['name']?.toString() ?? 'Чат по приглашению';
    final chatDesc = preview?['description']?.toString() ?? '';
    final chatType = preview?['chat_type']?.toString() ?? 'group';
    final memberCount = preview?['member_count'] ?? preview?['participants_count'];
    final alreadyMember = preview?['already_member'] == true;
    final previewChatId = preview?['id']?.toString() ?? preview?['chat_id']?.toString();

    if (alreadyMember && previewChatId != null && previewChatId.isNotEmpty) {
      _openGroupOrChannel(context, previewChatId, chatType, chatName);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(chatName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (memberCount != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  chatType == 'channel'
                      ? 'Канал • $memberCount подписчиков'
                      : 'Группа • $memberCount участников',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (chatDesc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(chatDesc),
              )
            else
              Text(
                l10n.translate('invite_join_prompt'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.translate('profile_cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final joinRes = await ChatService.joinByInviteLink(inviteCode);
              if (!context.mounted) return;
              if (joinRes['success'] == true) {
                final joinedChat = joinRes['chat'];
                final joinedId = joinedChat is Chat
                    ? joinedChat.id
                    : (joinRes['chat_id']?.toString() ?? previewChatId ?? '');
                final joinedType = joinedChat is Chat ? joinedChat.chatType : chatType;
                final joinedName = joinedChat is Chat ? joinedChat.name : chatName;
                if (joinedId.isNotEmpty) {
                  _openGroupOrChannel(context, joinedId, joinedType, joinedName);
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      joinRes['message']?.toString() ??
                          'Не удалось присоединиться по ссылке',
                    ),
                  ),
                );
              }
            },
            child: Text(l10n.translate('join')),
          ),
        ],
      ),
    );
  }

  void _openGroupOrChannel(
    BuildContext context,
    String chatId,
    String chatType,
    String chatName,
  ) {
    if (TilingLayoutController.instance.isWorkspaceMounted) {
      TilingLayoutController.instance.openChatInActiveTile(
        chatId: chatId,
        chatType: chatType,
        chatName: chatName,
      );
      return;
    }
    if (chatType == 'channel') {
      Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => ChannelScreen(
            channelId: chatId,
            channelName: chatName,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => GroupChatScreen(
            chatId: chatId,
            groupName: chatName,
          ),
        ),
      );
    }
  }

  /// Handles channel deep link (`/c/{channelName}`).
  Future<void> _handleChannel(String channelName) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('DeepLink: no navigator context');
      return;
    }

    try {
      final channels = await SearchService.searchChannels(query: channelName);
      if (channels.isNotEmpty && context.mounted) {
        final match = channels.firstWhere(
          (c) =>
              (c.username.toLowerCase() == channelName.toLowerCase()) ||
              c.name.toLowerCase() == channelName.toLowerCase(),
          orElse: () => channels.first,
        );
        await ChatService.joinPublicChat(match.id);
        if (!context.mounted) return;
        _openGroupOrChannel(context, match.id, match.chatType, match.name);
        return;
      }
    } catch (e) {
      debugPrint('DeepLink: error searching channel: $e');
    }

    if (context.mounted) {
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('channel_not_found')),
        ),
      );
    }
  }

  /// Finds existing private chat with a specific user.
  Future<String?> _findPrivateChatWithUser(String userId) async {
    try {
      final result = await ChatService.getChats();
      if (result['success'] == true && result['chats'] != null) {
        final chats = result['chats'] as List<Chat>;
        for (final chat in chats) {
          if (chat.chatType == 'private') {
            final detailsResult = await ChatService.getChat(chat.id);
            if (detailsResult['success'] == true && detailsResult['chat'] != null) {
              final chatDetails = detailsResult['chat'] as ChatDetails;
              final hasUser = chatDetails.participants.any((p) => p.id == userId);
              if (hasUser) {
                return chat.id;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DeepLink: error finding chat: $e');
    }
    return null;
  }

  /// Navigates to existing private chat.
  void _navigateToPrivateChat(
    BuildContext context,
    String chatId, {
    String? otherUserId,
    String? otherUserName,
    String? otherUserAvatar,
  }) {
    if (TilingLayoutController.instance.isWorkspaceMounted) {
      TilingLayoutController.instance.openChatInActiveTile(
        chatId: chatId,
        chatType: 'private',
        chatName: otherUserName ?? '',
        avatarUrl: otherUserAvatar,
        otherUserId: otherUserId,
      );
      return;
    }
    Navigator.of(context).push(
      SwipeBackPageRoute(
        builder: (_) => PrivateChatScreen(
          chatId: chatId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          otherUserAvatar: otherUserAvatar,
        ),
      ),
    );
  }

  /// Shows user profile popup dialog.
  Future<void> _showUserProfilePopup(BuildContext context, String userId) async {
    final l10n = context.l10n;

    String displayName = userId;
    String username = '';
    String? avatarUrl;

    try {
      final result = await AuthService.getUserProfile(userId);
      if (result['success'] == true && result['user'] != null) {
        final user = result['user'] as Map<String, dynamic>;
        displayName = user['display_name']?.toString() ?? userId;
        username = user['username']?.toString() ?? '';
        avatarUrl = user['avatar_url']?.toString();
      }
    } catch (e) {
      debugPrint('DeepLink: error loading user profile: $e');
    }

    if (!context.mounted) return;

    UserProfilePopup.show(
      context,
      userId: userId,
      displayName: displayName,
      username: username.isNotEmpty ? username : userId,
      avatarUrl: avatarUrl,
      startChatLabel: l10n.translate('profile_start_chat_with')
          .replaceAll('{name}', displayName),
      closeLabel: l10n.translate('profile_cancel'),
      onStartChat: () async {
        final result = await ChatService.createChat(
          chatType: 'private',
          participantIds: [userId],
        );

        if (result['success'] == true && context.mounted) {
          Navigator.of(context).pop();
          final chat = result['chat'];
          if (chat != null) {
            _navigateToPrivateChat(context, chat.id);
          }
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('profile_chat_create_error')
                  .replaceAll('{error}', result['message'] ?? '')),
            ),
          );
        }
      },
    );
  }

  /// Confirms a pending QR login request scanned by an already authenticated device.
  Future<void> _handleQrLogin(String token) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final authToken = await AuthService.getToken();
    if (!context.mounted) return;
    final l10n = context.l10n;
    if (authToken == null || authToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('devices_link_error'))),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('qr_confirm_dialog_title')),
        content: Text(l10n.translate('qr_confirm_dialog_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final res = await AuthService.confirmQrLogin(token: token);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['success'] == true
              ? (res['status'] == 'awaiting_2fa'
                  ? l10n.translate('devices_link_awaiting_2fa')
                  : l10n.translate('devices_link_success'))
              : (res['message']?.toString().isNotEmpty == true &&
                      res['error'] != 'qr_expired_or_invalid'
                  ? res['message'].toString()
                  : l10n.translate('devices_link_error')),
        ),
      ),
    );
  }

  /// Claims a QR grant generated on an authenticated device (`mode=grant`).
  Future<void> _handleQrGrant(String token) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('qr_confirm_dialog_title')),
        content: Text(l10n.translate('qr_confirm_dialog_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    var res = await AuthService.claimQrGrantSession(token: token);
    if (!context.mounted) return;

    if (res['requires_2fa'] == true) {
      final pwdCtrl = TextEditingController();
      final pwd = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.translate('security_2fa')),
          content: TextField(
            controller: pwdCtrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.translate('email_2fa_password_label'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, pwdCtrl.text.trim()),
              child: Text(l10n.translate('confirm')),
            ),
          ],
        ),
      );
      pwdCtrl.dispose();
      if (!context.mounted || pwd == null || pwd.isEmpty) return;
      res = await AuthService.claimQrGrantSession(
        token: token,
        twoFactorPassword: pwd,
      );
      if (!context.mounted) return;
    }

    if (res['success'] == true && res['auth_token'] != null) {
      final authToken = res['auth_token'].toString();
      final userId = res['user_id']?.toString() ?? '';
      final userMap = res['user'] is Map
          ? Map<String, dynamic>.from(res['user'] as Map)
          : null;
      await AuthService.completeExternalLoginSession(
        authToken: authToken,
        userId: userId,
        user: userMap,
        context: context,
      );
      await SettingsService().reloadForUser(userId);
      if (context.mounted) {
        try {
          await context.read<PrivacySettingsProvider>().reloadForUser();
        } catch (_) {}
      }
      if (context.mounted) {
        try {
          await context.read<NotificationSettingsProvider>().reloadForUser();
        } catch (_) {}
      }
      await WebSocketService().updateUserId(userId);
      TilingLayoutController.instance.closeAllChats();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        SwipeBackPageRoute(builder: (_) => const TilingWorkspaceScaffold()),
        (route) => false,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['error'] == 'invalid_2fa_password'
              ? l10n.translate('email_error_invalid_2fa')
              : l10n.translate('devices_link_error'),
        ),
      ),
    );
  }
}
