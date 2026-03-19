import 'package:bulletholebackgammon/src/game/engine/backgammon_online_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'classifyServerErrorCode maps recoverable relay errors to action_rejected',
    () {
      expect(
        BackgammonOnlineProtocol.classifyServerErrorCode('relay_not_ready'),
        'action_rejected',
      );
      expect(
        BackgammonOnlineProtocol.classifyServerErrorCode(
          'waiting_for_opponent',
        ),
        'action_rejected',
      );
      expect(
        BackgammonOnlineProtocol.classifyServerErrorCode(
          'unexpected_backend_fault',
        ),
        'invariant_failure',
      );
    },
  );

  test('deterministic action payload and hash are stable', () {
    final payloadA = BackgammonOnlineProtocol.buildDeterministicActionPayload(
      seed: 101,
      step: 0,
      actorColor: 'w',
    );
    final payloadB = BackgammonOnlineProtocol.buildDeterministicActionPayload(
      seed: 101,
      step: 0,
      actorColor: 'w',
    );

    expect(payloadA, payloadB);

    final hashA = BackgammonOnlineProtocol.buildActionStateHash(
      seed: 101,
      step: 0,
      actorColor: 'w',
      payload: payloadA,
    );
    final hashB = BackgammonOnlineProtocol.buildActionStateHash(
      seed: 101,
      step: 0,
      actorColor: 'w',
      payload: payloadB,
    );

    expect(hashA, hashB);
  });

  test('termination contract uses non-empty result', () {
    expect(BackgammonOnlineProtocol.isTerminalResult(null), isFalse);
    expect(BackgammonOnlineProtocol.isTerminalResult('   '), isFalse);
    expect(BackgammonOnlineProtocol.isTerminalResult('draw'), isTrue);

    final result = BackgammonOnlineProtocol.buildSessionResult(
      seed: 42,
      actionCount: 2,
    );
    expect(result, contains('seed_42'));
    expect(BackgammonOnlineProtocol.isTerminalResult(result), isTrue);
  });
}
