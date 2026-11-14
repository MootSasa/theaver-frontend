import 'dart:async' show unawaited;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/screens/chat/archived_chats_screen.dart';
import 'package:theaver/services/archive_preferences_service.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/notification_settings_provider.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/chat/chat_selection_header.dart';
import 'package:theaver/widgets/common/adaptive_switch.dart';
import 'package:theaver/widgets/settings/settings_group.dart';

class _PreloadedLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations localizations;
  const _PreloadedLocalizationsDelegate(this.localizations);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(localizations);

  @override
  bool shouldReload(_PreloadedLocalizationsDelegate old) => false;
}

Future<AppLocalizations> _loadRuL10n(WidgetTester tester) async {
  final l10n = AppLocalizations(const Locale('ru'));
  await tester.runAsync(() => l10n.load());
  return l10n;
}

Future<void> _pumpAnim(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 350),
]) async {
  await tester.pump();
  await tester.pump(duration);
}

Widget _wrapWithApp({
  required AppLocalizations l10n,
  required LiquidGlassProvider glassProvider,
  NotificationSettingsProvider? notifProvider,
  required Widget home,
  ThemeData? theme,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LiquidGlassProvider>.value(value: glassProvider),
      if (notifProvider != null)
        ChangeNotifierProvider<NotificationSettingsProvider>.value(
          value: notifProvider,
        ),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      theme: theme ?? ThemeData.light(useMaterial3: true),
      localizationsDelegates: [
        _PreloadedLocalizationsDelegate(l10n),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru'), Locale('en')],
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  group('ArchivePreferencesService', () {
    test('persists and isolates hide-above-list preference per user', () async {
      final prefs = ArchivePreferencesService();
      await prefs.reloadForTest(userId: 'user_a');
      expect(prefs.isHiddenAboveList, isFalse);

      int notifyCount = 0;
      void listener() => notifyCount++;
      prefs.addListener(listener);
      addTearDown(() => prefs.removeListener(listener));

      await prefs.setHiddenAboveList(true);
      expect(prefs.isHiddenAboveList, isTrue);
      expect(notifyCount, 1);

      // Switching to another account defaults to false independently.
      await prefs.reloadForTest(userId: 'user_b');
      expect(prefs.isHiddenAboveList, isFalse);

      await prefs.toggleHiddenAboveList();
      expect(prefs.isHiddenAboveList, isTrue);
      await prefs.toggleHiddenAboveList();
      expect(prefs.isHiddenAboveList, isFalse);

      // Returning to user_a restores persisted true value.
      await prefs.reloadForTest(userId: 'user_a');
      expect(prefs.isHiddenAboveList, isTrue);
    });
  });

  group('AppDatabase archive pin reset and batch operations', () {
    test('setChatArchived and batchSetArchived reset isPinned on archive state change',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
      });

      const now = '2026-11-14T12:00:00Z';
      await db.saveChat(
        ChatsCompanion.insert(
          chatId: 'chat_1',
          chatType: 'private',
          name: 'Alice',
          updatedAt: now,
          isPinned: const Value(true),
          isArchived: const Value(false),
        ),
      );
      await db.saveChat(
        ChatsCompanion.insert(
          chatId: 'chat_2',
          chatType: 'group',
          name: 'Team',
          updatedAt: now,
          isPinned: const Value(true),
          isArchived: const Value(false),
          unreadCount: const Value(0),
        ),
      );

      await db.setChatArchived('chat_1', true);
      final archivedAfterSingle = await db.watchArchivedChats().first;
      expect(archivedAfterSingle.map((c) => c.chatId), ['chat_1']);
      expect(archivedAfterSingle.first.isArchived, isTrue);
      expect(archivedAfterSingle.first.isPinned, isFalse);

      await db.batchSetArchived(['chat_2'], true);
      await db.batchMarkAsUnread(['chat_1', 'chat_2']);

      final archivedAfterBatch = await db.watchArchivedChats().first;
      expect(archivedAfterBatch.length, 2);
      for (final chat in archivedAfterBatch) {
        expect(chat.isArchived, isTrue);
        expect(chat.isPinned, isFalse);
        expect(chat.unreadCount, -1);
      }

      await db.batchSetArchived(['chat_1'], false);
      final chat1 = await db.getChat('chat_1');
      expect(chat1?.isArchived, isFalse);
      expect(chat1?.isPinned, isFalse);
    });
  });

  group('ChatListAdaptiveTopBar', () {
    testWidgets(
      'morphs normal <-> selection mode, triggers actions/overflow in Classic mode, and fits 320px split pane without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final l10n = await _loadRuL10n(tester);
        final glassProvider = LiquidGlassProvider();
        await tester.runAsync(() => glassProvider.setMode(GlassMode.disabled));

        bool isSelectMode = false;
        int selectedCount = 0;
        bool isOverflowOpen = false;
        bool pinnedTapped = false;
        bool mutedTapped = false;
        bool archiveTapped = false;
        bool deleteTapped = false;
        bool canceledTapped = false;
        String? overflowActionId;

        Widget buildHarness({double? width}) {
          return StatefulBuilder(
            builder: (context, setState) {
              return _wrapWithApp(
                l10n: l10n,
                glassProvider: glassProvider,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width ?? 420,
                      height: 360,
                      child: Stack(
                        children: [
                          ChatListAdaptiveTopBar(
                            isSelectMode: isSelectMode,
                            selectedCount: selectedCount,
                            onCancelSelection: () {
                              canceledTapped = true;
                              setState(() {
                                isSelectMode = false;
                                selectedCount = 0;
                                isOverflowOpen = false;
                              });
                            },
                            isSelectionOverflowOpen: isOverflowOpen,
                            onSelectionOverflowOpenChanged: (open) {
                              setState(() => isOverflowOpen = open);
                            },
                            selectionConfig: SelectionQuickActionsConfig(
                              canPin: true,
                              onPin: () => pinnedTapped = true,
                              canMute: true,
                              onMute: () => mutedTapped = true,
                              canArchive: true,
                              onArchive: () => archiveTapped = true,
                              canDelete: true,
                              onDelete: () => deleteTapped = true,
                              overflowItems: [
                                SelectionMorphMenuItem(
                                  id: 'select_all',
                                  label: 'Выбрать все',
                                  iconBuilder: (color, size) => Icon(
                                    Icons.select_all,
                                    color: color,
                                    size: size,
                                  ),
                                ),
                              ],
                              onOverflowAction: (id) {
                                overflowActionId = id;
                              },
                            ),
                            showBackButton: true,
                            onBack: () {},
                            normalTitle: 'Архив',
                            normalTitleKey: 'archive_title',
                            normalMenuItems: [
                              SelectionMorphMenuItem(
                                id: 'archive_settings',
                                label: 'Настройки архива',
                                iconBuilder: (color, size) => Icon(
                                  Icons.settings,
                                  color: color,
                                  size: size,
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  isSelectMode = true;
                                  selectedCount = 2;
                                });
                              },
                              child: const Text('enter_select'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }

        await tester.pumpWidget(buildHarness());
        await tester.pump();
        expect(find.text('Архив'), findsOneWidget);

        // Morph into selection mode
        await tester.tap(find.text('enter_select'));
        await _pumpAnim(tester);
        expect(find.text('Выбрано: 2'), findsOneWidget);
        expect(find.byTooltip('Закрепить'), findsOneWidget);
        expect(find.byTooltip('Без звука'), findsOneWidget);
        expect(find.byTooltip('В архив'), findsOneWidget);
        expect(find.byTooltip('Удалить'), findsOneWidget);

        await tester.tap(find.byTooltip('Закрепить'));
        await tester.tap(find.byTooltip('Без звука'));
        await tester.tap(find.byTooltip('В архив'));
        await tester.tap(find.byTooltip('Удалить'));
        expect(pinnedTapped, isTrue);
        expect(mutedTapped, isTrue);
        expect(archiveTapped, isTrue);
        expect(deleteTapped, isTrue);

        // Open overflow menu and tap item
        await tester.tap(find.byTooltip('Ещё'));
        await _pumpAnim(tester);
        expect(find.text('Выбрать все'), findsOneWidget);
        await tester.tap(find.text('Выбрать все'));
        await _pumpAnim(tester);
        expect(overflowActionId, 'select_all');

        // Cancel selection morphs back to normal header
        await tester.tap(
          find.byKey(const ValueKey<String>('left_cancel_selection')),
        );
        await _pumpAnim(tester);
        expect(canceledTapped, isTrue);
        expect(find.text('Архив'), findsOneWidget);

        // Narrow 320px pane switches counter to compact without layout overflow
        isSelectMode = true;
        selectedCount = 12;
        isOverflowOpen = false;
        await tester.pumpWidget(buildHarness(width: 320));
        await _pumpAnim(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('center_select_counter_compact')),
          findsOneWidget,
        );
        expect(find.text('12'), findsOneWidget);
      },
    );

    testWidgets(
      'renders cleanly in Liquid Glass mode during normal and selection states',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(900, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final l10n = await _loadRuL10n(tester);
        final glassProvider = LiquidGlassProvider();
        await tester.runAsync(() => glassProvider.setMode(GlassMode.full));

        try {
          await tester.pumpWidget(
            _wrapWithApp(
              l10n: l10n,
              glassProvider: glassProvider,
              home: LiquidGlassScaffold(
                pixelRatio: 1.0,
                useSync: true,
                batch: false,
                appBar: ChatListAdaptiveTopBar(
                  isSelectMode: true,
                  selectedCount: 3,
                  onCancelSelection: () {},
                  normalTitle: 'Архив',
                  normalTitleKey: 'archive_title',
                  selectionConfig: SelectionQuickActionsConfig(
                    canPin: true,
                    onPin: () {},
                    canMute: true,
                    onMute: () {},
                    canArchive: true,
                    isUnarchive: true,
                    onArchive: () {},
                    canDelete: true,
                    onDelete: () {},
                    onOverflowAction: (_) {},
                  ),
                ),
                appBarTopMargin: 8.0,
                body: const Scaffold(
                  backgroundColor: Colors.transparent,
                  body: SizedBox.shrink(),
                ),
              ),
            ),
          );
          await _pumpAnim(tester);

          expect(tester.takeException(), isNull);
          expect(find.byType(LiquidGlassMorph), findsWidgets);
          expect(find.text('Выбрано: 3'), findsOneWidget);
          expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.runAsync(() => glassProvider.setMode(GlassMode.disabled));
        }
      },
    );
  });

  group('ChatListTileItem', () {
    testWidgets(
      'keeps timestamps and unread badges visible in selection mode and styles muted chats with BellOff and neutral gray badge',
      (WidgetTester tester) async {
        final l10n = await _loadRuL10n(tester);
        final glassProvider = LiquidGlassProvider();
        await tester.runAsync(() => glassProvider.setMode(GlassMode.disabled));

        final nowIso = DateTime.now().toUtc().toIso8601String();
        final mutedChat = Chat(
          id: 'muted_1',
          chatType: 'private',
          name: 'Тихая Алиса',
          lastMessage: 'Проверь сообщение',
          lastMessageTime: nowIso,
          updatedAt: nowIso,
          unreadCount: 5,
        );

        final theme = ThemeData.light(useMaterial3: true);
        await tester.pumpWidget(
          _wrapWithApp(
            l10n: l10n,
            glassProvider: glassProvider,
            theme: theme,
            home: Scaffold(
              body: ChatListTileItem(
                chat: mutedChat,
                isSelectMode: true,
                isSelected: true,
                isMuted: true,
                onTap: () {},
                onLongPress: () {},
                onSwipeAction: (_) async {},
              ),
            ),
          ),
        );
        await _pumpAnim(tester, const Duration(milliseconds: 250));

        expect(find.text('Тихая Алиса'), findsOneWidget);
        expect(find.text('Проверь сообщение', findRichText: true), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.textContaining(':'), findsOneWidget);
        expect(find.byType(iconoir.BellOff), findsOneWidget);

        // Unread badge uses neutral gray instead of accent primaryColor when muted.
        final badgeContainerFinder = find.ancestor(
          of: find.text('5'),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        );
        final badgeContainer = tester.widget<Container>(
          badgeContainerFinder.first,
        );
        final badgeDeco = badgeContainer.decoration as BoxDecoration;
        expect(badgeDeco.color, isNot(theme.colorScheme.primary));
        expect(badgeDeco.color, Colors.grey.withValues(alpha: 0.48));
      },
    );
  });

  group('ArchivedChatsScreen', () {
    testWidgets(
      'shows clean chat list without permanent settings card, enters multi-select on long press, and toggles ArchivePreferencesService from modal settings sheet',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final l10n = await _loadRuL10n(tester);
        final glassProvider = LiquidGlassProvider();
        await tester.runAsync(() => glassProvider.setMode(GlassMode.disabled));

        final archivePrefs = ArchivePreferencesService();
        await tester.runAsync(() => archivePrefs.reloadForTest(userId: ''));
        expect(archivePrefs.isHiddenAboveList, isFalse);

        final notifProvider = NotificationSettingsProvider();
        final db = AppDatabase.forTesting(NativeDatabase.memory());

        try {
          final nowIso = DateTime.now().toUtc().toIso8601String();
          await tester.runAsync(() async {
            await db.saveChat(
              ChatsCompanion.insert(
                chatId: 'arch_1',
                chatType: 'private',
                name: 'Архивный Борис',
                lastMessage: const Value('Привет из архива'),
                lastMessageTime: Value(nowIso),
                updatedAt: nowIso,
                unreadCount: const Value(3),
                isArchived: const Value(true),
              ),
            );
            await db.saveChat(
              ChatsCompanion.insert(
                chatId: 'arch_2',
                chatType: 'group',
                name: 'Рабочий чат',
                lastMessage: const Value('Отчёт готов'),
                lastMessageTime: Value(nowIso),
                updatedAt: nowIso,
                unreadCount: const Value(0),
                isArchived: const Value(true),
              ),
            );
          });

          await tester.pumpWidget(
            _wrapWithApp(
              l10n: l10n,
              glassProvider: glassProvider,
              notifProvider: notifProvider,
              home: ArchivedChatsScreen(database: db),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await _pumpAnim(tester, const Duration(milliseconds: 250));

          expect(find.text('Архивный Борис'), findsOneWidget);
          expect(find.text('Рабочий чат'), findsOneWidget);
          expect(find.text('3'), findsOneWidget);

          // No permanent top Settings card and no per-row unarchive IconButton.
          expect(find.byType(SettingsGroup), findsNothing);
          expect(
            find.widgetWithIcon(IconButton, Icons.unarchive_outlined),
            findsNothing,
          );

          // Long-pressing enters multi-select mode; tapping X exits cleanly.
          await tester.longPress(find.text('Архивный Борис'));
          await _pumpAnim(tester);
          expect(find.text('Выбрано: 1'), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey<String>('left_cancel_selection')),
          );
          await _pumpAnim(tester);
          expect(find.text('Выбрано: 1'), findsNothing);
          expect(find.text('Архив'), findsOneWidget);

          // Open header menu -> Настройки архива -> modal bottom sheet.
          await tester.tap(
            find.byKey(const ValueKey<String>('right_normal_dots')),
          );
          await _pumpAnim(tester);
          expect(find.text('Настройки архива'), findsOneWidget);

          await tester.tap(find.text('Настройки архива'));
          await _pumpAnim(tester, const Duration(milliseconds: 450));

          expect(find.byType(SettingsGroup), findsOneWidget);
          expect(find.text('Оставлять архив со звуком'), findsOneWidget);
          expect(find.text('Скрыть над списком'), findsOneWidget);
          expect(find.byType(AdaptiveSwitch), findsNWidgets(2));

          // Toggling the second switch updates ArchivePreferencesService.
          await tester.tap(find.byType(AdaptiveSwitch).at(1));
          await _pumpAnim(tester, const Duration(milliseconds: 250));
          expect(archivePrefs.isHiddenAboveList, isTrue);

          Navigator.of(tester.element(find.byType(SettingsGroup))).pop();
          await _pumpAnim(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
          unawaited(db.close());
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );
  });
}
