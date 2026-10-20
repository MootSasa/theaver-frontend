import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/haptic_utils.dart';
import '../profile/reply_strip_painter.dart';

/// Interactive Collapsible Blockquote Widget.
///
/// Features a stylish accent strip on the left, card background, line-by-line smooth
/// reveal animation, and a firmly docked expand/collapse button at the bottom.
class CollapsibleBlockquoteWidget extends StatefulWidget {
  final String text;
  final Widget? child;
  final bool isCollapsible;
  final bool initialExpanded;
  final bool isDark;
  final bool isMe;
  final NameColorPreset? preset;
  final ReplyStripStyle? stripStyle;

  const CollapsibleBlockquoteWidget({
    Key? key,
    required this.text,
    this.child,
    this.isCollapsible = false,
    this.initialExpanded = false,
    required this.isDark,
    required this.isMe,
    this.preset,
    this.stripStyle,
  }) : super(key: key);

  @override
  State<CollapsibleBlockquoteWidget> createState() =>
      _CollapsibleBlockquoteWidgetState();
}

class _CollapsibleBlockquoteWidgetState
    extends State<CollapsibleBlockquoteWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curvedAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.initialExpanded ? 1.0 : 0.0,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    HapticUtils.tap();
    if (_controller.value > 0.5) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileTheme = context.watch<ProfileThemeProvider>();
    final effectivePreset = widget.preset ?? profileTheme.currentNameColorPreset;
    final effectiveStripStyle = widget.stripStyle ?? profileTheme.currentStripStyle;

    final cardBgColor = effectivePreset.getOpaqueCardBackgroundColor(widget.isDark);
    final primaryColor = effectivePreset.primaryColor;

    final quoteTextStyle = TextStyle(
      fontSize: 14,
      color: widget.isDark
          ? const Color(0xFFE2E8F0)
          : const Color(0xFF1C2530),
      height: 1.35,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Container padding horizontal: 8 + 8 = 16
        // ReplyStrip width: 3.5
        // Gap: 8
        // Quote icon right padding / margin: 18
        // Total non-text width: 45.5
        final double availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 360.0;
        final double maxContentWidth = (availableWidth - 45.5).clamp(10.0, double.infinity);

        final textDirection = Directionality.of(context);

        TextPainter collapsedPainter = TextPainter(
          text: TextSpan(text: widget.text, style: quoteTextStyle),
          textDirection: textDirection,
          maxLines: 3,
        )..layout(maxWidth: maxContentWidth);

        final fullPainter = TextPainter(
          text: TextSpan(text: widget.text, style: quoteTextStyle),
          textDirection: textDirection,
          maxLines: null,
        )..layout(maxWidth: maxContentWidth);

        final bool didExceed = collapsedPainter.didExceedMaxLines;
        final bool showToggle = widget.isCollapsible;

        if (widget.isCollapsible && !didExceed) {
          collapsedPainter = TextPainter(
            text: TextSpan(text: widget.text, style: quoteTextStyle),
            textDirection: textDirection,
            maxLines: 1,
          )..layout(maxWidth: maxContentWidth);
        }

        final double collapsedHeight = collapsedPainter.height;
        final double fullHeight = fullPainter.height;

        final double naturalTextWidth = showToggle
            ? math.max(collapsedPainter.width, fullPainter.width)
            : fullPainter.width;

        final double minCardWidth = showToggle ? 140.0 : 60.0;
        final double targetCardWidth = (naturalTextWidth + 45.5)
            .clamp(minCardWidth, availableWidth);

        return MetaData(
          metaData: 'block_element',
          child: Container(
            width: targetCardWidth,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: _curvedAnimation,
              builder: (context, child) {
                final double progress = showToggle ? _curvedAnimation.value : 1.0;
                final double currentTextHeight = showToggle
                    ? ui.lerpDouble(collapsedHeight, fullHeight, progress)!
                    : fullHeight;

                final bool isExpanded = progress > 0.5;

                final Widget quoteBody = widget.child ??
                    Text(
                      widget.text,
                      style: quoteTextStyle,
                    );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Main Quote Content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            right: 0,
                            child: iconoir.QuoteSolid(
                              color: primaryColor.withValues(alpha: 0.35),
                              width: 14,
                              height: 14,
                            ),
                          ),
                          if (!showToggle)
                            Stack(
                              children: [
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: 0,
                                  child: ReplyStripWidget(
                                    preset: effectivePreset,
                                    style: effectiveStripStyle,
                                    width: 3.5,
                                    borderRadius: 2,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 11.5, right: 14.0),
                                  child: quoteBody,
                                ),
                              ],
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: currentTextHeight,
                                  child: ReplyStripWidget(
                                    preset: effectivePreset,
                                    style: effectiveStripStyle,
                                    width: 3.5,
                                    borderRadius: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 14.0),
                                    child: SizedBox(
                                      height: currentTextHeight,
                                      child: ClipRect(
                                        child: (progress < 1.0 && currentTextHeight < fullHeight - 1.0)
                                            ? ShaderMask(
                                                shaderCallback: (Rect bounds) {
                                                  const double fadeHeight = 20.0;
                                                  final double fadeRatio = (bounds.height > fadeHeight)
                                                      ? (bounds.height - fadeHeight) / bounds.height
                                                      : 0.0;
                                                  return LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    stops: [0.0, fadeRatio, 1.0],
                                                    colors: const [
                                                      Colors.white,
                                                      Colors.white,
                                                      Colors.transparent,
                                                    ],
                                                  ).createShader(bounds);
                                                },
                                                blendMode: BlendMode.dstIn,
                                                child: SingleChildScrollView(
                                                  physics: const NeverScrollableScrollPhysics(),
                                                  child: quoteBody,
                                                ),
                                              )
                                            : SingleChildScrollView(
                                                physics: const NeverScrollableScrollPhysics(),
                                                child: quoteBody,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    // Firmly docked expand/collapse footer button
                    if (showToggle)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: primaryColor.withValues(alpha: 0.12),
                              width: 0.5,
                            ),
                          ),
                          color: primaryColor.withValues(alpha: 0.04),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _toggleExpand,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isExpanded
                                        ? context.l10n.translate('format_collapsed_state')
                                        : context.l10n.translate('format_expand'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Transform.rotate(
                                    angle: progress * 3.141592653589793,
                                    child: iconoir.NavArrowDown(
                                      width: 14,
                                      height: 14,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
