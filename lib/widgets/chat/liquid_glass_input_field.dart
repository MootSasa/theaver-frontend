import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/entity_parser.dart';
import '../message/spoiler_text_widget.dart';
import 'rich_text_editing_controller.dart';
export 'rich_text_editing_controller.dart';

// --- НАСТРОЙКИ СТИЛЯ ПОЛЯ ВВОДА ---
/// Радиус скругления контейнера поля ввода (в классическом и стеклянном режимах).
const double _kInputFillBorderRadius = 24.0;
/// Внешний горизонтальный отступ всего блока ввода от краев экрана.
const double _kInputHorizontalPadding = 12.0;
/// Внешний вертикальный отступ всего блока ввода от краев экрана.
const double _kInputVerticalPadding = 12.0;

/// Размер круглых кнопок действий (скрепка, микрофон/отправить).
const double _kActionButtonSize = 38.0;
/// Размер иконок внутри кнопок действий.
const double _kActionIconSize = 24.0;

/// Размер кнопки эмодзи.
const double _kEmojiButtonSize = 38.0;
/// Размер иконки эмодзи.
const double _kEmojiIconSize = 26.0;

/// Размер шрифта в поле ввода.
const double _kInputFontSize = 17.0;

/// Мятный акцентный цвет для тулбара и цитат.
const Color _kMintAccent = Color(0xFF7BE5DA);

/// Максимальная высота поля ввода до появления скролла.
const double _kInputMaxHeight = 250.0;
// ----------------------------------

/// Плавающее овальное поле ввода с Liquid Glass эффектом.
class LiquidGlassInputField extends StatefulWidget {
  final bool enabled;
  final bool isLite;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onEmoji;
  final VoidCallback? onVoice;
  final VoidCallback? onStartVoiceRecord;
  final ValueChanged<Offset>? onVoiceRecordMove;
  final VoidCallback? onVoiceRecordEnd;
  final VoidCallback? onVoiceRecordCancel;
  final VoidCallback? onStartVideoRecord;
  final ValueChanged<Offset>? onVideoRecordMove;
  final VoidCallback? onVideoRecordEnd;
  final VoidCallback? onVideoRecordCancel;
  final bool isSending;
  final IconData attachIcon;
  final Widget? attachIconWidget;
  final bool hasAttachments;

  const LiquidGlassInputField({
    Key? key,
    required this.enabled,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.isLite = false,
    this.onChanged,
    this.onSend,
    this.onAttach,
    this.onEmoji,
    this.onVoice,
    this.onStartVoiceRecord,
    this.onVoiceRecordMove,
    this.onVoiceRecordEnd,
    this.onVoiceRecordCancel,
    this.onStartVideoRecord,
    this.onVideoRecordMove,
    this.onVideoRecordEnd,
    this.onVideoRecordCancel,
    this.isSending = false,
    this.attachIcon = Icons.attach_file,
    this.attachIconWidget,
    this.hasAttachments = false,
  }) : super(key: key);

  @override
  State<LiquidGlassInputField> createState() => _LiquidGlassInputFieldState();
}

