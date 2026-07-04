import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every checker of [color]: on-board points + bar + borne-off.
int _totalCheckers(SheshBeshPosition position, String color) {
  var onBoard = 0;
  for (final point in position.points) {
    if (point.color == color) {
      onBoard += point.count;
    }
  }
  return onBoard + position.barCount(color) + position.borneOffCount(color);
}

void main() {
  test(
    'bar-entry move with empty bar is rejected and never fabricates a checker',
    () {
      // A full, legal 15-checker white layout with an EMPTY bar. A bar-entry
      // move applied here must not silently place a 16th white checker.
      final points = List<SheshBeshPoint>.generate(
        24,
        (_) => const SheshBeshPoint(),
        growable: false,
      );
      points[23] = const SheshBeshPoint(color: 'w', count: 2);
      points[12] = const SheshBeshPoint(color: 'w', count: 5);
      points[7] = const SheshBeshPoint(color: 'w', count: 3);
      points[5] = const SheshBeshPoint(color: 'w', count: 5);

      final position = SheshBeshPosition(
        points: points,
        whiteBar: 0,
        blackBar: 0,
        whiteBorneOff: 0,
        blackBorneOff: 0,
      );

      expect(_totalCheckers(position, 'w'), 15);

      // die=3 => white entry point index 24-3 = 21 (an empty point).
      const barEntry = SheshBeshMove(
        source: SheshBeshMoveSource.bar,
        die: 3,
        toPoint: 21,
      );

      // The engine must reject this loudly instead of creating a phantom
      // checker (15 -> 16).
      expect(
        () => SheshBeshRules.applyMove(
          position: position,
          color: 'w',
          move: barEntry,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
