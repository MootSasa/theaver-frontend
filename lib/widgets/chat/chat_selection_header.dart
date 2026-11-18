import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';
import '../tiling/tile_viewport_scope.dart';

String _tr(
  BuildContext context,
  String key,
  String fallback, [
  Map<String, String>? params,
]) {
  final translated = AppLocalizations.of(context)?.translate(key, params);
  if (translated == null || translated.isEmpty || translated == key) {
    var result = fallback;
    params?.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }
  return translated;
}

/// Telegram-style vertical rolling counter for selected chats (`Выбрано: N` or compact `N`).
class AnimatedRollingCountText extends StatefulWidget {
  final int count;
  final bool compact;
  final TextStyle? style;

  const AnimatedRollingCountText({
    super.key,
    required this.count,
    this.compact = false,
    this.style,
  });

  @override
  State<AnimatedRollingCountText> createState() =>
      _AnimatedRollingCountTextState();
}

class _AnimatedRollingCountTextState extends State<AnimatedRollingCountText> {
  late int _prevCount;
  bool _goingUp = true;

  @override
  void initState() {
    super.initState();
    _prevCount = widget.count;
  }

  @override
  void didUpdateWidget(covariant AnimatedRollingCountText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != _prevCount) {
      _goingUp = widget.count >= _prevCount;
      _prevCount = widget.count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.compact
        ? '${widget.count}'
        : _tr(
            context,
            'selection_count_label',
            'Выбрано: ${widget.count}',
            {'count': '${widget.count}'},
          );
    final keyStr = '${widget.compact ? 'c' : 'f'}_${widget.count}';

    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.center,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == ValueKey<String>(keyStr);
          final beginOffset = isIncoming
              ? Offset(0.0, _goingUp ? 0.65 : -0.65)
              : Offset(0.0, _goingUp ? -0.65 : 0.65);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(keyStr),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      ),
    ),
  );
  }
}

/// Telegram-style vertical top-to-bottom title switcher (`сверху вниз`) for header navigation.
/// Incoming title slides down from above (`-0.85 -> 0.0`) while outgoing title slides down
/// toward the bottom (`0.0 -> +0.85`) in synchronized lockstep.
class AnimatedVerticalTitleText extends StatelessWidget {
  final String title;
  final String titleKey;
  final TextStyle style;
  final double width;
  final double height;
  final double horizontalPadding;

