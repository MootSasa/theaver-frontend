import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';

/// Описание вкладки в нижнем баре.
class ClassicBottomBarTab {
  const ClassicBottomBarTab({
    required this.label,
    this.icon = Icons.circle,
    this.selectedIcon,
    this.iconBuilder,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final Widget Function(Color color, double size)? iconBuilder;
}

/// Классический нижний бар, визуально повторяющий стеклянный бар,
/// но использующий сплошную заливку вместо эффекта стекла.
///
/// Layout идентичен [LiquidGlassBottomBar]:
/// Row с Expanded(скруглённый суперквадрат с вкладками + индикатор) +
/// овальная кнопка "+".
class ClassicBottomBar extends StatefulWidget {
  const ClassicBottomBar({
    Key? key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.onAddTap,
    this.spacing = 8,
    this.horizontalPadding = 20,
    this.bottomPadding = 20,
    this.barHeight = 64,
  }) : super(key: key);

  /// Индекс активной вкладки
  final int selectedIndex;

  /// Коллбэк при выборе вкладки
  final ValueChanged<int> onTabSelected;

  /// Коллбэк при нажатии кнопки "+" (добавить)
  final VoidCallback? onAddTap;

  final double spacing;
  final double horizontalPadding;
  final double bottomPadding;
  final double barHeight;

  @override
  State<ClassicBottomBar> createState() => _ClassicBottomBarState();
}

class _ClassicBottomBarState extends State<ClassicBottomBar> {
  static final _tabs = [
    ClassicBottomBarTab(
      label: 'Настройки',
      icon: Icons.settings,
      iconBuilder: (color, size) => iconoir.Settings(color: color, width: size, height: size),
    ),
    ClassicBottomBarTab(
      label: 'Чаты',
      icon: Icons.chat,
      iconBuilder: (color, size) => iconoir.ChatBubble(color: color, width: size, height: size),
    ),
    ClassicBottomBarTab(
      label: 'Поиск',
      icon: Icons.search,
      iconBuilder: (color, size) => iconoir.Search(color: color, width: size, height: size),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final theme = Theme.of(context);

    // Цвета заливки — непрозрачные (классический дизайн)
    final barBackgroundColor = isDark
        ? const Color(0xFF2C2C2E)
        : Colors.white;
    final indicatorColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);
    final addButtonColor = isDark
        ? const Color(0xFF2C2C2E)
        : Colors.white;

    return Padding(
      padding: EdgeInsets.only(
        left: widget.horizontalPadding,
        right: widget.horizontalPadding,
        bottom: widget.bottomPadding,
        top: widget.bottomPadding,
      ),
      child: Row(
        spacing: widget.spacing,
        children: [
          // Основной бар с вкладками (скруглённый суперквадрат)
          Expanded(
            child: Container(
              height: widget.barHeight,
              decoration: BoxDecoration(
                color: barBackgroundColor,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Скользящий индикатор
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment(
                      _computeXAlignmentForTab(widget.selectedIndex),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / _tabs.length,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: BoxDecoration(
                            color: indicatorColor,
                            borderRadius: BorderRadius.circular(64),
                            border: Border.all(color: indicatorColor, width: 0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Вкладки поверх индикатора
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: _ClassicBottomBarTabButton(
                            tab: _tabs[i],
                            selected: widget.selectedIndex == i,
                            onTap: () {
                              HapticUtils.selection();
                              widget.onTabSelected(i);
                            },
                            isDark: isDark,
                            theme: theme,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Кнопка "+"
          if (widget.onAddTap != null)
            GestureDetector(
              onTap: widget.onAddTap,
              child: Container(
                height: widget.barHeight,
                width: widget.barHeight,
                decoration: BoxDecoration(
                  color: addButtonColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: iconoir.Plus(
                    width: 28,
                    height: 28,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _computeXAlignmentForTab(int tabIndex) {
    final relativeTabIndex =
        (tabIndex / (_tabs.length - 1)).clamp(0.0, 1.0);
    return (relativeTabIndex * 2) - 1; // от -1 до 1
  }
}

/// Кнопка вкладки в классическом нижнем баре.
class _ClassicBottomBarTabButton extends StatelessWidget {
  const _ClassicBottomBarTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.isDark,
    required this.theme,
  });

  final ClassicBottomBarTab tab;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected
        ? theme.colorScheme.primary
        : (isDark ? Colors.white54 : Colors.black54);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: tab.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Transform.translate(
            offset: const Offset(0, 2),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: tab.iconBuilder != null
                    ? tab.iconBuilder!(iconColor, 24)
                    : Icon(
                        selected ? (tab.selectedIcon ?? tab.icon) : tab.icon,
                        color: iconColor,
                        size: 24,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
