import 'dart:math';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';

/// Backgammon-specific relay protocol helpers for online bughunt autoplay.
class BackgammonOnlineProtocol {
  BackgammonOnlineProtocol._();

  static const Set<String> recoverableErrorCodes = <String>{
    'stale_state',
    'cooldown_active',
    'not_your_turn',
    'invalid_move',
    'illegal_move',
    'queue_rejected',
    'queue_conflict',
    'waiting_for_opponent',
    'relay_not_ready',
    'relay_invalid_payload',
    'relay_invalid_action',
    'relay_missing_result',
  };

  static String classifyServerErrorCode(String? codeRaw) {
    final code = codeRaw?.trim().toLowerCase() ?? '';
    if (recoverableErrorCodes.contains(code)) {
      return 'action_rejected';
    }
    return 'invariant_failure';
  }

  static bool isTerminalResult(String? raw) {
    if (raw == null) {
      return false;
    }
    return raw.trim().isNotEmpty;
  }

  static Map<String, Object?> buildDeterministicActionPayload({
    required int seed,
    required int step,
    required String actorColor,
  }) {
    final normalizedActor = actorColor.trim().toLowerCase();
    if (normalizedActor != 'w' && normalizedActor != 'b') {
      throw ArgumentError.value(actorColor, 'actorColor', 'Must be w or b');
    }

    final random = Random(
      seed ^ (step * 7919) ^ (normalizedActor == 'w' ? 73 : 211),
    );
    var fromPoint = 1 + random.nextInt(24);
    var toPoint = 1 + random.nextInt(24);
    if (toPoint == fromPoint) {
      toPoint = ((toPoint + 6 - 1) % 24) + 1;
    }

    return <String, Object?>{
      'kind': 'checker_move',
      'actionId': (step + 1) * 100 + (normalizedActor == 'w' ? 1 : 2),
      'actorColor': normalizedActor,
      'fromPoint': fromPoint,
      'toPoint': toPoint,
      'die': 1 + random.nextInt(6),
    };
  }

  static String buildActionStateHash({
    required int seed,
    required int step,
    required String actorColor,
    required Map<String, Object?> payload,
  }) {
    const hasher = BughuntStateHasher();
    return hasher.hashSnapshot(<String, Object?>{
      'seed': seed,
      'step': step,
      'actorColor': actorColor,
      'payload': payload,
    }).value;
  }

  static String buildSessionResult({
    required int seed,
    required int actionCount,
  }) {
    return 'relay_complete_seed_${seed}_actions_$actionCount';
  }
}
