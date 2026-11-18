import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../screens/chat/group_chat_screen.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import 'chat_input_bar.dart';

/// Bottom action bar for channel screens supporting three Telegram-accurate states:
/// 1. Guest (`!isMember || myRole == 'guest'`): 44dp stadium capsule «Подписаться».
/// 2. Subscriber / non-posting participant: 44dp stadium «Выключить звук» / «Включить звук»
///    capsule plus an optional 44x44dp circular discussion button when [linkedChatId] exists.
/// 3. Admin with [canPostInChannel]: [ChatInputBar] with inline silent broadcast toggle.
class ChannelBottomCapsuleBar extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String? myRole;
  final bool isMember;
  final bool canPostInChannel;
  final bool isMuted;
  final String? linkedChatId;
  final String? linkedChatName;
  final String? linkedChatAvatar;
  final bool isSilentBroadcast;
  final ValueChanged<bool>? onToggleSilentBroadcast;
  final ValueChanged<bool>? onMuteChanged;
  final ValueChanged<Chat?>? onSubscribed;
  final VoidCallback? onOpenDiscussion;

  // Optional ChatInputBar props when rendered in admin posting mode
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final bool isEditing;
  final VoidCallback? onCancelEditing;
  final Message? replyToMessage;
  final bool isQuote;
  final String? quoteText;
  final int quoteOffset;
  final int quoteLength;
  final VoidCallback? onCancelReply;
  final VoidCallback? onTapReply;
  final List<File> attachedFiles;
  final List<String> attachedFileNames;
  final ValueChanged<int>? onRemoveAttachment;
  final bool isUploading;
  final ValueNotifier<double>? uploadProgressNotifier;
  final bool isSending;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSend;
  final SendDetailedCallback? onSendDetailed;
  final VoidCallback? onAttach;
  final VoidCallback? onEmoji;
  final VoidCallback? onStartVoiceRecord;
  final ValueChanged<Offset>? onVoiceRecordMove;
  final VoidCallback? onVoiceRecordEnd;
  final VoidCallback? onVoiceRecordCancel;
  final VoidCallback? onStartVideoRecord;
  final ValueChanged<Offset>? onVideoRecordMove;
  final VoidCallback? onVideoRecordEnd;
  final VoidCallback? onVideoRecordCancel;
  final String? currentUserId;
  final VoidCallback? onEditLastMessage;
  final bool isEmojiPanelOpen;
  final VoidCallback? onTapInputWhenEmojiOpen;
  final LinkPreviewOptions? linkPreviewOptions;
  final ValueChanged<LinkPreviewOptions?>? onLinkPreviewOptionsChanged;
  final bool invertMedia;
  final ValueChanged<bool>? onInvertMediaChanged;

  const ChannelBottomCapsuleBar({
    super.key,
    required this.channelId,
    this.channelName = '',
    this.myRole,
    this.isMember = true,
    this.canPostInChannel = false,
    this.isMuted = false,
    this.linkedChatId,
    this.linkedChatName,
    this.linkedChatAvatar,
    this.isSilentBroadcast = false,
    this.onToggleSilentBroadcast,
    this.onMuteChanged,
    this.onSubscribed,
    this.onOpenDiscussion,
    this.controller,
    this.focusNode,
    this.hintText,
    this.isEditing = false,
    this.onCancelEditing,
    this.replyToMessage,
    this.isQuote = false,
    this.quoteText,
    this.quoteOffset = 0,
    this.quoteLength = 0,
    this.onCancelReply,
    this.onTapReply,
    this.attachedFiles = const [],
    this.attachedFileNames = const [],
    this.onRemoveAttachment,
    this.isUploading = false,
    this.uploadProgressNotifier,
    this.isSending = false,
    this.onChanged,
    this.onSend,
    this.onSendDetailed,
    this.onAttach,
    this.onEmoji,
    this.onStartVoiceRecord,
    this.onVoiceRecordMove,
    this.onVoiceRecordEnd,
    this.onVoiceRecordCancel,
    this.onStartVideoRecord,
    this.onVideoRecordMove,
    this.onVideoRecordEnd,
    this.onVideoRecordCancel,
    this.currentUserId,
    this.onEditLastMessage,
    this.isEmojiPanelOpen = false,
    this.onTapInputWhenEmojiOpen,
    this.linkPreviewOptions,
    this.onLinkPreviewOptionsChanged,
    this.invertMedia = false,
    this.onInvertMediaChanged,
  });

  @override
  State<ChannelBottomCapsuleBar> createState() =>
      _ChannelBottomCapsuleBarState();
}

class _ChannelBottomCapsuleBarState extends State<ChannelBottomCapsuleBar> {
  static const double _kCapsuleHeight = 44.0;
  static const double _kCapsuleRadius = 22.0;

  TextEditingController? _fallbackController;
  bool _isJoining = false;
  bool? _optimisticMember;
  bool? _optimisticMuted;
  bool? _optimisticSilent;

