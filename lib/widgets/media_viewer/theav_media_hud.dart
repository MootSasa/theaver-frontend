import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../models/theav_media_item.dart';
import '../../services/contacts_service.dart';
import '../../services/media_cache_manager.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../message/text_message_widget.dart';
import 'theav_media_video_surface.dart';

/// Zero-shader, zero-blur matte HUD overlay for [TheavMediaViewer].
///
/// Uses only lightweight [LinearGradient] edge scrims, opaque/semi-opaque matte
/// `#B3101218` pills with `1px` hairline borders, and hardware [FadeTransition]
/// (never [Opacity] `saveLayer`, [BackdropFilter], or `LiquidGlassLens`).
class TheavMediaHud extends StatefulWidget {
  final List<TheavMediaItem> items;
  final int currentIndex;
  final TheavMediaItem currentItem;
  final bool hudVisible;
  final bool isZoomed;
  final bool isSaving;
  final String? titleOverride;
  final TheavMediaAction? primaryTopAction;
  final TheavVideoPlaybackBridge? videoBridge;
  final Widget? bottomAccessory;
  final bool hasJumpToMessage;
  final VoidCallback onClose;
  final VoidCallback? onSave;
  final VoidCallback? onEnterPip;
  final VoidCallback onOpenMoreMenu;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;
  final ValueChanged<int> onSelectFilmstripIndex;
  final VoidCallback? onCaptionInteraction;

  const TheavMediaHud({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.currentItem,
    required this.hudVisible,
    required this.isZoomed,
    required this.isSaving,
    this.titleOverride,
    this.primaryTopAction,
    this.videoBridge,
    this.bottomAccessory,
    this.hasJumpToMessage = false,
    required this.onClose,
    this.onSave,
    this.onEnterPip,
    required this.onOpenMoreMenu,
    this.onPrevPage,
    this.onNextPage,
    required this.onSelectFilmstripIndex,
    this.onCaptionInteraction,
  });

  @override
  State<TheavMediaHud> createState() => _TheavMediaHudState();
}