class _LiquidGlassInputFieldState extends State<LiquidGlassInputField>
    with TickerProviderStateMixin {
  final GlobalKey _fieldKey = GlobalKey();
  late final AnimationController _blinkController;
  late final AnimationController _spoilerController;
  late final AnimationController _mediaFlipController;
  late final ScrollController _scrollController;
  final List<SpoilerParticle> _spoilerParticles = [];
  String _lastRecordedText = '';
  bool _lastShowItalic = false;
  bool _lastHasSpoilers = false;
  bool _lastHasQuotes = false;
  bool _isVideoMode = false;

  bool _computeShowItalic() {
    final richCtrl = widget.controller is RichTextEditingController
        ? widget.controller as RichTextEditingController
        : null;
    return (richCtrl?.isCursorItalic ?? false) &&
        (widget.focusNode?.hasFocus ?? false) &&
        widget.controller.selection.isValid &&
        widget.controller.selection.isCollapsed;
  }

  bool _hasSpoilers() {
    final richCtrl = widget.controller is RichTextEditingController
        ? widget.controller as RichTextEditingController
        : null;
    return richCtrl?.spans.any((s) => s.type == 'spoiler') ?? false;
  }

  bool _hasQuotes() {
    final richCtrl = widget.controller is RichTextEditingController
        ? widget.controller as RichTextEditingController
        : null;
    return richCtrl?.spans.any((s) =>
            s.type == 'blockquote' ||
            s.type == 'quote' ||
            s.type == 'collapse') ??
        false;
  }

  void _ensureInputSpoilerParticles() {
    while (_spoilerParticles.length < 80) {
      _spoilerParticles.add(SpoilerParticle.create(300, 40));
    }
  }

  @override
  void initState() {
    super.initState();
    _lastRecordedText = widget.controller.text;
    _lastShowItalic = _computeShowItalic();
    _lastHasQuotes = _hasQuotes();
    _scrollController = ScrollController();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    if (widget.focusNode?.hasFocus == true) {
      _blinkController.repeat(reverse: true);
    }

    _spoilerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _lastHasSpoilers = _hasSpoilers();
    if (_lastHasSpoilers) {
      _ensureInputSpoilerParticles();
      _spoilerController.repeat();
    }

    widget.controller.addListener(_onControllerChanged);
    widget.focusNode?.addListener(_onFocusChanged);
    // Refresh text field when font loads
    EmojiUtils.isFontLoaded.addListener(_handleFontLoaded);

    _mediaFlipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadMediaMode();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastRecordedText = widget.controller.text;
      _lastShowItalic = _computeShowItalic();
      _lastHasQuotes = _hasQuotes();
      final hasSpoilers = _hasSpoilers();
      if (hasSpoilers && !_spoilerController.isAnimating) {
        _ensureInputSpoilerParticles();
        _spoilerController.repeat();
      } else if (!hasSpoilers && _spoilerController.isAnimating) {
        _spoilerController.stop();
      }
      _lastHasSpoilers = hasSpoilers;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      widget.focusNode?.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    _blinkController.dispose();
    _spoilerController.dispose();
    _mediaFlipController.dispose();
    _scrollController.dispose();
    EmojiUtils.isFontLoaded.removeListener(_handleFontLoaded);
    super.dispose();
  }

  Future<void> _loadMediaMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('chat_input_media_mode');
      if (mode == 'video' && mounted) {
        setState(() {
          _isVideoMode = true;
          _mediaFlipController.value = 1.0;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleMediaMode() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isVideoMode = !_isVideoMode;
    });
    if (_isVideoMode) {
      _mediaFlipController.forward(from: 0.0);
    } else {
      _mediaFlipController.reverse(from: 1.0);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'chat_input_media_mode', _isVideoMode ? 'video' : 'voice');
    } catch (_) {}
  }

  void _onControllerChanged() {
    _blinkController.value = 1.0;
    if (widget.focusNode?.hasFocus == true && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    }
    final hasSpoilers = _hasSpoilers();
    if (hasSpoilers && !_spoilerController.isAnimating) {
      _ensureInputSpoilerParticles();
      _spoilerController.repeat();
    } else if (!hasSpoilers && _spoilerController.isAnimating) {
      _spoilerController.stop();
    }

    final showItalic = _computeShowItalic();
    final hasQuotes = _hasQuotes();
    if (widget.controller.text != _lastRecordedText ||
        showItalic != _lastShowItalic ||
        hasSpoilers != _lastHasSpoilers ||
        hasQuotes != _lastHasQuotes) {
      _lastRecordedText = widget.controller.text;
      _lastShowItalic = showItalic;
      _lastHasSpoilers = hasSpoilers;
      _lastHasQuotes = hasQuotes;
      if (mounted) setState(() {});
    }
  }

  void _onFocusChanged() {
    if (widget.focusNode?.hasFocus == true) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      if (_blinkController.isAnimating) {
        _blinkController.stop();
      }
      _blinkController.value = 1.0;
    }
    _lastShowItalic = _computeShowItalic();
    if (mounted) setState(() {});
  }

  void _handleFontLoaded() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return _buildClassicInput(context);
    }
    return _buildGlassInput(context);
  }

  Widget _buildClassicInput(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _kInputHorizontalPadding,
        vertical: _kInputVerticalPadding,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kInputFillBorderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(_kInputFillBorderRadius),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 0.5,
              ),
            ),
            child: _buildInputRow(context),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassInput(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);

    final shape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: _kInputFillBorderRadius,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: isDark ? 0.7 : 0.95,
      lightDirection: lightAngle,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final style = LiquidGlassStyle(
      shape: shape,
      appearance: LiquidGlassAppearance(
        color: isDark ? const Color(0x33202025) : const Color(0x8FFFFFFF),
        blur: glassProvider.blurEffect,
        shadow: LiquidGlassShadow(
          blur: 16,
          opacity: isDark ? 0.40 : 0.18,
          offset: const Offset(0, 4),
          color: Colors.black,
        ),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.06,
        distortionWidth: 26,
      ),
      liteGlass: widget.isLite ? LiquidGlassLitePickup.backdrop : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _kInputHorizontalPadding,
        vertical: _kInputVerticalPadding,
      ),
      child: LiquidGlassLens(
        style: style,
        child: _buildInputRow(context),
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    final theme = Theme.of(context);
    const rightButtonBg = Color(0xFF0088CC);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6, top: 6),
          child: widget.onEmoji != null
              ? GestureDetector(
                  onTap: widget.onEmoji,
                  child: Container(
                    width: _kEmojiButtonSize,
                    height: _kEmojiButtonSize,
                    alignment: Alignment.center,
                    child: iconoir.Emoji(
                      width: _kEmojiIconSize,
                      height: _kEmojiIconSize,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (widget.onEmoji != null) const SizedBox(width: 4),
        Expanded(
          child: _buildTextField(context),
        ),
        if (widget.onAttach != null) const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: widget.onAttach != null
              ? GestureDetector(
                  onTap: widget.onAttach,
                  child: Container(
                    width: _kActionButtonSize,
                    height: _kActionButtonSize,
                    alignment: Alignment.center,
                    child: widget.attachIconWidget ??
                        (widget.hasAttachments
                            ? iconoir.PlusCircle(
                                width: _kActionIconSize,
                                height: _kActionIconSize,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              )
                            : (widget.attachIcon != Icons.attach_file
                                ? Icon(
                                    widget.attachIcon,
                                    size: _kActionIconSize,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  )
                                : iconoir.Attachment(
                                    width: _kActionIconSize,
                                    height: _kActionIconSize,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ))),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: _buildSendButton(rightButtonBg),
        ),
      ],
    );
  }

  Widget _buildTextField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final richCtrl = widget.controller is RichTextEditingController
        ? widget.controller as RichTextEditingController
        : null;
    final isItalic = richCtrl?.isCursorItalic ?? false;
    final isFocused = widget.focusNode?.hasFocus ?? false;
    final hasCollapsedSelection = widget.controller.selection.isValid &&
        widget.controller.selection.isCollapsed;
    final showItalicCursor = isItalic && isFocused && hasCollapsedSelection;
    final hasSpoilers = richCtrl?.spans.any((s) => s.type == 'spoiler') ?? false;
    final spoilerColor = isDark ? Colors.white70 : Colors.black87;

    final cursorColor = theme.colorScheme.primary;
    final selectionHandleColor =
        isDark ? const Color(0xFF7BE5DA) : const Color(0xFF0088CC);
    final selectionColor = isDark
        ? const Color(0x597BE5DA)
        : const Color(0x470088CC);

    final textSelectionTheme = theme.textSelectionTheme.copyWith(
      cursorColor: cursorColor,
      selectionHandleColor: selectionHandleColor,
      selectionColor: selectionColor,
    );

    final profileTheme = context.watch<ProfileThemeProvider?>();
    final userPreset = profileTheme?.currentNameColorPreset;
    final quoteAccentColor = userPreset?.primaryColor ?? _kMintAccent;
    final quoteCardColor = userPreset?.getOpaqueCardBackgroundColor(isDark) ??
        (isDark ? const Color(0x22FFFFFF) : const Color(0x15000000));

    return Theme(
      data: theme.copyWith(textSelectionTheme: textSelectionTheme),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: _kInputMaxHeight,
          ),
          child: Scrollbar(
            controller: _scrollController,
            child: ValueListenableBuilder<bool>(
              valueListenable: EmojiUtils.isFontLoaded,
              builder: (context, isLoaded, child) {
                final hasQuotes = _hasQuotes();
                return CustomPaint(
                  painter: hasQuotes && richCtrl != null
                      ? InputQuotePainter(
                          fieldKey: _fieldKey,
                          controller: richCtrl,
                          accentColor: quoteAccentColor,
                          cardColor: quoteCardColor,
                        )
                      : null,
                  foregroundPainter: hasSpoilers && richCtrl != null
                      ? InputSpoilerOverlayPainter(
                          fieldKey: _fieldKey,
                          controller: richCtrl,
                          color: spoilerColor,
                          particles: _spoilerParticles,
                          repaint: _spoilerController,
                        )
                      : null,
                  child: CustomPaint(
                    foregroundPainter: showItalicCursor
                        ? ItalicCaretPainter(
                            fieldKey: _fieldKey,
                            controller: widget.controller,
                            color: cursorColor,
                            repaint: _blinkController,
                            opacityAnimation: _blinkController,
                          )
                        : null,
                    child: TextField(
                    key: _fieldKey,
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: _scrollController,
                    selectionControls: telegramTextSelectionControls,
                    cursorColor: showItalicCursor ? Colors.transparent : cursorColor,
                    cursorWidth: 2.0,
                    cursorRadius: const Radius.circular(1.0),
                    cursorOpacityAnimates: true,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    contextMenuBuilder: (context, editableTextState) {
                      if (!editableTextState.textEditingValue.selection.isCollapsed) {
                        return ScrollableTextSelectionToolbar(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: editableTextState.contextMenuButtonItems,
                          controller: widget.controller,
                          onHideToolbar: editableTextState.hideToolbar,
                        );
                      }

                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: editableTextState.contextMenuAnchors,
                        buttonItems: editableTextState.contextMenuButtonItems,
                      );
                    },
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: _kInputFontSize,
                      height: 1.2,
                    ),
                    onChanged: (text) {
                      widget.onChanged?.call(text);
                    },
                    textAlignVertical: TextAlignVertical.center,
                  ),
                ),
              );
            },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(Color rightButtonBg) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final canSend = value.text.isNotEmpty || widget.hasAttachments;
        final color = widget.isSending ? Colors.grey : rightButtonBg;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (widget.isSending) return;
            if (canSend) {
              widget.onSend?.call();
            } else {
              _toggleMediaMode();
            }
          },
          onLongPressStart: (details) {
            if (canSend || widget.isSending) return;
            if (_isVideoMode) {
              widget.onStartVideoRecord?.call();
            } else {
              widget.onStartVoiceRecord?.call();
              widget.onVoice?.call();
            }
          },
          onLongPressMoveUpdate: (details) {
            if (canSend || widget.isSending) return;
            if (_isVideoMode) {
              widget.onVideoRecordMove?.call(details.offsetFromOrigin);
            } else {
              widget.onVoiceRecordMove?.call(details.offsetFromOrigin);
            }
          },
          onLongPressEnd: (details) {
            if (canSend || widget.isSending) return;
            if (_isVideoMode) {
              widget.onVideoRecordEnd?.call();
            } else {
              widget.onVoiceRecordEnd?.call();
            }
          },
          onLongPressCancel: () {
            if (canSend || widget.isSending) return;
            if (_isVideoMode) {
              widget.onVideoRecordCancel?.call();
            } else {
              widget.onVoiceRecordCancel?.call();
            }
          },
          child: Container(
            width: _kActionButtonSize,
            height: _kActionButtonSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: widget.isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : (canSend
                    ? const iconoir.SendDiagonalSolid(
                        width: 22, height: 22, color: Colors.white)
                    : AnimatedBuilder(
                        animation: _mediaFlipController,
                        builder: (context, child) {
                          final angle = _mediaFlipController.value * math.pi;
                          final isVideo = _mediaFlipController.value >= 0.5;
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.002)
                              ..rotateY(angle + (isVideo ? math.pi : 0)),
                            child: isVideo
                                ? const iconoir.VideoCamera(
                                    width: 22,
                                    height: 22,
                                    color: Colors.white,
                                  )
                                : const iconoir.MicrophoneSolid(
                                    width: 22,
                                    height: 22,
                                    color: Colors.white,
                                  ),
                          );
                        },
                      )),
          ),
        );
      },
    );
  }
}

