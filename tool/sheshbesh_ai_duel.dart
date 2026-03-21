// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';

import 'package:bulletholebackgammon/src/game/engine/sheshbesh_ai_engine.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';

const int _checkersPerSide = 15;
const int _defaultGames = 40;
const int _defaultSeed = 20260304;
const int _defaultMaxTurns = 280;

Future<void> main(List<String> args) async {
  final config = _Config.parse(args);
  final logger = GameSessionLogger(
    applicationId: 'bulletholebackgammon',
    gameId: 'backgammon',
    mode: 'ai',
    bughuntConfig: BughuntConfig(
      runId: config.runId ?? 'adhoc_sheshbesh_ai_duel',
      mode: BughuntMode.ai,
      role: BughuntRole.localA,
      seed: config.seed,
      maxTurns: config.maxTurns,
    ),
  );
  logger.beginSession(
    sessionLabel: 'sheshbesh_ai_duel',
    context: <String, Object?>{
      'games': config.games,
      'seed': config.seed,
      'maxTurns': config.maxTurns,
    },
  );

  final random = Random(config.seed);
  final aiWhite = SheshBeshAiEngine(random: Random(random.nextInt(1 << 31)));
  final aiBlack = SheshBeshAiEngine(random: Random(random.nextInt(1 << 31)));
  final failures = <_Failure>[];

  var whiteWins = 0;
  var blackWins = 0;
  var draws = 0;
  var cappedGames = 0;

  for (var gameIndex = 1; gameIndex <= config.games; gameIndex++) {
    logger.logBughuntEvent(
      'session_joined',
      payload: <String, Object?>{'gameIndex': gameIndex},
      turnIndex: 1,
      actionIndexOrPlyIndex: 0,
    );

    try {
      final result = _playSingleGame(
        gameIndex: gameIndex,
        config: config,
        random: random,
        aiWhite: aiWhite,
        aiBlack: aiBlack,
        logger: logger,
      );
      switch (result.outcome) {
        case _GameOutcome.whiteWin:
          whiteWins += 1;
          break;
        case _GameOutcome.blackWin:
          blackWins += 1;
          break;
        case _GameOutcome.draw:
          draws += 1;
          break;
        case _GameOutcome.capped:
          cappedGames += 1;
          break;
      }
    } catch (error) {
      final failure = _Failure(gameIndex: gameIndex, message: error.toString());
      failures.add(failure);
      logger.recordInvariantFailure(
        failureCode: invariantSessionTerminationInvalid,
        message: failure.message,
        context: <String, Object?>{'gameIndex': gameIndex},
      );
    }
  }

  print('Sheshbesh AI duel summary:');
  print('  games: ${config.games}');
  print('  white wins: $whiteWins');
  print('  black wins: $blackWins');
  print('  draws: $draws');
  print('  capped games: $cappedGames');
  print('  failures: ${failures.length}');
  print('  seed: ${config.seed}');
  print('  max turns: ${config.maxTurns}');

  if (failures.isNotEmpty) {
    print('');
    print('Failures:');
    for (final failure in failures) {
      print('  game=${failure.gameIndex}: ${failure.message}');
    }
    logger.closeSession(
      reason: 'failed',
      summary: <String, Object?>{
        'games': config.games,
        'whiteWins': whiteWins,
        'blackWins': blackWins,
        'draws': draws,
        'cappedGames': cappedGames,
        'failures': failures.length,
      },
    );
    throw StateError('AI duel failed with ${failures.length} failure(s).');
  }

  logger.closeSession(
    reason: 'completed',
    summary: <String, Object?>{
      'games': config.games,
      'whiteWins': whiteWins,
      'blackWins': blackWins,
      'draws': draws,
      'cappedGames': cappedGames,
      'failures': 0,
    },
  );
}

