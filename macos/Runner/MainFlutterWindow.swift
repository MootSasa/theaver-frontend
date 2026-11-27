import Cocoa
import FlutterMacOS
import AVFoundation
import WebKit

class MainFlutterWindow: NSWindow {
  private var blockAllCookiesRuleList: WKContentRuleList?
  private var blockThirdPartyCookiesRuleList: WKContentRuleList?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupMediaMuxer(messenger: flutterViewController.engine.binaryMessenger)
    setupBrowserStorageChannel(messenger: flutterViewController.engine.binaryMessenger)
    setupWebViewSnapshotChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
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

  private func collectWebViews(in view: NSView?, onlyVisible: Bool, out: inout [WKWebView]) {
    guard let view = view else { return }
    if onlyVisible && (view.isHidden || view.alphaValue <= 0.01 || view.bounds.width <= 0 || view.bounds.height <= 0) {
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
    var candidates = [WKWebView]()
    collectWebViews(in: self.contentView, onlyVisible: true, out: &candidates)
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
    collectWebViews(in: self.contentView, onlyVisible: false, out: &result)
    return result
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
          if #available(macOS 10.15, *) {
            config.afterScreenUpdates = false
          }
          let clampedTop = min(CGFloat(topCropDp), webView.bounds.height * 0.35)
          if clampedTop > 0 && webView.bounds.height > 1 {
            config.rect = CGRect(
              x: 0,
              y: clampedTop,
              width: webView.bounds.width,
              height: max(1, webView.bounds.height - clampedTop)
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
              var jpegData: Data?
              if let tiffData = image.tiffRepresentation,
                 let bitmap = NSBitmapImageRep(data: tiffData) {
                jpegData = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: NSNumber(value: Double(quality) / 100.0)]
                )
              }
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
        _ = args?["locked"] as? Bool
        DispatchQueue.main.async {
          _ = self.findTargetWebView(targetUrl: urlArg)
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
        let blockAllCookies = (args?["blockAllCookies"] as? Bool) ?? false
        let acceptThirdPartyCookies = (args?["acceptThirdPartyCookies"] as? Bool) ?? true
        DispatchQueue.main.async {
          guard let self = self else {
            result(true)
            return
          }
          let webViews = self.allMountedWebViews()
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
            if #available(macOS 10.15, *), let policy = cookie.sameSitePolicy {
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
          if #available(macOS 10.15, *), let sameSite = (item["sameSite"] as? NSNumber)?.intValue {
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
}
