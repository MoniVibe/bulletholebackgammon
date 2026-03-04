import 'package:flutter_test/flutter_test.dart';

import '../tool/sheshbesh_ai_duel.dart' as duel;

void main() {
  test(
    'sheshbesh ai duel stress run has no failures',
    () async {
      await duel.main(<String>[
        '--games=8',
        '--seed=20260304',
        '--cooldown-ms=120',
        '--ai-think-min-ms=12',
        '--ai-think-max-ms=24',
        '--step-ms=8',
        '--max-game-ms=45000',
        '--max-stall-ms=2200',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
