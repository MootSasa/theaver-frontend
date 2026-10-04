import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders an SVG wallpaper pattern tiled seamlessly at a delicate, refined scale
/// (~360-390px per tile) matching preview cards and preventing oversized doodles on full screens.
class TiledWallpaperPattern extends StatelessWidget {
  final String? assetPath;
  final String? filePath;
  final ColorFilter colorFilter;
  final double baseTileWidth;

  const TiledWallpaperPattern({
    Key? key,
    this.assetPath,
    this.filePath,
    required this.colorFilter,
    this.baseTileWidth = 360.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (assetPath == null && filePath == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0) return const SizedBox.shrink();

        // On mobile screens (width < 500), 1 tile spans the screen width exactly
        // to prevent any awkward horizontal seams while keeping doodles fine and compact.
        // On wider screens (tablets, desktop), integer columns ensure seamless horizontal repetition.
        final int cols = w < 500 ? 1 : math.max(1, (w / baseTileWidth).round());
        final double tileSize = w / cols;
        final int rows = (h / tileSize).ceil();

        return ClipRect(
          child: SizedBox(
            width: w,
            height: h,
            child: RepaintBoundary(
              child: Stack(
                children: [
                  for (int r = 0; r < rows; r++)
                    for (int c = 0; c < cols; c++)
                      Positioned(
                        left: c * tileSize,
                        top: r * tileSize,
                        width: tileSize,
                        height: tileSize,
                        child: assetPath != null
                            ? SvgPicture.asset(
                                assetPath!,
                                width: tileSize,
                                height: tileSize,
                                fit: BoxFit.fill,
                                colorFilter: colorFilter,
                              )
                            : SvgPicture.file(
                                File(filePath!),
                                width: tileSize,
                                height: tileSize,
                                fit: BoxFit.fill,
                                colorFilter: colorFilter,
                              ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
