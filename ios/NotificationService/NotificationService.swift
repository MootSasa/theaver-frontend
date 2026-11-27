import ImageIO
import Intents
import UIKit
import UserNotifications

/// Notification Service Extension for chat pushes.
///
/// Turns `new_message` pushes into Communication Notifications (iOS 15+): the
/// notification shows the sender / chat avatar, is grouped per chat
/// (`thread-id = chat_<id>`) and keeps the `message` category with the
/// "Ответить" / "Прочитано" actions (handled natively in `AppDelegate`).
///
/// Base URLs and the auth token are written by the Flutter app (MethodChannel
/// `app.theaver.messenger/native_notifications`) into the shared App Group
/// `UserDefaults`, so the extension can resolve relative avatar URLs.
class NotificationService: UNNotificationServiceExtension {

  // MARK: - Shared configuration (keep in sync with AppDelegate.swift)

  private enum Shared {
    static let appGroupId = "group.app.theaver.messenger"
    static let baseUrlKey = "notif_base_url"
    static let storageUrlKey = "notif_storage_url"
    static let authTokenKey = "notif_auth_token"
    static let userIdKey = "notif_user_id"
    static let messageCategory = "message"
  }

  private static let avatarTimeout: TimeInterval = 5
  private static let avatarMaxPixelSize = 256

  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?
  private var delivered = false
  private let deliverLock = NSLock()
  private var session: URLSession?

