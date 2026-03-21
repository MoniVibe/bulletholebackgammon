import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholebackgammon/src/game/engine/local_game_controller.dart';

void main() {
  test('turn deadline is deterministic with injected clock', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 3, 18, 12, 0, 0);
      final controller = LocalGameController(
        initialCooldownDuration: const Duration(seconds: 1),
        aiThinkDelayMin: const Duration(days: 1),
        aiThinkDelayMax: const Duration(days: 1),
        nowProvider: () => now,
      );

      controller.startNewGame(playerAsWhite: true);
      final initial = controller.statusText;
      expect(initial.isNotEmpty, isTrue);

      now = now.add(const Duration(milliseconds: 1200));
      async.elapse(const Duration(milliseconds: 1200));

      expect(controller.statusText.contains('W:'), isTrue);
      controller.dispose();
    });
  });
}
