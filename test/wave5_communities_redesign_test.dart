import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import 'package:theaver/models/call_models.dart';
import 'package:theaver/models/community_models.dart';
import 'package:theaver/screens/community/community_screen.dart';
import 'package:theaver/screens/community/community_settings_sheet.dart';
import 'package:theaver/screens/community/create_community_screen.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/community/community_channel_icon.dart';
import 'package:theaver/widgets/community/community_members_panel.dart';
import 'package:theaver/widgets/design_system/theav_design_system.dart';

Community _buildSampleCommunity({
  bool isMember = true,
  bool withChannels = true,
}) {
  const adminRole = CommunityRole(
    id: 'role_admin',
    communityId: '10',
    name: 'Админы',
    colorHex: '#EF4444',
    position: 20,
    permissions: CommunityPermissions.administrator,
    isHoisted: true,
    isMentionable: true,
  );
  const modRole = CommunityRole(
    id: 'role_mod',
    communityId: '10',
    name: 'Модераторы',
    colorHex: '#10B981',
    position: 10,
    permissions: CommunityPermissions.viewChannel |
        CommunityPermissions.sendMessages |
        CommunityPermissions.kickMembers,
    isHoisted: true,
    isMentionable: true,
  );
  const everyoneRole = CommunityRole(
    id: 'role_everyone',
    communityId: '10',
    name: '@everyone',
    colorHex: '#99AAB5',
    position: 0,
    permissions: CommunityPermissions.defaultEveryone,
    isEveryone: true,
  );

  return Community(
    id: '10',
    name: 'Theaver Dev',
    description: 'Сообщество разработчиков и стримов',
    ownerId: '1',
    memberCount: 24,
    onlineCount: 9,
    isMember: isMember,
    isPublic: true,
    myPermissions:
        isMember ? CommunityPermissions.administrator : CommunityPermissions.defaultEveryone,
    categories: withChannels
        ? const [
            CommunityCategory(
              id: 'cat_text',
              communityId: '10',
              name: 'Общение',
              position: 0,
            ),
            CommunityCategory(
              id: 'cat_voice',
              communityId: '10',
              name: 'Голосовые',
              position: 1,
            ),
          ]
        : const [],
    channels: withChannels
        ? const [
            CommunityChannel(
              id: '101',
              communityId: '10',
              categoryId: 'cat_text',
              name: 'общий',
              topic: 'Главный чат',
              channelType: 'text',
              position: 0,
              unreadCount: 3,
            ),
            CommunityChannel(
              id: '102',
              communityId: '10',
              categoryId: 'cat_text',
              name: 'форум-идей',
              channelType: 'forum',
              position: 1,
            ),
            CommunityChannel(
              id: '103',
              communityId: '10',
              categoryId: 'cat_voice',
              name: 'Стрим-зал 144 FPS',
              channelType: 'voice',
              position: 0,
              activeVoiceParticipants: [
                CallParticipant(
                  userId: '2',
                  displayName: 'Alex',
                  isSpeaking: true,
                  isScreenSharing: true,
                ),
              ],
            ),
          ]
        : const [],
    roles: [adminRole, modRole, everyoneRole],
    createdAt: DateTime(2026, 1, 1),
  );
}

List<CommunityMember> _buildSampleMembers() {
  return const [
    CommunityMember(
      userId: '1',
      username: 'owner',
      displayName: 'Иван',
      isOnline: true,
      isVerified: true,
      roleIds: ['role_admin', 'role_everyone'],
    ),
    CommunityMember(
      userId: '2',
      username: 'alex_mod',
      displayName: 'Alex',
      isOnline: true,
      roleIds: ['role_mod', 'role_everyone'],
    ),
    CommunityMember(
      userId: '3',
      username: 'guest_online',
      displayName: 'Мария',
      isOnline: true,
      roleIds: ['role_everyone'],
    ),
    CommunityMember(
      userId: '4',
      username: 'offline_dev',
      displayName: 'Дмитрий',
      isOnline: false,
      roleIds: ['role_mod', 'role_everyone'],
    ),
  ];
}

