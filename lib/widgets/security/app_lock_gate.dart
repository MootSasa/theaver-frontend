import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/app_lock_service.dart';

/// Root App Lock overlay enforcing lifecycle privacy shielding and PIN/biometric unlock.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final FocusNode _keyboardFocusNode = FocusNode();
  String _enteredPin = '';
  bool _hasError = false;
  bool _biometricPromptedForCurrentLock = false;
  bool _wasLocked = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.instance.addListener(_onServiceChanged);
    _syncLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppLockService.instance.removeListener(_onServiceChanged);
    _countdownTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLockService.instance.onAppLifecycleChanged(state);
  }

  void _onServiceChanged() {
    if (!mounted) return;
    _syncLockState();
    setState(() {});
  }

  void _syncLockState() {
    final svc = AppLockService.instance;
    final shouldShowLock =
        svc.isLocked && svc.hasPin && AccountManager().hasSavedAccount;

    if (shouldShowLock && !_wasLocked) {
      _enteredPin = '';
      _hasError = false;
      _biometricPromptedForCurrentLock = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _keyboardFocusNode.requestFocus();
        _maybeTriggerBiometrics();
      });
    } else if (!shouldShowLock && _wasLocked) {
      _enteredPin = '';
      _hasError = false;
      _biometricPromptedForCurrentLock = false;
    }
    _wasLocked = shouldShowLock;

    if (svc.isLockedOut && _countdownTimer == null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (!AppLockService.instance.isLockedOut) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
        }
        setState(() {});
      });
    } else if (!svc.isLockedOut && _countdownTimer != null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  Future<void> _maybeTriggerBiometrics() async {
    final svc = AppLockService.instance;
    if (_biometricPromptedForCurrentLock ||
        !svc.isLocked ||
        !svc.biometricsEnabled ||
        svc.isLockedOut ||
        kIsWeb) {
      return;
    }
    _biometricPromptedForCurrentLock = true;
    final reason = context.mounted
        ? context.l10n.translate('app_lock_biometric_reason')
        : 'Unlock Theaver';
    await svc.authenticateWithBiometrics(reason);
  }

  void _onDigitPressed(String digit) async {
    final svc = AppLockService.instance;
    if (svc.isLockedOut) return;
    if (_enteredPin.length >= svc.pinLength) return;

    HapticFeedback.selectionClick();
    setState(() {
      _hasError = false;
      _enteredPin += digit;
    });

    if (_enteredPin.length == svc.pinLength) {
      final ok = await svc.verifyPin(_enteredPin);
      if (!mounted) return;
      if (!ok) {
        HapticFeedback.heavyImpact();
        setState(() {
          _hasError = true;
          _enteredPin = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _hasError = false;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _onBackspace();
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.length == 1) {
      final code = char.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        _onDigitPressed(char);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  String _tr(AppLocalizations l10n, String key, String fallback) {
    final val = l10n.translate(key);
    return val == key ? fallback : val;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AppLockService>();
    final hasAccount = AccountManager().hasSavedAccount;
    final showLockOverlay = svc.isLocked && svc.hasPin && hasAccount;
    final showPrivacyShield =
        svc.isPrivacyShieldActive && svc.hasPin && hasAccount && !showLockOverlay;

    return Stack(
      children: [
        widget.child,
        if (showPrivacyShield)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  color: Theme.of(context)
                      .scaffoldBackgroundColor
                      .withValues(alpha: 0.92),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Theaver',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (showLockOverlay)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Focus(
                focusNode: _keyboardFocusNode,
                autofocus: true,
                onKeyEvent: _handleKeyEvent,
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: _buildLockBody(context, svc),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLockBody(BuildContext context, AppLockService svc) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lockoutSec = svc.lockoutRemaining.inSeconds;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_rounded,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          _tr(l10n, 'app_lock_enter_passcode', 'Введите код-пароль'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(svc.pinLength, (i) {
            final filled = i < _enteredPin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hasError
                    ? theme.colorScheme.error
                    : (filled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest),
                border: Border.all(
                  color: _hasError
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 24,
          child: lockoutSec > 0
              ? Text(
                  _tr(
                    l10n,
                    'app_lock_locked_out_seconds',
                    'Подождите {seconds} сек.',
                  ).replaceAll('{seconds}', '$lockoutSec'),
                  style: TextStyle(color: theme.colorScheme.error),
                )
              : (_hasError
                  ? Text(
                      _tr(l10n, 'app_lock_wrong_pin', 'Неверный код-пароль'),
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : const SizedBox.shrink()),
        ),
        const SizedBox(height: 20),
        _buildKeypad(context, svc),
      ],
    );
  }

  Widget _buildKeypad(BuildContext context, AppLockService svc) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row
                  .map((d) => _KeypadButton(
                        label: d,
                        onTap: () => _onDigitPressed(d),
                      ))
                  .toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: svc.biometricsEnabled
                  ? IconButton(
                      icon: const Icon(Icons.fingerprint_rounded, size: 32),
                      onPressed: () {
                        _biometricPromptedForCurrentLock = false;
                        _maybeTriggerBiometrics();
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            _KeypadButton(
              label: '0',
              onTap: () => _onDigitPressed('0'),
            ),
            SizedBox(
              width: 72,
              height: 72,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined, size: 26),
                onPressed: _enteredPin.isNotEmpty ? _onBackspace : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeypadButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
