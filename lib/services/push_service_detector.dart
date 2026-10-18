import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:huawei_hmsavailability/huawei_hmsavailability.dart';

/// Результат детектирования доступных push-сервисов на устройстве.
enum PushServiceType {
  /// Google Play Services доступны — используем FCM
  gms,

  /// HMS Core доступен — используем Huawei Push Kit
  hms,

  /// Ни GMS, ни HMS не доступны — только локальные уведомления
  none,
}

/// Детектор доступных push-сервисов на устройстве.
///
/// Проверяет наличие Google Play Services (GMS) и HMS Core.
/// На устройствах Huawei (и Honor) приоритетно использует HMS Core / Huawei Push Kit,
/// защищая от ложных срабатываний из-за присутствующих в системе заглушек GMS.
class PushServiceDetector {
  PushServiceDetector._internal();
  static final PushServiceDetector _instance = PushServiceDetector._internal();
  factory PushServiceDetector() => _instance;

  PushServiceType _detected = PushServiceType.none;
  bool _isDetected = false;

  String? _deviceManufacturer;
  String? _deviceModel;
  bool _isHuaweiDevice = false;
  int? _hmsStatusCode;

  /// Текущий обнаруженный тип push-сервиса
  PushServiceType get serviceType => _detected;

  /// Было ли выполнено детектирование
  bool get isDetected => _isDetected;

  /// Доступен ли FCM (Google Play Services)
  bool get isGmsAvailable => _detected == PushServiceType.gms;

  /// Доступен ли HMS Push Kit
  bool get isHmsAvailable => _detected == PushServiceType.hms;

  /// Доступен ли хотя бы один push-сервис
  bool get isPushAvailable => _detected != PushServiceType.none;

  /// Является ли устройство Huawei / Honor
  bool get isHuaweiDevice => _isHuaweiDevice;

  /// Производитель устройства
  String? get deviceManufacturer => _deviceManufacturer;

  /// Модель устройства
  String? get deviceModel => _deviceModel;

  /// Код статуса HMS Core (0 = SUCCESS)
  int? get hmsStatusCode => _hmsStatusCode;

  /// Текстовое описание статуса HMS Core
  String get hmsStatusDescription {
    if (_hmsStatusCode == null) return 'Не проверялся';
    switch (_hmsStatusCode) {
      case 0:
        return 'HMS Core активен (SUCCESS)';
      case 1:
        return 'HMS Core отсутствует (SERVICE_MISSING)';
      case 2:
        return 'Требуется обновление HMS Core (VERSION_UPDATE_REQUIRED)';
      case 3:
        return 'HMS Core отключен в настройках (SERVICE_DISABLED)';
      case 9:
        return 'Недействительный сервис (SERVICE_INVALID)';
      case 21:
        return 'HMS Core обновляется (SERVICE_UPDATING)';
      default:
        return 'Статус HMS Core: $_hmsStatusCode';
    }
  }

  /// Выполнить детектирование доступных push-сервисов.
  ///
  /// Вызывается при инициализации приложения.
  /// На iOS всегда возвращает GMS (FCM работает через APNS).
  /// На Android:
  /// - Для устройств Huawei/Honor: приоритетно проверяет HMS Core.
  /// - Для остальных: приоритетно проверяет GMS.
  /// На остальных платформах — none.
  Future<PushServiceType> detect() async {
    if (_isDetected) return _detected;

    if (kIsWeb) {
      _detected = PushServiceType.none;
      _isDetected = true;
      debugPrint('PushServiceDetector: web platform → $_detected');
      return _detected;
    }

    if (!Platform.isAndroid) {
      // iOS / macOS / Windows / Linux — FCM работает через APNS на iOS
      if (Platform.isIOS || Platform.isMacOS) {
        _detected = PushServiceType.gms;
      } else {
        _detected = PushServiceType.none;
      }
      _isDetected = true;
      debugPrint('PushServiceDetector: non-Android platform → $_detected');
      return _detected;
    }

    // Android: определяем параметры устройства
    await _detectDeviceInfo();

    if (_isHuaweiDevice) {
      debugPrint(
        'PushServiceDetector: Huawei/Honor device detected '
        '($_deviceManufacturer $_deviceModel) → prioritizing HMS Core',
      );

      // 1. Проверяем HMS Core на устройствах Huawei
      final hmsAvailable = await _checkHmsAvailability();
      if (hmsAvailable) {
        _detected = PushServiceType.hms;
        _isDetected = true;
        debugPrint('PushServiceDetector: HMS available ($hmsStatusDescription) → Huawei Push Kit');
        return _detected;
      }

      // 2. Если HMS Core не доступен на Huawei, проверяем GMS только при строгой валидации
      try {
        final gmsAvailable = await _checkGmsAvailability();
        if (gmsAvailable) {
          _detected = PushServiceType.gms;
          _isDetected = true;
          debugPrint('PushServiceDetector: GMS available on Huawei device → FCM fallback');
          return _detected;
        }
      } catch (e) {
        debugPrint('PushServiceDetector: GMS check on Huawei failed: $e');
      }
    } else {
      // Non-Huawei (Samsung, Xiaomi, Pixel, etc.) — проверяем GMS в первую очередь
      try {
        final gmsAvailable = await _checkGmsAvailability();
        if (gmsAvailable) {
          _detected = PushServiceType.gms;
          _isDetected = true;
          debugPrint('PushServiceDetector: GMS available → FCM');
          return _detected;
        }
      } catch (e) {
        debugPrint('PushServiceDetector: GMS check failed: $e');
      }

      // Fallback на HMS Core для других устройств (если пользователь установил AppGallery)
      final hmsAvailable = await _checkHmsAvailability();
      if (hmsAvailable) {
        _detected = PushServiceType.hms;
        _isDetected = true;
        debugPrint('PushServiceDetector: HMS available on non-Huawei → Huawei Push Kit');
        return _detected;
      }
    }

    _detected = PushServiceType.none;
    _isDetected = true;
    debugPrint(
      'PushServiceDetector: no push services available '
      '(HMS code: $_hmsStatusCode) → local notifications only',
    );
    return _detected;
  }

