import 'avatar_gallery_viewer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/profile_customization.dart';
import '../../services/contacts_service.dart';
import '../../services/peer_customization_cache.dart';
import '../common/peer_badges_widget.dart';
import '../user/avatar_with_status.dart';
import '../user/emoji_status_badge.dart';

/// Попап с информацией о пользователе, который был найден через QR-код.
///
/// Показывает: аватарку, имя, username, кнопку «Начать чат».
/// Не на весь экран — компактный диалог.
/// Поддерживает светлую и тёмную тему приложения.
class UserProfilePopup extends StatefulWidget {
  /// ID пользователя
  final String userId;

  /// Отображаемое имя
  final String displayName;

  /// Username (без @)
  final String username;

  /// URL аватарки
  final String? avatarUrl;

  /// Локализованная подпись кнопки «Начать чат с {name}»
  final String startChatLabel;

  /// Локализованная подпись «Закрыть»
  final String closeLabel;

  /// Коллбэк при нажатии «Начать чат»
  final VoidCallback? onStartChat;

  const UserProfilePopup({
    Key? key,
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.startChatLabel = 'Начать чат',
    this.closeLabel = 'Закрыть',
    this.onStartChat,
  }) : super(key: key);

  /// Показать попап
  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String displayName,
    required String username,
    String? avatarUrl,
    String startChatLabel = 'Начать чат',
    String closeLabel = 'Закрыть',
    VoidCallback? onStartChat,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => UserProfilePopup(
        userId: userId,
        displayName: displayName,
        username: username,
        avatarUrl: avatarUrl,
        startChatLabel: startChatLabel,
        closeLabel: closeLabel,
        onStartChat: onStartChat,
      ),
    );
  }

  @override
  State<UserProfilePopup> createState() => _UserProfilePopupState();
}

class _UserProfilePopupState extends State<UserProfilePopup> {
  bool _isCreating = false;

  Future<void> _handleStartChat() async {
    setState(() => _isCreating = true);
    try {
      widget.onStartChat?.call();
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    PeerCustomization? customization;
    try {
      customization = context.select<PeerCustomizationCache?, PeerCustomization?>(
        (cache) => cache?.getSync(widget.userId),
      );
    } catch (_) {
      customization = PeerCustomizationCache.instance.getSync(widget.userId);
    }

    // Цвета из палитры приложения
    final backgroundColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final onSurfaceColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E);
    final secondaryColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43);
    const brandColor = Color(0xFF0088CC);

    return ValueListenableBuilder<int>(
      valueListenable: ContactsService.revisionNotifier,
      builder: (context, _, __) {
        final resolvedName = ContactsService.resolvePeerName(
          widget.userId,
          widget.displayName,
        );
        final resolvedAvatar = ContactsService.resolvePeerAvatarUrl(
          widget.userId,
          widget.avatarUrl,
        );

        return Dialog(
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Кнопка закрытия
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: secondaryColor, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(height: 8),

                // Аватарка
                GestureDetector(
                  onTap: resolvedAvatar != null && resolvedAvatar.isNotEmpty
                      ? () => AvatarGalleryViewer.open(
                            context,
                            avatarUrls: [resolvedAvatar],
                            displayName: resolvedName,
                          )
                      : null,
                  child: Hero(
                    tag: 'avatar_hero_$resolvedAvatar',
                    flightShuttleBuilder: (
                      flightContext,
                      animation,
                      flightDirection,
                      fromHeroContext,
                      toHeroContext,
                    ) {
                      final CurvedAnimation curvedAnimation = CurvedAnimation(
                        parent: animation,
                        curve: Curves.fastOutSlowIn,
                      );
                      return AnimatedBuilder(
                        animation: curvedAnimation,
                        builder: (context, child) {
                          final double currentRadius = (1.0 - curvedAnimation.value) * 40.0;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(currentRadius),
                            child: toHeroContext.widget,
                          );
                        },
                      );
                    },
                    child: AvatarWithStatus(
                      userId: widget.userId,
                      avatarUrl: resolvedAvatar,
                      name: resolvedName,
                      radius: 40,
                      backgroundColor:
                          isDark ? const Color(0xFF3C3C43) : const Color(0xFFE0E0E0),
                      decorationOverride: customization?.avatarDecoration,
                      showDecoration: true,
                      animateDecoration: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Имя + статус + бейдж
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        resolvedName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: onSurfaceColor,
                        ),
                      ),
                    ),
                    if (customization?.activeEmojiStatus != null) ...[
                      const SizedBox(width: 6),
                      EmojiStatusBadge(
                        status: customization!.activeEmojiStatus,
                        size: 18,
                        animate: true,
                      ),
                    ],
                    PeerBadgesRow(
                      badge: customization?.visibleBadge,
                      interactiveBadge: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Username
                Text(
                  '@${widget.username}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: brandColor,
                  ),
                ),
                const SizedBox(height: 24),

                // Кнопка «Начать чат»
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _handleStartChat,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.startChatLabel,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
