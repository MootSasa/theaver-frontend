import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/dm_parity_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../common/adaptive_switch.dart';
import '../design_system/theav_design_system.dart';

class ChatAppearanceDialogResult {
  final bool changed;
  final ChatAppearanceConfig? appearance;

  const ChatAppearanceDialogResult({
    required this.changed,
    this.appearance,
  });
}

/// Telegram-style chat auto-delete preset selector.
Future<int?> showAutoDeleteTimerSheet(
  BuildContext context, {
  int currentSeconds = 0,
}) {
  const presets = <({int seconds, String label})>[
    (seconds: 0, label: 'Выключено'),
    (seconds: 86400, label: '24 часа'),
    (seconds: 604800, label: '7 дней'),
    (seconds: 2592000, label: '1 месяц'),
    (seconds: 31536000, label: '1 год'),
  ];

  return showTheavModalSheet<int>(
    context: context,
    title: 'Автоудаление сообщений',
    showCloseButton: true,
    builder: (ctx) {
      final palette = ctx.theav;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Новые сообщения в этом чате будут автоматически удаляться у всех участников после истечения выбранного срока.',
              style: TextStyle(color: palette.subtext, fontSize: 13),
            ),
          ),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            children: [
              for (final preset in presets)
                TheavListRow(
                  leading: iconoir.Timer(
                    width: 20,
                    height: 20,
                    color: preset.seconds == 0 ? palette.subtext : palette.primary,
                  ),
                  title: preset.label,
                  trailing: currentSeconds == preset.seconds
                      ? Icon(Icons.check_rounded, color: palette.primary)
                      : null,
                  onTap: () {
                    HapticUtils.selection();
                    Navigator.of(ctx).pop(preset.seconds);
                  },
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// Telegram-style Pin confirmation ("Pin for both" vs "Only for me" in DMs, or silent/notify in groups).
Future<({bool onlyForMe, bool notify})?> showPinOptionsSheet(
  BuildContext context, {
  required bool isPrivateChat,
  String peerName = '',
}) {
  return showTheavModalSheet<({bool onlyForMe, bool notify})>(
    context: context,
    title: 'Закрепить сообщение',
    showCloseButton: true,
    builder: (ctx) {
      final palette = ctx.theav;
      return TheavInsetGroup(
        margin: EdgeInsets.zero,
        children: [
          if (isPrivateChat) ...[
            TheavListRow(
              leading: iconoir.Pin(width: 20, height: 20, color: palette.primary),
              title: peerName.isNotEmpty
                  ? 'Закрепить для меня и $peerName'
                  : 'Закрепить для обоих',
              onTap: () => Navigator.of(ctx).pop((onlyForMe: false, notify: true)),
            ),
            TheavListRow(
              leading:
                  iconoir.User(width: 20, height: 20, color: palette.primary),
              title: 'Закрепить только для меня',
              onTap: () => Navigator.of(ctx).pop((onlyForMe: true, notify: false)),
            ),
          ] else ...[
            TheavListRow(
              leading: iconoir.Pin(width: 20, height: 20, color: palette.primary),
              title: 'Закрепить и уведомить участников',
              onTap: () => Navigator.of(ctx).pop((onlyForMe: false, notify: true)),
            ),
            TheavListRow(
              leading:
                  iconoir.BellOff(width: 20, height: 20, color: palette.primary),
              title: 'Закрепить без уведомления',
              onTap: () => Navigator.of(ctx).pop((onlyForMe: false, notify: false)),
            ),
          ],
        ],
      );
    },
  );
}

/// Telegram-style Abuse Report sheet backed by `POST /api/reports`.
Future<bool> showAbuseReportSheet(
  BuildContext context, {
  String? chatId,
  String? targetUserId,
  List<String> messageIds = const [],
}) async {
  final res = await showTheavModalSheet<bool>(
    context: context,
    title: 'Пожаловаться',
    showCloseButton: true,
    builder: (ctx) => _AbuseReportSheetBody(
      chatId: chatId,
      targetUserId: targetUserId,
      messageIds: messageIds,
    ),
  );
  return res == true;
}

class _AbuseReportSheetBody extends StatefulWidget {
  final String? chatId;
  final String? targetUserId;
  final List<String> messageIds;

  const _AbuseReportSheetBody({
    this.chatId,
    this.targetUserId,
    this.messageIds = const [],
  });

  @override
  State<_AbuseReportSheetBody> createState() => _AbuseReportSheetBodyState();
}

class _AbuseReportSheetBodyState extends State<_AbuseReportSheetBody> {
  static const _reasons = <({String key, String label})>[
    (key: 'spam', label: 'Спам'),
    (key: 'violence', label: 'Насилие'),
    (key: 'pornography', label: 'Материалы 18+'),
    (key: 'illegal_drugs', label: 'Запрещённые товары'),
    (key: 'personal_details', label: 'Личные данные'),
    (key: 'fake', label: 'Мошенничество или фейк'),
    (key: 'copyright', label: 'Нарушение авторских прав'),
    (key: 'other', label: 'Другое'),
  ];

  String _selectedReason = 'spam';
  final TextEditingController _detailsCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final result = await DmParityService.submitReport(
      chatId: widget.chatId,
      targetUserId: widget.targetUserId,
      messageIds: widget.messageIds,
      reason: _selectedReason,
      details: _detailsCtrl.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result['success'] == true) {
      GlassToastService().show(context, 'Жалоба отправлена');
      Navigator.of(context).pop(true);
    } else {
      GlassToastService().showError(
        context,
        result['message']?.toString() ?? 'Не удалось отправить жалобу',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TheavInsetGroup(
          margin: const EdgeInsets.only(bottom: 10),
          children: [
            for (final r in _reasons)
              TheavListRow(
                title: r.label,
                trailing: _selectedReason == r.key
                    ? Icon(Icons.check_rounded, color: palette.primary)
                    : null,
                onTap: () {
                  HapticUtils.selection();
                  setState(() => _selectedReason = r.key);
                },
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _detailsCtrl,
            maxLines: 2,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Комментарий (необязательно)',
              filled: true,
              fillColor: palette.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.divider, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.divider, width: 0.5),
              ),
            ),
          ),
        ),
        TheavFloatingPillButton(
          label: _submitting ? 'Отправка...' : 'Отправить жалобу',
          icon: const iconoir.WarningCircle(
            width: 18,
            height: 18,
            color: Colors.white,
          ),
          isDestructive: true,
          enabled: !_submitting,
          onTap: _submit,
        ),
      ],
    );
  }
}

