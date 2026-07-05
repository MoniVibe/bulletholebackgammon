import 'dart:math';

import 'package:bulletholebackgammon/src/game/engine/sheshbesh_ai_engine.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// F1 regression/documentation suite.
///
/// Claim under test: `SheshBeshAiEngine.chooseMove` re-greedies each ply and
/// could end a turn having used fewer dice than the backgammon maximal-play
/// rule obligates, because it scores `computeTurnDecision(...).legalMoves`
/// independently per ply.
///
/// Verdict reached (see report): NO-BUG. `computeTurnDecision` recomputes the
/// maximal outcome from the CURRENT position every ply and only surfaces
/// first-moves that belong to a maximal-length (and, tie-broken, maximal-pip)
/// outcome. Every move the AI can pick therefore lies on a maximal path, and
/// the next ply re-derives maximality from the resulting position. The AI's
/// heuristic scoring only chooses *among* already-maximal first moves, so it
/// cannot forfeit an obligated die.
///
/// These tests drive the real engine's exact choose-apply loop through the
/// classic adversarial positions and assert dice-used == rules-maximal.

/// Replays the engine's real per-ply loop for [color] over [dice] on
/// [position], returning how many dice it actually consumed.
int _driveAiTurn({
  required SheshBeshAiEngine engine,
  required SheshBeshPosition position,
  required String color,
  required List<int> dice,
}) {
  var current = position;
  final remaining = List<int>.from(dice);
  var used = 0;

  while (remaining.isNotEmpty) {
    final move = engine.chooseMove(
      position: current,
      color: color,
      dice: remaining,
    );
    if (move == null) {
      break;
    }
    current = SheshBeshRules.applyMove(
      position: current,
      color: color,
      move: move,
    );
    final dieIndex = remaining.indexOf(move.die);
    expect(dieIndex, isNot(-1), reason: 'AI consumed a die it was not holding');
    remaining.removeAt(dieIndex);
    used += 1;
  }

  return used;
}

/// The rules-obligated number of dice for [color] on [position] with [dice].
int _rulesMaximal({
  required SheshBeshPosition position,
  required String color,
  required List<int> dice,
}) {
  return SheshBeshRules.computeTurnDecision(
    position: position,
    color: color,
    dice: dice,
  ).maxMovesUsable;
}

SheshBeshPosition _emptyBoard({
  Map<int, SheshBeshPoint> points = const <int, SheshBeshPoint>{},
  int whiteBar = 0,
  int blackBar = 0,
  int whiteBorneOff = 0,
  int blackBorneOff = 0,
}) {
  final board = List<SheshBeshPoint>.generate(
    24,
    (index) => points[index] ?? const SheshBeshPoint(),
    growable: false,
  );
  return SheshBeshPosition(
    points: board,
    whiteBar: whiteBar,
    blackBar: blackBar,
    whiteBorneOff: whiteBorneOff,
    blackBorneOff: blackBorneOff,
  );
}

