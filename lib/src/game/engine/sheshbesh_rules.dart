import 'dart:math';

import 'sheshbesh_model.dart';

/// Pure rules/helpers for sheshbesh (backgammon) state transitions.
class SheshBeshRules {
  static const int totalCheckersPerSide = 15;

  static SheshBeshPosition initialPosition() {
    final points = List<SheshBeshPoint>.generate(
      24,
      (_) => const SheshBeshPoint(),
      growable: false,
    );

    void place(int index, String color, int count) {
      points[index] = SheshBeshPoint(color: color, count: count);
    }

    // Standard backgammon setup.
    place(23, 'w', 2);
    place(12, 'w', 5);
    place(7, 'w', 3);
    place(5, 'w', 5);

    place(0, 'b', 2);
    place(11, 'b', 5);
    place(16, 'b', 3);
    place(18, 'b', 5);

    return SheshBeshPosition(
      points: points,
      whiteBar: 0,
      blackBar: 0,
      whiteBorneOff: 0,
      blackBorneOff: 0,
    );
  }

  static String oppositeColor(String color) => color == 'w' ? 'b' : 'w';

  static List<int> rollTurnDice(Random random) {
    final first = random.nextInt(6) + 1;
    final second = random.nextInt(6) + 1;
    if (first == second) {
      return List<int>.filled(4, first, growable: false);
    }
    return <int>[first, second];
  }

  static ({String startingColor, int whiteRoll, int blackRoll})
  determineOpeningStarter(Random random) {
    while (true) {
      final white = random.nextInt(6) + 1;
      final black = random.nextInt(6) + 1;
      if (white == black) {
        continue;
      }
      return (
        startingColor: white > black ? 'w' : 'b',
        whiteRoll: white,
        blackRoll: black,
      );
    }
  }

  static String? winnerColor(SheshBeshPosition position) {
    if (position.whiteBorneOff >= totalCheckersPerSide) {
      return 'w';
    }
    if (position.blackBorneOff >= totalCheckersPerSide) {
      return 'b';
    }
    return null;
  }

  static TurnDecision computeTurnDecision({
    required SheshBeshPosition position,
    required String color,
    required List<int> dice,
  }) {
    if (dice.isEmpty) {
      return const TurnDecision(
        legalMoves: <SheshBeshMove>[],
        maxMovesUsable: 0,
        maxUsedPips: 0,
      );
    }

    final outcomes = <_TurnOutcome>[];
    _collectOutcomes(
      position: position,
      color: color,
      dice: dice,
      usedPips: 0,
      movesSoFar: const <SheshBeshMove>[],
      outcomes: outcomes,
    );

    if (outcomes.isEmpty) {
      return const TurnDecision(
        legalMoves: <SheshBeshMove>[],
        maxMovesUsable: 0,
        maxUsedPips: 0,
      );
    }

    var bestMoveCount = 0;
    var bestPipUsage = 0;
    for (final outcome in outcomes) {
      if (outcome.moves.length > bestMoveCount) {
        bestMoveCount = outcome.moves.length;
        bestPipUsage = outcome.usedPips;
        continue;
      }
      if (outcome.moves.length == bestMoveCount &&
          outcome.usedPips > bestPipUsage) {
        bestPipUsage = outcome.usedPips;
      }
    }

    final selectedFirstMoves = <String, SheshBeshMove>{};
    for (final outcome in outcomes) {
      if (outcome.moves.length != bestMoveCount ||
          outcome.usedPips != bestPipUsage ||
          outcome.moves.isEmpty) {
        continue;
      }
      final first = outcome.moves.first;
      selectedFirstMoves.putIfAbsent(_moveIdentity(first), () => first);
    }

    final legalMoves = selectedFirstMoves.values.toList(growable: false)
      ..sort(_compareMoves);

    return TurnDecision(
      legalMoves: legalMoves,
      maxMovesUsable: bestMoveCount,
      maxUsedPips: bestPipUsage,
    );
  }

