import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../models/call_models.dart';
import '../../models/community_models.dart';
import '../../models/theav_theme.dart';
import '../../services/call_state_provider.dart';
import '../../services/community_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../widgets/whiteboard/interactive_whiteboard.dart';
import '../call/group_call_screen.dart';
import '../chat/group_chat_screen.dart';
import 'community_settings_sheet.dart';

/// Adaptive Community («Сообщество») Screen:
/// - On Compact tiles (`width < 680px`): Displays the Community Banner, Collapsible Categories,
///   Text Channels (`#`), Voice Rooms (`🔊`) with live participant avatars & `LIVE 144fps` badges,
///   and Stage Channels (`🎙️`). Tapping a text channel opens `GroupChatScreen` with a swipeable
///   left channel-tree drawer; tapping a voice/stage channel joins the room via `CallStateProvider`.
/// - On Wide tiles/Desktop (`width >= 680px`): Renders a two-pane split layout (268px channel tree
///   sidebar on the left + active text chat or embedded live voice/stage room on the right).
class CommunityScreen extends StatefulWidget {
  final Community community;
  final ValueChanged<Community>? onCommunityJoined;
  final VoidCallback? onCommunityLeft;

  const CommunityScreen({
    super.key,
    required this.community,
    this.onCommunityJoined,
    this.onCommunityLeft,
  });

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late Community _community;
  CommunityChannel? _selectedChannel;
  final Set<String> _collapsedCategoryIds = {};
  bool _loadingDetails = false;
  bool _joining = false;
  StreamSubscription<WebSocketEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    _community = widget.community;
    _selectInitialChannel();
    _fetchFreshCommunity();
    _wsSub = WebSocketService().eventStream.listen(_onWsMessage);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void _onWsMessage(WebSocketEvent event) {
    if (event.type == WebSocketEventType.emojiInteraction &&
        event.data['action']?.toString() == '__webrtc_call__') {
      final rawEmoji = event.data['emoji']?.toString() ?? '';
      if (rawEmoji.isNotEmpty) {
        try {
          final decodedJson = utf8.decode(base64Decode(rawEmoji));
          final envelope = jsonDecode(decodedJson);
          if (envelope is Map<String, dynamic>) {
            final evType = (envelope['event'] ?? '').toString();
            final payload = envelope['payload'] is Map
                ? Map<String, dynamic>.from(envelope['payload'] as Map)
                : <String, dynamic>{};
            final senderId = event.data['user_id']?.toString() ?? '';
            if (senderId.isNotEmpty) {
              payload.putIfAbsent('user_id', () => senderId);
              payload.putIfAbsent('from_user_id', () => senderId);
            }
            _handleVoiceOrCallEvent(evType.replaceAll('.', '_'), payload);
          }
        } catch (_) {}
      }
      return;
    }

    final rawType = event.rawType.isNotEmpty
        ? event.rawType
        : (event.data['__raw_type'] ?? event.data['type'] ?? '').toString();
    final normalizedType = rawType.replaceAll('.', '_');
    final raw = event.data;
    final payload = raw['payload'] is Map<String, dynamic>
        ? raw['payload'] as Map<String, dynamic>
        : raw;

    if (normalizedType == 'community_updated' ||
        normalizedType == 'community_channel_created') {
      final commId = (payload['community_id'] ??
              (payload['community'] is Map
                  ? (payload['community'] as Map)['id']
                  : null) ??
              '')
          .toString();
      if (commId.isEmpty || commId == _community.id) {
        _fetchFreshCommunity();
      }
      return;
    }

    if (normalizedType == 'community_channel_deleted') {
      final commId = (payload['community_id'] ?? '').toString();
      final channelId =
          (payload['channel_id'] ?? payload['chat_id'] ?? '').toString();
      if ((commId.isEmpty || commId == _community.id) && channelId.isNotEmpty) {
        setState(() {
          final remaining = _community.channels
              .where((c) => c.id != channelId)
              .toList();
          _community = _community.copyWith(channels: remaining);
          if (_community.isMember) {
            CommunityService.cacheCommunity(_community);
          }
          if (_selectedChannel?.id == channelId) {
            _selectedChannel = null;
            _selectInitialChannel();
          }
        });
      }
      return;
    }

    if (normalizedType == 'community_deleted') {
      final commId =
          (payload['community_id'] ?? payload['id'] ?? '').toString();
      if (commId == _community.id) {
        CommunityService.removeCommunityFromCache(_community.id);
        if (mounted) {
          TilingLayoutController.popOrCloseChatTile(context);
        }
      }
      return;
    }

    if (normalizedType == 'community_voice_state_updated' ||
        normalizedType.startsWith('call_')) {
      _handleVoiceOrCallEvent(normalizedType, payload);
    }
  }

