import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/widgets/user/avatar_decoration_frame.dart';

void main() {
  test('AvatarDecorationPreset.builtInDefaults defines all 9 procedural presets with unique ids', () {
    const defaults = AvatarDecorationPreset.builtInDefaults;
    expect(defaults.length, 9);

    final ids = defaults.map((e) => e.id).toSet();
    expect(ids, containsAll(<String>[
      'neon_pulse',
      'aurora_halo',
      'sakura_petals',
      'cyber_grid',
      'golden_laurel',
      'frost_crystal',
      'prism_glass',
      'ember_flame',
      'starlight_orbit',
    ]));
  });

  testWidgets('AvatarDecorationFrame renders all presets cleanly (animated & static)', (tester) async {
    for (final preset in AvatarDecorationPreset.builtInDefaults) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarDecorationFrame(
                decoration: preset,
                avatarDiameter: 64,
                animate: true,
                child: const CircleAvatar(radius: 32, child: Text('A')),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('A'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarDecorationFrame(
                decoration: preset,
                avatarDiameter: 32,
                animate: false,
                child: const CircleAvatar(radius: 16, child: Text('B')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('AvatarDecorationFrame pauses cleanly for none or null decoration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AvatarDecorationFrame(
                decoration: null,
                avatarDiameter: 48,
                child: SizedBox(width: 48, height: 48, child: Text('NullDeco')),
              ),
              AvatarDecorationFrame(
                decoration: AvatarDecorationPreset(
                  id: 'none',
                  nameKey: 'decoNone',
                  category: 'none',
                  proceduralStyle: 'none',
                ),
                avatarDiameter: 48,
                child: SizedBox(width: 48, height: 48, child: Text('None')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('NullDeco'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    unawaited(Future<void>.value());
  });
}