class _TheavMediaHudState extends State<TheavMediaHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hudAnimController;
  late final CurvedAnimation _hudCurvedAnimation;
  late final ScrollController _filmstripController = ScrollController();

  bool _isCaptionExpanded = false;
  bool _isScrubbing = false;
  double _scrubFraction = 0.0;

  @override
  void initState() {
    super.initState();
    _hudAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.hudVisible ? 1.0 : 0.0,
    );
    _hudCurvedAnimation = CurvedAnimation(
      parent: _hudAnimController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant TheavMediaHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hudVisible != widget.hudVisible) {
      if (widget.hudVisible) {
        _hudAnimController.forward();
      } else {
        _hudAnimController.reverse();
      }
    }
    if (oldWidget.currentItem.id != widget.currentItem.id) {
      _isCaptionExpanded = false;
    }
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollFilmstripToIndex(widget.currentIndex);
      });
    }
  }

  @override
  void dispose() {
    _hudCurvedAnimation.dispose();
    _hudAnimController.dispose();
    _filmstripController.dispose();
    super.dispose();
  }

  void _scrollFilmstripToIndex(int index) {
    if (!mounted || !_filmstripController.hasClients || widget.items.length <= 1) {
      return;
    }
    final pos = _filmstripController.position;
    if (!pos.hasViewportDimension) return;
    // Approximate centered offset for active thumb (28px + 4px margin = 32px step).
    const double itemStep = 32.0;
    final double targetCenter = index * itemStep + 21.0;
    final double targetOffset =
        (targetCenter - pos.viewportDimension * 0.5).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((pos.pixels - targetOffset).abs() < 4.0) return;
    _filmstripController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  String _tr(BuildContext context, String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  String _formatDuration(Duration d) {
    final totalSecs = math.max(0, d.inSeconds);
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final s = totalSecs % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatSpeed(double speed) {
    if ((speed - speed.roundToDouble()).abs() < 0.05) {
      return '${speed.round()}x';
    }
    return '${speed.toStringAsFixed(1)}x';
  }

  String _formatTimestamp(BuildContext context, DateTime? ts) {
    if (ts == null) return '';
    final local = ts.toLocal();
    final hhmm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (DateTimeUtils.isToday(local)) {
      return '${_tr(context, 'date_today', 'Сегодня')} в $hhmm';
    }
    if (DateTimeUtils.isYesterday(local)) {
      return '${_tr(context, 'date_yesterday', 'Вчера')} в $hhmm';
    }
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd.$mm.${local.year} в $hhmm';
  }

  String _resolvePrimaryTitle(BuildContext context) {
    if (widget.items.length > 1) {
      final template = _tr(context, 'media_viewer_of', '{current} из {total}');
      return template
          .replaceAll('{current}', '${widget.currentIndex + 1}')
          .replaceAll('{total}', '${widget.items.length}');
    }
    if (widget.titleOverride != null && widget.titleOverride!.isNotEmpty) {
      return widget.titleOverride!;
    }
    switch (widget.currentItem.kind) {
      case TheavMediaKind.avatar:
        return widget.currentItem.senderName ??
            _tr(context, 'profile_avatar_title', 'Фото профиля');
      case TheavMediaKind.gif:
        return 'GIF';
      case TheavMediaKind.video:
        return _tr(context, 'chat_video', 'Видео');
      case TheavMediaKind.photo:
        return _tr(context, 'chat_photo', 'Фото');
    }
  }

  String _resolveSubtitle(BuildContext context, TheavMediaItem item) {
    final String rawAuthor = item.senderName?.trim() ?? '';
    String resolvedAuthor = rawAuthor;
    if (rawAuthor.isNotEmpty &&
        item.senderId != null &&
        item.senderId!.isNotEmpty &&
        ContactsService.shouldResolveUserIdentity(
          item.senderId,
          senderChatId: item.senderChatId,
          isAnonymousAdmin: item.isAnonymousAdmin,
          isMirroredChannelPost: item.isMirroredChannelPost,
        )) {
      resolvedAuthor = ContactsService.resolvePeerName(
        item.senderId!,
        rawAuthor,
        senderChatId: item.senderChatId,
        isAnonymousAdmin: item.isAnonymousAdmin,
        isMirroredChannelPost: item.isMirroredChannelPost,
      );
    }

    final String datePart = _formatTimestamp(context, item.timestamp);
    // Avoid duplicating author name if single avatar already shows displayName as title.
    final bool titleAlreadyAuthor = widget.items.length <= 1 &&
        item.kind == TheavMediaKind.avatar &&
        resolvedAuthor == _resolvePrimaryTitle(context);

    if (resolvedAuthor.isNotEmpty && !titleAlreadyAuthor && datePart.isNotEmpty) {
      return '$resolvedAuthor · $datePart';
    }
    if (resolvedAuthor.isNotEmpty && !titleAlreadyAuthor) {
      return resolvedAuthor;
    }
    return datePart;
  }

  double _nextPlaybackSpeed(double current) {
    if (current < 1.25) return 1.5;
    if (current < 1.75) return 2.0;
    if (current >= 1.75) return 0.5;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final platform = Theme.of(context).platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;
    final item = widget.currentItem;
    final bool showArrows = isDesktop && widget.items.length > 1 && !widget.isZoomed;

    final Widget content = Stack(
      fit: StackFit.expand,
      children: [
        // 1. Top bar + gradient scrim
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: RepaintBoundary(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                10,
                pad.top + 8,
                10,
                20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xB8000000),
                    Color(0x00000000),
                  ],
                ),
              ),
              child: Row(
                children: [
                  _MatteCircleButton(
                    tooltip: _tr(context, 'close', 'Закрыть'),
                    onTap: widget.onClose,
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: ContactsService.revisionNotifier,
                      builder: (context, _, __) {
                        final primaryTitle = _resolvePrimaryTitle(context);
                        final subtitle = _resolveSubtitle(context, item);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              primaryTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                            if (item.isCustomAvatar) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xD9007AFF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item.customBadgeLabel ??
                                      _tr(
                                        context,
                                        'contact_custom_photo_badge',
                                        'Персональное фото',
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.primaryTopAction != null) ...[
                        _MatteCircleButton(
                          tooltip: widget.primaryTopAction!.label,
                          onTap: () => widget.primaryTopAction!.onSelected(
                            context,
                            item,
                            widget.currentIndex,
                          ),
                          child: Icon(
                            widget.primaryTopAction!.icon ??
                                Icons.add_a_photo_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (item.kind == TheavMediaKind.video &&
                          widget.onEnterPip != null &&
                          widget.videoBridge != null)
                        ValueListenableBuilder<TheavVideoPlaybackState>(
                          valueListenable: widget.videoBridge!.state,
                          builder: (_, s, __) {
                            if (!s.isInitialized) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _MatteCircleButton(
                                tooltip: _tr(
                                  context,
                                  'media_viewer_pip',
                                  'Мини-окно',
                                ),
                                onTap: widget.onEnterPip!,
                                child: const Icon(
                                  Icons.picture_in_picture_alt_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      if (item.hasProtectedContent) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message: _tr(
                              context,
                              'media_viewer_protected_content',
                              'Копирование и сохранение запрещены',
                            ),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xB3101218),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 1.0,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const iconoir.Lock(
                                color: Colors.white70,
                                width: 18,
                                height: 18,
                              ),
                            ),
                          ),
                        ),
                      ] else if (widget.onSave != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _MatteCircleButton(
                            tooltip: _tr(
                              context,
                              'media_viewer_save_to_gallery',
                              'Сохранить',
                            ),
                            onTap: widget.isSaving ? null : widget.onSave!,
                            child: widget.isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const iconoir.Download(
                                    color: Colors.white,
                                    width: 20,
                                    height: 20,
                                  ),
                          ),
                        ),
                      ],
                      _MatteCircleButton(
                        tooltip: _tr(context, 'more', 'Ещё'),
                        onTap: widget.onOpenMoreMenu,
                        child: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // 2. Desktop < / > hover/navigation arrows
        if (showArrows && widget.currentIndex > 0 && widget.onPrevPage != null)
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _MatteCircleButton(
                size: 44,
                tooltip: _tr(context, 'previous', 'Назад'),
                onTap: widget.onPrevPage!,
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        if (showArrows &&
            widget.currentIndex < widget.items.length - 1 &&
            widget.onNextPage != null)
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _MatteCircleButton(
                size: 44,
                tooltip: _tr(context, 'next', 'Вперёд'),
                onTap: widget.onNextPage!,
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),

        // 3. Bottom area: expandable caption + video bar + filmstrip + optional accessory
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                0,
                26,
                0,
                math.max(pad.bottom, 10.0),
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[
                    Color(0xD9000000),
                    Color(0x88000000),
                    Color(0x00000000),
                  ],
                  stops: <double>[0.0, 0.55, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (item.hasCaption) _buildCaptionBlock(context, item),
                  if (item.kind == TheavMediaKind.video &&
                      widget.videoBridge != null)
                    _buildVideoControlsBar(context, widget.videoBridge!),
                  if (widget.bottomAccessory != null) widget.bottomAccessory!,
                  if (widget.items.length > 1) _buildFilmstrip(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    return FadeTransition(
      opacity: _hudCurvedAnimation,
      child: IgnorePointer(
        key: const ValueKey<String>('theav_media_hud_ignore_pointer'),
        ignoring: !widget.hudVisible,
        child: content,
      ),
    );
  }

  Widget _buildCaptionBlock(BuildContext context, TheavMediaItem item) {
    final String text = item.caption!.trim();
    const TextStyle captionStyle = TextStyle(
      color: Colors.white,
      fontSize: 14.5,
      height: 1.32,
      decoration: TextDecoration.none,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.selection();
          setState(() => _isCaptionExpanded = !_isCaptionExpanded);
          widget.onCaptionInteraction?.call();
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: _isCaptionExpanded ? 185.0 : 54.0,
          ),
          child: _isCaptionExpanded
              ? SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: item.entities.isNotEmpty
                      ? TextMessageWidget(
                          text: text,
                          entities: item.entities,
                          isMe: false,
                          style: captionStyle,
                        )
                      : Text(text, style: captionStyle),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: item.entities.isNotEmpty
                          ? Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: captionStyle,
                            )
                          : Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: captionStyle,
                            ),
                    ),
                    if (text.length > 90 || text.contains('\n'))
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          _tr(context, 'media_viewer_more', 'ещё'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildVideoControlsBar(
    BuildContext context,
    TheavVideoPlaybackBridge bridge,
  ) {
    return RepaintBoundary(
      child: ValueListenableBuilder<TheavVideoPlaybackState>(
        valueListenable: bridge.state,
        builder: (context, s, _) {
          final int totalMs = s.duration.inMilliseconds;
          final int posMs = s.position.inMilliseconds;
          final int bufMs = s.bufferedEnd.inMilliseconds;
          final double progress = _isScrubbing
              ? _scrubFraction
              : (totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0);
          final double bufferedProgress =
              totalMs > 0 ? (bufMs / totalMs).clamp(0.0, 1.0) : 0.0;
          final Duration displayedPosition = _isScrubbing
              ? Duration(milliseconds: (totalMs * _scrubFraction).round())
              : s.position;

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isScrubbing && totalMs > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC101218),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        _formatDuration(displayedPosition),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                SwipeBackBlocker(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double trackWidth =
                          math.max(1.0, constraints.maxWidth - 20.0);
                      void updateScrub(double localDx) {
                        final f =
                            ((localDx - 10.0) / trackWidth).clamp(0.0, 1.0);
                        setState(() {
                          _isScrubbing = true;
                          _scrubFraction = f;
                        });
                      }

                      Future<void> commitScrub() async {
                        if (!_isScrubbing) return;
                        final targetMs = (totalMs * _scrubFraction).round();
                        setState(() => _isScrubbing = false);
                        if (totalMs > 0) {
                          await bridge
                              .seekTo(Duration(milliseconds: targetMs));
                        }
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (d) =>
                            updateScrub(d.localPosition.dx),
                        onHorizontalDragUpdate: (d) =>
                            updateScrub(d.localPosition.dx),
                        onHorizontalDragEnd: (_) => unawaited(commitScrub()),
                        onHorizontalDragCancel: () =>
                            setState(() => _isScrubbing = false),
                        onTapDown: (d) => updateScrub(d.localPosition.dx),
                        onTapUp: (_) => unawaited(commitScrub()),
                        child: SizedBox(
                          height: 28,
                          child: Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: _isScrubbing ? 5.0 : 3.5,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.24),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: bufferedProgress,
                                  child: Container(
                                    height: _isScrubbing ? 5.0 : 3.5,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.42),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: progress,
                                  child: Container(
                                    height: _isScrubbing ? 5.0 : 3.5,
                                    margin: const EdgeInsets.only(left: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 10.0 + trackWidth * progress - 7.0,
                                  child: Container(
                                    width: _isScrubbing ? 16 : 13,
                                    height: _isScrubbing ? 16 : 13,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
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
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MatteCircleButton(
                      size: 36,
                      tooltip: s.isPlaying
                          ? _tr(context, 'pause', 'Пауза')
                          : _tr(context, 'play', 'Воспроизвести'),
                      onTap: () => bridge.togglePlayPause(),
                      child: s.isPlaying
                          ? const iconoir.Pause(
                              color: Colors.white,
                              width: 18,
                              height: 18,
                            )
                          : const iconoir.Play(
                              color: Colors.white,
                              width: 18,
                              height: 18,
                            ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDuration(displayedPosition)} / ${_formatDuration(s.duration)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.90),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        bridge.setSpeed(_nextPlaybackSpeed(s.playbackSpeed));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xB3101218),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          _formatSpeed(s.playbackSpeed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MatteCircleButton(
                      size: 36,
                      tooltip: s.isMuted
                          ? _tr(context, 'unmute', 'Включить звук')
                          : _tr(context, 'mute', 'Выключить звук'),
                      onTap: () => bridge.toggleMute(),
                      child: Icon(
                        s.isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilmstrip(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        controller: _filmstripController,
        scrollDirection: Axis.horizontal,
        scrollCacheExtent: const ScrollCacheExtent.pixels(240),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        itemCount: widget.items.length,
        itemBuilder: (context, idx) {
          final item = widget.items[idx];
          final bool active = idx == widget.currentIndex;
          return GestureDetector(
            onTap: () {
              HapticUtils.selection();
              widget.onSelectFilmstripIndex(idx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: active ? 44 : 28,
              height: 42,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(active ? 7 : 5),
                border: Border.all(
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.16),
                  width: active ? 1.8 : 0.7,
                ),
                color: const Color(0xFF1A1D24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(active ? 5.2 : 4.2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _FilmstripThumbImage(item: item),
                    if (item.kind == TheavMediaKind.video)
                      Center(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const iconoir.Play(
                            color: Colors.white,
                            width: 10,
                            height: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilmstripThumbImage extends StatelessWidget {
  final TheavMediaItem item;

  const _FilmstripThumbImage({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.memoryBytes != null && item.memoryBytes!.isNotEmpty) {
      return Image.memory(
        item.memoryBytes!,
        fit: BoxFit.cover,
        cacheWidth: 96,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      );
    }

    final resolved = item.resolvedUrl;
    if (item.kind == TheavMediaKind.photo || item.kind == TheavMediaKind.avatar) {
      if (!kIsWeb && item.localFilePath != null && item.localFilePath!.isNotEmpty) {
        final f = File(item.localFilePath!);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            cacheWidth: 96,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          );
        }
      }
      final cachedFile = MediaCacheManager.instance.getCachedFileSync(resolved);
      if (cachedFile != null) {
        return Image.file(
          cachedFile,
          fit: BoxFit.cover,
          cacheWidth: 96,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      }
      if (!kIsWeb && resolved.startsWith('file://')) {
        return Image.file(
          File(Uri.parse(resolved).toFilePath()),
          fit: BoxFit.cover,
          cacheWidth: 96,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      }
      if (!kIsWeb &&
          resolved.startsWith('/') &&
          !resolved.startsWith('/api/') &&
          !resolved.startsWith('/uploads/') &&
          File(resolved).existsSync()) {
        return Image.file(
          File(resolved),
          fit: BoxFit.cover,
          cacheWidth: 96,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      }
      final validUrl = stripAvatarCropFragment(getValidAvatarUrl(resolved)) ??
          resolved;
      if (validUrl.startsWith('http://') || validUrl.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: validUrl,
          fit: BoxFit.cover,
          memCacheWidth: 96,
          filterQuality: FilterQuality.low,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        );
      }
    }

    // Video / GIF thumbnail: local extracted frame -> thumbUrl -> thumbBase64
    final localOrCached = item.localFilePath ??
        MediaCacheManager.instance.getCachedFileSync(resolved)?.path;
    if (localOrCached != null) {
      final firstFrame = MediaCacheManager.instance
          .getCachedVideoThumbnailSync(localOrCached);
      if (firstFrame != null) {
        return Image.memory(
          firstFrame,
          fit: BoxFit.cover,
          cacheWidth: 96,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      }
    }
    final thumbUrl = item.resolvedThumbUrl;
    if (thumbUrl != null && thumbUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: thumbUrl,
        fit: BoxFit.cover,
        memCacheWidth: 96,
        filterQuality: FilterQuality.low,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    final b64 = item.thumbBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final raw = b64.contains(',') ? b64.split(',').last : b64;
        return Image.memory(
          base64Decode(raw),
          fit: BoxFit.cover,
          cacheWidth: 96,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }

    return const Center(
      child: iconoir.MediaImage(
        color: Colors.white30,
        width: 14,
        height: 14,
      ),
    );
  }
}

class _MatteCircleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String tooltip;
  final Widget child;
  final double size;

  const _MatteCircleButton({
    required this.onTap,
    required this.tooltip,
    required this.child,
    this.size = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xB3101218),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