  void _handleVoiceOrCallEvent(
    String normalizedType,
    Map<String, dynamic> payload,
  ) {
    if (!mounted) return;
    final callMap = payload['call'] is Map
        ? Map<String, dynamic>.from(payload['call'] as Map)
        : null;
    final chatId = (payload['chat_id'] ??
            callMap?['chat_id'] ??
            (payload['stream'] is Map
                ? (payload['stream'] as Map)['chat_id']
                : null) ??
            '')
        .toString();
    final commId =
        (payload['community_id'] ?? callMap?['community_id'] ?? '').toString();

    final hasMatchingChannel =
        chatId.isNotEmpty && _community.channels.any((c) => c.id == chatId);
    if (!hasMatchingChannel && commId != _community.id) {
      return;
    }

    if (callMap != null && hasMatchingChannel) {
      final session = CallSession.fromJson(callMap);
      final isEnded = session.status == 'ended' ||
          session.status == 'canceled' ||
          session.status == 'declined' ||
          normalizedType == 'call_ended';
      final streamOwnerIds =
          session.streams.map((s) => s.streamerId).toSet();
      final updatedParticipants = isEnded
          ? const <CallParticipant>[]
          : session.participants
              .where((p) => p.state == 'connected' || p.state.isEmpty)
              .map((p) => streamOwnerIds.contains(p.userId) && !p.isScreenSharing
                  ? p.copyWith(isScreenSharing: true)
                  : p)
              .toList();
      _updateChannelParticipants(chatId, updatedParticipants);
      return;
    }

    if (!hasMatchingChannel) {
      if (commId == _community.id) {
        _fetchFreshCommunity();
      }
      return;
    }

    final ch = _community.channels.firstWhere((c) => c.id == chatId);
    switch (normalizedType) {
      case 'call_ended':
        final reason = (payload['reason'] ?? '').toString();
        final fromUserId =
            (payload['from_user_id'] ?? payload['user_id'] ?? '').toString();
        if (reason.isEmpty && fromUserId.isNotEmpty) {
          _updateChannelParticipants(
            chatId,
            ch.activeVoiceParticipants
                .where((p) => p.userId != fromUserId)
                .toList(),
          );
        } else {
          _updateChannelParticipants(chatId, const []);
        }
        break;
      case 'call_participant_left':
        final userId =
            (payload['user_id'] ?? payload['from_user_id'] ?? '').toString();
        if (userId.isNotEmpty) {
          _updateChannelParticipants(
            chatId,
            ch.activeVoiceParticipants
                .where((p) => p.userId != userId)
                .toList(),
          );
        }
        break;
      case 'call_participant_joined':
      case 'call_accepted':
        if (payload['participant'] is Map) {
          final p = CallParticipant.fromJson(
            Map<String, dynamic>.from(payload['participant'] as Map),
          );
          final next = [
            ...ch.activeVoiceParticipants.where((x) => x.userId != p.userId),
            p,
          ];
          _updateChannelParticipants(chatId, next);
        } else {
          _fetchFreshCommunity();
        }
        break;
      case 'call_participant_updated':
      case 'call_state_changed':
        final userId =
            (payload['user_id'] ?? payload['from_user_id'] ?? '').toString();
        if (userId.isNotEmpty) {
          final next = ch.activeVoiceParticipants.map((p) {
            if (p.userId != userId) return p;
            return p.copyWith(
              isMuted:
                  (payload['self_mute'] ?? payload['is_muted']) as bool?,
              isDeafened:
                  (payload['self_deaf'] ?? payload['is_deafened']) as bool?,
              isVideoOn: payload['is_video_on'] as bool?,
              isScreenSharing: payload['is_screen_sharing'] as bool?,
            );
          }).toList();
          _updateChannelParticipants(chatId, next);
        }
        break;
      case 'call_stream_started':
        final sMap = payload['stream'] is Map
            ? Map<String, dynamic>.from(payload['stream'] as Map)
            : payload;
        final streamerId = (sMap['streamer_id'] ?? '').toString();
        if (streamerId.isNotEmpty) {
          final next = ch.activeVoiceParticipants
              .map((p) => p.userId == streamerId
                  ? p.copyWith(isScreenSharing: true)
                  : p)
              .toList();
          _updateChannelParticipants(chatId, next);
        }
        break;
      case 'call_stream_stopped':
        final streamerId =
            (payload['streamer_id'] ?? payload['from_user_id'] ?? '')
                .toString();
        if (streamerId.isNotEmpty) {
          final next = ch.activeVoiceParticipants
              .map((p) => p.userId == streamerId
                  ? p.copyWith(isScreenSharing: false)
                  : p)
              .toList();
          _updateChannelParticipants(chatId, next);
        } else {
          _fetchFreshCommunity();
        }
        break;
    }
  }

