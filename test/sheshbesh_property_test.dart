import 'dart:math';

import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checker conservation invariants hold across seeded random playouts', () {
    for (var seed = 1; seed <= 25; seed += 1) {
      _simulate(seed: seed, maxTurns: 180);
    }
  });

  test('same seed replays to same terminal fingerprint', () {
    const seed = 1729;
    final first = _simulate(seed: seed, maxTurns: 220);
    final second = _simulate(seed: seed, maxTurns: 220);
    expect(first, second);
  });
}

String _simulate({required int seed, required int maxTurns}) {
  final random = Random(seed);
  var position = SheshBeshRules.initialPosition();
  var color = 'w';

  for (var turn = 0; turn < maxTurns; turn += 1) {
    _expectCheckerConservation(position);
    if (SheshBeshRules.winnerColor(position) != null) {
      break;
    }

    final dice = SheshBeshRules.rollTurnDice(random);
    final remainingDice = List<int>.from(dice);

    while (remainingDice.isNotEmpty) {
      final decision = SheshBeshRules.computeTurnDecision(
        position: position,
        color: color,
        dice: remainingDice,
      );
      if (!decision.hasMoves) {
        break;
      }

      final move = decision.legalMoves[random.nextInt(decision.legalMoves.length)];
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
      _expectCheckerConservation(position);
      if (SheshBeshRules.winnerColor(position) != null) {
        break;
      }
    }

    color = SheshBeshRules.oppositeColor(color);
  }

  return _positionFingerprint(position: position, sideToMove: color);
}

void _expectCheckerConservation(SheshBeshPosition position) {
  final whiteOnBoard = _checkersOnBoard(position, 'w');
  final blackOnBoard = _checkersOnBoard(position, 'b');
  final whiteTotal = whiteOnBoard + position.whiteBar + position.whiteBorneOff;
  final blackTotal = blackOnBoard + position.blackBar + position.blackBorneOff;

  expect(whiteTotal, SheshBeshRules.totalCheckersPerSide);
  expect(blackTotal, SheshBeshRules.totalCheckersPerSide);
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
