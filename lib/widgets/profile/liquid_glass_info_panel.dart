import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/entity_parser.dart';
import '../../utils/haptic_utils.dart';

/// Чистая информационная карточка профиля в стиле Telegram (без боковых иконок слева).
///
/// Каждая строка содержит верхнюю приглушённую подпись (`label`) и основное значение (`value`) снизу.
/// Поддерживает:
/// - Копирование по тапу или долгому нажатию с тактильным откликом и стеклянным тостом `GlassToastService`.
/// - Кликабельные ссылки и `@упоминания` в полях «О себе» / «Описание».
/// - Кнопку `iconoir.QrCode` справа в строке `@username` или ссылки-приглашения.
class LiquidGlassInfoPanel extends StatelessWidget {
  /// Включён ли стеклянный дизайн (полный или облегчённый)
  final bool enabled;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Телефон
  final String? phone;

  /// О себе (био) или описание группы/канала
  final String? bio;

  /// Username (без @ или с @)
  final String? username;

  /// Ссылка-приглашение (для групп/каналов)
  final String? inviteLink;

  /// Дата рождения (строка)
  final String? birthday;

  /// Возраст (строка)
  final String? age;

  /// Коллбэк при нажатии на иконку QR-кода справа от username / inviteLink
  final VoidCallback? onQrCodeTap;

  /// Коллбэк при нажатии на иконку календаря справа от даты рождения
  final VoidCallback? onBirthdayTap;

  /// Коллбэк при нажатии на @упоминание в био/описании
  final ValueChanged<String>? onMentionTap;

  /// Активен ли цветной/градиентный пресет профиля
  final bool hasColoredTheme;

  /// Локализованные подписи
  final String phoneLabel;
  final String bioLabel;
  final String usernameLabel;
  final String inviteLinkLabel;
  final String birthdayLabel;
  final String ageLabel;

  const LiquidGlassInfoPanel({
    Key? key,
    required this.enabled,
    this.isLite = false,
    this.hasColoredTheme = false,
    this.phone,
    this.bio,
    this.username,
    this.inviteLink,
    this.birthday,
    this.age,
    this.onQrCodeTap,
    this.onBirthdayTap,
    this.onMentionTap,
    this.phoneLabel = 'телефон',
    this.bioLabel = 'о себе',
    this.usernameLabel = 'имя пользователя',
    this.inviteLinkLabel = 'ссылка-приглашение',
    this.birthdayLabel = 'дата рождения',
    this.ageLabel = 'лет',
  }) : super(key: key);

  List<_InfoRowData> _buildRows() {
    final rows = <_InfoRowData>[];

    if (phone != null && phone!.trim().isNotEmpty) {
      rows.add(_InfoRowData(
        label: phoneLabel.toLowerCase(),
        value: phone!.trim(),
        copyValue: phone!.trim(),
        isRichText: false,
      ));
    }

    if (username != null && username!.trim().isNotEmpty) {
      final cleanUser = username!.trim().startsWith('@')
          ? username!.trim()
          : '@${username!.trim()}';
      rows.add(_InfoRowData(
        label: usernameLabel.toLowerCase(),
        value: cleanUser,
        copyValue: cleanUser,
        isRichText: false,
        showQrButton: onQrCodeTap != null,
      ));
    }

    if (inviteLink != null && inviteLink!.trim().isNotEmpty) {
      rows.add(_InfoRowData(
        label: inviteLinkLabel.toLowerCase(),
        value: inviteLink!.trim(),
        copyValue: inviteLink!.trim(),
        isRichText: false,
        showQrButton: onQrCodeTap != null && (username == null || username!.trim().isEmpty),
      ));
    }

    if (bio != null && bio!.trim().isNotEmpty) {
      rows.add(_InfoRowData(
        label: bioLabel.toLowerCase(),
        value: bio!.trim(),
        copyValue: bio!.trim(),
        isRichText: true,
      ));
    }

    if (birthday != null && birthday!.trim().isNotEmpty) {
      final hasAge = age != null && age!.trim().isNotEmpty;
      final formattedValue = hasAge
          ? '${birthday!.trim()} ($age $ageLabel)'
          : birthday!.trim();
      rows.add(_InfoRowData(
        label: birthdayLabel.toLowerCase(),
        value: formattedValue,
        copyValue: formattedValue,
        isRichText: false,
        showCalendarButton: onBirthdayTap != null,
      ));
    }

    return rows;
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticUtils.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String copiedMsg = 'Скопировано в буфер обмена';
    try {
      final tr = context.l10n.translate('copied_to_clipboard');
      if (tr.isNotEmpty && tr != 'copied_to_clipboard') {
        copiedMsg = tr;
      }
    } catch (_) {}

    GlassToastService().show(
      context,
      copiedMsg,
      iconWidget: iconoir.Copy(
        width: 18,
        height: 18,
        color: isDark ? Colors.white : Colors.black87,
      ),
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    if (enabled) {
      return _buildGlassPanel(context, rows);
    }
    return _buildClassicPanel(context, rows);
  }

  Widget _buildGlassPanel(BuildContext context, List<_InfoRowData> rows) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || hasColoredTheme;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassStyle = glassProvider.createStyle(
      context: context,
      isDarkOverride: isDark,
      isLiteOverride: isLite,
      color: isDark ? const Color(0x33202025) : const Color(0x66FFFFFF),
      refractionIndex: 1.15,
      refractionWidth: 22.0,
      shape: const LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: 24,
      ),
    );

