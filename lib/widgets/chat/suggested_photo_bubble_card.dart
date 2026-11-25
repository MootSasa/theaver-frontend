import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../models/theav_media_item.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/avatar_sync_service.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/profile_instant_cache.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../avatar_editor/theav_avatar_editor_screen.dart';
import '../design_system/theav_design_system.dart';
import '../media_viewer/theav_media_viewer.dart';

/// Telegram-style centered service card rendered inside private chats when a
/// peer suggests a profile photo (`system_action == 'suggest_profile_photo'`).
class SuggestedPhotoBubbleCard extends StatelessWidget {
  final Message message;
  final String currentUserId;
  final VoidCallback? onPhotoApplied;

  const SuggestedPhotoBubbleCard({
    super.key,
    required this.message,
    required this.currentUserId,
    this.onPhotoApplied,
  });

  static String? _nonEmpty(dynamic raw) {
    if (raw == null) return null;
    final trimmed = raw.toString().trim();
    return trimmed.isNotEmpty && trimmed != 'null' ? trimmed : null;
  }

  String _resolveRawPhotoUrl(Map<String, dynamic>? payload) {
    return _nonEmpty(payload?['photo_url']) ??
        _nonEmpty(payload?['photoUrl']) ??
        _nonEmpty(payload?['avatar_url']) ??
        _nonEmpty(message.fileUrl) ??
        '';
  }

  String _resolveResolvedPhotoUrl(String rawPhotoUrl) {
    if (rawPhotoUrl.isEmpty) return '';
    return getValidAvatarUrl(rawPhotoUrl) ??
        AppConfig.resolveMediaUrl(rawPhotoUrl) ??
        rawPhotoUrl;
  }

  String _heroTagFor(String resolvedPhotoUrl) {
    final msgId = message.id.isNotEmpty ? message.id : (message.localId ?? '');
    return 'suggested_photo_${msgId}_$resolvedPhotoUrl';
  }

