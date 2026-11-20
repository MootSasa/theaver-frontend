import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../models/call_models.dart';
import '../../models/theav_theme.dart';
import '../../services/call_state_provider.dart';
import '../../services/chat_service.dart';
import '../../services/power_saving_provider.dart';
import '../../services/websocket_service.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../screens/call/group_call_screen.dart';
import '../design_system/theav_design_system.dart';
import 'telegram_avatar_stack.dart';

CallStateProvider? _maybeCallProvider(
  BuildContext context, {
  bool listen = true,
}) {
  try {
    return Provider.of<CallStateProvider>(context, listen: listen);
  } catch (_) {
    return null;
  }
}

/// Floating Liquid Glass / Matte banner shown right below `FloatingGlassAppBar`
/// when a group voice chat or channel livestream is currently active.
class LiveChatCallBanner extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String currentUserId;
  final bool isChannel;
  final VoidCallback? onJoined;

  const LiveChatCallBanner({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.currentUserId,
    this.isChannel = false,
    this.onJoined,
  });

  @override
  State<LiveChatCallBanner> createState() => _LiveChatCallBannerState();
}

class _LiveChatCallBannerState extends State<LiveChatCallBanner>
    with SingleTickerProviderStateMixin {
  static const double _kCornerRadius = 22.0;

  late final AnimationController _pulseController;
  StreamSubscription<ChatRealtimeUpdate>? _realtimeSub;
  StreamSubscription<WebSocketEvent>? _wsSub;

  String? _activeCallId;
  int _participantCount = 0;
  List<Map<String, dynamic>> _speakers = const [];
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _subscribeStreams();
    _fetchActiveCall();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulseAnimation();
  }

  @override
  void didUpdateWidget(covariant LiveChatCallBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _activeCallId = null;
      _participantCount = 0;
      _speakers = const [];
      _fetchActiveCall();
    }
    _syncPulseAnimation();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _wsSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _syncPulseAnimation() {
    final disableAnimations = MediaQuery.disableAnimationsOf(context) ||
        !PowerSavingProvider.instance.allowAnimations;
    final hasCall = _hasEffectiveActiveCall(
      _maybeCallProvider(context, listen: false)?.activeCall,
    );
    if (disableAnimations || !hasCall) {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
      _pulseController.value = 1.0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _subscribeStreams() {
    _realtimeSub = ChatService.realtimeUpdates.listen((update) {
      if (!mounted || update.chatId != widget.chatId) return;
      if (update.type == WebSocketEventType.chatSettingsUpdated) {
        if (update.data.containsKey('has_active_call')) {
          final hasCall = update.data['has_active_call'] == true ||
              update.data['has_active_call'] == 1 ||
              update.data['has_active_call'] == 'true';
          if (hasCall) {
            final cid = update.data['active_call_id']?.toString().trim();
            if (cid != null && cid.isNotEmpty) {
              setState(() => _activeCallId = cid);
            }
            _fetchActiveCall();
          } else {
            _clearRemoteCall();
          }
        }
      }
    });

    _wsSub = WebSocketService().eventStream.listen((event) {
      if (!mounted) return;
      final rawType = event.rawType.isNotEmpty
          ? event.rawType
          : (event.data['__raw_type'] ?? event.data['type'] ?? '').toString();
      final normalized = rawType.replaceAll('.', '_');
      if (!normalized.startsWith('call_')) return;

      final callMap = event.data['call'] is Map
          ? Map<String, dynamic>.from(event.data['call'] as Map)
          : null;
      final eventChatId = (event.data['chat_id'] ?? callMap?['chat_id'] ?? '')
          .toString()
          .trim();
      if (eventChatId != widget.chatId) return;

      if (normalized == 'call_started') {
        if (callMap != null) {
          _applyCallDtoMap(callMap);
        } else {
          final cid =
              (event.data['active_call_id'] ?? event.data['call_id'] ?? '')
                  .toString()
                  .trim();
          if (cid.isNotEmpty) {
            setState(() => _activeCallId = cid);
            _syncPulseAnimation();
          }
          _fetchActiveCall();
        }
      } else if (normalized == 'call_ended') {
        final reason = (event.data['reason'] ?? '').toString().trim();
        final status = (callMap?['status'] ?? event.data['status'] ?? '')
            .toString()
            .trim();
        if (reason.isNotEmpty || status == 'ended' || callMap == null) {
          _clearRemoteCall();
        } else {
          _fetchActiveCall();
        }
      } else if (normalized == 'call_participant_joined' ||
          normalized == 'call_participant_left' ||
          normalized == 'call_participant_updated' ||
          normalized == 'call_participant_kicked') {
        if (callMap != null) {
          _applyCallDtoMap(callMap);
        } else {
          _fetchActiveCall();
        }
      }
    });
  }

  Future<void> _fetchActiveCall() async {
    if (_isFetching || widget.chatId.isEmpty) return;
    _isFetching = true;
    try {
      final callMap = await ChatService.getChatActiveCall(widget.chatId);
      if (!mounted) return;
      if (callMap == null) {
        _clearRemoteCall();
      } else {
        _applyCallDtoMap(callMap);
      }
    } catch (_) {
      // Non-fatal in offline/test environments.
    } finally {
      _isFetching = false;
    }
  }

  void _clearRemoteCall() {
    if (!mounted) return;
    setState(() {
      _activeCallId = null;
      _participantCount = 0;
      _speakers = const [];
    });
    _syncPulseAnimation();
  }

  void _applyCallDtoMap(Map<String, dynamic> callMap) {
    final status = (callMap['status'] ?? 'active').toString().toLowerCase();
    final callId = (callMap['id'] ?? callMap['call_id'] ?? '').toString().trim();
    if (callId.isEmpty || status == 'ended') {
      _clearRemoteCall();
      return;
    }

    final rawParticipants = callMap['participants'];
    final speakers = <Map<String, dynamic>>[];
    int activeCount = 0;

    if (rawParticipants is List) {
      final activeRows = <Map<String, dynamic>>[];
      for (final item in rawParticipants) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final state = (map['state'] ?? 'connected').toString().toLowerCase();
        if (state == 'left' || state == 'ended') continue;
        activeCount++;
        activeRows.add(map);
      }

      // Prioritize active speakers / non-listeners, then fill up to 3 avatars.
      activeRows.sort((a, b) {
        final aSpeaking = a['is_speaking'] == true ? 1 : 0;
        final bSpeaking = b['is_speaking'] == true ? 1 : 0;
        if (aSpeaking != bSpeaking) return bSpeaking.compareTo(aSpeaking);
        final aRole = (a['stage_role'] ?? a['role'] ?? 'speaker').toString();
        final bRole = (b['stage_role'] ?? b['role'] ?? 'speaker').toString();
        final aSpeakerRank = aRole == 'listener' ? 0 : 1;
        final bSpeakerRank = bRole == 'listener' ? 0 : 1;
        return bSpeakerRank.compareTo(aSpeakerRank);
      });

      for (final row in activeRows.take(3)) {
        speakers.add({
          'user_id': row['user_id'] ?? row['id'],
          'display_name': row['display_name'] ?? row['name'] ?? row['username'],
          'username': row['username'],
          'avatar_url': row['avatar_url'],
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _activeCallId = callId;
      _participantCount = activeCount;
      _speakers = speakers;
    });
    _syncPulseAnimation();
  }

  bool _hasEffectiveActiveCall(CallSession? providerCall) {
    if (_activeCallId != null && _activeCallId!.isNotEmpty) return true;
    return providerCall != null &&
        providerCall.chatId == widget.chatId &&
        providerCall.status != 'ended';
  }

  String _formatParticipantCount(int count) {
    if (count <= 0) {
      return widget.isChannel ? 'Эфир идёт сейчас' : 'Чат идёт сейчас';
    }
    final mod100 = count % 100;
    final mod10 = count % 10;
    final String noun;
    if (mod100 >= 11 && mod100 <= 19) {
      noun = widget.isChannel ? 'слушателей' : 'участников';
    } else if (mod10 == 1) {
      noun = widget.isChannel ? 'слушатель' : 'участник';
    } else if (mod10 >= 2 && mod10 <= 4) {
      noun = widget.isChannel ? 'слушателя' : 'участника';
    } else {
      noun = widget.isChannel ? 'слушателей' : 'участников';
    }
    return '$count $noun';
  }

  List<Map<String, dynamic>> _speakersFromProvider(CallSession session) {
    final active = session.participants
        .where((p) => p.state != 'left' && p.state != 'ended')
        .toList();
    active.sort((a, b) {
      if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
      final aRank = a.role == 'listener' ? 0 : 1;
      final bRank = b.role == 'listener' ? 0 : 1;
      return bRank.compareTo(aRank);
    });
    return active
        .take(3)
        .map((p) => <String, dynamic>{
              'user_id': p.userId,
              'display_name': p.displayName,
              'username': p.username,
              'avatar_url': p.avatarUrl,
            })
        .toList();
  }

  void _openCallScreen({
    required String callId,
    required CallStateProvider? callProvider,
    required bool isAlreadyInCall,
  }) {
    HapticUtils.tap();
    if (isAlreadyInCall) {
      callProvider?.setMinimized(false);
    } else {
      widget.onJoined?.call();
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          callId: callId,
          chatId: widget.chatId,
          userId: widget.currentUserId,
          title: widget.chatTitle,
          isStage: widget.isChannel,
        ),
      ),
    );
  }

  Widget _buildInnerContent(
    BuildContext context, {
    required String effectiveCallId,
    required int participantCount,
    required List<Map<String, dynamic>> speakers,
    required CallStateProvider? callProvider,
    required bool isAlreadyInCall,
  }) {
    final theme = Theme.of(context);
    final palette = theme.extension<TheavThemeExtension>()?.palette ?? context.theav;
    final accentColor = palette.accent;
    final titleColor = palette.onSurface;
    final subtitleColor = palette.subtext;

    final titleText =
        widget.isChannel ? 'Прямая трансляция' : 'Голосовой чат';
    final subtitleText = _formatParticipantCount(participantCount);
    final buttonLabel = isAlreadyInCall ? 'Вернуться' : 'Вступить';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48.0),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 6, top: 4, bottom: 4),
        child: Row(
          children: [
            _PulsingLiveDot(
              animation: _pulseController,
              color: accentColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      iconoir.SoundHigh(
                        width: 13,
                        height: 13,
                        color: accentColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          titleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            if (speakers.isNotEmpty) ...[
              const SizedBox(width: 8),
              TelegramAvatarStack(
                users: speakers,
                maxCount: 3,
                size: 24.0,
              ),
            ],
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: buttonLabel,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22.0),
                  onTap: () => _openCallScreen(
                    callId: effectiveCallId,
                    callProvider: callProvider,
                    isAlreadyInCall: isAlreadyInCall,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 44.0,
                      minWidth: 72.0,
                    ),
                    child: Center(
                      widthFactor: 1.0,
                      child: Container(
                        height: 34.0,
                        padding: const EdgeInsets.symmetric(horizontal: 14.0),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(17.0),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          buttonLabel,
                          style: TextStyle(
                            color: palette.onPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerCard(
    BuildContext context, {
    required String effectiveCallId,
    required int participantCount,
    required List<Map<String, dynamic>> speakers,
    required CallStateProvider? callProvider,
    required bool isAlreadyInCall,
  }) {
    final surfaceStyle = TheavSurfaceStyle.of(context);
    final glassProvider = surfaceStyle.glassProvider;
    final glassEnabled = glassProvider?.enabled ?? false;
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    final inner = _buildInnerContent(
      context,
      effectiveCallId: effectiveCallId,
      participantCount: participantCount,
      speakers: speakers,
      callProvider: callProvider,
      isAlreadyInCall: isAlreadyInCall,
    );

    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: _kCornerRadius,
        refractionIndex: 1.1,
        refractionWidth: 24.0,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openCallScreen(
              callId: effectiveCallId,
              callProvider: callProvider,
              isAlreadyInCall: isAlreadyInCall,
            ),
            child: LiquidGlassLens(
              style: style,
              touch: const LiquidGlassTouch.flexing(
                LiquidGlassFlex(
                  stretch: 4,
                  squeeze: 0.75,
                  lean: 0.2,
                  grip: 0.5,
                ),
              ),
              child: inner,
            ),
          ),
        ),
      );
    }

    final blurFilter = surfaceStyle.getMaterialHudBlurFilter(sigma: 10.0);
    final rawBg = themeExt?.palette.explicitChatInputBackground ??
        themeExt?.palette.surface ??
        (isDark ? const Color(0xFF1C1C1E) : Colors.white);
    final matteBg = surfaceStyle.isGlass
        ? surfaceStyle.hudFill
        : BlurUtils.resolveMaterialHudColor(
            rawBg,
            isDark: isDark,
            blurEnabled: blurFilter != null,
          );

    Widget card = Container(
      decoration: BoxDecoration(
        color: matteBg,
        borderRadius: BorderRadius.circular(_kCornerRadius),
        border: Border.all(
          color: (surfaceStyle.isGlass || blurFilter != null)
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.10))
              : surfaceStyle.hairlineBorder,
          width: blurFilter != null ? 0.6 : 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          onTap: () => _openCallScreen(
            callId: effectiveCallId,
            callProvider: callProvider,
            isAlreadyInCall: isAlreadyInCall,
          ),
          child: inner,
        ),
      ),
    );

    if (blurFilter != null) {
      card = BackdropFilter.grouped(
        filter: blurFilter,
        child: card,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          boxShadow: surfaceStyle.floatingShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          child: card,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callProvider = _maybeCallProvider(context);
    final providerCall = callProvider?.activeCall;
    final bool isCurrentCallInProvider = providerCall != null &&
        providerCall.chatId == widget.chatId &&
        providerCall.status != 'ended';

    final String? effectiveCallId = (_activeCallId != null &&
            _activeCallId!.isNotEmpty)
        ? _activeCallId
        : (isCurrentCallInProvider ? providerCall.id : null);

    final bool shouldShow = effectiveCallId != null &&
        effectiveCallId.isNotEmpty &&
        (!isCurrentCallInProvider || (callProvider?.isMinimized ?? true));

    final int participantCount = isCurrentCallInProvider &&
            providerCall.participants.isNotEmpty
        ? providerCall.participants
            .where((p) => p.state != 'left' && p.state != 'ended')
            .length
        : _participantCount;

    final List<Map<String, dynamic>> speakers = isCurrentCallInProvider &&
            providerCall.participants.isNotEmpty
        ? _speakersFromProvider(providerCall)
        : _speakers;

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final Duration animDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return AnimatedSize(
      duration: animDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: animDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          return ClipRect(
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: shouldShow
            ? KeyedSubtree(
                key: ValueKey<String>('live_call_${widget.chatId}_$effectiveCallId'),
                child: _buildBannerCard(
                  context,
                  effectiveCallId: effectiveCallId,
                  participantCount: participantCount,
                  speakers: speakers,
                  callProvider: callProvider,
                  isAlreadyInCall: isCurrentCallInProvider,
                ),
              )
            : const SizedBox.shrink(key: ValueKey<String>('live_call_empty')),
      ),
    );
  }
}

class _PulsingLiveDot extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _PulsingLiveDot({
    required this.animation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final v = animation.value;
          final haloScale = 0.85 + (0.35 * v);
          final haloAlpha = 0.36 - (0.20 * v);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: haloScale,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: haloAlpha.clamp(0.10, 0.40)),
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
