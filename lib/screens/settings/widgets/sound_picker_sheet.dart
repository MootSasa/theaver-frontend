import 'package:flutter/material.dart';
import '../../../services/sound_preview_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/design_system/theav_design_system.dart';

class SoundOption {
  final String id;
  final String title;

  const SoundOption({required this.id, required this.title});
}

/// Id «без звука». Пустой id ('') — звук по умолчанию.
const String kSilentSoundId = 'none';

const Set<String> kValidSoundIds = {
  '',
  'crystal',
  'aurora',
  'pulse',
  'bamboo',
  'chime',
  'ringtone_classic',
  kSilentSoundId,
};

const List<SoundOption> kAvailableNotificationSounds = [
  SoundOption(id: '', title: 'По умолчанию'),
  SoundOption(id: 'crystal', title: 'Кристалл (Crystal)'),
  SoundOption(id: 'aurora', title: 'Аврора (Aurora)'),
  SoundOption(id: 'pulse', title: 'Импульс (Pulse)'),
  SoundOption(id: 'bamboo', title: 'Бамбук (Bamboo)'),
  SoundOption(id: 'chime', title: 'Перезвон (Chime)'),
  SoundOption(id: kSilentSoundId, title: 'Без звука'),
];

const List<SoundOption> kAvailableRingtones = [
  SoundOption(id: '', title: 'По умолчанию'),
  SoundOption(id: 'ringtone_classic', title: 'Классический рингтон'),
  SoundOption(id: 'crystal', title: 'Кристалл (Crystal)'),
  SoundOption(id: 'aurora', title: 'Аврора (Aurora)'),
  SoundOption(id: 'pulse', title: 'Импульс (Pulse)'),
  SoundOption(id: 'bamboo', title: 'Бамбук (Bamboo)'),
  SoundOption(id: 'chime', title: 'Перезвон (Chime)'),
  SoundOption(id: kSilentSoundId, title: 'Без мелодии'),
];

/// Нормализует сохранённый id звука: неизвестные id сбрасываются на «По умолчанию».
String normalizeSoundId(String? id) {
  if (id == null || id.isEmpty || id == 'default') return '';
  return kValidSoundIds.contains(id) ? id : '';
}

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
  final bool isRingtone;

  const SoundPickerSheet({
    Key? key,
    required this.currentSoundId,
    required this.options,
    required this.title,
    required this.onSelected,
    this.isRingtone = false,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required String? currentSoundId,
    required ValueChanged<String> onSelected,
    String title = 'Звук уведомления',
    bool isRingtone = false,
  }) {
    HapticUtils.tap();
    return showTheavModalSheet<void>(
      context: context,
      title: title,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      builder: (ctx) => SoundPickerSheet(
        currentSoundId: normalizeSoundId(currentSoundId),
        options: isRingtone ? kAvailableRingtones : kAvailableNotificationSounds,
        title: title,
        onSelected: onSelected,
        isRingtone: isRingtone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = currentSoundId ?? '';

    return ListView.builder(
      shrinkWrap: true,
      itemCount: options.length,
      itemBuilder: (context, index) {
        final opt = options[index];
        final isSelected = opt.id == selectedId;

        return ListTile(
          title: Text(opt.title),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (opt.id != kSilentSoundId)
                IconButton(
                  icon: const Icon(Icons.volume_up_outlined, size: 20),
                  tooltip: 'Прослушать',
                  onPressed: () {
                    HapticUtils.selection();
                    SoundPreviewService.instance.preview(
                      opt.id,
                      isRingtone: isRingtone,
                    );
                  },
                ),
              if (isSelected)
                const Icon(Icons.check, color: Color(0xFF0088CC)),
            ],
          ),
          onTap: () {
            HapticUtils.selection();
            SoundPreviewService.instance.preview(
              opt.id,
              isRingtone: isRingtone,
            );
            onSelected(opt.id);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}
