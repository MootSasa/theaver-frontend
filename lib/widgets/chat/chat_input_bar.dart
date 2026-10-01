import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/entity_parser.dart';
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
  final VoidCallback? onCancelReply;
  final VoidCallback? onTapReply;
  final List<File> attachedFiles;
  final List<String> attachedFileNames;
  final ValueChanged<int>? onRemoveAttachment;
  final bool isUploading;
  final double uploadProgress;
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
    this.onCancelReply,
    this.onTapReply,
    this.attachedFiles = const [],
    this.attachedFileNames = const [],
    this.onRemoveAttachment,
    this.isUploading = false,
    this.uploadProgress = 0.0,
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
    final urls = <String>[...EntityParser.extractUrls(text)];
    if (widget.controller is RichTextEditingController) {
      final richCtrl = widget.controller as RichTextEditingController;
      for (final span in richCtrl.spans) {
        if (span.url != null && span.url!.trim().isNotEmpty) {
          final u = EntityParser.normalizeUrl(span.url!);
          if (!urls.contains(u)) urls.add(u);
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

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Link Preview Input Bar (when URLs detected and not disabled)
        if (_detectedUrls.isNotEmpty &&
            _effectiveLinkPreviewOptions != null &&
            !_effectiveLinkPreviewOptions!.isDisabled)
          LinkPreviewInputBar(
            options: _effectiveLinkPreviewOptions!,
            detectedUrls: _detectedUrls,
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
          ),

        // 2. Editing message banner
        if (widget.isEditing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            child: Row(
              children: [
                iconoir.EditPencil(
                  color: Theme.of(context).colorScheme.primary,
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.editingTitle ??
                        context.l10n.translate('chat_editing_title'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (widget.onCancelEditing != null)
                  IconButton(
                    icon: const iconoir.Xmark(
                      width: 18,
                      height: 18,
                    ),
                    onPressed: widget.onCancelEditing,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

        // 3. Reply/Quote preview bar
        if (widget.replyToMessage != null)
          ReplyPreviewBar(
            replyToMessage: widget.replyToMessage!,
            isQuote: widget.isQuote,
            quoteText: widget.quoteText,
            onClose: widget.onCancelReply ?? () {},
            onTap: widget.onTapReply,
            enabled: glassEnabled,
            isLite: isLite,
            currentUserId: widget.currentUserId,
          ),

        // 4. Attached files preview list
        if (widget.attachedFiles.isNotEmpty)
          Container(
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const iconoir.Page(
                                        width: 28,
                                        height: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        fileName,
                                        style: const TextStyle(fontSize: 10),
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
                            onTap: () => widget.onRemoveAttachment!(index),
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
          ),

        // 5. Upload progress
        if (widget.isUploading)
          LinearProgressIndicator(
            value: widget.uploadProgress > 0 ? widget.uploadProgress : null,
            backgroundColor: Colors.grey[300],
          ),

        // 6. Input field row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: LiquidGlassInputField(
                enabled: glassEnabled,
                isLite: isLite,
                controller: widget.controller,
                focusNode: widget.focusNode,
                hintText: widget.hintText ??
                    (widget.attachedFiles.isNotEmpty
                        ? 'Add a caption...'
                        : 'Type a message...'),
                onChanged: widget.onChanged,
                onSend: widget.isSending ? null : _handleSend,
                onAttach: widget.onAttach,
                onEmoji: widget.onEmoji,
                onVoice: widget.onVoice,
                onStartVoiceRecord: widget.onStartVoiceRecord,
                onVoiceRecordMove: widget.onVoiceRecordMove,
                onVoiceRecordEnd: widget.onVoiceRecordEnd,
                onVoiceRecordCancel: widget.onVoiceRecordCancel,
                onStartVideoRecord: widget.onStartVideoRecord,
                onVideoRecordMove: widget.onVideoRecordMove,
                onVideoRecordEnd: widget.onVideoRecordEnd,
                onVideoRecordCancel: widget.onVideoRecordCancel,
                isSending: widget.isSending,
                hasAttachments: widget.attachedFiles.isNotEmpty,
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ],
    );
  }
}
