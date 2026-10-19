import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/voice_playback_service.dart';
import '../../utils/entity_parser.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import 'avatar_gallery_viewer.dart';
import 'profile_section_pill.dart';

/// Модель участника группы/канала для вкладки «Участники».
class ProfileMemberItem {
  final String userId;
  final String name;
  final String surname;
  final String username;
  final String? avatarUrl;
  final String role; // 'owner', 'admin', 'member'
  final bool isOnline;
  final String? lastSeen;

  const ProfileMemberItem({
    required this.userId,
    required this.name,
    this.surname = '',
    this.username = '',
    this.avatarUrl,
    this.role = 'member',
    this.isOnline = false,
    this.lastSeen,
  });

  String get displayName {
    final full = '$name $surname'.trim();
    if (full.isNotEmpty) return full;
    if (username.isNotEmpty) return '@$username';
    return 'Пользователь';
  }

  factory ProfileMemberItem.fromJson(Map<String, dynamic> json) {
    return ProfileMemberItem(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      surname: (json['surname'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      avatarUrl: json['avatar_url']?.toString(),
      role: (json['role'] ?? 'member').toString(),
      isOnline: json['is_online'] == true,
      lastSeen: json['last_seen']?.toString(),
    );
  }
}

/// Контент одной страницы в `PageView` разделов профиля.
class ProfileSectionPageContent extends StatelessWidget {
  final ProfileSectionType sectionType;
  final bool glassEnabled;
  final bool isLite;
  final String chatId;
  final String chatType;
  final String chatTitle;
  final String? currentUserId;

  // Данные вкладок
  final List<ProfileMemberItem> members;
  final List<DbMessage> mediaMessages;
  final List<DbMessage> fileMessages;
  final List<DbMessage> linkMessages;
  final List<DbMessage> voiceMessages;

  // Права и коллбэки для участников
  final bool canAddMembers;
  final bool canManageMembers;
  final VoidCallback? onAddMemberTap;
  final ValueChanged<ProfileMemberItem>? onMemberTap;
  final ValueChanged<ProfileMemberItem>? onToggleAdminRole;
  final ValueChanged<ProfileMemberItem>? onRemoveMember;

  // Коллбэк перехода к сообщению в чате
  final ValueChanged<DbMessage>? onJumpToMessage;

  const ProfileSectionPageContent({
    Key? key,
    required this.sectionType,
    required this.glassEnabled,
    this.isLite = false,
    required this.chatId,
    this.chatType = 'private',
    this.chatTitle = '',
    this.currentUserId,
    this.members = const [],
    this.mediaMessages = const [],
    this.fileMessages = const [],
    this.linkMessages = const [],
    this.voiceMessages = const [],
    this.canAddMembers = false,
    this.canManageMembers = false,
    this.onAddMemberTap,
    this.onMemberTap,
    this.onToggleAdminRole,
    this.onRemoveMember,
    this.onJumpToMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    switch (sectionType) {
      case ProfileSectionType.members:
        return _buildMembersTab(context);
      case ProfileSectionType.wall:
        return _buildEmptyState(
          context,
          iconBuilder: (color, size) => iconoir.ViewGrid(color: color, width: size, height: size),
          title: _tr(context, 'profile_wall_empty_title', 'Публикаций пока нет'),
          subtitle: _tr(context, 'profile_wall_empty_subtitle', 'Записи на стене профиля появятся здесь'),
        );
      case ProfileSectionType.gifts:
        return _buildEmptyState(
          context,
          iconBuilder: (color, size) => iconoir.Gift(color: color, width: size, height: size),
          title: _tr(context, 'profile_gifts_empty_title', 'Подарков пока нет'),
          subtitle: _tr(context, 'profile_gifts_empty_subtitle', 'Полученные подарки будут отображаться в этом разделе'),
        );
      case ProfileSectionType.media:
        return _buildMediaTab(context);
      case ProfileSectionType.files:
        return _buildFilesTab(context);
      case ProfileSectionType.links:
        return _buildLinksTab(context);
      case ProfileSectionType.voice:
        return _buildVoiceTab(context);
    }
  }

  String _tr(BuildContext context, String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  // ============================================================
  // 1. Вкладка «Участники»
  // ============================================================

  Widget _buildMembersTab(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);

    if (members.isEmpty && !canAddMembers) {
      return _buildEmptyState(
        context,
        iconBuilder: (color, size) => iconoir.Group(color: color, width: size, height: size),
        title: _tr(context, 'group_no_members', 'Нет участников'),
        subtitle: _tr(context, 'group_no_members_sub', 'Список участников пуст'),
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canAddMembers && onAddMemberTap != null) ...[
          InkWell(
            onTap: () {
              HapticUtils.tap();
              onAddMemberTap!();
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: iconoir.UserPlus(
                      width: 20,
                      height: 20,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tr(context, 'group_add_members', 'Добавить участников'),
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (members.isNotEmpty)
            Divider(
              height: 1,
              indent: 70,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
        ],
        for (int i = 0; i < members.length; i++) ...[
          _buildMemberRow(context, members[i], isDark, accentColor),
          if (i < members.length - 1)
            Divider(
              height: 1,
              indent: 70,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
        ],
      ],
    );

    return content;
  }

  Widget _buildMemberRow(
    BuildContext context,
    ProfileMemberItem member,
    bool isDark,
    Color accentColor,
  ) {
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF6C6C70);

    final validAvatar = getValidAvatarUrl(member.avatarUrl);
    final canEditThisMember = canManageMembers &&
        member.userId != currentUserId &&
        member.role != 'owner';
    final memberName = member.displayName == 'Пользователь'
        ? _tr(context, 'profile_default_user', 'Пользователь')
        : member.displayName;

    String? roleBadge;
    if (member.role == 'owner') {
      roleBadge = _tr(context, 'role_owner', 'владелец');
    } else if (member.role == 'admin') {
      roleBadge = _tr(context, 'role_admin', 'админ');
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.tap();
        onMemberTap?.call(member);
      },
      onSecondaryTapUp: (details) {
        HapticUtils.selection();
        _showMemberContextMenuAtPosition(
          context,
          details.globalPosition,
          member,
          canEditThisMember: canEditThisMember,
        );
      },
      onLongPress: canEditThisMember
          ? () {
              HapticUtils.selection();
              _showMemberActionsSheet(context, member);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accentColor.withValues(alpha: 0.2),
                  backgroundImage: (validAvatar != null && validAvatar.isNotEmpty)
                      ? CachedNetworkImageProvider(validAvatar)
                      : null,
                  child: (validAvatar == null || validAvatar.isEmpty)
                      ? Text(
                          memberName.isNotEmpty
                              ? memberName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        )
                      : null,
                ),
                if (member.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.isOnline
                        ? _tr(context, 'profile_online', 'в сети')
                        : _tr(context, 'status_offline', 'был(а) недавно'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: member.isOnline ? accentColor : subColor,
                    ),
                  ),
                ],
              ),
            ),
            if (roleBadge != null) ...[
              const SizedBox(width: 8),
              Text(
                roleBadge,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: member.role == 'owner' ? accentColor : subColor,
                ),
              ),
            ],
            if (canEditThisMember) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  HapticUtils.tap();
                  _showMemberContextMenuAtPosition(
                    context,
                    details.globalPosition,
                    member,
                    canEditThisMember: canEditThisMember,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: iconoir.MoreVert(
                    width: 18,
                    height: 18,
                    color: subColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMemberActionsSheet(BuildContext context, ProfileMemberItem member) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = member.role == 'admin';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xB82C2C2E)
                    : const Color(0xCCFFFFFF),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: iconoir.User(
                        width: 22,
                        height: 22,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      title: Text(_tr(context, 'open_profile', 'Открыть профиль')),
                      onTap: () {
                        Navigator.pop(ctx);
                        onMemberTap?.call(member);
                      },
                    ),
                    if (onToggleAdminRole != null)
                      ListTile(
                        leading: iconoir.Shield(
                          width: 22,
                          height: 22,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        title: Text(
                          isAdmin
                              ? _tr(context, 'group_demote_admin', 'Снять права администратора')
                              : _tr(context, 'group_promote_admin', 'Назначить администратором'),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onToggleAdminRole!(member);
                        },
                      ),
                    if (onRemoveMember != null)
                      ListTile(
                        leading: const iconoir.UserXmark(
                          width: 22,
                          height: 22,
                          color: Colors.redAccent,
                        ),
                        title: Text(
                          _tr(context, 'group_remove_member', 'Удалить из чата'),
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onRemoveMember!(member);
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // 2. Вкладка «Медиа» (сетка 3xN)
  // ============================================================

  Widget _buildMediaTab(BuildContext context) {
    if (mediaMessages.isEmpty) {
      return _buildEmptyState(
        context,
        iconBuilder: (color, size) => iconoir.MediaImage(color: color, width: size, height: size),
        title: _tr(context, 'profile_media_empty_title', 'Медиафайлов пока нет'),
        subtitle: _tr(context, 'profile_media_empty_subtitle', 'Фотографии и видео из чата появятся здесь'),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageUrls = mediaMessages
        .where((m) => m.messageType == 'image' && m.fileUrl != null)
        .map((m) => AppConfig.resolveMediaUrl(m.fileUrl!) ?? m.fileUrl!)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: mediaMessages.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          final msg = mediaMessages[index];
          final rawUrl = msg.fileUrl ?? '';
          final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
          final isVideo = msg.messageType == 'video';

          return GestureDetector(
            onTap: () {
              HapticUtils.tap();
              if (!isVideo && imageUrls.isNotEmpty) {
                final imgIdx = imageUrls.indexOf(resolvedUrl);
                AvatarGalleryViewer.open(
                  context,
                  avatarUrls: imageUrls,
                  initialIndex: imgIdx >= 0 ? imgIdx : 0,
                  displayName: chatTitle,
                );
              } else {
                _showMessageItemSheet(context, msg, resolvedUrl: resolvedUrl);
              }
            },
            onSecondaryTapUp: (details) {
              HapticUtils.selection();
              _showMessageContextMenuAtPosition(
                context,
                details.globalPosition,
                msg,
                resolvedUrl: resolvedUrl,
              );
            },
            onLongPress: () {
              HapticUtils.selection();
              _showMessageItemSheet(context, msg, resolvedUrl: resolvedUrl);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  child: resolvedUrl.isNotEmpty && !isVideo
                      ? CachedNetworkImage(
                          imageUrl: resolvedUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          errorWidget: (_, __, ___) => Center(
                            child: iconoir.MediaImage(
                              width: 24,
                              height: 24,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        )
                      : Center(
                          child: iconoir.VideoCamera(
                            width: 28,
                            height: 28,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                ),
                if (isVideo)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const iconoir.Play(
                                width: 12,
                                height: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _extractDurationText(msg) ??
                                    _tr(context, 'chat_video', 'Видео'),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // 3. Вкладка «Файлы»
  // ============================================================

  Widget _buildFilesTab(BuildContext context) {
    if (fileMessages.isEmpty) {
      return _buildEmptyState(
        context,
        iconBuilder: (color, size) => iconoir.Page(color: color, width: size, height: size),
        title: _tr(context, 'profile_files_empty_title', 'Файлов пока нет'),
        subtitle: _tr(context, 'profile_files_empty_subtitle', 'Отправленные в чате документы появятся здесь'),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6C6C70);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < fileMessages.length; i++) ...[
          Builder(
            builder: (context) {
              final msg = fileMessages[i];
              final fileName = (msg.fileName != null && msg.fileName!.isNotEmpty)
                  ? msg.fileName!
                  : (msg.content.isNotEmpty
                      ? msg.content
                      : _tr(context, 'profile_document_default', 'Документ'));
              final dateStr = _formatDateShort(context, msg.createdAt);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _downloadAndOpenFile(context, msg, fileName),
                onSecondaryTapUp: (details) {
                  HapticUtils.selection();
                  _showMessageContextMenuAtPosition(
                    context,
                    details.globalPosition,
                    msg,
                    fileName: fileName,
                  );
                },
                onLongPress: () {
                  HapticUtils.selection();
                  _showMessageItemSheet(context, msg, fileName: fileName);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: iconoir.Page(
                          width: 22,
                          height: 22,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: subColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      iconoir.Download(
                        width: 20,
                        height: 20,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (i < fileMessages.length - 1)
            Divider(
              height: 1,
              indent: 72,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
        ],
      ],
    );

    return content;
  }

  Future<void> _downloadAndOpenFile(BuildContext context, DbMessage msg, String fileName) async {
    HapticUtils.tap();
    final rawUrl = msg.fileUrl ?? '';
    if (rawUrl.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    GlassToastService().show(
      context,
      _tr(context, 'profile_downloading_file', 'Загрузка {file}...')
          .replaceAll('{file}', fileName),
      iconWidget: iconoir.Download(
        width: 18,
        height: 18,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );

    try {
      if (kIsWeb) {
        final resolved = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
        final uri = Uri.tryParse(resolved);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      final fileService = FileService();
      final savedPath = await fileService.downloadToDownloads(rawUrl, fileName);
      if (!savedPath.startsWith('content://')) {
        await fileService.openFile(savedPath);
      }
    } catch (_) {
      final resolved = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
      final uri = Uri.tryParse(resolved);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ============================================================
  // 4. Вкладка «Ссылки»
  // ============================================================

  Widget _buildLinksTab(BuildContext context) {
    if (linkMessages.isEmpty) {
      return _buildEmptyState(
        context,
        iconBuilder: (color, size) => iconoir.Link(color: color, width: size, height: size),
        title: _tr(context, 'profile_links_empty_title', 'Ссылок пока нет'),
        subtitle: _tr(context, 'profile_links_empty_subtitle', 'Ссылки из сообщений чата будут собраны здесь'),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6C6C70);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < linkMessages.length; i++) ...[
          Builder(
            builder: (context) {
              final msg = linkMessages[i];
              final urls = EntityParser.extractUrls(msg.content);
              final primaryUrl = urls.isNotEmpty
                  ? urls.first
                  : EntityParser.normalizeUrl(msg.content);
              final host = Uri.tryParse(primaryUrl)?.host.replaceFirst('www.', '') ?? primaryUrl;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  HapticUtils.tap();
                  final uri = Uri.tryParse(primaryUrl);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                onSecondaryTapUp: (details) {
                  HapticUtils.selection();
                  _showMessageContextMenuAtPosition(
                    context,
                    details.globalPosition,
                    msg,
                    linkUrl: primaryUrl,
                  );
                },
                onLongPress: () {
                  HapticUtils.selection();
                  _showMessageItemSheet(context, msg, linkUrl: primaryUrl);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: iconoir.Link(
                          width: 22,
                          height: 22,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (msg.content.trim() != primaryUrl)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  msg.content.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subColor,
                                  ),
                                ),
                              ),
                            Text(
                              primaryUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (i < linkMessages.length - 1)
            Divider(
              height: 1,
              indent: 72,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
        ],
      ],
    );

    return content;
  }

  // ============================================================
  // 5. Вкладка «Голосовые» (+ кружочки)
  // ============================================================

  Widget _buildVoiceTab(BuildContext context) {
    if (voiceMessages.isEmpty) {
      return _buildEmptyState(
        context,
        iconBuilder: (color, size) => iconoir.Microphone(color: color, width: size, height: size),
        title: _tr(context, 'profile_voice_empty_title', 'Голосовых сообщений нет'),
        subtitle: _tr(context, 'profile_voice_empty_subtitle', 'Голосовые сообщения и видеокружочки появятся здесь'),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6C6C70);

    final content = AnimatedBuilder(
      animation: Listenable.merge([
        MediaPlaybackCoordinator(),
        VoicePlaybackService(),
      ]),
      builder: (context, _) {
        final activeId = MediaPlaybackCoordinator().activeTrack?.messageId;
        final isPlayingVoice = VoicePlaybackService().isPlaying;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < voiceMessages.length; i++) ...[
              Builder(
                builder: (context) {
                  final msg = voiceMessages[i];
                  final msgId = msg.serverId ?? msg.localId;
                  final isRound = msg.isRound || msg.messageType == 'round';
                  final isActive = activeId == msgId && isPlayingVoice;
                  final sender = (msg.senderName != null && msg.senderName!.isNotEmpty)
                      ? msg.senderName!
                      : (isRound
                          ? _tr(context, 'chat_video_note', 'Видеосообщение')
                          : _tr(context, 'chat_voice_message', 'Голосовое сообщение'));
                  final durationStr = _extractDurationText(msg) ??
                      (isRound
                          ? _tr(context, 'profile_round_video', 'Кружочек')
                          : _tr(context, 'storage_audio', 'Аудио'));
                  final dateStr = _formatDateShort(context, msg.createdAt);

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _playVoiceOrRound(msg),
                    onSecondaryTapUp: (details) {
                      HapticUtils.selection();
                      _showMessageContextMenuAtPosition(
                        context,
                        details.globalPosition,
                        msg,
                        resolvedUrl: msg.fileUrl,
                      );
                    },
                    onLongPress: () {
                      HapticUtils.selection();
                      _showMessageItemSheet(context, msg);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: isActive
                                ? const iconoir.Pause(
                                    width: 20,
                                    height: 20,
                                    color: Colors.white,
                                  )
                                : (isRound
                                    ? const iconoir.VideoCamera(
                                        width: 20,
                                        height: 20,
                                        color: Colors.white,
                                      )
                                    : const iconoir.Play(
                                        width: 20,
                                        height: 20,
                                        color: Colors.white,
                                      )),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sender,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$durationStr • $dateStr',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (i < voiceMessages.length - 1)
                Divider(
                  height: 1,
                  indent: 72,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
            ],
          ],
        );
      },
    );

    return content;
  }

  void _playVoiceOrRound(DbMessage msg) {
    HapticUtils.tap();
    final rawUrl = msg.fileUrl ?? '';
    if (rawUrl.isEmpty) return;

    final msgId = msg.serverId ?? msg.localId;
    final coordinator = MediaPlaybackCoordinator();
    if (coordinator.activeTrack?.messageId == msgId && VoicePlaybackService().isPlaying) {
      VoicePlaybackService().pauseVoice();
      return;
    }

    final isRound = msg.isRound || msg.messageType == 'round';
    coordinator.startPlayback(
      track: PlaybackTrack(
        messageId: msgId,
        chatId: msg.chatId,
        chatType: chatType,
        mediaType: isRound ? 'video_note' : 'voice',
        mediaUrl: rawUrl,
        senderName: msg.senderName,
        chatTitle: chatTitle,
      ),
    );
  }

  // ============================================================
  // Компактное контекстное меню у курсора (ПКМ) и BottomSheet
  // ============================================================

  void _showMemberContextMenuAtPosition(
    BuildContext context,
    Offset globalPosition,
    ProfileMemberItem member, {
    required bool canEditThisMember,
  }) {
    final isAdmin = member.role == 'admin';
    final actions = <_ProfileContextMenuAction>[
      _ProfileContextMenuAction(
        label: _tr(context, 'open_profile', 'Открыть профиль'),
        iconBuilder: (color, size) => iconoir.User(
          width: size,
          height: size,
          color: color,
        ),
        onTap: () => onMemberTap?.call(member),
      ),
      if (canEditThisMember && onToggleAdminRole != null)
        _ProfileContextMenuAction(
          label: isAdmin
              ? _tr(context, 'group_demote_admin', 'Снять права администратора')
              : _tr(context, 'group_promote_admin', 'Назначить администратором'),
          iconBuilder: (color, size) => iconoir.Shield(
            width: size,
            height: size,
            color: color,
          ),
          onTap: () => onToggleAdminRole!(member),
        ),
      if (canEditThisMember && onRemoveMember != null)
        _ProfileContextMenuAction(
          label: _tr(context, 'group_remove_member', 'Удалить из чата'),
          isDestructive: true,
          iconBuilder: (color, size) => iconoir.UserXmark(
            width: size,
            height: size,
            color: color,
          ),
          onTap: () => onRemoveMember!(member),
        ),
    ];

    _showCompactContextMenu(context, globalPosition, actions);
  }

  void _showMessageContextMenuAtPosition(
    BuildContext context,
    Offset globalPosition,
    DbMessage msg, {
    String? resolvedUrl,
    String? fileName,
    String? linkUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actions = <_ProfileContextMenuAction>[
      if (onJumpToMessage != null)
        _ProfileContextMenuAction(
          label: _tr(context, 'jump_to_message', 'Перейти к сообщению в чате'),
          iconBuilder: (color, size) => iconoir.ChatBubble(
            width: size,
            height: size,
            color: color,
          ),
          onTap: () => onJumpToMessage!(msg),
        ),
      if (linkUrl != null)
        _ProfileContextMenuAction(
          label: _tr(context, 'copy_link', 'Скопировать ссылку'),
          iconBuilder: (color, size) => iconoir.Copy(
            width: size,
            height: size,
            color: color,
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: linkUrl));
            GlassToastService().show(
              context,
              _tr(context, 'copied_to_clipboard', 'Скопировано в буфер обмена'),
              iconWidget: iconoir.Copy(
                width: 18,
                height: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
            );
          },
        ),
      if (fileName != null || (resolvedUrl != null && resolvedUrl.isNotEmpty))
        _ProfileContextMenuAction(
          label: _tr(context, 'download_file', 'Скачать / Открыть'),
          iconBuilder: (color, size) => iconoir.Download(
            width: size,
            height: size,
            color: color,
          ),
          onTap: () {
            _downloadAndOpenFile(
              context,
              msg,
              fileName ?? 'media_${msg.localId}',
            );
          },
        ),
    ];

    if (actions.isEmpty) return;
    _showCompactContextMenu(context, globalPosition, actions);
  }

  void _showCompactContextMenu(
    BuildContext context,
    Offset globalPosition,
    List<_ProfileContextMenuAction> actions,
  ) {
    if (actions.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double menuWidth = 248.0;
    const double itemHeight = 42.0;
    final double menuHeight = actions.length * itemHeight + 12.0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogCtx, animation, secondaryAnimation) {
        final screenSize = MediaQuery.of(dialogCtx).size;
        final double left = globalPosition.dx.clamp(
          12.0,
          math.max(12.0, screenSize.width - menuWidth - 12.0),
        );
        final double top = globalPosition.dy.clamp(
          12.0,
          math.max(12.0, screenSize.height - menuHeight - 12.0),
        );
        final bool alignRight =
            globalPosition.dx + menuWidth + 12.0 > screenSize.width;
        final bool alignBottom =
            globalPosition.dy + menuHeight + 12.0 > screenSize.height;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogCtx).pop(),
                onSecondaryTap: () => Navigator.of(dialogCtx).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: ScaleTransition(
                alignment: Alignment(
                  alignRight ? 1.0 : -1.0,
                  alignBottom ? 1.0 : -1.0,
                ),
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.34 : 0.14,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xCC2C2C2E)
                                  : const Color(0xE6FFFFFF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.14)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final action in actions)
                                  _CompactContextMenuRow(
                                    action: action,
                                    isDark: isDark,
                                    onSelect: () {
                                      Navigator.of(dialogCtx).pop();
                                      action.onTap();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMessageItemSheet(
    BuildContext context,
    DbMessage msg, {
    String? resolvedUrl,
    String? fileName,
    String? linkUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xB82C2C2E)
                    : const Color(0xCCFFFFFF),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (onJumpToMessage != null)
                      ListTile(
                        leading: iconoir.ChatBubble(
                          width: 22,
                          height: 22,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        title: Text(_tr(context, 'jump_to_message', 'Перейти к сообщению в чате')),
                        onTap: () {
                          Navigator.pop(ctx);
                          onJumpToMessage!(msg);
                        },
                      ),
                    if (linkUrl != null)
                      ListTile(
                        leading: iconoir.Copy(
                          width: 22,
                          height: 22,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        title: Text(_tr(context, 'copy_link', 'Скопировать ссылку')),
                        onTap: () {
                          Navigator.pop(ctx);
                          Clipboard.setData(ClipboardData(text: linkUrl));
                          GlassToastService().show(
                            context,
                            _tr(context, 'copied_to_clipboard', 'Скопировано в буфер обмена'),
                            iconWidget: iconoir.Copy(
                              width: 18,
                              height: 18,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          );
                        },
                      ),
                    if (fileName != null || resolvedUrl != null)
                      ListTile(
                        leading: iconoir.Download(
                          width: 22,
                          height: 22,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        title: Text(_tr(context, 'download_file', 'Скачать / Открыть')),
                        onTap: () {
                          Navigator.pop(ctx);
                          _downloadAndOpenFile(
                            context,
                            msg,
                            fileName ?? 'media_${msg.localId}',
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // Empty State разделов (без карточных обёрток)
  // ============================================================

  Widget _buildEmptyState(
    BuildContext context, {
    required Widget Function(Color color, double size) iconBuilder,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF6C6C70);
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: iconBuilder(accentColor, 26),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: subColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String? _extractDurationText(DbMessage msg) {
    if (msg.mediaPayload == null || msg.mediaPayload!.isEmpty) return null;
    try {
      final map = jsonDecode(msg.mediaPayload!);
      if (map is Map) {
        final durSec = int.tryParse((map['duration'] ?? '').toString());
        if (durSec != null && durSec >= 0) {
          final mins = durSec ~/ 60;
          final secs = (durSec % 60).toString().padLeft(2, '0');
          return '$mins:$secs';
        }
      }
    } catch (_) {}
    return null;
  }

  String _formatDateShort(BuildContext context, String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return _tr(context, 'profile_date_at_time', '{date} в {time}')
        .replaceAll('{date}', '$d.$m.$y')
        .replaceAll('{time}', '$hh:$mm');
  }
}

class _ProfileContextMenuAction {
  final String label;
  final bool isDestructive;
  final Widget Function(Color color, double size) iconBuilder;
  final VoidCallback onTap;

  const _ProfileContextMenuAction({
    required this.label,
    required this.iconBuilder,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _CompactContextMenuRow extends StatefulWidget {
  final _ProfileContextMenuAction action;
  final bool isDark;
  final VoidCallback onSelect;

  const _CompactContextMenuRow({
    required this.action,
    required this.isDark,
    required this.onSelect,
  });

  @override
  State<_CompactContextMenuRow> createState() => _CompactContextMenuRowState();
}

class _CompactContextMenuRowState extends State<_CompactContextMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final defaultColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF1C1C1E);
    final itemColor =
        widget.action.isDestructive ? Colors.redAccent : defaultColor;
    final hoverBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.tap();
          widget.onSelect();
        },
        child: Container(
          height: 42.0,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              widget.action.iconBuilder(itemColor, 19.0),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: itemColor,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