_GameResult _playSingleGame({
  required int gameIndex,
  required _Config config,
  required Random random,
  required SheshBeshAiEngine aiWhite,
  required SheshBeshAiEngine aiBlack,
  required GameSessionLogger logger,
}) {
  var position = SheshBeshRules.initialPosition();
  final opening = SheshBeshRules.determineOpeningStarter(random);
  var turnColor = opening.startingColor;
  var actionIndex = 0;

  for (var turnIndex = 1; turnIndex <= config.maxTurns; turnIndex++) {
    final dice = SheshBeshRules.rollTurnDice(random).toList(growable: true);
    logger.logBughuntEvent(
      'turn_started',
      payload: <String, Object?>{
        'gameIndex': gameIndex,
        'turnColor': turnColor,
        'dice': List<int>.from(dice),
      },
      turnIndex: turnIndex,
      actionIndexOrPlyIndex: actionIndex,
    );

    while (dice.isNotEmpty) {
      final ai = turnColor == 'w' ? aiWhite : aiBlack;
      final decision = SheshBeshRules.computeTurnDecision(
        position: position,
        color: turnColor,
        dice: dice,
      );
      if (!decision.hasMoves) {
        break;
      }

      final move = ai.chooseMove(
        position: position,
        color: turnColor,
        dice: dice,
      );
      if (move == null) {
        throw StateError(
          'No move returned for color=$turnColor with legal moves present.',
        );
      }
      if (!_containsMove(decision.legalMoves, move)) {
        throw StateError(
          'AI selected illegal move for color=$turnColor die=${move.die}.',
        );
      }

      position = SheshBeshRules.applyMove(
        position: position,
        color: turnColor,
        move: move,
      );
      _consumeDie(dice, move.die);
      actionIndex += 1;

      _validatePosition(
        position: position,
        gameIndex: gameIndex,
        turnIndex: turnIndex,
      );
      logger.logBughuntEvent(
        'action_applied',
        payload: <String, Object?>{
          'gameIndex': gameIndex,
          'actorColor': turnColor,
          'turnColor': turnColor,
          'move': move.describe(turnColor),
          'die': move.die,
          'diceRemaining': List<int>.from(dice),
        },
        turnIndex: turnIndex,
        actionIndexOrPlyIndex: actionIndex,
      );

      final winner = SheshBeshRules.winnerColor(position);
      if (winner != null) {
        logger.recordStateSnapshot(
          _snapshot(position, gameIndex: gameIndex, turnColor: turnColor),
          turnIndex: turnIndex,
          actionIndexOrPlyIndex: actionIndex,
        );
        logger.logBughuntEvent(
          'turn_ended',
          payload: <String, Object?>{
            'gameIndex': gameIndex,
            'turnColor': turnColor,
            'winnerColor': winner,
          },
          turnIndex: turnIndex,
          actionIndexOrPlyIndex: actionIndex,
        );
        return _GameResult(
          outcome: winner == 'w'
              ? _GameOutcome.whiteWin
              : _GameOutcome.blackWin,
        );
      }
    }

    logger.recordStateSnapshot(
      _snapshot(position, gameIndex: gameIndex, turnColor: turnColor),
      turnIndex: turnIndex,
      actionIndexOrPlyIndex: actionIndex,
    );
    logger.logBughuntEvent(
      'turn_ended',
      payload: <String, Object?>{
        'gameIndex': gameIndex,
        'turnColor': turnColor,
      },
      turnIndex: turnIndex,
      actionIndexOrPlyIndex: actionIndex,
    );
    turnColor = SheshBeshRules.oppositeColor(turnColor);
  }

  return const _GameResult(outcome: _GameOutcome.capped);
}

bool _containsMove(List<SheshBeshMove> legalMoves, SheshBeshMove candidate) {
  for (final move in legalMoves) {
    if (move.source == candidate.source &&
        move.fromPoint == candidate.fromPoint &&
        move.toPoint == candidate.toPoint &&
        move.bearsOff == candidate.bearsOff &&
        move.die == candidate.die) {
      return true;
    }
  }
  return false;
}

void _consumeDie(List<int> dice, int die) {
  final index = dice.indexOf(die);
  if (index < 0) {
    throw StateError('Consumed die $die not found in remaining dice $dice.');
  }
  dice.removeAt(index);
}

