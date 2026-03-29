import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final config = _Config.parse(args);
  final rootPath = config.runId == null
      ? config.rootPath
      : '${config.rootPath}${Platform.pathSeparator}${config.runId}';
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    if (config.allowEmpty) {
      stdout.writeln(
        'Replay artifact root does not exist, skipping: $rootPath',
      );
      return;
    }
    stderr.writeln('Replay artifact root does not exist: $rootPath');
    exit(1);
  }

  final traces = <File>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.jsonl')) {
      if (entity.lengthSync() == 0) {
        continue;
      }
      traces.add(entity);
    }
  }
  traces.sort((a, b) => a.path.compareTo(b.path));

  if (traces.isEmpty) {
    if (config.allowEmpty) {
      stdout.writeln('No replay traces found under $rootPath');
      return;
    }
    stderr.writeln('No replay traces found under $rootPath');
    exit(1);
  }

  final errors = <String>[];
  for (final trace in traces) {
    final summaryPath = _summaryPathForTrace(trace.path);
    final summaryFile = File(summaryPath);
    if (!summaryFile.existsSync()) {
      errors.add('Missing summary for trace: ${trace.path}');
      continue;
    }

    Map<String, Object?> summary;
    try {
      final decoded = jsonDecode(summaryFile.readAsStringSync());
      summary = _asStringKeyedMap(decoded);
    } catch (error) {
      errors.add('Invalid summary JSON: $summaryPath ($error)');
      continue;
    }

    _requireField(summary, 'commit_sha', summaryPath, errors);
    _requireField(summary, 'workflow_run_id', summaryPath, errors);
    _requireField(summary, 'seed', summaryPath, errors);
    _requireField(summary, 'run_id', summaryPath, errors);
    _requireField(summary, 'trace_path', summaryPath, errors);
    _requireField(summary, 'state_hash_before', summaryPath, errors);
    _requireField(summary, 'state_hash_after', summaryPath, errors);

    final tracePathField = summary['trace_path'];
    if (_isPresent(tracePathField)) {
      final canonicalExpected = _canonicalPath(trace.path);
      final canonicalActual = _canonicalPath(tracePathField.toString());
      if (canonicalExpected != canonicalActual) {
        errors.add(
          'trace_path mismatch in $summaryPath '
          '(expected: $canonicalExpected, actual: $canonicalActual)',
        );
      }
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Replay artifact verification failed:');
    for (final error in errors) {
      stderr.writeln('- $error');
    }
    exit(1);
  }

  stdout.writeln(
    'Verified ${traces.length} replay trace summaries under $rootPath',
  );
}

void _requireField(
  Map<String, Object?> summary,
  String key,
  String summaryPath,
  List<String> errors,
) {
  final value = summary[key];
  if (!_isPresent(value)) {
    errors.add('Missing required field "$key" in $summaryPath');
    return;
  }
  if (value is String && value.trim().toLowerCase() == 'unknown') {
    errors.add('Field "$key" is unknown in $summaryPath');
  }
}

bool _isPresent(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is String) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed == 'null' || trimmed == 'missing' || trimmed == 'none') {
      return false;
    }
    return true;
  }
  return true;
}

String _summaryPathForTrace(String tracePath) {
  final traceFile = File(tracePath);
  final fileName = _fileName(traceFile.path);
  final stem = fileName.toLowerCase().endsWith('.jsonl')
      ? fileName.substring(0, fileName.length - 6)
      : fileName;
  return '${traceFile.parent.path}${Platform.pathSeparator}$stem.summary.json';
}

String _canonicalPath(String path) {
  return File(path).absolute.path.replaceAll('\\', '/').toLowerCase();
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index < 0 || index == normalized.length - 1) {
    return normalized;
  }
  return normalized.substring(index + 1);
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

class _Config {
  const _Config({required this.rootPath, required this.allowEmpty, this.runId});

  final String rootPath;
  final String? runId;
  final bool allowEmpty;

  static _Config parse(List<String> args) {
    var rootPath = 'artifacts/bughunt';
    String? runId;
    var allowEmpty = true;

    for (final arg in args) {
      if (arg.startsWith('--root=')) {
        rootPath = arg.substring('--root='.length).trim();
        continue;
      }
      if (arg.startsWith('--run-id=')) {
        runId = arg.substring('--run-id='.length).trim();
        continue;
      }
      if (arg == '--allow-empty') {
        allowEmpty = true;
        continue;
      }
      if (arg == '--no-allow-empty') {
        allowEmpty = false;
        continue;
      }
      if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      }
      throw ArgumentError('Unknown argument: $arg');
    }

    return _Config(rootPath: rootPath, runId: runId, allowEmpty: allowEmpty);
  }
}

Never _printUsageAndExit() {
  stdout.writeln(
    'Usage: flutter pub run tool/verify_replay_artifacts.dart '
    '[--root=artifacts/bughunt] [--run-id=<id>] [--allow-empty|--no-allow-empty]',
  );
  exit(0);
}
