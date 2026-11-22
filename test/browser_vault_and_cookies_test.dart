import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:theaver/screens/settings/browser_vault_and_data_screen.dart';
import 'package:theaver/services/app_lock_service.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/browser_cookie_jar_vault.dart';
import 'package:theaver/services/browser_data_service.dart';
import 'package:theaver/services/browser_site_settings_service.dart';
import 'package:theaver/services/browser_storage_bridge.dart';
import 'package:theaver/services/browser_vault_auth_gate.dart';
import 'package:theaver/services/browser_vault_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/utils/browser_autofill_script.dart';
import 'package:theaver/widgets/bot/mini_app_webview_sheet.dart';
import 'package:theaver/widgets/browser/in_app_browser_sheet.dart';
import 'package:theaver/widgets/browser/safari_autofill_overlays.dart';
import 'package:theaver/widgets/browser/safari_library_sheet.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';

class _TestLiquidGlassProvider extends LiquidGlassProvider {
  _TestLiquidGlassProvider(this._mode);

  final GlassMode _mode;

  @override
  GlassMode get mode => _mode;

  @override
  bool get enabled => _mode != GlassMode.disabled;

  @override
  bool get isLite => _mode == GlassMode.lite;

  @override
  bool get isFull => _mode == GlassMode.full;
}

Widget _wrapTestApp({
  required Widget child,
  GlassMode mode = GlassMode.disabled,
}) {
  final glass = _TestLiquidGlassProvider(mode);
  return ChangeNotifierProvider<LiquidGlassProvider>.value(
    value: glass,
    child: MaterialApp(
      theme: ThemeData.light(),
      home: BackdropGroup(
        child: Scaffold(body: child),
      ),
    ),
  );
}

