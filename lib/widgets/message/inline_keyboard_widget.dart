import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';

import '../../services/bot_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';

/// Renders a Telegram-style `inline_keyboard` grid directly beneath a
/// [MessageBubble].
///
/// Supports:
/// - `callback_data` buttons (shows a compact loading spinner until the request
///   resolves or times out, and displays toast/alert answers)
/// - `url` buttons (opens external or internal link with a subtle corner icon)
/// - `copy_text` buttons (copies text to clipboard with toast confirmation)
/// - `switch_inline_query` / `switch_inline_query_current_chat` buttons
class InlineKeyboardWidget extends StatefulWidget {
  final String chatId;
  final String messageId;
  final List<List<Map<String, dynamic>>> rows;
  final double maxWidth;
  final void Function(String text)? onInsertText;

  const InlineKeyboardWidget({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.rows,
    this.maxWidth = 280,
    this.onInsertText,
  });

  @override
  State<InlineKeyboardWidget> createState() => _InlineKeyboardWidgetState();
}

class _InlineKeyboardWidgetState extends State<InlineKeyboardWidget> {
  final Set<String> _loadingKeys = {};

  Future<void> _handleButtonTap(
    Map<String, dynamic> btn,
    String btnKey,
  ) async {
    HapticUtils.tap();

    final copyRaw = btn['copy_text'];
    final copyStr = copyRaw is Map
        ? copyRaw['text']?.toString()
        : copyRaw?.toString();
    if (copyStr != null && copyStr.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: copyStr));
      if (mounted) {
        GlassToastService().show(context, 'Скопировано в буфер обмена');
      }
      return;
    }

    final urlStr = btn['url']?.toString();
    if (urlStr != null && urlStr.isNotEmpty) {
      final uri = Uri.tryParse(urlStr);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final switchInline =
        (btn['switch_inline_query_current_chat'] ?? btn['switch_inline_query'])
            ?.toString();
    if (switchInline != null && widget.onInsertText != null) {
      widget.onInsertText!(switchInline);
      return;
    }

    final callbackData =
        (btn['callback_data'] ?? btn['data'])?.toString();
    if (callbackData == null || callbackData.isEmpty) return;

    if (_loadingKeys.contains(btnKey)) return;
    setState(() => _loadingKeys.add(btnKey));

    try {
      final res = await BotService.sendCallbackQuery(
        chatId: widget.chatId,
        messageId: widget.messageId,
        callbackData: callbackData,
      );

      if (!mounted) return;
      final answer = res['answer'] is Map
          ? Map<String, dynamic>.from(res['answer'] as Map)
          : res;
      final answerText = answer['text']?.toString();
      final showAlert = answer['show_alert'] == true;
      final answerUrl = answer['url']?.toString();

      if (answerUrl != null && answerUrl.isNotEmpty) {
        final uri = Uri.tryParse(answerUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (answerText != null && answerText.isNotEmpty && mounted) {
        if (showAlert) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              content: Text(answerText),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('ОК'),
                ),
              ],
            ),
          );
        } else {
          GlassToastService().show(context, answerText);
        }
      } else if (res['success'] == false &&
          res['message'] != null &&
          mounted) {
        GlassToastService().show(context, res['message'].toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingKeys.remove(btnKey));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buttonBg = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.76)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85);
    final borderColor =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.28);
    final textColor = theme.colorScheme.onSurface;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.rows.length, (rIdx) {
            final row = widget.rows[rIdx];
            if (row.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: EdgeInsets.only(top: rIdx == 0 ? 0 : 4),
              child: Row(
                children: List.generate(row.length, (cIdx) {
                  final btn = row[cIdx];
                  final label = (btn['text'] ?? '').toString();
                  final isUrl =
                      btn['url'] != null && btn['url'].toString().isNotEmpty;
                  final btnKey = '${widget.messageId}_${rIdx}_$cIdx';
                  final isLoading = _loadingKeys.contains(btnKey);

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: cIdx == 0 ? 0 : 4),
                      child: Material(
                        color: buttonBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: borderColor, width: 0.9),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _handleButtonTap(btn, btnKey),
                          child: SizedBox(
                            height: 36,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (isLoading) ...[
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Flexible(
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isUrl)
                                  Positioned(
                                    top: 4,
                                    right: 5,
                                    child: iconoir.OpenNewWindow(
                                      width: 10,
                                      height: 10,
                                      color: textColor.withValues(alpha: 0.65),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}
