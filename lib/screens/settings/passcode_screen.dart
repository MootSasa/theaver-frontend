import 'package:flutter/material.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';

/// Экран настройки PIN-кода для блокировки приложения
class PasscodeScreen extends StatefulWidget {
  const PasscodeScreen({super.key});

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSetting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final lock = context.read<PrivacySettingsProvider>().appLock;
    _isSetting = !lock.hasPin;
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsFloatingScaffold(
      title: l10n.translate('security_pin_code'),
      padBodyTop: true,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isSetting
                  ? l10n.translate('security_set_pin')
                  : l10n.translate('security_change_pin'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
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
              obscureText: true,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: l10n.translate('security_confirm_pin'),
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _savePin,
                child: Text(l10n.translate('security_save_pin')),
              ),
            ),
            if (!_isSetting) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _removePin,
                  child: Text(l10n.translate('security_remove_pin')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _savePin() {
    final pin = _pinController.text;
    final confirm = _confirmController.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN должен быть не менее 4 цифр');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PIN не совпадает');
      return;
    }
    final lock = context.read<PrivacySettingsProvider>().appLock;
    context.read<PrivacySettingsProvider>().saveAppLock(AppLockSettings(
      hasPin: true,
      biometricsEnabled: lock.biometricsEnabled,
      autoLockTimeout: lock.autoLockTimeout,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PIN сохранён')),
    );
    Navigator.pop(context);
  }

  void _removePin() {
    final lock = context.read<PrivacySettingsProvider>().appLock;
    context.read<PrivacySettingsProvider>().saveAppLock(AppLockSettings(
      hasPin: false,
      biometricsEnabled: lock.biometricsEnabled,
      autoLockTimeout: lock.autoLockTimeout,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PIN удалён')),
    );
    Navigator.pop(context);
  }
}