Widget _wrapTestApp(Widget home, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0088CC),
        brightness: brightness,
      ),
      useMaterial3: true,
    ),
    home: home,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave 5 Models & Role Grouping Helpers', () {
    test('CommunityChannel.isForum, slowModeSeconds & category isPrivate', () {
      final cat = CommunityCategory.fromJson(const {
        'id': 4,
        'community_id': 10,
        'name': 'Закрытая',
        'position': 2,
        'is_private': true,
      });
      expect(cat.id, '4');
      expect(cat.isPrivate, isTrue);

      final forum = CommunityChannel.fromJson(const {
        'id': 77,
        'community_id': 10,
        'channel_kind': 'forum',
        'name': 'Баги',
        'slow_mode_seconds': 15,
        'voice_bitrate_kbps': 96,
        'voice_user_limit': 12,
      });
      expect(forum.isForum, isTrue);
      expect(forum.slowModeSeconds, 15);
      expect(forum.voiceBitrateKbps, 96);
      expect(forum.voiceUserLimit, 12);
    });

    test('CommunityPermissionOverwrite tri-state bitmask round-trip', () {
      var ow = const CommunityPermissionOverwrite(
        targetType: 'role',
        targetId: '42',
      );
      expect(ow.isEmpty, isTrue);
      expect(
        ow.stateForBit(CommunityPermissions.sendMessages),
        PermissionOverwriteState.inherit,
      );

      ow = ow.withBitState(
        CommunityPermissions.sendMessages,
        PermissionOverwriteState.deny,
      );
      expect(
        ow.stateForBit(CommunityPermissions.sendMessages),
        PermissionOverwriteState.deny,
      );

      ow = ow.withBitState(
        CommunityPermissions.viewChannel,
        PermissionOverwriteState.allow,
      );
      expect(
        ow.stateForBit(CommunityPermissions.viewChannel),
        PermissionOverwriteState.allow,
      );

      final serialized = ow.toJson();
      expect(serialized['target_id'], 42);
      final decoded = CommunityPermissionOverwrite.fromJson(serialized);
      expect(
        decoded.stateForBit(CommunityPermissions.sendMessages),
        PermissionOverwriteState.deny,
      );
      expect(
        decoded.stateForBit(CommunityPermissions.viewChannel),
        PermissionOverwriteState.allow,
      );

      ow = ow.withBitState(
        CommunityPermissions.sendMessages,
        PermissionOverwriteState.inherit,
      );
      ow = ow.withBitState(
        CommunityPermissions.viewChannel,
        PermissionOverwriteState.inherit,
      );
      expect(ow.isEmpty, isTrue);
    });

    test('CommunityBan, CommunityInvite, and groupMembersByHoistedRoles', () {
      final ban = CommunityBan.fromJson(const {
        'user_id': 99,
        'username': 'spammer',
        'display_name': 'Spam Bot',
        'reason': 'Флуд',
      });
      expect(ban.userId, '99');
      expect(ban.reason, 'Флуд');

      final inv = CommunityInvite.fromJson(const {
        'id': 5,
        'community_id': 10,
        'code': 'abcde12345',
        'max_uses': 10,
        'uses': 3,
      });
      expect(inv.code, 'abcde12345');
      expect(inv.isExpired, isFalse);

      final comm = _buildSampleCommunity();
      final members = _buildSampleMembers();
      final sections = groupMembersByHoistedRoles(members, comm.roles);

      // Sections: Админы (online), Модераторы (online), В сети (Мария), Не в сети (Дмитрий)
      expect(sections.map((s) => s.title).toList(), [
        'Админы',
        'Модераторы',
        'В сети',
        'Не в сети',
      ]);
      expect(sections[0].members.single.userId, '1');
      expect(sections[1].members.single.userId, '2');
      expect(sections[2].members.single.userId, '3');
      expect(sections[3].members.single.userId, '4');

      final colored = highestColoredRoleForMember(members.first, comm.roles);
      expect(colored?.id, 'role_admin');
      expect(colored?.parsedColor, const Color(0xFFEF4444));
    });
  });

  group('Wave 5 UI & Widget Tests', () {
    testWidgets(
      'CommunityScreen compact shows 3-part header, collapsible TheavInsetGroup categories, and LIVE voice participant',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(412, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final comm = _buildSampleCommunity();
        await tester.pumpWidget(
          _wrapTestApp(
            CommunityScreen(
              community: comm,
              autoFetch: false,
              initialMembers: _buildSampleMembers(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Theaver Dev'), findsOneWidget);
        expect(find.text('общий'), findsOneWidget);
        expect(find.text('форум-идей'), findsOneWidget);
        expect(find.text('Стрим-зал 144 FPS'), findsOneWidget);
        expect(find.text('Alex'), findsOneWidget);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.byType(CommunityAvatar), findsWidgets);
        expect(find.byType(TheavInsetGroup), findsWidgets);

        // Collapse category 'ОБЩЕНИЕ' and verify unread pill aggregates (3)
        await tester.tap(find.text('ОБЩЕНИЕ'));
        await tester.pumpAndSettle();
        expect(find.text('общий'), findsNothing);
        expect(find.text('3'), findsOneWidget);
      },
    );

    testWidgets(
      'CommunityScreen non-member renders floating Join CTA and desktop renders right CommunityMembersPane',
      (tester) async {
        // Non-member compact join bar
        await tester.binding.setSurfaceSize(const Size(412, 820));
        final nonMember = _buildSampleCommunity(isMember: false);
        await tester.pumpWidget(
          _wrapTestApp(
            CommunityScreen(
              key: const ValueKey('compact_non_member'),
              community: nonMember,
              autoFetch: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Вступить в «Theaver Dev»'), findsOneWidget);

        // Unmount compact non-member before resizing to desktop to avoid mounting GroupChatScreen
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        // Desktop wide layout (>= 1060px) renders left sidebar + right members pane
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final desktopComm = _buildSampleCommunity(withChannels: false);
        await tester.pumpWidget(
          _wrapTestApp(
            CommunityScreen(
              key: const ValueKey('desktop_members'),
              community: desktopComm,
              autoFetch: false,
              initialMembers: _buildSampleMembers(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CommunityMembersPane), findsOneWidget);
        expect(find.text('Иван'), findsOneWidget);
        expect(find.text('Мария'), findsOneWidget);
      },
    );

    testWidgets(
      'CommunityMembersPane filters members by search query across hoisted roles',
      (tester) async {
        final comm = _buildSampleCommunity();
        await tester.pumpWidget(
          _wrapTestApp(
            Scaffold(
              body: CommunityMembersPane(
                community: comm,
                members: _buildSampleMembers(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Иван'), findsOneWidget);
        expect(find.text('Дмитрий'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Мария');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(TheavListRow),
            matching: find.text('Мария'),
          ),
          findsOneWidget,
        );
        expect(find.text('Иван'), findsNothing);
        expect(find.text('Дмитрий'), findsNothing);
      },
    );

    testWidgets(
      'CommunitySettingsSheet switches tabs and toggles role permissions with TheavSwitch',
      (tester) async {
        Community latest = _buildSampleCommunity();
        await tester.pumpWidget(
          _wrapTestApp(
            Scaffold(
              body: CommunitySettingsSheet(
                community: latest,
                onCommunityUpdated: (updated) => latest = updated,
                autoFetch: false,
                initialMembers: _buildSampleMembers(),
                initialInvites: [
                  CommunityInvite(
                    id: '1',
                    communityId: '10',
                    code: 'theav12345',
                    uses: 2,
                    maxUses: 10,
                    createdAt: DateTime(2026, 1, 1),
                  ),
                ],
                initialBans: [
                  CommunityBan(
                    userId: '88',
                    username: 'banned_u',
                    displayName: 'Забаненный',
                    reason: 'Спам',
                    createdAt: DateTime(2026, 1, 1),
                  ),
                ],
                initialSounds: const [
                  SoundboardItem(
                    id: '7',
                    communityId: '10',
                    name: 'Фанфары',
                    emoji: '🎉',
                    durationMs: 1800,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Overview tab shows invite & TheavSwitch for public community
        expect(find.text('theav12345'), findsOneWidget);
        expect(find.byType(TheavSwitch), findsWidgets);

        // Switch to Роли tab and toggle a permission switch
        await tester.tap(find.text('Роли'));
        await tester.pumpAndSettle();
        expect(find.text('ОБЩИЕ ПРАВА'), findsOneWidget);

        // Select mod role and toggle 'Отправка сообщений' off
        await tester.tap(find.text('Модераторы'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Отправка сообщений'),
          200,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.tap(find.text('Отправка сообщений'));
        await tester.pumpAndSettle();
        final updatedMod = latest.roles.firstWhere((r) => r.id == 'role_mod');
        expect(
          (updatedMod.permissions & CommunityPermissions.sendMessages) == 0,
          isTrue,
        );

        // Switch to Участники -> Баны
        await tester.tap(find.text('Участники'));
        await tester.pumpAndSettle();
        expect(find.text('Иван'), findsOneWidget);
        await tester.tap(find.text('Баны (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Забаненный'), findsOneWidget);

        // Switch to Звуки
        await tester.tap(find.text('Звуки'));
        await tester.pumpAndSettle();
        expect(find.text('Фанфары'), findsOneWidget);
      },
    );

    testWidgets(
      'CreateCommunityScreen uses TheavSegmentedControl, CommunityAvatar squircle & TheavCheckCircle',
      (tester) async {
        await tester.pumpWidget(
          _wrapTestApp(const CreateCommunityScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TheavSegmentedControl<bool>), findsOneWidget);
        expect(find.byType(TheavCheckCircle), findsWidgets);
        expect(find.text('Гейминг & Стримы'), findsOneWidget);

        await tester.tap(find.text('Войти по коду'));
        await tester.pumpAndSettle();
        expect(find.text('Присоединиться по коду или ссылке'), findsOneWidget);
      },
    );

    testWidgets(
      'ChatListTileItem renders community as single general chat tile with squircle avatar, iconoir.Community, and active call ring',
      (tester) async {
        final commChat = Chat(
          id: 'community_10',
          chatType: 'community',
          name: 'Theaver Dev',
          lastMessage: '🔊 2 в голосовом • 24 участн.',
          updatedAt: '2026-11-19T12:00:00Z',
          unreadCount: 5,
          hasActiveCall: true,
        );

        await tester.pumpWidget(
          _wrapTestApp(
            Scaffold(
              body: ChatListTileItem(
                chat: commChat,
                isSelectMode: false,
                isSelected: false,
                isMuted: false,
                onTap: () {},
                onLongPress: () {},
                onSwipeAction: (_) async {},
              ),
            ),
            brightness: Brightness.light,
          ),
        );
        await tester.pump();

        expect(find.text('Theaver Dev'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.byType(iconoir.Community), findsWidgets);
        expect(find.byType(iconoir.SoundHigh), findsOneWidget);
      },
    );
  });
}
