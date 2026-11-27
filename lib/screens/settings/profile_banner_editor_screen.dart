import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../models/profile_customization.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/common/glass_modal_sheet.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/profile/profile_banner_layer.dart';
import '../../widgets/profile/profile_floating_top_switcher.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/user/emoji_status_badge.dart';

/// Interactive non-destructive profile banner editor supporting live drag/pinch
/// focal positioning, zoom, height presets, contrast dimming, Gaussian blur,
/// and image replacement across local bytes/file and remote banner URLs.
class ProfileBannerEditorScreen extends StatefulWidget {
  final String? initialBannerUrl;
  final String? initialFilePath;
  final Uint8List? initialBytes;
  final String? initialFileName;
  final ProfileBannerLayout? _initialLayout;
  final String displayName;
  final String? avatarUrl;
  final String? userId;
  final Future<bool> Function(
    ProfileBannerLayout layout, {
    String? filePath,
    Uint8List? bytes,
    String? fileName,
  })? onSaveOverride;

  /// Hot-Reload-safe getter for [initialLayout].
  ProfileBannerLayout get initialLayout =>
      _initialLayout ?? const ProfileBannerLayout();

  const ProfileBannerEditorScreen({
    super.key,
    this.initialBannerUrl,
    this.initialFilePath,
    this.initialBytes,
    this.initialFileName,
    ProfileBannerLayout? initialLayout,
    required this.displayName,
    this.avatarUrl,
    this.userId,
    this.onSaveOverride,
  }) : _initialLayout = initialLayout;

  @override
  State<ProfileBannerEditorScreen> createState() =>
      _ProfileBannerEditorScreenState();
}

class _ProfileBannerEditorScreenState extends State<ProfileBannerEditorScreen> {
  static const int _maxBannerBytes = 15 * 1024 * 1024;

  ProfileBannerLayout? _layoutState;
  ProfileBannerLayout get _layout => _layoutState ?? widget.initialLayout;
  set _layout(ProfileBannerLayout value) => _layoutState = value;
  String? _bannerUrl;
  String? _localFilePath;
  Uint8List? _localBytes;
  String? _localFileName;

  bool _isInteracting = false;
  bool _isSaving = false;

