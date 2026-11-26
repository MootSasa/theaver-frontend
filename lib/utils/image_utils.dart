import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture, immutable, kIsWeb;
import 'package:flutter/material.dart';
import '../config/app_config.dart';

/// Normalized `[0..1] x [0..1]` square subregion specifying which part of a full
/// avatar image is framed as the miniature circular/squircle icon across chats,
/// contacts, and collapsed profiles.
@immutable
class AvatarCropSpec {
  final double nx;
  final double ny;
  final double nw;
  final double nh;

  const AvatarCropSpec({
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
  });

  double get cx => nx + nw * 0.5;
  double get cy => ny + nh * 0.5;

  /// Full outer image `width / height` inferred from a square pixel crop
  /// (`nw * imgW == nh * imgH` -> `imgW / imgH == nh / nw`).
  double get imageAspectRatio => nw > 1e-6 ? (nh / nw) : 1.0;

  bool get isFullSquare =>
      nx <= 0.002 && ny <= 0.002 && nw >= 0.998 && nh >= 0.998;

  String toCompactParam() =>
      '${nx.toStringAsFixed(4)},${ny.toStringAsFixed(4)},${nw.toStringAsFixed(4)},${nh.toStringAsFixed(4)}';

  String attachToUrl(String base) {
    final clean = stripAvatarCropFragment(base) ?? base;
    if (clean.isEmpty || isFullSquare) return clean;
    return '$clean#acrop=${toCompactParam()}';
  }

  static AvatarCropSpec? tryParseParam(String? raw) {
    if (raw == null) return null;
    String s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.startsWith('acrop=')) s = s.substring(6);
    final parts = s.split(',');
    if (parts.length != 4) return null;

    final List<double> vals = <double>[];
    for (final part in parts) {
      final double? v = double.tryParse(part.trim());
      if (v == null || v.isNaN || v.isInfinite) return null;
      vals.add(v);
    }

    double nx = vals[0];
    double ny = vals[1];
    double nw = vals[2];
    double nh = vals[3];
    if (nx < -0.001 ||
        ny < -0.001 ||
        nw < 0.05 ||
        nh < 0.05 ||
        nx + nw > 1.002 ||
        ny + nh > 1.002) {
      return null;
    }
    nx = nx.clamp(0.0, 0.95).toDouble();
    ny = ny.clamp(0.0, 0.95).toDouble();
    nw = nw.clamp(0.05, 1.0 - nx).toDouble();
    nh = nh.clamp(0.05, 1.0 - ny).toDouble();

    final spec = AvatarCropSpec(nx: nx, ny: ny, nw: nw, nh: nh);
    return spec.isFullSquare ? null : spec;
  }

  static ({String? cleanUrl, AvatarCropSpec? crop}) split(String? url) {
    if (url == null || url.isEmpty || url.startsWith('data:')) {
      return (cleanUrl: url, crop: null);
    }
    final int idx = url.indexOf('#acrop=');
    if (idx < 0) {
      return (cleanUrl: url, crop: null);
    }
    final String clean = url.substring(0, idx);
    final String rawParam = url.substring(idx + 7);
    return (cleanUrl: clean, crop: tryParseParam(rawParam));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarCropSpec &&
          runtimeType == other.runtimeType &&
          (nx - other.nx).abs() < 1e-4 &&
          (ny - other.ny).abs() < 1e-4 &&
          (nw - other.nw).abs() < 1e-4 &&
          (nh - other.nh).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(
        (nx * 10000).round(),
        (ny * 10000).round(),
        (nw * 10000).round(),
        (nh * 10000).round(),
      );
}

/// Removes any `#acrop=...` fragment from [url] when fetching or reading the
/// underlying full-resolution file or network object.
String? stripAvatarCropFragment(String? url) => AvatarCropSpec.split(url).cleanUrl;

