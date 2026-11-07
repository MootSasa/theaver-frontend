import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/whiteboard_models.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

/// REST & real-time synchronization service for the Miro-style Interactive Whiteboard.
class WhiteboardService {
  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetches all persisted elements on a board (`GET /api/whiteboards/:roomId`).
  static Future<List<WhiteboardElement>> fetchElements(String roomId) async {
    if (roomId.isEmpty || roomId.startsWith('local_')) return [];
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/whiteboards/$roomId'),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['elements'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((m) =>
                  WhiteboardElement.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[WhiteboardService] fetchElements error: $e');
    }
    return [];
  }

  /// Posts a whiteboard mutation or cursor/laser event (`POST /api/whiteboards/:roomId/events`).
  static Future<bool> postEvent(
    String roomId,
    Map<String, dynamic> payload,
  ) async {
    if (roomId.isEmpty || roomId.startsWith('local_')) return false;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/whiteboards/$roomId/events'),
        headers: await _headers(),
        body: jsonEncode(payload),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[WhiteboardService] postEvent error: $e');
      return false;
    }
  }

  /// Clears all elements on the board (`DELETE /api/whiteboards/:roomId`).
  static Future<bool> clearBoard(String roomId) async {
    if (roomId.isEmpty || roomId.startsWith('local_')) return false;
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/whiteboards/$roomId'),
        headers: await _headers(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[WhiteboardService] clearBoard error: $e');
      return false;
    }
  }
}

/// Interactive state controller for a collaborative Miro-style whiteboard session.
class WhiteboardController extends ChangeNotifier {
  final String roomId;
  final String? chatId;

  static const List<int> defaultPalette = [
    0xFF2979FF, // Electric Blue
    0xFF00E676, // Emerald Green
    0xFFFFB300, // Amber Gold
    0xFFFF5252, // Coral Red
    0xFFAA00FF, // Vivid Purple
    0xFF00E5FF, // Cyan
    0xFFFF4081, // Pink
    0xFFFFFFFF, // Pure White
    0xFF1E2430, // Charcoal Ink
  ];

  static const List<int> stickyPalette = [
    0xFFFFF59D, // Classic Miro Yellow
    0xFFA5D6A7, // Mint Green
    0xFF90CAF9, // Sky Blue
    0xFFF48FB1, // Pastel Pink
    0xFFCE93D8, // Lavender
    0xFFFFCC80, // Warm Peach
  ];

  String _currentUserId = 'local';
  String _currentUserName = 'Вы';
  int _myCursorColor = 0xFF2979FF;

  final Map<String, WhiteboardElement> _elements = {};
  final List<Map<String, WhiteboardElement>> _undoStack = [];
  final List<Map<String, WhiteboardElement>> _redoStack = [];
  final Map<String, WhiteboardRemoteCursor> _remoteCursors = {};
  final List<LaserTrailPoint> _localLaserTrail = [];
  final List<int> _customColors = [];

  WhiteboardTool _activeTool = WhiteboardTool.pen;
  int _activeColor = 0xFF2979FF;
  double _activeStrokeWidth = 4.0;
  String _activeStrokeStyle = 'solid'; // 'solid' | 'dashed' | 'dotted'
  String _activeFillStyle = 'translucent'; // 'translucent' | 'solid' | 'none'
  double _activeFontSize = 16.0;
  double _activeOpacity = 1.0;
  WhiteboardGridStyle _gridStyle = WhiteboardGridStyle.dots;
  String? _selectedElementId;
  WhiteboardResizeHandle? _activeResizeHandle;
  WhiteboardElement? _activeDraftElement;
  bool _isLoading = false;

  StreamSubscription<WebSocketEvent>? _wsSub;
  Timer? _decayTimer;
  int _lastCursorSentMs = 0;
  int _lastDraftSentMs = 0;

  WhiteboardController({
    required this.roomId,
    this.chatId,
  }) {
    _initSession();
  }

