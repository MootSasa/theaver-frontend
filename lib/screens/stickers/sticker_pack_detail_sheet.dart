import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../widgets/chat/sticker_item_widget.dart';

class StickerPackDetailSheet extends StatefulWidget {
  final String packIdOrSlug;
  final StickerPack? initialPack;
  final ValueChanged<StickerItem>? onSelectSticker;

  const StickerPackDetailSheet({
    super.key,
    required this.packIdOrSlug,
    this.initialPack,
    this.onSelectSticker,
  });

  static Future<void> show(
    BuildContext context, {
    required Object packIdOrSlug,
    StickerPack? initialPack,
    ValueChanged<StickerItem>? onSelectSticker,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StickerPackDetailSheet(
        packIdOrSlug: packIdOrSlug.toString(),
        initialPack: initialPack,
        onSelectSticker: onSelectSticker,
      ),
    );
  }

  @override
  State<StickerPackDetailSheet> createState() => _StickerPackDetailSheetState();
}

class _StickerPackDetailSheetState extends State<StickerPackDetailSheet> {
  StickerPack? _pack;
  bool _loading = true;
  bool _togglingInstall = false;

  @override
  void initState() {
    super.initState();
    _pack = widget.initialPack;
    if (_pack != null && _pack!.items.isNotEmpty) {
      _loading = false;
    }
    _fetchPack();
  }

  Future<void> _fetchPack() async {
    final loaded = await StickerService.instance.getPackByIdOrSlug(widget.packIdOrSlug);
    if (mounted) {
      setState(() {
        if (loaded != null) {
          _pack = loaded;
        }
        _loading = false;
      });
    }
  }

  Future<void> _toggleInstall() async {
    final pack = _pack;
    if (pack == null || _togglingInstall) return;
    setState(() => _togglingInstall = true);
    try {
      bool ok;
      if (pack.isInstalled) {
        ok = await StickerService.instance.uninstallPack(pack.id);
        if (ok && mounted) {
          setState(() => _pack = pack.copyWith(isInstalled: false));
        }
      } else {
        ok = await StickerService.instance.installPack(pack.id);
        if (ok && mounted) {
          setState(() => _pack = pack.copyWith(isInstalled: true));
        }
      }
    } finally {
      if (mounted) {
        setState(() => _togglingInstall = false);
      }
    }
  }

  void _copyLink() {
    final pack = _pack;
    if (pack == null) return;
    final link = 'https://theaver.app/addstickers/${pack.shortName}';
    Clipboard.setData(ClipboardData(text: link));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка на набор скопирована'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleItemTap(StickerItem item) {
    if (widget.onSelectSticker != null) {
      Navigator.of(context).pop();
      widget.onSelectSticker!(item);
      return;
    }
    final activeTarget = StickerService.instance.activeInputTarget;
    if (activeTarget != null) {
      Navigator.of(context).pop();
      if ( _pack?.isCustomEmoji == true) {
        activeTarget.onInsertCustomEmoji(item);
      } else {
        activeTarget.onSendSticker(item);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TheavTheme.of(context);
    final pack = _pack;
    final isEmojiPack = pack?.isCustomEmoji ?? false;
    final items = pack?.items ?? const <StickerItem>[];
    final count = items.isNotEmpty ? items.length : (pack?.stickerCount ?? 0);

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.secondaryBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: theme.dividerColor,
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (pack != null &&
                        (pack.coverUrl.isNotEmpty || items.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: StickerMediaView(
                          fileUrl: pack.coverUrl.isNotEmpty
                              ? pack.coverUrl
                              : items.first.fileUrl,
                          format: items.isNotEmpty ? items.first.format : 'webp',
                          width: 44,
                          height: 44,
                          animate: true,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pack?.title ?? 'Загрузка набора...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEmojiPack
                                ? '$count эмодзи • /${pack?.shortName ?? ''}'
                                : '$count стикеров • /${pack?.shortName ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: pack != null ? _copyLink : null,
                      tooltip: 'Скопировать ссылку',
                      icon: iconoir.Link(
                        width: 20,
                        height: 20,
                        color: theme.textSecondary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: iconoir.Xmark(
                        width: 20,
                        height: 20,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 0.5, thickness: 0.5, color: theme.dividerColor),
              Expanded(
                child: _loading && items.isEmpty
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.accent,
                          ),
                        ),
                      )
                    : items.isEmpty
                        ? Center(
                            child: Text(
                              'Набор пуст или не найден',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.textSecondary,
                              ),
                            ),
                          )
                        : GridView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(14),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isEmojiPack ? 8 : 5,
                              crossAxisSpacing: isEmojiPack ? 6 : 8,
                              mainAxisSpacing: isEmojiPack ? 6 : 8,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return GestureDetector(
                                onTap: () => _handleItemTap(item),
                                onLongPress: () {
                                  StickerPeekPopOverlay.show(
                                    context: context,
                                    sticker: item,
                                    onSend: () => _handleItemTap(item),
                                  );
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    StickerMediaView(
                                      fileUrl: item.fileUrl,
                                      format: item.format,
                                      width: isEmojiPack ? 36 : 64,
                                      height: isEmojiPack ? 36 : 64,
                                      animate: true,
                                    ),
                                    if (item.hasFullscreenEffect)
                                      Positioned(
                                        right: 2,
                                        bottom: 2,
                                        child: iconoir.Sparks(
                                          width: 11,
                                          height: 11,
                                          color: theme.accent,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              if (pack != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: GestureDetector(
                        onTap: _togglingInstall ? null : _toggleInstall,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: pack.isInstalled
                                ? theme.inputBg
                                : theme.accent,
                            borderRadius: BorderRadius.circular(14),
                            border: pack.isInstalled
                                ? Border.all(
                                    color: theme.dividerColor,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: _togglingInstall
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: pack.isInstalled
                                        ? theme.textPrimary
                                        : Colors.white,
                                  ),
                                )
                              : Text(
                                  pack.isInstalled
                                      ? 'УДАЛИТЬ НАБОР'
                                      : 'ДОБАВИТЬ НАБОР ($count)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: pack.isInstalled
                                        ? const Color(0xFFFF453A)
                                        : Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