/// Curated Per-Chat Theme / Wallpaper ("For Both") selector.
Future<ChatAppearanceDialogResult?> showChatAppearanceSheet(
  BuildContext context, {
  required String chatId,
  ChatAppearanceConfig? current,
  required bool canApplyForBoth,
}) {
  return showTheavModalSheet<ChatAppearanceDialogResult>(
    context: context,
    title: 'Оформление чата',
    showCloseButton: true,
    builder: (ctx) => _ChatAppearanceSheetBody(
      chatId: chatId,
      current: current,
      canApplyForBoth: canApplyForBoth,
    ),
  );
}

class ChatAppearancePreset {
  final String id;
  final String label;
  final List<Color> colors;
  final String accent;

  const ChatAppearancePreset({
    required this.id,
    required this.label,
    required this.colors,
    required this.accent,
  });
}

const List<ChatAppearancePreset> kChatAppearancePresets = [
  ChatAppearancePreset(
    id: 'aurora_blue',
    label: 'Северное сияние',
    colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    accent: '5CAEFF',
  ),
  ChatAppearancePreset(
    id: 'sunset_peach',
    label: 'Закат',
    colors: [Color(0xFF3E1E38), Color(0xFF8E3B59), Color(0xFFD67D6B)],
    accent: 'FF8E72',
  ),
  ChatAppearancePreset(
    id: 'mint_forest',
    label: 'Изумрудный лес',
    colors: [Color(0xFF0E2A25), Color(0xFF1A4B42), Color(0xFF2D7A68)],
    accent: '4FD1A5',
  ),
  ChatAppearancePreset(
    id: 'lavender_dusk',
    label: 'Лаванда',
    colors: [Color(0xFF211C3B), Color(0xFF3E356B), Color(0xFF6B5CA5)],
    accent: '9D8CFF',
  ),
  ChatAppearancePreset(
    id: 'graphite_night',
    label: 'Графит',
    colors: [Color(0xFF14161A), Color(0xFF22262E), Color(0xFF2E3440)],
    accent: '64B5F6',
  ),
];

