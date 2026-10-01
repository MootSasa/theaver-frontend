import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/auth_service.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/adaptive_switch.dart';

/// Экран создания опроса — вопрос + варианты + настройки
class PollCreateScreen extends StatefulWidget {
  final String chatId;

  const PollCreateScreen({Key? key, required this.chatId}) : super(key: key);

  @override
  State<PollCreateScreen> createState() => _PollCreateScreenState();
}

class _PollCreateScreenState extends State<PollCreateScreen> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isAnonymous = false;
  bool _isMultipleChoice = false;
  bool _isQuiz = false;
  int? _correctOptionId;
  bool _isSending = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 10) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
      if (_correctOptionId == index) _correctOptionId = null;
    });
  }

  Future<void> _sendPoll() async {
    final l10n = context.l10n;
    if (_questionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('poll_error_question_empty'))),
      );
      return;
    }

    final options = _optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('poll_error_min_options'))),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.post(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/polls',
        data: {
          'question': _questionController.text.trim(),
          'options': options,
          'is_anonymous': _isAnonymous,
          'is_multiple_choice': _isMultipleChoice,
          'is_quiz': _isQuiz,
          if (_isQuiz && _correctOptionId != null)
            'correct_option_id': _correctOptionId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('poll_create_title')),
        actions: [
          TextButton(
            onPressed: _isSending ? null : _sendPoll,
            child: _isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.translate('poll_create_send'), style: TextStyle(color: theme.colorScheme.primary)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Question
          TextField(
            controller: _questionController,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: l10n.translate('poll_create_question_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Options
          Text(l10n.translate('poll_create_options_label'),
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (int i = 0; i < _optionControllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                if (_isQuiz)
                  Radio<int>(
                    value: i,
                    groupValue: _correctOptionId,
                    onChanged: (v) => setState(() => _correctOptionId = v),
                  ),
                Expanded(
                  child: TextField(
                    controller: _optionControllers[i],
                    maxLength: 100,
                    decoration: InputDecoration(
                      hintText: '${l10n.translate('poll_create_option')} ${i + 1}',
                      counterText: '',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_optionControllers.length > 2)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _removeOption(i),
                  ),
              ]),
            ),
          if (_optionControllers.length < 10)
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add),
              label: Text(l10n.translate('poll_create_add_option')),
            ),
          const SizedBox(height: 16),

          // Settings
          AdaptiveSwitchListTile(
            title: Text(l10n.translate('poll_create_anonymous')),
            subtitle: Text(l10n.translate('poll_create_anonymous_desc')),
            value: _isAnonymous,
            onChanged: (v) => setState(() => _isAnonymous = v),
          ),
          AdaptiveSwitchListTile(
            title: Text(l10n.translate('poll_create_multiple')),
            value: _isMultipleChoice,
            onChanged: (v) => setState(() => _isMultipleChoice = v),
          ),
          AdaptiveSwitchListTile(
            title: Text(l10n.translate('poll_create_quiz')),
            subtitle: Text(l10n.translate('poll_create_quiz_desc')),
            value: _isQuiz,
            onChanged: (v) => setState(() {
              _isQuiz = v;
              if (!v) _correctOptionId = null;
            }),
          ),
        ],
      ),
    );
  }
}
