import 'package:flutter/material.dart';
import '../../models/theav_theme.dart';
import '../../l10n/app_localizations.dart';
import 'chat_preview_card.dart';

/// Modal bottom sheet allowing users to inspect and apply/save an imported theme.
class ThemePreviewSheet extends StatelessWidget {
  final TheavTheme theme;
  final VoidCallback onApply;
  final VoidCallback? onSaveToCloud;

  const ThemePreviewSheet({
    Key? key,
    required this.theme,
    required this.onApply,
    this.onSaveToCloud,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required TheavTheme theme,
    required VoidCallback onApply,
    VoidCallback? onSaveToCloud,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ThemePreviewSheet(
        theme: theme,
        onApply: onApply,
        onSaveToCloud: onSaveToCloud,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top drag handle
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Theme Name & Author Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          theme.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.translate('theme_author')}: ${theme.author}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.isDark
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFE0F7FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.isDark ? Colors.white24 : const Color(0xFF0088CC),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          theme.isDark ? Icons.dark_mode : Icons.light_mode,
                          size: 14,
                          color: theme.isDark ? Colors.white : const Color(0xFF0088CC),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          theme.isDark ? l10n.translate('theme_dark') : l10n.translate('theme_light'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.isDark ? Colors.white : const Color(0xFF0088CC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Live Interactive Preview Card
            ChatPreviewCard(
              theme: theme,
              height: 220,
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0088CC),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        onApply();
                      },
                      child: Text(
                        l10n.translate('theme_apply_to_device'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (onSaveToCloud != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0088CC),
                          side: const BorderSide(color: Color(0xFF0088CC), width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: Text(
                          l10n.translate('theme_save_to_cloud'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          onSaveToCloud!();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
