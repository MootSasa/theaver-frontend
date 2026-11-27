import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/contacts_service.dart';
import '../../utils/image_utils.dart';
import '../design_system/theav_design_system.dart';

/// Transparent 1x1 PNG bytes for temporary fallback
final Uint8List _transparentPixelBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
]);

/// Generates a PNG byte list containing a circular avatar with initial letter
Future<Uint8List> _createInitialsAvatarBytes(String displayName, {required bool isDark}) async {
  final letter = displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : '?';
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 200, 200));

  final bgPaint = Paint()
    ..color = isDark ? const Color(0xFF3C3C43) : const Color(0xFFD1D1D6);
  canvas.drawCircle(const Offset(100, 100), 100, bgPaint);

  final textPainter = TextPainter(
    text: TextSpan(
      text: letter,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        fontSize: 96,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();
  textPainter.paint(
    canvas,
    Offset(100 - textPainter.width / 2, 100 - textPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final img = await picture.toImage(200, 200);
  picture.dispose();
  try {
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}

/// Encodes an already-resolved (and `#acrop=...` subregion-cropped when present)
/// avatar [src] image into a crisp square PNG for synchronous `MemoryImage`
/// painting inside `PrettyQrDecorationImage`.
Future<Uint8List?> _renderSquareAvatarPng(
  ui.Image src, {
  int side = 256,
}) async {
  final double w = src.width.toDouble();
  final double h = src.height.toDouble();
  if (w < 1.0 || h < 1.0) return null;

  final double square = math.min(w, h);
  final Rect srcRect = Rect.fromLTWH(
    (w - square) * 0.5,
    (h - square) * 0.5,
    square,
    square,
  );
  final double dstSide = side.toDouble();
  final Rect dstRect = Rect.fromLTWH(0.0, 0.0, dstSide, dstSide);

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder, dstRect);
  canvas.drawImageRect(
    src,
    srcRect,
    dstRect,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image outImg = await picture.toImage(side, side);
  picture.dispose();
  try {
    final ByteData? byteData =
        await outImg.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } finally {
    outImg.dispose();
  }
}

/// Диалоговое окно с QR-кодом профиля пользователя.
class QrCodeDialog extends StatefulWidget {
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String scanHintLabel;

  const QrCodeDialog({
    Key? key,
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.scanHintLabel = 'Отсканируйте QR-код, чтобы открыть профиль',
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String displayName,
    required String username,
    String? avatarUrl,
    String scanHintLabel = 'Отсканируйте QR-код, чтобы открыть профиль',
  }) {
    return showDialog(
      context: context,
      builder: (context) => QrCodeDialog(
        userId: userId,
        displayName: displayName,
        username: username,
        avatarUrl: avatarUrl,
        scanHintLabel: scanHintLabel,
      ),
    );
  }

  @override
  State<QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<QrCodeDialog> {
  bool _brightnessChanged = false;
  Uint8List? _bakedAvatarBytes;
  Uint8List? _fallbackAvatarBytes;
  ImageStream? _avatarStream;
  ImageStreamListener? _avatarListener;
  int _avatarLoadGen = 0;
  bool _hasLoadedAvatar = false;
  String? _loadedAvatarUrl;
  String? _loadedDisplayName;
  bool? _loadedIsDark;

  String? get _effectiveAvatarUrl {
    String? raw = widget.avatarUrl?.trim();
    if (widget.userId.isNotEmpty) {
      Account? currentAcc;
      try {
        currentAcc = AccountManager().currentAccount;
      } catch (_) {}
      if (currentAcc != null && currentAcc.userId == widget.userId) {
        if (raw == null || raw.isEmpty) {
          raw = (currentAcc.avatarUrl != null &&
                  currentAcc.avatarUrl!.trim().isNotEmpty)
              ? currentAcc.avatarUrl!.trim()
              : currentAcc.localAvatarPath?.trim();
        }
        raw = preferAvatarUrlWithCrop(raw, <String?>[
          currentAcc.avatarUrl,
          currentAcc.localAvatarPath,
        ]);
      } else {
        final ContactItem? cachedContact =
            ContactsService.getCached(widget.userId);
        final String? contactOverride =
            ContactsService.resolveAvatarUrl(widget.userId, raw);
        if ((raw == null || raw.isEmpty) &&
            contactOverride != null &&
            contactOverride.trim().isNotEmpty) {
          raw = contactOverride.trim();
        }
        raw = preferAvatarUrlWithCrop(raw, <String?>[
          contactOverride,
          cachedContact?.customAvatarUrl,
          cachedContact?.avatarUrl,
        ]);
      }
    }
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  String get _effectiveDisplayName {
    if (ContactsService.shouldResolveUserIdentity(widget.userId)) {
      return ContactsService.resolvePeerName(
        widget.userId,
        widget.displayName,
      );
    }
    return widget.displayName;
  }

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    _setMaxBrightness();
  }

  void _onContactsRevisionChanged() {
    if (!mounted) return;
    final effectiveUrl = _effectiveAvatarUrl;
    final effectiveName = _effectiveDisplayName;
    final isDark = _loadedIsDark ?? Theme.of(context).brightness == Brightness.dark;
    if (_loadedAvatarUrl != effectiveUrl || _loadedDisplayName != effectiveName) {
      _loadedAvatarUrl = effectiveUrl;
      _loadedDisplayName = effectiveName;
      _refreshAvatarGraphics(effectiveUrl: effectiveUrl, isDark: isDark);
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? effectiveUrl = _effectiveAvatarUrl;
    final String effectiveName = _effectiveDisplayName;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_hasLoadedAvatar ||
        _loadedAvatarUrl != effectiveUrl ||
        _loadedDisplayName != effectiveName ||
        (effectiveUrl == null && _loadedIsDark != isDark)) {
      _hasLoadedAvatar = true;
      _loadedAvatarUrl = effectiveUrl;
      _loadedDisplayName = effectiveName;
      _loadedIsDark = isDark;
      _refreshAvatarGraphics(effectiveUrl: effectiveUrl, isDark: isDark);
    }
  }

  @override
  void didUpdateWidget(covariant QrCodeDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.userId != widget.userId ||
        oldWidget.displayName != widget.displayName) {
      final String? effectiveUrl = _effectiveAvatarUrl;
      final String effectiveName = _effectiveDisplayName;
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      _loadedAvatarUrl = effectiveUrl;
      _loadedDisplayName = effectiveName;
      _loadedIsDark = isDark;
      _refreshAvatarGraphics(effectiveUrl: effectiveUrl, isDark: isDark);
    }
  }

  void _clearAvatarStream() {
    if (_avatarStream != null && _avatarListener != null) {
      _avatarStream!.removeListener(_avatarListener!);
    }
    _avatarStream = null;
    _avatarListener = null;
  }

  Future<void> _loadFallbackInitials(int gen, {required bool isDark}) async {
    try {
      final bytes =
          await _createInitialsAvatarBytes(_effectiveDisplayName, isDark: isDark);
      if (!mounted || gen != _avatarLoadGen) return;
      setState(() {
        _fallbackAvatarBytes = bytes;
      });
    } catch (_) {}
  }

  void _refreshAvatarGraphics({
    required String? effectiveUrl,
    required bool isDark,
  }) {
    _clearAvatarStream();
    final int gen = ++_avatarLoadGen;
    _bakedAvatarBytes = null;
    _fallbackAvatarBytes = null;

    final ImageProvider? provider = avatarImageProvider(
      effectiveUrl,
      maxDecodeDimension: 256,
    );
    if (provider == null) {
      _loadFallbackInitials(gen, isDark: isDark);
      return;
    }

    final ImageStream stream = provider.resolve(ImageConfiguration.empty);
    _avatarStream = stream;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!mounted || gen != _avatarLoadGen) return;
        final ui.Image ownedImage = info.image.clone();
        stream.removeListener(listener);
        if (identical(_avatarStream, stream)) {
          _avatarStream = null;
          _avatarListener = null;
        }
        _renderSquareAvatarPng(ownedImage, side: 256).then(
          (Uint8List? bytes) {
            ownedImage.dispose();
            if (!mounted || gen != _avatarLoadGen || bytes == null) return;
            setState(() {
              _bakedAvatarBytes = bytes;
            });
          },
          onError: (_, __) {
            ownedImage.dispose();
          },
        );
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (identical(_avatarStream, stream)) {
          _avatarStream = null;
          _avatarListener = null;
        }
        if (!mounted || gen != _avatarLoadGen) return;
        _loadFallbackInitials(gen, isDark: isDark);
      },
    );
    _avatarListener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _avatarLoadGen++;
    _clearAvatarStream();
    _restoreBrightness();
    super.dispose();
  }

  Future<void> _setMaxBrightness() async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      _brightnessChanged = true;
    } catch (e) {
      debugPrint('QrCodeDialog: failed to set brightness: $e');
    }
  }

  Future<void> _restoreBrightness() async {
    if (_brightnessChanged) {
      _brightnessChanged = false;
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (e) {
        debugPrint('QrCodeDialog: failed to restore brightness: $e');
      }
    }
  }

  String get _profileUrl => AppConfig.getProfileUrl(widget.userId);

  String get _formattedUsername {
    final raw = widget.username.trim();
    if (raw.startsWith('@')) return raw;
    return '@$raw';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;

    final backgroundColor = palette.surface;
    final onSurfaceColor = palette.onSurface;
    final secondaryColor = palette.subtext;
    final brandColor = palette.primary;

    const double qrSize = 200.0;

    final String? effectiveAvatarUrl = _effectiveAvatarUrl;
    final ImageProvider? resolvedAvatarProvider =
        avatarImageProvider(effectiveAvatarUrl, maxDecodeDimension: 256);
    final ImageProvider avatarImage = _bakedAvatarBytes != null
        ? MemoryImage(_bakedAvatarBytes!)
        : (resolvedAvatarProvider ??
            (_fallbackAvatarBytes != null
                ? MemoryImage(_fallbackAvatarBytes!)
                : MemoryImage(_transparentPixelBytes)));

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _restoreBrightness();
        }
      },
      child: Dialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Заголовок
              Row(
                children: [
                  Expanded(
                    child: Text(
                      () {
                        try {
                          final tr = context.l10n.translate('profile_qr_code');
                          if (tr.isNotEmpty && tr != 'profile_qr_code') {
                            return tr;
                          }
                        } catch (_) {}
                        return 'QR-код';
                      }(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: onSurfaceColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: secondaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // QR-код со сглаживанием и круглой аватаркой прямо в центре (без рамочки)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: qrSize,
                  height: qrSize,
                  child: PrettyQrView.data(
                    data: _profileUrl,
                    errorCorrectLevel: QrErrorCorrectLevel.H,
                    decoration: PrettyQrDecoration(
                      shape: const PrettyQrSmoothSymbol(
                        color: Color(0xFF1C1C1E),
                      ),
                      image: PrettyQrDecorationImage(
                        image: avatarImage,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                        position: PrettyQrDecorationImagePosition.embedded,
                        clipper: const PrettyQrCircleClipper(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Имя пользователя (если задано)
              if (_effectiveDisplayName.isNotEmpty) ...[
                Text(
                  _effectiveDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: secondaryColor,
                  ),
                ),
                const SizedBox(height: 4),
              ],

              // Крупный никнейм пользователя "@...", не превышающий ширину QR-кода
              SizedBox(
                width: qrSize,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    _formattedUsername,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: brandColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Подсказка
              Text(
                widget.scanHintLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