  /// Сбор информации об устройстве для точной маршрутизации push-сервисов
  Future<void> _detectDeviceInfo() async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      _deviceManufacturer = androidInfo.manufacturer;
      _deviceModel = androidInfo.model;
      final m = (_deviceManufacturer ?? '').toLowerCase();
      final b = (androidInfo.brand).toLowerCase();
      _isHuaweiDevice = m.contains('huawei') || b.contains('huawei') || b.contains('honor');
    } catch (e) {
      debugPrint('PushServiceDetector: DeviceInfoPlugin error: $e');
      // Fallback через нативный MethodChannel
      try {
        const channel = MethodChannel('app.theaver.messenger/push_detector');
        _isHuaweiDevice = await channel.invokeMethod<bool>('isHuaweiDevice') ?? false;
      } catch (_) {}
    }
  }

  /// Проверка доступности Google Play Services.
  ///
  /// Использует MethodChannel с официальной проверкой GoogleApiAvailability.
  Future<bool> _checkGmsAvailability() async {
    try {
      const channel = MethodChannel('app.theaver.messenger/push_detector');
      return await channel.invokeMethod<bool>('isGmsAvailable') ?? false;
    } catch (e) {
      debugPrint('PushServiceDetector: GMS MethodChannel failed: $e');
      return false;
    }
  }

  /// Проверка доступности HMS Core.
  ///
  /// 1. Сначала использует официальный пакет huawei_hmsavailability (HmsApiAvailability).
  /// 2. При сбое использует нативный MethodChannel как резерв.
  Future<bool> _checkHmsAvailability() async {
    // 1. Официальный пакет Huawei
    try {
      final hmsAvailability = HmsApiAvailability();
      final code = await hmsAvailability.isHMSAvailable();
      _hmsStatusCode = code;
      debugPrint('PushServiceDetector: HmsApiAvailability.isHMSAvailable returned $code');
      if (code == 0) {
        return true;
      }
    } catch (e) {
      debugPrint('PushServiceDetector: HmsApiAvailability invocation error: $e');
    }

    // 2. Резервная нативная проверка через MethodChannel
    try {
      const channel = MethodChannel('app.theaver.messenger/push_detector');
      final available = await channel.invokeMethod<bool>('isHmsAvailable') ?? false;
      if (available && _hmsStatusCode == null) {
        _hmsStatusCode = 0;
      }
      return available;
    } catch (e) {
      debugPrint('PushServiceDetector: HMS MethodChannel error: $e');
      return false;
    }
  }

  /// Открыть системный диалог для исправления ошибки HMS Core
  /// (например, если требуется обновление HMS Core)
  Future<void> resolveHmsError() async {
    if (_hmsStatusCode != null && _hmsStatusCode != 0) {
      try {
        final hmsAvailability = HmsApiAvailability();
        hmsAvailability.resolveError(_hmsStatusCode!, 1001);
      } catch (e) {
        debugPrint('PushServiceDetector: resolveHmsError error: $e');
      }
    }
  }
}
