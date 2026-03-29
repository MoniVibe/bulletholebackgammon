import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final config = _Config.parse(args);
  final traces = _resolveTraces(config);
  if (traces.isEmpty) {
    stderr.writeln('No JSONL traces found.');
    exit(1);
  }

  var hadFailure = false;
  for (final trace in traces) {
    try {
      final summary = _buildSummary(trace: trace, config: config);
      final outputPath = config.tracePath != null && config.outputPath != null
          ? config.outputPath!
          : _summaryPathForTrace(trace.path);
      final outputFile = File(outputPath);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
      stdout.writeln('Wrote replay summary: ${outputFile.path}');
    } catch (error) {
      hadFailure = true;
      stderr.writeln('Failed to summarize ${trace.path}: $error');
    }
  }

  if (hadFailure) {
    exit(1);
  }
}

Map<String, Object?> _buildSummary({
  required File trace,
  required _Config config,
}) {
  final lines = trace.readAsLinesSync();
  if (lines.isEmpty) {
    throw StateError('Trace is empty: ${trace.path}');
  }

  String? commitSha = _firstEnv(<String>['BULLETHOLE_COMMIT_SHA', 'GITHUB_SHA']);
  String? workflowRunId = _firstEnv(<String>['GITHUB_RUN_ID']);
  int? seed = config.seed;
  String? runId = config.runId;
  String? terminalResult;
  String? terminalStatus;
  String? winner;
  String? failureType;
  String? currentPlayerAtFailure;
  int? failureIndex;
  int? failureTurn;
  Map<String, Object?> latestMovePayload = <String, Object?>{};

  String? previousStateHash;
  String? lastStateHash;
  String? stateHashBeforeFailure;
  String? stateHashAfterFailure;

  var eventCount = 0;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      continue;
    }
    final decoded = jsonDecode(line);
    final event = _asStringKeyedMap(decoded);
    eventCount += 1;

    final payload = _asStringKeyedMap(event['payload']);
    final eventType = _pickString(event, <String>[
          'eventType',
          'event_type',
          'event',
        ]) ??
        _pickString(payload, <String>['eventType', 'event_type', 'event']);
    final severity = _pickString(event, <String>['severity']) ??
        _pickString(payload, <String>['severity']);

    commitSha ??= _pickString(event, <String>[
      'appVersionOrCommitSha',
      'app_version_or_commit_sha',
      'commit_sha',
    ]);
    commitSha ??= _pickString(payload, <String>['commit_sha']);

    workflowRunId ??= _pickString(event, <String>[
      'workflowRunId',
      'workflow_run_id',
    ]);
    workflowRunId ??= _pickString(payload, <String>['workflow_run_id']);

    seed ??= _pickInt(event, <String>['seed']) ?? _pickInt(payload, <String>['seed']);
    runId ??= _pickString(event, <String>['runId', 'run_id']) ??
        _pickString(payload, <String>['runId', 'run_id']);

    terminalResult ??= _pickString(payload, <String>['result', 'terminalResult']);
    terminalResult ??= _pickString(event, <String>['result', 'terminalResult']);
    terminalStatus ??=
        _pickString(payload, <String>['status', 'terminalStatus']) ??
            _pickString(event, <String>['status', 'terminalStatus']);
    winner ??= _pickString(payload, <String>['winner', 'winnerColor']) ??
        _pickString(event, <String>['winner', 'winnerColor']);

    final stateHash = _pickString(event, <String>['stateHash', 'state_hash']) ??
        _pickString(payload, <String>[
          'stateHash',
          'state_hash',
          'relayStateHash',
        ]);
    if (_isPresentString(stateHash)) {
      previousStateHash = lastStateHash;
      lastStateHash = stateHash;
    }

    final movePayload = _extractMovePayload(payload);
    if (movePayload.isNotEmpty) {
      latestMovePayload = movePayload;
    }

    final isFailure = _isFailureEvent(eventType: eventType, severity: severity);
    if (isFailure && failureType == null) {
      failureType = eventType ?? 'unknown_failure';
      failureIndex = _pickInt(event, <String>[
        'actionIndexOrPlyIndex',
        'action_index_or_ply_index',
      ]);
      failureTurn =
          _pickInt(event, <String>['turnIndex', 'turn_index']) ??
              _pickInt(payload, <String>['turnIndex', 'turn_index']);
      currentPlayerAtFailure = _pickString(payload, <String>[
            'turnColor',
            'actorColor',
            'color',
            'turn',
            'currentPlayer',
          ]) ??
          _pickString(event, <String>[
            'turnColor',
            'actorColor',
            'color',
            'turn',
          ]);
      stateHashBeforeFailure = previousStateHash ?? lastStateHash;
      stateHashAfterFailure = stateHash ?? lastStateHash;
    }
  }

  final tracePath = trace.absolute.path;
  final summary = <String, Object?>{
    'summary_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'commit_sha': commitSha,
    'workflow_run_id': workflowRunId,
    'seed': seed,
    'run_id': runId,
    'trace_path': tracePath,
    'state_hash_before': stateHashBeforeFailure ?? previousStateHash,
    'state_hash_after': stateHashAfterFailure ?? lastStateHash,
    'failure_type': failureType ?? 'none',
    'action_index_or_ply_index': failureIndex,
    'turn_index': failureTurn,
    'current_player': currentPlayerAtFailure,
    'latest_move_payload': latestMovePayload,
    'terminal_result': terminalResult,
    'terminal_status': terminalStatus,
    'winner': winner,
    'event_count': eventCount,
  };
  return summary;
}

