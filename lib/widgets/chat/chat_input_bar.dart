import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/entity_parser.dart';
import '../design_system/theav_design_system.dart';
import '../user/avatar_with_status.dart';
import 'link_preview_input_bar.dart';
import 'liquid_glass_input_field.dart';
import 'reply_preview_bar.dart';

/// Callback when sending message with complete rich-text and preview options
typedef SendDetailedCallback = void Function(
  String cleanText,
  List<MessageEntity> entities,
  LinkPreviewOptions? linkPreviewOptions,
  bool invertMedia,
);

/// Unified chat input bar component managing text entry, attachments preview,
/// formatting toolbar, link preview configuration bar, editing banner,
/// reply/quote preview, and uploading progress.
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final bool isEditing;
  final String? editingTitle;
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
  final double uploadProgress;
  final ValueNotifier<double>? uploadProgressNotifier;
  final bool isSending;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSend;
  final SendDetailedCallback? onSendDetailed;
  final VoidCallback? onAttach;
  final VoidCallback? onEmoji;
  final VoidCallback? onVoice;
  final VoidCallback? onStartVoiceRecord;
  final ValueChanged<Offset>? onVoiceRecordMove;
  final VoidCallback? onVoiceRecordEnd;
  final VoidCallback? onVoiceRecordCancel;
  final VoidCallback? onStartVideoRecord;
  final ValueChanged<Offset>? onVideoRecordMove;
  final VoidCallback? onVideoRecordEnd;
  final VoidCallback? onVideoRecordCancel;
  final String? currentUserId;
  final Widget? trailing;
  final LinkPreviewOptions? linkPreviewOptions;
  final ValueChanged<LinkPreviewOptions?>? onLinkPreviewOptionsChanged;
  final bool invertMedia;
  final ValueChanged<bool>? onInvertMediaChanged;
  final VoidCallback? onEditLastMessage;
  final bool isEmojiPanelOpen;
  final VoidCallback? onTapInputWhenEmojiOpen;
  final bool showBotCommandsButton;
  final bool isBotCommandsOpen;
  final VoidCallback? onToggleBotCommands;
  final String? botMenuWebAppLabel;
  final VoidCallback? onOpenBotMenuWebApp;
  final bool hasReplyKeyboard;
  final bool isReplyKeyboardOpen;
  final VoidCallback? onToggleReplyKeyboard;
  final int slowmodeRemainingSeconds;
  final bool showSilentBroadcastToggle;
  final bool isSilentBroadcast;
  final ValueChanged<bool>? onToggleSilentBroadcast;
  final bool canSendMedia;
  final bool canSendStickersGifs;
  final bool canSendPolls;
  final bool isAnonymousAdmin;
  final String? anonymousGroupAvatarUrl;
  final VoidCallback? onSendLongPress;
  final Widget? forwardPreviewBanner;
  final int scheduledCount;
  final VoidCallback? onOpenScheduled;
  final Widget? sendAsLeadingWidget;

  const ChatInputBar({
    Key? key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.isEditing = false,
    this.editingTitle,
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
    this.uploadProgress = 0.0,
    this.uploadProgressNotifier,
    this.isSending = false,
    this.onChanged,
    this.onSend,
    this.onSendDetailed,
    this.onAttach,
    this.onEmoji,
    this.onVoice,
    this.onStartVoiceRecord,
    this.onVoiceRecordMove,
    this.onVoiceRecordEnd,
    this.onVoiceRecordCancel,
    this.onStartVideoRecord,
    this.onVideoRecordMove,
    this.onVideoRecordEnd,
    this.onVideoRecordCancel,
    this.currentUserId,
    this.trailing,
    this.linkPreviewOptions,
    this.onLinkPreviewOptionsChanged,
    this.invertMedia = false,
    this.onInvertMediaChanged,
    this.onEditLastMessage,
    this.isEmojiPanelOpen = false,
    this.onTapInputWhenEmojiOpen,
    this.showBotCommandsButton = false,
    this.isBotCommandsOpen = false,
    this.onToggleBotCommands,
    this.botMenuWebAppLabel,
    this.onOpenBotMenuWebApp,
    this.hasReplyKeyboard = false,
    this.isReplyKeyboardOpen = false,
    this.onToggleReplyKeyboard,
    this.slowmodeRemainingSeconds = 0,
    this.showSilentBroadcastToggle = false,
    this.isSilentBroadcast = false,
    this.onToggleSilentBroadcast,
    this.canSendMedia = true,
    this.canSendStickersGifs = true,
    this.canSendPolls = true,
    this.isAnonymousAdmin = false,
    this.anonymousGroupAvatarUrl,
    this.onSendLongPress,
    this.forwardPreviewBanner,
    this.scheduledCount = 0,
    this.onOpenScheduled,
    this.sendAsLeadingWidget,
  }) : super(key: key);

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _internalInvertMedia = false;
  LinkPreviewOptions? _internalLinkPreviewOptions;
  bool _linkPreviewDismissed = false;
  List<String> _detectedUrls = [];

  bool get _effectiveInvertMedia =>
      widget.invertMedia || _internalInvertMedia;

  LinkPreviewOptions? get _effectiveLinkPreviewOptions =>
      widget.linkPreviewOptions ?? _internalLinkPreviewOptions;

  @override
  void initState() {
    super.initState();
    _internalInvertMedia = widget.invertMedia;
    _internalLinkPreviewOptions = widget.linkPreviewOptions;
    widget.controller.addListener(_handleTextChange);
    _extractUrls(widget.controller.text);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      widget.controller.addListener(_handleTextChange);
      _extractUrls(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleTextChange() {
    _extractUrls(widget.controller.text);
  }

  void _extractUrls(String text) {
    final urls = <String>[
      for (final u in EntityParser.extractUrls(text))
        if (!EntityParser.isInternalStorageUrl(u)) u,
    ];
    if (widget.controller is RichTextEditingController) {
      final richCtrl = widget.controller as RichTextEditingController;
      for (final span in richCtrl.spans) {
        if ((span.type == 'text_link' || span.type == 'link' || span.type == 'url') &&
            span.url != null &&
            span.url!.trim().isNotEmpty) {
          final u = EntityParser.normalizeUrl(span.url!);
          if (!EntityParser.isInternalStorageUrl(u) && !urls.contains(u)) {
            urls.add(u);
          }
        }
      }
    }

    if (_detectedUrls.length != urls.length ||
        !_detectedUrls.every(urls.contains)) {
      setState(() {
        _detectedUrls = urls;
        if (urls.isEmpty) {
          _internalLinkPreviewOptions = null;
          _linkPreviewDismissed = false;
        } else if (!_linkPreviewDismissed) {
          if (_internalLinkPreviewOptions == null ||
              _internalLinkPreviewOptions!.url == null ||
              !urls.contains(_internalLinkPreviewOptions!.url)) {
            _internalLinkPreviewOptions = LinkPreviewOptions(url: urls.first);
          }
        }
      });
    }
  }

  void _handleSend() {
    if (widget.onSendDetailed != null) {
      final String cleanText;
      final List<MessageEntity> entities;

      if (widget.controller is RichTextEditingController) {
        final richCtrl = widget.controller as RichTextEditingController;
        cleanText = richCtrl.cleanText;
        entities = richCtrl.entities;
      } else {
        final parsed = EntityParser.parseMarkdown(widget.controller.text);
        cleanText = parsed.cleanText;
        entities = parsed.entities;
      }

      // Trim only spaces and enters at the very end of the text.
      // Consecutive spaces and enters inside the text are preserved without changes.
      final trimmedText = cleanText.trimRight();
      final hasAttachments = widget.attachedFiles.isNotEmpty;
      if (trimmedText.isEmpty && !hasAttachments) {
        return;
      }

      final maxLen = trimmedText.length;
      final adjustedEntities = <MessageEntity>[];
      for (final e in entities) {
        if (e.offset >= maxLen) continue;
        if (e.offset + e.length > maxLen) {
          final clampedLength = maxLen - e.offset;
          if (clampedLength > 0) {
            adjustedEntities.add(e.copyWith(length: clampedLength));
          }
        } else {
          adjustedEntities.add(e);
        }
      }

      LinkPreviewOptions? sendPreviewOptions = _effectiveLinkPreviewOptions;
      if (sendPreviewOptions != null &&
          sendPreviewOptions.url != null &&
          EntityParser.isInternalStorageUrl(sendPreviewOptions.url!)) {
        sendPreviewOptions = null;
      }
      if (sendPreviewOptions == null &&
          !_linkPreviewDismissed &&
          _detectedUrls.isNotEmpty) {
        sendPreviewOptions = LinkPreviewOptions(url: _detectedUrls.first);
      }

      widget.onSendDetailed!(
        trimmedText,
        adjustedEntities,
        sendPreviewOptions,
        _effectiveInvertMedia,
      );
    } else {
      if (widget.controller.text.trim().isEmpty &&
          widget.attachedFiles.isEmpty) {
        return;
      }
      widget.onSend?.call();
    }
    widget.controller.clear();
    setState(() {
      _internalInvertMedia = false;
      _internalLinkPreviewOptions = null;
      _linkPreviewDismissed = false;
    });
  }

  bool _isImageFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  Widget _buildEditingBanner(
    BuildContext context,
    bool glassEnabled,
    bool isLite,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          iconoir.EditPencil(
            color: theme.colorScheme.primary,
            width: 16,
            height: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.editingTitle ??
                  context.l10n.translate('chat_editing_title'),
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          if (widget.onCancelEditing != null)
            IconButton(
              icon: iconoir.Xmark(
                width: 18,
                height: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: widget.onCancelEditing,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );

    if (glassEnabled) {
      final glassProvider = LiquidGlassProvider.maybeOf(context);
      if (glassProvider != null) {
        final style = glassProvider.createStyle(
          context: context,
          cornerRadius: 16,
          refractionIndex: 1.1,
          refractionWidth: 24,
          isLiteOverride: isLite,
        );
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: LiquidGlassLens(
            style: style,
            child: content,
          ),
        );
      }
    }

    final blurEnabled = BlurUtils.shouldBlurMaterialHud(context);
    final baseBg = Theme.of(context).colorScheme.surface;
    final bannerBg = BlurUtils.resolveMaterialHudColor(
      baseBg,
      isDark: isDark,
      blurEnabled: blurEnabled,
    );
    final Widget card = Container(
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: blurEnabled ? 0.6 : 0.5,
        ),
      ),
      child: content,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: blurEnabled
            ? BackdropFilter.grouped(
                filter: BlurUtils.createMaterialHudBlur(sigma: 10.0),
                child: card,
              )
            : card,
      ),
    );
  }

  Widget _wrapContextualPill(
    BuildContext context, {
    required bool glassEnabled,
    required bool isLite,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (glassEnabled) {
      final glassProvider = LiquidGlassProvider.maybeOf(context);
      if (glassProvider != null) {
        final style = glassProvider.createStyle(
          context: context,
          cornerRadius: 16,
          refractionIndex: 1.1,
          refractionWidth: 24,
          isLiteOverride: isLite,
        );
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: LiquidGlassLens(
            style: style,
            child: child,
          ),
        );
      }
    }
    final blurEnabled = BlurUtils.shouldBlurMaterialHud(context);
    final baseBg = Theme.of(context).colorScheme.surface;
    final pillBg = BlurUtils.resolveMaterialHudColor(
      baseBg,
      isDark: isDark,
      blurEnabled: blurEnabled,
    );
    final Widget card = Container(
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: blurEnabled ? 0.6 : 0.5,
        ),
      ),
      child: child,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: blurEnabled
            ? BackdropFilter.grouped(
                filter: BlurUtils.createMaterialHudBlur(sigma: 10.0),
                child: card,
              )
            : card,
      ),
    );
  }

  Widget _buildAnonymousAdminBanner(
    BuildContext context,
    bool glassEnabled,
    bool isLite,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color accentColor = isDark
        ? const Color(0xFF66C7F4)
        : theme.colorScheme.primary;
    final Color textColor = theme.colorScheme.onSurface.withValues(alpha: 0.92);
    final hasAvatar = widget.anonymousGroupAvatarUrl != null &&
        widget.anonymousGroupAvatarUrl!.trim().isNotEmpty;

    return _wrapContextualPill(
      context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasAvatar) ...[
              AvatarWithStatus(
                avatarUrl: widget.anonymousGroupAvatarUrl,
                name: 'G',
                radius: 10,
                isOnline: false,
                showDecoration: false,
                animateDecoration: false,
              ),
              const SizedBox(width: 6),
            ],
            iconoir.ShieldCheck(
              width: 15,
              height: 15,
              color: accentColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'От имени группы',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestrictedStickersBanner(
    BuildContext context,
    bool glassEnabled,
    bool isLite,
  ) {
    final theme = Theme.of(context);
    final Color textColor = theme.colorScheme.onSurface.withValues(alpha: 0.9);

    return _wrapContextualPill(
      context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Lock(
              width: 14,
              height: 14,
              color: textColor.withValues(alpha: 0.78),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Стикеры и GIF ограничены',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSilentBroadcastButton(
    BuildContext context,
    bool glassEnabled,
    bool isLite,
    LiquidGlassProvider? glassProvider,
  ) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final Color activeColor =
        themeExt?.palette.primary ?? theme.colorScheme.primary;
    final Color inactiveColor =
        theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.8 : 0.75);

    final Widget iconSwitcher = AnimatedSwitcher(
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: widget.isSilentBroadcast
          ? iconoir.BellOff(
              key: const ValueKey('silent_bell_off'),
              width: 20,
              height: 20,
              color: activeColor,
            )
          : iconoir.Bell(
              key: const ValueKey('silent_bell_on'),
              width: 20,
              height: 20,
              color: inactiveColor,
            ),
    );

    final Widget innerTap = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () =>
            widget.onToggleSilentBroadcast?.call(!widget.isSilentBroadcast),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: iconSwitcher),
        ),
      ),
    );

    final Widget capsule;
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: 22,
        refractionIndex: 1.1,
        refractionWidth: 20,
        isLiteOverride: isLite,
      );
      capsule = LiquidGlassLens(
        style: style,
        child: Container(
          decoration: widget.isSilentBroadcast
              ? BoxDecoration(
                  color: activeColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                )
              : null,
          child: innerTap,
        ),
      );
    } else {
      final blurEnabled = BlurUtils.shouldBlurMaterialHud(context);
      final rawBg = themeExt?.palette.explicitChatInputBackground ??
          themeExt?.palette.surface ??
          (isDark ? const Color(0xFF1C1C1E) : Colors.white);
      final resolvedRaw = widget.isSilentBroadcast
          ? Color.alphaBlend(
              activeColor.withValues(alpha: isDark ? 0.22 : 0.14),
              rawBg,
            )
          : rawBg;
      final bg = BlurUtils.resolveMaterialHudColor(
        resolvedRaw,
        isDark: isDark,
        blurEnabled: blurEnabled,
      );
      final Widget circle = Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.isSilentBroadcast
                ? activeColor.withValues(alpha: 0.45)
                : (isDark ? Colors.white12 : Colors.black12),
            width: blurEnabled ? 0.6 : 0.5,
          ),
        ),
        child: innerTap,
      );
      capsule = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: blurEnabled
            ? BackdropFilter.grouped(
                filter: BlurUtils.createMaterialHudBlur(sigma: 10.0),
                child: circle,
              )
            : circle,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 10),
      child: Semantics(
        button: true,
        toggled: widget.isSilentBroadcast,
        label: widget.isSilentBroadcast
            ? 'Беззвучная отправка включена'
            : 'Беззвучная отправка выключена',
        child: Tooltip(
          message: widget.isSilentBroadcast ? 'Без звука' : 'Со звуком',
          child: SizedBox(
            width: 44,
            height: 44,
            child: capsule,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    final hasLinkPreview = _detectedUrls.isNotEmpty &&
        _effectiveLinkPreviewOptions != null &&
        !_effectiveLinkPreviewOptions!.isDisabled;

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Link Preview Input Bar (when URLs detected and not disabled)
        _GlassSafeAnimatedSection(
          visible: hasLinkPreview,
          child: hasLinkPreview
              ? LinkPreviewInputBar(
                  options: _effectiveLinkPreviewOptions!,
                  detectedUrls: _detectedUrls,
                  enabled: glassEnabled,
                  isLite: isLite,
                  onOptionsChanged: (opts) {
                    setState(() => _internalLinkPreviewOptions = opts);
                    widget.onLinkPreviewOptionsChanged?.call(opts);
                  },
                  onRemove: () {
                    const disabled = LinkPreviewOptions(isDisabled: true);
                    setState(() {
                      _internalLinkPreviewOptions = disabled;
                      _linkPreviewDismissed = true;
                    });
                    widget.onLinkPreviewOptionsChanged?.call(disabled);
                  },
                )
              : null,
        ),

        // 2. Editing message banner
        _GlassSafeAnimatedSection(
          visible: widget.isEditing,
          child: widget.isEditing
              ? _buildEditingBanner(context, glassEnabled, isLite)
              : null,
        ),

        // 3a. Staged forward preview bar
        _GlassSafeAnimatedSection(
          visible: widget.forwardPreviewBanner != null,
          child: widget.forwardPreviewBanner,
        ),

        // 3b. Reply/Quote preview bar
        _GlassSafeAnimatedSection(
          visible: widget.replyToMessage != null,
          child: widget.replyToMessage != null
              ? ReplyPreviewBar(
                  replyToMessage: widget.replyToMessage!,
                  isQuote: widget.isQuote,
                  quoteText: widget.quoteText,
                  quoteOffset: widget.quoteOffset,
                  quoteLength: widget.quoteLength,
                  onClose: widget.onCancelReply ?? () {},
                  onTap: widget.onTapReply,
                  enabled: glassEnabled,
                  isLite: isLite,
                  currentUserId: widget.currentUserId,
                )
              : null,
        ),

        // 4. Attached files preview list
        _GlassSafeAnimatedSection(
          visible: widget.attachedFiles.isNotEmpty,
          child: widget.attachedFiles.isNotEmpty
              ? Container(
                  height: 80,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.attachedFiles.length,
                    itemBuilder: (context, index) {
                      final fileName = index < widget.attachedFileNames.length
                          ? widget.attachedFileNames[index]
                          : '';
                      return Container(
                        width: 80,
                        margin: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _isImageFile(fileName)
                                    ? Image.file(
                                        widget.attachedFiles[index],
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: Colors.grey[300],
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const iconoir.Page(
                                              width: 28,
                                              height: 28,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              fileName,
                                              style:
                                                  const TextStyle(fontSize: 10),
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            if (widget.onRemoveAttachment != null)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () =>
                                      widget.onRemoveAttachment!(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const iconoir.Xmark(
                                      color: Colors.white,
                                      width: 14,
                                      height: 14,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                )
              : null,
        ),

        // 5. Upload progress
        if (widget.isUploading)
          widget.uploadProgressNotifier != null
              ? ValueListenableBuilder<double>(
                  valueListenable: widget.uploadProgressNotifier!,
                  builder: (context, progress, _) => LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    backgroundColor: Colors.grey[300],
                  ),
                )
              : LinearProgressIndicator(
                  value: widget.uploadProgress > 0 ? widget.uploadProgress : null,
                  backgroundColor: Colors.grey[300],
                ),

        // 5b. Anonymous admin banner («От имени группы»)
        _GlassSafeAnimatedSection(
          visible: widget.isAnonymousAdmin,
          child: widget.isAnonymousAdmin
              ? _buildAnonymousAdminBanner(context, glassEnabled, isLite)
              : null,
        ),

        // 5c. Stickers/GIFs restricted notice when emoji panel is open
        _GlassSafeAnimatedSection(
          visible: !widget.canSendStickersGifs && widget.isEmojiPanelOpen,
          child: (!widget.canSendStickersGifs && widget.isEmojiPanelOpen)
              ? _buildRestrictedStickersBanner(context, glassEnabled, isLite)
              : null,
        ),

        // 6. Input field row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.sendAsLeadingWidget != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 7),
                child: widget.sendAsLeadingWidget!,
              ),
            Expanded(
              child: LiquidGlassInputField(
                enabled: glassEnabled,
                isLite: isLite,
                controller: widget.controller,
                focusNode: widget.focusNode,
                hintText: widget.hintText ??
                    (widget.attachedFiles.isNotEmpty
                        ? (AppLocalizations.of(context)
                                ?.translate('chat_add_caption') ??
                            'Add a caption...')
                        : (AppLocalizations.of(context)
                                ?.translate('chat_type_message') ??
                            'Сообщение')),
                onChanged: widget.onChanged,
                onSend: widget.isSending ? null : _handleSend,
                onSendLongPress: widget.isSending ? null : widget.onSendLongPress,
                onAttach: widget.canSendMedia ? widget.onAttach : null,
                onEmoji: widget.onEmoji,
                onVoice: widget.canSendMedia ? widget.onVoice : null,
                onStartVoiceRecord:
                    widget.canSendMedia ? widget.onStartVoiceRecord : null,
                onVoiceRecordMove:
                    widget.canSendMedia ? widget.onVoiceRecordMove : null,
                onVoiceRecordEnd:
                    widget.canSendMedia ? widget.onVoiceRecordEnd : null,
                onVoiceRecordCancel:
                    widget.canSendMedia ? widget.onVoiceRecordCancel : null,
                onStartVideoRecord:
                    widget.canSendMedia ? widget.onStartVideoRecord : null,
                onVideoRecordMove:
                    widget.canSendMedia ? widget.onVideoRecordMove : null,
                onVideoRecordEnd:
                    widget.canSendMedia ? widget.onVideoRecordEnd : null,
                onVideoRecordCancel:
                    widget.canSendMedia ? widget.onVideoRecordCancel : null,
                isSending: widget.isSending,
                hasAttachments: widget.attachedFiles.isNotEmpty,
                onEditLastMessage: widget.isEditing ? null : widget.onEditLastMessage,
                isEmojiPanelOpen: widget.isEmojiPanelOpen,
                onTapInputWhenEmojiOpen: widget.onTapInputWhenEmojiOpen,
                showBotCommandsButton: widget.showBotCommandsButton,
                isBotCommandsOpen: widget.isBotCommandsOpen,
                onToggleBotCommands: widget.onToggleBotCommands,
                botMenuWebAppLabel: widget.botMenuWebAppLabel,
                onOpenBotMenuWebApp: widget.onOpenBotMenuWebApp,
                hasReplyKeyboard: widget.hasReplyKeyboard,
                isReplyKeyboardOpen: widget.isReplyKeyboardOpen,
                onToggleReplyKeyboard: widget.onToggleReplyKeyboard,
                slowmodeRemainingSeconds: widget.slowmodeRemainingSeconds,
              ),
            ),
            if (widget.scheduledCount > 0 && widget.onOpenScheduled != null)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 10),
                child: TheavHeaderIconButton(
                  tooltip: 'Отложенные сообщения',
                  badgeCount: widget.scheduledCount,
                  onTap: widget.onOpenScheduled,
                  icon: iconoir.Calendar(
                    width: 20,
                    height: 20,
                    color: context.theav.appBarForeground != Colors.transparent
                        ? context.theav.appBarForeground
                        : context.theav.onSurface,
                  ),
                ),
              ),
            if (widget.showSilentBroadcastToggle)
              _buildSilentBroadcastButton(
                context,
                glassEnabled,
                isLite,
                glassProvider,
              ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ],
    );

    if (glassEnabled && !isLite && glassProvider != null) {
      return LiquidGlassBatch(
        child: column,
      );
    }

    return column;
  }
}

/// Geometric appear/disappear wrapper for Liquid Glass contextual bars
/// (`ReplyPreviewBar`, `LinkPreviewInputBar`, editing banner, attachments).
///
/// Strictly adheres to the Liquid Glass rule: NEVER applies `FadeTransition`
/// or `Opacity` to the `LiquidGlassLens` shape. Instead, animates height
/// (`ClipRect` + `Align(heightFactor)`) and vertical slide (`SlideTransition`),
/// retaining the last active child while animating out so closing transitions
/// play smoothly.
class _GlassSafeAnimatedSection extends StatefulWidget {
  final bool visible;
  final Widget? child;

  const _GlassSafeAnimatedSection({
    Key? key,
    required this.visible,
    required this.child,
  }) : super(key: key);

  @override
  State<_GlassSafeAnimatedSection> createState() =>
      _GlassSafeAnimatedSectionState();
}

class _GlassSafeAnimatedSectionState extends State<_GlassSafeAnimatedSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _heightFactor;
  late final Animation<Offset> _slideAnimation;
  Widget? _cachedChild;

  @override
  void initState() {
    super.initState();
    _cachedChild = widget.child;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: (widget.visible && widget.child != null) ? 1.0 : 0.0,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _heightFactor = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(covariant _GlassSafeAnimatedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child != null) {
      _cachedChild = widget.child;
    }
    if (widget.visible != oldWidget.visible) {
      if (widget.visible && _cachedChild != null) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if ((_controller.isDismissed && !widget.visible) ||
            _cachedChild == null) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: !widget.visible,
          child: ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: _heightFactor.value,
              child: SlideTransition(
                position: _slideAnimation,
                child: _cachedChild,
              ),
            ),
          ),
        );
      },
    );
  }
}
