import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
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
  final Alignment alignment;

  const AnimatedRollingCountText({
    super.key,
    required this.count,
    this.compact = false,
    this.style,
    this.alignment = Alignment.center,
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
            alignment: widget.alignment,
            clipBehavior: Clip.hardEdge,
            children: [
              for (final prev in previousChildren)
                Positioned.fill(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: widget.alignment,
                      minWidth: 0.0,
                      maxWidth: double.infinity,
                      child: prev,
                    ),
                  ),
                ),
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

        final double expandedCenterWidth = math.min(
          openCenterMenuWidth ?? 220.0,
          totalWidth - 16.0,
        );
        final double expandedCenterHeight = openCenterMenuHeight ?? _ctrlSize;
        final double expandedCenterLeft = ((totalWidth - expandedCenterWidth) / 2)
            .clamp(8.0, math.max(8.0, totalWidth - expandedCenterWidth - 8.0));

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
        final double closedCenterLeft = isSelectMode
            ? idealSelectCenterLeft.clamp(leftOccupied, maxCenterLeft)
            : idealCenterLeft.clamp(
                edgePadding,
                math.max(edgePadding, totalWidth - edgePadding - centerClosedWidth),
              );
        final double centerLeft =
            centerMenuActive ? expandedCenterLeft : closedCenterLeft;

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
        final double activeCenterHeight =
            centerMenuActive ? expandedCenterHeight : _ctrlSize;
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

        void dismissOpenMenus() {
          if (centerMenuActive) onDismissCenterMenu?.call();
          if (overflowMenuActive) onSelectionOverflowOpenChanged?.call(false);
          if (normalMenuActive) onNormalMenuOpenChanged?.call(false);
        }

        final bool anyMenuOpen = centerMenuActive || isRightMenuActive;

        if (isGlassEnabled && glassProvider != null) {
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
            child: LiquidGlassBatch(
              child: stack,
            ),
          );
        }

        final bool reduceMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final Widget closedCenterContent = _buildClosedCenterPillChild(
          context,
          textColor: textColor,
          titleStyle: normalTitleStyle,
          counterStyle: counterTextStyle,
          useCompactCounter: useCompactCounter,
          closedWidth: centerClosedWidth,
        );
        final Widget closedRightContent = _buildClosedRightPillChild(
          context,
          textColor: textColor,
          iconBtnWidth: iconBtnWidth,
          capsuleHorizontalPadding: capsuleHorizontalPadding,
          capsuleWidth: capsuleWidth,
          showPin: showPin,
          showMute: showMute,
          showArchive: showArchive,
          showDelete: showDelete,
          showOverflow: showOverflow,
        );
        final Widget? expandedRightMenu = _buildExpandedRightMenu(
          cfg: cfg,
          rightMenuWidth: rightMenuWidth,
          overflowMenuActive: overflowMenuActive,
          normalMenuActive: normalMenuActive,
        );

        return _ClassicAdaptiveTopBarBody(
          reduceMotion: reduceMotion,
          edgePadding: edgePadding,
          showLeftControl: showLeftControl,
          showRightControl: showRightControl,
          closedCenterWidth: centerClosedWidth,
          closedCenterLeft: closedCenterLeft,
          expandedCenterWidth: expandedCenterWidth,
          expandedCenterHeight: expandedCenterHeight,
          expandedCenterLeft: expandedCenterLeft,
          centerMenuActive: centerMenuActive,
          closedRightWidth: rightClosedBoxWidth,
          expandedRightMenuWidth: rightMenuWidth,
          expandedRightMenuHeight: rightMenuHeight,
          isRightMenuActive: isRightMenuActive,
          leftContent: leftContent,
          closedCenterContent: closedCenterContent,
          openCenterMenu: openCenterMenu,
          closedRightContent: closedRightContent,
          expandedRightMenu: expandedRightMenu,
          onDismissOpenMenus: dismissOpenMenus,
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

  Widget _buildClosedCenterPillChild(
    BuildContext context, {
    required Color textColor,
    required TextStyle titleStyle,
    required TextStyle counterStyle,
    required bool useCompactCounter,
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

  Widget _buildCenterPillChild(
    BuildContext context, {
    required Color textColor,
    required TextStyle titleStyle,
    required TextStyle counterStyle,
    required bool useCompactCounter,
    required bool centerMenuActive,
    required double closedWidth,
  }) {
    if (!isSelectMode && centerMenuActive && openCenterMenu != null) {
      return KeyedSubtree(
        key: const ValueKey<String>('center_folder_menu'),
        child: openCenterMenu!,
      );
    }

    return _buildClosedCenterPillChild(
      context,
      textColor: textColor,
      titleStyle: titleStyle,
      counterStyle: counterStyle,
      useCompactCounter: useCompactCounter,
      closedWidth: closedWidth,
    );
  }

  Widget? _buildExpandedRightMenu({
    required SelectionQuickActionsConfig? cfg,
    required double rightMenuWidth,
    required bool overflowMenuActive,
    required bool normalMenuActive,
  }) {
    if (isSelectMode && cfg != null && overflowMenuActive) {
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

    if (!isSelectMode && normalMenuActive) {
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

    return null;
  }

  Widget _buildClosedRightPillChild(
    BuildContext context, {
    required Color textColor,
    required double iconBtnWidth,
    required double capsuleHorizontalPadding,
    required double capsuleWidth,
    required bool showPin,
    required bool showMute,
    required bool showArchive,
    required bool showDelete,
    required bool showOverflow,
  }) {
    final cfg = selectionConfig;

    if (isSelectMode && cfg != null) {
      return SizedBox(
        key: const ValueKey<String>('right_select_capsule'),
        width: capsuleWidth,
        height: _ctrlSize,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: capsuleHorizontalPadding),
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
        ),
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
    final expanded = _buildExpandedRightMenu(
      cfg: cfg,
      rightMenuWidth: rightMenuWidth,
      overflowMenuActive: overflowMenuActive,
      normalMenuActive: normalMenuActive,
    );
    if (expanded != null) {
      return expanded;
    }

    return _buildClosedRightPillChild(
      context,
      textColor: textColor,
      iconBtnWidth: iconBtnWidth,
      capsuleHorizontalPadding: capsuleHorizontalPadding,
      capsuleWidth: capsuleWidth,
      showPin: showPin,
      showMute: showMute,
      showArchive: showArchive,
      showDelete: showDelete,
      showOverflow: showOverflow,
    );
  }
}

enum _ClassicMenuSlot { none, center, right }

/// Stateful Classic/Material morph host for [ChatListAdaptiveTopBar].
///
/// Uses explicit [AnimationController]s matching [ProfileSectionPill] and
/// `_classicCreateMenuController` kinematics so center folder and right overflow
/// cards expand/collapse smoothly in lockstep while keeping collapsed headers
/// pinned to their top origin instead of cross-fading at vertical center.
class _ClassicAdaptiveTopBarBody extends StatefulWidget {
  final bool reduceMotion;
  final double edgePadding;
  final bool showLeftControl;
  final bool showRightControl;
  final double closedCenterWidth;
  final double closedCenterLeft;
  final double expandedCenterWidth;
  final double expandedCenterHeight;
  final double expandedCenterLeft;
  final bool centerMenuActive;
  final double closedRightWidth;
  final double expandedRightMenuWidth;
  final double expandedRightMenuHeight;
  final bool isRightMenuActive;
  final Widget leftContent;
  final Widget closedCenterContent;
  final Widget? openCenterMenu;
  final Widget closedRightContent;
  final Widget? expandedRightMenu;
  final VoidCallback onDismissOpenMenus;

  const _ClassicAdaptiveTopBarBody({
    required this.reduceMotion,
    required this.edgePadding,
    required this.showLeftControl,
    required this.showRightControl,
    required this.closedCenterWidth,
    required this.closedCenterLeft,
    required this.expandedCenterWidth,
    required this.expandedCenterHeight,
    required this.expandedCenterLeft,
    required this.centerMenuActive,
    required this.closedRightWidth,
    required this.expandedRightMenuWidth,
    required this.expandedRightMenuHeight,
    required this.isRightMenuActive,
    required this.leftContent,
    required this.closedCenterContent,
    required this.openCenterMenu,
    required this.closedRightContent,
    required this.expandedRightMenu,
    required this.onDismissOpenMenus,
  });

  @override
  State<_ClassicAdaptiveTopBarBody> createState() =>
      _ClassicAdaptiveTopBarBodyState();
}

class _ClassicAdaptiveTopBarBodyState extends State<_ClassicAdaptiveTopBarBody>
    with TickerProviderStateMixin {
  late final AnimationController _centerMorphController;
  late final AnimationController _rightMorphController;
  late final Animation<double> _centerMorphAnimation;
  late final Animation<double> _rightMorphAnimation;

  Widget? _cachedCenterMenu;
  double _cachedCenterMenuWidth = 220.0;
  double _cachedCenterMenuHeight = ChatListAdaptiveTopBar._ctrlSize;
  double _cachedExpandedCenterLeft = 0.0;

  Widget? _cachedRightMenu;
  double _cachedRightMenuWidth = ChatListAdaptiveTopBar._normalMenuWidth;
  double _cachedRightMenuHeight = ChatListAdaptiveTopBar._ctrlSize;

  _ClassicMenuSlot _lastActiveMenuSlot = _ClassicMenuSlot.none;
  bool _allowCenterClosedAnim = false;
  bool _allowRightClosedAnim = false;

  @override
  void initState() {
    super.initState();
    _centerMorphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      value: widget.centerMenuActive ? 1.0 : 0.0,
    )..addStatusListener(_handleCenterStatusChanged);
    _centerMorphAnimation = CurvedAnimation(
      parent: _centerMorphController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _rightMorphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      value: widget.isRightMenuActive ? 1.0 : 0.0,
    )..addStatusListener(_handleRightStatusChanged);
    _rightMorphAnimation = CurvedAnimation(
      parent: _rightMorphController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (widget.centerMenuActive && widget.openCenterMenu != null) {
      _cacheCenterMenu();
      _lastActiveMenuSlot = _ClassicMenuSlot.center;
    }
    if (widget.isRightMenuActive && widget.expandedRightMenu != null) {
      _cacheRightMenu();
      _lastActiveMenuSlot = _ClassicMenuSlot.right;
    }
  }

  void _cacheCenterMenu() {
    _cachedCenterMenu = widget.openCenterMenu;
    _cachedCenterMenuWidth = widget.expandedCenterWidth;
    _cachedCenterMenuHeight = widget.expandedCenterHeight;
    _cachedExpandedCenterLeft = widget.expandedCenterLeft;
  }

  void _cacheRightMenu() {
    _cachedRightMenu = widget.expandedRightMenu;
    _cachedRightMenuWidth = widget.expandedRightMenuWidth;
    _cachedRightMenuHeight = widget.expandedRightMenuHeight;
  }

  void _handleCenterStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && !widget.centerMenuActive) {
      setState(() {
        _cachedCenterMenu = null;
        if (_lastActiveMenuSlot == _ClassicMenuSlot.center) {
          _lastActiveMenuSlot = widget.isRightMenuActive
              ? _ClassicMenuSlot.right
              : _ClassicMenuSlot.none;
        }
      });
    }
  }

  void _handleRightStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && !widget.isRightMenuActive) {
      setState(() {
        _cachedRightMenu = null;
        if (_lastActiveMenuSlot == _ClassicMenuSlot.right) {
          _lastActiveMenuSlot = widget.centerMenuActive
              ? _ClassicMenuSlot.center
              : _ClassicMenuSlot.none;
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ClassicAdaptiveTopBarBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.centerMenuActive && widget.openCenterMenu != null) {
      _cacheCenterMenu();
    }
    if (widget.isRightMenuActive && widget.expandedRightMenu != null) {
      _cacheRightMenu();
    }

    if (widget.centerMenuActive != oldWidget.centerMenuActive) {
      _allowCenterClosedAnim = false;
      if (widget.centerMenuActive) {
        _lastActiveMenuSlot = _ClassicMenuSlot.center;
        if (widget.reduceMotion) {
          _centerMorphController.value = 1.0;
        } else {
          _centerMorphController.forward();
        }
      } else {
        if (widget.reduceMotion) {
          _centerMorphController.value = 0.0;
          _cachedCenterMenu = null;
          if (_lastActiveMenuSlot == _ClassicMenuSlot.center) {
            _lastActiveMenuSlot = widget.isRightMenuActive
                ? _ClassicMenuSlot.right
                : _ClassicMenuSlot.none;
          }
        } else {
          _centerMorphController.reverse();
        }
      }
    } else if (!widget.centerMenuActive &&
        _centerMorphController.isDismissed &&
        (widget.closedCenterWidth != oldWidget.closedCenterWidth ||
            widget.closedCenterLeft != oldWidget.closedCenterLeft)) {
      _allowCenterClosedAnim = true;
    }

    if (widget.isRightMenuActive != oldWidget.isRightMenuActive) {
      _allowRightClosedAnim = false;
      if (widget.isRightMenuActive) {
        _lastActiveMenuSlot = _ClassicMenuSlot.right;
        if (widget.reduceMotion) {
          _rightMorphController.value = 1.0;
        } else {
          _rightMorphController.forward();
        }
      } else {
        if (widget.reduceMotion) {
          _rightMorphController.value = 0.0;
          _cachedRightMenu = null;
          if (_lastActiveMenuSlot == _ClassicMenuSlot.right) {
            _lastActiveMenuSlot = widget.centerMenuActive
                ? _ClassicMenuSlot.center
                : _ClassicMenuSlot.none;
          }
        } else {
          _rightMorphController.reverse();
        }
      }
    } else if (!widget.isRightMenuActive &&
        _rightMorphController.isDismissed &&
        widget.closedRightWidth != oldWidget.closedRightWidth) {
      _allowRightClosedAnim = true;
    }
  }

  @override
  void dispose() {
    _centerMorphController
      ..removeStatusListener(_handleCenterStatusChanged)
      ..dispose();
    _rightMorphController
      ..removeStatusListener(_handleRightStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final palette = themeExt?.palette;
    final blurEnabled = BlurUtils.shouldBlurMaterialHud(context);
    final rawBaseBg = (palette?.appBarBackground != null &&
            palette!.appBarBackground != Colors.transparent)
        ? palette.appBarBackground
        : (palette?.surface ??
            (isDark ? const Color(0xFF2C2C2E) : Colors.white));
    final barBackgroundColor = BlurUtils.resolveMaterialHudColor(
      rawBaseBg,
      isDark: isDark,
      blurEnabled: blurEnabled,
    );
    final borderColor = palette?.divider ??
        (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.06));
    final double baseShadowAlpha = isDark ? 0.35 : 0.08;

    Widget wrapFrosted(Widget child) {
      if (!blurEnabled) return child;
      return BackdropFilter.grouped(
        filter: BlurUtils.createMaterialHudBlur(sigma: 10.0),
        child: child,
      );
    }

    BoxDecoration pillDecoration({
      bool elevated = false,
      double radius = ChatListAdaptiveTopBar._barRadius,
    }) =>
        BoxDecoration(
          color: elevated && blurEnabled
              ? BlurUtils.resolveMaterialHudColor(
                  palette?.surface ?? rawBaseBg,
                  isDark: isDark,
                  blurEnabled: true,
                  darkAlpha: 0.84,
                  lightAlpha: 0.88,
                )
              : barBackgroundColor,
          borderRadius: BorderRadius.circular(radius),
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

    Widget wrapPillBorder(
      Widget child, {
      double radius = ChatListAdaptiveTopBar._barRadius,
    }) =>
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor,
              width: blurEnabled ? 0.6 : 0.5,
            ),
          ),
          child: child,
        );

    final Widget classicLeftWidget = Positioned(
      key: const ValueKey<String>('classic_left_pos'),
      top: 2,
      left: widget.edgePadding,
      child: IgnorePointer(
        ignoring: !widget.showLeftControl,
        child: AnimatedScale(
          scale: widget.showLeftControl ? 1.0 : 0.72,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: widget.showLeftControl ? 1.0 : 0.0,
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(ChatListAdaptiveTopBar._barRadius),
              child: wrapFrosted(
                Container(
                  width: ChatListAdaptiveTopBar._ctrlSize,
                  height: ChatListAdaptiveTopBar._ctrlSize,
                  decoration: pillDecoration(),
                  clipBehavior: Clip.antiAlias,
                  child: wrapPillBorder(
                    AnimatedSwitcher(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: widget.leftContent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Widget classicCenterWidget = AnimatedBuilder(
      animation: _centerMorphAnimation,
      builder: (context, _) {
        final double p = _centerMorphAnimation.value.clamp(0.0, 1.0);
        final bool isMorphActive =
            _centerMorphController.isAnimating || p > 0.001;
        final double targetExpW =
            p > 0.0 ? _cachedCenterMenuWidth : widget.expandedCenterWidth;
        final double targetExpH =
            p > 0.0 ? _cachedCenterMenuHeight : widget.expandedCenterHeight;
        final double targetExpLeft =
            p > 0.0 ? _cachedExpandedCenterLeft : widget.expandedCenterLeft;

        final double currentWidth = widget.closedCenterWidth +
            (targetExpW - widget.closedCenterWidth) * p;
        final double currentHeight = ChatListAdaptiveTopBar._ctrlSize +
            (targetExpH - ChatListAdaptiveTopBar._ctrlSize) * p;
        final double currentLeft = widget.closedCenterLeft +
            (targetExpLeft - widget.closedCenterLeft) * p;
        final double radius = ChatListAdaptiveTopBar._barRadius + 2.0 * p;

        final Duration implicitDuration =
            (widget.reduceMotion || isMorphActive || !_allowCenterClosedAnim)
                ? Duration.zero
                : const Duration(milliseconds: 240);

        final Widget? activeCenterMenu =
            _cachedCenterMenu ?? widget.openCenterMenu;

        return AnimatedPositioned(
          key: const ValueKey<String>('classic_center_pos'),
          duration: implicitDuration,
          curve: Curves.easeOutCubic,
          top: 2,
          left: currentLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: wrapFrosted(
              AnimatedContainer(
                key: const ValueKey<String>('classic_center_card'),
                duration: implicitDuration,
                curve: Curves.easeOutCubic,
                width: currentWidth,
                height: currentHeight,
                decoration: pillDecoration(
                  elevated: p > 0.05,
                  radius: radius,
                ),
                clipBehavior: Clip.antiAlias,
                child: wrapPillBorder(
                  radius: radius,
                  Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (p < 0.99)
                        OverflowBox(
                          alignment: Alignment.topCenter,
                          minWidth: widget.closedCenterWidth,
                          maxWidth: widget.closedCenterWidth,
                          minHeight: ChatListAdaptiveTopBar._ctrlSize,
                          maxHeight: ChatListAdaptiveTopBar._ctrlSize,
                          child: IgnorePointer(
                            ignoring: widget.centerMenuActive || p > 0.1,
                            child: Opacity(
                              opacity: (1.0 - p * 2.5).clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: 1.0 - 0.10 * p,
                                alignment: Alignment.topCenter,
                                child: AnimatedSwitcher(
                                  duration: widget.reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 200),
                                  child: widget.closedCenterContent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (p > 0.01 && activeCenterMenu != null)
                        OverflowBox(
                          alignment: Alignment.topCenter,
                          minWidth: targetExpW,
                          maxWidth: targetExpW,
                          minHeight: targetExpH,
                          maxHeight: targetExpH,
                          child: IgnorePointer(
                            ignoring: !widget.centerMenuActive || p < 0.8,
                            child: Opacity(
                              opacity: ((p - 0.18) / 0.82).clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: Offset(0, -8.0 * (1.0 - p)),
                                child: Transform.scale(
                                  scale: 0.94 + 0.06 * p,
                                  alignment: Alignment.topCenter,
                                  child: KeyedSubtree(
                                    key: const ValueKey<String>(
                                      'center_folder_menu',
                                    ),
                                    child: activeCenterMenu,
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
            ),
          ),
        );
      },
    );

    final bool keepRightMounted =
        widget.showRightControl || _rightMorphController.value > 0.001;
    final Widget? classicRightWidget = keepRightMounted
        ? Positioned(
            key: const ValueKey<String>('classic_right_pos'),
            top: 2,
            right: widget.edgePadding,
            child: AnimatedBuilder(
              animation: _rightMorphAnimation,
              builder: (context, _) {
                final double p = _rightMorphAnimation.value.clamp(0.0, 1.0);
                final bool isMorphActive =
                    _rightMorphController.isAnimating || p > 0.001;
                final double targetExpW = p > 0.0
                    ? _cachedRightMenuWidth
                    : widget.expandedRightMenuWidth;
                final double targetExpH = p > 0.0
                    ? _cachedRightMenuHeight
                    : widget.expandedRightMenuHeight;

                final double currentWidth = widget.closedRightWidth +
                    (targetExpW - widget.closedRightWidth) * p;
                final double currentHeight = ChatListAdaptiveTopBar._ctrlSize +
                    (targetExpH - ChatListAdaptiveTopBar._ctrlSize) * p;
                final double radius =
                    ChatListAdaptiveTopBar._barRadius + 2.0 * p;

                final Duration implicitDuration =
                    (widget.reduceMotion ||
                            isMorphActive ||
                            !_allowRightClosedAnim)
                        ? Duration.zero
                        : const Duration(milliseconds: 240);

                final Widget? activeRightMenu =
                    _cachedRightMenu ?? widget.expandedRightMenu;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: wrapFrosted(
                    AnimatedContainer(
                      key: const ValueKey<String>('classic_right_card'),
                      duration: implicitDuration,
                      curve: Curves.easeOutCubic,
                      width: currentWidth,
                      height: currentHeight,
                      decoration: pillDecoration(
                        elevated: p > 0.05,
                        radius: radius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: wrapPillBorder(
                        radius: radius,
                        Stack(
                          alignment: Alignment.topRight,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            if (p < 0.99)
                              OverflowBox(
                                alignment: Alignment.topRight,
                                minWidth: widget.closedRightWidth,
                                maxWidth: widget.closedRightWidth,
                                minHeight: ChatListAdaptiveTopBar._ctrlSize,
                                maxHeight: ChatListAdaptiveTopBar._ctrlSize,
                                child: IgnorePointer(
                                  ignoring: widget.isRightMenuActive || p > 0.1,
                                  child: Opacity(
                                    opacity: (1.0 - p * 2.5).clamp(0.0, 1.0),
                                    child: Transform.scale(
                                      scale: 1.0 - 0.12 * p,
                                      alignment: Alignment.topRight,
                                      child: AnimatedSwitcher(
                                        duration: widget.reduceMotion
                                            ? Duration.zero
                                            : const Duration(milliseconds: 200),
                                        layoutBuilder: (
                                          currentChild,
                                          previousChildren,
                                        ) {
                                          return Stack(
                                            alignment: Alignment.centerRight,
                                            children: [
                                              ...previousChildren,
                                              if (currentChild != null)
                                                currentChild,
                                            ],
                                          );
                                        },
                                        child: widget.closedRightContent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (p > 0.01 && activeRightMenu != null)
                              OverflowBox(
                                alignment: Alignment.topRight,
                                minWidth: targetExpW,
                                maxWidth: targetExpW,
                                minHeight: targetExpH,
                                maxHeight: targetExpH,
                                child: IgnorePointer(
                                  ignoring: !widget.isRightMenuActive || p < 0.8,
                                  child: Opacity(
                                    opacity: ((p - 0.18) / 0.82).clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset(0, -8.0 * (1.0 - p)),
                                      child: Transform.scale(
                                        scale: 0.94 + 0.06 * p,
                                        alignment: Alignment.topRight,
                                        child: activeRightMenu,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        : null;

    final bool anyMenuOpen = widget.centerMenuActive || widget.isRightMenuActive;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _centerMorphAnimation,
        _rightMorphAnimation,
      ]),
      builder: (context, _) {
        final double centerP = _centerMorphAnimation.value.clamp(0.0, 1.0);
        final double rightP = _rightMorphAnimation.value.clamp(0.0, 1.0);
        final double centerH = ChatListAdaptiveTopBar._ctrlSize +
            (_cachedCenterMenuHeight - ChatListAdaptiveTopBar._ctrlSize) *
                centerP;
        final double rightH = ChatListAdaptiveTopBar._ctrlSize +
            (_cachedRightMenuHeight - ChatListAdaptiveTopBar._ctrlSize) *
                rightP;
        final double barHeight = math.max(
          ChatListAdaptiveTopBar._ctrlSize + 4.0,
          math.max(
            centerP > 0.001 ? centerH + 8.0 : 0.0,
            rightP > 0.001 ? rightH + 8.0 : 0.0,
          ),
        );

        final bool isCenterOnTop = widget.centerMenuActive ||
            (_lastActiveMenuSlot == _ClassicMenuSlot.center &&
                centerP > 0.001 &&
                !widget.isRightMenuActive);
        final bool isRightOnTop = !isCenterOnTop &&
            (widget.isRightMenuActive ||
                (_lastActiveMenuSlot == _ClassicMenuSlot.right &&
                    rightP > 0.001));

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
                    onTap: widget.onDismissOpenMenus,
                  ),
                ),
              classicLeftWidget,
              if (isCenterOnTop) ...[
                if (classicRightWidget != null) classicRightWidget,
                classicCenterWidget,
              ] else if (isRightOnTop) ...[
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
          tooltip: _tr(context, 'chat_action_reply', 'Ответить'),
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
          tooltip: _tr(context, 'chat_action_copy', 'Копировать'),
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
          tooltip: _tr(context, 'chat_action_forward', 'Переслать'),
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

        final bool isNarrow = maxWidth < 300.0;
        final double actionBtnWidth = isNarrow ? 34.0 : _actionBtnWidth;
        final double rightHorizPadding = isNarrow ? 3.0 : 6.0;
        final double rightTotalPadding = rightHorizPadding * 2.0;

        final rightCapsuleWidth = actions.isEmpty
            ? 0.0
            : math.min(
                maxWidth,
                math.max(barHeight, actions.length * actionBtnWidth + rightTotalPadding),
              );
        final remainingForLeft = actions.isEmpty
            ? maxWidth
            : math.max(0.0, maxWidth - rightCapsuleWidth - 8.0);
        final bool useCompactLeft = remainingForLeft < 152.0;
        final bool ultraTightLeft = remainingForLeft < 84.0;

        return SizedBox(
          height: barHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (remainingForLeft > 0.0)
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
                            padding: EdgeInsets.only(
                              left: ultraTightLeft ? 9.0 : 12.0,
                              right: ultraTightLeft ? 10.0 : 16.0,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: math.max(
                                    24.0,
                                    remainingForLeft - (ultraTightLeft ? 19.0 : 28.0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    iconoir.Xmark(
                                      width: ultraTightLeft ? 18 : 20,
                                      height: ultraTightLeft ? 18 : 20,
                                      color: primaryFg,
                                    ),
                                    SizedBox(width: ultraTightLeft ? 5 : 8),
                                    Flexible(
                                      child: AnimatedRollingCountText(
                                        count: selectedCount,
                                        compact: useCompactLeft,
                                        alignment: Alignment.centerLeft,
                                        style: TextStyle(
                                          fontSize: ultraTightLeft ? 14 : 15,
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
                  ),
                ),
              if (actions.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: rightCapsuleWidth),
                  child: SizedBox(
                    key: const ValueKey<String>('chat_message_selection_right_island'),
                    height: barHeight,
                    child: TheavFloatingSurface(
                      borderRadius: barHeight / 2,
                      padding: EdgeInsets.symmetric(horizontal: rightHorizPadding),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
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
                                        width: actionBtnWidth,
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
