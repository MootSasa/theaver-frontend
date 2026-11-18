import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Telegram-inspired Layer 1 solid inset group card with `0.5dp` hairline
/// perimeter border, indented internal dividers, and compact section header /
/// footer caption.
///
/// Never wraps scrollable card content in [LiquidGlassLens] or [BackdropFilter].
class TheavInsetGroup extends StatelessWidget {
  final String? header;
  final Widget? headerTrailing;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final double dividerIndent;
  final Color? backgroundColor;
  final bool showDividers;

  const TheavInsetGroup({
    super.key,
    required this.children,
    this.header,
    this.headerTrailing,
    this.footer,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.borderRadius = 18.0,
    this.dividerIndent = 54.0,
    this.backgroundColor,
    this.showDividers = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context, listen: false);
    final palette = style.palette;
    final effectiveBg = backgroundColor ?? style.cardSurface;
    final horizontalInset = margin.horizontal > 0 ? 16.0 : 4.0;

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((header != null && header!.isNotEmpty) || headerTrailing != null)
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalInset, 8, horizontalInset, 6),
              child: Row(
                children: [
                  if (header != null && header!.isNotEmpty)
                    Expanded(
                      child: Text(
                        header!,
                        style: TextStyle(
                          color: palette.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  if (headerTrailing != null) headerTrailing!,
                ],
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: effectiveBg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: palette.divider,
                width: 0.5,
              ),
              boxShadow: style.isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildSeparatedChildren(palette),
                ),
              ),
            ),
          ),
          if (footer != null && footer!.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalInset, 6, horizontalInset, 2),
              child: Text(
                footer!,
                style: TextStyle(
                  color: palette.subtext,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSeparatedChildren(TheavPalette palette) {
    if (children.isEmpty) return const [];
    if (!showDividers || children.length == 1) return children;
    final items = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: dividerIndent,
            endIndent: 16,
            color: palette.divider,
          ),
        );
      }
    }
    return items;
  }
}

/// Clean interactive row designed for [TheavInsetGroup] cards, sheets, and
/// settings menus.
class TheavListRow extends StatelessWidget {
  final Widget? leading;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String? valueText;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isDestructive;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  const TheavListRow({
    super.key,
    this.leading,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.valueText,
    this.trailing,
    this.showChevron = false,
    this.onTap,
    this.onLongPress,
    this.isDestructive = false,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    this.minHeight = 48.0,
  }) : assert(title != null || titleWidget != null);

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final Color foreground = isDestructive
        ? palette.error
        : (enabled
            ? palette.onSurface
            : palette.onSurface.withValues(alpha: 0.42));
    final Color secondary = enabled
        ? palette.subtext
        : palette.subtext.withValues(alpha: 0.45);

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: isDestructive ? palette.error : palette.primary,
                  size: 22,
                ),
                child: SizedBox(
                  width: 26,
                  child: Center(child: leading!),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget ??
                      Text(
                        title!,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                  if (subtitleWidget != null) ...[
                    const SizedBox(height: 2),
                    subtitleWidget!,
                  ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (valueText != null && valueText!.isNotEmpty) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  valueText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (showChevron) ...[
              const SizedBox(width: 6),
              iconoir.NavArrowRight(
                width: 18,
                height: 18,
                color: palette.subtext.withValues(alpha: 0.72),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null && onLongPress == null) {
      return content;
    }

    return InkWell(
      onTap: enabled && onTap != null
          ? () {
              HapticUtils.tap();
              onTap!();
            }
          : null,
      onLongPress: enabled ? onLongPress : null,
      splashColor: palette.primary.withValues(alpha: 0.08),
      highlightColor: palette.onSurface.withValues(alpha: 0.04),
      child: content,
    );
  }
}

/// Borderless Telegram-style inline text field intended for [TheavInsetGroup]
/// rows and modal forms (avoids heavy Material outlined boxes).
class TheavInlineTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? placeholder;
  final Widget? prefix;
  final Widget? suffix;
  final int? maxLength;
  final int maxLines;
  final int minLines;
  final bool showCounter;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final TextStyle? style;

  const TheavInlineTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.maxLength,
    this.maxLines = 1,
    this.minLines = 1,
    this.showCounter = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null && label!.isNotEmpty) ...[
            Text(
              label!,
              style: TextStyle(
                color: palette.subtext,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment:
                maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (prefix != null) ...[
                prefix!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  enabled: enabled,
                  readOnly: readOnly,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  inputFormatters: inputFormatters,
                  maxLength: maxLength,
                  maxLines: maxLines,
                  minLines: minLines,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  onTap: onTap,
                  cursorColor: palette.primary,
                  style: style ??
                      TextStyle(
                        color: palette.onSurface,
                        fontSize: 16,
                        height: 1.35,
                      ),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: TextStyle(
                      color: palette.subtext.withValues(alpha: 0.72),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    counterText: showCounter ? null : '',
                    counterStyle: TextStyle(
                      color: palette.subtext,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 8),
                suffix!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}
