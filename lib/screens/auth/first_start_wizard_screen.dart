import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/session_bootstrap_coordinator.dart';
import '../../services/theav_theme_service.dart';
import '../../theme/theme_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/auth/theav_auth_primitives.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/theme/real_app_appearance_preview.dart';
import '../../widgets/theme/theme_carousel_strip.dart';
import 'login_screen.dart';

const String kOnboardingWizardCompletedPrefKey =
    SessionBootstrapCoordinator.onboardingCompletedPrefKey;

/// First-run onboarding wizard shown once before sign-in when no accounts exist:
/// Step 0: Interface language selection (OS locale + GeoIP recommendation).
/// Step 1: Real app interactive preview with ThemeMode, Material/Glass Lite/Liquid Glass, and built-in palettes.
class FirstStartWizardScreen extends StatefulWidget {
  final int initialStep;

  const FirstStartWizardScreen({
    super.key,
    this.initialStep = 0,
  });

  @override
  State<FirstStartWizardScreen> createState() => _FirstStartWizardScreenState();
}

class _FirstStartWizardScreenState extends State<FirstStartWizardScreen> {
  late int _step = widget.initialStep.clamp(0, 1);
  bool _stepForward = true;
  bool _finishing = false;
  String? _recommendedLang;
  String? _detectedCountryCode;

  @override
  void initState() {
    super.initState();
    _loadRegionDefaults();
  }

  Future<void> _loadRegionDefaults() async {
    final cfg = await AuthService.fetchAuthProviders();
    if (!mounted) return;
    final localeProvider = context.read<LocaleProvider>();
    await localeProvider.ready;
    if (!mounted) return;
    setState(() {
      _detectedCountryCode = cfg.countryCode;
      _recommendedLang = cfg.recommendedLanguage.isNotEmpty
          ? cfg.recommendedLanguage
          : LocaleProvider.resolveSystemLanguageCode();
    });
    if (!localeProvider.hasExplicitSelection &&
        cfg.recommendedLanguage.isNotEmpty &&
        LocaleProvider.supportedLanguageCodes.contains(cfg.recommendedLanguage)) {
      await localeProvider.setLocaleByCode(cfg.recommendedLanguage);
    }
  }

  void _goToStep(int next) {
    if (_step == next) return;
    HapticUtils.tap();
    setState(() {
      _stepForward = next > _step;
      _step = next.clamp(0, 1);
    });
  }