  String get currentUserId => _currentUserId;
  String get currentUserName => _currentUserName;
  WhiteboardTool get activeTool => _activeTool;
  int get activeColor => _activeColor;
  double get activeStrokeWidth => _activeStrokeWidth;
  String get activeStrokeStyle => _activeStrokeStyle;
  String get activeFillStyle => _activeFillStyle;
  double get activeFontSize => _activeFontSize;
  double get activeOpacity => _activeOpacity;
  WhiteboardGridStyle get gridStyle => _gridStyle;
  String? get selectedElementId => _selectedElementId;
  WhiteboardElement? get selectedElement =>
      _selectedElementId != null ? _elements[_selectedElementId] : null;
  WhiteboardElement? get activeDraftElement => _activeDraftElement;
  bool get isLoading => _isLoading;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<int> get customColors => List.unmodifiable(_customColors);

  List<WhiteboardElement> get elements {
    final list = _elements.values.toList();
    list.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return list;
  }

  Map<String, WhiteboardRemoteCursor> get remoteCursors =>
      Map.unmodifiable(_remoteCursors);
  List<LaserTrailPoint> get localLaserTrail =>
      List.unmodifiable(_localLaserTrail);

  Future<void> _initSession() async {
    final uid = await AuthService.getUserId();
    final acc = AccountManager().currentAccount;
    if (uid != null && uid.isNotEmpty) {
      _currentUserId = uid;
    }
    if (acc != null) {
      final dn = acc.displayName;
      final un = acc.username;
      _currentUserName = (dn != null && dn.isNotEmpty)
          ? dn
          : ((un != null && un.isNotEmpty) ? un : 'Участник');
    }
    final hash = _currentUserId.hashCode.abs();
    _myCursorColor = defaultPalette[hash % 7];

    _wsSub = WebSocketService().eventStream.listen(_onWsEvent);
    _decayTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      _pruneStaleCursorsAndLaser();
    });

    await loadInitialBoard();
  }

  Future<void> loadInitialBoard() async {
    _isLoading = true;
    notifyListeners();
    final effectiveRoomId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;
    final loaded = await WhiteboardService.fetchElements(effectiveRoomId);
    for (final e in loaded) {
      _elements[e.id] = e;
    }
    _isLoading = false;
    notifyListeners();
  }

  void setTool(WhiteboardTool tool) {
    if (_activeTool == tool) return;
    _activeTool = tool;
    if (tool != WhiteboardTool.select) {
      _selectedElementId = null;
      _activeResizeHandle = null;
    }
    if (tool == WhiteboardTool.sticky &&
        !stickyPalette.contains(_activeColor) &&
        !_customColors.contains(_activeColor)) {
      _activeColor = stickyPalette.first;
    } else if (tool != WhiteboardTool.sticky &&
        stickyPalette.contains(_activeColor)) {
      _activeColor = defaultPalette.first;
    }
    notifyListeners();
  }

  void setColor(int colorValue, {bool addToCustom = false}) {
    _activeColor = colorValue;
    if (addToCustom &&
        !defaultPalette.contains(colorValue) &&
        !stickyPalette.contains(colorValue)) {
      _customColors.remove(colorValue);
      _customColors.insert(0, colorValue);
      if (_customColors.length > 8) {
        _customColors.removeLast();
      }
    }
    if (_selectedElementId != null &&
        _elements.containsKey(_selectedElementId)) {
      _saveUndoSnapshot();
      final updated = _elements[_selectedElementId!]!.copyWith(
        colorValue: colorValue,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _elements[updated.id] = updated;
      _broadcastUpsert(updated);
    }
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _activeStrokeWidth = width.clamp(1.0, 48.0);
    if (_selectedElementId != null &&
        _elements.containsKey(_selectedElementId)) {
      _saveUndoSnapshot();
      final updated = _elements[_selectedElementId!]!.copyWith(
        strokeWidth: _activeStrokeWidth,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _elements[updated.id] = updated;
      _broadcastUpsert(updated);
    }
    notifyListeners();
  }

  void setStrokeStyle(String style) {
    _activeStrokeStyle = style;
    if (_selectedElementId != null &&
        _elements.containsKey(_selectedElementId)) {
      _saveUndoSnapshot();
      final updated = _elements[_selectedElementId!]!.copyWith(
        strokeStyle: style,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _elements[updated.id] = updated;
      _broadcastUpsert(updated);
    }
    notifyListeners();
  }

  void cycleStrokeStyle() {
    final current = selectedElement?.strokeStyle ?? _activeStrokeStyle;
    final next = switch (current) {
      'solid' => 'dashed',
      'dashed' => 'dotted',
      _ => 'solid',
    };
    setStrokeStyle(next);
  }

  void setFillStyle(String style) {
    _activeFillStyle = style;
    if (_selectedElementId != null &&
        _elements.containsKey(_selectedElementId)) {
      _saveUndoSnapshot();
      final updated = _elements[_selectedElementId!]!.copyWith(
        fillStyle: style,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _elements[updated.id] = updated;
      _broadcastUpsert(updated);
    }
    notifyListeners();
  }

  void cycleFillStyle() {
    final current = selectedElement?.fillStyle ?? _activeFillStyle;
    final next = switch (current) {
      'translucent' => 'solid',
      'solid' => 'none',
      _ => 'translucent',
    };
    setFillStyle(next);
  }

  void setFontSize(double size) {
    _activeFontSize = size.clamp(10.0, 64.0);
    if (_selectedElementId != null &&
        _elements.containsKey(_selectedElementId)) {
      _saveUndoSnapshot();
      final updated = _elements[_selectedElementId!]!.copyWith(
        fontSize: _activeFontSize,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _elements[updated.id] = updated;
      _broadcastUpsert(updated);
    }
    notifyListeners();
  }

  void setOpacity(double opacity) {
    _activeOpacity = opacity.clamp(0.1, 1.0);
    if (_selectedElementId != null &&
        _elements.containsKey(_selectedElementId)) {
      _saveUndoSnapshot();
      final updated = _elements[_selectedElementId!]!.copyWith(
        opacity: _activeOpacity,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _elements[updated.id] = updated;
      _broadcastUpsert(updated);
    }
    notifyListeners();
  }

  void cycleGridStyle() {
    switch (_gridStyle) {
      case WhiteboardGridStyle.dots:
        _gridStyle = WhiteboardGridStyle.lines;
        break;
      case WhiteboardGridStyle.lines:
        _gridStyle = WhiteboardGridStyle.none;
        break;
      case WhiteboardGridStyle.none:
        _gridStyle = WhiteboardGridStyle.dots;
        break;
    }
    notifyListeners();
  }

  void selectElement(String? id) {
    if (_selectedElementId == id) return;
    _selectedElementId = id;
    _activeResizeHandle = null;
    notifyListeners();
  }

  void _saveUndoSnapshot() {
    _undoStack.add(Map<String, WhiteboardElement>.from(_elements));
    if (_undoStack.length > 40) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(Map<String, WhiteboardElement>.from(_elements));
    final prev = _undoStack.removeLast();
    _syncDiffWithRemote(prev);
    _elements
      ..clear()
      ..addAll(prev);
    _selectedElementId = null;
    _activeResizeHandle = null;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(Map<String, WhiteboardElement>.from(_elements));
    final next = _redoStack.removeLast();
    _syncDiffWithRemote(next);
    _elements
      ..clear()
      ..addAll(next);
    _selectedElementId = null;
    _activeResizeHandle = null;
    notifyListeners();
  }

  void _syncDiffWithRemote(Map<String, WhiteboardElement> targetState) {
    final currentIds = _elements.keys.toSet();
    final targetIds = targetState.keys.toSet();
    for (final deletedId in currentIds.difference(targetIds)) {
      _broadcastDelete(deletedId);
    }
    for (final entry in targetState.entries) {
      final cur = _elements[entry.key];
      if (cur == null || cur.updatedAt != entry.value.updatedAt) {
        final refreshed = entry.value.copyWith(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _broadcastUpsert(refreshed);
      }
    }
  }

  // ===========================================================================
  // Interactive Drawing / Element Manipulation
  // ===========================================================================

  void startInteraction(Offset scenePoint) {
    if (_activeTool == WhiteboardTool.laser) {
      _appendLocalLaserPoint(scenePoint);
      _broadcastCursorOrLaser(scenePoint, isLaser: true);
      return;
    }

    if (_activeTool == WhiteboardTool.eraser) {
      _eraseAtPoint(scenePoint);
      return;
    }

    if (_activeTool == WhiteboardTool.select) {
      // First check if dragging a resize handle of the currently selected element
      final currentSelected = selectedElement;
      if (currentSelected != null) {
        final handle = currentSelected.hitTestHandle(scenePoint);
        if (handle != null) {
          _activeResizeHandle = handle;
          _saveUndoSnapshot();
          notifyListeners();
          return;
        }
      }

      _activeResizeHandle = null;
      final hit = _hitTestTopElement(scenePoint);
      _selectedElementId = hit?.id;
      if (hit != null) {
        _saveUndoSnapshot();
      }
      notifyListeners();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'wb_${_currentUserId}_$now';

    if (_activeTool == WhiteboardTool.pen ||
        _activeTool == WhiteboardTool.highlighter) {
      _activeDraftElement = WhiteboardElement(
        id: id,
        type: _activeTool == WhiteboardTool.highlighter
            ? 'highlighter'
            : 'stroke',
        authorId: _currentUserId,
        authorName: _currentUserName,
        points: [scenePoint],
        colorValue: _activeColor,
        strokeWidth: _activeTool == WhiteboardTool.highlighter
            ? (_activeStrokeWidth * 2.6).clamp(10.0, 48.0)
            : _activeStrokeWidth,
        strokeStyle: _activeTool == WhiteboardTool.highlighter
            ? 'solid'
            : _activeStrokeStyle,
        opacity: _activeOpacity,
        updatedAt: now,
      );
      notifyListeners();
    } else if (_activeTool == WhiteboardTool.rectangle ||
        _activeTool == WhiteboardTool.ellipse ||
        _activeTool == WhiteboardTool.diamond ||
        _activeTool == WhiteboardTool.triangle ||
        _activeTool == WhiteboardTool.line ||
        _activeTool == WhiteboardTool.arrow) {
      final shapeType = switch (_activeTool) {
        WhiteboardTool.rectangle => 'rectangle',
        WhiteboardTool.ellipse => 'ellipse',
        WhiteboardTool.diamond => 'diamond',
        WhiteboardTool.triangle => 'triangle',
        WhiteboardTool.line => 'line',
        WhiteboardTool.arrow => 'arrow',
        _ => 'rectangle',
      };
      _activeDraftElement = WhiteboardElement(
        id: id,
        type: shapeType,
        authorId: _currentUserId,
        authorName: _currentUserName,
        x: scenePoint.dx,
        y: scenePoint.dy,
        width: 1,
        height: 1,
        colorValue: _activeColor,
        strokeWidth: _activeStrokeWidth,
        strokeStyle: _activeStrokeStyle,
        fillStyle: _activeFillStyle,
        fontSize: _activeFontSize,
        opacity: _activeOpacity,
        updatedAt: now,
      );
      notifyListeners();
    }
  }

  void updateInteraction(Offset scenePoint, Offset sceneDelta) {
    _broadcastCursorOrLaser(
      scenePoint,
      isLaser: _activeTool == WhiteboardTool.laser,
    );

    if (_activeTool == WhiteboardTool.laser) {
      _appendLocalLaserPoint(scenePoint);
      return;
    }

    if (_activeTool == WhiteboardTool.eraser) {
      _eraseAtPoint(scenePoint);
      return;
    }

    if (_activeTool == WhiteboardTool.select) {
      if (_selectedElementId != null &&
          _elements.containsKey(_selectedElementId)) {
        final current = _elements[_selectedElementId!]!;
        final WhiteboardElement updated;
        if (_activeResizeHandle != null) {
          updated = current.resizedByHandle(_activeResizeHandle!, scenePoint);
        } else {
          updated = current.translated(sceneDelta.dx, sceneDelta.dy);
        }
        _elements[updated.id] = updated;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastDraftSentMs >= 45) {
          _lastDraftSentMs = now;
          _broadcastUpsert(updated, persistToServer: false);
        }
        notifyListeners();
      }
      return;
    }

    final draft = _activeDraftElement;
    if (draft == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (draft.isStroke) {
      final lastPt = draft.points.last;
      if ((scenePoint - lastPt).distance < 1.8) return;
      _activeDraftElement = draft.copyWith(
        points: [...draft.points, scenePoint],
        updatedAt: now,
      );
    } else if (draft.isShape) {
      _activeDraftElement = draft.copyWith(
        width: scenePoint.dx - draft.x,
        height: scenePoint.dy - draft.y,
        updatedAt: now,
      );
    }

    // Stream live stroke/shape preview to peers every 50ms
    if (now - _lastDraftSentMs >= 50 && _activeDraftElement != null) {
      _lastDraftSentMs = now;
      _broadcastUpsert(_activeDraftElement!, persistToServer: false);
    }
    notifyListeners();
  }

  void endInteraction() {
    if (_activeTool == WhiteboardTool.select) {
      _activeResizeHandle = null;
      if (_selectedElementId != null &&
          _elements.containsKey(_selectedElementId)) {
        _broadcastUpsert(_elements[_selectedElementId!]!);
      }
      return;
    }

    final draft = _activeDraftElement;
    if (draft == null) return;
    _activeDraftElement = null;

    if (draft.isShape && draft.width.abs() < 6 && draft.height.abs() < 6) {
      notifyListeners();
      return;
    }

    _saveUndoSnapshot();
    final finalized = draft.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _elements[finalized.id] = finalized;
    _broadcastUpsert(finalized);
    notifyListeners();
  }

  /// Adds a Sticky Note or Text Box at [scenePoint].
  WhiteboardElement addStickyOrText({
    required Offset scenePoint,
    required bool isSticky,
    String initialText = '',
  }) {
    _saveUndoSnapshot();
    final now = DateTime.now().millisecondsSinceEpoch;
    final elem = WhiteboardElement(
      id: 'wb_${_currentUserId}_$now',
      type: isSticky ? 'sticky' : 'text',
      authorId: _currentUserId,
      authorName: _currentUserName,
      x: scenePoint.dx - (isSticky ? 95 : 80),
      y: scenePoint.dy - (isSticky ? 95 : 24),
      width: isSticky ? 190 : 220,
      height: isSticky ? 190 : 64,
      colorValue: isSticky
          ? (stickyPalette.contains(_activeColor) ||
                  _customColors.contains(_activeColor)
              ? _activeColor
              : stickyPalette.first)
          : _activeColor,
      strokeWidth: _activeStrokeWidth,
      fontSize: _activeFontSize,
      opacity: _activeOpacity,
      text: initialText.isNotEmpty
          ? initialText
          : (isSticky ? 'Новая заметка...' : 'Текст'),
      updatedAt: now,
    );
    _elements[elem.id] = elem;
    _selectedElementId = elem.id;
    _activeTool = WhiteboardTool.select;
    _broadcastUpsert(elem);
    notifyListeners();
    return elem;
  }

  /// Duplicates the selected or specified element with a `(24, 24)` offset.
  WhiteboardElement? duplicateElement([String? id]) {
    final targetId = id ?? _selectedElementId;
    if (targetId == null || !_elements.containsKey(targetId)) return null;
    _saveUndoSnapshot();
    final original = _elements[targetId]!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final clone = original.translated(24, 24).copyWith(
          id: 'wb_${_currentUserId}_$now',
          authorId: _currentUserId,
          authorName: _currentUserName,
          updatedAt: now,
        );
    _elements[clone.id] = clone;
    _selectedElementId = clone.id;
    _broadcastUpsert(clone);
    notifyListeners();
    return clone;
  }

  /// Moves the selected or specified element to the top of the z-order.
  void bringToFront([String? id]) {
    final targetId = id ?? _selectedElementId;
    if (targetId == null || !_elements.containsKey(targetId)) return;
    _saveUndoSnapshot();
    int maxUpdated = DateTime.now().millisecondsSinceEpoch;
    for (final e in _elements.values) {
      if (e.updatedAt >= maxUpdated) {
        maxUpdated = e.updatedAt + 1;
      }
    }
    final updated = _elements[targetId]!.copyWith(updatedAt: maxUpdated);
    _elements[targetId] = updated;
    _broadcastUpsert(updated);
    notifyListeners();
  }

  /// Moves the selected or specified element to the bottom of the z-order.
  void sendToBack([String? id]) {
    final targetId = id ?? _selectedElementId;
    if (targetId == null || !_elements.containsKey(targetId)) return;
    _saveUndoSnapshot();
    int minUpdated = DateTime.now().millisecondsSinceEpoch;
    for (final e in _elements.values) {
      if (e.updatedAt <= minUpdated) {
        minUpdated = math.max(1, e.updatedAt - 1);
      }
    }
    final updated = _elements[targetId]!.copyWith(updatedAt: minUpdated);
    _elements[targetId] = updated;
    _broadcastUpsert(updated);
    notifyListeners();
  }

  /// Updates the text or properties of an existing element.
  void updateElement(WhiteboardElement updated) {
    _saveUndoSnapshot();
    final stamped = updated.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _elements[stamped.id] = stamped;
    _broadcastUpsert(stamped);
    notifyListeners();
  }

  /// Deletes the currently selected element or a specific element by [id].
  void deleteElement([String? id]) {
    final targetId = id ?? _selectedElementId;
    if (targetId == null || !_elements.containsKey(targetId)) return;
    _saveUndoSnapshot();
    _elements.remove(targetId);
    if (_selectedElementId == targetId) {
      _selectedElementId = null;
      _activeResizeHandle = null;
    }
    _broadcastDelete(targetId);
    notifyListeners();
  }

  /// Clears all elements from the board.
  Future<void> clearAll() async {
    if (_elements.isEmpty) return;
    _saveUndoSnapshot();
    _elements.clear();
    _selectedElementId = null;
    _activeResizeHandle = null;
    notifyListeners();

    final effectiveRoomId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;
    _sendFastRelay({
      'action': 'clear_board',
      'room_id': effectiveRoomId,
    });
    await WhiteboardService.clearBoard(effectiveRoomId);
  }

  /// Broadcasts hover cursor position on Desktop/Web even when mouse button is not pressed.
  void onHover(Offset scenePoint) {
    _broadcastCursorOrLaser(
      scenePoint,
      isLaser: _activeTool == WhiteboardTool.laser,
    );
  }

  WhiteboardElement? _hitTestTopElement(Offset scenePoint) {
    final sorted = elements.reversed;
    for (final elem in sorted) {
      if (elem.containsPoint(scenePoint)) {
        return elem;
      }
    }
    return null;
  }

  void _eraseAtPoint(Offset scenePoint) {
    final hit = _hitTestTopElement(scenePoint);
    if (hit != null) {
      _saveUndoSnapshot();
      _elements.remove(hit.id);
      _broadcastDelete(hit.id);
      notifyListeners();
    }
  }

  void _appendLocalLaserPoint(Offset pt) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _localLaserTrail.add(LaserTrailPoint(point: pt, timestampMs: now));
    notifyListeners();
  }

  void _pruneStaleCursorsAndLaser() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;

    if (_localLaserTrail.isNotEmpty) {
      final before = _localLaserTrail.length;
      _localLaserTrail.removeWhere((p) => now - p.timestampMs > 850);
      if (_localLaserTrail.length != before) changed = true;
    }

    final staleUsers = <String>[];
    _remoteCursors.forEach((uid, cursor) {
      if (now - cursor.lastSeenMs > 8000) {
        staleUsers.add(uid);
        changed = true;
      } else if (cursor.laserTrail.isNotEmpty) {
        final filtered = cursor.laserTrail
            .where((p) => now - p.timestampMs <= 850)
            .toList();
        if (filtered.length != cursor.laserTrail.length) {
          _remoteCursors[uid] = cursor.copyWith(laserTrail: filtered);
          changed = true;
        }
      }
    });
    for (final uid in staleUsers) {
      _remoteCursors.remove(uid);
    }

    if (changed) {
      notifyListeners();
    }
  }

  // ===========================================================================
  // Outgoing & Incoming Real-Time Sync
  // ===========================================================================

  void _broadcastUpsert(
    WhiteboardElement element, {
    bool persistToServer = true,
  }) {
    final effectiveRoomId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;
    final payload = <String, dynamic>{
      'action': 'upsert_element',
      'room_id': effectiveRoomId,
      'element': element.toJson(),
    };
    _sendFastRelay(payload);
    if (persistToServer) {
      unawaited(WhiteboardService.postEvent(effectiveRoomId, payload));
    }
  }

  void _broadcastDelete(String elementId) {
    final effectiveRoomId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;
    final payload = <String, dynamic>{
      'action': 'delete_element',
      'room_id': effectiveRoomId,
      'element_id': elementId,
    };
    _sendFastRelay(payload);
    unawaited(WhiteboardService.postEvent(effectiveRoomId, payload));
  }

  void _broadcastCursorOrLaser(Offset scenePoint, {required bool isLaser}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCursorSentMs < 35) return;
    _lastCursorSentMs = now;

    final effectiveRoomId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;
    final payload = <String, dynamic>{
      'action': isLaser ? 'laser_move' : 'cursor_move',
      'room_id': effectiveRoomId,
      'user_id': _currentUserId,
      'user_name': _currentUserName,
      'color': _myCursorColor,
      'x': (scenePoint.dx * 10).roundToDouble() / 10,
      'y': (scenePoint.dy * 10).roundToDouble() / 10,
    };
    _sendFastRelay(payload);
    if (chatId == null || chatId!.isEmpty) {
      unawaited(WhiteboardService.postEvent(effectiveRoomId, payload));
    }
  }

  void _sendFastRelay(Map<String, dynamic> payload) {
    final targetChatId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;
    if (targetChatId.isEmpty) return;
    try {
      final envelope = <String, dynamic>{
        ...payload,
        'from_user_id': _currentUserId,
        'user_name': _currentUserName,
      };
      final encoded = base64Encode(utf8.encode(jsonEncode(envelope)));
      WebSocketService().sendEmojiInteraction(
        targetChatId,
        messageId: 'wb',
        emoji: encoded,
        action: '__whiteboard__',
      );
    } catch (_) {}
  }

  void _onWsEvent(WebSocketEvent event) {
    if (event.type == WebSocketEventType.emojiInteraction &&
        event.data['action']?.toString() == '__whiteboard__') {
      final rawEmoji = event.data['emoji']?.toString() ?? '';
      if (rawEmoji.isNotEmpty) {
        try {
          final decoded = utf8.decode(base64Decode(rawEmoji));
          final map = jsonDecode(decoded);
          if (map is Map<String, dynamic>) {
            final senderId = event.data['user_id']?.toString() ?? '';
            if (senderId.isNotEmpty) {
              map.putIfAbsent('from_user_id', () => senderId);
            }
            _handleIncomingBoardEvent(map);
          }
        } catch (_) {}
      }
      return;
    }

    final rawType = event.rawType.isNotEmpty
        ? event.rawType
        : (event.data['__raw_type'] ?? event.data['type'] ?? '').toString();
    if (rawType == 'whiteboard.event' || rawType == 'whiteboard_event') {
      final payload = event.data['payload'] is Map<String, dynamic>
          ? event.data['payload'] as Map<String, dynamic>
          : event.data;
      _handleIncomingBoardEvent(payload);
    }
  }

  void _handleIncomingBoardEvent(Map<String, dynamic> payload) {
    final eventRoomId = (payload['room_id'] ?? '').toString();
    final rawRoomId = (payload['raw_room_id'] ?? '').toString();
    final effectiveRoomId =
        (chatId != null && chatId!.isNotEmpty) ? chatId! : roomId;

    if (eventRoomId.isNotEmpty &&
        eventRoomId != effectiveRoomId &&
        eventRoomId != roomId &&
        rawRoomId != roomId) {
      return;
    }

    final senderId =
        (payload['from_user_id'] ?? payload['user_id'] ?? '').toString();
    if (senderId.isNotEmpty && senderId == _currentUserId) {
      return;
    }

    final action = (payload['action'] ?? '').toString();
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (action) {
      case 'upsert_element':
        final elemMap = payload['element'];
        if (elemMap is Map) {
          final elem = WhiteboardElement.fromJson(
            Map<String, dynamic>.from(elemMap),
          );
          if (elem.id.isNotEmpty) {
            final existing = _elements[elem.id];
            if (existing == null || elem.updatedAt >= existing.updatedAt) {
              _elements[elem.id] = elem;
              notifyListeners();
            }
          }
        }
        break;

      case 'delete_element':
        final elemId = (payload['element_id'] ?? '').toString();
        if (elemId.isNotEmpty && _elements.containsKey(elemId)) {
          _elements.remove(elemId);
          if (_selectedElementId == elemId) {
            _selectedElementId = null;
            _activeResizeHandle = null;
          }
          notifyListeners();
        }
        break;

      case 'clear_board':
        if (_elements.isNotEmpty) {
          _elements.clear();
          _selectedElementId = null;
          _activeResizeHandle = null;
          notifyListeners();
        }
        break;

      case 'cursor_move':
      case 'laser_move':
        if (senderId.isEmpty) break;
        final x = (payload['x'] as num?)?.toDouble() ?? 0.0;
        final y = (payload['y'] as num?)?.toDouble() ?? 0.0;
        final userName = (payload['user_name'] ?? 'Участник').toString();
        final colorVal = (payload['color'] as num?)?.toInt() ?? 0xFF00E676;
        final isLaser = action == 'laser_move';
        final pos = Offset(x, y);

        final prev = _remoteCursors[senderId];
        final nextTrail = isLaser
            ? [
                ...(prev?.laserTrail ?? const <LaserTrailPoint>[]),
                LaserTrailPoint(point: pos, timestampMs: now),
              ]
            : (prev?.laserTrail ?? const <LaserTrailPoint>[]);

        _remoteCursors[senderId] = WhiteboardRemoteCursor(
          userId: senderId,
          userName: userName,
          colorValue: colorVal,
          position: pos,
          isLaser: isLaser,
          laserTrail: nextTrail,
          lastSeenMs: now,
        );
        notifyListeners();
        break;
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _decayTimer?.cancel();
    super.dispose();
  }
}
