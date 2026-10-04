import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../models/theav_theme.dart';
import '../../models/name_color_preset.dart';
import '../../services/chat_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../chat/message_reply_info.dart';
import '../chat/reactions_panel.dart';
import 'message_status_widget.dart';
import '../../utils/entity_parser.dart';
import 'text_message_widget.dart';
import 'fullscreen_photo_viewer.dart';
import 'inline_video_player.dart';
import 'document_message_widget.dart';
import 'dart:io';
import 'video_message_widget.dart';
import 'voice_message_widget.dart';
import 'link_preview_card.dart';
import 'blurred_media_placeholder.dart';
import 'media_download_button.dart';
import '../../services/media_cache_manager.dart';
import '../../l10n/app_localizations.dart';
import '../theme/viewport_gradient_box.dart';

/// Радиус скругления "облачка" сообщения.
const double kMessageBorderRadius = 18.0;

/// Role of a child inside [BubbleLayoutWidget].
enum BubbleChildRole {
  senderName,
  reply,
  content,
  metadata,
}

/// Parent data for children of [RenderBubbleLayout].
class BubbleParentData extends ContainerBoxParentData<RenderBox> {
  BubbleChildRole? role;
}

/// Wrapper widget to attach [BubbleChildRole] to children of [BubbleLayoutWidget].
class BubbleChild extends ParentDataWidget<BubbleParentData> {
  final BubbleChildRole role;

