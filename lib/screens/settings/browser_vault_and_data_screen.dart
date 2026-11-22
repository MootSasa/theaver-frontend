import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/browser_data_service.dart';
import '../../services/browser_site_settings_service.dart';
import '../../services/browser_vault_auth_gate.dart';
import '../../services/browser_vault_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../../widgets/browser/safari_library_sheet.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';

Timer? _sharedClipboardWipeTimer;
String? _lastCopiedSecretValue;

void _copyPasswordWithAutoWipe(BuildContext context, String password) {
  Clipboard.setData(ClipboardData(text: password));
  HapticUtils.selection();
  _lastCopiedSecretValue = password;
  _sharedClipboardWipeTimer?.cancel();
  _sharedClipboardWipeTimer = Timer(const Duration(seconds: 60), () async {
    final expected = _lastCopiedSecretValue;
    if (expected == null) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == expected) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {}
    if (_lastCopiedSecretValue == expected) {
      _lastCopiedSecretValue = null;
    }
  });
  if (context.mounted) {
    GlassToastService().show(
      context,
      'Пароль скопирован (очистится через 60 с)',
      icon: Icons.check_rounded,
    );
  }
}

/// Opens Theaver's Browser Passwords, Autofill, Cookie & Site Settings hub
/// inside a Safari Liquid Glass modal sheet (used directly from the browser).
Future<void> showBrowserVaultAndDataSheet(
  BuildContext context, {
  int initialSection = 0,
  String? initialSearchQuery,
  bool autoUnlockPasswords = true,
}) async {
  await Future.wait([
    BrowserVaultService.instance.ensureLoaded(),
    BrowserSiteSettingsService.instance.ensureLoaded(),
    BrowserDataService.instance.ensureLoaded(),
  ]);
  if (!context.mounted) return;
  await showTheavModalSheet<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.86,
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
    builder: (_) => _BrowserVaultHubContent(
      initialSection: initialSection,
      initialSearchQuery: initialSearchQuery,
      autoUnlockPasswords: autoUnlockPasswords,
      isModalSheet: true,
    ),
  );
}

/// Full-screen settings destination for Browser Passwords, Contact Autofill,
/// Cookie Policy, and Per-Site Permissions/Storage management.
class BrowserVaultAndDataScreen extends StatelessWidget {
  final int initialSection;
  final String? initialSearchQuery;
  final bool autoUnlockPasswords;

