import 'package:flutter/material.dart';
import '../settings/profile_screen.dart';

/// Экран информации о группе в стиле Telegram.
///
/// Делегирует отображение в универсальный [ProfileScreen] с типом [ProfileEntityType.group],
/// поддерживая Liquid Glass, Material Design, морфинг-капсулу разделов («Участники»,
/// «Подарки», «Медиа», «Файлы», «Ссылки», «Голосовые») и управление группой для админов.
class GroupInfoScreen extends StatelessWidget {
  final String chatId;
  final String? groupName;
  final String? groupAvatar;
  final String? heroTag;
  final VoidCallback? onSearchInChat;
  final ValueChanged<String>? onJumpToMessageId;

  const GroupInfoScreen({
    Key? key,
    required this.chatId,
    this.groupName,
    this.groupAvatar,
    this.heroTag,
    this.onSearchInChat,
    this.onJumpToMessageId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ProfileScreen(
      entityType: ProfileEntityType.group,
      chatId: chatId,
      initialName: groupName,
      initialAvatarUrl: groupAvatar,
      heroTag: heroTag ?? groupName ?? chatId,
      onSearchInChat: onSearchInChat,
      onJumpToMessageId: onJumpToMessageId,
    );
  }
}
