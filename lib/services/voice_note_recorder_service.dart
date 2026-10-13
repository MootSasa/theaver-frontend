import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Result data of a completed voice recording.
class VoiceRecordResult {
  final File file;
  final Duration duration;
  final List<int> waveform;

  VoiceRecordResult({
    required this.file,
    required this.duration,
    required this.waveform,
  });
}

/// Service managing audio recording, live amplitude streaming, and hands-free locking.
class VoiceNoteRecorderService with ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  bool _isRecording = false;
  bool _isPaused = false;
  bool _isLocked = false;
  Duration _elapsed = Duration.zero;
  String? _currentFilePath;
  final List<double> _liveAmplitudes = [];
  final List<double> _allAmplitudes = [];
  String? _errorMessage;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isLocked => _isLocked;
  Duration get elapsed => _elapsed;
  String? get currentFilePath => _currentFilePath;
  List<double> get liveAmplitudes => List.unmodifiable(_liveAmplitudes);
  String? get errorMessage => _errorMessage;

  /// Checks whether microphone permission is granted.
  Future<bool> hasPermissions() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }
    try {
      final mic = await Permission.microphone.status;
      return mic.isGranted || mic.isLimited;
    } catch (_) {
      return true;
    }
  }

  /// Alias for hasPermissions()
  Future<bool> hasPermission() => hasPermissions();

  /// Checks whether microphone permission is permanently denied.
  Future<bool> isPermanentlyDenied() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final mic = await Permission.microphone.status;
      return mic.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Requests microphone permission natively.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }
    try {
      final status = await Permission.microphone.request();
      return status.isGranted || status.isLimited;
    } catch (_) {
      return true;
    }
  }

  /// Starts voice recording to a temporary `.m4a` file.
  Future<bool> startRecording() async {
    if (_isRecording) return true;

    try {
      _errorMessage = null;
      final ok = await hasPermissions();
      if (!ok) {
        final granted = await requestPermissions();
        if (!granted) {
          _errorMessage = 'Microphone permission denied';
          notifyListeners();
          return false;
        }
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentFilePath = '${dir.path}/voice_note_$timestamp.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentFilePath!,
      );

      _isRecording = true;
      _isPaused = false;
      _isLocked = false;
      _elapsed = Duration.zero;
      _liveAmplitudes.clear();
      _allAmplitudes.clear();

      _startTimer();
      _startAmplitudeSampling();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[VoiceNoteRecorderService] startRecording error: $e');
      _errorMessage = e.toString();
      _isRecording = false;
      if (_currentFilePath != null) {
        try {
          final file = File(_currentFilePath!);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (_) {}
        _currentFilePath = null;
      }
      notifyListeners();
      return false;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_isRecording && !_isPaused) {
        _elapsed += const Duration(milliseconds: 200);
        notifyListeners();
      }
    });
  }

  void _startAmplitudeSampling() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      if (!_isRecording || _isPaused) return;

      // Normalize dBFS (-55 dBFS to 0 dBFS) into 0.0 .. 1.0 range
      final raw = amp.current;
      final normalized = ((raw.clamp(-55.0, 0.0) + 55.0) / 55.0).clamp(0.06, 1.0);

      _liveAmplitudes.add(normalized);
      if (_liveAmplitudes.length > 35) {
        _liveAmplitudes.removeAt(0);
      }

      _allAmplitudes.add(normalized);
      notifyListeners();
    });
  }

  /// Sets whether the recording is locked in hands-free mode.
  void setLocked(bool locked) {
    if (_isLocked != locked) {
      _isLocked = locked;
      notifyListeners();
    }
  }

  /// Pauses the active recording (in locked mode).
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    try {
      await _recorder.pause();
      _isPaused = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceNoteRecorderService] pauseRecording error: $e');
    }
  }

  /// Resumes the active recording.
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    try {
      await _recorder.resume();
      _isPaused = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceNoteRecorderService] resumeRecording error: $e');
    }
  }

  /// Stops recording and returns the file, duration, and sampled waveform.
  Future<VoiceRecordResult?> stopRecording() async {
    if (!_isRecording) return null;

    _timer?.cancel();
    _timer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      final recordedPath = await _recorder.stop();
      _isRecording = false;
      _isPaused = false;
      _isLocked = false;

      final path = recordedPath ?? _currentFilePath;
      _currentFilePath = null;
      if (path == null) {
        notifyListeners();
        return null;
      }

      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        notifyListeners();
        return null;
      }

      final duration = _elapsed;
      final waveform = _generateWaveformSamples(_allAmplitudes, targetCount: 36);

      notifyListeners();
      return VoiceRecordResult(
        file: file,
        duration: duration,
        waveform: waveform,
      );
    } catch (e) {
      debugPrint('[VoiceNoteRecorderService] stopRecording error: $e');
      _isRecording = false;
      _currentFilePath = null;
      notifyListeners();
      return null;
    }
  }

  /// Cancels recording and discards temporary file.
  Future<void> cancelRecording() async {
    _timer?.cancel();
    _timer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {}

    if (_currentFilePath != null) {
      try {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _isRecording = false;
    _isPaused = false;
    _isLocked = false;
    _elapsed = Duration.zero;
    _liveAmplitudes.clear();
    _allAmplitudes.clear();
    _currentFilePath = null;
    notifyListeners();
  }

  /// Resamples recorded amplitudes into a fixed number of integer values (0..31).
  List<int> _generateWaveformSamples(List<double> raw, {int targetCount = 36}) {
    if (raw.isEmpty) {
      return List.filled(targetCount, 8);
    }

    final result = <int>[];
    if (raw.length <= targetCount) {
      // Upsample / duplicate
      for (int i = 0; i < targetCount; i++) {
        final idx = ((i / targetCount) * raw.length).floor().clamp(0, raw.length - 1);
        result.add((raw[idx] * 31).round().clamp(2, 31));
      }
    } else {
      // Downsample by averaging chunk windows
      final chunkSize = raw.length / targetCount;
      for (int i = 0; i < targetCount; i++) {
        final start = (i * chunkSize).floor();
        final end = math.min(((i + 1) * chunkSize).ceil(), raw.length);
        double sum = 0.0;
        int count = 0;
        for (int j = start; j < end; j++) {
          sum += raw[j];
          count++;
        }
        final avg = count > 0 ? (sum / count) : 0.2;
        result.add((avg * 31).round().clamp(2, 31));
      }
    }
    return result;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (_isRecording) {
      _isRecording = false;
      try {
        _recorder.stop();
      } catch (_) {}
    }
    if (_currentFilePath != null) {
      try {
        final file = File(_currentFilePath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
      _currentFilePath = null;
    }
    try {
      _recorder.dispose();
    } catch (_) {}
    super.dispose();
  }
}
