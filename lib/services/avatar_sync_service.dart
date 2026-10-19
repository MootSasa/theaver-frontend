import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/image_utils.dart';
import 'account_manager.dart';
import 'auth_service.dart';

/// Сервис локального сохранения и бесшовной фоновой загрузки аватарок.
/// 
/// Позволяет немедленно применить несколько выбранных фото профиля локально подряд,
/// сохраняя их во внутреннее хранилище приложения и формируя очередь загрузки.
/// При появлении сети все отложенные фото последовательно загружаются на сервер.
class AvatarSyncService extends ChangeNotifier {
  static final AvatarSyncService _instance = AvatarSyncService._internal();
  factory AvatarSyncService() => _instance;
  AvatarSyncService._internal();

  final AccountManager _accountManager = AccountManager();
  final Set<String> _syncingUsers = {};

  static String _pendingKey(String userId) => 'pending_avatars_$userId';
  static String _historyKey(String userId) => 'local_avatar_history_$userId';

  /// Устанавливает новое фото профиля локально и добавляет его в очередь фоновой загрузки.
  /// Поддерживает добавление нескольких аватарок подряд.
  Future<String> setLocalAvatar(String userId, String sourcePath) async {
    debugPrint('[AvatarSyncService] Setting local avatar for userId=$userId from path=$sourcePath');
    final prefs = await SharedPreferences.getInstance();

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source avatar file does not exist: $sourcePath');
    }