/// Upgrades [primary] to include an `#acrop=...` fragment from [candidates]
/// when both reference the same underlying full photo and [primary] lost its
/// fragment in a non-fragmented cache/API field.
String? preferAvatarUrlWithCrop(
  String? primary,
  Iterable<String?> candidates,
) {
  if (primary == null) return null;
  final String trimmedPrimary = primary.trim();
  if (trimmedPrimary.isEmpty) return primary;

  final ({String? cleanUrl, AvatarCropSpec? crop}) primarySplit =
      AvatarCropSpec.split(trimmedPrimary);
  if (primarySplit.crop != null ||
      primarySplit.cleanUrl == null ||
      primarySplit.cleanUrl!.isEmpty) {
    return trimmedPrimary;
  }

  final String rawCleanPrimary = primarySplit.cleanUrl!;
  final String? resolvedCleanPrimary = getValidAvatarUrl(rawCleanPrimary);

  for (final String? candidate in candidates) {
    if (candidate == null) continue;
    final String trimmedCand = candidate.trim();
    if (trimmedCand.isEmpty) continue;
    final ({String? cleanUrl, AvatarCropSpec? crop}) candSplit =
        AvatarCropSpec.split(trimmedCand);
    final AvatarCropSpec? candCrop = candSplit.crop;
    final String? rawCleanCand = candSplit.cleanUrl;
    if (candCrop == null || rawCleanCand == null || rawCleanCand.isEmpty) {
      continue;
    }
    final String? resolvedCleanCand = getValidAvatarUrl(rawCleanCand);
    final bool matches = rawCleanCand == rawCleanPrimary ||
        (resolvedCleanPrimary != null &&
            resolvedCleanCand != null &&
            resolvedCleanCand == resolvedCleanPrimary);
    if (matches) {
      return candCrop.attachToUrl(rawCleanPrimary);
    }
  }

  return trimmedPrimary;
}

@immutable
class AvatarSubregionImageKey {
  final Object baseKey;
  final int nx10k;
  final int ny10k;
  final int nw10k;
  final int nh10k;
  final int targetDimension;

