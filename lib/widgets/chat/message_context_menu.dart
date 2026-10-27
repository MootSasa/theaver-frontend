import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/glass_toast_service.dart';
import '../../services/message_context_menu_service.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../theme/viewport_gradient_box.dart';
import '../tiling/static_tile_cache_boundary.dart';

class MessageContextMenu extends StatefulWidget {
  /// Color matrix that unpremultiplies any partially-transparent edge samples
  /// produced by [ui.ImageFilter.blur] (when a tile or route subpass is
  /// surrounded by transparent pixels in the GPU texture) and forces the
  /// output alpha to `1.0` (`255`).
  ///
  /// Because [BackdropFilter] composites its blurred result over the unblurred
  /// canvas with [BlendMode.srcOver]:
  /// `Final = BlurredPremul + (1 - alpha_blur) * UnblurredCanvas`
  /// any pixel with `alpha_blur < 1.0` within `3 * sigma` of the left/right
  /// chat edges would otherwise let `(1 - alpha_blur)` of the sharp unblurred
  /// chat bleed straight through, making the blur appear weaker near the edges.
  static const ui.ColorFilter _kOpaqueBlurAlphaNormalizeFilter =
      ui.ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 0, 255,
  ]);

  /// Builds an opaque Gaussian blur [ui.ImageFilter] that normalizes edge
  /// alpha on desktop so [BackdropFilter] never blends sharp unblurred
  /// background pixels at the left/right edges of a chat or tile, while
  /// returning a standalone [ui.ImageFilter.blur] on mobile (Android / iOS) so
  /// Impeller's hardware bilinear upsampling (`MinMagFilter::kLinear`) is
  /// preserved.
  static ui.ImageFilter buildOpaqueBackdropBlurFilter(double sigma) {
    final blurFilter = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.mirror,
    );
    final bool isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) {
      return blurFilter;
    }
    return ui.ImageFilter.compose(
      outer: _kOpaqueBlurAlphaNormalizeFilter,
      inner: blurFilter,
    );
  }

  final Offset messageOffset;
  final Size messageSize;
  final bool isMe;
  final int? sendStatus;
  final GlobalKey? messageKey;
  final String? activeBlurMessageId;
  final String messageContent;
  final Widget Function(GlobalKey focusedKey)? focusedMessageBuilder;
  final bool enableBlur;
  final Offset? initialDragStartGlobalPosition;
  final Offset? initialDragCurrentGlobalPosition;
  final VoidCallback onReply;
  final VoidCallback? onQuote;
  final void Function(String selectedText, int offset, int length)? onQuotePartial;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback? onEdit;
  final VoidCallback? onSelect;
  final VoidCallback? onViewPollResults;
  final VoidCallback? onRetractVote;
  final VoidCallback? onStopPoll;
  final VoidCallback onDelete;
  final Function(String emoji) onReaction;
  final Set<String> selectedEmojis;

  const MessageContextMenu({
    Key? key,
    required this.messageOffset,
    required this.messageSize,
    required this.isMe,
    this.sendStatus,
    this.messageKey,
    this.activeBlurMessageId,
    this.messageContent = '',
    this.focusedMessageBuilder,
    this.enableBlur = true,
    this.initialDragStartGlobalPosition,
    this.initialDragCurrentGlobalPosition,
    required this.onReply,
    this.onQuote,
    this.onQuotePartial,
    required this.onCopy,
    required this.onPin,
    this.onEdit,
    this.onSelect,
    this.onViewPollResults,
    this.onRetractVote,
    this.onStopPoll,
    required this.onDelete,
    required this.onReaction,
    this.selectedEmojis = const {},
  }) : super(key: key);

  @override
  State<MessageContextMenu> createState() => MessageContextMenuState();
}

enum _MessageHandleDragMode {
  none,
  newRange,
  leftHandle,
  rightHandle,
}

