import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../screens/stickers/sticker_pack_detail_sheet.dart';
import '../../services/sticker_service.dart';
import '../../utils/emoji_utils.dart';
import '../chat/sticker_item_widget.dart';

class StickerMessageWidget extends StatefulWidget {
  final String imageUrl;
  final String format;
  final String? stickerId;
  final String? packId;
  final String? effectAnimationUrl;
  final String? fallbackEmoji;
  final bool isSentByMe;
  final bool autoPlayEffect;
  final String? messageKeyId;
  final Widget? floatingTimestampBadge;

  const StickerMessageWidget({
    super.key,
    required this.imageUrl,
    this.format = 'webp',
    this.stickerId,
    this.packId,
    this.effectAnimationUrl,
    this.fallbackEmoji,
    this.isSentByMe = false,
    this.autoPlayEffect = false,
    this.messageKeyId,
    this.floatingTimestampBadge,
  });

  @override
  State<StickerMessageWidget> createState() => _StickerMessageWidgetState();
}

class _StickerMessageWidgetState extends State<StickerMessageWidget> {
  static final Set<String> _autoPlayedStickerEffects = <String>{};
  final LayerLink _layerLink = LayerLink();
  StickerItem? _resolvedSticker;

  @override
  void initState() {
    super.initState();
    _resolveMetadata();
    if (widget.autoPlayEffect) {
      final keyId = widget.messageKeyId ?? widget.imageUrl;
      if (_autoPlayedStickerEffects.add(keyId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _triggerEffectIfAvailable(openPackFallback: false);
          }
        });
      }
    }
  }

  Future<void> _resolveMetadata() async {
    final sid = widget.stickerId;
    if (sid == null || sid.isEmpty) return;
    final syncItem = StickerService.instance.getStickerByIdSync(sid);
    if (syncItem != null) {
      if (mounted) setState(() => _resolvedSticker = syncItem);
      return;
    }
    final fetched = await StickerService.instance.getStickerById(sid);
    if (mounted && fetched != null) {
      setState(() => _resolvedSticker = fetched);
    }
  }

  String get _effectiveEffectUrl {
    if (widget.effectAnimationUrl != null &&
        widget.effectAnimationUrl!.trim().isNotEmpty) {
      return widget.effectAnimationUrl!.trim();
    }
    return _resolvedSticker?.effectAnimationUrl ?? '';
  }

  String? get _effectivePackId {
    if (widget.packId != null && widget.packId!.trim().isNotEmpty) {
      return widget.packId!.trim();
    }
    final p = _resolvedSticker?.packId;
    return (p != null && p > 0) ? p.toString() : null;
  }

  String? get _effectiveEmoji {
    if (widget.fallbackEmoji != null &&
        widget.fallbackEmoji!.trim().isNotEmpty) {
      return widget.fallbackEmoji!.trim();
    }
    if (_resolvedSticker != null && _resolvedSticker!.emojis.isNotEmpty) {
      return _resolvedSticker!.emojis.first;
    }
    return null;
  }

  void _triggerEffectIfAvailable({bool openPackFallback = true}) {
    final effectUrl = _effectiveEffectUrl;
    final emoji = _effectiveEmoji;
    final size = MediaQuery.sizeOf(context).width >= 640 ? 184.0 : 160.0;

    if (effectUrl.isNotEmpty || (emoji != null && emoji.isNotEmpty)) {
      if (EmojiEffectOverlay.isStickerEffectActive(_layerLink)) {
        return;
      }
      HapticFeedback.lightImpact();
      EmojiEffectOverlay.showStickerEffect(
        context: context,
        effectUrl: effectUrl.isNotEmpty ? effectUrl : null,
        fallbackEmoji: emoji,
        layerLink: _layerLink,
        stickerSize: size,
        isMe: widget.isSentByMe,
      );
      return;
    }

    final packId = _effectivePackId;
    if (openPackFallback && packId != null && packId.isNotEmpty) {
      HapticFeedback.selectionClick();
      StickerPackDetailSheet.show(
        context,
        packIdOrSlug: packId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double stickerSize =
        MediaQuery.sizeOf(context).width >= 640 ? 184.0 : 160.0;
    final hasEffect = _effectiveEffectUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => _triggerEffectIfAvailable(openPackFallback: true),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CompositedTransformTarget(
            link: _layerLink,
            child: StickerMediaView(
              fileUrl: widget.imageUrl,
              format: _resolvedSticker?.format.isNotEmpty == true
                  ? _resolvedSticker!.format
                  : widget.format,
              width: stickerSize,
              height: stickerSize,
              animate: true,
            ),
          ),
          if (hasEffect)
            Positioned(
              top: 4,
              right: widget.isSentByMe ? null : 4,
              left: widget.isSentByMe ? 4 : null,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.38),
                  shape: BoxShape.circle,
                ),
                child: const iconoir.Sparks(
                  width: 11,
                  height: 11,
                  color: Colors.white,
                ),
              ),
            ),
          if (widget.floatingTimestampBadge != null)
            Positioned(
              right: 2,
              bottom: 2,
              child: widget.floatingTimestampBadge!,
            ),
        ],
      ),
    );
  }
}

class GifMessageWidget extends StatelessWidget {
  final String gifUrl;
  final int? width;
  final int? height;
  final Widget? floatingTimestampBadge;

  const GifMessageWidget({
    super.key,
    required this.gifUrl,
    this.width,
    this.height,
    this.floatingTimestampBadge,
  });

  @override
  Widget build(BuildContext context) {
    final double maxW = MediaQuery.sizeOf(context).width >= 640 ? 280.0 : 240.0;
    final double aspect = (width != null && height != null && height! > 0)
        ? (width! / height!).clamp(0.6, 2.0)
        : 1.33;
    final double displayW = maxW;
    final double displayH = (displayW / aspect).clamp(130.0, 300.0);
    final resolvedUrl = StickerService.resolveUrl(gifUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: displayW,
        height: displayH,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              resolvedUrl,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const Text(
                  'GIF',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (floatingTimestampBadge != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: floatingTimestampBadge!,
              ),
          ],
        ),
      ),
    );
  }
}
