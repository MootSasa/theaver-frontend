import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:motor/motor.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/theav_theme_service.dart';
import '../../theme/theme_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';
import '../theme/baked_chat_wallpaper.dart';

/// Visual variant for [TheavSpringButton].
enum TheavSpringButtonVariant {
  primary,
  glass,
  tonal,
}

/// Tactile capsule button powered by `package:motor` spring physics and native
/// Theaver surfaces (replacing legacy button widgets).
class TheavSpringButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool enabled;
  final Widget? leading;
  final Widget? trailing;
  final TheavSpringButtonVariant variant;
  final double height;
  final double borderRadius;

  const TheavSpringButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.leading,
    this.trailing,
    this.variant = TheavSpringButtonVariant.primary,
    this.height = 50.0,
    this.borderRadius = 25.0,
  });

  @override
  State<TheavSpringButton> createState() => _TheavSpringButtonState();
}

class _TheavSpringButtonState extends State<TheavSpringButton> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && !widget.isLoading && widget.onPressed != null;

  void _setPressed(bool next) {
    if (!_interactive || _pressed == next) return;
    setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final bool active = _interactive;
    final bool isDark = style.isDark;

    final Widget labelRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.1,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.variant == TheavSpringButtonVariant.primary
                    ? palette.onPrimary
                    : palette.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.15,
              color: widget.variant == TheavSpringButtonVariant.primary
                  ? (active
                      ? palette.onPrimary
                      : palette.onPrimary.withValues(alpha: 0.72))
                  : (active
                      ? palette.onSurface
                      : palette.onSurface.withValues(alpha: 0.45)),
            ),
          ),
        ),
        if (widget.trailing != null && !widget.isLoading) ...[
          const SizedBox(width: 8),
          widget.trailing!,
        ],
      ],
    );

    Widget surface;
    if (widget.variant == TheavSpringButtonVariant.primary) {
      final Color fillColor = active
          ? palette.primary
          : palette.primary.withValues(alpha: isDark ? 0.36 : 0.42);
      surface = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.26),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Center(child: labelRow),
      );
    } else {
      final Color? override = widget.variant == TheavSpringButtonVariant.tonal
          ? palette.surface.withValues(alpha: isDark ? 0.82 : 0.90)
          : null;
      surface = SizedBox(
        height: widget.height,
        child: TheavFloatingSurface(
          borderRadius: widget.borderRadius,
          colorOverride: override,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Center(child: labelRow),
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: active,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => _setPressed(true) : null,
        onTapUp: active ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: active
            ? () {
                HapticUtils.tap();
                widget.onPressed!();
              }
            : null,
        child: SingleMotionBuilder(
          value: _pressed ? 0.965 : 1.0,
          motion: _pressed
              ? const Motion.interactiveSpring(snapToEnd: true)
              : const Motion.bouncySpring(snapToEnd: true),
          builder: (context, scale, child) => Transform.scale(
            scale: scale.clamp(0.92, 1.04),
            child: child,
          ),
          child: surface,
        ),
      ),
    );
  }
}

