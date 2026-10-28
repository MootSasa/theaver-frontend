import Flutter
import UIKit
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private var proximityEventSink: FlutterEventSink?
  private var mediaSessionChannel: FlutterMethodChannel?
  private var remoteCommandsConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
      setupMediaMuxer(messenger: messenger)
      setupProximityAndMediaSession(messenger: messenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    setupMediaMuxer(messenger: messenger)
    setupProximityAndMediaSession(messenger: messenger)
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
