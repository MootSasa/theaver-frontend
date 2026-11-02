import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../models/call_models.dart';
import '../../models/theav_theme.dart';
import '../../services/call_state_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/call/call_fullscreen_video_modal.dart';
import '../../widgets/call/stream_quality_sheet.dart';

/// Group Voice/Video Call, Go Live Screen Share Stage, and Community Stage Room Screen.
///
/// Can be pushed full-screen or embedded (`embedded: true`) inside the right pane of
/// `CommunityScreen` on desktop.
class GroupCallScreen extends StatefulWidget {
  final String callId;
  final String userId;
  final String? chatId;
  final String? title;
  final bool isStage;
  final bool embedded;

  const GroupCallScreen({
    super.key,
    required this.callId,
    required this.userId,
    this.chatId,
    this.title,
    this.isStage = false,
    this.embedded = false,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  static const List<String> _quickReactions = ['👍', '❤️', '🔥', '🎉', '👏', '😂'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CallStateProvider>();
      if (!widget.embedded) {
        provider.setMinimized(false);
      }
      final targetChatId = widget.chatId ?? widget.callId;
      if (!provider.hasActiveCall ||
          provider.activeCall?.chatId != targetChatId) {
        provider.startOrJoinCall(
          chatId: targetChatId,
          chatTitle:
              widget.title ?? (widget.isStage ? 'Трибуна' : 'Голосовой чат'),
          callType: widget.isStage ? 'stage' : 'group',
          isVideo: false,
        );
      }
    });
  }

  Future<void> _onTapGoLive(CallStateProvider provider) async {
    if (provider.isScreenSharing) {
      final updated = await StreamQualitySheet.show(
        context,
        initialConfig: provider.streamConfig,
        isUpdatingActiveStream: true,
      );
      if (updated != null) {
        await provider.updateScreenShareQuality(updated);
      }
      return;
    }
    final config = await StreamQualitySheet.show(
      context,
      initialConfig: provider.streamConfig,
    );
    if (config != null) {
      await provider.startScreenShare(config);
    }
  }

