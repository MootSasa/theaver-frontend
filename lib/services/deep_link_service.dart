import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'chat_service.dart';
import 'search_service.dart';
import 'account_manager.dart';
import 'tiling_layout_controller.dart';
import '../l10n/app_localizations.dart';
import '../widgets/profile/user_profile_popup.dart';
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
}

/// Parsed deep link metadata
class ParsedDeepLink {
  final DeepLinkType type;
  final String identifier;

  const ParsedDeepLink(this.type, this.identifier);
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
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;

  /// Global navigator key to access current context
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Initializes deep link handling and processes initial link on Web.
  Future<void> init() async {
    debugPrint('DeepLinkService: initialized');

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final uri = Uri.base;
          final parsed = parseUri(uri);
          if (parsed != null) {
            handleLink(uri);
          }
        } catch (e) {
          debugPrint('DeepLinkService: web initial link error: $e');
        }
      });
    }
  }

  /// Parses an incoming URI into a structured ParsedDeepLink or null if unrecognized.
  static ParsedDeepLink? parseUri(Uri uri) {
    // 1. Check fragment first (for Web hash routing e.g. /#/u/123 or /#/join/code)
    if (uri.fragment.isNotEmpty) {
      final fragmentPath = uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}';
      try {
        final fragmentUri = Uri.parse('app://local$fragmentPath');
        final fromFragment = _extractFromSegments(fragmentUri.pathSegments, fragmentUri.queryParameters);
        if (fromFragment != null) return fromFragment;
      } catch (_) {}
    }

    // 2. Check custom scheme: theaver://
    if (uri.scheme == 'theaver') {
      final host = uri.host.toLowerCase();
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
      }
    }

    // 3. Check regular path segments for any domain or IP
    return _extractFromSegments(uri.pathSegments, uri.queryParameters);
  }

  static ParsedDeepLink? _extractFromSegments(List<String> segments, Map<String, String> query) {
    if (segments.isEmpty) return null;

    final first = segments.first.toLowerCase();
    if ((first == 'u' || first == 'user') && segments.length >= 2) {
      final id = segments[1].trim();
      if (id.isNotEmpty) return ParsedDeepLink(DeepLinkType.userProfile, id);
    }
    if ((first == 'join' || first == 'invite') && segments.length >= 2) {
      final code = segments[1].trim();
      if (code.isNotEmpty) return ParsedDeepLink(DeepLinkType.groupInvite, code);
    }
    if ((first == 'c' || first == 'channel') && segments.length >= 2) {
      final name = segments[1].trim();
      if (name.isNotEmpty) return ParsedDeepLink(DeepLinkType.channel, name);
    }
    if ((first == 'addtheme' || first == 'theme') && segments.length >= 2) {
      final code = segments[1].trim();
      if (code.isNotEmpty) return ParsedDeepLink(DeepLinkType.addTheme, code);
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
        await _handleUserProfile(parsed.identifier);
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
    }
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

  /// Handles user profile deep link (`/u/{userId}`).
  Future<void> _handleUserProfile(String userId) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('DeepLink: no navigator context');
      return;
    }

    // Ignore self-profile links
    final currentAccount = AccountManager().currentAccount;
    if (currentAccount != null && currentAccount.userId == userId) {
      debugPrint('DeepLink: own profile, ignoring');
      return;
    }

    // 1. Check if private chat already exists
    final existingChatId = await _findPrivateChatWithUser(userId);

    if (existingChatId != null && context.mounted) {
      _navigateToPrivateChat(context, existingChatId);
    } else if (context.mounted) {
      _showUserProfilePopup(context, userId);
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
  void _navigateToPrivateChat(BuildContext context, String chatId) {
    if (TilingLayoutController.instance.isWorkspaceMounted) {
      TilingLayoutController.instance.openChatInActiveTile(
        chatId: chatId,
        chatType: 'private',
        chatName: '',
      );
      return;
    }
    Navigator.of(context).push(
      SwipeBackPageRoute(
        builder: (_) => PrivateChatScreen(chatId: chatId),
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
}
