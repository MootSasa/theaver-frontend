import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import '../../utils/haptic_utils.dart';
import 'chat_notification_settings_screen.dart';

class NotificationExceptionsScreen extends StatelessWidget {
  const NotificationExceptionsScreen({Key? key}) : super(key: key);

  String _formatExceptionDescription(ChatNotificationSettings s) {
    final parts = <String>[];
    if (s.muteState == MuteState.muted) {
      parts.add('Без звука');
    } else if (s.muteState == MuteState.mutedUntil && s.muteUntil != null) {
      final hours = s.muteUntil!.difference(DateTime.now()).inHours;
      if (hours > 0) {
        parts.add('Без звука на $hoursч');
      } else {
        parts.add('Без звука');
      }
    }
    if (!s.previewEnabled) {
      parts.add('Без предпросмотра');
    }
    if (s.soundEnabled == false) {
      parts.add('Звук выкл');
    }
    if (s.mentionsOnly) {
      parts.add('Только упоминания');
    }
    return parts.isEmpty ? 'Особые настройки' : parts.join(' • ');
  }

  void _showClearAllDialog(BuildContext context, NotificationSettingsProvider provider) {
    HapticUtils.tap();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить исключения'),
        content: const Text(
          'Удалить все индивидуальные настройки уведомлений для чатов? '
          'Ко всем чатам будут применяться общие настройки.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.resetAllChatSettings();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Все исключения сброшены')),
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
  Widget build(BuildContext context) {
    const title = 'Исключения';

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        final body = Consumer<NotificationSettingsProvider>(
          builder: (context, provider, _) {
            final exceptions = provider.exceptions;

            if (exceptions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tune_rounded, size: 72, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Нет исключений',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Вы можете настроить персональные параметры уведомлений в профиле любого чата или группы.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }

            final privateList = exceptions.where((e) => e.chatType == 'private').toList();
            final groupList = exceptions.where((e) => e.chatType == 'group').toList();
            final channelList = exceptions.where((e) => e.chatType == 'channel').toList();

            return ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (privateList.isNotEmpty)
                  SettingsGroup(
                    title: 'Личные чаты (${privateList.length})',
                    children: privateList.map((ex) => _buildExceptionTile(context, provider, ex)).toList(),
                  ),
                if (groupList.isNotEmpty)
                  SettingsGroup(
                    title: 'Группы (${groupList.length})',
                    children: groupList.map((ex) => _buildExceptionTile(context, provider, ex)).toList(),
                  ),
                if (channelList.isNotEmpty)
                  SettingsGroup(
                    title: 'Каналы (${channelList.length})',
                    children: channelList.map((ex) => _buildExceptionTile(context, provider, ex)).toList(),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                    label: const Text(
                      'Сбросить все исключения',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _showClearAllDialog(context, provider),
                  ),
                ),
                const SizedBox(height: 24),
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

  Widget _buildExceptionTile(
    BuildContext context,
    NotificationSettingsProvider provider,
    ChatNotificationException ex,
  ) {
    final isMuted = ex.settings.muteState == MuteState.muted;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF0088CC).withValues(alpha: 0.15),
        child: Text(
          ex.chatTitle.isNotEmpty ? ex.chatTitle[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Color(0xFF0088CC),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(ex.chatTitle),
      subtitle: Text(
        _formatExceptionDescription(ex.settings),
        style: TextStyle(
          color: isMuted ? Colors.orange : Colors.grey[600],
          fontSize: 13,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 20, color: Colors.grey),
        tooltip: 'Удалить исключение',
        onPressed: () {
          HapticUtils.tap();
          provider.removeChatSettings(ex.settings.chatId);
        },
      ),
      onTap: () {
        HapticUtils.tap();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatNotificationSettingsScreen(
              chatId: ex.settings.chatId,
              chatName: ex.chatTitle,
              isGroup: ex.chatType != 'private',
              isChannel: ex.chatType == 'channel',
            ),
          ),
        );
      },
    );
  }
}
