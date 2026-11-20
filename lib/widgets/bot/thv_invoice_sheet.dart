import 'package:flutter/material.dart';

import '../../services/bot_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';
import 'mini_app_webview_sheet.dart';

/// Custom vector icon depicting Theav (`THV`): a faceted Liquid Glass prism crystal
/// enclosing a crisp `T` silhouette.
class ThvCrystalIcon extends StatelessWidget {
  final double size;
  final Color color;

  const ThvCrystalIcon({
    super.key,
    this.size = 24,
    this.color = const Color(0xFF00B4D8),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ThvCrystalPainter(color: color),
    );
  }
}

class _ThvCrystalPainter extends CustomPainter {
  final Color color;

  const _ThvCrystalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outer = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.88, h * 0.38)
      ..lineTo(w * 0.5, h * 0.94)
      ..lineTo(w * 0.12, h * 0.38)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color,
          Color.lerp(color, Colors.indigoAccent, 0.25) ?? color,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(outer, fillPaint);

    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.055).clamp(1.0, 2.5);
    canvas.drawPath(outer, rimPaint);

    final facetPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.04).clamp(0.8, 1.8);
    canvas.drawLine(Offset(w * 0.12, h * 0.38), Offset(w * 0.88, h * 0.38), facetPaint);

    final tPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (w * 0.10).clamp(1.6, 4.0);
    canvas.drawLine(Offset(w * 0.34, h * 0.34), Offset(w * 0.66, h * 0.34), tPaint);
    canvas.drawLine(Offset(w * 0.5, h * 0.34), Offset(w * 0.5, h * 0.70), tPaint);
  }

  @override
  bool shouldRepaint(covariant _ThvCrystalPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Extracts an invoice slug from `/api/invoices/<slug>` or `theaver://invoice/<slug>`.
String? extractThvInvoiceSlug(String rawUrlOrSlug) {
  final trimmed = rawUrlOrSlug.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^inv_[a-zA-Z0-9_-]{6,48}$').hasMatch(trimmed)) {
    return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() == 'theaver' &&
      uri.host.toLowerCase() == 'invoice' &&
      uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segs.length - 1; i++) {
    if (segs[i].toLowerCase() == 'invoices') {
      return segs[i + 1];
    }
  }
  return null;
}

/// Opens a native modal checkout sheet for a bot's `THV` invoice and returns
/// Telegram-compatible invoice status: `'paid'`, `'cancelled'`, or `'failed'`.
Future<String> openThvInvoiceSheet(
  BuildContext context, {
  required String slugOrUrl,
}) async {
  final slug = extractThvInvoiceSlug(slugOrUrl);
  if (slug == null || slug.isEmpty) {
    GlassToastService().showError(context, 'Некорректная ссылка на счёт THV');
    return 'failed';
  }

  final res = await BotService.getInvoice(slug);
  if (!context.mounted) return 'cancelled';
  if (res['success'] != true || res['invoice'] is! Map) {
    GlassToastService().showError(
      context,
      res['message']?.toString() ?? 'Счёт не найден',
    );
    return 'failed';
  }

  final invoice = Map<String, dynamic>.from(res['invoice'] as Map);
  final result = await showTheavModalSheet<String>(
    context: context,
    useRootNavigator: true,
    title: 'Подтверждение оплаты THV',
    showCloseButton: true,
    builder: (sheetCtx) => _ThvInvoiceCheckoutBody(
      slug: slug,
      invoice: invoice,
    ),
  );
  return result ?? 'cancelled';
}

class _ThvInvoiceCheckoutBody extends StatefulWidget {
  final String slug;
  final Map<String, dynamic> invoice;

  const _ThvInvoiceCheckoutBody({
    required this.slug,
    required this.invoice,
  });

  @override
  State<_ThvInvoiceCheckoutBody> createState() =>
      _ThvInvoiceCheckoutBodyState();
}

class _ThvInvoiceCheckoutBodyState extends State<_ThvInvoiceCheckoutBody> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final title = widget.invoice['title']?.toString() ?? 'Оплата';
    final description = widget.invoice['description']?.toString() ?? '';
    final botName = widget.invoice['bot_display_name']?.toString() ??
        widget.invoice['bot_username']?.toString() ??
        'Бот';
    final botUsername = widget.invoice['bot_username']?.toString() ?? '';
    final amount = (widget.invoice['amount'] as num?)?.toInt() ?? 0;
    final callerBal =
        (widget.invoice['caller_thv_balance'] as num?)?.toDouble() ?? 0.0;
    final status = widget.invoice['status']?.toString() ?? 'pending';
    final waltBotId = widget.invoice['walt_bot_id']?.toString() ?? '';
    final bool alreadyPaid = status == 'paid';
    final bool insufficient = !alreadyPaid && callerBal < amount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.divider, width: 0.7),
          ),
          child: Row(
            children: [
              const ThvCrystalIcon(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      botUsername.isNotEmpty
                          ? '$botName (@$botUsername)'
                          : botName,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.subtext,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$amount THV',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00B4D8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ваш баланс Theav (THV):',
              style: TextStyle(fontSize: 13.5, color: palette.subtext),
            ),
            Text(
              '${callerBal == callerBal.roundToDouble() ? callerBal.toInt() : callerBal.toStringAsFixed(2)} THV',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: insufficient ? palette.error : palette.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (alreadyPaid)
          TheavFloatingPillButton(
            label: 'Этот счёт уже оплачен',
            isPrimary: false,
            onTap: () => Navigator.of(context).pop('paid'),
          )
        else if (insufficient) ...[
          TheavFloatingPillButton(
            label: 'Пополнить THV в @walt',
            isPrimary: true,
            onTap: () async {
              HapticUtils.tap();
              Navigator.of(context).pop('cancelled');
              if (waltBotId.isNotEmpty && context.mounted) {
                await openMiniAppSheet(
                  context,
                  botId: waltBotId,
                  botName: 'Walt',
                  botUsername: 'walt',
                  isVerified: true,
                  startParam: 'buy_thv',
                );
              }
            },
          ),
        ] else
          TheavFloatingPillButton(
            label: _submitting ? 'Оплата...' : 'Оплатить $amount THV',
            isPrimary: true,
            enabled: !_submitting,
            onTap: () async {
              HapticUtils.tap();
              setState(() => _submitting = true);
              final payRes = await BotService.payInvoice(widget.slug);
              if (!context.mounted) return;
              if (payRes['success'] == true) {
                HapticUtils.impact();
                GlassToastService().show(
                  context,
                  'Оплачено $amount THV',
                  icon: Icons.check,
                );
                Navigator.of(context).pop('paid');
              } else {
                setState(() => _submitting = false);
                HapticUtils.heavy();
                GlassToastService().showError(
                  context,
                  payRes['message']?.toString() ?? 'Ошибка оплаты',
                );
              }
            },
          ),
      ],
    );
  }
}