void _validatePosition({
  required SheshBeshPosition position,
  required int gameIndex,
  required int turnIndex,
}) {
  int totalFor(String color) {
    var total = position.barCount(color) + position.borneOffCount(color);
    for (final point in position.points) {
      if (point.count < 0) {
        throw StateError(
          'Negative stack count at game=$gameIndex turn=$turnIndex',
        );
      }
      if (point.count > 0 && point.color != 'w' && point.color != 'b') {
        throw StateError(
          'Invalid stack color "${point.color}" at game=$gameIndex turn=$turnIndex',
        );
      }
      if (point.color == color) {
        total += point.count;
      }
    }
    return total;
  }

  final whiteTotal = totalFor('w');
  final blackTotal = totalFor('b');
  if (whiteTotal != _checkersPerSide || blackTotal != _checkersPerSide) {
    throw StateError(
      'Checker conservation broken at game=$gameIndex turn=$turnIndex '
      '(white=$whiteTotal black=$blackTotal)',
    );
  }
}

Map<String, Object?> _snapshot(
  SheshBeshPosition position, {
  required int gameIndex,
  required String turnColor,
}) {
  return <String, Object?>{
    'gameIndex': gameIndex,
    'turnColor': turnColor,
    'whiteBar': position.whiteBar,
    'blackBar': position.blackBar,
    'whiteBorneOff': position.whiteBorneOff,
    'blackBorneOff': position.blackBorneOff,
    'points': position.points
        .asMap()
        .entries
        .map(
          (entry) => <String, Object?>{
            'index': entry.key,
            'color': entry.value.color,
            'count': entry.value.count,
          },
        )
        .toList(growable: false),
  };
}

enum _GameOutcome { whiteWin, blackWin, draw, capped }

class _GameResult {
  const _GameResult({required this.outcome});

  final _GameOutcome outcome;
}

class _Failure {
  const _Failure({required this.gameIndex, required this.message});

  final int gameIndex;
  final String message;
}

class _Config {
  const _Config({
    required this.games,
    required this.seed,
    required this.maxTurns,
    required this.runId,
  });

  final int games;
  final int seed;
  final int maxTurns;
  final String? runId;

  static _Config parse(List<String> args) {
    var games = _defaultGames;
    var seed = _defaultSeed;
    var maxTurns = _defaultMaxTurns;
    String? runId;

    for (final arg in args) {
      if (arg.startsWith('--games=')) {
        games = int.parse(arg.substring('--games='.length));
        continue;
      }
      if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
        continue;
      }
      if (arg.startsWith('--max-turns=')) {
        maxTurns = int.parse(arg.substring('--max-turns='.length));
        continue;
      }
      if (arg.startsWith('--max-game-ms=')) {
        // Compatibility alias from older controller-based runner.
        final ms = int.parse(arg.substring('--max-game-ms='.length));
        maxTurns = max(1, ms ~/ 40);
        continue;
      }
      if (arg.startsWith('--run-id=')) {
        runId = arg.substring('--run-id='.length).trim();
        continue;
      }

      // Compatibility no-op flags from the previous implementation.
      if (arg.startsWith('--cooldown-ms=') ||
          arg.startsWith('--ai-think-min-ms=') ||
          arg.startsWith('--ai-think-max-ms=') ||
          arg.startsWith('--step-ms=') ||
          arg.startsWith('--max-stall-ms=')) {
        continue;
      }

      if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      }
      throw ArgumentError('Unknown argument: $arg');
    }

    if (games <= 0) {
      throw ArgumentError('--games must be > 0');
    }
    if (maxTurns <= 0) {
      throw ArgumentError('--max-turns must be > 0');
    }

    return _Config(games: games, seed: seed, maxTurns: maxTurns, runId: runId);
  }
}

Never _printUsageAndExit() {
  print(
    'Usage: flutter pub run tool/sheshbesh_ai_duel.dart '
    '[--games=40] [--seed=20260304] [--max-turns=280] [--run-id=id]',
  );
  exit(0);
}
