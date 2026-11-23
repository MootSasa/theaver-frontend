import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_lock_service.dart';
import '../../services/browser_vault_auth_gate.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// User choice returned by [showBrowserVaultUnprotectedChoiceSheet] when no
/// App Lock PIN, Vault PIN, or OS device lock is configured.
enum BrowserVaultUnprotectedAction {
  setVaultPin,
  continueWithoutPin,
  cancel,
}

/// Prompts the user to confirm their App Lock PIN or autonomous Vault PIN
/// inside a Safari Liquid Glass modal sheet before decrypting saved browser
/// credentials, payment cards, or viewing sensitive vault sections.
Future<bool> showBrowserVaultPinSheet(
  BuildContext context, {
  required String reason,
  AppLockService? appLockService,
  BrowserVaultAuthGate? authGate,
  bool useVaultPin = false,
}) async {
  final AppLockService lock = appLockService ?? AppLockService.instance;
  final BrowserVaultAuthGate gate = authGate ?? BrowserVaultAuthGate.instance;
  final bool? ok = await showTheavModalSheet<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.65,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
    builder: (sheetCtx) => _BrowserVaultPinSheetBody(
      reason: reason,
      lockService: lock,
      authGate: gate,
      useVaultPin: useVaultPin,
    ),
  );
  return ok ?? false;
}

/// Opens a 2-step modal sheet to create and confirm a 4-digit per-account
/// autonomous Vault PIN saved via [BrowserVaultAuthGate.setVaultPin].
Future<bool> showBrowserVaultCreatePinSheet(
  BuildContext context, {
  BrowserVaultAuthGate? authGate,
}) async {
  final BrowserVaultAuthGate gate = authGate ?? BrowserVaultAuthGate.instance;
  final bool? ok = await showTheavModalSheet<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.68,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
    builder: (sheetCtx) => _BrowserVaultCreatePinSheetBody(authGate: gate),
  );
  return ok ?? false;
}

/// Explains that no PIN or OS screen lock protects the browser vault yet and
/// lets the user either set a Vault PIN or (when [allowSkipAuth] is `true`)
/// continue without requiring authentication.
Future<BrowserVaultUnprotectedAction> showBrowserVaultUnprotectedChoiceSheet(
  BuildContext context, {
  required String reason,
  bool allowSkipAuth = true,
}) async {
  final BrowserVaultUnprotectedAction? action =
      await showTheavModalSheet<BrowserVaultUnprotectedAction>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.68,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
    builder: (sheetCtx) => _BrowserVaultUnprotectedChoiceBody(
      reason: reason,
      allowSkipAuth: allowSkipAuth,
    ),
  );
  return action ?? BrowserVaultUnprotectedAction.cancel;
}

class _BrowserVaultPinSheetBody extends StatefulWidget {
  final String reason;
  final AppLockService lockService;
  final BrowserVaultAuthGate authGate;
  final bool useVaultPin;

  const _BrowserVaultPinSheetBody({
    required this.reason,
    required this.lockService,
    required this.authGate,
    required this.useVaultPin,
  });

  @override
  State<_BrowserVaultPinSheetBody> createState() =>
      _BrowserVaultPinSheetBodyState();
}

class _BrowserVaultPinSheetBodyState extends State<_BrowserVaultPinSheetBody> {
  final TextEditingController _pinCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _lockoutTimer;
  String? _errorText;
  bool _verifying = false;

  bool get _isLockedOut => widget.useVaultPin
      ? widget.authGate.isVaultPinLockedOut
      : widget.lockService.isLockedOut;

  Duration get _lockoutRemaining => widget.useVaultPin
      ? widget.authGate.vaultPinLockoutRemaining
      : widget.lockService.lockoutRemaining;

  int get _pinLength => widget.useVaultPin
      ? widget.authGate.vaultPinLength
      : widget.lockService.pinLength;