  void _showParticipantOptions(
    BuildContext context,
    CallStateProvider provider,
    CallParticipant participant,
  ) {
    final p = context.theav;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int vol = participant.volume;
        return StatefulBuilder(
          builder: (ctx, setModalState) => Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            decoration: BoxDecoration(
              color: const Color(0xFF161A24),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: p.borderSubtle, width: 0.8),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                      child: Text(
                        participant.displayName.isNotEmpty
                            ? participant.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            participant.displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Роль: ${participant.role}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Индивидуальная громкость',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      '$vol%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: vol.toDouble(),
                  min: 0,
                  max: 200,
                  divisions: 40,
                  onChanged: (v) {
                    setModalState(() => vol = v.round());
                    provider.setParticipantVolume(participant.userId, vol);
                  },
                ),
                if (widget.isStage && participant.isHandRaised)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.record_voice_over_rounded,
                      color: Color(0xFF00E676),
                    ),
                    title: const Text(
                      'Пригласить на трибуну (Спикер)',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      provider.moderateParticipant(
                        participant.userId,
                        'promote_speaker',
                      );
                      Navigator.of(ctx).pop();
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.mic_off_rounded,
                    color: Colors.orangeAccent,
                  ),
                  title: const Text(
                    'Отключить микрофон на сервере',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    provider.moderateParticipant(participant.userId, 'mute');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.person_remove_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Отключить от голосового канала',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    provider.moderateParticipant(participant.userId, 'kick');
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReactionsSheet(BuildContext context, CallStateProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Color(0xFF161A24),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Отправить реакцию или звук (Soundboard)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _quickReactions.map((emoji) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    provider.sendReaction(emoji);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallStateProvider>();
    final glassProvider = context.watch<LiquidGlassProvider>();
    final useGlass = glassProvider.enabled;
    final isFullGlass = glassProvider.isFull;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final call = callProvider.activeCall;
    final participants = call?.participants ?? const <CallParticipant>[];
    final stream = callProvider.focusedStream;
    final title =
        widget.title ?? call?.title ?? (widget.isStage ? 'Трибуна' : 'Голосовой канал');

    final content = Stack(
      children: [
        Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.embedded ? 12 : MediaQuery.of(context).padding.top + 8,
                16,
                10,
              ),
              child: Row(
                children: [
                  if (!widget.embedded)
                    IconButton(
                      onPressed: () {
                        callProvider.setMinimized(true);
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: 'Свернуть',
                    ),
                  Icon(
                    widget.isStage
                        ? Icons.podcasts_rounded
                        : Icons.volume_up_rounded,
                    color: const Color(0xFF00E676),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${participants.length} участн. • ${callProvider.formattedDuration}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Server Recording Button
                  GestureDetector(
                    onTap: () => callProvider.toggleRecording(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: callProvider.isRecording
                            ? Colors.redAccent.withValues(alpha: 0.24)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: callProvider.isRecording
                              ? Colors.redAccent
                              : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: callProvider.isRecording
                                  ? Colors.redAccent
                                  : Colors.white54,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            callProvider.isRecording ? 'REC' : 'Запись',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Active High-FPS Go Live Stage (if a stream is active)
            if (stream != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: GestureDetector(
                  onTap: () {
                    CallFullscreenVideoModal.show(
                      context,
                      title: 'Трансляция ${stream.streamerName}',
                      subtitle:
                          '${stream.resolutionWidth}×${stream.resolutionHeight} @ ${stream.fps} FPS • ${stream.codec}',
                      isScreenShare: true,
                      fallbackRenderer: callProvider.screenShareRenderer,
                    );
                  },
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    padding: const EdgeInsets.all(1.2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090B10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18.6),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (callProvider.hasScreenShareStream)
                            RTCVideoView(
                              callProvider.screenShareRenderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitContain,
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.screen_share_rounded,
                                    size: 42,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Трансляция ${stream.streamerName}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${stream.resolutionWidth}×${stream.resolutionHeight} @ ${stream.fps} FPS • ${stream.codec} • ${(stream.bitrateKbps / 1000).toStringAsFixed(1)} Mbps',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Positioned(
                            left: 12,
                            top: 10,
                            right: 12,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${stream.qualityBadge} • ${stream.codec}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFFFAB40),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () async {
                                    final q =
                                        await ViewerQualitySelectorSheet.show(
                                      context,
                                      currentQuality:
                                          callProvider.viewerQuality,
                                      stream: stream,
                                    );
                                    if (q != null) {
                                      callProvider.setViewerQuality(q);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white24,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.hd_rounded,
                                          size: 15,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          callProvider.viewerQuality.label,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full_rounded,
                                    size: 15,
                                    color: Colors.white,
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

            // Participants Grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  final participant = participants[index];
                  final isSelf =
                      participant.userId == callProvider.currentUserId ||
                      participant.userId == 'local';
                  final videoRenderer =
                      callProvider.rendererForParticipant(participant.userId);
                  final showVideo =
                      participant.isVideoOn && videoRenderer != null;
                  final canOpenScreenShare = participant.isScreenSharing &&
                      callProvider.hasScreenShareStream;
                  final resolvedAvatar =
                      AppConfig.resolveMediaUrl(participant.avatarUrl) ?? '';
                  final isSpeaking =
                      participant.isSpeaking ||
                      (!participant.isMuted && index == 0);
                  return GestureDetector(
                    onTap: () {
                      if (showVideo) {
                        CallFullscreenVideoModal.show(
                          context,
                          title: participant.displayName,
                          subtitle: callProvider.formattedDuration,
                          participantUserId: participant.userId,
                          mirror: isSelf,
                          fallbackRenderer: videoRenderer,
                        );
                      } else if (canOpenScreenShare) {
                        CallFullscreenVideoModal.show(
                          context,
                          title: 'Трансляция ${participant.displayName}',
                          isScreenShare: true,
                          fallbackRenderer: callProvider.screenShareRenderer,
                        );
                      } else {
                        _showParticipantOptions(
                          context,
                          callProvider,
                          participant,
                        );
                      }
                    },
                    onLongPress: () => _showParticipantOptions(
                      context,
                      callProvider,
                      participant,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: EdgeInsets.all(isSpeaking ? 2.0 : 1.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171C28),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSpeaking
                              ? const Color(0xFF00E676)
                              : Colors.white.withValues(alpha: 0.08),
                          width: isSpeaking ? 2.0 : 1.0,
                        ),
                        boxShadow: isSpeaking
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.22),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(isSpeaking ? 18.0 : 18.8),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (showVideo) ...[
                              RTCVideoView(
                                videoRenderer,
                                mirror: isSelf,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                              Positioned(
                                left: 8,
                                top: 8,
                                right: 8,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.55),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.open_in_full_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _showParticipantOptions(
                                        context,
                                        callProvider,
                                        participant,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.more_horiz_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    18,
                                    10,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.72),
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    participant.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 30,
                                      backgroundColor:
                                          primaryColor.withValues(alpha: 0.26),
                                      backgroundImage:
                                          resolvedAvatar.isNotEmpty
                                              ? NetworkImage(resolvedAvatar)
                                              : null,
                                      child: resolvedAvatar.isEmpty
                                          ? Text(
                                              participant.displayName.isNotEmpty
                                                  ? participant.displayName[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        participant.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Status badges (Muted / Deafened / Hand Raised / Screen Share)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (participant.isHandRaised)
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFFAB00),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.front_hand_rounded,
                                        size: 12,
                                        color: Colors.black,
                                      ),
                                    ),
                                  if (participant.isScreenSharing)
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'LIVE',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (participant.isMuted)
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent
                                            .withValues(alpha: 0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.mic_off_rounded,
                                        size: 13,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // Floating Emoji Reactions
        if (callProvider.reactions.isNotEmpty)
          Positioned(
            right: 24,
            bottom: 104,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: callProvider.reactions.map((r) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      r.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        // Bottom Control Dock (LiquidGlassLens or Material Matte)
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + (widget.embedded ? 0 : MediaQuery.of(context).padding.bottom),
          child: SizedBox(
            height: 70,
            width: double.infinity,
            child: useGlass
                ? LiquidGlassLens(
                    style: glassProvider.createStyle(
                      context: context,
                      cornerRadius: 35,
                      color: Colors.white.withValues(alpha: 0.08),
                      refractionIndex: isFullGlass ? 1.12 : 1.05,
                      refractionWidth: 24.0,
                    ),
                    child: _buildDockRow(context, callProvider, primaryColor),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    child: BackdropFilter.grouped(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFF181D2A).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(35),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                        child: _buildDockRow(
                          context,
                          callProvider,
                          primaryColor,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Container(
        color: const Color(0xFF0E121B),
        child: content,
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && callProvider.hasActiveCall) {
          callProvider.setMinimized(true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E121B),
        body: content,
      ),
    );
  }

  Widget _buildDockRow(
    BuildContext context,
    CallStateProvider callProvider,
    Color primaryColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildDockItem(
          icon: callProvider.isMuted
              ? Icons.mic_off_rounded
              : Icons.mic_rounded,
          label: callProvider.isMuted ? 'Вкл. микр.' : 'Микрофон',
          danger: callProvider.isMuted,
          active: !callProvider.isMuted,
          onTap: () => callProvider.toggleMute(),
        ),
        _buildDockItem(
          icon: callProvider.isDeafened
              ? Icons.headset_off_rounded
              : Icons.headset_rounded,
          label: 'Звук',
          danger: callProvider.isDeafened,
          active: !callProvider.isDeafened,
          onTap: () => callProvider.toggleDeafen(),
        ),
        _buildDockItem(
          icon: callProvider.isVideoOn
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: 'Видео',
          active: callProvider.isVideoOn,
          accentColor: primaryColor,
          onTap: () => callProvider.toggleVideo(),
        ),
        _buildDockItem(
          icon: callProvider.isScreenSharing
              ? Icons.tune_rounded
              : Icons.screen_share_rounded,
          label: callProvider.isScreenSharing
              ? callProvider.streamConfig.badgeLabel
              : 'Go Live',
          active: callProvider.isScreenSharing,
          accentColor: primaryColor,
          onTap: () => _onTapGoLive(callProvider),
        ),
        if (widget.isStage)
          _buildDockItem(
            icon: Icons.front_hand_rounded,
            label: 'Рука',
            active: callProvider.isHandRaised,
            accentColor: const Color(0xFFFFAB00),
            onTap: () => callProvider.toggleHandRaise(),
          )
        else
          _buildDockItem(
            icon: Icons.emoji_emotions_outlined,
            label: 'Реакции',
            onTap: () => _showReactionsSheet(context, callProvider),
          ),
        GestureDetector(
          onTap: () async {
            HapticFeedback.mediumImpact();
            await callProvider.leaveCall();
            if (!widget.embedded && context.mounted) {
              Navigator.of(context).maybePop();
            }
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDockItem({
    required IconData icon,
    required String label,
    bool active = false,
    bool danger = false,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    final bg = danger
        ? Colors.redAccent.withValues(alpha: 0.22)
        : (active
            ? (accentColor ?? Colors.white).withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.08));
    final fg = danger ? Colors.redAccent : Colors.white;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}