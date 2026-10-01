import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';
import 'widgets/sound_picker_sheet.dart';
import 'chat_notification_settings_screen.dart';

enum ChatCategory {
  privateChats,
  groupChats,
  channels,
}

class ChatTypeNotificationsScreen extends StatelessWidget {
  final ChatCategory category;

  const ChatTypeNotificationsScreen({
    Key? key,
    required this.category,
  }) : super(key: key);

  String _getTitle(AppLocalizations l10n) {
    switch (category) {
      case ChatCategory.privateChats:
        return l10n.translate('notifications_private_chats');
      case ChatCategory.groupChats:
        return l10n.translate('notifications_group_chats');
      case ChatCategory.channels:
        return l10n.translate('notifications_channels');
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

  String _soundLabel(String? uri) {
    if (uri == null || uri.isEmpty) return 'По умолчанию';
    for (final opt in kAvailableNotificationSounds) {
      if (opt.id == uri) return opt.title;
    }
    return uri;
  }

  void _showVibrationPicker(
    BuildContext context,
    VibrationPattern current,
    ValueChanged<VibrationPattern> onChanged,
  ) {
    final l10n = context.l10n;
    HapticUtils.tap();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.translate('notifications_vibration'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ...VibrationPattern.values.map(
                (pattern) => ListTile(
                  title: Text(_vibrationLabel(pattern, l10n)),
                  trailing: pattern == current
                      ? const Icon(Icons.check, color: Color(0xFF0088CC))
                      : null,
                  onTap: () {
                    HapticUtils.selection();
                    onChanged(pattern);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _getTitle(l10n);

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        final body = Consumer<NotificationSettingsProvider>(
          builder: (context, provider, _) {
            final s = provider.globalSettings;

            bool isEnabled;
            bool isPreview;
            bool isSound;
            String? soundUri;
            VibrationPattern vibration;

            switch (category) {
              case ChatCategory.privateChats:
                isEnabled = s.privateChatNotifications;
                isPreview = s.privateChatPreview;
                isSound = s.privateChatSound;
                soundUri = s.privateChatSoundUri;
                vibration = s.privateChatVibration;
                break;
              case ChatCategory.groupChats:
                isEnabled = s.groupChatNotifications;
                isPreview = s.groupChatPreview;
                isSound = s.groupChatSound;
                soundUri = s.groupChatSoundUri;
                vibration = s.groupChatVibration;
                break;
              case ChatCategory.channels:
                isEnabled = s.channelNotifications;
                isPreview = s.channelPreview;
                isSound = s.channelSound;
                soundUri = s.channelSoundUri;
                vibration = s.channelVibration;
                break;
            }

            // Исключения, относящиеся к этой категории
            final categoryExceptions = provider.exceptions.where((ex) {
              if (category == ChatCategory.privateChats) return ex.chatType == 'private';
              if (category == ChatCategory.groupChats) return ex.chatType == 'group';
              if (category == ChatCategory.channels) return ex.chatType == 'channel';
              return false;
            }).toList();

            return ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SettingsGroup(
                  title: 'Основные',
                  children: [
                    AdaptiveSwitchListTile(
                      secondary: Icon(
                        category == ChatCategory.privateChats
                            ? Icons.person
                            : (category == ChatCategory.groupChats ? Icons.group : Icons.campaign),
                        color: const Color(0xFF0088CC),
                      ),
                      title: const Text('Оповещения'),
                      subtitle: const Text('Показывать уведомления для этого типа чатов'),
                      value: isEnabled,
                      onChanged: (val) {
                        HapticUtils.selection();
                        if (category == ChatCategory.privateChats) {
                          provider.updateGlobalSettings(privateChatNotifications: val);
                        } else if (category == ChatCategory.groupChats) {
                          provider.updateGlobalSettings(groupChatNotifications: val);
                        } else {
                          provider.updateGlobalSettings(channelNotifications: val);
                        }
                      },
                    ),
                    if (isEnabled) ...[
                      AdaptiveSwitchListTile(
                        title: Text(l10n.translate('notifications_preview')),
                        subtitle: Text(l10n.translate('notifications_preview_desc')),
                        value: isPreview,
                        onChanged: (val) {
                          HapticUtils.selection();
                          if (category == ChatCategory.privateChats) {
                            provider.updateGlobalSettings(privateChatPreview: val);
                          } else if (category == ChatCategory.groupChats) {
                            provider.updateGlobalSettings(groupChatPreview: val);
                          } else {
                            provider.updateGlobalSettings(channelPreview: val);
                          }
                        },
                      ),
                      ListTile(
                        title: Text(l10n.translate('notifications_sound')),
                        subtitle: Text(_soundLabel(soundUri)),
                        trailing: AdaptiveSwitch(
                          value: isSound,
                          onChanged: (val) {
                            HapticUtils.selection();
                            if (category == ChatCategory.privateChats) {
                              provider.updateGlobalSettings(privateChatSound: val);
                            } else if (category == ChatCategory.groupChats) {
                              provider.updateGlobalSettings(groupChatSound: val);
                            } else {
                              provider.updateGlobalSettings(channelSound: val);
                            }
                          },
                        ),
                        onTap: () {
                          SoundPickerSheet.show(
                            context,
                            currentSoundId: soundUri,
                            onSelected: (newSound) {
                              if (category == ChatCategory.privateChats) {
                                provider.updateGlobalSettings(
                                  privateChatSoundUri: newSound,
                                  privateChatSound: newSound != 'none',
                                );
                              } else if (category == ChatCategory.groupChats) {
                                provider.updateGlobalSettings(
                                  groupChatSoundUri: newSound,
                                  groupChatSound: newSound != 'none',
                                );
                              } else {
                                provider.updateGlobalSettings(
                                  channelSoundUri: newSound,
                                  channelSound: newSound != 'none',
                                );
                              }
                            },
                          );
                        },
                      ),
                      ListTile(
                        title: Text(l10n.translate('notifications_vibration')),
                        subtitle: Text(_vibrationLabel(vibration, l10n)),
                        onTap: () => _showVibrationPicker(
                          context,
                          vibration,
                          (pat) {
                            if (category == ChatCategory.privateChats) {
                              provider.updateGlobalSettings(privateChatVibration: pat);
                            } else if (category == ChatCategory.groupChats) {
                              provider.updateGlobalSettings(groupChatVibration: pat);
                            } else {
                              provider.updateGlobalSettings(channelVibration: pat);
                            }
                          },
                        ),
                      ),
                      if (category == ChatCategory.groupChats)
                        AdaptiveSwitchListTile(
                          title: Text(l10n.translate('notifications_mentions')),
                          subtitle: Text(l10n.translate('notifications_mentions_desc')),
                          value: s.mentionsNotifications,
                          onChanged: (val) {
                            HapticUtils.selection();
                            provider.updateGlobalSettings(mentionsNotifications: val);
                          },
                        ),
                    ],
                  ],
                ),

                // Секция исключений
                SettingsGroup(
                  title: 'Исключения (${categoryExceptions.length})',
                  children: [
                    if (categoryExceptions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(
                          'Нет исключений. Индивидуальные настройки для конкретных чатов настраиваются в профиле чата.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    else
                      ...categoryExceptions.map((ex) {
                        final isMuted = ex.settings.muteState == MuteState.muted;
                        String statusDesc = isMuted ? 'Без звука' : 'Включены';
                        if (ex.settings.soundUri != null && ex.settings.soundUri!.isNotEmpty) {
                          statusDesc += ' • ${_soundLabel(ex.settings.soundUri)}';
                        }

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
                            statusDesc,
                            style: TextStyle(
                              color: isMuted ? Colors.orange : Colors.grey[600],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
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
                                ),
                              ),
                            );
                          },
                        );
                      }),
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
                    title: Text(title),
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
            title: Text(title),
            centerTitle: true,
          ),
          body: body,
        );
      },
    );
  }
}
