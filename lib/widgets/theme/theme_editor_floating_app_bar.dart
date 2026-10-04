import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';

const double _kAppBarHeight = 44.0;
const double _kAppBarBorderRadius = 22.0;
const double _kAppBarHorizontalPadding = 8.0;
const double _kAppBarVerticalPadding = 8.0;
const double _kPillSpacing = 8.0;
const double _kBackPillWidth = 44.0;
const double _kRightPillWidth = 88.0;

/// Total height of the floating app bar including vertical padding
const double kThemeEditorAppBarTotalHeight = _kAppBarHeight + (_kAppBarVerticalPadding * 2);

/// Floating AppBar for the Theme Editor featuring 3 distinct pills:
/// 1. Left pill: Back button (44x44 circular pill)
/// 2. Center capsule: "Редактировать" / Title
/// 3. Right capsule: Two buttons - Share & Apply (Checkmark)
///
/// Supports both Liquid Glass and Matte modes.
class ThemeEditorFloatingAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onApply;
  final bool isSaving;

  const ThemeEditorFloatingAppBar({
    Key? key,
    required this.title,
    required this.onBack,
    required this.onShare,
    required this.onApply,
    this.isSaving = false,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kThemeEditorAppBarTotalHeight);

  @override
  Widget build(BuildContext context) {
    final glassProvider = Provider.of<LiquidGlassProvider>(context);
    final isGlassEnabled = glassProvider.enabled;
    final isLite = glassProvider.isLite;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);
    final themeExt = theme.extension<TheavThemeExtension>();
    final foregroundColor = themeExt?.palette.appBarForeground ??
        (isDark ? Colors.white : const Color(0xFF1C1C1E));

    final morphShape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: _kAppBarBorderRadius,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: isDark ? 0.7 : 0.95,
      lightDirection: lightAngle,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final morphStyle = LiquidGlassStyle(
      shape: morphShape,
      appearance: LiquidGlassAppearance(
        color: isDark ? const Color(0x33202025) : const Color(0x8FFFFFFF),
        blur: glassProvider.blurEffect,
        shadow: LiquidGlassShadow(
          blur: 16,
          opacity: isDark ? 0.40 : 0.18,
          offset: const Offset(0, 4),
          color: Colors.black,
        ),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.06,
        distortionWidth: 26,
      ),
      liteGlass: isLite ? LiquidGlassLitePickup.backdrop : null,
    );

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kAppBarHorizontalPadding,
          vertical: _kAppBarVerticalPadding,
        ),
        child: SizedBox(
          height: _kAppBarHeight,
          child: Row(
            children: [
              // 1. Left Pill: Circular Back Button (44x44)
              SizedBox(
                width: _kBackPillWidth,
                height: _kAppBarHeight,
                child: _buildPill(
                  context: context,
                  isGlassEnabled: isGlassEnabled,
                  morphStyle: morphStyle,
                  isDark: isDark,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
                      onTap: () {
                        HapticUtils.tap();
                        onBack();
                      },
                      child: Center(
                        child: iconoir.NavArrowLeft(
                          width: 22.0,
                          height: 22.0,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: _kPillSpacing),

              // 2. Center Pill: Title Capsule
              Expanded(
                child: SizedBox(
                  height: _kAppBarHeight,
                  child: _buildPill(
                    context: context,
                    isGlassEnabled: isGlassEnabled,
                    morphStyle: morphStyle,
                    isDark: isDark,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0),
                      child: Center(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            color: foregroundColor,
                            fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: _kPillSpacing),

              // 3. Right Pill: Share & Apply Actions
              SizedBox(
                width: _kRightPillWidth,
                height: _kAppBarHeight,
                child: _buildPill(
                  context: context,
                  isGlassEnabled: isGlassEnabled,
                  morphStyle: morphStyle,
                  isDark: isDark,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Share Button
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(_kAppBarBorderRadius),
                            ),
                            onTap: () {
                              HapticUtils.tap();
                              onShare();
                            },
                            child: Center(
                              child: iconoir.ShareAndroid(
                                width: 20.0,
                                height: 20.0,
                                color: foregroundColor,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Subtle divider
                      Container(
                        width: 0.5,
                        height: 20.0,
                        color: foregroundColor.withValues(alpha: 0.15),
                      ),

                      // Apply (Checkmark) Button
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(_kAppBarBorderRadius),
                            ),
                            onTap: isSaving
                                ? null
                                : () {
                                    HapticUtils.tap();
                                    onApply();
                                  },
                            child: Center(
                              child: isSaving
                                  ? SizedBox(
                                      width: 18.0,
                                      height: 18.0,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          foregroundColor,
                                        ),
                                      ),
                                    )
                                  : iconoir.Check(
                                      width: 22.0,
                                      height: 22.0,
                                      color: foregroundColor,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill({
    required BuildContext context,
    required bool isGlassEnabled,
    required LiquidGlassStyle morphStyle,
    required bool isDark,
    required Widget child,
  }) {
    if (isGlassEnabled) {
      return LiquidGlassLens(
        style: morphStyle,
        child: child,
      );
    }

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final defaultBg = isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.65);
    final pillBg = themeExt?.palette.appBarBackground ?? defaultBg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(_kAppBarBorderRadius),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
