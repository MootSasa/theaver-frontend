import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/profile_customization.dart';
import '../../utils/blur_utils.dart';
import '../chat/sticker_item_widget.dart';

/// Shared non-destructive profile banner renderer used across customization preview,
/// interactive banner editor, and profile headers (own & peer).
class ProfileBannerLayer extends StatelessWidget {
  final String? bannerUrl;
  final Uint8List? localBytes;
  final String? localFilePath;
  final ProfileBannerLayout? _layout;
  final bool animate;
  final FilterQuality filterQuality;

  /// Hot-Reload-safe getter for [layout].
  ProfileBannerLayout get layout => _layout ?? const ProfileBannerLayout();

  const ProfileBannerLayer({
    super.key,
    this.bannerUrl,
    this.localBytes,
    this.localFilePath,
    ProfileBannerLayout? layout,
    this.animate = true,
    this.filterQuality = FilterQuality.medium,
  }) : _layout = layout;

  bool get hasMedia =>
      localBytes != null ||
      (!kIsWeb && localFilePath != null && localFilePath!.isNotEmpty) ||
      (bannerUrl != null && bannerUrl!.isNotEmpty);

  Widget _buildMedia(Alignment alignment) {
    if (localBytes != null) {
      return Image.memory(
        localBytes!,
        fit: BoxFit.cover,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    if (!kIsWeb && localFilePath != null && localFilePath!.isNotEmpty) {
      return Image.file(
        File(localFilePath!),
        fit: BoxFit.cover,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    if (bannerUrl != null && bannerUrl!.isNotEmpty) {
      return ControlledAnimatedNetworkImage(
        url: bannerUrl!,
        fit: BoxFit.cover,
        alignment: alignment,
        filterQuality: filterQuality,
        animate: animate,
        errorBuilder: (_) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (!hasMedia) return const SizedBox.shrink();

    final alignment = layout.alignment;
    final scale = layout.scale.clamp(1.0, 3.0).toDouble();
    final blurSigma = layout.blur.clamp(0.0, 20.0).toDouble();
    final dim = layout.dim.clamp(0.0, 0.75).toDouble();

    Widget media = _buildMedia(alignment);
    if ((scale - 1.0).abs() > 0.001) {
      media = Transform.scale(
        scale: scale,
        alignment: alignment,
        child: media,
      );
    }

    // Avoid saveLayer cost on default unblurred banners for 120fps scrolling.
    if (blurSigma > 0.1) {
      media = ImageFiltered(
        imageFilter: BlurUtils.createDownsampledBlur(blurSigma),
        child: media,
      );
    }

    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.54, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            media,
            if (dim > 0.005)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: (dim * 0.68).clamp(0.0, 0.75)),
                      Colors.black.withValues(alpha: (dim * 1.32).clamp(0.0, 0.85)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