  const AvatarSubregionImageKey({
    required this.baseKey,
    required this.nx10k,
    required this.ny10k,
    required this.nw10k,
    required this.nh10k,
    required this.targetDimension,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarSubregionImageKey &&
          runtimeType == other.runtimeType &&
          baseKey == other.baseKey &&
          nx10k == other.nx10k &&
          ny10k == other.ny10k &&
          nw10k == other.nw10k &&
          nh10k == other.nh10k &&
          targetDimension == other.targetDimension;

  @override
  int get hashCode => Object.hash(
        baseKey,
        nx10k,
        ny10k,
        nw10k,
        nh10k,
        targetDimension,
      );
}

/// Renders a crisp square miniature image from the normalized [crop] subregion
/// of [baseProvider], keeping the stored source image full-size.
class AvatarSubregionImageProvider
    extends ImageProvider<AvatarSubregionImageKey> {
  final ImageProvider baseProvider;
  final AvatarCropSpec crop;
  final int targetDimension;

  const AvatarSubregionImageProvider({
    required this.baseProvider,
    required this.crop,
    this.targetDimension = 240,
  });

  @override
  Future<AvatarSubregionImageKey> obtainKey(
    ImageConfiguration configuration,
  ) {
    Completer<AvatarSubregionImageKey>? completer;
    SynchronousFuture<AvatarSubregionImageKey>? result;
    baseProvider.obtainKey(configuration).then(
      (Object baseKey) {
        final key = AvatarSubregionImageKey(
          baseKey: baseKey,
          nx10k: (crop.nx * 10000).round(),
          ny10k: (crop.ny * 10000).round(),
          nw10k: (crop.nw * 10000).round(),
          nh10k: (crop.nh * 10000).round(),
          targetDimension: targetDimension,
        );
        if (completer == null) {
          result = SynchronousFuture<AvatarSubregionImageKey>(key);
        } else {
          completer!.complete(key);
        }
      },
      onError: (Object error, StackTrace stack) {
        completer ??= Completer<AvatarSubregionImageKey>();
        completer!.completeError(error, stack);
      },
    );
    if (result != null) {
      return result!;
    }
    final c = Completer<AvatarSubregionImageKey>();
    completer = c;
    return c.future;
  }

  @override
  ImageStreamCompleter loadImage(
    AvatarSubregionImageKey key,
    ImageDecoderCallback decode,
  ) {
    return _SubregionImageStreamCompleter(
      baseProvider: baseProvider,
      crop: crop,
      targetDimension: targetDimension,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarSubregionImageProvider &&
          runtimeType == other.runtimeType &&
          baseProvider == other.baseProvider &&
          crop == other.crop &&
          targetDimension == other.targetDimension;

  @override
  int get hashCode => Object.hash(baseProvider, crop, targetDimension);
}

class _SubregionImageStreamCompleter extends ImageStreamCompleter {
  final ImageProvider baseProvider;
  final AvatarCropSpec crop;
  final int targetDimension;

  ImageStream? _baseStream;
  late final ImageStreamListener _baseListener;
  bool _subscribed = false;
  bool _disposed = false;
  int _cropGeneration = 0;

  _SubregionImageStreamCompleter({
    required this.baseProvider,
    required this.crop,
    required this.targetDimension,
  }) {
    _baseListener = ImageStreamListener(
      _handleBaseImage,
      onChunk: reportImageChunkEvent,
      onError: (Object err, StackTrace? st) {
        if (!_disposed) {
          reportError(exception: err, stack: st);
        }
      },
    );
  }

  void _ensureSubscribed() {
    if (_subscribed || _disposed) return;
    _subscribed = true;
    final ImageStream stream = baseProvider.resolve(ImageConfiguration.empty);
    _baseStream = stream;
    stream.addListener(_baseListener);
  }

  @override
  void addListener(ImageStreamListener listener) {
    _ensureSubscribed();
    super.addListener(listener);
  }

  @override
  void onDisposed() {
    _disposed = true;
    _cropGeneration++;
    _baseStream?.removeListener(_baseListener);
    _baseStream = null;
    super.onDisposed();
  }

  void _handleBaseImage(ImageInfo baseInfo, bool synchronousCall) {
    if (_disposed) return;
    final int gen = ++_cropGeneration;
    final ui.Image srcImg = baseInfo.image;
    final double w = srcImg.width.toDouble();
    final double h = srcImg.height.toDouble();
    if (w < 1.0 || h < 1.0) return;

    final double srcX = (crop.nx * w).clamp(0.0, math.max(0.0, w - 1.0));
    final double srcY = (crop.ny * h).clamp(0.0, math.max(0.0, h - 1.0));
    final double srcW = (crop.nw * w).clamp(1.0, w - srcX);
    final double srcH = (crop.nh * h).clamp(1.0, h - srcY);
    final Rect srcRect = Rect.fromLTWH(srcX, srcY, srcW, srcH);

    final int outSide = math
        .min(
          targetDimension.clamp(32, 1024),
          math.max(srcW, srcH).round().clamp(32, 1024),
        )
        .clamp(32, 1024);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawImageRect(
      srcImg,
      srcRect,
      Rect.fromLTWH(0.0, 0.0, outSide.toDouble(), outSide.toDouble()),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    final ui.Picture picture = recorder.endRecording();

    picture.toImage(outSide, outSide).then((ui.Image cropped) {
      picture.dispose();
      if (_disposed || gen != _cropGeneration) {
        cropped.dispose();
        return;
      }
      setImage(ImageInfo(image: cropped, scale: 1.0));
    }, onError: (Object err, StackTrace st) {
      picture.dispose();
      if (!_disposed && gen == _cropGeneration) {
        reportError(exception: err, stack: st);
      }
    });
  }
}

final Map<String, ({bool exists, int checkedAtMs})> _localFileExistsCache = {};
const int _kLocalFileExistsTtlMs = 5000;

/// Invalidates cached `File.existsSync()` lookups for local avatar paths.
void invalidateLocalAvatarCache([String? path]) {
  if (path != null && path.isNotEmpty) {
    final clean = stripAvatarCropFragment(path);
    _localFileExistsCache.remove(path);
    if (clean != null && clean.isNotEmpty) {
      _localFileExistsCache.remove(clean);
    }
  } else {
    _localFileExistsCache.clear();
  }
}

bool _localFileExistsCached(String filePath) {
  final String lookupPath = stripAvatarCropFragment(filePath) ?? filePath;
  if (kIsWeb || lookupPath.isEmpty) return false;
  final now = DateTime.now().millisecondsSinceEpoch;
  final cached = _localFileExistsCache[lookupPath];
  if (cached != null && (now - cached.checkedAtMs) < _kLocalFileExistsTtlMs) {
    return cached.exists;
  }
  bool exists = false;
  try {
    exists = File(lookupPath).existsSync();
  } catch (_) {}
  if (_localFileExistsCache.length > 512) {
    _localFileExistsCache.clear();
  }
  _localFileExistsCache[lookupPath] = (exists: exists, checkedAtMs: now);
  return exists;
}

/// Validates and returns a valid avatar URL or local file path, or null if invalid
///
/// This function checks if the URL is a valid HTTP/HTTPS URL, data: URL, relative URL,
/// or local file path to prevent errors when loading images.
String? getValidAvatarUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  // data: URLs are valid (base64 encoded avatars)
  if (url.startsWith('data:')) return url;

  final ({String? cleanUrl, AvatarCropSpec? crop}) split =
      AvatarCropSpec.split(url);
  String? working = split.cleanUrl;
  if (working == null || working.isEmpty) return null;

  String withCrop(String resolved) =>
      split.crop != null ? split.crop!.attachToUrl(resolved) : resolved;

  // Local file path or file:// URI (keep filesystem resolution fast and explicit).
  if (!kIsWeb && working.startsWith('file://')) {
    try {
      if (_localFileExistsCached(Uri.parse(working).toFilePath())) {
        return withCrop(working);
      }
    } catch (_) {}
  } else if (!kIsWeb && (working.contains(':\\') || working.contains(':/'))) {
    if (_localFileExistsCached(working)) return withCrop(working);
  } else if (working.startsWith('/')) {
    if (!kIsWeb && _localFileExistsCached(working)) {
      return withCrop(working);
    }
  }

  final resolved = AppConfig.resolveMediaUrl(working);
  if (resolved == null || resolved.isEmpty) return null;
  if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
    return withCrop(resolved);
  }
  if (!kIsWeb && _localFileExistsCached(resolved)) {
    return withCrop(resolved);
  }
  return null;
}

final Map<String, MemoryImage> _dataUrlMemoryImageCache = {};

ImageProvider _maybeResizeAvatar(
  ImageProvider provider, {
  required int? maxDecodeDimension,
  required bool fullResolution,
}) {
  if (fullResolution || maxDecodeDimension == null || maxDecodeDimension <= 0) {
    return provider;
  }
  return ResizeImage(
    provider,
    width: maxDecodeDimension,
    height: maxDecodeDimension,
    policy: ResizeImagePolicy.fit,
  );
}

ImageProvider? _buildRawAvatarImageProvider(
  String? cleanUrl, {
  String? cleanFallbackPath,
  int? maxDecodeDimension = 200,
  bool fullResolution = false,
}) {
  if ((cleanUrl == null || cleanUrl.isEmpty) &&
      (cleanFallbackPath == null || cleanFallbackPath.isEmpty)) {
    return null;
  }

  // If URL is missing, try fallback local path
  if (cleanUrl == null || cleanUrl.isEmpty) {
    if (!kIsWeb &&
        cleanFallbackPath != null &&
        _localFileExistsCached(cleanFallbackPath)) {
      return _maybeResizeAvatar(
        FileImage(File(cleanFallbackPath)),
        maxDecodeDimension: maxDecodeDimension,
        fullResolution: fullResolution,
      );
    }
    return null;
  }

  // Handle data: URLs (base64 encoded avatars stored in DB)
  if (cleanUrl.startsWith('data:')) {
    var cached = _dataUrlMemoryImageCache[cleanUrl];
    if (cached == null) {
      try {
        final commaIndex = cleanUrl.indexOf(',');
        if (commaIndex == -1) return null;
        final base64Str = cleanUrl.substring(commaIndex + 1);
        final bytes = base64Decode(base64Str);
        cached = MemoryImage(bytes);
        if (_dataUrlMemoryImageCache.length > 64) {
          _dataUrlMemoryImageCache.remove(_dataUrlMemoryImageCache.keys.first);
        }
        _dataUrlMemoryImageCache[cleanUrl] = cached;
      } catch (_) {
        return null;
      }
    }
    return _maybeResizeAvatar(
      cached,
      maxDecodeDimension: maxDecodeDimension,
      fullResolution: fullResolution,
    );
  }

  // Handle local file paths or file:// URIs on non-Web platforms
  if (!kIsWeb) {
    if (cleanUrl.startsWith('file://')) {
      try {
        final filePath = Uri.parse(cleanUrl).toFilePath();
        if (_localFileExistsCached(filePath)) {
          return _maybeResizeAvatar(
            FileImage(File(filePath)),
            maxDecodeDimension: maxDecodeDimension,
            fullResolution: fullResolution,
          );
        }
      } catch (_) {}
    }

    if (_localFileExistsCached(cleanUrl)) {
      return _maybeResizeAvatar(
        FileImage(File(cleanUrl)),
        maxDecodeDimension: maxDecodeDimension,
        fullResolution: fullResolution,
      );
    }
  }

  // Network URL or relative backend path
  final validUrl = stripAvatarCropFragment(getValidAvatarUrl(cleanUrl));
  if (validUrl == null ||
      (!validUrl.startsWith('http://') && !validUrl.startsWith('https://'))) {
    if (!kIsWeb &&
        cleanFallbackPath != null &&
        _localFileExistsCached(cleanFallbackPath)) {
      return _maybeResizeAvatar(
        FileImage(File(cleanFallbackPath)),
        maxDecodeDimension: maxDecodeDimension,
        fullResolution: fullResolution,
      );
    }
    return null;
  }

  return _maybeResizeAvatar(
    CachedNetworkImageProvider(
      validUrl,
      cacheKey: AppConfig.cacheKeyForUrl(validUrl),
      headers: AppConfig.authHeadersForUrl(validUrl),
      errorListener: (e) {
        debugPrint('[avatarImageProvider] Failed to load avatar ($validUrl): $e');
      },
    ),
    maxDecodeDimension: maxDecodeDimension,
    fullResolution: fullResolution,
  );
}

/// Creates a thumbnail [ImageProvider] from an avatar URL or local file path.
/// When [url] carries an `#acrop=...` subregion fragment and [fullResolution] is
/// `false`, wraps the decoded full photo in [AvatarSubregionImageProvider].
ImageProvider? avatarImageProvider(
  String? url, {
  String? localFallbackPath,
  int? maxDecodeDimension = 200,
  bool fullResolution = false,
}) {
  final ({String? cleanUrl, AvatarCropSpec? crop}) primarySplit =
      AvatarCropSpec.split(url);
  final ({String? cleanUrl, AvatarCropSpec? crop}) fallbackSplit =
      AvatarCropSpec.split(localFallbackPath);

  final String? cleanPrimary = primarySplit.cleanUrl;
  final String? cleanFallback = fallbackSplit.cleanUrl;

  if (fullResolution) {
    return _buildRawAvatarImageProvider(
      cleanPrimary,
      cleanFallbackPath: cleanFallback,
      fullResolution: true,
    );
  }

  final bool usingPrimary = cleanPrimary != null && cleanPrimary.isNotEmpty;
  final AvatarCropSpec? effectiveCrop =
      usingPrimary ? primarySplit.crop : fallbackSplit.crop;

  if (effectiveCrop == null) {
    return _buildRawAvatarImageProvider(
      cleanPrimary,
      cleanFallbackPath: cleanFallback,
      maxDecodeDimension: maxDecodeDimension,
      fullResolution: false,
    );
  }

  final int targetOutDim = (maxDecodeDimension ?? 240).clamp(64, 720);
  final double minFrac =
      math.min(effectiveCrop.nw, effectiveCrop.nh).clamp(0.05, 1.0);
  final int baseDecodeDim = (targetOutDim / minFrac).round().clamp(240, 1600);

  final ImageProvider? baseProvider = _buildRawAvatarImageProvider(
    cleanPrimary,
    cleanFallbackPath: cleanFallback,
    maxDecodeDimension: baseDecodeDim,
    fullResolution: false,
  );
  if (baseProvider == null) return null;

  return AvatarSubregionImageProvider(
    baseProvider: baseProvider,
    crop: effectiveCrop,
    targetDimension: targetOutDim,
  );
}

/// Creates a full-resolution [ImageProvider] without thumbnail downscaling,
/// used for fullscreen photo inspection and expanded profile headers.
ImageProvider? avatarFullImageProvider(
  String? url, {
  String? localFallbackPath,
}) {
  return avatarImageProvider(
    url,
    localFallbackPath: localFallbackPath,
    fullResolution: true,
  );
}

/// Creates a CircleAvatar with proper error handling for avatar URLs and local file paths
/// 
/// If the URL is invalid or empty, displays initials instead
Widget buildAvatar({
  required String? avatarUrl,
  required String name,
  double radius = 20,
  Color backgroundColor = const Color(0xFF0088CC),
  String? localFallbackPath,
  Key? key,
}) {
  final provider = avatarImageProvider(
    avatarUrl,
    localFallbackPath: localFallbackPath,
    maxDecodeDimension: (radius * 6).round().clamp(120, 480),
  );
  return CircleAvatar(
    key: key,
    radius: radius,
    backgroundColor: backgroundColor,
    backgroundImage: provider,
    onBackgroundImageError: provider != null
        ? (exception, stackTrace) {
            debugPrint('[buildAvatar] Failed to render avatar ($avatarUrl): $exception');
          }
        : null,
    child: provider == null
        ? Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: radius * 0.9,
              fontWeight: FontWeight.bold,
            ),
          )
        : null,
  );
}
