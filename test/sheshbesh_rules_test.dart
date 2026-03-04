import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bar checkers must enter before any board checker moves', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    points[23] = const SheshBeshPoint(color: 'w', count: 1);
    points[12] = const SheshBeshPoint(color: 'w', count: 1);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 1,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'w',
      dice: const <int>[3, 5],
    );

    expect(decision.hasMoves, isTrue);
    expect(
      decision.legalMoves.every(
        (move) => move.source == SheshBeshMoveSource.bar,
      ),
      isTrue,
    );
  });

  test('uses higher die when only one die can be played', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );

    // White has one checker on bar. Die=2 entry (point 22 index) is blocked,
    // while die=5 entry is open.
    points[22] = const SheshBeshPoint(color: 'b', count: 2);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 1,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'w',
      dice: const <int>[2, 5],
    );

    expect(decision.legalMoves.length, 1);
    expect(decision.legalMoves.single.die, 5);
  });

  test('white overshoot bear-off only allowed with no higher home checker', () {
    final pointsBlocked = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    pointsBlocked[2] = const SheshBeshPoint(color: 'w', count: 1);
    pointsBlocked[4] = const SheshBeshPoint(color: 'w', count: 1);

    final blockedPosition = SheshBeshPosition(
      points: pointsBlocked,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 13,
      blackBorneOff: 0,
    );

    final blockedDecision = SheshBeshRules.computeTurnDecision(
      position: blockedPosition,
      color: 'w',
      dice: const <int>[6],
    );
    expect(
      blockedDecision.legalMoves.any(
        (move) => move.bearsOff && move.fromPoint == 2,
      ),
      isFalse,
    );

    final pointsAllowed = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    pointsAllowed[2] = const SheshBeshPoint(color: 'w', count: 1);

    final allowedPosition = SheshBeshPosition(
      points: pointsAllowed,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 14,
      blackBorneOff: 0,
    );

    final allowedDecision = SheshBeshRules.computeTurnDecision(
      position: allowedPosition,
      color: 'w',
      dice: const <int>[6],
    );
    expect(allowedDecision.legalMoves.any((move) => move.bearsOff), isTrue);
  });
}
