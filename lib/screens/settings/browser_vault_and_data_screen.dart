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
import '../../widgets/browser/browser_vault_pin_sheet.dart';
import '../../widgets/browser/safari_library_sheet.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';

Timer? _sharedClipboardWipeTimer;
String? _lastCopiedSecretValue;

enum _VaultPinAction { change, remove }

void _copySecretWithAutoWipe(
  BuildContext context,
  String secret, {
  required String toastMessage,
}) {
  Clipboard.setData(ClipboardData(text: secret));
  HapticUtils.selection();
  _lastCopiedSecretValue = secret;
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
      toastMessage,
      icon: Icons.check_rounded,
    );
  }
}

void _copyPasswordWithAutoWipe(BuildContext context, String password) {
  _copySecretWithAutoWipe(
    context,
    password,
    toastMessage: context.trOr(
      'browser_vault_password_copied_toast',
      'Пароль скопирован (очистится через 60 с)',
    ),
  );
}

void _copyCardNumberWithAutoWipe(BuildContext context, String cardNumber) {
  _copySecretWithAutoWipe(
    context,
    cardNumber,
    toastMessage: context.trOr(
      'browser_vault_card_copied_toast',
      'Номер карты скопирован (очистится через 60 с)',
    ),
  );
}

/// Opens Theaver's Browser Passwords, Autofill, Cookie & Site Settings hub
/// inside a Safari Liquid Glass modal sheet (used directly from the browser).
Future<void> showBrowserVaultAndDataSheet(
  BuildContext context, {
  int initialSection = 0,
  String? initialSearchQuery,
  bool autoUnlockPasswords = true,
  ValueChanged<BrowserCredentialHint>? onSelectForAutofill,
  ValueChanged<BrowserCardHint>? onSelectCardForAutofill,
  ValueChanged<BrowserSavedAddress>? onSelectAddressForAutofill,
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
      onSelectForAutofill: onSelectForAutofill,
      onSelectCardForAutofill: onSelectCardForAutofill,
      onSelectAddressForAutofill: onSelectAddressForAutofill,
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
    final String headerTitle = context.trOr(
      'settings_browser_vault_title',
      'Пароли и данные браузера',
    );
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
  final ValueChanged<BrowserCredentialHint>? onSelectForAutofill;
  final ValueChanged<BrowserCardHint>? onSelectCardForAutofill;
  final ValueChanged<BrowserSavedAddress>? onSelectAddressForAutofill;

  const _BrowserVaultHubContent({
    required this.initialSection,
    this.initialSearchQuery,
    required this.autoUnlockPasswords,
    required this.isModalSheet,
    this.onSelectForAutofill,
    this.onSelectCardForAutofill,
    this.onSelectAddressForAutofill,
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
  bool _hasVaultPin = false;
  bool _authToggleInProgress = false;
  bool _vaultPinActionInProgress = false;
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
    _hasSavedContactSnapshot = profile.hasAnyField;
    _nameCtrl.text = profile.fullName;
    _emailCtrl.text = profile.email;
    _phoneCtrl.text = profile.phone;
    _syncContactDirtyFlag();
    setState(() {
      _contactEnabled = profile.enabled &&
          BrowserSiteSettingsService.instance.contactAutofillEnabled;
      _contactAutofillCardLoaded = true;
    });
    if (widget.autoUnlockPasswords && _activeSection == 0) {
      unawaited(_unlockPasswords());
    }
    unawaited(_refreshVaultPinState());
  }

  Future<void> _refreshVaultPinState() async {
    final hasPin = await BrowserVaultAuthGate.instance
        .hasVaultPin()
        .catchError((_) => false);
    if (!mounted) return;
    if (_hasVaultPin != hasPin) {
      setState(() => _hasVaultPin = hasPin);
    }
  }

  Future<void> _syncContactControllersFromVault() async {
    final profile = await BrowserVaultService.instance.getContactProfile();
    if (!mounted) return;
    _savedContactProfile = profile;
    _hasSavedContactSnapshot = profile.hasAnyField;
    _nameCtrl.text = profile.fullName;
    _emailCtrl.text = profile.email;
    _phoneCtrl.text = profile.phone;
    _syncContactDirtyFlag();
    setState(() {});
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
            message: sheetCtx.trOr('common_close', 'Закрыть'),
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
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
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
              textInputAction: textInputAction,
              textCapitalization: textCapitalization,
              inputFormatters: inputFormatters,
              obscureText: obscureText,
              onChanged: onChanged,
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
        reason: context.trOr(
          'browser_vault_unlock_passwords_reason',
          'Разблокировка сохранённых паролей браузера',
        ),
      );
      if (!mounted) return;
      unawaited(_refreshVaultPinState());
      if (creds == null) return;
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
    if (!_unlocked) {
      final bool ok = await BrowserVaultAuthGate.instance.authenticate(
        context,
        reason: existing == null
            ? context.trOr(
                'browser_vault_add_password_reason',
                'Подтвердите личность для добавления пароля',
              )
            : context.trOr(
                'browser_vault_edit_password_reason',
                'Подтвердите личность для изменения пароля',
              ),
      );
      if (!mounted) return;
      unawaited(_refreshVaultPinState());
      if (!ok) return;
    }

    final urlCtrl = TextEditingController(
      text: existing?.origin ?? 'https://',
    );
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    bool obscure = true;

    final ({BrowserCredentialHint hint, String password})? savedResult =
        await showTheavModalSheet<({BrowserCredentialHint hint, String password})>(
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
                  title: existing == null
                      ? sheetCtx.trOr(
                          'browser_vault_new_password_title',
                          'Новый пароль',
                        )
                      : existing.displayHost,
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
                        hintText: sheetCtx.trOr(
                          'browser_vault_url_hint',
                          'Сайт (https://example.com)',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_add_user_input'),
                      palette: pal,
                      icon: Icons.person_outline_rounded,
                      controller: userCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_save_password_username_hint',
                        'Логин или Email',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_add_pass_input'),
                      palette: pal,
                      icon: Icons.key_rounded,
                      controller: passCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_http_auth_password_hint',
                        'Пароль',
                      ),
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
                  label: sheetCtx.trOr('common_save', 'Сохранить'),
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
                        sheetCtx.trOr(
                          'browser_vault_invalid_url_password',
                          'Укажите корректный URL и непустой пароль',
                        ),
                        icon: Icons.error_outline_rounded,
                      );
                      return;
                    }
                    final enteredPassword = passCtrl.text;
                    final savedHint =
                        await BrowserVaultService.instance.saveOrUpdateCredential(
                      url: normUrl,
                      username: userCtrl.text.trim(),
                      password: enteredPassword,
                      existingId: existing?.id,
                      isHttpAuth: existing?.isHttpAuth ?? false,
                      realm: existing?.realm,
                    );
                    if (sheetCtx.mounted) {
                      Navigator.of(sheetCtx).pop(
                        (hint: savedHint, password: enteredPassword),
                      );
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

    if (savedResult != null && mounted) {
      GlassToastService().show(
        context,
        context.trOr('browser_vault_password_saved_toast', 'Пароль сохранён'),
        icon: Icons.check_rounded,
      );
      if (_unlocked) {
        final updatedCred = BrowserSavedCredential(
          hint: savedResult.hint,
          password: savedResult.password,
        );
        setState(() {
          final existingIdx = _unlockedCredentials.indexWhere(
            (c) => c.id == savedResult.hint.id,
          );
          if (existingIdx >= 0) {
            _unlockedCredentials[existingIdx] = updatedCred;
          } else {
            _unlockedCredentials.insert(0, updatedCred);
          }
        });
      }
    }
  }

  void _triggerAutofillSelection(BrowserCredentialHint hint) {
    final cb = widget.onSelectForAutofill;
    if (cb == null) return;
    HapticUtils.selection();
    if (widget.isModalSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    cb(hint);
  }

  void _triggerCardAutofillSelection(BrowserCardHint hint) {
    final cb = widget.onSelectCardForAutofill;
    if (cb == null) return;
    HapticUtils.selection();
    if (widget.isModalSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    cb(hint);
  }

  void _triggerAddressAutofillSelection(BrowserSavedAddress addr) {
    final cb = widget.onSelectAddressForAutofill;
    if (cb == null) return;
    HapticUtils.selection();
    if (widget.isModalSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    cb(addr);
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
                    title: sheetCtx.trOr('browser_vault_field_site', 'Сайт'),
                    subtitle: cred.origin,
                  ),
                  TheavListRow(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    minHeight: 50.0,
                    leading: Icon(Icons.person_outline_rounded, size: 19, color: pal.subtext),
                    title: sheetCtx.trOr('browser_vault_field_login', 'Логин'),
                    subtitle: cred.username.isNotEmpty
                        ? cred.username
                        : sheetCtx.trOr(
                            'browser_vault_no_username',
                            'Без логина',
                          ),
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
                                sheetCtx.trOr(
                                  'browser_vault_login_copied_toast',
                                  'Логин скопирован',
                                ),
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
                    title: sheetCtx.trOr(
                      'browser_http_auth_password_hint',
                      'Пароль',
                    ),
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
              if (widget.onSelectForAutofill != null) ...[
                _buildSafariPillButton(
                  buttonKey: const ValueKey('browser_vault_detail_autofill_btn'),
                  backgroundColor: pal.primary,
                  foregroundColor: pal.onPrimary,
                  icon: Icons.login_rounded,
                  label: sheetCtx.trOr(
                    'browser_vault_autofill_btn',
                    'Автозаполнить',
                  ),
                  height: 40.0,
                  fontSize: 14.0,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _triggerAutofillSelection(cred.hint);
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: _buildSafariPillButton(
                      backgroundColor: pal.primary.withValues(
                        alpha: st.isDark ? 0.18 : 0.11,
                      ),
                      foregroundColor: pal.primary,
                      icon: Icons.edit_rounded,
                      label: sheetCtx.trOr(
                        'browser_vault_edit_btn',
                        'Изменить',
                      ),
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
                      label: sheetCtx.trOr('common_delete', 'Удалить'),
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

  Future<void> _toggleRequireVaultAuth(bool next) async {
    if (_authToggleInProgress) return;
    final settings = BrowserSiteSettingsService.instance;
    if (next) {
      await settings.setRequireAuthForVaultAccess(true);
      return;
    }
    _authToggleInProgress = true;
    try {
      final ok = await BrowserVaultAuthGate.instance.authenticate(
        context,
        reason: context.trOr(
          'browser_vault_disable_auth_reason',
          'Подтвердите личность для отключения защиты хранилища',
        ),
        forceChallenge: true,
      );
      if (!mounted) return;
      unawaited(_refreshVaultPinState());
      if (!ok) return;
      await settings.setRequireAuthForVaultAccess(false);
    } finally {
      _authToggleInProgress = false;
    }
  }

  Future<void> _onTapVaultPinTile() async {
    if (_vaultPinActionInProgress) return;
    _vaultPinActionInProgress = true;
    try {
      final bool hasPin = await BrowserVaultAuthGate.instance.hasVaultPin();
      if (!mounted) return;
      if (!hasPin) {
        final bool created = await showBrowserVaultCreatePinSheet(context);
        if (!mounted) return;
        await _refreshVaultPinState();
        if (created && mounted) {
          GlassToastService().show(
            context,
            context.trOr(
              'browser_vault_pin_saved_toast',
              'PIN-код сейфа установлен',
            ),
            icon: Icons.check_rounded,
          );
        }
        return;
      }

      final _VaultPinAction? action = await showTheavModalSheet<_VaultPinAction>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        maxHeightFactor: 0.45,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
        builder: (sheetCtx) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModalHeaderRow(
                sheetCtx,
                title: sheetCtx.trOr(
                  'browser_setting_vault_pin_title',
                  'PIN-код сейфа браузера',
                ),
              ),
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
                    key: const ValueKey('browser_vault_pin_change_btn'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    minHeight: 52.0,
                    leading: Icon(Icons.pin_rounded, size: 20, color: pal.primary),
                    title: sheetCtx.trOr(
                      'browser_vault_pin_change',
                      'Изменить PIN-код сейфа',
                    ),
                    showChevron: true,
                    onTap: () => Navigator.of(sheetCtx).pop(_VaultPinAction.change),
                  ),
                  TheavListRow(
                    key: const ValueKey('browser_vault_pin_remove_btn'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    minHeight: 52.0,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: pal.error,
                    ),
                    title: sheetCtx.trOr(
                      'browser_vault_pin_remove',
                      'Удалить PIN-код сейфа',
                    ),
                    isDestructive: true,
                    onTap: () => Navigator.of(sheetCtx).pop(_VaultPinAction.remove),
                  ),
                ],
              ),
            ],
          );
        },
      );
      if (action == null || !mounted) return;
      if (action == _VaultPinAction.change) {
        final bool ok = await BrowserVaultAuthGate.instance.authenticate(
          context,
          reason: context.trOr(
            'browser_vault_change_pin_reason',
            'Подтвердите доступ для смены PIN-кода сейфа',
          ),
          forceChallenge: true,
        );
        if (!ok || !mounted) return;
        final bool changed = await showBrowserVaultCreatePinSheet(context);
        if (!mounted) return;
        await _refreshVaultPinState();
        if (changed && mounted) {
          GlassToastService().show(
            context,
            context.trOr(
              'browser_vault_pin_updated_toast',
              'PIN-код сейфа обновлён',
            ),
            icon: Icons.check_rounded,
          );
        }
      } else if (action == _VaultPinAction.remove) {
        final bool ok = await BrowserVaultAuthGate.instance.authenticate(
          context,
          reason: context.trOr(
            'browser_vault_remove_pin_reason',
            'Подтвердите личность для удаления PIN-кода сейфа',
          ),
          forceChallenge: true,
        );
        if (!ok || !mounted) return;
        await BrowserVaultAuthGate.instance.clearVaultPin();
        if (!mounted) return;
        await _refreshVaultPinState();
        if (mounted) {
          GlassToastService().show(
            context,
            context.trOr(
              'browser_vault_pin_removed_toast',
              'PIN-код сейфа удалён',
            ),
            icon: Icons.check_rounded,
          );
        }
      }
    } finally {
      _vaultPinActionInProgress = false;
    }
  }

  ({int month, int year})? _parseCardExpiry(String raw) {
    final clean = raw.trim();
    final match = RegExp(r'^(\d{1,2})\s*/\s*(\d{2}|\d{4})$').firstMatch(clean);
    final String? mStr;
    final String? yStr;
    if (match != null) {
      mStr = match.group(1);
      yStr = match.group(2);
    } else {
      final digits = clean.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 4) {
        mStr = digits.substring(0, 2);
        yStr = digits.substring(2, 4);
      } else if (digits.length == 6) {
        mStr = digits.substring(0, 2);
        yStr = digits.substring(2, 6);
      } else {
        return null;
      }
    }
    final month = int.tryParse(mStr ?? '');
    final rawYear = int.tryParse(yStr ?? '');
    if (month == null || rawYear == null) return null;
    final year = BrowserVaultService.normalizeExpiryYear(rawYear);
    return (month: month, year: year);
  }

  Future<void> _openCardDetailSheet(BrowserCardHint hint) async {
    BrowserSavedCard? unlockedCard;
    bool revealNumber = false;
    bool unlocking = false;

    Future<BrowserSavedCard?> ensureUnlocked(
      BuildContext sheetCtx,
      StateSetter setSheetState,
    ) async {
      if (unlockedCard != null) return unlockedCard;
      if (unlocking) return null;
      setSheetState(() => unlocking = true);
      try {
        final card = await BrowserVaultService.instance.unlockAndReadCard(
          sheetCtx,
          hint.id,
          reason: sheetCtx.trOr(
            'browser_vault_unlock_card_reason',
            'Подтвердите личность для доступа к данным карты',
          ),
        );
        if (sheetCtx.mounted && card != null) {
          unlockedCard = card;
        }
        return card;
      } finally {
        if (sheetCtx.mounted) {
          setSheetState(() => unlocking = false);
        }
      }
    }

    await showTheavModalSheet<void>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.80,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          final String cardDisplayTitle = hint.nickname.isNotEmpty
              ? '${hint.nickname} (${hint.brand.displayName})'
              : '${hint.brand.displayName} •••• ${hint.last4}';
          final String displayedNumber = (revealNumber && unlockedCard != null)
              ? BrowserVaultService.formatCardNumberGroups(
                  unlockedCard!.cardNumber,
                )
              : '•••• •••• •••• ${hint.last4}';

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModalHeaderRow(sheetCtx, title: cardDisplayTitle),
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  borderRadius: 20.0,
                  dividerIndent: 46.0,
                  showBorder: false,
                  showShadow: false,
                  backgroundColor: _cardFill(st),
                  dividerColor: _dividerTint(st),
                  footer: sheetCtx.trOr(
                    'browser_vault_card_cvv_never_stored',
                    'CVV/CVC не сохраняется в целях безопасности.',
                  ),
                  children: [
                    TheavListRow(
                      key: const ValueKey('browser_vault_card_detail_number_tile'),
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      minHeight: 52.0,
                      leading: Icon(
                        Icons.credit_card_rounded,
                        size: 19,
                        color: pal.subtext,
                      ),
                      title: sheetCtx.trOr(
                        'browser_vault_card_number_label',
                        'Номер карты',
                      ),
                      subtitleWidget: Text(
                        displayedNumber,
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
                            key: const ValueKey(
                              'browser_vault_card_detail_reveal_btn',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onTap: unlocking
                                ? null
                                : () async {
                                    HapticUtils.selection();
                                    if (revealNumber) {
                                      setSheetState(() => revealNumber = false);
                                      return;
                                    }
                                    final card = await ensureUnlocked(
                                      sheetCtx,
                                      setSheetState,
                                    );
                                    if (card != null && sheetCtx.mounted) {
                                      setSheetState(() => revealNumber = true);
                                    }
                                  },
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Center(
                                child: Icon(
                                  revealNumber
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
                            key: const ValueKey(
                              'browser_vault_card_detail_copy_btn',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onTap: unlocking
                                ? null
                                : () async {
                                    final card = await ensureUnlocked(
                                      sheetCtx,
                                      setSheetState,
                                    );
                                    if (card != null && sheetCtx.mounted) {
                                      _copyCardNumberWithAutoWipe(
                                        sheetCtx,
                                        card.cardNumber,
                                      );
                                    }
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
                        ],
                      ),
                    ),
                    TheavListRow(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      minHeight: 50.0,
                      leading: Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: pal.subtext,
                      ),
                      title: sheetCtx.trOr(
                        'browser_vault_card_expiry_label',
                        'Срок действия',
                      ),
                      subtitle: hint.formattedExpiry,
                    ),
                    TheavListRow(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      minHeight: 50.0,
                      leading: Icon(
                        Icons.person_outline_rounded,
                        size: 19,
                        color: pal.subtext,
                      ),
                      title: sheetCtx.trOr(
                        'browser_vault_card_holder_label',
                        'Владелец карты',
                      ),
                      subtitle: hint.holderName.isNotEmpty
                          ? hint.holderName
                          : '—',
                    ),
                    if (hint.nickname.isNotEmpty)
                      TheavListRow(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        minHeight: 50.0,
                        leading: Icon(
                          Icons.label_outline_rounded,
                          size: 19,
                          color: pal.subtext,
                        ),
                        title: sheetCtx.trOr(
                          'browser_vault_card_nickname_label',
                          'Название',
                        ),
                        subtitle: hint.nickname,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (widget.onSelectCardForAutofill != null) ...[
                  _buildSafariPillButton(
                    buttonKey: const ValueKey(
                      'browser_vault_card_detail_autofill_btn',
                    ),
                    backgroundColor: pal.primary,
                    foregroundColor: pal.onPrimary,
                    icon: Icons.credit_card_rounded,
                    label: sheetCtx.trOr(
                      'browser_vault_autofill_btn',
                      'Автозаполнить',
                    ),
                    height: 40.0,
                    fontSize: 14.0,
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _triggerCardAutofillSelection(hint);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _buildSafariPillButton(
                        buttonKey: const ValueKey(
                          'browser_vault_card_detail_edit_btn',
                        ),
                        backgroundColor: pal.primary.withValues(
                          alpha: st.isDark ? 0.18 : 0.11,
                        ),
                        foregroundColor: pal.primary,
                        icon: Icons.edit_rounded,
                        label: sheetCtx.trOr(
                          'browser_vault_edit_btn',
                          'Изменить',
                        ),
                        height: 38.0,
                        fontSize: 13.5,
                        onTap: unlocking
                            ? null
                            : () async {
                                final card = await ensureUnlocked(
                                  sheetCtx,
                                  setSheetState,
                                );
                                if (card == null || !sheetCtx.mounted) return;
                                Navigator.of(sheetCtx).pop();
                                if (mounted) {
                                  unawaited(
                                    _openAddOrEditCardDialog(existing: card),
                                  );
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSafariPillButton(
                        buttonKey: const ValueKey(
                          'browser_vault_card_detail_delete_btn',
                        ),
                        backgroundColor: pal.error.withValues(
                          alpha: st.isDark ? 0.18 : 0.10,
                        ),
                        foregroundColor: pal.error,
                        icon: Icons.delete_outline_rounded,
                        label: sheetCtx.trOr('common_delete', 'Удалить'),
                        height: 38.0,
                        fontSize: 13.5,
                        onTap: unlocking
                            ? null
                            : () async {
                                final card = await ensureUnlocked(
                                  sheetCtx,
                                  setSheetState,
                                );
                                if (card == null || !sheetCtx.mounted) return;
                                await BrowserVaultService.instance
                                    .deleteCard(hint.id);
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAddOrEditCardDialog({BrowserSavedCard? existing}) async {
    final numberCtrl = TextEditingController(
      text: existing != null
          ? BrowserVaultService.formatCardNumberGroups(existing.cardNumber)
          : '',
    );
    final expiryCtrl = TextEditingController(
      text: existing != null ? existing.formattedExpiry : '',
    );
    final holderCtrl = TextEditingController(text: existing?.holderName ?? '');
    final nicknameCtrl = TextEditingController(text: existing?.nickname ?? '');
    String? errorText;

    final bool? saved = await showTheavModalSheet<bool>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.86,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          final detectedBrand =
              BrowserVaultService.detectCardBrand(numberCtrl.text);

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModalHeaderRow(
                  sheetCtx,
                  title: existing == null
                      ? sheetCtx.trOr(
                          'browser_vault_new_card_title',
                          'Новая банковская карта',
                        )
                      : sheetCtx.trOr(
                          'browser_vault_edit_card_title',
                          'Редактировать карту',
                        ),
                  trailing: detectedBrand != BrowserCardBrand.unknown
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: pal.primary.withValues(
                              alpha: st.isDark ? 0.20 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            detectedBrand.displayName,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: pal.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                TheavInsetGroup(
                  margin: EdgeInsets.zero,
                  borderRadius: 20.0,
                  dividerIndent: 44.0,
                  showBorder: false,
                  showShadow: false,
                  backgroundColor: _cardFill(st),
                  dividerColor: _dividerTint(st),
                  footer: sheetCtx.trOr(
                    'browser_vault_card_cvv_never_stored',
                    'CVV/CVC не сохраняется в целях безопасности.',
                  ),
                  children: [
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_card_number_input'),
                      palette: pal,
                      icon: Icons.credit_card_rounded,
                      controller: numberCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_card_number_hint',
                        'Номер карты',
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\s-]')),
                        LengthLimitingTextInputFormatter(24),
                      ],
                      onChanged: (_) => setSheetState(() => errorText = null),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_card_expiry_input'),
                      palette: pal,
                      icon: Icons.calendar_today_rounded,
                      controller: expiryCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_card_expiry_hint',
                        'Срок действия (ММ/ГГ)',
                      ),
                      keyboardType: TextInputType.datetime,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      onChanged: (_) => setSheetState(() => errorText = null),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_card_holder_input'),
                      palette: pal,
                      icon: Icons.person_outline_rounded,
                      controller: holderCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_card_holder_hint',
                        'Имя владельца (как на карте)',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey(
                        'browser_vault_card_nickname_input',
                      ),
                      palette: pal,
                      icon: Icons.label_outline_rounded,
                      controller: nicknameCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_card_nickname_hint',
                        'Название карты (необязательно)',
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      errorText!,
                      style: TextStyle(
                        color: pal.error,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _buildSafariPillButton(
                  buttonKey: const ValueKey('browser_vault_card_save_btn'),
                  backgroundColor: pal.primary,
                  foregroundColor: pal.onPrimary,
                  label: sheetCtx.trOr('common_save', 'Сохранить'),
                  height: 42.0,
                  fontSize: 14.5,
                  onTap: () async {
                    final digits =
                        BrowserVaultService.stripCardDigits(numberCtrl.text);
                    if (!BrowserVaultService.isValidLuhn(digits)) {
                      final msg = sheetCtx.trOr(
                        'browser_vault_card_invalid_number',
                        'Укажите корректный номер карты',
                      );
                      setSheetState(() => errorText = msg);
                      GlassToastService().show(
                        sheetCtx,
                        msg,
                        icon: Icons.error_outline_rounded,
                      );
                      return;
                    }
                    final parsed = _parseCardExpiry(expiryCtrl.text);
                    if (parsed == null ||
                        parsed.month < 1 ||
                        parsed.month > 12) {
                      final msg = sheetCtx.trOr(
                        'browser_vault_card_invalid_expiry',
                        'Укажите срок действия в формате ММ/ГГ',
                      );
                      setSheetState(() => errorText = msg);
                      GlassToastService().show(
                        sheetCtx,
                        msg,
                        icon: Icons.error_outline_rounded,
                      );
                      return;
                    }
                    if (BrowserVaultService.isCardExpired(
                      parsed.month,
                      parsed.year,
                    )) {
                      final msg = sheetCtx.trOr(
                        'browser_vault_card_expired',
                        'Срок действия карты истёк',
                      );
                      setSheetState(() => errorText = msg);
                      GlassToastService().show(
                        sheetCtx,
                        msg,
                        icon: Icons.error_outline_rounded,
                      );
                      return;
                    }
                    await BrowserVaultService.instance.saveOrUpdateCard(
                      cardNumber: digits,
                      holderName: holderCtrl.text.trim(),
                      expMonth: parsed.month,
                      expYear: parsed.year,
                      nickname: nicknameCtrl.text.trim(),
                      existingId: existing?.id,
                      clearNickname:
                          existing != null && nicknameCtrl.text.trim().isEmpty,
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
    numberCtrl.dispose();
    expiryCtrl.dispose();
    holderCtrl.dispose();
    nicknameCtrl.dispose();

    if (saved == true && mounted) {
      GlassToastService().show(
        context,
        context.trOr('browser_vault_card_saved_toast', 'Карта сохранена'),
        icon: Icons.check_rounded,
      );
    }
  }

  Future<void> _openAddOrEditAddressDialog({
    BrowserSavedAddress? existing,
  }) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final fullNameCtrl = TextEditingController(text: existing?.fullName ?? '');
    final orgCtrl = TextEditingController(text: existing?.organization ?? '');
    final line1Ctrl = TextEditingController(text: existing?.addressLine1 ?? '');
    final line2Ctrl = TextEditingController(text: existing?.addressLine2 ?? '');
    final cityCtrl = TextEditingController(text: existing?.city ?? '');
    final regionCtrl = TextEditingController(text: existing?.region ?? '');
    final postalCtrl = TextEditingController(text: existing?.postalCode ?? '');
    final countryCtrl = TextEditingController(text: existing?.country ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    bool isDefault =
        existing?.isDefault ?? BrowserVaultService.instance.addresses.isEmpty;

    final String? actionResult = await showTheavModalSheet<String>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.88,
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
                  title: existing == null
                      ? sheetCtx.trOr(
                          'browser_vault_new_address_title',
                          'Новый адрес',
                        )
                      : sheetCtx.trOr(
                          'browser_vault_edit_address_title',
                          'Редактировать адрес',
                        ),
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
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_label_input'),
                      palette: pal,
                      icon: Icons.label_outline_rounded,
                      controller: labelCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_label_hint',
                        'Название (Дом, Работа...)',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey(
                        'browser_vault_addr_fullname_input',
                      ),
                      palette: pal,
                      icon: Icons.person_outline_rounded,
                      controller: fullNameCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_fullname_hint',
                        'ФИО',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_org_input'),
                      palette: pal,
                      icon: Icons.business_outlined,
                      controller: orgCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_org_hint',
                        'Организация',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_line1_input'),
                      palette: pal,
                      icon: Icons.location_on_outlined,
                      controller: line1Ctrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_line1_hint',
                        'Улица, дом, квартира',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_line2_input'),
                      palette: pal,
                      icon: Icons.apartment_rounded,
                      controller: line2Ctrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_line2_hint',
                        'Подъезд, этаж, комментарий',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_city_input'),
                      palette: pal,
                      icon: Icons.location_city_rounded,
                      controller: cityCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_city_hint',
                        'Город',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_region_input'),
                      palette: pal,
                      icon: Icons.map_outlined,
                      controller: regionCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_region_hint',
                        'Область / регион',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_postal_input'),
                      palette: pal,
                      icon: Icons.markunread_mailbox_outlined,
                      controller: postalCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_postal_hint',
                        'Почтовый индекс',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey(
                        'browser_vault_addr_country_input',
                      ),
                      palette: pal,
                      icon: Icons.public_rounded,
                      controller: countryCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_addr_country_hint',
                        'Страна',
                      ),
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_phone_input'),
                      palette: pal,
                      icon: Icons.phone_outlined,
                      controller: phoneCtrl,
                      hintText: sheetCtx.trOr(
                        'browser_vault_contact_phone_hint',
                        'Телефон',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    _buildSheetFieldRow(
                      fieldKey: const ValueKey('browser_vault_addr_email_input'),
                      palette: pal,
                      icon: Icons.alternate_email_rounded,
                      controller: emailCtrl,
                      hintText: 'Email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _cardFill(st),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: TheavListRow(
                    padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
                    minHeight: 52.0,
                    title: sheetCtx.trOr(
                      'browser_vault_addr_default_switch_title',
                      'Использовать по умолчанию',
                    ),
                    trailing: AdaptiveSwitch(
                      key: const ValueKey('browser_vault_addr_default_switch'),
                      value: isDefault,
                      onChanged: (v) => setSheetState(() => isDefault = v),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _buildSafariPillButton(
                  buttonKey: const ValueKey('browser_vault_addr_save_btn'),
                  backgroundColor: pal.primary,
                  foregroundColor: pal.onPrimary,
                  label: sheetCtx.trOr('common_save', 'Сохранить'),
                  height: 42.0,
                  fontSize: 14.5,
                  onTap: () async {
                    final candidate = BrowserSavedAddress(
                      id: existing?.id ?? '',
                      label: labelCtrl.text.trim(),
                      fullName: fullNameCtrl.text.trim(),
                      organization: orgCtrl.text.trim(),
                      addressLine1: line1Ctrl.text.trim(),
                      addressLine2: line2Ctrl.text.trim(),
                      city: cityCtrl.text.trim(),
                      region: regionCtrl.text.trim(),
                      postalCode: postalCtrl.text.trim(),
                      country: countryCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      isDefault: isDefault,
                    );
                    if (!candidate.hasAnyField && candidate.label.isEmpty) {
                      GlassToastService().show(
                        sheetCtx,
                        sheetCtx.trOr(
                          'browser_vault_addr_empty_error',
                          'Заполните хотя бы одно поле адреса',
                        ),
                        icon: Icons.error_outline_rounded,
                      );
                      return;
                    }
                    await BrowserVaultService.instance
                        .saveOrUpdateAddress(candidate);
                    if (sheetCtx.mounted) {
                      Navigator.of(sheetCtx).pop('saved');
                    }
                  },
                ),
                if (existing != null) ...[
                  const SizedBox(height: 10),
                  _buildSafariPillButton(
                    buttonKey: const ValueKey('browser_vault_addr_delete_btn'),
                    backgroundColor: pal.error.withValues(
                      alpha: st.isDark ? 0.18 : 0.10,
                    ),
                    foregroundColor: pal.error,
                    icon: Icons.delete_outline_rounded,
                    label: sheetCtx.trOr('common_delete', 'Удалить'),
                    height: 38.0,
                    fontSize: 13.5,
                    onTap: () async {
                      await BrowserVaultService.instance
                          .deleteAddress(existing.id);
                      if (sheetCtx.mounted) {
                        Navigator.of(sheetCtx).pop('deleted');
                      }
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    labelCtrl.dispose();
    fullNameCtrl.dispose();
    orgCtrl.dispose();
    line1Ctrl.dispose();
    line2Ctrl.dispose();
    cityCtrl.dispose();
    regionCtrl.dispose();
    postalCtrl.dispose();
    countryCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();

    if (actionResult != null && mounted) {
      await _syncContactControllersFromVault();
      if (mounted) {
        GlassToastService().show(
          context,
          actionResult == 'deleted'
              ? context.trOr(
                  'browser_vault_address_deleted_toast',
                  'Адрес удалён',
                )
              : context.trOr(
                  'browser_vault_address_saved_toast',
                  'Адрес сохранён',
                ),
          icon: Icons.check_rounded,
        );
      }
    }
  }

  Future<void> _saveContactProfile({bool showToast = true}) async {
    final savedMsg = context.trOr(
      'browser_vault_contact_saved_toast',
      'Контактные данные сохранены',
    );
    final profile = BrowserContactProfile(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      enabled: _contactEnabled,
    );
    await BrowserVaultService.instance.saveContactProfile(profile);
    await BrowserSiteSettingsService.instance
        .setContactAutofillEnabled(_contactEnabled);
    if (!mounted) return;
    _savedContactProfile = profile;
    _hasSavedContactSnapshot = true;
    _syncContactDirtyFlag();
    setState(() {});
    if (showToast) {
      GlassToastService().show(
        context,
        savedMsg,
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
    final clearedMsg = context.trOr(
      'browser_vault_clear_selected_done_toast',
      'Выбранные данные очищены',
    );

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
                title: sheetCtx.trOr(
                  'browser_vault_clear_dialog_title',
                  'Очистка данных браузера',
                ),
              ),
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                borderRadius: 20.0,
                dividerIndent: 14.0,
                showBorder: false,
                showShadow: false,
                backgroundColor: _cardFill(st),
                dividerColor: _dividerTint(st),
                footer: sheetCtx.trOr(
                  'browser_vault_clear_dialog_footer',
                  'Сохранённые пароли останутся в безопасности.',
                ),
                children: [
                  checkRow(
                    rowKey: const ValueKey('clear_opt_history'),
                    label: sheetCtx.trOr(
                      'browser_vault_clear_opt_history',
                      'История посещений',
                    ),
                    value: clearHistory,
                    onChanged: (v) => setSheetState(() => clearHistory = v),
                  ),
                  checkRow(
                    rowKey: const ValueKey('clear_opt_cookies'),
                    label: sheetCtx.trOr(
                      'browser_vault_clear_opt_cookies',
                      'Cookie и данные сайтов (WebStorage)',
                    ),
                    value: clearCookies,
                    onChanged: (v) => setSheetState(() => clearCookies = v),
                  ),
                  checkRow(
                    rowKey: const ValueKey('clear_opt_site_settings'),
                    label: sheetCtx.trOr(
                      'browser_vault_clear_opt_site_settings',
                      'Настройки сайтов и разрешения',
                    ),
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
                label: sheetCtx.trOr(
                  'browser_vault_clear_confirm_btn',
                  'Очистить выбранное',
                ),
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
        clearedMsg,
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
        label: context.trOr('common_add', 'Добавить'),
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
        label: context.trOr('browser_clear_action', 'Очистить'),
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
        options: [
          TheavSegmentOption<int>(
            value: 0,
            label: context.trOr('browser_autofill_passwords', 'Пароли'),
          ),
          TheavSegmentOption<int>(
            value: 1,
            label: context.trOr('browser_vault_tab_autofill', 'Автозаполнение'),
          ),
          TheavSegmentOption<int>(
            value: 2,
            label: context.trOr('browser_vault_tab_cookies', 'Cookie и сайты'),
          ),
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
                              ? context.trOr(
                                  'browser_vault_search_passwords_hint',
                                  'Поиск по сайтам и логинам...',
                                )
                              : context.trOr(
                                  'browser_vault_search_sites_hint',
                                  'Поиск по сайтам...',
                                ),
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
            title: context.trOr(
              'browser_vault_sheet_title',
              'Пароли и данные браузера',
            ),
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
        header: context.trOr(
          'browser_vault_never_save_header',
          'Никогда не сохранять',
        ),
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

    final String lockedTitle = context.trOr(
      'browser_vault_passwords_locked_title',
      'Пароли защищены',
    );
    final String lockedSubtitle = context.trOr(
      'browser_vault_passwords_locked_subtitle',
      'В связке сохранено паролей: {count}. Подтвердите личность для просмотра.',
      {'count': '${vault.hints.length}'},
    );
    final String lockedBtnLabel = _unlockInProgress
        ? context.trOr('browser_vault_checking', 'Проверка...')
        : context.trOr(
            'browser_vault_unlock_passwords_btn',
            'Разблокировать пароли',
          );

    if (!_unlocked && vault.neverSaveOrigins.isEmpty) {
      return SafariSheetEmptyState(
        icon: Icons.verified_user_rounded,
        title: lockedTitle,
        subtitle: lockedSubtitle,
        actionLabel: lockedBtnLabel,
        actionIcon: Icons.lock_open_rounded,
        isPrimaryAction: true,
        actionButtonKey: const ValueKey('browser_vault_unlock_btn'),
        onAction: _unlockInProgress ? null : _unlockPasswords,
      );
    }

    if (_unlocked && filtered.isEmpty && vault.neverSaveOrigins.isEmpty) {
      return SafariSheetEmptyState(
        icon: q.isNotEmpty ? Icons.search_off_rounded : Icons.key_rounded,
        title: q.isNotEmpty
            ? context.trOr('common_nothing_found', 'Ничего не найдено')
            : context.trOr(
                'browser_vault_no_passwords_title',
                'Нет сохранённых паролей',
              ),
        subtitle: q.isNotEmpty
            ? context.trOr(
                'browser_search_empty_subtitle',
                'Попробуйте изменить запрос поиска.',
              )
            : context.trOr(
                'browser_vault_no_passwords_subtitle',
                'Добавьте пароль вручную или сохраните его при входе на сайт.',
              ),
        actionLabel: q.isNotEmpty
            ? context.trOr('browser_search_reset', 'Сбросить поиск')
            : context.trOr('browser_vault_add_password_btn', 'Добавить пароль'),
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
                title: lockedTitle,
                subtitle: lockedSubtitle,
                actionLabel: lockedBtnLabel,
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
                  ? context.trOr('common_nothing_found', 'Ничего не найдено')
                  : context.trOr(
                      'browser_vault_no_passwords_title',
                      'Нет сохранённых паролей',
                    ),
              subtitle: q.isNotEmpty
                  ? context.trOr(
                      'browser_search_empty_subtitle',
                      'Попробуйте изменить запрос поиска.',
                    )
                  : context.trOr(
                      'browser_vault_no_passwords_subtitle',
                      'Добавьте пароль вручную или сохраните его при входе на сайт.',
                    ),
              actionLabel: q.isNotEmpty
                  ? context.trOr('browser_search_reset', 'Сбросить поиск')
                  : context.trOr(
                      'browser_vault_add_password_btn',
                      'Добавить пароль',
                    ),
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
              header: context.trOr(
                'browser_vault_saved_accounts_header',
                'Сохранённые аккаунты',
              ),
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
                        cred.username.isNotEmpty
                            ? cred.username
                            : context.trOr(
                                'browser_vault_no_username',
                                'Без логина',
                              ),
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
                        trailing: widget.onSelectForAutofill != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSafariPillButton(
                                    buttonKey: ValueKey(
                                      'browser_vault_autofill_btn_${cred.id}',
                                    ),
                                    backgroundColor: palette.primary.withValues(
                                      alpha: style.isDark ? 0.18 : 0.11,
                                    ),
                                    foregroundColor: palette.primary,
                                    label: context.trOr(
                                      'browser_vault_autofill_btn',
                                      'Автозаполнить',
                                    ),
                                    height: 28.0,
                                    horizontalPadding: 9.0,
                                    fontSize: 11.5,
                                    onTap: () =>
                                        _triggerAutofillSelection(cred.hint),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => unawaited(
                                      _openCredentialDetailSheet(cred),
                                    ),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Center(
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 19,
                                          color: palette.subtext
                                              .withValues(alpha: 0.72),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Icon(
                                Icons.chevron_right_rounded,
                                size: 19,
                                color: palette.subtext.withValues(alpha: 0.72),
                              ),
                        onTap: widget.onSelectForAutofill != null
                            ? () => _triggerAutofillSelection(cred.hint)
                            : () => unawaited(_openCredentialDetailSheet(cred)),
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
    final vault = BrowserVaultService.instance;
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
            header: context.trOr(
              'browser_autofill_passwords_and_system_header',
              'Пароли и система',
            ),
            children: [
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: context.trOr(
                  'browser_setting_save_passwords_title',
                  'Предлагать сохранение паролей',
                ),
                subtitle: context.trOr(
                  'browser_setting_save_passwords_subtitle',
                  'Показывать карточку сохранения после входа на сайте',
                ),
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
                title: context.trOr(
                  'browser_setting_os_autofill_title',
                  'Системное автозаполнение ОС',
                ),
                subtitle: context.trOr(
                  'browser_setting_os_autofill_subtitle',
                  'Совместимость с Android Autofill и связкой ключей iOS',
                ),
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_os_autofill_switch'),
                  value: settings.osAutofillEnabled,
                  onChanged: (v) => unawaited(settings.setOsAutofillEnabled(v)),
                ),
              ),
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: context.trOr(
                  'browser_setting_require_vault_auth_title',
                  'Запрашивать PIN или биометрию',
                ),
                subtitle: context.trOr(
                  'browser_setting_require_vault_auth_subtitle',
                  'Защищать доступ к паролям и банковским картам',
                ),
                trailing: AdaptiveSwitch(
                  key: const ValueKey(
                    'browser_setting_require_vault_auth_switch',
                  ),
                  value: settings.requireAuthForVaultAccess,
                  onChanged: (v) => unawaited(_toggleRequireVaultAuth(v)),
                ),
              ),
              TheavListRow(
                key: const ValueKey('browser_setting_vault_pin_tile'),
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: context.trOr(
                  'browser_setting_vault_pin_title',
                  'PIN-код сейфа браузера',
                ),
                subtitle: context.trOr(
                  'browser_setting_vault_pin_subtitle',
                  'Отдельный 4-значный PIN-код защиты хранилища',
                ),
                valueText: _hasVaultPin
                    ? context.trOr('browser_vault_pin_set', 'Установлен')
                    : context.trOr('browser_vault_pin_not_set', 'Не задан'),
                showChevron: true,
                onTap: () => unawaited(_onTapVaultPinTile()),
              ),
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: context.trOr(
                  'browser_setting_card_autofill_title',
                  'Автозаполнение банковских карт',
                ),
                subtitle: context.trOr(
                  'browser_setting_card_autofill_subtitle',
                  'Предлагать сохранённые карты при оплате на сайтах',
                ),
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_card_autofill_switch'),
                  value: settings.cardAutofillEnabled,
                  onChanged: (v) =>
                      unawaited(settings.setCardAutofillEnabled(v)),
                ),
              ),
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: context.trOr(
                  'browser_setting_otp_autofill_title',
                  'Автоподстановка одноразовых кодов (OTP)',
                ),
                subtitle: context.trOr(
                  'browser_setting_otp_autofill_subtitle',
                  'Предлагать коды подтверждения в полях ввода',
                ),
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_otp_autofill_switch'),
                  value: settings.otpAutofillEnabled,
                  onChanged: (v) =>
                      unawaited(settings.setOtpAutofillEnabled(v)),
                ),
              ),
              TheavListRow(
                padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
                minHeight: 54.0,
                title: context.trOr(
                  'browser_setting_contact_autofill_title',
                  'Автозаполнение контактов',
                ),
                subtitle: context.trOr(
                  'browser_setting_contact_autofill_subtitle',
                  'Предлагать имя, email и телефон в веб-формах',
                ),
                trailing: AdaptiveSwitch(
                  key: const ValueKey('browser_setting_contact_autofill_switch'),
                  value: _contactAutofillCardLoaded
                      ? _contactEnabled
                      : settings.contactAutofillEnabled,
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
            dividerIndent: 64.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: cardFill,
            dividerColor: dividerTint,
            header: context.trOr(
              'browser_vault_cards_header',
              'Банковские карты',
            ),
            headerTrailing: _buildSafariPillButton(
              buttonKey: const ValueKey('browser_vault_add_card_btn'),
              backgroundColor: pal.primary.withValues(
                alpha: style.isDark ? 0.18 : 0.11,
              ),
              foregroundColor: pal.primary,
              icon: Icons.add_rounded,
              label: context.trOr('common_add', 'Добавить'),
              height: 28.0,
              horizontalPadding: 10.0,
              fontSize: 12.0,
              onTap: () => unawaited(_openAddOrEditCardDialog()),
            ),
            footer: context.trOr(
              'browser_vault_card_cvv_never_stored',
              'CVV/CVC не сохраняется в целях безопасности.',
            ),
            children: [
              if (vault.cardHints.isEmpty)
                TheavListRow(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  minHeight: 54.0,
                  leading: Icon(
                    Icons.credit_card_outlined,
                    size: 20,
                    color: pal.subtext,
                  ),
                  title: context.trOr(
                    'browser_vault_cards_empty',
                    'Нет сохранённых банковских карт',
                  ),
                  subtitle: context.trOr(
                    'browser_vault_cards_empty_sub',
                    'Нажмите «Добавить», чтобы сохранить карту',
                  ),
                  showChevron: true,
                  onTap: () => unawaited(_openAddOrEditCardDialog()),
                )
              else
                for (final cardHint in vault.cardHints)
                  () {
                    final String cardTitle =
                        '${cardHint.brand.displayName} •••• ${cardHint.last4}';
                    final String cardSubtitle =
                        '${cardHint.holderName.isNotEmpty ? '${cardHint.holderName} • ' : ''}'
                        '${cardHint.formattedExpiry}'
                        '${cardHint.nickname.isNotEmpty ? ' • ${cardHint.nickname}' : ''}';
                    return TheavListRow(
                      key: ValueKey('browser_vault_card_tile_${cardHint.id}'),
                      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                      minHeight: 56.0,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: pal.primary.withValues(
                            alpha: style.isDark ? 0.20 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.credit_card_rounded,
                          size: 19,
                          color: pal.primary,
                        ),
                      ),
                      titleWidget: Text(
                        cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      subtitle: cardSubtitle,
                      trailing: widget.onSelectCardForAutofill != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSafariPillButton(
                                  buttonKey: ValueKey(
                                    'browser_vault_autofill_card_btn_${cardHint.id}',
                                  ),
                                  backgroundColor: pal.primary.withValues(
                                    alpha: style.isDark ? 0.18 : 0.11,
                                  ),
                                  foregroundColor: pal.primary,
                                  label: context.trOr(
                                    'browser_vault_autofill_btn',
                                    'Автозаполнить',
                                  ),
                                  height: 28.0,
                                  horizontalPadding: 9.0,
                                  fontSize: 11.5,
                                  onTap: () =>
                                      _triggerCardAutofillSelection(cardHint),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => unawaited(
                                    _openCardDetailSheet(cardHint),
                                  ),
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Center(
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        size: 19,
                                        color:
                                            pal.subtext.withValues(alpha: 0.72),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              size: 19,
                              color: pal.subtext.withValues(alpha: 0.72),
                            ),
                      onTap: widget.onSelectCardForAutofill != null
                          ? () => _triggerCardAutofillSelection(cardHint)
                          : () => unawaited(_openCardDetailSheet(cardHint)),
                    );
                  }(),
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
            header: context.trOr(
              'browser_vault_addresses_header',
              'Почтовые адреса',
            ),
            headerTrailing: _buildSafariPillButton(
              buttonKey: const ValueKey('browser_vault_add_address_btn'),
              backgroundColor: pal.primary.withValues(
                alpha: style.isDark ? 0.18 : 0.11,
              ),
              foregroundColor: pal.primary,
              icon: Icons.add_rounded,
              label: context.trOr('common_add', 'Добавить'),
              height: 28.0,
              horizontalPadding: 10.0,
              fontSize: 12.0,
              onTap: () => unawaited(_openAddOrEditAddressDialog()),
            ),
            children: [
              if (vault.addresses.isEmpty)
                TheavListRow(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  minHeight: 54.0,
                  leading: Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: pal.subtext,
                  ),
                  title: context.trOr(
                    'browser_vault_addresses_empty',
                    'Нет сохранённых адресов',
                  ),
                  subtitle: context.trOr(
                    'browser_vault_addresses_empty_sub',
                    'Добавьте адрес для быстрого заполнения форм',
                  ),
                  showChevron: true,
                  onTap: () => unawaited(_openAddOrEditAddressDialog()),
                )
              else
                for (final addr in vault.addresses)
                  () {
                    final String addrTitle = addr.displayTitle.isNotEmpty
                        ? addr.displayTitle
                        : context.trOr(
                            'browser_vault_address_untitled',
                            'Адрес',
                          );
                    final String addrSub = addr.summarySubtitle.isNotEmpty
                        ? addr.summarySubtitle
                        : context.trOr(
                            'browser_vault_address_empty_summary',
                            'Нажмите для редактирования',
                          );
                    return TheavListRow(
                      key: ValueKey('browser_vault_address_tile_${addr.id}'),
                      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                      minHeight: 56.0,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: pal.primary.withValues(
                            alpha: style.isDark ? 0.20 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 19,
                          color: pal.primary,
                        ),
                      ),
                      titleWidget: Row(
                        children: [
                          Flexible(
                            child: Text(
                              addrTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: pal.onSurface,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (addr.isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: pal.primary.withValues(
                                  alpha: style.isDark ? 0.20 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.trOr(
                                  'browser_vault_address_default_badge',
                                  'По умолчанию',
                                ),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: pal.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: addrSub,
                      trailing: widget.onSelectAddressForAutofill != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSafariPillButton(
                                  buttonKey: ValueKey(
                                    'browser_vault_autofill_address_btn_${addr.id}',
                                  ),
                                  backgroundColor: pal.primary.withValues(
                                    alpha: style.isDark ? 0.18 : 0.11,
                                  ),
                                  foregroundColor: pal.primary,
                                  label: context.trOr(
                                    'browser_vault_autofill_btn',
                                    'Автозаполнить',
                                  ),
                                  height: 28.0,
                                  horizontalPadding: 9.0,
                                  fontSize: 11.5,
                                  onTap: () =>
                                      _triggerAddressAutofillSelection(addr),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => unawaited(
                                    _openAddOrEditAddressDialog(existing: addr),
                                  ),
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Center(
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        size: 19,
                                        color:
                                            pal.subtext.withValues(alpha: 0.72),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              size: 19,
                              color: pal.subtext.withValues(alpha: 0.72),
                            ),
                      onTap: widget.onSelectAddressForAutofill != null
                          ? () => _triggerAddressAutofillSelection(addr)
                          : () => unawaited(
                                _openAddOrEditAddressDialog(existing: addr),
                              ),
                    );
                  }(),
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
            header: context.trOr(
              'browser_vault_contact_card_header',
              'Карточка контакта',
            ),
            children: [
              _buildSheetFieldRow(
                fieldKey: const ValueKey('browser_contact_name_input'),
                palette: pal,
                icon: Icons.badge_outlined,
                controller: _nameCtrl,
                focusNode: _nameFocusNode,
                hintText: context.trOr(
                  'browser_vault_contact_name_hint',
                  'Имя и фамилия',
                ),
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
                hintText: context.trOr(
                  'browser_vault_contact_phone_hint',
                  'Телефон',
                ),
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
                  label: context.trOr(
                    'browser_vault_from_profile_btn',
                    'Из профиля',
                  ),
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
                                            ? context.trOr(
                                                'browser_saved',
                                                'Сохранено',
                                              )
                                            : context.trOr(
                                                'common_save',
                                                'Сохранить',
                                              ),
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
    final Map<String, List<Uri>> originsByHost = <String, List<Uri>>{};
    for (final rawOrigin in dataSvc.knownOrigins) {
      final hostKey = BrowserSiteSettingsService.normalizeHostKey(rawOrigin);
      if (hostKey.isEmpty) continue;
      final list = originsByHost.putIfAbsent(hostKey, () => <Uri>[]);
      final parsed = Uri.tryParse(rawOrigin.trim());
      if (parsed != null && parsed.host.isNotEmpty) {
        list.add(parsed);
      }
    }
    final Set<String> allHosts = <String>{
      ...prefsMap.keys,
      ...originsByHost.keys,
    };
    final List<String> sortedHosts = allHosts.toList()..sort();
    final List<String> filteredHosts = q.isEmpty
        ? sortedHosts
        : sortedHosts.where((h) {
            final pref = prefsMap[h];
            final display = pref?.displayHost ?? '';
            final originMatch = (originsByHost[h] ?? const <Uri>[]).any(
              (u) => u.toString().toLowerCase().contains(q),
            );
            return h.toLowerCase().contains(q) ||
                display.toLowerCase().contains(q) ||
                originMatch;
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
            header: context.trOr(
              'browser_cookie_policy_header',
              'Политика cookie',
            ),
            footer: context.trOr(
              'browser_cookie_policy_footer',
              'Режим «Без сторонних cookie» усиливает приватность, но может нарушать OAuth-вход на некоторых сайтах.',
            ),
            children: [
              for (final option in [
                (
                  policy: BrowserCookiePolicy.allowAll,
                  title: context.trOr(
                    'browser_cookie_allow_all_title',
                    'Разрешить все cookie',
                  ),
                  sub: context.trOr(
                    'browser_cookie_allow_all_sub',
                    'Рекомендуется для стабильной работы сайтов и входа',
                  ),
                ),
                (
                  policy: BrowserCookiePolicy.blockThirdParty,
                  title: context.trOr(
                    'browser_cookie_block_third_party_title',
                    'Блокировать сторонние cookie',
                  ),
                  sub: context.trOr(
                    'browser_cookie_block_third_party_sub',
                    'Запрещает межсайтовое отслеживание',
                  ),
                ),
                (
                  policy: BrowserCookiePolicy.blockAll,
                  title: context.trOr(
                    'browser_cookie_block_all_title',
                    'Блокировать все cookie',
                  ),
                  sub: context.trOr(
                    'browser_cookie_block_all_sub',
                    'Сайты не смогут сохранять сессии входа',
                  ),
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
            header: context.trOr(
              'browser_sites_settings_header',
              'Настройки и данные сайтов',
            ),
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
                        ? context.trOr(
                            'browser_sites_search_empty',
                            'Сайты по запросу не найдены',
                          )
                        : context.trOr(
                            'browser_sites_empty',
                            'Нет сохранённых данных или индивидуальных настроек сайтов',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: pal.subtext),
                  ),
                )
              else
                for (final host in filteredHosts)
                  Builder(
                    builder: (ctx) {
                      final pref = prefsMap[host];
                      final List<Uri> siteOrigins =
                          originsByHost[host] ?? const <Uri>[];
                      final Uri? primaryOrigin =
                          siteOrigins.isNotEmpty ? siteOrigins.first : null;
                      final String primaryOriginStr =
                          primaryOrigin?.toString() ?? 'https://$host';
                      final bool isSiteSecure = siteOrigins.isEmpty
                          ? true
                          : primaryOriginStr.startsWith('https://');
                      final String displayHost =
                          pref?.displayHost.isNotEmpty == true
                              ? pref!.displayHost
                              : host;
                      final double? textZoom = pref?.textZoom;
                      final tags = <String>[
                        if (pref?.desktopMode == true)
                          ctx.trOr('browser_site_tag_desktop', 'ПК-версия'),
                        if (pref?.cameraPolicy == SitePermissionDecision.allow)
                          ctx.trOr('browser_site_tag_camera', 'Камера'),
                        if (pref?.microphonePolicy ==
                            SitePermissionDecision.allow)
                          ctx.trOr('browser_site_tag_microphone', 'Микрофон'),
                        if (pref?.muteJsDialogs == true)
                          ctx.trOr('browser_site_tag_mute_js', 'Без JS-окон'),
                        if (textZoom != null)
                          ctx.trOr(
                            'browser_site_tag_zoom',
                            'Масштаб {percent}%',
                            {'percent': '${(textZoom * 100).round()}'},
                          ),
                      ];
                      return TheavListRow(
                        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                        minHeight: 56.0,
                        leading: SafariDomainMonogramBadge(
                          host: displayHost,
                          isSecure: isSiteSecure,
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
                              : ctx.trOr(
                                  'browser_site_cookies_and_cache',
                                  'Cookie и кэш сайта',
                                ),
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
                          label: ctx.trOr('browser_clear_action', 'Очистить'),
                          height: 28.0,
                          horizontalPadding: 10.0,
                          fontSize: 12.0,
                          onTap: () async {
                            HapticUtils.selection();
                            final clearedHostMsg = ctx.trOr(
                              'browser_site_data_cleared_toast',
                              'Данные {host} очищены',
                              {'host': host},
                            );
                            if (siteOrigins.isEmpty) {
                              await dataSvc.clearSiteData('https://$host/');
                            } else {
                              for (final u in siteOrigins) {
                                final scheme = u.scheme.isNotEmpty
                                    ? u.scheme
                                    : 'https';
                                final targetUrl =
                                    '$scheme://${u.host}${u.hasPort && u.port > 0 ? ':${u.port}' : ''}/';
                                await dataSvc.clearSiteData(targetUrl);
                              }
                            }
                            await settings.resetHost(host);
                            if (context.mounted) {
                              GlassToastService().show(
                                context,
                                clearedHostMsg,
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
                  context.trOr(
                    'browser_clear_data_granular_title',
                    'Очистить данные браузера...',
                  ),
                  style: TextStyle(
                    color: pal.error,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: context.trOr(
                  'browser_clear_data_granular_subtitle',
                  'Выборочная очистка истории, cookie и настроек сайтов',
                ),
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
