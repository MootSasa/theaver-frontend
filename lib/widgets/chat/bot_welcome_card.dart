import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/bot_service.dart';
import '../../services/liquid_glass_provider.dart';

/// Centered welcome card rendered inside an empty bot conversation.
/// Displays the bot's description (`about_text` / `description`) and
/// clickable command chips so the user can inspect or trigger commands right away.
class BotWelcomeCard extends StatelessWidget {
  final String botName;
  final String? botUsername;
  final BotInfo? botInfo;
  final ValueChanged<String> onCommandTap;

  const BotWelcomeCard({
    super.key,
    required this.botName,
    this.botUsername,
    this.botInfo,
    required this.onCommandTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = theme.extension<TheavThemeExtension>();
    final colorScheme = theme.colorScheme;
    final rawAbout = botInfo?.aboutText?.trim();
    final about = (rawAbout != null && rawAbout.isNotEmpty)
        ? rawAbout
        : 'Нажмите «Запустить», чтобы начать диалог с ботом.';
    final commands = botInfo?.commands ?? const <BotCommand>[];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ext?.glassSurfaceColor ??
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: ext?.glassBorderColor ??
                    colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: iconoir.Sparks(
                        width: 20,
                        height: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Что умеет этот бот?',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (botUsername != null && botUsername!.isNotEmpty)
                            Text(
                              '@$botUsername',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  about,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.88),
                    height: 1.4,
                  ),
                ),
                if (commands.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Доступные команды',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...commands.take(6).map((cmd) {
                    final normalized = cmd.normalizedCommand;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onCommandTap(normalized),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 6,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              normalized,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                            if (cmd.description.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '— ${cmd.description}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom action bar shown in place of or above the input bar when a bot
/// conversation has 0 messages, sending `/start` on tap.
class BotStartBar extends StatelessWidget {
  final VoidCallback onStartPressed;
  final bool isLoading;

  const BotStartBar({
    super.key,
    required this.onStartPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final glassEnabled = context.watch<LiquidGlassProvider?>()?.enabled ?? false;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(
          alpha: glassEnabled ? 0.72 : 0.96,
        ),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: isLoading ? null : onStartPressed,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              : iconoir.Play(
                  width: 18,
                  height: 18,
                  color: colorScheme.onPrimary,
                ),
          label: const Text(
            'ЗАПУСТИТЬ (/start)',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
