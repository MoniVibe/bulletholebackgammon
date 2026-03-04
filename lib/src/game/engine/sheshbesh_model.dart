import 'package:flutter/foundation.dart';

/// Immutable stack on a board point.
@immutable
class SheshBeshPoint {
  const SheshBeshPoint({this.color, this.count = 0})
    : assert(count >= 0),
      assert((color == null && count == 0) || (color != null && count > 0));

  final String? color;
  final int count;

  bool get isEmpty => color == null || count == 0;

  SheshBeshPoint withCount(int nextCount) {
    if (nextCount <= 0) {
      return const SheshBeshPoint();
    }
    return SheshBeshPoint(color: color, count: nextCount);
  }

  SheshBeshPoint withColorAndCount(String nextColor, int nextCount) {
    if (nextCount <= 0) {
      return const SheshBeshPoint();
    }
    return SheshBeshPoint(color: nextColor, count: nextCount);
  }
}

/// Source of a checker move.
enum SheshBeshMoveSource { point, bar }

/// One atomic checker move that consumes exactly one die value.
@immutable
class SheshBeshMove {
  const SheshBeshMove({
    required this.source,
    required this.die,
    this.fromPoint,
    this.toPoint,
    this.hitsOpponent = false,
    this.bearsOff = false,
  }) : assert(die >= 1 && die <= 6);

  final SheshBeshMoveSource source;
  final int die;
  final int? fromPoint;
  final int? toPoint;
  final bool hitsOpponent;
  final bool bearsOff;

  String describe(String color) {
    final colorLabel = color == 'w' ? 'W' : 'B';
    final fromLabel = source == SheshBeshMoveSource.bar
        ? 'bar'
        : _pointLabel(fromPoint!);
    final toLabel = bearsOff ? 'off' : _pointLabel(toPoint!);
    final hitLabel = hitsOpponent ? ' hit' : '';
    return '$colorLabel $fromLabel->$toLabel ($die)$hitLabel';
  }

  static String _pointLabel(int pointIndex) {
    return 'P${pointIndex + 1}';
  }
}

/// Full immutable board position.
@immutable
class SheshBeshPosition {
  const SheshBeshPosition({
    required this.points,
    required this.whiteBar,
    required this.blackBar,
    required this.whiteBorneOff,
    required this.blackBorneOff,
  }) : assert(points.length == 24);

  final List<SheshBeshPoint> points;
  final int whiteBar;
  final int blackBar;
  final int whiteBorneOff;
  final int blackBorneOff;

  int barCount(String color) => color == 'w' ? whiteBar : blackBar;

  int borneOffCount(String color) =>
      color == 'w' ? whiteBorneOff : blackBorneOff;

  SheshBeshPosition copyWith({
    List<SheshBeshPoint>? points,
    int? whiteBar,
    int? blackBar,
    int? whiteBorneOff,
    int? blackBorneOff,
  }) {
    return SheshBeshPosition(
      points: points ?? this.points,
      whiteBar: whiteBar ?? this.whiteBar,
      blackBar: blackBar ?? this.blackBar,
      whiteBorneOff: whiteBorneOff ?? this.whiteBorneOff,
      blackBorneOff: blackBorneOff ?? this.blackBorneOff,
    );
  }
}

@immutable
class TurnDecision {
  const TurnDecision({
    required this.legalMoves,
    required this.maxMovesUsable,
    required this.maxUsedPips,
  });

  final List<SheshBeshMove> legalMoves;
  final int maxMovesUsable;
  final int maxUsedPips;

  bool get hasMoves => legalMoves.isNotEmpty;
}
