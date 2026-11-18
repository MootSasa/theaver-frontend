import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../models/theav_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/liquid_glass_provider.dart';
import '../../../utils/emoji_utils.dart';
import '../../../utils/haptic_utils.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final glassProvider = maybeLiquidGlassProvider(context);
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    final modes = <({String id, String label})>[
      (id: 'all', label: 'Все реакции'),
      (id: 'selected', label: 'Только выбранные'),
      (id: 'none', label: 'Выключены'),
    ];
    final selectedFg = accentColor.computeLuminance() > 0.35
        ? const Color(0xFF0F172A)
        : Colors.white;

    return SettingsFloatingScaffold(
      title: 'Реакции',
      backgroundColor: bgColor,
      actions: [
        if (_isSaving)
          const SettingsHeaderAction(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          SettingsHeaderAction(
            tooltip: 'Сохранить',
            foregroundColor: accentColor,
            icon: iconoir.Check(width: 22, height: 22, color: accentColor),
            onTap: _saveSettings,
          ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          SettingsFloatingHeader.topClearanceOf(context) + 12,
          16,
          36,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Row(
              children: [
                iconoir.Heart(width: 15, height: 15, color: subColor),
                const SizedBox(width: 6),
                Text(
                  'ДОСТУПНЫЕ РЕАКЦИИ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
          _buildSurfaceCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            radius: 18,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  for (final m in modes)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticUtils.selection();
                          setState(() => _mode = m.id);
                        },
                        child: AnimatedContainer(
                          duration: disableAnim
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _mode == m.id
                                ? accentColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            m.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _mode == m.id ? selectedFg : textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 8, right: 14),
            child: Text(
              _modeExplanation(),
              style: TextStyle(fontSize: 12.5, color: subColor, height: 1.35),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: disableAnim
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              duration: disableAnim
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              opacity: _mode == 'selected' ? 1.0 : 0.0,
              child: _mode == 'selected'
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Text(
                                'РАЗРЕШЁННЫЕ ЭМОДЗИ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: subColor,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    HapticUtils.selection();
                                    setState(
                                      () => _selectedEmojis.addAll(_palette),
                                    );
                                  },
                                  child: Text(
                                    'Выбрать все',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    HapticUtils.selection();
                                    setState(() => _selectedEmojis.clear());
                                  },
                                  child: Text(
                                    'Очистить',
                                    style: TextStyle(
                                      color: subColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _buildSurfaceCard(
                          context,
                          glassProvider: glassProvider,
                          isDark: isDark,
                          child: Padding(
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
                                    isDark: isDark,
                                    accentColor: accentColor,
                                    disableAnim: disableAnim,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: selectedFg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: iconoir.Check(
                width: 20,
                height: 20,
                color: selectedFg,
              ),
              label: const Text(
                'Сохранить',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiChip(
    BuildContext context, {
    required String emoji,
    required bool selected,
    required bool isDark,
    required Color accentColor,
    required bool disableAnim,
  }) {
    final unselectedBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final unselectedBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

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
          color: selected ? accentColor.withValues(alpha: 0.18) : unselectedBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accentColor : unselectedBorder,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: EmojiUtils.appleEmoji(emoji, size: 25),
      ),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    double radius = 20,
    required Widget child,
  }) {
    if ((glassProvider?.enabled ?? false) && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: radius,
        ),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: isDark
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
