import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholebackgammon/src/game/engine/local_game_controller.dart';

/// F2 regression: during an overtime dual-live window the two turn side panels
/// must not BOTH show "Turn". Exactly one lane (the real [turnColor] lane) may
/// read as the active turn; the timed-out side reads as "Overtime".
///
/// The previous panel logic keyed `isActive` purely on `hasActiveDice(color)`,
/// so in the dual-live window (both sides holding dice) both panels rendered
/// "Turn" — a visible lie. The panels now derive their state from the same
/// controller truth these helpers replicate:
///   * active turn  == turnColor lane, allowed to move, NOT the overtime lane
///   * overtime lane == overtimeColor with dice still held
///
/// This test mirrors those exact predicates (kept in sync with
/// `_GameScreenState._isTurnLaneActive` / `_isOvertimeLane`) and asserts, at
/// every observed instant including proven dual-live windows, that at most one
/// side is "active turn" and the two states never overlap on one side.
bool _panelIsTurnLaneActive(LocalGameController c, String color) {
  if (!c.hasActiveGame || c.isGameOver) {
    return false;
  }
  if (c.overtimeColor == color) {
    return false;
  }
  return c.turnColor == color && c.isColorActiveNow(color);
}

bool _panelIsOvertimeLane(LocalGameController c, String color) {
  if (!c.hasActiveGame || c.isGameOver) {
    return false;
  }
  return c.overtimeColor == color && c.hasActiveDice(color);
}

void main() {
  test(
    'only one panel is "Turn" during the overtime dual-live window',
    () async {
      var sawOvertimeWithBothLive = false;
      var checks = 0;

      for (var seed = 1; seed <= 8; seed += 1) {
        final controller = LocalGameController(
          initialCooldownDuration: const Duration(milliseconds: 120),
          aiThinkDelayMin: const Duration(milliseconds: 10),
          aiThinkDelayMax: const Duration(milliseconds: 30),
          random: Random(seed),
        );
        addTearDown(controller.dispose);

        void assertPanelTruth() {
          checks += 1;
          final wTurn = _panelIsTurnLaneActive(controller, 'w');
          final bTurn = _panelIsTurnLaneActive(controller, 'b');
          final wOt = _panelIsOvertimeLane(controller, 'w');
          final bOt = _panelIsOvertimeLane(controller, 'b');

          // Never both panels showing the active turn.
          expect(
            wTurn && bTurn,
            isFalse,
            reason: 'seed=$seed both panels active-turn: '
                'turnColor=${controller.turnColor} '
                'overtime=${controller.overtimeColor} '
                'diceW=${controller.diceForColor('w')} '
                'diceB=${controller.diceForColor('b')}',
          );
          // A single side is never simultaneously "Turn" and "Overtime".
          expect(wTurn && wOt, isFalse, reason: 'seed=$seed white turn+overtime');
          expect(bTurn && bOt, isFalse, reason: 'seed=$seed black turn+overtime');

          // Record the specific dual-live shape this fix targets: one lane in
          // overtime while both colours still hold dice.
          final bothHaveDice = controller.hasActiveDice('w') &&
              controller.hasActiveDice('b');
          if (controller.overtimeColor != null && bothHaveDice) {
            sawOvertimeWithBothLive = true;
            // In that exact window the overtime side must NOT read as the
            // active turn, and the other side must be the sole active turn (or
            // itself overtime), so the panels can't both say "Turn".
            final ot = controller.overtimeColor!;
            expect(
              _panelIsTurnLaneActive(controller, ot),
              isFalse,
              reason: 'seed=$seed overtime lane $ot wrongly shown as Turn',
            );
          }
        }

        controller.addListener(assertPanelTruth);
        controller.startNewGame(playerAsWhite: true);
        assertPanelTruth();

        final deadline = DateTime.now().add(const Duration(seconds: 8));
        var idleSpins = 0;
        while (DateTime.now().isBefore(deadline)) {
          if (controller.isGameOver) {
            break;
          }
          final acted = _tryPlayOnePlayerMove(controller);
          idleSpins = acted ? 0 : idleSpins + 1;
          await Future<void>.delayed(const Duration(milliseconds: 8));
          if (idleSpins > 400) {
            break;
          }
        }
        assertPanelTruth();
      }

      expect(
        sawOvertimeWithBothLive,
        isTrue,
        reason: 'never reached an overtime window with both sides holding dice; '
            'the dual-live panel case was not exercised so a green result '
            'would prove nothing (checks=$checks)',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

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
