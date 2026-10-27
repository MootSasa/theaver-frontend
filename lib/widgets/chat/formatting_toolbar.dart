import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../utils/entity_parser.dart';
import '../../utils/haptic_utils.dart';
import 'rich_text_editing_controller.dart';

/// Floating Liquid Glass Formatting Toolbar for message input.
///
/// Provides Telegram-like quick actions for rich text formatting:
/// Bold, Italic, Strikethrough, Underline, Spoiler, Code, Quote,
/// Collapsible Quote, Link, and Caption Move (invert media).
class FormattingToolbar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasMedia;
  final bool invertMedia;
  final ValueChanged<bool>? onToggleInvertMedia;
  final VoidCallback? onClose;

  const FormattingToolbar({
    Key? key,
    required this.controller,
    this.hasMedia = false,
    this.invertMedia = false,
    this.onToggleInvertMedia,
    this.onClose,
  }) : super(key: key);

  void _apply(BuildContext context, String type) {
    HapticUtils.tap();
    if (type == 'link') {
      _showLinkDialog(context);
    } else {
      if (controller is RichTextEditingController) {
        (controller as RichTextEditingController).applyFormat(type);
      } else {
        EntityParser.applyFormatting(
          controller: controller,
          formatType: type,
        );
      }
    }
  }

  void _showLinkDialog(BuildContext context) {
    final textController = TextEditingController(text: 'https://');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.translate('chat_action_link') != 'chat_action_link'
            ? ctx.l10n.translate('chat_action_link')
            : 'Ссылка'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              final url = textController.text.trim();
              Navigator.pop(ctx);
              if (url.isNotEmpty && url != 'https://') {
                if (controller is RichTextEditingController) {
                  (controller as RichTextEditingController).applyFormat('link', url: url);
                } else {
                  EntityParser.applyFormatting(
                    controller: controller,
                    formatType: 'link',
                    url: url,
                  );
                }
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final richCtrl = controller is RichTextEditingController
        ? controller as RichTextEditingController
        : null;
    bool isActive(String type) => richCtrl?.isFormatActive(type) ?? false;

    final bgColor = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.92);
    final iconColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final activeColor = theme.colorScheme.primary;

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildButton(
                  icon: iconoir.Bold(color: isActive('bold') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_bold'),
                  onTap: () => _apply(context, 'bold'),
                  isActive: isActive('bold'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.Italic(color: isActive('italic') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_italic'),
                  onTap: () => _apply(context, 'italic'),
                  isActive: isActive('italic'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.Strikethrough(color: isActive('strikethrough') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_strikethrough'),
                  onTap: () => _apply(context, 'strikethrough'),
                  isActive: isActive('strikethrough'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.Underline(color: isActive('underline') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_underline'),
                  onTap: () => _apply(context, 'underline'),
                  isActive: isActive('underline'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.EyeClosed(color: isActive('spoiler') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_spoiler'),
                  onTap: () => _apply(context, 'spoiler'),
                  isActive: isActive('spoiler'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.Code(color: isActive('code') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_code'),
                  onTap: () => _apply(context, 'code'),
                  isActive: isActive('code'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.Quote(color: isActive('quote') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_quote'),
                  onTap: () => _apply(context, 'quote'),
                  isActive: isActive('quote'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.NavArrowDown(color: isActive('collapse') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: context.l10n.translate('format_collapse'),
                  onTap: () => _apply(context, 'collapse'),
                  isActive: isActive('collapse'),
                  activeColor: activeColor,
                ),
                _buildButton(
                  icon: iconoir.Link(color: isActive('link') ? activeColor : iconColor, width: 18, height: 18),
                  tooltip: 'Ссылка',
                  onTap: () => _apply(context, 'link'),
                  isActive: isActive('link'),
                  activeColor: activeColor,
                ),
                if (hasMedia)
                  _buildButton(
                    icon: iconoir.SortDown(
                      color: invertMedia ? activeColor : iconColor,
                      width: 18,
                      height: 18,
                    ),
                    tooltip: invertMedia
                        ? context.l10n.translate('caption_below_media')
                        : context.l10n.translate('caption_above_media'),
                    onTap: () {
                      HapticUtils.tap();
                      onToggleInvertMedia?.call(!invertMedia);
                    },
                    isActive: invertMedia,
                    activeColor: activeColor,
                  ),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: iconoir.Xmark(
                width: 18,
                height: 18,
                color: iconColor.withValues(alpha: 0.6),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                HapticUtils.tap();
                onClose?.call();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
          decoration: isActive
              ? BoxDecoration(
                  color: (activeColor ?? Colors.blue).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                )
              : null,
          child: Center(child: icon),
        ),
      ),
    );
  }
}
