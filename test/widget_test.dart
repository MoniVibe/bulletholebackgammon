// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bulletholebackgammon/main.dart';
import 'package:bulletholebackgammon/src/game/engine/backgammon_online_controller.dart';

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

    // Hermetic transport: the online panel's automatic backend health check
    // and any transport call are served by an in-memory MockClient, so the
    // test never opens a real socket to localhost:8080. This makes the tab
    // switch deterministic and independent of test order / network state.
    var healthChecks = 0;
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/healthz')) {
        healthChecks += 1;
        return http.Response('{"message":"Healthy."}', 200);
      }
      // Any other transport call in this screen stays offline-safe.
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      BulletholeBackgammonApp(
        showOnlineTab: true,
        onlineControllerFactory: () =>
            BackgammonOnlineController(httpClient: mockClient),
      ),
    );
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

    // The panel's initState health check ran against the stub, not the network.
    expect(healthChecks, greaterThanOrEqualTo(1));
  });

  testWidgets('hides the online tab by default (ONLINE_TAB_ENABLED off)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // No showOnlineTab override: exercises the default kOnlineTabEnabled
    // flag, which is false unless ONLINE_TAB_ENABLED=true is dart-defined.
    await tester.pumpWidget(const BulletholeBackgammonApp());
    await tester.pump();

    expect(find.text('Sheshbesh Local'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.text('Sheshbesh Online'), findsNothing);
    expect(find.text('Game Menu'), findsOneWidget);
    expect(find.byKey(const ValueKey('top_bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_bar')), findsOneWidget);
  });
}
