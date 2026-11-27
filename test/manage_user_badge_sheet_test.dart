import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/widgets/profile/manage_user_badge_sheet.dart';

void main() {
  testWidgets('ManageUserBadgeSheet lists only the 5 assignable roles (never CREATOR) and submits updates', (tester) async {
    String? lastBadgeSubmitted;
    UserBadge? returnedBadge;
    final currentDevBadge = UserBadge.builtInDefaults.firstWhere((b) => b.id == 'developer');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedBadge = await ManageUserBadgeSheet.show(
                  context,
                  targetUserId: 'u_target',
                  targetDisplayName: 'Alex',
                  currentBadge: currentDevBadge,
                  catalogOverride: UserBadge.builtInDefaults,
                  onUpdateBadge: (badgeId) async {
                    lastBadgeSubmitted = badgeId;
                    return true;
                  },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('CREATOR'), findsNothing);
    expect(find.text('DEV'), findsWidgets);
    expect(find.text('DESIGN'), findsWidgets);
    expect(find.text('EARLY'), findsWidgets);
    expect(find.text('BOOST'), findsWidgets);
    expect(find.text('BUG'), findsWidgets);
    expect(find.text('Revoke Badge'), findsOneWidget);

    await tester.tap(find.text('DESIGN').first);
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(lastBadgeSubmitted, 'designer');
    expect(returnedBadge?.id, 'designer');

    // Reopen and test revoking current badge
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke Badge'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(lastBadgeSubmitted, isNull);
    expect(returnedBadge, isNull);
  });

  testWidgets('ManageUserBadgeSheet hides Revoke button when user has no current badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManageUserBadgeSheet(
            targetUserId: 'u_empty',
            targetDisplayName: 'Bob',
            currentBadge: null,
            catalogOverride: UserBadge.builtInDefaults,
            onUpdateBadge: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.text('Revoke Badge'), findsNothing);
    expect(find.text('CREATOR'), findsNothing);
    expect(find.text('BUG'), findsWidgets);
  });
}
