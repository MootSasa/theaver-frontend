import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/screens/settings/profile_screen.dart';
import 'package:theaver/screens/chat/user_profile_screen.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(Locale locale, this.translations) : super(locale);

  @override
  String translate(String key) => translations[key] ?? key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final Map<String, String> translations;
  const _TestAppLocalizationsDelegate([this.translations = const {}]);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(_TestAppLocalizations(locale, translations));
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

final Map<String, String> _kTranslations = {
  'profile_online': 'в сети',
  'chat_online': 'в сети',
  'chat_offline': 'не в сети',
  'chat_title': 'Чат',
  'call': 'Звонок',
  'video': 'Видео',
  'chat_mute': 'Заглушить',
  'chat_unmute': 'Включить звук',
  'profile_choose_photo': 'Выбрать фото',
  'profile_qr_code': 'QR-код',
  'profile_edit_btn': 'Изменить',
  'profile_delete_photo': 'Удалить',
  'profile_music': 'Музыка',
  'profile_phone': 'Телефон',
  'profile_bio': 'О себе',
  'profile_username': 'Имя пользователя',
  'profile_birthday': 'Дата рождения',
  'profile_age': 'Возраст',
  'profile_tab_wall': 'Стена',
  'profile_tab_gifts': 'Подарки',
};

Widget _wrapWithApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
      ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: [
        _TestAppLocalizationsDelegate(_kTranslations),
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unified Profile & Hero Transition Tests', () {
    testWidgets('FloatingGlassAppBar exposes matching Hero tags for avatar, name, and status', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          FloatingGlassAppBar(
            name: 'Pavel Durov',
            heroTag: 'durov_123',
            isOnline: true,
            onBack: () {},
            onTitleTap: () {},
          ),
        ),
      );

      await tester.pump();

      // Find Heroes by tag
      final avatarHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'profile_avatar_durov_123',
      );
      final nameHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'profile_name_durov_123',
      );
      final statusHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'profile_status_durov_123',
      );

      expect(avatarHero, findsOneWidget);
      expect(nameHero, findsOneWidget);
      expect(statusHero, findsOneWidget);
    });

    testWidgets('ProfileScreen in peer user mode renders name, status, and peer action buttons', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          const ProfileScreen(
            userId: 'peer_user_456',
            initialName: 'Nikolai Durov',
            initialIsOnline: true,
            heroTag: 'peer_user_456',
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Nikolai Durov'), findsWidgets);
      expect(find.text('в сети'), findsWidgets);

      // Verify matching Hero tags on ProfileScreen
      final avatarHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'profile_avatar_peer_user_456',
      );
      final nameHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'profile_name_peer_user_456',
      );
      final statusHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'profile_status_peer_user_456',
      );

      expect(avatarHero, findsOneWidget);
      expect(nameHero, findsOneWidget);
      expect(statusHero, findsOneWidget);

      // Verify peer user action icons (chat, phone, video, mute)
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    });

    testWidgets('Tapping center pill in FloatingGlassAppBar navigates directly to UserProfileScreen', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          FloatingGlassAppBar(
            name: 'Pavel Durov',
            heroTag: 'durov_hero',
            isOnline: true,
            onBack: () {},
            onTitleTap: () {},
            profileScreenBuilder: (context) => const UserProfileScreen(
              userId: 'durov_id',
              initialName: 'Pavel Durov',
              heroTag: 'durov_hero',
              isOnline: true,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Pavel Durov'), findsOneWidget);

      // Tap center pill
      await tester.tap(find.text('Pavel Durov'));
      await tester.pumpAndSettle();

      // Should now be on ProfileScreen with Nikolai/Pavel Durov profile UI
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
    });
  });
}