/// Custom painter that draws a tilted (italic) caret matching the font slant.
class ItalicCaretPainter extends CustomPainter {
  final GlobalKey fieldKey;
  final TextEditingController controller;
  final Color color;
  final Animation<double> opacityAnimation;

  ItalicCaretPainter({
    required this.fieldKey,
    required this.controller,
    required this.color,
    required Listenable repaint,
    required this.opacityAnimation,
  }) : super(repaint: repaint);

  static RenderEditable? _findRenderEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? found;
    root.visitChildren((child) {
      if (found != null) return;
      found = _findRenderEditable(child);
    });
    return found;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = opacityAnimation.value;
    if (opacity <= 0.05) return;

    final renderBox = fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final renderEditable = _findRenderEditable(renderBox);
    if (renderEditable == null) return;

    final sel = controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;

    final rawRect = renderEditable.getLocalRectForCaret(TextPosition(offset: sel.baseOffset));
    final globalTopLeft = renderEditable.localToGlobal(rawRect.topLeft);
    final localTopLeft = renderBox.globalToLocal(globalTopLeft);
    final caretRect = Rect.fromLTWH(
      localTopLeft.dx,
      localTopLeft.dy,
      math.max(rawRect.width, 2.0),
      rawRect.height,
    );

    final height = caretRect.height;
    final tilt = height * 0.23; // ~13 degrees forward tilt
    const width = 2.0;

