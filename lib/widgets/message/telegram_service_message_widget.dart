import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/image_utils.dart';

/// Telegram-style structured service/system message pill for groups and channels.
///
/// Parses `message.mediaPayload?['system_action']` and supports:
/// - `chat_created`
/// - `photo_updated` (pill + clickable 64dp circular preview)
/// - `title_updated`
/// - `message_pinned` (clickable pill with `iconoir.Pin`)
/// - `member_joined` / `member_added` (clickable actor & target user names)
/// - `voice_chat_started` / `voice_chat_ended` (`iconoir.SoundHigh` + duration)
/// - Fallback: centered pill with `message.content`
class TelegramServiceMessageWidget extends StatelessWidget {
  final Message message;
  final bool isChannel;
  final void Function(String userId)? onTapUser;
  final void Function(String messageId)? onTapPinnedMessage;
  final void Function(String photoUrl)? onTapPhoto;

  const TelegramServiceMessageWidget({
    super.key,
    required this.message,
    this.isChannel = false,
    this.onTapUser,
    this.onTapPinnedMessage,
    this.onTapPhoto,
  });

  String? _stringField(Map<String, dynamic>? payload, String key) {
    final val = payload?[key]?.toString().trim();
    return (val != null && val.isNotEmpty) ? val : null;
  }

  int _intField(Map<String, dynamic>? payload, String key) {
    final raw = payload?[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hoursч ${minutes.toString().padLeft(2, '0')}м';
    }
    if (minutes > 0) {
      return '$minutesм ${seconds.toString().padLeft(2, '0')}с';
    }
    return '$secondsс';
  }

  String _resolveActorName(Map<String, dynamic>? payload) {
    return _stringField(payload, 'actor_name') ??
        (message.senderName.trim().isNotEmpty
            ? message.senderName.trim()
            : 'Администратор');
  }

  String _resolveActorId(Map<String, dynamic>? payload) {
    return _stringField(payload, 'actor_id') ?? message.senderId.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final payload = message.mediaPayload;
    final action = _stringField(payload, 'system_action') ?? '';
    final effectiveIsChannel =
        isChannel || _stringField(payload, 'chat_type') == 'channel';

    // High-contrast semi-transparent surface (>= 4.5:1 on both light and dark wallpapers).
    final Color pillBg = isDark
        ? const Color(0xBA141923)
        : const Color(0xE0FFFFFF);
    final Color pillText = isDark
        ? Colors.white
        : const Color(0xFF0F172A);
    final Color pillBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.10);
    final Color linkColor = isDark
        ? const Color(0xFF7DD3FC)
        : const Color(0xFF0369A1);

