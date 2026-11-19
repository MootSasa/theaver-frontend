import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/image_utils.dart';

/// Telegram-style shared contact card inside a message bubble.
class ContactMessageWidget extends StatelessWidget {
  final Message message;
  final bool isMe;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final void Function(String userId)? onOpenUserProfile;

  const ContactMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    this.onOpenUserProfile,
  });

  String _str(String key) => (message.mediaPayload?[key] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final payloadUserId = _str('user_id');
    final firstName = _str('first_name');
    final lastName = _str('last_name');
    final displayNameField = _str('display_name');
    final phone = _str('phone_number');
    final username = _str('username');
    final avatarUrl = _str('avatar_url');

    final combined = '$firstName $lastName'.trim();
    final title = combined.isNotEmpty
        ? combined
        : (displayNameField.isNotEmpty
            ? displayNameField
            : (message.content.trim().isNotEmpty
                ? message.content.trim()
                : (phone.isNotEmpty ? phone : 'Контакт')));

    final subtitle = phone.isNotEmpty
        ? phone
        : (username.isNotEmpty ? '@$username' : 'Контакт');

    final canOpenProfile =
        payloadUserId.isNotEmpty && payloadUserId != '0' && onOpenUserProfile != null;

    return Container(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accentColor.withValues(alpha: 0.18),
                backgroundImage:
                    avatarUrl.isNotEmpty ? avatarImageProvider(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        title.isNotEmpty ? title[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: isMe ? textColor : accentColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtextColor,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 0.5,
            color: subtextColor.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (canOpenProfile)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onOpenUserProfile!(payloadUserId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          iconoir.User(
                            width: 15,
                            height: 15,
                            color: isMe ? textColor : accentColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Профиль',
                            style: TextStyle(
                              color: isMe ? textColor : accentColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (phone.isNotEmpty)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: phone));
                      if (context.mounted) {
                        GlassToastService().show(context, 'Номер скопирован');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          iconoir.Phone(
                            width: 15,
                            height: 15,
                            color: isMe ? textColor : accentColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Копировать',
                            style: TextStyle(
                              color: isMe ? textColor : accentColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
