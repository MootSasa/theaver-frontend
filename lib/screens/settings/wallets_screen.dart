import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../widgets/settings/settings_floating_header.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/banking_cards_provider.dart';
import '../../services/wallet_security_provider.dart';
import '../../widgets/settings/card_widget.dart';
import 'add_card_screen.dart';
import 'wallet_setup_screen.dart';
import 'wallet_unlock_screen.dart';

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSecurity();
    });
  }

  void _checkSecurity() {
    final security = context.read<WalletSecurityProvider>();
    if (!security.isInitialized) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
      );
    } else if (!security.isUnlocked) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WalletUnlockScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final security = context.watch<WalletSecurityProvider>();
    
    if (!security.isUnlocked) {
      return SettingsFloatingScaffold(
        title: l10n.translate('settings_wallets_cards'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Wallet is locked'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _checkSecurity,
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      );
    }
    
    final headerFg = Theme.of(context).colorScheme.onSurface;
    return SettingsFloatingScaffold(
      title: l10n.translate('settings_wallets_cards'),
      actions: [
        SettingsHeaderAction(
          icon: iconoir.Lock(width: 21, height: 21, color: headerFg),
          onTap: () => security.lock(),
          tooltip: 'Lock Wallet',
        ),
      ],
      body: Consumer<BankingCardsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.cards.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.credit_card_off, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No cards added yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              SettingsFloatingHeader.topClearanceOf(context) + 12,
              16,
              88,
            ),
            itemCount: provider.cards.length,
            itemBuilder: (context, index) {
              final card = provider.cards[index];
              return CardWidget(
                card: card,
                onDelete: () => _confirmDelete(context, provider, card.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddCardScreen()),
          );
        },
        label: const Text('Add Card'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(BuildContext context, BankingCardsProvider provider, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Are you sure you want to delete this card?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteCard(id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
