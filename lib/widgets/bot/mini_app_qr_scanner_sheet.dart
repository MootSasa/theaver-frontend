import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Opens a dual-mode Liquid-Glass-safe QR scanner sheet for Mini Apps
/// (`Telegram.WebApp.showScanQrPopup`), returning the scanned or manually
/// entered QR payload string, or `null` if cancelled.
Future<String?> showMiniAppQrScannerSheet(
  BuildContext context, {
  String? title,
  String? hintText,
}) {
  final effectiveTitle =
      (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : 'Сканирование QR-кода';
  return showTheavModalSheet<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    title: effectiveTitle,
    showCloseButton: true,
    maxHeightFactor: 0.88,
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
    builder: (_) => MiniAppQrScannerSheet(hintText: hintText),
  );
}

/// Interactive QR scanner sheet featuring a live [CameraPreview] when a camera
/// is available, a graceful fallback banner on headless/test/no-camera setups,
/// a clipboard paste helper, and manual QR text submission.
class MiniAppQrScannerSheet extends StatefulWidget {
  final String? hintText;

  const MiniAppQrScannerSheet({
    super.key,
    this.hintText,
  });

  @override
  State<MiniAppQrScannerSheet> createState() => _MiniAppQrScannerSheetState();
}

class _MiniAppQrScannerSheetState extends State<MiniAppQrScannerSheet> {
  final TextEditingController _manualController = TextEditingController();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  bool _isInitializingCamera = true;
  bool _cameraUnavailable = false;
  bool _torchEnabled = false;
  bool _disposed = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
  }

  @override
  void dispose() {
    _disposed = true;
    _manualController.dispose();
    final ctrl = _cameraController;
    _cameraController = null;
    if (ctrl != null) {
      unawaited(ctrl.dispose());
    }
    super.dispose();
  }

  bool get _isCameraPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows;
  }

  Future<void> _initCamera({int? preferredIndex}) async {
    if (_disposed) return;
    if (!_isCameraPlatformSupported) {
      if (mounted) {
        setState(() {
          _isInitializingCamera = false;
          _cameraUnavailable = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isInitializingCamera = true;
        _cameraUnavailable = false;
      });
    }

    CameraController? nextController;
    try {
      final cameras = await availableCameras();
      if (_disposed || !mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _cameras = const [];
          _isInitializingCamera = false;
          _cameraUnavailable = true;
        });
        return;
      }

      int targetIdx = preferredIndex ??
          cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
          );
      if (targetIdx < 0 || targetIdx >= cameras.length) {
        targetIdx = 0;
      }

      nextController = CameraController(
        cameras[targetIdx],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await nextController.initialize();
      if (_disposed || !mounted) {
        await nextController.dispose();
        return;
      }

      final previousController = _cameraController;
      _cameraController = null;
      if (previousController != null) {
        await previousController.dispose();
        if (_disposed || !mounted) {
          await nextController.dispose();
          return;
        }
      }

      setState(() {
        _cameras = cameras;
        _selectedCameraIndex = targetIdx;
        _cameraController = nextController;
        _isInitializingCamera = false;
        _cameraUnavailable = false;
        _torchEnabled = false;
      });
    } catch (_) {
      if (nextController != null) {
        unawaited(nextController.dispose());
      }
      if (!_disposed && mounted) {
        setState(() {
          _isInitializingCamera = false;
          _cameraUnavailable = true;
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isInitializingCamera) return;
    HapticUtils.selection();
    final nextIdx = (_selectedCameraIndex + 1) % _cameras.length;
    await _initCamera(preferredIndex: nextIdx);
  }

  Future<void> _toggleTorch() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final next = !_torchEnabled;
    try {
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!_disposed && mounted) {
        HapticUtils.selection();
        setState(() => _torchEnabled = next);
      }
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = clip?.text?.trim() ?? '';
      if (text.isEmpty) {
        setState(() => _validationError = 'Буфер обмена пуст');
        return;
      }
      HapticUtils.selection();
      _manualController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      setState(() => _validationError = null);
    } catch (_) {
      if (mounted) {
        setState(() => _validationError = 'Не удалось прочитать буфер обмена');
      }
    }
  }

  void _submitManualCode() {
    final value = _manualController.text.trim();
    if (value.isEmpty) {
      HapticUtils.selection();
      setState(() => _validationError = 'Введите или вставьте данные QR-кода');
      return;
    }
    HapticUtils.tap();
    Navigator.of(context).pop(value);
  }

  Widget _buildCameraViewport(TheavSurfaceStyle style) {
    final palette = style.palette;
    final ctrl = _cameraController;
    final bool hasLiveCamera = ctrl != null && ctrl.value.isInitialized;

    return Container(
      key: const ValueKey('mini_app_qr_camera_viewport'),
      height: 210,
      decoration: BoxDecoration(
        color: style.isDark
            ? Colors.black.withValues(alpha: 0.42)
            : palette.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: style.hairlineBorder,
          width: 0.6,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasLiveCamera) ...[
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctrl.value.previewSize?.height ?? 240,
                  height: ctrl.value.previewSize?.width ?? 320,
                  child: CameraPreview(ctrl),
                ),
              ),
              Center(
                child: Container(
                  width: 146,
                  height: 146,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.9),
                      width: 2.2,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ViewportActionBadge(
                      icon: Icon(
                        _torchEnabled
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        size: 18,
                        color: _torchEnabled ? palette.primary : Colors.white,
                      ),
                      tooltip: 'Подсветка',
                      onTap: _toggleTorch,
                    ),
                    if (_cameras.length > 1) ...[
                      const SizedBox(width: 8),
                      _ViewportActionBadge(
                        icon: const iconoir.Camera(
                          width: 18,
                          height: 18,
                          color: Colors.white,
                        ),
                        tooltip: 'Сменить камеру',
                        onTap: _switchCamera,
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (_isInitializingCamera)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Подключение камеры...',
                      style: TextStyle(
                        color: palette.subtext,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                key: const ValueKey('mini_app_qr_camera_fallback'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: iconoir.QrCode(
                            width: 24,
                            height: 24,
                            color: palette.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _cameraUnavailable
                            ? 'Камера недоступна в текущем окружении'
                            : 'Наведите камеру на QR-код',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Вы можете вставить содержимое QR-кода из буфера или ввести его вручную ниже.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.subtext,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      if (_isCameraPlatformSupported) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () => _initCamera(),
                          icon: iconoir.RefreshDouble(
                            width: 15,
                            height: 15,
                            color: palette.primary,
                          ),
                          label: Text(
                            'Повторить',
                            style: TextStyle(
                              color: palette.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final hint = widget.hintText?.trim() ?? '';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint.isNotEmpty) ...[
            Text(
              hint,
              style: TextStyle(
                color: palette.subtext,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _buildCameraViewport(style),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            children: [
              TheavInlineTextField(
                key: const ValueKey('mini_app_qr_manual_input'),
                controller: _manualController,
                placeholder: 'Содержимое QR-кода (URL, токен, текст)...',
                textInputAction: TextInputAction.done,
                prefix: iconoir.QrCode(
                  width: 18,
                  height: 18,
                  color: palette.subtext,
                ),
                suffix: _manualController.text.isNotEmpty
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _manualController.clear();
                          setState(() => _validationError = null);
                        },
                        child: iconoir.Xmark(
                          width: 16,
                          height: 16,
                          color: palette.subtext,
                        ),
                      )
                    : null,
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  } else {
                    setState(() {});
                  }
                },
                onSubmitted: (_) => _submitManualCode(),
              ),
              TheavListRow(
                key: const ValueKey('mini_app_qr_paste_button'),
                leading: iconoir.PasteClipboard(
                  width: 19,
                  height: 19,
                  color: palette.primary,
                ),
                title: 'Вставить из буфера обмена',
                showChevron: false,
                onTap: _pasteFromClipboard,
              ),
            ],
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _validationError!,
                style: TextStyle(
                  color: palette.error,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TheavFloatingPillButton(
                  key: const ValueKey('mini_app_qr_cancel_button'),
                  label: 'Отмена',
                  isPrimary: false,
                  onTap: () => Navigator.of(context).pop(null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TheavFloatingPillButton(
                  key: const ValueKey('mini_app_qr_submit_button'),
                  label: 'Отправить код',
                  isPrimary: true,
                  onTap: _submitManualCode,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewportActionBadge extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ViewportActionBadge({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.48),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
