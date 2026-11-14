import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_security_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/settings/settings_floating_header.dart';

class WalletSetupScreen extends StatefulWidget {
  const WalletSetupScreen({super.key});

  @override
  State<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  WalletPasswordType? _selectedType;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String _numericPassword = '';
  String _numericConfirm = '';
  bool _isConfirming = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedType == null) {
      return _buildTypeSelection();
    }

    return SettingsFloatingScaffold(
      title: _isConfirming ? 'Confirm Password' : 'Set Password',
      padBodyTop: true,
      onBack: () {
        if (_isConfirming) {
          setState(() {
            _isConfirming = false;
            _numericConfirm = '';
            _confirmController.clear();
          });
        } else {
          setState(() => _selectedType = null);
        }
      },
      body: _buildPasswordInput(),
    );
  }

  Widget _buildTypeSelection() {
    return SettingsFloatingScaffold(
      title: 'Wallet Security',
      padBodyTop: true,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose how you want to protect your wallet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildTypeOption(
              icon: Icons.password,
              title: 'Alphanumeric',
              subtitle: 'Letters, numbers and symbols',
              type: WalletPasswordType.alphanumeric,
            ),
            const SizedBox(height: 16),
            _buildTypeOption(
              icon: Icons.numbers,
              title: 'Numeric PIN',
              subtitle: 'Simple 4-6 digit code',
              type: WalletPasswordType.numeric,
            ),
            const SizedBox(height: 16),
            _buildTypeOption(
              icon: Icons.gesture,
              title: 'Pattern',
              subtitle: 'Graphical pattern lock',
              type: WalletPasswordType.pattern,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required WalletPasswordType type,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    switch (_selectedType!) {
      case WalletPasswordType.alphanumeric:
        return _buildAlphanumericInput();
      case WalletPasswordType.numeric:
        return _buildNumericInput();
      case WalletPasswordType.pattern:
        return _buildPatternInput();
    }
  }

  Widget _buildAlphanumericInput() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          TextField(
            controller: _isConfirming ? _confirmController : _passwordController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _isConfirming ? 'Confirm Password' : 'New Password',
              errorText: _error,
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (!_isConfirming) {
                if (_passwordController.text.length < 4) {
                  setState(() => _error = 'Password too short');
                } else {
                  setState(() {
                    _isConfirming = true;
                    _error = null;
                  });
                }
              } else {
                if (_passwordController.text != _confirmController.text) {
                  setState(() => _error = 'Passwords do not match');
                } else {
                  _showBiometricDialog(_passwordController.text);
                }
              }
            },
            child: Text(_isConfirming ? 'Confirm' : 'Next'),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericInput() {
    final currentInput = _isConfirming ? _numericConfirm : _numericPassword;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    _isConfirming ? 'Confirm your PIN' : 'Enter a new PIN',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      bool filled = index < currentInput.length;
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
        _buildCustomKeyboard(),
      ],
    );
  }

  Widget _buildCustomKeyboard() {
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
              if (_isConfirming) {
                if (_numericConfirm.isNotEmpty)
                  _numericConfirm =
                      _numericConfirm.substring(0, _numericConfirm.length - 1);
              } else {
                if (_numericPassword.isNotEmpty)
                  _numericPassword = _numericPassword.substring(
                      0, _numericPassword.length - 1);
              }
            } else {
              if (_isConfirming) {
                if (_numericConfirm.length < 6) _numericConfirm += value;
                if (_numericConfirm.length == 6) {
                  if (_numericPassword == _numericConfirm) {
                    _showBiometricDialog(_numericPassword);
                  } else {
                    _error = 'PINs do not match';
                    _numericConfirm = '';
                  }
                }
              } else {
                if (_numericPassword.length < 6) _numericPassword += value;
                if (_numericPassword.length == 6) {
                  _isConfirming = true;
                }
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(35),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 24)
              : Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w400)),
        ),
      ),
    );
  }

  Widget _buildPatternInput() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.gesture, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Pattern Lock (TODO)', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _showBiometricDialog('demo_pattern'),
            child: const Text('Simulate Set Pattern'),
          ),
        ],
      ),
    );
  }

  void _showBiometricDialog(String password) async {
    final security = context.read<WalletSecurityProvider>();
    final canFingerprint = await security.canUseFingerprint();

    if (!canFingerprint) {
      await security.initialize(password, _selectedType!, false);
      if (mounted) Navigator.pop(context);
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fingerprint, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Use Fingerprint?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Would you like to enable fingerprint to quickly unlock your cards? Face recognition is disabled for security.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await security.initialize(password, _selectedType!, false);
                      if (mounted) {
                        Navigator.pop(context); // Close sheet
                        Navigator.pop(this.context); // Close setup screen
                      }
                    },
                    child: const Text('No, thanks'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await security.initialize(password, _selectedType!, true);
                      if (mounted) {
                        Navigator.pop(context); // Close sheet
                        Navigator.pop(this.context); // Close setup screen
                      }
                    },
                    child: const Text('Enable'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