  @override
  void initState() {
    super.initState();
    _syncLockoutTimer();
    if (widget.useVaultPin) {
      unawaited(
        widget.authGate.hasVaultPin().then((_) {
          if (!mounted) return;
          _syncLockoutTimer();
          setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _pinCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncLockoutTimer() {
    _lockoutTimer?.cancel();
    if (!_isLockedOut) return;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isLockedOut) {
        _lockoutTimer?.cancel();
        setState(() => _errorText = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submit() async {
    if (_verifying) return;
    if (_isLockedOut) {
      HapticUtils.heavy();
      _syncLockoutTimer();
      setState(() {});
      return;
    }
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4) {
      HapticUtils.heavy();
      setState(
        () => _errorText = context.trOr(
          'browser_vault_pin_length_error',
          'Введите {count}-значный PIN-код',
          {'count': '$_pinLength'},
        ),
      );
      return;
    }
    setState(() {
      _verifying = true;
      _errorText = null;
    });
    final bool valid = widget.useVaultPin
        ? await widget.authGate.verifyVaultPin(pin)
        : await widget.lockService.verifyPin(
            pin,
            unlockOnSuccess: false,
          );
    if (!mounted) return;
    if (valid) {
      HapticUtils.selection();
      Navigator.of(context).pop(true);
      return;
    }
    HapticUtils.heavy();
    _pinCtrl.clear();
    _syncLockoutTimer();
    setState(() {
      _verifying = false;
      _errorText = _isLockedOut
          ? null
          : context.trOr('browser_vault_pin_wrong', 'Неверный PIN-код');
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final Duration lockout = _lockoutRemaining;
    final int lockoutSec =
        lockout > Duration.zero ? (lockout.inMilliseconds / 1000).ceil() : 0;

    return SingleChildScrollView(
      key: const ValueKey('browser_vault_pin_sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinHeaderBadge(
            icon: Icons.lock_person_rounded,
            style: style,
          ),
          const SizedBox(height: 12),
          Text(
            widget.useVaultPin
                ? context.trOr(
                    'browser_vault_pin_title',
                    'PIN-код хранилища',
                  )
                : context.trOr(
                    'browser_vault_auth_title',
                    'Подтверждение доступа',
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.reason,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: palette.subtext,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _PinInputContainer(
            fieldKey: const ValueKey('browser_vault_pin_input'),
            controller: _pinCtrl,
            focusNode: _focusNode,
            maxLength: widget.useVaultPin ? 8 : 6,
            hintDots: '•' * _pinLength,
            hasError: _errorText != null || lockoutSec > 0,
            style: style,
            onSubmitted: (_) => _submit(),
          ),
          if (lockoutSec > 0) ...[
            const SizedBox(height: 8),
            Text(
              context.trOr(
                'browser_vault_pin_lockout',
                'Слишком много попыток. Повторите через {seconds} с',
                {'seconds': '$lockoutSec'},
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.error,
              ),
            ),
          ] else if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SheetPillButton(
                  buttonKey: const ValueKey('browser_vault_pin_cancel_btn'),
                  label: context.trOr('common_cancel', 'Отмена'),
                  isPrimary: false,
                  style: style,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetPillButton(
                  buttonKey: const ValueKey('browser_vault_pin_submit_btn'),
                  label: context.trOr('common_confirm', 'Подтвердить'),
                  isPrimary: true,
                  style: style,
                  onTap: _verifying ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrowserVaultCreatePinSheetBody extends StatefulWidget {
  final BrowserVaultAuthGate authGate;

  const _BrowserVaultCreatePinSheetBody({required this.authGate});

  @override
  State<_BrowserVaultCreatePinSheetBody> createState() =>
      _BrowserVaultCreatePinSheetBodyState();
}

class _BrowserVaultCreatePinSheetBodyState
    extends State<_BrowserVaultCreatePinSheetBody> {
  final TextEditingController _pinCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _firstPin;
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _refocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final pin = _pinCtrl.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      HapticUtils.heavy();
      setState(
        () => _errorText = context.trOr(
          'browser_vault_pin_length_error',
          'Введите {count}-значный PIN-код',
          {'count': '4'},
        ),
      );
      return;
    }

    if (_firstPin == null) {
      HapticUtils.selection();
      setState(() {
        _firstPin = pin;
        _errorText = null;
        _pinCtrl.clear();
      });
      _refocus();
      return;
    }

    if (pin != _firstPin) {
      HapticUtils.heavy();
      _pinCtrl.clear();
      setState(
        () => _errorText = context.trOr(
          'browser_vault_create_pin_mismatch',
          'PIN-коды не совпадают. Попробуйте снова',
        ),
      );
      _refocus();
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.authGate.setVaultPin(pin);
      if (!mounted) return;
      HapticUtils.selection();
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = context.trOr(
          'browser_vault_create_pin_error',
          'Не удалось сохранить PIN-код',
        );
      });
    }
  }

  void _handleSecondary() {
    if (_saving) return;
    if (_firstPin != null) {
      HapticUtils.tap();
      setState(() {
        _firstPin = null;
        _errorText = null;
        _pinCtrl.clear();
      });
      _refocus();
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final bool isConfirmStep = _firstPin != null;

    return SingleChildScrollView(
      key: const ValueKey('browser_vault_create_pin_sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinHeaderBadge(
            icon: isConfirmStep
                ? Icons.verified_user_rounded
                : Icons.pin_rounded,
            style: style,
          ),
          const SizedBox(height: 12),
          Text(
            isConfirmStep
                ? context.trOr(
                    'browser_vault_confirm_pin_title',
                    'Подтвердите PIN-код',
                  )
                : context.trOr(
                    'browser_vault_create_pin_title',
                    'Создать PIN-код хранилища',
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isConfirmStep
                ? context.trOr(
                    'browser_vault_confirm_pin_subtitle',
                    'Введите 4-значный PIN-код повторно для подтверждения',
                  )
                : context.trOr(
                    'browser_vault_create_pin_subtitle',
                    'Придумайте 4-значный PIN-код для защиты паролей, карт и адресов',
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: palette.subtext,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _PinInputContainer(
            fieldKey: const ValueKey('browser_vault_create_pin_input'),
            controller: _pinCtrl,
            focusNode: _focusNode,
            maxLength: 4,
            hintDots: '••••',
            hasError: _errorText != null,
            style: style,
            onSubmitted: (_) => _submit(),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SheetPillButton(
                  buttonKey: const ValueKey('browser_vault_create_pin_cancel_btn'),
                  label: isConfirmStep
                      ? context.trOr('common_back', 'Назад')
                      : context.trOr('common_cancel', 'Отмена'),
                  isPrimary: false,
                  style: style,
                  onTap: _saving ? null : _handleSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetPillButton(
                  buttonKey: const ValueKey('browser_vault_create_pin_submit_btn'),
                  label: isConfirmStep
                      ? context.trOr('common_save', 'Сохранить')
                      : context.trOr('common_next', 'Далее'),
                  isPrimary: true,
                  style: style,
                  onTap: _saving ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrowserVaultUnprotectedChoiceBody extends StatelessWidget {
  final String reason;
  final bool allowSkipAuth;

  const _BrowserVaultUnprotectedChoiceBody({
    required this.reason,
    required this.allowSkipAuth,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    return SingleChildScrollView(
      key: const ValueKey('browser_vault_unprotected_sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinHeaderBadge(
            icon: Icons.shield_outlined,
            style: style,
          ),
          const SizedBox(height: 12),
          Text(
            context.trOr(
              'browser_vault_unprotected_title',
              'Защита хранилища не настроена',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
          ),
          if (reason.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              reason.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: palette.onSurface,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            allowSkipAuth
                ? context.trOr(
                    'browser_vault_unprotected_body',
                    'На устройстве не задан PIN-код или системная блокировка экрана. Создайте отдельный PIN-код хранилища или продолжите без проверки.',
                  )
                : context.trOr(
                    'browser_vault_unprotected_body_required',
                    'На устройстве не задан PIN-код или системная блокировка экрана. Создайте PIN-код хранилища для защиты данных.',
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.0,
              color: palette.subtext,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          _SheetPillButton(
            buttonKey: const ValueKey('browser_vault_unprotected_set_pin_btn'),
            label: context.trOr(
              'browser_vault_unprotected_set_pin',
              'Задать PIN-код хранилища',
            ),
            isPrimary: true,
            style: style,
            onTap: () {
              HapticUtils.selection();
              Navigator.of(context).pop(BrowserVaultUnprotectedAction.setVaultPin);
            },
          ),
          if (allowSkipAuth) ...[
            const SizedBox(height: 10),
            _SheetPillButton(
              buttonKey:
                  const ValueKey('browser_vault_unprotected_continue_btn'),
              label: context.trOr(
                'browser_vault_unprotected_continue',
                'Продолжить без PIN-кода',
              ),
              isPrimary: false,
              style: style,
              onTap: () {
                HapticUtils.tap();
                Navigator.of(context)
                    .pop(BrowserVaultUnprotectedAction.continueWithoutPin);
              },
            ),
          ],
          const SizedBox(height: 10),
          _SheetPillButton(
            buttonKey: const ValueKey('browser_vault_unprotected_cancel_btn'),
            label: context.trOr('common_cancel', 'Отмена'),
            isPrimary: false,
            isSubtle: true,
            style: style,
            onTap: () =>
                Navigator.of(context).pop(BrowserVaultUnprotectedAction.cancel),
          ),
        ],
      ),
    );
  }
}

class _PinHeaderBadge extends StatelessWidget {
  final IconData icon;
  final TheavSurfaceStyle style;

  const _PinHeaderBadge({
    required this.icon,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final palette = style.palette;
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: palette.primary.withValues(alpha: style.isDark ? 0.22 : 0.14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 22,
          color: palette.primary,
        ),
      ),
    );
  }
}

class _PinInputContainer extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final String hintDots;
  final bool hasError;
  final TheavSurfaceStyle style;
  final ValueChanged<String> onSubmitted;

  const _PinInputContainer({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.hintDots,
    required this.hasError,
    required this.style,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final palette = style.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: palette.onSurface.withValues(alpha: style.isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasError ? palette.error : palette.divider,
          width: 0.8,
        ),
      ),
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLength),
        ],
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 6,
          color: palette.onSurface,
        ),
        decoration: InputDecoration(
          filled: false,
          fillColor: Colors.transparent,
          hoverColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: hintDots,
          hintStyle: TextStyle(
            color: palette.subtext.withValues(alpha: 0.5),
            letterSpacing: 6,
          ),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _SheetPillButton extends StatelessWidget {
  final Key buttonKey;
  final String label;
  final bool isPrimary;
  final bool isSubtle;
  final TheavSurfaceStyle style;
  final VoidCallback? onTap;

  const _SheetPillButton({
    required this.buttonKey,
    required this.label,
    required this.isPrimary,
    this.isSubtle = false,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = style.palette;
    final Color bgColor = isPrimary
        ? palette.primary
        : (isSubtle
            ? Colors.transparent
            : palette.onSurface.withValues(alpha: style.isDark ? 0.10 : 0.06));
    final Color fgColor = isPrimary
        ? palette.onPrimary
        : (isSubtle ? palette.subtext : palette.onSurface);

    return SizedBox(
      height: 44,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
