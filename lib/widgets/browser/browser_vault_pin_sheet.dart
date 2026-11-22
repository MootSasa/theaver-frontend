import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_lock_service.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Prompts the user to confirm their App Lock PIN inside a Safari Liquid Glass
/// modal sheet before decrypting saved browser credentials or viewing passwords.
///
/// Uses [AppLockService.verifyPin] with `unlockOnSuccess: false` and enforces
/// lockout countdowns when too many incorrect attempts occur.
Future<bool> showBrowserVaultPinSheet(
  BuildContext context, {
  required String reason,
  AppLockService? appLockService,
}) async {
  final AppLockService lock = appLockService ?? AppLockService.instance;
  final bool? ok = await showTheavModalSheet<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.62,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
    builder: (sheetCtx) => _BrowserVaultPinSheetBody(
      reason: reason,
      lockService: lock,
    ),
  );
  return ok ?? false;
}

class _BrowserVaultPinSheetBody extends StatefulWidget {
  final String reason;
  final AppLockService lockService;

  const _BrowserVaultPinSheetBody({
    required this.reason,
    required this.lockService,
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

  @override
  void initState() {
    super.initState();
    _syncLockoutTimer();
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
    if (!widget.lockService.isLockedOut) return;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!widget.lockService.isLockedOut) {
        _lockoutTimer?.cancel();
        setState(() => _errorText = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submit() async {
    if (_verifying) return;
    if (widget.lockService.isLockedOut) {
      HapticUtils.heavy();
      _syncLockoutTimer();
      setState(() {});
      return;
    }
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4) {
      HapticUtils.heavy();
      setState(() => _errorText = 'Введите ${widget.lockService.pinLength}-значный PIN-код');
      return;
    }
    setState(() {
      _verifying = true;
      _errorText = null;
    });
    final bool valid = await widget.lockService.verifyPin(
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
      _errorText = widget.lockService.isLockedOut
          ? null
          : 'Неверный PIN-код';
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final Duration lockout = widget.lockService.lockoutRemaining;
    final int lockoutSec = lockout.inSeconds;

    return Padding(
      key: const ValueKey('browser_vault_pin_sheet'),
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: style.isDark ? 0.22 : 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_person_rounded,
                size: 22,
                color: palette.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Подтверждение доступа',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: palette.onSurface.withValues(alpha: style.isDark ? 0.10 : 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (_errorText != null || lockoutSec > 0)
                    ? palette.error
                    : palette.divider,
                width: 0.8,
              ),
            ),
            child: TextField(
              key: const ValueKey('browser_vault_pin_input'),
              controller: _pinCtrl,
              focusNode: _focusNode,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
                color: palette.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '•' * widget.lockService.pinLength,
                hintStyle: TextStyle(
                  color: palette.subtext.withValues(alpha: 0.5),
                  letterSpacing: 6,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (lockoutSec > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Слишком много попыток. Повторите через $lockoutSec с',
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
                child: SizedBox(
                  height: 44,
                  child: Material(
                    color: palette.onSurface
                        .withValues(alpha: style.isDark ? 0.10 : 0.06),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      key: const ValueKey('browser_vault_pin_cancel_btn'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => Navigator.of(context).pop(false),
                      child: Center(
                        child: Text(
                          'Отмена',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: palette.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Material(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      key: const ValueKey('browser_vault_pin_submit_btn'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: _verifying ? null : _submit,
                      child: Center(
                        child: Text(
                          'Подтвердить',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: palette.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
