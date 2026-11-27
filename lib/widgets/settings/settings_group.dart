import 'package:flutter/material.dart';
import '../design_system/theav_inset_group.dart';

/// Backward-compatible wrapper over [TheavInsetGroup] so existing settings
/// screens automatically inherit the dual-mode Layer 1 surface and `0.5dp`
/// [TheavPalette] hairline dividers.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  final String? footer;
  final EdgeInsetsGeometry margin;

  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return TheavInsetGroup(
      header: title,
      footer: footer,
      margin: margin,
      children: children,
    );
  }
}
