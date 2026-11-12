import 'package:flutter/material.dart';
import '../../../utils/haptic_utils.dart';

class SoundOption {
  final String id;
  final String title;

  const SoundOption({required this.id, required this.title});
}

/// Id «без звука». Пустой id ('') — звук по умолчанию.
const String kSilentSoundId = 'none';

// Встроенных звуковых файлов в проекте нет, поэтому доступны только
// «По умолчанию» и «Без звука». На Android конкретный звук чата выбирается
// через системный выбор мелодии (см. NotificationService.pickChatSound).
const List<SoundOption> kAvailableNotificationSounds = [
  SoundOption(id: '', title: 'По умолчанию'),
  SoundOption(id: kSilentSoundId, title: 'Без звука'),
];

const List<SoundOption> kAvailableRingtones = [
  SoundOption(id: '', title: 'По умолчанию'),
  SoundOption(id: kSilentSoundId, title: 'Без мелодии'),
];

/// Нормализует сохранённый id звука: всё, кроме [kSilentSoundId],
/// (включая устаревшие id удалённых встроенных звуков) считается «по умолчанию».
String normalizeSoundId(String? id) => id == kSilentSoundId ? kSilentSoundId : '';

/// Человекочитаемое название сохранённого звука.
String soundOptionLabel(String? id, {bool isRingtone = false}) {
  final normalized = normalizeSoundId(id);
  final options = isRingtone ? kAvailableRingtones : kAvailableNotificationSounds;
  return options.firstWhere((o) => o.id == normalized, orElse: () => options.first).title;
}

class SoundPickerSheet extends StatelessWidget {
  final String? currentSoundId;
  final List<SoundOption> options;
  final String title;
  final ValueChanged<String> onSelected;

  const SoundPickerSheet({
    Key? key,
    required this.currentSoundId,
    required this.options,
    required this.title,
    required this.onSelected,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required String? currentSoundId,
    required ValueChanged<String> onSelected,
    String title = 'Звук уведомления',
    bool isRingtone = false,
  }) {
    HapticUtils.tap();
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SoundPickerSheet(
        currentSoundId: normalizeSoundId(currentSoundId),
        options: isRingtone ? kAvailableRingtones : kAvailableNotificationSounds,
        title: title,
        onSelected: onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedId = currentSoundId ?? '';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final opt = options[index];
                final isSelected = opt.id == selectedId;

                return ListTile(
                  title: Text(opt.title),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Color(0xFF0088CC))
                      : null,
                  onTap: () {
                    HapticUtils.selection();
                    onSelected(opt.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
