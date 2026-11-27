import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Choice returned by [showSendOptionsPopup].
enum SendOptionChoice {
  sendSilent,
  schedule,
  sendWhenOnline,
  sendWithEffect,
}

/// Telegram-style send options sheet shown when long-pressing the Send button
/// (`Отправить без звука`, `Отправить позже`, `Отправить, когда будет в сети`).
Future<SendOptionChoice?> showSendOptionsPopup({
  required BuildContext context,
  bool isPrivateChat = false,
  bool isPeerOnline = true,
  bool showSilentOption = true,
  bool showEffectOption = true,
}) {
  return showTheavModalSheet<SendOptionChoice>(
    context: context,
    title: 'Способ отправки',
    showCloseButton: true,
    builder: (ctx) {
      final palette = ctx.theav;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TheavInsetGroup(
            margin: const EdgeInsets.only(bottom: 8),
            children: [
              if (showSilentOption)
                TheavListRow(
                  leading: iconoir.BellOff(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Отправить без звука',
                  subtitle: 'У получателя не прозвучит уведомление',
                  onTap: () =>
                      Navigator.of(ctx).pop(SendOptionChoice.sendSilent),
                ),
              TheavListRow(
                leading: iconoir.Calendar(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Отправить позже',
                subtitle: 'Выбрать точную дату и время',
                showChevron: true,
                onTap: () => Navigator.of(ctx).pop(SendOptionChoice.schedule),
              ),
              if (isPrivateChat && !isPeerOnline)
                TheavListRow(
                  leading: iconoir.Wifi(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Отправить, когда будет в сети',
                  subtitle: 'Автоматически доставится при появлении онлайн',
                  onTap: () =>
                      Navigator.of(ctx).pop(SendOptionChoice.sendWhenOnline),
                ),
              if (showEffectOption)
                TheavListRow(
                  leading: iconoir.Sparks(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Отправить с эффектом',
                  subtitle: 'Выбрать анимацию к сообщению',
                  showChevron: true,
                  onTap: () =>
                      Navigator.of(ctx).pop(SendOptionChoice.sendWithEffect),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// Dual-mode Telegram schedule date & time sheet returning a future [DateTime]
/// (in UTC) or `null` if cancelled.
Future<DateTime?> showTheavScheduleSheet({
  required BuildContext context,
  DateTime? initialDateTime,
  String confirmLabel = 'Запланировать',
}) {
  final now = DateTime.now();
  final DateTime initial =
      (initialDateTime != null && initialDateTime.isAfter(now))
          ? initialDateTime
          : now.add(const Duration(minutes: 15));

  return showTheavModalSheet<DateTime>(
    context: context,
    title: 'Отправить позже',
    showCloseButton: true,
    builder: (ctx) => _TheavScheduleSheetBody(
      initialLocal: initial.toLocal(),
      confirmLabel: confirmLabel,
    ),
  );
}

class _TheavScheduleSheetBody extends StatefulWidget {
  final DateTime initialLocal;
  final String confirmLabel;

  const _TheavScheduleSheetBody({
    required this.initialLocal,
    required this.confirmLabel,
  });

  @override
  State<_TheavScheduleSheetBody> createState() =>
      _TheavScheduleSheetBodyState();
}

class _TheavScheduleSheetBodyState extends State<_TheavScheduleSheetBody> {
  late DateTime _selected;
  int _quickPreset = 0; // 0: custom/today, 1: +1h, 2: tomorrow 09:00

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocal;
  }

  void _applyPreset(int idx) {
    HapticUtils.selection();
    final now = DateTime.now();
    setState(() {
      _quickPreset = idx;
      if (idx == 0) {
        _selected = now.add(const Duration(minutes: 15));
      } else if (idx == 1) {
        _selected = now.add(const Duration(hours: 1));
      } else {
        final tomorrow = now.add(const Duration(days: 1));
        _selected = DateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          9,
          0,
        );
      }
    });
  }

  String _formatDateTimeLabel(DateTime dt) {
    const months = [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final DateTime minDt = DateTime.now().add(const Duration(minutes: 1));
    final DateTime safeSelected =
        _selected.isBefore(minDt) ? minDt : _selected;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TheavSegmentedControl<int>(
          useGlass: false,
          options: const [
            TheavSegmentOption(value: 0, label: 'Сегодня'),
            TheavSegmentOption(value: 1, label: 'Через час'),
            TheavSegmentOption(value: 2, label: 'Завтра 9:00'),
          ],
          selected: _quickPreset,
          onChanged: _applyPreset,
          margin: const EdgeInsets.only(bottom: 12),
        ),
        TheavInsetGroup(
          margin: const EdgeInsets.only(bottom: 14),
          children: [
            SizedBox(
              height: 180,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: palette.onSurface,
                      fontSize: 18,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: ValueKey<int>(_quickPreset),
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  initialDateTime: safeSelected,
                  minimumDate: DateTime.now().subtract(
                    const Duration(minutes: 1),
                  ),
                  maximumDate: DateTime.now().add(const Duration(days: 365)),
                  onDateTimeChanged: (dt) {
                    setState(() => _selected = dt);
                  },
                ),
              ),
            ),
          ],
        ),
        TheavFloatingPillButton(
          label: '${widget.confirmLabel} (${_formatDateTimeLabel(safeSelected)})',
          icon: iconoir.Send(
            width: 17,
            height: 17,
            color: palette.onPrimary,
          ),
          isPrimary: true,
          onTap: () => Navigator.of(context).pop(safeSelected.toUtc()),
        ),
      ],
    );
  }
}
