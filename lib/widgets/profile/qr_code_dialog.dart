import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/image_utils.dart';

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
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
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
  Uint8List? _fallbackAvatarBytes;

  @override
  void initState() {
    super.initState();
    _setMaxBrightness();
    _initFallbackAvatar();
  }

  void _initFallbackAvatar() {
    if (widget.avatarUrl == null || widget.avatarUrl!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final bytes = await _createInitialsAvatarBytes(widget.displayName, isDark: isDark);
        if (mounted) {
          setState(() {
            _fallbackAvatarBytes = bytes;
          });
        }
      });
    }
  }

  @override
  void dispose() {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final onSurfaceColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E);
    final secondaryColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF3C3C43);
    const brandColor = Color(0xFF0088CC);

    const double qrSize = 200.0;

    final ImageProvider? resolvedAvatarProvider = avatarImageProvider(widget.avatarUrl);
    final ImageProvider avatarImage = resolvedAvatarProvider ??
        (_fallbackAvatarBytes != null
            ? MemoryImage(_fallbackAvatarBytes!)
            : MemoryImage(_transparentPixelBytes));

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
                        position: PrettyQrDecorationImagePosition.embedded,
                        clipper: const PrettyQrCircleClipper(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Имя пользователя (если задано)
              if (widget.displayName.isNotEmpty) ...[
                Text(
                  widget.displayName,
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
                    style: const TextStyle(
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
