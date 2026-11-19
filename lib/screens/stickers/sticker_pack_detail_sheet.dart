import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../widgets/chat/sticker_item_widget.dart';
import '../../widgets/design_system/theav_design_system.dart';

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
    return showTheavModalSheet<void>(
      context: context,
      enableDrag: false,
      builder: (_) => const SizedBox.shrink(),
      customSheetBuilder: (ctx) => StickerPackDetailSheet(
        packIdOrSlug: packIdOrSlug.toString(),
        initialPack: initialPack,
        onSelectSticker: onSelectSticker,
      ),
    );
  }

  @override
  State<StickerPackDetailSheet> createState() => _StickerPackDetailSheetState();
}

class _StickerPackDetailSheetState extends State<StickerPackDetailSheet>
    with SingleTickerProviderStateMixin {
  static const double _initialSheetFraction = 0.68;
  static const double _minSheetFraction = 0.36;
  static const double _maxSheetFraction = 0.92;

  final ScrollController _gridScrollController = ScrollController();
  late final AnimationController _snapController;
  double _sheetFraction = _initialSheetFraction;
  double _snapFrom = _initialSheetFraction;
  double _snapTo = _initialSheetFraction;
  double _rawStretchPull = 0.0;
  double _overscrollStretch = 0.0;
  double _stretchFrom = 0.0;
  bool _isDismissing = false;

  StickerPack? _pack;
  bool _loading = true;
  bool _togglingInstall = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_snapController.value);
        setState(() {
          _sheetFraction = _snapFrom + (_snapTo - _snapFrom) * t;
          _overscrollStretch = _stretchFrom * (1.0 - t);
        });
      });
    _pack = widget.initialPack;
    if (_pack != null && _pack!.items.isNotEmpty) {
      _loading = false;
    }
    _fetchPack();
  }

  @override
  void dispose() {
    _snapController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _onHandleDragStart() {
    if (_isDismissing) return;
    _snapController.stop();
  }

  void _onHandleDragUpdate(double deltaY, double screenHeight) {
    if (_isDismissing || screenHeight <= 0) return;
    setState(() {
      final double nextFrac = _sheetFraction - deltaY / screenHeight;
      if (nextFrac > _maxSheetFraction) {
        _sheetFraction = _maxSheetFraction;
        final double overflowPx = (nextFrac - _maxSheetFraction) * screenHeight;
        _rawStretchPull = (_rawStretchPull + overflowPx).clamp(0.0, 240.0);
        _overscrollStretch = 28.0 * (1.0 - math.exp(-_rawStretchPull / 75.0));
      } else if (_rawStretchPull > 0 && deltaY > 0) {
        _rawStretchPull = math.max(0.0, _rawStretchPull - deltaY);
        _overscrollStretch = _rawStretchPull > 0
            ? 28.0 * (1.0 - math.exp(-_rawStretchPull / 75.0))
            : 0.0;
        if (_rawStretchPull == 0.0) {
          _sheetFraction =
              nextFrac.clamp(_minSheetFraction, _maxSheetFraction);
        }
      } else {
        _rawStretchPull = 0.0;
        _overscrollStretch = 0.0;
        _sheetFraction = nextFrac.clamp(_minSheetFraction, _maxSheetFraction);
      }
    });
  }

  void _onHandleDragEnd(double velocityY) {
    if (_isDismissing) return;
    _rawStretchPull = 0.0;
    if (_sheetFraction < 0.45 ||
        (velocityY > 750 && _sheetFraction < 0.78) ||
        velocityY > 1400) {
      _isDismissing = true;
      Navigator.of(context).maybePop();
      return;
    }

    final double target =
        (velocityY < -500 || (_sheetFraction > 0.80 && velocityY <= 500))
            ? _maxSheetFraction
            : _initialSheetFraction;
    _snapFrom = _sheetFraction;
    _snapTo = target;
    _stretchFrom = _overscrollStretch;
    _snapController.forward(from: 0.0);
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
    final double screenHeight = MediaQuery.sizeOf(context).height;

    final double sheetHeight = math.min(
      screenHeight * 0.97,
      screenHeight * _sheetFraction + _overscrollStretch,
    );

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: SizedBox(
        height: sheetHeight,
        child: TheavSheetSurface(
          cornerRadius: 24.0,
          stretchPx: _overscrollStretch,
          maxStretch: 28.0,
          matteColor: theme.secondaryBg,
          child: Column(
            children: [
              Center(
                child: GestureDetector(
                  key: const ValueKey('sticker_pack_sheet_drag_handle'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => _onHandleDragStart(),
                  onVerticalDragUpdate: (d) =>
                      _onHandleDragUpdate(d.delta.dy, screenHeight),
                  onVerticalDragEnd: (d) =>
                      _onHandleDragEnd(d.velocity.pixelsPerSecond.dy),
                  onVerticalDragCancel: () => _onHandleDragEnd(0.0),
                  child: SizedBox(
                    width: 112,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 12),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.dividerColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (pack != null &&
                        (pack.coverUrl.isNotEmpty || items.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Builder(
                          builder: (_) {
                            final firstItem =
                                items.isNotEmpty ? items.first : null;
                            final headerFileUrl = (firstItem != null &&
                                    firstItem.fileUrl.isNotEmpty)
                                ? firstItem.fileUrl
                                : pack.coverUrl;
                            final headerFormat = firstItem?.format ??
                                (pack.isAnimated ? 'tgs' : 'webp');
                            final isHeaderAdaptive = pack.isAdaptiveTextColor ||
                                (firstItem?.isAdaptiveTextColor ?? false);
                            return StickerMediaView(
                              fileUrl: headerFileUrl,
                              thumbnailUrl: firstItem != null
                                  ? firstItem.thumbnailUrl
                                  : pack.thumbnailUrl,
                              stickerId: firstItem?.id,
                              format: headerFormat,
                              width: 44,
                              height: 44,
                              animate: true,
                              isAdaptiveOverride: isHeaderAdaptive,
                              adaptiveTintColor:
                                  isHeaderAdaptive ? theme.textPrimary : null,
                            );
                          },
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
                            controller: _gridScrollController,
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
                              final isItemAdaptive = item.isAdaptiveTextColor ||
                                  (pack?.isAdaptiveTextColor ?? false);
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
                                      thumbnailUrl: item.thumbnailUrl,
                                      stickerId: item.id,
                                      format: item.format,
                                      width: isEmojiPack ? 36 : 64,
                                      height: isEmojiPack ? 36 : 64,
                                      animate: true,
                                      isAdaptiveOverride: isItemAdaptive,
                                      adaptiveTintColor: isItemAdaptive
                                          ? theme.textPrimary
                                          : null,
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
        ),
      ),
    );
  }
}