  const AnimatedVerticalTitleText({
    super.key,
    required this.title,
    required this.titleKey,
    required this.style,
    required this.width,
    required this.height,
    this.horizontalPadding = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final effectiveKey = ValueKey<String>('${titleKey}_$title');
    final maxTextWidth = math.max(40.0, width - horizontalPadding * 2);

    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (final prev in previousChildren)
                  OverflowBox(
                    minWidth: 0,
                    maxWidth: math.max(maxTextWidth, 280.0),
                    minHeight: 0,
                    maxHeight: height,
                    alignment: Alignment.center,
                    child: prev,
                  ),
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            final isIncoming = child.key == effectiveKey;
            final beginOffset = isIncoming
                ? const Offset(0.0, -0.85)
                : const Offset(0.0, 0.85);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: beginOffset,
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: ConstrainedBox(
            key: effectiveKey,
            constraints: BoxConstraints(maxWidth: maxTextWidth),
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}

/// Descriptor for an action item inside an adaptive morph dropdown menu.
class SelectionMorphMenuItem {
  final String id;
  final String label;
  final Widget Function(Color color, double size) iconBuilder;
  final Color? color;

  const SelectionMorphMenuItem({
    required this.id,
    required this.label,
    required this.iconBuilder,
    this.color,
  });
}

/// Quick action bar & overflow menu configuration displayed during multi-select mode.
class SelectionQuickActionsConfig {
  final bool canPin;
  final bool isUnpin;
  final VoidCallback? onPin;
  final bool canMute;
  final bool isUnmute;
  final VoidCallback? onMute;
  final bool canArchive;
  final bool isUnarchive;
  final VoidCallback? onArchive;
  final bool canDelete;
  final VoidCallback? onDelete;
  final List<SelectionMorphMenuItem> overflowItems;
  final ValueChanged<String> onOverflowAction;

  const SelectionQuickActionsConfig({
    this.canPin = false,
    this.isUnpin = false,
    this.onPin,
    this.canMute = false,
    this.isUnmute = false,
    this.onMute,
    this.canArchive = false,
    this.isUnarchive = false,
    this.onArchive,
    this.canDelete = false,
    this.onDelete,
    this.overflowItems = const [],
    required this.onOverflowAction,
  });
}

/// Adaptive 3-pill floating top header supporting both normal navigation/menus
/// and animated Telegram-style multi-select morphing in Liquid Glass and Classic modes.
class ChatListAdaptiveTopBar extends StatelessWidget {
  final bool isSelectMode;
  final int selectedCount;
  final VoidCallback onCancelSelection;
  final SelectionQuickActionsConfig? selectionConfig;
  final bool isSelectionOverflowOpen;
  final ValueChanged<bool>? onSelectionOverflowOpenChanged;

  final Widget? normalLeftButton;
  final bool showBackButton;
  final VoidCallback? onBack;

  final String normalTitle;
  final String normalTitleKey;
  final bool isTitleConnected;
  final VoidCallback? onTitleTap;

  final Widget? openCenterMenu;
  final double? openCenterMenuWidth;
  final double? openCenterMenuHeight;
  final bool isCenterMenuOpen;
  final VoidCallback? onDismissCenterMenu;

  final List<SelectionMorphMenuItem> normalMenuItems;
  final ValueChanged<String>? onNormalMenuAction;
  final bool isNormalMenuOpen;
  final ValueChanged<bool>? onNormalMenuOpenChanged;

  const ChatListAdaptiveTopBar({
    super.key,
    required this.isSelectMode,
    required this.selectedCount,
    required this.onCancelSelection,
    this.selectionConfig,
    this.isSelectionOverflowOpen = false,
    this.onSelectionOverflowOpenChanged,
    this.normalLeftButton,
    this.showBackButton = false,
    this.onBack,
    required this.normalTitle,
    this.normalTitleKey = 'title',
    this.isTitleConnected = true,
    this.onTitleTap,
    this.openCenterMenu,
    this.openCenterMenuWidth,
    this.openCenterMenuHeight,
    this.isCenterMenuOpen = false,
    this.onDismissCenterMenu,
    this.normalMenuItems = const [],
    this.onNormalMenuAction,
    this.isNormalMenuOpen = false,
    this.onNormalMenuOpenChanged,
  });

  static const double _ctrlSize = 44.0;
  static const double _barRadius = _ctrlSize / 2;
  static const double _normalMenuWidth = 204.0;
  static const double _overflowMenuWidth = 232.0;

  double _measureTextWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final isGlassEnabled = glassProvider?.enabled ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = TileViewportScope.widthOf(context);
        final rawWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : fallbackWidth;
        final double totalWidth =
            (rawWidth.isFinite && rawWidth > 0) ? rawWidth : 390.0;

        final theme = Theme.of(context);
        final palette = context.theav;
        final isDark = theme.brightness == Brightness.dark;
        final textColor =
            palette.appBarForeground != Colors.transparent
                ? palette.appBarForeground
                : theme.colorScheme.onSurface;

        final double edgePadding = totalWidth < 380.0 ? 12.0 : 16.0;
        final double normalGap = totalWidth < 360.0 ? 6.0 : 8.0;
        final double selectGap = totalWidth < 360.0 ? 10.0 : 14.0;
        final double gap = isSelectMode ? selectGap : normalGap;
        final double capsuleHorizontalPadding =
            totalWidth < 360.0 ? 6.0 : 8.0;

        final cfg = selectionConfig;
        final bool showPin =
            cfg != null && cfg.canPin && cfg.onPin != null;
        final bool showMute =
            cfg != null && cfg.canMute && cfg.onMute != null;
        final bool showArchive =
            cfg != null && cfg.canArchive && cfg.onArchive != null;
        final bool showDelete =
            cfg != null && cfg.canDelete && cfg.onDelete != null;
        final bool showOverflow = cfg != null && cfg.overflowItems.isNotEmpty;

        final int visibleQuickActionsCount = [
          showPin,
          showMute,
          showArchive,
          showDelete,
          showOverflow,
        ].where((v) => v).length;

        final double maxCapsuleBudget = math.max(
          _ctrlSize,
          totalWidth - edgePadding * 2 - _ctrlSize * 2 - selectGap * 2,
        );
        final double idealIconBtnWidth = totalWidth >= 380.0 ? 44.0 : 42.0;
        final double iconBtnWidth = visibleQuickActionsCount == 0
            ? idealIconBtnWidth
            : math
                .min(
                  idealIconBtnWidth,
                  (maxCapsuleBudget - capsuleHorizontalPadding * 2) /
                      visibleQuickActionsCount,
                )
                .clamp(32.0, 46.0);

        final double capsuleWidth = visibleQuickActionsCount == 0
            ? _ctrlSize
            : math.max(
                _ctrlSize,
                visibleQuickActionsCount * iconBtnWidth +
                    capsuleHorizontalPadding * 2,
              );

        final bool hasNormalLeft =
            normalLeftButton != null || showBackButton;
        final bool showLeftControl = isSelectMode || hasNormalLeft;
        final bool showRightControl =
            isSelectMode || normalMenuItems.isNotEmpty;

        final double leftOccupied =
            showLeftControl ? (edgePadding + _ctrlSize + gap) : edgePadding;
        final double closedRightWidth = isSelectMode
            ? capsuleWidth
            : (normalMenuItems.isNotEmpty ? _ctrlSize : 0.0);
        final double rightOccupied =
            edgePadding + closedRightWidth + (showRightControl ? gap : 0.0);

        final double availableCenterSlot =
            math.max(44.0, totalWidth - leftOccupied - rightOccupied);
        final bool useCompactCounter =
            isSelectMode && availableCenterSlot < 122.0;

        const normalTitleStyle = TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        );
        const counterTextStyle = TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        );

        final double desiredCenterWidth;
        if (isSelectMode) {
          final sampleText = useCompactCounter
              ? '$selectedCount'
              : _tr(
                  context,
                  'selection_count_label',
                  'Выбрано: $selectedCount',
                  {'count': '$selectedCount'},
                );
          final pad = useCompactCounter ? 28.0 : 32.0;
          desiredCenterWidth = math.max(
            _ctrlSize,
            _measureTextWidth(context, sampleText, counterTextStyle) + pad,
          );
        } else {
          desiredCenterWidth = math.max(
            120.0,
            _measureTextWidth(context, normalTitle, normalTitleStyle) + 40.0,
          );
        }

        final bool centerMenuActive =
            !isSelectMode && isCenterMenuOpen && openCenterMenu != null;
        final bool overflowMenuActive =
            isSelectMode && isSelectionOverflowOpen && showOverflow;
        final bool normalMenuActive = !isSelectMode &&
            isNormalMenuOpen &&
            normalMenuItems.isNotEmpty;
        final bool isRightMenuActive = overflowMenuActive || normalMenuActive;

        final double centerClosedWidth = isSelectMode
            ? desiredCenterWidth.clamp(_ctrlSize, availableCenterSlot)
            : math.min(
                desiredCenterWidth,
                math.max(88.0, totalWidth - edgePadding * 2),
              );

        final double activeCenterWidth = centerMenuActive
            ? math.min(
                openCenterMenuWidth ?? 220.0,
                totalWidth - 16.0,
              )
            : centerClosedWidth;
        final double activeCenterHeight = centerMenuActive
            ? (openCenterMenuHeight ?? _ctrlSize)
            : _ctrlSize;

        final double maxCenterLeft = math.max(
          leftOccupied,
          totalWidth - rightOccupied - centerClosedWidth,
        );
        final double idealCenterLeft = (totalWidth - centerClosedWidth) / 2;
        final double selectSlotStart =
            showLeftControl ? (edgePadding + _ctrlSize) : edgePadding;
        final double selectSlotEnd =
            totalWidth - edgePadding - closedRightWidth;
        final double idealSelectCenterLeft =
            (selectSlotStart + selectSlotEnd - centerClosedWidth) / 2;
        final double centerLeft = centerMenuActive
            ? ((totalWidth - activeCenterWidth) / 2)
                .clamp(8.0, math.max(8.0, totalWidth - activeCenterWidth - 8.0))
            : (isSelectMode
                ? idealSelectCenterLeft.clamp(leftOccupied, maxCenterLeft)
                : idealCenterLeft.clamp(
                    edgePadding,
                    math.max(edgePadding, totalWidth - edgePadding - centerClosedWidth),
                  ));

        final double rightMenuWidth = overflowMenuActive
            ? math.min(_overflowMenuWidth, totalWidth - edgePadding * 2)
            : math.min(_normalMenuWidth, totalWidth - edgePadding * 2);
        final double rightMenuHeight = overflowMenuActive
            ? math.max(
                _ctrlSize,
                cfg.overflowItems.length * 44.0 + 12.0,
              )
            : (normalMenuActive
                ? math.max(_ctrlSize, normalMenuItems.length * 44.0 + 12.0)
                : _ctrlSize);

        final double rightClosedBoxWidth =
            isSelectMode ? capsuleWidth : _ctrlSize;
        final double activeRightWidth =
            isRightMenuActive ? rightMenuWidth : rightClosedBoxWidth;
        final double activeRightHeight =
            isRightMenuActive ? rightMenuHeight : _ctrlSize;

        final double barHeight = math.max(
          _ctrlSize + 4.0,
          math.max(
            centerMenuActive ? activeCenterHeight + 8.0 : 0.0,
            isRightMenuActive ? activeRightHeight + 8.0 : 0.0,
          ),
        );

        final Widget leftContent = _buildLeftPillChild(
          context,
          textColor: textColor,
        );
        final Widget centerContent = _buildCenterPillChild(
          context,
          textColor: textColor,
          titleStyle: normalTitleStyle,
          counterStyle: counterTextStyle,
          useCompactCounter: useCompactCounter,
          centerMenuActive: centerMenuActive,
          closedWidth: centerClosedWidth,
        );
        final Widget rightContent = _buildRightPillChild(
          context,
          textColor: textColor,
          iconBtnWidth: iconBtnWidth,
          capsuleHorizontalPadding: capsuleHorizontalPadding,
          capsuleWidth: capsuleWidth,
          rightMenuWidth: rightMenuWidth,
          overflowMenuActive: overflowMenuActive,
          normalMenuActive: normalMenuActive,
          showPin: showPin,
          showMute: showMute,
          showArchive: showArchive,
          showDelete: showDelete,
          showOverflow: showOverflow,
        );

        void dismissOpenMenus() {
          if (centerMenuActive) onDismissCenterMenu?.call();
          if (overflowMenuActive) onSelectionOverflowOpenChanged?.call(false);
          if (normalMenuActive) onNormalMenuOpenChanged?.call(false);
        }

        final bool anyMenuOpen = centerMenuActive || isRightMenuActive;

        if (isGlassEnabled && glassProvider != null) {
          final morphStyle = glassProvider.createStyle(
            context: context,
            cornerRadius: _barRadius,
            refractionIndex: 1.1,
            refractionWidth: 24.0,
          );
          const morphMotion = LiquidGlassMorphMotion.fluid;

          final double glassCenterBoxWidth = math.max(
            openCenterMenuWidth ?? 0.0,
            math.max(centerClosedWidth, 130.0),
          );
          final double glassCenterLeft = centerMenuActive
              ? ((totalWidth - glassCenterBoxWidth) / 2).clamp(
                  8.0,
                  math.max(8.0, totalWidth - glassCenterBoxWidth - 8.0),
                )
              : (centerLeft + centerClosedWidth / 2 - glassCenterBoxWidth / 2);

          final double glassRightBoxWidth = math.max(
            capsuleWidth,
            isSelectMode
                ? (showOverflow ? _overflowMenuWidth : capsuleWidth)
                : (normalMenuItems.isNotEmpty ? _normalMenuWidth : _ctrlSize),
          );
          final double maxOverflowHeight = showOverflow
              ? cfg.overflowItems.length * 44.0 + 12.0
              : _ctrlSize;
          final double maxNormalMenuHeight = normalMenuItems.isNotEmpty
              ? normalMenuItems.length * 44.0 + 12.0
              : _ctrlSize;
          final double glassRightBoxHeight = math.max(
            _ctrlSize,
            isSelectMode ? maxOverflowHeight : maxNormalMenuHeight,
          );

          final leftWidget = showLeftControl
              ? Positioned(
                  key: const ValueKey<String>('adaptive_left_pos'),
                  top: 2,
                  left: edgePadding,
                  child: SizedBox(
                    width: _ctrlSize,
                    height: _ctrlSize,
                    child: LiquidGlassMorph(
                      key: const ValueKey<String>('adaptive_left_morph'),
                      alignment: Alignment.topLeft,
                      motion: morphMotion,
                      smoothness: 28,
                      style: morphStyle,
                      child: leftContent,
                    ),
                  ),
                )
              : null;

          final centerWidget = AnimatedPositioned(
            key: const ValueKey<String>('adaptive_center_pos'),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: 2,
            left: glassCenterLeft,
            child: IgnorePointer(
              ignoring: isSelectMode,
              child: SizedBox(
                width: glassCenterBoxWidth,
                height: math.max(_ctrlSize, openCenterMenuHeight ?? _ctrlSize),
                child: LiquidGlassMorph(
                  key: const ValueKey<String>('adaptive_center_morph'),
                  alignment: Alignment.topCenter,
                  motion: morphMotion,
                  smoothness: 28,
                  style: morphStyle,
                  child: centerContent,
                ),
              ),
            ),
          );

          final rightWidget = showRightControl
              ? Positioned(
                  key: const ValueKey<String>('adaptive_right_pos'),
                  top: 2,
                  right: edgePadding,
                  child: SizedBox(
                    width: glassRightBoxWidth,
                    height: glassRightBoxHeight,
                    child: LiquidGlassMorph(
                      key: const ValueKey<String>('adaptive_right_morph'),
                      alignment: Alignment.topRight,
                      motion: morphMotion,
                      smoothness: 28,
                      style: morphStyle,
                      child: rightContent,
                    ),
                  ),
                )
              : null;

          final int glassCount =
              1 + (showLeftControl ? 1 : 0) + (showRightControl ? 1 : 0);

          final stack = Stack(
            clipBehavior: Clip.none,
            children: [
              if (anyMenuOpen)
                Positioned.fill(
                  key: const ValueKey<String>('adaptive_dismiss_backdrop'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: dismissOpenMenus,
                  ),
                ),
              if (leftWidget != null) leftWidget,
              if (centerMenuActive) ...[
                if (rightWidget != null) rightWidget,
                centerWidget,
              ] else if (isRightMenuActive) ...[
                centerWidget,
                if (rightWidget != null) rightWidget,
              ] else ...[
                if (rightWidget != null) rightWidget,
                centerWidget,
              ],
            ],
          );

          return SizedBox(
            width: double.infinity,
            height: barHeight,
            child: glassCount >= 2
                ? LiquidGlassBlender(
                    smoothness: 0,
                    style: morphStyle,
                    child: stack,
                  )
                : stack,
          );
        }

        // Classic Material floating pills with smooth container morphing
        final themeExt = theme.extension<TheavThemeExtension>();
        final p = themeExt?.palette;
        final barBackgroundColor = p?.surface ??
            (isDark ? const Color(0xFF2C2C2E) : Colors.white);
        final borderColor = p?.divider ??
            (isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.06));
        final double baseShadowAlpha = isDark ? 0.35 : 0.08;