  double _gestureStartScale = 1.0;
  double _gestureStartPosX = 0.0;
  double _gestureStartPosY = 0.0;
  Offset _gestureStartFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout;
    _bannerUrl = widget.initialBannerUrl;
    _localFilePath = widget.initialFilePath;
    _localBytes = widget.initialBytes;
    _localFileName = widget.initialFileName;
  }

  static double _computeCoverLuminance(ProfileColorPreset preset) {
    if (preset.isGradient &&
        preset.gradientColors != null &&
        preset.gradientColors!.isNotEmpty) {
      final sum = preset.gradientColors!.fold<double>(
        0.0,
        (acc, c) => acc + c.computeLuminance(),
      );
      return sum / preset.gradientColors!.length;
    }
    return preset.backgroundColor.computeLuminance();
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    try {
      GlassToastService().show(
        context,
        message,
        icon: isError
            ? Icons.error_outline_rounded
            : Icons.check_circle_outline_rounded,
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _resetLayout() {
    HapticUtils.selection();
    setState(() => _layout = const ProfileBannerLayout());
  }

  Future<void> _pickReplacementImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.size > _maxBannerBytes) {
        if (mounted) {
          _showToast(
            translateOrFallback(
              context,
              'customizationUploadError',
              'File exceeds 15 MB or unsupported format',
            ),
            isError: true,
          );
        }
        return;
      }
      if (!mounted) return;
      HapticUtils.selection();
      setState(() {
        _localBytes = kIsWeb ? file.bytes : null;
        _localFilePath = kIsWeb ? null : file.path;
        _localFileName = file.name;
      });
    } catch (e) {
      if (mounted) {
        _showToast(
          translateOrFallback(
            context,
            'customizationUploadError',
            'Failed to pick banner image',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _saveBanner() async {
    if (_isSaving) return;
    HapticUtils.tap();
    setState(() => _isSaving = true);

    bool ok = false;
    try {
      if (widget.onSaveOverride != null) {
        ok = await widget.onSaveOverride!(
          _layout,
          filePath: _localFilePath,
          bytes: _localBytes,
          fileName: _localFileName,
        );
      } else {
        final provider = context.read<ProfileThemeProvider>();
        if (_localBytes != null ||
            (_localFilePath != null && _localFilePath!.isNotEmpty)) {
          final uploadedUrl = await provider.uploadBanner(
            filePath: _localFilePath,
            bytes: _localBytes,
            fileName: _localFileName ?? 'banner.jpg',
            layout: _layout,
          );
          ok = uploadedUrl != null && uploadedUrl.isNotEmpty;
        } else {
          ok = await provider.updateCustomization(bannerLayout: _layout);
        }
      }
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _showToast(
        translateOrFallback(
          context,
          'customizationUploadError',
          'Failed to save banner settings',
        ),
        isError: true,
      );
    }
  }

  void _handlePointerScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final step = event.scrollDelta.dy > 0 ? -0.08 : 0.08;
    setState(() {
      _layout = _layout.copyWith(
        scale: (_layout.scale + step).clamp(1.0, 3.0),
      );
    });
  }

  Widget _buildFloatingActionCircle({
    required Widget icon,
    required VoidCallback? onTap,
    required bool glassEnabled,
    required bool isLite,
    required bool isDarkBackdrop,
    Key? buttonKey,
    String? tooltip,
  }) {
    const size = kProfileFloatingBarHeight;
    final inner = GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticUtils.tap();
              onTap();
            },
      child: Container(
        width: size,
        height: size,
        decoration: glassEnabled
            ? null
            : BoxDecoration(
                color: isDarkBackdrop
                    ? const Color(0xFF26262A).withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDarkBackdrop
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
        child: Center(child: icon),
      ),
    );

    Widget result;
    final glassProvider = maybeLiquidGlassProvider(context);
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDarkBackdrop,
        isLiteOverride: isLite,
        cornerRadius: size / 2,
        color: isDarkBackdrop
            ? const Color(0x38202025)
            : const Color(0x66FFFFFF),
        refractionIndex: 1.12,
        refractionWidth: 22.0,
      );
      result = LiquidGlassLens(
        style: style,
        child: SizedBox(width: size, height: size, child: inner),
      );
    } else {
      result = ClipOval(
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(15),
          child: inner,
        ),
      );
    }

    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: result);
    }
    return result;
  }

  Widget _buildFloatingTitlePill({
    required String title,
    required bool glassEnabled,
    required bool isLite,
    required bool isDarkBackdrop,
  }) {
    final textColor =
        isDarkBackdrop ? Colors.white.withValues(alpha: 0.94) : const Color(0xFF1C1C1E);
    final pillBody = Container(
      height: kProfileFloatingBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: glassEnabled
          ? null
          : BoxDecoration(
              color: isDarkBackdrop
                  ? const Color(0xFF26262A).withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(kProfileFloatingBarHeight / 2),
              border: Border.all(
                color: isDarkBackdrop
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
      child: Center(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: textColor,
          ),
        ),
      ),
    );

    final glassProvider = maybeLiquidGlassProvider(context);
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDarkBackdrop,
        isLiteOverride: isLite,
        cornerRadius: kProfileFloatingBarHeight / 2,
        color: isDarkBackdrop
            ? const Color(0x38202025)
            : const Color(0x66FFFFFF),
        refractionIndex: 1.12,
        refractionWidth: 22.0,
      );
      return LiquidGlassLens(style: style, child: pillBody);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(kProfileFloatingBarHeight / 2),
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: pillBody,
      ),
    );
  }

  Widget _buildHeightSelector({
    required bool isDarkBackdrop,
    required Color accentColor,
    required Color primaryText,
    required Color secondaryText,
  }) {
    const modes = ProfileBannerHeightMode.values;
    final selectedIndex = modes.indexOf(_layout.heightMode);
    final alignX = (selectedIndex / (modes.length - 1)) * 2.0 - 1.0;

    String labelFor(ProfileBannerHeightMode mode) {
      switch (mode) {
        case ProfileBannerHeightMode.compact:
          return translateOrFallback(
            context,
            'bannerHeightCompact',
            'Compact',
          );
        case ProfileBannerHeightMode.standard:
          return translateOrFallback(
            context,
            'bannerHeightStandard',
            'Standard',
          );
        case ProfileBannerHeightMode.tall:
          return translateOrFallback(
            context,
            'bannerHeightTall',
            'Tall',
          );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translateOrFallback(
              context,
              'bannerHeightLabel',
              'Banner Height',
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(alignX, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1.0 / modes.length,
                    heightFactor: 1.0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accentColor.withValues(
                            alpha: isDarkBackdrop ? 0.24 : 0.14,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final mode in modes)
                      Expanded(
                        child: GestureDetector(
                          key: ValueKey<String>('banner_height_${mode.wireValue}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticUtils.selection();
                            setState(() {
                              _layout = _layout.copyWith(heightMode: mode);
                            });
                          },
                          child: Center(
                            child: Text(
                              labelFor(mode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: _layout.heightMode == mode
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: _layout.heightMode == mode
                                    ? primaryText
                                    : secondaryText,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderControl({
    required Key sliderKey,
    required String label,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color primaryText,
    required Color secondaryText,
    required Color accentColor,
    required bool isDarkBackdrop,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: primaryText,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: secondaryText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accentColor,
              inactiveTrackColor: isDarkBackdrop
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.12),
              thumbColor: Colors.white,
              overlayColor: accentColor.withValues(alpha: 0.16),
              trackHeight: 4,
            ),
            child: Slider(
              key: sliderKey,
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final themeProvider = context.watch<ProfileThemeProvider>();

    final coverPreset = themeProvider.currentPreset ?? ProfileColorPresets.blue;
    final isDarkBackdrop = _computeCoverLuminance(coverPreset) < 0.60;
    final baseBgColor = coverPreset.isGradient &&
            coverPreset.gradientColors != null &&
            coverPreset.gradientColors!.isNotEmpty
        ? coverPreset.gradientColors!.last
        : coverPreset.backgroundColor;

    final primaryText =
        isDarkBackdrop ? Colors.white : const Color(0xFF1C1C1E);
    final secondaryText = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF5A5A60);
    final hasBannerMedia = _localBytes != null ||
        (!kIsWeb && _localFilePath != null && _localFilePath!.isNotEmpty) ||
        (_bannerUrl != null && _bannerUrl!.isNotEmpty);

    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final topContentPadding = topPadding + 8.0 + kProfileFloatingBarHeight + 8.0;
    final maxStageHeight = math.max(220.0, mediaQuery.size.height * 0.44);
    final rawBannerHeight = _layout.heightMode.resolveCustomizationHeight(
      topContentPadding,
      devicePixelRatio: mediaQuery.devicePixelRatio,
    );
    final stageHeight = ProfileBannerHeightMode.snapToPixelGrid(
      rawBannerHeight.clamp(196.0, maxStageHeight).toDouble(),
      mediaQuery.devicePixelRatio,
    );

    final hasLightCoverAndNoDarkBanner = !isDarkBackdrop && !hasBannerMedia;
    final onHeroForeground = hasLightCoverAndNoDarkBanner
        ? const Color(0xFF1C1C1E)
        : Colors.white;
    final onHeroSubtitle = hasLightCoverAndNoDarkBanner
        ? const Color(0xFF3A3A40)
        : Colors.white.withValues(alpha: 0.78);

    final glassEnabled = glassProvider.enabled;
    final isLite = glassProvider.isLite;
    final accentColor = coverPreset.ringColor;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isDarkBackdrop ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          isDarkBackdrop ? Brightness.dark : Brightness.light,
    );

    final activeStatus = themeProvider.currentEmojiStatus;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: baseBgColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: coverPreset.isGradient &&
                        coverPreset.gradientColors != null
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: coverPreset.gradientColors!,
                        ),
                      )
                    : BoxDecoration(color: coverPreset.backgroundColor),
              ),
            ),
            Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stageW = constraints.maxWidth > 0
                        ? constraints.maxWidth
                        : mediaQuery.size.width;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: double.infinity,
                      height: stageHeight,
                      child: Listener(
                        onPointerSignal: _handlePointerScroll,
                        child: GestureDetector(
                          key: const ValueKey<String>(
                            'banner_editor_gesture_stage',
                          ),
                          behavior: HitTestBehavior.opaque,
                          onDoubleTap: () {
                            HapticUtils.selection();
                            setState(() {
                              final nextScale =
                                  (_layout.scale - 1.0).abs() < 0.15 ? 2.0 : 1.0;
                              _layout = _layout.copyWith(scale: nextScale);
                            });
                          },
                          onScaleStart: (details) {
                            _gestureStartScale = _layout.scale;
                            _gestureStartPosX = _layout.posX;
                            _gestureStartPosY = _layout.posY;
                            _gestureStartFocal = details.focalPoint;
                            setState(() => _isInteracting = true);
                          },
                          onScaleUpdate: (details) {
                            final delta =
                                details.focalPoint - _gestureStartFocal;
                            final stepX =
                                (stageW * 0.5 * _layout.scale).clamp(80.0, 2000.0);
                            final stepY = (stageHeight * 0.5 * _layout.scale)
                                .clamp(80.0, 2000.0);
                            setState(() {
                              _layout = _layout.copyWith(
                                scale: (_gestureStartScale * details.scale)
                                    .clamp(1.0, 3.0),
                                posX: (_gestureStartPosX - delta.dx / stepX)
                                    .clamp(-1.0, 1.0),
                                posY: (_gestureStartPosY - delta.dy / stepY)
                                    .clamp(-1.0, 1.0),
                              );
                            });
                          },
                          onScaleEnd: (_) {
                            setState(() => _isInteracting = false);
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ProfileBannerLayer(
                                bannerUrl: _bannerUrl,
                                localBytes: _localBytes,
                                localFilePath: _localFilePath,
                                layout: _layout,
                                animate: true,
                              ),
                              IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: _isInteracting ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 140),
                                  child: CustomPaint(
                                    painter: _RuleOfThirdsGridPainter(),
                                  ),
                                ),
                              ),
                              IgnorePointer(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    20,
                                    topContentPadding,
                                    20,
                                    28,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AvatarWithStatus(
                                          userId: widget.userId,
                                          avatarUrl: widget.avatarUrl,
                                          name: widget.displayName,
                                          radius: 48,
                                          isOnline: false,
                                          decorationOverride: themeProvider
                                              .currentAvatarDecoration,
                                          showDecoration: true,
                                          animateDecoration: true,
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              widget.displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 21,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -0.3,
                                                color: onHeroForeground,
                                              ),
                                            ),
                                            if (activeStatus != null) ...[
                                              const SizedBox(width: 6),
                                              EmojiStatusBadge(
                                                status: activeStatus,
                                                size: 19,
                                                animate: true,
                                                interactive: false,
                                                fallbackColor: onHeroForeground,
                                              ),
                                            ],
                                            if (themeProvider
                                                    .currentVisibleBadge !=
                                                null)
                                              PeerBadgesRow(
                                                isBot: false,
                                                isVerified: false,
                                                badge: themeProvider
                                                    .currentVisibleBadge,
                                                interactiveBadge: false,
                                                accentColor: accentColor,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          translateOrFallback(
                                            context,
                                            'profile_online',
                                            'online',
                                          ),
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                            color: onHeroSubtitle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 6,
                                left: 16,
                                right: 16,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.28,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        translateOrFallback(
                                          context,
                                          'bannerDragZoomHint',
                                          'Drag and pinch to position banner',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
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
                  },
                ),
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.only(
                      top: 6,
                      bottom: 96 + mediaQuery.padding.bottom,
                    ),
                    children: [
                      ProfileGlassSection(
                        glassEnabled: glassEnabled,
                        isLite: isLite,
                        isDarkBackdrop: isDarkBackdrop,
                        accentColor: accentColor,
                        dividerIndent: 16,
                        children: [
                          _buildHeightSelector(
                            isDarkBackdrop: isDarkBackdrop,
                            accentColor: accentColor,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                          ),
                          _buildSliderControl(
                            sliderKey: const ValueKey<String>(
                              'banner_scale_slider',
                            ),
                            label: translateOrFallback(
                              context,
                              'bannerZoomLabel',
                              'Zoom',
                            ),
                            valueLabel: '${_layout.scale.toStringAsFixed(1)}×',
                            value: _layout.scale,
                            min: 1.0,
                            max: 3.0,
                            onChanged: (v) {
                              setState(() {
                                _layout = _layout.copyWith(scale: v);
                              });
                            },
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                            accentColor: accentColor,
                            isDarkBackdrop: isDarkBackdrop,
                          ),
                          _buildSliderControl(
                            sliderKey: const ValueKey<String>(
                              'banner_dim_slider',
                            ),
                            label: translateOrFallback(
                              context,
                              'bannerDimLabel',
                              'Dimming',
                            ),
                            valueLabel: '${(_layout.dim * 100).round()}%',
                            value: _layout.dim,
                            min: 0.0,
                            max: 0.75,
                            onChanged: (v) {
                              setState(() {
                                _layout = _layout.copyWith(dim: v);
                              });
                            },
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                            accentColor: accentColor,
                            isDarkBackdrop: isDarkBackdrop,
                          ),
                          _buildSliderControl(
                            sliderKey: const ValueKey<String>(
                              'banner_blur_slider',
                            ),
                            label: translateOrFallback(
                              context,
                              'bannerBlurLabel',
                              'Blur',
                            ),
                            valueLabel: '${_layout.blur.round()}',
                            value: _layout.blur,
                            min: 0.0,
                            max: 20.0,
                            onChanged: (v) {
                              setState(() {
                                _layout = _layout.copyWith(blur: v);
                              });
                            },
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                            accentColor: accentColor,
                            isDarkBackdrop: isDarkBackdrop,
                          ),
                          ListTile(
                            key: const ValueKey<String>(
                              'banner_editor_pick_another_row',
                            ),
                            leading: iconoir.MediaImage(
                              width: 22,
                              height: 22,
                              color: primaryText,
                            ),
                            title: Text(
                              translateOrFallback(
                                context,
                                'bannerReplace',
                                'Choose Another Image',
                              ),
                            ),
                            trailing: iconoir.NavArrowRight(
                              width: 18,
                              height: 18,
                              color: secondaryText,
                            ),
                            onTap: _isSaving ? null : _pickReplacementImage,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const ChatBottomScrollEdge(height: 76),
            Positioned(
              left: 16,
              right: 16,
              bottom: math.max(12.0, mediaQuery.padding.bottom + 8.0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const ValueKey<String>('banner_editor_save_btn'),
                  onPressed: _isSaving ? null : _saveBanner,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          translateOrFallback(
                            context,
                            'bannerSave',
                            'Save Banner',
                          ),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              top: topPadding + 8.0,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ProfileFloatingBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                    glassEnabled: glassEnabled,
                    isLite: isLite,
                    isDarkBackdrop: isDarkBackdrop,
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: _buildFloatingTitlePill(
                        title: translateOrFallback(
                          context,
                          'bannerAdjust',
                          'Adjust Banner',
                        ),
                        glassEnabled: glassEnabled,
                        isLite: isLite,
                        isDarkBackdrop: isDarkBackdrop,
                      ),
                    ),
                  ),
                  _buildFloatingActionCircle(
                    buttonKey: const ValueKey<String>('banner_editor_reset_btn'),
                    glassEnabled: glassEnabled,
                    isLite: isLite,
                    isDarkBackdrop: isDarkBackdrop,
                    tooltip: translateOrFallback(
                      context,
                      'customizationReset',
                      'Reset',
                    ),
                    onTap: _resetLayout,
                    icon: iconoir.RefreshDouble(
                      width: 19,
                      height: 19,
                      color: isDarkBackdrop
                          ? Colors.white.withValues(alpha: 0.94)
                          : const Color(0xFF1C1C1E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleOfThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.75;

    final thirdW = size.width / 3;
    final thirdH = size.height / 3;
    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, size.height), paint);
    canvas.drawLine(
      Offset(thirdW * 2, 0),
      Offset(thirdW * 2, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, thirdH), Offset(size.width, thirdH), paint);
    canvas.drawLine(
      Offset(0, thirdH * 2),
      Offset(size.width, thirdH * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