    final path = Path()
      ..moveTo(caretRect.left + tilt, caretRect.top)
      ..lineTo(caretRect.left + tilt + width, caretRect.top)
      ..lineTo(caretRect.left + width, caretRect.bottom)
      ..lineTo(caretRect.left, caretRect.bottom)
      ..close();

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ItalicCaretPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Custom painter that renders a blockquote background, left accent strip,
/// and upper-right quote icon directly inside the TextField in-place.
class InputQuotePainter extends CustomPainter {
  final GlobalKey fieldKey;
  final RichTextEditingController controller;
  final Color accentColor;
  final Color cardColor;

  InputQuotePainter({
    required this.fieldKey,
    required this.controller,
    required this.accentColor,
    required this.cardColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final renderBox = fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final renderEditable = ItalicCaretPainter._findRenderEditable(renderBox);
    if (renderEditable == null) return;

    final text = controller.text;
    final quoteSpans = controller.spans
        .where((s) => s.type == 'blockquote' || s.type == 'quote' || s.type == 'collapse')
        .toList();
    if (quoteSpans.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    for (final span in quoteSpans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(start, text.length);
      if (start >= end) continue;

      final boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      if (boxes.isEmpty) continue;

      double minTop = double.infinity;
      double maxBottom = -double.infinity;

      for (final box in boxes) {
        final rawRect = box.toRect();
        final globalTopLeft = renderEditable.localToGlobal(rawRect.topLeft);
        final localTopLeft = renderBox.globalToLocal(globalTopLeft);
        if (localTopLeft.dy < minTop) minTop = localTopLeft.dy;
        if (localTopLeft.dy + rawRect.height > maxBottom) {
          maxBottom = localTopLeft.dy + rawRect.height;
        }
      }

      if (minTop >= maxBottom) continue;

      final quoteRect = Rect.fromLTRB(2.0, minTop - 2.0, size.width - 2.0, maxBottom + 2.0);
      final bgRRect = RRect.fromRectAndRadius(quoteRect, const Radius.circular(6.0));

      // 1. Draw card background
      canvas.drawRRect(bgRRect, Paint()..color = cardColor);

      // 2. Draw left vertical strip
      final stripRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(6.0, quoteRect.top + 2.0, 3.5, quoteRect.height - 4.0),
        const Radius.circular(2.0),
      );
      canvas.drawRRect(stripRRect, Paint()..color = accentColor);

      // 3. Draw quote-solid icon in upper-right corner
      final quotePath = Path();
      // Left quotation mark
      quotePath.moveTo(9.21, 12.75);
      quotePath.cubicTo(9.13, 13.52, 8.91, 14.14, 8.51, 14.69);
      quotePath.cubicTo(7.99, 15.42, 7.12, 16.10, 5.66, 16.83);
      quotePath.cubicTo(5.29, 17.01, 5.14, 17.46, 5.33, 17.84);
      quotePath.cubicTo(5.51, 18.21, 5.96, 18.36, 6.34, 18.17);
      quotePath.cubicTo(7.88, 17.40, 9.01, 16.58, 9.74, 15.56);
      quotePath.cubicTo(10.48, 14.52, 10.75, 13.36, 10.75, 12.0);
      quotePath.lineTo(10.75, 7.5);
      quotePath.cubicTo(10.75, 6.53, 9.97, 5.75, 9.0, 5.75);
      quotePath.lineTo(5.0, 5.75);
      quotePath.cubicTo(4.03, 5.75, 3.25, 6.53, 3.25, 7.5);
      quotePath.lineTo(3.25, 11.0);
      quotePath.cubicTo(3.25, 11.97, 4.03, 12.75, 5.0, 12.75);
      quotePath.close();

      // Right quotation mark
      quotePath.moveTo(19.21, 12.75);
      quotePath.cubicTo(19.13, 13.52, 18.91, 14.14, 18.51, 14.69);
      quotePath.cubicTo(17.99, 15.42, 17.12, 16.10, 15.66, 16.83);
      quotePath.cubicTo(15.29, 17.01, 15.14, 17.46, 15.33, 17.84);
      quotePath.cubicTo(15.51, 18.21, 15.96, 18.36, 16.34, 18.17);
      quotePath.cubicTo(17.88, 17.40, 19.01, 16.58, 19.74, 15.56);
      quotePath.cubicTo(20.48, 14.52, 20.75, 13.36, 20.75, 12.0);
      quotePath.lineTo(20.75, 7.5);
      quotePath.cubicTo(20.75, 6.53, 19.97, 5.75, 19.0, 5.75);
      quotePath.lineTo(15.0, 5.75);
      quotePath.cubicTo(14.03, 5.75, 13.25, 6.53, 13.25, 7.5);
      quotePath.lineTo(13.25, 11.0);
      quotePath.cubicTo(13.25, 11.97, 14.03, 12.75, 15.0, 12.75);
      quotePath.close();

      canvas.save();
      canvas.translate(quoteRect.right - 22.0, quoteRect.top + 4.0);
      canvas.scale(14.0 / 24.0);
      canvas.drawPath(
        quotePath,
        Paint()
          ..color = accentColor.withValues(alpha: 0.40)
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant InputQuotePainter oldDelegate) {
    return oldDelegate.controller.text != controller.text ||
        oldDelegate.controller.spans != controller.spans ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.cardColor != cardColor;
  }
}

/// Custom painter that overlays shimmering spoiler particles over spoiler text spans
/// in the input field, exactly as Telegram does.
class InputSpoilerOverlayPainter extends CustomPainter {
  final GlobalKey fieldKey;
  final RichTextEditingController controller;
  final Color color;
  final List<SpoilerParticle> particles;

  InputSpoilerOverlayPainter({
    required this.fieldKey,
    required this.controller,
    required this.color,
    required this.particles,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || particles.isEmpty) return;

    final renderBox = fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final renderEditable = ItalicCaretPainter._findRenderEditable(renderBox);
    if (renderEditable == null) return;

    final text = controller.text;
    final spoilerSpans = controller.spans.where((s) => s.type == 'spoiler').toList();
    if (spoilerSpans.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    for (final span in spoilerSpans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(start, text.length);
      if (start >= end) continue;

      final boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );

      for (final box in boxes) {
        final rawRect = box.toRect();
        final globalTopLeft = renderEditable.localToGlobal(rawRect.topLeft);
        final localTopLeft = renderBox.globalToLocal(globalTopLeft);
        final rect = Rect.fromLTWH(
          localTopLeft.dx,
          localTopLeft.dy,
          rawRect.width,
          rawRect.height,
        );

        if (rect.width <= 0 || rect.height <= 0) continue;

        // Clip strictly to this text box with slight rounded corners
        canvas.save();
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        canvas.clipRRect(rrect);

        // Subtle underlay
        canvas.drawRRect(
          rrect,
          Paint()..color = color.withValues(alpha: 0.18),
        );

        // Render shimmering particles inside this box
        final brightPoints = <Offset>[];
        final dimPoints = <Offset>[];

        for (final p in particles) {
          final px = (p.x % rect.width);
          final py = (p.y % rect.height);
          final pt = Offset(rect.left + px, rect.top + py);
          if (p.alpha > 0.5) {
            brightPoints.add(pt);
          } else {
            dimPoints.add(pt);
          }
        }

        if (dimPoints.isNotEmpty) {
          canvas.drawPoints(
            ui.PointMode.points,
            dimPoints,
            Paint()
              ..color = color.withValues(alpha: 0.45)
              ..strokeWidth = 2.0
              ..strokeCap = StrokeCap.round,
          );
        }

        if (brightPoints.isNotEmpty) {
          canvas.drawPoints(
            ui.PointMode.points,
            brightPoints,
            Paint()
              ..color = color.withValues(alpha: 0.85)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round,
          );
        }

        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant InputSpoilerOverlayPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.controller != controller;
  }
}

/// Кастомные маркеры выделения текста в стиле Telegram.
/// Имеют размер 26px и увеличенную область нажатия, что обеспечивает
/// комфортное и точное перетаскивание на сенсорных экранах.
class TelegramTextSelectionControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  TelegramTextSelectionControls();

  static const double _kHandleSize = 26.0;

  @override
  Size getHandleSize(double textLineHeight) => const Size(_kHandleSize, _kHandleSize);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return switch (type) {
      TextSelectionHandleType.collapsed => const Offset(_kHandleSize / 2, -4),
      TextSelectionHandleType.left => const Offset(_kHandleSize, 0),
      TextSelectionHandleType.right => Offset.zero,
    };
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) {
    final ThemeData theme = Theme.of(context);
    final Color handleColor =
        TextSelectionTheme.of(context).selectionHandleColor ?? theme.colorScheme.primary;
    final Widget handle = SizedBox(
      width: _kHandleSize,
      height: _kHandleSize,
      child: CustomPaint(
        painter: _TelegramSelectionHandlePainter(color: handleColor),
        child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.translucent),
      ),
    );

    return switch (type) {
      TextSelectionHandleType.left => Transform.rotate(
        angle: math.pi / 2.0,
        child: handle,
      ),
      TextSelectionHandleType.right => handle,
      TextSelectionHandleType.collapsed => Transform.rotate(
        angle: math.pi / 4.0,
        child: handle,
      ),
    };
  }
}

class _TelegramSelectionHandlePainter extends CustomPainter {
  final Color color;
  _TelegramSelectionHandlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final double radius = size.width / 2.0;
    final circle = Rect.fromCircle(center: Offset(radius, radius), radius: radius);
    final point = Rect.fromLTWH(0.0, 0.0, radius, radius);
    final path = Path()
      ..addOval(circle)
      ..addRect(point);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TelegramSelectionHandlePainter oldPainter) {
    return color != oldPainter.color;
  }
}

final TextSelectionControls telegramTextSelectionControls = TelegramTextSelectionControls();

/// Telegram-style floating text selection toolbar with compact horizontal pill and expanded vertical menu.
class TelegramTextSelectionToolbar extends StatefulWidget {
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;
  final TextEditingController controller;
  final VoidCallback onHideToolbar;