  static SheshBeshPosition applyMove({
    required SheshBeshPosition position,
    required String color,
    required SheshBeshMove move,
  }) {
    final points = List<SheshBeshPoint>.from(position.points);
    var whiteBar = position.whiteBar;
    var blackBar = position.blackBar;
    var whiteBorneOff = position.whiteBorneOff;
    var blackBorneOff = position.blackBorneOff;

    if (move.source == SheshBeshMoveSource.bar) {
      if (color == 'w') {
        whiteBar = max(0, whiteBar - 1);
      } else {
        blackBar = max(0, blackBar - 1);
      }
    } else {
      final from = move.fromPoint!;
      final sourceStack = points[from];
      final nextCount = sourceStack.count - 1;
      points[from] = nextCount <= 0
          ? const SheshBeshPoint()
          : SheshBeshPoint(color: sourceStack.color, count: nextCount);
    }

    if (move.bearsOff) {
      if (color == 'w') {
        whiteBorneOff += 1;
      } else {
        blackBorneOff += 1;
      }
      return SheshBeshPosition(
        points: points,
        whiteBar: whiteBar,
        blackBar: blackBar,
        whiteBorneOff: whiteBorneOff,
        blackBorneOff: blackBorneOff,
      );
    }

    final to = move.toPoint!;
    final destination = points[to];
    if (!destination.isEmpty &&
        destination.color != color &&
        destination.count == 1) {
      // Hits send a blot to the bar before placing the mover checker.
      if (destination.color == 'w') {
        whiteBar += 1;
      } else {
        blackBar += 1;
      }
      points[to] = SheshBeshPoint(color: color, count: 1);
    } else if (destination.isEmpty) {
      points[to] = SheshBeshPoint(color: color, count: 1);
    } else {
      points[to] = SheshBeshPoint(color: color, count: destination.count + 1);
    }

    return SheshBeshPosition(
      points: points,
      whiteBar: whiteBar,
      blackBar: blackBar,
      whiteBorneOff: whiteBorneOff,
      blackBorneOff: blackBorneOff,
    );
  }

  static int pipCount(SheshBeshPosition position, String color) {
    var pips = 0;
    for (var point = 0; point < position.points.length; point++) {
      final stack = position.points[point];
      if (stack.color != color || stack.count == 0) {
        continue;
      }
      final distance = color == 'w' ? (point + 1) : (24 - point);
      pips += distance * stack.count;
    }

    // Bar checkers are furthest from bearing off.
    pips += position.barCount(color) * 25;
    return pips;
  }

  static void _collectOutcomes({
    required SheshBeshPosition position,
    required String color,
    required List<int> dice,
    required int usedPips,
    required List<SheshBeshMove> movesSoFar,
    required List<_TurnOutcome> outcomes,
  }) {
    final candidates = _singleDieCandidates(
      position: position,
      color: color,
      dice: dice,
    );

    if (candidates.isEmpty) {
      outcomes.add(_TurnOutcome(moves: movesSoFar, usedPips: usedPips));
      return;
    }

    for (final candidate in candidates) {
      final nextPosition = applyMove(
        position: position,
        color: color,
        move: candidate.move,
      );
      final nextDice = List<int>.from(dice)..removeAt(candidate.dieIndex);
      final nextMoves = List<SheshBeshMove>.from(movesSoFar)
        ..add(candidate.move);
      _collectOutcomes(
        position: nextPosition,
        color: color,
        dice: nextDice,
        usedPips: usedPips + candidate.move.die,
        movesSoFar: nextMoves,
        outcomes: outcomes,
      );
    }
  }

  static List<_MoveCandidate> _singleDieCandidates({
    required SheshBeshPosition position,
    required String color,
    required List<int> dice,
  }) {
    final candidates = <_MoveCandidate>[];

    for (var dieIndex = 0; dieIndex < dice.length; dieIndex++) {
      final die = dice[dieIndex];
      candidates.addAll(
        _singleDieMoves(
          position: position,
          color: color,
          die: die,
        ).map((move) => _MoveCandidate(dieIndex: dieIndex, move: move)),
      );
    }

    return candidates;
  }

