import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/app_lock_service.dart';
import 'package:theaver/services/browser_data_service.dart';
import 'package:theaver/services/browser_otp_autofill_service.dart';
import 'package:theaver/services/browser_site_settings_service.dart';
import 'package:theaver/services/browser_vault_auth_gate.dart';
import 'package:theaver/services/browser_vault_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/websocket_service.dart';
import 'package:theaver/utils/browser_autofill_script.dart';
import 'package:theaver/widgets/browser/safari_autofill_overlays.dart';
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

class _FakeLocalAuth implements LocalAuthentication {
  _FakeLocalAuth({this.deviceSupported = false});
  final bool deviceSupported;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> get canCheckBiometrics async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapTestApp({
  required Widget child,
  GlassMode mode = GlassMode.full,
}) {
  return ChangeNotifierProvider<LiquidGlassProvider>.value(
    value: _TestLiquidGlassProvider(mode),
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void _expectNoTranslucentOpacityAboveGlass(WidgetTester tester) {
  final glassFinders = <Finder>[
    find.byType(LiquidGlassLens),
    find.byType(LiquidGlassMorph),
    find.byType(LiquidGlassSwitch),
    find.byType(TheavFloatingSurface),
  ];

  for (final finder in glassFinders) {
    for (final element in finder.evaluate()) {
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is Scaffold || widget is MaterialApp) return false;
        if (widget is Opacity && widget.opacity < 1.0) {
          fail('Forbidden translucent Opacity(${widget.opacity}) above glass $element');
        }
        if (widget is FadeTransition) {
          fail('Forbidden FadeTransition above glass $element');
        }
        if (widget is ClipRRect) {
          fail('Forbidden ClipRRect above glass $element');
        }
        return true;
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BrowserVaultService.instance.resetForTesting();
    BrowserVaultAuthGate.instance.resetForTesting();
    BrowserSiteSettingsService.instance.resetForTesting();
    BrowserDataService.instance.resetForTesting();
    BrowserOtpAutofillService.instance.resetForTesting();
    AppLocalizations.debugCurrent = null;
    await AppLockService.instance.init(lockOnInitIfConfigured: false);
  });

  tearDown(() {
    BrowserVaultService.instance.resetForTesting();
    BrowserVaultAuthGate.instance.resetForTesting();
    BrowserSiteSettingsService.instance.resetForTesting();
    BrowserDataService.instance.resetForTesting();
    BrowserOtpAutofillService.instance.resetForTesting();
    AppLocalizations.debugCurrent = null;
  });

  group('Payment Cards: Luhn, Brands, Encryption, HTTPS Guard & Multi-Account', () {
    test('validates Luhn, detects card brands, formats PAN groups, and checks expiry', () {
      // Valid Luhn PANs (test fixtures only)
      const visaPan = '4111 1111 1111 1111';
      const mcPan5 = '5500 0000 0000 0004';
      const mcPan2 = '2221 0000 0000 0009';
      const mirPan = '2200 7000 0000 0017';
      const amexPan = '3782 8224 6310 005';
      const unionPan = '6200 0000 0000 0005';
      const jcbPan = '3530 1113 3330 0000';

      expect(BrowserVaultService.isValidLuhn(visaPan), isTrue);
      expect(BrowserVaultService.detectCardBrand(visaPan), BrowserCardBrand.visa);

      expect(BrowserVaultService.isValidLuhn(mcPan5), isTrue);
      expect(BrowserVaultService.detectCardBrand(mcPan5), BrowserCardBrand.mastercard);
      expect(BrowserVaultService.isValidLuhn(mcPan2), isTrue);
      expect(BrowserVaultService.detectCardBrand(mcPan2), BrowserCardBrand.mastercard);

      expect(BrowserVaultService.isValidLuhn(mirPan), isTrue);
      expect(BrowserVaultService.detectCardBrand(mirPan), BrowserCardBrand.mir);

      expect(BrowserVaultService.isValidLuhn(amexPan), isTrue);
      expect(BrowserVaultService.detectCardBrand(amexPan), BrowserCardBrand.amex);
      expect(
        BrowserVaultService.formatCardNumberGroups(amexPan),
        '3782 822463 10005',
      );

      expect(BrowserVaultService.isValidLuhn(unionPan), isTrue);
      expect(BrowserVaultService.detectCardBrand(unionPan), BrowserCardBrand.unionpay);

      expect(BrowserVaultService.isValidLuhn(jcbPan), isTrue);
      expect(BrowserVaultService.detectCardBrand(jcbPan), BrowserCardBrand.jcb);

      // Invalid Luhn / too short
      expect(BrowserVaultService.isValidLuhn('4111 1111 1111 1112'), isFalse);
      expect(BrowserVaultService.isValidLuhn('411111111111'), isFalse);

      // Expiry boundary checks relative to Nov 2026
      final ref = DateTime(2026, 11, 15);
      expect(BrowserVaultService.isCardExpired(10, 2026, now: ref), isTrue);
      expect(BrowserVaultService.isCardExpired(11, 2026, now: ref), isFalse);
      expect(BrowserVaultService.isCardExpired(12, 26, now: ref), isFalse);
      expect(BrowserVaultService.isCardExpired(13, 2028, now: ref), isTrue);
    });

    test('encrypts cards with AES-256-GCM, never stores CVV, enforces HTTPS & isolates accounts', () async {
      final vault = BrowserVaultService.instance
        ..debugSecureStoreOverride = <String, String>{}
        ..debugUserIdOverride = 'alice';
      await vault.ensureLoaded(forceReload: true);

      // 1. Insecure HTTP and suspicious homograph pages cannot save cards
      final httpEval = await vault.evaluateCardSubmission(
        url: 'http://shop.example.org/checkout',
        cardNumber: '4111111111111111',
        holderName: 'ALICE IVANOVA',
        expMonth: 12,
        expYear: 2029,
      );
      expect(httpEval.status, BrowserCardSaveStatus.ignoredInsecureOrigin);

      final sslWarnEval = await vault.evaluateCardSubmission(
        url: 'https://shop.example.org/checkout',
        cardNumber: '4111111111111111',
        holderName: 'ALICE IVANOVA',
        expMonth: 12,
        expYear: 2029,
        hasSslWarning: true,
      );
      expect(sslWarnEval.status, BrowserCardSaveStatus.ignoredInsecureOrigin);

      // Mixed-script & Punycode homograph domains blocked
      final homographEval = await vault.evaluateCardSubmission(
        url: 'https://аpple.com/pay',
        cardNumber: '4111111111111111',
        holderName: 'ALICE IVANOVA',
        expMonth: 12,
        expYear: 2029,
      );
      expect(homographEval.status, BrowserCardSaveStatus.ignoredInsecureOrigin);

      final punyHomographEval = await vault.evaluateCardSubmission(
        url: 'https://xn--pple-43d.com/pay',
        cardNumber: '4111111111111111',
        holderName: 'ALICE IVANOVA',
        expMonth: 12,
        expYear: 2029,
      );
      expect(
        punyHomographEval.status,
        BrowserCardSaveStatus.ignoredInsecureOrigin,
      );

      // 2. Valid HTTPS submission evaluates as newCard and persists encrypted
      final validEval = await vault.evaluateCardSubmission(
        url: 'https://shop.example.org/checkout',
        cardNumber: '4111 1111 1111 1111',
        holderName: 'ALICE IVANOVA',
        expMonth: 12,
        expYear: 2029,
      );
      expect(validEval.status, BrowserCardSaveStatus.newCard);
      expect(validEval.brand, BrowserCardBrand.visa);
      expect(validEval.last4, '1111');

      final hint = await vault.saveOrUpdateCard(
        cardNumber: '4111 1111 1111 1111',
        holderName: 'ALICE IVANOVA',
        expMonth: 12,
        expYear: 2029,
        nickname: 'Основная Visa',
      );
      expect(hint.last4, '1111');
      expect(hint.brand, BrowserCardBrand.visa);
      expect(hint.formattedExpiry, '12/29');

      // Plaintext PAN & CVV/CVC must NEVER appear in SharedPreferences or hint JSON
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        final raw = prefs.get(k)?.toString() ?? '';
        expect(raw.contains('4111111111111111'), isFalse);
        expect(raw.toLowerCase().contains('cvv'), isFalse);
        expect(raw.toLowerCase().contains('cvc'), isFalse);
      }
      final hintJson = hint.toJson();
      expect(hintJson.containsKey('cvv'), isFalse);
      expect(hintJson.containsKey('cvc'), isFalse);
      expect(hintJson.containsKey('cardNumber'), isFalse);

      // Duplicate vs updated expiry evaluation
      final sameEval = await vault.evaluateCardSubmission(
        url: 'https://shop.example.org/checkout',
        cardNumber: '4111111111111111',
        holderName: 'alice ivanova',
        expMonth: 12,
        expYear: 29,
      );
      expect(sameEval.status, BrowserCardSaveStatus.alreadyUpToDate);

      final updateEval = await vault.evaluateCardSubmission(
        url: 'https://shop.example.org/checkout',
        cardNumber: '4111111111111111',
        holderName: 'ALICE IVANOVA',
        expMonth: 1,
        expYear: 2030,
      );
      expect(updateEval.status, BrowserCardSaveStatus.updateCard);
      expect(updateEval.existingId, hint.id);

      // Account isolation: bob cannot see alice's card
      vault.debugUserIdOverride = 'bob';
      await vault.ensureLoaded(forceReload: true);
      expect(vault.cardHints, isEmpty);

      // Switch back to alice, decrypt after auth, then wipe
      vault.debugUserIdOverride = 'alice';
      await vault.ensureLoaded(forceReload: true);
      expect(vault.cardHints, hasLength(1));

      // Verify invalid Luhn or expired card throws ArgumentError on save
      expect(
        () => vault.saveOrUpdateCard(
          cardNumber: '4111111111111119',
          holderName: 'ALICE',
          expMonth: 12,
          expYear: 2029,
        ),
        throwsArgumentError,
      );
      expect(
        () => vault.saveOrUpdateCard(
          cardNumber: '4111111111111111',
          holderName: 'ALICE',
          expMonth: 1,
          expYear: 2020,
        ),
        throwsArgumentError,
      );

      await vault.wipeAccountVault('alice');
      await vault.ensureLoaded(forceReload: true);
      expect(vault.cardHints, isEmpty);
    });
  });

  group('Postal Addresses & Legacy Contact Migration', () {
    test('supports encrypted multi-address CRUD, default toggle, and legacy contact migration', () async {
      final vault = BrowserVaultService.instance
        ..debugSecureStoreOverride = <String, String>{}
        ..debugUserIdOverride = 'alice';

      // Seed legacy encrypted contact profile directly before loading vault
      final prefs = await SharedPreferences.getInstance();
      final keyBytes = await vault.getOrCreateAccountMasterKey('alice');
      final legacyCipher = vault.encryptWithMasterKey(
        keyBytes,
        jsonEncode(<String, dynamic>{
          'fullName': 'Alexey Petrov',
          'email': 'alexey@theaver.app',
          'phone': '+79991112233',
          'enabled': true,
        }),
      );
      await prefs.setString('browser_vault_contact_v1_u_alice', legacyCipher);

      await vault.ensureLoaded(forceReload: true);
      expect(vault.addresses, hasLength(1));
      expect(vault.defaultAddress?.fullName, 'Alexey Petrov');
      expect(vault.defaultAddress?.email, 'alexey@theaver.app');
      expect(vault.defaultAddress?.isDefault, isTrue);

      final contact = await vault.getContactProfile();
      expect(contact.fullName, 'Alexey Petrov');
      expect(contact.phone, '+79991112233');

      // Add a second default postal address & reload from encrypted SharedPreferences
      final workAddr = await vault.saveOrUpdateAddress(
        BrowserSavedAddress(
          label: 'Офис',
          fullName: 'Alexey Petrov',
          organization: 'Theaver',
          addressLine1: 'Tverskaya St, 10',
          city: 'Moscow',
          postalCode: '125009',
          country: 'RU',
          phone: '+79991112233',
          email: 'work@theaver.app',
          isDefault: true,
        ),
      );
      expect(workAddr.isDefault, isTrue);

      await vault.ensureLoaded(forceReload: true);
      expect(vault.addresses, hasLength(2));
      expect(vault.defaultAddress?.id, workAddr.id);
      expect(vault.defaultAddress?.postalCode, '125009');

      // Plaintext address fields must not leak unencrypted in SharedPreferences
      final encRaw = prefs.getString('browser_vault_addresses_enc_v1_u_alice') ?? '';
      expect(encRaw.startsWith('v1:'), isTrue);
      expect(encRaw.contains('Tverskaya'), isFalse);

      // Reassign default & delete work address
      final legacyId = vault.addresses.firstWhere((a) => a.id != workAddr.id).id;
      await vault.setDefaultAddress(legacyId);
      expect(vault.defaultAddress?.id, legacyId);
      await vault.deleteAddress(workAddr.id);
      expect(vault.addresses, hasLength(1));
    });
  });

  group('BrowserAutofillScript Security & Classification', () {
    test('observer and injector scripts include card/address/OTP handling and exclude CVV / insecure HTTP cards', () {
      final observer = BrowserAutofillScript.buildObserverScript();
      expect(observer, contains('cc-number'));
      expect(observer, contains('isCscField'));
      expect(observer, contains('one-time-code'));
      expect(observer, contains('address-line1'));
      expect(observer, contains('window !== window.top'));

      final fillCard = BrowserAutofillScript.buildFillCardScript(
        expectedOrigin: 'https://checkout.example.org',
        cardNumber: '4111 1111 1111 1111',
        holderName: 'ALICE IVANOVA',
        expMonth: 8,
        expYear: 2029,
      );
      expect(fillCard, contains("window.location.protocol !== 'https:'"));
      expect(fillCard, contains('isCscField(el)'));
      expect(fillCard, contains('"https://checkout.example.org"'));
      expect(fillCard, contains('"4111111111111111"'));
      expect(fillCard, contains('"08/29"'));

      final fillAddress = BrowserAutofillScript.buildFillAddressScript(
        expectedOrigin: 'https://checkout.example.org',
        fullName: 'Alice Ivanova',
        addressLine1: 'Tverskaya 10',
        city: 'Moscow',
        postalCode: '125009',
        country: 'RU',
        phone: '+79990001122',
        email: 'alice@example.org',
      );
      expect(fillAddress, contains('address-level2'));
      expect(fillAddress, contains('postal-code'));
      expect(fillAddress, contains('"Tverskaya 10"'));

      final fillOtp = BrowserAutofillScript.buildFillOtpScript(
        expectedOrigin: 'https://auth.example.org',
        code: '73-92 01',
      );
      expect(fillOtp, contains('"739201"'));
      expect(fillOtp, contains('window.location.origin !== "https://auth.example.org"'));
    });
  });

  group('BrowserOtpAutofillService Extraction, TTL & Platform Clipboard Policy', () {
    test('extracts valid OTP codes while filtering URLs, money, phone numbers, and expired candidates', () async {
      DateTime fakeNow = DateTime(2026, 11, 23, 12, 0, 0);
      final controller = StreamController<WebSocketEvent>.broadcast();
      String? clipText;
      final otp = BrowserOtpAutofillService.forTesting(
        clock: () => fakeNow,
        eventStream: controller.stream,
        currentUserIdGetter: () => 'me_1',
        clipboardReader: () async => clipText,
      );
      addTearDown(() async {
        otp.resetForTesting();
        await controller.close();
      });

      expect(
        BrowserOtpAutofillService.extractOtpFromMessageText(
          'Ваш код подтверждения: 482910. Никому не сообщайте.',
        ),
        '482910',
      );
      expect(
        BrowserOtpAutofillService.extractOtpFromMessageText(
          'Verification code G-739201 for login',
        ),
        '739201',
      );
      expect(
        BrowserOtpAutofillService.extractOtpFromMessageText(
          'Подтвердите перевод 1500 ₽ по ссылке https://pay.example.org/987654 в 2026 году',
        ),
        isNull,
      );
      expect(
        BrowserOtpAutofillService.extractOtpFromMessageText(
          'Позвоните +7 (495) 123-4567 если не приходил звонок',
        ),
        isNull,
      );
      expect(
        BrowserOtpAutofillService.extractOtpFromMessageText(
          'Оплата 1234.56 руб. без подтверждения',
        ),
        isNull,
      );
      expect(BrowserOtpAutofillService.extractPureClipboardOtp(' 619204 '), '619204');
      expect(BrowserOtpAutofillService.extractPureClipboardOtp('Hello 619204'), isNull);

      // WebSocket incoming chat message from peer creates a 3-minute candidate
      otp.attachBrowserObserver();
      controller.add(
        WebSocketEvent(
          type: WebSocketEventType.newMessage,
          rawType: 'new_message',
          timestamp: fakeNow.millisecondsSinceEpoch,
          data: <String, dynamic>{
            'message': <String, dynamic>{
              'sender_id': 'bank_bot',
              'sender_name': 'Bank',
              'content': 'Ваш одноразовый код: 551820',
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(otp.activeCandidate?.code, '551820');
      expect(otp.activeCandidate?.sourceKind, 'chat');

      // Self-sent message does not overwrite
      controller.add(
        WebSocketEvent(
          type: WebSocketEventType.newMessage,
          rawType: 'new_message',
          timestamp: fakeNow.millisecondsSinceEpoch,
          data: <String, dynamic>{
            'message': <String, dynamic>{
              'sender_id': 'me_1',
              'content': 'Код: 999999',
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(otp.activeCandidate?.code, '551820');

      // Advance past 3-minute TTL -> expires
      fakeNow = fakeNow.add(const Duration(minutes: 3, seconds: 1));
      expect(otp.activeCandidate, isNull);

      // Clipboard policy: non-iOS reads pure-digit OTP on focus; iOS requires explicit tap
      clipText = '884422';
      await otp.onOtpFieldFocused(isIosPlatform: true);
      expect(otp.showExplicitPasteOtpAction, isTrue);
      expect(otp.activeCandidate, isNull);

      final tapped = await otp.readOtpFromClipboardByUserTap();
      expect(tapped, '884422');
      expect(otp.activeCandidate?.code, '884422');
      otp.consumeCandidate();
      expect(otp.activeCandidate, isNull);

      await otp.onOtpFieldFocused(isIosPlatform: false);
      expect(otp.showExplicitPasteOtpAction, isFalse);
      expect(otp.activeCandidate?.code, '884422');
    });
  });

  group('BrowserVaultAuthGate Toggle, Autonomous Vault PIN & UI Overlays', () {
    test('manages autonomous Vault PIN + lockout and respects requireAuthForVaultAccess vs forceChallenge', () async {
      DateTime fakeNow = DateTime(2026, 11, 23, 14, 0, 0);
      final gate = BrowserVaultAuthGate.instance
        ..resetForTesting()
        ..debugUserIdOverride = 'alice'
        ..debugPinStoreOverride = <String, String>{}
        ..debugClockOverride = () => fakeNow;
      BrowserSiteSettingsService.instance.debugUserIdOverride = 'alice';
      await BrowserSiteSettingsService.instance.ensureLoaded(forceReload: true);

      expect(await gate.hasVaultPin(), isFalse);
      await gate.setVaultPin('2580');
      expect(await gate.hasVaultPin(), isTrue);
      expect(await gate.verifyVaultPin('2580'), isTrue);

      // 5 wrong attempts trigger lockout
      for (int i = 0; i < 5; i++) {
        expect(await gate.verifyVaultPin('0000'), isFalse);
      }
      expect(gate.isVaultPinLockedOut, isTrue);
      // Even right PIN fails during lockout
      expect(await gate.verifyVaultPin('2580'), isFalse);

      // Advance past 30s first lockout window
      fakeNow = fakeNow.add(const Duration(seconds: 31));
      expect(gate.isVaultPinLockedOut, isFalse);
      expect(await gate.verifyVaultPin('2580'), isTrue);

      await gate.clearVaultPin();
      expect(await gate.hasVaultPin(), isFalse);
    });

    testWidgets('requireAuthForVaultAccess skips auth when off unless forceChallenge is true, and unprotected choice offers skip or PIN', (tester) async {
      final gate = BrowserVaultAuthGate.instance
        ..resetForTesting()
        ..debugUserIdOverride = 'alice'
        ..debugPinStoreOverride = <String, String>{};
      final settings = BrowserSiteSettingsService.instance
        ..debugUserIdOverride = 'alice';
      await settings.ensureLoaded(forceReload: true);
      await settings.setRequireAuthForVaultAccess(false);

      int promptCalls = 0;
      gate.debugAuthOverride = (_, __, ___) async {
        promptCalls++;
        return true;
      };

      late BuildContext hostCtx;
      await tester.pumpWidget(
        _wrapTestApp(
          child: Builder(
            builder: (ctx) {
              hostCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With requireAuth == false and forceChallenge == false -> zero prompts
      final noChallengeOk = await gate.authenticate(
        hostCtx,
        reason: 'Fill login',
      );
      expect(noChallengeOk, isTrue);
      expect(promptCalls, 0);

      // Disabling auth from Settings passes forceChallenge: true -> always challenges!
      final forcedOk = await gate.authenticate(
        hostCtx,
        reason: 'Disable vault protection',
        forceChallenge: true,
      );
      expect(forcedOk, isTrue);
      expect(promptCalls, 1);

      // Unprotected fallback choice sheet when debugAuthOverride == null and no PINs exist
      final prevLocalAuth = gate.debugLocalAuth;
      addTearDown(() => gate.debugLocalAuth = prevLocalAuth);
      gate.debugLocalAuth = _FakeLocalAuth(deviceSupported: false);
      gate.invalidateGrant();
      gate.debugAuthOverride = null;
      await settings.setRequireAuthForVaultAccess(true);

      bool authCompleted = false;
      final Future<bool> authFuture = gate
          .authenticate(
        hostCtx,
        reason: 'Unlock card',
      )
          .whenComplete(() {
        authCompleted = true;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(authCompleted, isFalse);
      expect(find.byKey(const ValueKey('browser_vault_unprotected_sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser_vault_unprotected_continue_btn')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('browser_vault_unprotected_continue_btn')));
      await tester.pumpAndSettle();
      expect(await authFuture, isTrue);
      expect(settings.requireAuthForVaultAccess, isFalse);
    });

    for (final mode in <GlassMode>[GlassMode.full, GlassMode.disabled]) {
      testWidgets('SafariSaveCardSheet & SafariAutofillAccessoryBar cards/OTP/addresses render without translucent glass in $mode', (tester) async {
        final cardHint = BrowserCardHint(
          id: 'card_1',
          brand: BrowserCardBrand.mir,
          last4: '0017',
          holderName: 'ALICE IVANOVA',
          expMonth: 12,
          expYear: 2029,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
        final address = BrowserSavedAddress(
          id: 'addr_1',
          label: 'Дом',
          fullName: 'Алиса Иванова',
          addressLine1: 'ул. Тверская, 10',
          city: 'Москва',
          postalCode: '125009',
          isDefault: true,
        );

        bool savedTapped = false;
        String? filledOtp;
        bool pasteOtpTapped = false;
        String? selectedCardId;
        String? selectedAddrId;

        await tester.pumpWidget(
          _wrapTestApp(
            mode: mode,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SafariSaveCardSheet(
                    candidate: const BrowserPendingCardSubmission(
                      url: 'https://checkout.example.org',
                      origin: 'https://checkout.example.org',
                      displayHost: 'checkout.example.org',
                      cardNumber: '2200700000000017',
                      holderName: 'ALICE IVANOVA',
                      expMonth: 12,
                      expYear: 2029,
                      isUpdate: false,
                    ),
                    onSave: () => savedTapped = true,
                    onDismiss: () {},
                  ),
                  const SizedBox(height: 12),
                  SafariAutofillAccessoryBar(
                    focusedField: const BrowserFocusedFieldState(
                      kind: 'card',
                      subtype: 'cc-number',
                      origin: 'https://checkout.example.org',
                    ),
                    hints: const [],
                    contactProfile: const BrowserContactProfile(),
                    totalSavedCount: 0,
                    onSelectCredential: (_) {},
                    onOpenPasswordPicker: () {},
                    onFillContact: () {},
                    onDismiss: () {},
                    cards: [cardHint],
                    totalSavedCardsCount: 1,
                    onSelectCard: (c) => selectedCardId = c.id,
                    onOpenCardPicker: () {},
                  ),
                  const SizedBox(height: 12),
                  SafariAutofillAccessoryBar(
                    focusedField: const BrowserFocusedFieldState(
                      kind: 'otp',
                      subtype: 'one-time-code',
                      origin: 'https://auth.example.org',
                      isSplitOtp: true,
                    ),
                    hints: const [],
                    contactProfile: const BrowserContactProfile(),
                    totalSavedCount: 0,
                    onSelectCredential: (_) {},
                    onOpenPasswordPicker: () {},
                    onFillContact: () {},
                    onDismiss: () {},
                    otpCandidateCode: '482910',
                    showExplicitPasteOtpChip: true,
                    onFillOtp: (code) => filledOtp = code,
                    onPasteOtpFromClipboard: () => pasteOtpTapped = true,
                  ),
                  const SizedBox(height: 12),
                  SafariAutofillAccessoryBar(
                    focusedField: const BrowserFocusedFieldState(
                      kind: 'address',
                      subtype: 'address-line1',
                      origin: 'https://checkout.example.org',
                    ),
                    hints: const [],
                    contactProfile: const BrowserContactProfile(),
                    totalSavedCount: 0,
                    onSelectCredential: (_) {},
                    onOpenPasswordPicker: () {},
                    onFillContact: () {},
                    onDismiss: () {},
                    addresses: [address],
                    onSelectAddress: (a) => selectedAddrId = a.id,
                    onOpenAddressPicker: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectNoTranslucentOpacityAboveGlass(tester);
        expect(find.byKey(const ValueKey('safari_save_card_sheet')), findsOneWidget);
        expect(find.text('CVV не сохраняется'), findsOneWidget);
        expect(find.textContaining('Мир •••• 0017'), findsWidgets);
        expect(find.byKey(const ValueKey('safari_autofill_card_chip_card_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_autofill_otp_chip')), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_autofill_paste_otp_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('safari_autofill_address_chip_addr_1')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('safari_save_card_confirm_btn')));
        await tester.tap(find.byKey(const ValueKey('safari_autofill_card_chip_card_1')));
        await tester.tap(find.byKey(const ValueKey('safari_autofill_otp_chip')));
        await tester.tap(find.byKey(const ValueKey('safari_autofill_paste_otp_btn')));
        await tester.tap(find.byKey(const ValueKey('safari_autofill_address_chip_addr_1')));
        await tester.pumpAndSettle();

        expect(savedTapped, isTrue);
        expect(selectedCardId, 'card_1');
        expect(filledOtp, '482910');
        expect(pasteOtpTapped, isTrue);
        expect(selectedAddrId, 'addr_1');
      });
    }
  });
}