    // 1. Сохраняем файл в постоянную директорию приложения
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${appDir.path}/avatars');
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }

    final localFileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final permanentFile = File('${avatarsDir.path}/$localFileName');
    await sourceFile.copy(permanentFile.path);

    final permanentPath = permanentFile.path;
    debugPrint('[AvatarSyncService] Saved permanent avatar copy to: $permanentPath');

    // Сохраняем стабильную локальную копию текущего аватара: avatar_${userId}_current.jpg
    final currentLocalFile = File('${avatarsDir.path}/avatar_${userId}_current.jpg');
    try {
      await sourceFile.copy(currentLocalFile.path);
    } catch (_) {}

    // 2. Добавляем путь в очередь отложенной загрузки
    final pendingList = prefs.getStringList(_pendingKey(userId)) ?? [];
    if (!pendingList.contains(permanentPath)) {
      pendingList.add(permanentPath);
      await prefs.setStringList(_pendingKey(userId), pendingList);
    }

    // 3. Обновляем локальную историю аватарок (новейшая первая)
    final historyList = prefs.getStringList(_historyKey(userId)) ?? [];
    historyList.remove(permanentPath);
    historyList.insert(0, permanentPath);
    await prefs.setStringList(_historyKey(userId), historyList);

    // 4. Мгновенно обновляем текущий аватар в AccountManager
    await _accountManager.updateAccountProfile(
      userId,
      avatarUrl: permanentPath,
      localAvatarPath: currentLocalFile.path,
    );

    notifyListeners();

    // 5. Запускаем фоновую очередированную синхронизацию с сервером
    syncPendingAvatar(userId);

    return permanentPath;
  }

  /// Возвращает список всех несинхронизированных локальных путей аватарок.
  Future<List<String>> getPendingAvatarPaths(String userId) async {
    if (kIsWeb) return [];
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pendingKey(userId)) ?? [];
    final existing = <String>[];
    for (final p in list) {
      if (await File(p).exists()) {
        existing.add(p);
      }
    }
    return existing;
  }

  /// Возвращает локальную историю аватарок пользователя.
  Future<List<String>> getLocalAvatarUrls(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey(userId)) ?? [];
    final validList = <String>[];
    for (final p in list) {
      if (p.startsWith('http://') || p.startsWith('https://') || p.startsWith('data:') || (!kIsWeb && await File(p).exists())) {
        validList.add(p);
      }
    }
    return validList;
  }

  /// Удаляет аватар из локальной истории, очереди и с диска (если это локальный файл).
  Future<void> removeAvatar(String userId, String avatarUrlOrPath) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingList = prefs.getStringList(_pendingKey(userId)) ?? [];
    if (pendingList.remove(avatarUrlOrPath)) {
      await prefs.setStringList(_pendingKey(userId), pendingList);
    }
    final historyList = prefs.getStringList(_historyKey(userId)) ?? [];
    if (historyList.remove(avatarUrlOrPath)) {
      await prefs.setStringList(_historyKey(userId), historyList);
    }
    if (!kIsWeb &&
        !avatarUrlOrPath.startsWith('http://') &&
        !avatarUrlOrPath.startsWith('https://') &&
        !avatarUrlOrPath.startsWith('data:') &&
        avatarUrlOrPath.contains('/avatars/')) {
      try {
        final f = File(avatarUrlOrPath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Очищает все локальные файлы и ключи аватарок конкретного пользователя (при выходе из аккаунта).
  Future<void> clearUserAvatars(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey(userId));
      await prefs.remove(_historyKey(userId));
      if (!kIsWeb) {
        final appDir = await getApplicationDocumentsDirectory();
        final avatarsDir = Directory('${appDir.path}/avatars');
        if (await avatarsDir.exists()) {
          await for (final entity in avatarsDir.list()) {
            if (entity is File && entity.path.contains('avatar_${userId}_')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Последовательно синхронизирует все отложенные локальные аватары с сервером.
  Future<void> syncPendingAvatar(String userId) async {
    if (kIsWeb) return;
    if (_syncingUsers.contains(userId)) {
      debugPrint('[AvatarSyncService] Sync already in progress for userId=$userId');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    List<String> pendingList = prefs.getStringList(_pendingKey(userId)) ?? [];

    if (pendingList.isEmpty) {
      return;
    }

    _syncingUsers.add(userId);
    debugPrint('[AvatarSyncService] Starting background queue upload for userId=$userId (count=${pendingList.length})');

    try {
      while (pendingList.isNotEmpty) {
        final pendingPath = pendingList.first;
        final pendingFile = File(pendingPath);

        if (!await pendingFile.exists()) {
          debugPrint('[AvatarSyncService] Pending file missing, skipping: $pendingPath');
          pendingList.removeAt(0);
          await prefs.setStringList(_pendingKey(userId), pendingList);
          continue;
        }

        debugPrint('[AvatarSyncService] Uploading avatar in queue: $pendingPath');
        final uploadResult = await AuthService.uploadAvatar(pendingPath);
        debugPrint('[AvatarSyncService] uploadAvatar result: $uploadResult');

        if (uploadResult['success'] == true) {
          final remoteAvatarUrl = uploadResult['avatar_url'] as String?;
          if (remoteAvatarUrl != null && remoteAvatarUrl.isNotEmpty) {
            // Удаляем успешно загруженный из очереди
            pendingList.removeAt(0);
            await prefs.setStringList(_pendingKey(userId), pendingList);

            // Кэшируем байты в DefaultCacheManager, чтобы CachedNetworkImageProvider
            // мог мгновенно отображать аватарку оффлайн
            try {
              final bytes = await pendingFile.readAsBytes();
              await DefaultCacheManager().putFile(
                remoteAvatarUrl,
                bytes,
                fileExtension: 'jpg',
              );
              final validRemote = getValidAvatarUrl(remoteAvatarUrl);
              if (validRemote != null && validRemote != remoteAvatarUrl) {
                await DefaultCacheManager().putFile(
                  validRemote,
                  bytes,
                  fileExtension: 'jpg',
                );
              }
            } catch (e) {
              debugPrint('[AvatarSyncService] Cache put error: $e');
            }

            // Обновляем историю: заменяем локальный путь на серверный URL
            final historyList = prefs.getStringList(_historyKey(userId)) ?? [];
            final idx = historyList.indexOf(pendingPath);
            if (idx != -1) {
              historyList[idx] = remoteAvatarUrl;
              await prefs.setStringList(_historyKey(userId), historyList);
            }

            // Если этот аватар был текущим в AccountManager, обновляем его
            final currentAcc = _accountManager.currentAccount;
            if (currentAcc != null && (currentAcc.avatarUrl == pendingPath || pendingList.isEmpty)) {
              await _accountManager.updateAccountProfile(
                userId,
                avatarUrl: remoteAvatarUrl,
                localAvatarPath: pendingPath,
              );
            }

            debugPrint('[AvatarSyncService] Successfully synced queued avatar for userId=$userId -> $remoteAvatarUrl');
            notifyListeners();
          } else {
            break;
          }
        } else {
          debugPrint('[AvatarSyncService] Queue upload postponed for userId=$userId: ${uploadResult['message']}');
          break; // При ошибке сети останавливаем цикл до следующего восстановительного триггера
        }
      }
    } catch (e) {
      debugPrint('[AvatarSyncService] Background queue upload exception for userId=$userId: $e');
    } finally {
      _syncingUsers.remove(userId);
    }
  }
}
