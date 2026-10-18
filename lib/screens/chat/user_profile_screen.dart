import 'package:flutter/material.dart';
import '../settings/profile_screen.dart';

/// Унифицированный экран профиля пользователя.
///
/// Делегирует отображение в общий [ProfileScreen] с типом [ProfileEntityType.user],
/// обеспечивая единый дизайн, физику пружинного расширения аватарки, Liquid Glass
/// и плавные Hero-переходы между чатом и экраном профиля.
class UserProfileScreen extends StatelessWidget {
  final String userId;
  final String? initialName;
  final String? initialAvatarUrl;
  final bool? isOnline;
  final DateTime? lastSeen;
  final String? chatId;
  final String? heroTag;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onSearchInChat;
  final ValueChanged<String>? onJumpToMessageId;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.initialAvatarUrl,
    this.isOnline,
    this.lastSeen,
    this.chatId,
    this.heroTag,
    this.onVoiceCall,
    this.onVideoCall,
    this.onSearchInChat,
    this.onJumpToMessageId,
  });

  @override
  Widget build(BuildContext context) {
    final isSelf = userId.isEmpty;
    return ProfileScreen(
      entityType: isSelf ? ProfileEntityType.self : ProfileEntityType.user,
      userId: isSelf ? null : userId,
      initialName: isSelf ? null : initialName,
      initialAvatarUrl: initialAvatarUrl,
      initialIsOnline: isSelf ? null : isOnline,
      initialLastSeen: isSelf ? null : lastSeen,
      chatId: chatId,
      heroTag: heroTag ?? (userId.isNotEmpty ? userId : (initialName ?? 'profile')),
      onVoiceCall: isSelf ? null : onVoiceCall,
      onVideoCall: isSelf ? null : onVideoCall,
      onSearchInChat: onSearchInChat,
      onJumpToMessageId: onJumpToMessageId,
    );
  }
}