    final TextStyle baseStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: pillText,
      height: 1.3,
      decoration: TextDecoration.none,
    );

    Widget buildPill({
      Widget? leadingIcon,
      required Widget child,
      VoidCallback? onTap,
    }) {
      final pill = Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pillBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leadingIcon != null) ...[
              leadingIcon,
              const SizedBox(width: 6),
            ],
            Flexible(child: child),
          ],
        ),
      );

      if (onTap == null) {
        return pill;
      }

      return Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                widthFactor: 1.0,
                child: pill,
              ),
            ),
          ),
        ),
      );
    }

    Widget? extraBelow;
    late final Widget pillWidget;

    switch (action) {
      case 'chat_created':
        final title = _stringField(payload, 'title');
        final text = effectiveIsChannel
            ? 'Канал создан'
            : (title != null ? 'Группа «$title» создана' : 'Группа создана');
        pillWidget = buildPill(
          child: Text(text, textAlign: TextAlign.center, style: baseStyle),
        );
        break;

      case 'photo_updated':
        final actor = _resolveActorName(payload);
        final label = effectiveIsChannel
            ? '$actor обновил(а) фото канала'
            : '$actor обновил(а) фото группы';
        final rawPhotoUrl = _stringField(payload, 'photo_url') ??
            _stringField(payload, 'url') ??
            message.fileUrl;
        pillWidget = buildPill(
          leadingIcon: iconoir.Camera(width: 14, height: 14, color: pillText),
          child: Text(label, textAlign: TextAlign.center, style: baseStyle),
        );
        if (rawPhotoUrl != null && rawPhotoUrl.isNotEmpty) {
          final resolved = AppConfig.resolveMediaUrl(rawPhotoUrl) ??
              getValidAvatarUrl(rawPhotoUrl) ??
              rawPhotoUrl;
          extraBelow = Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MouseRegion(
              cursor: onTapPhoto != null
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                onTap: onTapPhoto != null ? () => onTapPhoto!(resolved) : null,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.24)
                          : Colors.black.withValues(alpha: 0.14),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _buildPhotoPreview(context, resolved, pillBg, pillText),
                  ),
                ),
              ),
            ),
          );
        }
        break;

      case 'title_updated':
        final actor = _resolveActorName(payload);
        final newTitle = _stringField(payload, 'title');
        final text = newTitle != null
            ? '$actor изменил(а) название на «$newTitle»'
            : message.content;
        pillWidget = buildPill(
          child: Text(text, textAlign: TextAlign.center, style: baseStyle),
        );
        break;

      case 'message_pinned':
        final actor = _resolveActorName(payload);
        final pinnedMsgId = _stringField(payload, 'pinned_message_id') ??
            _stringField(payload, 'message_id') ??
            '';
        final preview = _stringField(payload, 'pinned_preview') ?? '';
        final text = preview.isNotEmpty
            ? '$actor закрепил(а) сообщение «$preview»'
            : '$actor закрепил(а) сообщение';
        pillWidget = buildPill(
          leadingIcon: iconoir.Pin(width: 14, height: 14, color: pillText),
          onTap: (onTapPinnedMessage != null && pinnedMsgId.isNotEmpty)
              ? () => onTapPinnedMessage!(pinnedMsgId)
              : null,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: baseStyle,
          ),
        );
        break;

      case 'member_joined':
      case 'member_added':
        final actorId = _resolveActorId(payload);
        final actorName = _resolveActorName(payload);
        final targetId = _stringField(payload, 'target_id') ??
            _stringField(payload, 'member_id') ??
            _stringField(payload, 'user_id') ??
            '';
        final targetName = _stringField(payload, 'target_name') ??
            _stringField(payload, 'member_name') ??
            _stringField(payload, 'display_name') ??
            '';

        final bool isSelfJoin = action == 'member_joined' ||
            targetName.isEmpty ||
            (targetId.isNotEmpty && targetId == actorId);

        pillWidget = buildPill(
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                _buildUserLinkSpan(
                  name: actorName,
                  userId: actorId,
                  linkColor: linkColor,
                  baseStyle: baseStyle,
                ),
                if (isSelfJoin)
                  TextSpan(
                    text: effectiveIsChannel
                        ? ' подписался(ась) на канал'
                        : ' вступил(а) в группу',
                  )
                else ...[
                  const TextSpan(text: ' пригласил(а) '),
                  _buildUserLinkSpan(
                    name: targetName,
                    userId: targetId,
                    linkColor: linkColor,
                    baseStyle: baseStyle,
                  ),
                ],
              ],
            ),
            textAlign: TextAlign.center,
          ),
        );
        break;

      case 'voice_chat_started':
        final actorName = _stringField(payload, 'actor_name');
        final text = actorName != null
            ? (effectiveIsChannel
                ? '$actorName начал(а) прямую трансляцию'
                : '$actorName начал(а) голосовой чат')
            : (effectiveIsChannel
                ? 'Прямая трансляция началась'
                : 'Голосовой чат начался');
        pillWidget = buildPill(
          leadingIcon:
              iconoir.SoundHigh(width: 14, height: 14, color: pillText),
          child: Text(text, textAlign: TextAlign.center, style: baseStyle),
        );
        break;

      case 'voice_chat_ended':
        final actorName = _stringField(payload, 'actor_name');
        final durationSec = _intField(payload, 'duration_seconds');
        final formattedDur = _formatDuration(durationSec);
        final base = actorName != null
            ? (effectiveIsChannel
                ? '$actorName завершил(а) трансляцию'
                : '$actorName завершил(а) голосовой чат')
            : (effectiveIsChannel
                ? 'Прямая трансляция завершена'
                : 'Голосовой чат завершён');
        final text = formattedDur.isNotEmpty ? '$base ($formattedDur)' : base;
        pillWidget = buildPill(
          leadingIcon:
              iconoir.SoundHigh(width: 14, height: 14, color: pillText),
          child: Text(text, textAlign: TextAlign.center, style: baseStyle),
        );
        break;

      default:
        pillWidget = buildPill(
          child: Text(
            message.content,
            textAlign: TextAlign.center,
            style: baseStyle,
          ),
        );
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pillWidget,
            if (extraBelow != null) extraBelow,
          ],
        ),
      ),
    );
  }

  InlineSpan _buildUserLinkSpan({
    required String name,
    required String userId,
    required Color linkColor,
    required TextStyle baseStyle,
  }) {
    final canTap = onTapUser != null && userId.isNotEmpty && userId != '0';
    if (!canTap) {
      return TextSpan(
        text: name,
        style: baseStyle.copyWith(fontWeight: FontWeight.w700),
      );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onTapUser!(userId),
          child: Text(
            name,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: linkColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(
    BuildContext context,
    String resolvedUrl,
    Color bg,
    Color fg,
  ) {
    Widget fallback = Container(
      width: 64,
      height: 64,
      color: bg,
      alignment: Alignment.center,
      child: iconoir.Camera(width: 24, height: 24, color: fg),
    );

    if (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    }

    if (resolvedUrl.startsWith('data:')) {
      final provider = avatarImageProvider(resolvedUrl);
      if (provider != null) {
        return Image(
          image: provider,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      }
    }

    if (!kIsWeb) {
      try {
        final localPath = resolvedUrl.startsWith('file://')
            ? Uri.parse(resolvedUrl).toFilePath()
            : resolvedUrl;
        final file = File(localPath);
        if (file.existsSync()) {
          return Image.file(
            file,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          );
        }
      } catch (_) {}
    }

    return fallback;
  }
}

/// Telegram-style centered frosted/matte welcome card shown in newly created
/// or empty channels and groups.
class TelegramChatCreatedIntroCard extends StatelessWidget {
  final bool isChannel;
  final String title;
  final String? description;

  const TelegramChatCreatedIntroCard({
    super.key,
    required this.isChannel,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final palette = themeExt?.palette;
    final glassEnabled = context.watch<LiquidGlassProvider?>()?.enabled ?? false;
    final accentColor = palette?.accent ?? theme.colorScheme.primary;

    final cardBg = isDark
        ? const Color(0xCC161B24)
        : Colors.white.withValues(alpha: 0.88);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.10);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF334155);

    final effectiveTitle = title.trim().isNotEmpty
        ? title.trim()
        : (isChannel ? 'Новый канал' : 'Новая группа');
    final trimmedDesc = description?.trim();

    final List<({Widget icon, String text})> bullets = isChannel
        ? [
            (
              icon: iconoir.Megaphone(width: 16, height: 16, color: accentColor),
              text: 'Публикации видны всем подписчикам канала',
            ),
            (
              icon: iconoir.Eye(width: 16, height: 16, color: accentColor),
              text: 'Счётчик просмотров для каждого поста',
            ),
            (
              icon: iconoir.ChatBubble(width: 16, height: 16, color: accentColor),
              text: 'Обсуждения, реакции и тихая отправка',
            ),
          ]
        : [
            (
              icon: iconoir.Group(width: 16, height: 16, color: accentColor),
              text: 'Общение участников и настройка прав доступа',
            ),
            (
              icon: iconoir.SoundHigh(width: 16, height: 16, color: accentColor),
              text: 'Голосовые чаты и совместные трансляции',
            ),
            (
              icon: iconoir.Pin(width: 16, height: 16, color: accentColor),
              text: 'Закреплённые сообщения, альбомы и опросы',
            ),
          ];

    Widget cardContent = Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: isDark ? 0.20 : 0.12),
            ),
            alignment: Alignment.center,
            child: isChannel
                ? iconoir.Megaphone(
                    width: 40,
                    height: 40,
                    color: accentColor,
                  )
                : iconoir.Group(
                    width: 40,
                    height: 40,
                    color: accentColor,
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            effectiveTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: titleColor,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isChannel ? 'Вы создали канал' : 'Вы создали группу',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
          if (trimmedDesc != null && trimmedDesc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              trimmedDesc,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: bodyColor,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 0.5,
            color: borderColor,
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < bullets.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: bullets[i].icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bullets[i].text,
                    style: TextStyle(
                      fontSize: 13,
                      color: bodyColor,
                      height: 1.32,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (glassEnabled) {
      cardContent = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(15),
          child: cardContent,
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: cardContent,
        ),
      ),
    );
  }
}
