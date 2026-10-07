import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Cross-platform service for recording Telegram-style circular video notes.
/// Uses [camera_windows] on Windows for native direct recording, and [flutter_webrtc] on other platforms.
class VideoNoteRecorderService with ChangeNotifier {
  RTCVideoRenderer? _renderer;
  MediaStream? _stream;
  MediaRecorder? _recorder;
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  Timer? _timer;
  String? _currentFilePath;

  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isFrontCamera = true;
  Duration _elapsed = Duration.zero;
  String? _errorMessage;
  double _zoomLevel = 1.0;

  RTCVideoRenderer? get renderer => _renderer;
  CameraController? get cameraController => _cameraController;
  bool get isCameraController => _cameraController != null;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isFrontCamera => _isFrontCamera;
  Duration get elapsed => _elapsed;
  String? get errorMessage => _errorMessage;
  String? get currentFilePath => _currentFilePath;
  double get zoomLevel => _zoomLevel;

  /// Sets the zoom level between 1.0 and 3.0
  Future<void> setZoom(double zoom) async {
    _zoomLevel = zoom.clamp(1.0, 3.0);
    notifyListeners();
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setZoomLevel(_zoomLevel);
      } catch (_) {
        // Unimplemented on camera_windows or unsupported by hardware
      }
    }
  }

  /// Checks whether both camera and microphone permissions are currently granted.
  Future<bool> hasPermissions() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }
    try {
      final cam = await Permission.camera.status;
      final mic = await Permission.microphone.status;
      return (cam.isGranted || cam.isLimited) &&
          (mic.isGranted || mic.isLimited);
    } catch (_) {
      return true;
    }
  }

  /// Checks whether either camera or microphone permission is permanently denied.
  Future<bool> isPermanentlyDenied() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final cam = await Permission.camera.status;
      final mic = await Permission.microphone.status;
      return cam.isPermanentlyDenied || mic.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Requests camera and microphone permissions together in a single native request dialog batch.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }

    try {
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final cam = statuses[Permission.camera];
      final mic = statuses[Permission.microphone];

      final camOk = cam?.isGranted == true || cam?.isLimited == true;
      final micOk = mic?.isGranted == true || mic?.isLimited == true;

      return camOk && micOk;
    } catch (_) {
      return true;
    }
  }

  /// Request permissions and initialize live camera preview stream
  Future<bool> initialize() async {
    if (_isInitialized && (_renderer != null || _cameraController != null)) {
      return true;
    }

    try {
      _errorMessage = null;

      final ok = await requestPermissions();
      if (!ok) {
        _errorMessage = 'permission_denied';
        notifyListeners();
        return false;
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        try {
          _availableCameras = await availableCameras();
          if (_availableCameras.isEmpty) {
            _errorMessage = 'No camera available';
            notifyListeners();
            return false;
          }
          final cam = _availableCameras.firstWhere(
            (c) => _isFrontCamera
                ? c.lensDirection == CameraLensDirection.front
                : c.lensDirection == CameraLensDirection.back,
            orElse: () => _availableCameras.first,
          );
          _cameraController = CameraController(
            cam,
            ResolutionPreset.medium,
            enableAudio: true,
          );
          await _cameraController!.initialize();
          _isInitialized = true;
          notifyListeners();
          return true;
        } catch (e) {
          debugPrint('VideoNoteRecorderService: Windows camera initialization failed: $e');
          _errorMessage = e.toString();
          notifyListeners();
          return false;
        }
      }

      _renderer = RTCVideoRenderer();
      await _renderer!.initialize();

      await _acquireStream();

      _isInitialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('VideoNoteRecorderService: Failed to initialize: $e');
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('permission') ||
          errorStr.contains('notallowed') ||
          errorStr.contains('denied')) {
        _errorMessage = 'permission_denied';
      } else {
        _errorMessage = e.toString();
      }
      _cleanupStream();
      notifyListeners();
      return false;
    }
  }

  Future<void> _acquireStream() async {
    try {
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'optional': [],
        },
      };
      _stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      debugPrint(
          'VideoNoteRecorderService: Failed with mandatory constraints, retrying basic: $e');
      final fallbackConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
        },
      };
      _stream = await navigator.mediaDevices.getUserMedia(fallbackConstraints);
    }

    if (_renderer != null) {
      _renderer!.srcObject = _stream;
    }
  }

  AudioRecorder? _audioRecorder;
  String? _audioFilePath;

  /// Start recording video note to a local file (no 60s limit)
  Future<bool> startRecording() async {
    if (!_isInitialized || (_stream == null && _cameraController == null)) {
      final ok = await initialize();
      if (!ok) return false;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      const extension = kIsWeb ? 'webm' : 'mp4';
      _currentFilePath =
          '${tempDir.path}/video_note_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // 1. Windows CameraController path (hardware encoded MP4 with synchronized audio)
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.startVideoRecording();
        _isRecording = true;
        _elapsed = Duration.zero;

        _timer?.cancel();
        _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
          _elapsed += const Duration(milliseconds: 100);
          notifyListeners();
        });

        notifyListeners();
        return true;
      }

      // 2. WebRTC path (Android, iOS, macOS, Web)
      // Start parallel audio recording with package:record for clean AAC microphone recording
      try {
        _audioRecorder = AudioRecorder();
        _audioFilePath =
            '${tempDir.path}/audio_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder!.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 96000,
            sampleRate: 44100,
          ),
          path: _audioFilePath!,
        );
      } catch (audioErr) {
        debugPrint('VideoNoteRecorderService: Audio recording start note: $audioErr');
      }

      // Start video recording with flutter_webrtc
      _recorder = MediaRecorder();
      final videoTracks = _stream!.getVideoTracks();
      final videoTrack = videoTracks.isNotEmpty ? videoTracks.first : null;

      if (!kIsWeb) {
        await _recorder!.start(
          _currentFilePath!,
          videoTrack: videoTrack,
        );
      } else {
        _recorder!.startWeb(
          _stream!,
          mimeType: 'video/webm',
        );
      }

      _isRecording = true;
      _elapsed = Duration.zero;

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        _elapsed += const Duration(milliseconds: 100);
        notifyListeners();
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('VideoNoteRecorderService: Failed to start recording: $e');
      _isRecording = false;
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('permission') ||
          errorStr.contains('notallowed') ||
          errorStr.contains('denied')) {
        _errorMessage = 'permission_denied';
      } else {
        _errorMessage = e.toString();
      }
      notifyListeners();
      return false;
    }
  }

  /// Toggle between front (selfie) and rear cameras during recording or preview
  Future<void> flipCamera() async {
    if (_cameraController != null) {
      try {
        if (_availableCameras.length > 1) {
          final targetDir = _isFrontCamera
              ? CameraLensDirection.back
              : CameraLensDirection.front;
          final nextCam = _availableCameras.firstWhere(
            (c) => c.lensDirection == targetDir,
            orElse: () => _availableCameras.firstWhere(
              (c) => c.name != _cameraController!.description.name,
              orElse: () => _availableCameras.first,
            ),
          );
          final wasRecording = _isRecording;
          await _cameraController!.dispose();
          _cameraController = CameraController(
            nextCam,
            ResolutionPreset.medium,
            enableAudio: true,
          );
          await _cameraController!.initialize();
          if (wasRecording) {
            await _cameraController!.startVideoRecording();
          }
          _isFrontCamera = !_isFrontCamera;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('VideoNoteRecorderService: Camera flip error: $e');
      }
      return;
    }

    if (_stream == null) return;
    final videoTracks = _stream!.getVideoTracks();
    if (videoTracks.isEmpty) return;

    try {
      final track = videoTracks.first;
      if (!kIsWeb) {
        try {
          final isFront = await Helper.switchCamera(track);
          _isFrontCamera = isFront;
        } catch (e) {
          debugPrint('VideoNoteRecorderService: switchCamera error, toggling flag: $e');
          _isFrontCamera = !_isFrontCamera;
        }
      } else {
        final cams = await Helper.cameras;
        if (cams.length > 1) {
          final otherCam = cams.firstWhere(
            (c) => _isFrontCamera
                ? (c.label.toLowerCase().contains('back') ||
                    c.label.toLowerCase().contains('rear') ||
                    c.label.toLowerCase().contains('environment'))
                : (c.label.toLowerCase().contains('front') ||
                    c.label.toLowerCase().contains('user')),
            orElse: () => cams.firstWhere((c) => c.deviceId != track.id,
                orElse: () => cams.first),
          );
          await Helper.switchCamera(track, otherCam.deviceId, _stream);
          _isFrontCamera = !_isFrontCamera;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('VideoNoteRecorderService: Failed to flip camera: $e');
    }
  }

  /// Stop recording and return the finalized video file
  Future<File?> stopRecording() async {
    if (!_isRecording) return null;

    _timer?.cancel();
    _timer = null;
    _isRecording = false;

    // 1. Windows CameraController
    if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
      File? resultFile;
      try {
        final xfile = await _cameraController!.stopVideoRecording();
        final file = File(xfile.path);
        if (await file.exists() && await file.length() > 0) {
          resultFile = file;
          debugPrint(
              'VideoNoteRecorderService: CameraController video recorded: ${file.path} (${await file.length()} bytes)');
        }
      } catch (e) {
        debugPrint('VideoNoteRecorderService: CameraController stop error: $e');
      } finally {
        await _cleanupStream();
        notifyListeners();
      }
      return resultFile;
    }

    File? resultFile;
    try {
      final path = _currentFilePath;
      _currentFilePath = null;

      // 1. Stop video recording
      await _recorder?.stop();
      _recorder = null;

      // 2. Stop audio recording
      String? recordedAudioPath;
      if (_audioRecorder != null) {
        try {
          recordedAudioPath = await _audioRecorder!.stop();
        } catch (e) {
          debugPrint('VideoNoteRecorderService: Audio stop error: $e');
        }
        try {
          _audioRecorder?.dispose();
        } catch (_) {}
        _audioRecorder = null;
      }

      if (path != null) {
        final file = File(path);
        // MediaMuxer on mobile/macOS flushes asynchronously on background thread.
        // Poll for up to 3 seconds for the file to be flushed and non-empty.
        for (int i = 0; i < 30; i++) {
          if (await file.exists() && await file.length() > 0) {
            debugPrint(
                'VideoNoteRecorderService: Video note recorded: ${file.path} (${await file.length()} bytes)');
            resultFile = file;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (resultFile == null && await file.exists() && await file.length() > 0) {
          resultFile = file;
        }

        // 3. Mux audio into video file on mobile/macOS (Android, iOS, macOS)
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
             defaultTargetPlatform == TargetPlatform.iOS ||
             defaultTargetPlatform == TargetPlatform.macOS) &&
            resultFile != null &&
            recordedAudioPath != null) {
          final audioFile = File(recordedAudioPath);
          if (await audioFile.exists() && await audioFile.length() > 0) {
            final muxedPath = '${path}_muxed.mp4';
            try {
              const muxChannel = MethodChannel('com.example.app/media_muxer');
              final success = await muxChannel.invokeMethod<bool>('mux', {
                'videoPath': path,
                'audioPath': recordedAudioPath,
                'outputPath': muxedPath,
              });
              if (success == true) {
                final muxedFile = File(muxedPath);
                if (await muxedFile.exists() && await muxedFile.length() > 0) {
                  await resultFile.delete();
                  await muxedFile.rename(path);
                  resultFile = File(path);
                  debugPrint(
                      'VideoNoteRecorderService: Successfully muxed audio into video: $path');
                }
              }
            } catch (muxErr) {
              debugPrint('VideoNoteRecorderService: Native muxer note: $muxErr');
            }
            try {
              if (await audioFile.exists()) await audioFile.delete();
            } catch (_) {}
          }
        }

        if (resultFile == null) {
          debugPrint('VideoNoteRecorderService: File at $path is missing or empty');
        }
      }
    } catch (e) {
      debugPrint('VideoNoteRecorderService: Failed to stop recording: $e');
    } finally {
      await _cleanupStream();
      notifyListeners();
    }

    return resultFile;
  }

  /// Cancel recording and discard the recorded file (e.g. slide to cancel)
  Future<void> cancelRecording() async {
    _timer?.cancel();
    _timer = null;
    _isRecording = false;

    if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
      try {
        final xfile = await _cameraController!.stopVideoRecording();
        final file = File(xfile.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('VideoNoteRecorderService: Camera cancel error: $e');
      } finally {
        _elapsed = Duration.zero;
        await _cleanupStream();
        notifyListeners();
      }
      return;
    }

    try {
      await _recorder?.stop();
      _recorder = null;

      if (_audioRecorder != null) {
        try {
          await _audioRecorder!.stop();
          _audioRecorder!.dispose();
        } catch (_) {}
        _audioRecorder = null;
      }

      if (_audioFilePath != null) {
        final audioFile = File(_audioFilePath!);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      }

      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('VideoNoteRecorderService: Error during cancel: $e');
    } finally {
      _currentFilePath = null;
      _audioFilePath = null;
      _elapsed = Duration.zero;
      await _cleanupStream();
      notifyListeners();
    }
  }

  Future<void> _cleanupStream() async {
    _timer?.cancel();
    _timer = null;

    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
      } catch (e) {
        debugPrint('VideoNoteRecorderService: CameraController dispose error: $e');
      }
      _cameraController = null;
    }

    if (_audioRecorder != null) {
      try {
        await _audioRecorder!.stop();
        _audioRecorder!.dispose();
      } catch (_) {}
      _audioRecorder = null;
    }

    try {
      if (_renderer != null) {
        _renderer!.srcObject = null;
      }
    } catch (e) {
      debugPrint('VideoNoteRecorderService: Error clearing renderer srcObject: $e');
    }

    if (_stream != null) {
      for (final track in _stream!.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      try {
        await _stream!.dispose();
      } catch (_) {}
      _stream = null;
    }

    _recorder = null;
    _isRecording = false;
    _isInitialized = false;
    _zoomLevel = 1.0;
  }

  @override
  void dispose() {
    _cleanupStream();
    _renderer?.dispose();
    _renderer = null;
    super.dispose();
  }
}
