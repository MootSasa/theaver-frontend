import Cocoa
import FlutterMacOS
import AVFoundation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupMediaMuxer(messenger: flutterViewController.engine.binaryMessenger)

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
}
