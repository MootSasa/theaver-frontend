import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'chat_service.dart';
import 'desktop_tray_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/tiling/tile_viewport_scope.dart';

/// Зона сброса (Drop Slot) в правой области чатов при перетаскивании тайла или чата из списка.
enum TilingDropSlot {
  /// Разделить по горизонтали: новый/перетаскиваемый тайл слева в правой области.
  left,

  /// Разделить по горизонтали: новый/перетаскиваемый тайл справа в правой области.
  right,

  /// Разделить по вертикали: новый/перетаскиваемый тайл сверху в правой области.
  top,

  /// Разделить по вертикали: новый/перетаскиваемый тайл снизу в правой области.
  bottom,

  /// Заменить содержимое целевого тайла (или открыть первый тайл).
  replace,
}

/// Описание открытого тайла чата в правой области рабочего пространства.
class ChatTileDescriptor {
  final String tileId;
  final GlobalKey<NavigatorState> navigatorKey;
  ModalRoute<dynamic>? rootRoute;
  String chatId;
  String chatType;
  String chatName;
  String? avatarUrl;
  bool isOnline;
  DateTime? lastSeen;
  String? otherUserId;
  String? initialMessageId;
  int revision;

  ChatTileDescriptor({
    required this.tileId,
    required this.chatId,
    required this.chatType,
    required this.chatName,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.otherUserId,
    this.initialMessageId,
    this.revision = 0,
  }) : navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'ChatTileNav_$tileId');

  Key get contentKey => ValueKey<String>('${tileId}_${chatId}_$revision');
}

/// Данные перетаскиваемого чата (из списка чатов или за шапку открытого тайла).
class DraggingChatPayload {
  final String chatId;
  final String chatType;
  final String chatName;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? otherUserId;

  /// Если перетаскивается уже открытый тайл за его шапку — содержит его [tileId].
  /// Если перетаскивается чат из списка в левом тайле — `null`.
  final String? sourceTileId;

  /// Начальный глобальный прямоугольник тайла/элемента в момент старта перетаскивания.
  final Rect initialGlobalRect;

  /// Текущая глобальная позиция курсора/пальца.
  Offset currentGlobalPosition;

  /// Текущая скорость движения курсора для лёгкого наклона превью-окна.
  Offset velocity;

  DraggingChatPayload({
    required this.chatId,
    required this.chatType,
    String? chatName,
    String? title,
    this.avatarUrl,
    bool? isOnline,
    bool? otherUserOnline,
    DateTime? lastSeen,
    DateTime? otherUserLastSeen,
    this.otherUserId,
    this.sourceTileId,
    required this.initialGlobalRect,
    Offset? currentGlobalPosition,
    Offset? currentGlobalPos,
    this.velocity = Offset.zero,
  })  : chatName = chatName ?? title ?? '',
        isOnline = isOnline ?? otherUserOnline ?? false,
        lastSeen = lastSeen ?? otherUserLastSeen,
        currentGlobalPosition = currentGlobalPosition ??
            currentGlobalPos ??
            initialGlobalRect.center;
}

/// Центральный контроллер тайлингового многооконного режима.
///
/// Управляет:
/// - левым закреплённым тайлом ([MainScreen]) с его собственным вложенным [Navigator];
/// - правой областью чатов (от 0 до 2 открытых тайлов чатов, горизонтальный или вертикальный сплит);
/// - ограничениями ширины (`320..480px` слева, `320..900px` справа) и высоты (`>= 280px` на тайл);
/// - двусторонним перестроением (ширина <-> высота) и блокировкой сжатия окна ОС
///   через [DesktopTrayService.updateMinimumWindowSize], пока оба чата открыты;
/// - состоянием живого перетаскивания (Drag & Drop с блюром и сдвигом соседнего тайла);
/// - фокусом активного тайла и приоритетной навигацией «Назад» (`Esc` и свайп 2 пальцами по тачпаду).
class TilingLayoutController extends ChangeNotifier {
  TilingLayoutController._internal();
  static final TilingLayoutController _instance = TilingLayoutController._internal();
  factory TilingLayoutController() => _instance;
  static TilingLayoutController get instance => _instance;

  // === Константы габаритов и брейкпоинтов ===
  static const double kMinTileWidth = 320.0;
  static const double kMaxLeftTileWidth = 480.0;
  static const double kDefaultLeftTileWidth = 380.0;
  static const double kMaxChatTileWidth = 900.0;
  static const double kDividerThickness = 1.0;

  static const double kMinVerticalSplitTileHeight = 280.0;
  static const double kMinSingleRowWindowHeight = 420.0;

  /// Брейкпоинт для 2 колонок: [MainScreen (320) | ChatArea (320)] = 640px
  static const double kTwoColumnBreakpoint = kMinTileWidth * 2;

  /// Брейкпоинт для 3 колонок: [MainScreen (320) | Chat 1 (320) | Chat 2 (320)] = 960px
  static const double kThreeColumnBreakpoint = kMinTileWidth * 3;

  /// Минимальная высота окна для вертикального сплита двух чатов: 2 * 280 = 560px
  static const double kVerticalSplitHeightBreakpoint = kMinVerticalSplitTileHeight * 2;

  static const String kLeftTileId = 'left_main_tile';

