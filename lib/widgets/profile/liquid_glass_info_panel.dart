import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../services/liquid_glass_provider.dart';

/// Большая стеклянная информационная панель с данными пользователя.
///
/// Содержит строки: телефон, «О себе», username, дата рождения + возраст.
/// В Liquid Glass режиме — одна большая стеклянная панель с внутренним
/// шумом, размытием и глубиной. В классическом режиме — обычная Card.
class LiquidGlassInfoPanel extends StatelessWidget {
  /// Включён ли стеклянный дизайн (полный или облегчённый)
  final bool enabled;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Телефон
  final String? phone;

  /// О себе (био)
  final String? bio;

  /// Username
  final String? username;

  /// Дата рождения (строка)
  final String? birthday;

  /// Возраст (строка)
  final String? age;

  /// Локализованные подписи
  final String phoneLabel;
  final String bioLabel;
  final String usernameLabel;
  final String birthdayLabel;
  final String ageLabel;

  const LiquidGlassInfoPanel({
    Key? key,
    required this.enabled,
    this.isLite = false,
    this.phone,
    this.bio,
    this.username,
    this.birthday,
    this.age,
    this.phoneLabel = 'Телефон',
    this.bioLabel = 'О себе',
    this.usernameLabel = 'Имя пользователя',
    this.birthdayLabel = 'Дата рождения',
    this.ageLabel = 'Возраст',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      return _buildGlassPanel(context);
    }
    return _buildClassicPanel(context);
  }

  /// Собираем список строк информации (без null/пустых)
  List<_InfoRow> _buildRows() {
    final rows = <_InfoRow>[];

    if (phone != null && phone!.isNotEmpty) {
      rows.add(_InfoRow(
        icon: Icons.phone,
        label: phoneLabel,
        value: phone!,
      ));
    }

    if (bio != null && bio!.isNotEmpty) {
      rows.add(_InfoRow(
        icon: Icons.info_outline,
        label: bioLabel,
        value: bio!,
      ));
    }

    if (username != null && username!.isNotEmpty) {
      rows.add(_InfoRow(
        icon: Icons.alternate_email,
        label: usernameLabel,
        value: '@$username',
      ));
    }

    // Дата рождения + возраст в одной строке
    if (birthday != null && birthday!.isNotEmpty) {
      final ageSuffix = (age != null && age!.isNotEmpty) ? ' ($ageLabel: $age)' : '';
      rows.add(_InfoRow(
        icon: Icons.cake,
        label: birthdayLabel,
        value: '$birthday$ageSuffix',
      ));
    }

    return rows;
  }

  /// Стеклянная панель
  Widget _buildGlassPanel(BuildContext context) {
    final rows = _buildRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassStyle = glassProvider.createStyle(
      context: context,
      isLiteOverride: isLite,
    );

    final panelContent = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: isDark
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _GlassInfoRow(row: rows[i], isDark: isDark),
            if (i < rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
          ],
        ],
      ),
    );

    return LiquidGlassLens(
      style: glassStyle.copyWith(
        shape: const LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 28,
        ),
      ),
      child: panelContent,
    );
  }

  /// Классическая панель (Card)
  Widget _buildClassicPanel(BuildContext context) {
    final rows = _buildRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              _ClassicInfoRow(row: rows[i], theme: theme),
              if (i < rows.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Данные одной строки информации
class _InfoRow {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Одна строка информации в стеклянной панели
class _GlassInfoRow extends StatelessWidget {
  final _InfoRow row;
  final bool isDark;

  const _GlassInfoRow({
    Key? key,
    required this.row,
    required this.isDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Иконка (брендовый цвет #0088CC в светлой теме)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            row.icon,
            size: 18,
            color: isDark ? Colors.white70 : const Color(0xFF0088CC),
          ),
        ),
        const SizedBox(width: 12),
        // Заголовок + значение
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF3C3C43),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                row.value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Одна строка информации в классической панели
class _ClassicInfoRow extends StatelessWidget {
  final _InfoRow row;
  final ThemeData theme;

  const _ClassicInfoRow({
    Key? key,
    required this.row,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            row.icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                row.value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
