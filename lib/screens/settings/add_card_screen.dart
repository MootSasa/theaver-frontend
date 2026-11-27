import 'package:flutter/material.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'package:provider/provider.dart';
import '../../services/banking_cards_provider.dart';
import '../../l10n/app_localizations.dart';

class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _holderController = TextEditingController();
  final _expiryController = TextEditingController();
  String _cardType = 'Visa';
  int _selectedColor = 0;

  @override
  void dispose() {
    _numberController.dispose();
    _holderController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    
    return SettingsFloatingScaffold(
      title: 'Add Banking Card',
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          SettingsFloatingHeader.topClearanceOf(context) + 12,
          16,
          24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _numberController,
                decoration: const InputDecoration(
                  labelText: 'Card Number',
                  hintText: 'XXXX XXXX XXXX XXXX',
                  prefixIcon: Icon(Icons.credit_card),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter card number';
                  if (value.replaceAll(' ', '').length != 16) return 'Invalid length';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _holderController,
                decoration: const InputDecoration(
                  labelText: 'Card Holder Name',
                  hintText: 'JOHN DOE',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter holder name';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _expiryController,
                decoration: const InputDecoration(
                  labelText: 'Expiry Date',
                  hintText: 'MM/YY',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.datetime,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter expiry date';
                  if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) return 'Use MM/YY format';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Text('Card Type', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  _buildTypeChip('Visa'),
                  const SizedBox(width: 8),
                  _buildTypeChip('Mastercard'),
                  const SizedBox(width: 8),
                  _buildTypeChip('MIR'),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Card Color', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    final colors = [
                      Colors.blue[900],
                      Colors.green[900],
                      Colors.red[900],
                      Colors.purple[900],
                      Colors.black87,
                      Colors.orange[900],
                    ];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = index),
                      child: Container(
                        width: 50,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: colors[index],
                          shape: BoxShape.circle,
                          border: _selectedColor == index
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _saveCard,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Card', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    return ChoiceChip(
      label: Text(type),
      selected: _cardType == type,
      onSelected: (selected) {
        if (selected) setState(() => _cardType = type);
      },
    );
  }

  void _saveCard() async {
    if (_formKey.currentState!.validate()) {
      try {
        await context.read<BankingCardsProvider>().addCard(
          cardNumber: _numberController.text,
          cardHolder: _holderController.text,
          expiryDate: _expiryController.text,
          cardType: _cardType,
          colorIndex: _selectedColor,
        );
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
