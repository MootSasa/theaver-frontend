import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../screens/settings/theme_preview_screen.dart';
import '../services/deep_link_service.dart';
import '../services/settings_service.dart';
import '../services/theav_theme_service.dart';
import '../widgets/bot/thv_invoice_sheet.dart';
import '../widgets/browser/in_app_browser_sheet.dart';
import '../widgets/browser/safari_browser_dialogs.dart';
import 'entity_parser.dart';
import 'safari_url_safety.dart';

/// Unified URL router across messages, profiles, inline buttons, and Mini Apps.
class LinkOpener {
  LinkOpener._();

  @visibleForTesting
  static bool debugForceInAppSupportedForTest = false;

  @visibleForTesting
  static Future<void> Function(Uri uri)? debugExternalLauncherForTest;

  static bool get isInAppBrowserSupported =>
      debugForceInAppSupportedForTest ||
      (!kIsWeb && WebViewPlatform.instance != null);

  static String _normalizeRaw(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return trimmed;
    }
    return EntityParser.normalizeUrl(trimmed);
  }

  static Future<void> openUrl(
    BuildContext context,
    String rawUrl, {
    bool forceExternal = false,
    bool forceInApp = false,
    bool confirmExternalApp = false,
  }) async {
    final normalized = _normalizeRaw(rawUrl);
    if (normalized.isEmpty) return;

    // 1. Native THV Bot Invoice links
    final invoiceSlug = extractThvInvoiceSlug(normalized);
    if (invoiceSlug != null) {
      if (!context.mounted) return;
      await openThvInvoiceSheet(context, slugOrUrl: invoiceSlug);
      return;
    }

    // 2. Shared Theaver Theme previews
    final themeCode = TheavThemeService.extractThemeCode(normalized);
    if (themeCode != null) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThemePreviewScreen(themeCode: themeCode),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) return;

    final schemeInfo = SafariUrlSafetyAnalyzer.classifyExternalUri(uri);
    if (schemeInfo.kind == ExternalSchemeKind.blocked) {
      return;
    }

    // 3. Internal Theaver Deep Links (/u/..., /join/..., /c/..., theaver://...)
    if (DeepLinkService.parseUri(uri) != null) {
      await DeepLinkService().handleLink(uri);
      return;
    }

    final scheme = uri.scheme.toLowerCase();
    final bool isWebHttp = scheme == 'http' || scheme == 'https';
    if (isWebHttp) {
      final safety = SafariUrlSafetyAnalyzer.analyzeUrl(uri.toString());
      if (safety.isSuspiciousHomograph && context.mounted) {
        final bool proceed = await showSafariSuspiciousLinkDialog(
          context,
          info: safety,
        );
        if (!proceed || !context.mounted) return;
      }
    } else if (confirmExternalApp ||
        schemeInfo.kind == ExternalSchemeKind.appIntent ||
        schemeInfo.kind == ExternalSchemeKind.customApp) {
      if (context.mounted) {
        final bool proceed = await showSafariExternalAppDialog(
          context,
          uri: uri,
        );
        if (!proceed || !context.mounted) return;
      }
    }

    final bool shouldOpenInApp = isWebHttp &&
        !forceExternal &&
        isInAppBrowserSupported &&
        (forceInApp || SettingsService().inAppBrowser);

    if (shouldOpenInApp && context.mounted) {
      await openInAppBrowser(context, url: uri.toString());
      return;
    }

    try {
      if (debugExternalLauncherForTest != null) {
        await debugExternalLauncherForTest!(uri);
      } else if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('LinkOpener failed for $uri: $e');
    }
  }
}
