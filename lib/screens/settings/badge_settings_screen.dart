import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';

class BadgeSettingsScreen extends StatelessWidget {
  const BadgeSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const title = 'Значок на иконке';

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        final body = Consumer<NotificationSettingsProvider>(
          builder: (context, provider, _) {
            final s = provider.globalSettings;

            return ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
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
        );

        if (glassEnabled) {
          final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: body,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: const Text(title),
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
            title: const Text(title),
            centerTitle: true,
          ),
          body: body,
        );
      },
    );
  }
}
