import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholebackgammon/src/game/engine/local_game_controller.dart';

void main() {
  test('startNewGame creates valid 15-checker state and opening dice', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 3),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: Random(7),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    int totalFor(String color) {
      var total = controller.barCount(color) + controller.borneOffCount(color);
      for (final point in controller.points) {
        if (point.color == color) {
          total += point.count;
        }
      }
      return total;
    }

    expect(controller.hasActiveGame, isTrue);
    expect(totalFor('w'), 15);
    expect(totalFor('b'), 15);
    expect(
      controller.diceForColor('w').isNotEmpty ||
          controller.diceForColor('b').isNotEmpty,
      isTrue,
    );
  });

  test(
    'timeout unlocks opponent without removing timed-out side dice',
    () async {
      final controller = LocalGameController(
        initialCooldownDuration: const Duration(milliseconds: 250),
        aiThinkDelayMin: const Duration(days: 1),
        aiThinkDelayMax: const Duration(days: 1),
        random: _FixedRandom(<int>[
          5, 1, // opening roll -> white starts
          1, 1, // white opening dice
          3, 4, // black dice unlocked by timeout
        ]),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(playerAsWhite: true);
      expect(controller.diceForColor('w').length, 4);
      expect(controller.diceForColor('b'), isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 520));

      expect(controller.diceForColor('w').length, 4);
      expect(controller.diceForColor('b'), isNotEmpty);
      expect(
        controller.history.any((entry) => entry.contains('time expired')),
        isTrue,
      );
      expect(controller.canPlayerInteract, isTrue);
    },
  );

  test('opponent finishing first waits for timed-out side leftovers', () async {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(milliseconds: 350),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: _FixedRandom(<int>[
        5, 1, // opening roll -> white starts (AI starts)
        1, 1, // white opening dice kept after timeout
        2, 3, // black unlocked by timeout (player)
      ]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: false);
    await Future<void>.delayed(const Duration(milliseconds: 520));

    expect(controller.diceForColor('w'), isNotEmpty);
    expect(controller.diceForColor('b'), isNotEmpty);

    await _playAllPlayerMoves(controller);
    expect(
      controller.history.any((entry) => entry.contains('time expired')),
      isTrue,
    );
    // Player (black) finished, but white still has timed-out leftovers,
    // so black must wait with no immediate reroll.
    expect(controller.diceForColor('b'), isEmpty);
    expect(controller.diceForColor('w'), isNotEmpty);
  });

  test(
    'opponent gets queued reroll after timed-out player clears leftovers',
    () async {
      final controller = LocalGameController(
        initialCooldownDuration: const Duration(milliseconds: 250),
        aiThinkDelayMin: const Duration(milliseconds: 80),
        aiThinkDelayMax: const Duration(milliseconds: 80),
        random: _FixedRandom(<int>[
          5, 1, // opening roll -> white starts (player)
          1, 1, // white opening dice
          1, 1, // black unlocked by timeout (AI), should finish first
          4, 5, // black queued reroll once white clears leftovers
        ]),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(playerAsWhite: true);
      await _waitUntil(
        () =>
            controller.diceForColor('b').isEmpty &&
            controller.diceForColor('w').isNotEmpty,
        timeout: const Duration(seconds: 3),
      );

      await _playAllPlayerMoves(controller);
      // As soon as overtime white clears, black receives the queued roll.
      expect(controller.diceForColor('b'), isNotEmpty);
    },
  );

  test('player exposes source and target dice-spend hints', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 1),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: _FixedRandom(<int>[5, 1, 1, 1]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    expect(controller.playableSourcePoints, isNotEmpty);
    final source = controller.playableSourcePoints.toList()..sort();
    controller.tapPoint(source.first);

    expect(controller.legalTargetPoints, isNotEmpty);
    expect(
      controller.targetDiceSpentHints.keys.toSet(),
      equals(controller.legalTargetPoints),
    );
    expect(
      controller.targetDiceSpentHints.values.every((value) => value >= 1),
      isTrue,
    );
  });

  test(
    'opponent move keeps player selection when selected source remains valid',
    () async {
      final controller = LocalGameController(
        initialCooldownDuration: const Duration(milliseconds: 250),
        aiThinkDelayMin: const Duration(milliseconds: 40),
        aiThinkDelayMax: const Duration(milliseconds: 40),
        random: _FixedRandom(<int>[
          5, 1, // opening roll -> white starts (AI)
          1, 1, // white opening dice
          2, 3, // black dice unlocked by timeout (player)
        ]),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(playerAsWhite: false);
      await _waitUntil(
        () =>
            controller.canPlayerInteract &&
            controller.diceForColor('w').isNotEmpty &&
            controller.diceForColor('b').isNotEmpty &&
            controller.playableSourcePoints.isNotEmpty,
        timeout: const Duration(seconds: 3),
      );

      final sourceCandidates = controller.playableSourcePoints.toList()..sort();
      final selectedSource = sourceCandidates.firstWhere(
        (point) => controller.points[point].count > 1,
        orElse: () => sourceCandidates.first,
      );
      controller.tapPoint(selectedSource);
      expect(controller.selectedPoint, selectedSource);

      final previousOpponentMove = controller.opponentLastMove;
      await _waitUntil(() {
        final latestOpponentMove = controller.opponentLastMove;
        if (latestOpponentMove == null) {
          return false;
        }
        if (previousOpponentMove == null) {
          return true;
        }
        return latestOpponentMove != previousOpponentMove;
      }, timeout: const Duration(seconds: 3));

      expect(controller.canPlayerInteract, isTrue);
      expect(controller.selectedPoint, selectedSource);
    },
  );

  test('long press selects stacked destination source without spending dice', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 1),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: _FixedRandom(<int>[5, 1, 1, 1]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);
    final sourceTarget = _findSelectableDestinationSource(controller);
    expect(
      sourceTarget,
      isNotNull,
      reason:
          'Expected at least one legal destination that also has a playable source checker.',
    );
    final source = sourceTarget![0];
    final destinationSource = sourceTarget[1];
    expect(controller.selectedPoint, source);

    final historyBefore = controller.history.length;
    final diceBefore = controller.diceForColor(controller.playerColor);

    controller.longPressPoint(destinationSource);

    expect(controller.selectedPoint, destinationSource);
    expect(controller.history.length, historyBefore);
    expect(controller.diceForColor(controller.playerColor), equals(diceBefore));
    expect(controller.legalTargetPoints, isNotEmpty);
  });
}

