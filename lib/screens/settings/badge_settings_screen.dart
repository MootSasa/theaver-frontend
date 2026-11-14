import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';

class BadgeSettingsScreen extends StatelessWidget {
  const BadgeSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const title = 'Значок на иконке';

    return SettingsFloatingScaffold(
      title: title,
      body: Consumer<NotificationSettingsProvider>(
        builder: (context, provider, _) {
          final s = provider.globalSettings;

          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              top: SettingsFloatingHeader.topClearanceOf(context) + 8,
              bottom: 24,
            ),
              children: [
                SettingsGroup(
                  title: 'Значок приложения',
                  children: [
                    AdaptiveSwitchListTile(
                      secondary: const Icon(Icons.badge, color: Color(0xFF0088CC)),
                      title: const Text('Показывать значок'),
                      subtitle: const Text('Отображать количество непрочитанных на иконке приложения'),
                      value: s.badgeEnabled,
                      onChanged: (val) {
                        HapticUtils.selection();
                        provider.updateGlobalSettings(badgeEnabled: val);
                      },
                    ),
                  ],
                ),
                if (s.badgeEnabled) ...[
                  SettingsGroup(
                    title: 'Режим подсчёта',
                    children: [
                      RadioListTile<BadgeMode>(
                        title: const Text('Количество сообщений'),
                        subtitle: const Text('Считать каждое новое непрочитанное сообщение'),
                        value: BadgeMode.messages,
                        groupValue: s.badgeMode,
                        activeColor: const Color(0xFF0088CC),
                        onChanged: (val) {
                          if (val != null) {
                            HapticUtils.selection();
                            provider.updateGlobalSettings(badgeMode: val);
                          }
                        },
                      ),
                      RadioListTile<BadgeMode>(
                        title: const Text('Количество чатов'),
                        subtitle: const Text('Считать только количество чатов с новыми сообщениями'),
                        value: BadgeMode.chats,
                        groupValue: s.badgeMode,
                        activeColor: const Color(0xFF0088CC),
                        onChanged: (val) {
                          if (val != null) {
                            HapticUtils.selection();
                            provider.updateGlobalSettings(badgeMode: val);
                          }
                        },
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: 'Беззвучные чаты',
                    children: [
                      AdaptiveSwitchListTile(
                        secondary: const Icon(Icons.notifications_off_outlined, color: Color(0xFF0088CC)),
                        title: const Text('Включать беззвучные чаты'),
                        subtitle: const Text('Учитывать заглушённые чаты и каналы в счётчике значка'),
                        value: s.includeMutedChats,
                        onChanged: (val) {
                          HapticUtils.selection();
                          provider.updateGlobalSettings(includeMutedChats: val);
                        },
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      );
  }
}
