import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../utils/emoji_utils.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/settings/settings_floating_header.dart';

/// Chat reactions mode and allowed-emoji selector screen for groups and channels.
class ChatReactionsSettingsScreen extends StatefulWidget {
  final String chatId;
  final ReactionSettings initialSettings;

  const ChatReactionsSettingsScreen({
    super.key,
    required this.chatId,
    required this.initialSettings,
  });

  @override
  State<ChatReactionsSettingsScreen> createState() =>
      _ChatReactionsSettingsScreenState();
}

class _ChatReactionsSettingsScreenState
    extends State<ChatReactionsSettingsScreen> {
  static const List<String> _defaultPalette = [
    '❤️',
    '👍',
    '👎',
    '🔥',
    '🎉',
    '👏',
    '😂',
    '🥰',
    '🤯',
    '😱',
    '😢',
    '🤔',
    '🤬',
    '💯',
    '⚡',
    '🏆',
    '🙏',
    '👌',
    '🤩',
    '💔',
    '👀',
    '🫡',
    '🤝',
    '🥳',
    '😎',
    '👻',
    '🤡',
    '😈',
    '😴',
    '😭',
    '🕊️',
    '🍾',
  ];

  late String _mode; // 'all' | 'selected' | 'none'
  late final Set<String> _selectedEmojis;
  late final List<String> _palette;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialSettings.mode;
    _selectedEmojis = Set<String>.from(
      widget.initialSettings.allowedReactions,
    );
    if (_mode == 'selected' && _selectedEmojis.isEmpty) {
      _selectedEmojis.addAll(const ['❤️', '👍', '🔥', '👏', '😂', '🎉']);
    }
    final combined = <String>[..._defaultPalette];
    for (final existing in widget.initialSettings.allowedReactions) {
      if (!combined.contains(existing)) {
        combined.add(existing);
      }
    }
    _palette = combined;
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    if (_mode == 'selected' && _selectedEmojis.isEmpty) {
      GlassToastService().show(
        context,
        'Выберите хотя бы одну реакцию или отключите реакции',
      );
      return;
    }

    HapticUtils.tap();
    setState(() => _isSaving = true);

    final allowedList = _mode == 'selected'
        ? _palette.where(_selectedEmojis.contains).toList()
        : <String>[];

    final res = await ChatService.updateGroupSettings(widget.chatId, {
      'reaction_mode': _mode,
      'allowed_reactions': allowedList,
    });

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] == true) {
      final updated = ReactionSettings(
        mode: _mode,
        allowedReactions: List<String>.unmodifiable(allowedList),
      );
      GlassToastService().show(
        context,
        'Настройки реакций сохранены',
        iconWidget: const iconoir.Check(
          width: 18,
          height: 18,
          color: Color(0xFF34C759),
        ),
      );
      Navigator.pop(context, updated);
    } else {
      GlassToastService().show(
        context,
        res['message']?.toString() ?? 'Не удалось сохранить настройки реакций',
      );
    }
  }

  String _modeExplanation() {
    switch (_mode) {
      case 'none':
        return 'Участники и подписчики не смогут ставить реакции на сообщения в этом чате.';
      case 'selected':
        return 'Пользователи смогут выбирать только отмеченные ниже реакции (выбрано: ${_selectedEmojis.length}).';
      default:
        return 'В чате доступны все стандартные реакции без ограничений.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    return SettingsFloatingScaffold(
      title: 'Реакции',
      backgroundColor: palette.background,
      actions: [
        if (_isSaving)
          SettingsHeaderAction(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primary,
              ),
            ),
          )
        else
          SettingsHeaderAction(
            tooltip: 'Сохранить',
            foregroundColor: palette.primary,
            icon: iconoir.Check(width: 22, height: 22, color: palette.primary),
            onTap: _saveSettings,
          ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          SettingsFloatingHeader.topClearanceOf(context) + 12,
          0,
          MediaQuery.paddingOf(context).bottom + 36,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 4, 32, 8),
            child: Row(
              children: [
                iconoir.Heart(width: 15, height: 15, color: palette.primary),
                const SizedBox(width: 6),
                Text(
                  'ДОСТУПНЫЕ РЕАКЦИИ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: palette.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TheavSegmentedControl<String>(
              options: const [
                TheavSegmentOption(value: 'all', label: 'Все'),
                TheavSegmentOption(value: 'selected', label: 'Выбранные'),
                TheavSegmentOption(value: 'none', label: 'Выкл'),
              ],
              selected: _mode,
              onChanged: (val) => setState(() => _mode = val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 12),
            child: Text(
              _modeExplanation(),
              style: TextStyle(
                fontSize: 12.5,
                color: palette.subtext,
                height: 1.35,
              ),
            ),
          ),
          AnimatedSize(
            duration: disableAnim
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _mode == 'selected'
                ? TheavInsetGroup(
                    header: 'РАЗРЕШЁННЫЕ ЭМОДЗИ',
                    headerTrailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            setState(() => _selectedEmojis.addAll(_palette));
                          },
                          child: Text(
                            'Все',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            setState(() => _selectedEmojis.clear());
                          },
                          child: Text(
                            'Очистить',
                            style: TextStyle(
                              color: palette.subtext,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final emoji in _palette)
                              _buildEmojiChip(
                                context,
                                emoji: emoji,
                                selected: _selectedEmojis.contains(emoji),
                                palette: palette,
                                disableAnim: disableAnim,
                              ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiChip(
    BuildContext context, {
    required String emoji,
    required bool selected,
    required TheavPalette palette,
    required bool disableAnim,
  }) {
    final unselectedBg = palette.onSurface.withValues(alpha: 0.05);
    final unselectedBorder = palette.divider;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.selection();
        setState(() {
          if (selected) {
            _selectedEmojis.remove(emoji);
          } else {
            _selectedEmojis.add(emoji);
          }
        });
      },
      child: AnimatedContainer(
        duration: disableAnim
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 48,
        decoration: BoxDecoration(
          color: selected ? palette.primary.withValues(alpha: 0.16) : unselectedBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.primary : unselectedBorder,
            width: selected ? 1.5 : 0.6,
          ),
        ),
        alignment: Alignment.center,
        child: EmojiUtils.appleEmoji(emoji, size: 25),
      ),
    );
  }
}