class MessageContextMenuState extends State<MessageContextMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final GlobalKey _focusedBubbleKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  Rect? _originGradientBounds;
  VoidCallback? _releaseBackdropIsolation;

  bool _isDismissing = false;

  // Text selection state within the focused message
  RenderParagraph? _activeParagraph;
  TextSelection _selection = const TextSelection.collapsed(offset: -1);
  _MessageHandleDragMode _dragMode = _MessageHandleDragMode.none;

  // External LMB drag selection state (initiated directly from chat screen on PC/Web)
  bool _isExternalDragging = false;
  Offset? _pendingExternalStartPos;
  Offset? _pendingExternalCurrentPos;
  int? _externalBaseOffset;

  static const double _kHandleSize = 26.0;
  static const Color _kMintAccent = Color(0xFF7BE5DA);

  bool get _hasActiveSelection =>
      _selection.isValid && !_selection.isCollapsed && _activeParagraph != null;

  @override
  void initState() {
    super.initState();
    _originGradientBounds = ViewportGradientBoundsScope.resolveFromRenderObject(
      widget.messageKey?.currentContext?.findRenderObject(),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    if (widget.initialDragStartGlobalPosition != null) {
      _isExternalDragging = true;
      _pendingExternalStartPos = widget.initialDragStartGlobalPosition;
      _pendingExternalCurrentPos =
          MessageContextMenuService().pendingExternalCurrentPos ??
              widget.initialDragCurrentGlobalPosition ??
              widget.initialDragStartGlobalPosition;
      _applyPendingExternalDrag(allowWithoutSetState: true);
    }

    // Wait until after Frame 0 has laid out and painted the focused message at
    // 100% opacity directly over the in-list message (with sigma == 0.0) before
    // hiding the in-list message and starting the blur animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDismissing) return;
      if (widget.activeBlurMessageId != null) {
        MessageContextMenuService().activeBlurMessageId.value =
            widget.activeBlurMessageId;
      }
      _controller.forward();

      if (widget.initialDragStartGlobalPosition != null) {
        final service = MessageContextMenuService();
        if (service.pendingExternalCurrentPos != null) {
          _pendingExternalCurrentPos = service.pendingExternalCurrentPos;
        }
        _applyPendingExternalDrag();
        if (!service.isExternalDragActive) {
          endExternalDrag();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.enableBlur) {
      _releaseBackdropIsolation ??=
          StaticTileCacheBoundary.acquireLiveBackdropIsolation(context);
    }
  }

  void updateExternalDrag(Offset globalPosition) {
    if (!mounted || _isDismissing) return;
    _isExternalDragging = true;
    _pendingExternalCurrentPos = globalPosition;
    _applyPendingExternalDrag();
  }

  void endExternalDrag() {
    if (!mounted || _isDismissing) return;
    _applyPendingExternalDrag();
    _isExternalDragging = false;
    _dragMode = _MessageHandleDragMode.none;

    // If the user dragged across a single character/word where baseOffset == extentOffset,
    // expand to the word at that position so direct LMB selection always succeeds.
    if (!_hasActiveSelection &&
        _activeParagraph != null &&
        _externalBaseOffset != null) {
      final p = _activeParagraph!;
      final plain = p.text.toPlainText();
      if (plain.trim().isNotEmpty) {
        final wordRange = p.getWordBoundary(
          TextPosition(offset: _externalBaseOffset!.clamp(0, plain.length)),
        );
        int start = wordRange.start.clamp(0, plain.length);
        int end = wordRange.end.clamp(start, plain.length);
        while (start < end && plain[start].trim().isEmpty) {
          start++;
        }
        while (end > start && plain[end - 1].trim().isEmpty) {
          end--;
        }
        if (start < end) {
          _selection = TextSelection(baseOffset: start, extentOffset: end);
        }
      }
    }

    if (!_hasActiveSelection) {
      _handleDismiss();
    } else {
      HapticUtils.selection();
      setState(() {});
    }
  }

  void _applyPendingExternalDrag({bool allowWithoutSetState = false}) {
    if (!mounted || _isDismissing) return;
    final focusedParagraph = _focusedBubbleKey.currentContext != null
        ? _resolveParagraphForGlobalOffset(_pendingExternalStartPos ?? Offset.zero)
        : null;
    if (focusedParagraph != null && _activeParagraph != focusedParagraph) {
      if (_externalBaseOffset == null && _pendingExternalStartPos != null) {
        final plainLen = focusedParagraph.text.toPlainText().length;
        if (plainLen > 0) {
          final localStart = focusedParagraph.globalToLocal(_pendingExternalStartPos!);
          final posStart = focusedParagraph.getPositionForOffset(localStart);
          _externalBaseOffset = posStart.offset.clamp(0, plainLen);
        }
      }
      _activeParagraph = focusedParagraph;
      _dragMode = _MessageHandleDragMode.newRange;
    } else if (_activeParagraph == null && _pendingExternalStartPos != null) {
      final p = _resolveParagraphForGlobalOffset(_pendingExternalStartPos!);
      if (p != null && p.hasSize) {
        final plainLen = p.text.toPlainText().length;
        if (plainLen > 0) {
          final localStart = p.globalToLocal(_pendingExternalStartPos!);
          final posStart = p.getPositionForOffset(localStart);
          _activeParagraph = p;
          _externalBaseOffset = posStart.offset.clamp(0, plainLen);
          _dragMode = _MessageHandleDragMode.newRange;
        }
      }
    }

    final p = _activeParagraph;
    final baseOffset = _externalBaseOffset;
    final currentPos = _pendingExternalCurrentPos;
    if (p == null || !p.hasSize || !p.attached || baseOffset == null || currentPos == null) {
      return;
    }

    final plainLen = p.text.toPlainText().length;
    if (plainLen == 0) return;

    final localCurrent = p.globalToLocal(currentPos);
    final posCurrent = p.getPositionForOffset(localCurrent);
    final extentOffset = posCurrent.offset.clamp(0, plainLen);

    final nextSelection = TextSelection(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
    );
    if (allowWithoutSetState) {
      _selection = nextSelection;
    } else if (_selection != nextSelection) {
      setState(() {
        _selection = nextSelection;
      });
    }
  }

  @override
  void dispose() {
    _releaseBackdropIsolation?.call();
    _releaseBackdropIsolation = null;
    MessageContextMenuService().clearActiveBlurMessage();
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss([VoidCallback? onDismissed]) {
    if (_isDismissing) return;
    _isDismissing = true;
    _controller.reverse().then((_) {
      // Un-hide the in-list message while the focused message is still covering
      // it at sigma == 0.0, then remove the overlay on the next frame so there is zero blink.
      MessageContextMenuService().clearActiveBlurMessage();
      if (!mounted) {
        MessageContextMenuService().removeActiveOverlay();
        onDismissed?.call();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (MessageContextMenuService().hasActiveOverlay) {
          MessageContextMenuService().removeActiveOverlay();
        } else if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        onDismissed?.call();
      });
    });
  }

  void _clearSelection() {
    if (!_hasActiveSelection) return;
    setState(() {
      _selection = const TextSelection.collapsed(offset: -1);
      _dragMode = _MessageHandleDragMode.none;
    });
  }

  /// Finds all selectable [RenderParagraph]s belonging to the message body
  /// (tagged with `MetaData('message_selectable_content')` or fallback paragraphs).
  List<RenderParagraph> _findSelectableParagraphs() {
    final focusedObj = _focusedBubbleKey.currentContext?.findRenderObject();
    final origObj = widget.messageKey?.currentContext?.findRenderObject();
    final rootObj = (focusedObj is RenderBox && focusedObj.hasSize && focusedObj.attached)
        ? focusedObj
        : origObj;
    if (rootObj == null || !rootObj.attached) return const [];

    final taggedParagraphs = <RenderParagraph>[];
    final allParagraphs = <RenderParagraph>[];

    void collectParagraphs(RenderObject node, bool insideSelectableTag) {
      bool tagged = insideSelectableTag;
      if (node is RenderMetaData &&
          node.metaData == 'message_selectable_content') {
        tagged = true;
      }
      if (node is RenderParagraph) {
        final plain = node.text.toPlainText();
        if (plain.trim().isNotEmpty) {
          allParagraphs.add(node);
          if (tagged) {
            taggedParagraphs.add(node);
          }
        }
        return;
      }
      node.visitChildren((child) => collectParagraphs(child, tagged));
    }

    collectParagraphs(rootObj, false);
    return taggedParagraphs.isNotEmpty ? taggedParagraphs : allParagraphs;
  }

  RenderParagraph? _resolveParagraphForGlobalOffset(Offset globalPos) {
    final paragraphs = _findSelectableParagraphs();
    if (paragraphs.isEmpty) return null;
    if (paragraphs.length == 1) return paragraphs.first;

    RenderParagraph? best;
    double bestDist = double.infinity;
    for (final p in paragraphs) {
      if (!p.hasSize) continue;
      final local = p.globalToLocal(globalPos);
      final rect = Offset.zero & p.size;
      if (rect.inflate(8.0).contains(local)) {
        return p;
      }
      final dy = local.dy < 0
          ? -local.dy
          : (local.dy > rect.height ? local.dy - rect.height : 0.0);
      if (dy < bestDist) {
        bestDist = dy;
        best = p;
      }
    }
    return best ?? paragraphs.first;
  }

  List<Rect> _getSelectionRectsInStack(RenderBox? stackBox) {
    final p = _activeParagraph;
    if (p == null || !p.hasSize || !p.attached || !_selection.isValid || _selection.isCollapsed) {
      return const [];
    }
    final plainLen = p.text.toPlainText().length;
    final start = math.min(_selection.start, _selection.end).clamp(0, plainLen);
    final end = math.max(_selection.start, _selection.end).clamp(start, plainLen);
    if (start >= end) return const [];

    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
    );
    final rects = <Rect>[];
    for (final box in boxes) {
      final r = box.toRect();
      if (r.width <= 0 || r.height <= 0) continue;
      final globalTopLeft = p.localToGlobal(r.topLeft);
      final stackTopLeft = stackBox != null
          ? stackBox.globalToLocal(globalTopLeft)
          : globalTopLeft;
      rects.add(Rect.fromLTWH(stackTopLeft.dx, stackTopLeft.dy, r.width, r.height));
    }
    return rects;
  }

  double? _liveFocusedHeight;

  bool _isGlobalPointInsideFocusedBubble(Offset globalPosition) {
    final rootRender = _focusedBubbleKey.currentContext?.findRenderObject();
    if (rootRender == null || !rootRender.attached) {
      final fallbackRect = Rect.fromLTWH(
        widget.messageOffset.dx,
        widget.messageOffset.dy,
        widget.messageSize.width,
        _liveFocusedHeight ?? widget.messageSize.height,
      );
      return fallbackRect.contains(globalPosition);
    }

    bool foundBubbleMeta = false;
    bool hitInsideBubble = false;

    void visit(RenderObject node) {
      if (hitInsideBubble) return;
      if (node is RenderMetaData && node.metaData == 'message_bubble_box') {
        foundBubbleMeta = true;
        if (node.hasSize && node.attached) {
          try {
            final local = node.globalToLocal(globalPosition);
            if (local.dx >= 0.0 &&
                local.dy >= 0.0 &&
                local.dx <= node.size.width &&
                local.dy <= node.size.height) {
              hitInsideBubble = true;
              return;
            }
          } catch (_) {}
        }
      }
      node.visitChildren(visit);
    }

    visit(rootRender);
    if (foundBubbleMeta) {
      return hitInsideBubble;
    }

    if (rootRender is RenderBox && rootRender.hasSize) {
      try {
        final local = rootRender.globalToLocal(globalPosition);
        return (Offset.zero & rootRender.size).contains(local);
      } catch (_) {}
    }
    return false;
  }

  Rect _resolveVisualBubbleRect(BuildContext layoutContext) {
    final RenderBox? layoutBox =
        layoutContext.findRenderObject() as RenderBox?;
    final List<RenderObject?> candidateRoots = <RenderObject?>[
      _focusedBubbleKey.currentContext?.findRenderObject(),
      widget.messageKey?.currentContext?.findRenderObject(),
    ];

    for (final root in candidateRoots) {
      if (root == null || !root.attached) continue;
      Rect? foundRect;
      void visit(RenderObject node) {
        if (foundRect != null) return;
        if (node is RenderMetaData && node.metaData == 'message_bubble_box') {
          if (node.hasSize && node.attached) {
            try {
              final Offset topLeft = layoutBox != null && layoutBox.attached
                  ? node.localToGlobal(Offset.zero, ancestor: layoutBox)
                  : node.localToGlobal(Offset.zero);
              foundRect = topLeft & node.size;
              return;
            } catch (_) {}
          }
        }
        node.visitChildren(visit);
      }

      visit(root);
      if (foundRect != null) {
        return foundRect!;
      }
    }

    return widget.messageOffset & widget.messageSize;
  }

  void _handleMessageTapUp(TapUpDetails details) {
    // Tapping/clicking in the empty area beside the message bubble dismisses the blur/menu
    if (!_isGlobalPointInsideFocusedBubble(details.globalPosition)) {
      if (_hasActiveSelection) {
        _clearSelection();
      } else {
        _handleDismiss();
      }
      return;
    }

    // Inside the focused message bubble:
    // Do NOT automatically select a word on a simple tap.
    // If there is already an active selection, a simple tap clears it.
    if (_hasActiveSelection) {
      _clearSelection();
    }
  }

  void _handleMessageSecondaryTapUp(TapUpDetails details) {
    _handleDismiss();
  }

  void _handlePanStart(DragStartDetails details) {
    final platform = Theme.of(context).platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    if (!isDesktop) {
      final stackBox =
          _stackKey.currentContext?.findRenderObject() as RenderBox?;
      final currentRects = _getSelectionRectsInStack(stackBox);

      if (currentRects.isNotEmpty && stackBox != null) {
        final localInStack = stackBox.globalToLocal(details.globalPosition);
        final firstRect = currentRects.first;
        final lastRect = currentRects.last;
        final leftHandleTouchCenter =
            Offset(firstRect.left - 8, firstRect.bottom + 10);
        final rightHandleTouchCenter =
            Offset(lastRect.right + 8, lastRect.bottom + 10);

        if ((localInStack - leftHandleTouchCenter).distance <= 30.0) {
          _dragMode = _MessageHandleDragMode.leftHandle;
          return;
        }
        if ((localInStack - rightHandleTouchCenter).distance <= 30.0) {
          _dragMode = _MessageHandleDragMode.rightHandle;
          return;
        }
      }
    }

    if (!_isGlobalPointInsideFocusedBubble(details.globalPosition)) {
      _dragMode = _MessageHandleDragMode.none;
      return;
    }

    final p = _resolveParagraphForGlobalOffset(details.globalPosition);
    if (p == null || !p.hasSize) {
      _dragMode = _MessageHandleDragMode.none;
      return;
    }

    final local = p.globalToLocal(details.globalPosition);
    if (!(Offset.zero & p.size).inflate(16.0).contains(local)) {
      _dragMode = _MessageHandleDragMode.none;
      return;
    }

    final pos = p.getPositionForOffset(local);
    final offset = pos.offset.clamp(0, p.text.toPlainText().length);
    _activeParagraph = p;
    _dragMode = _MessageHandleDragMode.newRange;
    setState(() {
      _selection = TextSelection(baseOffset: offset, extentOffset: offset);
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final p = _activeParagraph;
    if (_dragMode == _MessageHandleDragMode.none || p == null || !p.hasSize) {
      return;
    }

    final plainLen = p.text.toPlainText().length;
    if (plainLen == 0) return;

    final local = p.globalToLocal(details.globalPosition);
    final pos = p.getPositionForOffset(local);
    final newOffset = pos.offset.clamp(0, plainLen);

    setState(() {
      switch (_dragMode) {
        case _MessageHandleDragMode.newRange:
          _selection = _selection.copyWith(extentOffset: newOffset);
          break;
        case _MessageHandleDragMode.leftHandle:
          final currentEnd = math.max(_selection.start, _selection.end);
          final clampedStart = math.min(newOffset, currentEnd - 1).clamp(0, plainLen);
          _selection = TextSelection(baseOffset: clampedStart, extentOffset: currentEnd);
          break;
        case _MessageHandleDragMode.rightHandle:
          final currentStart = math.min(_selection.start, _selection.end);
          final clampedEnd = math.max(newOffset, currentStart + 1).clamp(0, plainLen);
          _selection = TextSelection(baseOffset: currentStart, extentOffset: clampedEnd);
          break;
        case _MessageHandleDragMode.none:
          break;
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    _dragMode = _MessageHandleDragMode.none;
  }

  void _selectAllMessageText() {
    final p = _activeParagraph ?? _findSelectableParagraphs().firstOrNull;
    if (p == null) return;
    final plain = p.text.toPlainText();
    if (plain.isEmpty) return;
    HapticUtils.selection();
    setState(() {
      _activeParagraph = p;
      _selection = TextSelection(baseOffset: 0, extentOffset: plain.length);
    });
  }

  String _getSelectedPlainText() {
    final p = _activeParagraph;
    if (p == null || !_selection.isValid || _selection.isCollapsed) return '';
    final plain = p.text.toPlainText();
    final start = math.min(_selection.start, _selection.end).clamp(0, plain.length);
    final end = math.max(_selection.start, _selection.end).clamp(start, plain.length);
    if (start >= end) return '';
    return plain.substring(start, end).replaceAll('\uFFFC', '').trim();
  }

  (String, int, int) _getSelectedQuoteRange() {
    final p = _activeParagraph;
    if (p == null || !_selection.isValid || _selection.isCollapsed) {
      return (widget.messageContent, 0, widget.messageContent.length);
    }
    final plain = p.text.toPlainText();
    final start = math.min(_selection.start, _selection.end).clamp(0, plain.length);
    final end = math.max(_selection.start, _selection.end).clamp(start, plain.length);
    final selected = plain.substring(start, end).replaceAll('\uFFFC', '');

    if (widget.messageContent.isNotEmpty && selected.isNotEmpty) {
      final idx = widget.messageContent.indexOf(selected);
      if (idx != -1) {
        return (selected, idx, selected.length);
      }
    }
    return (selected, start, selected.length);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final mediaSize = mediaQuery.size;
    final mediaPadding = mediaQuery.padding;
    final viewInsets = mediaQuery.viewInsets;
    final theme = Theme.of(context);
    final platform = theme.platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size size = (constraints.hasBoundedWidth &&
                  constraints.hasBoundedHeight &&
                  constraints.maxWidth > 0 &&
                  constraints.maxHeight > 0)
              ? Size(constraints.maxWidth, constraints.maxHeight)
              : mediaSize;

          // Keep the focused message at its exact original vertical position
          // so it does not jump during blur and text selection stays aligned with the cursor.
          final double targetMessageTop = widget.messageOffset.dy;
          final double effectiveMessageHeight =
              _liveFocusedHeight ?? widget.messageSize.height;
          final double messageBottom = targetMessageTop + effectiveMessageHeight;

          const double kMenuGap = 8.0;
          const double kScreenEdgeMargin = 12.0;
          const double kDesiredMenuMaxHeight = 350.0;
          const double kMinPanelHeight = 120.0;
          const double kMinSidePlacementChatWidth = 440.0;
          const double kSideMenuTotalWidth = 267.0; // 44 (emoji) + 8 (gap) + 215 (actions)

          int actionItemCount = 4; // reply, copy, pin, delete
          if (widget.onQuote != null) actionItemCount++;
          if (widget.onViewPollResults != null) actionItemCount++;
          if (widget.onRetractVote != null) actionItemCount++;
          if (widget.onStopPoll != null) actionItemCount++;
          if (widget.isMe && widget.onEdit != null) actionItemCount++;
          if (widget.onSelect != null) actionItemCount++;
          final double naturalMenuHeight = math.min(
            kDesiredMenuMaxHeight,
            math.max(220.0, actionItemCount * 44.0 + 4.0),
          );

          final double safeTop = mediaPadding.top + kScreenEdgeMargin;
          final double safeBottom =
              math.max(mediaPadding.bottom, viewInsets.bottom) +
                  kScreenEdgeMargin;
          final double visibleHeight =
              math.max(kMinPanelHeight, size.height - safeTop - safeBottom);

          final double availableBelow =
              (size.height - safeBottom) - (messageBottom + kMenuGap);
          final double availableAbove =
              (targetMessageTop - kMenuGap) - safeTop;

          final bool placeBesideMessage =
              size.width >= kMinSidePlacementChatWidth &&
                  availableBelow < naturalMenuHeight &&
                  availableAbove < naturalMenuHeight &&
                  visibleHeight > math.max(availableBelow, availableAbove);

          bool showAbove = false;
          double? menuTop;
          double? menuBottom;
          double maxAvailableHeight;
          double menuLeft;

          if (placeBesideMessage) {
            showAbove = false;
            maxAvailableHeight =
                visibleHeight.clamp(kMinPanelHeight, kDesiredMenuMaxHeight);
            final double effectiveSideMenuHeight =
                math.min(naturalMenuHeight, maxAvailableHeight);
            menuTop = targetMessageTop.clamp(
              safeTop,
              math.max(safeTop, size.height - safeBottom - effectiveSideMenuHeight),
            );
            menuBottom = null;

            final Rect visualBubbleRect = _resolveVisualBubbleRect(context);
            final double maxLeft =
                math.max(16.0, size.width - kSideMenuTotalWidth - 16.0);
            if (widget.isMe) {
              // Outgoing message -> place menu to the left of the message bubble
              final double idealLeft =
                  visualBubbleRect.left - kSideMenuTotalWidth - kMenuGap;
              menuLeft = idealLeft.clamp(16.0, maxLeft);
            } else {
              // Incoming message -> place menu to the right of the message bubble
              final double idealLeft = visualBubbleRect.right + kMenuGap;
              menuLeft = idealLeft.clamp(16.0, maxLeft);
            }
          } else {
            if (availableBelow >= kDesiredMenuMaxHeight ||
                (availableBelow >= availableAbove &&
                    availableBelow >= kMinPanelHeight)) {
              showAbove = false;
              menuTop = messageBottom + kMenuGap;
              maxAvailableHeight =
                  availableBelow.clamp(kMinPanelHeight, kDesiredMenuMaxHeight);
            } else if (availableAbove >= kMinPanelHeight) {
              showAbove = true;
              menuBottom = size.height - (targetMessageTop - kMenuGap);
              maxAvailableHeight =
                  availableAbove.clamp(kMinPanelHeight, kDesiredMenuMaxHeight);
            } else {
              showAbove = false;
              maxAvailableHeight =
                  visibleHeight.clamp(kMinPanelHeight, kDesiredMenuMaxHeight);
              menuTop = (size.height - safeBottom - maxAvailableHeight)
                  .clamp(safeTop, math.max(safeTop, size.height - safeBottom));
            }

            final double menuWidth = (size.width - 32.0).clamp(220.0, 275.0);
            menuLeft = widget.isMe
                ? (size.width - menuWidth - 16.0)
                    .clamp(8.0, math.max(8.0, size.width - menuWidth - 8.0))
                : ((size.width - 283.0) < 8.0 ? 8.0 : 16.0);
          }

          final stackBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          final selectionRects = _hasActiveSelection
              ? _getSelectionRectsInStack(stackBox)
              : const <Rect>[];

          TextSelectionToolbarAnchors? selectionAnchors;
          if (selectionRects.isNotEmpty) {
            final first = selectionRects.first;
            final last = selectionRects.last;
            final unionLeft = selectionRects.map((r) => r.left).reduce(math.min);
            final unionRight =
                selectionRects.map((r) => r.right).reduce(math.max);
            final double centerX = ((unionLeft + unionRight) * 0.5)
                .clamp(24.0, math.max(24.0, size.width - 24.0));
            selectionAnchors = TextSelectionToolbarAnchors(
              primaryAnchor: Offset(centerX, math.max(16.0, first.top - 8.0)),
              secondaryAnchor: Offset(
                centerX,
                math.min(size.height - 16.0, last.bottom + 28.0),
              ),
            );
          }

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: (event) {
              if (_isExternalDragging) {
                if (event.kind == PointerDeviceKind.mouse &&
                    (event.buttons & kPrimaryMouseButton) == 0) {
                  MessageContextMenuService().endExternalDragSelection();
                } else {
                  MessageContextMenuService()
                      .updateExternalDragSelection(event.position);
                }
              }
            },
            onPointerUp: (_) {
              if (_isExternalDragging) {
                MessageContextMenuService().endExternalDragSelection();
              }
            },
            onPointerCancel: (_) {
              if (_isExternalDragging) {
                MessageContextMenuService().endExternalDragSelection();
              }
            },
            child: Stack(
              key: _stackKey,
              children: [
                // 1. Telegram iOS Blur Backdrop + Dark Tint (or lightweight transparent barrier when enableBlur is false)
                Positioned.fill(
                  child: widget.enableBlur
                      ? RepaintBoundary(
                          child: ClipRect(
                            child: AnimatedBuilder(
                              animation: _animation,
                              builder: (context, _) {
                                final t = _animation.value;
                                final sigma = 14.0 * t;
                                final barrier = GestureDetector(
                                  onTap: () {
                                    if (_hasActiveSelection) {
                                      _clearSelection();
                                    } else {
                                      _handleDismiss();
                                    }
                                  },
                                  onSecondaryTap: _handleDismiss,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    color: Colors.black
                                        .withValues(alpha: 0.28 * t),
                                  ),
                                );
                                if (sigma <= 0.01) {
                                  return barrier;
                                }
                                return BackdropFilter(
                                  filter: MessageContextMenu
                                      .buildOpaqueBackdropBlurFilter(sigma),
                                  child: barrier,
                                );
                              },
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: _handleDismiss,
                          onSecondaryTap: _handleDismiss,
                          behavior: HitTestBehavior.opaque,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                ),

                // 2. Sharp Focused Message rendered ON TOP of the blur layer, with interactive text selection
                if (widget.enableBlur && widget.focusedMessageBuilder != null)
                  Positioned(
                    left: widget.messageOffset.dx,
                    top: targetMessageTop,
                    width: widget.messageSize.width,
                    child: HeroMode(
                      enabled: false,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: _handleMessageTapUp,
                        onSecondaryTapUp: _handleMessageSecondaryTapUp,
                        onPanStart: _handlePanStart,
                        onPanUpdate: _handlePanUpdate,
                        onPanEnd: _handlePanEnd,
                        child: _FocusedBubbleSizeReporter(
                          onSizeChanged: (newSize) {
                            if (!mounted) return;
                            if (newSize.height > 0 &&
                                (_liveFocusedHeight == null ||
                                    (newSize.height - _liveFocusedHeight!)
                                            .abs() >
                                        0.5)) {
                              setState(() {
                                _liveFocusedHeight = newSize.height;
                              });
                            }
                          },
                          child: _originGradientBounds != null
                              ? ViewportGradientBoundsScope(
                                  globalBounds: _originGradientBounds!,
                                  child: widget
                                      .focusedMessageBuilder!(_focusedBubbleKey),
                                )
                              : widget.focusedMessageBuilder!(_focusedBubbleKey),
                        ),
                      ),
                    ),
                  )
                else if (widget.enableBlur)
                  // Fallback interactive hit region at messageOffset when no focusedMessageBuilder is provided
                  Positioned(
                    left: widget.messageOffset.dx,
                    top: targetMessageTop,
                    width: widget.messageSize.width,
                    height: widget.messageSize.height,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: _handleMessageTapUp,
                        onSecondaryTapUp: _handleMessageSecondaryTapUp,
                        onPanStart: _handlePanStart,
                        onPanUpdate: _handlePanUpdate,
                        onPanEnd: _handlePanEnd,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                // 3. Text Selection Highlight + Telegram Teardrop Handles over the focused message
                if (selectionRects.isNotEmpty) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _MessageSelectionHighlightPainter(
                          rects: selectionRects,
                          color: _kMintAccent.withValues(alpha: 0.30),
                        ),
                      ),
                    ),
                  ),
                  if (!isDesktop) ...[
                    // Left selection handle (mobile only)
                    Positioned(
                      left: selectionRects.first.left - _kHandleSize,
                      top: selectionRects.first.bottom,
                      width: _kHandleSize,
                      height: _kHandleSize,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) {
                          _dragMode = _MessageHandleDragMode.leftHandle;
                        },
                        onPanUpdate: _handlePanUpdate,
                        onPanEnd: _handlePanEnd,
                        child: Transform.rotate(
                          angle: math.pi / 2.0,
                          child: const CustomPaint(
                            painter: _MessageTeardropHandlePainter(
                              color: _kMintAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Right selection handle (mobile only)
                    Positioned(
                      left: selectionRects.last.right,
                      top: selectionRects.last.bottom,
                      width: _kHandleSize,
                      height: _kHandleSize,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) {
                          _dragMode = _MessageHandleDragMode.rightHandle;
                        },
                        onPanUpdate: _handlePanUpdate,
                        onPanEnd: _handlePanEnd,
                        child: const CustomPaint(
                          painter: _MessageTeardropHandlePainter(
                            color: _kMintAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],

                // 4. Main Message Context Menu (Reactions + Actions)
                if (!_hasActiveSelection && !_isExternalDragging)
                  Positioned(
                    top: menuTop,
                    bottom: menuBottom,
                    left: menuLeft,
                    child: RepaintBoundary(
                      child: ScaleTransition(
                        scale: _animation,
                        alignment: placeBesideMessage
                            ? (widget.isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft)
                            : (showAbove
                                ? (widget.isMe
                                    ? Alignment.bottomRight
                                    : Alignment.bottomLeft)
                                : (widget.isMe
                                    ? Alignment.topRight
                                    : Alignment.topLeft)),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxAvailableHeight,
                            maxWidth: (size.width - 16.0).clamp(220.0, 290.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: showAbove
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              _buildEmojiPanel(theme, maxAvailableHeight),
                              const SizedBox(width: 8),
                              Flexible(
                                child: _buildActionPanel(
                                  theme,
                                  maxAvailableHeight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // 5. Floating MessageTextSelectionToolbar when text is selected inside the message
                if (_hasActiveSelection &&
                    !_isExternalDragging &&
                    selectionAnchors != null)
                  Positioned.fill(
                    child: MessageTextSelectionToolbar(
                      anchors: selectionAnchors,
                      onCopy: () {
                        final text = _getSelectedPlainText();
                        if (text.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: text));
                          GlassToastService().show(
                            context,
                            context.l10n.translate('copied_to_clipboard'),
                            icon: Icons.check,
                          );
                        }
                        _handleDismiss();
                      },
                      onQuote: () {
                        final (selectedText, offset, length) =
                            _getSelectedQuoteRange();
                        _handleDismiss(() {
                          if (widget.onQuotePartial != null &&
                              selectedText.isNotEmpty) {
                            widget.onQuotePartial!(
                              selectedText,
                              offset,
                              length,
                            );
                          } else {
                            widget.onQuote?.call();
                          }
                        });
                      },
                      onTranslate: () {
                        // TODO: Translate selected message text
                        GlassToastService().show(
                          context,
                          'Перевод скоро появится',
                          icon: Icons.translate,
                        );
                      },
                      onSearchMessages: () {
                        // TODO: Search messages with selected text
                        GlassToastService().show(
                          context,
                          'Поиск сообщений скоро появится',
                          icon: Icons.search,
                        );
                      },
                      onSelectAll: _selectAllMessageText,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmojiPanel(ThemeData theme, double maxHeight) {
    final emojis = EmojiUtils.getFrequentEmojis();
    return Container(
      width: 44,
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            overscroll: false,
            scrollbars: false,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: emojis.map((emoji) {
                final isSelected = widget.selectedEmojis.contains(emoji);
                return InkWell(
                  onTap: () {
                    HapticUtils.tap();
                    _handleDismiss(() => widget.onReaction(emoji));
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    padding: const EdgeInsets.all(4),
                    decoration: isSelected
                        ? BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 1.5,
                            ),
                          )
                        : null,
                    child: Center(
                      child: EmojiUtils.appleEmoji(emoji, size: 24),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionPanel(ThemeData theme, double maxHeight) {
    final bool isSending = widget.sendStatus == 0;
    return Container(
      width: 215,
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            overscroll: false,
            scrollbars: false,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionItem(
                  (c) => iconoir.Reply(color: c, width: 20, height: 20),
                  context.l10n.translate('chat_action_reply'),
                  widget.onReply,
                  theme,
                  enabled: !isSending,
                ),
                if (widget.onQuote != null)
                  _buildActionItem(
                    (c) => iconoir.Quote(color: c, width: 20, height: 20),
                    context.l10n.translate('format_quote'),
                    widget.onQuote!,
                    theme,
                    enabled: !isSending,
                  ),
                if (widget.onViewPollResults != null)
                  _buildActionItem(
                    (c) => iconoir.StatsReport(color: c, width: 20, height: 20),
                    context.l10n.translate('poll_view_results'),
                    widget.onViewPollResults!,
                    theme,
                    enabled: !isSending,
                  ),
                if (widget.onRetractVote != null)
                  _buildActionItem(
                    (c) => iconoir.Undo(color: c, width: 20, height: 20),
                    context.l10n.translate('poll_retract_vote'),
                    widget.onRetractVote!,
                    theme,
                    enabled: !isSending,
                  ),
                if (widget.onStopPoll != null)
                  _buildActionItem(
                    (c) => Icon(Icons.stop_circle_outlined, color: c, size: 20),
                    context.l10n.translate('poll_stop'),
                    widget.onStopPoll!,
                    theme,
                    enabled: !isSending,
                  ),
                _buildActionItem(
                  (c) => iconoir.Copy(color: c, width: 20, height: 20),
                  context.l10n.translate('chat_action_copy'),
                  widget.onCopy,
                  theme,
                  enabled: !isSending,
                ),
                _buildActionItem(
                  (c) => iconoir.Pin(color: c, width: 20, height: 20),
                  context.l10n.translate('chat_action_pin'),
                  widget.onPin,
                  theme,
                  enabled: !isSending,
                ),
                if (widget.isMe && widget.onEdit != null)
                  _buildActionItem(
                    (c) => iconoir.EditPencil(color: c, width: 20, height: 20),
                    context.l10n.translate('chat_edit_message'),
                    widget.onEdit!,
                    theme,
                    enabled: !isSending,
                  ),
                if (widget.onSelect != null)
                  _buildActionItem(
                    (c) => iconoir.CheckCircle(color: c, width: 20, height: 20),
                    context.l10n.translate('chat_action_select'),
                    widget.onSelect!,
                    theme,
                    enabled: !isSending,
                  ),
                const Divider(height: 1),
                _buildActionItem(
                  (c) => iconoir.Trash(color: c, width: 20, height: 20),
                  context.l10n.translate('chat_action_delete'),
                  widget.onDelete,
                  theme,
                  isDestructive: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem(
    Widget Function(Color color) iconBuilder,
    String label,
    VoidCallback onTap,
    ThemeData theme, {
    bool isDestructive = false,
    bool enabled = true,
  }) {
    final color = isDestructive
        ? Colors.red
        : (enabled ? theme.colorScheme.onSurface : theme.disabledColor);
    return InkWell(
      onTap: enabled
          ? () {
              HapticUtils.tap();
              _handleDismiss(onTap);
            }
          : null,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Center(child: iconBuilder(color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageSelectionHighlightPainter extends CustomPainter {
  final List<Rect> rects;
  final Color color;

  _MessageSelectionHighlightPainter({
    required this.rects,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final rect in rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MessageSelectionHighlightPainter oldDelegate) {
    return oldDelegate.rects != rects || oldDelegate.color != color;
  }
}

class _MessageTeardropHandlePainter extends CustomPainter {
  final Color color;
  const _MessageTeardropHandlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final double radius = size.width / 2.0;
    final circle = Rect.fromCircle(center: Offset(radius, radius), radius: radius);
    final point = Rect.fromLTWH(0.0, 0.0, radius, radius);
    final path = Path()
      ..addOval(circle)
      ..addRect(point);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MessageTeardropHandlePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Floating context menu for selected text inside a message, modeled after
/// [TelegramTextSelectionToolbar] with:
/// - Compact horizontal pill: "Копировать", "Цитировать", "Перевести" (TODO), and "⋮"
/// - Expanded vertical menu: "Найти сообщения" (TODO), "Выбрать всё", and "Назад".
class MessageTextSelectionToolbar extends StatefulWidget {
  final TextSelectionToolbarAnchors anchors;
  final VoidCallback onCopy;
  final VoidCallback onQuote;
  final VoidCallback onTranslate;
  final VoidCallback onSearchMessages;
  final VoidCallback onSelectAll;

  const MessageTextSelectionToolbar({
    Key? key,
    required this.anchors,
    required this.onCopy,
    required this.onQuote,
    required this.onTranslate,
    required this.onSearchMessages,
    required this.onSelectAll,
  }) : super(key: key);

  @override
  State<MessageTextSelectionToolbar> createState() =>
      _MessageTextSelectionToolbarState();
}

class _MessageTextSelectionToolbarState
    extends State<MessageTextSelectionToolbar> {
  bool _isExpanded = false;

  static const Color _kDarkBg = Color(0xFF1E2225);
  static const Color _kMintAccent = Color(0xFF7BE5DA);

  void _expand() {
    HapticUtils.tap();
    setState(() => _isExpanded = true);
  }

  void _collapse() {
    HapticUtils.tap();
    setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: TextSelectionToolbarLayoutDelegate(
        anchorAbove: widget.anchors.primaryAnchor,
        anchorBelow:
            widget.anchors.secondaryAnchor ?? widget.anchors.primaryAnchor,
        fitsAbove: widget.anchors.primaryAnchor.dy >= 180 ? true : null,
      ),
      child: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(16.0),
        color: _kDarkBg,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            color: _kDarkBg,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: Colors.white12, width: 0.8),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: _isExpanded
                  ? KeyedSubtree(
                      key: const ValueKey('msg_sel_expanded'),
                      child: _buildExpandedVerticalMenu(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('msg_sel_compact'),
                      child: _buildCompactPill(),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactPill() {
    return Container(
      height: 44.0,
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildPillButton('Копировать', widget.onCopy),
          _buildPillButton('Цитировать', widget.onQuote),
          _buildPillButton('Перевести', widget.onTranslate),
          InkWell(
            borderRadius: BorderRadius.circular(12.0),
            onTap: _expand,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: iconoir.MoreVert(
                color: _kMintAccent,
                width: 22,
                height: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12.0),
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Text(
          label,
          style: const TextStyle(
            color: _kMintAccent,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedVerticalMenu() {
    return Container(
      width: 235.0,
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMenuItem(
            icon: const iconoir.Search(
              color: _kMintAccent,
              width: 20,
              height: 20,
            ),
            label: 'Найти сообщения',
            onTap: () {
              HapticUtils.tap();
              widget.onSearchMessages();
            },
          ),
          _buildMenuItem(
            icon: const Icon(
              Icons.select_all_rounded,
              color: _kMintAccent,
              size: 20,
            ),
            label: 'Выбрать всё',
            onTap: () {
              widget.onSelectAll();
              _collapse();
            },
          ),
          const Divider(height: 1, thickness: 0.5, color: Colors.white12),
          InkWell(
            onTap: _collapse,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 11.0),
              child: Row(
                children: [
                  iconoir.NavArrowLeft(
                    color: _kMintAccent,
                    width: 18,
                    height: 18,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Назад',
                    style: TextStyle(
                      color: _kMintAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          children: [
            SizedBox(
              width: 20.0,
              height: 20.0,
              child: Center(child: icon),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _kMintAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusedBubbleSizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSizeChanged;

  const _FocusedBubbleSizeReporter({
    required this.onSizeChanged,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFocusedBubbleSizeReporter(onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFocusedBubbleSizeReporter renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _RenderFocusedBubbleSizeReporter extends RenderProxyBox {
  ValueChanged<Size> onSizeChanged;
  Size? _lastSize;

  _RenderFocusedBubbleSizeReporter(this.onSizeChanged);

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_lastSize == null ||
        (newSize.height - _lastSize!.height).abs() > 0.5 ||
        (newSize.width - _lastSize!.width).abs() > 0.5) {
      _lastSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onSizeChanged(newSize);
      });
    }
  }
}

