import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:photo_view/photo_view.dart';

import '../../config/app_config.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import 'inline_video_player.dart';
import 'voice_message_widget.dart';

/// Renders sealed, active-countdown, or burned state for view-once and TTL media.
class ViewOnceMediaWidget extends StatefulWidget {
  final Message message;
  final bool isMe;
  final bool isSavedChat;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Future<Map<String, dynamic>> Function()? onConsumeViewOnce;

  const ViewOnceMediaWidget({
    super.key,
    required this.message,
    required this.isMe,
    this.isSavedChat = false,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    this.onConsumeViewOnce,
  });

  @override
  State<ViewOnceMediaWidget> createState() => _ViewOnceMediaWidgetState();
}

class _ViewOnceMediaWidgetState extends State<ViewOnceMediaWidget> {
  bool _opening = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _syncExpiryTimer();
  }

  @override
  void didUpdateWidget(covariant ViewOnceMediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.expiresAt != widget.message.expiresAt ||
        oldWidget.message.viewedAt != widget.message.viewedAt ||
        oldWidget.message.isBurned != widget.message.isBurned) {
      _syncExpiryTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _syncExpiryTimer() {
    _countdownTimer?.cancel();
    final expRaw = widget.message.expiresAt;
    if (expRaw == null || expRaw.isEmpty) {
      _remainingSeconds = 0;
      return;
    }
    final exp = DateTime.tryParse(expRaw);
    if (exp == null) {
      _remainingSeconds = 0;
      return;
    }
    final diff = exp.difference(DateTime.now().toUtc()).inSeconds;
    _remainingSeconds = diff > 0 ? diff : 0;
    if (_remainingSeconds > 0 && mounted) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final left = exp.difference(DateTime.now().toUtc()).inSeconds;
        setState(() {
          _remainingSeconds = left > 0 ? left : 0;
        });
        if (left <= 0) {
          _countdownTimer?.cancel();
        }
      });
    }
  }

  bool get _isBurnedNow {
    final msg = widget.message;
    if (msg.isBurned) return true;
    if (msg.isViewOnce && msg.viewedAt != null && msg.viewedAt!.isNotEmpty) {
      return true;
    }
    if (msg.expiresAt != null && msg.expiresAt!.isNotEmpty) {
      final exp = DateTime.tryParse(msg.expiresAt!);
      if (exp != null && !exp.isAfter(DateTime.now().toUtc())) {
        return true;
      }
    }
    final url = msg.fileUrl?.trim() ?? '';
    return url.isEmpty;
  }

  String _mediaKindLabel() {
    switch (widget.message.messageType) {
      case 'video':
        return 'Однократное видео';
      case 'voice':
        return 'Однократное голосовое';
      case 'audio':
        return 'Однократное аудио';
      default:
        return 'Однократное фото';
    }
  }

  Future<void> _handleTap() async {
    if (_opening || _isBurnedNow) return;
    final msg = widget.message;
    final resolvedUrl = AppConfig.resolveMediaUrl(msg.fileUrl) ?? msg.fileUrl ?? '';

    if (widget.isMe && !widget.isSavedChat && msg.viewedAt == null) {
      GlassToastService().show(
        context,
        msg.isViewOnce
            ? 'Собеседник ещё не открыл это медиа'
            : 'Таймер запустится после открытия получателем',
      );
      return;
    }
    if (resolvedUrl.isEmpty) {
      GlassToastService().show(context, 'Медиа уже удалено');
      return;
    }

    setState(() => _opening = true);
    try {
      String? activeExpiresAt = msg.expiresAt;
      if (widget.onConsumeViewOnce != null && msg.viewedAt == null) {
        final res = await widget.onConsumeViewOnce!();
        if (!mounted) return;
        if (res['status_code'] == 410 ||
            (res['success'] != true && res['is_burned'] == true)) {
          GlassToastService().show(context, 'Срок действия медиа истёк');
          return;
        }
        activeExpiresAt = res['expires_at']?.toString() ?? activeExpiresAt;
      }

      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          fullscreenDialog: true,
          pageBuilder: (ctx, _, __) => _ViewOnceViewerDialog(
            message: msg,
            mediaUrl: resolvedUrl,
            expiresAtIso: activeExpiresAt,
            initialTtlSeconds: msg.ttlSeconds,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final burned = _isBurnedNow;
    final msg = widget.message;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: burned ? null : _handleTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 270),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.textColor.withValues(alpha: burned ? 0.06 : 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.textColor.withValues(alpha: 0.16),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: burned
                    ? widget.subtextColor.withValues(alpha: 0.18)
                    : (widget.isMe
                        ? widget.textColor.withValues(alpha: 0.22)
                        : widget.accentColor.withValues(alpha: 0.18)),
              ),
              alignment: Alignment.center,
              child: burned
                  ? Icon(
                      Icons.local_fire_department_rounded,
                      size: 20,
                      color: widget.subtextColor,
                    )
                  : _opening
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.isMe
                                ? widget.textColor
                                : widget.accentColor,
                          ),
                        )
                      : msg.isViewOnce
                          ? Text(
                              '1',
                              style: TextStyle(
                                color: widget.isMe
                                    ? widget.textColor
                                    : widget.accentColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : iconoir.Timer(
                              width: 19,
                              height: 19,
                              color: widget.isMe
                                  ? widget.textColor
                                  : widget.accentColor,
                            ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    burned
                        ? 'Медиа исчезло'
                        : (msg.isViewOnce
                            ? _mediaKindLabel()
                            : 'Скроется через ${msg.ttlSeconds} сек'),
                    style: TextStyle(
                      color: burned ? widget.subtextColor : widget.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    burned
                        ? 'Просмотр завершён'
                        : (_remainingSeconds > 0
                            ? 'Осталось $_remainingSeconds с'
                            : (msg.isViewOnce
                                ? 'Нажмите для 1 просмотра'
                                : 'Нажмите для просмотра')),
                    style: TextStyle(
                      color: widget.subtextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewOnceViewerDialog extends StatefulWidget {
  final Message message;
  final String mediaUrl;
  final String? expiresAtIso;
  final int initialTtlSeconds;

  const _ViewOnceViewerDialog({
    required this.message,
    required this.mediaUrl,
    this.expiresAtIso,
    this.initialTtlSeconds = 0,
  });

  @override
  State<_ViewOnceViewerDialog> createState() => _ViewOnceViewerDialogState();
}

class _ViewOnceViewerDialogState extends State<_ViewOnceViewerDialog> {
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    DateTime? deadline = widget.expiresAtIso != null
        ? DateTime.tryParse(widget.expiresAtIso!)
        : null;
    if (deadline == null &&
        !widget.message.isViewOnce &&
        widget.initialTtlSeconds > 0) {
      deadline = DateTime.now()
          .toUtc()
          .add(Duration(seconds: widget.initialTtlSeconds));
    }
    if (deadline != null) {
      final initialLeft = deadline.difference(DateTime.now().toUtc()).inSeconds;
      _secondsLeft = initialLeft > 0 ? initialLeft : 1;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final left = deadline!.difference(DateTime.now().toUtc()).inSeconds;
        if (left <= 0) {
          _timer?.cancel();
          Navigator.of(context).maybePop();
        } else {
          setState(() => _secondsLeft = left);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgType = widget.message.messageType.toLowerCase();
    Widget body;
    if (msgType == 'video') {
      body = Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height * 0.72,
          child: InlineVideoPlayer(
            url: widget.mediaUrl,
            autoplay: true,
          ),
        ),
      );
    } else if (msgType == 'voice' || msgType == 'audio') {
      body = Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2430),
            borderRadius: BorderRadius.circular(18),
          ),
          child: VoiceMessageWidget(
            messageId: widget.message.id,
            audioUrl: widget.mediaUrl,
            waveform: widget.message.waveform,
            duration: widget.message.duration != null
                ? Duration(seconds: widget.message.duration!)
                : null,
            isMe: false,
          ),
        ),
      );
    } else {
      body = PhotoView(
        imageProvider: CachedNetworkImageProvider(widget.mediaUrl),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2.5,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: body),
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  if (_secondsLeft > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const iconoir.Timer(
                            width: 15,
                            height: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$_secondsLeft с',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        '1 просмотр',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
