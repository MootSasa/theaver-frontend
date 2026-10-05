import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'auth_service.dart';
import 'avatar_sync_service.dart';
import 'account_manager.dart';

/// Event types for WebSocket messages
enum WebSocketEventType {
  connected,
  newMessage,
  newChat,
  chatUpdate,
  userStatus,
  typing,
  messageRead,
  userOnline,
  userOffline,
  pong,
  unreadCountUpdated,
  sessionTerminated,
  messageEdited,
  messageDeleted,
  messageReactionUpdated,
  userAvatarUpdated,
  userAppearanceUpdated,
}

/// WebSocket event data
class WebSocketEvent {
  final WebSocketEventType type;
  final Map<String, dynamic> data;
  final int timestamp;

  WebSocketEvent({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketEvent(
      type: _parseEventType(json['type'] as String?),
      data: json['data'] as Map<String, dynamic>? ?? {},
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static WebSocketEventType _parseEventType(String? type) {
    switch (type) {
      case 'connected':
        return WebSocketEventType.connected;
      case 'new_message':
        return WebSocketEventType.newMessage;
      case 'new_chat':
        return WebSocketEventType.newChat;
      case 'chat_update':
        return WebSocketEventType.chatUpdate;
      case 'user_status':
        return WebSocketEventType.userStatus;
      case 'typing':
        return WebSocketEventType.typing;
      case 'message_read':
        return WebSocketEventType.messageRead;
      case 'user_online':
        return WebSocketEventType.userOnline;
      case 'user_offline':
        return WebSocketEventType.userOffline;
      case 'pong':
        return WebSocketEventType.pong;
      case 'unread_count_updated':
        return WebSocketEventType.unreadCountUpdated;
      case 'session_terminated':
        return WebSocketEventType.sessionTerminated;
      case 'message_edited':
        return WebSocketEventType.messageEdited;
      case 'message_deleted':
      case 'delete_message':
        return WebSocketEventType.messageDeleted;
      case 'message_reaction_updated':
        return WebSocketEventType.messageReactionUpdated;
      case 'user_avatar_updated':
        return WebSocketEventType.userAvatarUpdated;
      case 'user_appearance_updated':
        return WebSocketEventType.userAppearanceUpdated;
      default:
        return WebSocketEventType.connected;
    }
  }
}

/// Callback types for WebSocket events
typedef WebSocketEventCallback = void Function(WebSocketEvent event);

/// WebSocketService manages WebSocket connection for real-time updates
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(true);
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _onlineRefreshTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 100; // Практически без лимита
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _onlineRefreshInterval = Duration(hours: 12);
  StreamSubscription? _streamSubscription;
  bool _isSessionTerminated = false;
  bool _isKeepAliveEnabled = false;
  bool get isKeepAliveEnabled => _isKeepAliveEnabled;

  /// Initialize KeepAlive background service based on saved settings
  Future<void> initKeepAlive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isKeepAliveEnabled = prefs.getBool('bg_connection_enabled') ?? false;
      if (_isKeepAliveEnabled && Platform.isAndroid) {
        const channel = MethodChannel('app.theaver.messenger/push_detector');
        await channel.invokeMethod('startKeepAliveService');
      }
    } catch (_) {}
  }

