import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';

/// Экран настроек уведомлений для конкретного чата.
/// Доступен из профиля чата / информации о группе.
///
/// На Android звук и вибрация чата применяются через отдельный системный
/// канал уведомлений `chat_<id>_v<n>` (как в Telegram): звук выбирается
/// системным выбором мелодии, а URI звука хранится только на устройстве.
class ChatNotificationSettingsScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  /// Групповой чат или канал (влияет на базовый канал уведомлений Android).
  final bool isGroup;

  /// Канал (для выбора глобальной вибрации по умолчанию).
  final bool isChannel;

  const ChatNotificationSettingsScreen({
    Key? key,
    required this.chatId,
    required this.chatName,
    this.isGroup = false,
    this.isChannel = false,
  }) : super(key: key);

  @override
  State<ChatNotificationSettingsScreen> createState() =>
      _ChatNotificationSettingsScreenState();
}

class _ChatNotificationSettingsScreenState
    extends State<ChatNotificationSettingsScreen> {
  final TextEditingController _keywordController = TextEditingController();

  static const String _soundTitlePrefsPrefix = 'notif_chat_sound_title_';

  /// Название звука, выбранного в системном пикере (Android).
  String? _androidSoundTitle;

  /// Для чата создан собственный канал уведомлений (Android).
  bool _hasCustomChannel = false;

  bool get _supportsChannels => NotificationService().supportsChatChannels;

  String get _soundTitleKey => '$_soundTitlePrefsPrefix${widget.chatId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationSettingsProvider>().init();
    });
    _loadChannelState();
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

    return SettingsFloatingScaffold(
      title: widget.chatName,
      body: _buildSettingsList(context, l10n, theme),
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
          padding: EdgeInsets.only(
            top: SettingsFloatingHeader.topClearanceOf(context) + 8,
            bottom: 80,
          ),
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
                _supportsChannels && _androidSoundTitle != null
                    ? _androidSoundTitle!
                    : soundEnabled == null
                        ? l10n.translate('chat_notif_use_global')
                        : soundEnabled
                            ? 'По умолчанию'
                            : 'Без звука',
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _supportsChannels
                  ? _pickAndroidSound(provider)
                  : _showSoundOptions(context, provider, soundEnabled, l10n),
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
                (pattern) => _setVibration(provider, pattern),
                allowUseGlobal: true,
                l10n: l10n,
              ),
            ),

            // === Системный канал уведомлений (Android) ===
            if (_supportsChannels) ...[
              ListTile(
                leading: const Icon(Icons.settings_applications_outlined,
                    color: Color(0xFF0088CC)),
                title: const Text('Системные настройки канала'),
                trailing: const Icon(Icons.open_in_new, color: Colors.grey),
                onTap: () {
                  HapticUtils.tap();
                  NotificationService().openChatChannelSettings(widget.chatId);
                },
              ),
              if (_hasCustomChannel)
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore,
                      color: Color(0xFF0088CC)),
                  title: const Text('Сбросить к настройкам по умолчанию'),
                  onTap: () {
                    HapticUtils.tap();
                    _resetChatChannel(provider);
                  },
                ),
            ],

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
                if (_supportsChannels) _removeChatChannel();
                provider.removeChatSettings(widget.chatId);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // ======================= Android: per-chat channel =======================

  Future<void> _loadChannelState() async {
    if (!_supportsChannels) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final title = prefs.getString(_soundTitleKey);
      final uri = await NotificationService().chatSoundUri(widget.chatId);
      if (!mounted) return;
      setState(() {
        _androidSoundTitle = title;
        _hasCustomChannel = title != null || uri != null;
      });
    } catch (e) {
      debugPrint('ChatNotificationSettings: failed to load channel state: $e');
    }
  }

  Future<void> _storeSoundTitle(String? title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (title == null) {
        await prefs.remove(_soundTitleKey);
      } else {
        await prefs.setString(_soundTitleKey, title);
      }
    } catch (_) {}
  }

  /// Эффективная вибрация чата: per-chat настройка или глобальная для типа чата.
  VibrationPattern _effectiveVibration(NotificationSettingsProvider provider) {
    final perChat = provider.getChatSettings(widget.chatId)?.vibration;
    if (perChat != null) return perChat;
    final global = provider.globalSettings;
    if (widget.isChannel) return global.channelVibration;
    return widget.isGroup ? global.groupChatVibration : global.privateChatVibration;
  }

  Future<void> _applyChannel(
    NotificationSettingsProvider provider, {
    required String? soundUri,
  }) {
    return NotificationService().applyChatChannelSettings(
      chatId: widget.chatId,
      chatTitle: widget.chatName,
      isGroup: widget.isGroup,
      useCustomChannel: true,
      soundUri: soundUri,
      vibration: _effectiveVibration(provider),
    );
  }

  /// Открывает системный выбор мелодии и применяет звук к каналу чата.
  Future<void> _pickAndroidSound(NotificationSettingsProvider provider) async {
    HapticUtils.tap();
    final service = NotificationService();
    final currentUri = await service.chatSoundUri(widget.chatId);
    final pick = await service.pickChatSound(currentUri: currentUri);
    if (pick == null || !mounted) return;

    final silent = pick.uri == '';
    // На сервер уходит только вкл/выкл звука: «Без звука» направляет пуши в
    // беззвучный канал. URI звука локален для устройства и не отправляется.
    _updateChatSetting(
      provider,
      (existing) => existing.copyWith(soundEnabled: !silent, soundUri: ''),
    );

    final title = pick.title.isNotEmpty
        ? pick.title
        : (silent ? 'Без звука' : 'По умолчанию');
    await _storeSoundTitle(title);
    await _applyChannel(provider, soundUri: pick.uri);
    if (!mounted) return;
    setState(() {
      _androidSoundTitle = title;
      _hasCustomChannel = true;
    });
  }

  void _setVibration(
      NotificationSettingsProvider provider, VibrationPattern? pattern) {
    _updateChatSetting(
      provider,
      (existing) => pattern == null
          ? existing.copyWith(clearVibration: true)
          : existing.copyWith(vibration: pattern),
    );
    if (!_supportsChannels) return;
    // «Как в общих настройках» без собственного канала — менять нечего.
    if (pattern == null && !_hasCustomChannel) return;
    _applyVibrationToChannel(provider);
  }

  Future<void> _applyVibrationToChannel(
      NotificationSettingsProvider provider) async {
    final service = NotificationService();
    String? soundUri;
    String? title = _androidSoundTitle;
    if (_hasCustomChannel) {
      soundUri = await service.chatSoundUri(widget.chatId);
    } else {
      final soundOff =
          provider.getChatSettings(widget.chatId)?.soundEnabled == false;
      soundUri = soundOff ? '' : null;
      title = soundOff ? 'Без звука' : 'По умолчанию';
    }
    if (title != null) await _storeSoundTitle(title);
    await _applyChannel(provider, soundUri: soundUri);
    if (!mounted) return;
    setState(() {
      _androidSoundTitle = title;
      _hasCustomChannel = true;
    });
  }

  /// Удаляет собственный канал чата и сбрасывает звук/вибрацию к общим настройкам.
  Future<void> _resetChatChannel(NotificationSettingsProvider provider) async {
    _updateChatSetting(
      provider,
      (existing) => existing.copyWith(
        clearSoundEnabled: true,
        clearSoundUri: true,
        clearVibration: true,
      ),
    );
    await _removeChatChannel();
  }

  Future<void> _removeChatChannel() async {
    await NotificationService().applyChatChannelSettings(
      chatId: widget.chatId,
      chatTitle: widget.chatName,
      isGroup: widget.isGroup,
      useCustomChannel: false,
    );
    await _storeSoundTitle(null);
    if (!mounted) return;
    setState(() {
      _androidSoundTitle = null;
      _hasCustomChannel = false;
    });
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
                        existing.copyWith(clearSoundEnabled: true, soundUri: ''),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('По умолчанию'),
                trailing: currentSound == true
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  _updateChatSetting(
                    provider,
                    (existing) =>
                        existing.copyWith(soundEnabled: true, soundUri: ''),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Без звука'),
                trailing: currentSound == false
                    ? const Icon(Icons.check, color: Color(0xFF0088CC))
                    : null,
                onTap: () {
                  _updateChatSetting(
                    provider,
                    (existing) =>
                        existing.copyWith(soundEnabled: false, soundUri: ''),
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
    ValueChanged<VibrationPattern?> onChanged, {
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
                    HapticUtils.selection();
                    // null означает «использовать глобальное»
                    onChanged(null);
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
