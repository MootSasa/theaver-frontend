import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../models/theav_theme.dart';
import '../../services/glass_toast_service.dart';
import '../../services/sticker_service.dart';
import '../../utils/avatar_studio_renderer.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../chat/sticker_item_widget.dart';
import '../design_system/theav_design_system.dart';
import 'avatar_crop_canvas.dart';
import 'avatar_rotation_dial.dart';

/// Full-screen dark photo & avatar studio supporting crop, rotation,
/// color grading presets, stickers/emojis, text capsules, and markup brushes.
class TheavAvatarEditorScreen extends StatefulWidget {
  final Uint8List? initialBytes;
  final String? initialFilePath;
  final String fileName;
  final AvatarShapeMask maskShape;
  final AvatarEditorCtaMode ctaMode;
  final String? subjectName;
  final AvatarCropAspectMode? initialAspectMode;
  final bool isFromConstructor;

  const TheavAvatarEditorScreen({
    super.key,
    this.initialBytes,
    this.initialFilePath,
    this.fileName = 'avatar.jpg',
    this.maskShape = AvatarShapeMask.circle,
    this.ctaMode = AvatarEditorCtaMode.done,
    this.subjectName,
    this.initialAspectMode,
    this.isFromConstructor = false,
  }) : assert(initialBytes != null || initialFilePath != null);

  /// Pushes [TheavAvatarEditorScreen] via [SwipeBackPageRoute] and returns the
  /// rendered [AvatarPickResult], or `null` if cancelled.
  static Future<AvatarPickResult?> open({
    required BuildContext context,
    Uint8List? initialBytes,
    String? initialFilePath,
    String fileName = 'avatar.jpg',
    AvatarShapeMask maskShape = AvatarShapeMask.circle,
    AvatarEditorCtaMode ctaMode = AvatarEditorCtaMode.done,
    String? subjectName,
    AvatarCropAspectMode? initialAspectMode,
    bool isFromConstructor = false,
  }) {
    return Navigator.of(context).push<AvatarPickResult>(
      SwipeBackPageRoute<AvatarPickResult>(
        builder: (_) => TheavAvatarEditorScreen(
          initialBytes: initialBytes,
          initialFilePath: initialFilePath,
          fileName: fileName,
          maskShape: maskShape,
          ctaMode: ctaMode,
          subjectName: subjectName,
          initialAspectMode: initialAspectMode,
          isFromConstructor: isFromConstructor,
        ),
      ),
    );
  }

  @override
  State<TheavAvatarEditorScreen> createState() =>
      _TheavAvatarEditorScreenState();
}

class _TheavAvatarEditorScreenState extends State<TheavAvatarEditorScreen> {
  static const Color _studioBackground = Color(0xFF090B10);
  static const int _maxHistoryLength = 40;

  static const List<String> _quickEmojis = <String>[
    '😎', '🔥', '❤️', '✨', '🎉', '🚀', '🐱', '👑', '💎', '⚡', '🌈', '🎧',
  ];

  static const List<String> _pickerEmojis = <String>[
    '😀', '😎', '🥳', '🤩', '😇', '😈', '🤠', '🥸',
    '🤯', '🥹', '😂', '🥰', '😘', '🤗', '🤔', '🤫',
    '🔥', '✨', '⚡', '💥', '💫', '🌈', '🌟', '💎',
    '❤️', '🩷', '💜', '💙', '💚', '🖤', '👑', '🏆',
    '🎉', '🎊', '🎈', '🎁', '🚀', '🛸', '🌙', '☀️',
    '🐱', '🐶', '🦊', '🐼', '🐯', '🦁', '🐸', '🦋',
    '🌸', '🌺', '🍀', '🍕', '🍓', '☕', '🎧', '🎮',
  ];

