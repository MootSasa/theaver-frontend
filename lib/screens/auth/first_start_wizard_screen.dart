import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
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

const List<String> _kGreetingKeys = [
  'onboarding_greeting_1',
  'onboarding_greeting_2',
  'onboarding_greeting_3',
  'onboarding_greeting_4',
  'onboarding_greeting_5',
  'onboarding_greeting_6',
  'onboarding_greeting_7',
];

const List<String> _kGreetingFallbacks = [
  'Hey there! Come on in, make yourself at home',
  'Oh, hi. Ready to make it yours?',
  'Finally, a messenger that feels right',
  'Welcome to Theaver',
  'Glad you made it here',
  'Your calm space to stay connected',
  'Let us set the vibe from second one',
];

/// First-run onboarding wizard shown once before sign-in when no accounts exist:
/// Step 0: Expressive dissolving greeting hero with a compact morph language button.
/// Step 1: Real app interactive preview with ThemeMode, Material/Glass Lite/Liquid Glass,
///         brightness-filtered palettes, and a floating bottom CTA over the scroll view.
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
  bool _navigating = false;
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

  void _completeAndProceedToLogin() {
    if (_navigating) return;
    _navigating = true;
    HapticUtils.tap();
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool(kOnboardingWizardCompletedPrefKey, true))
          .catchError((_) => false),
    );
    final nav = Navigator.of(context);
    final route = SwipeBackPageRoute<void>(
      builder: (_) => LoginScreen(
        initialCountryCode: _detectedCountryCode,
      ),
    );
    if (nav.canPop()) {
      unawaited(nav.pushReplacement(route));
    } else {
      unawaited(nav.pushAndRemoveUntil(route, (r) => false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final screenStack = Stack(
      fit: StackFit.expand,
      children: [
        const TheavAuthWallpaperBackground(),
        TheavStepViewport(
          stepIndex: _step,
          forward: _stepForward,
          child: _step == 0
              ? _buildWelcomeStep(context, l10n, palette)
              : _buildAppearanceStep(context, l10n, palette),
        ),
      ],
    );

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 1) {
          _goToStep(0);
        }
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: BackdropGroup.of(context) == null
            ? BackdropGroup(child: screenStack)
            : screenStack,
      ),
    );
  }

  Widget _buildWelcomeStep(
    BuildContext context,
    AppLocalizations l10n,
    TheavPalette palette,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final bool isWide = w >= 840;
        final double greetingFontSize = (w * 0.056).clamp(38.0, 62.0);
        final double heroMaxWidth =
            isWide ? 940.0 : (w >= 600 ? 720.0 : 540.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 48 : 28,
                    36,
                    isWide ? 48 : 28,
                    152,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: heroMaxWidth),
                      child: _DissolvingGreetingHero(
                        l10n: l10n,
                        palette: palette,
                        fontSize: greetingFontSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TheavFloatingBottomBar(
              maxWidth: isWide ? 480 : 540,
              showBottomEdgeBlur: false,
              padding: EdgeInsets.fromLTRB(16, 8, 16, isWide ? 28 : 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: TheavLanguageMorphButton(
                      recommendedCode: _recommendedLang,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TheavSpringButton(
                    label: l10n.trOr('onboarding_continue', 'Continue'),
                    trailing: iconoir.NavArrowRight(
                      width: 18,
                      height: 18,
                      color: palette.onPrimary,
                    ),
                    onPressed: () => _goToStep(1),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildAppearanceControlCards({
    required AppLocalizations l10n,
    required TheavPalette palette,
    required ThemeProvider themeProvider,
    required LiquidGlassProvider? glassProvider,
    required GlassMode glassMode,
    required bool glassSupported,
    required List<TheavTheme> carouselThemes,
    required TheavTheme activeTheme,
    EdgeInsets cardMargin =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    EdgeInsets stripPadding = const EdgeInsets.symmetric(horizontal: 16),
  }) {
    final double headerHorizontalInset =
        cardMargin.horizontal > 0 ? 16.0 + cardMargin.left : 20.0;
    return [
      TheavInsetGroup(
        margin: cardMargin,
        header: l10n.trOr('onboarding_theme_mode_header', 'Color scheme'),
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TheavSegmentedControl<ThemeMode>(
              selected: themeProvider.themeMode,
              expand: true,
              height: 40,
              useGlass: false,
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
          margin: cardMargin,
          header: l10n.trOr('onboarding_surface_style_header', 'Interface style'),
          footer: l10n.trOr(
            'onboarding_surface_style_footer',
            'Scroll the preview above to compare matte Material surfaces and live Liquid Glass refraction.',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TheavSegmentedControl<GlassMode>(
                selected: glassMode,
                expand: true,
                height: 40,
                useGlass: false,
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
        padding: EdgeInsets.fromLTRB(
          headerHorizontalInset,
          6,
          headerHorizontalInset,
          6,
        ),
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
        themes: carouselThemes,
        activeTheme: activeTheme,
        activePrimary: palette.primary,
        padding: stripPadding,
        onThemeSelected: (t) async {
          HapticUtils.selection();
          await themeProvider.setActiveTheme(
            t,
            syncCounterpart: true,
            preserveSystemMode: true,
          );
        },
      ),
    ];
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
    final carouselThemes = TheavThemeService.builtInThemesForBrightness(isDark);

    final glassMode = glassProvider?.mode ?? GlassMode.disabled;
    final glassSupported = glassProvider?.isSupported ?? false;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;

    final Widget header = SettingsFloatingHeader(
      title: l10n.trOr('onboarding_step_appearance_title', 'Appearance'),
      showBackButton: true,
      onBack: () => _goToStep(0),
      actions: [
        SettingsHeaderAction(
          tooltip: '2 / 2',
          child: Text(
            '2/2',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: palette.primary,
            ),
          ),
          onTap: null,
        ),
      ],
    );

    final Widget continueButton = TheavSpringButton(
      label: l10n.trOr('onboarding_continue_to_login', 'Continue to Sign In'),
      trailing: iconoir.NavArrowRight(
        width: 18,
        height: 18,
        color: palette.onPrimary,
      ),
      onPressed: _completeAndProceedToLogin,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 860;
        if (isWide) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1220),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 11,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                0,
                                topClearance + 14,
                                0,
                                math.max(20.0, safeBottom + 16.0),
                              ),
                              child: LayoutBuilder(
                                builder: (ctx, leftBox) {
                                  final double widePreviewHeight =
                                      (leftBox.maxHeight - 54.0)
                                          .clamp(280.0, 660.0);
                                  return Center(
                                    child: RealAppAppearancePreview(
                                      height: widePreviewHeight,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            flex: 10,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  child: SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                    padding: EdgeInsets.fromLTRB(
                                      0,
                                      topClearance + 14,
                                      0,
                                      108 + safeBottom,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _buildAppearanceControlCards(
                                        l10n: l10n,
                                        palette: palette,
                                        themeProvider: themeProvider,
                                        glassProvider: glassProvider,
                                        glassMode: glassMode,
                                        glassSupported: glassSupported,
                                        carouselThemes: carouselThemes,
                                        activeTheme: activeTheme,
                                        cardMargin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                        stripPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                TheavFloatingBottomBar(
                                  maxWidth: double.infinity,
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 18, 4, 20),
                                  child: continueButton,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: header,
              ),
            ],
          );
        }

        final previewHeight = (screenHeight * 0.41).clamp(288.0, 384.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  0,
                  topClearance + 8,
                  0,
                  108 + safeBottom,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: RealAppAppearancePreview(height: previewHeight),
                        ),
                        const SizedBox(height: 14),
                        ..._buildAppearanceControlCards(
                          l10n: l10n,
                          palette: palette,
                          themeProvider: themeProvider,
                          glassProvider: glassProvider,
                          glassMode: glassMode,
                          glassSupported: glassSupported,
                          carouselThemes: carouselThemes,
                          activeTheme: activeTheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: header,
            ),
            TheavFloatingBottomBar(
              maxWidth: 640,
              child: continueButton,
            ),
          ],
        );
      },
    );
  }
}

class _DissolvingGreetingHero extends StatefulWidget {
  final AppLocalizations l10n;
  final TheavPalette palette;
  final double fontSize;

  const _DissolvingGreetingHero({
    required this.l10n,
    required this.palette,
    this.fontSize = 38.0,
  });

  @override
  State<_DissolvingGreetingHero> createState() =>
      _DissolvingGreetingHeroState();
}

class _DissolvingGreetingHeroState extends State<_DissolvingGreetingHero>
    with SingleTickerProviderStateMixin {
  late final List<int> _order = _buildShuffledOrder();
  int _cursor = 0;
  int? _previousOrderPos;
  Timer? _cycleTimer;

  late final AnimationController _dissolveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1.0,
  );

  static List<int> _buildShuffledOrder() {
    final indices = List<int>.generate(_kGreetingKeys.length, (i) => i);
    indices.shuffle(math.Random());
    return indices;
  }

  @override
  void initState() {
    super.initState();
    _dissolveCtrl.addStatusListener((status) {
      if (status.isCompleted && _previousOrderPos != null && mounted) {
        setState(() => _previousOrderPos = null);
      }
    });
    _cycleTimer = Timer.periodic(
      const Duration(milliseconds: 3800),
      (_) => _advanceGreeting(),
    );
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _dissolveCtrl.dispose();
    super.dispose();
  }

  void _advanceGreeting({bool userTapped = false}) {
    if (!mounted) return;
    if (userTapped) {
      HapticUtils.selection();
      _cycleTimer?.cancel();
      _cycleTimer = Timer.periodic(
        const Duration(milliseconds: 3800),
        (_) => _advanceGreeting(),
      );
    }
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final prev = _cursor;
    final next = (_cursor + 1) % _order.length;
    setState(() {
      _previousOrderPos = disableAnim ? null : prev;
      _cursor = next;
    });
    if (disableAnim) {
      _dissolveCtrl.value = 1.0;
    } else {
      _dissolveCtrl.forward(from: 0.0);
    }
  }

  String _phraseAt(int orderPos) {
    final idx = _order[orderPos % _order.length];
    return widget.l10n.trOr(_kGreetingKeys[idx], _kGreetingFallbacks[idx]);
  }

  Widget _buildGreetingText(
    String text, {
    Key? key,
  }) {
    return Text(
      text,
      key: key,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: widget.fontSize >= 48 ? -1.3 : -0.9,
        height: 1.12,
        color: widget.palette.onSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPhrase = _phraseAt(_cursor);
    final prevPos = _previousOrderPos;

    if (prevPos == null || _dissolveCtrl.isCompleted) {
      return GestureDetector(
        key: const ValueKey<String>('onboarding_greeting_hero'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _advanceGreeting(userTapped: true),
        child: _buildGreetingText(
          currentPhrase,
          key: const ValueKey<String>('onboarding_greeting_text'),
        ),
      );
    }

    final outgoingPhrase = _phraseAt(prevPos);
    return GestureDetector(
      key: const ValueKey<String>('onboarding_greeting_hero'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _advanceGreeting(userTapped: true),
      child: AnimatedBuilder(
        animation: _dissolveCtrl,
        builder: (context, _) {
          final double t = Curves.easeInOutCubic.transform(_dissolveCtrl.value);
          final double outOpacity = (1.0 - t * 1.15).clamp(0.0, 1.0);
          final double inOpacity = ((t - 0.12) / 0.88).clamp(0.0, 1.0);
          final double outSigma = 4.5 * t;
          final double inSigma = 4.5 * (1.0 - t);

          return Stack(
            alignment: Alignment.center,
            children: [
              if (outOpacity > 0.01)
                Opacity(
                  opacity: outOpacity,
                  child: Transform.scale(
                    scale: 1.0 + 0.02 * t,
                    child: outSigma > 0.25
                        ? ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: outSigma,
                              sigmaY: outSigma,
                            ),
                            child: _buildGreetingText(outgoingPhrase),
                          )
                        : _buildGreetingText(outgoingPhrase),
                  ),
                ),
              if (inOpacity > 0.01)
                Opacity(
                  opacity: inOpacity,
                  child: Transform.scale(
                    scale: 0.98 + 0.02 * t,
                    child: inSigma > 0.25
                        ? ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: inSigma,
                              sigmaY: inSigma,
                            ),
                            child: _buildGreetingText(
                              currentPhrase,
                              key: const ValueKey<String>(
                                'onboarding_greeting_text',
                              ),
                            ),
                          )
                        : _buildGreetingText(
                            currentPhrase,
                            key: const ValueKey<String>(
                              'onboarding_greeting_text',
                            ),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
