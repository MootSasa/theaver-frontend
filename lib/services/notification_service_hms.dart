import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:huawei_push/huawei_push.dart';

/// Сервис Huawei Push Kit для устройств без Google Play Services.
///
/// Интегрирован с официальным плагином Huawei Push Kit (huawei_push),
/// предоставляя унифицированное API для NotificationService.
class HMSPushService {
  HMSPushService._internal() {
    if (Platform.isAndroid) {
      setupMessageHandlers();
    }
  }
  factory HMSPushService() => _instance;
  static final HMSPushService _instance = HMSPushService._internal();

  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _messageOpenedAppController =
      StreamController<Map<String, dynamic>>.broadcast();

  String? _token;
  Map<String, dynamic>? _initialNotificationData;

  /// Текущий HMS Push токен
  String? get token => _token;

  /// Получить данные уведомления, открывшего приложение при холодном старте
  Future<Map<String, dynamic>?> getInitialNotification() async {
    if (!Platform.isAndroid) return null;
    if (_initialNotificationData != null && _initialNotificationData!.isNotEmpty) {
      final data = _initialNotificationData;
      _initialNotificationData = null;
      return data;
    }
    try {
      final dynamic event = await Push.getInitialNotification();
      if (event != null) {
        final data = _extractMap(event);
        if (data.isNotEmpty) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('HMSPushService: getInitialNotification error: $e');
    }
    return null;
  }

  /// Поток обновлений токена
  Stream<String> get onTokenRefresh => _tokenController.stream;

  /// Поток входящих сообщений (foreground)
  Stream<Map<String, dynamic>> get onMessageReceived =>
      _messageController.stream;

  /// Поток сообщений, открывших приложение
  Stream<Map<String, dynamic>> get onMessageOpenedApp =>
      _messageOpenedAppController.stream;

  /// Запрос разрешений на уведомления (HMS Push)
  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await Push.setAutoInitEnabled(true);
      await Push.turnOnPush();
      debugPrint('HMSPushService: autoInit enabled, push turned on');
    } catch (e) {
      debugPrint('HMSPushService: permission request failed: $e');
    }
  }

  /// Получить HMS Push токен
  Future<String?> getToken() async {
    if (!Platform.isAndroid) return null;
    try {
      if (_token != null && _token!.isNotEmpty) {
        return _token;
      }

      final completer = Completer<String?>();
      late StreamSubscription sub;
      sub = Push.getTokenStream.listen((token) {
        _token = token;
        _tokenController.add(token);
        if (!completer.isCompleted) {
          completer.complete(token);
        }
      }, onError: (e) {
        debugPrint('HMSPushService: getTokenStream error: $e');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      // Запрос токена от HMS Core (HCM — default scope)
      Push.getToken('');

      // Ожидание токена до 5 секунд
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(_token);
        }
        sub.cancel();
      });

      return await completer.future;
    } catch (e) {
      debugPrint('HMSPushService: getToken failed: $e');
      return null;
    }
  }

  /// Подписаться на тему (HMS Push topic messaging)
  Future<void> subscribeToTopic(String topic) async {
    if (!Platform.isAndroid) return;
    try {
      await Push.subscribe(topic);
      debugPrint('HMSPushService: subscribed to topic $topic');
    } catch (e) {
      debugPrint('HMSPushService: subscribeToTopic failed: $e');
    }
  }

  /// Отписаться от темы
  Future<void> unsubscribeFromTopic(String topic) async {
    if (!Platform.isAndroid) return;
    try {
      await Push.unsubscribe(topic);
      debugPrint('HMSPushService: unsubscribed from topic $topic');
    } catch (e) {
      debugPrint('HMSPushService: unsubscribeFromTopic failed: $e');
    }
  }

  /// Удалить токен (при выходе из аккаунта)
  Future<void> deleteToken() async {
    if (!Platform.isAndroid) return;
    try {
      await Push.deleteToken('');
      _token = null;
      debugPrint('HMSPushService: token deleted');
    } catch (e) {
      debugPrint('HMSPushService: deleteToken failed: $e');
    }
  }

  /// Инициализация обработчиков сообщений
  void setupMessageHandlers() {
    Push.getTokenStream.listen((token) {
      debugPrint('HMSPushService: token received: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
      _token = token;
      _tokenController.add(token);
    }, onError: (e) {
      debugPrint('HMSPushService: token error: $e');
    });

    Push.onMessageReceivedStream.listen((RemoteMessage message) {
      debugPrint('HMSPushService: onMessageReceived');
      Map<String, dynamic> data = {};
      if (message.dataOfMap != null && message.dataOfMap!.isNotEmpty) {
        data = Map<String, dynamic>.from(message.dataOfMap!);
      } else if (message.data != null && message.data!.isNotEmpty) {
        try {
          data = Map<String, dynamic>.from(json.decode(message.data!));
        } catch (_) {
          data = {'data': message.data};
        }
      }
      _messageController.add(data);
    }, onError: (e) {
      debugPrint('HMSPushService: message error: $e');
    });

    Push.onNotificationOpenedApp.listen((dynamic event) {
      debugPrint('HMSPushService: onNotificationOpenedApp: $event');
      Map<String, dynamic> data = _extractMap(event);
      if (data.isNotEmpty) {
        _messageOpenedAppController.add(data);
      }
    }, onError: (e) {
      debugPrint('HMSPushService: notification open error: $e');
    });

    // Проверка начального уведомления при холодном старте
    Push.getInitialNotification().then((dynamic event) {
      if (event != null) {
        debugPrint('HMSPushService: getInitialNotification: $event');
        final Map<String, dynamic> data = _extractMap(event);
        if (data.isNotEmpty) {
          _initialNotificationData = data;
          _messageOpenedAppController.add(data);
        }
      }
    }).catchError((e) {
      debugPrint('HMSPushService: getInitialNotification error: $e');
    });
  }

  Map<String, dynamic> _extractMap(dynamic event) {
    if (event == null) return {};
    Map<String, dynamic> raw = {};
    if (event is Map) {
      raw = Map<String, dynamic>.from(event);
    } else if (event is String && event.isNotEmpty) {
      try {
        final decoded = json.decode(event);
        if (decoded is Map) {
          raw = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return {'data': event};
      }
    }

    if (raw.isEmpty) return {};

    // If chat_id is already present at top level, return raw
    if (raw.containsKey('chat_id') && raw['chat_id'] != null) {
      return raw;
    }

    final Map<String, dynamic> result = Map<String, dynamic>.from(raw);

    // 1. Try extracting payload from remoteMessage (HMS Push Kit structure)
    if (raw['remoteMessage'] is Map) {
      final rm = Map<String, dynamic>.from(raw['remoteMessage']);
      if (rm['dataOfMap'] != null) {
        if (rm['dataOfMap'] is Map) {
          result.addAll(Map<String, dynamic>.from(rm['dataOfMap']));
        } else if (rm['dataOfMap'] is String && rm['dataOfMap'].isNotEmpty) {
          try {
            final decoded = json.decode(rm['dataOfMap']);
            if (decoded is Map) {
              result.addAll(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
      }
      if (rm['data'] != null) {
        if (rm['data'] is Map) {
          result.addAll(Map<String, dynamic>.from(rm['data']));
        } else if (rm['data'] is String && rm['data'].isNotEmpty) {
          try {
            final decoded = json.decode(rm['data']);
            if (decoded is Map) {
              result.addAll(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
      }
    }

    // 2. Try extracting payload from extras
    if (raw['extras'] is Map) {
      final extras = Map<String, dynamic>.from(raw['extras']);
      if (extras.containsKey('chat_id')) {
        result.addAll(extras);
      } else if (extras['data'] != null) {
        if (extras['data'] is Map) {
          result.addAll(Map<String, dynamic>.from(extras['data']));
        } else if (extras['data'] is String && extras['data'].isNotEmpty) {
          try {
            final decoded = json.decode(extras['data']);
            if (decoded is Map) {
              result.addAll(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
      }
    }

    // 3. Try top-level data string
    if (raw['data'] is String && (raw['data'] as String).isNotEmpty) {
      try {
        final decoded = json.decode(raw['data'] as String);
        if (decoded is Map) {
          result.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    return result;
  }

  /// Отменить уведомления чата в строке состояния Huawei / Android
  Future<void> cancelChatNotifications(String chatId) async {
    if (!Platform.isAndroid) return;
    try {
      final activeNotifications = await Push.getNotifications();
      final idsToCancel = <int>[];
      final idTagsToCancel = <int, String>{};

      for (final notif in activeNotifications) {
        final tag = notif['tag']?.toString() ?? '';
        final idStr = notif['id']?.toString() ?? notif['identifier']?.toString();
        final id = int.tryParse(idStr ?? '');

        if (tag == 'chat_$chatId' || tag.startsWith('chat_${chatId}_')) {
          if (id != null) {
            idsToCancel.add(id);
            idTagsToCancel[id] = tag;
          }
          try {
            await Push.cancelNotificationsWithTag(tag);
          } catch (_) {}
        }
      }

      if (idsToCancel.isNotEmpty) {
        try {
          await Push.cancelNotificationsWithId(idsToCancel);
        } catch (_) {}
      }
      if (idTagsToCancel.isNotEmpty) {
        try {
          await Push.cancelNotificationsWithIdTag(idTagsToCancel);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('HMSPushService: cancelChatNotifications error: $e');
    }
  }

  /// Отменить конкретные notification IDs
  Future<void> cancelNotificationsWithIds(List<int> ids) async {
    if (!Platform.isAndroid || ids.isEmpty) return;
    try {
      await Push.cancelNotificationsWithId(ids);
    } catch (e) {
      debugPrint('HMSPushService: cancelNotificationsWithIds error: $e');
    }
  }

  /// Отменить все уведомления в NotificationManager
  Future<void> cancelAllNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await Push.cancelNotifications();
      await Push.cancelAllNotifications();
    } catch (e) {
      debugPrint('HMSPushService: cancelAllNotifications error: $e');
    }
  }

  /// Освободить ресурсы
  void dispose() {
    _tokenController.close();
    _messageController.close();
    _messageOpenedAppController.close();
  }
}
