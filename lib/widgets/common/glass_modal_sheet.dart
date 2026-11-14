import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/power_saving_provider.dart';

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
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) => TheavGlassModalSheet(child: builder(ctx)),
  );
}

/// Shared bottom sheet surface matching Material 3 and Liquid Glass modes.
class TheavGlassModalSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const TheavGlassModalSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    bool glassEnabled = false;
    try {
      glassEnabled = context.watch<LiquidGlassProvider>().enabled;
    } catch (_) {}

    final allowBlur = glassEnabled && PowerSavingProvider.instance.allowBlur;
    final bgColor = glassEnabled
        ? (isDark
            ? const Color(0xFF1A1B22).withValues(alpha: 0.84)
            : Colors.white.withValues(alpha: 0.88))
        : (isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surface);

    final borderColor = glassEnabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.08))
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.45);

    Widget content = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );

    if (allowBlur) {
      content = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: content,
        ),
      );
    }

    return content;
  }
}
