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
  Future<String> setLocalAvatar(
    String userId,
    String sourcePath, {
    String? avatarCrop,
  }) async {
    debugPrint('[AvatarSyncService] Setting local avatar for userId=$userId from path=$sourcePath');
    final prefs = await SharedPreferences.getInstance();

    final cleanSourcePath = stripAvatarCropFragment(sourcePath) ?? sourcePath;
    final sourceFile = File(cleanSourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source avatar file does not exist: $cleanSourcePath');
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
    invalidateLocalAvatarCache(permanentPath);
    invalidateLocalAvatarCache(currentLocalFile.path);

    final AvatarCropSpec? cropSpec = AvatarCropSpec.tryParseParam(avatarCrop) ??
        AvatarCropSpec.split(sourcePath).crop;
    final String permanentEntry =
        cropSpec != null ? cropSpec.attachToUrl(permanentPath) : permanentPath;
    final String currentEntry = cropSpec != null
        ? cropSpec.attachToUrl(currentLocalFile.path)
        : currentLocalFile.path;

    // 2. Добавляем путь в очередь отложенной загрузки
    final pendingList = prefs.getStringList(_pendingKey(userId)) ?? [];
    if (!pendingList.contains(permanentEntry)) {
      pendingList.add(permanentEntry);
      await prefs.setStringList(_pendingKey(userId), pendingList);
    }

    // 3. Обновляем локальную историю аватарок (новейшая первая)
    final historyList = prefs.getStringList(_historyKey(userId)) ?? [];
    historyList.remove(permanentEntry);
    historyList.insert(0, permanentEntry);
    await prefs.setStringList(_historyKey(userId), historyList);

    // 4. Мгновенно обновляем текущий аватар в AccountManager
    await _accountManager.updateAccountProfile(
      userId,
      avatarUrl: permanentEntry,
      localAvatarPath: currentEntry,
    );

    notifyListeners();

    // 5. Запускаем фоновую очередированную синхронизацию с сервером
    syncPendingAvatar(userId);

    return permanentEntry;
  }

  /// Возвращает список всех несинхронизированных локальных путей аватарок.
  Future<List<String>> getPendingAvatarPaths(String userId) async {
    if (kIsWeb) return [];
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pendingKey(userId)) ?? [];
    final existing = <String>[];
    for (final p in list) {
      final clean = stripAvatarCropFragment(p) ?? p;
      if (await File(clean).exists()) {
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
      final clean = stripAvatarCropFragment(p) ?? p;
      if (clean.startsWith('http://') ||
          clean.startsWith('https://') ||
          clean.startsWith('data:') ||
          (!kIsWeb && await File(clean).exists())) {
        validList.add(p);
      }
    }
    return validList;
  }

  /// Удаляет аватар из локальной истории, очереди и с диска (если это локальный файл).
  Future<void> removeAvatar(String userId, String avatarUrlOrPath) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanTarget = stripAvatarCropFragment(avatarUrlOrPath) ?? avatarUrlOrPath;
    final pendingList = prefs.getStringList(_pendingKey(userId)) ?? [];
    final prevPendingLen = pendingList.length;
    pendingList.removeWhere(
      (item) => item == avatarUrlOrPath || (stripAvatarCropFragment(item) ?? item) == cleanTarget,
    );
    if (pendingList.length != prevPendingLen) {
      await prefs.setStringList(_pendingKey(userId), pendingList);
    }
    final historyList = prefs.getStringList(_historyKey(userId)) ?? [];
    final prevHistoryLen = historyList.length;
    historyList.removeWhere(
      (item) => item == avatarUrlOrPath || (stripAvatarCropFragment(item) ?? item) == cleanTarget,
    );
    if (historyList.length != prevHistoryLen) {
      await prefs.setStringList(_historyKey(userId), historyList);
    }
    if (!kIsWeb &&
        !cleanTarget.startsWith('http://') &&
        !cleanTarget.startsWith('https://') &&
        !cleanTarget.startsWith('data:') &&
        cleanTarget.contains('/avatars/')) {
      try {
        final f = File(cleanTarget);
        if (await f.exists()) {
          await f.delete();
        }
        invalidateLocalAvatarCache(cleanTarget);
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
        final pendingEntry = pendingList.first;
        final pendingSplit = AvatarCropSpec.split(pendingEntry);
        final cleanPendingPath = pendingSplit.cleanUrl ?? pendingEntry;
        final pendingFile = File(cleanPendingPath);

        if (!await pendingFile.exists()) {
          debugPrint('[AvatarSyncService] Pending file missing, skipping: $cleanPendingPath');
          pendingList.removeAt(0);
          await prefs.setStringList(_pendingKey(userId), pendingList);
          continue;
        }

        debugPrint('[AvatarSyncService] Uploading avatar in queue: $pendingEntry');
        final uploadResult = await AuthService.uploadAvatar(
          cleanPendingPath,
          avatarCrop: pendingSplit.crop?.toCompactParam(),
        );
        debugPrint('[AvatarSyncService] uploadAvatar result: $uploadResult');

        if (uploadResult['success'] == true) {
          final remoteAvatarUrl = uploadResult['avatar_url'] as String?;
          if (remoteAvatarUrl != null && remoteAvatarUrl.isNotEmpty) {
            // Удаляем успешно загруженный из очереди
            pendingList.removeAt(0);
            await prefs.setStringList(_pendingKey(userId), pendingList);

            final normalizedRemoteUrl =
                getValidAvatarUrl(remoteAvatarUrl) ?? remoteAvatarUrl;
            final cleanRemoteUrl =
                stripAvatarCropFragment(normalizedRemoteUrl) ?? normalizedRemoteUrl;
            final cleanRawRemoteUrl =
                stripAvatarCropFragment(remoteAvatarUrl) ?? remoteAvatarUrl;

            // Кэшируем байты в DefaultCacheManager, чтобы CachedNetworkImageProvider
            // мог мгновенно отображать аватарку оффлайн
            try {
              final bytes = await pendingFile.readAsBytes();
              await DefaultCacheManager().putFile(
                cleanRemoteUrl,
                bytes,
                fileExtension: 'jpg',
              );
              if (cleanRemoteUrl != cleanRawRemoteUrl) {
                await DefaultCacheManager().putFile(
                  cleanRawRemoteUrl,
                  bytes,
                  fileExtension: 'jpg',
                );
              }
            } catch (e) {
              debugPrint('[AvatarSyncService] Cache put error: $e');
            }

            // Обновляем историю: заменяем локальный путь на серверный URL
            final historyList = prefs.getStringList(_historyKey(userId)) ?? [];
            final idx = historyList.indexOf(pendingEntry);
            if (idx != -1) {
              historyList[idx] = normalizedRemoteUrl;
              await prefs.setStringList(_historyKey(userId), historyList);
            }

            // Если этот аватар был текущим в AccountManager, обновляем его
            final currentAcc = _accountManager.currentAccount;
            if (currentAcc != null &&
                (currentAcc.avatarUrl == pendingEntry ||
                    currentAcc.avatarUrl == cleanPendingPath ||
                    pendingList.isEmpty)) {
              await _accountManager.updateAccountProfile(
                userId,
                avatarUrl: normalizedRemoteUrl,
                localAvatarPath: pendingEntry,
              );
            }

            debugPrint('[AvatarSyncService] Successfully synced queued avatar for userId=$userId -> $normalizedRemoteUrl');
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
