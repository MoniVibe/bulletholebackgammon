import 'dart:math';

import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backgammon core invariants hold across seeded random playouts', () {
    for (var seed = 1; seed <= 25; seed += 1) {
      _simulate(seed: seed, maxTurns: 180);
    }
  });

  test(
    'same seed replays to identical terminal fingerprint and state sequence',
    () {
      const seed = 1729;
      final first = _simulate(seed: seed, maxTurns: 220);
      final second = _simulate(seed: seed, maxTurns: 220);
      expect(first.finalFingerprint, second.finalFingerprint);
      expect(first.stateSequence, second.stateSequence);
    },
  );
}

_SimulationResult _simulate({required int seed, required int maxTurns}) {
  final random = Random(seed);
  var position = SheshBeshRules.initialPosition();
  var color = SheshBeshRules.determineOpeningStarter(random).startingColor;
  final stateSequence = <String>[
    _positionFingerprint(position: position, sideToMove: color),
  ];

  for (var turn = 0; turn < maxTurns; turn += 1) {
    _expectCheckerConservation(position);
    _expectNoNegativeCounts(position);
    _expectWinnerConsistency(position);
    if (SheshBeshRules.winnerColor(position) != null) {
      break;
    }

    final dice = SheshBeshRules.rollTurnDice(random);
    final remainingDice = List<int>.from(dice);
    final turnDecision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: color,
      dice: remainingDice,
    );
    expect(
      turnDecision.maxMovesUsable,
      lessThanOrEqualTo(remainingDice.length),
    );
    expect(turnDecision.maxUsedPips, greaterThanOrEqualTo(0));
    var usedMoveCount = 0;
    var usedPips = 0;

    while (remainingDice.isNotEmpty) {
      final decision = SheshBeshRules.computeTurnDecision(
        position: position,
        color: color,
        dice: remainingDice,
      );
      expect(decision.maxMovesUsable, lessThanOrEqualTo(remainingDice.length));
      expect(decision.maxUsedPips, greaterThanOrEqualTo(0));
      if (!decision.hasMoves) {
        break;
      }

      final move =
          decision.legalMoves[random.nextInt(decision.legalMoves.length)];
      final dieIndex = remainingDice.indexOf(move.die);
      expect(
        dieIndex,
        isNot(-1),
        reason: 'seed=$seed turn=$turn selected move consumed missing die',
      );
      remainingDice.removeAt(dieIndex);

      position = SheshBeshRules.applyMove(
        position: position,
        color: color,
        move: move,
      );
      usedMoveCount += 1;
      usedPips += move.die;
      _expectCheckerConservation(position);
      _expectNoNegativeCounts(position);
      _expectWinnerConsistency(position);
      stateSequence.add(
        _positionFingerprint(position: position, sideToMove: color),
      );
      if (SheshBeshRules.winnerColor(position) != null) {
        break;
      }
    }

    if (SheshBeshRules.winnerColor(position) == null) {
      expect(
        usedMoveCount,
        turnDecision.maxMovesUsable,
        reason:
            'seed=$seed turn=$turn did not use max legal moves for the rolled dice',
      );
      expect(
        usedPips,
        turnDecision.maxUsedPips,
        reason:
            'seed=$seed turn=$turn did not use max legal pip total for the rolled dice',
      );
      final previousColor = color;
      color = SheshBeshRules.oppositeColor(color);
      expect(color, isNot(previousColor));
      stateSequence.add(
        _positionFingerprint(position: position, sideToMove: color),
      );
    }
  }

  return _SimulationResult(
    finalFingerprint: _positionFingerprint(
      position: position,
      sideToMove: color,
    ),
    stateSequence: stateSequence,
  );
}

void _expectCheckerConservation(SheshBeshPosition position) {
  final whiteOnBoard = _checkersOnBoard(position, 'w');
  final blackOnBoard = _checkersOnBoard(position, 'b');
  final whiteTotal = whiteOnBoard + position.whiteBar + position.whiteBorneOff;
  final blackTotal = blackOnBoard + position.blackBar + position.blackBorneOff;

  expect(whiteTotal, SheshBeshRules.totalCheckersPerSide);
  expect(blackTotal, SheshBeshRules.totalCheckersPerSide);
}

void _expectNoNegativeCounts(SheshBeshPosition position) {
  expect(position.whiteBar, greaterThanOrEqualTo(0));
  expect(position.blackBar, greaterThanOrEqualTo(0));
  expect(position.whiteBorneOff, greaterThanOrEqualTo(0));
  expect(position.blackBorneOff, greaterThanOrEqualTo(0));
  for (final point in position.points) {
    expect(point.count, greaterThanOrEqualTo(0));
    if (point.count == 0) {
      expect(point.color, isNull);
    } else {
      expect(point.color == 'w' || point.color == 'b', isTrue);
    }
  }
}

void _expectWinnerConsistency(SheshBeshPosition position) {
  final winner = SheshBeshRules.winnerColor(position);
  if (winner == null) {
    expect(
      position.whiteBorneOff < SheshBeshRules.totalCheckersPerSide,
      isTrue,
    );
    expect(
      position.blackBorneOff < SheshBeshRules.totalCheckersPerSide,
      isTrue,
    );
    return;
  }
  if (winner == 'w') {
    expect(position.whiteBorneOff, SheshBeshRules.totalCheckersPerSide);
    expect(
      position.blackBorneOff < SheshBeshRules.totalCheckersPerSide,
      isTrue,
    );
    return;
  }
  expect(position.blackBorneOff, SheshBeshRules.totalCheckersPerSide);
  expect(position.whiteBorneOff < SheshBeshRules.totalCheckersPerSide, isTrue);
}

int _checkersOnBoard(SheshBeshPosition position, String color) {
  var total = 0;
  for (final point in position.points) {
    if (point.color == color) {
      total += point.count;
    }
  }
  return total;
}

String _positionFingerprint({
  required SheshBeshPosition position,
  required String sideToMove,
}) {
  final pointData = <String>[];
  for (var i = 0; i < position.points.length; i += 1) {
    final point = position.points[i];
    final color = point.color ?? '-';
    pointData.add('$i:$color:${point.count}');
  }

  return [
    'stm=$sideToMove',
    'wb=${position.whiteBar}',
    'bb=${position.blackBar}',
    'wo=${position.whiteBorneOff}',
    'bo=${position.blackBorneOff}',
    pointData.join('|'),
  ].join('||');
}

class _SimulationResult {
  const _SimulationResult({
    required this.finalFingerprint,
    required this.stateSequence,
  });

  final String finalFingerprint;
  final List<String> stateSequence;
}
