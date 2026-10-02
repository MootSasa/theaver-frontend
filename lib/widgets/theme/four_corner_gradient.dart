import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/theav_theme.dart';
import '../../l10n/app_localizations.dart';

/// GPU-accelerated 4-corner mesh gradient painter using Canvas.drawVertices.
class FourCornerGradientPainter extends CustomPainter {
  final Color topLeft;
  final Color topRight;
  final Color bottomLeft;
  final Color bottomRight;

  const FourCornerGradientPainter({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final positions = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    final colors = <Color>[
      topLeft,
      topRight,
      bottomLeft,
      bottomRight,
    ];

    final vertices = ui.Vertices(
      ui.VertexMode.triangleStrip,
      positions,
      colors: colors,
    );

    final paint = Paint()..isAntiAlias = true;
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  @override
  bool shouldRepaint(FourCornerGradientPainter oldDelegate) {
    return topLeft != oldDelegate.topLeft ||
        topRight != oldDelegate.topRight ||
        bottomLeft != oldDelegate.bottomLeft ||
        bottomRight != oldDelegate.bottomRight;
  }
}

/// Interactive 4-corner gradient editor with interactive corner handles and presets.
class FourCornerGradientSelector extends StatelessWidget {
  final FourCornerGradient gradient;
  final ValueChanged<FourCornerGradient> onChanged;
  final String? patternSvgPath;
  final Color? patternColor;
  final double patternOpacity;

  const FourCornerGradientSelector({
    Key? key,
    required this.gradient,
    required this.onChanged,
    this.patternSvgPath,
    this.patternColor,
    this.patternOpacity = 0.15,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Interactive Preview Card with corner buttons
        Container(
          height: 180,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Mesh background
                Positioned.fill(
                  child: CustomPaint(
                    painter: FourCornerGradientPainter(
                      topLeft: gradient.topLeft,
                      topRight: gradient.topRight,
                      bottomLeft: gradient.bottomLeft,
                      bottomRight: gradient.bottomRight,
                    ),
                  ),
                ),
                // Pattern overlay (if active)
                if (patternSvgPath != null && patternOpacity > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: SvgPicture.asset(
                        patternSvgPath!,
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          (patternColor ?? Colors.white).withValues(alpha: patternOpacity),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                // Top-Left corner handle
                Positioned(
                  top: 12,
                  left: 12,
                  child: _CornerColorChip(
                    color: gradient.topLeft,
                    label: l10n.translate('wallpaper_corner_top_left'),
                    onColorChanged: (c) => onChanged(gradient.copyWith(topLeft: c)),
                  ),
                ),
                // Top-Right corner handle
                Positioned(
                  top: 12,
                  right: 12,
                  child: _CornerColorChip(
                    color: gradient.topRight,
                    label: l10n.translate('wallpaper_corner_top_right'),
                    onColorChanged: (c) => onChanged(gradient.copyWith(topRight: c)),
                  ),
                ),
                // Bottom-Left corner handle
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: _CornerColorChip(
                    color: gradient.bottomLeft,
                    label: l10n.translate('wallpaper_corner_bottom_left'),
                    onColorChanged: (c) => onChanged(gradient.copyWith(bottomLeft: c)),
                  ),
                ),
                // Bottom-Right corner handle
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _CornerColorChip(
                    color: gradient.bottomRight,
                    label: l10n.translate('wallpaper_corner_bottom_right'),
                    onColorChanged: (c) => onChanged(gradient.copyWith(bottomRight: c)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Quick Presets Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Пресеты градиента',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _PresetChip(
                name: 'Classic',
                gradient: FourCornerGradient.defaultClassic,
                isSelected: gradient == FourCornerGradient.defaultClassic,
                onTap: () => onChanged(FourCornerGradient.defaultClassic),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                name: 'Dark',
                gradient: FourCornerGradient.defaultDark,
                isSelected: gradient == FourCornerGradient.defaultDark,
                onTap: () => onChanged(FourCornerGradient.defaultDark),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                name: 'Sunset',
                gradient: FourCornerGradient.defaultSunset,
                isSelected: gradient == FourCornerGradient.defaultSunset,
                onTap: () => onChanged(FourCornerGradient.defaultSunset),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                name: 'Ocean',
                gradient: FourCornerGradient.defaultOcean,
                isSelected: gradient == FourCornerGradient.defaultOcean,
                onTap: () => onChanged(FourCornerGradient.defaultOcean),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                name: 'Aurora',
                gradient: FourCornerGradient.defaultAurora,
                isSelected: gradient == FourCornerGradient.defaultAurora,
                onTap: () => onChanged(FourCornerGradient.defaultAurora),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                name: 'Pastel',
                gradient: FourCornerGradient.defaultPastel,
                isSelected: gradient == FourCornerGradient.defaultPastel,
                onTap: () => onChanged(FourCornerGradient.defaultPastel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String name;
  final FourCornerGradient gradient;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.name,
    required this.gradient,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          color: Theme.of(context).cardColor,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: FourCornerGradientPainter(
                    topLeft: gradient.topLeft,
                    topRight: gradient.topRight,
                    bottomLeft: gradient.bottomLeft,
                    bottomRight: gradient.bottomRight,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? const Color(0xFF0088CC) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerColorChip extends StatelessWidget {
  final Color color;
  final String label;
  final ValueChanged<Color> onColorChanged;

  const _CornerColorChip({
    required this.color,
    required this.label,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _pickColor(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickColor(BuildContext context) {
    final curatedColors = [
      const Color(0xFF0088CC),
      const Color(0xFF5CB8E6),
      const Color(0xFF0D47A1),
      const Color(0xFF00BFA5),
      const Color(0xFF69F0AE),
      const Color(0xFF4CAF50),
      const Color(0xFF8BC34A),
      const Color(0xFFFFD54F),
      const Color(0xFFFF9800),
      const Color(0xFFFF5722),
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      const Color(0xFF673AB7),
      const Color(0xFF3F51B5),
      const Color(0xFF607D8B),
      const Color(0xFF263238),
      const Color(0xFF1C1C1E),
      const Color(0xFFE0F7FA),
      const Color(0xFFF3E5F5),
      const Color(0xFFFFFFFF),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: curatedColors.map((c) {
                    final isSel = c.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        onColorChanged(c);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? const Color(0xFF0088CC) : Colors.grey.withValues(alpha: 0.3),
                            width: isSel ? 3 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: isSel
                            ? Icon(
                                Icons.check,
                                size: 20,
                                color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
