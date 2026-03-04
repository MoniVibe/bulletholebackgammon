// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholebackgammon/main.dart';

void main() {
  testWidgets('loads local shell and can switch to online tab', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const BulletholeBackgammonApp());
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Sheshbesh Local'), findsOneWidget);
    expect(find.text('Game Menu'), findsOneWidget);
    expect(find.textContaining('Status:'), findsOneWidget);
    expect(find.textContaining('Log:'), findsOneWidget);
    expect(find.text('Match Chat'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.byKey(const ValueKey('top_bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_bar')), findsOneWidget);

    await tester.tap(find.text('Game Menu'));
    await tester.pumpAndSettle();

    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Turn Cooldown (seconds)'), findsOneWidget);

    await tester.tap(find.text('Online').first);
    await tester.pumpAndSettle();

    expect(find.text('Sheshbesh Online'), findsOneWidget);
    expect(find.text('Matchmaking'), findsOneWidget);
    expect(find.text('Session Status'), findsOneWidget);
    expect(find.text('Transport Debug'), findsOneWidget);
  });
}
