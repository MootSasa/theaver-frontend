import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/settings/widgets/update_dialog.dart';
import '../../services/chat_service.dart';
import '../../services/update_service.dart';
import '../../utils/haptic_utils.dart';

/// Widget rendering unsupported messages inside a message bubble.
/// Displays an italic warning notice and an update action button
/// styled similarly to the poll results button.
class UnsupportedMessageWidget extends StatefulWidget {
  final Message message;
  final bool isMe;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final Widget? metadata;
  final Widget? replyWidget;
  final Widget? senderNameWidget;

  const UnsupportedMessageWidget({
    Key? key,
    required this.message,
    required this.isMe,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    this.metadata,
    this.replyWidget,
    this.senderNameWidget,
  }) : super(key: key);

  @override
  State<UnsupportedMessageWidget> createState() =>
      _UnsupportedMessageWidgetState();
}

class _UnsupportedMessageWidgetState extends State<UnsupportedMessageWidget> {
  bool _isCheckingUpdate = false;

  Future<void> _handleUpdate() async {
    if (_isCheckingUpdate) return;
    HapticUtils.tap();
    setState(() => _isCheckingUpdate = true);

    try {
      if (kIsWeb) {
        await AppConfig.syncWebVersionFromServer();
      }
      final update =
          await AppUpdateService.instance.checkForUpdate(silent: false);
      if (!mounted) return;

      if (update.hasUpdate) {
        UpdateDialog.show(context, update, isManual: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.translate('app_up_to_date'),
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.translate('check_updates_error')}: $e',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final warningText = l10n.translate('message_unsupported_text');
    final buttonText = l10n.translate('message_unsupported_update_btn');

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.senderNameWidget != null) ...[
            widget.senderNameWidget!,
            const SizedBox(height: 4.0),
          ],
          if (widget.replyWidget != null) ...[
            widget.replyWidget!,
            const SizedBox(height: 6.0),
          ],
          Text(
            warningText,
            style: TextStyle(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              color: widget.textColor,
              height: 1.35,
            ),
          ),
          if (widget.metadata != null) ...[
            const SizedBox(height: 4.0),
            Align(
              alignment: Alignment.centerRight,
              child: widget.metadata!,
            ),
          ],
          const SizedBox(height: 6.0),
          Divider(
            height: 1.0,
            thickness: 0.6,
            color: widget.textColor.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 2.0),
          SizedBox(
            width: double.infinity,
            height: 34.0,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onPressed: _isCheckingUpdate ? null : _handleUpdate,
              child: _isCheckingUpdate
                  ? SizedBox(
                      width: 16.0,
                      height: 16.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: widget.accentColor,
                      ),
                    )
                  : Text(
                      buttonText,
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                        color: widget.accentColor,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
