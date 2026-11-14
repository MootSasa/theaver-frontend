import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Сервис прослушивания встроенных звуков уведомлений и рингтонов.
class SoundPreviewService {
  SoundPreviewService._();

  static final SoundPreviewService instance = SoundPreviewService._();

  AudioPlayer? _player;

  static const Map<String, String> _soundAssets = {
    'crystal': 'assets/sounds/crystal.wav',
    'aurora': 'assets/sounds/aurora.wav',
    'pulse': 'assets/sounds/pulse.wav',
    'bamboo': 'assets/sounds/bamboo.wav',
    'chime': 'assets/sounds/chime.wav',
    'ringtone_classic': 'assets/sounds/ringtone_classic.wav',
  };

  /// Возвращает путь к asset-файлу для переданного id звука, либо `null` для режима без звука.
  static String? assetForSoundId(String? soundId, {bool isRingtone = false}) {
    if (soundId == 'none') return null;
    if (soundId == null || soundId.isEmpty || soundId == 'default') {
      return isRingtone
          ? _soundAssets['ringtone_classic']
          : _soundAssets['crystal'];
    }
    return _soundAssets[soundId] ?? _soundAssets['crystal'];
  }

  /// Проигрывает предпрослушивание звука по id. Для `'none'` останавливает текущее воспроизведение.
  Future<void> preview(String? soundId, {bool isRingtone = false}) async {
    final assetPath = assetForSoundId(soundId, isRingtone: isRingtone);
    if (assetPath == null) {
      await stop();
      return;
    }

    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.setAsset(assetPath);
      await _player!.play();
    } catch (e) {
      debugPrint('SoundPreviewService: preview error for $soundId: $e');
    }
  }

  /// Останавливает активное предпрослушивание.
  Future<void> stop() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.stop();
    } catch (e) {
      debugPrint('SoundPreviewService: stop error: $e');
    }
  }

  /// Освобождает ресурсы плеера.
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (e) {
      debugPrint('SoundPreviewService: dispose error: $e');
    }
  }
}