  const BrowserVaultAndDataScreen({
    super.key,
    this.initialSection = 0,
    this.initialSearchQuery,
    this.autoUnlockPasswords = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final String headerTitle =
        Localizations.of<AppLocalizations>(context, AppLocalizations)
                ?.translate('settings_browser_vault_title') ??
            'Пароли и данные браузера';
    final topInset = MediaQuery.paddingOf(context).top;

    return BackdropGroup(
      child: Scaffold(
        backgroundColor: style.palette.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: topInset + 56.0),
                child: _BrowserVaultHubContent(
                  initialSection: initialSection,
                  initialSearchQuery: initialSearchQuery,
                  autoUnlockPasswords: autoUnlockPasswords,
                  isModalSheet: false,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SettingsFloatingHeader(
                title: headerTitle,
                showBackButton: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserVaultHubContent extends StatefulWidget {
  final int initialSection;
  final String? initialSearchQuery;
  final bool autoUnlockPasswords;
  final bool isModalSheet;

  const _BrowserVaultHubContent({
    required this.initialSection,
    this.initialSearchQuery,
    required this.autoUnlockPasswords,
    required this.isModalSheet,
  });

  @override
  State<_BrowserVaultHubContent> createState() =>
      _BrowserVaultHubContentState();
}

class _BrowserVaultHubContentState extends State<_BrowserVaultHubContent> {
  late int _activeSection;
  late final PageController _pageCtrl;
  late final TextEditingController _searchCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  final ScrollController _passwordsScrollCtrl = ScrollController();
  final ScrollController _autofillScrollCtrl = ScrollController();
  final ScrollController _cookiesScrollCtrl = ScrollController();

  int? _programmaticTargetPage;
  String _searchQuery = '';
  bool _unlocked = false;
  bool _unlockInProgress = false;
  List<BrowserSavedCredential> _unlockedCredentials =
      <BrowserSavedCredential>[];
  bool _contactAutofillCardLoaded = false;
  bool _contactEnabled = true;
  BrowserContactProfile _savedContactProfile = const BrowserContactProfile();
  bool _hasSavedContactSnapshot = false;
  final ValueNotifier<bool> _contactDirtyNotifier = ValueNotifier<bool>(false);
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _activeSection = widget.initialSection.clamp(0, 2);
    _pageCtrl = PageController(initialPage: _activeSection);
    _searchQuery = widget.initialSearchQuery?.trim() ?? '';
    _searchCtrl = TextEditingController(text: _searchQuery);
    _nameCtrl = TextEditingController()..addListener(_syncContactDirtyFlag);
    _emailCtrl = TextEditingController()..addListener(_syncContactDirtyFlag);
    _phoneCtrl = TextEditingController()..addListener(_syncContactDirtyFlag);

    BrowserVaultService.instance.addListener(_onServiceChanged);
    BrowserSiteSettingsService.instance.addListener(_onServiceChanged);
    BrowserDataService.instance.addListener(_onServiceChanged);

    unawaited(_loadInitialState());
  }

  Future<void> _loadInitialState() async {
    await Future.wait([
      BrowserVaultService.instance.ensureLoaded(),
      BrowserSiteSettingsService.instance.ensureLoaded(),
      BrowserDataService.instance.ensureLoaded(),
    ]);
    final profile = await BrowserVaultService.instance.getContactProfile();
    if (!mounted) return;
    _savedContactProfile = profile;
    _hasSavedContactSnapshot = profile.fullName.trim().isNotEmpty ||
        profile.email.trim().isNotEmpty ||
        profile.phone.trim().isNotEmpty;
    _nameCtrl.text = profile.fullName;
    _emailCtrl.text = profile.email;
    _phoneCtrl.text = profile.phone;
    _syncContactDirtyFlag();
    setState(() {
      _contactEnabled = profile.enabled;
      _contactAutofillCardLoaded = true;
    });
    if (widget.autoUnlockPasswords && _activeSection == 0) {
      unawaited(_unlockPasswords());
    }
  }

  @override
  void dispose() {
    BrowserVaultService.instance.removeListener(_onServiceChanged);
    BrowserSiteSettingsService.instance.removeListener(_onServiceChanged);
    BrowserDataService.instance.removeListener(_onServiceChanged);
    _nameCtrl.removeListener(_syncContactDirtyFlag);
    _emailCtrl.removeListener(_syncContactDirtyFlag);
    _phoneCtrl.removeListener(_syncContactDirtyFlag);
    _contactDirtyNotifier.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordsScrollCtrl.dispose();
    _autofillScrollCtrl.dispose();
    _cookiesScrollCtrl.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  bool _computeHasUnsavedContactChanges() =>
      _nameCtrl.text.trim() != _savedContactProfile.fullName.trim() ||
      _emailCtrl.text.trim() != _savedContactProfile.email.trim() ||
      _phoneCtrl.text.trim() != _savedContactProfile.phone.trim();

  void _syncContactDirtyFlag() {
    final bool dirty = _computeHasUnsavedContactChanges();
    if (_contactDirtyNotifier.value != dirty) {
      _contactDirtyNotifier.value = dirty;
    }
  }

  void _selectSection(int idx) {
    if (_activeSection == idx) return;
    HapticUtils.selection();
    setState(() {
      _activeSection = idx;
      _programmaticTargetPage = idx;
    });
    if (!_pageCtrl.hasClients) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pageCtrl.jumpToPage(idx);
      _programmaticTargetPage = null;
    } else {
      _pageCtrl
          .animateToPage(
            idx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        if (mounted) {
          _programmaticTargetPage = null;
        }
      });
    }
  }

  void _handlePageChanged(int idx) {
    if (idx < 0 || idx > 2) return;
    if (_programmaticTargetPage != null) {
      if (idx == _programmaticTargetPage) {
        _programmaticTargetPage = null;
      }
      return;
    }
    if (_activeSection != idx) {
      HapticUtils.selection();
      setState(() => _activeSection = idx);
    }
  }

  void _clearSearch() {
    HapticUtils.selection();
    _searchCtrl.clear();
    if (_searchQuery.isNotEmpty) {
      setState(() => _searchQuery = '');
    }
  }

  Color _cardFill(TheavSurfaceStyle style) =>
      style.palette.onSurface.withValues(alpha: style.isDark ? 0.06 : 0.04);

  Color _dividerTint(TheavSurfaceStyle style) =>
      style.palette.onSurface.withValues(alpha: style.isDark ? 0.06 : 0.045);

  Widget _buildSafariPillButton({
    Key? buttonKey,
    required Color backgroundColor,
    required Color foregroundColor,
    required String label,
    IconData? icon,
    double height = 34.0,
    double horizontalPadding = 12.0,
    double fontSize = 13.0,
    VoidCallback? onTap,
  }) {
    final double radius = height / 2.0;
    return Material(
      key: buttonKey,
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: height <= 30.0 ? 15.0 : 16.0, color: foregroundColor),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalHeaderRow(
    BuildContext sheetCtx, {
    required String title,
    Key? closeButtonKey,
    Widget? trailing,
  }) {
    final palette = TheavSurfaceStyle.of(sheetCtx).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Tooltip(
            message: 'Закрыть',
            child: GestureDetector(
              key: closeButtonKey,
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticUtils.tap();
                Navigator.of(sheetCtx).maybePop();
              },
              child: SizedBox(
                width: 34,
                height: 34,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: palette.subtext,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.25,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  InputDecoration _transparentFieldDecoration(
    TheavPalette palette, {
    required String hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: palette.subtext.withValues(alpha: 0.78),
        fontSize: 14.5,
      ),
      filled: false,
      fillColor: Colors.transparent,
      hoverColor: Colors.transparent,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 11),
      suffixIcon: suffixIcon,
    );
  }

  Widget _buildSheetFieldRow({
    Key? fieldKey,
    required TheavPalette palette,
    required IconData icon,
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hintText,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.subtext),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              obscureText: obscureText,
              cursorColor: palette.primary,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 14.5,
              ),
              decoration: _transparentFieldDecoration(
                palette,
                hintText: hintText,
                suffixIcon: suffixIcon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unlockPasswords() async {
    if (_unlockInProgress) return;
    setState(() => _unlockInProgress = true);
    try {
      final creds = await BrowserVaultService.instance.unlockAndReadAllCredentials(
        context,
        reason: 'Разблокировка сохранённых паролей браузера',
      );
      if (!mounted || creds == null) return;
      setState(() {
        _unlocked = true;
        _unlockedCredentials = creds;
      });
    } finally {
      if (mounted) {
        setState(() => _unlockInProgress = false);
      }
    }
  }

  Future<void> _openAddOrEditCredentialDialog({
    BrowserSavedCredential? existing,
  }) async {
    final bool ok = await BrowserVaultAuthGate.instance.authenticate(
      context,
      reason: existing == null
          ? 'Подтвердите личность для добавления пароля'
          : 'Подтвердите личность для изменения пароля',
    );
    if (!ok || !mounted) return;

    final urlCtrl = TextEditingController(
      text: existing?.origin ?? 'https://',
    );
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    bool obscure = true;

    final bool? saved = await showTheavModalSheet<bool>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.84,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModalHeaderRow(
                  sheetCtx,
                  title: existing == null ? 'Новый пароль' : existing.displayHost,
                ),
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  borderRadius: 20.0,
                  dividerIndent: 44.0,
                  showBorder: false,
                  showShadow: false,
                  backgroundColor: _cardFill(st),
                  dividerColor: _dividerTint(st),
                  children: [
                    if (existing == null)
                      _buildSheetFieldRow(
                        fieldKey: const ValueKey('browser_vault_add_url_input'),
                        palette: pal,
                        icon: Icons.language_rounded,
                        controller: urlCtrl,
                        hintText: 'Сайт (https://example.com)',
                        keyboardType: TextInputType.url,
                      ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_add_user_input'),
                      palette: pal,
                      icon: Icons.person_outline_rounded,
                      controller: userCtrl,
                      hintText: 'Логин или Email',
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_add_pass_input'),
                      palette: pal,
                      icon: Icons.key_rounded,
                      controller: passCtrl,
                      hintText: 'Пароль',
                      obscureText: obscure,
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setSheetState(() => obscure = !obscure),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: Icon(
                              obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 18,
                              color: pal.subtext,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildSafariPillButton(
                  buttonKey: const ValueKey('browser_vault_save_manual_btn'),
                  backgroundColor: pal.primary,
                  foregroundColor: pal.onPrimary,
                  label: 'Сохранить',
                  height: 42.0,
                  fontSize: 14.5,
                  onTap: () async {
                    final rawUrl = urlCtrl.text.trim();
                    final normUrl =
                        rawUrl.contains('://') ? rawUrl : 'https://$rawUrl';
                    if (BrowserVaultService.normalizeOrigin(normUrl) == null ||
                        passCtrl.text.isEmpty) {
                      GlassToastService().show(
                        sheetCtx,
                        'Укажите корректный URL и непустой пароль',
                        icon: Icons.error_outline_rounded,
                      );
                      return;
                    }
                    await BrowserVaultService.instance.saveOrUpdateCredential(
                      url: normUrl,
                      username: userCtrl.text.trim(),
                      password: passCtrl.text,
                      existingId: existing?.id,
                      isHttpAuth: existing?.isHttpAuth ?? false,
                      realm: existing?.realm,
                    );
                    if (sheetCtx.mounted) {
                      Navigator.of(sheetCtx).pop(true);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
    urlCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();

    if (saved == true && mounted) {
      GlassToastService().show(
        context,
        'Пароль сохранён',
        icon: Icons.check_rounded,
      );
      if (_unlocked) {
        final refreshed =
            await BrowserVaultService.instance.unlockAndReadAllCredentials(
          context,
          reason: 'Обновление списка паролей',
        );
        if (mounted && refreshed != null) {
          setState(() => _unlockedCredentials = refreshed);
        }
      }
    }
  }

  Future<void> _openCredentialDetailSheet(BrowserSavedCredential cred) async {
    bool reveal = false;
    final String hostTitle =
        cred.displayHost.isNotEmpty ? cred.displayHost : cred.origin;
    await showTheavModalSheet<void>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.80,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModalHeaderRow(sheetCtx, title: hostTitle),
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                borderRadius: 20.0,
                dividerIndent: 46.0,
                showBorder: false,
                showShadow: false,
                backgroundColor: _cardFill(st),
                dividerColor: _dividerTint(st),
                children: [
                  TheavListRow(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    minHeight: 50.0,
                    leading: Icon(Icons.language_rounded, size: 19, color: pal.subtext),
                    title: 'Сайт',
                    subtitle: cred.origin,
                  ),
                  TheavListRow(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    minHeight: 50.0,
                    leading: Icon(Icons.person_outline_rounded, size: 19, color: pal.subtext),
                    title: 'Логин',
                    subtitle: cred.username.isNotEmpty ? cred.username : 'Без логина',
                    trailing: cred.username.isEmpty
                        ? null
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: cred.username),
                              );
                              HapticUtils.selection();
                              GlassToastService().show(
                                sheetCtx,
                                'Логин скопирован',
                                icon: Icons.check_rounded,
                              );
                            },
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Center(
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 18,
                                  color: pal.subtext,
                                ),
                              ),
                            ),
                          ),
                  ),
                  TheavListRow(
                    key: const ValueKey('browser_vault_detail_password_tile'),
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    minHeight: 52.0,
                    leading: Icon(Icons.key_rounded, size: 19, color: pal.subtext),
                    title: 'Пароль',
                    subtitleWidget: Text(
                      reveal
                          ? cred.password
                          : '•' * cred.password.length.clamp(6, 14),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: pal.onSurface,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          key: const ValueKey('browser_vault_detail_reveal_btn'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticUtils.selection();
                            setSheetState(() => reveal = !reveal);
                          },
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Center(
                              child: Icon(
                                reveal
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 19,
                                color: pal.subtext,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          key: const ValueKey('browser_vault_detail_copy_btn'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              _copyPasswordWithAutoWipe(sheetCtx, cred.password),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Center(
                              child: Icon(
                                Icons.copy_rounded,
                                size: 18,
                                color: pal.subtext,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildSafariPillButton(
                      backgroundColor: pal.primary.withValues(
                        alpha: st.isDark ? 0.18 : 0.11,
                      ),
                      foregroundColor: pal.primary,
                      icon: Icons.edit_rounded,
                      label: 'Изменить',
                      height: 38.0,
                      fontSize: 13.5,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        unawaited(
                          _openAddOrEditCredentialDialog(existing: cred),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSafariPillButton(
                      buttonKey: const ValueKey('browser_vault_detail_delete_btn'),
                      backgroundColor: pal.error.withValues(
                        alpha: st.isDark ? 0.18 : 0.10,
                      ),
                      foregroundColor: pal.error,
                      icon: Icons.delete_outline_rounded,
                      label: 'Удалить',
                      height: 38.0,
                      fontSize: 13.5,
                      onTap: () async {
                        await BrowserVaultService.instance
                            .deleteCredential(cred.id);
                        _unlockedCredentials
                            .removeWhere((c) => c.id == cred.id);
                        if (sheetCtx.mounted) {
                          Navigator.of(sheetCtx).pop();
                        }
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveContactProfile({bool showToast = true}) async {
    final profile = BrowserContactProfile(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      enabled: _contactEnabled,
    );
    await BrowserVaultService.instance.saveContactProfile(profile);
    if (!mounted) return;
    _savedContactProfile = profile;
    _hasSavedContactSnapshot = true;
    _syncContactDirtyFlag();
    setState(() {});
    if (showToast) {
      GlassToastService().show(
        context,
        'Контактные данные сохранены',
        icon: Icons.check_rounded,
      );
    }
  }

  void _prefillContactFromAccount() {
    final defaults = BrowserContactProfile.fromCurrentAccount();
    setState(() {
      _nameCtrl.text = defaults.fullName;
      _emailCtrl.text = defaults.email;
      _phoneCtrl.text = defaults.phone;
    });
    unawaited(_saveContactProfile());
  }

  Future<void> _showGranularClearDialog() async {
    bool clearHistory = true;
    bool clearCookies = true;
    bool clearSiteSettings = false;

    final confirmed = await showTheavModalSheet<bool>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.78,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          Widget checkRow({
            required Key rowKey,
            required String label,
            required bool value,
            required ValueChanged<bool> onChanged,
          }) {
            return TheavListRow(
              key: rowKey,
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              minHeight: 50.0,
              title: label,
              trailing: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value
                      ? pal.primary
                      : pal.onSurface.withValues(alpha: st.isDark ? 0.10 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: value
                    ? Icon(Icons.check_rounded, size: 14.5, color: pal.onPrimary)
                    : null,
              ),
              onTap: () {
                HapticUtils.selection();
                onChanged(!value);
              },
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModalHeaderRow(
                sheetCtx,
                title: 'Очистка данных браузера',
              ),
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                borderRadius: 20.0,
                dividerIndent: 14.0,
                showBorder: false,
                showShadow: false,
                backgroundColor: _cardFill(st),
                dividerColor: _dividerTint(st),
                footer: 'Сохранённые пароли останутся в безопасности.',
                children: [
                  checkRow(
                    rowKey: const ValueKey('clear_opt_history'),
                    label: 'История посещений',
                    value: clearHistory,
                    onChanged: (v) => setSheetState(() => clearHistory = v),
                  ),
                  checkRow(
                    rowKey: const ValueKey('clear_opt_cookies'),
                    label: 'Cookie и данные сайтов (WebStorage)',
                    value: clearCookies,
                    onChanged: (v) => setSheetState(() => clearCookies = v),
                  ),
                  checkRow(
                    rowKey: const ValueKey('clear_opt_site_settings'),
                    label: 'Настройки сайтов и разрешения',
                    value: clearSiteSettings,
                    onChanged: (v) => setSheetState(() => clearSiteSettings = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSafariPillButton(
                buttonKey: const ValueKey('clear_opt_confirm_btn'),
                backgroundColor: pal.error,
                foregroundColor: Colors.white,
                label: 'Очистить выбранное',
                icon: Icons.delete_sweep_rounded,
                height: 42.0,
                fontSize: 14.5,
                onTap: () => Navigator.of(sheetCtx).pop(true),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    if (clearHistory || clearCookies) {
      await BrowserDataService.instance.clearHistoryAndCookies(
        clearHistory: clearHistory,
        clearCookiesAndSiteData: clearCookies,
      );
    }
    if (clearSiteSettings) {
      await BrowserSiteSettingsService.instance.clearAllSitePreferences();
    }
    if (mounted) {
      GlassToastService().show(
        context,
        'Выбранные данные очищены',
        icon: Icons.cleaning_services_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final double modalContentHeight = widget.isModalSheet
        ? () {
            final mq = MediaQuery.of(context);
            final double availAfterKeyboard =
                mq.size.height * 0.86 - mq.viewInsets.bottom - 190.0;
            return math.min(
              450.0,
              math.max(
                140.0,
                math.min(mq.size.height * 0.56, availAfterKeyboard),
              ),
            );
          }()
        : 0.0;
    final double hPad = widget.isModalSheet ? 0.0 : 16.0;
    final bool showSearchBar =
        (_activeSection == 0 && _unlocked) || _activeSection == 2;

    Widget? headerTrailing;
    if (_activeSection == 0 && _unlocked) {
      headerTrailing = _buildSafariPillButton(
        buttonKey: const ValueKey('browser_vault_add_password_btn'),
        backgroundColor: palette.primary.withValues(
          alpha: style.isDark ? 0.18 : 0.11,
        ),
        foregroundColor: palette.primary,
        icon: Icons.add_rounded,
        label: 'Добавить',
        height: 30.0,
        horizontalPadding: 10.0,
        fontSize: 12.5,
        onTap: () => unawaited(_openAddOrEditCredentialDialog()),
      );
    } else if (_activeSection == 2) {
      headerTrailing = _buildSafariPillButton(
        buttonKey: const ValueKey('browser_vault_header_clear_btn'),
        backgroundColor: palette.error.withValues(
          alpha: style.isDark ? 0.14 : 0.08,
        ),
        foregroundColor: palette.error,
        icon: Icons.delete_sweep_rounded,
        label: 'Очистить',
        height: 30.0,
        horizontalPadding: 10.0,
        fontSize: 12.5,
        onTap: _showGranularClearDialog,
      );
    }

    final Widget segmentedBar = Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: TheavSegmentedControl<int>(
        key: const ValueKey('browser_vault_section_segment'),
        expand: true,
        height: 40.0,
        margin: const EdgeInsets.only(top: 2, bottom: 8),
        options: const [
          TheavSegmentOption<int>(value: 0, label: 'Пароли'),
          TheavSegmentOption<int>(value: 1, label: 'Автозаполнение'),
          TheavSegmentOption<int>(value: 2, label: 'Cookie и сайты'),
        ],
        selected: _activeSection,
        onChanged: _selectSection,
      ),
    );

    final Widget searchBar = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: showSearchBar
          ? Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 6),
              child: SizedBox(
                key: const ValueKey('browser_vault_search_bar'),
                height: 38.0,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: palette.subtext,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('browser_vault_search_input'),
                        controller: _searchCtrl,
                        cursorColor: palette.primary,
                        style: TextStyle(
                          color: palette.onSurface,
                          fontSize: 14.5,
                        ),
                        decoration: _transparentFieldDecoration(
                          palette,
                          hintText: _activeSection == 0
                              ? 'Поиск по сайтам и логинам...'
                              : 'Поиск по сайтам...',
                        ).copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        key: const ValueKey('browser_vault_search_clear_btn'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _clearSearch,
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: Center(
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: palette.subtext,
                            ),
                          ),
                        ),
                      ),
                    if (!widget.isModalSheet &&
                        _activeSection == 0 &&
                        _unlocked) ...[
                      const SizedBox(width: 6),
                      headerTrailing!,
                    ],
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );

    final Widget pageView = PageView(
      key: const ValueKey('browser_vault_page_view'),
      controller: _pageCtrl,
      physics: const BouncingScrollPhysics(),
      onPageChanged: _handlePageChanged,
      children: [
        _buildPasswordsTab(context, style),
        _buildAutofillTab(context, style),
        _buildCookiesAndSitesTab(context, style),
      ],
    );

    return Column(
      mainAxisSize:
          widget.isModalSheet ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isModalSheet)
          _buildModalHeaderRow(
            context,
            title: 'Пароли и данные браузера',
            closeButtonKey: const ValueKey('browser_vault_close_btn'),
            trailing: headerTrailing,
          ),
        segmentedBar,
        searchBar,
        if (widget.isModalSheet)
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: modalContentHeight,
                minHeight: math.min(140.0, modalContentHeight),
              ),
              child: SizedBox(
                height: modalContentHeight,
                child: pageView,
              ),
            ),
          )
        else
          Expanded(child: pageView),
      ],
    );
  }

  Widget _buildPasswordsTab(BuildContext context, TheavSurfaceStyle style) {
    final palette = style.palette;
    final vault = BrowserVaultService.instance;
    final double hPad = widget.isModalSheet ? 0.0 : 16.0;
    final Color cardFill = _cardFill(style);
    final Color dividerTint = _dividerTint(style);
    final String q = _searchQuery.trim().toLowerCase();
    final filtered = _unlockedCredentials.where((c) {
      if (q.isEmpty) return true;
      return c.displayHost.toLowerCase().contains(q) ||
          c.origin.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q);
    }).toList();

    Widget buildNeverSaveGroup() {
      return TheavInsetGroup(
        margin: EdgeInsets.zero,
        borderRadius: 20.0,
        dividerIndent: 64.0,
        showBorder: false,
        showShadow: false,
        backgroundColor: cardFill,
        dividerColor: dividerTint,
        header: 'Никогда не сохранять',
        headerTrailing: Text(
          '${vault.neverSaveOrigins.length}',
          style: TextStyle(
            color: palette.subtext,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final origin in vault.neverSaveOrigins)
            TheavListRow(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              minHeight: 54.0,
              leading: SafariDomainMonogramBadge(
                host: SafariUrlSafetyAnalyzer.analyzeUrl(origin).displayHost,
                isSecure: false,
                iconOverride: Icons.block_rounded,
              ),
              title: origin,
              trailing: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticUtils.selection();
                  unawaited(vault.removeNeverSaveOrigin(origin));
                },
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: palette.subtext.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (!_unlocked && vault.neverSaveOrigins.isEmpty) {
      return SafariSheetEmptyState(
        icon: Icons.verified_user_rounded,
        title: 'Пароли защищены',
        subtitle:
            'В связке сохранено паролей: ${vault.hints.length}. Подтвердите личность для просмотра.',
        actionLabel:
            _unlockInProgress ? 'Проверка...' : 'Разблокировать пароли',
        actionIcon: Icons.lock_open_rounded,
        isPrimaryAction: true,
        actionButtonKey: const ValueKey('browser_vault_unlock_btn'),
        onAction: _unlockInProgress ? null : _unlockPasswords,
      );
    }

    if (_unlocked && filtered.isEmpty && vault.neverSaveOrigins.isEmpty) {
      return SafariSheetEmptyState(
        icon: q.isNotEmpty ? Icons.search_off_rounded : Icons.key_rounded,
        title: q.isNotEmpty ? 'Ничего не найдено' : 'Нет сохранённых паролей',
        subtitle: q.isNotEmpty
            ? 'Попробуйте изменить запрос поиска.'
            : 'Добавьте пароль вручную или сохраните его при входе на сайт.',
        actionLabel: q.isNotEmpty ? 'Сбросить поиск' : 'Добавить пароль',
        actionIcon: q.isNotEmpty ? null : Icons.add_rounded,
        isPrimaryAction: q.isEmpty,
        onAction: q.isNotEmpty
            ? _clearSearch
            : () => unawaited(_openAddOrEditCredentialDialog()),
      );
    }

    return SafariFeatherScrollView(
      controller: _passwordsScrollCtrl,
      edgeKeyPrefix: 'browser_vault_passwords',
      child: ListView(
        controller: _passwordsScrollCtrl,
        padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 20),
        children: [
          if (!_unlocked) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: cardFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SafariSheetEmptyState(
                icon: Icons.verified_user_rounded,
                title: 'Пароли защищены',
                subtitle:
                    'В связке сохранено паролей: ${vault.hints.length}. Подтвердите личность для просмотра.',
                actionLabel:
                    _unlockInProgress ? 'Проверка...' : 'Разблокировать пароли',
                actionIcon: Icons.lock_open_rounded,
                isPrimaryAction: true,
                actionButtonKey: const ValueKey('browser_vault_unlock_btn'),
                onAction: _unlockInProgress ? null : _unlockPasswords,
              ),
            ),
          ] else if (filtered.isEmpty) ...[
            SafariSheetEmptyState(
              icon: q.isNotEmpty ? Icons.search_off_rounded : Icons.key_rounded,
              title: q.isNotEmpty
                  ? 'Ничего не найдено'
                  : 'Нет сохранённых паролей',
              subtitle: q.isNotEmpty
                  ? 'Попробуйте изменить запрос поиска.'
                  : 'Добавьте пароль вручную или сохраните его при входе на сайт.',
              actionLabel: q.isNotEmpty ? 'Сбросить поиск' : 'Добавить пароль',
              actionIcon: q.isNotEmpty ? null : Icons.add_rounded,
              onAction: q.isNotEmpty
                  ? _clearSearch
                  : () => unawaited(_openAddOrEditCredentialDialog()),
            ),
          ] else
            TheavInsetGroup(
              margin: EdgeInsets.zero,
              borderRadius: 20.0,
              dividerIndent: 64.0,
              showBorder: false,
              showShadow: false,
              backgroundColor: cardFill,
              dividerColor: dividerTint,
              header: 'Сохранённые аккаунты',
              headerTrailing: Text(
                '${filtered.length}',
                style: TextStyle(
                  color: palette.subtext,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                for (final cred in filtered)
                  Dismissible(
                    key: ValueKey('browser_vault_cred_dismiss_${cred.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: palette.error.withValues(alpha: 0.14),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 18),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: palette.error,
                        size: 20,
                      ),
                    ),
                    onDismissed: (_) {
                      HapticUtils.selection();
                      setState(() {
                        _unlockedCredentials
                            .removeWhere((item) => item.id == cred.id);
                      });
                      unawaited(vault.deleteCredential(cred.id));
                    },
                    child: () {
                      final String hostLabel = cred.displayHost.isNotEmpty
                          ? cred.displayHost
                          : cred.origin;
                      final String subtitleLabel = [
                        cred.username.isNotEmpty ? cred.username : 'Без логина',
                        if (cred.isHttpAuth) 'HTTP Auth',
                      ].join(' • ');
                      return TheavListRow(
                        key: ValueKey('browser_vault_cred_tile_${cred.id}'),
                        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                        minHeight: 56.0,
                        leading: SafariDomainMonogramBadge(
                          host: hostLabel,
                          isSecure: cred.origin.startsWith('https://'),
                        ),
                        titleWidget: Text(
                          hostLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.onSurface,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        subtitleWidget: Row(
                          children: [
                            Icon(
                              cred.isHttpAuth
                                  ? Icons.vpn_key_outlined
                                  : Icons.person_outline_rounded,
                              size: 11.5,
                              color: palette.subtext,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                subtitleLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.subtext,
                                  fontSize: 12.2,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          size: 19,
                          color: palette.subtext.withValues(alpha: 0.72),
                        ),
                        onTap: () =>
                            unawaited(_openCredentialDetailSheet(cred)),
                      );
                    }(),
                  ),
              ],
            ),
          if (vault.neverSaveOrigins.isNotEmpty) ...[
            const SizedBox(height: 12),
            buildNeverSaveGroup(),
          ],
        ],
      ),
    );
  }

  Widget _buildAutofillTab(BuildContext context, TheavSurfaceStyle style) {
    final settings = BrowserSiteSettingsService.instance;
    final pal = style.palette;
    final double hPad = widget.isModalSheet ? 0.0 : 16.0;
    final Color cardFill = _cardFill(style);
    final Color dividerTint = _dividerTint(style);

    return SafariFeatherScrollView(
      controller: _autofillScrollCtrl,
      edgeKeyPrefix: 'browser_vault_autofill',
      // Keep interactive TextFields and LiquidGlassSwitch out of ShaderMask so
      // IME focus, TextInputConnection, and backdrop sampling remain intact.
      enableShaderMask: false,
      child: SingleChildScrollView(
        controller: _autofillScrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            borderRadius: 20.0,
            dividerIndent: 16.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: cardFill,
            dividerColor: dividerTint,
            header: 'Пароли и система',
            children: [
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: 'Предлагать сохранение паролей',
                subtitle:
                    'Показывать карточку сохранения после входа на сайте',
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_save_passwords_switch'),
                  value: settings.savePasswordsEnabled,
                  onChanged: (v) =>
                      unawaited(settings.setSavePasswordsEnabled(v)),
                ),
              ),
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: 'Системное автозаполнение ОС',
                subtitle:
                    'Совместимость с Android Autofill и связкой ключей iOS',
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_os_autofill_switch'),
                  value: settings.osAutofillEnabled,
                  onChanged: (v) => unawaited(settings.setOsAutofillEnabled(v)),
                ),
              ),
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: 'Автозаполнение контактов',
                subtitle: 'Предлагать имя, email и телефон в веб-формах',
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_contact_autofill_switch'),
                  value: _contactEnabled,
                  onChanged: (v) {
                    final nextSaved = BrowserContactProfile(
                      fullName: _savedContactProfile.fullName,
                      email: _savedContactProfile.email,
                      phone: _savedContactProfile.phone,
                      enabled: v,
                    );
                    setState(() {
                      _contactEnabled = v;
                      _savedContactProfile = nextSaved;
                    });
                    unawaited(settings.setContactAutofillEnabled(v));
                    if (_contactAutofillCardLoaded) {
                      unawaited(
                        BrowserVaultService.instance
                            .saveContactProfile(nextSaved),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            borderRadius: 20.0,
            dividerIndent: 44.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: cardFill,
            dividerColor: dividerTint,
            header: 'Карточка контакта',
            children: [
              _buildSheetFieldRow(
                fieldKey: const ValueKey('browser_contact_name_input'),
                palette: pal,
                icon: Icons.badge_outlined,
                controller: _nameCtrl,
                focusNode: _nameFocusNode,
                hintText: 'Имя и фамилия',
              ),
              _buildSheetFieldRow(
                fieldKey: const ValueKey('browser_contact_email_input'),
                palette: pal,
                icon: Icons.alternate_email_rounded,
                controller: _emailCtrl,
                focusNode: _emailFocusNode,
                hintText: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              _buildSheetFieldRow(
                fieldKey: const ValueKey('browser_contact_phone_input'),
                palette: pal,
                icon: Icons.phone_outlined,
                controller: _phoneCtrl,
                focusNode: _phoneFocusNode,
                hintText: 'Телефон',
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSafariPillButton(
                  buttonKey: const ValueKey('browser_contact_prefill_btn'),
                  backgroundColor: pal.primary.withValues(
                    alpha: style.isDark ? 0.18 : 0.11,
                  ),
                  foregroundColor: pal.primary,
                  icon: Icons.person_rounded,
                  label: 'Из профиля',
                  height: 38.0,
                  horizontalPadding: 10.0,
                  fontSize: 13.5,
                  onTap: _prefillContactFromAccount,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _contactDirtyNotifier,
                  builder: (context, canSaveContact, _) {
                    final bool contactSaved = _contactAutofillCardLoaded &&
                        !canSaveContact &&
                        _hasSavedContactSnapshot;
                    final Color savePillBg = contactSaved
                        ? pal.primary.withValues(
                            alpha: style.isDark ? 0.22 : 0.13,
                          )
                        : (canSaveContact
                            ? pal.primary
                            : pal.primary.withValues(
                                alpha: style.isDark ? 0.38 : 0.42,
                              ));
                    final Color savePillFg = contactSaved
                        ? pal.primary
                        : (canSaveContact
                            ? pal.onPrimary
                            : pal.onPrimary.withValues(alpha: 0.85));

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 38.0,
                      decoration: BoxDecoration(
                        color: savePillBg,
                        borderRadius: BorderRadius.circular(19.0),
                      ),
                      child: Material(
                        key: const ValueKey('browser_contact_save_btn'),
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(19.0),
                          onTap: canSaveContact
                              ? () {
                                  HapticUtils.tap();
                                  unawaited(_saveContactProfile());
                                }
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: Row(
                                  key: ValueKey<bool>(contactSaved),
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      contactSaved
                                          ? Icons.check_circle_rounded
                                          : Icons.check_rounded,
                                      size: 16.0,
                                      color: savePillFg,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        contactSaved
                                            ? 'Сохранено'
                                            : 'Сохранить',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: savePillFg,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildCookiesAndSitesTab(
    BuildContext context,
    TheavSurfaceStyle style,
  ) {
    final settings = BrowserSiteSettingsService.instance;
    final dataSvc = BrowserDataService.instance;
    final pal = style.palette;
    final double hPad = widget.isModalSheet ? 0.0 : 16.0;
    final Color cardFill = _cardFill(style);
    final Color dividerTint = _dividerTint(style);
    final String q = _searchQuery.trim().toLowerCase();

    final Map<String, BrowserSitePreference> prefsMap =
        settings.sitePreferences;
    final Set<String> allHosts = <String>{
      ...prefsMap.keys,
      ...dataSvc.knownOrigins
          .map(BrowserSiteSettingsService.normalizeHostKey)
          .where((h) => h.isNotEmpty),
    };
    final List<String> sortedHosts = allHosts.toList()..sort();
    final List<String> filteredHosts = q.isEmpty
        ? sortedHosts
        : sortedHosts.where((h) {
            final pref = prefsMap[h];
            final display = pref?.displayHost ?? '';
            return h.toLowerCase().contains(q) ||
                display.toLowerCase().contains(q);
          }).toList();

    return SafariFeatherScrollView(
      controller: _cookiesScrollCtrl,
      edgeKeyPrefix: 'browser_vault_cookies',
      child: ListView(
        controller: _cookiesScrollCtrl,
        padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 22),
        children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            borderRadius: 20.0,
            dividerIndent: 16.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: cardFill,
            dividerColor: dividerTint,
            header: 'Политика cookie',
            footer:
                'Режим «Без сторонних cookie» усиливает приватность, но может нарушать OAuth-вход на некоторых сайтах.',
            children: [
              for (final option in [
                (
                  policy: BrowserCookiePolicy.allowAll,
                  title: 'Разрешить все cookie',
                  sub: 'Рекомендуется для стабильной работы сайтов и входа',
                ),
                (
                  policy: BrowserCookiePolicy.blockThirdParty,
                  title: 'Блокировать сторонние cookie',
                  sub: 'Запрещает межсайтовое отслеживание',
                ),
                (
                  policy: BrowserCookiePolicy.blockAll,
                  title: 'Блокировать все cookie',
                  sub: 'Сайты не смогут сохранять сессии входа',
                ),
              ])
                TheavListRow(
                  key: ValueKey('browser_cookie_policy_${option.policy.name}'),
                  padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                  minHeight: 54.0,
                  title: option.title,
                  subtitle: option.sub,
                  trailing: settings.cookiePolicy == option.policy
                      ? Icon(Icons.check_rounded, size: 19, color: pal.primary)
                      : const SizedBox(width: 19),
                  onTap: () {
                    HapticUtils.selection();
                    unawaited(settings.setCookiePolicy(option.policy));
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            borderRadius: 20.0,
            dividerIndent: 64.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: cardFill,
            dividerColor: dividerTint,
            header: 'Настройки и данные сайтов',
            headerTrailing: Text(
              '${filteredHosts.length}',
              style: TextStyle(
                color: pal.subtext,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              if (filteredHosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    q.isNotEmpty
                        ? 'Сайты по запросу не найдены'
                        : 'Нет сохранённых данных или индивидуальных настроек сайтов',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: pal.subtext),
                  ),
                )
              else
                for (final host in filteredHosts)
                  Builder(
                    builder: (ctx) {
                      final pref = prefsMap[host];
                      final String displayHost =
                          pref?.displayHost.isNotEmpty == true
                              ? pref!.displayHost
                              : host;
                      final tags = <String>[
                        if (pref?.desktopMode == true) 'ПК-версия',
                        if (pref?.cameraPolicy == SitePermissionDecision.allow)
                          'Камера',
                        if (pref?.microphonePolicy ==
                            SitePermissionDecision.allow)
                          'Микрофон',
                        if (pref?.muteJsDialogs == true) 'Без JS-окон',
                      ];
                      return TheavListRow(
                        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                        minHeight: 56.0,
                        leading: SafariDomainMonogramBadge(
                          host: displayHost,
                          isSecure: true,
                        ),
                        titleWidget: Text(
                          displayHost,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: pal.onSurface,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        subtitleWidget: Text(
                          tags.isNotEmpty
                              ? tags.join(' • ')
                              : 'Cookie и кэш сайта',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.2,
                            color: pal.subtext,
                            height: 1.25,
                          ),
                        ),
                        trailing: _buildSafariPillButton(
                          backgroundColor: pal.onSurface.withValues(
                            alpha: style.isDark ? 0.08 : 0.055,
                          ),
                          foregroundColor: pal.primary,
                          label: 'Очистить',
                          height: 28.0,
                          horizontalPadding: 10.0,
                          fontSize: 12.0,
                          onTap: () async {
                            HapticUtils.selection();
                            await dataSvc.clearSiteData('https://$host/');
                            await settings.resetHost(host);
                            if (context.mounted) {
                              GlassToastService().show(
                                context,
                                'Данные $host очищены',
                                icon: Icons.cleaning_services_rounded,
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
            ],
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            borderRadius: 20.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: pal.error.withValues(
              alpha: style.isDark ? 0.11 : 0.06,
            ),
            children: [
              TheavListRow(
                key: const ValueKey('browser_clear_data_granular_btn'),
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                minHeight: 54.0,
                leading: Icon(
                  Icons.delete_sweep_rounded,
                  size: 20,
                  color: pal.error,
                ),
                titleWidget: Text(
                  'Очистить данные браузера...',
                  style: TextStyle(
                    color: pal.error,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: 'Выборочная очистка истории, cookie и настроек сайтов',
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: pal.error.withValues(alpha: 0.72),
                ),
                onTap: _showGranularClearDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