  static const List<Color> _paletteColors = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF111318),
    Color(0xFF38BDF8),
    Color(0xFF2563EB),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
  ];

  static const List<double> _brushWidths = <double>[0.010, 0.020, 0.036];

  Uint8List? _sourceBytes;
  ui.Image? _decodedImage;
  bool _isLoadingSource = true;
  bool _isExporting = false;
  String? _loadError;

  late AvatarCropAspectMode _baselineAspectMode;
  late AvatarStudioState _state;
  AvatarStudioState? _lastCommittedState;
  final List<AvatarStudioState> _undoStack = <AvatarStudioState>[];
  final List<AvatarStudioState> _redoStack = <AvatarStudioState>[];

  AvatarEditorTab _activeTab = AvatarEditorTab.crop;
  AvatarAdjustmentAttribute _selectedAttr = AvatarAdjustmentAttribute.exposure;
  AvatarBrushStyle _brushStyle = AvatarBrushStyle.pen;
  Color _brushColor = const Color(0xFF38BDF8);
  double _brushWidthFraction = 0.020;

  String? _selectedLayerId;
  bool _isAdjustingSlider = false;
  int _layerSeq = 0;

  bool get _hasUnsavedChanges =>
      _state.aspectMode != _baselineAspectMode ||
      !_state.isGeometryIdentity ||
      !_state.adjustments.isIdentity ||
      _state.strokes.isNotEmpty ||
      _state.stickers.isNotEmpty ||
      _state.textLayers.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _baselineAspectMode =
        widget.initialAspectMode ?? AvatarCropAspectMode.square1x1;
    _state = AvatarStudioState(aspectMode: _baselineAspectMode);
    _lastCommittedState = _state;
    _loadSourceMedia();
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    _decodedImage = null;
    super.dispose();
  }

  Future<void> _loadSourceMedia() async {
    try {
      Uint8List? bytes = widget.initialBytes;
      if (bytes == null && widget.initialFilePath != null && !kIsWeb) {
        final File f = File(widget.initialFilePath!);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoadingSource = false;
          _loadError = 'Failed to load image';
        });
        return;
      }

      final ui.Image decoded = await AvatarStudioRenderer.decodeImage(bytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }

      final AvatarCropAspectMode effectiveStartAspect =
          widget.initialAspectMode ??
              (widget.isFromConstructor
                  ? AvatarCropAspectMode.square1x1
                  : AvatarCropAspectMode.original);

      setState(() {
        _sourceBytes = bytes;
        _decodedImage = decoded;
        _baselineAspectMode = effectiveStartAspect;
        _state = AvatarStudioState(aspectMode: effectiveStartAspect);
        _lastCommittedState = _state;
        _isLoadingSource = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSource = false;
        _loadError = e.toString();
      });
    }
  }

  void _updateLiveState(AvatarStudioState next) {
    setState(() => _state = next);
  }

  void _commitHistory(AvatarStudioState next) {
    final AvatarStudioState? prev = _lastCommittedState;
    if (prev != null && prev == next) {
      if (_state != next) {
        setState(() => _state = next);
      }
      return;
    }
    setState(() {
      if (prev != null) {
        _undoStack.add(prev);
        if (_undoStack.length > _maxHistoryLength) {
          _undoStack.removeAt(0);
        }
      }
      _redoStack.clear();
      _state = next;
      _lastCommittedState = next;
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    HapticUtils.selection();
    setState(() {
      _redoStack.add(_state);
      _state = _undoStack.removeLast();
      _lastCommittedState = _state;
      _selectedLayerId = null;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    HapticUtils.selection();
    setState(() {
      _undoStack.add(_state);
      _state = _redoStack.removeLast();
      _lastCommittedState = _state;
      _selectedLayerId = null;
    });
  }

  void _resetAll() {
    if (!_hasUnsavedChanges) return;
    HapticUtils.selection();
    _commitHistory(
      _state.resetAll(aspectMode: _baselineAspectMode),
    );
    setState(() => _selectedLayerId = null);
  }

  void _setAspectMode(AvatarCropAspectMode mode) {
    if (_state.aspectMode == mode) return;
    HapticUtils.selection();
    final ui.Image? img = _decodedImage;
    Rect nextFreeRect = AvatarStudioState.fullRect;
    if (img != null && mode != AvatarCropAspectMode.square1x1) {
      final Size rot = AvatarStudioGeometry.rotatedImageSize(
        Size(img.width.toDouble(), img.height.toDouble()),
        _state.quarterTurns,
      );
      nextFreeRect =
          AvatarStudioGeometry.defaultOriginalNormRect(rot.width, rot.height);
    }

    AvatarStudioState next = _state.copyWith(
      aspectMode: mode,
      freeRectNormalized: nextFreeRect,
    );
    if (img != null) {
      final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
      final Rect norm = AvatarStudioGeometry.effectiveCropNormRect(next, rawSize);
      final Offset clamped = AvatarStudioGeometry.clampPanOffset(
        panOffset: next.panOffset,
        stageSide: 1.0,
        cropSize: norm.size,
        rawImageSize: rawSize,
        state: next,
      );
      final Offset clampedMini = AvatarStudioGeometry.clampMiniCenterNorm(
        next,
        norm.size,
      );
      next = next.copyWith(
        panOffset: clamped,
        miniCenterNorm: clampedMini,
      );
    }
    _commitHistory(next);
  }

  void _rotateMinus90() {
    final ui.Image? img = _decodedImage;
    HapticUtils.selection();
    final int nextTurns = ((_state.quarterTurns - 1) % 4 + 4) % 4;
    Rect nextFreeRect = _state.freeRectNormalized;
    if (img != null && _state.aspectMode != AvatarCropAspectMode.square1x1) {
      final Size rot = AvatarStudioGeometry.rotatedImageSize(
        Size(img.width.toDouble(), img.height.toDouble()),
        nextTurns,
      );
      nextFreeRect =
          AvatarStudioGeometry.defaultOriginalNormRect(rot.width, rot.height);
    }
    AvatarStudioState next = _state.copyWith(
      quarterTurns: nextTurns,
      freeRectNormalized: nextFreeRect,
      panOffset: Offset.zero,
    );
    if (img != null) {
      final Size rawSize = Size(img.width.toDouble(), img.height.toDouble());
      final Rect norm = AvatarStudioGeometry.effectiveCropNormRect(next, rawSize);
      next = next.copyWith(
        miniCenterNorm:
            AvatarStudioGeometry.clampMiniCenterNorm(next, norm.size),
      );
    }
    _commitHistory(next);
  }

  void _toggleFlipHorizontal() {
    HapticUtils.selection();
    final AvatarStudioState next = _state.copyWith(
      flipHorizontal: !_state.flipHorizontal,
    );
    _commitHistory(next);
  }

  Future<void> _handleClose() async {
    if (_isExporting) return;
    if (!_hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop(null);
      return;
    }

    final bool? discard = await showTheavDialog<bool>(
      context: context,
      title: context.trOr(
        'avatar_editor_discard_title',
        'Отменить изменения?',
      ),
      message: context.trOr(
        'avatar_editor_discard_message',
        'Несохранённые правки будут потеряны.',
      ),
      actions: [
        TheavDialogAction<bool>(
          label: context.trOr('avatar_editor_keep_editing', 'Остаться'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: context.trOr('avatar_editor_discard_confirm', 'Сбросить'),
          result: true,
          isDestructive: true,
        ),
      ],
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop(null);
    }
  }

  Future<void> _exportAndFinish() async {
    if (_isExporting || _sourceBytes == null) return;
    HapticUtils.tap();
    setState(() => _isExporting = true);
    try {
      final rendered = await AvatarStudioRenderer.renderEditedAvatar(
        sourceBytes: _sourceBytes!,
        sourceFileName: widget.fileName,
        state: _state,
        textDirection: Directionality.of(context),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        AvatarPickResult(
          file: rendered.file,
          bytes: rendered.bytes,
          fileName: rendered.fileName,
          maskShape: widget.maskShape,
          aspectMode: _state.aspectMode,
          isFromConstructor: widget.isFromConstructor,
          miniCrop: rendered.miniCrop,
          previewBytes: rendered.previewBytes,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      GlassToastService().showError(
        context,
        context.trOr('avatar_editor_export_error', 'Не удалось сохранить фото'),
      );
    }
  }

  void _addEmojiSticker(String emoji) {
    HapticUtils.selection();
    final String id =
        'st_${++_layerSeq}_${DateTime.now().microsecondsSinceEpoch}';
    final layer = AvatarStickerLayer(id: id, emoji: emoji);
    _commitHistory(
      _state.copyWith(
        stickers: <AvatarStickerLayer>[..._state.stickers, layer],
      ),
    );
    setState(() => _selectedLayerId = id);
  }

  void _addCustomSticker(StickerItem item) {
    HapticUtils.selection();
    final String id =
        'st_${++_layerSeq}_${DateTime.now().microsecondsSinceEpoch}';
    final layer = AvatarStickerLayer(
      id: id,
      stickerUrl: item.fileUrl,
      stickerFormat: item.format,
    );
    _commitHistory(
      _state.copyWith(
        stickers: <AvatarStickerLayer>[..._state.stickers, layer],
      ),
    );
    setState(() => _selectedLayerId = id);
  }

  void _deleteSelectedLayer() {
    final String? id = _selectedLayerId;
    if (id == null) return;
    HapticUtils.heavy();
    final next = _state.copyWith(
      stickers: _state.stickers.where((s) => s.id != id).toList(),
      textLayers: _state.textLayers.where((t) => t.id != id).toList(),
    );
    _commitHistory(next);
    setState(() => _selectedLayerId = null);
  }

  Future<void> _openStickerPickerSheet() async {
    if (!mounted) return;
    await showTheavModalSheet<void>(
      context: context,
      title: context.trOr('avatar_editor_stickers', 'Стикеры'),
      showCloseButton: true,
      maxHeightFactor: 0.72,
      builder: (BuildContext sheetCtx) {
        return _AvatarStickerChooserContent(
          emojis: _pickerEmojis,
          onSelectEmoji: (emoji) {
            Navigator.of(sheetCtx).pop();
            _addEmojiSticker(emoji);
          },
          onSelectSticker: (sticker) {
            Navigator.of(sheetCtx).pop();
            _addCustomSticker(sticker);
          },
        );
      },
    );
  }

  Future<void> _openTextEditorDialog({AvatarTextLayer? existing}) async {
    String draftText = existing?.text ?? '';
    Color textColor = existing?.color ?? Colors.white;
    AvatarTextBackgroundMode bgMode =
        existing?.backgroundMode ?? AvatarTextBackgroundMode.solid;
    bool bold = existing?.bold ?? true;

    final bool? saved = await showTheavDialog<bool>(
      context: context,
      title: context.trOr('avatar_editor_text', 'Текст'),
      content: _AvatarTextLayerDialogContent(
        initialText: draftText,
        initialColor: textColor,
        initialBgMode: bgMode,
        initialBold: bold,
        paletteColors: _paletteColors,
        onChanged: (t, c, mode, isBold) {
          draftText = t;
          textColor = c;
          bgMode = mode;
          bold = isBold;
        },
      ),
      actions: [
        TheavDialogAction<bool>(
          label: context.trOr('profile_cancel', 'Отмена'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: context.trOr('avatar_editor_done', 'Готово'),
          result: true,
          isPrimary: true,
        ),
      ],
    );

    final String text = draftText.trim();
    if (saved != true || text.isEmpty || !mounted) return;

    if (existing != null) {
      final updated = _state.textLayers.map((t) {
        if (t.id != existing.id) return t;
        return t.copyWith(
          text: text,
          color: textColor,
          backgroundMode: bgMode,
          bold: bold,
        );
      }).toList();
      _commitHistory(_state.copyWith(textLayers: updated));
    } else {
      final String id =
          'txt_${++_layerSeq}_${DateTime.now().microsecondsSinceEpoch}';
      final created = AvatarTextLayer(
        id: id,
        text: text,
        color: textColor,
        backgroundMode: bgMode,
        bold: bold,
      );
      _commitHistory(
        _state.copyWith(
          textLayers: <AvatarTextLayer>[..._state.textLayers, created],
        ),
      );
      setState(() => _selectedLayerId = id);
    }
  }

  ThemeData _buildStudioTheme(BuildContext context) {
    final TheavPalette callerPalette = context.theav;
    final Color primary = callerPalette.primary.computeLuminance() > 0.15
        ? callerPalette.primary
        : const Color(0xFF38BDF8);
    final TheavPalette darkPalette = TheavPalette(
      primary: primary,
      onPrimary: primary.computeLuminance() > 0.55 ? Colors.black : Colors.white,
      background: _studioBackground,
      surface: const Color(0xFF151923),
      onSurface: Colors.white,
      appBarBackground: const Color(0xFF181D28),
      appBarForeground: Colors.white,
      chatBubbleOutgoing: primary,
      chatBubbleOutgoingText: Colors.white,
      chatBubbleOutgoingSubtext: Colors.white70,
      chatBubbleIncoming: const Color(0xFF1D2230),
      chatBubbleIncomingText: Colors.white,
      chatBubbleIncomingSubtext: Colors.white60,
      chatDateBadge: const Color(0x66000000),
      chatDateBadgeText: Colors.white,
      subtext: Colors.white.withValues(alpha: 0.65),
      divider: Colors.white.withValues(alpha: 0.12),
      error: const Color(0xFFFF453A),
    );
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: _studioBackground,
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: darkPalette.onPrimary,
        surface: darkPalette.surface,
        onSurface: Colors.white,
      ),
      extensions: <ThemeExtension<dynamic>>[
        TheavThemeExtension(
          palette: darkPalette,
          wallpaper: const TheavWallpaper(),
          bubbleRadius: 16.0,
        ),
      ],
    );
  }

  String _ctaLabel(BuildContext context) {
    switch (widget.ctaMode) {
      case AvatarEditorCtaMode.done:
        return context.trOr('avatar_editor_done', 'Готово');
      case AvatarEditorCtaMode.setPhoto:
        final String? name = widget.subjectName?.trim();
        if (name != null && name.isNotEmpty) {
          return context.trOr(
            'avatar_editor_set_photo_for',
            'Установить фото для {name}',
            <String, String>{'name': name},
          );
        }
        return context.trOr('avatar_editor_set_photo', 'Установить фото');
      case AvatarEditorCtaMode.suggestPhoto:
        return context.trOr(
          'avatar_editor_suggest_photo',
          'Предложить фото',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData studioTheme = _buildStudioTheme(context);

    return Theme(
      data: studioTheme,
      child: Builder(
        builder: (BuildContext themedCtx) {
          return PopScope(
            canPop: !_hasUnsavedChanges && !_isExporting,
            onPopInvokedWithResult: (bool didPop, _) {
              if (!didPop) {
                _handleClose();
              }
            },
            child: SwipeBackPopScope(
              swipeBackEnabled: !_hasUnsavedChanges && !_isExporting,
              onSwipeBackPop: _handleClose,
              child: Scaffold(
                backgroundColor: _studioBackground,
                body: _buildBody(themedCtx),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bool isWide = mq.size.width >= 640;
    final double topHudPad = mq.padding.top + (isWide ? 64.0 : 112.0);
    final double bottomHudPad =
        math.min(mq.size.height * 0.44, mq.padding.bottom + 264.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_isLoadingSource)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          )
        else if (_loadError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _loadError!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          AvatarCropCanvas(
            image: _decodedImage,
            state: _state,
            maskShape: widget.maskShape,
            activeTab: _activeTab,
            activeBrushStyle: _brushStyle,
            activeBrushColor: _brushColor,
            activeBrushWidthFraction: _brushWidthFraction,
            selectedLayerId: _selectedLayerId,
            viewportPadding: EdgeInsets.fromLTRB(
              18,
              topHudPad,
              18,
              bottomHudPad,
            ),
            forceShowThirdsGrid: _isAdjustingSlider,
            onStateChanged: _updateLiveState,
            onCommitHistory: _commitHistory,
            onSelectLayer: (id) => setState(() => _selectedLayerId = id),
            onEditTextLayer: (layer) => _openTextEditorDialog(existing: layer),
          ),

        // Top Floating HUD
        Positioned(
          top: mq.padding.top + 8.0,
          left: 12,
          right: 12,
          child: _buildTopHud(context, isWide: isWide),
        ),

        // Bottom Floating HUD
        Positioned(
          left: 12,
          right: 12,
          bottom: mq.padding.bottom + 10.0,
          child: _buildBottomHud(context),
        ),
      ],
    );
  }

  Widget _buildTopHud(BuildContext context, {required bool isWide}) {
    final bool glass = TheavSurfaceStyle.of(context).isGlass;

    final Widget closeBtn = TheavHeaderIconButton(
      key: const ValueKey<String>('avatar_editor_close_btn'),
      size: 40,
      tooltip: context.trOr('profile_cancel', 'Закрыть'),
      icon: const iconoir.Xmark(width: 20, height: 20, color: Colors.white),
      onTap: _handleClose,
    );

    final Widget historyPill = TheavFloatingSurface(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey<String>('avatar_editor_undo_btn'),
              visualDensity: VisualDensity.compact,
              onPressed: _undoStack.isNotEmpty ? _undo : null,
              icon: iconoir.Undo(
                width: 18,
                height: 18,
                color: _undoStack.isNotEmpty
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.30),
              ),
            ),
            IconButton(
              key: const ValueKey<String>('avatar_editor_redo_btn'),
              visualDensity: VisualDensity.compact,
              onPressed: _redoStack.isNotEmpty ? _redo : null,
              icon: iconoir.Redo(
                width: 18,
                height: 18,
                color: _redoStack.isNotEmpty
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.30),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('avatar_editor_reset_btn'),
              onPressed: _hasUnsavedChanges ? _resetAll : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
              ),
              child: Text(
                context.trOr('avatar_editor_reset', 'Сбросить'),
                style: TextStyle(
                  color: _hasUnsavedChanges
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final Widget aspectPill = TheavFloatingSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AspectChip(
            label: context.trOr('avatar_editor_aspect_square', '1:1'),
            selected: _state.aspectMode == AvatarCropAspectMode.square1x1,
            onTap: () => _setAspectMode(AvatarCropAspectMode.square1x1),
          ),
          _AspectChip(
            label:
                context.trOr('avatar_editor_aspect_original', 'Оригинал'),
            selected: _state.aspectMode == AvatarCropAspectMode.original,
            onTap: () => _setAspectMode(AvatarCropAspectMode.original),
          ),
          _AspectChip(
            label: context.trOr('avatar_editor_aspect_free', 'Свободно'),
            selected: _state.aspectMode == AvatarCropAspectMode.free,
            onTap: () => _setAspectMode(AvatarCropAspectMode.free),
          ),
        ],
      ),
    );

    final Widget content = isWide
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              closeBtn,
              historyPill,
              aspectPill,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  closeBtn,
                  historyPill,
                ],
              ),
              const SizedBox(height: 8),
              Center(child: aspectPill),
            ],
          );

    return glass ? LiquidGlassBatch(child: content) : content;
  }

  Widget _buildBottomHud(BuildContext context) {
    final bool glass = TheavSurfaceStyle.of(context).isGlass;
    final palette = context.theav;

    final Widget tabBar = TheavSegmentedControl<AvatarEditorTab>(
      height: 36,
      expand: true,
      selected: _activeTab,
      onChanged: (AvatarEditorTab tab) {
        setState(() {
          _activeTab = tab;
          if (tab == AvatarEditorTab.markup) {
            _selectedLayerId = null;
          }
        });
      },
      options: [
        TheavSegmentOption(
          value: AvatarEditorTab.crop,
          label: context.trOr('avatar_editor_crop', 'Обрезка'),
        ),
        TheavSegmentOption(
          value: AvatarEditorTab.adjust,
          label: context.trOr('avatar_editor_adjust', 'Коррекция'),
        ),
        TheavSegmentOption(
          value: AvatarEditorTab.stickers,
          label: context.trOr('avatar_editor_stickers', 'Стикеры'),
        ),
        TheavSegmentOption(
          value: AvatarEditorTab.markup,
          label: context.trOr('avatar_editor_markup', 'Рисунок'),
        ),
      ],
    );

    final Widget deck = TheavFloatingSurface(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: _buildTabControls(context, palette),
    );

    final Widget ctaRow = Row(
      children: [
        Expanded(
          child: TheavFloatingPillButton(
            key: const ValueKey<String>('avatar_editor_cta_btn'),
            height: 46,
            isPrimary: true,
            enabled: !_isLoadingSource && !_isExporting && _decodedImage != null,
            label: _ctaLabel(context),
            icon: _isExporting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: palette.onPrimary,
                    ),
                  )
                : iconoir.Check(
                    width: 18,
                    height: 18,
                    color: palette.onPrimary,
                  ),
            onTap: _exportAndFinish,
          ),
        ),
      ],
    );

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        deck,
        const SizedBox(height: 8),
        glass ? LiquidGlassBatch.exclude(child: tabBar) : tabBar,
        const SizedBox(height: 8),
        ctaRow,
      ],
    );

    return glass ? LiquidGlassBatch(child: column) : column;
  }

  Widget _buildTabControls(BuildContext context, TheavPalette palette) {
    switch (_activeTab) {
      case AvatarEditorTab.crop:
        return _buildCropTab(context, palette);
      case AvatarEditorTab.adjust:
        return _buildAdjustTab(context, palette);
      case AvatarEditorTab.stickers:
        return _buildStickersTab(context, palette);
      case AvatarEditorTab.markup:
        return _buildMarkupTab(context, palette);
    }
  }

  Widget _buildCropTab(BuildContext context, TheavPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvatarRotationDial(
          angleDegrees: _state.fineAngleDegrees,
          accentColor: palette.primary,
          onInteractionStart: () => setState(() => _isAdjustingSlider = true),
          onInteractionEnd: () {
            setState(() => _isAdjustingSlider = false);
            _commitHistory(_state);
          },
          onChanged: (double deg) {
            final ui.Image? img = _decodedImage;
            AvatarStudioState next = _state.copyWith(fineAngleDegrees: deg);
            if (img != null) {
              final Size rawSize =
                  Size(img.width.toDouble(), img.height.toDouble());
              final Rect norm =
                  AvatarStudioGeometry.effectiveCropNormRect(next, rawSize);
              final Offset clamped = AvatarStudioGeometry.clampPanOffset(
                panOffset: next.panOffset,
                stageSide: 1.0,
                cropSize: norm.size,
                rawImageSize: rawSize,
                state: next,
              );
              next = next.copyWith(panOffset: clamped);
            }
            _updateLiveState(next);
          },
        ),
        const SizedBox(height: 6),
        SwipeBackBlocker(
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                Text(
                  context.trOr('avatar_editor_circle_size', 'Кружок'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primary,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                      thumbColor: Colors.white,
                      trackHeight: 3.0,
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                    ),
                    child: Slider(
                      key: const ValueKey<String>(
                        'avatar_editor_mini_circle_slider',
                      ),
                      value: _state.miniSizeFrac.clamp(
                        AvatarStudioState.minMiniSizeFraction,
                        1.0,
                      ),
                      min: AvatarStudioState.minMiniSizeFraction,
                      max: 1.0,
                      onChanged: (double frac) {
                        final ui.Image? img = _decodedImage;
                        AvatarStudioState next =
                            _state.copyWith(miniSizeFrac: frac);
                        if (img != null) {
                          final Size rawSize = Size(
                            img.width.toDouble(),
                            img.height.toDouble(),
                          );
                          final Rect norm =
                              AvatarStudioGeometry.effectiveCropNormRect(
                            next,
                            rawSize,
                          );
                          next = next.copyWith(
                            miniCenterNorm:
                                AvatarStudioGeometry.clampMiniCenterNorm(
                              next,
                              norm.size,
                            ),
                          );
                        }
                        _updateLiveState(next);
                      },
                      onChangeEnd: (_) => _commitHistory(_state),
                    ),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(_state.miniSizeFrac * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StudioActionChip(
              icon: const iconoir.RotateCameraLeft(
                width: 17,
                height: 17,
                color: Colors.white,
              ),
              label: '-90°',
              onTap: _rotateMinus90,
            ),
            const SizedBox(width: 10),
            _StudioActionChip(
              icon: iconoir.Flip(
                width: 17,
                height: 17,
                color: _state.flipHorizontal ? palette.primary : Colors.white,
              ),
              label: context.trOr('avatar_editor_flip', 'Отразить'),
              selected: _state.flipHorizontal,
              accentColor: palette.primary,
              onTap: _toggleFlipHorizontal,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdjustTab(BuildContext context, TheavPalette palette) {
    final AvatarColorAdjustments adj = _state.adjustments;
    final (double minVal, double maxVal, double curVal) = switch (_selectedAttr) {
      AvatarAdjustmentAttribute.exposure => (-1.0, 1.0, adj.exposure),
      AvatarAdjustmentAttribute.contrast => (-1.0, 1.0, adj.contrast),
      AvatarAdjustmentAttribute.saturation => (-1.0, 1.0, adj.saturation),
      AvatarAdjustmentAttribute.warmth => (-1.0, 1.0, adj.warmth),
      AvatarAdjustmentAttribute.vignette => (0.0, 1.0, adj.vignette),
      AvatarAdjustmentAttribute.sharpen => (0.0, 1.0, adj.sharpen),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 8 Preset Filter Chips
        SwipeBackBlocker(
          child: SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AvatarFilterPreset.presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, int index) {
                final AvatarFilterPreset preset =
                    AvatarFilterPreset.presets[index];
                final bool active = adj.presetId == preset.id;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticUtils.selection();
                    _commitHistory(
                      _state.copyWith(adjustments: preset.adjustments),
                    );
                  },
                  child: SizedBox(
                    width: 58,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: active
                                  ? palette.primary
                                  : Colors.white.withValues(alpha: 0.22),
                              width: active ? 2.0 : 0.8,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _decodedImage != null
                              ? ColorFiltered(
                                  colorFilter: ColorFilter.matrix(
                                    preset.adjustments.toColorMatrix(),
                                  ),
                                  child: RawImage(
                                    image: _decodedImage,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Container(color: Colors.white12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.trOr(preset.labelKey, preset.fallbackLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active
                                ? palette.primary
                                : Colors.white.withValues(alpha: 0.78),
                            fontSize: 10.5,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Attribute selector chips
        SwipeBackBlocker(
          child: SizedBox(
            height: 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AvatarAdjustmentAttribute.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, int i) {
                final attr = AvatarAdjustmentAttribute.values[i];
                final bool selected = _selectedAttr == attr;
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _selectedAttr = attr);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? palette.primary.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? palette.primary.withValues(alpha: 0.65)
                            : Colors.white.withValues(alpha: 0.14),
                        width: 0.6,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _attrLabel(context, attr),
                      style: TextStyle(
                        color: selected ? palette.primary : Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        SwipeBackBlocker(
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: palette.primary,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                    thumbColor: Colors.white,
                    trackHeight: 3.5,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: curVal.clamp(minVal, maxVal),
                    min: minVal,
                    max: maxVal,
                    onChanged: (double v) {
                      final AvatarColorAdjustments nextAdj = switch (_selectedAttr) {
                        AvatarAdjustmentAttribute.exposure =>
                          adj.copyWith(exposure: v, presetId: 'custom'),
                        AvatarAdjustmentAttribute.contrast =>
                          adj.copyWith(contrast: v, presetId: 'custom'),
                        AvatarAdjustmentAttribute.saturation =>
                          adj.copyWith(saturation: v, presetId: 'custom'),
                        AvatarAdjustmentAttribute.warmth =>
                          adj.copyWith(warmth: v, presetId: 'custom'),
                        AvatarAdjustmentAttribute.vignette =>
                          adj.copyWith(vignette: v, presetId: 'custom'),
                        AvatarAdjustmentAttribute.sharpen =>
                          adj.copyWith(sharpen: v, presetId: 'custom'),
                      };
                      _updateLiveState(_state.copyWith(adjustments: nextAdj));
                    },
                    onChangeEnd: (_) => _commitHistory(_state),
                  ),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '${(curVal * 100).round()}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _attrLabel(BuildContext context, AvatarAdjustmentAttribute attr) {
    switch (attr) {
      case AvatarAdjustmentAttribute.exposure:
        return context.trOr('avatar_editor_exposure', 'Экспозиция');
      case AvatarAdjustmentAttribute.contrast:
        return context.trOr('avatar_editor_contrast', 'Контраст');
      case AvatarAdjustmentAttribute.saturation:
        return context.trOr('avatar_editor_saturation', 'Насыщенность');
      case AvatarAdjustmentAttribute.warmth:
        return context.trOr('avatar_editor_warmth', 'Теплота');
      case AvatarAdjustmentAttribute.vignette:
        return context.trOr('avatar_editor_vignette', 'Виньетка');
      case AvatarAdjustmentAttribute.sharpen:
        return context.trOr('avatar_editor_sharpen', 'Резкость');
    }
  }

  Widget _buildStickersTab(BuildContext context, TheavPalette palette) {
    final AvatarTextLayer? selectedText = _selectedLayerId == null
        ? null
        : _state.textLayers
            .where((t) => t.id == _selectedLayerId)
            .firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _StudioActionChip(
                icon: const iconoir.Emoji(
                  width: 17,
                  height: 17,
                  color: Colors.white,
                ),
                label: context.trOr(
                  'avatar_editor_add_sticker',
                  'Стикер / Эмодзи',
                ),
                onTap: _openStickerPickerSheet,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StudioActionChip(
                icon: const iconoir.Text(
                  width: 17,
                  height: 17,
                  color: Colors.white,
                ),
                label: context.trOr('avatar_editor_add_text', 'Добавить текст'),
                onTap: () => _openTextEditorDialog(),
              ),
            ),
            if (_selectedLayerId != null) ...[
              const SizedBox(width: 8),
              if (selectedText != null) ...[
                _StudioActionChip(
                  icon: const iconoir.EditPencil(
                    width: 16,
                    height: 16,
                    color: Colors.white,
                  ),
                  label: '',
                  onTap: () => _openTextEditorDialog(existing: selectedText),
                ),
                const SizedBox(width: 6),
              ],
              _StudioActionChip(
                icon: const iconoir.Trash(
                  width: 16,
                  height: 16,
                  color: Color(0xFFFF453A),
                ),
                label: '',
                onTap: _deleteSelectedLayer,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SwipeBackBlocker(
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickEmojis.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, int i) {
                final String emoji = _quickEmojis[i];
                return GestureDetector(
                  onTap: () => _addEmojiSticker(emoji),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      emoji,
                      style: EmojiUtils.emojiTextStyle(fontSize: 22, height: 1.0),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarkupTab(BuildContext context, TheavPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _StudioActionChip(
              label: context.trOr('avatar_editor_brush_pen', 'Перо'),
              selected: _brushStyle == AvatarBrushStyle.pen,
              accentColor: palette.primary,
              onTap: () => setState(() => _brushStyle = AvatarBrushStyle.pen),
            ),
            const SizedBox(width: 6),
            _StudioActionChip(
              label: context.trOr('avatar_editor_brush_neon', 'Неон'),
              selected: _brushStyle == AvatarBrushStyle.neon,
              accentColor: palette.primary,
              onTap: () => setState(() => _brushStyle = AvatarBrushStyle.neon),
            ),
            const SizedBox(width: 6),
            _StudioActionChip(
              label: context.trOr(
                'avatar_editor_brush_highlighter',
                'Маркер',
              ),
              selected: _brushStyle == AvatarBrushStyle.highlighter,
              accentColor: palette.primary,
              onTap: () =>
                  setState(() => _brushStyle = AvatarBrushStyle.highlighter),
            ),
            const Spacer(),
            // Stroke thickness dots
            for (final double w in _brushWidths)
              GestureDetector(
                onTap: () {
                  HapticUtils.selection();
                  setState(() => _brushWidthFraction = w);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_brushWidthFraction - w).abs() < 1e-4
                          ? Colors.white.withValues(alpha: 0.20)
                          : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: (w * 380).clamp(5.0, 15.0),
                      height: (w * 380).clamp(5.0, 15.0),
                      decoration: BoxDecoration(
                        color: _brushColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _state.strokes.isNotEmpty
                  ? () {
                      HapticUtils.selection();
                      final next = _state.copyWith(
                        strokes: _state.strokes
                            .sublist(0, _state.strokes.length - 1),
                      );
                      _commitHistory(next);
                    }
                  : null,
              icon: iconoir.Undo(
                width: 17,
                height: 17,
                color: _state.strokes.isNotEmpty
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.28),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwipeBackBlocker(
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _paletteColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, int i) {
                final Color c = _paletteColors[i];
                final bool active = c.toARGB32() == _brushColor.toARGB32();
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _brushColor = c);
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active
                            ? palette.primary
                            : Colors.white.withValues(alpha: 0.35),
                        width: active ? 2.5 : 1.0,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AspectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AspectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.65),
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StudioActionChip extends StatelessWidget {
  final Widget? icon;
  final String label;
  final bool selected;
  final Color? accentColor;
  final VoidCallback onTap;

  const _StudioActionChip({
    this.icon,
    required this.label,
    this.selected = false,
    this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = accentColor ?? const Color(0xFF38BDF8);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 10 : 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.14),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) icon!,
            if (icon != null && label.isNotEmpty) const SizedBox(width: 6),
            if (label.isNotEmpty)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? accent : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TextModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = context.theav.primary;
    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : Colors.white.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? primary : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AvatarTextLayerDialogContent extends StatefulWidget {
  final String initialText;
  final Color initialColor;
  final AvatarTextBackgroundMode initialBgMode;
  final bool initialBold;
  final List<Color> paletteColors;
  final void Function(
    String text,
    Color color,
    AvatarTextBackgroundMode bgMode,
    bool bold,
  ) onChanged;

  const _AvatarTextLayerDialogContent({
    required this.initialText,
    required this.initialColor,
    required this.initialBgMode,
    required this.initialBold,
    required this.paletteColors,
    required this.onChanged,
  });

  @override
  State<_AvatarTextLayerDialogContent> createState() =>
      _AvatarTextLayerDialogContentState();
}

class _AvatarTextLayerDialogContentState
    extends State<_AvatarTextLayerDialogContent> {
  late final TextEditingController _ctrl;
  late Color _color;
  late AvatarTextBackgroundMode _bgMode;
  late bool _bold;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _color = widget.initialColor;
    _bgMode = widget.initialBgMode;
    _bold = widget.initialBold;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_ctrl.text, _color, _bgMode, _bold);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          onChanged: (_) => _emit(),
          decoration: InputDecoration(
            hintText: context.trOr(
              'avatar_editor_text_hint',
              'Введите текст...',
            ),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwipeBackBlocker(
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.paletteColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, int i) {
                final Color c = widget.paletteColors[i];
                final bool active = c.toARGB32() == _color.toARGB32();
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _color = c);
                    _emit();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active
                            ? const Color(0xFF38BDF8)
                            : Colors.white.withValues(alpha: 0.3),
                        width: active ? 2.5 : 1.0,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _TextModeChip(
              label: context.trOr('avatar_text_bg_none', 'Без фона'),
              selected: _bgMode == AvatarTextBackgroundMode.none,
              onTap: () {
                setState(() => _bgMode = AvatarTextBackgroundMode.none);
                _emit();
              },
            ),
            _TextModeChip(
              label: context.trOr('avatar_text_bg_solid', 'Плашка'),
              selected: _bgMode == AvatarTextBackgroundMode.solid,
              onTap: () {
                setState(() => _bgMode = AvatarTextBackgroundMode.solid);
                _emit();
              },
            ),
            _TextModeChip(
              label: context.trOr('avatar_text_bg_translucent', 'Стекло'),
              selected: _bgMode == AvatarTextBackgroundMode.translucent,
              onTap: () {
                setState(() => _bgMode = AvatarTextBackgroundMode.translucent);
                _emit();
              },
            ),
            _TextModeChip(
              label: 'B',
              selected: _bold,
              onTap: () {
                setState(() => _bold = !_bold);
                _emit();
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarStickerChooserContent extends StatefulWidget {
  final List<String> emojis;
  final ValueChanged<String> onSelectEmoji;
  final ValueChanged<StickerItem> onSelectSticker;

  const _AvatarStickerChooserContent({
    required this.emojis,
    required this.onSelectEmoji,
    required this.onSelectSticker,
  });

  @override
  State<_AvatarStickerChooserContent> createState() =>
      _AvatarStickerChooserContentState();
}

class _AvatarStickerChooserContentState
    extends State<_AvatarStickerChooserContent> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    StickerService.instance.addListener(_onServiceUpdated);
    StickerService.instance.ensureInitialized();
  }

  @override
  void dispose() {
    StickerService.instance.removeListener(_onServiceUpdated);
    super.dispose();
  }

  void _onServiceUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = StickerService.instance;
    final List<StickerItem> stickers = <StickerItem>[
      ...service.favoriteStickers,
      ...service.recentStickers,
      for (final p in service.installedStickerPacks) ...p.stickers,
      for (final p in service.installedEmojiPacks) ...p.stickers,
      for (final p in service.featuredEmojiPacks) ...p.stickers,
    ];
    final Set<int> seenIds = <int>{};
    final List<StickerItem> uniqueStickers = <StickerItem>[
      for (final s in stickers)
        if (s.fileUrl.isNotEmpty && seenIds.add(s.id)) s,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TheavSegmentedControl<int>(
          height: 36,
          expand: true,
          selected: _tab,
          onChanged: (v) => setState(() => _tab = v),
          options: [
            TheavSegmentOption(
              value: 0,
              label: context.trOr('avatar_constructor_emojis', 'Эмодзи'),
            ),
            TheavSegmentOption(
              value: 1,
              label: context.trOr('avatar_constructor_stickers', 'Стикеры'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: math.min(320.0, MediaQuery.sizeOf(context).height * 0.42),
          child: _tab == 0
              ? GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: widget.emojis.length,
                  itemBuilder: (_, int i) {
                    final String emoji = widget.emojis[i];
                    return GestureDetector(
                      onTap: () => widget.onSelectEmoji(emoji),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          emoji,
                          style: EmojiUtils.emojiTextStyle(
                            fontSize: 28,
                            height: 1.0,
                          ),
                        ),
                      ),
                    );
                  },
                )
              : (uniqueStickers.isEmpty
                  ? Center(
                      child: Text(
                        context.trOr(
                          'avatar_stickers_empty',
                          'Установленные стикерпаки не найдены',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: uniqueStickers.length,
                      itemBuilder: (_, int i) {
                        final StickerItem st = uniqueStickers[i];
                        return GestureDetector(
                          onTap: () => widget.onSelectSticker(st),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: StickerMediaView(
                                fileUrl: st.fileUrl,
                                thumbnailUrl: st.thumbnailUrl,
                                stickerId: st.id,
                                format: st.format,
                                width: 48,
                                height: 48,
                                animate: false,
                              ),
                            ),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }
}
