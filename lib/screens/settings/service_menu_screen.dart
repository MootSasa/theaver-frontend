import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../auth/login_screen.dart';
import '../../widgets/common/adaptive_switch.dart';

/// Экран сервисного меню (скрытый раздел для отладки и сервисных функций).
class ServiceMenuScreen extends StatefulWidget {
  const ServiceMenuScreen({Key? key}) : super(key: key);

  @override
  State<ServiceMenuScreen> createState() => _ServiceMenuScreenState();
}
class _ServiceMenuScreenState extends State<ServiceMenuScreen> {
  static const platform = MethodChannel('com.example.app/cutout');
  static OverlayEntry? _cutoutOverlayEntry;
  bool _isCutoutHighlighted = false;

  bool _isCheckingConnection = false;
  String? _connectionTestResult;
  bool? _connectionTestSuccess;
  String? _currentUserToken;

  @override
  void initState() {
    super.initState();
    _isCutoutHighlighted = _cutoutOverlayEntry != null;
    _loadCurrentUserInfo();
  }

  Future<void> _loadCurrentUserInfo() async {
    final token = await AuthService.getToken();
    if (mounted) {
      setState(() {
        _currentUserToken = token;
      });
    }
  }

  Future<void> _testServerConnection() async {
    setState(() {
      _isCheckingConnection = true;
      _connectionTestResult = null;
      _connectionTestSuccess = null;
    });

    try {
      final startTime = DateTime.now();
      final healthUri = Uri.parse('${AppConfig.baseUrl}/health');
      final response = await http.get(healthUri).timeout(const Duration(seconds: 4));
      final latency = DateTime.now().difference(startTime).inMilliseconds;

      if (response.statusCode == 200) {
        String msg = 'REST API: OK (${latency}мс)';
        if (_currentUserToken == 'test_token_offline_mode') {
          msg += '\n⚠️ Токен тестовый (офлайн). Сервер отклонит WebSocket (401). Для работы выйдите и зарегистрируйтесь.';
          setState(() {
            _connectionTestResult = msg;
            _connectionTestSuccess = false;
            _isCheckingConnection = false;
          });
        } else {
          final token = await AuthService.getToken();
          bool isAuthValid = false;
          if (token != null && token.isNotEmpty) {
            try {
              final authResp = await http.get(
                Uri.parse('${AppConfig.baseUrl}/api/auth/sessions'),
                headers: {'Authorization': 'Bearer $token'},
              ).timeout(const Duration(seconds: 4));
              if (authResp.statusCode == 200) {
                isAuthValid = true;
                msg += '\nАвторизация: Действительна (OK)';
              } else if (authResp.statusCode == 401) {
                msg += '\n⚠️ Авторизация: Ошибка 401 (Сессия истекла или отозвана)';
              } else {
                msg += '\n⚠️ Авторизация: HTTP ${authResp.statusCode}';
              }
            } catch (_) {}
          }

          await WebSocketService().reconnect();
          await Future.delayed(const Duration(milliseconds: 600));
          final isWs = WebSocketService().isConnected;
          msg += isWs ? '\nWebSocket: Подключено (OK)' : '\nWebSocket: В процессе подключения...';
          setState(() {
            _connectionTestResult = msg;
            _connectionTestSuccess = isAuthValid && isWs;
            _isCheckingConnection = false;
          });
        }
      } else {
        setState(() {
          _connectionTestResult = 'Ошибка HTTP ${response.statusCode}: ${response.body}';
          _connectionTestSuccess = false;
          _isCheckingConnection = false;
        });
      }
    } catch (e) {
      setState(() {
        _connectionTestResult = 'Ошибка подключения: $e';
        _connectionTestSuccess = false;
        _isCheckingConnection = false;
      });
    }
  }