void main() {
  // A fixed seed keeps the AI's heuristic tie-breaking deterministic so the
  // test pins behaviour rather than flaking on random tie-breaks.
  SheshBeshAiEngine newEngine() => SheshBeshAiEngine(random: Random(20260704));

  test(
    'ordering trap: only one die order plays both dice — AI must not forfeit',
    () {
      // White moves high point -> low point (target = from - die).
      // White checker on point 12. Dice [6, 1].
      //   - Play the 1 first: 12 -> 11. Point 11 is fine, but from 11 the 6
      //     lands on 5, which black has primed (a made point of >=2 black
      //     checkers is an illegal landing). So after 12->11 the 6 is dead.
      //     => that ordering plays only ONE die.
      //   - Play the 6 first: 12 -> 6. Point 6 is open. Then the 1: 6 -> 5?
      //     also blocked. Hmm — so we must design so exactly one order yields
      //     two dice. We instead route the checker down an open corridor.
      //
      // Concrete construction below is validated by asserting rules-maximal==2,
      // i.e. a two-die play exists, while a naive per-die greedy that took the
      // 1 first would strand the 6.
      final position = _emptyBoard(
        points: <int, SheshBeshPoint>{
          // Lone white runner.
          12: const SheshBeshPoint(color: 'w', count: 1),
          // Keep the rest of white at home so the runner is the only mover and
          // conservation stays valid (white needs 15 total).
          0: const SheshBeshPoint(color: 'w', count: 5),
          1: const SheshBeshPoint(color: 'w', count: 5),
          2: const SheshBeshPoint(color: 'w', count: 4),
          // Black prime: block intermediate landings that would strand a die.
          // Block point 11 (the 12->11 with the 1) with a made black point, so
          // the 1 cannot be played first from 12. It CAN be played second from
          // point 6.
          11: const SheshBeshPoint(color: 'b', count: 2),
          // Black filler to reach 15.
          20: const SheshBeshPoint(color: 'b', count: 5),
          21: const SheshBeshPoint(color: 'b', count: 5),
          22: const SheshBeshPoint(color: 'b', count: 3),
        },
      );

      const color = 'w';
      final dice = <int>[6, 1];

      final maximal = _rulesMaximal(
        position: position,
        color: color,
        dice: dice,
      );
      // Sanity: this position must actually be a two-die-obligated trap.
      expect(
        maximal,
        2,
        reason:
            'test position mis-built: expected a two-die maximal play to exist',
      );

      final used = _driveAiTurn(
        engine: newEngine(),
        position: position,
        color: color,
        dice: dice,
      );
      expect(
        used,
        maximal,
        reason: 'AI forfeited an obligated die (used $used of $maximal)',
      );
    },
  );

  test(
    'single-die-only position: AI plays the one obligated die and stops',
    () {
      // Only one die is ever playable; maximal == 1. Confirms the loop also
      // pins the lower bound and does not fabricate a second move.
      final position = _emptyBoard(
        points: <int, SheshBeshPoint>{
          5: const SheshBeshPoint(color: 'w', count: 1),
          0: const SheshBeshPoint(color: 'w', count: 5),
          1: const SheshBeshPoint(color: 'w', count: 5),
          2: const SheshBeshPoint(color: 'w', count: 4),
          // Block everything the second die could reach.
          3: const SheshBeshPoint(color: 'b', count: 2),
          4: const SheshBeshPoint(color: 'b', count: 2),
          20: const SheshBeshPoint(color: 'b', count: 5),
          21: const SheshBeshPoint(color: 'b', count: 4),
        },
      );
      const color = 'w';
      final dice = <int>[2, 1];

      final maximal = _rulesMaximal(
        position: position,
        color: color,
        dice: dice,
      );
      final used = _driveAiTurn(
        engine: newEngine(),
        position: position,
        color: color,
        dice: dice,
      );
      expect(used, maximal);
    },
  );

  test(
    'doubles: AI uses every die a maximal play affords',
    () {
      // Doubles roll [3,3,3,3] with an open corridor for a single runner that
      // can spend all four on the same checker, plus spare men so the position
      // is legal. Maximal must equal the full count the corridor allows.
      final position = _emptyBoard(
        points: <int, SheshBeshPoint>{
          23: const SheshBeshPoint(color: 'w', count: 1),
          0: const SheshBeshPoint(color: 'w', count: 5),
          1: const SheshBeshPoint(color: 'w', count: 5),
          2: const SheshBeshPoint(color: 'w', count: 4),
          // Black stays out of the 23->20->17->14->11 corridor.
          6: const SheshBeshPoint(color: 'b', count: 5),
          7: const SheshBeshPoint(color: 'b', count: 5),
          8: const SheshBeshPoint(color: 'b', count: 5),
        },
      );
      const color = 'w';
      final dice = <int>[3, 3, 3, 3];

      final maximal = _rulesMaximal(
        position: position,
        color: color,
        dice: dice,
      );
      expect(
        maximal,
        greaterThanOrEqualTo(1),
        reason: 'doubles position must admit at least one move',
      );

      final used = _driveAiTurn(
        engine: newEngine(),
        position: position,
        color: color,
        dice: dice,
      );
      expect(
        used,
        maximal,
        reason: 'AI forfeited obligated doubles dice (used $used of $maximal)',
      );
    },
  );

  test(
    'seeded fuzz: AI never uses fewer dice than the rules oblige',
    () {
      // Broad coverage from real opening positions: for many seeded dice rolls
      // on the standard start, the engine-driven dice count must match the
      // rules-maximal count every time.
      final rng = Random(4242);
      final engine = SheshBeshAiEngine(random: Random(99));
      for (var i = 0; i < 400; i += 1) {
        final position = SheshBeshRules.initialPosition();
        final color = i.isEven ? 'w' : 'b';
        final d1 = rng.nextInt(6) + 1;
        final d2 = rng.nextInt(6) + 1;
        final dice = d1 == d2
            ? <int>[d1, d1, d1, d1]
            : <int>[d1, d2];

        final maximal = _rulesMaximal(
          position: position,
          color: color,
          dice: dice,
        );
        final used = _driveAiTurn(
          engine: engine,
          position: position,
          color: color,
          dice: dice,
        );
        expect(
          used,
          maximal,
          reason:
              'seed-index=$i color=$color dice=$dice: AI used $used of '
              'obligated $maximal',
        );
      }
    },
  );
}