  // === Навигаторы и состояние ===
  GlobalKey<NavigatorState> _leftTileNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'LeftMainTileNavigator');
  GlobalKey<NavigatorState> get leftTileNavigatorKey => _leftTileNavigatorKey;

  void attachLeftTileNavigatorKey(GlobalKey<NavigatorState> key) {
    _leftTileNavigatorKey = key;
  }

  bool _isWorkspaceMounted = false;
  bool get isWorkspaceMounted => _isWorkspaceMounted;

  final List<ChatTileDescriptor> _chatTiles = [];
  List<ChatTileDescriptor> get chatTiles => List.unmodifiable(_chatTiles);

  String _activeTileId = kLeftTileId;
  String get activeTileId => _activeTileId;

  String? _lastFocusedChatTileId;
  String? get lastFocusedChatTileId => _lastFocusedChatTileId;

  Axis _preferredSplitAxis = Axis.horizontal;
  Axis get preferredSplitAxis => _preferredSplitAxis;

  Axis _effectiveSplitAxis = Axis.horizontal;
  Axis get effectiveSplitAxis => _effectiveSplitAxis;

  double _leftTileWidth = kDefaultLeftTileWidth;
  double get leftTileWidth => _leftTileWidth;

  /// Пропорция деления правой области между 1-м и 2-м тайлом чата (0.0 .. 1.0).
  double _chatSplitRatio = 0.5;
  double get chatSplitRatio => _chatSplitRatio;

  Size _windowSize = const Size(1100, 750);
  Size get windowSize => _windowSize;

  /// Находится ли окно в узком однооконном режиме (`width < 640px` и не более 1 открытого чата).
  bool get isSinglePane =>
      _windowSize.width < kTwoColumnBreakpoint && _chatTiles.length < 2;

  /// В узком режиме (`width < 640px`) показывает, открыт ли поверх списка чатов активный чат.
  bool _singlePaneShowingChat = false;
  bool get singlePaneShowingChat => _singlePaneShowingChat && _chatTiles.isNotEmpty;

  // === Состояние перетаскивания (Drag & Drop) и ресайза ===
  DraggingChatPayload? _activeDrag;
  DraggingChatPayload? get activeDrag => _activeDrag;
  bool get isDragging => _activeDrag != null;

  /// Лёгкий нотификатор кадров перетаскивания, который слушает только [TileDragPreviewOverlay],
  /// чтобы движение курсора (120 Гц) не вызывало ребилд всего [TilingWorkspaceScaffold].
  final ValueNotifier<int> dragFrameNotifier = ValueNotifier<int>(0);

  /// Флаг активного ручного перетаскивания разделителя [TileResizeDivider].
  /// Во время ручного ресайза отключает инерционную задержку `AnimatedPositioned`.
  bool _isResizingDivider = false;
  bool get isResizingDivider => _isResizingDivider;

  void setResizingDivider(bool value) {
    if (_isResizingDivider == value) return;
    _isResizingDivider = value;
    notifyListeners();
  }

  TilingDropSlot? _hoveredDropSlot;
  TilingDropSlot? get hoveredDropSlot => _hoveredDropSlot;

  String? _hoveredTargetTileId;
  String? get hoveredTargetTileId => _hoveredTargetTileId;

  int _tileIdCounter = 0;

  /// Колбэки закрытия внутренних оверлеев/меню для каждого тайла (по его `tileId`),
  /// возвращающие `true`, если действие «Назад» было перехвачено и обработано внутри экрана.
  final Map<String, List<bool Function()>> _tileBackHandlers = {};

  /// Колбэк для возврата `MainScreen` на вкладку чатов (индекс 1), если открыты настройки или поиск.
  bool Function()? onMainScreenHandleBack;

  /// Колбэк обновления последнего сообщения в списке чатов при закрытии тайла.
  void Function(String chatId)? onChatTileClosed;

  /// Колбэк для плавной анимации закрытия чата в однооконном режиме перед удалением тайла.
  Future<void> Function(String tileId)? onRequestAnimatedSinglePaneClose;

  void setWorkspaceMounted(bool mounted) {
    _isWorkspaceMounted = mounted;
    if (mounted) {
      _recalculateSplitAndWindowLocks();
    }
  }

  // === Регистрация локальных перехватчиков «Назад» (меню, эмодзи, запись и т.д.) ===

  void registerTileBackHandler(String tileId, bool Function() handler) {
    final list = _tileBackHandlers.putIfAbsent(tileId, () => []);
    if (!list.contains(handler)) {
      list.add(handler);
    }
  }

  void unregisterTileBackHandler(String tileId, bool Function() handler) {
    _tileBackHandlers[tileId]?.remove(handler);
  }

  // === Управление фокусом тайлов ===

  void setFocusedTile(String tileId) {
    if (tileId != kLeftTileId) {
      _lastFocusedChatTileId = tileId;
    }
    if (_activeTileId != tileId) {
      _activeTileId = tileId;
      notifyListeners();
    }
  }

  ChatTileDescriptor? get focusedChatTile {
    if (_chatTiles.isEmpty) return null;
    if (_activeTileId != kLeftTileId) {
      for (final t in _chatTiles) {
        if (t.tileId == _activeTileId) return t;
      }
    }
    if (_lastFocusedChatTileId != null) {
      for (final t in _chatTiles) {
        if (t.tileId == _lastFocusedChatTileId) return t;
      }
    }
    return _chatTiles.first;
  }

  bool isChatOpenInAnyTile(String chatId) {
    return _chatTiles.any((t) => t.chatId == chatId);
  }

  // === Обновление размеров окна и двустороннее перестроение (Width <-> Height) ===
  Size? _lastTargetMinSize;

  void updateWindowMetrics(Size newSize) {
    if (newSize.width <= 0 || newSize.height <= 0) return;
    if (_windowSize == newSize) return;
    final prevSize = _windowSize;
    _windowSize = newSize;

    final prevAxis = _effectiveSplitAxis;
    final prevLeftWidth = _leftTileWidth;

    // Ограничиваем ширину левого тайла так, чтобы правая область всегда имела минимум
    // 320px (при 1 колонке справа) или 640px (при 2 горизонтальных колонках справа).
    _clampLeftTileWidthForWindow(newSize.width);

    _recalculateSplitAndWindowLocks();

    if (prevAxis != _effectiveSplitAxis ||
        prevLeftWidth != _leftTileWidth ||
        (prevSize.width < kTwoColumnBreakpoint) != (newSize.width < kTwoColumnBreakpoint) ||
        (prevSize.width < kThreeColumnBreakpoint) != (newSize.width < kThreeColumnBreakpoint) ||
        (prevSize.height < kVerticalSplitHeightBreakpoint) !=
            (newSize.height < kVerticalSplitHeightBreakpoint)) {
      notifyListeners();
    }
  }

  void _clampLeftTileWidthForWindow(double windowWidth) {
    if (windowWidth < kTwoColumnBreakpoint) return;
    final minRightRequired =
        (_chatTiles.length == 2 && _effectiveSplitAxis == Axis.horizontal)
            ? kMinTileWidth * 2
            : kMinTileWidth;
    final maxAllowedLeft = math.min(
      kMaxLeftTileWidth,
      math.max(kMinTileWidth, windowWidth - minRightRequired),
    );
    _leftTileWidth = _leftTileWidth.clamp(kMinTileWidth, maxAllowedLeft);
  }

  /// Пересчитывает ориентацию сплита (горизонтальный <-> вертикальный) и синхронизирует
  /// минимальный размер окна ОС через `windowManager.setMinimumSize`.
  void _recalculateSplitAndWindowLocks({bool expandWindowIfNeeded = false}) {
    final bool canFitHorizontal = _windowSize.width >= kThreeColumnBreakpoint;
    final bool canFitVertical = _windowSize.width >= kTwoColumnBreakpoint &&
        _windowSize.height >= kVerticalSplitHeightBreakpoint;

    if (_chatTiles.length == 2) {
      if (_preferredSplitAxis == Axis.horizontal) {
        if (canFitHorizontal) {
          _effectiveSplitAxis = Axis.horizontal;
        } else if (canFitVertical) {
          // Окно сузили (< 960px), но высота позволяет (>= 560px) -> авто-переход в вертикальный сплит
          _effectiveSplitAxis = Axis.vertical;
        } else {
          // Высота < 560px, вертикальный сплит невозможен -> остаёмся в горизонтальном
          _effectiveSplitAxis = Axis.horizontal;
        }
      } else {
        // _preferredSplitAxis == Axis.vertical
        if (canFitVertical) {
          _effectiveSplitAxis = Axis.vertical;
        } else if (canFitHorizontal) {
          // Окно сжали по высоте (< 560px), но ширина позволяет (>= 960px) -> авто-переход в горизонтальный сплит
          _effectiveSplitAxis = Axis.horizontal;
        } else {
          // Ширина < 960px, горизонтальный сплит невозможен -> остаёмся в вертикальном
          _effectiveSplitAxis = Axis.vertical;
        }
      }
      _clampLeftTileWidthForWindow(_windowSize.width);
    } else {
      _effectiveSplitAxis = _preferredSplitAxis;
    }

    // Вычисляем минимально допустимый размер окна ОС:
    // Если открыты 2 чата и перестроение в другую ось невозможно — блокируем сжатие окна!
    final Size targetMinSize;
    if (_chatTiles.length == 2) {
      if (_effectiveSplitAxis == Axis.horizontal) {
        if (_windowSize.height < kVerticalSplitHeightBreakpoint) {
          // Высота слишком мала для вертикального сплита (< 560px) ->
          // запрещаем сжимать окно по ширине меньше 960px!
          targetMinSize = const Size(kThreeColumnBreakpoint, kMinSingleRowWindowHeight);
        } else {
          // Высота >= 560px, значит при сужении < 960px чаты смогут перестроиться вертикально,
          // но уже 640px сжать окно с 2 чатами нельзя!
          targetMinSize = const Size(kTwoColumnBreakpoint, kMinSingleRowWindowHeight);
        }
      } else {
        // Сейчас _effectiveSplitAxis == Axis.vertical
        if (_windowSize.width < kThreeColumnBreakpoint) {
          // Ширина < 960px, значит перестроиться в горизонтальный ряд чаты НЕ могут ->
          // запрещаем сжимать окно по высоте меньше 560px и по ширине меньше 640px!
          targetMinSize = const Size(kTwoColumnBreakpoint, kVerticalSplitHeightBreakpoint);
        } else {
          // Ширина >= 960px, значит при уменьшении высоты < 560px чаты смогут перестроиться горизонтально
          targetMinSize = const Size(kTwoColumnBreakpoint, kMinSingleRowWindowHeight);
        }
      }
    } else {
      // Открыт 0 или 1 чат — разрешаем свободное сжатие вплоть до однооконного режима
      targetMinSize = const Size(360.0, kMinSingleRowWindowHeight);
    }

    if (expandWindowIfNeeded || _lastTargetMinSize != targetMinSize) {
      _lastTargetMinSize = targetMinSize;
      DesktopTrayService().updateMinimumWindowSize(
        targetMinSize,
        expandIfNeeded: expandWindowIfNeeded,
      );
    }
  }

  // === Изменение размеров тайлов пользователем (Resizing) ===

  void updateLeftTileWidth(double deltaDx) {
    final minRightRequired =
        (_chatTiles.length == 2 && _effectiveSplitAxis == Axis.horizontal)
            ? kMinTileWidth * 2
            : kMinTileWidth;
    final maxAllowedLeft = math.min(
      kMaxLeftTileWidth,
      math.max(kMinTileWidth, _windowSize.width - minRightRequired),
    );
    final nextWidth = (_leftTileWidth + deltaDx).clamp(kMinTileWidth, maxAllowedLeft);
    if ((nextWidth - _leftTileWidth).abs() > 0.1) {
      _leftTileWidth = nextWidth;
      notifyListeners();
    }
  }

  void updateChatSplitRatio(double deltaPixels, double totalAvailableSpan) {
    if (_chatTiles.length < 2 || totalAvailableSpan <= 0) return;

    final minSpan = _effectiveSplitAxis == Axis.horizontal
        ? kMinTileWidth
        : kMinVerticalSplitTileHeight;
    final maxSpan = _effectiveSplitAxis == Axis.horizontal
        ? math.min(kMaxChatTileWidth, totalAvailableSpan - minSpan)
        : totalAvailableSpan - minSpan;

    final currentFirstPixels = _chatSplitRatio * totalAvailableSpan;
    final lowerBound = math.min(minSpan, totalAvailableSpan * 0.5);
    final upperBound = math.max(lowerBound, math.min(maxSpan, totalAvailableSpan - minSpan));

    final nextFirstPixels = (currentFirstPixels + deltaPixels).clamp(lowerBound, upperBound);
    final nextRatio = (nextFirstPixels / totalAvailableSpan).clamp(0.15, 0.85);
    if ((nextRatio - _chatSplitRatio).abs() > 0.001) {
      _chatSplitRatio = nextRatio;
      notifyListeners();
    }
  }

  /// Меняет местами два открытых тайла чатов (при двойном тапе по ручке разделителя между ними).
  void swapChatTiles() {
    if (_chatTiles.length < 2) return;
    final first = _chatTiles[0];
    final second = _chatTiles[1];
    _chatTiles
      ..clear()
      ..addAll([second, first]);
    notifyListeners();
  }

  // === Открытие, замена и закрытие чатов в тайлах ===

  bool isChatOpen(String chatId) => isChatOpenInAnyTile(chatId);

  /// Открывает чат в активном тайле (при обычном клике в списке чатов или поиске).
  /// Если этот чат уже открыт в одном из тайлов — просто переводит фокус на него.
  void openChatInActiveTile({
    required String chatId,
    required String chatType,
    String? chatName,
    String? title,
    String? avatarUrl,
    bool? isOnline,
    bool? otherUserOnline,
    DateTime? lastSeen,
    DateTime? otherUserLastSeen,
    String? otherUserId,
    String? initialMessageId,
  }) {
    final effectiveChatName = chatName ?? title ?? '';
    final effectiveIsOnline = isOnline ?? otherUserOnline ?? false;
    final effectiveLastSeen = lastSeen ?? otherUserLastSeen;

    // 1. Проверяем, не открыт ли уже этот чат в каком-либо тайле
    for (final existing in _chatTiles) {
      if (existing.chatId == chatId) {
        if (initialMessageId != null && existing.initialMessageId != initialMessageId) {
          existing.initialMessageId = initialMessageId;
          existing.revision++;
        }
        // Сбрасываем вложенные экраны (например, открытый профиль) обратно к чату
        existing.navigatorKey.currentState?.popUntil((route) => route.isFirst);
        _activeTileId = existing.tileId;
        _lastFocusedChatTileId = existing.tileId;
        _singlePaneShowingChat = true;
        notifyListeners();
        return;
      }
    }

    // 2. Если нет открытых тайлов чатов — создаём первый
    if (_chatTiles.isEmpty) {
      final newTile = _createTileDescriptor(
        chatId: chatId,
        chatType: chatType,
        chatName: effectiveChatName,
        avatarUrl: avatarUrl,
        isOnline: effectiveIsOnline,
        lastSeen: effectiveLastSeen,
        otherUserId: otherUserId,
        initialMessageId: initialMessageId,
      );
      _chatTiles.add(newTile);
      _activeTileId = newTile.tileId;
      _lastFocusedChatTileId = newTile.tileId;
      _singlePaneShowingChat = true;
      _recalculateSplitAndWindowLocks();
      notifyListeners();
      return;
    }

    // 3. Заменяем чат в активном (или последнем сфокусированном) тайле чата
    final target = focusedChatTile ?? _chatTiles.first;
    final previousChatId = target.chatId;
    target.chatId = chatId;
    target.chatType = chatType;
    target.chatName = effectiveChatName;
    target.avatarUrl = avatarUrl;
    target.isOnline = effectiveIsOnline;
    target.lastSeen = effectiveLastSeen;
    target.otherUserId = otherUserId;
    target.initialMessageId = initialMessageId;
    target.revision++;

    // Очищаем стек вложенных маршрутов этого тайла
    target.navigatorKey.currentState?.popUntil((route) => route.isFirst);

    _activeTileId = target.tileId;
    _lastFocusedChatTileId = target.tileId;
    _singlePaneShowingChat = true;

    if (previousChatId != chatId) {
      onChatTileClosed?.call(previousChatId);
    }
    notifyListeners();
  }

  /// Открывает чат во втором (соседнем) окне/тайле.
  void openChatInAdjacentTile({
    required String chatId,
    required String chatType,
    String? chatName,
    String? title,
    String? avatarUrl,
    bool? isOnline,
    bool? otherUserOnline,
    DateTime? lastSeen,
    DateTime? otherUserLastSeen,
    String? otherUserId,
    String? initialMessageId,
    Axis? splitAxis,
    bool placeFirst = false,
  }) {
    final effectiveChatName = chatName ?? title ?? '';
    final effectiveIsOnline = isOnline ?? otherUserOnline ?? false;
    final effectiveLastSeen = lastSeen ?? otherUserLastSeen;

    // Если этот чат уже открыт, а всего открыт 1 тайл — ничего не дублируем, просто фокусируем
    final existingIdx = _chatTiles.indexWhere((t) => t.chatId == chatId);
    if (existingIdx != -1 && _chatTiles.length == 1) {
      _activeTileId = _chatTiles[existingIdx].tileId;
      _lastFocusedChatTileId = _activeTileId;
      _singlePaneShowingChat = true;
      notifyListeners();
      return;
    }

    // Если уже открыт в одном из 2 тайлов — фокусируем его
    if (existingIdx != -1 && _chatTiles.length == 2) {
      if (splitAxis != null) {
        _preferredSplitAxis = splitAxis;
      }
      _activeTileId = _chatTiles[existingIdx].tileId;
      _lastFocusedChatTileId = _activeTileId;
      _recalculateSplitAndWindowLocks(expandWindowIfNeeded: true);
      notifyListeners();
      return;
    }

    if (splitAxis != null) {
      _preferredSplitAxis = splitAxis;
    } else {
      // По умолчанию выбираем горизонтальный сплит, если ширина >= 960px, иначе вертикальный
      _preferredSplitAxis = _windowSize.width >= kThreeColumnBreakpoint
          ? Axis.horizontal
          : Axis.vertical;
    }

    if (_chatTiles.isEmpty) {
      openChatInActiveTile(
        chatId: chatId,
        chatType: chatType,
        chatName: effectiveChatName,
        avatarUrl: avatarUrl,
        isOnline: effectiveIsOnline,
        lastSeen: effectiveLastSeen,
        otherUserId: otherUserId,
        initialMessageId: initialMessageId,
      );
      return;
    }

    if (_chatTiles.length == 1) {
      final newTile = _createTileDescriptor(
        chatId: chatId,
        chatType: chatType,
        chatName: effectiveChatName,
        avatarUrl: avatarUrl,
        isOnline: effectiveIsOnline,
        lastSeen: effectiveLastSeen,
        otherUserId: otherUserId,
        initialMessageId: initialMessageId,
      );
      if (placeFirst) {
        _chatTiles.insert(0, newTile);
      } else {
        _chatTiles.add(newTile);
      }
      _chatSplitRatio = 0.5;
      _activeTileId = newTile.tileId;
      _lastFocusedChatTileId = newTile.tileId;
      _singlePaneShowingChat = true;
      _recalculateSplitAndWindowLocks(expandWindowIfNeeded: true);
      notifyListeners();
      return;
    }

    // Если уже открыто 2 тайла — выбираем целевой тайл по позиции сплита или неактивный
    final ChatTileDescriptor target;
    if (splitAxis != null) {
      target = placeFirst ? _chatTiles.first : _chatTiles.last;
    } else {
      final active = focusedChatTile ?? _chatTiles.first;
      target = _chatTiles.firstWhere(
        (t) => t.tileId != active.tileId,
        orElse: () => _chatTiles.last,
      );
    }
    final prevChatId = target.chatId;
    target.chatId = chatId;
    target.chatType = chatType;
    target.chatName = effectiveChatName;
    target.avatarUrl = avatarUrl;
    target.isOnline = effectiveIsOnline;
    target.lastSeen = effectiveLastSeen;
    target.otherUserId = otherUserId;
    target.initialMessageId = initialMessageId;
    target.revision++;
    target.navigatorKey.currentState?.popUntil((route) => route.isFirst);

    _activeTileId = target.tileId;
    _lastFocusedChatTileId = target.tileId;
    _recalculateSplitAndWindowLocks(expandWindowIfNeeded: true);
    if (prevChatId != chatId) {
      onChatTileClosed?.call(prevChatId);
    }
    notifyListeners();
  }

  /// Удобный хелпер для открытия модели [Chat] из `MainScreen`.
  void openChatModel(Chat chat, {bool inAdjacentTile = false, String? fallbackSavedTitle, String? fallbackSavedAvatar}) {
    final String effectiveName = chat.chatType == 'saved'
        ? (fallbackSavedTitle ?? 'Избранное')
        : chat.name;
    final String? effectiveAvatar = chat.chatType == 'saved'
        ? (chat.avatarUrl ?? fallbackSavedAvatar)
        : chat.avatarUrl;

    if (inAdjacentTile) {
      openChatInAdjacentTile(
        chatId: chat.id,
        chatType: chat.chatType,
        chatName: effectiveName,
        avatarUrl: effectiveAvatar,
        isOnline: chat.isOnline,
        lastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
        otherUserId: chat.otherUserId,
      );
    } else {
      openChatInActiveTile(
        chatId: chat.id,
        chatType: chat.chatType,
        chatName: effectiveName,
        avatarUrl: effectiveAvatar,
        isOnline: chat.isOnline,
        lastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
        otherUserId: chat.otherUserId,
      );
    }
  }

  /// Закрывает конкретный тайл чата по его [tileId].
  void closeChatTile(String tileId) {
    final idx = _chatTiles.indexWhere((t) => t.tileId == tileId);
    if (idx == -1) return;

    // В однооконном мобильном/узком режиме (`width < 640px`), если открыто 2 чата,
    // закрываем активный; если 1 чат — удаляем его и возвращаемся к списку чатов.
    final removed = _chatTiles.removeAt(idx);
    _tileBackHandlers.remove(tileId);
    onChatTileClosed?.call(removed.chatId);

    if (_chatTiles.isNotEmpty) {
      _activeTileId = _chatTiles.first.tileId;
      _lastFocusedChatTileId = _activeTileId;
    } else {
      _activeTileId = kLeftTileId;
      _lastFocusedChatTileId = null;
      _singlePaneShowingChat = false;
    }

    _recalculateSplitAndWindowLocks();
    notifyListeners();
  }

  /// Закрывает тайл чата с плавной анимацией сдвига вправо в однооконном режиме.
  Future<void> requestCloseChatTile(
    String tileId, {
    bool animateSinglePane = true,
  }) async {
    final idx = _chatTiles.indexWhere((t) => t.tileId == tileId);
    if (idx == -1) return;

    final bool shouldAnimate = animateSinglePane &&
        singlePaneShowingChat &&
        _chatTiles.length < 2 &&
        onRequestAnimatedSinglePaneClose != null;
    if (shouldAnimate) {
      await onRequestAnimatedSinglePaneClose!(tileId);
    }
    closeChatTile(tileId);
  }

  /// Универсальный выход из экрана чата или вложенного под-экрана (по кнопке «Назад» в AppBar и т.д.).
  /// Если во вложенном [Navigator] есть куда вернуться (`canPop() == true`), делает `pop()`.
  /// Если мы на корневом экране чата внутри тайла — плавно закрывает тайл чата.
  static void popOrCloseChatTile(BuildContext context) {
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    final tileId = TileViewportScope.maybeTileIdOf(context);
    if (tileId != null &&
        tileId != kLeftTileId &&
        instance.isWorkspaceMounted) {
      instance.requestCloseChatTile(tileId);
      return;
    }
    if (instance.isWorkspaceMounted && instance.singlePaneShowingChat) {
      final active = instance.focusedChatTile;
      if (active != null) {
        instance.requestCloseChatTile(active.tileId);
        return;
      }
    }
    nav?.maybePop();
  }

  /// Закрывает все открытые тайлы чатов (например, при выходе или смене аккаунта).
  void closeAllChats() {
    if (_chatTiles.isEmpty && _activeDrag == null) return;
    _chatTiles.clear();
    _tileBackHandlers.removeWhere((key, _) => key != kLeftTileId);
    _activeTileId = kLeftTileId;
    _lastFocusedChatTileId = null;
    _singlePaneShowingChat = false;
    _activeDrag = null;
    _hoveredDropSlot = null;
    _hoveredTargetTileId = null;
    _recalculateSplitAndWindowLocks();
    notifyListeners();
  }

  ChatTileDescriptor _createTileDescriptor({
    required String chatId,
    required String chatType,
    required String chatName,
    String? avatarUrl,
    bool isOnline = false,
    DateTime? lastSeen,
    String? otherUserId,
    String? initialMessageId,
  }) {
    _tileIdCounter++;
    return ChatTileDescriptor(
      tileId: 'chat_tile_$_tileIdCounter',
      chatId: chatId,
      chatType: chatType,
      chatName: chatName,
      avatarUrl: avatarUrl,
      isOnline: isOnline,
      lastSeen: lastSeen,
      otherUserId: otherUserId,
      initialMessageId: initialMessageId,
    );
  }

  // === Управление Drag & Drop с живым сдвигом тайлов ===

  Rect? _lastRightWorkspaceGlobalRect;
  Rect? Function()? rightWorkspaceRectResolver;

  bool get canSplitHorizontally => _windowSize.width >= kThreeColumnBreakpoint;
  bool get canSplitVertically =>
      _windowSize.width >= kTwoColumnBreakpoint &&
      _windowSize.height >= kVerticalSplitHeightBreakpoint;

  void startDraggingChat(DraggingChatPayload payload) {
    _activeDrag = payload;
    _hoveredDropSlot = null;
    _hoveredTargetTileId = null;
    dragFrameNotifier.value++;
    notifyListeners();
  }

  TilingDropSlot _resolveSplitOrCenterSlot(
    double relX,
    double relY, {
    bool allowCurrentSplitAxis = false,
  }) {
    final bool allowHoriz = canSplitHorizontally ||
        (allowCurrentSplitAxis &&
            _chatTiles.length == 2 &&
            _effectiveSplitAxis == Axis.horizontal);
    final bool allowVert = canSplitVertically ||
        (allowCurrentSplitAxis &&
            _chatTiles.length == 2 &&
            _effectiveSplitAxis == Axis.vertical);

    if (allowHoriz && relX < 0.36) {
      return TilingDropSlot.left;
    }
    if (allowHoriz && relX > 0.64) {
      return TilingDropSlot.right;
    }
    if (allowVert && relY < 0.36) {
      return TilingDropSlot.top;
    }
    if (allowVert && relY > 0.64) {
      return TilingDropSlot.bottom;
    }
    return TilingDropSlot.replace;
  }

  void updateDraggingChat(
    Offset globalPosition, {
    Offset velocity = Offset.zero,
    Rect? rightWorkspaceGlobalRect,
  }) {
    final drag = _activeDrag;
    if (drag == null) return;

    drag.currentGlobalPosition = globalPosition;
    drag.velocity = velocity;
    // Обновляем легковесный нотификатор превью-карточки без полного ребилда дерева
    dragFrameNotifier.value++;

    final resolvedRect = rightWorkspaceGlobalRect ??
        rightWorkspaceRectResolver?.call() ??
        _lastRightWorkspaceGlobalRect;
    if (resolvedRect != null) {
      _lastRightWorkspaceGlobalRect = resolvedRect;
    }

    final effectiveRightRect = resolvedRect ??
        ((_windowSize.width >= kTwoColumnBreakpoint || _chatTiles.length >= 2)
            ? Rect.fromLTWH(
                _leftTileWidth + kDividerThickness,
                0,
                math.max(0.0, _windowSize.width - _leftTileWidth - kDividerThickness),
                _windowSize.height,
              )
            : null);

    if (effectiveRightRect == null || !effectiveRightRect.contains(globalPosition)) {
      if (_hoveredDropSlot != null || _hoveredTargetTileId != null) {
        _hoveredDropSlot = null;
        _hoveredTargetTileId = null;
        notifyListeners();
      }
      return;
    }

    // Вычисляем относительные координаты (0..1) внутри правой области чатов
    final relX = ((globalPosition.dx - effectiveRightRect.left) /
            effectiveRightRect.width)
        .clamp(0.0, 1.0);
    final relY = ((globalPosition.dy - effectiveRightRect.top) /
            effectiveRightRect.height)
        .clamp(0.0, 1.0);

    // Если нет открытых чатов — вся правая область является слотом replace
    if (_chatTiles.isEmpty) {
      if (_hoveredDropSlot != TilingDropSlot.replace || _hoveredTargetTileId != null) {
        _hoveredDropSlot = TilingDropSlot.replace;
        _hoveredTargetTileId = null;
        notifyListeners();
      }
      return;
    }

    // Если перетаскивается единственный открытый тайл сам над собой (или тот же чат из списка) — сплит не нужен
    if (_chatTiles.length == 1 &&
        (drag.sourceTileId == _chatTiles.first.tileId ||
            drag.chatId == _chatTiles.first.chatId)) {
      final firstId = _chatTiles.first.tileId;
      if (_hoveredDropSlot != TilingDropSlot.replace || _hoveredTargetTileId != firstId) {
        _hoveredDropSlot = TilingDropSlot.replace;
        _hoveredTargetTileId = firstId;
        notifyListeners();
      }
      return;
    }

    TilingDropSlot candidateSlot;
    String? targetTileId;

    if (_chatTiles.length == 1) {
      // Открыт 1 чат, перетаскивается другой чат из левого списка
      candidateSlot = _resolveSplitOrCenterSlot(relX, relY);
      targetTileId = _chatTiles.first.tileId;
    } else if (drag.sourceTileId != null) {
      // Открыто 2 чата, перетаскивается один из открытых чатов за его шапку:
      // Края (left/right/top/bottom) меняют чаты местами или меняют ось сплита,
      // а центр (replace) схлопывает 2 чата в 1 полноэкранный чат.
      candidateSlot = _resolveSplitOrCenterSlot(
        relX,
        relY,
        allowCurrentSplitAxis: true,
      );
      targetTileId = null;
    } else {
      // Открыто 2 чата, перетаскивается чат из левого списка:
      // Наведение на середину между чатами заменяет ОБА чата на один (targetTileId == null),
      // а наведение на конкретный тайл заменяет именно этот тайл (targetTileId == tile.tileId).
      final bool inCenterCollapse = _effectiveSplitAxis == Axis.horizontal
          ? ((relX - _chatSplitRatio).abs() <= 0.14 &&
              relY >= 0.34 &&
              relY <= 0.66)
          : (relX >= 0.34 &&
              relX <= 0.66 &&
              (relY - _chatSplitRatio).abs() <= 0.14);

      candidateSlot = TilingDropSlot.replace;
      if (inCenterCollapse) {
        targetTileId = null;
      } else if (_effectiveSplitAxis == Axis.horizontal) {
        targetTileId = relX < _chatSplitRatio
            ? _chatTiles[0].tileId
            : _chatTiles[1].tileId;
      } else {
        targetTileId = relY < _chatSplitRatio
            ? _chatTiles[0].tileId
            : _chatTiles[1].tileId;
      }
    }

    if (_hoveredDropSlot != candidateSlot || _hoveredTargetTileId != targetTileId) {
      _hoveredDropSlot = candidateSlot;
      _hoveredTargetTileId = targetTileId;
      notifyListeners();
    }
  }

  void endDraggingChat() {
    final drag = _activeDrag;
    final slot = _hoveredDropSlot;
    final targetTileId = _hoveredTargetTileId;

    _activeDrag = null;
    _hoveredDropSlot = null;
    _hoveredTargetTileId = null;

    if (drag == null || slot == null) {
      notifyListeners();
      return;
    }

    // Случай 1: Перетаскивался уже открытый тайл за его шапку
    if (drag.sourceTileId != null) {
      _applyExistingTileDrop(drag, slot, targetTileId);
      return;
    }

    // Случай 2: Перетаскивался чат из списка чатов (левого тайла)
    switch (slot) {
      case TilingDropSlot.left:
        openChatInAdjacentTile(
          chatId: drag.chatId,
          chatType: drag.chatType,
          chatName: drag.chatName,
          avatarUrl: drag.avatarUrl,
          isOnline: drag.isOnline,
          lastSeen: drag.lastSeen,
          otherUserId: drag.otherUserId,
          splitAxis: Axis.horizontal,
          placeFirst: true,
        );
        break;
      case TilingDropSlot.right:
        openChatInAdjacentTile(
          chatId: drag.chatId,
          chatType: drag.chatType,
          chatName: drag.chatName,
          avatarUrl: drag.avatarUrl,
          isOnline: drag.isOnline,
          lastSeen: drag.lastSeen,
          otherUserId: drag.otherUserId,
          splitAxis: Axis.horizontal,
          placeFirst: false,
        );
        break;
      case TilingDropSlot.top:
        openChatInAdjacentTile(
          chatId: drag.chatId,
          chatType: drag.chatType,
          chatName: drag.chatName,
          avatarUrl: drag.avatarUrl,
          isOnline: drag.isOnline,
          lastSeen: drag.lastSeen,
          otherUserId: drag.otherUserId,
          splitAxis: Axis.vertical,
          placeFirst: true,
        );
        break;
      case TilingDropSlot.bottom:
        openChatInAdjacentTile(
          chatId: drag.chatId,
          chatType: drag.chatType,
          chatName: drag.chatName,
          avatarUrl: drag.avatarUrl,
          isOnline: drag.isOnline,
          lastSeen: drag.lastSeen,
          otherUserId: drag.otherUserId,
          splitAxis: Axis.vertical,
          placeFirst: false,
        );
        break;
      case TilingDropSlot.replace:
        if (_chatTiles.length == 2 && targetTileId == null) {
          _collapseTwoChatsIntoOne(drag);
        } else if (targetTileId != null) {
          _replaceChatInSpecificTile(targetTileId, drag);
        } else {
          openChatInActiveTile(
            chatId: drag.chatId,
            chatType: drag.chatType,
            chatName: drag.chatName,
            avatarUrl: drag.avatarUrl,
            isOnline: drag.isOnline,
            lastSeen: drag.lastSeen,
            otherUserId: drag.otherUserId,
          );
        }
        break;
    }
  }

  void _collapseTwoChatsIntoOne(DraggingChatPayload drag) {
    if (_chatTiles.length < 2) {
      openChatInActiveTile(
        chatId: drag.chatId,
        chatType: drag.chatType,
        chatName: drag.chatName,
        avatarUrl: drag.avatarUrl,
        isOnline: drag.isOnline,
        lastSeen: drag.lastSeen,
        otherUserId: drag.otherUserId,
      );
      return;
    }

    final existingIdx = _chatTiles.indexWhere((t) => t.chatId == drag.chatId);
    if (existingIdx != -1) {
      final keepTile = _chatTiles[existingIdx];
      final otherTile = _chatTiles[existingIdx == 0 ? 1 : 0];
      _tileBackHandlers.remove(otherTile.tileId);
      _chatTiles
        ..clear()
        ..add(keepTile);
      _chatSplitRatio = 0.5;
      keepTile.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      _activeTileId = keepTile.tileId;
      _lastFocusedChatTileId = keepTile.tileId;
      _singlePaneShowingChat = true;
      onChatTileClosed?.call(otherTile.chatId);
      _recalculateSplitAndWindowLocks();
      notifyListeners();
      return;
    }

    final keepTile = _chatTiles[0];
    final removedTile = _chatTiles[1];
    final prevKeepChatId = keepTile.chatId;
    _tileBackHandlers.remove(removedTile.tileId);
    _chatTiles
      ..clear()
      ..add(keepTile);
    _chatSplitRatio = 0.5;

    keepTile.chatId = drag.chatId;
    keepTile.chatType = drag.chatType;
    keepTile.chatName = drag.chatName;
    keepTile.avatarUrl = drag.avatarUrl;
    keepTile.isOnline = drag.isOnline;
    keepTile.lastSeen = drag.lastSeen;
    keepTile.otherUserId = drag.otherUserId;
    keepTile.initialMessageId = null;
    keepTile.revision++;
    keepTile.navigatorKey.currentState?.popUntil((route) => route.isFirst);

    _activeTileId = keepTile.tileId;
    _lastFocusedChatTileId = keepTile.tileId;
    _singlePaneShowingChat = true;

    if (prevKeepChatId != drag.chatId) {
      onChatTileClosed?.call(prevKeepChatId);
    }
    if (removedTile.chatId != drag.chatId && removedTile.chatId != prevKeepChatId) {
      onChatTileClosed?.call(removedTile.chatId);
    }
    _recalculateSplitAndWindowLocks();
    notifyListeners();
  }

  void _replaceChatInSpecificTile(String targetTileId, DraggingChatPayload drag) {
    final targetIdx = _chatTiles.indexWhere((t) => t.tileId == targetTileId);
    if (targetIdx == -1) {
      openChatInActiveTile(
        chatId: drag.chatId,
        chatType: drag.chatType,
        chatName: drag.chatName,
        avatarUrl: drag.avatarUrl,
        isOnline: drag.isOnline,
        lastSeen: drag.lastSeen,
        otherUserId: drag.otherUserId,
      );
      return;
    }

    final existingIdx = _chatTiles.indexWhere((t) => t.chatId == drag.chatId);
    if (existingIdx != -1) {
      if (existingIdx != targetIdx && _chatTiles.length == 2) {
        final reversed = _chatTiles.reversed.toList();
        _chatTiles
          ..clear()
          ..addAll(reversed);
      }
      final existingTile = _chatTiles[targetIdx];
      existingTile.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      _activeTileId = existingTile.tileId;
      _lastFocusedChatTileId = existingTile.tileId;
      _singlePaneShowingChat = true;
      notifyListeners();
      return;
    }

    final target = _chatTiles[targetIdx];
    final previousChatId = target.chatId;
    target.chatId = drag.chatId;
    target.chatType = drag.chatType;
    target.chatName = drag.chatName;
    target.avatarUrl = drag.avatarUrl;
    target.isOnline = drag.isOnline;
    target.lastSeen = drag.lastSeen;
    target.otherUserId = drag.otherUserId;
    target.initialMessageId = null;
    target.revision++;
    target.navigatorKey.currentState?.popUntil((route) => route.isFirst);

    _activeTileId = target.tileId;
    _lastFocusedChatTileId = target.tileId;
    _singlePaneShowingChat = true;

    if (previousChatId != drag.chatId) {
      onChatTileClosed?.call(previousChatId);
    }
    notifyListeners();
  }

  void cancelDraggingChat() {
    if (_activeDrag == null) return;
    _activeDrag = null;
    _hoveredDropSlot = null;
    _hoveredTargetTileId = null;
    notifyListeners();
  }

  void _applyExistingTileDrop(
    DraggingChatPayload drag,
    TilingDropSlot slot,
    String? targetTileId,
  ) {
    if (_chatTiles.length < 2) {
      notifyListeners();
      return;
    }

    final srcIndex = _chatTiles.indexWhere((t) => t.tileId == drag.sourceTileId);
    if (srcIndex == -1) {
      notifyListeners();
      return;
    }

    final srcTile = _chatTiles[srcIndex];
    final otherTile = _chatTiles[srcIndex == 0 ? 1 : 0];

    switch (slot) {
      case TilingDropSlot.left:
        _preferredSplitAxis = Axis.horizontal;
        _chatTiles
          ..clear()
          ..addAll([srcTile, otherTile]);
        break;
      case TilingDropSlot.right:
        _preferredSplitAxis = Axis.horizontal;
        _chatTiles
          ..clear()
          ..addAll([otherTile, srcTile]);
        break;
      case TilingDropSlot.top:
        _preferredSplitAxis = Axis.vertical;
        _chatTiles
          ..clear()
          ..addAll([srcTile, otherTile]);
        break;
      case TilingDropSlot.bottom:
        _preferredSplitAxis = Axis.vertical;
        _chatTiles
          ..clear()
          ..addAll([otherTile, srcTile]);
        break;
      case TilingDropSlot.replace:
        // Схлопываем 2 открытых чата в 1 при перетаскивании чата на середину
        _tileBackHandlers.remove(otherTile.tileId);
        _chatTiles
          ..clear()
          ..add(srcTile);
        _chatSplitRatio = 0.5;
        onChatTileClosed?.call(otherTile.chatId);
        break;
    }

    _activeTileId = srcTile.tileId;
    _lastFocusedChatTileId = srcTile.tileId;
    _recalculateSplitAndWindowLocks();
    notifyListeners();
  }

  // === Приоритетная обработка действия «Назад» (Esc / Trackpad 2-Finger Swipe / Back Button) ===

  /// Выполняет действие «Назад» для указанного [targetTileId] (или текущего активного тайла)
  /// по строгой цепочке приоритетов:
  /// 1. Внутренние меню / панель эмодзи / запись / выделение в этом тайле.
  /// 2. Вложенный [Navigator] этого тайла (профиль, настройки, вложения и т.д.).
  /// 3. Закрытие самого тайла чата (или возврат на вкладку Чатов в левом тайле).
  Future<bool> handleBackAction({String? forTileId, NavigatorState? rootNavigator}) async {
    // 0. Если в процессе перетаскивания тайла нажали Esc — отменяем перетаскивание
    if (_activeDrag != null) {
      cancelDraggingChat();
      return true;
    }

    // 1. Если на корневом Navigator открыт полноэкранный диалог/просмотрщик медиа/звонок —
    // сначала закрываем его.
    if (rootNavigator != null && rootNavigator.canPop()) {
      final popped = await rootNavigator.maybePop();
      if (popped) return true;
    }

    // В узком режиме (< 640px), если открыт чат поверх списка, целью является активный чат
    final String effectiveTileId;
    if (forTileId != null) {
      effectiveTileId = forTileId;
    } else if (_windowSize.width < kTwoColumnBreakpoint && singlePaneShowingChat) {
      effectiveTileId = focusedChatTile?.tileId ?? _activeTileId;
    } else if (_activeTileId != kLeftTileId &&
        _chatTiles.any((t) => t.tileId == _activeTileId)) {
      effectiveTileId = _activeTileId;
    } else if ( _chatTiles.isNotEmpty && _lastFocusedChatTileId != null &&
        _chatTiles.any((t) => t.tileId == _lastFocusedChatTileId)) {
      effectiveTileId = _lastFocusedChatTileId!;
    } else {
      effectiveTileId = kLeftTileId;
    }

    // 2. Проверяем зарегистрированные внутренние перехватчики тайла (в обратном порядке — от верхних к нижним)
    final handlers = _tileBackHandlers[effectiveTileId];
    if (handlers != null && handlers.isNotEmpty) {
      for (int i = handlers.length - 1; i >= 0; i--) {
        if (handlers[i]()) {
          return true;
        }
      }
    }

    // 3. Проверяем вложенный Navigator целевого тайла
    if (effectiveTileId == kLeftTileId) {
      final leftNav = leftTileNavigatorKey.currentState;
      if (leftNav != null && leftNav.canPop()) {
        final popped = await leftNav.maybePop();
        if (popped) return true;
      }
      // Если на корневом экране MainScreen открыта вкладка Настроек или Поиска — возвращаем на Чаты
      if (onMainScreenHandleBack != null && onMainScreenHandleBack!()) {
        return true;
      }
      // Если в левом тайле нечего закрывать, но справа есть открытый чат — закрываем последний активный чат
      if (_chatTiles.isNotEmpty) {
        final chatTile = focusedChatTile ?? _chatTiles.last;
        return handleBackAction(forTileId: chatTile.tileId);
      }
      return false;
    } else {
      final idx = _chatTiles.indexWhere((t) => t.tileId == effectiveTileId);
      if (idx != -1) {
        final tile = _chatTiles[idx];
        final tileNav = tile.navigatorKey.currentState;
        if (tileNav != null &&
            (tileNav.canPop() ||
                tile.rootRoute?.popDisposition == RoutePopDisposition.doNotPop)) {
          final popped = await tileNav.maybePop();
          if (popped) return true;
        }
        // Находимся на корневом экране чата внутри тайла -> закрываем сам тайл чата!
        await requestCloseChatTile(tile.tileId);
        return true;
      }
    }

    return false;
  }
}