        BoxDecoration pillDecoration({bool elevated = false}) => BoxDecoration(
              color: barBackgroundColor,
              borderRadius: BorderRadius.circular(_barRadius),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: (baseShadowAlpha * (elevated ? 1.0 : 0.65))
                        .clamp(0.0, 1.0),
                  ),
                  blurRadius: elevated ? 16 : 10,
                  offset: Offset(0, elevated ? 6 : 3),
                ),
              ],
            );

        final classicLeftWidget = Positioned(
          key: const ValueKey<String>('classic_left_pos'),
          top: 2,
          left: edgePadding,
          child: IgnorePointer(
            ignoring: !showLeftControl,
            child: AnimatedScale(
              scale: showLeftControl ? 1.0 : 0.72,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: showLeftControl ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: _ctrlSize,
                  height: _ctrlSize,
                  decoration: pillDecoration(),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: leftContent,
                  ),
                ),
              ),
            ),
          ),
        );

        final classicCenterWidget = AnimatedPositioned(
          key: const ValueKey<String>('classic_center_pos'),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: 2,
          left: centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: activeCenterWidth,
            height: activeCenterHeight,
            decoration: pillDecoration(elevated: centerMenuActive),
            clipBehavior: Clip.antiAlias,
            child: OverflowBox(
              minWidth: 0,
              maxWidth: math.max(activeCenterWidth, openCenterMenuWidth ?? 220),
              minHeight: 0,
              maxHeight: math.max(_ctrlSize, openCenterMenuHeight ?? _ctrlSize),
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: centerContent,
              ),
            ),
          ),
        );

        final classicRightWidget = showRightControl
            ? Positioned(
                key: const ValueKey<String>('classic_right_pos'),
                top: 2,
                right: edgePadding,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: activeRightWidth,
                  height: activeRightHeight,
                  decoration: pillDecoration(elevated: isRightMenuActive),
                  clipBehavior: Clip.antiAlias,
                  child: OverflowBox(
                    minWidth: 0,
                    maxWidth: math.max(
                      activeRightWidth,
                      math.max(capsuleWidth, rightMenuWidth),
                    ),
                    minHeight: 0,
                    maxHeight: math.max(_ctrlSize, rightMenuHeight),
                    alignment: Alignment.topRight,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: rightContent,
                    ),
                  ),
                ),
              )
            : null;

        return SizedBox(
          width: double.infinity,
          height: barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (anyMenuOpen)
                Positioned.fill(
                  key: const ValueKey<String>('classic_dismiss_backdrop'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: dismissOpenMenus,
                  ),
                ),
              classicLeftWidget,
              if (centerMenuActive) ...[
                if (classicRightWidget != null) classicRightWidget,
                classicCenterWidget,
              ] else if (isRightMenuActive) ...[
                classicCenterWidget,
                if (classicRightWidget != null) classicRightWidget,
              ] else ...[
                if (classicRightWidget != null) classicRightWidget,
                classicCenterWidget,
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeftPillChild(
    BuildContext context, {
    required Color textColor,
  }) {
    if (isSelectMode) {
      return Semantics(
        button: true,
        label: _tr(context, 'common_cancel', 'Отмена'),
        child: Tooltip(
          message: _tr(context, 'common_cancel', 'Отмена'),
          child: GestureDetector(
            key: const ValueKey<String>('left_cancel_selection'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticUtils.tap();
              onCancelSelection();
            },
            child: SizedBox(
              width: _ctrlSize,
              height: _ctrlSize,
              child: Center(
                child: iconoir.Xmark(
                  width: 20,
                  height: 20,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (normalLeftButton != null) {
      return KeyedSubtree(
        key: const ValueKey<String>('left_custom_btn'),
        child: normalLeftButton!,
      );
    }

    if (showBackButton) {
      return GestureDetector(
        key: const ValueKey<String>('left_back_btn'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.tap();
          if (onBack != null) {
            onBack!();
          } else {
            Navigator.of(context).maybePop();
          }
        },
        child: SizedBox(
          width: _ctrlSize,
          height: _ctrlSize,
          child: Center(
            child: iconoir.NavArrowLeft(
              width: 22,
              height: 22,
              color: textColor,
            ),
          ),
        ),
      );
    }

    return const SizedBox(
      key: ValueKey<String>('left_empty'),
      width: _ctrlSize,
      height: _ctrlSize,
    );
  }

  Widget _buildCenterPillChild(
    BuildContext context, {
    required Color textColor,
    required TextStyle titleStyle,
    required TextStyle counterStyle,
    required bool useCompactCounter,
    required bool centerMenuActive,
    required double closedWidth,
  }) {
    if (isSelectMode) {
      return Container(
        key: ValueKey<String>(
          'center_select_counter_${useCompactCounter ? 'compact' : 'full'}',
        ),
        width: closedWidth,
        height: _ctrlSize,
        padding: EdgeInsets.symmetric(horizontal: useCompactCounter ? 10 : 14),
        alignment: Alignment.center,
        child: AnimatedRollingCountText(
          count: selectedCount,
          compact: useCompactCounter,
          style: counterStyle.copyWith(color: textColor),
        ),
      );
    }

    if (centerMenuActive && openCenterMenu != null) {
      return KeyedSubtree(
        key: const ValueKey<String>('center_folder_menu'),
        child: openCenterMenu!,
      );
    }

    final displayColor = isTitleConnected ? textColor : Colors.grey;

    return GestureDetector(
      key: const ValueKey<String>('center_normal_title'),
      behavior: HitTestBehavior.opaque,
      onTap: onTitleTap,
      child: AnimatedVerticalTitleText(
        title: normalTitle,
        titleKey: normalTitleKey,
        style: titleStyle.copyWith(color: displayColor),
        width: closedWidth,
        height: _ctrlSize,
      ),
    );
  }

  Widget _buildRightPillChild(
    BuildContext context, {
    required Color textColor,
    required double iconBtnWidth,
    required double capsuleHorizontalPadding,
    required double capsuleWidth,
    required double rightMenuWidth,
    required bool overflowMenuActive,
    required bool normalMenuActive,
    required bool showPin,
    required bool showMute,
    required bool showArchive,
    required bool showDelete,
    required bool showOverflow,
  }) {
    final cfg = selectionConfig;

    if (isSelectMode && cfg != null) {
      if (overflowMenuActive) {
        return _AdaptiveMorphMenu(
          key: const ValueKey<String>('right_select_overflow_menu'),
          width: rightMenuWidth,
          items: cfg.overflowItems,
          onItemTap: (id) {
            onSelectionOverflowOpenChanged?.call(false);
            cfg.onOverflowAction(id);
          },
        );
      }

      return SizedBox(
        key: const ValueKey<String>('right_select_capsule'),
        width: capsuleWidth,
        height: _ctrlSize,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: capsuleHorizontalPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showPin)
                _QuickActionButton(
                  width: iconBtnWidth,
                  tooltip: _tr(
                    context,
                    cfg.isUnpin ? 'selection_unpin' : 'selection_pin',
                    cfg.isUnpin ? 'Открепить' : 'Закрепить',
                  ),
                  onTap: cfg.onPin!,
                  icon: cfg.isUnpin
                      ? iconoir.PinSlash(width: 19, height: 19, color: textColor)
                      : iconoir.Pin(width: 19, height: 19, color: textColor),
                ),
              if (showMute)
                _QuickActionButton(
                  width: iconBtnWidth,
                  tooltip: _tr(
                    context,
                    cfg.isUnmute ? 'selection_unmute' : 'selection_mute',
                    cfg.isUnmute ? 'Включить звук' : 'Без звука',
                  ),
                  onTap: cfg.onMute!,
                  icon: cfg.isUnmute
                      ? iconoir.Bell(width: 19, height: 19, color: textColor)
                      : iconoir.BellOff(width: 19, height: 19, color: textColor),
                ),
              if (showArchive)
                _QuickActionButton(
                  width: iconBtnWidth,
                  tooltip: _tr(
                    context,
                    cfg.isUnarchive
                        ? 'selection_unarchive'
                        : 'selection_archive',
                    cfg.isUnarchive ? 'Из архива' : 'В архив',
                  ),
                  onTap: cfg.onArchive!,
                  icon: cfg.isUnarchive
                      ? Icon(
                          Icons.unarchive_outlined,
                          size: 20,
                          color: textColor,
                        )
                      : iconoir.Archive(
                          width: 19,
                          height: 19,
                          color: textColor,
                        ),
                ),
              if (showDelete)
                _QuickActionButton(
                  width: iconBtnWidth,
                  tooltip: _tr(context, 'selection_delete', 'Удалить'),
                  onTap: cfg.onDelete!,
                  icon: const iconoir.Trash(
                    width: 19,
                    height: 19,
                    color: Colors.redAccent,
                  ),
                ),
              if (showOverflow)
                _QuickActionButton(
                  width: iconBtnWidth,
                  tooltip: 'Ещё',
                  onTap: () {
                    HapticUtils.tap();
                    onSelectionOverflowOpenChanged?.call(true);
                  },
                  icon: iconoir.MoreVert(
                    width: 20,
                    height: 20,
                    color: textColor,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (normalMenuActive) {
      return _AdaptiveMorphMenu(
        key: const ValueKey<String>('right_normal_menu'),
        width: rightMenuWidth,
        items: normalMenuItems,
        onItemTap: (id) {
          onNormalMenuOpenChanged?.call(false);
          onNormalMenuAction?.call(id);
        },
      );
    }

    return GestureDetector(
      key: const ValueKey<String>('right_normal_dots'),
      behavior: HitTestBehavior.opaque,
      onTap: normalMenuItems.isNotEmpty
          ? () {
              HapticUtils.tap();
              onNormalMenuOpenChanged?.call(!isNormalMenuOpen);
            }
          : null,
      child: SizedBox(
        width: _ctrlSize,
        height: _ctrlSize,
        child: Center(
          child: iconoir.MoreVert(
            width: 22.0,
            height: 22.0,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final double width;
  final String tooltip;
  final VoidCallback onTap;
  final Widget icon;

  const _QuickActionButton({
    required this.width,
    required this.tooltip,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticUtils.tap();
            onTap();
          },
          child: SizedBox(
            width: width,
            height: ChatListAdaptiveTopBar._ctrlSize,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveMorphMenu extends StatelessWidget {
  final double width;
  final List<SelectionMorphMenuItem> items;
  final ValueChanged<String> onItemTap;

  const _AdaptiveMorphMenu({
    super.key,
    required this.width,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final defaultColor = palette.onSurface;
    final totalHeight = items.length * 44.0 + 12.0;

    return SizedBox(
      width: width,
      height: totalHeight,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: totalHeight,
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    GestureDetector(
                      key: ValueKey<String>('morph_menu_${item.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticUtils.tap();
                        onItemTap(item.id);
                      },
                      child: SizedBox(
                        height: 44.0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0),
                          child: Row(
                            children: [
                              item.iconBuilder(
                                item.color ?? defaultColor,
                                20.0,
                              ),
                              const SizedBox(width: 10.0),
                              Expanded(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.0,
                                    fontWeight: FontWeight.w500,
                                    color: item.color ?? defaultColor,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram Variant A 2-island `44dp` floating header for message multi-select mode.
///
/// Renders strictly two floating islands without a middle chat-title pill:
/// 1. Left pill (`44dp` height): `[✕  Выбрано: N]` (tapping cancels selection)
/// 2. Right pill (`44dp` height): `[Reply? | Copy? | Pin? | Forward? | Delete]`
///
/// When [hasProtectedContent] is `true`, both `Copy` and `Forward` actions are omitted.
class ChatMessageSelectionHeader extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onPin;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final bool hasProtectedContent;

  const ChatMessageSelectionHeader({
    super.key,
    required this.selectedCount,
    required this.onCancel,
    this.onReply,
    this.onCopy,
    this.onPin,
    this.onForward,
    this.onDelete,
    this.hasProtectedContent = false,
  });

  static const double barHeight = 44.0;
  static const double _actionBtnWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final primaryFg = palette.appBarForeground != Colors.transparent
        ? palette.appBarForeground
        : palette.onSurface;
    final deleteFg = palette.error;

    final effectiveCopy = hasProtectedContent ? null : onCopy;
    final effectiveForward = hasProtectedContent ? null : onForward;

    final actions = <_SelectionHeaderActionSpec>[
      if (onReply != null)
        _SelectionHeaderActionSpec(
          key: const ValueKey<String>('msg_sel_action_reply'),
          tooltip: _tr(context, 'reply', 'Ответить'),
          onTap: onReply!,
          icon: iconoir.Reply(
            width: 20,
            height: 20,
            color: primaryFg,
          ),
        ),
      if (effectiveCopy != null)
        _SelectionHeaderActionSpec(
          key: const ValueKey<String>('msg_sel_action_copy'),
          tooltip: _tr(context, 'copy', 'Копировать'),
          onTap: effectiveCopy,
          icon: iconoir.Copy(
            width: 20,
            height: 20,
            color: primaryFg,
          ),
        ),
      if (onPin != null)
        _SelectionHeaderActionSpec(
          key: const ValueKey<String>('msg_sel_action_pin'),
          tooltip: _tr(context, 'selection_pin', 'Закрепить'),
          onTap: onPin!,
          icon: iconoir.Pin(
            width: 20,
            height: 20,
            color: primaryFg,
          ),
        ),
      if (effectiveForward != null)
        _SelectionHeaderActionSpec(
          key: const ValueKey<String>('msg_sel_action_forward'),
          tooltip: _tr(context, 'forward', 'Переслать'),
          onTap: effectiveForward,
          icon: iconoir.ForwardMessage(
            width: 20,
            height: 20,
            color: primaryFg,
          ),
        ),
      if (onDelete != null)
        _SelectionHeaderActionSpec(
          key: const ValueKey<String>('msg_sel_action_delete'),
          tooltip: _tr(context, 'selection_delete', 'Удалить'),
          onTap: onDelete!,
          icon: iconoir.Trash(
            width: 20,
            height: 20,
            color: deleteFg,
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = TileViewportScope.widthOf(context);
        final maxWidth = constraints.hasBoundedWidth && constraints.maxWidth > 0
            ? constraints.maxWidth
            : fallbackWidth;

        final rightCapsuleWidth = actions.isEmpty
            ? barHeight
            : math.max(barHeight, actions.length * _actionBtnWidth + 12.0);
        final remainingForLeft = math.max(88.0, maxWidth - rightCapsuleWidth - 10.0);
        final bool useCompactLeft = remainingForLeft < 152.0;

        return SizedBox(
          height: barHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: remainingForLeft),
                child: SizedBox(
                  key: const ValueKey<String>('chat_message_selection_left_island'),
                  height: barHeight,
                  child: TheavFloatingSurface(
                    borderRadius: barHeight / 2,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(barHeight / 2),
                        onTap: () {
                          HapticUtils.tap();
                          onCancel();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              iconoir.Xmark(
                                width: 20,
                                height: 20,
                                color: primaryFg,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: AnimatedRollingCountText(
                                  count: selectedCount,
                                  compact: useCompactLeft,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: primaryFg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (actions.isNotEmpty)
                SizedBox(
                  key: const ValueKey<String>('chat_message_selection_right_island'),
                  height: barHeight,
                  child: TheavFloatingSurface(
                    borderRadius: barHeight / 2,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in actions)
                          Tooltip(
                            message: action.tooltip,
                            child: Semantics(
                              button: true,
                              label: action.tooltip,
                              child: Material(
                                key: action.key,
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(barHeight / 2),
                                  onTap: () {
                                    HapticUtils.tap();
                                    action.onTap();
                                  },
                                  child: SizedBox(
                                    width: _actionBtnWidth,
                                    height: barHeight,
                                    child: Center(child: action.icon),
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
        );
      },
    );
  }
}

class _SelectionHeaderActionSpec {
  final Key key;
  final String tooltip;
  final VoidCallback onTap;
  final Widget icon;

  const _SelectionHeaderActionSpec({
    required this.key,
    required this.tooltip,
    required this.onTap,
    required this.icon,
  });
}
