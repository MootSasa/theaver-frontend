import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';

/// Типы вкладок (разделов) в нижней части экрана профиля.
enum ProfileSectionType {
  members,
  wall,
  gifts,
  media,
  files,
  links,
  voice,
}

/// Описание одной вкладки (раздела) профиля.
class ProfileSectionItem {
  final ProfileSectionType type;
  final String label;
  final int? count;
  final Widget Function(Color color, double size)? iconBuilder;

  const ProfileSectionItem({
    required this.type,
    required this.label,
    this.iconBuilder,
    this.count,
  });

  Widget buildIcon(Color color, double size) {
    if (iconBuilder != null) {
      return iconBuilder!(color, size);
    }
    switch (type) {
      case ProfileSectionType.members:
        return iconoir.Group(color: color, width: size, height: size);
      case ProfileSectionType.wall:
        return iconoir.ViewGrid(color: color, width: size, height: size);
      case ProfileSectionType.gifts:
        return iconoir.Gift(color: color, width: size, height: size);
      case ProfileSectionType.media:
        return iconoir.MediaImageList(color: color, width: size, height: size);
      case ProfileSectionType.files:
        return iconoir.Page(color: color, width: size, height: size);
      case ProfileSectionType.links:
        return iconoir.Link(color: color, width: size, height: size);
      case ProfileSectionType.voice:
        return iconoir.Microphone(color: color, width: size, height: size);
    }
  }
}

/// Единая капсула-переключатель текущего раздела профиля («Стена v», «Медиа v» и т.д.).
///
/// Рендерится напрямую в `Stack` экрана профиля без `OverlayPortal`, благодаря чему:
/// - Движется синхронно со скроллом без задержки в 1 кадр и без мигания.
/// - Имеет абсолютно тот же стиль `LiquidGlassLens` и уровень, что и кнопки `<`, `•••` и быстрые действия.
/// - При нажатии плавно морфится (`280ms` / `220ms`, `Curves.easeInOutCubic`) в выпадающий список разделов
///   точно так же, как кнопка смены папки чатов на главном экране (`MainScreen`).
class ProfileSectionPill extends StatefulWidget {
  final List<ProfileSectionItem> sections;
  final int selectedIndex;
  final ValueChanged<int> onSectionSelected;
  final ValueChanged<bool>? onOpenChanged;
  final bool glassEnabled;
  final bool isLite;
  final bool hasColoredTheme;
  final bool compact;

  const ProfileSectionPill({
    Key? key,
    required this.sections,
    required this.selectedIndex,
    required this.onSectionSelected,
    this.onOpenChanged,
    this.glassEnabled = false,
    this.isLite = false,
    this.hasColoredTheme = false,
    this.compact = false,
  }) : super(key: key);

  @override
  State<ProfileSectionPill> createState() => ProfileSectionPillState();
}

