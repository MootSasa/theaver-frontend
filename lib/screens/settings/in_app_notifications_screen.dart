import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';

class InAppNotificationsScreen extends StatelessWidget {
  const InAppNotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const title = 'Уведомления в приложении';

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
                  title: 'В приложении',
                  children: [
                    AdaptiveSwitchListTile(
                      secondary: const Icon(Icons.volume_up, color: Color(0xFF0088CC)),
                      title: const Text('Звуки в приложении'),
                      subtitle: const Text('Воспроизводить звуки при получении новых сообщений'),
                      value: s.inAppSounds,
                      onChanged: (val) {
                        HapticUtils.selection();
                        provider.updateGlobalSettings(inAppSounds: val);
                      },
                    ),
                    AdaptiveSwitchListTile(
                      secondary: const Icon(Icons.vibration, color: Color(0xFF0088CC)),
                      title: const Text('Вибрация в приложении'),
                      subtitle: const Text('Вибрировать при получении сообщений'),
                      value: s.inAppVibrate,
                      onChanged: (val) {
                        HapticUtils.selection();
                        provider.updateGlobalSettings(inAppVibrate: val);
                      },
                    ),
                    AdaptiveSwitchListTile(
                      secondary: const Icon(Icons.picture_in_picture, color: Color(0xFF0088CC)),
                      title: const Text('Предпросмотр в приложении'),
                      subtitle: const Text('Показывать всплывающий баннер вверху экрана'),
                      value: s.inAppPreview,
                      onChanged: (val) {
                        HapticUtils.selection();
                        provider.updateGlobalSettings(inAppPreview: val);
                      },
                    ),
                    AdaptiveSwitchListTile(
                      secondary: const Icon(Icons.chat_bubble_outline, color: Color(0xFF0088CC)),
                      title: const Text('Звуки в чатах'),
                      subtitle: const Text('Звуки отправки и получения сообщений в активном чате'),
                      value: s.inAppChatSounds,
                      onChanged: (val) {
                        HapticUtils.selection();
                        provider.updateGlobalSettings(inAppChatSounds: val);
                      },
                    ),
                  ],
                ),
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
