import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_security_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/settings/settings_floating_header.dart';

class WalletUnlockScreen extends StatefulWidget {
  const WalletUnlockScreen({super.key});

  @override
  State<WalletUnlockScreen> createState() => _WalletUnlockScreenState();
}

class _WalletUnlockScreenState extends State<WalletUnlockScreen> {
  final _passwordController = TextEditingController();
  String _numericInput = '';
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometrics();
    });
  }

  Future<void> _tryBiometrics() async {
    final security = context.read<WalletSecurityProvider>();
    if (security.useBiometrics) {
      setState(() {
        _isLoading = true;
        _error = 'Waiting for fingerprint...';
      });
      
      debugPrint('WalletUnlockScreen: Attempting biometric unlock...');
      final success = await security.unlockWithBiometrics();
      
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Biometric authentication failed')),
          );
          setState(() {
            _error = 'Biometric authentication failed';
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<WalletSecurityProvider>();
    
    return SettingsFloatingScaffold(
      title: 'Unlock Wallet',
      padBodyTop: true,
      body: _buildUnlockContent(security),
    );
  }

  Widget _buildUnlockContent(WalletSecurityProvider security) {
    switch (security.passwordType) {
      case WalletPasswordType.alphanumeric:
        return _buildAlphanumericUnlock(security);
      case WalletPasswordType.numeric:
        return _buildNumericUnlock(security);
      case WalletPasswordType.pattern:
        return _buildPatternUnlock(security);
    }
  }

  Widget _buildAlphanumericUnlock(WalletSecurityProvider security) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _onUnlock(_passwordController.text),
              ),
            ),
            obscureText: true,
            onSubmitted: (v) => _onUnlock(v),
          ),
          if (security.useBiometrics) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _tryBiometrics,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use Biometrics'),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildNumericUnlock(WalletSecurityProvider security) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.blue),
                  const SizedBox(height: 24),
                  const Text('Enter PIN', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      bool filled = index < _numericInput.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? Colors.blue : Colors.grey[300],
                        ),
                      );
                    }),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _buildCustomKeyboard(security),
      ],
    );
  }

  Widget _buildCustomKeyboard(WalletSecurityProvider security) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var j = 1; j <= 3; j++) _buildKey((i * 3 + j).toString()),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (security.useBiometrics)
                _buildKey('biometric', icon: Icons.fingerprint)
              else
                const SizedBox(width: 70),
              _buildKey('0'),
              _buildKey('backspace', icon: Icons.backspace_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String value, {IconData? icon}) {
    return Container(
      width: 70,
      height: 70,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          HapticUtils.tap();
          setState(() {
            _error = null;
            if (value == 'backspace') {
              if (_numericInput.isNotEmpty) {
                _numericInput =
                    _numericInput.substring(0, _numericInput.length - 1);
              }
            } else if (value == 'biometric') {
              _tryBiometrics();
            } else {
              if (_numericInput.length < 6) {
                _numericInput += value;
                if (_numericInput.length == 6) {
                  _onUnlock(_numericInput);
                }
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(35),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 24, color: value == 'biometric' ? Colors.blue : null)
              : Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w400)),
        ),
      ),
    );
  }

  Widget _buildPatternUnlock(WalletSecurityProvider security) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.gesture, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          const Text('Enter Pattern', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _onUnlock('demo_pattern'),
            child: const Text('Unlock (Simulate)'),
          ),
          if (security.useBiometrics) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _tryBiometrics,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use Biometrics'),
            ),
          ]
        ],
      ),
    );
  }

  void _onUnlock(String password) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success = await context.read<WalletSecurityProvider>().unlockWithPassword(password);
    
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
      } else {
        setState(() {
          _error = 'Incorrect password';
          _numericInput = '';
        });
      }
    }
  }
}
