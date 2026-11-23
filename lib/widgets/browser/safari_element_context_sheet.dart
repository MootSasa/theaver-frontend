import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/browser_context_menu_script.dart';
import '../../utils/safari_url_safety.dart';
import '../design_system/theav_design_system.dart';

/// Actions presented when the user long-presses a link or image inside the
/// in-app browser WebView.
enum SafariElementContextAction {
  openInNewTab,
  copyLink,
  shareLink,
  addBookmark,
  saveImage,
  openImageInNewTab,
  copyImageUrl,
  shareImage,
}

String _cleanContextStr(Object? value) =>
    value == null ? '' : value.toString().trim();

/// Presents a Safari iOS 26 style context action sheet for a long-pressed
/// link and/or image target.
Future<SafariElementContextAction?> showSafariElementContextSheet(
  BuildContext context, {
  required BrowserContextMenuTarget target,
  bool alreadyBookmarked = false,
}) {
  if (!target.hasLink && !target.hasImage) {
    return Future<SafariElementContextAction?>.value(null);
  }

  return showTheavModalSheet<SafariElementContextAction>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.68,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
    builder: (sheetCtx) => _SafariElementContextSheetBody(
      target: target,
      alreadyBookmarked: alreadyBookmarked,
    ),
  );
}

class _SafariElementContextSheetBody extends StatelessWidget {
  final BrowserContextMenuTarget target;
  final bool alreadyBookmarked;

