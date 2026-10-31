import 'package:flutter/material.dart';
import '../../models/theav_theme.dart';

/// Collapsible grid of reply keyboard buttons (`reply_markup.keyboard`)
/// displayed below `ChatInputBar` when a bot message provides a custom keyboard.
class ReplyKeyboardPanel extends StatelessWidget {
  final List<List<Map<String, dynamic>>> rows;
  final ValueChanged<String> onButtonPressed;
  final bool resizeKeyboard;

  const ReplyKeyboardPanel({
    super.key,
    required this.rows,
    required this.onButtonPressed,
    this.resizeKeyboard = true,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final ext = theme.extension<TheavThemeExtension>();
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: resizeKeyboard ? 220 : 260,
      ),
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomPadding),
      decoration: BoxDecoration(
        color: ext?.glassSurfaceColor ??
            colorScheme.surfaceContainerLow.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: ext?.glassBorderColor ??
                colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: 6),
              Row(
                children: [
                  for (int c = 0; c < rows[r].length; c++) ...[
                    if (c > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _buildReplyButton(
                        context,
                        rows[r][c],
                        theme,
                        ext,
                        colorScheme,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReplyButton(
    BuildContext context,
    Map<String, dynamic> button,
    ThemeData theme,
    TheavThemeExtension? ext,
    ColorScheme colorScheme,
  ) {
    final text = button['text']?.toString() ?? '';
    return SizedBox(
      height: 42,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: text.isEmpty ? null : () => onButtonPressed(text),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ext?.glassBorderColor ??
                    colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