  // MARK: - UNNotificationServiceExtension

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler

    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      deliver(request.content)
      return
    }
    bestAttemptContent = content

    let userInfo = request.content.userInfo
    guard NotificationService.string(userInfo, "type") == "new_message",
          let chatId = NotificationService.string(userInfo, "chat_id") else {
      deliver(content)
      return
    }

    // Grouping per chat + reply/read actions.
    if content.threadIdentifier.isEmpty {
      content.threadIdentifier = "chat_\(chatId)"
    }
    if content.categoryIdentifier.isEmpty {
      content.categoryIdentifier = Shared.messageCategory
    }

    guard #available(iOS 15.0, *) else {
      deliver(content)
      return
    }

    let chatType = (NotificationService.string(userInfo, "chat_type") ?? "private").lowercased()
    let isChannel = chatType == "channel"
    let isGroup = !isChannel && (chatType == "group" || NotificationService.string(userInfo, "is_group")?.lowercased() == "true")
    let chatName = NotificationService.string(userInfo, "chat_name")
    let senderId = NotificationService.string(userInfo, "sender_id")
    let senderName = NotificationService.string(userInfo, "sender_name")

    // Group bodies are formatted by the backend as "Sender: text" (for devices without
    // the extension). The Communication Notification already shows the sender name,
    // so strip the prefix to avoid showing it twice.
    if isGroup, let name = senderName {
      let prefix = name + ": "
      if content.body.hasPrefix(prefix) {
        let stripped = String(content.body.dropFirst(prefix.count))
        if !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          content.body = stripped
        }
      }
    }

    let text = NotificationService.string(userInfo, "message_text") ?? (content.body.isEmpty ? nil : content.body)

    // Who is shown as the "person" of the notification.
    let personName: String
    let personKey: String
    let personAvatarUrl: String?
    let groupAvatarUrl: String?
    if isGroup {
      personName = senderName ?? (content.title.isEmpty ? (chatName ?? "Theaver") : content.title)
      personKey = senderId ?? personName
      personAvatarUrl = NotificationService.string(userInfo, "sender_avatar_url")
      groupAvatarUrl = NotificationService.string(userInfo, "avatar_url")
    } else if isChannel {
      // Channel posts are shown as coming from the channel itself.
      personName = chatName ?? senderName ?? (content.title.isEmpty ? "Theaver" : content.title)
      personKey = "chat_\(chatId)"
      personAvatarUrl = NotificationService.string(userInfo, "avatar_url")
      groupAvatarUrl = nil
    } else {
      personName = senderName ?? chatName ?? (content.title.isEmpty ? "Theaver" : content.title)
      personKey = senderId ?? "chat_\(chatId)"
      personAvatarUrl = NotificationService.string(userInfo, "avatar_url") ?? NotificationService.string(userInfo, "sender_avatar_url")
      groupAvatarUrl = nil
    }

    let group = DispatchGroup()
    var personImageData: Data?
    var groupImageData: Data?

    if let url = resolveUrl(personAvatarUrl) {
      group.enter()
      downloadImage(url) { data in
        personImageData = data
        group.leave()
      }
    }
    if isGroup, let url = resolveUrl(groupAvatarUrl) {
      group.enter()
      downloadImage(url) { data in
        groupImageData = data
        group.leave()
      }
    }

    group.notify(queue: .global(qos: .userInitiated)) { [self] in
      let avatarData = personImageData ?? NotificationService.initialsImageData(name: personName, key: personKey)
      self.applyCommunicationIntent(
        to: content,
        chatId: chatId,
        isGroup: isGroup,
        chatName: chatName,
        personName: personName,
        personKey: personKey,
        personImageData: avatarData,
        groupImageData: groupImageData,
        text: text
      )
    }
  }

  override func serviceExtensionTimeWillExpire() {
    session?.invalidateAndCancel()
    if let content = bestAttemptContent {
      deliver(content)
    } else {
      deliver(UNNotificationContent())
    }
  }

  // MARK: - Communication Notification

  @available(iOS 15.0, *)
  private func applyCommunicationIntent(
    to content: UNMutableNotificationContent,
    chatId: String,
    isGroup: Bool,
    chatName: String?,
    personName: String,
    personKey: String,
    personImageData: Data?,
    groupImageData: Data?,
    text: String?
  ) {
    let senderImage = personImageData.map { INImage(imageData: $0) }
    let sender = INPerson(
      personHandle: INPersonHandle(value: personKey, type: .unknown),
      nameComponents: nil,
      displayName: personName,
      image: senderImage,
      contactIdentifier: nil,
      customIdentifier: personKey,
      isMe: false,
      suggestionType: .none
    )

    var recipients: [INPerson]?
    var speakableGroupName: INSpeakableString?
    if isGroup {
      let userId = UserDefaults(suiteName: Shared.appGroupId)?.string(forKey: Shared.userIdKey) ?? "me"
      let me = INPerson(
        personHandle: INPersonHandle(value: userId, type: .unknown),
        nameComponents: nil,
        displayName: nil,
        image: nil,
        contactIdentifier: nil,
        customIdentifier: userId,
        isMe: true,
        suggestionType: .none
      )
      // More than one recipient + a group name => group conversation.
      recipients = [me, sender]
      speakableGroupName = INSpeakableString(spokenPhrase: chatName ?? "Theaver")
    }

    let intent = INSendMessageIntent(
      recipients: recipients,
      outgoingMessageType: .outgoingMessageText,
      content: text,
      speakableGroupName: speakableGroupName,
      conversationIdentifier: chatId,
      serviceName: nil,
      sender: sender,
      attachments: nil
    )
    if isGroup, let groupData = groupImageData {
      intent.setImage(INImage(imageData: groupData), forParameterNamed: \.speakableGroupName)
    }

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    interaction.donate { [self] _ in
      // The donation result does not matter: updating(from:) is what turns
      // the push into a Communication Notification.
      do {
        let updated = try content.updating(from: intent)
        self.deliver(updated)
      } catch {
        self.deliver(content)
      }
    }
  }

  // MARK: - Delivery

  /// Calls the content handler exactly once.
  private func deliver(_ content: UNNotificationContent) {
    deliverLock.lock()
    if delivered {
      deliverLock.unlock()
      return
    }
    delivered = true
    let handler = contentHandler
    contentHandler = nil
    deliverLock.unlock()
    handler?(content)
  }

  // MARK: - Avatars

  private func makeSession() -> URLSession {
    if let existing = session {
      return existing
    }
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = NotificationService.avatarTimeout
    config.timeoutIntervalForResource = NotificationService.avatarTimeout + 1
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    let created = URLSession(configuration: config)
    session = created
    return created
  }

  private func downloadImage(_ url: URL, completion: @escaping (Data?) -> Void) {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: NotificationService.avatarTimeout)
    if let token = sharedDefaults?.string(forKey: Shared.authTokenKey), !token.isEmpty,
       isOwnHost(url) {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let task = makeSession().dataTask(with: request) { data, response, error in
      guard error == nil,
            let data = data, !data.isEmpty,
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode) else {
        completion(nil)
        return
      }
      completion(NotificationService.thumbnailData(from: data))
    }
    task.resume()
  }

  /// Decodes (and downsamples) the image; returns PNG data or nil if it is not an image.
  private static func thumbnailData(from data: Data) -> Data? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
      return nil
    }
    let thumbOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: avatarMaxPixelSize,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: cgImage).pngData()
  }

  /// Fallback avatar: coloured square (iOS masks it to a circle) with initials.
  private static func initialsImageData(name: String, key: String) -> Data? {
    let palette: [UIColor] = [
      UIColor(red: 0.36, green: 0.50, blue: 1.00, alpha: 1), // #5B7FFF
      UIColor(red: 0.90, green: 0.36, blue: 0.36, alpha: 1),
      UIColor(red: 0.30, green: 0.69, blue: 0.47, alpha: 1),
      UIColor(red: 0.96, green: 0.62, blue: 0.24, alpha: 1),
      UIColor(red: 0.62, green: 0.40, blue: 0.86, alpha: 1),
      UIColor(red: 0.20, green: 0.66, blue: 0.80, alpha: 1),
      UIColor(red: 0.89, green: 0.40, blue: 0.64, alpha: 1),
    ]
    var hash: UInt32 = 0
    for scalar in key.unicodeScalars {
      hash = hash &* 31 &+ scalar.value
    }
    let color = palette[Int(hash % UInt32(palette.count))]

    let words = name.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
    var initials = words.prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()
    if initials.isEmpty {
      initials = "?"
    }

    let side: CGFloat = 192
    let size = CGSize(width: side, height: side)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { _ in
      color.setFill()
      UIRectFill(CGRect(origin: .zero, size: size))
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: side * 0.4, weight: .semibold),
        .foregroundColor: UIColor.white,
      ]
      let string = initials as NSString
      let textSize = string.size(withAttributes: attributes)
      let origin = CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2)
      string.draw(at: origin, withAttributes: attributes)
    }
    return image.pngData()
  }

  // MARK: - URL helpers

  private var sharedDefaults: UserDefaults? {
    return UserDefaults(suiteName: Shared.appGroupId)
  }

  /// Base URL without a trailing "/" or "/api" suffix.
  private static func normalizedBase(_ raw: String?) -> String? {
    guard var base = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty else {
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

  /// Resolves absolute / relative avatar URLs:
  /// "/avatars/..." -> storage base URL, other "/..." -> API base URL.
  private func resolveUrl(_ raw: String?) -> URL? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    let lower = value.lowercased()
    if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
      return URL(string: value)
    }
    if value.hasPrefix("//") {
      return URL(string: "https:" + value)
    }
    let path = value.hasPrefix("/") ? value : "/" + value
    let apiBase = NotificationService.normalizedBase(sharedDefaults?.string(forKey: Shared.baseUrlKey))
    let storageBase = NotificationService.normalizedBase(sharedDefaults?.string(forKey: Shared.storageUrlKey))
    let base: String?
    if path.hasPrefix("/avatars/") {
      base = storageBase ?? apiBase
    } else {
      base = apiBase ?? storageBase
    }
    guard let resolvedBase = base else {
      return nil
    }
    if let url = URL(string: resolvedBase + path) {
      return url
    }
    if let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
      return URL(string: resolvedBase + encoded)
    }
    return nil
  }

  /// The auth token is only sent to our own API / storage hosts.
  private func isOwnHost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else {
      return false
    }
    let bases = [Shared.baseUrlKey, Shared.storageUrlKey].compactMap { key -> String? in
      guard let base = NotificationService.normalizedBase(sharedDefaults?.string(forKey: key)) else { return nil }
      return URL(string: base)?.host?.lowercased()
    }
    return bases.contains(host)
  }

  // MARK: - Payload helpers

  /// Non-empty string value of a top-level push key (FCM data values are strings).
  private static func string(_ info: [AnyHashable: Any], _ key: String) -> String? {
    guard let raw = info[key] else {
      return nil
    }
    var value: String?
    if let s = raw as? String {
      value = s
    } else if let n = raw as? NSNumber {
      value = n.stringValue
    }
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          trimmed != "null",
          trimmed != "<null>" else {
      return nil
    }
    return trimmed
  }
}
