import 'package:flutter/material.dart';

import 'private_chat_screen.dart';

/// Unified wrapper for system chats (`chatType == 'system'`), delegating full
/// personal-chat UI and capabilities to [PrivateChatScreen].
class SystemNotificationsScreen extends StatelessWidget {
  final String chatId;
  final String chatName;
  final String? chatAvatar;
  final String? initialMessageId;

  const SystemNotificationsScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.chatAvatar,
    this.initialMessageId,
  });

  @override
  Widget build(BuildContext context) {
    return PrivateChatScreen(
      chatId: chatId,
      otherUserName: chatName,
      otherUserAvatar: chatAvatar,
      initialMessageId: initialMessageId,
      initialChatType: 'system',
    );
  }
}