List<File> _resolveTraces(_Config config) {
  if (config.tracePath != null) {
    return <File>[File(config.tracePath!)];
  }
  final rootPath = config.runId != null
      ? '${config.rootPath}${Platform.pathSeparator}${config.runId}'
      : config.rootPath;
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    return const <File>[];
  }

  final traces = <File>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    if (!entity.path.toLowerCase().endsWith('.jsonl')) {
      continue;
    }
    traces.add(entity);
  }
  traces.sort((a, b) => a.path.compareTo(b.path));
  return traces;
}

String _summaryPathForTrace(String tracePath) {
  final traceFile = File(tracePath);
  final fileName = _fileName(traceFile.path);
  final stem = fileName.toLowerCase().endsWith('.jsonl')
      ? fileName.substring(0, fileName.length - 6)
      : fileName;
  return '${traceFile.parent.path}${Platform.pathSeparator}$stem.summary.json';
}

Map<String, Object?> _extractMovePayload(Map<String, Object?> payload) {
  final out = <String, Object?>{};

  void copyIfPresent(String key) {
    final value = payload[key];
    if (value != null) {
      out[key] = value;
    }
  }

  copyIfPresent('move');
  copyIfPresent('from');
  copyIfPresent('to');
  copyIfPresent('promotion');
  copyIfPresent('die');
  copyIfPresent('dice');
  copyIfPresent('diceRemaining');
  copyIfPresent('action');

  return out;
}

bool _isFailureEvent({String? eventType, String? severity}) {
  if (_isPresentString(severity) && severity!.toLowerCase() == 'error') {
    return true;
  }
  if (!_isPresentString(eventType)) {
    return false;
  }
  final normalized = eventType!.toLowerCase();
  return normalized.contains('invariant_failure') ||
      normalized.contains('action_rejected') ||
      normalized.contains('crash') ||
      normalized.contains('fatal') ||
      normalized.contains('server_error') ||
      normalized.contains('engine_state_error') ||
      normalized.contains('conversion_failure');
}

Map<String, Object?> _asStringKeyedMap(dynamic raw) {
  if (raw is! Map) {
    return <String, Object?>{};
  }
  final map = <String, Object?>{};
  raw.forEach((dynamic key, dynamic value) {
    map[key.toString()] = value;
  });
  return map;
}

String? _pickString(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) {
      continue;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
      continue;
    }
    return value.toString();
  }
  return null;
}

int? _pickInt(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) {
      continue;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

String? _firstEnv(List<String> names) {
  for (final name in names) {
    final value = Platform.environment[name];
    if (_isPresentString(value)) {
      return value!.trim();
    }
  }
  return null;
}

bool _isPresentString(String? value) {
  return value != null && value.trim().isNotEmpty;
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index < 0 || index == normalized.length - 1) {
    return normalized;
  }
  return normalized.substring(index + 1);
}

class _Config {
  const _Config({
    required this.rootPath,
    this.tracePath,
    this.outputPath,
    this.runId,
    this.seed,
  });

  final String rootPath;
  final String? tracePath;
  final String? outputPath;
  final String? runId;
  final int? seed;

  static _Config parse(List<String> args) {
    var rootPath = 'artifacts/bughunt';
    String? tracePath;
    String? outputPath;
    String? runId;
    int? seed;

    for (final arg in args) {
      if (arg.startsWith('--trace=')) {
        tracePath = arg.substring('--trace='.length).trim();
        continue;
      }
      if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
        continue;
      }
      if (arg.startsWith('--run-id=')) {
        runId = arg.substring('--run-id='.length).trim();
        continue;
      }
      if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
        continue;
      }
      if (arg.startsWith('--root=')) {
        rootPath = arg.substring('--root='.length).trim();
        continue;
      }
      if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      }
      throw ArgumentError('Unknown argument: $arg');
    }

    if (tracePath == null && runId == null) {
      throw ArgumentError('Provide --trace=<path> or --run-id=<id>.');
    }
    if (tracePath == null && outputPath != null) {
      throw ArgumentError('--output is only valid with --trace.');
    }

    return _Config(
      rootPath: rootPath,
      tracePath: tracePath,
      outputPath: outputPath,
      runId: runId,
      seed: seed,
    );
  }
}

Never _printUsageAndExit() {
  stdout.writeln(
    'Usage: flutter pub run tool/replay.dart '
    '--run-id=<id> [--root=artifacts/bughunt]\n'
    '   or: flutter pub run tool/replay.dart --trace=<path> '
    '[--output=<path>] [--seed=<seed>] [--run-id=<id>]',
  );
  exit(0);
}
