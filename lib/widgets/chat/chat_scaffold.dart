import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:inspire_blur/inspire_blur.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/wallpaper_provider.dart';
import '../theme/four_corner_gradient.dart';
import '../theme/motion_wallpaper_wrapper.dart';

/// Unified scaffold for all chat screens (private chat, group chat, channel).
/// Supports custom wallpapers, floating glass AppBar, bottom input bars,
/// and smooth back navigation with keyboard dismissal.
class ChatScaffold extends StatelessWidget {
  final Widget body;
  final Widget? appBar;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final Widget? customBackground;
  final Color? backgroundColor;
  final bool? canPop;
  final void Function(bool didPop, dynamic result)? onPopInvoked;
  final bool enableStatusBarBlur;
  final bool enableBottomScrollEdge;
  final double? bottomScrollEdgeHeight;

  const ChatScaffold({
    Key? key,
    required this.body,
    this.appBar,
    this.bottomBar,
    this.floatingActionButton,
    this.customBackground,
    this.backgroundColor,
    this.canPop,
    this.onPopInvoked,
    this.enableStatusBarBlur = true,
    this.enableBottomScrollEdge = true,
    this.bottomScrollEdgeHeight,
  }) : super(key: key);

  /// Helper to calculate standard top padding for chat message lists
  /// when a floating glass app bar is positioned over the content.
  static double getTopContentPadding(BuildContext context) {
    return MediaQuery.of(context).padding.top + kToolbarHeight + 16.0;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardVisible = bottomInset > 0;
    final defaultCanPop = canPop ?? !isKeyboardVisible;
    final glassProvider = context.watch<LiquidGlassProvider?>();

    return PopScope(
      canPop: defaultCanPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (isKeyboardVisible) {
            FocusScope.of(context).unfocus();
          }
          if (onPopInvoked != null) {
            onPopInvoked!(didPop, result);
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Wallpaper background layer
            _buildBackground(context),

            // 2. Main content layer
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(child: body),
                  if (bottomBar != null)
                    SafeArea(
                      top: false,
                      child: bottomBar!,
                    ),
                ],
              ),
            ),

            // 3. Top scroll edge / status bar blur
            _buildTopScrollEdge(context, glassProvider),

            // 4. Floating AppBar layer
            if (appBar != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: appBar!,
              ),

            // 5. Floating Action Button layer
            if (floatingActionButton != null)
              Positioned(
                right: 16,
                bottom: bottomInset + 80,
                child: floatingActionButton!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopScrollEdge(BuildContext context, LiquidGlassProvider? glassProvider) {
    if (!enableStatusBarBlur) return const SizedBox.shrink();

    final statusBarHeight = MediaQuery.paddingOf(context).top;
    // On PC / desktop / web, statusBarHeight is 0, so do not apply blur at all
    if (statusBarHeight <= 0) return const SizedBox.shrink();

    final isGlass = glassProvider?.enabled ?? false;
    final effectiveBlur = math.max(glassProvider?.blur ?? 8.0, 8.0);
    if (isGlass) {
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: statusBarHeight,
        child: LiquidGlassScrollEdge(
          edge: LiquidGlassEdge.top,
          style: LiquidGlassScrollEdgeStyle.soft,
          blur: effectiveBlur,
          color: Colors.transparent,
        ),
      );
    }

    // Fallback for classic / matte mode
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: statusBarHeight,
      child: IgnorePointer(
        child: InspireBackdropBlur(
          clipBehavior: Clip.hardEdge,
          config: InspireBlurConfig.topToBottom(
            sigma: 16.0,
            extent: 1.0,
            fadeCurve: Curves.easeOutCubic,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    if (customBackground != null) {
      return customBackground!;
    }

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final wp = themeExt?.wallpaper;

    if (wp != null) {
      // 1. Base 4-corner gradient or background color
      Widget baseBackground;
      if (wp.fourCornerGradient != null) {
        final grad = wp.fourCornerGradient!;
        baseBackground = CustomPaint(
          painter: FourCornerGradientPainter(
            topLeft: grad.topLeft,
            topRight: grad.topRight,
            bottomLeft: grad.bottomLeft,
            bottomRight: grad.bottomRight,
          ),
          child: const SizedBox.expand(),
        );
      } else {
        baseBackground = Container(color: wp.backgroundColor);
      }

      Widget content;
      if (wp.type == 'image') {
        final imgPath = wp.imagePath ?? context.watch<WallpaperProvider?>()?.wallpaperPath;
        if (imgPath != null && imgPath.isNotEmpty && File(imgPath).existsSync()) {
          Widget img = Image.file(
            File(imgPath),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
          if (wp.blurRadius > 0) {
            img = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: wp.blurRadius,
                sigmaY: wp.blurRadius,
              ),
              child: img,
            );
          }
          content = Stack(
            fit: StackFit.expand,
            children: [
              img,
              if (wp.dimming > 0)
                Container(
                  color: Colors.black.withValues(alpha: wp.dimming),
                ),
            ],
          );
        } else {
          content = baseBackground;
        }
      } else {
        // Pattern over 4-corner gradient
        final svgPath = wp.assetSvgPath;
        Widget patternWidget = const SizedBox.shrink();

        if (svgPath != null && wp.patternOpacity > 0) {
          patternWidget = SvgPicture.asset(
            svgPath,
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              wp.patternColor.withValues(alpha: wp.patternOpacity),
              BlendMode.srcIn,
            ),
          );
        } else if (wp.customSvgPath != null && File(wp.customSvgPath!).existsSync() && wp.patternOpacity > 0) {
          patternWidget = SvgPicture.file(
            File(wp.customSvgPath!),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              wp.patternColor.withValues(alpha: wp.patternOpacity),
              BlendMode.srcIn,
            ),
          );
        }

        content = Stack(
          fit: StackFit.expand,
          children: [
            baseBackground,
            patternWidget,
          ],
        );
      }

      if (wp.motionEnabled) {
        return Positioned.fill(
          child: MotionWallpaperWrapper(
            enabled: true,
            child: content,
          ),
        );
      }

      return Positioned.fill(child: content);
    }

    final wallpaperPath = context.watch<WallpaperProvider?>()?.wallpaperPath;
    if (wallpaperPath != null && wallpaperPath.isNotEmpty) {
      final file = File(wallpaperPath);
      if (file.existsSync()) {
        return Positioned.fill(
          child: Image.file(
            file,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    return const SizedBox.shrink();
  }
}

/// Fading bottom scroll edge blur placed under the input field (above messages, below input).
class ChatBottomScrollEdge extends StatelessWidget {
  final double? height;

  const ChatBottomScrollEdge({Key? key, this.height}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final isGlass = glassProvider?.enabled ?? false;
    if (!isGlass) return const SizedBox.shrink();

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    // Hide bottom scroll edge when virtual keyboard is visible
    if (bottomInset > 0) return const SizedBox.shrink();

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final edgeHeight = height ?? math.max(safeBottom + 52.0, 52.0);
    final effectiveBlur = math.max(glassProvider?.blur ?? 8.0, 8.0);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: edgeHeight,
      child: LiquidGlassScrollEdge(
        edge: LiquidGlassEdge.bottom,
        style: LiquidGlassScrollEdgeStyle.soft,
        blur: effectiveBlur,
        color: Colors.transparent,
      ),
    );
  }
}
