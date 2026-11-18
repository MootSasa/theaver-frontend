import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design_system/theav_overlays.dart';

/// Looks up [key] via [AppLocalizations] when mounted in [context], falling back
/// cleanly to [fallback] for hermetic widget tests or missing runtime locales.
String translateOrFallback(
  BuildContext context,
  String key,
  String fallback, [
  Map<String, String>? params,
]) {
  final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
  if (l10n != null) {
    final res = l10n.translate(key, params);
    if (res != key) return res;
  }
  var out = fallback;
  if (params != null) {
    params.forEach((k, v) => out = out.replaceAll('{$k}', v));
  }
  return out;
}

/// Shows a Material 3 + Liquid Glass adaptive modal bottom sheet.
Future<T?> showTheavGlassModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  String? title,
  bool showCloseButton = false,
}) {
  return showTheavModalSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    title: title,
    showCloseButton: showCloseButton,
  );
}

/// Shared bottom sheet surface matching Material 3 Matte and Liquid Glass modes.
class TheavGlassModalSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final bool showCloseButton;

  const TheavGlassModalSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
    this.title,
    this.showCloseButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return TheavModalSheet(
      padding: padding,
      title: title,
      showCloseButton: showCloseButton,
      child: child,
    );
  }
}
