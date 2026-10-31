import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../models/theav_theme.dart';
import '../../services/bot_service.dart';

/// Floating glass popup menu rendered above `ChatInputBar` when the user taps
/// the `/` bot commands button or types `/` at the start of the input.
class BotCommandsPopup extends StatelessWidget {
  final List<BotCommand> commands;
  final String filterQuery;
  final ValueChanged<BotCommand> onSelectCommand;
  final VoidCallback? onClose;

  const BotCommandsPopup({
    super.key,
    required this.commands,
    this.filterQuery = '',
    required this.onSelectCommand,
    this.onClose,
  });

  List<BotCommand> get _filteredCommands {
    final q = filterQuery.trim().toLowerCase();
    if (q.isEmpty || q == '/') return commands;
    final clean = q.startsWith('/') ? q.substring(1) : q;
    return commands.where((cmd) {
      final c = cmd.command.toLowerCase();
      final d = cmd.description.toLowerCase();
      return c.contains(clean) || d.contains(clean);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCommands;
    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final ext = theme.extension<TheavThemeExtension>();
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      constraints: const BoxConstraints(maxHeight: 230),
      decoration: BoxDecoration(
        color: ext?.glassSurfaceColor ??
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ext?.glassBorderColor ??
              colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
              child: Row(
                children: [
                  iconoir.TerminalTag(
                    width: 16,
                    height: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Команды бота',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onClose != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onClose,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: iconoir.Xmark(
                          width: 16,
                          height: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                ),
                itemBuilder: (context, index) {
                  final cmd = filtered[index];
                  return InkWell(
                    onTap: () => onSelectCommand(cmd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Text(
                            cmd.normalizedCommand,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              cmd.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