  const _SafariElementContextSheetBody({
    required this.target,
    required this.alreadyBookmarked,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    final String linkUrl = _cleanContextStr(target.linkUrl);
    final String linkText = _cleanContextStr(target.linkText);
    final String imageUrl = _cleanContextStr(target.imageUrl);
    final String imageAlt = _cleanContextStr(target.imageAlt);

    final bool hasLink = target.hasLink;
    final bool hasImage = target.hasImage;
    final bool isDataImage =
        hasImage && imageUrl.toLowerCase().startsWith('data:');

    final String previewUrl = (hasLink && linkUrl.isNotEmpty)
        ? linkUrl
        : imageUrl;
    final SafariHostSafetyInfo safety = SafariUrlSafetyAnalyzer.analyzeUrl(
      previewUrl,
    );
    final bool isWarning = safety.isSuspiciousHomograph ||
        safety.securityLevel == SafariConnectionSecurityLevel.insecureHttp;

    final String previewTitle;
    if (hasLink && linkText.isNotEmpty) {
      previewTitle = linkText;
    } else if (hasImage && imageAlt.isNotEmpty) {
      previewTitle = imageAlt;
    } else if (safety.displayHost.isNotEmpty) {
      previewTitle = safety.displayHost;
    } else if (isDataImage) {
      previewTitle = context.trOr('browser_context_image_label', 'Изображение');
    } else {
      previewTitle = previewUrl;
    }

    final String hostLabel = safety.isSuspiciousHomograph &&
            safety.asciiHost.isNotEmpty &&
            safety.asciiHost != safety.unicodeHost
        ? '${safety.displayHost} (${safety.asciiHost})'
        : safety.displayHost;

    final String truncatedUrl = previewUrl.length > 240
        ? '${previewUrl.substring(0, 240)}…'
        : previewUrl;

    final Uri? imageUri = imageUrl.isNotEmpty ? Uri.tryParse(imageUrl) : null;
    final bool isHttpImage = imageUri != null &&
        (imageUri.scheme.toLowerCase() == 'http' ||
            imageUri.scheme.toLowerCase() == 'https');

    final List<Widget> linkActions = <Widget>[
      if (hasLink) ...[
        TheavListRow(
          key: const ValueKey('safari_context_open_in_new_tab'),
          leading: const Icon(Icons.open_in_new_rounded),
          title: context.trOr(
            'browser_context_open_new_tab',
            'Открыть в новой вкладке',
          ),
          onTap: () => Navigator.of(context).pop(
            SafariElementContextAction.openInNewTab,
          ),
        ),
        if (!alreadyBookmarked)
          TheavListRow(
            key: const ValueKey('safari_context_add_bookmark'),
            leading: const Icon(Icons.bookmark_add_outlined),
            title: context.trOr(
              'browser_context_add_bookmark',
              'Добавить в закладки',
            ),
            onTap: () => Navigator.of(context).pop(
              SafariElementContextAction.addBookmark,
            ),
          ),
        TheavListRow(
          key: const ValueKey('safari_context_copy_link'),
          leading: const Icon(Icons.copy_rounded),
          title: context.trOr(
            'browser_context_copy_link',
            'Копировать ссылку',
          ),
          onTap: () => Navigator.of(context).pop(
            SafariElementContextAction.copyLink,
          ),
        ),
        TheavListRow(
          key: const ValueKey('safari_context_share_link'),
          leading: const Icon(Icons.ios_share_rounded),
          title: context.trOr(
            'browser_context_share_link',
            'Поделиться ссылкой',
          ),
          onTap: () => Navigator.of(context).pop(
            SafariElementContextAction.shareLink,
          ),
        ),
      ],
    ];

    final List<Widget> imageActions = <Widget>[
      if (hasImage) ...[
        TheavListRow(
          key: const ValueKey('safari_context_save_image'),
          leading: const Icon(Icons.download_rounded),
          title: context.trOr(
            'browser_context_save_image',
            'Сохранить изображение',
          ),
          onTap: () => Navigator.of(context).pop(
            SafariElementContextAction.saveImage,
          ),
        ),
        if (!hasLink)
          TheavListRow(
            key: const ValueKey('safari_context_open_image_in_new_tab'),
            leading: const Icon(Icons.open_in_new_rounded),
            title: context.trOr(
              'browser_context_open_image_new_tab',
              'Открыть изображение в новой вкладке',
            ),
            onTap: () => Navigator.of(context).pop(
              SafariElementContextAction.openImageInNewTab,
            ),
          ),
        if (!isDataImage)
          TheavListRow(
            key: const ValueKey('safari_context_copy_image_url'),
            leading: const Icon(Icons.link_rounded),
            title: context.trOr(
              'browser_context_copy_image_url',
              'Копировать ссылку на изображение',
            ),
            onTap: () => Navigator.of(context).pop(
              SafariElementContextAction.copyImageUrl,
            ),
          ),
        if (!hasLink)
          TheavListRow(
            key: const ValueKey('safari_context_share_image'),
            leading: const Icon(Icons.ios_share_rounded),
            title: context.trOr(
              'browser_context_share_image',
              'Поделиться изображением',
            ),
            onTap: () => Navigator.of(context).pop(
              SafariElementContextAction.shareImage,
            ),
          ),
      ],
    ];

    return SingleChildScrollView(
      key: const ValueKey('safari_element_context_sheet'),
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            showBorder: isWarning,
            showShadow: false,
            backgroundColor: isWarning
                ? palette.error.withValues(alpha: style.isDark ? 0.14 : 0.08)
                : null,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasImage) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: isHttpImage
                              ? Image.network(
                                  imageUrl,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _ContextImageFallback(
                                    isWarning: isWarning,
                                  ),
                                )
                              : _ContextImageFallback(isWarning: isWarning),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (previewTitle.isNotEmpty)
                            Text(
                              previewTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                color: palette.onSurface,
                              ),
                            ),
                          if (hostLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  isWarning
                                      ? Icons.warning_amber_rounded
                                      : (safety.securityLevel ==
                                              SafariConnectionSecurityLevel
                                                  .secureHttps
                                          ? Icons.lock_rounded
                                          : Icons.language_rounded),
                                  size: 13,
                                  color: isWarning
                                      ? palette.error
                                      : palette.primary,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    hostLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isWarning
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isWarning
                                          ? palette.error
                                          : palette.subtext,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (truncatedUrl.isNotEmpty &&
                              truncatedUrl != previewTitle) ...[
                            const SizedBox(height: 3),
                            Text(
                              truncatedUrl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: isWarning
                                    ? palette.error.withValues(alpha: 0.88)
                                    : palette.subtext,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (linkActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            TheavInsetGroup(
              margin: EdgeInsets.zero,
              dividerIndent: 52,
              showBorder: false,
              showShadow: false,
              children: linkActions,
            ),
          ],
          if (imageActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            TheavInsetGroup(
              margin: EdgeInsets.zero,
              dividerIndent: 52,
              showBorder: false,
              showShadow: false,
              children: imageActions,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextImageFallback extends StatelessWidget {
  final bool isWarning;

  const _ContextImageFallback({required this.isWarning});

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final Color tint = isWarning ? palette.error : palette.primary;
    return ColoredBox(
      color: tint.withValues(alpha: style.isDark ? 0.20 : 0.12),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 24,
          color: tint,
        ),
      ),
    );
  }
}
