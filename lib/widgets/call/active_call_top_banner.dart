import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/call_state_provider.dart';
import '../../services/liquid_glass_provider.dart';

/// Floating top banner shown across the app whenever:
/// 1) An incoming call is ringing (`callProvider.hasIncomingCall`), or
/// 2) An active call or voice channel is minimized (`callProvider.hasActiveCall && callProvider.isMinimized`).
///
/// Obeys the Liquid Glass animation contract:
/// - Outer shape animates strictly via [ClipRect] + [Align] (`heightFactor`) + [SlideTransition].
/// - No [FadeTransition] or [Opacity] is ever applied to [LiquidGlassLens].
class ActiveCallTopBanner extends StatefulWidget {
  final VoidCallback onRestoreCall;

  const ActiveCallTopBanner({
    super.key,
    required this.onRestoreCall,
  });

  @override
  State<ActiveCallTopBanner> createState() => _ActiveCallTopBannerState();
}

class _ActiveCallTopBannerState extends State<ActiveCallTopBanner>
    with TickerProviderStateMixin {
  late final AnimationController _visibilityCtrl;
  late final Animation<double> _heightFactor;
  late final Animation<Offset> _slideOffset;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _visibilityCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );
    final curve = CurvedAnimation(
      parent: _visibilityCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _heightFactor = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _slideOffset = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(curve);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _visibilityCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallStateProvider>();
    final isIncoming = callProvider.hasIncomingCall;
    final isMinimizedActive =
        callProvider.hasActiveCall && callProvider.isMinimized;
    final shouldShow = isIncoming || isMinimizedActive;

    if (shouldShow &&
        _visibilityCtrl.status != AnimationStatus.forward &&
        _visibilityCtrl.status != AnimationStatus.completed) {
      _visibilityCtrl.forward();
    } else if (!shouldShow &&
        _visibilityCtrl.status != AnimationStatus.reverse &&
        _visibilityCtrl.status != AnimationStatus.dismissed) {
      _visibilityCtrl.reverse();
    }

    return AnimatedBuilder(
      animation: _visibilityCtrl,
      builder: (context, _) {
        if (_visibilityCtrl.isDismissed && !shouldShow) {
          return const SizedBox.shrink();
        }
        final incoming = callProvider.incomingCall;
        final active = callProvider.activeCall;
        if (incoming == null && active == null) {
          return const SizedBox.shrink();
        }

        final p = context.theav;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final glassProvider = context.watch<LiquidGlassProvider>();
        final useGlass = glassProvider.enabled;
        final isFullGlass = glassProvider.isFull;

        if (incoming != null && active == null) {
          return _buildIncomingBanner(
            context: context,
            callProvider: callProvider,
            p: p,
            isDark: isDark,
            glassProvider: glassProvider,
            useGlass: useGlass,
            isFullGlass: isFullGlass,
          );
        }

        final call = active!;
        final stream = callProvider.focusedStream;

        final innerContent = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // Pulsing active voice dot
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) => Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676)
                        .withValues(alpha: 0.5 + 0.5 * _pulseCtrl.value),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onRestoreCall();
                  },
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          call.title.isNotEmpty ? call.title : 'Активный звонок',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : p.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        callProvider.formattedDuration,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF69F0AE)
                              : const Color(0xFF00897B),
                        ),
                      ),
                      if (stream != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6D00)
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFF9100),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            stream.qualityBadge,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFFAB40),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (callProvider.isScreenSharing) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  padding: EdgeInsets.zero,
                  tooltip: 'Остановить демонстрацию экрана',
                  icon: const Icon(
                    Icons.stop_screen_share_rounded,
                    size: 19,
                    color: Colors.redAccent,
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    callProvider.stopScreenShare();
                  },
                ),
                const SizedBox(width: 2),
              ],
              // Quick Mute button
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                tooltip: callProvider.isMuted
                    ? 'Включить микрофон'
                    : 'Выключить микрофон',
                icon: Icon(
                  callProvider.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  size: 19,
                  color: callProvider.isMuted
                      ? Colors.redAccent
                      : (isDark ? Colors.white : p.textPrimary),
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  callProvider.toggleMute();
                },
              ),
              const SizedBox(width: 4),
              // Quick Hangup button
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  callProvider.leaveCall();
                },
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _heightFactor.value,
            child: SlideTransition(
              position: _slideOffset,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: useGlass
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onRestoreCall,
                          child: LiquidGlassLens(
                            style: glassProvider.createStyle(
                              context: context,
                              cornerRadius: 22,
                              color: const Color(0xFF00C853)
                                  .withValues(alpha: isDark ? 0.16 : 0.22),
                              refractionIndex: isFullGlass ? 1.12 : 1.05,
                              refractionWidth: 24.0,
                            ),
                            touch: const LiquidGlassTouch.flexing(
                              LiquidGlassFlex(
                                stretch: 4,
                                squeeze: 0.75,
                                lean: 0.2,
                                grip: 0.5,
                              ),
                            ),
                            child: innerContent,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: BackdropFilter.grouped(
                            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Material(
                              color: isDark
                                  ? const Color(0xFF132A21)
                                      .withValues(alpha: 0.90)
                                  : const Color(0xFFE8F5E9)
                                      .withValues(alpha: 0.94),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                                side: BorderSide(
                                  color: const Color(0xFF00C853)
                                      .withValues(alpha: 0.38),
                                  width: 0.8,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: widget.onRestoreCall,
                                child: innerContent,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIncomingBanner({
    required BuildContext context,
    required CallStateProvider callProvider,
    required TheavPalette p,
    required bool isDark,
    required LiquidGlassProvider glassProvider,
    required bool useGlass,
    required bool isFullGlass,
  }) {
    final incoming = callProvider.incomingCall!;
    final callerTitle =
        incoming.title.isNotEmpty ? incoming.title : 'Входящий звонок';
    final subtitle = incoming.callType == 'group' || incoming.callType == 'stage'
        ? 'Приглашение в голосовой канал'
        : (incoming.isVideo
            ? 'Входящий видеозвонок...'
            : 'Входящий аудиозвонок...');

    final innerContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, _) => Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676)
                    .withValues(alpha: 0.18 + 0.16 * _pulseCtrl.value),
                shape: BoxShape.circle,
              ),
              child: Icon(
                incoming.isVideo
                    ? Icons.videocam_rounded
                    : Icons.phone_in_talk_rounded,
                size: 20,
                color: const Color(0xFF00E676),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  callerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF69F0AE)
                        : const Color(0xFF00897B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Decline Button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              callProvider.declineIncomingCall();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_end_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Accept Button
          GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              await callProvider.acceptIncomingCall();
              widget.onRestoreCall();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Color(0xFF00C853),
                shape: BoxShape.circle,
              ),
              child: Icon(
                incoming.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _heightFactor.value,
        child: SlideTransition(
          position: _slideOffset,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: SizedBox(
              height: 62,
              width: double.infinity,
              child: useGlass
                  ? LiquidGlassLens(
                      style: glassProvider.createStyle(
                        context: context,
                        cornerRadius: 26,
                        color: const Color(0xFF00C853)
                            .withValues(alpha: isDark ? 0.18 : 0.24),
                        refractionIndex: isFullGlass ? 1.12 : 1.05,
                        refractionWidth: 24.0,
                      ),
                      child: innerContent,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: BackdropFilter.grouped(
                        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Material(
                          color: isDark
                              ? const Color(0xFF132A21).withValues(alpha: 0.94)
                              : const Color(0xFFE8F5E9).withValues(alpha: 0.96),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                            side: BorderSide(
                              color: const Color(0xFF00C853)
                                  .withValues(alpha: 0.45),
                              width: 1.0,
                            ),
                          ),
                          child: innerContent,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
