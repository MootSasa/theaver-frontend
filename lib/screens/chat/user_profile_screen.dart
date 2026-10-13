import 'package:flutter/material.dart';
import '../settings/profile_screen.dart';

/// Унифицированный экран профиля пользователя.
///
/// Делегирует отображение в общий [ProfileScreen], обеспечивая единый дизайн,
/// физику пружинного расширения аватарки, Liquid Glass и плавные Hero-переходы
/// между чатом и экраном профиля.
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
  });

  @override
  Widget build(BuildContext context) {
    return ProfileScreen(
      userId: userId,
      initialName: initialName,
      initialAvatarUrl: initialAvatarUrl,
      initialIsOnline: isOnline,
      initialLastSeen: lastSeen,
      chatId: chatId,
      heroTag: heroTag ?? (userId.isNotEmpty ? userId : (initialName ?? 'profile')),
      onVoiceCall: onVoiceCall,
      onVideoCall: onVideoCall,
    );
  }
}