Future<void> _playAllPlayerMoves(LocalGameController controller) async {
  var guard = 0;
  while (controller.diceForColor(controller.playerColor).isNotEmpty &&
      guard < 30) {
    guard += 1;
    if (!controller.canPlayerInteract) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      continue;
    }
    if (controller.canEnterFromBar) {
      controller.tapBar();
      final targets = controller.legalTargetPoints.toList()..sort();
      if (targets.isEmpty) {
        break;
      }
      controller.tapPoint(targets.first);
    } else {
      final sources = controller.playableSourcePoints.toList()..sort();
      if (sources.isEmpty) {
        break;
      }
      controller.tapPoint(sources.first);
      final targets = controller.legalTargetPoints.toList()..sort();
      if (targets.isEmpty) {
        break;
      }
      controller.tapPoint(targets.first);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollEvery = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(pollEvery);
  }
  fail('Condition not met before timeout.');
}

List<int>? _findSelectableDestinationSource(LocalGameController controller) {
  final sources = controller.playableSourcePoints.toList()..sort();
  for (final source in sources) {
    controller.tapPoint(source);
    final targets = controller.legalTargetPoints.toList()..sort();
    for (final target in targets) {
      if (!controller.playableSourcePoints.contains(target)) {
        continue;
      }
      if (controller.points[target].color != controller.playerColor) {
        continue;
      }
      return <int>[source, target];
    }
    // Deselect before trying next source.
    controller.tapPoint(source);
  }
  return null;
}

class _FixedRandom implements Random {
  _FixedRandom(this._values);

  final List<int> _values;
  int _index = 0;

  @override
  bool nextBool() {
    return nextInt(2) == 1;
  }

  @override
  double nextDouble() {
    return (nextInt(1000000) / 1000000);
  }

  @override
  int nextInt(int max) {
    final value = _values[_index % _values.length];
    _index += 1;
    return value % max;
  }
}
