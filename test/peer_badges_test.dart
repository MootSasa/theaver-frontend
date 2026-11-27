import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/widgets/common/peer_badges_widget.dart';

void main() {
  testWidgets('PeerBadgesRow renders each of the 6 role badge capsules', (tester) async {
    expect(UserBadge.builtInDefaults.length, 6);

    for (final badge in UserBadge.builtInDefaults) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PeerBadgesRow(
                badge: badge,
                interactiveBadge: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text(badge.shortTag), findsOneWidget);
    }
  });

  testWidgets('PeerBadgesRow suppresses custom badge when isBot is true', (tester) async {
    final creatorBadge = UserBadge.builtInDefaults.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeerBadgesRow(
            isBot: true,
            badge: creatorBadge,
            interactiveBadge: false,
          ),
        ),
      ),
    );

    expect(find.text('BOT'), findsOneWidget);
    expect(find.text('CREATOR'), findsNothing);
  });

  testWidgets('PeerBadgesRow renders empty SizedBox.shrink when no badges or verification', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PeerBadgesRow(
            isBot: false,
            isVerified: false,
            badge: null,
          ),
        ),
      ),
    );

    expect(find.byType(Row), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('PeerBadgesRow opens badge detail modal sheet on tap when interactiveBadge is true', (tester) async {
    final badge = UserBadge(
      id: 'developer',
      shortTag: 'DEV',
      nameKey: 'badgeDeveloperName',
      descKey: 'badgeDeveloperDesc',
      category: 'system',
      accentColorHex: '#7C4DFF',
      grantedAt: DateTime.utc(2026, 11, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PeerBadgesRow(
              badge: badge,
              interactiveBadge: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('DEV'));
    await tester.pumpAndSettle();

    expect(find.text('DEV'), findsNWidgets(3));
    expect(find.textContaining('01.11.2026'), findsOneWidget);
  });
}
