import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private var proximityEventSink: FlutterEventSink?
  private var mediaSessionChannel: FlutterMethodChannel?
  private var remoteCommandsConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // AppDelegate (FlutterAppDelegate) is the notification center delegate: it handles
    // the native "reply"/"mark_read" actions of remote chat pushes and forwards
    // everything else to the plugins (firebase_messaging, flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self
    registerNotificationCategories()

    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
      setupMediaMuxer(messenger: messenger)
      setupProximityAndMediaSession(messenger: messenger)
      setupNativeNotifications(messenger: messenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    setupMediaMuxer(messenger: messenger)
    setupProximityAndMediaSession(messenger: messenger)
    setupNativeNotifications(messenger: messenger)
  }

  private func setupProximityAndMediaSession(messenger: FlutterBinaryMessenger) {
    let proximityChannel = FlutterMethodChannel(name: "app.theaver.messenger/proximity", binaryMessenger: messenger)
    proximityChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "startMonitoring":
        DispatchQueue.main.async {
          UIDevice.current.isProximityMonitoringEnabled = true
          result(UIDevice.current.isProximityMonitoringEnabled)
        }
      case "stopMonitoring":
        DispatchQueue.main.async {
          UIDevice.current.isProximityMonitoringEnabled = false
          result(true)
        }
      case "setEarpieceMode":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? false
        let session = AVAudioSession.sharedInstance()
        do {
          if enabled {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
          } else {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.overrideOutputAudioPort(.none)
          }
          try session.setActive(true)
          result(true)
        } catch {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(name: "app.theaver.messenger/proximity_events", binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)

    let mediaChannel = FlutterMethodChannel(name: "app.theaver.messenger/media_session", binaryMessenger: messenger)
    self.mediaSessionChannel = mediaChannel
    mediaChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "updateMetadata":
        guard let args = call.arguments as? [String: Any] else {
          result(false)
          return
        }
        self.configureRemoteCommandsIfNeeded()
        let title = args["title"] as? String ?? "Voice Message"
        let artist = args["artist"] as? String ?? "Theaver"
        let durationMs = args["durationMs"] as? Int ?? 0
        let positionMs = args["positionMs"] as? Int ?? 0
        let isPlaying = args["isPlaying"] as? Bool ?? false
        let speed = args["speed"] as? Double ?? 1.0

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        result(true)
      case "clearSession":
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureRemoteCommandsIfNeeded() {
    guard !remoteCommandsConfigured else { return }
    remoteCommandsConfigured = true
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.mediaSessionChannel?.invokeMethod("onPlay", arguments: nil)
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.mediaSessionChannel?.invokeMethod("onPause", arguments: nil)
      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.mediaSessionChannel?.invokeMethod("onTogglePlayPause", arguments: nil)
      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.mediaSessionChannel?.invokeMethod("onNext", arguments: nil)
      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let posMs = Int(posEvent.positionTime * 1000.0)
      self?.mediaSessionChannel?.invokeMethod("onSeek", arguments: ["positionMs": posMs])
      return .success
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.proximityEventSink = events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(proximityStateDidChange),
      name: UIDevice.proximityStateDidChangeNotification,
      object: nil
    )
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(
      self,
      name: UIDevice.proximityStateDidChangeNotification,
      object: nil
    )
    self.proximityEventSink = nil
    return nil
  }

  @objc private func proximityStateDidChange() {
    let isNear = UIDevice.current.proximityState
    proximityEventSink?(isNear)
  }

  // MARK: - Native notifications (chat pushes)

  /// Shared with the NotificationService extension (keep in sync with NotificationService.swift).
  private enum NativeNotifications {
    static let channelName = "app.theaver.messenger/native_notifications"
    static let appGroupId = "group.app.theaver.messenger"
    static let baseUrlKey = "notif_base_url"
    static let storageUrlKey = "notif_storage_url"
    static let authTokenKey = "notif_auth_token"
    static let userIdKey = "notif_user_id"

    static let messageCategory = "message"
    static let callCategory = "incoming_call"
    static let replyAction = "reply"
    static let markReadAction = "mark_read"

    static var defaults: UserDefaults? {
      return UserDefaults(suiteName: appGroupId)
    }

    /// Non-empty string from a push / channel value (String or NSNumber).
    static func string(_ raw: Any?) -> String? {
      var value: String?
      if let s = raw as? String {
        value = s
      } else if let n = raw as? NSNumber {
        value = n.stringValue
      }
      guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty,
            trimmed != "null" else {
        return nil
      }
      return trimmed
    }

    /// API base URL without a trailing "/" or "/api".
    static func apiBase() -> String? {
      guard var base = defaults?.string(forKey: baseUrlKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !base.isEmpty else {
        return nil
      }
      while base.hasSuffix("/") {
        base.removeLast()
      }
      if base.lowercased().hasSuffix("/api") {
        base.removeLast(4)
      }
      return base.isEmpty ? nil : base
    }

    static func authToken() -> String? {
      guard let token = defaults?.string(forKey: authTokenKey), !token.isEmpty else {
        return nil
      }
      return token
    }
  }

  /// Message (reply / read) and call (accept / decline) categories. Merged with the
  /// categories already registered (flutter_local_notifications registers the same ids;
  /// ours win, the definitions are identical).
  private func registerNotificationCategories() {
    let reply = UNTextInputNotificationAction(
      identifier: NativeNotifications.replyAction,
      title: "Ответить",
      options: [],
      textInputButtonTitle: "Отправить",
      textInputPlaceholder: "Сообщение"
    )
    // No .foreground option: handled in the background, the app is not opened.
    let markRead = UNNotificationAction(
      identifier: NativeNotifications.markReadAction,
      title: "Прочитано",
      options: []
    )
    let messageCategory = UNNotificationCategory(
      identifier: NativeNotifications.messageCategory,
      actions: [reply, markRead],
      intentIdentifiers: [],
      options: []
    )

    let accept = UNNotificationAction(identifier: "accept_call", title: "Принять", options: [.foreground])
    let decline = UNNotificationAction(identifier: "decline_call", title: "Отклонить", options: [.destructive])
    let callCategory = UNNotificationCategory(
      identifier: NativeNotifications.callCategory,
      actions: [accept, decline],
      intentIdentifiers: [],
      options: []
    )

    let ours: Set<UNNotificationCategory> = [messageCategory, callCategory]
    let ourIds = Set(ours.map { $0.identifier })
    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { existing in
      let merged = existing.filter { !ourIds.contains($0.identifier) }.union(ours)
      center.setNotificationCategories(merged)
    }
  }

  private func setupNativeNotifications(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: NativeNotifications.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { (call, result) in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "configure":
        if let defaults = NativeNotifications.defaults, let args = args {
          let mapping: [(String, String)] = [
            ("base_url", NativeNotifications.baseUrlKey),
            ("storage_url", NativeNotifications.storageUrlKey),
            ("token", NativeNotifications.authTokenKey),
            ("user_id", NativeNotifications.userIdKey),
          ]
          for (argKey, defaultsKey) in mapping {
            guard args.keys.contains(argKey) else { continue }
            if let value = NativeNotifications.string(args[argKey]) {
              defaults.set(value, forKey: defaultsKey)
            } else {
              // Empty / null value (e.g. token on logout) => remove.
              defaults.removeObject(forKey: defaultsKey)
            }
          }
        }
        result(nil)
      case "cancelChat":
        if let chatId = NativeNotifications.string(args?["chat_id"]) {
          AppDelegate.removeDeliveredChatNotifications(chatId: chatId, completion: nil)
        }
        result(nil)
      case "cancelAll":
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(nil)
      default:
        // setState, showChatNotification, getInitialTap, ...: no-op on iOS
        // (pushes are rendered by the NotificationService extension).
        result(nil)
      }
    }
  }

  /// Removes delivered notifications of a chat (thread "chat_<id>" or userInfo chat_id).
  private static func removeDeliveredChatNotifications(chatId: String, completion: (() -> Void)?) {
    let threadId = "chat_\(chatId)"
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notifications in
      let ids = notifications.filter { notification in
        let content = notification.request.content
        if content.threadIdentifier == threadId {
          return true
        }
        return NativeNotifications.string(content.userInfo["chat_id"]) == chatId
      }.map { $0.request.identifier }
      if !ids.isEmpty {
        center.removeDeliveredNotifications(withIdentifiers: ids)
      }
      completion?()
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let action = response.actionIdentifier
    let request = response.notification.request
    if action == NativeNotifications.replyAction || action == NativeNotifications.markReadAction,
       request.trigger is UNPushNotificationTrigger,
       let chatId = NativeNotifications.string(request.content.userInfo["chat_id"]) {
      let text = (response as? UNTextInputNotificationResponse)?.userText
      handleNativeChatAction(action: action, chatId: chatId, text: text, completionHandler: completionHandler)
      return
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  /// Sends the reply and/or marks the chat as read directly via the REST API, so the
  /// actions work even when the app was killed (iOS launches it in the background).
  private func handleNativeChatAction(
    action: String,
    chatId: String,
    text: String?,
    completionHandler: @escaping () -> Void
  ) {
    let lock = NSLock()
    var finished = false
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func finish() {
      lock.lock()
      if finished {
        lock.unlock()
        return
      }
      finished = true
      lock.unlock()
      DispatchQueue.main.async {
        completionHandler()
        if backgroundTask != .invalid {
          UIApplication.shared.endBackgroundTask(backgroundTask)
          backgroundTask = .invalid
        }
      }
    }

    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "theaver.notification_action") {
      finish()
    }

    guard let base = NativeNotifications.apiBase(),
          let token = NativeNotifications.authToken(),
          let encodedChatId = chatId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let messagesUrl = URL(string: "\(base)/api/chats/\(encodedChatId)/messages"),
          let readUrl = URL(string: "\(base)/api/chats/\(encodedChatId)/messages/read") else {
      finish()
      return
    }

    let markRead: (@escaping () -> Void) -> Void = { done in
      AppDelegate.postJSON(url: readUrl, token: token, body: [:]) { _ in
        AppDelegate.removeDeliveredChatNotifications(chatId: chatId) {
          done()
        }
      }
    }

    if action == NativeNotifications.markReadAction {
      markRead { finish() }
      return
    }

    // Reply.
    guard let message = text?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
      finish()
      return
    }
    let body: [String: Any] = [
      "content": message,
      "message_type": "text",
      "local_id": UUID().uuidString.lowercased(),
    ]
    AppDelegate.postJSON(url: messagesUrl, token: token, body: body) { success in
      if success {
        markRead { finish() }
      } else {
        AppDelegate.showReplyFailedNotification(chatId: chatId) { finish() }
      }
    }
  }

  private static func postJSON(
    url: URL,
    token: String,
    body: [String: Any],
    completion: @escaping (Bool) -> Void
  ) {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
    URLSession.shared.dataTask(with: request) { _, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      completion(error == nil && (200..<300).contains(status))
    }.resume()
  }

  /// Local notification shown when a background reply could not be sent.
  private static func showReplyFailedNotification(chatId: String, completion: @escaping () -> Void) {
    let content = UNMutableNotificationContent()
    content.title = "Theaver"
    content.body = "Не удалось отправить сообщение. Откройте чат, чтобы повторить."
    content.threadIdentifier = "chat_\(chatId)"
    content.userInfo = ["type": "new_message", "chat_id": chatId]
    let request = UNNotificationRequest(
      identifier: "reply_failed_\(chatId)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { _ in
      completion()
    }
  }

  private func setupMediaMuxer(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.example.app/media_muxer", binaryMessenger: messenger)
    channel.setMethodCallHandler { (call, result) in
      if call.method == "mux" {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let audioPath = args["audioPath"] as? String,
              let outputPath = args["outputPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing paths", details: nil))
          return
        }
        self.muxVideoAndAudio(videoPath: videoPath, audioPath: audioPath, outputPath: outputPath) { success, error in
          if success {
            result(true)
          } else {
            result(FlutterError(code: "MUX_ERROR", message: error?.localizedDescription ?? "Muxing failed", details: nil))
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func muxVideoAndAudio(videoPath: String, audioPath: String, outputPath: String, completion: @escaping (Bool, Error?) -> Void) {
    let composition = AVMutableComposition()
    let videoURL = URL(fileURLWithPath: videoPath)
    let audioURL = URL(fileURLWithPath: audioPath)
    let videoAsset = AVURLAsset(url: videoURL)
    let audioAsset = AVURLAsset(url: audioURL)

    guard let videoTrack = videoAsset.tracks(withMediaType: .video).first,
          let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      completion(false, NSError(domain: "MediaMuxer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video track not found"]))
      return
    }

    do {
      let videoDuration = videoAsset.duration
      try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
      compositionVideoTrack.preferredTransform = videoTrack.preferredTransform

      if let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
         let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        let audioDuration = min(videoDuration, audioAsset.duration)
        try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: audioTrack, at: .zero)
      }

      let outputURL = URL(fileURLWithPath: outputPath)
      if FileManager.default.fileExists(atPath: outputPath) {
        try? FileManager.default.removeItem(at: outputURL)
      }

      guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
        completion(false, NSError(domain: "MediaMuxer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
        return
      }

      exportSession.outputURL = outputURL
      exportSession.outputFileType = .mp4
      exportSession.shouldOptimizeForNetworkUse = true
      exportSession.exportAsynchronously {
        DispatchQueue.main.async {
          if exportSession.status == .completed {
            completion(true, nil)
          } else {
            completion(false, exportSession.error)
          }
        }
      }
    } catch {
      completion(false, error)
    }
  }
}
