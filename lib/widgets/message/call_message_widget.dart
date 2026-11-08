import 'dart:convert';
import 'package:flutter/material.dart';
import '../../screens/call/group_call_screen.dart';
import '../../services/chat_service.dart';

class CallMessageWidget extends StatelessWidget {
  final Message message;
  final bool isMine;

  const CallMessageWidget({
    super.key,
    required this.message,
    required this.isMine,
  });

  Map<String, dynamic> _parsePayload() {
    if (message.mediaPayload != null &&
        (message.mediaPayload!.containsKey('call_id') ||
            message.mediaPayload!.containsKey('status'))) {
      return message.mediaPayload!;
    }
    final raw = message.content.trim();
    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return const {};
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours ч ${mins.toString().padLeft(2, '0')} мин';
    }
    if (mins > 0) {
      return '$mins мин ${secs.toString().padLeft(2, '0')} сек';
    }
    return '$secs сек';
  }

  @override
  Widget build(BuildContext context) {
    final data = _parsePayload();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final reason = (data['end_reason'] ?? '').toString().toLowerCase();
    final isVideo =
        data['video_enabled'] == true ||
        data['is_video'] == true ||
        (data['call_type'] ?? '').toString().toLowerCase() == 'video';
    final durationSec = (data['duration_seconds'] as num?)?.toInt() ??
        int.tryParse((data['duration_seconds'] ?? '0').toString()) ??
        0;

    final bool isDeclined = status == 'declined' || reason == 'declined';
    final bool isCanceled = status == 'canceled' || reason == 'canceled';
    final bool isMissed =
        status == 'missed' ||
        reason == 'missed' ||
        reason == 'timeout' ||
        reason == 'unanswered' ||
        (!isMine && (isDeclined || isCanceled || durationSec <= 0));
    final bool isFailedOrUnanswered =
        isDeclined || isCanceled || isMissed || durationSec <= 0;

    final String title;
    if (isMissed && !isMine) {
      title = isVideo ? 'Пропущенный видеозвонок' : 'Пропущенный звонок';
    } else if (isDeclined) {
      title = isVideo ? 'Отклонённый видеозвонок' : 'Отклонённый звонок';
    } else if (isCanceled || durationSec <= 0) {
      title = isMine
          ? (isVideo ? 'Отменённый видеозвонок' : 'Отменённый звонок')
          : (isVideo ? 'Пропущенный видеозвонок' : 'Пропущенный звонок');
    } else {
      title = isMine
          ? (isVideo ? 'Исходящий видеозвонок' : 'Исходящий звонок')
          : (isVideo ? 'Входящий видеозвонок' : 'Входящий звонок');
    }

    final String subtitle = durationSec > 0
        ? _formatDuration(durationSec)
        : (isMine ? 'Без ответа' : 'Нажмите, чтобы перезвонить');

    final Color accentColor = isFailedOrUnanswered
        ? const Color(0xFFFF6B6B)
        : const Color(0xFF2ECC71);

    final Color textColor = isMine
        ? Colors.white
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF1F2430));
    final Color subTextColor = isMine
        ? Colors.white.withValues(alpha: 0.78)
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.white70
            : const Color(0xFF687082));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _handleCallback(context, isVideo: isVideo),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.18)
                      : accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                  color: isMine ? Colors.white : accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMine
                              ? Icons.call_made_rounded
                              : (isFailedOrUnanswered
                                  ? Icons.call_missed_rounded
                                  : Icons.call_received_rounded),
                          size: 14,
                          color: isFailedOrUnanswered
                              ? (isMine
                                  ? const Color(0xFFFFB8B8)
                                  : const Color(0xFFFF5252))
                              : (isMine ? Colors.white70 : accentColor),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: subTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.2)
                      : const Color(0xFF5B7FFF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Перезвонить',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isMine ? Colors.white : const Color(0xFF5B7FFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleCallback(BuildContext context, {required bool isVideo}) {
    if (message.chatId.isEmpty) return;
    final data = _parsePayload();
    final callTypeRaw = (data['call_type'] ?? '').toString().toLowerCase();
    final isGroupCall = callTypeRaw == 'group' || callTypeRaw == 'stage';
    final title = message.senderName.isNotEmpty ? message.senderName : 'Звонок';
    final nav = Navigator.maybeOf(context);
    if (nav == null) return;

    if (isGroupCall) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: message.chatId,
            chatId: message.chatId,
            userId: 'local',
            title: title,
            isStage: callTypeRaw == 'stage',
          ),
        ),
      );
      return;
    }

    nav.pushNamed(
      isVideo ? '/video-call' : '/voice-call',
      arguments: {
        'chatId': message.chatId,
        'peerName': title,
        'avatarUrl': message.senderAvatarUrl,
      },
    );
  }
}