/// Builds a fullscreen custom background widget for `ChatScaffold.customBackground`
/// from per-chat [ChatAppearanceConfig], or returns `null` when default theme should apply.
Widget? buildChatAppearanceBackgroundWidget(ChatAppearanceConfig? config) {
  if (config == null || config.isEmpty) return null;
  final rawList = config.wallpaperSettings['gradient_colors'];
  List<Color>? gradientColors;
  if (rawList is List) {
    final parsed = <Color>[];
    for (final item in rawList) {
      if (item is int) {
        parsed.add(Color(item));
      } else if (item is String) {
        final hex = item.replaceFirst('#', '');
        final val = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
        if (val != null) parsed.add(Color(val));
      }
    }
    if (parsed.length >= 2) gradientColors = parsed;
  }
  if (gradientColors == null && config.themeId.isNotEmpty) {
    for (final p in kChatAppearancePresets) {
      if (p.id == config.themeId) {
        gradientColors = p.colors;
        break;
      }
    }
  }
  if (gradientColors != null && gradientColors.length >= 2) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
      ),
    );
  }
  return null;
}

class _ChatAppearanceSheetBody extends StatefulWidget {
  final String chatId;
  final ChatAppearanceConfig? current;
  final bool canApplyForBoth;

  const _ChatAppearanceSheetBody({
    required this.chatId,
    this.current,
    required this.canApplyForBoth,
  });

  @override
  State<_ChatAppearanceSheetBody> createState() =>
      _ChatAppearanceSheetBodyState();
}

class _ChatAppearanceSheetBodyState extends State<_ChatAppearanceSheetBody> {
  static const List<ChatAppearancePreset> _presets = kChatAppearancePresets;

