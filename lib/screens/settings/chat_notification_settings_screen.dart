import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';

/// Экран настроек уведомлений для конкретного чата.
/// Доступен из профиля чата / информации о группе.
class ChatNotificationSettingsScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  const ChatNotificationSettingsScreen({
    Key? key,
    required this.chatId,
    required this.chatName,
  }) : super(key: key);

  @override
  State<ChatNotificationSettingsScreen> createState() =>
      _ChatNotificationSettingsScreenState();
}

class _ChatNotificationSettingsScreenState
    extends State<ChatNotificationSettingsScreen> {
  final TextEditingController _keywordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationSettingsProvider>().init();
    });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        if (glassEnabled) {
          final topPadding =
              MediaQuery.of(context).padding.top + kToolbarHeight;

          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: _buildSettingsList(context, l10n, theme),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: Text(widget.chatName),
                    centerTitle: true,
                    isLite: glassProvider.isLite,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.chatName),
            centerTitle: true,
          ),
          body: _buildSettingsList(context, l10n, theme),
        );
      },
    );
  }

  Widget _buildSettingsList(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    return Consumer<NotificationSettingsProvider>(
      builder: (context, provider, _) {
        final chatSettings = provider.getChatSettings(widget.chatId);
        final muteState = chatSettings?.muteState ?? MuteState.notMuted;
        final muteUntil = chatSettings?.muteUntil;
        final previewEnabled = chatSettings?.previewEnabled ?? true;
        final soundEnabled = chatSettings?.soundEnabled;
        final vibration = chatSettings?.vibration;
        final mentionsOnly = chatSettings?.mentionsOnly ?? false;
        final keywords = chatSettings?.keywords ?? <String>[];

        return ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            // === Без звука (Mute) ===
            _buildSectionHeader(l10n.translate('chat_notif_mute_section')),
            ListTile(
              leading: Icon(
                muteState != MuteState.notMuted
                    ? Icons.notifications_off
                    : Icons.notifications,
                color: const Color(0xFF0088CC),
              ),
              title: Text(l10n.translate('chat_notif_mute')),
              subtitle: Text(_muteLabel(muteState, muteUntil, l10n)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _showMutePicker(context, provider, muteState, l10n),
            ),

            // === Предпросмотр ===
            _buildSectionHeader(l10n.translate('chat_notif_preview_section')),
            AdaptiveSwitchListTile(
              secondary: const Icon(Icons.visibility,
                  color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_notif_preview')),
              subtitle: Text(l10n.translate('chat_notif_preview_desc')),
              value: previewEnabled,
              onChanged: (value) {
                HapticUtils.selection();
                _updateChatSetting(
                  provider,
                  (existing) => existing.copyWith(previewEnabled: value),
                );
              },
            ),

            // === Звук ===
            _buildSectionHeader(l10n.translate('chat_notif_sound_section')),
            ListTile(
              leading: const Icon(Icons.volume_up,
                  color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_notif_sound')),
              subtitle: Text(
                soundEnabled == null
                    ? l10n.translate('chat_notif_use_global')
                    : soundEnabled
                        ? l10n.translate('notifications_sound_on')
                        : l10n.translate('notifications_sound_off'),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _showSoundOptions(context, provider, soundEnabled, l10n),
            ),

            // === Вибрация ===
            _buildSectionHeader(l10n.translate('chat_notif_vibration_section')),
            ListTile(
              leading: const Icon(Icons.vibration,
                  color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_notif_vibration')),
              subtitle: Text(
                vibration == null
                    ? l10n.translate('chat_notif_use_global')
                    : _vibrationLabel(vibration, l10n),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _showVibrationPicker(
                context,
                vibration ?? VibrationPattern.default_,
                (pattern) {
                  _updateChatSetting(
                    provider,
                    (existing) => existing.copyWith(vibration: pattern),
                  );
                },
                allowUseGlobal: true,
                l10n: l10n,
              ),
            ),

            // === Только упоминания ===
            _buildSectionHeader(l10n.translate('chat_notif_mentions_section')),
            AdaptiveSwitchListTile(
              secondary: const Icon(Icons.alternate_email,
                  color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_notif_mentions_only')),
              subtitle: Text(l10n.translate('chat_notif_mentions_only_desc')),
              value: mentionsOnly,
              onChanged: (value) {
                HapticUtils.selection();
                _updateChatSetting(
                  provider,
                  (existing) => existing.copyWith(mentionsOnly: value),
                );
              },
            ),

            // === Ключевые слова ===
            _buildSectionHeader(l10n.translate('chat_notif_keywords_section')),
            AdaptiveSwitchListTile(
              secondary: const Icon(Icons.label,
                  color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_notif_keywords')),
              subtitle: Text(l10n.translate('chat_notif_keywords_desc')),
              value: keywords.isNotEmpty,
              onChanged: (value) {
                HapticUtils.selection();
                if (!value) {
                  _updateChatSetting(
                    provider,
                    (existing) => existing.copyWith(keywords: []),
                  );
                }
              },
            ),
            if (keywords.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: keywords.map((keyword) => Chip(
                        label: Text(keyword),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          final updated = keywords
                              .where((k) => k != keyword)
                              .toList();
                          _updateChatSetting(
                            provider,
                            (existing) =>
                                existing.copyWith(keywords: updated),
                          );
                        },
                      )).toList(),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _keywordController,
                decoration: InputDecoration(
                  hintText: l10n.translate('chat_notif_keyword_hint'),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addKeyword(provider, keywords),
                  ),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                onSubmitted: (_) => _addKeyword(provider, keywords),
              ),
            ),

            // === Сброс ===
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.orange),
              title: Text(
                l10n.translate('chat_notif_reset'),
                style: const TextStyle(color: Colors.orange),
              ),
              subtitle: Text(l10n.translate('chat_notif_reset_desc')),
              onTap: () {
                HapticUtils.tap();
                provider.removeChatSettings(widget.chatId);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _updateChatSetting(
    NotificationSettingsProvider provider,
    ChatNotificationSettings Function(ChatNotificationSettings) updater,
  ) {
    final existing =
        provider.getChatSettings(widget.chatId) ??
        ChatNotificationSettings(chatId: widget.chatId);
    final updated = updater(existing);
    provider.saveChatSettings(widget.chatId, updated);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF0088CC),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _muteLabel(
      MuteState state, DateTime? until, AppLocalizations l10n) {
    switch (state) {
      case MuteState.notMuted:
        return l10n.translate('chat_notif_mute_off');
      case MuteState.muted:
        return l10n.translate('chat_notif_mute_forever');
      case MuteState.mutedUntil:
        if (until != null) {
          final duration = until.difference(DateTime.now());
          if (duration.isNegative) {
            return l10n.translate('chat_notif_mute_expired');
          }
          final hours = duration.inHours;
          final minutes = duration.inMinutes.remainder(60);
          if (hours > 24) {
            final days = hours ~/ 24;
            return l10n.translate('chat_notif_mute_for_days')
                .replaceAll('{days}', days.toString());
          }
          return l10n
              .translate('chat_notif_mute_for_hours')
              .replaceAll('{hours}', hours.toString())
              .replaceAll('{minutes}', minutes.toString().padLeft(2, '0'));
        }
        return l10n.translate('chat_notif_mute_forever');
    }
  }

  String _vibrationLabel(VibrationPattern pattern, AppLocalizations l10n) {
    switch (pattern) {
      case VibrationPattern.default_:
        return l10n.translate('vibration_default');
      case VibrationPattern.none:
        return l10n.translate('vibration_none');
      case VibrationPattern.short:
        return l10n.translate('vibration_short');
      case VibrationPattern.long:
        return l10n.translate('vibration_long');
      case VibrationPattern.doubleShort:
        return l10n.translate('vibration_double_short');
      case VibrationPattern.tripleShort:
        return l10n.translate('vibration_triple_short');
    }
  }

  void _showMutePicker(
    BuildContext context,
    NotificationSettingsProvider provider,
    MuteState current,
    AppLocalizations l10n,
  ) {
    HapticUtils.tap();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.translate('chat_notif_mute'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: Text(l10n.translate('chat_notif_mute_off')),
                trailing: current == MuteState.notMuted
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  provider.setMuteState(widget.chatId, MuteState.notMuted);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off),
                title: Text(l10n.translate('chat_notif_mute_1h')),
                trailing: current == MuteState.mutedUntil
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  provider.setMuteState(
                    widget.chatId,
                    MuteState.mutedUntil,
                    until: DateTime.now().add(const Duration(hours: 1)),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off),
                title: Text(l10n.translate('chat_notif_mute_8h')),
                onTap: () {
                  provider.setMuteState(
                    widget.chatId,
                    MuteState.mutedUntil,
                    until: DateTime.now().add(const Duration(hours: 8)),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off),
                title: Text(l10n.translate('chat_notif_mute_2d')),
                onTap: () {
                  provider.setMuteState(
                    widget.chatId,
                    MuteState.mutedUntil,
                    until: DateTime.now().add(const Duration(days: 2)),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off),
                title: Text(l10n.translate('chat_notif_mute_forever')),
                trailing: current == MuteState.muted
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  provider.setMuteState(widget.chatId, MuteState.muted);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(l10n.translate('chat_notif_mute_custom')),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: this.context,
                    initialDate: now.add(const Duration(days: 1)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    if (!this.context.mounted) return;
                    final time = await showTimePicker(
                      context: this.context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      final until = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        time.hour,
                        time.minute,
                      );
                      provider.setMuteState(
                        widget.chatId,
                        MuteState.mutedUntil,
                        until: until,
                      );
                    }
                  }
                  if (this.context.mounted) Navigator.pop(this.context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSoundOptions(
    BuildContext context,
    NotificationSettingsProvider provider,
    bool? currentSound,
    AppLocalizations l10n,
  ) {
    HapticUtils.tap();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.translate('chat_notif_sound'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.translate('chat_notif_use_global')),
                trailing: currentSound == null
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  _updateChatSetting(
                    provider,
                    (existing) =>
                        existing.copyWith(soundEnabled: null),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(l10n.translate('notifications_sound_on')),
                trailing: currentSound == true
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  _updateChatSetting(
                    provider,
                    (existing) => existing.copyWith(soundEnabled: true),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(l10n.translate('notifications_sound_off')),
                trailing: currentSound == false
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  _updateChatSetting(
                    provider,
                    (existing) => existing.copyWith(soundEnabled: false),
                  );
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVibrationPicker(
    BuildContext context,
    VibrationPattern current,
    ValueChanged<VibrationPattern> onChanged, {
    bool allowUseGlobal = false,
    required AppLocalizations l10n,
  }) {
    HapticUtils.tap();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.translate('chat_notif_vibration'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              if (allowUseGlobal)
                ListTile(
                  title: Text(l10n.translate('chat_notif_use_global')),
                  onTap: () {
                    // null означает «использовать глобальное»
                    _updateChatSetting(
                      context.read<NotificationSettingsProvider>(),
                      (existing) => existing.copyWith(vibration: null),
                    );
                    Navigator.pop(context);
                  },
                ),
              ...VibrationPattern.values.map((pattern) => ListTile(
                    title: Text(_vibrationLabel(pattern, l10n)),
                    trailing: pattern == current
                        ? const Icon(Icons.check, color: Color(0xFF0088CC))
                        : null,
                    onTap: () {
                      HapticUtils.selection();
                      onChanged(pattern);
                      Navigator.pop(context);
                    },
                  )),
            ],
          ),
        );
      },
    );
  }

  void _addKeyword(
      NotificationSettingsProvider provider, List<String> keywords) {
    final text = _keywordController.text.trim();
    if (text.isEmpty) return;
    if (keywords.contains(text)) {
      _keywordController.clear();
      return;
    }
    final updated = [...keywords, text];
    _updateChatSetting(
      provider,
      (existing) => existing.copyWith(keywords: updated),
    );
    _keywordController.clear();
  }
}