  /// Enable or disable KeepAlive background service (for VPN / background connection)
  Future<void> setKeepAliveEnabled(bool enabled) async {
    _isKeepAliveEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bg_connection_enabled', enabled);
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('app.theaver.messenger/push_detector');
        if (enabled) {
          await channel.invokeMethod('startKeepAliveService');
          await channel.invokeMethod('requestIgnoreBatteryOptimizations');
        } else {
          await channel.invokeMethod('stopKeepAliveService');
        }
      } catch (e) {
        debugPrint('WebSocket: error setting KeepAlive service: $e');
      }
    }

    if (enabled) {
      if (!_isConnected && !_isConnecting) {
        tryReconnect();
      }
    }
  }

  void _setConnected(bool connected) {
    _isConnected = connected;
    if (isConnectedNotifier.value != connected) {
      isConnectedNotifier.value = connected;
    }
  }

  final StreamController<WebSocketEvent> _eventController = 
      StreamController<WebSocketEvent>.broadcast();
  Stream<WebSocketEvent> get eventStream => _eventController.stream;

  final Map<WebSocketEventType, List<WebSocketEventCallback>> _callbacks = {};

  String? _currentUserId;
  String? _activeChatId;

  /// Update current user ID (call when switching accounts)
  Future<void> updateUserId(String? userId) async {
    _isSessionTerminated = false;
    if (_currentUserId != userId) {
      debugPrint('WebSocket: Updating user ID from $_currentUserId to $userId');
      _currentUserId = userId;
      
      // If we have a new user ID, reconnect with new credentials
      if (userId != null) {
        await reconnect();
      } else {
        // If no user, disconnect
        disconnect();
      }
    }
  }

  /// Connect to WebSocket server
  Future<bool> connect() async {
    if (_isSessionTerminated) {
      debugPrint('WebSocket: Session was terminated, connect() skipped');
      return false;
    }

    if (_isConnected || _isConnecting) {
      debugPrint('WebSocket: Already connected or connecting');
      return _isConnected;
    }

    _isConnecting = true;

    try {
      // Get auth token
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('WebSocket: No auth token available');
        _isConnecting = false;
        return false;
      }

      // Get current user ID
      _currentUserId = await AuthService.getUserId();
      if (_currentUserId == null) {
        debugPrint('WebSocket: No user ID available');
        _isConnecting = false;
        return false;
      }

      // Build WebSocket URL with token AND device_id
      final accountManager = AccountManager();
      var deviceId = accountManager.currentDeviceId;
      if (deviceId == null || deviceId.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          deviceId = prefs.getString('current_device_id') ?? prefs.getString('device_id');
        } catch (_) {}
      }
      var wsUrl = '${AppConfig.wsUrl}?token=$token';
      if (deviceId != null && deviceId.isNotEmpty) {
        wsUrl += '&device_id=${Uri.encodeComponent(deviceId)}';
      }
      debugPrint('WebSocket: Connecting to $wsUrl');

      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );

      // Wait for connection
      await _channel!.ready;

      _setConnected(true);
      _isConnecting = false;
      _reconnectAttempts = 0;

      debugPrint('WebSocket: Connected successfully');

      // Start listening for messages
      _listenForMessages();

      // Start ping timer
      _startPingTimer();

      // Start online token refresh timer
      _startOnlineRefreshTimer();

      // Re-send currently open chat on this device to suppress push notifications
      if (_activeChatId != null && _activeChatId!.isNotEmpty) {
        sendActiveChat(_activeChatId);
      }

      // Trigger pending avatar upload if any
      if (_currentUserId != null) {
        AvatarSyncService().syncPendingAvatar(_currentUserId!);
      }

      // Notify connection established
      _eventController.add(WebSocketEvent(
        type: WebSocketEventType.connected,
        data: {'user_id': _currentUserId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      return true;
    } catch (e) {
      debugPrint('WebSocket: Connection error: $e');
      _setConnected(false);
      _isConnecting = false;

      final isAuthError = e.toString().contains('401') ||
          e.toString().toLowerCase().contains('unauthorized');
      if (isAuthError) {
        debugPrint('WebSocket: Authentication error (401). Attempting token refresh...');
        final refreshed = await AuthService.refreshToken();
        if (refreshed && !_isSessionTerminated) {
          debugPrint('WebSocket: Token refreshed after 401, reconnecting...');
          return await connect();
        } else {
          debugPrint('WebSocket: Token refresh failed or session expired. Logging out.');
          _isSessionTerminated = true;
          _reconnectTimer?.cancel();
          await AuthService.handleRemoteSessionTerminated(reason: 'session_expired');
          return false;
        }
      }

      if (!_isSessionTerminated) {
        _scheduleReconnect();
      }
      return false;
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    debugPrint('WebSocket: Disconnecting');
    _pingTimer?.cancel();
    _pingTimer = null;
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Cancel stream subscription to prevent leaks on reconnect
    _streamSubscription?.cancel();
    _streamSubscription = null;

    // Use 1000 (normal closure) instead of status.goingAway (1001)
    // to avoid "Invalid argument: 1001" error
    try {
      _channel?.sink.close(1000);
    } catch (_) {}
    _channel = null;
    _setConnected(false);
    _isConnecting = false;
    _currentUserId = null;
  }

  /// Reconnect to WebSocket server
  Future<void> reconnect() async {
    disconnect();
    await connect();
  }

  /// Listen for incoming messages
  void _listenForMessages() {
    // Cancel previous subscription to prevent duplicate listeners on reconnect
    _streamSubscription?.cancel();
    _streamSubscription = null;

    _streamSubscription = _channel?.stream.listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        debugPrint('WebSocket: Stream error: $error');
        _setConnected(false);
        if (!_isSessionTerminated) {
          _scheduleReconnect();
        }
      },
      onDone: () {
        debugPrint('WebSocket: Stream closed. CloseCode: ${_channel?.closeCode}');
        _setConnected(false);
        if (_channel?.closeCode == 4001 || _isSessionTerminated) {
          _isSessionTerminated = true;
          _reconnectTimer?.cancel();
          AuthService.handleRemoteSessionTerminated(reason: 'Session terminated');
        } else {
          _scheduleReconnect();
        }
      },
    );
  }

  /// Handle incoming message
  void _handleMessage(dynamic message) {
    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      final event = WebSocketEvent.fromJson(json);
      
      debugPrint('WebSocket: Received event: ${event.type}');

      if (event.type == WebSocketEventType.sessionTerminated) {
        debugPrint('WebSocket: Remote session termination received. Logging out immediately.');
        _isSessionTerminated = true;
        _reconnectTimer?.cancel();
        disconnect();
        AuthService.handleRemoteSessionTerminated(
          reason: event.data['reason']?.toString(),
        );
        return;
      }
      
      // Add to stream
      _eventController.add(event);
      
      // Call registered callbacks
      _callCallbacks(event);
    } catch (e) {
      debugPrint('WebSocket: Error parsing message: $e');
    }
  }

  /// Call registered callbacks for event type
  void _callCallbacks(WebSocketEvent event) {
    final callbacks = _callbacks[event.type];
    if (callbacks != null) {
      for (final callback in callbacks) {
        try {
          callback(event);
        } catch (e) {
          debugPrint('WebSocket: Callback error: $e');
        }
      }
    }
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WebSocket: Max reconnect attempts reached — will retry on app resume');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    
    // Cap delay at 30 seconds to avoid excessively long waits
    final delaySeconds = (_reconnectDelay.inSeconds * _reconnectAttempts).clamp(1, 30);
    final delay = Duration(seconds: delaySeconds);
    debugPrint('WebSocket: Reconnecting in ${delay.inSeconds} seconds (attempt $_reconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  /// Try to reconnect (called when app comes to foreground or needs manual reconnect)
  Future<void> tryReconnect() async {
    _reconnectAttempts = 0; // Reset attempt counter for fresh try
    if (!_isConnected && !_isConnecting) {
      await connect();
    }
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    final interval = _isKeepAliveEnabled ? const Duration(seconds: 25) : _pingInterval;
    _pingTimer = Timer.periodic(interval, (_) {
      sendPing();
    });
  }

  /// Start periodic token refresh timer while connected online
  void _startOnlineRefreshTimer() {
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = Timer.periodic(_onlineRefreshInterval, (_) {
      if (_isConnected) {
        AuthService.refreshToken();
      }
    });
    // Trigger a refresh check when starting online session
    AuthService.refreshToken();
  }

  /// Send ping message
  void sendPing() {
    if (!_isConnected || _channel == null) return;
    
    try {
      sendMessage('ping', {});
    } catch (e) {
      debugPrint('WebSocket: Error sending ping: $e');
    }
  }

  /// Send message to server
  void sendMessage(String type, Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      debugPrint('WebSocket: Cannot send message - not connected');
      return;
    }

    final message = jsonEncode({
      'type': type,
      'data': data,
    });

    _channel!.sink.add(message);
  }

  /// Send typing indicator
  void sendTypingIndicator(String chatId, {bool isTyping = true}) {
    sendMessage('typing', {
      'chat_id': chatId,
      'is_typing': isTyping,
    });
  }

  /// Send message read event
  void sendMessageRead(String chatId, {int markedCount = 0}) {
  	sendMessage('message_read', {
  		'chat_id': chatId,
  		'marked_count': markedCount,
  	});
  }
 
  /// Send message read up to event (for progressive read tracking)
  void sendMessageReadUpTo(String chatId, String messageId, {int markedCount = 0}) {
  	sendMessage('message_read_up_to', {
  		'chat_id': chatId,
  		'message_id': messageId,
  		'marked_count': markedCount,
  	});
  }

  /// Notify server about the currently open chat on this device,
  /// so that the server suppresses push notifications for this specific chat.
  void sendActiveChat(String? chatId) {
    _activeChatId = (chatId != null && chatId.isNotEmpty) ? chatId : null;
    sendMessage('active_chat', {
      'chat_id': chatId ?? '',
    });
  }

  /// Subscribe to specific event type
  void subscribe(WebSocketEventType type, WebSocketEventCallback callback) {
    _callbacks[type] ??= [];
    _callbacks[type]!.add(callback);
  }

  /// Unsubscribe from specific event type
  void unsubscribe(WebSocketEventType type, WebSocketEventCallback callback) {
    _callbacks[type]?.remove(callback);
  }

  /// Unsubscribe all callbacks for event type
  void unsubscribeAll(WebSocketEventType type) {
    _callbacks[type]?.clear();
  }

  /// Check if connected
  bool get isConnected => _isConnected;

  /// Get current user ID
  String? get currentUserId => _currentUserId;

  /// Dispose resources
  void dispose() {
    disconnect();
    _eventController.close();
    _callbacks.clear();
  }
}