  void _updateChannelParticipants(
    String channelId,
    List<CallParticipant> participants,
  ) {
    if (!mounted) return;
    setState(() {
      final updatedChannels = _community.channels.map((c) {
        if (c.id == channelId) {
          return c.copyWith(activeVoiceParticipants: participants);
        }
        return c;
      }).toList();
      _community = _community.copyWith(channels: updatedChannels);
      if (_selectedChannel?.id == channelId) {
        _selectedChannel = _selectedChannel!.copyWith(
          activeVoiceParticipants: participants,
        );
      }
      if (_community.isMember) {
        CommunityService.cacheCommunity(_community);
      }
    });
  }

  void _onLocalVoiceLeft(String? channelId) {
    if (!mounted) return;
    final myId = context.read<CallStateProvider>().currentUserId;
    setState(() {
      if (channelId != null && channelId.isNotEmpty) {
        final updatedChannels = _community.channels.map((c) {
          if (c.id == channelId) {
            return c.copyWith(
              activeVoiceParticipants: c.activeVoiceParticipants
                  .where((p) =>
                      p.userId != 'local' &&
                      (myId == null || p.userId != myId))
                  .toList(),
            );
          }
          return c;
        }).toList();
        _community = _community.copyWith(channels: updatedChannels);
      }
      if (_selectedChannel != null &&
          _selectedChannel!.isAudioRoom &&
          (channelId == null || _selectedChannel!.id == channelId)) {
        _selectedChannel = _community.channels
            .where((c) => !c.isAudioRoom)
            .firstOrNull;
      }
    });
    _fetchFreshCommunity();
  }

  void _selectInitialChannel() {
    if (_community.channels.isEmpty) {
      _selectedChannel = null;
      return;
    }
    if (_selectedChannel != null) {
      final match = _community.channels
          .where((c) => c.id == _selectedChannel!.id)
          .firstOrNull;
      if (match != null) {
        _selectedChannel = match;
        return;
      }
    }
    _selectedChannel = _community.channels
        .where((c) => !c.isAudioRoom)
        .firstOrNull;
  }

  Future<void> _fetchFreshCommunity() async {
    if (!mounted) return;
    setState(() => _loadingDetails = true);
    final fresh = await CommunityService.getCommunity(_community.id);
    if (!mounted) return;
    setState(() {
      _loadingDetails = false;
      if (fresh != null) {
        _community = fresh;
        if (_community.isMember) {
          CommunityService.cacheCommunity(_community);
        }
        _selectInitialChannel();
      }
    });
  }