  Future<void> _logoutFromCurrentAccount() async {
    await AuthService.logout();
    WebSocketService().disconnect();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showServerConfigDialog() {
    final controller = TextEditingController(text: AppConfig.baseUrl);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Настройка сервера'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Введите базовый URL сервера (например, http://192.168.1.50:8080):'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'http://192.168.1.50:8080',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await AppConfig.resetToDefaults();
              await WebSocketService().reconnect();
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (mounted) {
                setState(() {});
                _testServerConnection();
              }
            },
            child: const Text('Сбросить'),
          ),
          FilledButton(
            onPressed: () async {
              await AppConfig.setCustomServerUrl(controller.text.trim());
              await WebSocketService().reconnect();
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (mounted) {
                setState(() {});
                _testServerConnection();
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCutoutHighlight(BuildContext context) async {
    if (_cutoutOverlayEntry != null) {
      _cutoutOverlayEntry?.remove();
      _cutoutOverlayEntry = null;
      setState(() {
        _isCutoutHighlighted = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подсветка вырезов отключена'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Пытаемся получить точные вырезы через нативный MethodChannel
    List<Rect> preciseCutouts = [];
    try {
      final List<dynamic> result = await platform.invokeMethod('getCutoutInfo');
      for (var rectMap in result) {
        preciseCutouts.add(Rect.fromLTWH(
          (rectMap['left'] as num).toDouble(),
          (rectMap['top'] as num).toDouble(),
          (rectMap['width'] as num).toDouble(),
          (rectMap['height'] as num).toDouble(),
        ));
      }
    } catch (e) {
      debugPrint('Не удалось получить точные вырезы через MethodChannel: $e');
    }

    // Если нет активности контекста после async вызова
    if (!context.mounted) return;

    final mediaQuery = MediaQuery.of(context);
    final displayFeatures = mediaQuery.displayFeatures;
    final flutterCutouts = displayFeatures
        .where((f) => f.type == DisplayFeatureType.cutout)
        .map((f) => f.bounds)
        .toList();

    // Приоритет у точных координат от MethodChannel, фоллбэк - MediaQuery
    final cutouts = preciseCutouts.isNotEmpty ? preciseCutouts : flutterCutouts;

    // Выводим информацию об экране в логи
    _printScreenInfo(context);

    if (cutouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вырезов на экране не обнаружено. Проверьте пересборку приложения.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final overlay = Overlay.of(context);
    _cutoutOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: cutouts.map((rect) {
            return Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: IgnorePointer(
                child: Container(
                  color: Colors.red.withValues(alpha: 0.5),
                ),
              ),
            );
          }).toList(),
        );
      },
    );

    overlay.insert(_cutoutOverlayEntry!);
    setState(() {
      _isCutoutHighlighted = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Подсвечено вырезов: ${cutouts.length}'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _printScreenInfo(BuildContext context) async {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final padding = mediaQuery.padding;
    final viewInsets = mediaQuery.viewInsets;
    final viewPadding = mediaQuery.viewPadding;
    final systemGestureInsets = mediaQuery.systemGestureInsets;

    debugPrint('================ SCREEN INFO ================');
    debugPrint('Логическое разрешение (Size): ${size.width} x ${size.height}');
    debugPrint('Плотность пикселей (Device Pixel Ratio): ${mediaQuery.devicePixelRatio}');
    debugPrint('Физическое разрешение: ${size.width * mediaQuery.devicePixelRatio} x ${size.height * mediaQuery.devicePixelRatio}');
    debugPrint('Ориентация: ${mediaQuery.orientation.name}');
    debugPrint('Яркость платформы: ${mediaQuery.platformBrightness.name}');
    debugPrint('--- Отступы (Insets & Padding) ---');
    debugPrint('Padding (Safe Area): Left: ${padding.left}, Top: ${padding.top}, Right: ${padding.right}, Bottom: ${padding.bottom}');
    debugPrint('View Insets (Keyboard и т.д.): Left: ${viewInsets.left}, Top: ${viewInsets.top}, Right: ${viewInsets.right}, Bottom: ${viewInsets.bottom}');
    debugPrint('View Padding: Left: ${viewPadding.left}, Top: ${viewPadding.top}, Right: ${viewPadding.right}, Bottom: ${viewPadding.bottom}');
    debugPrint('System Gesture Insets: Left: ${systemGestureInsets.left}, Top: ${systemGestureInsets.top}, Right: ${systemGestureInsets.right}, Bottom: ${systemGestureInsets.bottom}');
    
    debugPrint('--- Аппаратные особенности (Display Features - Flutter) ---');
    final displayFeatures = mediaQuery.displayFeatures;

    if (displayFeatures.isEmpty) {
      debugPrint('Особенности экрана (вырезы/сгибы) через Flutter не найдены.');
    } else {
      for (final feature in displayFeatures) {
        debugPrint('Тип особенности: ${feature.type.name}');
        debugPrint('Координаты (Bounds): ${feature.bounds}');
        if (feature.type == DisplayFeatureType.cutout) {
          final Rect cutoutRect = feature.bounds;
          debugPrint('  [Детали выреза (Flutter)]');
          debugPrint('  X (Left): ${cutoutRect.left}, Y (Top): ${cutoutRect.top}');
          debugPrint('  Ширина: ${cutoutRect.width}, Высота: ${cutoutRect.height}');
        } else if (feature.type == DisplayFeatureType.fold || feature.type == DisplayFeatureType.hinge) {
          debugPrint('  [Детали сгиба/шарнира]');
          debugPrint('  Состояние: ${feature.state.name}');
        }
      }
    }

    debugPrint('--- Точные вырезы (MethodChannel / Native Android) ---');
    try {
      final List<dynamic> result = await platform.invokeMethod('getCutoutInfo');
      if (result.isEmpty) {
        debugPrint('Нативный API не вернул вырезов.');
      } else {
        for (int i = 0; i < result.length; i++) {
          final rectMap = result[i];
          final rect = Rect.fromLTWH(
            (rectMap['left'] as num).toDouble(),
            (rectMap['top'] as num).toDouble(),
            (rectMap['width'] as num).toDouble(),
            (rectMap['height'] as num).toDouble(),
          );
          debugPrint('  [Точный вырез ${i + 1}]');
          debugPrint('  Координаты (Bounds): $rect');
          debugPrint('  X (Left): ${rect.left}, Y (Top): ${rect.top}');
          debugPrint('  Ширина: ${rect.width}, Высота: ${rect.height}');
        }
      }
    } catch (e) {
      debugPrint('Ошибка при получении точных вырезов: $e');
    }

    debugPrint('=============================================');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('service_menu_title')),
      ),
      body: ListView(
        children: [
          if (_currentUserToken == 'test_token_offline_mode')
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Тестовый офлайн-аккаунт',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вы авторизованы под локальным тестовым аккаунтом. Сервер вернёт ошибку 401 при подключении WebSocket и чатов. Для полноценной работы выйдите и зарегистрируйтесь на сервере.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _logoutFromCurrentAccount,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Выйти и зарегистрироваться'),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'КОНФИГУРАЦИЯ СЕРВЕРА',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0088CC),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dns, color: Color(0xFF0088CC)),
            title: const Text('Базовый API URL'),
            subtitle: Text(AppConfig.baseUrl),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _showServerConfigDialog,
          ),
          ListTile(
            leading: const Icon(Icons.sync_alt, color: Color(0xFF0088CC)),
            title: const Text('WebSocket URL'),
            subtitle: Text(AppConfig.wsUrl),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_queue, color: Color(0xFF0088CC)),
            title: const Text('Storage URL (MinIO/S3)'),
            subtitle: Text(AppConfig.storageUrl),
          ),
          ListTile(
            leading: const Icon(Icons.web, color: Color(0xFF0088CC)),
            title: const Text('Web Base URL'),
            subtitle: Text(AppConfig.webBaseUrl),
          ),
          ListTile(
            leading: _isCheckingConnection
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _connectionTestSuccess == null
                        ? Icons.network_check
                        : (_connectionTestSuccess! ? Icons.check_circle : Icons.error),
                    color: _connectionTestSuccess == null
                        ? const Color(0xFF0088CC)
                        : (_connectionTestSuccess! ? Colors.green : Colors.red),
                  ),
            title: const Text('Проверить соединение с сервером'),
            subtitle: _connectionTestResult != null
                ? Text(
                    _connectionTestResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _connectionTestSuccess == true ? Colors.green : Colors.red,
                    ),
                  )
                : const Text('Нажмите для проверки REST API и WebSocket'),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isCheckingConnection ? null : _testServerConnection,
            ),
            onTap: _isCheckingConnection ? null : _testServerConnection,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'ОТЛАДКА ИНТЕРФЕЙСА',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0088CC),
              ),
            ),
          ),
          AdaptiveSwitchListTile(
            secondary: Icon(
              Icons.highlight_outlined,
              color: _isCutoutHighlighted ? Colors.red : const Color(0xFF0088CC),
            ),
            title: const Text('Подсветка вырезов экрана (Cutout)'),
            subtitle: Text(_isCutoutHighlighted
                ? 'Вырезы подсвечены полупрозрачным красным (нажмите чтобы выключить)'
                : 'Показать полупрозрачный красный слой поверх выреза и вывести инфо в лог'),
            value: _isCutoutHighlighted,
            onChanged: (_) => _toggleCutoutHighlight(context),
          ),
          ListTile(
            leading: const Icon(Icons.screenshot, color: Color(0xFF0088CC)),
            title: const Text('Полная информация об экране'),
            subtitle: const Text('Вывести размеры, отступы и вырезы в консоль'),
            onTap: () => _printScreenInfo(context),
          ),
        ],
      ),
    );
  }
}
