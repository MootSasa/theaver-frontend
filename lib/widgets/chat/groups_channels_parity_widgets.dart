import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../utils/blur_utils.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../common/peer_badges_widget.dart';
import '../design_system/theav_design_system.dart';
import '../user/avatar_with_status.dart';

String _trSendAs(BuildContext context, String key, String fallback) {
  final loc = AppLocalizations.of(context);
  if (loc != null) {
    if (loc.hasKey(key)) {
      return loc.translate(key);
    }
    final translated = loc.translate(key);
    if (translated.isNotEmpty && translated != key) {
      return translated;
    }
  }
  return fallback;
}

String _formatThousands(int n) {
  final raw = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) {
      buf.write(' ');
    }
    buf.write(raw[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}

String _formatSendAsSubscribers(BuildContext context, int count) {
  final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'ru';
  final formatted = _formatThousands(count);
  if (lang == 'ru') {
    final mod100 = count.abs() % 100;
    final mod10 = count.abs() % 10;
    if (mod100 >= 11 && mod100 <= 19) {
      return '$formatted подписчиков';
    }
    if (mod10 == 1) {
      return '$formatted подписчик';
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return '$formatted подписчика';
    }
    return '$formatted подписчиков';
  }
  return count == 1 ? '1 subscriber' : '$formatted subscribers';
}

final ValueNotifier<Set<String>> _openSendAsPopupChatIds =
    ValueNotifier<Set<String>>(<String>{});
final ValueNotifier<Set<int>> _openSendAsPopupAnchorHashes =
    ValueNotifier<Set<int>>(<int>{});
final Map<String, int> _openSendAsPopupChatCounts = <String, int>{};
final Map<String, BuildContext> _registeredSendAsAnchors =
    <String, BuildContext>{};
BuildContext? _lastTappedSendAsAnchor;
VoidCallback? _activeSenderSelectDismiss;

/// Inline `36x36` circular "Send As" button rendered inside the left edge of
/// [LiquidGlassInputField], matching Telegram Android's `SenderSelectView`:
/// spring-morphs (`menuProgress: 0.0 <-> 1.0`) between the active [SendAsPeer]
/// circular avatar and a solid primary accent circle with a crisp white `×`
/// close cross while the floating [showSenderSelectPopup] menu is open.
class InlineSendAsSelectorButton extends StatefulWidget {
  final List<SendAsPeer> peers;
  final SendAsPeer? selectedPeer;
  final bool isPopupOpen;
  final VoidCallback? onTap;
  final ValueChanged<BuildContext>? onOpenPopup;
  final String? chatId;
  final ValueChanged<SendAsPeer>? onPeerSelected;
  final double size;

  const InlineSendAsSelectorButton({
    super.key,
    required this.peers,
    this.selectedPeer,
    this.isPopupOpen = false,
    this.onTap,
    this.onOpenPopup,
    this.chatId,
    this.onPeerSelected,
    this.size = 36.0,
  });

  @override
  State<InlineSendAsSelectorButton> createState() =>
      _InlineSendAsSelectorButtonState();
}

class _InlineSendAsSelectorButtonState extends State<InlineSendAsSelectorButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphController;
  bool _localPopupOpen = false;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.isPopupOpen ? 1.0 : 0.0,
    );
    _openSendAsPopupChatIds.addListener(_syncOpenState);
    _openSendAsPopupAnchorHashes.addListener(_syncOpenState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      _registeredSendAsAnchors[widget.chatId!] = context;
    }
  }

  @override
  void didUpdateWidget(covariant InlineSendAsSelectorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      if (oldWidget.chatId != null &&
          _registeredSendAsAnchors[oldWidget.chatId!] == context) {
        _registeredSendAsAnchors.remove(oldWidget.chatId!);
      }
      if (widget.chatId != null && widget.chatId!.isNotEmpty) {
        _registeredSendAsAnchors[widget.chatId!] = context;
      }
    }
    _syncOpenState();
  }

  void _syncOpenState() {
    if (!mounted) return;
    final bool byChat = widget.chatId != null &&
        widget.chatId!.isNotEmpty &&
        _openSendAsPopupChatIds.value.contains(widget.chatId!);
    final bool byAnchor =
        _openSendAsPopupAnchorHashes.value.contains(identityHashCode(context));
    final bool effectiveOpen =
        widget.isPopupOpen || _localPopupOpen || byChat || byAnchor;
    if (effectiveOpen) {
      if (_morphController.status != AnimationStatus.forward &&
          _morphController.value < 1.0) {
        _morphController.forward();
      }
    } else {
      if (_morphController.status != AnimationStatus.reverse &&
          _morphController.value > 0.0) {
        _morphController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _openSendAsPopupChatIds.removeListener(_syncOpenState);
    _openSendAsPopupAnchorHashes.removeListener(_syncOpenState);
    if (widget.chatId != null &&
        _registeredSendAsAnchors[widget.chatId!] == context) {
      _registeredSendAsAnchors.remove(widget.chatId!);
    }
    if (_lastTappedSendAsAnchor == context) {
      _lastTappedSendAsAnchor = null;
    }
    _morphController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    HapticUtils.selection();
    _lastTappedSendAsAnchor = context;
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      _registeredSendAsAnchors[widget.chatId!] = context;
    }

    if (_localPopupOpen && _activeSenderSelectDismiss != null) {
      _activeSenderSelectDismiss!();
      return;
    }

    if (widget.onOpenPopup != null) {
      widget.onOpenPopup!(context);
      return;
    }
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      setState(() => _localPopupOpen = true);
      _syncOpenState();
      try {
        final active = widget.selectedPeer ??
            (widget.peers.isNotEmpty ? widget.peers.first : null);
        final picked = await showSenderSelectPopup(
          context,
          chatId: widget.chatId!,
          peers: widget.peers,
          currentPeer: active,
        );
        if (picked != null && mounted) {
          widget.onPeerSelected?.call(picked);
        }
      } finally {
        if (mounted) {
          setState(() => _localPopupOpen = false);
          _syncOpenState();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.peers.length <= 1) return const SizedBox.shrink();
    final palette = context.theav;
    final active = widget.selectedPeer ?? widget.peers.first;
    final String tooltipText;
    if (active.isChannel) {
      tooltipText = 'От имени канала: ${active.name}';
    } else if (active.isGroupAnon) {
      tooltipText = 'От имени группы: ${active.name}';
    } else {
      tooltipText = 'От своего имени: ${active.name}';
    }

    final bool hasAction = widget.onOpenPopup != null ||
        widget.onTap != null ||
        (widget.chatId != null && widget.chatId!.isNotEmpty);

    return TextFieldTapRegion(
      child: KeyedSubtree(
        key: const ValueKey('send_as_inline_avatar_button'),
        child: Tooltip(
          message: tooltipText,
          child: GestureDetector(
            onTap: hasAction ? _handleTap : null,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _morphController,
                builder: (context, _) {
                  final rawT = _morphController.value;
                  final bool isOpening =
                      _morphController.status != AnimationStatus.reverse;
                  final double progress = (isOpening
                          ? Curves.easeOutBack.transform(rawT)
                          : Curves.easeInCubic.transform(rawT))
                      .clamp(0.0, 1.15);
                  final double clampedT = rawT.clamp(0.0, 1.0);
                  final double avatarScale =
                      (1.0 - clampedT * 0.65).clamp(0.0, 1.0);
                  final double avatarOpacity =
                      (1.0 - clampedT * 1.25).clamp(0.0, 1.0);
                  final double closeScale = progress.clamp(0.0, 1.12);
                  final double closeOpacity =
                      (clampedT * 1.35).clamp(0.0, 1.0);

                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (avatarOpacity > 0.001)
                        Opacity(
                          opacity: avatarOpacity,
                          child: Transform.scale(
                            scale: avatarScale,
                            child: Container(
                              width: widget.size,
                              height: widget.size,
                              padding: const EdgeInsets.all(1.2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (active.isChannel || active.isGroupAnon)
                                      ? palette.chatSendButton
                                      : palette.divider,
                                  width: (active.isChannel || active.isGroupAnon)
                                      ? 1.4
                                      : 0.8,
                                ),
                              ),
                              child: AvatarWithStatus(
                                avatarUrl: active.avatarUrl,
                                name: active.name.isNotEmpty ? active.name : '?',
                                radius: (widget.size - 3.0) / 2,
                                isOnline: false,
                                showDecoration: false,
                                animateDecoration: false,
                              ),
                            ),
                          ),
                        ),
                      if (closeOpacity > 0.001)
                        Opacity(
                          opacity: closeOpacity,
                          child: Transform.scale(
                            scale: closeScale,
                            child: Container(
                              width: widget.size,
                              height: widget.size,
                              decoration: BoxDecoration(
                                color: palette.chatSendButton,
                                shape: BoxShape.circle,
                              ),
                              child: CustomPaint(
                                painter: _SenderSelectCloseCrossPainter(
                                  color: Colors.white,
                                  progress: clampedT,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SenderSelectCloseCrossPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _SenderSelectCloseCrossPainter({
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halfSpan = size.shortestSide * 0.175;
    final angle = (1.0 - progress) * (-math.pi / 4);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawLine(
      Offset(-halfSpan, -halfSpan),
      Offset(halfSpan, halfSpan),
      paint,
    );
    canvas.drawLine(
      Offset(halfSpan, -halfSpan),
      Offset(-halfSpan, halfSpan),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SenderSelectCloseCrossPainter oldDelegate) {
    return oldDelegate.color != color ||
        (oldDelegate.progress - progress).abs() > 0.001;
  }
}

/// Backward-compatible alias/wrapper around [InlineSendAsSelectorButton] (`36x36`)
/// so existing callers in chat/comment screens work seamlessly.
class SendAsPeerSelectorPill extends StatelessWidget {
  final List<SendAsPeer> peers;
  final SendAsPeer? selectedPeer;
  final VoidCallback? onTap;
  final ValueChanged<BuildContext>? onOpenPopup;
  final bool isPopupOpen;
  final String? chatId;
  final ValueChanged<SendAsPeer>? onPeerSelected;
  final double size;

  const SendAsPeerSelectorPill({
    super.key,
    required this.peers,
    this.selectedPeer,
    this.onTap,
    this.onOpenPopup,
    this.isPopupOpen = false,
    this.chatId,
    this.onPeerSelected,
    this.size = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return InlineSendAsSelectorButton(
      peers: peers,
      selectedPeer: selectedPeer,
      isPopupOpen: isPopupOpen,
      onTap: onTap,
      onOpenPopup: onOpenPopup,
      chatId: chatId,
      onPeerSelected: onPeerSelected,
      size: size,
    );
  }
}

/// Opens a Telegram-Android-style (`SenderSelectPopup`) anchored floating menu
/// positioned right above the bottom-left of the input bar via a non-route
/// [OverlayEntry] (preserving the active [FocusNode] and soft keyboard) using
/// glass-safe [LiquidGlassLens] (`LiquidGlassBatch.exclude` + pure `Transform.scale`,
/// ZERO `Opacity`, `FadeTransition`, or `ClipRRect` around the glass lens) in
/// Glass mode, or a frosted/elevated card in Material mode.
Future<SendAsPeer?> showSenderSelectPopup(
  BuildContext anchorContext, {
  required String chatId,
  required List<SendAsPeer> peers,
  SendAsPeer? currentPeer,
  String? selectedSendAsChatId,
  String? selectedSendAsMode,
}) async {
  if (peers.isEmpty) return null;
  if (!anchorContext.mounted) return null;

  if (_activeSenderSelectDismiss != null) {
    _activeSenderSelectDismiss!();
  }

  final OverlayState? overlay = Overlay.maybeOf(anchorContext, rootOverlay: true) ??
      Navigator.maybeOf(anchorContext, rootNavigator: true)?.overlay;
  if (overlay == null) return null;

  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;

  Rect? initialAnchorRect;
  if (anchorBox != null &&
      anchorBox.hasSize &&
      overlayBox != null &&
      overlayBox.hasSize) {
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    initialAnchorRect = topLeft & anchorBox.size;
  }

  final SendAsPeer? resolvedCurrent = currentPeer ??
      peers.cast<SendAsPeer?>().firstWhere(
            (p) =>
                p != null &&
                p.matchesSelection(
                  selectedSendAsMode: selectedSendAsMode,
                  selectedSendAsChatId: selectedSendAsChatId,
                ),
            orElse: () =>
                peers.cast<SendAsPeer?>().firstWhere(
                      (p) => p != null && p.isSelected,
                      orElse: () => peers.first,
                    ),
          );

  final CapturedThemes capturedThemes = InheritedTheme.capture(
    from: anchorContext,
    to: overlay.context,
  );
  final ModalRoute<dynamic>? hostRoute = ModalRoute.of(anchorContext);

  final int anchorHash = identityHashCode(anchorContext);
  if (chatId.isNotEmpty) {
    _openSendAsPopupChatCounts[chatId] =
        (_openSendAsPopupChatCounts[chatId] ?? 0) + 1;
    _openSendAsPopupChatIds.value = <String>{
      ..._openSendAsPopupChatIds.value,
      chatId,
    };
  }
  _openSendAsPopupAnchorHashes.value = <int>{
    ..._openSendAsPopupAnchorHashes.value,
    anchorHash,
  };

  final completer = Completer<SendAsPeer?>();
  final GlobalKey<_SenderSelectOverlayHostState> hostKey =
      GlobalKey<_SenderSelectOverlayHostState>();
  late final OverlayEntry entry;
  late final VoidCallback dismissClosure;

  void removeEntryAndComplete(SendAsPeer? result) {
    if (identical(_activeSenderSelectDismiss, dismissClosure)) {
      _activeSenderSelectDismiss = null;
    }
    try {
      entry.remove();
    } catch (_) {}
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  entry = OverlayEntry(
    builder: (overlayBuildContext) => capturedThemes.wrap(
      _SenderSelectOverlayHost(
        key: hostKey,
        anchorContext: anchorContext,
        overlayBox: overlayBox,
        initialAnchorRect: initialAnchorRect,
        hostRoute: hostRoute,
        peers: peers,
        currentPeer: resolvedCurrent,
        onFinished: removeEntryAndComplete,
      ),
    ),
  );

  dismissClosure = () {
    final hostState = hostKey.currentState;
    if (hostState != null) {
      hostState.dismiss(null);
    } else {
      removeEntryAndComplete(null);
    }
  };
  _activeSenderSelectDismiss = dismissClosure;

  overlay.insert(entry);

  SendAsPeer? picked;
  try {
    picked = await completer.future;
  } finally {
    if (identical(_activeSenderSelectDismiss, dismissClosure)) {
      _activeSenderSelectDismiss = null;
    }
    if (chatId.isNotEmpty) {
      final remaining = (_openSendAsPopupChatCounts[chatId] ?? 1) - 1;
      if (remaining <= 0) {
        _openSendAsPopupChatCounts.remove(chatId);
        final nextChats = Set<String>.from(_openSendAsPopupChatIds.value)
          ..remove(chatId);
        _openSendAsPopupChatIds.value = nextChats;
      } else {
        _openSendAsPopupChatCounts[chatId] = remaining;
      }
    }
    final nextAnchors = Set<int>.from(_openSendAsPopupAnchorHashes.value)
      ..remove(anchorHash);
    _openSendAsPopupAnchorHashes.value = nextAnchors;
  }

  if (picked == null) return null;
  final nextSendAsId = picked.isChannel ? (picked.chatId ?? picked.id) : null;
  final ok = await GroupsChannelsParityService.setSendAsPeer(
    chatId,
    nextSendAsId,
    sendAsMode: picked.peerType,
  );
  if (!ok) {
    if (anchorContext.mounted) {
      GlassToastService().showError(
        anchorContext,
        'Не удалось изменить профиль отправки',
      );
    }
    return null;
  }
  return picked;
}

class _SenderSelectPopEntry extends PopEntry<Object?> {
  _SenderSelectPopEntry({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(false);

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) {
      onDismiss();
    }
  }

  void dispose() {
    canPopNotifier.dispose();
  }
}

class _SenderSelectOverlayHost extends StatefulWidget {
  final BuildContext anchorContext;
  final RenderBox? overlayBox;
  final Rect? initialAnchorRect;
  final ModalRoute<dynamic>? hostRoute;
  final List<SendAsPeer> peers;
  final SendAsPeer? currentPeer;
  final ValueChanged<SendAsPeer?> onFinished;

  const _SenderSelectOverlayHost({
    super.key,
    required this.anchorContext,
    required this.overlayBox,
    required this.initialAnchorRect,
    required this.hostRoute,
    required this.peers,
    required this.currentPeer,
    required this.onFinished,
  });

  @override
  State<_SenderSelectOverlayHost> createState() =>
      _SenderSelectOverlayHostState();
}

class _SenderSelectOverlayHostState extends State<_SenderSelectOverlayHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _SenderSelectPopEntry _popEntry;
  bool _dismissStarted = false;
  bool _finishedCalled = false;
  Rect? _anchorRect;

  @override
  void initState() {
    super.initState();
    _anchorRect = widget.initialAnchorRect;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 150),
    )..forward();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _popEntry = _SenderSelectPopEntry(onDismiss: () => dismiss(null));
    widget.hostRoute?.registerPopEntry(_popEntry);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    try {
      widget.hostRoute?.unregisterPopEntry(_popEntry);
    } catch (_) {}
    _popEntry.dispose();
    _controller.dispose();
    if (!_finishedCalled) {
      _finishedCalled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFinished(null);
      });
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      dismiss(null);
      return true;
    }
    return false;
  }

  Future<void> dismiss(SendAsPeer? picked) async {
    if (_dismissStarted) return;
    _dismissStarted = true;
    try {
      widget.hostRoute?.unregisterPopEntry(_popEntry);
    } catch (_) {}
    final bool disableAnim =
        mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (!disableAnim && mounted && _controller.value > 0.0) {
      try {
        await _controller.reverse();
      } catch (_) {}
    }
    if (!_finishedCalled) {
      _finishedCalled = true;
      widget.onFinished(picked);
    }
  }

  Rect? _resolveLiveAnchorRect() {
    final RenderBox? overlayBox =
        (context.findRenderObject() as RenderBox?) ?? widget.overlayBox;
    if (widget.anchorContext.mounted && overlayBox != null && overlayBox.attached && overlayBox.hasSize) {
      final anchorObj = widget.anchorContext.findRenderObject();
      if (anchorObj is RenderBox && anchorObj.attached && anchorObj.hasSize) {
        try {
          final topLeft =
              anchorObj.localToGlobal(Offset.zero, ancestor: overlayBox);
          return topLeft & anchorObj.size;
        } catch (_) {}
      }
    }
    return _anchorRect;
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to viewport metrics so the popup tracks soft keyboard animations cleanly.
    MediaQuery.viewInsetsOf(context);
    final Rect? liveRect = _resolveLiveAnchorRect();
    if (liveRect != null && liveRect != _anchorRect) {
      _anchorRect = liveRect;
    }

    return SwipeBackBlocker(
      child: TextFieldTapRegion(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => dismiss(null),
                child: const SizedBox.expand(),
              ),
            ),
            _SenderSelectPopupLayout(
              anchorRect: _anchorRect,
              peers: widget.peers,
              currentPeer: widget.currentPeer,
              animation: _controller,
              onPeerSelected: (peer) => dismiss(peer),
            ),
          ],
        ),
      ),
    );
  }
}

class _SenderSelectPopupLayout extends StatelessWidget {
  final Rect? anchorRect;
  final List<SendAsPeer> peers;
  final SendAsPeer? currentPeer;
  final Animation<double> animation;
  final ValueChanged<SendAsPeer> onPeerSelected;

  const _SenderSelectPopupLayout({
    required this.anchorRect,
    required this.peers,
    required this.currentPeer,
    required this.animation,
    required this.onPeerSelected,
  });

  bool _isPeerSelected(SendAsPeer peer) {
    final cur = currentPeer;
    if (cur == null) return peer.isSelected;
    if (cur.peerType != peer.peerType) return false;
    if (peer.isChannel) {
      return (peer.chatId ?? peer.id) == (cur.chatId ?? cur.id);
    }
    return true;
  }

  String _subtitleForPeer(BuildContext context, SendAsPeer peer) {
    if (peer.isUser) {
      return _trSendAs(context, 'send_as_personal_account', 'Личный аккаунт');
    }
    if (peer.isGroupAnon) {
      return _trSendAs(
        context,
        'send_as_anonymous_admin',
        'Анонимный администратор',
      );
    }
    final subs = peer.subscriberCount;
    if (subs != null && subs > 0) {
      return _formatSendAsSubscribers(context, subs);
    }
    if (peer.username.isNotEmpty) {
      return '@${peer.username}';
    }
    return _trSendAs(context, 'send_as_public_channel', 'Публичный канал');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        final double screenW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mq.size.width;
        final double screenH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mq.size.height;

        final double maxPopupWidth =
            math.max(180.0, math.min(320.0, screenW * 0.78));
        final double minPopupWidth = math.min(260.0, maxPopupWidth);

        // Anchor right above the bottom-left of the input bar.
        double left = 10.0;
        double bottomOffset = mq.viewInsets.bottom + mq.padding.bottom + 62.0;
        final Rect? rect = anchorRect;
        if (rect != null && rect.height <= 120.0) {
          left = (rect.left - 4.0)
              .clamp(8.0, math.max(8.0, screenW - maxPopupWidth - 8.0));
          bottomOffset = (screenH - rect.top + 10.0).clamp(
            mq.viewInsets.bottom + 12.0,
            math.max(mq.viewInsets.bottom + 12.0, screenH - mq.padding.top - 140.0),
          );
        }

        final double availAbove =
            screenH - bottomOffset - mq.padding.top - 12.0;
        final double maxPopupHeight =
            math.min(380.0, math.max(160.0, availAbove));

        final style = TheavSurfaceStyle.of(context);
        final palette = style.palette;
        final bool isGlass = style.isGlass && style.glassProvider != null;

        final Widget innerBody = ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            type: MaterialType.transparency,
            child: ScrollConfiguration(
              behavior:
                  const MaterialScrollBehavior().copyWith(overscroll: false),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 6),
                    child: Text(
                      _trSendAs(
                        context,
                        'send_message_as_title',
                        'Отправить сообщение от имени...',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.primary,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final peer in peers)
                            _SenderSelectPeerRow(
                              key: ValueKey(
                                'sender_select_peer_${peer.peerType}_${peer.chatId ?? peer.id}',
                              ),
                              peer: peer,
                              selected: _isPeerSelected(peer),
                              subtitle: _subtitleForPeer(context, peer),
                              onTap: () {
                                HapticUtils.selection();
                                onPeerSelected(peer);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        Widget surface;
        if (isGlass) {
          final glassStyle = style.glassProvider!.createStyle(
            context: context,
            cornerRadius: 20.0,
            refractionIndex: 1.10,
            refractionWidth: 18.0,
            borderWidth: 1.1,
            color: style.hudFill.withValues(
              alpha: style.isDark ? 0.76 : 0.84,
            ),
          );
          surface = LiquidGlassBatch.exclude(
            child: LiquidGlassLens(
              style: glassStyle,
              child: innerBody,
            ),
          );
        } else {
          final blurFilter = style.getMaterialHudBlurFilter(sigma: 12.0);
          final Color cardBg = blurFilter != null
              ? BlurUtils.resolveMaterialHudColor(
                  style.overlayFill,
                  isDark: style.isDark,
                  blurEnabled: true,
                  darkAlpha: 0.88,
                  lightAlpha: 0.92,
                )
              : style.overlayFill;
          Widget materialBox = DecoratedBox(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: style.hudBorder,
                width: blurFilter != null ? 0.6 : 0.5,
              ),
              boxShadow: style.floatingShadow,
            ),
            child: innerBody,
          );
          if (blurFilter != null) {
            materialBox = ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter.grouped(
                filter: blurFilter,
                child: materialBox,
              ),
            );
          }
          surface = materialBox;
        }

        final bool disableAnim =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;

        return Stack(
          key: const ValueKey('sender_select_popup_overlay'),
          children: [
            Positioned(
              left: left,
              bottom: bottomOffset,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minPopupWidth,
                  maxWidth: maxPopupWidth,
                  maxHeight: maxPopupHeight,
                ),
                child: disableAnim
                    ? surface
                    : AnimatedBuilder(
                        animation: animation,
                        child: surface,
                        builder: (context, popupChild) {
                          final raw = animation.value;
                          if (raw <= 0.001) {
                            return const SizedBox.shrink();
                          }
                          final bool reversing =
                              animation.status == AnimationStatus.reverse;
                          final double scale = reversing
                              ? Curves.easeInCubic.transform(raw.clamp(0.0, 1.0))
                              : Curves.easeOutBack
                                  .transform(raw.clamp(0.0, 1.0));
                          final Widget scaled = Transform.scale(
                            scale: math.max(0.01, scale),
                            alignment: Alignment.bottomLeft,
                            child: popupChild,
                          );
                          // NEVER wrap LiquidGlassLens in Opacity or FadeTransition!
                          if (isGlass) {
                            return scaled;
                          }
                          final double op = Curves.easeOutCubic
                              .transform(raw.clamp(0.0, 1.0))
                              .clamp(0.0, 1.0);
                          return Opacity(
                            opacity: op,
                            child: scaled,
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SenderSelectPeerRow extends StatelessWidget {
  final SendAsPeer peer;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;

  const _SenderSelectPeerRow({
    super.key,
    required this.peer,
    required this.selected,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return InkWell(
      canRequestFocus: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: 42,
                    height: 42,
                    padding: EdgeInsets.all(selected ? 2.5 : 1.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? palette.primary : Colors.transparent,
                        width: selected ? 2.0 : 0.0,
                      ),
                    ),
                    child: AvatarWithStatus(
                      avatarUrl: peer.avatarUrl,
                      name: peer.name.isNotEmpty ? peer.name : '?',
                      radius: selected ? 16.5 : 20.0,
                      isOnline: false,
                      showDecoration: false,
                      animateDecoration: false,
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: AnimatedScale(
                      scale: selected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.surface,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: iconoir.Check(
                          width: 10,
                          height: 10,
                          color: palette.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          peer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.onSurface,
                            fontSize: 15.0,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (peer.isVerified) ...[
                        const SizedBox(width: 4),
                        const PeerBadgesRow(isVerified: true, iconSize: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? palette.primary : palette.subtext,
                      fontSize: 12.5,
                      height: 1.2,
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

/// Opens a Telegram-style anchored popup (delegating to [showSenderSelectPopup]
/// using the active inline button anchor when available) to pick the posting
/// identity ("Send As") for a group or channel comment thread.
Future<SendAsPeer?> showSendAsPeerSheet({
  required BuildContext context,
  required String chatId,
  required List<SendAsPeer> peers,
  String? selectedSendAsChatId,
  String? selectedSendAsMode,
  SendAsPeer? currentPeer,
}) {
  BuildContext effectiveAnchor = context;
  final registered = _registeredSendAsAnchors[chatId];
  if (registered != null && registered.mounted) {
    effectiveAnchor = registered;
  } else if (_lastTappedSendAsAnchor != null &&
      _lastTappedSendAsAnchor!.mounted) {
    effectiveAnchor = _lastTappedSendAsAnchor!;
  }
  return showSenderSelectPopup(
    effectiveAnchor,
    chatId: chatId,
    peers: peers,
    currentPeer: currentPeer,
    selectedSendAsChatId: selectedSendAsChatId,
    selectedSendAsMode: selectedSendAsMode,
  );
}

/// Stacked circular `@` (unread mentions/replies) and `♡` (unread reactions)
/// jump FABs positioned above the scroll-to-bottom FAB in group chats.
class UnreadJumpFabsColumn extends StatelessWidget {
  final int unreadMentionsCount;
  final int unreadReactionsCount;
  final VoidCallback? onMentionsTap;
  final VoidCallback? onMentionsLongPress;
  final VoidCallback? onReactionsTap;
  final VoidCallback? onReactionsLongPress;

  const UnreadJumpFabsColumn({
    super.key,
    required this.unreadMentionsCount,
    required this.unreadReactionsCount,
    this.onMentionsTap,
    this.onMentionsLongPress,
    this.onReactionsTap,
    this.onReactionsLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (unreadMentionsCount <= 0 && unreadReactionsCount <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unreadReactionsCount > 0) ...[
          _UnreadJumpFab(
            key: const ValueKey('unread_reactions_fab'),
            count: unreadReactionsCount,
            onTap: onReactionsTap,
            onLongPress: onReactionsLongPress,
            tooltip: 'Перейти к реакции (удерживайте чтобы прочитать все)',
            iconBuilder: (color) => iconoir.Heart(
              width: 20,
              height: 20,
              color: color,
            ),
          ),
          if (unreadMentionsCount > 0) const SizedBox(height: 10),
        ],
        if (unreadMentionsCount > 0)
          _UnreadJumpFab(
            key: const ValueKey('unread_mentions_fab'),
            count: unreadMentionsCount,
            onTap: onMentionsTap,
            onLongPress: onMentionsLongPress,
            tooltip: 'Перейти к упоминанию (удерживайте чтобы прочитать все)',
            iconBuilder: (color) => iconoir.AtSign(
              width: 20,
              height: 20,
              color: color,
            ),
          ),
      ],
    );
  }
}

class _UnreadJumpFab extends StatelessWidget {
  final int count;
  final Widget Function(Color color) iconBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String tooltip;

  const _UnreadJumpFab({
    super.key,
    required this.count,
    required this.iconBuilder,
    this.onTap,
    this.onLongPress,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: TheavFloatingSurface(
              borderRadius: 23,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(23),
                  onTap: () {
                    HapticUtils.selection();
                    onTap?.call();
                  },
                  onLongPress: () {
                    HapticUtils.impact();
                    onLongPress?.call();
                  },
                  child: Center(
                    child: iconBuilder(palette.primary),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -5,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: palette.surface, width: 1.5),
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    color: palette.onPrimary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal topic switcher strip inside a Forum topic screen.
class ForumTopicChipStrip extends StatelessWidget {
  final List<ForumTopic> topics;
  final int activeTopicId;
  final ValueChanged<ForumTopic> onSelectTopic;
  final VoidCallback? onViewAllTopics;

  const ForumTopicChipStrip({
    super.key,
    required this.topics,
    required this.activeTopicId,
    required this.onSelectTopic,
    this.onViewAllTopics,
  });

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();
    final palette = context.theav;

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: topics.length + (onViewAllTopics != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (onViewAllTopics != null && index == topics.length) {
            return TheavFloatingPillButton(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              label: 'Все темы',
              onTap: onViewAllTopics,
            );
          }
          final topic = topics[index];
          final selected = topic.id == activeTopicId;
          final badgeColor = Color(topic.iconColor | 0xFF000000);
          return GestureDetector(
            onTap: () {
              HapticUtils.selection();
              onSelectTopic(topic);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? palette.primary.withValues(alpha: 0.16)
                    : palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? palette.primary : palette.divider,
                  width: selected ? 1.0 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (topic.iconEmoji != null && topic.iconEmoji!.isNotEmpty)
                    Text(topic.iconEmoji!, style: const TextStyle(fontSize: 13))
                  else
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '#',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      topic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? palette.primary : palette.onSurface,
                      ),
                    ),
                  ),
                  if (topic.unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.unreadBadge,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${topic.unreadCount}',
                        style: TextStyle(
                          color: palette.unreadBadgeText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Modal sheet displaying public channels similar to [chatId] with quick subscribe/open.
Future<void> showSimilarChannelsSheet({
  required BuildContext context,
  required String chatId,
  ValueChanged<SimilarChannelItem>? onOpenChannel,
}) async {
  await showTheavModalSheet<void>(
    context: context,
    title: 'Похожие каналы',
    builder: (ctx) => _SimilarChannelsSheetBody(
      chatId: chatId,
      onOpenChannel: onOpenChannel,
    ),
  );
}

class _SimilarChannelsSheetBody extends StatefulWidget {
  final String chatId;
  final ValueChanged<SimilarChannelItem>? onOpenChannel;

  const _SimilarChannelsSheetBody({
    required this.chatId,
    this.onOpenChannel,
  });

  @override
  State<_SimilarChannelsSheetBody> createState() =>
      _SimilarChannelsSheetBodyState();
}

class _SimilarChannelsSheetBodyState extends State<_SimilarChannelsSheetBody> {
  List<SimilarChannelItem> _channels = [];
  final Set<String> _joiningIds = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await GroupsChannelsParityService.getSimilarChannels(
      widget.chatId,
      limit: 25,
    );
    if (!mounted) return;
    setState(() {
      _channels = items;
      _loading = false;
    });
  }

  Future<void> _joinOrOpen(SimilarChannelItem item) async {
    if (item.isMember) {
      Navigator.pop(context);
      widget.onOpenChannel?.call(item);
      return;
    }
    if (_joiningIds.contains(item.id)) return;
    setState(() => _joiningIds.add(item.id));
    final res = await ChatService.joinPublicChat(item.id);
    if (!mounted) return;
    setState(() => _joiningIds.remove(item.id));
    if (res['success'] == true) {
      final idx = _channels.indexWhere((c) => c.id == item.id);
      if (idx != -1) {
        setState(() {
          _channels[idx] = _channels[idx].copyWith(
            isMember: true,
            subscriberCount: _channels[idx].subscriberCount + 1,
          );
        });
      }
      GlassToastService().show(context, 'Вы подписались на «${item.name}»');
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось подписаться',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }
    if (_channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Megaphone(width: 36, height: 36, color: palette.subtext),
            const SizedBox(height: 12),
            Text(
              'Похожих каналов пока не найдено',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Рекомендации формируются автоматически по пересечению аудитории публичных каналов.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.subtext, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      child: TheavInsetGroup(
        children: [
          for (final ch in _channels)
            TheavListRow(
              leading: AvatarWithStatus(
                avatarUrl: ch.avatarUrl,
                name: ch.name,
                radius: 22,
                isOnline: false,
                showDecoration: false,
              ),
              titleWidget: Row(
                children: [
                  Flexible(
                    child: Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (ch.isVerified) ...[
                    const SizedBox(width: 5),
                    const PeerBadgesRow(isVerified: true, iconSize: 14),
                  ],
                ],
              ),
              subtitle:
                  '${ch.subscriberCount} подп.${ch.username.isNotEmpty ? ' · @${ch.username}' : ''}',
              trailing: TheavFloatingPillButton(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                isPrimary: !ch.isMember,
                enabled: !_joiningIds.contains(ch.id),
                label: ch.isMember ? 'Открыть' : 'Подписаться',
                onTap: () => _joinOrOpen(ch),
              ),
              onTap: widget.onOpenChannel != null
                  ? () {
                      Navigator.pop(context);
                      widget.onOpenChannel!(ch);
                    }
                  : () => _joinOrOpen(ch),
            ),
        ],
      ),
    );
  }
}

/// Paginated sheet showing members who joined via [linkItem].
Future<void> showInviteLinkImportersSheet({
  required BuildContext context,
  required String chatId,
  required InviteLinkItem linkItem,
}) async {
  final title = linkItem.title.trim().isNotEmpty
      ? 'Перешли: ${linkItem.title}'
      : 'Приглашённые по ссылке';
  await showTheavModalSheet<void>(
    context: context,
    title: title,
    builder: (ctx) => _InviteLinkImportersBody(
      chatId: chatId,
      linkItem: linkItem,
    ),
  );
}

class _InviteLinkImportersBody extends StatefulWidget {
  final String chatId;
  final InviteLinkItem linkItem;

  const _InviteLinkImportersBody({
    required this.chatId,
    required this.linkItem,
  });

  @override
  State<_InviteLinkImportersBody> createState() =>
      _InviteLinkImportersBodyState();
}

class _InviteLinkImportersBodyState extends State<_InviteLinkImportersBody> {
  final List<InviteLinkImporter> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    if (reset) {
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }
    final res = await GroupsChannelsParityService.getInviteLinkImporters(
      widget.chatId,
      widget.linkItem.id,
      limit: 50,
      offset: reset ? 0 : _items.length,
    );
    if (!mounted) return;
    setState(() {
      if (reset) _items.clear();
      _items.addAll(res.importers);
      _total = res.total;
      _hasMore = res.hasMore;
      _loading = false;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
        child: Text(
          'По этой ссылке пока никто не присоединился.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.subtext, fontSize: 14),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TheavInsetGroup(
            header: 'ВСТУПИЛО: $_total',
            children: [
              for (final imp in _items)
                TheavListRow(
                  leading: AvatarWithStatus(
                    userId: imp.userId,
                    avatarUrl: imp.avatarUrl,
                    name: imp.displayName.isNotEmpty
                        ? imp.displayName
                        : '@${imp.username}',
                    radius: 20,
                    isOnline: false,
                  ),
                  title: imp.displayName.isNotEmpty
                      ? imp.displayName
                      : '@${imp.username}',
                  subtitle: [
                    if (imp.username.isNotEmpty) '@${imp.username}',
                    if (imp.joinedAt != null)
                      DateTimeUtils.formatTimeHHmm(imp.joinedAt),
                  ].join(' · '),
                  trailing: imp.viaJoinRequest
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: palette.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'По заявке',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TheavFloatingPillButton(
                label: _loadingMore ? 'Загрузка...' : 'Загрузить ещё',
                enabled: !_loadingMore,
                onTap: () => _load(reset: false),
              ),
            ),
        ],
      ),
    );
  }
}

/// CustomPainter chart rendering daily joined vs left subscriber series for
/// [ChannelStatsScreen] without external charting dependencies.
class ChannelGrowthChart extends StatelessWidget {
  final List<ChannelDailyGrowthPoint> points;
  final double height;

  const ChannelGrowthChart({
    super.key,
    required this.points,
    this.height = 176,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    if (points.isEmpty) {
      return SizedBox(
        height: 96,
        child: Center(
          child: Text(
            'Недостаточно данных за период',
            style: TextStyle(color: palette.subtext, fontSize: 13),
          ),
        ),
      );
    }

    const joinedColor = Color(0xFF34C759);
    const leftColor = Color(0xFFFF453A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _legendDot(joinedColor, 'Присоединились', palette.subtext),
              const SizedBox(width: 16),
              _legendDot(leftColor, 'Покинули', palette.subtext),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _ChannelGrowthPainter(
                points: points,
                joinedColor: joinedColor,
                leftColor: leftColor,
                gridColor: palette.divider,
                labelColor: palette.subtext,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortDate(points.first.date),
                style: TextStyle(fontSize: 11, color: palette.subtext),
              ),
              if (points.length > 2)
                Text(
                  _shortDate(points[points.length ~/ 2].date),
                  style: TextStyle(fontSize: 11, color: palette.subtext),
                ),
              Text(
                _shortDate(points.last.date),
                style: TextStyle(fontSize: 11, color: palette.subtext),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    if (iso.length >= 10) {
      return '${iso.substring(8, 10)}.${iso.substring(5, 7)}';
    }
    return iso;
  }

  Widget _legendDot(Color c, String label, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ChannelGrowthPainter extends CustomPainter {
  final List<ChannelDailyGrowthPoint> points;
  final Color joinedColor;
  final Color leftColor;
  final Color gridColor;
  final Color labelColor;

  _ChannelGrowthPainter({
    required this.points,
    required this.joinedColor,
    required this.leftColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    int maxVal = 1;
    for (final p in points) {
      maxVal = math.max(maxVal, math.max(p.joined, p.left));
    }

    const leftPad = 26.0;
    const topPad = 8.0;
    const bottomPad = 8.0;
    final chartW = (size.width - leftPad - 6).clamp(1.0, size.width);
    final chartH = (size.height - topPad - bottomPad).clamp(1.0, size.height);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.6;

    for (int step = 0; step <= 2; step++) {
      final frac = step / 2.0;
      final y = topPad + chartH * (1.0 - frac);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
      final val = (maxVal * frac).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$val',
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    void drawSeries(List<int> values, Color color) {
      final path = Path();
      final fillPath = Path();
      final n = values.length;
      final stepX = n > 1 ? chartW / (n - 1) : 0.0;
      final offsets = <Offset>[];

      for (int i = 0; i < n; i++) {
        final x = n == 1 ? leftPad + chartW / 2 : leftPad + i * stepX;
        final y = topPad + chartH * (1.0 - (values[i] / maxVal));
        offsets.add(Offset(x, y));
      }

      if (offsets.length == 1) {
        canvas.drawCircle(offsets.first, 4.0, Paint()..color = color);
        return;
      }

      path.moveTo(offsets.first.dx, offsets.first.dy);
      fillPath.moveTo(offsets.first.dx, topPad + chartH);
      fillPath.lineTo(offsets.first.dx, offsets.first.dy);

      for (int i = 0; i < offsets.length - 1; i++) {
        final p0 = offsets[i];
        final p1 = offsets[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
        fillPath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }

      fillPath.lineTo(offsets.last.dx, topPad + chartH);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.01),
            ],
          ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
      );

      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    drawSeries(points.map((e) => e.left).toList(), leftColor);
    drawSeries(points.map((e) => e.joined).toList(), joinedColor);
  }

  @override
  bool shouldRepaint(covariant _ChannelGrowthPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.joinedColor != joinedColor ||
      oldDelegate.leftColor != leftColor;
}
