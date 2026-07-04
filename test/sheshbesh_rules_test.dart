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

  test('hitting a blot sends it to the bar and conserves both totals', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    // White on point 10, black lone blot on point 6. White die 4: 10 -> 6 hits.
    points[10] = const SheshBeshPoint(color: 'w', count: 2);
    points[6] = const SheshBeshPoint(color: 'b', count: 1);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );

    final hit = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'w',
      dice: const <int>[4],
    ).legalMoves.firstWhere(
      (move) => move.fromPoint == 10 && move.toPoint == 6,
      orElse: () => throw StateError('expected a 10->6 move'),
    );
    expect(hit.hitsOpponent, isTrue);

    final after = SheshBeshRules.applyMove(
      position: position,
      color: 'w',
      move: hit,
    );

    // Black blot is now on the bar; destination is owned by white, count 1.
    expect(after.blackBar, 1);
    expect(after.points[6].color, 'w');
    expect(after.points[6].count, 1);
    expect(after.points[10].count, 1);
    // Conservation holds for both sides (applyMove would throw otherwise, but
    // assert explicitly for documentation).
    expect(SheshBeshRules.checkerTotal(after, 'w'), 2);
    expect(SheshBeshRules.checkerTotal(after, 'b'), 1);
  });

  test('a checker on the bar cannot enter onto a blocked point (>=2 enemy)', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    // Black on bar; die 3 entry is index 2 (blocked by 2 white), die 4 entry is
    // index 3 (open). Only the die-4 entry must be legal.
    points[2] = const SheshBeshPoint(color: 'w', count: 2);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 1,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'b',
      dice: const <int>[3, 4],
    );

    expect(
      decision.legalMoves.every(
        (move) => move.source == SheshBeshMoveSource.bar,
      ),
      isTrue,
    );
    expect(
      decision.legalMoves.any((move) => move.toPoint == 2),
      isFalse,
      reason: 'die-3 entry onto blocked point 2 must be illegal',
    );
    expect(
      decision.legalMoves.any((move) => move.toPoint == 3),
      isTrue,
      reason: 'die-4 entry onto open point 3 must be legal',
    );
  });

  test('bar entry that hits a blot is offered and conserves on apply', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    // Black on bar; white lone blot sits on entry index 3 (die 4). Entry hits.
    points[3] = const SheshBeshPoint(color: 'w', count: 1);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 1,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );

    final entry = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'b',
      dice: const <int>[4],
    ).legalMoves.single;
    expect(entry.source, SheshBeshMoveSource.bar);
    expect(entry.toPoint, 3);
    expect(entry.hitsOpponent, isTrue);

    final after = SheshBeshRules.applyMove(
      position: position,
      color: 'b',
      move: entry,
    );
    expect(after.blackBar, 0);
    expect(after.whiteBar, 1);
    expect(after.points[3].color, 'b');
    expect(after.points[3].count, 1);
  });

  test('must use both dice: single-checker path that plays both is forced', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    // Only one white checker exists, deep enough that either die order plays
    // both. maxMovesUsable must be 2 and every reported first move must be able
    // to lead to a two-move sequence.
    points[20] = const SheshBeshPoint(color: 'w', count: 1);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 14,
      blackBorneOff: 0,
    );

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'w',
      dice: const <int>[3, 2],
    );
    expect(decision.maxMovesUsable, 2);
    expect(decision.maxUsedPips, 5);
  });

  test(
    'when only one of two dice is playable, exactly one die is usable',
    () {
      final points = List<SheshBeshPoint>.generate(
        24,
        (_) => const SheshBeshPoint(),
        growable: false,
      );
      // Single white checker on point 8 (outside home, so no bear-off can
      // sneak in a second die). White moves toward index 0, dice [2, 5]:
      //   die 2 first -> point 6 : blocked by 2 black.
      //   die 5 first -> point 3 : open, then die 2 -> point 1 : blocked.
      // Only the 5 is ever playable, so exactly one die is usable this turn.
      points[8] = const SheshBeshPoint(color: 'w', count: 1);
      points[6] = const SheshBeshPoint(color: 'b', count: 2); // blocks 8->6
      points[1] = const SheshBeshPoint(color: 'b', count: 2); // blocks 3->1

      final position = SheshBeshPosition(
        points: points,
        whiteBar: 0,
        blackBar: 0,
        whiteBorneOff: 0,
        blackBorneOff: 0,
      );

      final decision = SheshBeshRules.computeTurnDecision(
        position: position,
        color: 'w',
        dice: const <int>[2, 5],
      );
      expect(decision.maxMovesUsable, 1);
      expect(decision.legalMoves.length, 1);
      expect(decision.legalMoves.single.die, 5);
      expect(decision.legalMoves.single.fromPoint, 8);
      expect(decision.legalMoves.single.toPoint, 3);
    },
  );

  test('black overshoot bear-off only with no higher home checker', () {
    // Symmetric to the white overshoot test. Black home is points 18..23,
    // bearing off past index 23. A higher checker (nearer index 18) blocks
    // an overshoot from a lower point.
    final pointsBlocked = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    // Black on 21 and 19. die 6 from 21 -> target 27 (overshoot); a higher
    // checker on 19 (further from bearing off) blocks it.
    pointsBlocked[21] = const SheshBeshPoint(color: 'b', count: 1);
    pointsBlocked[19] = const SheshBeshPoint(color: 'b', count: 1);

    final blockedPosition = SheshBeshPosition(
      points: pointsBlocked,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 13,
    );

    final blockedDecision = SheshBeshRules.computeTurnDecision(
      position: blockedPosition,
      color: 'b',
      dice: const <int>[6],
    );
    expect(
      blockedDecision.legalMoves.any(
        (move) => move.bearsOff && move.fromPoint == 21,
      ),
      isFalse,
      reason: 'overshoot from 21 blocked while a higher black checker sits on 19',
    );

    final pointsAllowed = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    pointsAllowed[21] = const SheshBeshPoint(color: 'b', count: 1);

    final allowedPosition = SheshBeshPosition(
      points: pointsAllowed,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 14,
    );

    final allowedDecision = SheshBeshRules.computeTurnDecision(
      position: allowedPosition,
      color: 'b',
      dice: const <int>[6],
    );
    expect(allowedDecision.legalMoves.any((move) => move.bearsOff), isTrue);
  });

  test('cannot bear off while a checker is still outside home', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    // White has a checker on point 3 (home) and one on point 8 (outside home).
    points[3] = const SheshBeshPoint(color: 'w', count: 1);
    points[8] = const SheshBeshPoint(color: 'w', count: 1);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 13,
      blackBorneOff: 0,
    );

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'w',
      dice: const <int>[4],
    );
    expect(
      decision.legalMoves.any((move) => move.bearsOff),
      isFalse,
      reason: 'no bear-off is legal until all checkers are in the home board',
    );
  });

  test('cannot bear off with a checker on the bar', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );
    points[3] = const SheshBeshPoint(color: 'w', count: 1);

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 1,
      blackBar: 0,
      whiteBorneOff: 13,
      blackBorneOff: 0,
    );

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: 'w',
      dice: const <int>[4],
    );
    // The only legal action is entering from the bar; no bear-off is offered.
    expect(
      decision.legalMoves.every(
        (move) => move.source == SheshBeshMoveSource.bar,
      ),
      isTrue,
    );
    expect(decision.legalMoves.any((move) => move.bearsOff), isFalse);
  });

  test('applyMove throws if asked to enter from an empty bar', () {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );

    final position = SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );

    // Hand-crafted illegal bar move (the generator never emits this). The guard
    // added in f665d28 must reject it rather than fabricate a 16th checker.
    const illegal = SheshBeshMove(
      source: SheshBeshMoveSource.bar,
      die: 4,
      toPoint: 3,
    );

    expect(
      () => SheshBeshRules.applyMove(
        position: position,
        color: 'w',
        move: illegal,
      ),
      throwsStateError,
    );
  });
}
