import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholebackgammon/src/game/engine/local_game_controller.dart';
import 'package:bulletholebackgammon/src/game/engine/sheshbesh_rules.dart';

/// Controller-level conservation stress for the CONCURRENT OVERTIME window.
///
/// The pure rules engine is well covered by [test/sheshbesh_property_test.dart],
/// but that harness only ever drives ONE side at a time. The
/// [LocalGameController] overtime path is different: once a side's timer
/// expires it becomes an "overtime" lane that keeps its old dice, and the
/// opponent is unlocked in parallel. In that window BOTH colours are
/// simultaneously allowed to mutate the single shared `_position`
/// (`_completeDiceBatch`/`_isColorAllowedToMove`), and player selection is
/// preserved across the opponent's moves
/// (`_reconcileSelectionAfterExternalBoardChange`). That interleaving had no
/// conservation coverage at all.
///
/// This test drives a real controller with real timers (short cooldowns so
/// overtime is reached quickly, fast AI think delays so the AI interleaves
/// with the human), and after EVERY controller notification asserts the full
/// invariant set. It also PROVES it actually entered the dual-live window
/// (both colours allowed to move at the same instant) — without that proof a
/// green result would be vacuous.
void main() {
  test(
    'overtime dual-live window conserves checkers across interleaved play',
    () async {
      // Run several seeds so the interleaving/timeout races vary. Each seed is
      // an independent short game; we only need each to reach overtime once.
      for (var seed = 1; seed <= 8; seed += 1) {
        final monitor = _ConservationMonitor();
        final controller = LocalGameController(
          initialCooldownDuration: const Duration(milliseconds: 120),
          aiThinkDelayMin: const Duration(milliseconds: 10),
          aiThinkDelayMax: const Duration(milliseconds: 30),
          random: Random(seed),
        );
        addTearDown(controller.dispose);
        controller.addListener(() => monitor.check(controller, seed: seed));

        controller.startNewGame(playerAsWhite: true);
        monitor.check(controller, seed: seed);

        // Drive the human side whenever it is legally allowed to move, while
        // the AI fires on its own timer. Cap wall-clock so a stuck seed fails
        // loudly rather than hanging.
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        var idleSpins = 0;
        while (DateTime.now().isBefore(deadline)) {
          if (controller.isGameOver) {
            break;
          }

          // Record whether the dual-live window is currently open BEFORE we
          // act, so the proof reflects genuine concurrent eligibility, not a
          // state we manufactured by moving.
          monitor.observeDualLive(controller);

          final actedThisSpin = _tryPlayOnePlayerMove(controller);
          if (actedThisSpin) {
            idleSpins = 0;
          } else {
            idleSpins += 1;
          }

          // Yield so the ticker + AI timer run. Overtime is only reached once
          // a cooldown elapses, so we must actually pass wall-clock time.
          await Future<void>.delayed(const Duration(milliseconds: 8));

          // If nothing has been movable for a long stretch and the game is not
          // over, break — some seeds resolve to a state where only the AI acts.
          if (idleSpins > 400) {
            break;
          }
        }

        monitor.check(controller, seed: seed);

        expect(
          monitor.violations,
          isEmpty,
          reason: 'seed=$seed conservation violations:\n'
              '${monitor.violations.join('\n')}',
        );
        expect(
          monitor.sawDualLiveWindow,
          isTrue,
          reason: 'seed=$seed never entered the overtime dual-live window; '
              'the concurrent path was not actually exercised so a green '
              'result would prove nothing. dualLiveObservations='
              '${monitor.dualLiveObservationCount}',
        );
        // Coverage proof, surfaced to the run log: how many distinct instants
        // both colours were simultaneously eligible to mutate the board.
        // ignore: avoid_print
        print(
          'DUAL_LIVE_PROOF seed=$seed observations='
          '${monitor.dualLiveObservationCount} '
          'checks=${monitor.checkCount}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Attempts exactly one legal player move if the human is allowed to act.
/// Returns true if a move was applied.
bool _tryPlayOnePlayerMove(LocalGameController controller) {
  if (!controller.canPlayerInteract || controller.isGameOver) {
    return false;
  }

  final historyBefore = controller.history.length;

  if (controller.canEnterFromBar) {
    controller.tapBar();
    final targets = controller.legalTargetPoints.toList()..sort();
    if (targets.isEmpty) {
      return false;
    }
    controller.tapPoint(targets.first);
    return controller.history.length > historyBefore;
  }

  final sources = controller.playableSourcePoints.toList()..sort();
  if (sources.isEmpty) {
    return false;
  }
  controller.tapPoint(sources.first);

  if (controller.canBearOffTarget) {
    controller.tapBearOff();
    if (controller.history.length > historyBefore) {
      return true;
    }
  }

  final targets = controller.legalTargetPoints.toList()..sort();
  if (targets.isEmpty) {
    return false;
  }
  controller.tapPoint(targets.first);
  return controller.history.length > historyBefore;
}

/// Validates all board invariants on every observed controller state and
/// records whether the concurrent overtime window was ever open.
class _ConservationMonitor {
  final List<String> violations = <String>[];
  bool sawDualLiveWindow = false;
  int dualLiveObservationCount = 0;
  int checkCount = 0;

  int _lastWhiteBorneOff = 0;
  int _lastBlackBorneOff = 0;

  void observeDualLive(LocalGameController controller) {
    if (_isDualLive(controller)) {
      sawDualLiveWindow = true;
      dualLiveObservationCount += 1;
    }
  }

  /// Dual-live == both colours are simultaneously eligible to mutate the shared
  /// board. Derived purely from public surface:
  ///  * the human can interact (its lane is allowed to move), AND
  ///  * the opponent lane is ALSO in a movable state (overtime lane, or its
  ///    own timed turn) — surfaced through [LocalGameController.statusText]
  ///    which renders each lane's status.
  bool _isDualLive(LocalGameController controller) {
    if (!controller.hasActiveGame || controller.isGameOver) {
      return false;
    }
    final playerColor = controller.playerColor;
    final aiColor = controller.aiColor;

    final playerAllowed = controller.canPlayerInteract;
    if (!playerAllowed) {
      return false;
    }

    // The AI lane is eligible when it still holds dice AND is either the active
    // turn lane or an overtime lane. We detect the overtime lane via the status
    // text, and the active-turn case via the turn colour matching the AI while
    // the AI holds dice. When the player is allowed AND one of these holds for
    // the AI, both colours can move at once.
    final aiHasDice = controller.diceForColor(aiColor).isNotEmpty;
    if (!aiHasDice) {
      return false;
    }
    final status = controller.statusText;
    final aiLaneOvertime = status.contains('overtime');
    final aiIsTurnColor = controller.turnColor == aiColor;

    // The only way the player is allowed while it is NOT the active turn colour
    // is if the player is itself an overtime lane; in that case the AI holding
    // dice as the active turn colour is a genuine dual-live overlap. If the
    // player IS the active turn colour, then the AI must be an overtime lane to
    // overlap. Either branch requires an overtime lane somewhere, so require it.
    final playerIsTurnColor = controller.turnColor == playerColor;
    if (playerIsTurnColor) {
      // Player holds the active turn; AI overlaps only as an overtime lane.
      return aiLaneOvertime;
    }
    // Player is allowed without holding the active turn -> player is overtime;
    // AI overlaps as the active turn lane (or also overtime).
    return aiIsTurnColor || aiLaneOvertime;
  }

  void check(LocalGameController controller, {required int seed}) {
    checkCount += 1;
    final tag = 'seed=$seed';

    // Per-side totals must always be exactly 15 (on-board + bar + borne-off).
    for (final color in const <String>['w', 'b']) {
      var onBoard = 0;
      for (final point in controller.points) {
        if (point.color == color) {
          onBoard += point.count;
        }
      }
      final total =
          onBoard + controller.barCount(color) + controller.borneOffCount(color);
      if (total != SheshBeshRules.totalCheckersPerSide) {
        violations.add(
          '$tag color=$color total=$total (expected 15, '
          'onBoard=$onBoard bar=${controller.barCount(color)} '
          'off=${controller.borneOffCount(color)})',
        );
      }
      if (controller.barCount(color) < 0 ||
          controller.borneOffCount(color) < 0) {
        violations.add(
          '$tag color=$color negative bar/off '
          '(bar=${controller.barCount(color)} '
          'off=${controller.borneOffCount(color)})',
        );
      }
    }

    // No negative counts; no point owned by a colour with count 0 (phantom).
    for (var i = 0; i < controller.points.length; i += 1) {
      final point = controller.points[i];
      if (point.count < 0) {
        violations.add('$tag point $i negative count=${point.count}');
      }
      if (point.count == 0 && point.color != null) {
        violations.add(
          '$tag point $i owned by ${point.color} but count=0 (phantom)',
        );
      }
      if (point.count > 0 && point.color != 'w' && point.color != 'b') {
        violations.add(
          '$tag point $i count=${point.count} but color=${point.color}',
        );
      }
    }

    // Borne-off must never decrease.
    if (controller.borneOffCount('w') < _lastWhiteBorneOff) {
      violations.add(
        '$tag white borneOff decreased '
        '$_lastWhiteBorneOff -> ${controller.borneOffCount('w')}',
      );
    }
    if (controller.borneOffCount('b') < _lastBlackBorneOff) {
      violations.add(
        '$tag black borneOff decreased '
        '$_lastBlackBorneOff -> ${controller.borneOffCount('b')}',
      );
    }
    _lastWhiteBorneOff = controller.borneOffCount('w');
    _lastBlackBorneOff = controller.borneOffCount('b');
  }
}