  bool get _effectiveIsMember => _optimisticMember ?? widget.isMember;
  String? get _effectiveRole =>
      (_optimisticMember == true && widget.myRole == 'guest')
      ? 'subscriber'
      : widget.myRole;
  bool get _effectiveMuted => _optimisticMuted ?? widget.isMuted;
  bool get _effectiveSilent => _optimisticSilent ?? widget.isSilentBroadcast;

  @override
  void didUpdateWidget(covariant ChannelBottomCapsuleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMember != widget.isMember ||
        oldWidget.myRole != widget.myRole) {
      _optimisticMember = null;
    }
    if (oldWidget.isMuted != widget.isMuted) {
      _optimisticMuted = null;
    }
    if (oldWidget.isSilentBroadcast != widget.isSilentBroadcast) {
      _optimisticSilent = null;
    }
  }

  @override
  void dispose() {
    _fallbackController?.dispose();
    super.dispose();
  }

  TextEditingController get _effectiveController =>
      widget.controller ?? (_fallbackController ??= TextEditingController());

  Future<void> _handleSubscribe() async {
    if (_isJoining) return;
    HapticUtils.tap();
    setState(() {
      _isJoining = true;
      _optimisticMember = true;
    });

    final joinedChat = await ChatService.joinPublicChatModel(widget.channelId);
    if (!mounted) return;

    if (joinedChat != null) {
      setState(() => _isJoining = false);
      widget.onSubscribed?.call(joinedChat);
      GlassToastService().show(
        context,
        'Вы подписались на канал',
        iconWidget: iconoir.Megaphone(
          width: 18,
          height: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    } else {
      setState(() {
        _isJoining = false;
        _optimisticMember = null;
      });
      GlassToastService().show(context, 'Не удалось подписаться на канал');
    }
  }

  Future<void> _handleToggleMute() async {
    HapticUtils.tap();
    final currentMuted = _effectiveMuted;
    await ChatActionsHelper.toggleMute(
      chatId: widget.channelId,
      currentMuted: currentMuted,
      onMuteChanged: (newMuted) {
        if (!mounted) return;
        setState(() => _optimisticMuted = newMuted);
        widget.onMuteChanged?.call(newMuted);
      },
    );
  }

  void _handleOpenDiscussion() {
    HapticUtils.tap();
    if (widget.onOpenDiscussion != null) {
      widget.onOpenDiscussion!();
      return;
    }
    final linkedId = widget.linkedChatId;
    if (linkedId == null || linkedId.isEmpty) return;
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => GroupChatScreen(
          chatId: linkedId,
          groupName: widget.linkedChatName,
          groupAvatar: widget.linkedChatAvatar,
        ),
      ),
    );
  }

  void _handleToggleSilent(bool nextValue) {
    HapticUtils.selection();
    setState(() => _optimisticSilent = nextValue);
    widget.onToggleSilentBroadcast?.call(nextValue);

    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    GlassToastService().show(
      context,
      nextValue
          ? 'Тихая публикация: подписчики не получат звуковое уведомление'
          : 'Обычная публикация: уведомления со звуком включены',
      iconWidget: nextValue
          ? iconoir.BellOff(width: 18, height: 18, color: fg)
          : iconoir.Bell(width: 18, height: 18, color: fg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGuest = !_effectiveIsMember || _effectiveRole == 'guest';
    final bool isPostingAdmin =
        !isGuest &&
        widget.canPostInChannel &&
        (_effectiveRole == null ||
            _effectiveRole == 'owner' ||
            _effectiveRole == 'admin');

    final bool reduceAnimations = MediaQuery.disableAnimationsOf(context);
    final Duration animDuration = reduceAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    if (isPostingAdmin) {
      return ChatInputBar(
        controller: _effectiveController,
        focusNode: widget.focusNode,
        hintText: widget.hintText ?? 'Написать публикацию...',
        isEditing: widget.isEditing,
        onCancelEditing: widget.onCancelEditing,
        replyToMessage: widget.replyToMessage,
        isQuote: widget.isQuote,
        quoteText: widget.quoteText,
        quoteOffset: widget.quoteOffset,
        quoteLength: widget.quoteLength,
        onCancelReply: widget.onCancelReply,
        onTapReply: widget.onTapReply,
        attachedFiles: widget.attachedFiles,
        attachedFileNames: widget.attachedFileNames,
        onRemoveAttachment: widget.onRemoveAttachment,
        isUploading: widget.isUploading,
        uploadProgressNotifier: widget.uploadProgressNotifier,
        isSending: widget.isSending,
        onChanged: widget.onChanged,
        onSend: widget.onSend,
        onSendDetailed: widget.onSendDetailed,
        onAttach: widget.onAttach,
        onEmoji: widget.onEmoji,
        onStartVoiceRecord: widget.onStartVoiceRecord,
        onVoiceRecordMove: widget.onVoiceRecordMove,
        onVoiceRecordEnd: widget.onVoiceRecordEnd,
        onVoiceRecordCancel: widget.onVoiceRecordCancel,
        onStartVideoRecord: widget.onStartVideoRecord,
        onVideoRecordMove: widget.onVideoRecordMove,
        onVideoRecordEnd: widget.onVideoRecordEnd,
        onVideoRecordCancel: widget.onVideoRecordCancel,
        currentUserId: widget.currentUserId,
        onEditLastMessage: widget.onEditLastMessage,
        isEmojiPanelOpen: widget.isEmojiPanelOpen,
        onTapInputWhenEmojiOpen: widget.onTapInputWhenEmojiOpen,
        linkPreviewOptions: widget.linkPreviewOptions,
        onLinkPreviewOptionsChanged: widget.onLinkPreviewOptionsChanged,
        invertMedia: widget.invertMedia,
        onInvertMediaChanged: widget.onInvertMediaChanged,
        showSilentBroadcastToggle: true,
        isSilentBroadcast: _effectiveSilent,
        onToggleSilentBroadcast: _handleToggleSilent,
      );
    }

    final glassProvider = context.watch<LiquidGlassProvider?>();
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    final Color foregroundColor =
        themeExt?.palette.appBarForeground ??
        (isDark ? Colors.white : const Color(0xFF1C1C1E));
    final Color accentTextColor = isDark
        ? const Color(0xFF64C4FF)
        : Color.lerp(
            themeExt?.palette.primary ?? theme.colorScheme.primary,
            Colors.black,
            0.22,
          )!;

    final bool hasDiscussion =
        widget.linkedChatId != null && widget.linkedChatId!.isNotEmpty;

    final Widget barBody = isGuest
        ? _buildCapsuleSurface(
            context: context,
            glassProvider: glassProvider,
            isDark: isDark,
            themeExt: themeExt,
            onTap: _handleSubscribe,
            child: SizedBox(
              height: _kCapsuleHeight,
              child: Center(
                child: AnimatedSwitcher(
                  duration: animDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _isJoining
                      ? SizedBox(
                          key: const ValueKey('channel_sub_loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentTextColor,
                          ),
                        )
                      : Row(
                          key: const ValueKey('channel_sub_label'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconoir.Megaphone(
                              width: 18,
                              height: 18,
                              color: accentTextColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Подписаться',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: accentTextColor,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          )
        : Row(
            children: [
              Expanded(
                child: _buildCapsuleSurface(
                  context: context,
                  glassProvider: glassProvider,
                  isDark: isDark,
                  themeExt: themeExt,
                  onTap: _handleToggleMute,
                  child: SizedBox(
                    height: _kCapsuleHeight,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: animDuration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Row(
                          key: ValueKey<bool>(_effectiveMuted),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _effectiveMuted
                                ? iconoir.Bell(
                                    width: 18,
                                    height: 18,
                                    color: foregroundColor,
                                  )
                                : iconoir.BellOff(
                                    width: 18,
                                    height: 18,
                                    color: foregroundColor,
                                  ),
                            const SizedBox(width: 8),
                            Text(
                              _effectiveMuted
                                  ? 'Включить звук'
                                  : 'Выключить звук',
                              style: TextStyle(
                                fontSize: 15.0,
                                fontWeight: FontWeight.w600,
                                color: foregroundColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasDiscussion) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Обсуждение канала',
                  child: Tooltip(
                    message: 'Обсуждение',
                    child: SizedBox(
                      width: _kCapsuleHeight,
                      height: _kCapsuleHeight,
                      child: _buildCapsuleSurface(
                        context: context,
                        glassProvider: glassProvider,
                        isDark: isDark,
                        themeExt: themeExt,
                        onTap: _handleOpenDiscussion,
                        child: Center(
                          child: iconoir.ChatLines(
                            width: 20,
                            height: 20,
                            color: foregroundColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: barBody,
    );
  }

  Widget _buildCapsuleSurface({
    required BuildContext context,
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required TheavThemeExtension? themeExt,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final bool isGlassEnabled = glassProvider?.enabled ?? false;
    final Widget interactiveChild = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kCapsuleRadius),
        child: child,
      ),
    );

    if (isGlassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: _kCapsuleRadius,
        refractionIndex: 1.1,
        refractionWidth: 24.0,
      );
      return LiquidGlassLens(
        style: style,
        touch: const LiquidGlassTouch.flexing(
          LiquidGlassFlex(stretch: 6, squeeze: 0.65, lean: 0.3, grip: 0.5),
        ),
        child: interactiveChild,
      );
    }

    final defaultBg = isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.72);
    final pillBg = themeExt?.palette.appBarBackground ?? defaultBg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kCapsuleRadius),
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: Container(
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(_kCapsuleRadius),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: interactiveChild,
        ),
      ),
    );
  }
}
