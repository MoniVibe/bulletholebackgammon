import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bulletholebackgammon/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures baseline perf artifacts for bughunt flow', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => binding.setSurfaceSize(null));

    await binding.traceAction(() async {
      app.main();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      final startLabel = find.text('Start New Game');
      if (startLabel.evaluate().isNotEmpty) {
        await tester.tap(startLabel.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }

      final playWhite = find.text('Play White');
      if (playWhite.evaluate().isNotEmpty) {
        await tester.tap(playWhite.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 700));
      }
    }, reportKey: 'backgammon_bughunt_perf_timeline');

    final perfDir = Directory('artifacts/bughunt/perf/backgammon');
    if (!perfDir.existsSync()) {
      perfDir.createSync(recursive: true);
    }

    final timelineFile = File(
      '${perfDir.path}${Platform.pathSeparator}backgammon_bughunt_perf_timeline.json',
    );
    final summaryFile = File(
      '${perfDir.path}${Platform.pathSeparator}backgammon_bughunt_perf_summary.json',
    );
    final timeline =
        binding.reportData?['backgammon_bughunt_perf_timeline']
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final traceEvents = (timeline['traceEvents'] as List?) ?? const <Object?>[];
    final summary = <String, Object?>{
      'traceEventCount': traceEvents.length,
      'containsFrameBuild': traceEvents.any(
        (event) =>
            event is Map &&
            (event['name']?.toString().toLowerCase().contains('frame') ??
                false),
      ),
      'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
    };
    timelineFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(timeline),
    );
    summaryFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );

    expect(summaryFile.existsSync(), isTrue);
  });
}