  Future<void> _openViewer(
    BuildContext context, {
    required String apiPhotoUrl,
    required String resolvedPhotoUrl,
    required bool isRecipient,
  }) async {
    if (resolvedPhotoUrl.isEmpty) return;
    HapticUtils.tap();
    final appliedText = context.trOr(
      'contact_suggest_applied',
      'Фото профиля обновлено',
    );
    final item = TheavMediaItem(
      id: 'suggested_${message.id.isNotEmpty ? message.id : resolvedPhotoUrl}',
      kind: TheavMediaKind.avatar,
      url: resolvedPhotoUrl,
      heroTag: _heroTagFor(resolvedPhotoUrl),
      senderId: message.senderId,
      senderName: context.trOr(
        'contact_suggest_title',
        'Предложенное фото',
      ),
    );
    final applied = await TheavMediaViewer.open<bool>(
      context,
      items: <TheavMediaItem>[item],
      initialIndex: 0,
      config: TheavMediaViewerConfig(
        titleOverride: context.trOr(
          'contact_suggest_title',
          'Предложенное фото',
        ),
        bottomAccessoryBuilder: isRecipient
            ? (viewerCtx, _, __) => _SuggestedPhotoActionsBar(
                  apiPhotoUrl: apiPhotoUrl,
                  resolvedPhotoUrl: resolvedPhotoUrl,
                  onPhotoApplied: onPhotoApplied,
                  viewerContext: viewerCtx,
                )
            : null,
      ),
    );
    if (applied == true && context.mounted) {
      GlassToastService().show(context, appliedText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final payload = message.mediaPayload;

    final rawPhotoUrl = _resolveRawPhotoUrl(payload);
    final resolvedPhotoUrl = _resolveResolvedPhotoUrl(rawPhotoUrl);
    final suggesterId = _nonEmpty(payload?['suggester_id']) ??
        _nonEmpty(payload?['suggesterId']) ??
        message.senderId.trim();
    final rawSuggesterName = _nonEmpty(payload?['suggester_name']) ??
        _nonEmpty(payload?['suggesterName']) ??
        message.senderName.trim();
    final targetUserId = _nonEmpty(payload?['target_user_id']) ??
        _nonEmpty(payload?['targetUserId']) ??
        '';

    final bool isOutgoing =
        (suggesterId.isNotEmpty &&
            currentUserId.isNotEmpty &&
            suggesterId == currentUserId) ||
        message.isOwn ||
        (suggesterId.isEmpty &&
            currentUserId.isNotEmpty &&
            message.senderId.trim() == currentUserId);
    final bool isRecipient = !isOutgoing &&
        (targetUserId.isEmpty ||
            currentUserId.isEmpty ||
            targetUserId == currentUserId);

    final ImageProvider? thumbProvider = avatarImageProvider(
      resolvedPhotoUrl,
      maxDecodeDimension: 320,
    );

    final Color cardBg = style.isDark
        ? style.cardSurface.withValues(alpha: 0.88)
        : style.cardSurface.withValues(alpha: 0.94);
    final Color ctaBg = palette.primary.withValues(
      alpha: style.isDark ? 0.22 : 0.12,
    );
    final Color ringColor = palette.primary.withValues(
      alpha: style.isDark ? 0.34 : 0.24,
    );

    void handleOpen() => _openViewer(
          context,
          apiPhotoUrl: rawPhotoUrl.isNotEmpty ? rawPhotoUrl : resolvedPhotoUrl,
          resolvedPhotoUrl: resolvedPhotoUrl,
          isRecipient: isRecipient,
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: style.hudBorder, width: 0.75),
              boxShadow: style.floatingShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: resolvedPhotoUrl.isNotEmpty ? handleOpen : null,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 1.5),
                    ),
                    child: ClipOval(
                      child: SizedBox(
                        width: 116,
                        height: 116,
                        child: resolvedPhotoUrl.isNotEmpty && thumbProvider != null
                            ? Hero(
                                tag: _heroTagFor(resolvedPhotoUrl),
                                child: Image(
                                  image: thumbProvider,
                                  width: 116,
                                  height: 116,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) =>
                                      _AvatarPlaceholder(
                                    backgroundColor: style.trackFill,
                                    iconColor: palette.subtext,
                                  ),
                                ),
                              )
                            : _AvatarPlaceholder(
                                backgroundColor: style.trackFill,
                                iconColor: palette.subtext,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: ContactsService.revisionNotifier,
                  builder: (context, _, __) {
                    final String description;
                    if (isOutgoing) {
                      description = context.trOr(
                        'contact_suggest_card_you',
                        'Вы предложили фото профиля',
                      );
                    } else {
                      final fallbackName = rawSuggesterName.isNotEmpty
                          ? rawSuggesterName
                          : 'Пользователь';
                      final resolvedName = suggesterId.isNotEmpty
                          ? ContactsService.resolveName(
                              suggesterId,
                              fallbackName,
                            )
                          : fallbackName;
                      description = context.trOr(
                        'contact_suggest_card_other',
                        '{name} предлагает фото для вашего профиля',
                        {'name': resolvedName},
                      );
                    }
                    return Text(
                      description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: palette.onSurface,
                        height: 1.35,
                        decoration: TextDecoration.none,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: resolvedPhotoUrl.isNotEmpty ? handleOpen : null,
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: ctaBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconoir.Eye(
                              width: 16,
                              height: 16,
                              color: palette.primary,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                context.trOr(
                                  'contact_suggest_view_photo',
                                  'Посмотреть фото',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.primary,
                                  decoration: TextDecoration.none,
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final Color backgroundColor;
  final Color iconColor;

  const _AvatarPlaceholder({
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      color: backgroundColor,
      alignment: Alignment.center,
      child: iconoir.Camera(width: 34, height: 34, color: iconColor),
    );
  }
}

class _SuggestedPhotoActionsBar extends StatefulWidget {
  final String apiPhotoUrl;
  final String resolvedPhotoUrl;
  final VoidCallback? onPhotoApplied;
  final BuildContext viewerContext;

  const _SuggestedPhotoActionsBar({
    required this.apiPhotoUrl,
    required this.resolvedPhotoUrl,
    required this.viewerContext,
    this.onPhotoApplied,
  });

  @override
  State<_SuggestedPhotoActionsBar> createState() =>
      _SuggestedPhotoActionsBarState();
}

class _SuggestedPhotoActionsBarState extends State<_SuggestedPhotoActionsBar> {
  bool _isApplying = false;
  bool _isOpeningStudio = false;

  bool get _isBusy => _isApplying || _isOpeningStudio;

  Future<void> _applyDirectly() async {
    if (_isBusy) return;
    HapticUtils.tap();
    setState(() => _isApplying = true);
    try {
      final res =
          await ContactsService.applySuggestedAvatar(widget.apiPhotoUrl);
      if (!mounted) return;
      if (res['success'] == true) {
        final nextUrl =
            (res['avatar_url'] ?? widget.resolvedPhotoUrl).toString().trim();
        final uid = AccountManager().currentAccount?.userId ??
            await AuthService.getUserId();
        if (uid != null && uid.isNotEmpty && nextUrl.isNotEmpty) {
          ProfileInstantCache.instance.updateUserAvatar(uid, nextUrl);
        }
        widget.onPhotoApplied?.call();
        if (mounted && widget.viewerContext.mounted) {
          Navigator.of(widget.viewerContext).pop(true);
        }
        return;
      }
      GlassToastService().showError(
        context,
        (res['message'] ?? 'Не удалось обновить фото').toString(),
      );
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  Future<Uint8List?> _downloadPhotoBytes() async {
    final rawUrl = widget.resolvedPhotoUrl.trim();
    final url = (stripAvatarCropFragment(rawUrl) ?? rawUrl).trim();
    if (url.isEmpty) return null;

    if (url.startsWith('data:')) {
      final commaIdx = url.indexOf(',');
      if (commaIdx == -1) return null;
      return base64Decode(url.substring(commaIdx + 1));
    }

    if (!kIsWeb) {
      try {
        final localPath =
            url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        final f = File(localPath);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final headers = <String, String>{};
    final apiBase = AppConfig.baseUrl;
    if (url.startsWith(apiBase)) {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final resp = await http
        .get(uri, headers: headers.isNotEmpty ? headers : null)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      return resp.bodyBytes;
    }
    return null;
  }

  Future<void> _openInStudio() async {
    if (_isBusy) return;
    HapticUtils.tap();
    setState(() => _isOpeningStudio = true);
    try {
      final bytes = await _downloadPhotoBytes();
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        GlassToastService().showError(
          context,
          'Не удалось загрузить фото',
        );
        return;
      }

      setState(() => _isOpeningStudio = false);
      final AvatarPickResult? edited = await TheavAvatarEditorScreen.open(
        context: context,
        initialBytes: bytes,
        fileName: 'suggested_avatar.jpg',
        maskShape: AvatarShapeMask.circle,
        ctaMode: AvatarEditorCtaMode.setPhoto,
      );
      if (edited == null || !mounted) return;

      setState(() => _isOpeningStudio = true);
      final uid = AccountManager().currentAccount?.userId ??
          await AuthService.getUserId();
      if (uid == null || uid.isEmpty) {
        if (mounted) {
          GlassToastService().showError(context, 'Not authenticated');
        }
        return;
      }

      if (kIsWeb) {
        final uploadBytes = edited.bytes;
        if (uploadBytes == null || uploadBytes.isEmpty) {
          if (mounted) {
            GlassToastService().showError(context, 'Не удалось сохранить фото');
          }
          return;
        }
        final uploadRes = await AuthService.uploadAvatar(
          '',
          bytes: uploadBytes,
          fileName: edited.fileName,
          avatarCrop: edited.miniCrop?.toCompactParam(),
        );
        if (!mounted) return;
        if (uploadRes['success'] == true) {
          final remoteUrl = (uploadRes['avatar_url'] ?? '').toString().trim();
          if (remoteUrl.isNotEmpty) {
            ProfileInstantCache.instance.updateUserAvatar(uid, remoteUrl);
          }
          widget.onPhotoApplied?.call();
          if (widget.viewerContext.mounted) {
            Navigator.of(widget.viewerContext).pop(true);
          }
          return;
        }
        GlassToastService().showError(
          context,
          (uploadRes['message'] ?? 'Не удалось загрузить фото').toString(),
        );
        return;
      }

      String? localPath = edited.file?.path;
      if ((localPath == null || localPath.isEmpty) &&
          edited.bytes != null &&
          edited.bytes!.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final safeName = p.basename(edited.fileName).isNotEmpty
            ? p.basename(edited.fileName)
            : 'suggested_avatar.jpg';
        final outFile = File(
          p.join(
            dir.path,
            'suggested_${DateTime.now().millisecondsSinceEpoch}_$safeName',
          ),
        );
        await outFile.writeAsBytes(edited.bytes!, flush: true);
        localPath = outFile.path;
      }
      if (localPath == null || localPath.isEmpty) {
        if (mounted) {
          GlassToastService().showError(context, 'Не удалось сохранить фото');
        }
        return;
      }

      final permanentPath = await AvatarSyncService().setLocalAvatar(
        uid,
        localPath,
        avatarCrop: edited.miniCrop?.toCompactParam(),
      );
      ProfileInstantCache.instance.updateUserAvatar(uid, permanentPath);
      widget.onPhotoApplied?.call();
      if (mounted && widget.viewerContext.mounted) {
        Navigator.of(widget.viewerContext).pop(true);
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningStudio = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ViewerActionButton(
            label: context.trOr(
              'contact_suggest_apply_photo',
              'Установить как моё фото',
            ),
            isLoading: _isApplying,
            enabled: !_isBusy,
            backgroundColor: palette.primary,
            foregroundColor: palette.onPrimary,
            onTap: _applyDirectly,
          ),
          const SizedBox(height: 10),
          _ViewerActionButton(
            label: context.trOr(
              'avatar_editor_open_in_studio',
              'Открыть в студии',
            ),
            isLoading: _isOpeningStudio,
            enabled: !_isBusy,
            backgroundColor: const Color(0xB3101218),
            foregroundColor: Colors.white,
            borderColor: Colors.white.withValues(alpha: 0.16),
            onTap: _openInStudio,
          ),
        ],
      ),
    );
  }
}

class _ViewerActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool enabled;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback onTap;

  const _ViewerActionButton({
    required this.label,
    required this.isLoading,
    required this.enabled,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: enabled
                ? backgroundColor
                : backgroundColor.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 0.75)
                : null,
          ),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: foregroundColor,
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor,
                      decoration: TextDecoration.none,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
