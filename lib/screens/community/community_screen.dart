import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../models/call_models.dart';
import '../../models/community_models.dart';
import '../../services/call_state_provider.dart';
import '../../services/community_service.dart';
import '../../services/contacts_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/community/community_channel_icon.dart';
import '../../widgets/community/community_members_panel.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/whiteboard/interactive_whiteboard.dart';
import '../call/group_call_screen.dart';
import '../chat/group_chat_screen.dart';
import 'community_settings_sheet.dart';

/// Adaptive dual-mode Community screen blending Telegram's floating HUD and
/// inset-group hierarchy with full Discord server structure (categories, text,
/// announcement, forum, whiteboard, voice & stage rooms, hoisted members).
class CommunityScreen extends StatefulWidget {
  final Community community;
  final ValueChanged<Community>? onCommunityJoined;
  final VoidCallback? onCommunityLeft;
  final bool autoFetch;
  final List<CommunityMember>? initialMembers;

  const CommunityScreen({
    super.key,
    required this.community,
    this.onCommunityJoined,
    this.onCommunityLeft,
    this.autoFetch = true,
    this.initialMembers,
  });

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late Community _community;
  CommunityChannel? _selectedChannel;
  final Set<String> _collapsedCategoryIds = {};
  List<CommunityMember> _members = const [];
  bool _loadingDetails = false;
  bool _loadingMembers = false;
  bool _joining = false;
  bool _showMembersPane = true;
  StreamSubscription<WebSocketEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    _community = widget.community;
    if (widget.initialMembers != null) {
      _members = widget.initialMembers!;
    }
    _selectInitialChannel();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    if (widget.autoFetch) {
      _fetchFreshCommunity();
      if (_community.isMember) {
        _fetchMembers();
      }
      _wsSub = WebSocketService().eventStream.listen(_onWsMessage);
    }
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
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
        normalizedType == 'community_channel_created' ||
        normalizedType == 'community_member_joined' ||
        normalizedType == 'community_member_left') {
      final commId = (payload['community_id'] ??
              (payload['community'] is Map
                  ? (payload['community'] as Map)['id']
                  : null) ??
              '')
          .toString();
      if (commId.isEmpty || commId == _community.id) {
        _fetchFreshCommunity();
        if (_community.isMember) {
          _fetchMembers();
        }
      }
      return;
    }

    if (normalizedType == 'community_channel_deleted') {
      final commId = (payload['community_id'] ?? '').toString();
      final channelId =
          (payload['channel_id'] ?? payload['chat_id'] ?? '').toString();
      if ((commId.isEmpty || commId == _community.id) && channelId.isNotEmpty) {
        setState(() {
          final remaining =
              _community.channels.where((c) => c.id != channelId).toList();
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
      final streamOwnerIds = session.streams.map((s) => s.streamerId).toSet();
      final updatedParticipants = isEnded
          ? const <CallParticipant>[]
          : session.participants
              .where((p) => p.state == 'connected' || p.state.isEmpty)
              .map(
                (p) => streamOwnerIds.contains(p.userId) && !p.isScreenSharing
                    ? p.copyWith(isScreenSharing: true)
                    : p,
              )
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
          final part = CallParticipant.fromJson(
            Map<String, dynamic>.from(payload['participant'] as Map),
          );
          final next = [
            ...ch.activeVoiceParticipants.where((x) => x.userId != part.userId),
            part,
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
              isMuted: (payload['self_mute'] ?? payload['is_muted']) as bool?,
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
              .map(
                (p) => p.userId == streamerId
                    ? p.copyWith(isScreenSharing: true)
                    : p,
              )
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
              .map(
                (p) => p.userId == streamerId
                    ? p.copyWith(isScreenSharing: false)
                    : p,
              )
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
    final myId = Provider.of<CallStateProvider?>(context, listen: false)
        ?.currentUserId;
    setState(() {
      if (channelId != null && channelId.isNotEmpty) {
        final updatedChannels = _community.channels.map((c) {
          if (c.id == channelId) {
            return c.copyWith(
              activeVoiceParticipants: c.activeVoiceParticipants
                  .where(
                    (p) =>
                        p.userId != 'local' &&
                        (myId == null || p.userId != myId),
                  )
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
        _selectedChannel =
            _community.channels.where((c) => !c.isAudioRoom).firstOrNull;
      }
    });
    if (widget.autoFetch) {
      _fetchFreshCommunity();
    }
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
    _selectedChannel =
        _community.channels.where((c) => !c.isAudioRoom).firstOrNull;
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

  Future<void> _fetchMembers() async {
    if (!mounted) return;
    setState(() => _loadingMembers = true);
    final fetched = await CommunityService.getMembers(_community.id);
    if (!mounted) return;
    setState(() {
      _loadingMembers = false;
      if (fetched.isNotEmpty) {
        _members = fetched;
      }
    });
  }

  Future<void> _joinCommunity() async {
    if (_joining) return;
    HapticUtils.impact();
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
      _fetchMembers();
      GlassToastService().show(
        context,
        'Вы вступили в сообщество «${_community.name}»',
      );
    } else {
      GlassToastService().showError(context, 'Не удалось вступить в сообщество');
    }
  }

  Future<void> _confirmLeaveCommunity() async {
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Покинуть сообщество?',
      message:
          'Вы действительно хотите выйти из сообщества «${_community.name}»?',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Выйти',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    final ok = await CommunityService.leaveCommunity(_community.id);
    if (!mounted) return;
    if (ok) {
      widget.onCommunityLeft?.call();
      TilingLayoutController.popOrCloseChatTile(context);
    } else {
      GlassToastService().showError(context, 'Не удалось выйти из сообщества');
    }
  }

  Future<void> _copyInviteLink() async {
    final code = await CommunityService.createInviteCode(_community.id);
    if (!mounted) return;
    if (code == null || code.isEmpty) {
      GlassToastService().showError(
        context,
        'Не удалось создать приглашение',
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    GlassToastService().show(context, 'Код приглашения скопирован: $code');
  }

  void _openSettings({int initialTab = 0}) {
    if (!_community.isMember) return;
    CommunitySettingsSheet.show(
      context,
      community: _community,
      initialTab: initialTab,
      onCommunityUpdated: (updated) {
        setState(() {
          _community = updated;
          if (_community.isMember) {
            CommunityService.cacheCommunity(_community);
          }
          _selectInitialChannel();
        });
        if (widget.autoFetch) {
          _fetchMembers();
        }
      },
    );
  }

  void _openMembersModal({bool desktopToggle = false}) {
    if (desktopToggle) {
      setState(() => _showMembersPane = !_showMembersPane);
      if (_showMembersPane && _members.isEmpty && widget.autoFetch) {
        _fetchMembers();
      }
      return;
    }
    if (_members.isEmpty && widget.autoFetch) {
      _fetchMembers();
    }
    showCommunityMembersSheet(
      context,
      community: _community,
      members: _members,
      isLoading: _loadingMembers,
      onRefresh: widget.autoFetch ? _fetchMembers : null,
    );
  }

  void _showCommunityQuickActionsSheet() {
    final palette = context.theav;
    showTheavModalSheet<void>(
      context: context,
      title: _community.name,
      showCloseButton: true,
      padding: EdgeInsets.zero,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  CommunityAvatar(
                    avatarUrl: _community.avatarUrl,
                    name: _community.name,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
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
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                            if (_community.isPublic) ...[
                              const SizedBox(width: 6),
                              iconoir.BadgeCheck(
                                width: 16,
                                height: 16,
                                color: palette.primary,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_community.memberCount} участн. • ${_community.onlineCount} в сети',
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.subtext,
                          ),
                        ),
                        if (_community.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _community.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: palette.subtext,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TheavInsetGroup(
              children: [
                if (_community.isMember)
                  TheavListRow(
                    leading: const iconoir.Link(width: 20, height: 20),
                    title: 'Пригласить участников',
                    subtitle: 'Создать и скопировать код приглашения',
                    showChevron: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _copyInviteLink();
                    },
                  ),
                TheavListRow(
                  leading: const iconoir.Group(width: 20, height: 20),
                  title: 'Участники сообщества',
                  valueText: '${_community.memberCount}',
                  showChevron: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openMembersModal();
                  },
                ),
                if (_community.canManageCommunity)
                  TheavListRow(
                    leading: const iconoir.Settings(width: 20, height: 20),
                    title: 'Управление сообществом',
                    subtitle: 'Каналы, права, роли и саундборд',
                    showChevron: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _openSettings();
                    },
                  ),
                if (_community.isMember && !_community.canManageCommunity)
                  TheavListRow(
                    leading: const iconoir.LogOut(width: 20, height: 20),
                    title: 'Покинуть сообщество',
                    isDestructive: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _confirmLeaveCommunity();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  bool _isChannelReadOnly(CommunityChannel channel) {
    return (channel.isAnnouncement && !_community.canManageChannels) ||
        !_community.canSendMessages;
  }

  String _channelReadOnlyReason(CommunityChannel channel) {
    return channel.isAnnouncement
        ? 'Канал объявлений — публиковать могут только администраторы'
        : 'У вас нет прав на отправку сообщений в этом канале';
  }

  Future<void> _onSelectChannel(
    CommunityChannel channel, {
    required bool isDesktop,
  }) async {
    HapticUtils.selection();
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
        Provider.of<CallStateProvider?>(context, listen: false)?.startOrJoinCall(
          chatId: channel.id,
          chatTitle: '${_community.name} • ${channel.name}',
          callType: channel.isStage ? 'stage' : 'group',
          communityId: _community.id,
          isVideo: false,
        );
      }
      return;
    }

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
            onOpenSettings: () => _openSettings(),
            onOpenMembers: () => _openMembersModal(),
          ),
        ),
      );
    }
  }

  ImageProvider? _resolveAvatarImage(String? rawUrl) {
    return avatarImageProvider(rawUrl, maxDecodeDimension: 96);
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final callProvider = Provider.of<CallStateProvider?>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 680;
        final showRightMembers =
            constraints.maxWidth >= 1060 && _showMembersPane && _community.isMember;

        if (isDesktop) {
          final selected = _selectedChannel;
          return Scaffold(
            backgroundColor: palette.background,
            body: Row(
              children: [
                SizedBox(
                  width: 276,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: style.cardSurface,
                      border: Border(
                        right: BorderSide(
                          color: style.hairlineBorder,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: _buildDesktopSidebar(
                      context,
                      style: style,
                      callProvider: callProvider,
                    ),
                  ),
                ),
                Expanded(
                  child: selected == null
                      ? Center(
                          child: Text(
                            _loadingDetails
                                ? 'Загрузка каналов...'
                                : 'В сообществе пока нет доступных каналов',
                            style: TextStyle(color: palette.subtext),
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
                                  title:
                                      '${_community.name} • ${selected.name}',
                                )
                              : GroupChatScreen(
                                  key: ValueKey('text_${selected.id}'),
                                  chatId: selected.id,
                                  groupName: '# ${selected.name}',
                                  groupAvatar: _community.avatarUrl,
                                  initialIsForum: selected.isForum,
                                  communityName: _community.name,
                                  communityReadOnly:
                                      _isChannelReadOnly(selected),
                                  communityReadOnlyReason:
                                      _channelReadOnlyReason(selected),
                                  onOpenCommunityMembers: () =>
                                      _openMembersModal(
                                    desktopToggle: constraints.maxWidth >= 1060,
                                  ),
                                  onOpenCommunitySettings:
                                      _community.canManageCommunity
                                          ? () => _openSettings()
                                          : null,
                                ),
                ),
                if (showRightMembers)
                  SizedBox(
                    width: 252,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: style.cardSurface,
                        border: Border(
                          left: BorderSide(
                            color: style.hairlineBorder,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        left: false,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
                              child: Row(
                                children: [
                                  iconoir.Group(
                                    width: 17,
                                    height: 17,
                                    color: palette.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Участники',
                                      style: TextStyle(
                                        color: palette.onSurface,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(
                                      () => _showMembersPane = false,
                                    ),
                                    child: iconoir.Xmark(
                                      width: 18,
                                      height: 18,
                                      color: palette.subtext,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: CommunityMembersPane(
                                community: _community,
                                members: _members,
                                isLoading: _loadingMembers,
                                onRefresh:
                                    widget.autoFetch ? _fetchMembers : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        // Compact mobile layout with floating Theaver 3-part header
        return Scaffold(
          backgroundColor: palette.background,
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: _buildChannelTreeList(
                      context,
                      isDesktop: false,
                      topPadding:
                          MediaQuery.paddingOf(context).top + 68.0,
                      callProvider: callProvider,
                    ),
                  ),
                  if (!_community.isMember)
                    _buildCompactJoinBar(context, palette)
                  else if (callProvider != null && callProvider.hasActiveCall)
                    _buildVoiceConnectedDock(context, callProvider, palette),
                ],
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 10,
                right: 10,
                child: _buildCompactFloatingHeader(context, style),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactFloatingHeader(
    BuildContext context,
    TheavSurfaceStyle style,
  ) {
    final palette = style.palette;
    final activeVoice = _community.activeVoiceCount;
    final String subtitle = activeVoice > 0
        ? '$activeVoice в голосе • ${_community.memberCount} участн.'
        : '${_community.memberCount} участн. • ${_community.onlineCount} в сети';

    return Row(
      children: [
        TheavHeaderIconButton(
          icon: const iconoir.NavArrowLeft(width: 21, height: 21),
          tooltip: 'Назад',
          onTap: () => TilingLayoutController.popOrCloseChatTile(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 44,
            child: TheavFloatingSurface(
              borderRadius: 22,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: _showCommunityQuickActionsSheet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        CommunityAvatar(
                          avatarUrl: _community.avatarUrl,
                          name: _community.name,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                                        color: palette.appBarForeground,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                  if (_community.isPublic) ...[
                                    const SizedBox(width: 4),
                                    iconoir.BadgeCheck(
                                      width: 14,
                                      height: 14,
                                      color: palette.primary,
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: activeVoice > 0
                                      ? const Color(0xFF10B981)
                                      : palette.subtext,
                                  fontWeight: activeVoice > 0
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TheavHeaderIconButton(
          icon: const iconoir.Group(width: 19, height: 19),
          tooltip: 'Участники',
          onTap: () => _openMembersModal(),
        ),
        if (_community.isMember) ...[
          const SizedBox(width: 6),
          TheavHeaderIconButton(
            icon: _community.canManageCommunity
                ? const iconoir.Settings(width: 19, height: 19)
                : const iconoir.MoreVert(width: 19, height: 19),
            tooltip: _community.canManageCommunity
                ? 'Настройки сообщества'
                : 'Действия',
            onTap: _community.canManageCommunity
                ? () => _openSettings()
                : _showCommunityQuickActionsSheet,
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopSidebar(
    BuildContext context, {
    required TheavSurfaceStyle style,
    required CallStateProvider? callProvider,
  }) {
    final palette = style.palette;
    return SafeArea(
      right: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TheavHeaderIconButton(
                      size: 36,
                      icon: const iconoir.NavArrowLeft(width: 18, height: 18),
                      tooltip: 'Назад',
                      onTap: () =>
                          TilingLayoutController.popOrCloseChatTile(context),
                    ),
                    const SizedBox(width: 10),
                    CommunityAvatar(
                      avatarUrl: _community.avatarUrl,
                      name: _community.name,
                      size: 38,
                    ),
                    const SizedBox(width: 10),
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: palette.onSurface,
                                  ),
                                ),
                              ),
                              if (_community.isPublic) ...[
                                const SizedBox(width: 4),
                                iconoir.BadgeCheck(
                                  width: 14,
                                  height: 14,
                                  color: palette.primary,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${_community.memberCount} участн. • ${_community.onlineCount} в сети',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: palette.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_community.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _community.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.subtext,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (_community.isMember)
                  Row(
                    children: [
                      Expanded(
                        child: _SidebarActionChip(
                          icon: const iconoir.Link(width: 14, height: 14),
                          label: 'Инвайт',
                          onTap: _copyInviteLink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _SidebarIconChip(
                        icon: const iconoir.Group(width: 15, height: 15),
                        tooltip: 'Участники',
                        onTap: () => _openMembersModal(
                          desktopToggle:
                              MediaQuery.sizeOf(context).width >= 1060,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (_community.canManageCommunity)
                        _SidebarIconChip(
                          icon: const iconoir.Settings(width: 15, height: 15),
                          tooltip: 'Настройки',
                          onTap: () => _openSettings(),
                        )
                      else
                        _SidebarIconChip(
                          icon: const iconoir.LogOut(width: 15, height: 15),
                          tooltip: 'Выйти',
                          onTap: _confirmLeaveCommunity,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: palette.divider),
          Expanded(
            child: _buildChannelTreeList(
              context,
              isDesktop: true,
              topPadding: 6,
              callProvider: callProvider,
            ),
          ),
          if (!_community.isMember)
            _buildCompactJoinBar(context, palette)
          else if (callProvider != null && callProvider.hasActiveCall)
            _buildVoiceConnectedDock(context, callProvider, palette),
        ],
      ),
    );
  }

  Widget _buildChannelTreeList(
    BuildContext context, {
    required bool isDesktop,
    required double topPadding,
    required CallStateProvider? callProvider,
  }) {
    final palette = context.theav;
    final knownCatIds = _community.categories.map((c) => c.id).toSet();
    final uncategorized = _community.channels
        .where(
          (c) =>
              c.categoryId == null ||
              c.categoryId!.isEmpty ||
              !knownCatIds.contains(c.categoryId),
        )
        .toList();

    final groupMargin = isDesktop
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 5);

    if (_community.channels.isEmpty && !_loadingDetails) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24, topPadding + 40, 24, 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconoir.Community(
                width: 40,
                height: 40,
                color: palette.subtext.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'В этом сообществе пока нет открытых каналов',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.subtext, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(0, topPadding, 0, 20),
      children: [
        if (_loadingDetails)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Обновление...',
                  style: TextStyle(fontSize: 12, color: palette.subtext),
                ),
              ],
            ),
          ),
        if (!isDesktop && _community.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              _community.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: palette.subtext),
            ),
          ),
        if (uncategorized.isNotEmpty)
          TheavInsetGroup(
            margin: groupMargin,
            header: 'КАНАЛЫ',
            dividerIndent: 46,
            children: uncategorized
                .map(
                  (ch) => _buildChannelTile(
                    context,
                    ch,
                    isDesktop: isDesktop,
                    palette: palette,
                    callProvider: callProvider,
                  ),
                )
                .toList(),
          ),
        for (final cat in _community.categories) ...[
          _buildCategorySection(
            context,
            cat,
            channels: _community.channels
                .where((c) => c.categoryId == cat.id)
                .toList(),
            isDesktop: isDesktop,
            groupMargin: groupMargin,
            palette: palette,
            callProvider: callProvider,
          ),
        ],
      ],
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    CommunityCategory cat, {
    required List<CommunityChannel> channels,
    required bool isDesktop,
    required EdgeInsetsGeometry groupMargin,
    required TheavPalette palette,
    required CallStateProvider? callProvider,
  }) {
    final collapsed = _collapsedCategoryIds.contains(cat.id);
    final collapsedUnread = collapsed
        ? channels.fold<int>(0, (s, c) => s + c.unreadCount)
        : 0;
    final horizontalPad = isDesktop ? 14.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticUtils.selection();
            setState(() {
              if (collapsed) {
                _collapsedCategoryIds.remove(cat.id);
              } else {
                _collapsedCategoryIds.add(cat.id);
              }
            });
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPad,
              10,
              horizontalPad,
              4,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: iconoir.NavArrowDown(
                    width: 14,
                    height: 14,
                    color: palette.subtext,
                  ),
                ),
                const SizedBox(width: 6),
                if (cat.isPrivate) ...[
                  iconoir.Lock(width: 12, height: 12, color: palette.subtext),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    cat.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.45,
                      color: palette.primary,
                    ),
                  ),
                ),
                if (collapsedUnread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.unreadBadge,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$collapsedUnread',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: palette.unreadBadgeText,
                      ),
                    ),
                  ),
                if (_community.canManageChannels) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openSettings(initialTab: 1),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: iconoir.Plus(
                        width: 15,
                        height: 15,
                        color: palette.subtext,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!collapsed && channels.isNotEmpty)
          TheavInsetGroup(
            margin: groupMargin,
            dividerIndent: 46,
            children: channels
                .map(
                  (ch) => _buildChannelTile(
                    context,
                    ch,
                    isDesktop: isDesktop,
                    palette: palette,
                    callProvider: callProvider,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildChannelTile(
    BuildContext context,
    CommunityChannel ch, {
    required bool isDesktop,
    required TheavPalette palette,
    required CallStateProvider? callProvider,
  }) {
    final isSelected = isDesktop && _selectedChannel?.id == ch.id;
    final isThisVoiceActive = callProvider?.activeCall?.chatId == ch.id;
    final liveParticipants = isThisVoiceActive
        ? (callProvider?.activeCall?.participants ?? ch.activeVoiceParticipants)
        : ch.activeVoiceParticipants;

    Widget? trailing;
    if (ch.isAudioRoom && isThisVoiceActive) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'В эфире',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF10B981),
          ),
        ),
      );
    } else if (ch.unreadCount > 0) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: palette.unreadBadge,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          ch.unreadCount > 99 ? '99+' : '${ch.unreadCount}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: palette.unreadBadgeText,
          ),
        ),
      );
    } else if (ch.isAudioRoom && ch.voiceUserLimit > 0) {
      trailing = Text(
        '${liveParticipants.length}/${ch.voiceUserLimit}',
        style: TextStyle(
          fontSize: 12,
          color: palette.subtext,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: isSelected
              ? palette.primary.withValues(alpha: 0.11)
              : Colors.transparent,
          child: TheavListRow(
            minHeight: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            leading: CommunityChannelIcon(
              channelType: ch.channelType,
              size: 19,
              isSelected: isSelected,
            ),
            titleWidget: Text(
              ch.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: isSelected || ch.unreadCount > 0
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: isSelected ? palette.primary : palette.onSurface,
              ),
            ),
            subtitle: isDesktop && ch.topic.isNotEmpty ? ch.topic : null,
            trailing: trailing,
            onTap: () => _onSelectChannel(ch, isDesktop: isDesktop),
          ),
        ),
        if (ch.isAudioRoom && liveParticipants.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 14, 8),
            child: Column(
              children: liveParticipants.map((part) {
                final member = _members
                    .where((m) => m.userId == part.userId)
                    .firstOrNull;
                final isBot = member?.isBot ?? false;
                final partName = ContactsService.resolvePeerName(
                  part.userId,
                  part.displayName,
                  isBot: isBot,
                );
                final partAvatarUrl = ContactsService.resolvePeerAvatarUrl(
                  part.userId,
                  part.avatarUrl,
                  isBot: isBot,
                );
                final partAvatar = _resolveAvatarImage(partAvatarUrl);
                final isStreaming = part.isScreenSharing ||
                    (isThisVoiceActive &&
                        (callProvider?.activeCall?.streams
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
                          color: palette.primary.withValues(alpha: 0.22),
                          image: partAvatar != null
                              ? DecorationImage(
                                  image: partAvatar,
                                  fit: BoxFit.cover,
                                  onError: (_, __) {},
                                )
                              : null,
                          border: Border.all(
                            color: part.isSpeaking
                                ? const Color(0xFF10B981)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: partAvatar == null
                            ? Text(
                                partName.isNotEmpty
                                    ? partName.characters.first.toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: palette.onSurface,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          partName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: palette.subtext,
                          ),
                        ),
                      ),
                      if (part.isMuted) ...[
                        iconoir.Microphone(
                          width: 13,
                          height: 13,
                          color: palette.error,
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (part.isVideoOn && !isStreaming) ...[
                        iconoir.VideoCamera(
                          width: 13,
                          height: 13,
                          color: palette.primary,
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
                            color: palette.error,
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
    );
  }

  Widget _buildCompactJoinBar(BuildContext context, TheavPalette palette) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: SizedBox(
          width: double.infinity,
          child: TheavFloatingPillButton(
            label: _joining
                ? 'Вступление...'
                : 'Вступить в «${_community.name}»',
            icon: _joining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const iconoir.UserPlus(width: 18, height: 18),
            isPrimary: true,
            enabled: !_joining,
            onTap: _joinCommunity,
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceConnectedDock(
    BuildContext context,
    CallStateProvider callProvider,
    TheavPalette palette,
  ) {
    final call = callProvider.activeCall;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: SizedBox(
          height: 54,
          width: double.infinity,
          child: TheavFloatingSurface(
            borderRadius: 18,
            colorOverride: const Color(0xFF10B981).withValues(alpha: 0.14),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const iconoir.SoundHigh(
                  width: 19,
                  height: 19,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 10),
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
                          color: Color(0xFF10B981),
                        ),
                      ),
                      Text(
                        call?.title ?? _community.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.subtext,
                        ),
                      ),
                    ],
                  ),
                ),
                if (callProvider.isScreenSharing)
                  _DockIconBtn(
                    icon: iconoir.XmarkCircle(
                      width: 18,
                      height: 18,
                      color: palette.error,
                    ),
                    onTap: () => callProvider.stopScreenShare(),
                  ),
                _DockIconBtn(
                  icon: iconoir.Microphone(
                    width: 18,
                    height: 18,
                    color: callProvider.isMuted
                        ? palette.error
                        : palette.onSurface,
                  ),
                  onTap: () => callProvider.toggleMute(),
                ),
                _DockIconBtn(
                  icon: iconoir.Phone(
                    width: 18,
                    height: 18,
                    color: palette.error,
                  ),
                  onTap: () async {
                    final leftChatId = call?.chatId;
                    await callProvider.leaveCall();
                    _onLocalVoiceLeft(leftChatId);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarActionChip extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Material(
      color: palette.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () {
          HapticUtils.tap();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: palette.primary, size: 14),
                child: icon,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarIconChip extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SidebarIconChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            HapticUtils.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(7.5),
            child: IconTheme(
              data: IconThemeData(color: palette.onSurface, size: 15),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _DockIconBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;

  const _DockIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: icon,
      ),
    );
  }
}

/// Mobile wrapper around [GroupChatScreen] providing a Telegram-styled left
/// swipeable drawer for seamless Community channel switching, plus menu hooks
/// into Community Channels, Members, and Settings.
class _MobileCommunityChatWrapper extends StatefulWidget {
  final Community community;
  final CommunityChannel initialChannel;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMembers;

  const _MobileCommunityChatWrapper({
    required this.community,
    required this.initialChannel,
    required this.onOpenSettings,
    required this.onOpenMembers,
  });

  @override
  State<_MobileCommunityChatWrapper> createState() =>
      _MobileCommunityChatWrapperState();
}

class _MobileCommunityChatWrapperState
    extends State<_MobileCommunityChatWrapper> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late CommunityChannel _activeChannel;

  @override
  void initState() {
    super.initState();
    _activeChannel = widget.initialChannel;
  }

  Widget _buildDrawerChannelTile(
    BuildContext context,
    CommunityChannel ch,
    TheavPalette palette,
  ) {
    final selected = ch.id == _activeChannel.id;
    final voiceCount = ch.activeVoiceParticipants.length;

    Widget? trailing;
    if (ch.isAudioRoom && voiceCount > 0) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          '$voiceCount',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF10B981),
          ),
        ),
      );
    } else if (ch.unreadCount > 0 && !selected) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: palette.unreadBadge,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          '${ch.unreadCount}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: palette.unreadBadgeText,
          ),
        ),
      );
    }

    return Container(
      color: selected
          ? palette.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: TheavListRow(
        minHeight: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: CommunityChannelIcon(
          channelType: ch.channelType,
          size: 18,
          isSelected: selected,
        ),
        titleWidget: Text(
          ch.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? palette.primary : palette.onSurface,
          ),
        ),
        trailing: trailing,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final knownCatIds = widget.community.categories.map((c) => c.id).toSet();
    final uncategorized = widget.community.channels
        .where(
          (c) =>
              c.categoryId == null ||
              c.categoryId!.isEmpty ||
              !knownCatIds.contains(c.categoryId),
        )
        .toList();

    final isReadOnly = (_activeChannel.isAnnouncement &&
            !widget.community.canManageChannels) ||
        !widget.community.canSendMessages;
    final readOnlyReason = _activeChannel.isAnnouncement
        ? 'Канал объявлений — только для чтения'
        : 'У вас нет прав на отправку сообщений в этом канале';

    return Scaffold(
      key: _scaffoldKey,
      drawerEdgeDragWidth: 44,
      drawer: Drawer(
        backgroundColor: palette.background,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                child: Row(
                  children: [
                    CommunityAvatar(
                      avatarUrl: widget.community.avatarUrl,
                      name: widget.community.name,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.community.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: palette.onSurface,
                            ),
                          ),
                          Text(
                            '${widget.community.memberCount} участн.',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.community.canManageCommunity)
                      _SidebarIconChip(
                        icon: const iconoir.Settings(width: 17, height: 17),
                        tooltip: 'Настройки',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onOpenSettings();
                        },
                      ),
                  ],
                ),
              ),
              Divider(color: palette.divider, height: 0.5, thickness: 0.5),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 16),
                  children: [
                    if (uncategorized.isNotEmpty)
                      TheavInsetGroup(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        header: 'КАНАЛЫ',
                        dividerIndent: 42,
                        children: uncategorized
                            .map((ch) =>
                                _buildDrawerChannelTile(context, ch, palette))
                            .toList(),
                      ),
                    for (final cat in widget.community.categories) ...[
                      Builder(
                        builder: (context) {
                          final catChannels = widget.community.channels
                              .where((c) => c.categoryId == cat.id)
                              .toList();
                          if (catChannels.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return TheavInsetGroup(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            header: cat.name.toUpperCase(),
                            dividerIndent: 42,
                            children: catChannels
                                .map((ch) => _buildDrawerChannelTile(
                                    context, ch, palette))
                                .toList(),
                          );
                        },
                      ),
                    ],
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
          : GroupChatScreen(
              key: ValueKey('mobile_comm_${_activeChannel.id}'),
              chatId: _activeChannel.id,
              groupName: '# ${_activeChannel.name}',
              groupAvatar: widget.community.avatarUrl,
              initialIsForum: _activeChannel.isForum,
              communityName: widget.community.name,
              communityReadOnly: isReadOnly,
              communityReadOnlyReason: readOnlyReason,
              onOpenCommunityChannels: () =>
                  _scaffoldKey.currentState?.openDrawer(),
              onOpenCommunityMembers: widget.onOpenMembers,
              onOpenCommunitySettings: widget.community.canManageCommunity
                  ? widget.onOpenSettings
                  : null,
            ),
    );
  }
}