  const BubbleChild({
    Key? key,
    required this.role,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData as BubbleParentData;
    if (parentData.role != role) {
      parentData.role = role;
      final targetParent = renderObject.parent;
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => BubbleLayoutWidget;
}

/// Metrics extracted from inspecting the rendered content tree.
class _BubbleContentMetrics {
  final bool hasText;
  final bool isSingleLine;
  final double lastCharRight;
  final double lastCharBottom;
  final double lastLineHeight;

  const _BubbleContentMetrics({
    required this.hasText,
    required this.isSingleLine,
    required this.lastCharRight,
    required this.lastCharBottom,
    required this.lastLineHeight,
  });
}

/// Multi-child render object widget that performs dynamic layout for message bubbles.
class BubbleLayoutWidget extends MultiChildRenderObjectWidget {
  final double replyWidth;
  final double senderNameWidth;
  final double? metadataWidth;
  final bool hasBlockElement;

  BubbleLayoutWidget({
    Key? key,
    Widget? senderNameWidget,
    Widget? replyWidget,
    required Widget content,
    required Widget metadata,
    this.replyWidth = 0.0,
    this.senderNameWidth = 0.0,
    this.metadataWidth,
    this.hasBlockElement = false,
  }) : super(
          key: key,
          children: [
            if (senderNameWidget != null)
              BubbleChild(role: BubbleChildRole.senderName, child: senderNameWidget),
            if (replyWidget != null)
              BubbleChild(role: BubbleChildRole.reply, child: replyWidget),
            BubbleChild(role: BubbleChildRole.content, child: content),
            BubbleChild(role: BubbleChildRole.metadata, child: metadata),
          ],
        );

  @override
  RenderBubbleLayout createRenderObject(BuildContext context) {
    return RenderBubbleLayout(
      replyWidth: replyWidth,
      senderNameWidth: senderNameWidth,
      metadataWidth: metadataWidth,
      hasBlockElement: hasBlockElement,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderBubbleLayout renderObject) {
    renderObject
      ..replyWidth = replyWidth
      ..senderNameWidth = senderNameWidth
      ..metadataWidth = metadataWidth
      ..hasBlockElement = hasBlockElement;
  }
}

/// Custom RenderBox for pixel-perfect message bubble layout.
///
/// Gives [content] loose constraints so text wraps naturally across the full available
/// width without premature wrapping. Then inspects the actual rendered paragraph
/// boxes to position metadata inline on the last line whenever physical space permits,
/// or on a separate row below if the last line is full, without bloating bubble width.
class RenderBubbleLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, BubbleParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, BubbleParentData> {
  double _replyWidth;
  double _senderNameWidth;
  double? _metadataWidth;
  bool _hasBlockElement;

  RenderBubbleLayout({
    double replyWidth = 0.0,
    double senderNameWidth = 0.0,
    double? metadataWidth,
    bool hasBlockElement = false,
    List<RenderBox>? children,
  })  : _replyWidth = replyWidth,
        _senderNameWidth = senderNameWidth,
        _metadataWidth = metadataWidth,
        _hasBlockElement = hasBlockElement {
    addAll(children);
  }

  double get replyWidth => _replyWidth;
  set replyWidth(double value) {
    if (_replyWidth != value) {
      _replyWidth = value;
      markNeedsLayout();
    }
  }

  double get senderNameWidth => _senderNameWidth;
  set senderNameWidth(double value) {
    if (_senderNameWidth != value) {
      _senderNameWidth = value;
      markNeedsLayout();
    }
  }

  double? get metadataWidth => _metadataWidth;
  set metadataWidth(double? value) {
    if (_metadataWidth != value) {
      _metadataWidth = value;
      markNeedsLayout();
    }
  }

  bool get hasBlockElement => _hasBlockElement;
  set hasBlockElement(bool value) {
    if (_hasBlockElement != value) {
      _hasBlockElement = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BubbleParentData) {
      child.parentData = BubbleParentData();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    RenderBox? child = firstChild;
    double width = 0.0;
    while (child != null) {
      final childParentData = child.parentData as BubbleParentData;
      width = math.max(width, child.getMinIntrinsicWidth(height));
      child = childParentData.nextSibling;
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    RenderBox? child = firstChild;
    double width = 0.0;
    while (child != null) {
      final childParentData = child.parentData as BubbleParentData;
      width = math.max(width, child.getMaxIntrinsicWidth(height));
      child = childParentData.nextSibling;
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    RenderBox? child = firstChild;
    double height = 0.0;
    while (child != null) {
      final childParentData = child.parentData as BubbleParentData;
      height += child.getMinIntrinsicHeight(width);
      child = childParentData.nextSibling;
    }
    return height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    RenderBox? child = firstChild;
    double height = 0.0;
    while (child != null) {
      final childParentData = child.parentData as BubbleParentData;
      height += child.getMaxIntrinsicHeight(width);
      child = childParentData.nextSibling;
    }
    return height;
  }

  _BubbleContentMetrics _inspectContent(RenderBox root) {
    if (_hasBlockElement) {
      return const _BubbleContentMetrics(
        hasText: false,
        isSingleLine: false,
        lastCharRight: 0.0,
        lastCharBottom: 0.0,
        lastLineHeight: 0.0,
      );
    }

    RenderParagraph? firstParagraph;
    RenderParagraph? lastParagraph;
    int paragraphCount = 0;
    bool lastParagraphIsBlock = false;

    bool isInsideBlock(RenderObject obj) {
      RenderObject? curr = obj;
      while (curr != null && curr != root) {
        if (curr is RenderMetaData && curr.metaData == 'block_element') {
          return true;
        }
        curr = curr.parent;
      }
      return false;
    }

    void visitor(RenderObject child) {
      if (child is RenderParagraph) {
        final text = child.text.toPlainText();
        if (text.trim().isNotEmpty) {
          if (isInsideBlock(child)) {
            lastParagraphIsBlock = true;
            lastParagraph = null;
          } else {
            lastParagraphIsBlock = false;
            firstParagraph ??= child;
            lastParagraph = child;
            paragraphCount++;
          }
        }
      }
      child.visitChildren(visitor);
    }

    visitor(root);

    final targetParagraph = lastParagraph;
    if (lastParagraphIsBlock || targetParagraph == null) {
      return const _BubbleContentMetrics(
        hasText: false,
        isSingleLine: false,
        lastCharRight: 0.0,
        lastCharBottom: 0.0,
        lastLineHeight: 0.0,
      );
    }

    // Calculate offset of targetParagraph within root via BoxParentData
    Offset offsetInRoot = Offset.zero;
    RenderObject current = targetParagraph;
    while (current != root && current.parent != null) {
      if (current.parentData is BoxParentData) {
        offsetInRoot += (current.parentData as BoxParentData).offset;
      }
      current = current.parent!;
    }

    final plainText = targetParagraph.text.toPlainText();
    final trimmed = plainText.trimRight();
    final int targetIndex = trimmed.isNotEmpty ? trimmed.length - 1 : plainText.length - 1;

    final boxes = targetParagraph.getBoxesForSelection(
      TextSelection(baseOffset: targetIndex, extentOffset: targetIndex + 1),
    );

    if (boxes.isEmpty) {
      return const _BubbleContentMetrics(
        hasText: false,
        isSingleLine: false,
        lastCharRight: 0.0,
        lastCharBottom: 0.0,
        lastLineHeight: 0.0,
      );
    }

    final lastBox = boxes.last;
    final double lastCharRight = offsetInRoot.dx + lastBox.right;
    final double lastCharBottom = offsetInRoot.dy + lastBox.bottom;
    final double lastLineHeight = lastBox.bottom - lastBox.top;

    bool isSingleLine = false;
    if (paragraphCount == 1 && offsetInRoot.dy < 2.0) {
      final firstBoxes = targetParagraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      if (firstBoxes.isNotEmpty) {
        final firstBox = firstBoxes.first;
        if ((lastBox.top - firstBox.top).abs() < 2.0) {
          isSingleLine = true;
        }
      } else {
        isSingleLine = true;
      }
    }

    return _BubbleContentMetrics(
      hasText: true,
      isSingleLine: isSingleLine,
      lastCharRight: lastCharRight,
      lastCharBottom: lastCharBottom,
      lastLineHeight: lastLineHeight,
    );
  }

  @override
  void performLayout() {
    RenderBox? senderName;
    RenderBox? reply;
    RenderBox? content;
    RenderBox? metadata;

    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData as BubbleParentData;
      switch (childParentData.role) {
        case BubbleChildRole.senderName:
          senderName = child;
          break;
        case BubbleChildRole.reply:
          reply = child;
          break;
        case BubbleChildRole.content:
          content = child;
          break;
        case BubbleChildRole.metadata:
          metadata = child;
          break;
        case null:
          break;
      }
      child = childParentData.nextSibling;
    }

    if (content == null || metadata == null) {
      size = constraints.constrain(Size.zero);
      return;
    }

    const double gap = 4.0;
    const double senderSpacing = 2.0;
    const double replySpacing = 4.0;
    const double rowGap = 2.0;

    // 1. Measure senderName if present
    double senderNameHeight = 0.0;
    double measuredSenderWidth = 0.0;
    if (senderName != null) {
      senderName.layout(BoxConstraints(maxWidth: constraints.maxWidth), parentUsesSize: true);
      senderNameHeight = senderName.size.height + senderSpacing;
      measuredSenderWidth = senderName.size.width;
    }

    // 2. Measure content with loose constraints (unconstricted natural width up to maxWidth)
    content.layout(constraints.loosen(), parentUsesSize: true);
    final double contentWidth = content.size.width;
    final double contentHeight = content.size.height;

    // 3. Measure metadata unconstrained
    metadata.layout(const BoxConstraints(), parentUsesSize: true);
    final double metaWidth = math.max(metadata.size.width, _metadataWidth ?? 0.0);
    final double metaHeight = metadata.size.height;

    // 4. Header width baseline
    final double effectiveReplyWidth = replyWidth > 0.0
        ? replyWidth
        : (reply != null ? reply.getMinIntrinsicWidth(double.infinity) : 0.0);
    final double effectiveHeaderWidth = math.max(
      effectiveReplyWidth,
      senderName != null ? math.max(senderNameWidth, measuredSenderWidth) : 0.0,
    );

    // 5. Inspect content geometry
    final metrics = _inspectContent(content);

    double bubbleWidth;
    double bubbleHeight;
    double contentX = 0.0;
    double contentY = 0.0;
    double metaX = 0.0;
    double metaY = 0.0;

    if (metrics.hasText && metrics.isSingleLine) {
      // Case 1: Single line text
      final double neededWidth = metrics.lastCharRight + gap + metaWidth;
      if (neededWidth <= constraints.maxWidth) {
        // Fits inline with metadata
        bubbleWidth = math.min(
          constraints.maxWidth,
          math.max(effectiveHeaderWidth, math.max(contentWidth, neededWidth)),
        );
        final double lineContentHeight = math.max(contentHeight, metaHeight);
        contentX = 0.0;
        metaX = bubbleWidth - metaWidth;
        contentY = lineContentHeight - contentHeight;
        metaY = lineContentHeight - metaHeight;
        bubbleHeight = lineContentHeight;
      } else {
        // Single line too long to fit metadata inline -> row below
        bubbleWidth = math.min(
          constraints.maxWidth,
          math.max(effectiveHeaderWidth, math.max(contentWidth, metaWidth)),
        );
        contentX = 0.0;
        contentY = 0.0;
        metaX = bubbleWidth - metaWidth;
        metaY = contentHeight + rowGap;
        bubbleHeight = contentHeight + rowGap + metaHeight;
      }
    } else if (metrics.hasText) {
      // Case 2: Multi-line text
      final double lineHeight = metrics.lastLineHeight > 0 ? metrics.lastLineHeight : 20.0;
      final bool isAtBottom = (contentHeight - metrics.lastCharBottom) <= (lineHeight * 1.5 + 4.0);
      final bool canFitOnLastLine = isAtBottom && (metrics.lastCharRight + gap + metaWidth <= constraints.maxWidth);

      if (canFitOnLastLine) {
        final double neededWidth = metrics.lastCharRight + gap + metaWidth;
        bubbleWidth = math.min(
          constraints.maxWidth,
          math.max(effectiveHeaderWidth, math.max(contentWidth, neededWidth)),
        );
        contentX = 0.0;
        contentY = 0.0;
        metaX = bubbleWidth - metaWidth;
        metaY = math.min(contentHeight - metaHeight, math.max(0.0, metrics.lastCharBottom - metaHeight));
        bubbleHeight = contentHeight;
      } else {
        // Case 3: Does not fit on last line -> separate row below
        bubbleWidth = math.min(
          constraints.maxWidth,
          math.max(effectiveHeaderWidth, math.max(contentWidth, metaWidth)),
        );
        contentX = 0.0;
        contentY = 0.0;
        metaX = bubbleWidth - metaWidth;
        metaY = contentHeight + rowGap;
        bubbleHeight = contentHeight + rowGap + metaHeight;
      }
    } else {
      // Fallback: Non-text, block element, TeX, etc. -> separate row below
      bubbleWidth = math.min(
        constraints.maxWidth,
        math.max(effectiveHeaderWidth, math.max(contentWidth, metaWidth)),
      );
      contentX = 0.0;
      contentY = 0.0;
      metaX = bubbleWidth - metaWidth;
      metaY = contentHeight + rowGap;
      bubbleHeight = contentHeight + rowGap + metaHeight;
    }

    // 6. Layout reply with exact bubble width if present
    double replyHeight = 0.0;
    if (reply != null) {
      reply.layout(BoxConstraints.tightFor(width: bubbleWidth), parentUsesSize: true);
      replyHeight = reply.size.height + replySpacing;
    }

    final double headerHeight = senderNameHeight + replyHeight;
    bubbleHeight += headerHeight;
    contentY += headerHeight;
    metaY += headerHeight;

    size = constraints.constrain(Size(bubbleWidth, bubbleHeight));

    // 7. Assign child offsets
    if (senderName != null) {
      (senderName.parentData as BubbleParentData).offset = Offset.zero;
    }
    if (reply != null) {
      (reply.parentData as BubbleParentData).offset = Offset(0.0, senderNameHeight);
    }
    (content.parentData as BubbleParentData).offset = Offset(contentX, contentY);
    (metadata.parentData as BubbleParentData).offset = Offset(metaX, metaY);
  }
}

/// Custom layout widget for message bubble layout.
class MessageBubbleLayout extends StatelessWidget {
  final Widget content;
  final Widget metadata;
  final String? text;
  final TextStyle textStyle;
  final bool hasBlockElement;
  final bool isBigEmoji;
  final Widget? replyWidget;
  final double replyWidth;
  final Widget? senderNameWidget;
  final double senderNameWidth;
  final double? metadataWidth;

  const MessageBubbleLayout({
    Key? key,
    required this.content,
    required this.metadata,
    this.text,
    required this.textStyle,
    this.hasBlockElement = false,
    this.isBigEmoji = false,
    this.replyWidget,
    this.replyWidth = 0.0,
    this.senderNameWidget,
    this.senderNameWidth = 0.0,
    this.metadataWidth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isBigEmoji) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            bottom: 0,
            right: 0,
            child: metadata,
          ),
        ],
      );
    }

    return BubbleLayoutWidget(
      senderNameWidget: senderNameWidget,
      replyWidget: replyWidget,
      content: content,
      metadata: metadata,
      replyWidth: replyWidth,
      senderNameWidth: senderNameWidth,
      metadataWidth: metadataWidth,
      hasBlockElement: hasBlockElement,
    );
  }
}

/// Unified Message Bubble Widget.
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String currentUserId;
  final String? senderName;
  final String? chatType;
  final bool isHighlighted;
  final Map<String, int>? reactions;
  final String? myReaction;
  final Set<String>? myReactions;
  final Function(String emoji)? onReactionTap;
  final Function(Message message)? onRetry;
  final Function(String replyToId, String? chatId)? onReplyTap;
  final Function(String url, String name, String type)? onFileTap;
  final String Function(String timestamp) formatTime;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.currentUserId,
    this.senderName,
    this.chatType,
    this.isHighlighted = false,
    this.reactions,
    this.myReaction,
    this.myReactions,
    this.onReactionTap,
    this.onRetry,
    this.onReplyTap,
    this.onFileTap,
    required this.formatTime,
  }) : super(key: key);

  bool get _hasMedia {
    final url = message.fileUrl?.trim();
    return url != null && url.isNotEmpty;
  }

  bool _isImageUrl(String url) {
    final clean = url.split('?').first.toLowerCase();
    return clean.endsWith('.jpg') ||
        clean.endsWith('.jpeg') ||
        clean.endsWith('.png') ||
        clean.endsWith('.gif') ||
        clean.endsWith('.webp') ||
        clean.endsWith('.bmp') ||
        clean.endsWith('.heic') ||
        url.startsWith('data:image/');
  }

  bool _isVideoUrl(String url) {
    final clean = url.split('?').first.toLowerCase();
    return clean.endsWith('.mp4') ||
        clean.endsWith('.mov') ||
        clean.endsWith('.avi') ||
        clean.endsWith('.mkv') ||
        clean.endsWith('.webm');
  }

  bool _isAudioUrl(String url) {
    final clean = url.split('?').first.toLowerCase();
    return clean.endsWith('.mp3') ||
        clean.endsWith('.wav') ||
        clean.endsWith('.ogg') ||
        clean.endsWith('.m4a') ||
        clean.endsWith('.aac');
  }

  bool get _isImage =>
      _hasMedia &&
      (message.messageType == 'image' ||
          message.messageType == 'photo' ||
          _isImageUrl(message.fileUrl!));

  bool get _isVideo =>
      _hasMedia &&
      !_isRoundVideo &&
      (message.messageType == 'video' || _isVideoUrl(message.fileUrl!));

  bool get _isVoice =>
      _hasMedia && message.messageType == 'voice';

  bool get _isAudio =>
      _hasMedia &&
      !_isVoice &&
      (message.messageType == 'audio' ||
          _isAudioUrl(message.fileUrl!));

  bool get _isRoundVideo =>
      _hasMedia && (message.isRound || message.messageType == 'round');

  bool get _hasCaption {
    if (!_hasMedia || _isRoundVideo || _isVoice) return false;
    final trimmed = message.content.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == message.fileName) return false;
    if (trimmed == message.fileUrl) return false;
    return true;
  }

  bool get _isSingleEmoji {
    if (_hasMedia || message.messageType != 'text' || message.hasReply) {
      return false;
    }
    final trimmed = message.content.trim();
    if (trimmed.isEmpty) return false;
    final runes = trimmed.runes.toList();
    return runes.length <= 2 && EmojiUtils.emojiRegex.hasMatch(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final String? resolvedFileUrl = AppConfig.resolveMediaUrl(message.fileUrl);
    final bool hasMedia = _hasMedia && resolvedFileUrl != null && resolvedFileUrl.isNotEmpty;
    final bool hasCaption = _hasCaption;
    final bool isBigEmoji = !hasMedia && _isSingleEmoji;
    final Alignment alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final double effectiveBubbleRadius = themeExt?.bubbleRadius ?? kMessageBorderRadius;

    final Color bubbleColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoing ?? Theme.of(context).colorScheme.primary)
        : (themeExt?.palette.chatBubbleIncoming ?? Theme.of(context).colorScheme.secondaryContainer);

    final Color bubbleTextColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoingText ?? Theme.of(context).colorScheme.onPrimary)
        : (themeExt?.palette.chatBubbleIncomingText ?? Theme.of(context).colorScheme.onSecondaryContainer);

    final Color bubbleSubtextColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoingSubtext ?? bubbleTextColor.withValues(alpha: 0.7))
        : (themeExt?.palette.chatBubbleIncomingSubtext ?? bubbleTextColor.withValues(alpha: 0.7));

    final bool isPureMedia = hasMedia && !hasCaption && !_isAudio && !_isVoice;
    final Color backgroundColor = (isBigEmoji || _isRoundVideo || isPureMedia)
        ? Colors.transparent
        : bubbleColor;

    final TextStyle textStyle = TextStyle(
      fontSize: 16.0,
      height: 1.4,
      color: isBigEmoji
          ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)
          : bubbleTextColor,
    );

    final String trimmedContent = message.content.trim();
    final List<String> contentLines = trimmedContent.split('\n');
    final String lastLine = contentLines.isNotEmpty ? contentLines.last.trim() : '';
    final bool contentEndsWithQuote = lastLine.startsWith('>') ||
        lastLine.startsWith('**>') ||
        trimmedContent.startsWith('>') ||
        trimmedContent.startsWith('**>');
    final bool entityEndsWithQuote = message.entities.any((e) =>
        (e.type == 'blockquote' || e.type == 'quote') &&
        (e.offset + e.length >= trimmedContent.length - 2));
    final bool entityEndsWithPre = message.entities.any((e) =>
        (e.type == 'pre' || e.type == 'code') &&
        (e.offset + e.length >= trimmedContent.length - 2));

    final profileTheme = context.watch<ProfileThemeProvider?>();
    final NameColorPreset effectivePreset;
    final ReplyStripStyle effectiveStripStyle;
    if (isMe) {
      effectivePreset = profileTheme?.currentNameColorPreset ?? NameColorPresets.defaults.first;
      effectiveStripStyle = profileTheme?.currentStripStyle ?? ReplyStripStyle.solid;
    } else if (message.senderNameColorId != null && message.senderNameColorId!.isNotEmpty) {
      effectivePreset = NameColorPresets.getById(message.senderNameColorId!);
      effectiveStripStyle = ReplyStripStyle.values.firstWhere(
        (s) => s.name == message.senderReplyStripStyle,
        orElse: () => ReplyStripStyle.solid,
      );
    } else {
      final presetIndex = message.senderId.hashCode.abs() % NameColorPresets.defaults.length;
      effectivePreset = NameColorPresets.defaults[presetIndex];
      effectiveStripStyle = ReplyStripStyle.solid;
    }

    final previewOpts = message.linkPreviewOptions;
    final bool previewDisabled = previewOpts?.isDisabled ?? false;
    String? previewUrl = previewOpts?.url;
    if (previewUrl == null && !previewDisabled) {
      final urls = EntityParser.extractUrls(message.content);
      if (urls.isNotEmpty) previewUrl = urls.first;
    }
    final bool hasEffectivePreview = previewUrl != null && !previewDisabled;
    final bool showAbove = previewOpts?.showAboveText ?? false;
    final bool previewAtBottom = hasEffectivePreview && !showAbove && !hasMedia;

    final bool endsWithBlock =
        trimmedContent.endsWith('```') ||
        trimmedContent.endsWith(r'$$') ||
        contentEndsWithQuote ||
        entityEndsWithQuote ||
        entityEndsWithPre ||
        previewAtBottom ||
        hasMedia;

    // Build Metadata Widget
    final Widget metadataWidget = isBigEmoji
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isEdited) ...[
                  Text(
                    context.l10n.translate('chat_edited'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  formatTime(message.createdAt),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  if (message.sendStatus == 0)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.0, color: Colors.white),
                    )
                  else if (message.sendStatus == 2)
                    GestureDetector(
                      onTap: () => onRetry?.call(message),
                      child: const iconoir.WarningCircle(width: 14, height: 14, color: Colors.redAccent),
                    )
                  else
                    MessageStatusWidget(
                      isRead: message.isRead,
                      isOutgoing: isMe,
                      colorOverride: Colors.white.withValues(alpha: 0.9),
                    ),
                ],
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 1.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (message.isEdited) ...[
                  Text(
                    context.l10n.translate('chat_edited'),
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: bubbleSubtextColor.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: bubbleSubtextColor,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  if (message.sendStatus == 0)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.2, color: bubbleSubtextColor),
                    )
                  else if (message.sendStatus == 2)
                    GestureDetector(
                      onTap: () => onRetry?.call(message),
                      child: const iconoir.WarningCircle(width: 14, height: 14, color: Colors.red),
                    )
                  else
                    MessageStatusWidget(
                      isRead: message.isRead,
                      isOutgoing: isMe,
                      colorOverride: bubbleSubtextColor,
                    ),
                ],
              ],
            ),
          );

    final double maxBubbleWidth = MediaQuery.of(context).size.width * 0.76 - 24.0; // 24 = horizontal padding
    final double metadataWidthEstimate = _calculateMetadataWidth(context);

    // Prepare Reply Widget if present
    Widget? replyWidget;
    double replyWidthEstimate = 0.0;

    if (message.hasReply) {
      replyWidget = MessageReplyInfo(
        replyInfo: message.replyInfo,
        isQuote: message.isQuote,
        quoteText: message.quoteText,
        isMe: isMe,
        currentUserId: currentUserId,
        onTap: () => onReplyTap?.call(
          message.replyToMessageId!,
          message.replyInfo?.chatId,
        ),
      );

      final String replyText = message.quoteText ?? message.replyInfo?.content ?? '';
      final String senderTitle = (message.replyInfo?.senderId == currentUserId ? 'Вы' : message.replyInfo?.senderName) ?? 'Сообщение';
      
      // Fast estimate avoiding synchronous TextPainter.layout() during build
      final double estimatedTextWidth = math.max(senderTitle.length * 8.0, replyText.length * 7.0);
      replyWidthEstimate = (estimatedTextWidth + 28.0).clamp(60.0, maxBubbleWidth);
    } else if (chatType == 'saved' && (message.forwardFromName?.isNotEmpty ?? false || message.senderName.isNotEmpty)) {
      replyWidget = MessageReplyInfo.forwarded(
        authorName: message.forwardFromName ?? message.senderName,
        isMe: isMe,
      );
      replyWidthEstimate = 120.0;
    }

    Widget? senderNameWidget;
    double senderNameWidthEstimate = 0.0;
    if (!isMe && senderName != null && senderName!.isNotEmpty) {
      final style = TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: effectivePreset.primaryColor,
      );
      // Measured precisely by RenderBubbleLayout during layout; fast baseline here
      senderNameWidthEstimate = (senderName!.length * 8.0).clamp(0.0, maxBubbleWidth);

      senderNameWidget = Padding(
        padding: const EdgeInsets.only(bottom: 4.0),
        child: Text(
          senderName!,
          style: style,
        ),
      );
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    Widget textBodyWidget;
    if (isBigEmoji) {
      textBodyWidget = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: GestureDetector(
          onTap: () => HapticUtils.tap(),
          child: EmojiUtils.appleEmoji(
            message.content,
            size: 64.0,
            fallbackStyle: textStyle,
          ),
        ),
      );
    } else {
      textBodyWidget = TextMessageWidget(
        text: message.content,
        style: textStyle,
        isMe: isMe,
        entities: message.entities,
        nameColorPreset: effectivePreset,
        replyStripStyle: effectiveStripStyle,
      );

      if (!hasMedia) {
        final previewOpts = message.linkPreviewOptions;
        final bool previewDisabled = previewOpts?.isDisabled ?? false;
        String? previewUrl = previewOpts?.url;
        if ((previewUrl == null || previewUrl.isEmpty) && !previewDisabled) {
          final urls = EntityParser.extractUrls(message.content);
          if (urls.isNotEmpty) {
            previewUrl = urls.first;
          } else if (message.entities.isNotEmpty) {
            for (final e in message.entities) {
              if ((e.type == 'text_link' || e.type == 'link' || e.type == 'url') &&
                  e.url != null &&
                  e.url!.isNotEmpty) {
                previewUrl = e.url;
                break;
              }
            }
          }
        }

        if (previewUrl != null && previewUrl.isNotEmpty && !previewDisabled) {
          final bool showAbove = previewOpts?.showAboveText ?? false;
          final bool preferLarge = previewOpts?.preferLargeMedia ?? false;
          final previewCard = LinkPreviewCard(
            url: EntityParser.normalizeUrl(previewUrl),
            preferLargeMedia: preferLarge,
            isDark: isDark,
          );

          textBodyWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: showAbove
                ? [
                    previewCard,
                    const SizedBox(height: 6.0),
                    textBodyWidget,
                  ]
                : [
                    textBodyWidget,
                    const SizedBox(height: 6.0),
                    previewCard,
                  ],
          );
        }
      }
    }

    Widget? mediaContentWidget;
    if (hasMedia) {
      final double mediaWidth = math.min(maxBubbleWidth, 340.0);
      final Widget mediaWidget = _buildMediaWidget(context, mediaWidth, resolvedFileUrl);

      Widget innerContent;
      if (_isRoundVideo || _isVoice) {
        innerContent = mediaWidget;
      } else if (hasCaption) {
        final Widget captionWidget = TextMessageWidget(
          text: message.content,
          style: textStyle,
          isMe: isMe,
          entities: message.entities,
          nameColorPreset: effectivePreset,
          replyStripStyle: effectiveStripStyle,
        );

        final bool invertMedia = message.invertMedia;
        innerContent = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: invertMedia
              ? [
                  captionWidget,
                  const SizedBox(height: 6.0),
                  mediaWidget,
                  const SizedBox(height: 3.0),
                  metadataWidget,
                ]
              : [
                  mediaWidget,
                  const SizedBox(height: 6.0),
                  captionWidget,
                  const SizedBox(height: 3.0),
                  metadataWidget,
                ],
        );
      } else if (_isImage || _isVideo) {
        innerContent = Stack(
          alignment: Alignment.bottomRight,
          children: [
            mediaWidget,
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _buildFloatingMetadata(context),
              ),
            ),
          ],
        );
      } else {
        innerContent = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            mediaWidget,
            const SizedBox(height: 3.0),
            metadataWidget,
          ],
        );
      }

      if (replyWidget != null || (!isMe && senderName != null && senderName!.isNotEmpty)) {
        mediaContentWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && senderName != null && senderName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  senderName!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: effectivePreset.primaryColor,
                  ),
                ),
              ),
            if (replyWidget != null) ...[
              if (_isRoundVideo)
                Container(
                  width: math.min(mediaWidth, 230.0),
                  margin: const EdgeInsets.only(bottom: 6.0),
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.9)
                        : Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: replyWidget,
                )
              else ...[
                SizedBox(width: _isVoice ? 240.0 : mediaWidth, child: replyWidget),
                const SizedBox(height: 4.0),
              ],
            ],
            innerContent,
          ],
        );
      } else {
        mediaContentWidget = innerContent;
      }
    }

    final EdgeInsets bubblePadding = (isBigEmoji || _isRoundVideo)
        ? EdgeInsets.zero
        : _isVoice
            ? const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0)
            : (hasMedia && !hasCaption && replyWidget == null && (senderName == null || senderName!.isEmpty || isMe))
                ? const EdgeInsets.all(4.0)
                : const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);

    final bool useOutgoingGradient = isMe &&
        (themeExt?.palette.chatBubbleOutgoingGradient != null &&
            themeExt!.palette.chatBubbleOutgoingGradient!.length >= 2) &&
        !isPureMedia &&
        !isBigEmoji &&
        !_isRoundVideo;

    final Widget bubbleContent = hasMedia
        ? mediaContentWidget!
        : MessageBubbleLayout(
            content: textBodyWidget,
            metadata: metadataWidget,
            text: message.content,
            textStyle: textStyle,
            hasBlockElement: endsWithBlock,
            isBigEmoji: isBigEmoji,
            replyWidget: replyWidget,
            replyWidth: replyWidthEstimate,
            senderNameWidget: senderNameWidget,
            senderNameWidth: senderNameWidthEstimate,
            metadataWidth: metadataWidthEstimate,
          );

    Widget bubbleCore = Container(
      margin: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 8.0),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.76,
      ),
      child: ViewportGradientBox(
        borderRadius: BorderRadius.circular(effectiveBubbleRadius),
        gradientColors: useOutgoingGradient ? themeExt?.palette.chatBubbleOutgoingGradient : null,
        solidColor: backgroundColor,
        child: Padding(
          padding: bubblePadding,
          child: bubbleContent,
        ),
      ),
    );

    Widget result = Align(
      alignment: alignment,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        color: isHighlighted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        child: bubbleCore,
      ),
    );

    // Reactions row below message bubble if present
    final effectiveReactions = reactions ?? (message.reactions.isNotEmpty ? message.reactions : null);
    if (effectiveReactions != null && effectiveReactions.isNotEmpty) {
      final effectiveMyReactions = myReactions ?? (myReaction != null && myReaction!.isNotEmpty ? {myReaction!} : message.myReactions);
      result = Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          result,
          Padding(
            padding: const EdgeInsets.only(top: 4.0, left: 12, right: 12),
            child: MessageReactionsRow(
              reactions: effectiveReactions,
              myReactions: effectiveMyReactions,
              myReaction: myReaction,
              onTap: onReactionTap,
            ),
          ),
        ],
      );
    }

    return result;
  }

  Widget _buildMediaWidget(
    BuildContext context,
    double maxWidth,
    String resolvedUrl,
  ) {
    if (_isRoundVideo) {
      final double circleSize = math.min(240.0, MediaQuery.of(context).size.width * 0.68);
      return VideoMessageWidget(
        key: ValueKey('vmsg_${message.id}'),
        messageId: message.id,
        videoUrl: resolvedUrl,
        size: circleSize,
        duration: message.duration != null && message.duration! > 0
            ? Duration(seconds: message.duration!)
            : null,
        thumbUrl: message.thumbUrl,
        thumbBase64: message.thumbBase64,
        fileSize: message.mediaFileSize,
        isMe: isMe,
        isRead: message.isRead,
        sendStatus: message.sendStatus,
        timeText: formatTime(message.createdAt),
        senderName: isMe ? null : senderName,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    if (_isVoice) {
      return VoiceMessageWidget(
        key: ValueKey('voice_${message.id}'),
        messageId: message.id,
        audioUrl: resolvedUrl,
        duration: message.duration != null && message.duration! > 0
            ? Duration(seconds: message.duration!)
            : null,
        waveform: message.waveform,
        fileSize: message.mediaFileSize,
        isMe: isMe,
        isRead: message.isRead,
        sendStatus: message.sendStatus,
        timeText: formatTime(message.createdAt),
        senderName: isMe ? null : senderName,
        onRetry: onRetry != null ? () => onRetry!(message) : null,
      );
    }

    if (_isImage) {
      final heroTag = 'msg_photo_${message.id}_$resolvedUrl';
      final thumbBase64 = message.thumbBase64;
      final autoDownload = MediaCacheManager.instance.shouldAutoDownload(
        messageType: 'image',
        fileSize: message.mediaFileSize,
      );

      return _SingleMediaBubbleWidget(
        url: resolvedUrl,
        thumbBase64: thumbBase64,
        fileSize: message.mediaFileSize,
        isVideo: false,
        maxWidth: maxWidth,
        autoDownload: autoDownload,
        heroTag: heroTag,
        onTap: ([localPath]) {
          FullscreenPhotoViewer.open(
            context,
            resolvedUrl,
            tag: heroTag,
            localFilePath: localPath,
          );
          onFileTap?.call(
            localPath ?? resolvedUrl,
            message.fileName ?? 'image.jpg',
            'image',
          );
        },
      );
    }

    if (_isVideo) {
      final autoDownload = MediaCacheManager.instance.shouldAutoDownload(
        messageType: 'video',
        fileSize: message.mediaFileSize,
      );

      return _SingleMediaBubbleWidget(
        url: resolvedUrl,
        thumbBase64: message.thumbBase64,
        thumbUrl: message.thumbUrl,
        fileSize: message.mediaFileSize,
        duration: message.mediaDuration ?? message.duration,
        isVideo: true,
        maxWidth: maxWidth,
        autoDownload: autoDownload,
        heroTag: 'msg_video_${message.id}_$resolvedUrl',
        onTap: ([localPath]) {
          onFileTap?.call(
            localPath ?? resolvedUrl,
            message.fileName ?? 'video.mp4',
            'video',
          );
        },
      );
    }

    if (_isAudio) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const iconoir.MusicNote(width: 28, height: 28, color: Color(0xFF0088CC)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.fileName ?? 'Audio',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      );
    }

    // Default: Document / File
    return DocumentMessageWidget(
      fileUrl: resolvedUrl,
      fileName: message.fileName ??
          (message.content.trim().isNotEmpty ? message.content.trim() : 'file'),
      fileSize: 0,
    );
  }

  Widget _buildFloatingMetadata(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (message.isEdited) ...[
          Text(
            context.l10n.translate('chat_edited'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          formatTime(message.createdAt),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          if (message.sendStatus == 0)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.0,
                color: Colors.white,
              ),
            )
          else if (message.sendStatus == 2)
            GestureDetector(
              onTap: () => onRetry?.call(message),
              child: const iconoir.WarningCircle(
                color: Colors.redAccent,
                width: 14,
                height: 14,
              ),
            )
          else
            MessageStatusWidget(
              isRead: message.isRead,
              isOutgoing: isMe,
              colorOverride: Colors.white.withValues(alpha: 0.9),
            ),
        ],
      ],
    );
  }

  double _calculateMetadataWidth(BuildContext context) {
    // Fast estimation avoiding synchronous TextPainter.layout() during build.
    // RenderBubbleLayout.performLayout also measures the actual metadata widget during layout.
    double width = 0.0;
    if (message.isEdited) {
      width += 40.0; // "изм." / "edited" label + padding
    }

    final timeStr = formatTime(message.createdAt);
    // 11pt font width estimation (~6.5-7px per character)
    width += timeStr.length * 7.0;

    if (isMe) {
      width += 4.0;
      if (message.sendStatus == 0) {
        width += 10.0;
      } else if (message.sendStatus == 2) {
        width += 14.0;
      } else {
        width += 15.0; // iconoir Check or DoubleCheck width
      }
    }

    return width.ceilToDouble();
  }
}

