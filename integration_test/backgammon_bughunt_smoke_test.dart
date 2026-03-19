import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bulletholebackgammon/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bughunt smoke emits structured logs', (tester) async {
    await binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => binding.setSurfaceSize(null));

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
      await tester.pump(const Duration(milliseconds: 400));
    }

    final artifactRoot = Directory('artifacts/bughunt');
    expect(artifactRoot.existsSync(), isTrue);

    final files = artifactRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jsonl'))
        .toList(growable: false);
    expect(files, isNotEmpty);

    final hasStructuredEvent = files.any((file) {
      final lines = file.readAsLinesSync();
      return lines.any(
        (line) =>
            line.contains('"schemaVersion"') && line.contains('"eventType"'),
      );
    });
    expect(hasStructuredEvent, isTrue);
  });
}
