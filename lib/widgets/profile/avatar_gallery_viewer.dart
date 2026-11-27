import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_media_item.dart';
import '../media_viewer/theav_media_viewer.dart';
import '../media_viewer/theav_media_viewer_route.dart';

/// Fullscreen Telegram-style avatar gallery viewer powered by [TheavMediaViewer].
///
/// Retains backwards-compatible API for callers and widget tests while
/// eliminating frame drops via dynamic route `opaque` culling, zero shaders/blur,
/// zero host rebuilds during swiping (`onBeforeCloseSyncIndex`), and 2D drag-to-dismiss.
class AvatarGalleryViewer extends StatelessWidget {
  final List<String> avatarUrls;
  final int initialIndex;
  final String? displayName;
  final VoidCallback? onChoosePhoto;
  final Function(int index)? onDelete;
  final Function(int index)? onPageChanged;
  final ValueChanged<int>? onBeforeCloseSyncIndex;
  final bool firstIsCustomAvatar;
  final String? customAvatarBadgeText;
  final String? customDeleteLabel;
  final bool Function(int index)? canDeleteAt;
  final String? heroTagPrefix;
  final bool hasProtectedContent;

  const AvatarGalleryViewer({
    super.key,
    required this.avatarUrls,
    this.initialIndex = 0,
    this.displayName,
    this.heroTagPrefix = 'avatar_hero',
    this.onChoosePhoto,
    this.onDelete,
    this.onPageChanged,
    this.onBeforeCloseSyncIndex,
    this.firstIsCustomAvatar = false,
    this.customAvatarBadgeText,
    this.customDeleteLabel,
    this.canDeleteAt,
    this.hasProtectedContent = false,
  });

  /// Opens [AvatarGalleryViewer] over [TheavMediaViewerRoute].
  static Future<void> open(
    BuildContext context, {
    required List<String> avatarUrls,
    int initialIndex = 0,
    String? displayName,
    String? heroTagPrefix = 'avatar_hero',
    VoidCallback? onChoosePhoto,
    Function(int index)? onDelete,
    Function(int index)? onPageChanged,
    ValueChanged<int>? onBeforeCloseSyncIndex,
    bool firstIsCustomAvatar = false,
    String? customAvatarBadgeText,
    String? customDeleteLabel,
    bool Function(int index)? canDeleteAt,
    bool hasProtectedContent = false,
  }) {
    if (avatarUrls.isEmpty) return Future<void>.value();

    return Navigator.of(context, rootNavigator: true).push<void>(
      TheavMediaViewerRoute<void>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Navigator.of(context, rootNavigator: true).context,
        ),
        builder: (_) => AvatarGalleryViewer(
          avatarUrls: avatarUrls,
          initialIndex: initialIndex,
          displayName: displayName,
          heroTagPrefix: heroTagPrefix,
          onChoosePhoto: onChoosePhoto,
          onDelete: onDelete,
          onPageChanged: onPageChanged,
          onBeforeCloseSyncIndex: onBeforeCloseSyncIndex,
          firstIsCustomAvatar: firstIsCustomAvatar,
          customAvatarBadgeText: customAvatarBadgeText,
          customDeleteLabel: customDeleteLabel,
          canDeleteAt: canDeleteAt,
          hasProtectedContent: hasProtectedContent,
        ),
      ),
    );
  }

  String _tr(BuildContext context, String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final List<TheavMediaItem> items = List<TheavMediaItem>.generate(
      avatarUrls.length,
      (idx) => TheavMediaItem.fromAvatarUrl(
        avatarUrls[idx],
        index: idx,
        heroTagPrefix: heroTagPrefix,
        displayName: displayName,
        isCustomAvatar: firstIsCustomAvatar && idx == 0,
        customBadgeLabel: customAvatarBadgeText,
        hasProtectedContent: hasProtectedContent,
      ),
      growable: false,
    );

    final TheavMediaAction? choosePhotoAction = onChoosePhoto != null
        ? TheavMediaAction(
            id: 'choose_photo',
            label: _tr(
              context,
              'profile_choose_new_photo',
              'Выбрать новое фото',
            ),
            icon: Icons.add_a_photo_outlined,
            onSelected: (viewerCtx, _, __) {
              Navigator.of(viewerCtx).pop();
              onChoosePhoto?.call();
            },
          )
        : null;

    return TheavMediaViewer(
      items: items,
      initialIndex: initialIndex,
      config: TheavMediaViewerConfig(
        titleOverride:
            items.length <= 1 ? (displayName ?? 'Аватар') : null,
        onPageChanged: onPageChanged != null
            ? (idx) => onPageChanged!(idx)
            : null,
        onBeforeCloseSyncIndex: onBeforeCloseSyncIndex,
        primaryTopAction: choosePhotoAction,
        extraActionsBuilder: (item, idx) {
          final List<TheavMediaAction> actions = <TheavMediaAction>[];
          final bool canDeleteThis = onDelete != null &&
              (canDeleteAt == null || canDeleteAt!(idx));
          if (canDeleteThis) {
            final deleteLabel =
                (firstIsCustomAvatar && idx == 0 && customDeleteLabel != null)
                    ? customDeleteLabel!
                    : _tr(context, 'profile_delete_photo', 'Удалить фото');
            actions.add(
              TheavMediaAction(
                id: 'delete_avatar',
                label: deleteLabel,
                icon: Icons.delete_outline_rounded,
                isDestructive: true,
                onSelected: (viewerCtx, _, deleteIdx) {
                  Navigator.of(viewerCtx).pop();
                  onDelete?.call(deleteIdx);
                },
              ),
            );
          }
          return actions;
        },
      ),
    );
  }
}