    final panelContent = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: isDark
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
      child: _buildRowsColumn(context, rows, isDark: isDark, isGlass: true),
    );

    return LiquidGlassLens(
      style: glassStyle,
      child: panelContent,
    );
  }

  Widget _buildClassicPanel(BuildContext context, List<_InfoRowData> rows) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark || hasColoredTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0x99262628)
                  : const Color(0xB3FFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: _buildRowsColumn(context, rows, isDark: isDark, isGlass: false),
          ),
        ),
      ),
    );
  }

  Widget _buildRowsColumn(
    BuildContext context,
    List<_InfoRowData> rows, {
    required bool isDark,
    required bool isGlass,
  }) {
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF6C6C70);
    final valueColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final linkColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          _InfoRowWidget(
            row: rows[i],
            labelColor: labelColor,
            valueColor: valueColor,
            linkColor: linkColor,
            onCopy: () => _copyToClipboard(context, rows[i].copyValue, rows[i].label),
            onQrCodeTap: rows[i].showQrButton ? onQrCodeTap : null,
            onCalendarTap: rows[i].showCalendarButton ? onBirthdayTap : null,
            onMentionTap: onMentionTap,
          ),
          if (i < rows.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                thickness: 0.5,
                color: dividerColor,
              ),
            ),
        ],
      ],
    );
  }
}

class _InfoRowData {
  final String label;
  final String value;
  final String copyValue;
  final bool isRichText;
  final bool showQrButton;
  final bool showCalendarButton;

  const _InfoRowData({
    required this.label,
    required this.value,
    required this.copyValue,
    this.isRichText = false,
    this.showQrButton = false,
    this.showCalendarButton = false,
  });
}

class _InfoRowWidget extends StatelessWidget {
  final _InfoRowData row;
  final Color labelColor;
  final Color valueColor;
  final Color linkColor;
  final VoidCallback onCopy;
  final VoidCallback? onQrCodeTap;
  final VoidCallback? onCalendarTap;
  final ValueChanged<String>? onMentionTap;

  const _InfoRowWidget({
    required this.row,
    required this.labelColor,
    required this.valueColor,
    required this.linkColor,
    required this.onCopy,
    this.onQrCodeTap,
    this.onCalendarTap,
    this.onMentionTap,
  });

  static final RegExp _tokenRegex = RegExp(
    r'(?:https?:\/\/|www\.)[^\s]+'
    r'|@[a-zA-Z0-9_]{3,32}',
    caseSensitive: false,
  );

  Widget _buildValueText(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w500,
      color: valueColor,
      height: 1.28,
    );

    if (!row.isRichText) {
      return Text(
        row.value,
        style: baseStyle,
      );
    }

    final text = row.value;
    final matches = _tokenRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      final token = match.group(0)!;
      if (token.startsWith('@')) {
        final cleanUsername = token.substring(1);
        spans.add(
          TextSpan(
            text: token,
            style: baseStyle.copyWith(color: linkColor),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                HapticUtils.tap();
                if (onMentionTap != null) {
                  onMentionTap!(cleanUsername);
                } else {
                  onCopy();
                }
              },
          ),
        );
      } else {
        final normalized = EntityParser.normalizeUrl(token);
        spans.add(
          TextSpan(
            text: token,
            style: baseStyle.copyWith(
              color: linkColor,
              decoration: TextDecoration.underline,
              decorationColor: linkColor.withValues(alpha: 0.5),
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                HapticUtils.tap();
                final uri = Uri.tryParse(normalized);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
          ),
        );
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCopy,
      onLongPress: onCopy,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 2),
                _buildValueText(context),
              ],
            ),
          ),
          if (onQrCodeTap != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                onQrCodeTap!();
              },
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: iconoir.QrCode(
                  width: 22,
                  height: 22,
                  color: linkColor,
                ),
              ),
            ),
          ],
          if (onCalendarTap != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                onCalendarTap!();
              },
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: iconoir.Calendar(
                  width: 22,
                  height: 22,
                  color: linkColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