  Future<void> _completeAndProceedToLogin() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOnboardingWizardCompletedPrefKey, true);
      if (!mounted) return;
      final nav = Navigator.of(context);
      final route = SwipeBackPageRoute<void>(
        builder: (_) => LoginScreen(
          initialCountryCode: _detectedCountryCode,
        ),
      );
      if (nav.canPop()) {
        await nav.pushReplacement(route);
      } else {
        await nav.pushAndRemoveUntil(route, (r) => false);
      }
    } finally {
      if (mounted) {
        setState(() => _finishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeCode = context.watch<LocaleProvider>().locale.languageCode;
    final palette = context.theav;

    final String headerTitle = _step == 0
        ? l10n.trOr('onboarding_step_language_title', 'Language')
        : l10n.trOr('onboarding_step_appearance_title', 'Appearance');

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 1) {
          _goToStep(0);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const TheavAuthWallpaperBackground(),
          SettingsFloatingScaffold(
            backgroundColor: Colors.transparent,
            title: headerTitle,
            showBackButton: _step == 1 || Navigator.of(context).canPop(),
            onBack: () {
              if (_step == 1) {
                _goToStep(0);
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            actions: [
              SettingsHeaderAction(
                tooltip: '${_step + 1} / 2',
                child: Text(
                  '${_step + 1}/2',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
                onTap: null,
              ),
            ],
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: TheavStepViewport(
                    stepIndex: _step,
                    forward: _stepForward,
                    child: _step == 0
                        ? _buildLanguageStep(context, l10n, localeCode, palette)
                        : _buildAppearanceStep(context, l10n, palette),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageStep(
    BuildContext context,
    AppLocalizations l10n,
    String currentCode,
    TheavPalette palette,
  ) {
    final localeProvider = context.read<LocaleProvider>();
    final resolvedRecommended = _recommendedLang ??
        LocaleProvider.resolveSystemLanguageCode();
    final recommendedOption = kTheavSupportedLanguages.firstWhere(
      (item) => item.code == resolvedRecommended,
      orElse: () => kTheavSupportedLanguages.first,
    );
    final remaining = kTheavSupportedLanguages
        .where((item) => item.code != recommendedOption.code)
        .toList();
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, topClearance + 8, 0, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.trOr(
                          'onboarding_welcome_headline',
                          'Welcome to Theaver',
                        ),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.trOr(
                          'onboarding_language_subtitle',
                          'Choose the interface language. You can change it anytime in Settings.',
                        ),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          color: palette.subtext,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TheavInsetGroup(
                  header: l10n.trOr(
                    'onboarding_recommended_language',
                    'Recommended',
                  ),
                  children: [
                    TheavListRow(
                      leading: _WizardLangBadge(code: recommendedOption.code),
                      title: recommendedOption.nativeName,
                      subtitle: recommendedOption.secondaryName,
                      trailing: TheavCheckCircle(
                        selected: currentCode == recommendedOption.code,
                      ),
                      onTap: () {
                        HapticUtils.selection();
                        localeProvider.setLocaleByCode(recommendedOption.code);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TheavInsetGroup(
                  header: l10n.trOr(
                    'onboarding_all_languages',
                    'All languages',
                  ),
                  children: [
                    for (final item in remaining)
                      TheavListRow(
                        leading: _WizardLangBadge(code: item.code),
                        title: item.nativeName,
                        subtitle: item.secondaryName,
                        trailing: TheavCheckCircle(
                          selected: currentCode == item.code,
                        ),
                        onTap: () {
                          HapticUtils.selection();
                          localeProvider.setLocaleByCode(item.code);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TheavSpringButton(
            label: l10n.trOr('onboarding_continue', 'Continue'),
            trailing: iconoir.NavArrowRight(
              width: 18,
              height: 18,
              color: palette.onPrimary,
            ),
            onPressed: () => _goToStep(1),
          ),
        ),
      ],
    );
  }

  Widget _buildAppearanceStep(
    BuildContext context,
    AppLocalizations l10n,
    TheavPalette palette,
  ) {
    final themeProvider = context.watch<ThemeProvider>();
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTheme =
        isDark ? themeProvider.activeDarkTheme : themeProvider.activeLightTheme;
    final glassMode = glassProvider?.mode ?? GlassMode.disabled;
    final glassSupported = glassProvider?.isSupported ?? false;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final previewHeight = (screenHeight * 0.41).clamp(288.0, 384.0);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, topClearance + 6, 0, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RealAppAppearancePreview(height: previewHeight),
                ),
                const SizedBox(height: 14),
                TheavInsetGroup(
                  header: l10n.trOr('onboarding_theme_mode_header', 'Color scheme'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: TheavSegmentedControl<ThemeMode>(
                        selected: themeProvider.themeMode,
                        expand: true,
                        height: 40,
                        useGlass: glassMode != GlassMode.disabled,
                        onChanged: (mode) {
                          HapticUtils.selection();
                          switch (mode) {
                            case ThemeMode.system:
                              themeProvider.setToSystem();
                              break;
                            case ThemeMode.light:
                              themeProvider.setToLight();
                              break;
                            case ThemeMode.dark:
                              themeProvider.setToDark();
                              break;
                          }
                        },
                        options: [
                          TheavSegmentOption(
                            value: ThemeMode.system,
                            label: l10n.trOr('theme_system', 'System'),
                            icon: iconoir.Laptop(
                              width: 15,
                              height: 15,
                              color: palette.onSurface,
                            ),
                          ),
                          TheavSegmentOption(
                            value: ThemeMode.light,
                            label: l10n.trOr('theme_light', 'Light'),
                            icon: iconoir.SunLight(
                              width: 15,
                              height: 15,
                              color: palette.onSurface,
                            ),
                          ),
                          TheavSegmentOption(
                            value: ThemeMode.dark,
                            label: l10n.trOr('theme_dark', 'Dark'),
                            icon: iconoir.HalfMoon(
                              width: 15,
                              height: 15,
                              color: palette.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (glassSupported) ...[
                  const SizedBox(height: 4),
                  TheavInsetGroup(
                    header: l10n.trOr(
                      'onboarding_surface_style_header',
                      'Interface style',
                    ),
                    footer: l10n.trOr(
                      'onboarding_surface_style_footer',
                      'Try scrolling the preview above to compare matte Material surfaces and live glass refraction.',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: TheavSegmentedControl<GlassMode>(
                          selected: glassMode,
                          expand: true,
                          height: 40,
                          useGlass: glassMode != GlassMode.disabled,
                          onChanged: (next) {
                            HapticUtils.selection();
                            glassProvider?.setMode(next);
                          },
                          options: [
                            TheavSegmentOption(
                              value: GlassMode.disabled,
                              label: l10n.trOr('glass_mode_material', 'Material'),
                            ),
                            TheavSegmentOption(
                              value: GlassMode.lite,
                              label: l10n.trOr('glass_mode_lite', 'Glass Lite'),
                            ),
                            TheavSegmentOption(
                              value: GlassMode.full,
                              label: l10n.trOr('glass_mode_full', 'Liquid Glass'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Text(
                    l10n.trOr('onboarding_palette_header', 'Color palette'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.subtext,
                    ),
                  ),
                ),
                ThemeCarouselStrip(
                  themes: TheavThemeService.builtInThemes,
                  activeTheme: activeTheme,
                  activePrimary: palette.primary,
                  onThemeSelected: (t) async {
                    HapticUtils.selection();
                    await themeProvider.setActiveTheme(t);
                    if (t.isDark && !isDark) {
                      await themeProvider.setToDark();
                    } else if (!t.isDark && isDark) {
                      await themeProvider.setToLight();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TheavSpringButton(
            label: l10n.trOr(
              'onboarding_continue_to_login',
              'Continue to Sign In',
            ),
            isLoading: _finishing,
            trailing: iconoir.NavArrowRight(
              width: 18,
              height: 18,
              color: palette.onPrimary,
            ),
            onPressed: _completeAndProceedToLogin,
          ),
        ),
      ],
    );
  }
}

class _WizardLangBadge extends StatelessWidget {
  final String code;

  const _WizardLangBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        code.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: palette.primary,
        ),
      ),
    );
  }
}
