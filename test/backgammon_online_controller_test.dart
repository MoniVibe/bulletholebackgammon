import 'dart:convert';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:bulletholebackgammon/src/game/engine/backgammon_online_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'checkBackendHealth marks backend healthy on successful /healthz',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/healthz');
        return http.Response(jsonEncode(<String, dynamic>{'ok': true}), 200);
      });
      final controller = BackgammonOnlineController(httpClient: client);
      addTearDown(controller.dispose);

      final healthy = await controller.checkBackendHealth(
        apiBaseUrl: 'http://localhost:8080',
      );

      expect(healthy, isTrue);
      expect(controller.backendHealthState, BackendHealthState.healthy);
      expect(controller.backendHealthMessage, isNull);
      expect(controller.backendHealthCheckedAt, isNotNull);
    },
  );

  test('checkBackendHealth marks backend unhealthy for invalid URL', () async {
    final controller = BackgammonOnlineController(
      httpClient: MockClient((_) async => http.Response('', 200)),
    );
    addTearDown(controller.dispose);

    final healthy = await controller.checkBackendHealth(
      apiBaseUrl: 'localhost',
    );

    expect(healthy, isFalse);
    expect(controller.backendHealthState, BackendHealthState.unhealthy);
    expect(controller.backendHealthMessage, contains('Use a full URL'));
  });

  test('wakeBackend pings /healthz with wake query parameter', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/healthz');
      expect(request.url.queryParameters['wake'], '1');
      return http.Response(jsonEncode(<String, dynamic>{'ok': true}), 200);
    });
    final controller = BackgammonOnlineController(httpClient: client);
    addTearDown(controller.dispose);

    final healthy = await controller.wakeBackend(
      apiBaseUrl: 'https://example.com',
    );

    expect(healthy, isTrue);
    expect(controller.backendHealthState, BackendHealthState.healthy);
    expect(controller.backendHealthMessage, isNull);
  });
}
