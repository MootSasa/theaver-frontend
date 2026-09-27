import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_service.dart';
import '../../services/push_service_detector.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import '../../utils/haptic_utils.dart';
import 'chat_type_notifications_screen.dart';
import 'in_app_notifications_screen.dart';
import 'badge_settings_screen.dart';
import 'notification_exceptions_screen.dart';
import 'widgets/sound_picker_sheet.dart';

/// Экран настроек уведомлений — полная реализация в стиле Telegram.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isSendingTest = false;

  Future<void> _handleSendTestNotification() async {
    HapticUtils.tap();
    setState(() => _isSendingTest = true);

    final res = await NotificationService().sendTestNotification();

    if (!mounted) return;
    setState(() => _isSendingTest = false);

    final success = res['success'] == true;
    final message = res['message'] ?? (success ? 'Тестовое уведомление отправлено' : 'Ошибка отправки');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? const Color(0xFF2E7D32) : Colors.redAccent,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getPushServiceTitle() {
    switch (NotificationService().pushServiceType) {
      case PushServiceType.hms:
        return 'Служба Push: Huawei Push Kit';
      case PushServiceType.gms:
        return 'Служба Push: Google FCM';
      case PushServiceType.none:
        return 'Служба Push: Только локальные';
    }
  }

  String _getPushServiceSubtitle() {
    final detector = PushServiceDetector();
    final hasToken = NotificationService().pushToken != null &&
        NotificationService().pushToken!.isNotEmpty;
    final tokenStatus = hasToken ? 'Токен активен' : 'Токен ожидается';

    if (detector.isHuaweiDevice) {
      return '$tokenStatus • ${detector.hmsStatusDescription}';
    }
    final serviceName = NotificationService().pushServiceType == PushServiceType.gms
        ? 'Google Play Services'
        : 'Без cloud push';
    return '$tokenStatus • $serviceName';
  }

  String _repeatLabel(int minutes) {
    if (minutes <= 0) return 'Выключен';
    if (minutes < 60) return 'Через $minutes мин';
    final hours = minutes ~/ 60;
    return 'Через $hours ч';
  }

  void _showRepeatPicker(BuildContext context, int current, ValueChanged<int> onChanged) {
    HapticUtils.tap();
    final options = [0, 5, 10, 30, 60, 120];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Повтор уведомлений',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const Divider(height: 1),
            ...options.map((m) => ListTile(
                  title: Text(_repeatLabel(m)),
                  trailing: m == current
                      ? const Icon(Icons.check, color: Color(0xFF0088CC))
                      : null,
                  onTap: () {
                    HapticUtils.selection();
                    onChanged(m);
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, NotificationSettingsProvider provider) {
    HapticUtils.tap();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить все настройки'),
        content: const Text(
          'Сбросить все параметры уведомлений к исходным значениям '
          'и удалить все персональные настройки для чатов? Действие необратимо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.resetAllSettings();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Все настройки уведомлений сброшены')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationSettingsProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        final content = Consumer<NotificationSettingsProvider>(
          builder: (context, provider, _) {
            final s = provider.globalSettings;
            final exceptions = provider.exceptions;

            final privateExCount = exceptions.where((e) => e.chatType == 'private').length;
            final groupExCount = exceptions.where((e) => e.chatType == 'group').length;
            final channelExCount = exceptions.where((e) => e.chatType == 'channel').length;

            return ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // === Главный переключатель и статус доставки ===
                SettingsGroup(
                  title: 'Служба уведомлений',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_active, color: Color(0xFF0088CC)),
                      title: Text(l10n.translate('notifications_enabled')),
                      subtitle: Text(l10n.translate('notifications_enabled_desc')),
                      value: s.notificationsEnabled,
                      onChanged: (value) {
                        HapticUtils.selection();
                        provider.updateGlobalSettings(notificationsEnabled: value);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined, color: Color(0xFF0088CC)),
                      title: const Text('Отправить тестовое уведомление'),
                      subtitle: const Text('Проверить локальные и Push-уведомления'),
                      trailing: _isSendingTest
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 20, color: Color(0xFF0088CC)),
                      onTap: _isSendingTest ? null : _handleSendTestNotification,
                    ),
                    ListTile(
                      leading: Icon(
                        NotificationService().pushServiceType == PushServiceType.hms
                            ? Icons.cloud_done_rounded
                            : (NotificationService().pushServiceType == PushServiceType.gms
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded),
                        color: NotificationService().pushServiceType != PushServiceType.none
                            ? const Color(0xFF2E7D32)
                            : Colors.orange,
                      ),
                      title: Text(_getPushServiceTitle()),
                      subtitle: Text(_getPushServiceSubtitle()),
                      trailing: (PushServiceDetector().hmsStatusCode != null &&
                              PushServiceDetector().hmsStatusCode != 0 &&
                              PushServiceDetector().isHuaweiDevice)
                          ? TextButton(
                              onPressed: () {
                                PushServiceDetector().resolveHmsError();
                              },
                              child: const Text('Исправить'),
                            )
                          : null,
                    ),
                  ],
                ),

                if (!s.notificationsEnabled) ...[
                  const SizedBox(height: 32),
                  Center(
                    child: Icon(Icons.notifications_off, size: 64, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      l10n.translate('notifications_disabled_hint'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                if (s.notificationsEnabled) ...[
                  // === Оповещения для чатов ===
                  SettingsGroup(
                    title: 'Оповещения для чатов',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person, color: Color(0xFF0088CC)),
                        title: Text(l10n.translate('notifications_private_chats')),
                        subtitle: Text(
                          '${s.privateChatNotifications ? "Включены" : "Отключены"}'
                          '${privateExCount > 0 ? " • $privateExCount исключений" : ""}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: s.privateChatNotifications,
                              onChanged: (val) {
                                HapticUtils.selection();
                                provider.updateGlobalSettings(privateChatNotifications: val);
                              },
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChatTypeNotificationsScreen(
                                category: ChatCategory.privateChats,
                              ),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.group, color: Color(0xFF0088CC)),
                        title: Text(l10n.translate('notifications_group_chats')),
                        subtitle: Text(
                          '${s.groupChatNotifications ? "Включены" : "Отключены"}'
                          '${groupExCount > 0 ? " • $groupExCount исключений" : ""}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: s.groupChatNotifications,
                              onChanged: (val) {
                                HapticUtils.selection();
                                provider.updateGlobalSettings(groupChatNotifications: val);
                              },
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChatTypeNotificationsScreen(
                                category: ChatCategory.groupChats,
                              ),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.campaign, color: Color(0xFF0088CC)),
                        title: Text(l10n.translate('notifications_channels')),
                        subtitle: Text(
                          '${s.channelNotifications ? "Включены" : "Отключены"}'
                          '${channelExCount > 0 ? " • $channelExCount исключений" : ""}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: s.channelNotifications,
                              onChanged: (val) {
                                HapticUtils.selection();
                                provider.updateGlobalSettings(channelNotifications: val);
                              },
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChatTypeNotificationsScreen(
                                category: ChatCategory.channels,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // === Звонки ===
                  SettingsGroup(
                    title: l10n.translate('notifications_calls'),
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.call, color: Color(0xFF0088CC)),
                        title: Text(l10n.translate('notifications_call_notifications')),
                        value: s.callNotifications,
                        onChanged: (val) {
                          HapticUtils.selection();
                          provider.updateGlobalSettings(callNotifications: val);
                        },
                      ),
                      if (s.callNotifications) ...[
                        ListTile(
                          title: const Text('Мелодия звонка'),
                          subtitle: Text(s.callRingtone != null && s.callRingtone!.isNotEmpty
                              ? s.callRingtone!
                              : 'По умолчанию'),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () {
                            SoundPickerSheet.show(
                              context,
                              title: 'Мелодия звонка',
                              isRingtone: true,
                              currentSoundId: s.callRingtone,
                              onSelected: (tone) {
                                provider.updateGlobalSettings(callRingtone: tone);
                              },
                            );
                          },
                        ),
                        SwitchListTile(
                          title: Text(l10n.translate('notifications_vibration')),
                          value: s.callVibration,
                          onChanged: (val) {
                            HapticUtils.selection();
                            provider.updateGlobalSettings(callVibration: val);
                          },
                        ),
                      ],
                    ],
                  ),

                  // === Значок и в приложении ===
                  SettingsGroup(
                    title: 'Поведение',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge, color: Color(0xFF0088CC)),
                        title: Text(l10n.translate('notifications_badge')),
                        subtitle: Text(s.badgeEnabled
                            ? (s.badgeMode == BadgeMode.messages
                                ? 'Включен • Количество сообщений'
                                : 'Включен • Количество чатов')
                            : 'Отключен'),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BadgeSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.phone_android, color: Color(0xFF0088CC)),
                        title: const Text('Уведомления в приложении'),
                        subtitle: const Text('Звуки, вибрация, предпросмотр'),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InAppNotificationsScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.update, color: Color(0xFF0088CC)),
                        title: const Text('Повторять уведомления'),
                        subtitle: Text(_repeatLabel(s.repeatNotifications)),
                        onTap: () => _showRepeatPicker(
                          context,
                          s.repeatNotifications,
                          (m) => provider.updateGlobalSettings(repeatNotifications: m),
                        ),
                      ),
                    ],
                  ),

                  // === Фоновое подключение (для VPN и надежности) ===
                  SettingsGroup(
                    title: 'Фоновые службы',
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.wifi_tethering, color: Color(0xFF0088CC)),
                        title: const Text('Фоновое подключение'),
                        subtitle: const Text(
                          'Постоянное соединение в фоне для надежной доставки сообщений и работы через VPN (как в Telegram)',
                        ),
                        value: provider.backgroundConnection,
                        onChanged: (val) {
                          HapticUtils.selection();
                          provider.updateBackgroundConnection(val);
                        },
                      ),
                    ],
                  ),

                  // === Исключения ===
                  SettingsGroup(
                    title: 'Исключения',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tune, color: Color(0xFF0088CC)),
                        title: const Text('Исключения'),
                        subtitle: Text(
                          exceptions.isEmpty
                              ? 'Нет исключений'
                              : '${exceptions.length} чатов с особыми настройками',
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationExceptionsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // === Сброс ===
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(height: 1),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore, color: Colors.redAccent),
                    title: const Text(
                      'Сбросить все настройки',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    subtitle: const Text(
                      'Сбросить все настройки уведомлений и удалить исключения',
                    ),
                    onTap: () => _showResetDialog(context, provider),
                  ),
                ],
              ],
            );
          },
        );

        if (glassEnabled) {
          final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: content,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: Text(l10n.translate('notifications_title')),
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
            title: Text(l10n.translate('notifications_title')),
            centerTitle: true,
          ),
          body: content,
        );
      },
    );
  }
}