  const TelegramTextSelectionToolbar({
    Key? key,
    required this.anchors,
    required this.buttonItems,
    required this.controller,
    required this.onHideToolbar,
  }) : super(key: key);

  @override
  State<TelegramTextSelectionToolbar> createState() =>
      _TelegramTextSelectionToolbarState();
}

class _TelegramTextSelectionToolbarState
    extends State<TelegramTextSelectionToolbar> {
  static bool _persistedExpanded = false;
  static int _lastSelectionStart = -1;
  static int _lastSelectionEnd = -1;

  bool _isExpanded = false;

  static const Color _kDarkBg = Color(0xFF1E2225);
  static const Color _kMintAccent = Color(0xFF7BE5DA);

  @override
  void initState() {
    super.initState();
    final sel = widget.controller.selection;
    if (sel.isValid && !sel.isCollapsed && sel.start == _lastSelectionStart && sel.end == _lastSelectionEnd) {
      _isExpanded = _persistedExpanded;
    } else {
      _persistedExpanded = false;
      _isExpanded = false;
      _lastSelectionStart = sel.isValid ? sel.start : -1;
      _lastSelectionEnd = sel.isValid ? sel.end : -1;
    }
  }

  void _expand() {
    final sel = widget.controller.selection;
    _lastSelectionStart = sel.start;
    _lastSelectionEnd = sel.end;
    _persistedExpanded = true;
    setState(() => _isExpanded = true);
  }

  void _collapse() {
    _persistedExpanded = false;
    setState(() => _isExpanded = false);
  }

  void _hideToolbar() {
    _persistedExpanded = false;
    widget.onHideToolbar();
  }

  void _executeCut() {
    final cutItem = widget.buttonItems
        .where((b) => b.type == ContextMenuButtonType.cut)
        .firstOrNull;
    if (cutItem?.onPressed != null) {
      cutItem!.onPressed!();
      return;
    }
    final sel = widget.controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = widget.controller.text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: text));
    final newText = widget.controller.text.replaceRange(sel.start, sel.end, '');
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start),
    );
  }

  void _executeCopy() {
    final copyItem = widget.buttonItems
        .where((b) => b.type == ContextMenuButtonType.copy)
        .firstOrNull;
    if (copyItem?.onPressed != null) {
      copyItem!.onPressed!();
      return;
    }
    final sel = widget.controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = widget.controller.text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _executePaste() async {
    final pasteItem = widget.buttonItems
        .where((b) => b.type == ContextMenuButtonType.paste)
        .firstOrNull;
    if (pasteItem?.onPressed != null) {
      pasteItem!.onPressed!();
      return;
    }
    await _executePastePlainText();
  }

  Future<void> _executePastePlainText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final sel = widget.controller.selection;
      final start = sel.isValid ? sel.start : widget.controller.text.length;
      final end = sel.isValid ? sel.end : start;
      final newText =
          widget.controller.text.replaceRange(start, end, data!.text!);
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + data.text!.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: TextSelectionToolbarLayoutDelegate(
        anchorAbove: widget.anchors.primaryAnchor,
        anchorBelow:
            widget.anchors.secondaryAnchor ?? widget.anchors.primaryAnchor,
        fitsAbove: widget.anchors.primaryAnchor.dy >= 180 ? true : null,
      ),
      child: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(16.0),
        color: _kDarkBg,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            color: _kDarkBg,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: Colors.white12, width: 0.8),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: _isExpanded
                  ? KeyedSubtree(
                      key: const ValueKey('expanded'),
                      child: _buildExpandedVerticalMenu(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('compact'),
                      child: _buildCompactPill(),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactPill() {
    return Container(
      height: 44.0,
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildPillButton('Вырезать', () {
            _executeCut();
            _hideToolbar();
          }),
          _buildPillButton('Цитировать', () {
            TextFormattingUtils.applyFormatting(widget.controller, 'quote');
            _hideToolbar();
          }),
          InkWell(
            borderRadius: BorderRadius.circular(12.0),
            onTap: _expand,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: iconoir.MoreVert(color: _kMintAccent, width: 22, height: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12.0),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Text(
          label,
          style: const TextStyle(
            color: _kMintAccent,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedVerticalMenu() {
    return Container(
      width: 250.0,
      constraints: const BoxConstraints(maxHeight: 340.0),
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMenuItem(
                    icon: const iconoir.Copy(color: _kMintAccent, width: 20, height: 20),
                    label: 'Копировать',
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    onTap: () {
                      _executeCopy();
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.PasteClipboard(color: _kMintAccent, width: 20, height: 20),
                    label: 'Вставить',
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    onTap: () {
                      _executePaste();
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Text(color: _kMintAccent, width: 20, height: 20),
                    label: 'Обычный',
                    textStyle: const TextStyle(fontWeight: FontWeight.normal),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'clear');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Bold(color: _kMintAccent, width: 20, height: 20),
                    label: 'Жирный',
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'bold');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Italic(color: _kMintAccent, width: 20, height: 20),
                    label: 'Курсив',
                    textStyle: const TextStyle(fontStyle: FontStyle.italic),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'italic');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Code(color: _kMintAccent, width: 20, height: 20),
                    label: 'Моно',
                    textStyle: const TextStyle(fontFamily: 'monospace'),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'code');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.CodeBrackets(color: _kMintAccent, width: 20, height: 20),
                    label: 'Создать код',
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    onTap: () {
                      _hideToolbar();
                      TextFormattingUtils.showCodeDialog(context, widget.controller);
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Strikethrough(color: _kMintAccent, width: 20, height: 20),
                    label: 'Зачёркнутый',
                    textStyle: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: _kMintAccent,
                    ),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'strikethrough');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Underline(color: _kMintAccent, width: 20, height: 20),
                    label: 'Подчёркнутый',
                    textStyle: const TextStyle(
                      decoration: TextDecoration.underline,
                      decorationColor: _kMintAccent,
                    ),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'underline');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.EyeClosed(color: _kMintAccent, width: 20, height: 20),
                    label: 'Скрытый',
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    onTap: () {
                      TextFormattingUtils.applyFormatting(widget.controller, 'spoiler');
                      _hideToolbar();
                    },
                  ),
                  _buildMenuItem(
                    icon: const iconoir.Link(color: _kMintAccent, width: 20, height: 20),
                    label: 'Добавить ссылку',
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                    onTap: () {
                      _hideToolbar();
                      TextFormattingUtils.showLinkDialog(context, widget.controller);
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Colors.white12),
          InkWell(
            onTap: _collapse,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 11.0),
              child: Row(
                children: [
                  iconoir.NavArrowLeft(color: _kMintAccent, width: 18, height: 18),
                  SizedBox(width: 12),
                  Text(
                    'Назад',
                    style: TextStyle(
                      color: _kMintAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required Widget icon,
    required String label,
    TextStyle? textStyle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 9.0),
        child: Row(
          children: [
            SizedBox(
              width: 20.0,
              height: 20.0,
              child: Center(child: icon),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Text(
                label,
                style: (textStyle ?? const TextStyle()).copyWith(
                  color: _kMintAccent,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef ScrollableTextSelectionToolbar = TelegramTextSelectionToolbar;

/// Утилиты форматирования выделенного текста для контекстного меню
class TextFormattingUtils {
  static void applyFormatting(TextEditingController controller, String type,
      {String? url}) {
    if (controller is RichTextEditingController) {
      if (type == 'link' || type == 'text_link') {
        if (url != null && url.isNotEmpty) {
          controller.applyLinkToSelection(url);
        } else {
          controller.removeLinkFromSelection();
        }
      } else if (type == 'clear') {
        controller.clearFormatting();
      } else {
        controller.applyFormat(type, url: url);
      }
    } else {
      EntityParser.applyFormatting(
        controller: controller,
        formatType: type,
        url: url,
      );
    }
  }

  static void showCodeDialog(
      BuildContext context, TextEditingController controller) {
    final sel = controller.selection;
    final start = sel.isValid ? math.min(sel.start, sel.end) : controller.text.length;
    final end = sel.isValid ? math.max(sel.start, sel.end) : start;
    final String selectedText = (start < end)
        ? controller.text.substring(start, end)
        : '';

    final langController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2225) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Создать блок кода',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: langController,
              autofocus: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: const InputDecoration(
                labelText: 'Язык программирования',
                hintText: 'например: dart, python, js...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final lang = langController.text.trim();
              Navigator.of(ctx).pop();

              final codeBlock = '```$lang\n$selectedText\n```';
              final newText = controller.text.replaceRange(start, end, codeBlock);

              final cursorOffset = selectedText.isEmpty
                  ? start + 4 + lang.length
                  : start + codeBlock.length;

              controller.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: cursorOffset),
              );
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  static void showLinkDialog(
      BuildContext context, TextEditingController controller) {
    final sel = controller.selection;
    RichSpan? existingLink;
    if (controller is RichTextEditingController) {
      existingLink = controller.getLinkSpanForSelection(sel);
    }

    final bool isEditingExisting = existingLink != null;
    final String initialUrl = isEditingExisting
        ? (existingLink.url ?? 'https://')
        : (sel.isValid && !sel.isCollapsed
            ? (EntityParser.urlRegex.hasMatch(controller.text.substring(
                    math.min(sel.start, sel.end),
                    math.max(sel.start, sel.end)))
                ? EntityParser.normalizeUrl(controller.text.substring(
                    math.min(sel.start, sel.end),
                    math.max(sel.start, sel.end)))
                : 'https://')
            : 'https://');

    final bool showTextField =
        !isEditingExisting && (!sel.isValid || sel.isCollapsed);

    final urlController = TextEditingController(text: initialUrl);
    final textController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2225) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEditingExisting
              ? 'Редактировать ссылку'
              : (AppLocalizations.of(ctx)?.translate('chat_action_link') ??
                  'Ссылка'),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTextField) ...[
              TextField(
                controller: textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Текст ссылки',
                  hintText: 'Название ссылки',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: urlController,
              autofocus: !showTextField,
              decoration: InputDecoration(
                labelText: isEditingExisting ? 'URL' : null,
                hintText: 'https://example.com',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          if (isEditingExisting) ...[
            Builder(builder: (c) {
              final targetLink = existingLink!;
              return TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (controller is RichTextEditingController) {
                    controller.removeLinkFromSelection(
                      start: targetLink.start,
                      end: targetLink.end,
                    );
                  }
                },
                child: const Text('Удалить ссылку',
                    style: TextStyle(color: Colors.redAccent)),
              );
            }),
          ],
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
                AppLocalizations.of(ctx)?.translate('cancel') ?? 'Отмена'),
          ),
          TextButton(
            onPressed: () {
              final url = urlController.text.trim();
              final label = textController.text.trim();
              Navigator.pop(ctx);
              if (url.isNotEmpty && url != 'https://') {
                if (controller is RichTextEditingController) {
                  if (isEditingExisting) {
                    final targetLink = existingLink!;
                    controller.applyLinkToSelection(
                      url,
                      start: targetLink.start,
                      end: targetLink.end,
                    );
                  } else if (showTextField && label.isNotEmpty) {
                    controller.applyLinkToSelection(
                      url,
                      replacementText: label,
                    );
                  } else {
                    controller.applyLinkToSelection(url);
                  }
                } else {
                  applyFormatting(controller, 'link', url: url);
                }
              }
            },
            child: Text(isEditingExisting ? 'Сохранить' : 'OK'),
          ),
        ],
      ),
    );
  }
}


