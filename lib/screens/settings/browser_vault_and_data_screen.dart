import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/browser_data_service.dart';
import '../../services/browser_site_settings_service.dart';
import '../../services/browser_vault_auth_gate.dart';
import '../../services/browser_vault_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
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
    maxHeightFactor: 0.88,
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

  String _searchQuery = '';
  bool _unlocked = false;
  bool _unlockInProgress = false;
  List<BrowserSavedCredential> _unlockedCredentials =
      <BrowserSavedCredential>[];
  bool _contactAutofillCardLoaded = false;
  bool _contactEnabled = true;

  @override
  void initState() {
    super.initState();
    _activeSection = widget.initialSection.clamp(0, 2);
    _pageCtrl = PageController(initialPage: _activeSection);
    _searchQuery = widget.initialSearchQuery?.trim() ?? '';
    _searchCtrl = TextEditingController(text: _searchQuery);
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();

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
    _nameCtrl.text = profile.fullName;
    _emailCtrl.text = profile.email;
    _phoneCtrl.text = profile.phone;
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
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _selectSection(int idx) {
    if (_activeSection == idx) return;
    HapticUtils.selection();
    setState(() => _activeSection = idx);
    if (_pageCtrl.hasClients) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _pageCtrl.jumpToPage(idx);
      } else {
        _pageCtrl.animateToPage(
          idx,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    }
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
      title: existing == null ? 'Новый пароль' : existing.displayHost,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final st = TheavSurfaceStyle.of(sheetCtx);
          final pal = st.palette;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (existing == null) ...[
                  TextField(
                    key: const ValueKey('browser_vault_add_url_input'),
                    controller: urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Адрес сайта (например https://example.com)',
                      filled: true,
                      fillColor: pal.onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  key: const ValueKey('browser_vault_add_user_input'),
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText: 'Логин или Email',
                    filled: true,
                    fillColor: pal.onSurface.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('browser_vault_add_pass_input'),
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    filled: true,
                    fillColor: pal.onSurface.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                      onPressed: () => setSheetState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: Material(
                    color: pal.primary,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      key: const ValueKey('browser_vault_save_manual_btn'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: () async {
                        final rawUrl = urlCtrl.text.trim();
                        final normUrl = rawUrl.contains('://')
                            ? rawUrl
                            : 'https://$rawUrl';
                        if (BrowserVaultService.normalizeOrigin(normUrl) ==
                                null ||
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
                      child: Center(
                        child: Text(
                          'Сохранить',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: pal.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
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
    await showTheavModalSheet<void>(
      context: context,
      useRootNavigator: true,
      title: cred.displayHost.isNotEmpty ? cred.displayHost : cred.origin,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final pal = TheavSurfaceStyle.of(sheetCtx).palette;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.language_rounded, size: 20),
                    title: const Text('Сайт'),
                    subtitle: Text(
                      cred.origin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded, size: 20),
                    title: const Text('Логин'),
                    subtitle: Text(
                      cred.username.isNotEmpty ? cred.username : 'Без логина',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: cred.username.isEmpty
                          ? null
                          : () {
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
                    ),
                  ),
                  ListTile(
                    key: const ValueKey('browser_vault_detail_password_tile'),
                    leading: const Icon(Icons.key_rounded, size: 20),
                    title: const Text('Пароль'),
                    subtitle: Text(
                      reveal
                          ? cred.password
                          : '•' * cred.password.length.clamp(6, 14),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: pal.onSurface,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('browser_vault_detail_reveal_btn'),
                          icon: Icon(
                            reveal
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 19,
                          ),
                          onPressed: () =>
                              setSheetState(() => reveal = !reveal),
                        ),
                        IconButton(
                          key: const ValueKey('browser_vault_detail_copy_btn'),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () =>
                              _copyPasswordWithAutoWipe(sheetCtx, cred.password),
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
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Изменить'),
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        unawaited(
                          _openAddOrEditCredentialDialog(existing: cred),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('browser_vault_detail_delete_btn'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Удалить'),
                      onPressed: () async {
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

  Future<void> _saveContactProfile() async {
    final profile = BrowserContactProfile(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      enabled: _contactEnabled,
    );
    await BrowserVaultService.instance.saveContactProfile(profile);
    if (mounted) {
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
      title: 'Очистка данных браузера',
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final pal = TheavSurfaceStyle.of(sheetCtx).palette;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: const ValueKey('clear_opt_history'),
                value: clearHistory,
                onChanged: (v) =>
                    setSheetState(() => clearHistory = v ?? false),
                title: const Text('История посещений'),
              ),
              CheckboxListTile(
                key: const ValueKey('clear_opt_cookies'),
                value: clearCookies,
                onChanged: (v) =>
                    setSheetState(() => clearCookies = v ?? false),
                title: const Text('Cookie и данные сайтов (WebStorage)'),
              ),
              CheckboxListTile(
                key: const ValueKey('clear_opt_site_settings'),
                value: clearSiteSettings,
                onChanged: (v) =>
                    setSheetState(() => clearSiteSettings = v ?? false),
                title: const Text('Настройки сайтов и разрешения'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  'Сохранённые пароли останутся в безопасности.',
                  style: TextStyle(fontSize: 12, color: pal.subtext),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: Material(
                  color: pal.error,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    key: const ValueKey('clear_opt_confirm_btn'),
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => Navigator.of(sheetCtx).pop(true),
                    child: const Center(
                      child: Text(
                        'Очистить выбранное',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
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

    return Column(
      children: [
        if (widget.isModalSheet)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Пароли и данные браузера',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: palette.onSurface,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 21,
                      color: palette.subtext,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.isModalSheet ? 0 : 14),
          child: TheavSegmentedControl<int>(
            key: const ValueKey('browser_vault_section_segment'),
            expand: true,
            height: 38,
            options: const [
              TheavSegmentOption<int>(value: 0, label: 'Пароли'),
              TheavSegmentOption<int>(value: 1, label: 'Автозаполнение'),
              TheavSegmentOption<int>(value: 2, label: 'Cookie и сайты'),
            ],
            selected: _activeSection,
            onChanged: _selectSection,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            onPageChanged: (idx) {
              if (_activeSection != idx) {
                setState(() => _activeSection = idx);
              }
            },
            children: [
              _buildPasswordsTab(context, style),
              _buildAutofillTab(context, style),
              _buildCookiesAndSitesTab(context, style),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordsTab(BuildContext context, TheavSurfaceStyle style) {
    final palette = style.palette;
    final vault = BrowserVaultService.instance;
    final q = _searchQuery.toLowerCase();
    final filtered = _unlockedCredentials.where((c) {
      if (q.isEmpty) return true;
      return c.displayHost.toLowerCase().contains(q) ||
          c.origin.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        widget.isModalSheet ? 0 : 16,
        4,
        widget.isModalSheet ? 0 : 16,
        24,
      ),
      children: [
        if (!_unlocked)
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 38,
                      color: palette.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Пароли защищены',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'В связке сохранено паролей: ${vault.hints.length}. Подтвердите личность для просмотра.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: palette.subtext),
                    ),
                    const SizedBox(height: 14),
                    TheavFloatingPillButton(
                      key: const ValueKey('browser_vault_unlock_btn'),
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: _unlockInProgress
                          ? 'Проверка...'
                          : 'Разблокировать пароли',
                      isPrimary: true,
                      onTap: _unlockInProgress ? null : _unlockPasswords,
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('browser_vault_search_input'),
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Поиск по сайтам и логинам...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    isDense: true,
                    filled: false,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('browser_vault_add_password_btn'),
                tooltip: 'Добавить пароль',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => unawaited(_openAddOrEditCredentialDialog()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            TheavInsetGroup(
              margin: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'Совпадений не найдено'
                        : 'Нет сохранённых паролей. Они появятся здесь после входа на сайты.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: palette.subtext),
                  ),
                ),
              ],
            )
          else
            TheavInsetGroup(
              margin: EdgeInsets.zero,
              header: 'Сохранённые аккаунты (${filtered.length})',
              children: [
                for (final cred in filtered)
                  ListTile(
                    key: ValueKey('browser_vault_cred_tile_${cred.id}'),
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: palette.primary.withValues(alpha: 0.14),
                      child: Icon(
                        Icons.key_rounded,
                        size: 17,
                        color: palette.primary,
                      ),
                    ),
                    title: Text(
                      cred.displayHost.isNotEmpty
                          ? cred.displayHost
                          : cred.origin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        cred.username.isNotEmpty ? cred.username : 'Без логина',
                        if (cred.isHttpAuth) 'HTTP Auth',
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => unawaited(_openCredentialDetailSheet(cred)),
                  ),
              ],
            ),
        ],
        if (vault.neverSaveOrigins.isNotEmpty) ...[
          const SizedBox(height: 14),
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            header: 'Никогда не сохранять',
            children: [
              for (final origin in vault.neverSaveOrigins)
                ListTile(
                  leading: const Icon(Icons.block_rounded, size: 19),
                  title: Text(
                    origin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () =>
                        unawaited(vault.removeNeverSaveOrigin(origin)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAutofillTab(BuildContext context, TheavSurfaceStyle style) {
    final settings = BrowserSiteSettingsService.instance;
    final pal = style.palette;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        widget.isModalSheet ? 0 : 16,
        4,
        widget.isModalSheet ? 0 : 16,
        24,
      ),
      children: [
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          header: 'Пароли и система',
          children: [
            ListTile(
              title: const Text('Предлагать сохранение паролей'),
              subtitle: const Text(
                'Показывать карточку сохранения после входа на сайте',
              ),
              trailing: AdaptiveSwitch(
                key: const ValueKey('browser_setting_save_passwords_switch'),
                value: settings.savePasswordsEnabled,
                onChanged: (v) =>
                    unawaited(settings.setSavePasswordsEnabled(v)),
              ),
            ),
            ListTile(
              title: const Text('Системное автозаполнение ОС'),
              subtitle: const Text(
                'Совместимость с Android Autofill и связкой ключей iOS',
              ),
              trailing: AdaptiveSwitch(
                key: const ValueKey('browser_setting_os_autofill_switch'),
                value: settings.osAutofillEnabled,
                onChanged: (v) => unawaited(settings.setOsAutofillEnabled(v)),
              ),
            ),
            ListTile(
              title: const Text('Автозаполнение контактов'),
              subtitle: const Text(
                'Предлагать имя, email и телефон в веб-формах',
              ),
              trailing: AdaptiveSwitch(
                key: const ValueKey('browser_setting_contact_autofill_switch'),
                value: _contactEnabled,
                onChanged: (v) {
                  setState(() => _contactEnabled = v);
                  unawaited(settings.setContactAutofillEnabled(v));
                  if (_contactAutofillCardLoaded) {
                    unawaited(_saveContactProfile());
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          header: 'Карточка контакта',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('browser_contact_name_input'),
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Имя и фамилия',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('browser_contact_email_input'),
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('browser_contact_phone_input'),
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('browser_contact_prefill_btn'),
                          icon: const Icon(Icons.person_rounded, size: 17),
                          label: const Text('Из профиля'),
                          onPressed: _prefillContactFromAccount,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('browser_contact_save_btn'),
                          style: FilledButton.styleFrom(
                            backgroundColor: pal.primary,
                            foregroundColor: pal.onPrimary,
                          ),
                          onPressed: () => unawaited(_saveContactProfile()),
                          child: const Text('Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCookiesAndSitesTab(
    BuildContext context,
    TheavSurfaceStyle style,
  ) {
    final settings = BrowserSiteSettingsService.instance;
    final dataSvc = BrowserDataService.instance;
    final pal = style.palette;

    final Map<String, BrowserSitePreference> prefsMap =
        settings.sitePreferences;
    final Set<String> allHosts = <String>{
      ...prefsMap.keys,
      ...dataSvc.knownOrigins
          .map(BrowserSiteSettingsService.normalizeHostKey)
          .where((h) => h.isNotEmpty),
    };
    final List<String> sortedHosts = allHosts.toList()..sort();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        widget.isModalSheet ? 0 : 16,
        4,
        widget.isModalSheet ? 0 : 16,
        24,
      ),
      children: [
        TheavInsetGroup(
          margin: EdgeInsets.zero,
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
              ListTile(
                key: ValueKey('browser_cookie_policy_${option.policy.name}'),
                title: Text(option.title),
                subtitle: Text(
                  option.sub,
                  style: TextStyle(fontSize: 12, color: pal.subtext),
                ),
                trailing: settings.cookiePolicy == option.policy
                    ? Icon(Icons.check_rounded, color: pal.primary)
                    : null,
                onTap: () {
                  HapticUtils.selection();
                  unawaited(settings.setCookiePolicy(option.policy));
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          header: 'Настройки и данные сайтов (${sortedHosts.length})',
          children: [
            if (sortedHosts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Нет сохранённых данных или индивидуальных настроек сайтов',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: pal.subtext),
                ),
              )
            else
              for (final host in sortedHosts)
                Builder(
                  builder: (ctx) {
                    final pref = prefsMap[host];
                    final tags = <String>[
                      if (pref?.desktopMode == true) 'ПК-версия',
                      if (pref?.cameraPolicy == SitePermissionDecision.allow)
                        'Камера',
                      if (pref?.microphonePolicy ==
                          SitePermissionDecision.allow)
                        'Микрофон',
                      if (pref?.muteJsDialogs == true) 'Без JS-окон',
                    ];
                    return ListTile(
                      leading: const Icon(Icons.public_rounded, size: 19),
                      title: Text(
                        pref?.displayHost.isNotEmpty == true
                            ? pref!.displayHost
                            : host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        tags.isNotEmpty ? tags.join(' • ') : 'Cookie и кэш сайта',
                        style: TextStyle(fontSize: 12, color: pal.subtext),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
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
                        child: const Text('Очистить'),
                      ),
                    );
                  },
                ),
          ],
        ),
        const SizedBox(height: 14),
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          children: [
            ListTile(
              key: const ValueKey('browser_clear_data_granular_btn'),
              leading: Icon(Icons.delete_sweep_rounded, color: pal.error),
              title: Text(
                'Очистить данные браузера...',
                style: TextStyle(
                  color: pal.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Выборочная очистка истории, cookie и настроек сайтов',
              ),
              onTap: _showGranularClearDialog,
            ),
          ],
        ),
      ],
    );
  }
}
