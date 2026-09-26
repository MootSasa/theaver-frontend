import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Сервис управления окном и системным треем для Desktop (Windows, Linux, macOS).
/// 
/// Позволяет приложению сворачиваться в трей вместо закрытия,
/// сохраняя постоянное WebSocket-соединение для мгновенной доставки уведомлений.
class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService._internal();
  static final DesktopTrayService _instance = DesktopTrayService._internal();
  factory DesktopTrayService() => _instance;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Извлекает иконку приложения из assets во временную/системную директорию
  /// для передачи абсолютного пути в Win32/X11 API trayManager.
  Future<String> _resolveTrayIconPath() async {
    try {
      final isWin = Platform.isWindows;
      final assetKey = isWin ? 'assets/icons/app_icon.ico' : 'assets/icons/app_icon.png';
      final fileName = isWin ? 'tray_icon.ico' : 'tray_icon.png';

      final appSupportDir = await getApplicationSupportDirectory();
      final targetFile = File('${appSupportDir.path}/$fileName');

      if (!await targetFile.exists() || (await targetFile.length()) == 0) {
        final byteData = await rootBundle.load(assetKey);
        final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        await targetFile.writeAsBytes(bytes, flush: true);
      }
      return targetFile.path;
    } catch (e) {
      debugPrint('DesktopTrayService: failed to resolve tray icon path: $e');
      if (Platform.isWindows) {
        return 'windows/runner/resources/app_icon.ico';
      }
      return '';
    }
  }

  /// Инициализация управления окном и треем
  Future<void> init() async {
    if (_isInitialized) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        size: Size(1100, 750),
        minimumSize: Size(450, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'Theaver',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      // Перехватываем закрытие окна, чтобы сворачивать в трей
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);

      // Инициализируем системный трей
      trayManager.addListener(this);

      final iconPath = await _resolveTrayIconPath();
      if (iconPath.isNotEmpty) {
        try {
          await trayManager.setIcon(iconPath);
          await trayManager.setToolTip('Theaver');
        } catch (e) {
          debugPrint('DesktopTrayService: setIcon warning: $e');
        }
      }

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: 'Открыть Theaver',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit_app',
            label: 'Выйти из Theaver',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);

      _isInitialized = true;
      debugPrint('DesktopTrayService: successfully initialized');
    } catch (e) {
      debugPrint('DesktopTrayService: init warning: $e');
    }
  }

  /// Показать и сфокусировать окно приложения
  Future<void> showAndFocusWindow() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('DesktopTrayService: showAndFocusWindow error: $e');
    }
  }

  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      // Сворачиваем в трей вместо закрытия
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'quit_app':
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        break;
    }
  }

  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
  }
}