  static List<SheshBeshMove> _singleDieMoves({
    required SheshBeshPosition position,
    required String color,
    required int die,
  }) {
    final moves = <SheshBeshMove>[];
    final barCount = position.barCount(color);
    if (barCount > 0) {
      final entry = _entryPointIndex(color, die);
      if (_canLandOn(position.points[entry], color)) {
        moves.add(
          SheshBeshMove(
            source: SheshBeshMoveSource.bar,
            die: die,
            toPoint: entry,
            hitsOpponent: _isHit(position.points[entry], color),
          ),
        );
      }
      return moves;
    }

    for (var from = 0; from < position.points.length; from++) {
      final stack = position.points[from];
      if (stack.color != color || stack.count == 0) {
        continue;
      }

      final target = _targetPointIndex(color, from, die);
      if (_isOnBoard(target)) {
        final destination = position.points[target];
        if (_canLandOn(destination, color)) {
          moves.add(
            SheshBeshMove(
              source: SheshBeshMoveSource.point,
              die: die,
              fromPoint: from,
              toPoint: target,
              hitsOpponent: _isHit(destination, color),
            ),
          );
        }
        continue;
      }

      if (_canBearOff(position: position, color: color, from: from, die: die)) {
        moves.add(
          SheshBeshMove(
            source: SheshBeshMoveSource.point,
            die: die,
            fromPoint: from,
            bearsOff: true,
          ),
        );
      }
    }

    return moves;
  }

  static bool _canLandOn(SheshBeshPoint destination, String moverColor) {
    if (destination.isEmpty) {
      return true;
    }
    if (destination.color == moverColor) {
      return true;
    }
    return destination.count == 1;
  }

  static bool _isHit(SheshBeshPoint destination, String moverColor) {
    return !destination.isEmpty &&
        destination.color != moverColor &&
        destination.count == 1;
  }

  static int _entryPointIndex(String color, int die) {
    return color == 'w' ? 24 - die : die - 1;
  }

  static int _targetPointIndex(String color, int from, int die) {
    return color == 'w' ? from - die : from + die;
  }

  static bool _isOnBoard(int point) => point >= 0 && point <= 23;

  static bool _canBearOff({
    required SheshBeshPosition position,
    required String color,
    required int from,
    required int die,
  }) {
    if (position.barCount(color) > 0 || !_allCheckersInHome(position, color)) {
      return false;
    }

    if (color == 'w') {
      if (from < 0 || from > 5) {
        return false;
      }
      final target = from - die;
      if (target == -1) {
        return true;
      }
      if (target < -1) {
        for (var point = from + 1; point <= 5; point++) {
          final stack = position.points[point];
          if (stack.color == 'w' && stack.count > 0) {
            return false;
          }
        }
        return true;
      }
      return false;
    }

    if (from < 18 || from > 23) {
      return false;
    }
    final target = from + die;
    if (target == 24) {
      return true;
    }
    if (target > 24) {
      for (var point = 18; point < from; point++) {
        final stack = position.points[point];
        if (stack.color == 'b' && stack.count > 0) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  static bool _allCheckersInHome(SheshBeshPosition position, String color) {
    final homeMin = color == 'w' ? 0 : 18;
    final homeMax = color == 'w' ? 5 : 23;
    for (var point = 0; point < position.points.length; point++) {
      if (point >= homeMin && point <= homeMax) {
        continue;
      }
      final stack = position.points[point];
      if (stack.color == color && stack.count > 0) {
        return false;
      }
    }
    return true;
  }

  static int _compareMoves(SheshBeshMove a, SheshBeshMove b) {
    final sourceCompare = _sourceSortKey(a).compareTo(_sourceSortKey(b));
    if (sourceCompare != 0) {
      return sourceCompare;
    }
    final fromCompare = (a.fromPoint ?? -1).compareTo(b.fromPoint ?? -1);
    if (fromCompare != 0) {
      return fromCompare;
    }
    final toCompare = (a.toPoint ?? 99).compareTo(b.toPoint ?? 99);
    if (toCompare != 0) {
      return toCompare;
    }
    return a.die.compareTo(b.die);
  }

  static int _sourceSortKey(SheshBeshMove move) {
    return move.source == SheshBeshMoveSource.bar ? 0 : 1;
  }

  static String _moveIdentity(SheshBeshMove move) {
    final sourceKey = move.source == SheshBeshMoveSource.bar ? 'bar' : 'p';
    return '$sourceKey:${move.fromPoint ?? -1}:${move.toPoint ?? -1}:${move.die}:${move.bearsOff ? 1 : 0}:${move.hitsOpponent ? 1 : 0}';
  }
}

class _MoveCandidate {
  const _MoveCandidate({required this.dieIndex, required this.move});

  final int dieIndex;
  final SheshBeshMove move;
}

class _TurnOutcome {
  const _TurnOutcome({required this.moves, required this.usedPips});

  final List<SheshBeshMove> moves;
  final int usedPips;
}
