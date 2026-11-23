import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import ObjectiveC
import UserNotifications
import WebKit

private final class WebViewPullToRefreshHandler: NSObject {
  weak var webView: WKWebView?
  let refreshControl = UIRefreshControl()
  private var endTimer: Timer?
  private var loadingObserver: NSKeyValueObservation?

  init(webView: WKWebView) {
    self.webView = webView
    super.init()
    refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
    loadingObserver = webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
      if change.newValue == false {
        DispatchQueue.main.async {
          self?.stopRefreshing()
        }
      }
    }
  }

  @objc private func handleRefresh() {
    guard let wv = webView else {
      stopRefreshing()
      return
    }
    wv.reload()
    endTimer?.invalidate()
    endTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        self?.stopRefreshing()
      }
    }
  }

  func stopRefreshing() {
    endTimer?.invalidate()
    endTimer = nil
    if refreshControl.isRefreshing {
      refreshControl.endRefreshing()
    }
  }

  deinit {
    endTimer?.invalidate()
    loadingObserver?.invalidate()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private static let pullToRefreshAssocKey = UnsafeRawPointer(
    UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
  )
  private var proximityEventSink: FlutterEventSink?
  private var mediaSessionChannel: FlutterMethodChannel?
  private var remoteCommandsConfigured = false
  private var blockAllCookiesRuleList: WKContentRuleList?
  private var blockThirdPartyCookiesRuleList: WKContentRuleList?

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
      setupBrowserStorageChannel(messenger: messenger)
      setupWebViewSnapshotChannel(messenger: messenger)
      setupDisplayCutoutChannel(messenger: messenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    setupMediaMuxer(messenger: messenger)
    setupProximityAndMediaSession(messenger: messenger)
    setupNativeNotifications(messenger: messenger)
    setupBrowserStorageChannel(messenger: messenger)
    setupWebViewSnapshotChannel(messenger: messenger)
    setupDisplayCutoutChannel(messenger: messenger)
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

  private func activeKeyWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
      let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
      if let key = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first {
        return key
      }
    }
    if let appWindow = self.window {
      return appWindow
    }
    return UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first
  }

  private func collectWebViews(in view: UIView?, onlyVisible: Bool, out: inout [WKWebView]) {
    guard let view = view else { return }
    if onlyVisible && (view.isHidden || view.alpha <= 0.01 || view.bounds.width <= 0 || view.bounds.height <= 0) {
      return
    }
    if let webView = view as? WKWebView {
      out.append(webView)
      return
    }
    for subview in view.subviews {
      collectWebViews(in: subview, onlyVisible: onlyVisible, out: &out)
    }
  }

  private func findTargetWebView(targetUrl: String?) -> WKWebView? {
    guard let root = activeKeyWindow() else { return nil }
    var candidates = [WKWebView]()
    collectWebViews(in: root, onlyVisible: true, out: &candidates)
    if candidates.isEmpty { return nil }
    let query = targetUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !query.isEmpty {
      if let exact = candidates.last(where: { ($0.url?.absoluteString ?? "") == query }) {
        return exact
      }
      if let queryHost = URL(string: query)?.host?.lowercased(), !queryHost.isEmpty {
        if let hostMatch = candidates.last(where: { $0.url?.host?.lowercased() == queryHost }) {
          return hostMatch
        }
      }
    }
    var best: WKWebView?
    var bestArea: CGFloat = -1
    for wv in candidates {
      let area = wv.bounds.width * wv.bounds.height
      if area >= bestArea {
        best = wv
        bestArea = area
      }
    }
    return best
  }

  private func allMountedWebViews() -> [WKWebView] {
    var result = [WKWebView]()
    if let root = activeKeyWindow() {
      collectWebViews(in: root, onlyVisible: false, out: &result)
    }
    return result
  }

  private func applyPullToRefresh(enabled: Bool, to webView: WKWebView) {
    let existing = objc_getAssociatedObject(
      webView,
      AppDelegate.pullToRefreshAssocKey
    ) as? WebViewPullToRefreshHandler

    if enabled {
      let handler: WebViewPullToRefreshHandler
      if let existing = existing {
        handler = existing
      } else {
        handler = WebViewPullToRefreshHandler(webView: webView)
        objc_setAssociatedObject(
          webView,
          AppDelegate.pullToRefreshAssocKey,
          handler,
          .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
      }
      webView.scrollView.bounces = true
      webView.scrollView.alwaysBounceVertical = true
      if webView.scrollView.refreshControl !== handler.refreshControl {
        webView.scrollView.refreshControl = handler.refreshControl
      }
    } else if let existing = existing {
      existing.stopRefreshing()
      if webView.scrollView.refreshControl === existing.refreshControl {
        webView.scrollView.refreshControl = nil
      }
      objc_setAssociatedObject(
        webView,
        AppDelegate.pullToRefreshAssocKey,
        nil,
        .OBJC_ASSOCIATION_ASSIGN
      )
    }
  }

  private func setupWebViewSnapshotChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.theaver.messenger/webview_snapshot",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "captureWebView":
        let urlArg = args?["url"] as? String
        let rawMaxWidth = (args?["maxWidth"] as? NSNumber)?.intValue ?? 960
        let maxWidth = min(max(rawMaxWidth, 120), 1080)
        let rawQuality = (args?["quality"] as? NSNumber)?.intValue ?? 86
        let quality = min(max(rawQuality, 20), 95)
        let topCropDp = max((args?["topCropDp"] as? NSNumber)?.doubleValue ?? 0.0, 0.0)
        DispatchQueue.main.async {
          guard let webView = self.findTargetWebView(targetUrl: urlArg),
                webView.bounds.width > 0,
                webView.bounds.height > 0 else {
            result(nil)
            return
          }
          let config = WKSnapshotConfiguration()
          config.afterScreenUpdates = false
          let rawTopCrop = CGFloat(topCropDp)
          let effectiveTopCrop = min(
            max(rawTopCrop - max(webView.scrollView.contentOffset.y, 0), 0),
            webView.bounds.height * 0.35
          )
          if effectiveTopCrop > 0 && webView.bounds.height > 1 {
            config.rect = CGRect(
              x: 0,
              y: effectiveTopCrop,
              width: webView.bounds.width,
              height: max(1, webView.bounds.height - effectiveTopCrop)
            )
          }
          let targetWidth = min(CGFloat(maxWidth), webView.bounds.width)
          if targetWidth > 0 {
            config.snapshotWidth = NSNumber(value: Double(targetWidth))
          }
          webView.takeSnapshot(with: config) { image, _ in
            guard let image = image else {
              result(nil)
              return
            }
            DispatchQueue.global(qos: .userInitiated).async {
              let jpegData = image.jpegData(compressionQuality: CGFloat(quality) / 100.0)
              DispatchQueue.main.async {
                if let data = jpegData, !data.isEmpty {
                  result(FlutterStandardTypedData(bytes: data))
                } else {
                  result(nil)
                }
              }
            }
          }
        }

      case "setWebViewInteractionLocked":
        let urlArg = args?["url"] as? String
        let locked = (args?["locked"] as? Bool) ?? false
        DispatchQueue.main.async {
          if let webView = self.findTargetWebView(targetUrl: urlArg) {
            let scrollView = webView.scrollView
            if locked {
              scrollView.setContentOffset(scrollView.contentOffset, animated: false)
              scrollView.isScrollEnabled = false
            } else {
              scrollView.isScrollEnabled = true
              scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            }
          }
          result(true)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupBrowserStorageChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.theaver.messenger/browser_storage",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      let dataStore = WKWebsiteDataStore.default()
      let cookieStore = dataStore.httpCookieStore

      switch call.method {
      case "flushCookies":
        result(true)

      case "configureWebViewPolicies":
        let args = call.arguments as? [String: Any]
        let urlArg = args?["url"] as? String
        let blockAllCookies = (args?["blockAllCookies"] as? Bool) ?? false
        let acceptThirdPartyCookies = (args?["acceptThirdPartyCookies"] as? Bool) ?? true
        let enablePullToRefresh = (args?["enablePullToRefresh"] as? Bool) ?? false
        DispatchQueue.main.async {
          guard let self = self else {
            result(true)
            return
          }
          let webViews = self.allMountedWebViews()
          let ptrTargets: [WKWebView]
          if let targetWv = self.findTargetWebView(targetUrl: urlArg) {
            ptrTargets = [targetWv]
          } else {
            ptrTargets = webViews
          }
          for wv in ptrTargets {
            self.applyPullToRefresh(enabled: enablePullToRefresh, to: wv)
          }
          let ruleStore: WKContentRuleListStore? = WKContentRuleListStore.default()
          let blockAllId = "theaver_block_cookies"
          let blockThirdPartyId = "theaver_block_third_party_cookies"
          let group = DispatchGroup()

          if blockAllCookies {
            let ruleJson = "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block-cookies\"}}]"
            if let store = ruleStore {
              group.enter()
              store.compileContentRuleList(
                forIdentifier: blockAllId,
                encodedContentRuleList: ruleJson
              ) { ruleList, _ in
                DispatchQueue.main.async {
                  if let prev = self.blockAllCookiesRuleList {
                    for wv in webViews {
                      wv.configuration.userContentController.remove(prev)
                    }
                  }
                  self.blockAllCookiesRuleList = ruleList
                  if let ruleList = ruleList {
                    for wv in webViews {
                      wv.configuration.userContentController.add(ruleList)
                    }
                  }
                  group.leave()
                }
              }
            }
          } else {
            if let prev = self.blockAllCookiesRuleList {
              for wv in webViews {
                wv.configuration.userContentController.remove(prev)
              }
              self.blockAllCookiesRuleList = nil
            }
            if let store = ruleStore {
              group.enter()
              store.lookUpContentRuleList(forIdentifier: blockAllId) { existing, _ in
                DispatchQueue.main.async {
                  if let existing = existing {
                    for wv in webViews {
                      wv.configuration.userContentController.remove(existing)
                    }
                  }
                  store.removeContentRuleList(forIdentifier: blockAllId) { _ in
                    group.leave()
                  }
                }
              }
            }
          }

          if !blockAllCookies && !acceptThirdPartyCookies {
            let thirdPartyJson = "[{\"trigger\":{\"url-filter\":\".*\",\"load-type\":[\"third-party\"]},\"action\":{\"type\":\"block-cookies\"}}]"
            if let store = ruleStore {
              group.enter()
              store.compileContentRuleList(
                forIdentifier: blockThirdPartyId,
                encodedContentRuleList: thirdPartyJson
              ) { ruleList, _ in
                DispatchQueue.main.async {
                  if let prev = self.blockThirdPartyCookiesRuleList {
                    for wv in webViews {
                      wv.configuration.userContentController.remove(prev)
                    }
                  }
                  self.blockThirdPartyCookiesRuleList = ruleList
                  if let ruleList = ruleList {
                    for wv in webViews {
                      wv.configuration.userContentController.add(ruleList)
                    }
                  }
                  group.leave()
                }
              }
            }
          } else {
            if let prev = self.blockThirdPartyCookiesRuleList {
              for wv in webViews {
                wv.configuration.userContentController.remove(prev)
              }
              self.blockThirdPartyCookiesRuleList = nil
            }
            if let store = ruleStore {
              group.enter()
              store.lookUpContentRuleList(forIdentifier: blockThirdPartyId) { existing, _ in
                DispatchQueue.main.async {
                  if let existing = existing {
                    for wv in webViews {
                      wv.configuration.userContentController.remove(existing)
                    }
                  }
                  store.removeContentRuleList(forIdentifier: blockThirdPartyId) { _ in
                    group.leave()
                  }
                }
              }
            }
          }

          group.notify(queue: .main) {
            result(true)
          }
        }

      case "exportAllCookies":
        cookieStore.getAllCookies { cookies in
          let mapped: [[String: Any]] = cookies.map { cookie in
            let expiresMs = cookie.expiresDate != nil
              ? Int64((cookie.expiresDate!.timeIntervalSince1970 * 1000.0).rounded())
              : 0
            let sameSiteVal: Int
            if #available(iOS 13.0, *), let policy = cookie.sameSitePolicy {
              switch policy {
              case .lax:
                sameSiteVal = 1
              case .strict:
                sameSiteVal = 2
              default:
                sameSiteVal = -1
              }
            } else {
              sameSiteVal = -1
            }
            return [
              "hostKey": cookie.domain,
              "name": cookie.name,
              "value": cookie.value,
              "path": cookie.path.isEmpty ? "/" : cookie.path,
              "expiresEpochMs": expiresMs,
              "isSecure": cookie.isSecure,
              "isHttpOnly": cookie.isHTTPOnly,
              "sameSite": sameSiteVal,
            ]
          }
          result(mapped)
        }

      case "importCookies":
        let args = call.arguments as? [String: Any]
        let rawList = args?["cookies"] as? [[String: Any]] ?? []
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let group = DispatchGroup()
        for item in rawList {
          guard let domain = item["hostKey"] as? String,
                !domain.isEmpty,
                let name = item["name"] as? String,
                !name.isEmpty,
                let value = item["value"] as? String else {
            continue
          }
          let expiresMs = (item["expiresEpochMs"] as? NSNumber)?.int64Value ?? 0
          if expiresMs > 0 && expiresMs < nowMs {
            continue
          }
          let path = (item["path"] as? String)?.isEmpty == false ? (item["path"] as! String) : "/"
          let isSecure = (item["isSecure"] as? Bool) ?? false
          let isHttpOnly = (item["isHttpOnly"] as? Bool) ?? false
          var props: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .name: name,
            .value: value,
            .path: path,
          ]
          if isSecure {
            props[.secure] = "TRUE"
          }
          if isHttpOnly {
            props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
          }
          if expiresMs > 0 {
            props[.expires] = Date(timeIntervalSince1970: Double(expiresMs) / 1000.0)
          }
          if #available(iOS 13.0, *), let sameSite = (item["sameSite"] as? NSNumber)?.intValue {
            if sameSite == 1 {
              props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
            } else if sameSite == 2 {
              props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
            }
          }
          if let cookie = HTTPCookie(properties: props) {
            group.enter()
            cookieStore.setCookie(cookie) {
              group.leave()
            }
          }
        }
        group.notify(queue: .main) {
          result(true)
        }

      case "clearSiteData":
        let args = call.arguments as? [String: Any]
        let originUrl = (args?["originUrl"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: originUrl),
              let cleanHost = url.host?.lowercased() else {
          result(false)
          return
        }
        let hostNoDot = cleanHost.hasPrefix(".") ? String(cleanHost.dropFirst()) : cleanHost
        let group = DispatchGroup()

        group.enter()
        cookieStore.getAllCookies { cookies in
          let innerGroup = DispatchGroup()
          for cookie in cookies {
            let domain = cookie.domain.lowercased()
            let domNoDot = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let matches = domNoDot == hostNoDot ||
              domNoDot.hasSuffix("." + hostNoDot) ||
              (domain.hasPrefix(".") && hostNoDot.hasSuffix(domain))
            if matches {
              innerGroup.enter()
              cookieStore.delete(cookie) {
                innerGroup.leave()
              }
            }
          }
          innerGroup.notify(queue: .main) {
            group.leave()
          }
        }

        group.enter()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { records in
          let matching = records.filter { rec in
            let name = rec.displayName.lowercased()
            return name == hostNoDot || hostNoDot.hasSuffix("." + name) || name.hasSuffix("." + hostNoDot)
          }
          if matching.isEmpty {
            group.leave()
          } else {
            dataStore.removeData(ofTypes: types, for: matching) {
              group.leave()
            }
          }
        }

        group.notify(queue: .main) {
          result(true)
        }

      case "clearAllWebData":
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
          let storage = URLCredentialStorage.shared
          for (space, creds) in storage.allCredentials {
            for (_, cred) in creds {
              storage.remove(cred, for: space)
            }
          }
          result(true)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func currentMachineModelIdentifier() -> String {
    #if targetEnvironment(simulator)
    if let simId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simId.isEmpty {
      return simId
    }
    #endif
    var systemInfo = utsname()
    guard uname(&systemInfo) == 0 else { return "" }
    return withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(validatingUTF8: $0) ?? ""
      }
    }
  }

  private func setupDisplayCutoutChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.theaver.messenger/display_cutout",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard call.method == "getDisplayCutout" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
          result(["hasCutout": false])
          return
        }
        let activeWindow: UIWindow? = self?.window ?? UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first { $0.isKeyWindow }
        let bounds = activeWindow?.bounds ?? UIScreen.main.bounds
        let screenW = Double(bounds.width)
        let screenH = Double(bounds.height)
        guard screenW > 0, screenH > 0, screenW <= screenH else {
          result(["hasCutout": false])
          return
        }
        let safeTop = Double(activeWindow?.safeAreaInsets.top ?? 0.0)
        guard safeTop >= 38.0 else {
          result(["hasCutout": false])
          return
        }

        let model = Self.currentMachineModelIdentifier()
        var kind = ""
        var baseWidth = 0.0
        var baseHeight = 0.0
        var baseTop = 0.0
        var standardScreenWidth = screenW

        switch model {
        // Classic Top Notch (iPhone X -> iPhone 14 / 16e)
        case "iPhone10,3", "iPhone10,6", "iPhone11,2", "iPhone12,3":
          kind = "topNotch"; baseWidth = 223.0; baseHeight = 30.0; baseTop = 0.0; standardScreenWidth = 375.0
        case "iPhone11,4", "iPhone11,6", "iPhone12,5":
          kind = "topNotch"; baseWidth = 223.0; baseHeight = 30.0; baseTop = 0.0; standardScreenWidth = 414.0
        case "iPhone11,8", "iPhone12,1":
          kind = "topNotch"; baseWidth = 246.0; baseHeight = 33.0; baseTop = 0.0; standardScreenWidth = 414.0
        case "iPhone13,1":
          kind = "topNotch"; baseWidth = 242.0; baseHeight = 34.0; baseTop = 0.0; standardScreenWidth = 375.0
        case "iPhone13,2", "iPhone13,3":
          kind = "topNotch"; baseWidth = 222.0; baseHeight = 32.0; baseTop = 0.0; standardScreenWidth = 390.0
        case "iPhone13,4":
          kind = "topNotch"; baseWidth = 222.0; baseHeight = 32.0; baseTop = 0.0; standardScreenWidth = 428.0
        case "iPhone14,4":
          kind = "topNotch"; baseWidth = 189.0; baseHeight = 38.0; baseTop = 0.0; standardScreenWidth = 375.0
        case "iPhone14,5", "iPhone14,2", "iPhone14,7", "iPhone17,5":
          kind = "topNotch"; baseWidth = 176.0; baseHeight = 34.0; baseTop = 0.0; standardScreenWidth = 390.0
        case "iPhone14,3", "iPhone14,8":
          kind = "topNotch"; baseWidth = 176.0; baseHeight = 34.0; baseTop = 0.0; standardScreenWidth = 428.0

        // Dynamic Island (iPhone 14 Pro, 15/15 Pro, 16/16 Plus)
        case "iPhone15,2", "iPhone15,4", "iPhone16,1", "iPhone17,3":
          kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 11.0; standardScreenWidth = 393.0
        case "iPhone15,3", "iPhone15,5", "iPhone16,2", "iPhone17,4":
          kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 11.0; standardScreenWidth = 430.0

        // Dynamic Island (iPhone 16 Pro / Pro Max & newer Pro generations)
        case "iPhone17,1", "iPhone18,1", "iPhone19,1":
          kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 41.0 / 3.0; standardScreenWidth = 402.0
        case "iPhone17,2", "iPhone18,2", "iPhone19,2":
          kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 41.0 / 3.0; standardScreenWidth = 440.0

        default:
          if safeTop >= 65.0 {
            kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 59.0 / 3.0
          } else if safeTop >= 58.0 {
            kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 41.0 / 3.0
          } else if safeTop >= 50.0 || (safeTop >= 46.5 && screenW == 375.0) {
            kind = "dynamicIsland"; baseWidth = 126.0; baseHeight = 112.0 / 3.0; baseTop = 11.0
          } else if safeTop >= 43.0 {
            kind = "topNotch"; baseWidth = 176.0; baseHeight = 34.0; baseTop = 0.0
          } else {
            result(["hasCutout": false])
            return
          }
        }

        let zoomFactor = (standardScreenWidth > 0 && screenW < standardScreenWidth - 1.0)
          ? (screenW / standardScreenWidth)
          : 1.0
        let finalWidth = baseWidth * zoomFactor
        let finalHeight = baseHeight * zoomFactor
        let finalTop = baseTop * zoomFactor
        let finalLeft = (screenW - finalWidth) * 0.5
        let radius = kind == "dynamicIsland" ? finalHeight * 0.5 : 16.0 * zoomFactor

        result([
          "hasCutout": true,
          "kind": kind,
          "gravity": "center",
          "left": finalLeft,
          "top": finalTop,
          "width": finalWidth,
          "height": finalHeight,
          "cornerRadius": radius,
          "isOval": kind == "dynamicIsland"
        ])
      }
    }
  }
}
