import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../config/app_config.dart';
import '../../models/media_album.dart';
import '../../models/name_color_preset.dart';
import '../../models/profile_customization.dart';
import '../../models/theav_theme.dart';
import '../../screens/settings/profile_screen.dart';
import '../../services/chat_service.dart';
import '../../services/media_cache_manager.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/theav_theme_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/entity_parser.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../common/peer_badges_widget.dart';
import '../message/blurred_media_placeholder.dart';
import '../message/call_message_widget.dart';
import '../message/dice_message_widget.dart';
import '../message/document_message_widget.dart';
import '../message/fullscreen_photo_viewer.dart';
import '../message/inline_keyboard_widget.dart';
import '../message/inline_video_player.dart';
import '../message/media_album_widget.dart';
import '../message/media_download_button.dart';
import '../message/media_spoiler_overlay.dart';
import '../message/message_bubble.dart';
import '../message/message_interactive_state.dart';
import '../message/poll_message_widget.dart';
import '../message/sticker_message_widget.dart';
import '../message/text_message_widget.dart';
import '../message/theme_link_preview_card.dart';
import '../message/unsupported_message_widget.dart';
import '../message/video_message_widget.dart';
import '../message/voice_message_widget.dart';
import '../message/link_preview_card.dart';
import '../theme/viewport_gradient_box.dart';
import '../tiling/tile_viewport_scope.dart';
import '../user/avatar_with_status.dart';
import '../user/emoji_status_badge.dart';
import 'forward_chat_picker_sheet.dart';
import 'message_reply_info.dart';
import 'reactions_panel.dart';
import 'telegram_avatar_stack.dart';

/// Telegram-style broadcast post card for channel feeds (single post or media album).
///
/// Always left-aligned (`Alignment.centerLeft`) without a left avatar gutter,
/// supporting edge-to-edge top media, two-level author attribution
/// (`signMessages` / `showAuthorProfiles`), compact view counter, reactions,
/// quick-share circle button, and attached comments row.
class ChannelPostCard extends StatelessWidget {
  final Message? message;
  final MediaAlbum? album;
  final String currentUserId;
  final String channelName;
  final String? channelAvatar;
  final bool signMessages;
  final bool showAuthorProfiles;
  final String? linkedChatId;
  final bool? showCommentsRow;
  final ReactionSettings? reactionSettings;
  final Map<String, int>? reactionsOverride;
  final Set<String>? myReactionsOverride;
  final bool isHighlighted;
  final bool isSelected;
  final bool isSelectionMode;
  final String? highlightItemId;
  final String Function(String timestamp)? formatTime;
  final ValueChanged<String>? onReactionTap;
  final VoidCallback? onShareTap;
  final VoidCallback? onCommentsTap;
  final VoidCallback? onAuthorTap;
  final void Function(String replyToId, String? chatId)? onReplyTap;
  final void Function(String url, String name, String type)? onFileTap;
  final ValueChanged<Message>? onRetry;
  final VoidCallback? onBodyTap;
  final VoidCallback? onDoubleTap;
  final bool hasProtectedContent;
  final ValueChanged<String>? onInsertInlineQuery;

  const ChannelPostCard({
    super.key,
    this.message,
    this.album,
    this.currentUserId = '',
    this.channelName = '',
    this.channelAvatar,
    this.signMessages = false,
    this.showAuthorProfiles = false,
    this.linkedChatId,
    this.showCommentsRow,
    this.reactionSettings,
    this.reactionsOverride,
    this.myReactionsOverride,
    this.isHighlighted = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.highlightItemId,
    this.formatTime,
    this.onReactionTap,
    this.onShareTap,
    this.onCommentsTap,
    this.onAuthorTap,
    this.onReplyTap,
    this.onFileTap,
    this.onRetry,
    this.onBodyTap,
    this.onDoubleTap,
    this.hasProtectedContent = false,
    this.onInsertInlineQuery,
  }) : assert(
         message != null || album != null,
         'Either message or album must be provided to ChannelPostCard',
       );

  Message get effectiveMessage => message ?? album!.primaryMessage;

