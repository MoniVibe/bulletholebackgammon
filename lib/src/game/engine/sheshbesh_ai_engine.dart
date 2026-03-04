import 'dart:math';

import 'sheshbesh_model.dart';
import 'sheshbesh_rules.dart';

/// Lightweight heuristic AI for local play.
class SheshBeshAiEngine {
  SheshBeshAiEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  SheshBeshMove? chooseMove({
    required SheshBeshPosition position,
    required String color,
    required List<int> dice,
  }) {
    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: color,
      dice: dice,
    );
    if (!decision.hasMoves) {
      return null;
    }

    var bestScore = -1 << 30;
    final bestMoves = <SheshBeshMove>[];
    for (final move in decision.legalMoves) {
      final score = _scoreMove(position: position, color: color, move: move);
      if (score > bestScore) {
        bestScore = score;
        bestMoves
          ..clear()
          ..add(move);
        continue;
      }
      if (score == bestScore) {
        bestMoves.add(move);
      }
    }

    return bestMoves[_random.nextInt(bestMoves.length)];
  }

  int _scoreMove({
    required SheshBeshPosition position,
    required String color,
    required SheshBeshMove move,
  }) {
    var score = 0;
    if (move.hitsOpponent) {
      score += 70;
    }
    if (move.bearsOff) {
      score += 85;
    }

    final beforePips = SheshBeshRules.pipCount(position, color);
    final next = SheshBeshRules.applyMove(
      position: position,
      color: color,
      move: move,
    );
    final afterPips = SheshBeshRules.pipCount(next, color);
    score += (beforePips - afterPips) * 2;

    // Prefer landing on safer points over leaving blots in the home board race.
    if (!move.bearsOff && move.toPoint != null) {
      final stack = next.points[move.toPoint!];
      if (stack.color == color && stack.count >= 2) {
        score += 8;
      }
      if (stack.color == color && stack.count == 1) {
        score -= 6;
      }
    }

    score += _random.nextInt(5);
    return score;
  }
}
