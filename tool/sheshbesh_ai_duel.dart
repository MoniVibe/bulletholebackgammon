// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:bulletholebackgammon/src/game/engine/local_game_controller.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_ai_engine.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_model.dart';

const int _checkersPerSide = 15;
const int _defaultGames = 40;
const int _defaultSeed = 20260304;
const int _defaultCooldownMs = 300;
const int _defaultAiThinkMinMs = 120;
const int _defaultAiThinkMaxMs = 260;
const int _defaultStepMs = 20;
const int _defaultMaxGameMs = 12000;
const int _defaultMaxStallMs = 2200;

Future<void> main(List<String> args) async {
  final config = _Config.parse(args);
  final random = Random(config.seed);
  final failures = <_Failure>[];

  var whiteWins = 0;
  var blackWins = 0;

  final runStopwatch = Stopwatch()..start();

  for (var gameIndex = 1; gameIndex <= config.games; gameIndex++) {
    final playerAsWhite = random.nextBool();
    final localRandom = Random(random.nextInt(1 << 31));
    final playerAi = SheshBeshAiEngine(random: Random(random.nextInt(1 << 31)));
    final controller = LocalGameController(
      initialCooldownDuration: Duration(milliseconds: config.cooldownMs),
      aiThinkDelayMin: Duration(milliseconds: config.aiThinkMinMs),
      aiThinkDelayMax: Duration(milliseconds: config.aiThinkMaxMs),
      random: localRandom,
    );

    try {
      controller.startNewGame(
        playerAsWhite: playerAsWhite,
        cooldownDuration: Duration(milliseconds: config.cooldownMs),
      );

      final gameStopwatch = Stopwatch()..start();
      var lastState = _stateSignature(controller);
      var unchangedForMs = 0;

      while (!controller.isGameOver &&
          gameStopwatch.elapsedMilliseconds < config.maxGameMs) {
        _validateControllerState(
          controller: controller,
          gameIndex: gameIndex,
          elapsedMs: gameStopwatch.elapsedMilliseconds,
        );

        if (controller.canPlayerInteract) {
          _drivePlayerAi(controller: controller, ai: playerAi);
        }

        await Future<void>.delayed(Duration(milliseconds: config.stepMs));

        final nextState = _stateSignature(controller);
        if (nextState == lastState) {
          unchangedForMs += config.stepMs;
        } else {
          unchangedForMs = 0;
          lastState = nextState;
        }

        if (unchangedForMs >= config.maxStallMs) {
          throw StateError(
            'Stalled for ${unchangedForMs}ms. '
            'turn=${controller.turnColor} '
            'diceW=${controller.diceForColor('w')} '
            'diceB=${controller.diceForColor('b')} '
            'status="${controller.statusText}"',
          );
        }
      }

      if (!controller.isGameOver) {
        throw StateError(
          'Exceeded max game time ${config.maxGameMs}ms without winner. '
          'turn=${controller.turnColor} '
          'diceW=${controller.diceForColor('w')} '
          'diceB=${controller.diceForColor('b')} '
          'historyTail=${_historyTail(controller.history, 6)}',
        );
      }

      if (controller.winnerColor == 'w') {
        whiteWins += 1;
      } else if (controller.winnerColor == 'b') {
        blackWins += 1;
      }
    } catch (error) {
      failures.add(
        _Failure(
          gameIndex: gameIndex,
          message: error.toString(),
          turnColor: controller.turnColor,
          playerColor: controller.playerColor,
          diceWhite: controller.diceForColor('w'),
          diceBlack: controller.diceForColor('b'),
          historyTail: _historyTail(controller.history, 8),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  print('Sheshbesh AI duel summary:');
  print('  games: ${config.games}');
  print('  white wins: $whiteWins');
  print('  black wins: $blackWins');
  print('  draws/unfinished: ${config.games - whiteWins - blackWins}');
  print('  failures: ${failures.length}');
  print('  seed: ${config.seed}');
  print('  runtimeMs: ${runStopwatch.elapsedMilliseconds}');

  if (failures.isNotEmpty) {
    print('');
    print('Failures:');
    for (final failure in failures) {
      print(
        '  game=${failure.gameIndex} turn=${failure.turnColor} '
        'player=${failure.playerColor} '
        'diceW=${failure.diceWhite} diceB=${failure.diceBlack}',
      );
      print('    ${failure.message}');
      print('    historyTail=${failure.historyTail.join(' | ')}');
    }
    throw StateError('AI duel failed with ${failures.length} failure(s).');
  }
}

void _drivePlayerAi({
  required LocalGameController controller,
  required SheshBeshAiEngine ai,
}) {
  final position = _snapshotPosition(controller);
  final color = controller.playerColor;
  final dice = controller.diceForColor(color);
  if (dice.isEmpty) {
    return;
  }

  final beforeHistoryCount = controller.history.length;
  final move = ai.chooseMove(position: position, color: color, dice: dice);

  if (move == null) {
    _playFirstLegalThroughUi(controller);
    return;
  }

  _applyMoveThroughUi(controller, move);

  // Fallback when chosen move is no longer applicable due dynamic overlap.
  if (controller.history.length == beforeHistoryCount) {
    _playFirstLegalThroughUi(controller);
  }
}

void _applyMoveThroughUi(LocalGameController controller, SheshBeshMove move) {
  if (move.source == SheshBeshMoveSource.bar) {
    controller.tapBar();
  } else if (move.fromPoint != null) {
    controller.tapPoint(move.fromPoint!);
  }

  if (move.bearsOff) {
    controller.tapBearOff();
    return;
  }

  if (move.toPoint != null) {
    controller.tapPoint(move.toPoint!);
  }
}

void _playFirstLegalThroughUi(LocalGameController controller) {
  final before = controller.history.length;

  if (controller.canEnterFromBar) {
    controller.tapBar();
    if (controller.canBearOffTarget) {
      controller.tapBearOff();
      if (controller.history.length > before) {
        return;
      }
    }
    final targets = controller.legalTargetPoints.toList()..sort();
    if (targets.isNotEmpty) {
      controller.tapPoint(targets.first);
    }
    return;
  }

  final sources = controller.playableSourcePoints.toList()..sort();
  for (final source in sources) {
    controller.tapPoint(source);
    if (controller.canBearOffTarget) {
      controller.tapBearOff();
      if (controller.history.length > before) {
        return;
      }
    }
    final targets = controller.legalTargetPoints.toList()..sort();
    if (targets.isEmpty) {
      continue;
    }
    controller.tapPoint(targets.first);
    if (controller.history.length > before) {
      return;
    }
  }
}

SheshBeshPosition _snapshotPosition(LocalGameController controller) {
  final points = List<SheshBeshPoint>.generate(24, (index) {
    final point = controller.points[index];
    return SheshBeshPoint(color: point.color, count: point.count);
  }, growable: false);
  return SheshBeshPosition(
    points: points,
    whiteBar: controller.barCount('w'),
    blackBar: controller.barCount('b'),
    whiteBorneOff: controller.borneOffCount('w'),
    blackBorneOff: controller.borneOffCount('b'),
  );
}

void _validateControllerState({
  required LocalGameController controller,
  required int gameIndex,
  required int elapsedMs,
}) {
  int totalFor(String color) {
    var total = controller.barCount(color) + controller.borneOffCount(color);
    for (final point in controller.points) {
      if (point.color == color) {
        total += point.count;
      }
      if (point.count < 0) {
        throw StateError(
          'Negative stack count at game=$gameIndex elapsedMs=$elapsedMs',
        );
      }
      if (point.count > 0 && (point.color != 'w' && point.color != 'b')) {
        throw StateError(
          'Invalid stack color "${point.color}" '
          'at game=$gameIndex elapsedMs=$elapsedMs',
        );
      }
    }
    return total;
  }

  final whiteTotal = totalFor('w');
  final blackTotal = totalFor('b');
  if (whiteTotal != _checkersPerSide || blackTotal != _checkersPerSide) {
    throw StateError(
      'Checker conservation broken at game=$gameIndex elapsedMs=$elapsedMs '
      '(white=$whiteTotal black=$blackTotal)',
    );
  }
}

String _stateSignature(LocalGameController controller) {
  final buffer = StringBuffer()
    ..write('turn=${controller.turnColor};')
    ..write('wDice=${controller.diceForColor('w').join(',')};')
    ..write('bDice=${controller.diceForColor('b').join(',')};')
    ..write('wBar=${controller.barCount('w')};')
    ..write('bBar=${controller.barCount('b')};')
    ..write('wOff=${controller.borneOffCount('w')};')
    ..write('bOff=${controller.borneOffCount('b')};')
    ..write('hist=${controller.history.length};');

  for (final point in controller.points) {
    buffer.write('${point.color ?? '_'}${point.count}|');
  }

  return buffer.toString();
}

List<String> _historyTail(List<String> history, int count) {
  if (history.length <= count) {
    return List<String>.from(history);
  }
  return history.sublist(history.length - count);
}

class _Config {
  const _Config({
    required this.games,
    required this.seed,
    required this.cooldownMs,
    required this.aiThinkMinMs,
    required this.aiThinkMaxMs,
    required this.stepMs,
    required this.maxGameMs,
    required this.maxStallMs,
  });

  final int games;
  final int seed;
  final int cooldownMs;
  final int aiThinkMinMs;
  final int aiThinkMaxMs;
  final int stepMs;
  final int maxGameMs;
  final int maxStallMs;

  static _Config parse(List<String> args) {
    var games = _defaultGames;
    var seed = _defaultSeed;
    var cooldownMs = _defaultCooldownMs;
    var aiThinkMinMs = _defaultAiThinkMinMs;
    var aiThinkMaxMs = _defaultAiThinkMaxMs;
    var stepMs = _defaultStepMs;
    var maxGameMs = _defaultMaxGameMs;
    var maxStallMs = _defaultMaxStallMs;

    for (final arg in args) {
      if (arg.startsWith('--games=')) {
        games = int.parse(arg.substring('--games='.length));
        continue;
      }
      if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
        continue;
      }
      if (arg.startsWith('--cooldown-ms=')) {
        cooldownMs = int.parse(arg.substring('--cooldown-ms='.length));
        continue;
      }
      if (arg.startsWith('--ai-think-min-ms=')) {
        aiThinkMinMs = int.parse(arg.substring('--ai-think-min-ms='.length));
        continue;
      }
      if (arg.startsWith('--ai-think-max-ms=')) {
        aiThinkMaxMs = int.parse(arg.substring('--ai-think-max-ms='.length));
        continue;
      }
      if (arg.startsWith('--step-ms=')) {
        stepMs = int.parse(arg.substring('--step-ms='.length));
        continue;
      }
      if (arg.startsWith('--max-game-ms=')) {
        maxGameMs = int.parse(arg.substring('--max-game-ms='.length));
        continue;
      }
      if (arg.startsWith('--max-stall-ms=')) {
        maxStallMs = int.parse(arg.substring('--max-stall-ms='.length));
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
    if (cooldownMs <= 0) {
      throw ArgumentError('--cooldown-ms must be > 0');
    }
    if (aiThinkMinMs <= 0 || aiThinkMaxMs <= 0) {
      throw ArgumentError(
        '--ai-think-min-ms and --ai-think-max-ms must be > 0',
      );
    }
    if (aiThinkMaxMs < aiThinkMinMs) {
      throw ArgumentError('--ai-think-max-ms must be >= --ai-think-min-ms');
    }
    if (stepMs <= 0 || maxGameMs <= 0 || maxStallMs <= 0) {
      throw ArgumentError(
        '--step-ms, --max-game-ms and --max-stall-ms must be > 0',
      );
    }

    return _Config(
      games: games,
      seed: seed,
      cooldownMs: cooldownMs,
      aiThinkMinMs: aiThinkMinMs,
      aiThinkMaxMs: aiThinkMaxMs,
      stepMs: stepMs,
      maxGameMs: maxGameMs,
      maxStallMs: maxStallMs,
    );
  }
}

class _Failure {
  const _Failure({
    required this.gameIndex,
    required this.message,
    required this.turnColor,
    required this.playerColor,
    required this.diceWhite,
    required this.diceBlack,
    required this.historyTail,
  });

  final int gameIndex;
  final String message;
  final String turnColor;
  final String playerColor;
  final List<int> diceWhite;
  final List<int> diceBlack;
  final List<String> historyTail;
}

Never _printUsageAndExit() {
  print(
    'Usage: dart run tool/sheshbesh_ai_duel.dart '
    '[--games=N] [--seed=N] [--cooldown-ms=N] '
    '[--ai-think-min-ms=N] [--ai-think-max-ms=N] '
    '[--step-ms=N] [--max-game-ms=N] [--max-stall-ms=N]',
  );
  throw _UsageExit();
}

class _UsageExit implements Exception {}