  /// Formats post view counts compactly (`942`, `1.4K`, `12.8K`, `1.5M`).
  static String formatViewsCount(int views) {
    if (views <= 0) return '0';
    if (views < 1000) return '$views';
    if (views < 1000000) {
      final double k = views / 1000.0;
      final String s = views >= 100000
          ? k.round().toString()
          : k.toStringAsFixed(1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}K';
    }
    final double m = views / 1000000.0;
    final String s = views >= 100000000
        ? m.round().toString()
        : m.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}M';
  }

  /// Formats Russian plural comment labels (`Прокомментировать`, `1 комментарий`, `3 комментария`, `5 комментариев`).
  static String formatCommentsLabel(int count) {
    if (count <= 0) return 'Прокомментировать';
    final mod100 = count % 100;
    final mod10 = count % 10;
    if (mod10 == 1 && mod100 != 11) return '$count комментарий';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count комментария';
    }
    return '$count комментариев';
  }

  ChannelPostCard copyWithKey(Key? newKey) {
    return ChannelPostCard(
      key: newKey,
      message: message,
      album: album,
      currentUserId: currentUserId,
      channelName: channelName,
      channelAvatar: channelAvatar,
      signMessages: signMessages,
      showAuthorProfiles: showAuthorProfiles,
      linkedChatId: linkedChatId,
      showCommentsRow: showCommentsRow,
      reactionSettings: reactionSettings,
      reactionsOverride: reactionsOverride,
      myReactionsOverride: myReactionsOverride,
      isHighlighted: false,
      isSelected: false,
      isSelectionMode: false,
      highlightItemId: null,
      formatTime: formatTime,
      onReactionTap: onReactionTap,
      onShareTap: onShareTap,
      onCommentsTap: onCommentsTap,
      onAuthorTap: onAuthorTap,
      onReplyTap: onReplyTap,
      onFileTap: onFileTap,
      onRetry: onRetry,
      onBodyTap: onBodyTap,
      onDoubleTap: onDoubleTap,
      hasProtectedContent: hasProtectedContent,
    );
  }

  bool get _hasSingleMedia {
    if (album != null) return false;
    final url = effectiveMessage.fileUrl?.trim();
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

  bool get _isSticker =>
      _hasSingleMedia && effectiveMessage.messageType == 'sticker';

  bool get _isGif =>
      _hasSingleMedia &&
      (effectiveMessage.messageType == 'gif' ||
          effectiveMessage.messageType == 'animation');

  bool get _isRoundVideo =>
      _hasSingleMedia &&
      (effectiveMessage.isRound || effectiveMessage.messageType == 'round');

  bool get _isVoice =>
      _hasSingleMedia && effectiveMessage.messageType == 'voice';

  bool get _isAudio =>
      _hasSingleMedia &&
      !_isVoice &&
      (effectiveMessage.messageType == 'audio' ||
          _isAudioUrl(effectiveMessage.fileUrl!));

  bool get _isImage =>
      _hasSingleMedia &&
      !_isSticker &&
      !_isGif &&
      (effectiveMessage.messageType == 'image' ||
          effectiveMessage.messageType == 'photo' ||
          _isImageUrl(effectiveMessage.fileUrl!));

  bool get _isVideo =>
      _hasSingleMedia &&
      !_isSticker &&
      !_isGif &&
      !_isRoundVideo &&
      (effectiveMessage.messageType == 'video' ||
          _isVideoUrl(effectiveMessage.fileUrl!));

  bool get _hasSingleCaption {
    if (!_hasSingleMedia || _isRoundVideo || _isVoice || _isSticker || _isGif) {
      return false;
    }
    final trimmed = effectiveMessage.content.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == effectiveMessage.fileName) return false;
    if (trimmed == effectiveMessage.fileUrl) return false;
    return true;
  }

  String _resolveTimeString(Message msg) {
    if (formatTime != null) return formatTime!(msg.createdAt);
    return DateTimeUtils.formatTimeHHmm(msg.createdAt);
  }

  Color _resolveAuthorColor(Message msg, String authorId) {
    if (msg.senderNameColorId != null && msg.senderNameColorId!.isNotEmpty) {
      return NameColorPresets.getById(msg.senderNameColorId!).primaryColor;
    }
    final idx =
        (authorId.isNotEmpty ? authorId.hashCode : msg.senderId.hashCode)
            .abs() %
        NameColorPresets.defaults.length;
    return NameColorPresets.defaults[idx].primaryColor;
  }

  void _defaultOpenAuthorProfile(
    BuildContext context,
    String authorId,
    String authorName,
    String? avatarUrl,
  ) {
    if (authorId.isEmpty || authorId == '0') return;
    HapticUtils.tap();
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: authorId,
          initialName: authorName,
          initialAvatarUrl: avatarUrl,
        ),
      ),
    );
  }

  void _defaultSharePost(BuildContext context, Message msg) {
    if (msg.chatId.isEmpty || msg.id.isEmpty) return;
    final ids = album != null
        ? album!.items.map((e) => e.id).where((id) => id.isNotEmpty).toList()
        : <String>[msg.id];
    if (ids.isEmpty) return;
    ForwardChatPickerSheet.show(
      context,
      fromChatId: msg.chatId,
      messageIds: ids,
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = effectiveMessage;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final bool reduceAnimations = MediaQuery.disableAnimationsOf(context);
    final Duration animDuration = reduceAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    final bool showHighlighted =
        isSelected ||
        isHighlighted ||
        (highlightItemId != null &&
            (msg.id == highlightItemId ||
                (album?.items.any((it) => it.id == highlightItemId) ??
                    false)));

    final Color cardBgColor = showHighlighted
        ? (themeExt?.palette.chatBubbleIncomingSelected ??
              Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.22),
                theme.colorScheme.secondaryContainer,
              ))
        : (themeExt?.palette.chatBubbleIncoming ??
              theme.colorScheme.secondaryContainer);

    final Color textColor =
        themeExt?.palette.chatBubbleIncomingText ??
        theme.colorScheme.onSecondaryContainer;
    final Color subtextColor =
        themeExt?.palette.chatBubbleIncomingSubtext ??
        textColor.withValues(alpha: 0.72);
    final Color accentColor =
        themeExt?.palette.primary ?? theme.colorScheme.primary;
    final Color dividerColor =
        themeExt?.palette.divider ?? textColor.withValues(alpha: 0.12);

    final List<Color>? activeGradientColors = showHighlighted
        ? (themeExt?.palette.chatBubbleIncomingSelectedGradient ??
              themeExt?.palette.chatBubbleIncomingGradient)
        : themeExt?.palette.chatBubbleIncomingGradient;
    final bool useGradient =
        activeGradientColors != null && activeGradientColors.length >= 2;

    // Two-level author attribution rules:
    // 1. signMessages && showAuthorProfiles => clickable author header at top
    // 2. signMessages && !showAuthorProfiles => plain authorSignature in footer
    // 3. !signMessages => clean broadcast card without author name or avatar
    final bool showTopAuthorHeader = signMessages && showAuthorProfiles;
    final String authorId =
        (msg.postAuthorId != null && msg.postAuthorId!.isNotEmpty)
        ? msg.postAuthorId!
        : msg.senderId;
    final String resolvedAuthorName =
        (msg.senderName.isNotEmpty && msg.senderName != 'Unknown')
        ? msg.senderName
        : (msg.authorSignature?.trim().isNotEmpty == true
              ? msg.authorSignature!.trim()
              : (channelName.isNotEmpty ? channelName : 'Автор'));
    final String? inlineSignature =
        (signMessages &&
            !showAuthorProfiles &&
            msg.authorSignature != null &&
            msg.authorSignature!.trim().isNotEmpty)
        ? msg.authorSignature!.trim()
        : null;

    final bool hasCommentsBar =
        showCommentsRow ??
        ((linkedChatId != null && linkedChatId!.isNotEmpty) || msg.canComment);
    final bool showShareButton =
        !isSelectionMode && !hasProtectedContent && msg.messageType != 'system';

    final double viewportWidth = TileViewportScope.widthOf(context);
    final double specCardWidth = (viewportWidth - 56.0).clamp(260.0, 520.0);

    final effectiveReactions =
        reactionsOverride ?? (msg.reactions.isNotEmpty ? msg.reactions : null);
    final effectiveMyReactions =
        myReactionsOverride ??
        (msg.myReactions.isNotEmpty ? msg.myReactions : const <String>{});
    final bool hasReactions =
        effectiveReactions != null && effectiveReactions.isNotEmpty;

    final Color shareBgColor =
        themeExt?.palette.chatDateBadge ??
        (isDark
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.28));
    final Color shareIconColor =
        themeExt?.palette.chatDateBadgeText ?? Colors.white;

    final Widget postRow = LayoutBuilder(
      builder: (context, constraints) {
        final double reserveRight = showShareButton ? 58.0 : 20.0;
        final double cardWidth = constraints.maxWidth.isFinite
            ? math.min(
                specCardWidth,
                math.max(200.0, constraints.maxWidth - reserveRight),
              )
            : specCardWidth;

        final Widget cardColumn = _buildCardColumn(
          context: context,
          msg: msg,
          cardWidth: cardWidth,
          theme: theme,
          isDark: isDark,
          themeExt: themeExt,
          textColor: textColor,
          subtextColor: subtextColor,
          accentColor: accentColor,
          dividerColor: dividerColor,
          showTopAuthorHeader: showTopAuthorHeader,
          authorId: authorId,
          resolvedAuthorName: resolvedAuthorName,
          inlineSignature: inlineSignature,
          hasReactions: hasReactions,
          effectiveReactions: effectiveReactions,
          effectiveMyReactions: effectiveMyReactions,
          hasCommentsBar: hasCommentsBar,
        );

        final Widget cardContainer = MetaData(
          metaData: 'message_bubble_box',
          child: Container(
            margin: EdgeInsets.only(
              left: 12.0,
              right: showShareButton ? 4.0 : 8.0,
              top: 4.0,
              bottom: 4.0,
            ),
            width: cardWidth,
            decoration: BoxDecoration(
              color: useGradient ? null : cardBgColor,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.05),
                  blurRadius: 8.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: useGradient
                ? ViewportGradientBox(
                    borderRadius: BorderRadius.circular(16.0),
                    gradientColors: activeGradientColors,
                    solidColor: cardBgColor,
                    child: cardColumn,
                  )
                : cardColumn,
          ),
        );

        final Widget decoratedCard =
            (!isSelectionMode && (onBodyTap != null || onDoubleTap != null))
            ? GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onBodyTap,
                onDoubleTap: onDoubleTap,
                child: cardContainer,
              )
            : cardContainer;

        final Widget cardWithShare = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            decoratedCard,
            if (showShareButton)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: SizedBox(
                  width: 44.0,
                  height: 44.0,
                  child: Semantics(
                    button: true,
                    label: 'Поделиться постом',
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkResponse(
                        onTap: () {
                          HapticUtils.tap();
                          if (onShareTap != null) {
                            onShareTap!();
                          } else {
                            _defaultSharePost(context, msg);
                          }
                        },
                        radius: 22.0,
                        child: Center(
                          child: Container(
                            width: 36.0,
                            height: 36.0,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: shareBgColor,
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.14 : 0.24,
                                ),
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: iconoir.ShareIos(
                                width: 18.0,
                                height: 18.0,
                                color: shareIconColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

        final Widget leftAlignedCard = Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              cardWithShare,
              if (msg.inlineKeyboard.isNotEmpty && msg.id.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 12.0,
                    right: 8.0,
                    top: 2.0,
                    bottom: 2.0,
                  ),
                  child: InlineKeyboardWidget(
                    chatId: msg.chatId,
                    messageId: msg.id,
                    rows: msg.inlineKeyboard,
                    maxWidth: cardWidth,
                    botId: msg.viaBotId ?? msg.senderId,
                    botUsername: msg.viaBotUsername,
                    onInsertText: onInsertInlineQuery,
                    onSwitchInlineQuery: onInsertInlineQuery,
                  ),
                ),
            ],
          ),
        );

        if (isSelectionMode) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10.0, right: 2.0),
                child: MessageSelectionCheckbox(isSelected: isSelected),
              ),
              Expanded(child: IgnorePointer(child: leftAlignedCard)),
            ],
          );
        }

        return leftAlignedCard;
      },
    );

    final Color rowHighlightColor =
        themeExt?.palette.messageSelectionOverlay ??
        theme.colorScheme.primary.withValues(alpha: 0.18);

    final String interactiveKey =
        (msg.localId != null && msg.localId!.isNotEmpty)
        ? msg.localId!
        : (msg.id.isNotEmpty ? msg.id : 'ch_post_${msg.content.hashCode}');

    return MessageInteractiveScope(
      messageKey: interactiveKey,
      child: AnimatedContainer(
        duration: animDuration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        color: showHighlighted ? rowHighlightColor : Colors.transparent,
        child: postRow,
      ),
    );
  }

  Widget _buildCardColumn({
    required BuildContext context,
    required Message msg,
    required double cardWidth,
    required ThemeData theme,
    required bool isDark,
    required TheavThemeExtension? themeExt,
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
    required Color dividerColor,
    required bool showTopAuthorHeader,
    required String authorId,
    required String resolvedAuthorName,
    required String? inlineSignature,
    required bool hasReactions,
    required Map<String, int>? effectiveReactions,
    required Set<String> effectiveMyReactions,
    required bool hasCommentsBar,
  }) {
    final List<Widget> children = [];

    // 1. Clickable author header (Level 2b: signMessages && showAuthorProfiles)
    if (showTopAuthorHeader) {
      final Color authorColor = _resolveAuthorColor(msg, authorId);
      final PeerCustomization? authorCust =
          (authorId.isNotEmpty && authorId != '0')
          ? (PeerCustomizationCache.instance.getSync(authorId) ??
                msg.senderCustomization)
          : msg.senderCustomization;
      final bool canOpenAuthor =
          onAuthorTap != null || (authorId.isNotEmpty && authorId != '0');

      children.add(
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: canOpenAuthor
                ? (onAuthorTap ??
                      () => _defaultOpenAuthorProfile(
                        context,
                        authorId,
                        resolvedAuthorName,
                        msg.senderAvatarUrl,
                      ))
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 9.0, 12.0, 6.0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  AvatarWithStatus(
                    userId: (authorId.isNotEmpty && authorId != '0')
                        ? authorId
                        : null,
                    avatarUrl: msg.senderAvatarUrl,
                    name: resolvedAuthorName,
                    radius: 10.0,
                    isOnline: false,
                    showDecoration: false,
                  ),
                  const SizedBox(width: 6.0),
                  Flexible(
                    child: Text(
                      resolvedAuthorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: authorColor,
                      ),
                    ),
                  ),
                  if (authorCust?.activeEmojiStatus != null) ...[
                    const SizedBox(width: 4.0),
                    EmojiStatusBadge(
                      status: authorCust!.activeEmojiStatus,
                      size: 14.0,
                      animate: false,
                      interactive: false,
                      fallbackColor: authorColor,
                    ),
                  ],
                  if (authorCust?.visibleBadge != null)
                    PeerBadgesRow(
                      badge: authorCust!.visibleBadge,
                      interactiveBadge: false,
                      accentColor: authorColor,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 2. Forward / Reply header inside card
    Widget? replyOrForwardWidget;
    if (msg.hasReply) {
      replyOrForwardWidget = MessageReplyInfo(
        replyInfo: msg.replyInfo,
        isQuote: msg.isQuote,
        quoteText: msg.quoteText,
        quoteOffset: msg.quoteOffset,
        quoteLength: msg.quoteLength,
        isMe: false,
        currentUserId: currentUserId,
        onTap: () =>
            onReplyTap?.call(msg.replyToMessageId!, msg.replyInfo?.chatId),
      );
    } else if (msg.forwardFromName != null && msg.forwardFromName!.isNotEmpty) {
      replyOrForwardWidget = MessageReplyInfo.forwarded(
        authorName: msg.forwardFromName!,
        authorAvatarUrl: msg.forwardFromAvatarUrl,
        isMe: false,
      );
    }

    if (replyOrForwardWidget != null) {
      children.add(
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0,
            showTopAuthorHeader ? 2.0 : 9.0,
            12.0,
            6.0,
          ),
          child: replyOrForwardWidget,
        ),
      );
    }

    final bool hasTopHeader =
        showTopAuthorHeader || replyOrForwardWidget != null;

    // 3. Album OR Single Message body
    if (album != null) {
      final albumWidget = MediaAlbumWidget(
        album: album!,
        isMe: false,
        currentUserId: currentUserId,
        chatType: 'channel',
        formatTime: formatTime,
        onFileTap: onFileTap,
        isHighlighted: isHighlighted,
        highlightItemId: highlightItemId,
        isSelected: false,
        isSelectionMode: false,
        isChannelCard: true,
        suppressMargin: true,
        suppressFooter: true,
        overrideWidth: cardWidth,
        hasProtectedContent: hasProtectedContent,
        overrideBorderRadius: hasTopHeader
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(16.0)),
      );

      final Widget? albumCaptionWidget = album!.hasCaption
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                12.0,
                msg.invertMedia ? (hasTopHeader ? 2.0 : 10.0) : 8.0,
                12.0,
                msg.invertMedia ? 8.0 : 2.0,
              ),
              child: MetaData(
                metaData: 'message_selectable_content',
                child: _buildRichPostText(
                  context: context,
                  msg: msg,
                  text: album!.caption!,
                  entities: album!.entities,
                  textColor: textColor,
                  themeExt: themeExt,
                  isDark: isDark,
                  includeLinkPreview: false,
                ),
              ),
            )
          : null;

      if (msg.invertMedia && albumCaptionWidget != null) {
        children.add(albumCaptionWidget);
        children.add(albumWidget);
      } else {
        children.add(albumWidget);
        if (albumCaptionWidget != null) {
          children.add(albumCaptionWidget);
        }
      }
    } else {
      children.addAll(
        _buildSingleMessageBody(
          context: context,
          msg: msg,
          cardWidth: cardWidth,
          theme: theme,
          isDark: isDark,
          themeExt: themeExt,
          textColor: textColor,
          subtextColor: subtextColor,
          accentColor: accentColor,
          hasTopHeader: hasTopHeader,
        ),
      );
    }

    // 4. Reactions row inside card below text
    if (hasReactions) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12.0, 6.0, 12.0, 2.0),
          child: MessageReactionsRow(
            reactions: effectiveReactions!,
            myReactions: effectiveMyReactions,
            onTap: onReactionTap,
          ),
        ),
      );
    }

    // 5. Footer metadata row: [Eye 14dp] 1.4K · <authorSignature> · (изм.) · HH:mm
    children.add(
      Padding(
        padding: EdgeInsets.fromLTRB(
          12.0,
          hasReactions ? 4.0 : 6.0,
          12.0,
          hasCommentsBar ? 8.0 : 9.0,
        ),
        child: _buildFooterMetadataRow(
          msg: msg,
          subtextColor: subtextColor,
          inlineSignature: inlineSignature,
        ),
      ),
    );

    // 6. Attached comments row (42dp+ height, 0.5dp divider)
    if (hasCommentsBar) {
      children.add(Container(height: 0.5, color: dividerColor));
      children.add(
        _buildCommentsBar(
          context: context,
          msg: msg,
          accentColor: accentColor,
          subtextColor: subtextColor,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  List<Widget> _buildSingleMessageBody({
    required BuildContext context,
    required Message msg,
    required double cardWidth,
    required ThemeData theme,
    required bool isDark,
    required TheavThemeExtension? themeExt,
    required Color textColor,
    required Color subtextColor,
    required Color accentColor,
    required bool hasTopHeader,
  }) {
    final String? resolvedFileUrl = AppConfig.resolveMediaUrl(msg.fileUrl);
    final bool hasMedia =
        !msg.isUnsupported &&
        _hasSingleMedia &&
        resolvedFileUrl != null &&
        resolvedFileUrl.isNotEmpty;
    final bool hasCaption = !msg.isUnsupported && _hasSingleCaption;

    if (msg.isUnsupported) {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0,
            hasTopHeader ? 2.0 : 10.0,
            12.0,
            2.0,
          ),
          child: UnsupportedMessageWidget(
            message: msg,
            isMe: false,
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            accentColor: accentColor,
          ),
        ),
      ];
    }

    if (msg.messageType == 'poll') {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0,
            hasTopHeader ? 2.0 : 10.0,
            12.0,
            2.0,
          ),
          child: PollMessageWidget(
            chatId: msg.chatId,
            messageId: msg.id,
            currentUserId: currentUserId,
            questionFallback: msg.content,
            pollData: msg.mediaPayload,
            isMe: false,
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            accentColor: accentColor,
          ),
        ),
      ];
    }

    if (msg.messageType == 'call') {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0,
            hasTopHeader ? 2.0 : 10.0,
            12.0,
            2.0,
          ),
          child: CallMessageWidget(message: msg, isMine: false),
        ),
      ];
    }

    if (hasMedia) {
      if (_isImage || _isVideo) {
        final double mediaHeight = _computeSingleMediaHeight(msg, cardWidth);
        final Widget mediaWidget = MediaSpoilerOverlay(
          messageId: msg.id,
          hasSpoiler: msg.hasMediaSpoiler,
          borderRadius: 0.0,
          child: _SingleChannelMediaView(
            key: ValueKey('ch_media_${msg.id}_$resolvedFileUrl'),
            messageId: msg.id,
            url: resolvedFileUrl,
            thumbBase64: msg.thumbBase64,
            thumbUrl: msg.thumbUrl,
            fileSize: msg.mediaFileSize,
            duration: msg.mediaDuration ?? msg.duration,
            isVideo: _isVideo,
            width: cardWidth,
            height: mediaHeight,
            topRadius: hasTopHeader ? 0.0 : 16.0,
            autoDownload: MediaCacheManager.instance.shouldAutoDownload(
              messageType: _isVideo ? 'video' : 'image',
              fileSize: msg.mediaFileSize,
            ),
            onTap: ([localPath]) {
              if (_isVideo) {
                onFileTap?.call(
                  localPath ?? resolvedFileUrl,
                  msg.fileName ?? 'video.mp4',
                  'video',
                );
              } else {
                FullscreenPhotoViewer.open(
                  context,
                  resolvedFileUrl,
                  tag: 'ch_photo_${msg.id}_$resolvedFileUrl',
                  localFilePath: localPath,
                  hasProtectedContent: hasProtectedContent,
                );
              }
            },
          ),
        );

        final Widget? captionWidget = hasCaption
            ? Padding(
                padding: EdgeInsets.fromLTRB(
                  12.0,
                  msg.invertMedia ? (hasTopHeader ? 2.0 : 10.0) : 8.0,
                  12.0,
                  msg.invertMedia ? 8.0 : 2.0,
                ),
                child: MetaData(
                  metaData: 'message_selectable_content',
                  child: _buildRichPostText(
                    context: context,
                    msg: msg,
                    text: msg.content,
                    entities: msg.entities,
                    textColor: textColor,
                    themeExt: themeExt,
                    isDark: isDark,
                    includeLinkPreview: false,
                  ),
                ),
              )
            : null;

        if (msg.invertMedia && captionWidget != null) {
          return [captionWidget, mediaWidget];
        }
        return [mediaWidget, if (captionWidget != null) captionWidget];
      }

      if (_isGif) {
        final meta = msg.mediaPayload ?? const <String, dynamic>{};
        return [
          Padding(
            padding: EdgeInsets.fromLTRB(
              10.0,
              hasTopHeader ? 4.0 : 10.0,
              10.0,
              2.0,
            ),
            child: Center(
              child: GifMessageWidget(
                key: ValueKey('ch_gif_${msg.localId ?? msg.id}'),
                gifUrl: resolvedFileUrl,
                previewUrl: meta['preview_url']?.toString(),
                width: msg.mediaWidth,
                height: msg.mediaHeight,
              ),
            ),
          ),
        ];
      }

      if (_isSticker) {
        final meta = msg.mediaPayload ?? const <String, dynamic>{};
        return [
          Padding(
            padding: EdgeInsets.fromLTRB(
              12.0,
              hasTopHeader ? 4.0 : 10.0,
              12.0,
              2.0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StickerMessageWidget(
                key: ValueKey('ch_sticker_${msg.localId ?? msg.id}'),
                imageUrl: resolvedFileUrl,
                thumbnailUrl: meta['thumbnail_url']?.toString(),
                format: meta['format']?.toString() ?? 'webp',
                stickerId: meta['sticker_id']?.toString(),
                packId: meta['pack_id']?.toString(),
                effectAnimationUrl: meta['effect_animation_url']?.toString(),
                fallbackEmoji: msg.content.trim().isNotEmpty
                    ? msg.content.trim()
                    : null,
                isSentByMe: false,
                autoPlayEffect: false,
                messageKeyId: msg.localId ?? msg.id,
              ),
            ),
          ),
        ];
      }

      if (_isRoundVideo) {
        final double circleSize = math.min(220.0, cardWidth - 24.0);
        return [
          Padding(
            padding: EdgeInsets.fromLTRB(
              12.0,
              hasTopHeader ? 4.0 : 10.0,
              12.0,
              2.0,
            ),
            child: Center(
              child: VideoMessageWidget(
                key: ValueKey('ch_vmsg_${msg.id}'),
                messageId: msg.id,
                videoUrl: resolvedFileUrl,
                size: circleSize,
                duration: msg.duration != null && msg.duration! > 0
                    ? Duration(seconds: msg.duration!)
                    : null,
                thumbUrl: msg.thumbUrl,
                thumbBase64: msg.thumbBase64,
                fileSize: msg.mediaFileSize,
                isMe: false,
                isRead: true,
                sendStatus: msg.sendStatus,
                timeText: _resolveTimeString(msg),
                onRetry: onRetry != null ? () => onRetry!(msg) : null,
                chatId: msg.chatId,
                chatType: 'channel',
                chatTitle: channelName,
              ),
            ),
          ),
        ];
      }

      if (_isVoice || _isAudio) {
        final effectiveDurSec = msg.duration ?? msg.mediaDuration;
        return [
          Padding(
            padding: EdgeInsets.fromLTRB(
              8.0,
              hasTopHeader ? 2.0 : 8.0,
              8.0,
              2.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                VoiceMessageWidget(
                  key: ValueKey('ch_audio_${msg.id}'),
                  messageId: msg.id,
                  audioUrl: resolvedFileUrl,
                  title: _isAudio ? (msg.fileName ?? 'Audio') : null,
                  duration: effectiveDurSec != null && effectiveDurSec > 0
                      ? Duration(seconds: effectiveDurSec)
                      : null,
                  waveform: msg.waveform,
                  fileSize: msg.mediaFileSize,
                  isMe: false,
                  isRead: true,
                  isListened: true,
                  sendStatus: msg.sendStatus,
                  timeText: null,
                  onRetry: onRetry != null ? () => onRetry!(msg) : null,
                  chatId: msg.chatId,
                  chatType: 'channel',
                  chatTitle: channelName,
                ),
                if (hasCaption)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4.0, 6.0, 4.0, 0.0),
                    child: MetaData(
                      metaData: 'message_selectable_content',
                      child: _buildRichPostText(
                        context: context,
                        msg: msg,
                        text: msg.content,
                        entities: msg.entities,
                        textColor: textColor,
                        themeExt: themeExt,
                        isDark: isDark,
                        includeLinkPreview: false,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ];
      }

      // Document / File
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0,
            hasTopHeader ? 2.0 : 10.0,
            12.0,
            2.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DocumentMessageWidget(
                fileUrl: resolvedFileUrl,
                fileName:
                    msg.fileName ??
                    (msg.content.trim().isNotEmpty
                        ? msg.content.trim()
                        : 'file'),
                fileSize: (msg.mediaFileSize ?? 0).toDouble(),
              ),
              if (hasCaption)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: MetaData(
                    metaData: 'message_selectable_content',
                    child: _buildRichPostText(
                      context: context,
                      msg: msg,
                      text: msg.content,
                      entities: msg.entities,
                      textColor: textColor,
                      themeExt: themeExt,
                      isDark: isDark,
                      includeLinkPreview: false,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ];
    }

    // Dice or plain text post
    if (msg.messageType == 'dice' || EmojiUtils.isDiceEmoji(msg.content)) {
      final val = msg.mediaPayload?['value'];
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0,
            hasTopHeader ? 4.0 : 10.0,
            12.0,
            4.0,
          ),
          child: Center(
            child: DiceMessageWidget(
              key: ValueKey('ch_dice_${msg.localId ?? msg.id}'),
              emoji: msg.content,
              value: val is num ? val.toInt() : null,
              isMe: false,
              size: 112.0,
              autoPlay: false,
            ),
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: EdgeInsets.fromLTRB(
          12.0,
          hasTopHeader ? 2.0 : 10.0,
          12.0,
          2.0,
        ),
        child: MetaData(
          metaData: 'message_selectable_content',
          child: _buildRichPostText(
            context: context,
            msg: msg,
            text: msg.content,
            entities: msg.entities,
            textColor: textColor,
            themeExt: themeExt,
            isDark: isDark,
            includeLinkPreview: true,
          ),
        ),
      ),
    ];
  }

  double _computeSingleMediaHeight(Message msg, double cardWidth) {
    final w = msg.mediaWidth ?? 0;
    final h = msg.mediaHeight ?? 0;
    if (w > 0 && h > 0) {
      final double aspect = (w / h).clamp(0.55, 2.4).toDouble();
      return (cardWidth / aspect).clamp(150.0, 380.0).toDouble();
    }
    return 220.0;
  }

  Widget _buildRichPostText({
    required BuildContext context,
    required Message msg,
    required String text,
    required List<MessageEntity> entities,
    required Color textColor,
    required TheavThemeExtension? themeExt,
    required bool isDark,
    required bool includeLinkPreview,
  }) {
    final TextStyle style = TextStyle(
      fontSize: themeExt?.messageFontSize ?? 15.5,
      height: 1.25,
      leadingDistribution: TextLeadingDistribution.even,
      color: textColor,
    );

    final NameColorPreset preset =
        (msg.senderNameColorId != null && msg.senderNameColorId!.isNotEmpty)
        ? NameColorPresets.getById(msg.senderNameColorId!)
        : NameColorPresets.defaults.first;
    final ReplyStripStyle stripStyle = ReplyStripStyle.values.firstWhere(
      (s) => s.name == msg.senderReplyStripStyle,
      orElse: () => ReplyStripStyle.solid,
    );

    final Widget textWidget = TextMessageWidget(
      text: text,
      style: style,
      isMe: false,
      entities: entities,
      nameColorPreset: preset,
      replyStripStyle: stripStyle,
    );

    if (!includeLinkPreview) return textWidget;

    final previewOpts = msg.linkPreviewOptions;
    final bool previewDisabled = previewOpts?.isDisabled ?? false;
    String? previewUrl = previewOpts?.url;
    if (previewUrl != null && EntityParser.isInternalStorageUrl(previewUrl)) {
      previewUrl = null;
    }
    if ((previewUrl == null || previewUrl.isEmpty) && !previewDisabled) {
      if (text.contains('http://') ||
          text.contains('https://') ||
          text.contains('www.')) {
        for (final u in EntityParser.extractUrls(text)) {
          if (!EntityParser.isInternalStorageUrl(u)) {
            previewUrl = u;
            break;
          }
        }
      }
      if ((previewUrl == null || previewUrl.isEmpty) && entities.isNotEmpty) {
        for (final e in entities) {
          if ((e.type == 'text_link' || e.type == 'link' || e.type == 'url') &&
              e.url != null &&
              e.url!.isNotEmpty &&
              !EntityParser.isInternalStorageUrl(e.url!)) {
            previewUrl = e.url;
            break;
          }
        }
      }
    }

    final bool hasEffectivePreview =
        previewUrl != null &&
        previewUrl.isNotEmpty &&
        !previewDisabled &&
        !EntityParser.isInternalStorageUrl(previewUrl);
    if (!hasEffectivePreview) return textWidget;

    final bool showAbove = previewOpts?.showAboveText ?? false;
    final bool preferLarge = previewOpts?.preferLargeMedia ?? false;
    final String? themeCode = TheavThemeService.extractThemeCode(previewUrl);
    final Widget previewCard = themeCode != null
        ? ThemeLinkPreviewCard(
            code: themeCode,
            isDark: isDark,
            isMe: false,
            preset: preset,
            stripStyle: stripStyle,
          )
        : LinkPreviewCard(
            url: EntityParser.normalizeUrl(previewUrl),
            preferLargeMedia: preferLarge,
            isDark: isDark,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: showAbove
          ? [previewCard, const SizedBox(height: 6.0), textWidget]
          : [textWidget, const SizedBox(height: 6.0), previewCard],
    );
  }

  Widget _buildFooterMetadataRow({
    required Message msg,
    required Color subtextColor,
    required String? inlineSignature,
  }) {
    final int displayViews = msg.viewsCount > 0 ? msg.viewsCount : 1;
    final String viewsStr = formatViewsCount(displayViews);
    final String timeStr = _resolveTimeString(msg);

    final TextStyle metaStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w400,
      color: subtextColor,
      height: 1.15,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (msg.isSilent) ...[
          iconoir.BellOff(width: 12.0, height: 12.0, color: subtextColor),
          const SizedBox(width: 5.0),
        ],
        iconoir.Eye(width: 14.0, height: 14.0, color: subtextColor),
        const SizedBox(width: 4.0),
        Text(viewsStr, style: metaStyle),
        if (msg.forwardsCount > 0) ...[
          const SizedBox(width: 8.0),
          iconoir.ForwardMessage(
            width: 13.0,
            height: 13.0,
            color: subtextColor,
          ),
          const SizedBox(width: 3.0),
          Text(formatViewsCount(msg.forwardsCount), style: metaStyle),
        ],
        if (inlineSignature != null && inlineSignature.isNotEmpty) ...[
          Text(' · ', style: metaStyle),
          Flexible(
            child: Text(
              inlineSignature,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          ),
        ],
        if (msg.isEdited) ...[
          Text(' · ', style: metaStyle),
          Text(
            '(изм.)',
            style: metaStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
        Text(' · ', style: metaStyle),
        Text(timeStr, style: metaStyle),
        if (msg.sendStatus == 0) ...[
          const SizedBox(width: 5.0),
          SizedBox(
            width: 10.0,
            height: 10.0,
            child: CircularProgressIndicator(
              strokeWidth: 1.2,
              color: subtextColor,
            ),
          ),
        ] else if (msg.sendStatus == 2) ...[
          const SizedBox(width: 5.0),
          GestureDetector(
            onTap: () => onRetry?.call(msg),
            child: const iconoir.WarningCircle(
              width: 14.0,
              height: 14.0,
              color: Colors.redAccent,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCommentsBar({
    required BuildContext context,
    required Message msg,
    required Color accentColor,
    required Color subtextColor,
  }) {
    final int count = msg.commentsCount;
    final String label = formatCommentsLabel(count);
    final List<Map<String, dynamic>> repliers = msg.recentRepliers
        .take(3)
        .map((r) => r.toJson())
        .toList();

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onCommentsTap != null
            ? () {
                HapticUtils.tap();
                onCommentsTap!();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                if (count > 0 && repliers.isNotEmpty)
                  TelegramAvatarStack(
                    users: repliers,
                    maxCount: 3,
                    size: 22.0,
                  )
                else
                  iconoir.ChatBubble(
                    width: 18.0,
                    height: 18.0,
                    color: accentColor,
                  ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
                iconoir.NavArrowRight(
                  width: 16.0,
                  height: 16.0,
                  color: count > 0 ? accentColor : subtextColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SingleChannelMediaView extends StatefulWidget {
  final String messageId;
  final String url;
  final String? thumbBase64;
  final String? thumbUrl;
  final int? fileSize;
  final int? duration;
  final bool isVideo;
  final double width;
  final double height;
  final double topRadius;
  final bool autoDownload;
  final void Function([String? localPath]) onTap;

  const _SingleChannelMediaView({
    super.key,
    required this.messageId,
    required this.url,
    this.thumbBase64,
    this.thumbUrl,
    this.fileSize,
    this.duration,
    required this.isVideo,
    required this.width,
    required this.height,
    required this.topRadius,
    required this.autoDownload,
    required this.onTap,
  });

  @override
  State<_SingleChannelMediaView> createState() =>
      _SingleChannelMediaViewState();
}

class _SingleChannelMediaViewState extends State<_SingleChannelMediaView> {
  final GlobalKey<MediaDownloadButtonState> _downloadButtonKey =
      GlobalKey<MediaDownloadButtonState>();
  File? _cachedFile;
  Uint8List? _cachedFirstFrame;
  bool _isPlayingInline = false;

  @override
  void initState() {
    super.initState();
    _syncCacheImmediate();
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant _SingleChannelMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _cachedFile = null;
      _cachedFirstFrame = null;
      _isPlayingInline = false;
      _syncCacheImmediate();
      _checkCache();
    }
  }

  void _syncCacheImmediate() {
    if (widget.url.isEmpty) return;
    final syncFile = MediaCacheManager.instance.getCachedFileSync(widget.url);
    if (syncFile != null) {
      _cachedFile = syncFile;
      if (widget.isVideo) {
        _cachedFirstFrame = MediaCacheManager.instance
            .getCachedVideoThumbnailSync(syncFile.path);
      }
    }
  }

  Future<void> _checkCache() async {
    if (widget.url.isEmpty) return;
    final f = await MediaCacheManager.instance.getCachedFile(widget.url);
    if (mounted && f != null) {
      if (_cachedFile?.path != f.path) {
        setState(() => _cachedFile = f);
      }
      if (widget.isVideo && _cachedFirstFrame == null) {
        final syncThumb = MediaCacheManager.instance
            .getCachedVideoThumbnailSync(f.path);
        if (syncThumb != null) {
          setState(() => _cachedFirstFrame = syncThumb);
        } else {
          _extractLocalFirstFrame(f.path);
        }
      }
    }
  }

  Future<void> _extractLocalFirstFrame(String filePath) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.example.app/media_muxer');
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVideoThumbnail',
        {'videoPath': filePath},
      );
      final bytes = res != null ? res['thumbnail'] as Uint8List? : null;
      if (bytes != null) {
        MediaCacheManager.instance.cacheVideoThumbnail(filePath, bytes);
        if (mounted) {
          setState(() => _cachedFirstFrame = bytes);
        }
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
    final resolvedThumbUrl =
        widget.thumbUrl != null && widget.thumbUrl!.isNotEmpty
        ? (AppConfig.resolveMediaUrl(widget.thumbUrl!) ?? widget.thumbUrl!)
        : null;
    final radius = BorderRadius.vertical(top: Radius.circular(widget.topRadius));

    if (widget.isVideo && isCached && _isPlayingInline) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: widget.width,
          height: math.max(widget.height, 220.0),
          child: InlineVideoPlayer(url: _cachedFile!.path, autoplay: true),
        ),
      );
    }

    final bool hasOpaqueMedia =
        (!widget.isVideo && _cachedFile != null) ||
        (widget.isVideo && isCached && _cachedFirstFrame != null);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int targetCacheWidth = (widget.width * dpr).round().clamp(240, 1280);

    return GestureDetector(
      onTap: () {
        if (!isCached) {
          _downloadButtonKey.currentState?.handleTap();
          return;
        }
        if (!widget.isVideo) {
          widget.onTap(_cachedFile?.path);
        } else {
          setState(() => _isPlayingInline = true);
        }
      },
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFF181818),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!hasOpaqueMedia)
                BlurredMediaPlaceholder(
                  thumbBase64: widget.thumbBase64,
                  fit: BoxFit.cover,
                ),
              if (widget.isVideo && isCached) ...[
                if (_cachedFirstFrame != null)
                  Image.memory(
                    _cachedFirstFrame!,
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                  )
                else if (resolvedThumbUrl != null &&
                    resolvedThumbUrl.isNotEmpty)
                  Image.network(
                    resolvedThumbUrl,
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.cover,
                    cacheWidth: targetCacheWidth,
                    filterQuality: FilterQuality.low,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const SizedBox.shrink(),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
              ],
              if (!widget.isVideo && _cachedFile != null)
                Hero(
                  tag: 'ch_photo_${widget.messageId}_${widget.url}',
                  child: Image.file(
                    _cachedFile!,
                    width: widget.width,
                    height: widget.height,
                    cacheWidth: targetCacheWidth,
                    filterQuality: FilterQuality.low,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              if (widget.url.isNotEmpty && (!isCached || widget.isVideo))
                MediaDownloadButton(
                  key: _downloadButtonKey,
                  url: widget.url,
                  fileSize: widget.fileSize,
                  isVideo: widget.isVideo,
                  autoDownload: widget.autoDownload,
                  onDownloaded: _checkCache,
                  onPlayVideo: () {
                    if (_cachedFile != null) {
                      setState(() => _isPlayingInline = true);
                    }
                  },
                ),
              if (widget.isVideo &&
                  widget.duration != null &&
                  widget.duration! > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