  late String _selectedThemeId;
  late String _selectedAccent;
  late bool _forBoth;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedThemeId = widget.current?.themeId.isNotEmpty == true
        ? widget.current!.themeId
        : _presets.first.id;
    _selectedAccent = widget.current?.accentColorId.isNotEmpty == true
        ? widget.current!.accentColorId
        : _presets.first.accent;
    _forBoth = widget.current?.isShared == true && widget.canApplyForBoth;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final preset = _presets.firstWhere(
      (p) => p.id == _selectedThemeId,
      orElse: () => _presets.first,
    );
    final config = ChatAppearanceConfig(
      themeId: _selectedThemeId,
      accentColorId: _selectedAccent,
      wallpaperSettings: {
        'gradient_colors': preset.colors
            .map((c) => c.toARGB32())
            .toList(),
      },
      isShared: _forBoth,
    );
    final res = await DmParityService.updateChatAppearance(
      widget.chatId,
      config,
      forBoth: _forBoth,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.of(context).pop(
        ChatAppearanceDialogResult(
          changed: true,
          appearance: (res['appearance'] as ChatAppearanceConfig?) ?? config,
        ),
      );
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось сохранить оформление',
      );
    }
  }

  Future<void> _reset() async {
    if (_saving) return;
    setState(() => _saving = true);
    final res = await DmParityService.deleteChatAppearance(
      widget.chatId,
      forBoth: _forBoth,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.of(context).pop(
        ChatAppearanceDialogResult(
          changed: true,
          appearance: res['appearance'] as ChatAppearanceConfig?,
        ),
      );
    } else {
      GlassToastService().showError(context, 'Не удалось сбросить тему');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, idx) {
              final p = _presets[idx];
              final selected = p.id == _selectedThemeId;
              return GestureDetector(
                onTap: () {
                  HapticUtils.selection();
                  setState(() {
                    _selectedThemeId = p.id;
                    _selectedAccent = p.accent;
                  });
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: p.colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: selected ? palette.primary : palette.divider,
                          width: selected ? 2.5 : 0.8,
                        ),
                      ),
                      child: selected
                          ? const Center(
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.black54,
                                child: Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 84,
                      child: Text(
                        p.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? palette.primary : palette.subtext,
                          fontSize: 11.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (widget.canApplyForBoth)
          TheavInsetGroup(
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              AdaptiveSwitchListTile(
                title: const Text('Применить для обоих'),
                subtitle: const Text('Собеседник тоже увидит эту тему'),
                value: _forBoth,
                onChanged: (v) => setState(() => _forBoth = v),
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TheavFloatingPillButton(
                label: 'Сбросить',
                enabled: !_saving,
                onTap: _reset,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TheavFloatingPillButton(
                label: _saving ? 'Сохранение...' : 'Применить',
                icon: iconoir.Palette(
                  width: 18,
                  height: 18,
                  color: palette.onPrimary,
                ),
                isPrimary: true,
                enabled: !_saving,
                onTap: _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Telegram-style message send effect selector (`fire`, `heart`, `confetti`, etc.).
Future<String?> showMessageEffectPickerSheet(
  BuildContext context, {
  String? currentEffectId,
}) {
  const effects = <({String id, String emoji, String label})>[
    (id: 'fire', emoji: '🔥', label: 'Огонь'),
    (id: 'heart', emoji: '❤️', label: 'Сердечки'),
    (id: 'confetti', emoji: '🎉', label: 'Конфетти'),
    (id: 'thumbs_up', emoji: '👍', label: 'Палец вверх'),
    (id: 'lightning', emoji: '⚡', label: 'Молния'),
    (id: 'party', emoji: '🥳', label: 'Праздник'),
  ];

  return showTheavModalSheet<String>(
    context: context,
    title: 'Эффект при отправке',
    showCloseButton: true,
    builder: (ctx) {
      final palette = ctx.theav;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            children: [
              for (final e in effects)
                TheavListRow(
                  leading: Text(e.emoji, style: const TextStyle(fontSize: 20)),
                  title: e.label,
                  trailing: currentEffectId == e.id
                      ? Icon(Icons.check_rounded, color: palette.primary)
                      : null,
                  onTap: () {
                    HapticUtils.selection();
                    Navigator.of(ctx).pop(e.id);
                  },
                ),
              if (currentEffectId != null && currentEffectId.isNotEmpty)
                TheavListRow(
                  title: 'Без эффекта',
                  isDestructive: true,
                  onTap: () => Navigator.of(ctx).pop(''),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// Prompt to edit or clear a custom text label on a Saved Messages emoji tag.
Future<String?> showSavedTagLabelSheet(
  BuildContext context, {
  required String tag,
  String currentLabel = '',
}) {
  return showTheavModalSheet<String>(
    context: context,
    title: 'Название тега $tag',
    showCloseButton: true,
    builder: (ctx) => _SavedTagLabelSheetBody(
      tag: tag,
      currentLabel: currentLabel,
    ),
  );
}

class _SavedTagLabelSheetBody extends StatefulWidget {
  final String tag;
  final String currentLabel;

  const _SavedTagLabelSheetBody({
    required this.tag,
    required this.currentLabel,
  });

  @override
  State<_SavedTagLabelSheetBody> createState() =>
      _SavedTagLabelSheetBodyState();
}

class _SavedTagLabelSheetBodyState extends State<_SavedTagLabelSheetBody> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentLabel);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(
            hintText: 'Например: Работа, Пароли, Идеи...',
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.divider, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.divider, width: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TheavFloatingPillButton(
                label: 'Очистить',
                onTap: () => Navigator.of(context).pop(''),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TheavFloatingPillButton(
                label: 'Сохранить',
                isPrimary: true,
                onTap: () => Navigator.of(context).pop(_ctrl.text.trim()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