class _SingleMediaBubbleWidget extends StatefulWidget {
  final String url;
  final String? thumbBase64;
  final String? thumbUrl;
  final int? fileSize;
  final int? duration;
  final bool isVideo;
  final double maxWidth;
  final bool autoDownload;
  final String heroTag;
  final void Function([String? localPath]) onTap;

  const _SingleMediaBubbleWidget({
    Key? key,
    required this.url,
    this.thumbBase64,
    this.thumbUrl,
    this.fileSize,
    this.duration,
    required this.isVideo,
    required this.maxWidth,
    required this.autoDownload,
    required this.heroTag,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_SingleMediaBubbleWidget> createState() =>
      _SingleMediaBubbleWidgetState();
}

class _SingleMediaBubbleWidgetState extends State<_SingleMediaBubbleWidget> {
  File? _cachedFile;
  Uint8List? _cachedFirstFrame;
  bool _isPlayingInline = false;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    if (widget.url.isNotEmpty) {
      final f = await MediaCacheManager.instance.getCachedFile(widget.url);
      if (mounted && f != null) {
        setState(() => _cachedFile = f);
        if (widget.isVideo && _cachedFirstFrame == null) {
          _extractLocalFirstFrame(f.path);
        }
      }
    }
  }

  Future<void> _extractLocalFirstFrame(String filePath) async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.example.app/media_muxer');
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVideoThumbnail',
        {'videoPath': filePath},
      );
      if (res != null && res['thumbnail'] != null && mounted) {
        setState(() {
          _cachedFirstFrame = res['thumbnail'] as Uint8List?;
        });
      }
    } catch (_) {}
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCached = _cachedFile != null;
    final resolvedThumbUrl = widget.thumbUrl != null && widget.thumbUrl!.isNotEmpty
        ? (AppConfig.resolveMediaUrl(widget.thumbUrl!) ?? widget.thumbUrl!)
        : null;

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final double effectiveRadius = math.max(4.0, (themeExt?.bubbleRadius ?? 16.0) - 2.0);

    // If video is cached or auto-download allowed, and user tapped play inline:
    if (widget.isVideo &&
        (_isPlayingInline || (isCached && widget.autoDownload))) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: 280,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(effectiveRadius),
          child: InlineVideoPlayer(
            url: _cachedFile != null ? _cachedFile!.path : widget.url,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (!widget.isVideo) {
          widget.onTap(_cachedFile?.path);
        } else {
          if (isCached) {
            setState(() => _isPlayingInline = true);
          } else {
            widget.onTap();
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(effectiveRadius),
        child: Container(
          width: widget.maxWidth,
          height: 220,
          color: const Color(0xFF181818),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Blurred preview placeholder
              BlurredMediaPlaceholder(
                thumbBase64: widget.thumbBase64,
                fit: BoxFit.cover,
              ),

              // 2. Real first frame for video:
              // If video is already cached, show clear first frame.
              // If not cached, apply blur filter over the thumbnail so it stays blurred with download icon!
              if (widget.isVideo) ...[
                if (_cachedFirstFrame != null)
                  Image.memory(
                    _cachedFirstFrame!,
                    width: widget.maxWidth,
                    fit: BoxFit.cover,
                  )
                else if (resolvedThumbUrl != null && resolvedThumbUrl.isNotEmpty)
                  isCached
                      ? Image.network(
                          resolvedThumbUrl,
                          width: widget.maxWidth,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox.shrink();
                          },
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        )
                      : ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                          child: Transform.scale(
                            scale: 1.15,
                            child: Image.network(
                              resolvedThumbUrl,
                              width: widget.maxWidth,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox.shrink();
                              },
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
              ],

              // 3. Full image (if photo and (cached or auto-download enabled))
              if (!widget.isVideo) ...[
                if (_cachedFile != null)
                  Hero(
                    tag: widget.heroTag,
                    child: Image.file(
                      _cachedFile!,
                      width: widget.maxWidth,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (widget.url.isNotEmpty && widget.autoDownload)
                  Hero(
                    tag: widget.heroTag,
                    child: Image.network(
                      widget.url,
                      width: widget.maxWidth,
                      cacheWidth: (widget.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox.shrink();
                      },
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
              ],

              // 3. Download button / progress / size pill overlay
              if (widget.url.isNotEmpty && (!isCached || widget.isVideo))
                MediaDownloadButton(
                  url: widget.url,
                  fileSize: widget.fileSize,
                  isVideo: widget.isVideo,
                  onDownloaded: _checkCache,
                  onPlayVideo: () {
                    setState(() => _isPlayingInline = true);
                  },
                ),

              // 4. Video duration badge
              if (widget.isVideo &&
                  widget.duration != null &&
                  widget.duration! > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const iconoir.Play(
                          color: Colors.white,
                          width: 10,
                          height: 10,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(widget.duration!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
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
  }
}

