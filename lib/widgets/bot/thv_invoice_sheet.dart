import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
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

/// Extracts an invoice slug from `/api/invoices/<slug>`, `/invoice/<slug>`,
/// `theaver://invoice/<slug>`, or `tg://invoice?slug=<slug>`.
String? extractThvInvoiceSlug(String rawUrlOrSlug) {
  final trimmed = rawUrlOrSlug.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^inv_[a-zA-Z0-9_-]{6,48}$').hasMatch(trimmed)) {
    return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  if ((scheme == 'theaver' || scheme == 'tg') && host == 'invoice') {
    final querySlug = uri.queryParameters['slug']?.trim();
    if (querySlug != null && querySlug.isNotEmpty) {
      return querySlug;
    }
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
      return uri.pathSegments.first;
    }
  }
  if (uri.fragment.isNotEmpty) {
    final fragPath =
        uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}';
    final fragUri = Uri.tryParse('app://local$fragPath');
    if (fragUri != null) {
      final fSegs = fragUri.pathSegments.where((s) => s.isNotEmpty).toList();
      for (var i = 0; i < fSegs.length - 1; i++) {
        final seg = fSegs[i].toLowerCase();
        if (seg == 'invoices' || seg == 'invoice') {
          return fSegs[i + 1];
        }
      }
    }
  }
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segs.length - 1; i++) {
    final seg = segs[i].toLowerCase();
    if (seg == 'invoices' || seg == 'invoice') {
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

  final currentUserId =
      AccountManager().currentAccount?.userId ?? await AuthService.getUserId();
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
  if (res['pin_required'] == true && invoice['pin_required'] == null) {
    invoice['pin_required'] = true;
  }
  if (res['paid_by'] != null && invoice['paid_by'] == null) {
    invoice['paid_by'] = res['paid_by'];
  }
  if (res['paid_by_me'] != null && invoice['paid_by_me'] == null) {
    invoice['paid_by_me'] = res['paid_by_me'];
  }
  final result = await showTheavModalSheet<String>(
    context: context,
    useRootNavigator: true,
    title: 'Подтверждение оплаты THV',
    showCloseButton: true,
    builder: (sheetCtx) => _ThvInvoiceCheckoutBody(
      slug: slug,
      invoice: invoice,
      currentUserId: currentUserId,
    ),
  );
  return result ?? 'cancelled';
}

bool _isPaidByCurrentUser(Map<String, dynamic> data, String? currentUserId) {
  if (data['paid_by_me'] == true) return true;
  if (data['paid_by_me'] == false) return false;
  final paidBy = data['paid_by']?.toString().trim() ?? '';
  final me = currentUserId?.trim() ?? '';
  if (paidBy.isNotEmpty && me.isNotEmpty) {
    return paidBy == me;
  }
  return false;
}

bool _isAlreadyPaidResponse(Map<String, dynamic> data) {
  final statusCode = (data['http_status'] as num?)?.toInt();
  final errCode = (data['error_code'] ?? '').toString().toLowerCase();
  final err = (data['error'] ?? '').toString().toLowerCase();
  final statusStr = (data['status'] ?? '').toString().toLowerCase();
  return statusCode == 409 ||
      errCode == 'already_paid' ||
      err == 'already_paid' ||
      statusStr == 'already_paid';
}

bool _isWalletFrozenResponse(Map<String, dynamic> data) {
  if (data['is_frozen'] == true) return true;
  final errCode = (data['error_code'] ?? '').toString().toLowerCase();
  final err = (data['error'] ?? '').toString().toLowerCase();
  return errCode == 'wallet_frozen' || err == 'wallet_frozen';
}

bool _isInvalidPinResponse(Map<String, dynamic> data) {
  final errCode = (data['error_code'] ?? '').toString().toLowerCase();
  final err = (data['error'] ?? '').toString().toLowerCase();
  if (errCode == 'invalid_pin' || err == 'invalid_pin') return true;
  final statusCode = (data['http_status'] as num?)?.toInt();
  if (statusCode == 403 || statusCode == 428 || statusCode == 400) {
    final msg =
        '${data['message'] ?? ''} ${data['description'] ?? ''}'.toLowerCase();
    if ((msg.contains('pin') || msg.contains('пин')) &&
        (msg.contains('неверн') ||
            msg.contains('invalid') ||
            msg.contains('wrong'))) {
      return true;
    }
  }
  return false;
}

bool _isPinRequiredResponse(Map<String, dynamic> data) {
  if (_isInvalidPinResponse(data)) return false;
  if (data['pin_required'] == true) return true;
  final errCode = (data['error_code'] ?? '').toString().toLowerCase();
  final err = (data['error'] ?? '').toString().toLowerCase();
  if (errCode == 'pin_required' || err == 'pin_required') return true;
  final statusCode = (data['http_status'] as num?)?.toInt();
  if (statusCode == 403 || statusCode == 428) {
    final msg =
        '${data['message'] ?? ''} ${data['description'] ?? ''} ${data['error'] ?? ''}'
            .toLowerCase();
    if (msg.contains('pin') || msg.contains('пин')) return true;
  }
  return false;
}

class _ThvInvoiceCheckoutBody extends StatefulWidget {
  final String slug;
  final Map<String, dynamic> invoice;
  final String? currentUserId;

  const _ThvInvoiceCheckoutBody({
    required this.slug,
    required this.invoice,
    this.currentUserId,
  });

  @override
  State<_ThvInvoiceCheckoutBody> createState() =>
      _ThvInvoiceCheckoutBodyState();
}

class _ThvInvoiceCheckoutBodyState extends State<_ThvInvoiceCheckoutBody> {
  bool _submitting = false;

  Future<String?> _promptWalletPin({String? errorMessage}) {
    return showTheavDialog<String>(
      context: context,
      barrierDismissible: true,
      title: 'PIN-код кошелька',
      content: _WalletPinDialogContent(initialError: errorMessage),
    );
  }

  Future<void> _submitPayment(int amount) async {
    HapticUtils.tap();
    String? pin;
    if (widget.invoice['pin_required'] == true) {
      pin = await _promptWalletPin();
      if (!mounted || pin == null) return;
    }

    while (mounted) {
      setState(() => _submitting = true);
      final payRes = await BotService.payInvoice(widget.slug, pin: pin);
      if (!mounted) return;

      if (payRes['success'] == true) {
        HapticUtils.impact();
        GlassToastService().show(
          context,
          'Оплачено $amount THV',
          icon: Icons.check,
        );
        Navigator.of(context).pop('paid');
        return;
      }

      if (_isAlreadyPaidResponse(payRes)) {
        setState(() => _submitting = false);
        if (_isPaidByCurrentUser(payRes, widget.currentUserId)) {
          HapticUtils.impact();
          GlassToastService().show(
            context,
            'Счёт уже оплачен вами',
            icon: Icons.check,
          );
          Navigator.of(context).pop('paid');
        } else {
          HapticUtils.heavy();
          GlassToastService().showError(
            context,
            'Счёт уже оплачен другим пользователем',
          );
          Navigator.of(context).pop('cancelled');
        }
        return;
      }

      if (_isWalletFrozenResponse(payRes)) {
        setState(() => _submitting = false);
        HapticUtils.heavy();
        GlassToastService().showError(
          context,
          payRes['message']?.toString() ?? 'Кошелёк @walt заморожен',
        );
        Navigator.of(context).pop('cancelled');
        return;
      }

      final invalidPin = pin != null && _isInvalidPinResponse(payRes);
      if (_isPinRequiredResponse(payRes) || invalidPin) {
        setState(() => _submitting = false);
        HapticUtils.heavy();
        final errText = invalidPin
            ? (payRes['message']?.toString() ?? 'Неверный PIN-код кошелька')
            : null;
        if (errText != null) {
          GlassToastService().showError(context, errText);
        }
        pin = await _promptWalletPin(errorMessage: errText);
        if (!mounted || pin == null) return;
        continue;
      }

      setState(() => _submitting = false);
      HapticUtils.heavy();
      GlassToastService().showError(
        context,
        payRes['message']?.toString() ?? 'Ошибка оплаты',
      );
      return;
    }
  }

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
    final bool isFrozen = widget.invoice['is_frozen'] == true;
    final bool paidByMe =
        alreadyPaid && _isPaidByCurrentUser(widget.invoice, widget.currentUserId);
    final bool insufficient = !alreadyPaid && !isFrozen && callerBal < amount;

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
            label: paidByMe
                ? 'Этот счёт уже оплачен'
                : 'Счёт уже оплачен другим пользователем',
            isPrimary: false,
            onTap: () => Navigator.of(context).pop(paidByMe ? 'paid' : 'cancelled'),
          )
        else if (isFrozen)
          TheavFloatingPillButton(
            label: 'Кошелёк @walt заморожен',
            isPrimary: false,
            onTap: () => Navigator.of(context).pop('cancelled'),
          )
        else if (insufficient) ...[
          TheavFloatingPillButton(
            label: 'Пополнить THV в @walt',
            isPrimary: true,
            onTap: () async {
              HapticUtils.tap();
              final rootContext =
                  Navigator.of(context, rootNavigator: true).context;
              Navigator.of(context).pop('cancelled');
              final effectiveWaltId =
                  (waltBotId.isNotEmpty && waltBotId != '0') ? waltBotId : 'walt';
              if (rootContext.mounted) {
                await openMiniAppSheet(
                  rootContext,
                  botId: effectiveWaltId,
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
            onTap: () => _submitPayment(amount),
          ),
      ],
    );
  }
}

class _WalletPinDialogContent extends StatefulWidget {
  final String? initialError;

  const _WalletPinDialogContent({this.initialError});

  @override
  State<_WalletPinDialogContent> createState() =>
      _WalletPinDialogContentState();
}

class _WalletPinDialogContentState extends State<_WalletPinDialogContent> {
  final TextEditingController _pinController = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _errorText = widget.initialError;
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _errorText = 'Введите 4–6 цифр PIN-кода');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Введите PIN-код кошелька @walt (4–6 цифр) для подтверждения платежа.',
          style: TextStyle(fontSize: 13.5, color: palette.subtext, height: 1.35),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            color: palette.onSurface,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            hintText: '••••',
            counterText: '',
            errorText: _errorText,
            filled: true,
            fillColor: palette.onSurface.withValues(alpha: 0.06),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.divider, width: 0.7),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.divider, width: 0.7),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.primary, width: 1.2),
            ),
          ),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Отмена',
                style: TextStyle(color: palette.subtext),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      ],
    );
  }
}
