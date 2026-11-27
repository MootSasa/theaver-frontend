import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_lock_service.dart';
import '../../services/privacy_settings_provider.dart';
import '../../widgets/settings/settings_floating_header.dart';

/// Screen for setting, changing, or removing the local App Lock PIN.
class PasscodeScreen extends StatefulWidget {
  const PasscodeScreen({super.key});

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  final _currentPinController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  int _selectedLength = 4;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedLength = AppLockService.instance.pinLength;
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _tr(AppLocalizations l10n, String key, String fallback) {
    final val = l10n.translate(key);
    return val == key ? fallback : val;
  }

  Future<void> _savePin() async {
    final l10n = context.l10n;
    final appLock = AppLockService.instance;
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (appLock.isLockedOut) {
      setState(() => _error = _tr(
            l10n,
            'app_lock_locked_out_seconds',
            'Подождите {seconds} сек.',
          ).replaceAll('{seconds}', '${appLock.lockoutRemaining.inSeconds}'));
      return;
    }

    if (appLock.hasPin && _currentPinController.text.trim().isEmpty) {
      setState(
        () => _error = _tr(
          l10n,
          'app_lock_current_pin_required',
          'Введите текущий PIN',
        ),
      );
      return;
    }

    if (!RegExp(r'^\d+$').hasMatch(pin) || pin.length != _selectedLength) {
      setState(
        () => _error = _tr(
          l10n,
          'app_lock_pin_length_error',
          'PIN должен состоять из $_selectedLength цифр',
        ).replaceAll('{length}', '$_selectedLength'),
      );
      return;
    }

    if (pin != confirm) {
      setState(
        () => _error = _tr(
          l10n,
          'app_lock_pin_mismatch',
          'PIN не совпадает',
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await appLock.setPin(
      pin,
      currentPin: appLock.hasPin ? _currentPinController.text.trim() : null,
    );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = appLock.isLockedOut
            ? _tr(
                l10n,
                'app_lock_locked_out_seconds',
                'Подождите {seconds} сек.',
              ).replaceAll(
                '{seconds}',
                '${appLock.lockoutRemaining.inSeconds}',
              )
            : _tr(l10n, 'app_lock_wrong_pin', 'Неверный текущий PIN');
      });
      return;
    }

    await context
        .read<PrivacySettingsProvider>()
        .saveAppLock(appLock.toAppLockSettings());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tr(l10n, 'app_lock_pin_saved', 'PIN сохранён')),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _removePin() async {
    final l10n = context.l10n;
    final appLock = AppLockService.instance;
    final currentPin = _currentPinController.text.trim();

    if (appLock.isLockedOut) {
      setState(() => _error = _tr(
            l10n,
            'app_lock_locked_out_seconds',
            'Подождите {seconds} сек.',
          ).replaceAll('{seconds}', '${appLock.lockoutRemaining.inSeconds}'));
      return;
    }

    if (currentPin.isEmpty) {
      setState(
        () => _error = _tr(
          l10n,
          'app_lock_current_pin_required',
          'Введите текущий PIN',
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await appLock.disablePin(currentPin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = _tr(l10n, 'app_lock_wrong_pin', 'Неверный текущий PIN');
      });
      return;
    }

    await context
        .read<PrivacySettingsProvider>()
        .saveAppLock(appLock.toAppLockSettings());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tr(l10n, 'app_lock_pin_removed', 'PIN удалён')),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final appLock = context.watch<AppLockService>();
    final hasPin = appLock.hasPin;

    return SettingsFloatingScaffold(
      title: l10n.translate('security_pin_code'),
      padBodyTop: true,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            hasPin
                ? l10n.translate('security_change_pin')
                : l10n.translate('security_set_pin'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [4, 6].map((len) {
              final selected = _selectedLength == len;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$len ${_tr(l10n, 'app_lock_digits', 'цифр')}'),
                  selected: selected,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                            _selectedLength = len;
                            _error = null;
                          }),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (hasPin) ...[
            TextField(
              controller: _currentPinController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              obscureText: true,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: _tr(
                  l10n,
                  'app_lock_current_pin',
                  'Текущий PIN',
                ),
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            maxLength: _selectedLength,
            decoration: InputDecoration(
              labelText: l10n.translate('security_enter_pin'),
              counterText: '',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            maxLength: _selectedLength,
            decoration: InputDecoration(
              labelText: l10n.translate('security_confirm_pin'),
              counterText: '',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _savePin,
              child: Text(l10n.translate('security_save_pin')),
            ),
          ),
          if (hasPin) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _removePin,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(l10n.translate('security_remove_pin')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
