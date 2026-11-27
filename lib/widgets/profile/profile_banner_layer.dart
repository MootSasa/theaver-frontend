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

  /// C1-continuous smoothstep fade mask ending before the bottom clip edge so
  /// sub-pixel rounding of [ShaderMaskLayer] never leaves a hairline seam.
  static final LinearGradient _fadeMaskGradient = _buildSmoothFadeMaskGradient();

  static LinearGradient _buildSmoothFadeMaskGradient() {
    const double fadeStart = 0.38;
    const double fadeEnd = 0.97;
    const int steps = 8;

    final stops = <double>[0.0];
    final colors = <Color>[const Color(0xFFFFFFFF)];

    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final t = fadeStart + (fadeEnd - fadeStart) * u;
      final smooth = u * u * (3.0 - 2.0 * u);
      final alpha = (1.0 - smooth).clamp(0.0, 1.0).toDouble();
      stops.add(t);
      colors.add(Color.fromRGBO(255, 255, 255, alpha));
    }

    stops.add(1.0);
    colors.add(const Color(0x00FFFFFF));

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: stops,
      colors: colors,
    );
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
        imageFilter: BlurUtils.createDownsampledBlur(
          blurSigma,
          tileMode: TileMode.clamp,
        ),
        child: media,
      );
    }

    return ShaderMask(
      shaderCallback: _fadeMaskGradient.createShader,
      blendMode: BlendMode.dstIn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset =
              constraints.maxHeight.isFinite && constraints.maxHeight > 12.0
                  ? 1.0
                  : 0.0;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
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
                          stops: const [0.0, 0.52, 1.0],
                          colors: [
                            Colors.black.withValues(
                              alpha: (dim * 1.05).clamp(0.0, 0.78),
                            ),
                            Colors.black.withValues(
                              alpha: (dim * 0.88).clamp(0.0, 0.72),
                            ),
                            Colors.black.withValues(
                              alpha: (dim * 0.30).clamp(0.0, 0.45),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
