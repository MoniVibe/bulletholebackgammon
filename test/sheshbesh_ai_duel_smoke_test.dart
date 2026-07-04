import 'package:flutter_test/flutter_test.dart';

import '../tool/sheshbesh_ai_duel.dart' as duel;

void main() {
  // NOTE: this runner is a PURE SEQUENTIAL rules-engine duel — one side moves
  // at a time, no timers, no cooldown, no interleaving. Earlier revisions
  // passed --cooldown-ms/--ai-think-*/--step-ms/--max-stall-ms here believing
  // they exercised timed concurrent play, but those flags are DEAD NO-OPS
  // (see tool/sheshbesh_ai_duel.dart), so this only ever re-tested the
  // sequential engine. They have been removed to stop implying otherwise.
  //
  // Genuine concurrent OVERTIME coverage (both colours live on one shared
  // board, conservation asserted across the dual-live window) lives in
  // test/local_game_controller_overtime_conservation_test.dart.
  test(
    'sheshbesh ai duel sequential run has no invariant failures',
    () async {
      await duel.main(<String>[
        '--games=8',
        '--seed=20260304',
        '--max-turns=1125',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