  Future<void> _joinCommunity() async {
    if (_joining) return;
    HapticFeedback.mediumImpact();
    setState(() => _joining = true);
    final joined = await CommunityService.joinCommunity(_community.id);
    if (!mounted) return;
    setState(() => _joining = false);
    if (joined != null) {
      setState(() {
        _community = joined.copyWith(isMember: true);
        _selectInitialChannel();
      });
      CommunityService.cacheCommunity(_community);
      widget.onCommunityJoined?.call(_community);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Вы вступили в сообщество «${_community.name}»'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось вступить в сообщество'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmLeaveCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Покинуть сообщество?'),
        content: Text(
          'Вы действительно хотите выйти из сообщества «${_community.name}»?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await CommunityService.leaveCommunity(_community.id);
    if (!mounted) return;
    if (ok) {
      widget.onCommunityLeft?.call();
      TilingLayoutController.popOrCloseChatTile(context);
    }
  }

  void _openSettings() {
    if (!_community.isMember) return;
    CommunitySettingsSheet.show(
      context,
      community: _community,
      onCommunityUpdated: (updated) {
        setState(() {
          _community = updated;
          if (_community.isMember) {
            CommunityService.cacheCommunity(_community);
          }
          _selectInitialChannel();
        });
      },
    );
  }

  Future<void> _onSelectChannel(
    CommunityChannel channel, {
    required bool isDesktop,
  }) async {
    HapticFeedback.selectionClick();
    if (!_community.isMember && channel.isAudioRoom) {
      await _joinCommunity();
      if (!mounted || !_community.isMember) return;
    }
    final clearedChannel = channel.copyWith(unreadCount: 0);
    CommunityService.resetChannelUnread(channel.id);
    setState(() {
      _selectedChannel = clearedChannel;
      _community = _community.copyWith(
        channels: _community.channels
            .map((c) => c.id == channel.id ? clearedChannel : c)
            .toList(),
      );
    });

    if (isDesktop) {
      if (channel.isAudioRoom) {
        context.read<CallStateProvider>().startOrJoinCall(
              chatId: channel.id,
              chatTitle: '${_community.name} • ${channel.name}',
              callType: channel.isStage ? 'stage' : 'group',
              communityId: _community.id,
              isVideo: false,
            );
      }
      return;
    }

    // Compact / mobile navigation inside the current tile navigator
    if (channel.isAudioRoom) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: channel.id,
            chatId: channel.id,
            userId: 'local',
            title: '${_community.name} • ${channel.name}',
            isStage: channel.isStage,
            onLeave: () => _onLocalVoiceLeft(channel.id),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _MobileCommunityChatWrapper(
            community: _community,
            initialChannel: channel,
            onOpenSettings: _openSettings,
          ),
        ),
      );
    }
  }

  ImageProvider? _resolveAvatarImage(String? rawUrl) {
    final resolved = AppConfig.resolveMediaUrl(rawUrl);
    if (resolved == null || resolved.isEmpty) return null;
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return NetworkImage(resolved);
    }
    return FileImage(File(resolved));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theav;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 680;

        if (isDesktop) {
          final selected = _selectedChannel;
          return Scaffold(
            backgroundColor: p.bgBase,
            body: Row(
              children: [
                SizedBox(
                  width: 268,
                  child: Material(
                    color: p.surfacePrimary,
                    child: _buildChannelTreePane(
                      context,
                      isDesktop: true,
                    ),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 0.8, color: p.borderSubtle),
                Expanded(
                  child: selected == null
                      ? Center(
                          child: Text(
                            _loadingDetails
                                ? 'Загрузка каналов...'
                                : 'В сообществе пока нет доступных каналов',
                            style: TextStyle(color: p.textSecondary),
                          ),
                        )
                      : selected.isAudioRoom
                          ? GroupCallScreen(
                              key: ValueKey('voice_${selected.id}'),
                              callId: selected.id,
                              chatId: selected.id,
                              userId: 'local',
                              title: selected.name,
                              isStage: selected.isStage,
                              embedded: true,
                              onLeave: () => _onLocalVoiceLeft(selected.id),
                            )
                          : selected.isWhiteboard
                              ? InteractiveWhiteboard(
                                  key: ValueKey('wb_${selected.id}'),
                                  roomId: selected.id,
                                  chatId: selected.id,
                                  title: '${_community.name} • ${selected.name}',
                                )
                              : Column(
                              children: [
                                if ((selected.isAnnouncement &&
                                        !_community.canManageChannels) ||
                                    !_community.canSendMessages)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    color: p.surfaceSecondary,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.campaign_rounded,
                                          size: 16,
                                          color: p.textSecondary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            selected.isAnnouncement
                                                ? 'Канал объявлений — публиковать сообщения могут только администраторы и модераторы'
                                                : 'У вас нет прав на отправку сообщений в этом канале',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: p.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Expanded(
                                  child: GroupChatScreen(
                                    key: ValueKey('text_${selected.id}'),
                                    chatId: selected.id,
                                    groupName: '# ${selected.name}',
                                    groupAvatar: _community.avatarUrl,
                                  ),
                                ),
                              ],
                            ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: p.bgBase,
          body: _buildChannelTreePane(context, isDesktop: false),
        );
      },
    );
  }

  Widget _buildChannelTreePane(
    BuildContext context, {
    required bool isDesktop,
  }) {
    final p = context.theav;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final useGlass = glassProvider.enabled;
    final isFullGlass = glassProvider.isFull;
    final callProvider = context.watch<CallStateProvider>();

    final knownCatIds = _community.categories.map((c) => c.id).toSet();
    final uncategorized = _community.channels
        .where(
          (c) =>
              c.categoryId == null ||
              c.categoryId!.isEmpty ||
              !knownCatIds.contains(c.categoryId),
        )
        .toList();
    final avatarImage = _resolveAvatarImage(_community.avatarUrl);

    return Column(
      children: [
        // Top Community Header Banner
        Container(
          padding: EdgeInsets.fromLTRB(
            14,
            MediaQuery.of(context).padding.top + 10,
            14,
            14,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primaryColor.withValues(alpha: isDark ? 0.28 : 0.16),
                p.surfacePrimary,
              ],
            ),
            border: Border(
              bottom: BorderSide(color: p.borderSubtle, width: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 19,
                      color: p.textPrimary,
                    ),
                    onPressed: () =>
                        TilingLayoutController.popOrCloseChatTile(context),
                  ),
                  const SizedBox(width: 4),
                  // Squircle Community Avatar
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                      image: avatarImage != null
                          ? DecorationImage(
                              image: avatarImage,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: avatarImage == null
                        ? Text(
                            _community.name.isNotEmpty
                                ? _community.name[0].toUpperCase()
                                : 'C',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: primaryColor,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _community.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: primaryColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_community.memberCount} участн. • ${_community.onlineCount} в сети',
                          style: TextStyle(
                            fontSize: 12,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_community.isMember)
                    FilledButton.tonalIcon(
                      onPressed: _joining ? null : _joinCommunity,
                      icon: _joining
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.group_add_rounded, size: 17),
                      label: const Text('Вступить'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                    )
                  else if (_community.canManageCommunity)
                    IconButton(
                      icon: Icon(Icons.tune_rounded, color: p.textSecondary),
                      tooltip: 'Настройки сообщества',
                      onPressed: _openSettings,
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.logout_rounded, color: p.textSecondary),
                      tooltip: 'Покинуть сообщество',
                      onPressed: _confirmLeaveCommunity,
                    ),
                ],
              ),
              if (_community.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    _community.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (_loadingDetails)
          const LinearProgressIndicator(minHeight: 2),

        // Category & Channel Tree
        Expanded(
          child: _community.channels.isEmpty && !_loadingDetails
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'В этом сообществе пока нет открытых каналов',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  children: [
                    for (final ch in uncategorized)
                      _buildChannelTile(
                        context,
                        ch,
                        isDesktop: isDesktop,
                        primaryColor: primaryColor,
                        p: p,
                        callProvider: callProvider,
                      ),
                    for (final cat in _community.categories) ...[
                      _buildCategoryHeader(cat, p),
                      if (!_collapsedCategoryIds.contains(cat.id))
                        ..._community.channels
                            .where((c) => c.categoryId == cat.id)
                            .map(
                              (ch) => _buildChannelTile(
                                context,
                                ch,
                                isDesktop: isDesktop,
                                primaryColor: primaryColor,
                                p: p,
                                callProvider: callProvider,
                              ),
                            ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),

        // Prominent bottom Join Community CTA bar for non-members
        if (!_community.isMember)
          Container(
            padding: EdgeInsets.fromLTRB(
              14,
              10,
              14,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: p.surfaceElevated,
              border: Border(
                top: BorderSide(color: p.borderSubtle, width: 0.6),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: _joining ? null : _joinCommunity,
                  icon: _joining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_circle_outline_rounded),
                  label: Text(
                    _joining
                        ? 'Вступление...'
                        : 'Вступить в сообщество «${_community.name}»',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Bottom Connected Voice Status Bar (if user is in an active call)
        if (callProvider.hasActiveCall)
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              4,
              10,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: useGlass
                  ? LiquidGlassLens(
                      style: context.read<LiquidGlassProvider>().createStyle(
                            context: context,
                            cornerRadius: 18,
                            color: const Color(0xFF00C853).withValues(alpha: 0.14),
                            refractionIndex: isFullGlass ? 1.1 : 1.04,
                            refractionWidth: 20.0,
                          ),
                      child: _buildVoiceConnectedBar(callProvider, p),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter.grouped(
                        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: p.surfaceElevated.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF00C853)
                                  .withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: _buildVoiceConnectedBar(callProvider, p),
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryHeader(CommunityCategory cat, TheavPalette p) {
    final collapsed = _collapsedCategoryIds.contains(cat.id);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (collapsed) {
            _collapsedCategoryIds.remove(cat.id);
          } else {
            _collapsedCategoryIds.add(cat.id);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: p.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                cat.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: p.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelTile(
    BuildContext context,
    CommunityChannel ch, {
    required bool isDesktop,
    required Color primaryColor,
    required TheavPalette p,
    required CallStateProvider callProvider,
  }) {
    final isSelected = isDesktop && _selectedChannel?.id == ch.id;
    final isThisVoiceActive =
        callProvider.activeCall?.chatId == ch.id;
    final liveParticipants = isThisVoiceActive
        ? (callProvider.activeCall?.participants ?? ch.activeVoiceParticipants)
        : ch.activeVoiceParticipants;

    final IconData leadingIcon = ch.isStage
        ? Icons.podcasts_rounded
        : ch.isVoice
            ? Icons.volume_up_rounded
            : ch.isWhiteboard
                ? Icons.draw_rounded
                : ch.isAnnouncement
                    ? Icons.campaign_rounded
                    : Icons.tag_rounded;

    final Color iconColor = ch.isAudioRoom
        ? const Color(0xFF00C853)
        : ch.isWhiteboard
            ? const Color(0xFFAA00FF)
            : (isSelected ? primaryColor : p.textSecondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onSelectChannel(ch, isDesktop: isDesktop),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(
                  children: [
                    Icon(leadingIcon, size: 20, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: isSelected || ch.unreadCount > 0
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? primaryColor : p.textPrimary,
                        ),
                      ),
                    ),
                    if (ch.isAudioRoom && isThisVoiceActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C853).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'В эфире',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00C853),
                          ),
                        ),
                      )
                    else if (ch.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${ch.unreadCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Live voice participants nested under voice/stage room
          if (ch.isAudioRoom && liveParticipants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 2, bottom: 4),
              child: Column(
                children: liveParticipants.map((part) {
                  final partAvatar = _resolveAvatarImage(part.avatarUrl);
                  final isStreaming = part.isScreenSharing ||
                      (isThisVoiceActive &&
                          (callProvider.activeCall?.streams
                                  .any((s) => s.streamerId == part.userId) ??
                              false));
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withValues(alpha: 0.25),
                            image: partAvatar != null
                                ? DecorationImage(
                                    image: partAvatar,
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            border: Border.all(
                              color: part.isSpeaking
                                  ? const Color(0xFF00E676)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: partAvatar == null
                              ? Text(
                                  part.displayName.isNotEmpty
                                      ? part.displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            part.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                        if (part.isMuted) ...[
                          const Icon(
                            Icons.mic_off_rounded,
                            size: 13,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (part.isVideoOn && !isStreaming) ...[
                          Icon(
                            Icons.videocam_rounded,
                            size: 13,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (isStreaming)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceConnectedBar(
    CallStateProvider callProvider,
    TheavPalette p,
  ) {
    final call = callProvider.activeCall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(
            Icons.graphic_eq_rounded,
            color: Color(0xFF00E676),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Голос подключён',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00C853),
                  ),
                ),
                Text(
                  call?.title ?? _community.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (callProvider.isScreenSharing)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Остановить трансляцию экрана',
              icon: const Icon(
                Icons.stop_screen_share_rounded,
                size: 19,
                color: Colors.redAccent,
              ),
              onPressed: () => callProvider.stopScreenShare(),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              callProvider.isMuted
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              size: 19,
              color: callProvider.isMuted ? Colors.redAccent : p.textPrimary,
            ),
            onPressed: () => callProvider.toggleMute(),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.call_end_rounded,
              size: 19,
              color: Colors.redAccent,
            ),
            onPressed: () async {
              final leftChatId = call?.chatId;
              await callProvider.leaveCall();
              _onLocalVoiceLeft(leftChatId);
            },
          ),
        ],
      ),
    );
  }
}

/// Mobile wrapper around `GroupChatScreen` that provides a left-edge swipeable
/// `Drawer` with the Community Channel Tree so the user can jump between
/// `#text` and `🔊 voice` channels without backing out.
class _MobileCommunityChatWrapper extends StatefulWidget {
  final Community community;
  final CommunityChannel initialChannel;
  final VoidCallback onOpenSettings;

  const _MobileCommunityChatWrapper({
    required this.community,
    required this.initialChannel,
    required this.onOpenSettings,
  });

  @override
  State<_MobileCommunityChatWrapper> createState() =>
      _MobileCommunityChatWrapperState();
}

class _MobileCommunityChatWrapperState
    extends State<_MobileCommunityChatWrapper> {
  late CommunityChannel _activeChannel;

  @override
  void initState() {
    super.initState();
    _activeChannel = widget.initialChannel;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theav;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final knownCatIds = widget.community.categories.map((c) => c.id).toSet();
    final uncategorized = widget.community.channels
        .where((c) =>
            c.categoryId == null ||
            c.categoryId!.isEmpty ||
            !knownCatIds.contains(c.categoryId))
        .toList();

    Widget buildChannelTile(CommunityChannel ch) {
      final selected = ch.id == _activeChannel.id;
      final voiceCount = ch.activeVoiceParticipants.length;
      return ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selected: selected,
        leading: Icon(
          ch.isStage
              ? Icons.podcasts_rounded
              : ch.isVoice
                  ? Icons.volume_up_rounded
                  : ch.isWhiteboard
                      ? Icons.draw_rounded
                      : ch.isAnnouncement
                          ? Icons.campaign_rounded
                          : Icons.tag_rounded,
          size: 20,
        ),
        title: Text(
          ch.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ch.isAudioRoom && voiceCount > 0
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$voiceCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00C853),
                  ),
                ),
              )
            : ch.unreadCount > 0 && !selected
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${ch.unreadCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : null,
        onTap: () {
          Navigator.of(context).pop();
          if (ch.isAudioRoom) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupCallScreen(
                  callId: ch.id,
                  chatId: ch.id,
                  userId: 'local',
                  title: '${widget.community.name} • ${ch.name}',
                  isStage: ch.isStage,
                ),
              ),
            );
          } else {
            CommunityService.resetChannelUnread(ch.id);
            setState(() => _activeChannel = ch.copyWith(unreadCount: 0));
          }
        },
      );
    }

    return Scaffold(
      drawerEdgeDragWidth: 44,
      drawer: Drawer(
        backgroundColor: p.surfacePrimary,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.community.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    if (widget.community.canManageCommunity)
                      IconButton(
                        icon: Icon(Icons.tune_rounded, color: p.textSecondary),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenSettings();
                        },
                      ),
                  ],
                ),
              ),
              Divider(color: p.borderSubtle, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    ...uncategorized.map(buildChannelTile),
                    ...widget.community.categories.expand((cat) {
                      final catChannels = widget.community.channels
                          .where((c) => c.categoryId == cat.id)
                          .toList();
                      return [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: Text(
                            cat.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: p.textTertiary,
                            ),
                          ),
                        ),
                        ...catChannels.map(buildChannelTile),
                      ];
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _activeChannel.isWhiteboard
          ? SafeArea(
              child: InteractiveWhiteboard(
                key: ValueKey('mobile_wb_${_activeChannel.id}'),
                roomId: _activeChannel.id,
                chatId: _activeChannel.id,
                title: '${widget.community.name} • ${_activeChannel.name}',
                onClose: () => Navigator.of(context).maybePop(),
              ),
            )
          : Column(
              children: [
                if ((_activeChannel.isAnnouncement &&
                        !widget.community.canManageChannels) ||
                    !widget.community.canSendMessages)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: p.surfaceSecondary,
                    child: Text(
                      _activeChannel.isAnnouncement
                          ? 'Канал объявлений — только для чтения'
                          : 'У вас нет прав на отправку сообщений в этом канале',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ),
                Expanded(
                  child: GroupChatScreen(
                    key: ValueKey('mobile_comm_${_activeChannel.id}'),
                    chatId: _activeChannel.id,
                    groupName: '# ${_activeChannel.name}',
                    groupAvatar: widget.community.avatarUrl,
                  ),
                ),
              ],
            ),
    );
  }
}