void _expectNoTranslucentOpacityAboveGlass(WidgetTester tester) {
  final glassFinder = find.byWidgetPredicate(
    (w) => w is LiquidGlassLens || w is LiquidGlassMorph,
  );
  for (final element in glassFinder.evaluate()) {
    element.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      // Stop once we exit the component subtree into the outer test MaterialApp shell.
      if (w is Scaffold || w is MaterialApp) return false;
      if (w is Opacity && w.opacity > 0.0 && w.opacity < 1.0) {
        fail('Found forbidden translucent Opacity(${w.opacity}) above ${element.widget.runtimeType}');
      }
      if (w is FadeTransition) {
        fail('Found forbidden FadeTransition above ${element.widget.runtimeType}');
      }
      return true;
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BrowserDataService.instance.resetForTesting();
    BrowserVaultService.instance.resetForTesting();
    BrowserSiteSettingsService.instance.resetForTesting();
    BrowserCookieJarVault.instance.resetForTesting();
    BrowserVaultAuthGate.instance.resetForTesting();
    BrowserStorageBridge.instance.debugBackendOverride = null;
    MiniAppSessionController.instance.resetForTesting();
    await SettingsService().init();
  });

  tearDown(() {
    BrowserStorageBridge.instance.debugBackendOverride = null;
    BrowserVaultAuthGate.instance.resetForTesting();
    BrowserCookieJarVault.instance.resetForTesting();
    BrowserSiteSettingsService.instance.resetForTesting();
    BrowserVaultService.instance.resetForTesting();
    BrowserDataService.instance.resetForTesting();
    MiniAppSessionController.instance.resetForTesting();
  });

  group('BrowserVaultService Encryption, Origin Isolation & Multi-Account', () {
    test('encrypts credentials with AES-256-GCM random IVs and isolates accounts', () async {
      final secureStore = <String, String>{};
      final vault = BrowserVaultService.instance
        ..debugSecureStoreOverride = secureStore
        ..debugUserIdOverride = 'alice';
      await vault.ensureLoaded(forceReload: true);

      final hint1 = await vault.saveOrUpdateCredential(
        url: 'https://github.com/login',
        username: 'alice_gh',
        password: 'MySuperSecretPassword!1',
      );
      final hint2 = await vault.saveOrUpdateCredential(
        url: 'https://gitlab.com/users/sign_in',
        username: 'alice_gl',
        password: 'MySuperSecretPassword!1',
      );

      final prefs = await SharedPreferences.getInstance();
      final rawSecret1 = prefs.getString('browser_vault_secret_v1_u_alice_${hint1.id}')!;
      final rawSecret2 = prefs.getString('browser_vault_secret_v1_u_alice_${hint2.id}')!;
      final rawIndex = prefs.getString('browser_vault_index_v1_u_alice')!;

      expect(rawSecret1, startsWith('v1:'));
      expect(rawSecret2, startsWith('v1:'));
      expect(rawSecret1, isNot(equals(rawSecret2)));
      expect(rawSecret1.contains('MySuperSecretPassword!1'), isFalse);
      expect(rawIndex.contains('MySuperSecretPassword!1'), isFalse);
      expect(secureStore.containsKey('browser_vault_mk_u_alice'), isTrue);

      // Account bob cannot see alice hints
      vault.debugUserIdOverride = 'bob';
      await vault.ensureLoaded(forceReload: true);
      expect(vault.hints, isEmpty);
      expect(vault.getHintsForUrl('https://github.com/settings'), isEmpty);

      // Switch back to alice & inspect candidate
      vault.debugUserIdOverride = 'alice';
      await vault.ensureLoaded(forceReload: true);
      expect(vault.hints.length, 2);

      final samePass = await vault.inspectCandidate(
        url: 'https://github.com/session',
        username: 'alice_gh',
        password: 'MySuperSecretPassword!1',
      );
      expect(samePass.status, BrowserVaultSaveStatus.alreadyUpToDate);

      final updatedPass = await vault.inspectCandidate(
        url: 'https://github.com/session',
        username: 'alice_gh',
        password: 'NewRotatedPassword!2',
      );
      expect(updatedPass.status, BrowserVaultSaveStatus.updatePassword);
      expect(updatedPass.existingId, hint1.id);

      // Never-save origin suppression & restoration
      await vault.markNeverSaveForUrl('https://private.corp/signin');
      final blocked = await vault.inspectCandidate(
        url: 'https://private.corp/auth',
        username: 'u',
        password: 'p',
      );
      expect(blocked.status, BrowserVaultSaveStatus.ignoredNeverSave);

      // Wipe alice deletes all secrets, index, and master key
      await vault.wipeAccountVault('alice');
      expect(vault.hints, isEmpty);
      expect(secureStore.containsKey('browser_vault_mk_u_alice'), isFalse);
      expect(prefs.getString('browser_vault_secret_v1_u_alice_${hint1.id}'), isNull);
    });

    test('enforces strict scheme, port, subdomain, and homograph isolation', () async {
      final secureStore = <String, String>{};
      final vault = BrowserVaultService.instance
        ..debugSecureStoreOverride = secureStore
        ..debugUserIdOverride = 'alice';
      await vault.ensureLoaded(forceReload: true);

      await vault.saveOrUpdateCredential(
        url: 'https://bank.example:443/login',
        username: 'depositor',
        password: 'VaultOnlyPassword',
      );

      expect(vault.getHintsForUrl('https://bank.example/transfer').length, 1);
      // Never leak https credentials onto insecure http
      expect(vault.getHintsForUrl('http://bank.example/login'), isEmpty);
      // Non-default port must not match :443 credential
      expect(vault.getHintsForUrl('https://bank.example:8443/login'), isEmpty);
      // Different subdomain must not match
      expect(vault.getHintsForUrl('https://sub.bank.example/login'), isEmpty);
      // Homograph-suspicious IDN host is blocked
      final homoEval = await vault.inspectCandidate(
        url: 'https://xn--80ak6aa92e.com/login', // apple Cyrillic spoof pattern
        username: 'victim',
        password: 'pw',
      );
      expect(homoEval.status, BrowserVaultSaveStatus.ignoredSuspiciousOrigin);
    });
  });

  group('BrowserVaultAuthGate PIN Verification & 20s Same-Origin Grant', () {
    testWidgets('gates credential unlock on AppLock PIN and enforces 20s same-origin grant lifecycle', (tester) async {
      final appLock = AppLockService.forTesting();
      await appLock.init(lockOnInitIfConfigured: false);
      expect(await appLock.setPin('1234'), isTrue);

      var now = DateTime(2026, 11, 22, 12, 0, 0);
      final gate = BrowserVaultAuthGate.forTesting(appLockService: appLock)
        ..debugClockOverride = () => now;
      final vault = BrowserVaultService.forTesting(
        authGate: gate,
        secureStore: <String, String>{},
        userId: 'alice',
      );
      await vault.ensureLoaded(forceReload: true);
      final hint = await vault.saveOrUpdateCredential(
        url: 'https://sso.example.org/step1',
        username: 'alice',
        password: 'TwoStepSecret!99',
      );

      late BuildContext hostCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          child: Builder(
            builder: (ctx) {
              hostCtx = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Wrong PIN is rejected
      final denyFuture = vault.unlockAndReadCredential(
        hostCtx,
        hint.id,
        reason: 'Unlock test',
        originScope: 'https://sso.example.org/step1',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('browser_vault_pin_sheet')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('browser_vault_pin_input')),
        '0000',
      );
      await tester.tap(find.byKey(const ValueKey('browser_vault_pin_submit_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Неверный PIN-код'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('browser_vault_pin_cancel_btn')));
      await tester.pumpAndSettle();
      expect(await denyFuture, isNull);

      // 2. Correct PIN unlocks and grants 20s same-origin access
      final okFuture = vault.unlockAndReadCredential(
        hostCtx,
        hint.id,
        reason: 'Unlock test',
        originScope: 'https://sso.example.org/step1',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('browser_vault_pin_input')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('browser_vault_pin_submit_btn')));
      await tester.pumpAndSettle();
      final cred = await okFuture;
      expect(cred, isNotNull);
      expect(cred!.password, 'TwoStepSecret!99');

      // 3. Second step on the SAME origin within 20s succeeds immediately (no modal)
      now = now.add(const Duration(seconds: 10));
      final secondStepCred = await vault.unlockAndReadCredential(
        hostCtx,
        hint.id,
        reason: 'Step 2',
        originScope: 'https://sso.example.org/step2-password',
      );
      expect(secondStepCred?.password, 'TwoStepSecret!99');

      // 4. Cross-origin navigation immediately invalidates the grant
      gate.onOriginChanged('https://other-site.org/');
      expect(gate.hasActiveGrantFor('https://sso.example.org'), isFalse);

      // 5. Grant re-acquired & invalidated immediately on AppLifecycleState.paused
      final regrantFuture = gate.authenticate(
        hostCtx,
        reason: 'Re-grant',
        originScope: 'https://sso.example.org',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('browser_vault_pin_input')),
        '1234',
      );
      await tester.tap(find.byKey(const ValueKey('browser_vault_pin_submit_btn')));
      await tester.pumpAndSettle();
      expect(await regrantFuture, isTrue);
      expect(gate.hasActiveGrantFor('https://sso.example.org'), isTrue);

      gate.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(gate.hasActiveGrantFor('https://sso.example.org'), isFalse);
    });
  });

  group('BrowserCookieJarVault Multi-Account & Private Mode Isolation', () {
    test('swaps encrypted cookie jars across accounts and isolates Private tabs', () async {
      final backend = InMemoryBrowserStorageBackend();
      BrowserStorageBridge.instance.debugBackendOverride = backend;
      final vault = BrowserVaultService.instance
        ..debugSecureStoreOverride = <String, String>{}
        ..debugUserIdOverride = 'alice';
      await vault.ensureLoaded(forceReload: true);

      final cookieVault = BrowserCookieJarVault.forTesting(
        bridge: BrowserStorageBridge.instance,
        vaultService: vault,
      );

      // Alice signs into a site (HttpOnly session cookie)
      backend.seedCookie(
        const BrowserCookieRecord(
          hostKey: '.mail.example.com',
          name: 'SID',
          value: 'alice_httponly_token',
          isSecure: true,
          isHttpOnly: true,
        ),
      );
      await cookieVault.snapshotAndClearForOutgoingAccount('alice');
      expect(backend.currentCookies, isEmpty);

      // Bob logs in cleanly with his own cookie
      await cookieVault.restoreForIncomingAccount('bob');
      expect(backend.currentCookies, isEmpty);
      backend.seedCookie(
        const BrowserCookieRecord(
          hostKey: '.mail.example.com',
          name: 'SID',
          value: 'bob_httponly_token',
          isSecure: true,
          isHttpOnly: true,
        ),
      );
      await cookieVault.snapshotAndClearForOutgoingAccount('bob');
      expect(backend.currentCookies, isEmpty);

      // Switch back to Alice -> exact HttpOnly session cookie restored
      await cookieVault.restoreForIncomingAccount('alice');
      expect(backend.currentCookies.length, 1);
      expect(backend.currentCookies.first.value, 'alice_httponly_token');
      expect(backend.currentCookies.first.isHttpOnly, isTrue);

      // Enter Private Browsing («Частный доступ») -> stashes normal cookie & starts empty
      await cookieVault.onIncognitoSessionOpened('priv_1');
      expect(cookieVault.isIncognitoActive, isTrue);
      expect(backend.currentCookies, isEmpty);

      cookieVault.onIncognitoUrlVisited('https://secret.onion.test/login');
      backend.seedCookie(
        const BrowserCookieRecord(
          hostKey: 'secret.onion.test',
          name: 'INCOGNITO_SID',
          value: 'ephemeral',
        ),
      );

      // Second private tab opens -> closing first keeps incognito alive
      await cookieVault.onIncognitoSessionOpened('priv_2');
      await cookieVault.onIncognitoSessionClosed('priv_1');
      expect(cookieVault.isIncognitoActive, isTrue);
      expect(backend.currentCookies.length, 1);

      // Closing last private tab wipes incognito cookie & restores Alice's normal jar
      await cookieVault.onIncognitoSessionClosed('priv_2');
      expect(cookieVault.isIncognitoActive, isFalse);
      expect(
        backend.clearedSites.any((u) => u.contains('secret.onion.test')),
        isTrue,
      );
      expect(backend.currentCookies.length, 1);
      expect(backend.currentCookies.first.value, 'alice_httponly_token');

      // Verify private MiniAppSession ignores history and save-password messages
      await BrowserDataService.instance.ensureLoaded(forceReload: true);
      final privSession = MiniAppSession(
        id: 'priv_session_msg',
        launchData: const MiniAppLaunchData(
          url: 'https://example.org/login',
          initData: '',
          botId: '',
          botUsername: '',
        ),
        isBrowser: true,
        isIncognito: true,
        initialUrl: 'https://example.org/login',
      );
      await privSession.handleAutofillChannelMessage(
        jsonEncode({
          'type': 'credentialsSubmitted',
          'origin': 'https://example.org',
          'username': 'hidden',
          'password': 'hiddenPassword',
        }),
      );
      expect(privSession.pendingCredentialPrompt, isNull);
      expect(BrowserDataService.instance.history, isEmpty);

      // Wiping account clears snapshot + live cookies
      await cookieVault.wipeAccountCookies('alice', isCurrentAccount: true);
      expect(backend.currentCookies, isEmpty);
    });
  });

  group('BrowserSiteSettingsService Persistence', () {
    test('persists cookie policy, desktop mode, permissions, and JS mute across reloads', () async {
      final settings = BrowserSiteSettingsService.instance
        ..debugUserIdOverride = 'alice';
      await settings.ensureLoaded(forceReload: true);

      await settings.setCookiePolicy(BrowserCookiePolicy.blockThirdParty);
      await settings.setDesktopModeForUrl('https://docs.example.com/guide', true);
      await settings.setPermissionForHost(
        'meet.example.com',
        camera: SitePermissionDecision.allow,
        microphone: SitePermissionDecision.deny,
      );
      await settings.setMuteJsDialogsForHost('spam.example.com', true);

      settings.resetForTesting();
      settings.debugUserIdOverride = 'alice';
      await settings.ensureLoaded(forceReload: true);

      expect(settings.cookiePolicy, BrowserCookiePolicy.blockThirdParty);
      expect(
        settings.preferenceForUrl('https://docs.example.com/other')?.desktopMode,
        isTrue,
      );
      expect(
        settings.preferenceForHost('meet.example.com')?.cameraPolicy,
        SitePermissionDecision.allow,
      );
      expect(
        settings.preferenceForHost('meet.example.com')?.microphonePolicy,
        SitePermissionDecision.deny,
      );
      expect(
        settings.preferenceForHost('spam.example.com')?.muteJsDialogs,
        isTrue,
      );

      await settings.resetHost('docs.example.com');
      expect(settings.preferenceForHost('docs.example.com'), isNull);
    });
  });

  group('Safari Liquid Glass & Material Dual-Mode UI Overlays', () {
    for (final mode in [GlassMode.full, GlassMode.disabled]) {
      testWidgets('Autofill bar and Save Password sheet render cleanly without translucent glass in $mode', (tester) async {
        final now = DateTime.now();
        String? savedUser;
        bool neverPressed = false;
        bool credTapped = false;

        await tester.pumpWidget(
          _wrapTestApp(
            mode: mode,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SafariAutofillAccessoryBar(
                  focusedField: const BrowserFocusedFieldState(
                    kind: 'login',
                    subtype: 'username',
                    origin: 'https://example.org',
                  ),
                  hints: [
                    BrowserCredentialHint(
                      id: 'c1',
                      origin: 'https://example.org',
                      asciiHost: 'example.org',
                      displayHost: 'example.org',
                      username: 'user@example.org',
                      createdAt: now,
                      updatedAt: now,
                    ),
                  ],
                  contactProfile: const BrowserContactProfile(),
                  totalSavedCount: 1,
                  onSelectCredential: (_) => credTapped = true,
                  onOpenPasswordPicker: () {},
                  onFillContact: () {},
                  onDismiss: () {},
                ),
                const SizedBox(height: 12),
                SafariSavePasswordSheet(
                  candidate: const BrowserPendingCredentialSubmission(
                    url: 'https://example.org/login',
                    origin: 'https://example.org',
                    displayHost: 'example.org',
                    username: 'user@example.org',
                    password: 'Password123!',
                    isUpdate: false,
                  ),
                  onSave: (u) => savedUser = u,
                  onNeverSave: () => neverPressed = true,
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectNoTranslucentOpacityAboveGlass(tester);
        expect(find.byKey(const ValueKey('safari_autofill_accessory_bar')), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_save_password_sheet')), findsOneWidget);
        expect(find.text('Сохранить пароль?'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('safari_autofill_credential_chip_c1')));
        await tester.pump();
        expect(credTapped, isTrue);

        await tester.enterText(
          find.byKey(const ValueKey('safari_save_password_username')),
          'edited@example.org',
        );
        await tester.tap(find.byKey(const ValueKey('safari_save_password_confirm_btn')));
        await tester.pump();
        expect(savedUser, 'edited@example.org');

        await tester.tap(find.byKey(const ValueKey('safari_save_password_never_btn')));
        await tester.pump();
        expect(neverPressed, isTrue);
      });
    }

    testWidgets('InAppBrowserSheet shows Частный badge & new overflow items in Incognito mode', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = MiniAppSession(
        launchData: const MiniAppLaunchData(
          url: 'https://duckduckgo.com/',
          initData: '',
          botId: '',
          botUsername: '',
          botDisplayName: 'duckduckgo.com',
        ),
        isBrowser: true,
        isIncognito: true,
        initialUrl: 'https://duckduckgo.com/',
      );

      await tester.pumpWidget(
        _wrapTestApp(
          mode: GlassMode.full,
          child: InAppBrowserSheet(session: session),
        ),
      );
      await tester.pumpAndSettle();

      _expectNoTranslucentOpacityAboveGlass(tester);
      expect(find.byType(LiquidGlassMorph), findsNWidgets(2));
      expect(find.byKey(const ValueKey('in_app_browser_incognito_badge')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('in_app_browser_menu_button')));
      await tester.pumpAndSettle();
      expect(find.text('Новая частная вкладка'), findsOneWidget);
      expect(find.text('Пароли и автозаполнение'), findsOneWidget);
    });

    testWidgets('BrowserVaultAndDataScreen navigates sections and updates cookie policy', (tester) async {
      BrowserSiteSettingsService.instance.debugUserIdOverride = 'alice';
      BrowserVaultService.instance.debugSecureStoreOverride = <String, String>{};
      BrowserVaultService.instance.debugUserIdOverride = 'alice';

      await tester.pumpWidget(
        _wrapTestApp(
          mode: GlassMode.disabled,
          child: const BrowserVaultAndDataScreen(
            initialSection: 0,
            autoUnlockPasswords: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('browser_vault_unlock_btn')), findsOneWidget);

      // Switch to Autofill tab
      await tester.tap(find.text('Автозаполнение'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('browser_setting_save_passwords_switch')),
        findsOneWidget,
      );

      // Switch to Cookies & Sites tab and select blockThirdParty
      await tester.tap(find.text('Cookie и сайты'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('browser_cookie_policy_blockThirdParty')),
      );
      await tester.pumpAndSettle();
      expect(
        BrowserSiteSettingsService.instance.cookiePolicy,
        BrowserCookiePolicy.blockThirdParty,
      );
    });

    for (final mode in [GlassMode.full, GlassMode.disabled]) {
      testWidgets(
        'BrowserVaultAndDataScreen matches SafariLibrarySheet design tokens & glass safety in $mode',
        (tester) async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          BrowserSiteSettingsService.instance.debugUserIdOverride = 'alice';
          final vault = BrowserVaultService.instance
            ..debugSecureStoreOverride = <String, String>{}
            ..debugUserIdOverride = 'alice';
          await vault.ensureLoaded(forceReload: true);
          for (int i = 0; i < 12; i++) {
            await vault.saveOrUpdateCredential(
              url: 'https://site$i.example.org/login',
              username: 'user$i@example.org',
              password: 'SecretPassword!$i',
            );
          }

          BrowserVaultAuthGate.instance.debugAuthOverride =
              (_, __, ___) async => true;
          addTearDown(() => BrowserVaultAuthGate.instance.debugAuthOverride = null);

          await tester.pumpWidget(
            _wrapTestApp(
              mode: mode,
              child: const BrowserVaultAndDataScreen(
                initialSection: 0,
                autoUnlockPasswords: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          _expectNoTranslucentOpacityAboveGlass(tester);

          // Unlock passwords
          await tester.tap(find.byKey(const ValueKey('browser_vault_unlock_btn')));
          await tester.pumpAndSettle();
          _expectNoTranslucentOpacityAboveGlass(tester);

          // Transparent borderless search bar + plain close clear icon
          final searchTf = tester.widget<TextField>(
            find.byKey(const ValueKey('browser_vault_search_input')),
          );
          expect(searchTf.decoration?.filled, isFalse);
          expect(searchTf.decoration?.fillColor, Colors.transparent);
          expect(searchTf.decoration?.border, InputBorder.none);

          await tester.enterText(
            find.byKey(const ValueKey('browser_vault_search_input')),
            'site3',
          );
          await tester.pumpAndSettle();
          final clearBtn = find.byKey(const ValueKey('browser_vault_search_clear_btn'));
          expect(clearBtn, findsOneWidget);
          expect(
            find.ancestor(of: clearBtn, matching: find.byType(IconButton)),
            findsNothing,
          );
          expect(find.text('site3.example.org'), findsOneWidget);
          expect(find.text('site0.example.org'), findsNothing);

          await tester.tap(clearBtn);
          await tester.pumpAndSettle();
          expect(find.text('site0.example.org'), findsOneWidget);

          // Borderless inset groups & Safari monogram badges
          final group = tester.widget<TheavInsetGroup>(
            find.byType(TheavInsetGroup).first,
          );
          expect(group.showBorder, isFalse);
          expect(group.showShadow, isFalse);
          expect(find.byType(SafariDomainMonogramBadge), findsWidgets);
          expect(find.byType(SafariFeatherScrollView), findsOneWidget);

          // Scroll list to verify feathered edge overlay mounts
          await tester.drag(find.byType(ListView).first, const Offset(0, -140));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('browser_vault_passwords_top_scroll_edge')),
            findsOneWidget,
          );

          // Switch to Autofill tab: verify zero ShaderMask/Opacity above LiquidGlassSwitch
          await tester.tap(find.text('Автозаполнение'), warnIfMissed: false);
          await tester.pumpAndSettle();
          _expectNoTranslucentOpacityAboveGlass(tester);
          if (mode == GlassMode.full) {
            expect(
              find.ancestor(
                of: find.byKey(const ValueKey('browser_setting_save_passwords_switch')),
                matching: find.byType(ShaderMask),
              ),
              findsNothing,
            );
          }

          // Contact card Save button adapts dynamically: Сохранить -> Сохранено -> Сохранить
          final saveBtnFinder = find.byKey(const ValueKey('browser_contact_save_btn'));
          expect(
            find.descendant(of: saveBtnFinder, matching: find.text('Сохранить')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: saveBtnFinder, matching: find.text('Сохранено')),
            findsNothing,
          );

          final nameInput = find.byKey(const ValueKey('browser_contact_name_input'));
          await tester.ensureVisible(nameInput);
          await tester.pumpAndSettle();
          await tester.tap(nameInput);
          await tester.pump();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          final EditableTextState initialNameEditableState = tester.state(
            find.descendant(of: nameInput, matching: find.byType(EditableText)),
          );

          // Simulate opening soft keyboard so the ListView viewport shrinks.
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();

          // Type character-by-character / IME composing without dismissing keyboard.
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'A',
              selection: TextSelection.collapsed(offset: 1),
              composing: TextRange(start: 0, end: 1),
            ),
          );
          await tester.pump();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          expect(
            identical(
              tester.state(
                find.descendant(
                  of: nameInput,
                  matching: find.byType(EditableText),
                ),
              ),
              initialNameEditableState,
            ),
            isTrue,
          );

          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'Alexey Ivanov',
              selection: TextSelection.collapsed(offset: 13),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          expect(
            identical(
              tester.state(
                find.descendant(
                  of: nameInput,
                  matching: find.byType(EditableText),
                ),
              ),
              initialNameEditableState,
            ),
            isTrue,
          );

          await tester.ensureVisible(saveBtnFinder);
          await tester.pumpAndSettle();
          await tester.tap(saveBtnFinder);
          await tester.pumpAndSettle();
          _expectNoTranslucentOpacityAboveGlass(tester);
          expect(
            find.descendant(of: saveBtnFinder, matching: find.text('Сохранено')),
            findsOneWidget,
          );
          expect(
            (await BrowserVaultService.instance.getContactProfile()).fullName,
            'Alexey Ivanov',
          );

          final emailInput = find.byKey(const ValueKey('browser_contact_email_input'));
          await tester.ensureVisible(emailInput);
          await tester.pumpAndSettle();
          await tester.tap(emailInput);
          await tester.pump();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'a',
              selection: TextSelection.collapsed(offset: 1),
              composing: TextRange(start: 0, end: 1),
            ),
          );
          await tester.pump();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'alexey@example.org',
              selection: TextSelection.collapsed(offset: 18),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          expect(
            find.descendant(of: saveBtnFinder, matching: find.text('Сохранить')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: saveBtnFinder, matching: find.text('Сохранено')),
            findsNothing,
          );

          tester.view.resetViewInsets();
          await tester.pumpAndSettle();

          // Advance past the 3s GlassToastService timer before tearing down.
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();

          // Switch to Cookie & Sites tab
          await tester.tap(find.text('Cookie и сайты'), warnIfMissed: false);
          await tester.pumpAndSettle();
          _expectNoTranslucentOpacityAboveGlass(tester);
          final cookieGroup = tester.widget<TheavInsetGroup>(
            find.byType(TheavInsetGroup).first,
          );
          expect(cookieGroup.showBorder, isFalse);
        },
      );
    }

    testWidgets('showBrowserVaultAndDataSheet opens with Safari header & close icon in GlassMode.full', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      BrowserVaultService.instance.debugSecureStoreOverride = <String, String>{};
      BrowserVaultService.instance.debugUserIdOverride = 'alice';
      BrowserVaultAuthGate.instance.debugAuthOverride =
          (_, __, ___) async => true;
      addTearDown(() => BrowserVaultAuthGate.instance.debugAuthOverride = null);

      late BuildContext hostCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          mode: GlassMode.full,
          child: Builder(
            builder: (ctx) {
              hostCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(
        showBrowserVaultAndDataSheet(
          hostCtx,
          initialSection: 0,
          autoUnlockPasswords: true,
        ),
      );
      await tester.pumpAndSettle();

      _expectNoTranslucentOpacityAboveGlass(tester);
      final sheetClose = find.byKey(const ValueKey('browser_vault_close_btn'));
      expect(sheetClose, findsOneWidget);
      expect(
        find.ancestor(of: sheetClose, matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('browser_vault_add_password_btn')), findsOneWidget);

      // Verify editing Contact Card inside modal sheet keeps soft keyboard open.
      await tester.tap(find.text('Автозаполнение'), warnIfMissed: false);
      await tester.pumpAndSettle();
      final modalNameInput = find.byKey(const ValueKey('browser_contact_name_input'));
      await tester.ensureVisible(modalNameInput);
      await tester.pumpAndSettle();
      await tester.tap(modalNameInput);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      final EditableTextState modalNameEditable = tester.state(
        find.descendant(of: modalNameInput, matching: find.byType(EditableText)),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'M',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(
        identical(
          tester.state(
            find.descendant(
              of: modalNameInput,
              matching: find.byType(EditableText),
            ),
          ),
          modalNameEditable,
        ),
        isTrue,
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      await tester.tap(sheetClose);
      await tester.pumpAndSettle();
      expect(sheetClose, findsNothing);
    });
  });
}