class ProfileSectionPillState extends State<ProfileSectionPill>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  late final AnimationController _morphController;
  late final Animation<double> _morphAnimation;

  static const double _ctrlSize = 44.0;
  static const double _barRadius = _ctrlSize / 2; // 22.0
  static const double _menuWidth = 220.0;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _morphAnimation = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  void closeMenu() => _closeMenu();

  void _toggleMenu() {
    if (widget.sections.length <= 1) return;
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    if (_isOpen) return;
    HapticUtils.tap();
    setState(() {
      _isOpen = true;
    });
    _morphController.forward();
    widget.onOpenChanged?.call(true);
  }

  void _closeMenu() {
    if (!_isOpen) return;
    setState(() {
      _isOpen = false;
    });
    _morphController.reverse();
    widget.onOpenChanged?.call(false);
  }

  void _selectItem(int index) {
    HapticUtils.selection();
    widget.onSectionSelected(index);
    _closeMenu();
  }

  double _calculatePillWidth(BuildContext context, ProfileSectionItem current) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: current.label,
        style: const TextStyle(
          fontSize: 17.0,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();

    final extraWidth = widget.sections.length > 1 ? 64.0 : 44.0;
    return math.max(130.0, textPainter.size.width + extraWidth);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();

    final safeIndex =
        widget.selectedIndex.clamp(0, widget.sections.length - 1);
    final currentSection = widget.sections[safeIndex];
    final closedPillWidth = _calculatePillWidth(context, currentSection);
    final theme = Theme.of(context);
    final isDark =
        theme.brightness == Brightness.dark || widget.hasColoredTheme;
    final double folderMenuHeight =
        math.max(_ctrlSize, widget.sections.length * 44.0 + 12.0);

    if (widget.glassEnabled) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final pillStyle = glassProvider.createStyle(
        context: context,
        cornerRadius: _barRadius,
        isDarkOverride: isDark,
        isLiteOverride: widget.isLite,
        color: isDark ? const Color(0x33202025) : const Color(0x66FFFFFF),
        refractionIndex: 1.15,
        refractionWidth: 22.0,
        shape: const LiquidGlassShape.roundedRectangle(
          cornerRadius: _barRadius,
        ),
      );

      final Widget morphChild = SizedBox(
        width: _menuWidth,
        height: folderMenuHeight,
        child: LiquidGlassBatch(
          enabled: !_isOpen,
          child: LiquidGlassMorph(
            key: const ValueKey<String>('profile_section_pill_morph'),
            alignment: Alignment.topCenter,
            motion: LiquidGlassMorphMotion.fluid,
            smoothness: 28,
            style: pillStyle,
            child: _isOpen
                ? _SectionMorphMenuList(
                    key: const ValueKey<String>('section_menu'),
                    width: _menuWidth,
                    sections: widget.sections,
                    selectedIndex: safeIndex,
                    isDark: isDark,
                    onSelectSection: _selectItem,
                  )
                : _TitlePillContent(
                    key: const ValueKey<String>('section_pill'),
                    minWidth: closedPillWidth,
                    title: currentSection.label,
                    titleKey: currentSection.type.name,
                    showChevron: widget.sections.length > 1,
                    isDark: isDark,
                    onTap: _toggleMenu,
                  ),
          ),
        ),
      );

      if (widget.onOpenChanged != null) {
        return morphChild;
      }

      return TapRegion(
        onTapOutside: (_) {
          if (_isOpen) {
            _closeMenu();
          }
        },
        child: morphChild,
      );
    }
    final themeExt = theme.extension<TheavThemeExtension>();
    final p = themeExt?.palette;
    final baseSurface = p?.surface ??
        (isDark ? const Color(0xFF2C2C2E) : Colors.white);
    final barBackgroundColor = baseSurface.withValues(
      alpha: isDark ? 0.62 : 0.72,
    );
    final borderColor = p?.divider ??
        (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08));
    final double baseShadowAlpha = isDark ? 0.24 : 0.08;

    final Widget animatedChild = AnimatedBuilder(
      animation: _morphAnimation,
      builder: (context, _) {
        final double progress = _morphAnimation.value;
        final double currentWidth =
            closedPillWidth + (_menuWidth - closedPillWidth) * progress;
        final double currentHeight =
            _ctrlSize + (folderMenuHeight - _ctrlSize) * progress;

        final double titleOpacity = (1.0 - progress * 2.5).clamp(0.0, 1.0);
        final double menuOpacity =
            ((progress - 0.25) / 0.75).clamp(0.0, 1.0);
        final double titleScale = 1.0 - 0.15 * progress;

        return Container(
          width: currentWidth,
          height: currentHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_barRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: baseShadowAlpha + 0.12 * progress,
                ),
                blurRadius: 8 + 14 * progress,
                offset: Offset(0, 2 + 6 * progress),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_barRadius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: currentWidth,
                height: currentHeight,
                decoration: BoxDecoration(
                  color: barBackgroundColor,
                  borderRadius: BorderRadius.circular(_barRadius),
                  border: Border.all(
                    color: borderColor,
                    width: 0.5,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    if (titleOpacity > 0.0)
                      Opacity(
                        opacity: titleOpacity,
                        child: Transform.scale(
                          scale: titleScale,
                          child: SizedBox(
                            height: _ctrlSize,
                            child: _TitlePillContent(
                              minWidth: closedPillWidth,
                              title: currentSection.label,
                              titleKey: currentSection.type.name,
                              showChevron: widget.sections.length > 1,
                              isDark: isDark,
                              onTap: _toggleMenu,
                            ),
                          ),
                        ),
                      ),
                    if (menuOpacity > 0.0)
                      Opacity(
                        opacity: menuOpacity,
                        child: Transform.translate(
                          offset: Offset(0, -10.0 * (1.0 - progress)),
                          child: _SectionMorphMenuList(
                            width: _menuWidth,
                            sections: widget.sections,
                            selectedIndex: safeIndex,
                            isDark: isDark,
                            onSelectSection: _selectItem,
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
    );

    if (widget.onOpenChanged != null) {
      return animatedChild;
    }

    return TapRegion(
      onTapOutside: (_) {
        if (_isOpen) {
          _closeMenu();
        }
      },
      child: animatedChild,
    );
  }
}

/// Внутреннее содержимое закрытой капсулы раздела (в стиле `_TitlePillContent` из `MainScreen`).
class _TitlePillContent extends StatelessWidget {
  final double minWidth;
  final String title;
  final String titleKey;
  final bool showChevron;
  final bool isDark;
  final VoidCallback? onTap;

  const _TitlePillContent({
    super.key,
    required this.minWidth,
    required this.title,
    required this.titleKey,
    this.showChevron = true,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF1C1C1E);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44.0,
        constraints: BoxConstraints(minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) {
                  final inAnimation = Tween<Offset>(
                    begin: const Offset(0.0, -1.0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ));
                  final outAnimation = Tween<Offset>(
                    begin: const Offset(0.0, 1.0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInCubic,
                  ));
                  final isIncoming = child.key == ValueKey<String>(titleKey);
                  return ClipRect(
                    child: SlideTransition(
                      position: isIncoming ? inAnimation : outAnimation,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      ...previousChildren.map(
                        (w) => Positioned.fill(
                          child: Center(
                            child: OverflowBox(
                              minWidth: 0,
                              maxWidth: double.infinity,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: w,
                            ),
                          ),
                        ),
                      ),
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: Row(
                  key: ValueKey<String>(titleKey),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17.0,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (showChevron) ...[
                      const SizedBox(width: 4.0),
                      iconoir.NavArrowDown(
                        width: 16.0,
                        height: 16.0,
                        color: textColor.withValues(alpha: 0.75),
                      ),
                    ],
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

/// Выпадающий список разделов при морфинге капсулы (в стиле `_FolderMorphMenu` из `MainScreen`).
class _SectionMorphMenuList extends StatelessWidget {
  final double width;
  final List<ProfileSectionItem> sections;
  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onSelectSection;

  const _SectionMorphMenuList({
    super.key,
    required this.width,
    required this.sections,
    required this.selectedIndex,
    required this.isDark,
    required this.onSelectSection,
  });

  @override
  Widget build(BuildContext context) {
    final double totalHeight = math.max(44.0, sections.length * 44.0 + 12.0);
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < sections.length; i++)
                  _SectionMorphMenuRow(
                    key: ValueKey(sections[i].type.name),
                    item: sections[i],
                    isSelected: i == selectedIndex,
                    isDark: isDark,
                    onTap: () => onSelectSection(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionMorphMenuRow extends StatelessWidget {
  final ProfileSectionItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _SectionMorphMenuRow({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    const activeColor = Color(0xFF0088CC);
    final itemColor = isSelected ? activeColor : defaultColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
            children: [
              SizedBox(
                width: 22.0,
                height: 22.0,
                child: Center(
                  child: item.buildIcon(itemColor, 20.0),
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: itemColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (item.count != null && item.count! > 0) ...[
                const SizedBox(width: 6.0),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor
                        : defaultColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.count! > 999 ? '999+' : '${item.count}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : defaultColor.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
              if (isSelected) ...[
                const SizedBox(width: 6.0),
                const iconoir.Check(
                  width: 18.0,
                  height: 18.0,
                  color: activeColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
