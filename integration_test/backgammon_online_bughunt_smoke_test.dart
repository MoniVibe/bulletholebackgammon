import 'dart:async';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:bulletholebackgammon/src/game/engine/backgammon_online_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('online relay bughunt happy-path reaches session_complete', (
    tester,
  ) async {
    const backendFromDefine = String.fromEnvironment(
      'BUGHUNT_BACKEND_URL',
      defaultValue: '',
    );
    if (backendFromDefine.trim().isEmpty) {
      return;
    }

    final backendUrl = backendFromDefine.trim();
    final hostHttp = http.Client();
    final clientHttp = http.Client();
    final hostTransport = MultiplayerTransportClient(httpClient: hostHttp);
    final clientTransport = MultiplayerTransportClient(httpClient: clientHttp);
    final hostEvents = StreamController<Map<String, dynamic>>.broadcast();
    final clientEvents = StreamController<Map<String, dynamic>>.broadcast();

    addTearDown(() async {
      await hostTransport.disconnect();
      await clientTransport.disconnect();
      hostTransport.dispose();
      clientTransport.dispose();
      hostHttp.close();
      clientHttp.close();
      await hostEvents.close();
      await clientEvents.close();
    });

    final hostJoin = await hostTransport.joinMatch(
      apiBaseUrl: backendUrl,
      displayName: 'BgIntHost',
      gameType: 'backgammon',
      cooldownSeconds: 1,
      pieceSkinId: 'bg_ruby',
    );
    final clientJoin = await clientTransport.joinMatch(
      apiBaseUrl: backendUrl,
      displayName: 'BgIntClient',
      gameType: 'backgammon',
      cooldownSeconds: 1,
      pieceSkinId: 'bg_ruby',
    );

    await hostTransport.connectSocket(
      baseUri: hostJoin.baseUri,
      wsPath: hostJoin.wsPath,
      matchId: hostJoin.matchId,
      playerId: hostJoin.playerId,
      onMessage: (dynamic raw) {
        if (raw is! String) {
          return;
        }
        final decoded = MultiplayerClientUtils.decodeJsonMap(raw);
        hostEvents.add(decoded);
      },
      onError: (Object error) {
        hostEvents.add(<String, dynamic>{
          'type': 'error',
          'code': 'ws_error',
          'message': '$error',
        });
      },
      onDone: () {
        hostEvents.add(<String, dynamic>{'type': 'socket_done'});
      },
    );

    await clientTransport.connectSocket(
      baseUri: clientJoin.baseUri,
      wsPath: clientJoin.wsPath,
      matchId: clientJoin.matchId,
      playerId: clientJoin.playerId,
      onMessage: (dynamic raw) {
        if (raw is! String) {
          return;
        }
        final decoded = MultiplayerClientUtils.decodeJsonMap(raw);
        clientEvents.add(decoded);
      },
      onError: (Object error) {
        clientEvents.add(<String, dynamic>{
          'type': 'error',
          'code': 'ws_error',
          'message': '$error',
        });
      },
      onDone: () {
        clientEvents.add(<String, dynamic>{'type': 'socket_done'});
      },
    );

    final hostWelcome = await _waitFor(
      hostEvents.stream,
      (event) => event['type'] == 'welcome',
    );
    final clientWelcome = await _waitFor(
      clientEvents.stream,
      (event) => event['type'] == 'welcome',
    );

    final hostColor = hostWelcome['color']?.toString().trim().toLowerCase();
    final clientColor = clientWelcome['color']?.toString().trim().toLowerCase();
    expect(hostColor == 'w' || hostColor == 'b', isTrue);
    expect(clientColor == 'w' || clientColor == 'b', isTrue);

    hostTransport.sendJson(<String, dynamic>{'type': 'new_game'});

    await _waitFor(
      hostEvents.stream,
      (event) => event['type'] == 'state' && event['status'] == 'active',
    );
    await _waitFor(
      clientEvents.stream,
      (event) => event['type'] == 'state' && event['status'] == 'active',
    );

    hostTransport.sendJson(
      RelayEnvelope(
        event: RelayEventName.ready,
        payload: <String, Object?>{
          'kind': 'ready_signal',
          'actionId': 1,
          'actorColor': hostColor,
        },
      ).toSocketPayload(),
    );
    clientTransport.sendJson(
      RelayEnvelope(
        event: RelayEventName.ready,
        payload: <String, Object?>{
          'kind': 'ready_signal',
          'actionId': 1,
          'actorColor': clientColor,
        },
      ).toSocketPayload(),
    );

    await _waitFor(
      hostEvents.stream,
      (event) => event['type'] == 'relay_ack' && event['event'] == 'ready',
    );
    await _waitFor(
      clientEvents.stream,
      (event) => event['type'] == 'relay_ack' && event['event'] == 'ready',
    );

    final actorColor = hostColor!;
    final actionPayload =
        BackgammonOnlineProtocol.buildDeterministicActionPayload(
          seed: 333,
          step: 0,
          actorColor: actorColor,
        );
    final actionHash = BackgammonOnlineProtocol.buildActionStateHash(
      seed: 333,
      step: 0,
      actorColor: actorColor,
      payload: actionPayload,
    );

    hostTransport.sendJson(
      RelayEnvelope(
        event: RelayEventName.action,
        payload: actionPayload,
        stateHash: actionHash,
      ).toSocketPayload(),
    );

    await _waitFor(
      hostEvents.stream,
      (event) => event['type'] == 'relay_ack' && event['event'] == 'action',
    );
    await _waitFor(
      clientEvents.stream,
      (event) =>
          event['type'] == 'relay' &&
          event['event'] == 'action' &&
          event['stateHash'] == actionHash,
    );

    final result = BackgammonOnlineProtocol.buildSessionResult(
      seed: 333,
      actionCount: 1,
    );
    hostTransport.sendJson(
      RelayEnvelope(
        event: RelayEventName.complete,
        payload: <String, Object?>{
          'kind': 'session_complete',
          'actionId': 2000,
          'actorColor': actorColor,
        },
        result: result,
      ).toSocketPayload(),
    );

    final hostTerminal = await _waitFor(
      hostEvents.stream,
      (event) => event['type'] == 'state' && event['result'] == result,
    );
    final clientTerminal = await _waitFor(
      clientEvents.stream,
      (event) => event['type'] == 'state' && event['result'] == result,
    );

    expect(hostTerminal['status'], anyOf('active', 'game_over'));
    expect(clientTerminal['status'], anyOf('active', 'game_over'));
  });
}

Future<Map<String, dynamic>> _waitFor(
  Stream<Map<String, dynamic>> stream,
  bool Function(Map<String, dynamic>) predicate, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final completer = Completer<Map<String, dynamic>>();
  late final StreamSubscription<Map<String, dynamic>> subscription;
  subscription = stream.listen((event) {
    final type = event['type']?.toString() ?? '';
    if (type == 'error' && !completer.isCompleted) {
      final code = event['code']?.toString() ?? 'unknown';
      final message = event['message']?.toString() ?? 'server error';
      completer.completeError(StateError('Server error ($code): $message'));
      subscription.cancel();
      return;
    }
    if (predicate(event) && !completer.isCompleted) {
      completer.complete(event);
      subscription.cancel();
    }
  });

  return completer.future.timeout(
    timeout,
    onTimeout: () {
      subscription.cancel();
      throw TimeoutException('Timed out waiting for expected server event.');
    },
  );
}
