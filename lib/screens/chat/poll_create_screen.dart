import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/glass_toast_service.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';

/// Экран создания опроса — вопрос, варианты и настройки в стиле Telegram
/// (сохранение/отправка строго через правую кнопку `✓` в [SettingsFloatingHeader]).
class PollCreateScreen extends StatefulWidget {
  final String chatId;

  const PollCreateScreen({super.key, required this.chatId});

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
      if (_correctOptionId != null) {
        if (_correctOptionId == index) {
          _correctOptionId = null;
        } else if (_correctOptionId! > index) {
          _correctOptionId = _correctOptionId! - 1;
        }
      }
    });
  }

  Future<void> _sendPoll() async {
    final l10n = context.l10n;
    if (_questionController.text.trim().isEmpty) {
      GlassToastService().showError(
        context,
        l10n.translate('poll_error_question_empty'),
      );
      return;
    }

    final options = <String>[];
    int? mappedCorrectOptionId;
    for (int i = 0; i < _optionControllers.length; i++) {
      final text = _optionControllers[i].text.trim();
      if (text.isNotEmpty) {
        if (_isQuiz && _correctOptionId == i) {
          mappedCorrectOptionId = options.length;
        }
        options.add(text);
      }
    }

    if (options.length < 2) {
      GlassToastService().showError(
        context,
        l10n.translate('poll_error_min_options'),
      );
      return;
    }

    if (_isQuiz && mappedCorrectOptionId == null) {
      GlassToastService().showError(
        context,
        l10n.translate('poll_error_quiz_no_answer'),
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
          'is_multiple_choice': _isQuiz ? false : _isMultipleChoice,
          'is_quiz': _isQuiz,
          if (_isQuiz && mappedCorrectOptionId != null)
            'correct_option_id': mappedCorrectOptionId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final int remainingOptions = 10 - _optionControllers.length;
    final bottomPad = MediaQuery.paddingOf(context).bottom + 24.0;

    return SettingsFloatingScaffold(
      title: l10n.translate('poll_create_title'),
      backgroundColor: palette.background,
      actions: [
        if (_isSending)
          SettingsHeaderAction(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primary,
              ),
            ),
          )
        else
          SettingsHeaderAction(
            icon: iconoir.Check(
              width: 22,
              height: 22,
              color: palette.primary,
            ),
            foregroundColor: palette.primary,
            tooltip: l10n.translate('poll_create_send'),
            onTap: _sendPoll,
          ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          SettingsFloatingHeader.topClearanceOf(context) + 12,
          0,
          bottomPad,
        ),
        children: [
          TheavInsetGroup(
            header: 'ВОПРОС',
            dividerIndent: 16,
            children: [
              TheavInlineTextField(
                controller: _questionController,
                placeholder: l10n.translate('poll_create_question_hint'),
                maxLength: 200,
                maxLines: 3,
                minLines: 1,
                showCounter: true,
                autofocus: true,
                textInputAction: TextInputAction.next,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TheavInsetGroup(
            header: l10n.translate('poll_create_options_label').toUpperCase(),
            dividerIndent: 16,
            footer: remainingOptions > 0
                ? l10n
                    .translate('poll_create_remaining_options')
                    .replaceAll('{count}', '$remainingOptions')
                : l10n.translate('poll_create_max_options'),
            children: [
              for (int i = 0; i < _optionControllers.length; i++)
                TheavInlineTextField(
                  controller: _optionControllers[i],
                  maxLength: 100,
                  placeholder:
                      '${l10n.translate('poll_create_option')} ${i + 1}',
                  prefix: _isQuiz
                      ? Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: TheavCheckCircle(
                            selected: _correctOptionId == i,
                            onTap: () => setState(() => _correctOptionId = i),
                          ),
                        )
                      : null,
                  suffix: _optionControllers.length > 2
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _removeOption(i),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: iconoir.Xmark(
                              width: 18,
                              height: 18,
                              color: palette.subtext,
                            ),
                          ),
                        )
                      : null,
                ),
              if (_optionControllers.length < 10)
                TheavListRow(
                  leading: iconoir.Plus(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: l10n.translate('poll_create_add_option'),
                  onTap: _addOption,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TheavInsetGroup(
            header: 'ПАРАМЕТРЫ',
            dividerIndent: 16,
            children: [
              TheavListRow(
                title: l10n.translate('poll_create_anonymous'),
                subtitle: l10n.translate('poll_create_anonymous_desc'),
                trailing: TheavSwitch(
                  value: _isAnonymous,
                  onChanged: (v) => setState(() => _isAnonymous = v),
                ),
                onTap: () => setState(() => _isAnonymous = !_isAnonymous),
              ),
              TheavListRow(
                title: l10n.translate('poll_create_multiple'),
                enabled: !_isQuiz,
                trailing: TheavSwitch(
                  value: _isMultipleChoice,
                  onChanged: _isQuiz
                      ? null
                      : (v) => setState(() => _isMultipleChoice = v),
                ),
                onTap: _isQuiz
                    ? null
                    : () => setState(
                          () => _isMultipleChoice = !_isMultipleChoice,
                        ),
              ),
              TheavListRow(
                title: l10n.translate('poll_create_quiz'),
                subtitle: l10n.translate('poll_create_quiz_desc'),
                trailing: TheavSwitch(
                  value: _isQuiz,
                  onChanged: (v) => setState(() {
                    _isQuiz = v;
                    if (v) {
                      _isMultipleChoice = false;
                    } else {
                      _correctOptionId = null;
                    }
                  }),
                ),
                onTap: () => setState(() {
                  _isQuiz = !_isQuiz;
                  if (_isQuiz) {
                    _isMultipleChoice = false;
                  } else {
                    _correctOptionId = null;
                  }
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
