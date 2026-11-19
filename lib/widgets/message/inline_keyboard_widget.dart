import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';

import '../../services/bot_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../bot/mini_app_webview_sheet.dart';
import '../design_system/theav_design_system.dart';

/// Renders a Telegram-style `inline_keyboard` grid directly beneath a
/// [MessageBubble].
///
/// Supports:
/// - `callback_data` buttons (shows a compact loading spinner until the request
///   resolves or times out, and displays toast/alert answers)
/// - `web_app` buttons (opens an interactive Mini App WebView sheet with signed initData)
/// - `url` & `login_url` buttons (opens external or internal link with a subtle corner icon)
/// - `copy_text` buttons (copies text to clipboard with toast confirmation)
/// - `switch_inline_query` / `switch_inline_query_current_chat` buttons
class InlineKeyboardWidget extends StatefulWidget {
  final String chatId;
  final String messageId;
  final List<List<Map<String, dynamic>>> rows;
  final double maxWidth;
  final void Function(String text)? onInsertText;
  final String? botId;
  final String? botUsername;
  final void Function(String url, String buttonText)? onOpenWebApp;
  final void Function(String query)? onSwitchInlineQuery;

  const InlineKeyboardWidget({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.rows,
    this.maxWidth = 280,
    this.onInsertText,
    this.botId,
    this.botUsername,
    this.onOpenWebApp,
    this.onSwitchInlineQuery,
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

    final webAppRaw = btn['web_app'];
    final webAppUrl = webAppRaw is Map
        ? webAppRaw['url']?.toString()
        : (webAppRaw is String ? webAppRaw : null);
    if (webAppUrl != null && webAppUrl.isNotEmpty) {
      final btnText = (btn['text'] ?? '').toString();
      if (widget.onOpenWebApp != null) {
        widget.onOpenWebApp!(webAppUrl, btnText);
      } else if (widget.botId != null && widget.botId!.isNotEmpty) {
        await openMiniAppSheet(
          context,
          botId: widget.botId!,
          botUsername: widget.botUsername,
          url: webAppUrl,
          chatId: widget.chatId,
          mode: 'inline',
          buttonText: btnText,
          onSwitchInlineQuery: widget.onSwitchInlineQuery ?? widget.onInsertText,
        );
      } else {
        final uri = Uri.tryParse(webAppUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return;
    }

    final loginRaw = btn['login_url'];
    final loginUrl = loginRaw is Map
        ? loginRaw['url']?.toString()
        : (loginRaw is String ? loginRaw : null);
    if (loginUrl != null && loginUrl.isNotEmpty) {
      final uri = Uri.tryParse(loginUrl);
      if (uri != null && mounted) {
        final confirmed = await showTheavDialog<bool>(
              context: context,
              title: 'Авторизация на сайте',
              message: 'Перейти по ссылке авторизации ${uri.host}?',
              actions: const [
                TheavDialogAction<bool>(label: 'Отмена', result: false),
                TheavDialogAction<bool>(
                  label: 'Открыть',
                  result: true,
                  isPrimary: true,
                ),
              ],
            ) ??
            false;
        if (confirmed) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return;
    }

    final switchInline =
        (btn['switch_inline_query_current_chat'] ?? btn['switch_inline_query'])
            ?.toString();
    if (switchInline != null) {
      final handler = widget.onSwitchInlineQuery ?? widget.onInsertText;
      if (handler != null) {
        final uname = widget.botUsername?.trim() ?? '';
        final inserted = (uname.isNotEmpty && !switchInline.startsWith('@'))
            ? '@$uname $switchInline'
            : switchInline;
        handler(inserted);
      }
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
          await showTheavDialog<void>(
            context: context,
            message: answerText,
            actions: const [
              TheavDialogAction<void>(
                label: 'ОК',
                isPrimary: true,
              ),
            ],
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
                      (btn['url'] != null && btn['url'].toString().isNotEmpty) ||
                      (btn['login_url'] != null &&
                          btn['login_url'].toString().isNotEmpty);
                  final isWebApp = btn['web_app'] is Map
                      ? (btn['web_app']['url']?.toString().isNotEmpty ?? false)
                      : (btn['web_app'] is String &&
                          btn['web_app'].toString().isNotEmpty);
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
                                if (isWebApp)
                                  Positioned(
                                    top: 4,
                                    right: 5,
                                    child: iconoir.AppWindow(
                                      width: 10,
                                      height: 10,
                                      color: textColor.withValues(alpha: 0.65),
                                    ),
                                  )
                                else if (isUrl)
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