/// Wallpaper backdrop shared by onboarding, login, registration, and recovery.
class TheavAuthWallpaperBackground extends StatelessWidget {
  const TheavAuthWallpaperBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = context.watch<ThemeProvider?>();
    final themeSvc = tp == null ? TheavThemeService() : null;
    final wp = tp != null
        ? (isDark ? tp.activeDarkTheme.wallpaper : tp.activeLightTheme.wallpaper)
        : (isDark
            ? themeSvc!.activeDarkTheme.wallpaper
            : themeSvc!.activeLightTheme.wallpaper);
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          BakedChatWallpaper(wallpaper: wp),
          DecoratedBox(
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: isDark ? 0.24 : 0.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Crisp vector brand mark for OAuth2/OIDC providers (`yandex`, `vk`, `huawei`, `google`, `apple`).
class OAuthBrandGlyph extends StatelessWidget {
  final String providerId;
  final double size;

  const OAuthBrandGlyph({
    super.key,
    required this.providerId,
    this.size = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OAuthBrandPainter(
          providerId: providerId.toLowerCase().trim(),
          isDark: brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _OAuthBrandPainter extends CustomPainter {
  final String providerId;
  final bool isDark;

  _OAuthBrandPainter({required this.providerId, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    switch (providerId) {
      case 'yandex':
        final bg = Paint()..color = const Color(0xFFFC3F1D);
        canvas.drawCircle(Offset(s / 2, s / 2), s / 2, bg);
        final fg = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.12;
        final path = Path()
          ..moveTo(s * 0.60, s * 0.26)
          ..lineTo(s * 0.60, s * 0.74)
          ..moveTo(s * 0.60, s * 0.26)
          ..lineTo(s * 0.44, s * 0.26)
          ..cubicTo(s * 0.30, s * 0.26, s * 0.30, s * 0.51, s * 0.44, s * 0.51)
          ..lineTo(s * 0.60, s * 0.51)
          ..moveTo(s * 0.47, s * 0.52)
          ..lineTo(s * 0.34, s * 0.74);
        canvas.drawPath(path, fg);
        break;
      case 'vk':
        final bg = Paint()..color = const Color(0xFF0077FF);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(s * 0.28),
          ),
          bg,
        );
        final fg = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.115;
        final vPath = Path()
          ..moveTo(s * 0.22, s * 0.34)
          ..lineTo(s * 0.35, s * 0.66)
          ..lineTo(s * 0.48, s * 0.34)
          ..moveTo(s * 0.56, s * 0.34)
          ..lineTo(s * 0.56, s * 0.66)
          ..moveTo(s * 0.78, s * 0.34)
          ..lineTo(s * 0.58, s * 0.50)
          ..lineTo(s * 0.78, s * 0.66);
        canvas.drawPath(vPath, fg);
        break;
      case 'google':
        final stroke = s * 0.18;
        final rect = Rect.fromCircle(
          center: Offset(s / 2, s / 2),
          radius: (s - stroke) * 0.46,
        );
        final pRed = Paint()
          ..color = const Color(0xFFEA4335)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;
        final pYellow = Paint()
          ..color = const Color(0xFFFBBC05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;
        final pGreen = Paint()
          ..color = const Color(0xFF34A853)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;
        final pBlue = Paint()
          ..color = const Color(0xFF4285F4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;
        canvas.drawArc(rect, -2.55, 1.85, false, pRed);
        canvas.drawArc(rect, -3.70, 1.20, false, pYellow);
        canvas.drawArc(rect, 0.70, 2.05, false, pGreen);
        canvas.drawArc(rect, -0.15, 0.90, false, pBlue);
        canvas.drawLine(
          Offset(s * 0.52, s * 0.50),
          Offset(s * 0.90, s * 0.50),
          pBlue..strokeCap = StrokeCap.round,
        );
        break;
      case 'huawei':
        final bg = Paint()..color = const Color(0xFFCF0A2C);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(s * 0.28),
          ),
          bg,
        );
        final petalPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        final cx = s * 0.50;
        final cy = s * 0.72;
        const int petalCount = 7;
        for (var i = 0; i < petalCount; i++) {
          final t = i / (petalCount - 1);
          final angle = -math.pi * 0.90 + t * (math.pi * 0.80);
          final innerR = s * 0.11;
          final outerR = s * 0.38;
          final tipX = cx + outerR * math.cos(angle);
          final tipY = cy + outerR * math.sin(angle);
          final baseX = cx + innerR * math.cos(angle);
          final baseY = cy + innerR * math.sin(angle);
          final midR = (innerR + outerR) * 0.54;
          final perp = angle + math.pi / 2;
          final halfWidth = s * 0.042;
          final ctrl1X =
              cx + midR * math.cos(angle) + halfWidth * math.cos(perp);
          final ctrl1Y =
              cy + midR * math.sin(angle) + halfWidth * math.sin(perp);
          final ctrl2X =
              cx + midR * math.cos(angle) - halfWidth * math.cos(perp);
          final ctrl2Y =
              cy + midR * math.sin(angle) - halfWidth * math.sin(perp);
          final petal = Path()
            ..moveTo(baseX, baseY)
            ..quadraticBezierTo(ctrl1X, ctrl1Y, tipX, tipY)
            ..quadraticBezierTo(ctrl2X, ctrl2Y, baseX, baseY)
            ..close();
          canvas.drawPath(petal, petalPaint);
        }
        break;
      case 'apple':
      default:
        final fill = Paint()
          ..color = isDark ? Colors.white : const Color(0xFF1C1C1E);
        final body = Path()
          ..moveTo(s * 0.50, s * 0.32)
          ..cubicTo(s * 0.25, s * 0.28, s * 0.18, s * 0.55, s * 0.28, s * 0.75)
          ..cubicTo(s * 0.35, s * 0.87, s * 0.44, s * 0.85, s * 0.50, s * 0.82)
          ..cubicTo(s * 0.56, s * 0.85, s * 0.65, s * 0.87, s * 0.73, s * 0.74)
          ..cubicTo(s * 0.83, s * 0.56, s * 0.76, s * 0.29, s * 0.50, s * 0.32)
          ..close();
        canvas.drawPath(body, fill);
        final leaf = Path()
          ..moveTo(s * 0.52, s * 0.27)
          ..cubicTo(s * 0.52, s * 0.14, s * 0.64, s * 0.11, s * 0.66, s * 0.12)
          ..cubicTo(s * 0.65, s * 0.22, s * 0.57, s * 0.27, s * 0.52, s * 0.27)
          ..close();
        canvas.drawPath(leaf, fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _OAuthBrandPainter oldDelegate) =>
      oldDelegate.providerId != providerId || oldDelegate.isDark != isDark;
}

/// Interactive 6-digit verification code input built on [TheavSurfaceStyle]
/// with full paste support, spring digit pop, and shake feedback.
class TheavOtpPinRow extends StatefulWidget {
  final int length;
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final int errorShakeCounter;
  final bool enabled;

  const TheavOtpPinRow({
    super.key,
    this.length = 6,
    required this.value,
    required this.onChanged,
    this.onCompleted,
    this.errorShakeCounter = 0,
    this.enabled = true,
  });

  @override
  State<TheavOtpPinRow> createState() => _TheavOtpPinRowState();
}

class _TheavOtpPinRowState extends State<TheavOtpPinRow>
    with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers = List.generate(
    widget.length,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _focusNodes = List.generate(
    widget.length,
    (_) => FocusNode(),
  );
  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  int _activeIndex = -1;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _focusNodes.length; i++) {
      final idx = i;
      _focusNodes[idx].addListener(() {
        if (!mounted) return;
        setState(() {
          if (_focusNodes[idx].hasFocus) {
            _activeIndex = idx;
          } else if (_activeIndex == idx) {
            _activeIndex = -1;
          }
        });
      });
    }
    _applyExternalValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant TheavOtpPinRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _applyExternalValue(widget.value);
    }
    if (widget.errorShakeCounter != oldWidget.errorShakeCounter &&
        widget.errorShakeCounter > 0) {
      HapticUtils.heavy();
      _shakeCtrl.forward(from: 0.0);
    }
  }

  void _applyExternalValue(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    _syncing = true;
    for (var i = 0; i < widget.length; i++) {
      final char = i < digits.length ? digits[i] : '';
      if (_controllers[i].text != char) {
        _controllers[i].text = char;
      }
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _emitCurrentValue({bool triggerCompletion = true}) {
    final combined = _controllers.map((c) => c.text).join();
    widget.onChanged(combined);
    if (triggerCompletion && combined.length == widget.length) {
      widget.onCompleted?.call(combined);
    }
  }

  void _handleChanged(int index, String raw) {
    if (_syncing) return;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      _syncing = true;
      var cursor = index;
      for (var i = 0; i < digits.length && cursor < widget.length; i++) {
        _controllers[cursor].text = digits[i];
        cursor++;
      }
      _syncing = false;
      final focusTarget = (cursor >= widget.length)
          ? widget.length - 1
          : cursor;
      _focusNodes[focusTarget].requestFocus();
      HapticUtils.selection();
      _emitCurrentValue();
      return;
    }

    if (digits.isEmpty) {
      if (_controllers[index].text.isNotEmpty) {
        _syncing = true;
        _controllers[index].clear();
        _syncing = false;
      }
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      _emitCurrentValue(triggerCompletion: false);
      return;
    }

    _syncing = true;
    _controllers[index].text = digits[0];
    _controllers[index].selection = const TextSelection.collapsed(offset: 1);
    _syncing = false;
    HapticUtils.selection();
    if (index + 1 < widget.length) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
    _emitCurrentValue();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final double t = _shakeCtrl.value;
        final double dx = _shakeCtrl.isAnimating
            ? math.sin(t * math.pi * 6.0) * (1.0 - t) * 10.0
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (i) {
          final filled = _controllers[i].text.isNotEmpty;
          final focused = _activeIndex == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: i == 0 || i == widget.length - 1 ? 2 : 3.5),
              child: SingleMotionBuilder(
                value: filled ? 1.03 : 1.0,
                motion: const Motion.bouncySpring(snapToEnd: true),
                builder: (context, scale, cellChild) =>
                    Transform.scale(scale: scale, child: cellChild),
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: style.cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: focused
                          ? palette.primary
                          : (filled
                              ? palette.primary.withValues(alpha: 0.55)
                              : style.hairlineBorder),
                      width: focused ? 1.6 : 0.75,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: focused
                            ? palette.primary.withValues(alpha: 0.14)
                            : Colors.black.withValues(
                                alpha: style.isDark ? 0.22 : 0.06,
                              ),
                        blurRadius: focused ? 10 : 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.backspace &&
                          _controllers[i].text.isEmpty &&
                          i > 0) {
                        _controllers[i - 1].clear();
                        _focusNodes[i - 1].requestFocus();
                        _emitCurrentValue(triggerCompletion: false);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      enabled: widget.enabled,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: i + 1 == widget.length
                          ? TextInputAction.done
                          : TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      maxLength: widget.length,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: palette.onSurface,
                      ),
                      decoration: const InputDecoration.collapsed(hintText: ''),
                      buildCounter: (
                        _, {
                        required int currentLength,
                        required bool isFocused,
                        int? maxLength,
                      }) =>
                          null,
                      onChanged: (val) => _handleChanged(i, val),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Compact floating capsule indicator showing step progress (`1 / 3`) for wizards.
class TheavStepProgressPill extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const TheavStepProgressPill({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final clampedStep = currentStep.clamp(1, math.max(1, totalSteps));
    final double targetProgress =
        totalSteps > 0 ? (clampedStep / totalSteps).clamp(0.0, 1.0) : 1.0;

    return TheavFloatingSurface(
      borderRadius: 20.0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$clampedStep / $totalSteps',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: palette.onSurface.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(2.5),
            ),
            alignment: Alignment.centerLeft,
            child: SingleMotionBuilder(
              value: targetProgress,
              motion: const Motion.cupertino(),
              builder: (context, progress, _) => FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final SpringDescription _kAuthStepSpring = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 520.0,
  ratio: 1.0,
);

const Tolerance _kAuthStepTolerance = Tolerance(
  distance: 6e-3,
  velocity: 3e-2,
);

/// Zero-delay shader-safe step viewport driven by critically damped spring
/// physics without any [Opacity] or [FadeTransition] wrapping glass widgets.
class TheavStepViewport extends StatefulWidget {
  final int stepIndex;
  final bool forward;
  final Widget child;

  const TheavStepViewport({
    super.key,
    required this.stepIndex,
    this.forward = true,
    required this.child,
  });

  @override
  State<TheavStepViewport> createState() => _TheavStepViewportState();
}

class _TheavStepViewportState extends State<TheavStepViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController.unbounded(
    vsync: this,
  )..value = 1.0;

  Widget? _outgoingChild;
  int? _outgoingStep;
  double _dir = 1.0;

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((status) {
      if (status.isCompleted && _outgoingChild != null && mounted) {
        setState(() {
          _outgoingChild = null;
          _outgoingStep = null;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant TheavStepViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stepIndex != oldWidget.stepIndex) {
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _outgoingChild = null;
        _outgoingStep = null;
        _ctrl.value = 1.0;
        return;
      }
      _outgoingChild = KeyedSubtree(
        key: ValueKey<int>(oldWidget.stepIndex),
        child: oldWidget.child,
      );
      _outgoingStep = oldWidget.stepIndex;
      _dir = widget.forward ? 1.0 : -1.0;
      _ctrl.animateWith(
        SpringSimulation(
          _kAuthStepSpring,
          0.0,
          1.0,
          1.2,
          tolerance: _kAuthStepTolerance,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = KeyedSubtree(
      key: ValueKey<int>(widget.stepIndex),
      child: widget.child,
    );

    if (_outgoingChild == null || _outgoingStep == widget.stepIndex) {
      return ClipRect(child: incoming);
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final double t = _ctrl.value.clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.passthrough,
            children: [
              FractionalTranslation(
                translation: Offset(-0.28 * t * _dir, 0.0),
                child: IgnorePointer(child: _outgoingChild),
              ),
              FractionalTranslation(
                translation: Offset((1.0 - t) * _dir, 0.0),
                child: incoming,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Floating bottom action container rendered directly inside a [Stack] over a
/// full-bleed scrollable view so scrolled lists never clip at a hard seam.
class TheavFloatingBottomBar extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool keyboardAware;
  final bool showBottomEdgeBlur;

  const TheavFloatingBottomBar({
    super.key,
    required this.child,
    this.maxWidth = 640.0,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 16),
    this.keyboardAware = true,
    this.showBottomEdgeBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final viewInsetsBottom =
        keyboardAware ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    final bool useGlassEdge = showBottomEdgeBlur &&
        style.isGlass &&
        BlurUtils.shouldBlurMaterialHud(context);

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsetsBottom),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: useGlassEdge
                    ? LiquidGlassScrollEdge(
                        edge: LiquidGlassEdge.bottom,
                        style: LiquidGlassScrollEdgeStyle.soft,
                        blur: math.max(style.glassProvider?.blur ?? 8.0, 8.0),
                        color: Colors.transparent,
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              palette.background.withValues(alpha: 0.0),
                              palette.background.withValues(
                                alpha: style.isDark ? 0.54 : 0.62,
                              ),
                              palette.background.withValues(
                                alpha: style.isDark ? 0.84 : 0.88,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1.0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: padding,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Metadata descriptor for each supported Theaver UI language.
class TheavLanguageOption {
  final String code;
  final String nativeName;
  final String secondaryName;

  const TheavLanguageOption({
    required this.code,
    required this.nativeName,
    required this.secondaryName,
  });
}

const List<TheavLanguageOption> kTheavSupportedLanguages = [
  TheavLanguageOption(code: 'ru', nativeName: 'Русский', secondaryName: 'Russian'),
  TheavLanguageOption(code: 'en', nativeName: 'English', secondaryName: 'English'),
  TheavLanguageOption(code: 'es', nativeName: 'Español', secondaryName: 'Spanish'),
  TheavLanguageOption(code: 'fr', nativeName: 'Français', secondaryName: 'French'),
  TheavLanguageOption(code: 'de', nativeName: 'Deutsch', secondaryName: 'German'),
  TheavLanguageOption(code: 'it', nativeName: 'Italiano', secondaryName: 'Italian'),
  TheavLanguageOption(code: 'pt', nativeName: 'Português', secondaryName: 'Portuguese'),
  TheavLanguageOption(code: 'zh', nativeName: '中文', secondaryName: 'Chinese'),
  TheavLanguageOption(code: 'ja', nativeName: '日本語', secondaryName: 'Japanese'),
  TheavLanguageOption(code: 'ko', nativeName: '한국어', secondaryName: 'Korean'),
];

/// Compact button that morphs into the interface language picker menu via
/// [openTheavMorphPopover] without opening a heavy bottom sheet.
class TheavLanguageMorphButton extends StatelessWidget {
  final String? recommendedCode;
  final ValueChanged<String>? onSelected;
  final bool compactCircle;

  const TheavLanguageMorphButton({
    super.key,
    this.recommendedCode,
    this.onSelected,
    this.compactCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final currentCode = context.watch<LocaleProvider>().locale.languageCode;
    final currentOption = kTheavSupportedLanguages.firstWhere(
      (item) => item.code == currentCode,
      orElse: () => kTheavSupportedLanguages.first,
    );

    return TheavMorphMenuButton<String>(
      key: ValueKey<String>(
        compactCircle
            ? 'login_language_morph_btn'
            : 'onboarding_language_morph_btn',
      ),
      width: compactCircle ? 44.0 : null,
      height: compactCircle ? 44.0 : 42.0,
      padding: compactCircle
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 15),
      renderSurface: true,
      menuWidth: 256.0,
      menuHeight: 296.0,
      cornerRadius: 22.0,
      menuBuilder: (menuCtx, close) => _LanguageMorphMenuBody(
        recommendedCode: recommendedCode,
        onSelected: (code) {
          onSelected?.call(code);
          close(code);
        },
      ),
      child: compactCircle
          ? Text(
              currentCode.toUpperCase(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: palette.primary,
              ),
            )
          : Semantics(
              button: true,
              label: l10n.trOr('onboarding_change_language', 'Change language'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconoir.Language(
                    width: 17,
                    height: 17,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${l10n.trOr('onboarding_change_language', 'Change language')} · ${currentOption.nativeName}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  iconoir.NavArrowDown(
                    width: 15,
                    height: 15,
                    color: palette.subtext,
                  ),
                ],
              ),
            ),
    );
  }
}

/// Opens the compact morphing language picker anchored to [anchorContext].
Future<void> showLanguagePickerSheet(
  BuildContext anchorContext, {
  String? recommendedCode,
  ValueChanged<String>? onSelected,
}) async {
  await openTheavMorphPopover<String>(
    anchorContext: anchorContext,
    menuWidth: 256.0,
    menuHeight: 296.0,
    cornerRadius: 22.0,
    menuBuilder: (menuCtx, close) => _LanguageMorphMenuBody(
      recommendedCode: recommendedCode,
      onSelected: (code) {
        onSelected?.call(code);
        close(code);
      },
    ),
  );
}

class _LanguageMorphMenuBody extends StatelessWidget {
  final String? recommendedCode;
  final ValueChanged<String> onSelected;

  const _LanguageMorphMenuBody({
    this.recommendedCode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final localeProvider = context.read<LocaleProvider>();
    final currentCode = context.watch<LocaleProvider>().locale.languageCode;
    final resolvedRecommended =
        (recommendedCode != null && recommendedCode!.isNotEmpty)
            ? recommendedCode!
            : LocaleProvider.resolveSystemLanguageCode();

    final recommendedItem = kTheavSupportedLanguages.firstWhere(
      (item) => item.code == resolvedRecommended,
      orElse: () => kTheavSupportedLanguages.first,
    );
    final orderedItems = <TheavLanguageOption>[
      recommendedItem,
      ...kTheavSupportedLanguages.where(
        (item) => item.code != recommendedItem.code,
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              iconoir.Language(
                width: 17,
                height: 17,
                color: palette.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.trOr('onboarding_select_language', 'Language'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: palette.divider),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: orderedItems.length,
            separatorBuilder: (_, __) => Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 48,
              endIndent: 12,
              color: palette.divider,
            ),
            itemBuilder: (_, idx) {
              final item = orderedItems[idx];
              final bool isSelected = currentCode == item.code;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticUtils.selection();
                  localeProvider.setLocaleByCode(item.code);
                  onSelected(item.code);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      _LanguageCodeBadge(code: item.code),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.nativeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: palette.onSurface,
                              ),
                            ),
                            Text(
                              l10n.trOr(
                                'lang_name_${item.code}',
                                item.secondaryName,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.subtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TheavCheckCircle(selected: isSelected, size: 19),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LanguageCodeBadge extends StatelessWidget {
  final String code;

  const _LanguageCodeBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        code.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: palette.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Helper row for error banner presentation without standard Material cards.
class TheavAuthErrorBanner extends StatelessWidget {
  final String message;

  const TheavAuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: palette.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: palette.error.withValues(alpha: 0.35),
            width: 0.75,
          ),
        ),
        child: Row(
          children: [
            iconoir.WarningCircle(
              width: 18,
              height: 18,
              color: palette.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: palette.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
