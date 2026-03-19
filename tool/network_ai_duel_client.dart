// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final config = _Config.parse(args);
  final logger = _JsonlLogger(
    path: config.logFilePath,
    runId: config.runId,
    role: config.role,
    seed: config.seed,
  );

  final httpClient = http.Client();
  final transport = MultiplayerTransportClient(
    httpClient: httpClient,
    requestTimeout: const Duration(seconds: 10),
  );

  final session = _BackgammonNetworkSession(
    config: config,
    transport: transport,
    logger: logger,
  );

  try {
    await session.run();
  } finally {
    await transport.disconnect();
    transport.dispose();
    httpClient.close();
    await logger.close();
  }
}

class _BackgammonNetworkSession {
  _BackgammonNetworkSession({
    required this.config,
    required this.transport,
    required this.logger,
  });

  final _Config config;
  final MultiplayerTransportClient transport;
  final _JsonlLogger logger;

  final Completer<void> _done = Completer<void>();
  Timer? _watchdog;
  bool _disposed = false;
  String? _matchId;

  Future<void> run() async {
    await logger.log(<String, Object?>{
      'event': 'app_start',
      'backendUrl': config.backendUrl,
      'name': config.displayName,
      'cooldownSeconds': config.cooldownSeconds,
    });

    final joined = await transport.joinMatch(
      apiBaseUrl: config.backendUrl,
      displayName: config.displayName,
      pieceSkinId: 'bg_ruby',
      cooldownSeconds: config.cooldownSeconds,
      gameType: 'backgammon',
      metadata: <String, dynamic>{'client': 'network_ai_duel'},
    );
    _matchId = joined.matchId;
    await logger.log(<String, Object?>{
      'event': 'session_joined',
      'matchId': joined.matchId,
      'playerId': joined.playerId,
      'wsPath': joined.wsPath,
    });

    await transport.connectSocket(
      baseUri: joined.baseUri,
      wsPath: joined.wsPath,
      matchId: joined.matchId,
      playerId: joined.playerId,
      onMessage: _onMessage,
      onError: (Object error) => _finishWithError('WebSocket error: $error'),
      onDone: () {
        if (_disposed || _done.isCompleted) {
          return;
        }
        _finish();
      },
    );

    transport.sendJson(<String, dynamic>{'type': 'new_game'});
    await logger.log(<String, Object?>{
      'event': 'action_launched',
      'action': 'new_game',
      'matchId': joined.matchId,
    });

    _watchdog = Timer(Duration(seconds: config.maxSeconds), () {
      if (_done.isCompleted) {
        return;
      }
      _finishWithError('Timed out waiting for terminal result.');
    });

    await _done.future;
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      return;
    }

    final map = MultiplayerClientUtils.decodeJsonMap(raw);
    final type = map['type'] as String?;
    if (type == null) {
      return;
    }

    switch (type) {
      case 'welcome':
        logger.log(<String, Object?>{
          'event': 'session_joined',
          'matchId': map['matchId'] ?? _matchId,
          'myColor': map['color'],
        });
        return;
      case 'state':
        final state = Map<String, dynamic>.from(map);
        final history = state['history'];
        final historyLen = history is List ? history.length : 0;
        logger.log(<String, Object?>{
          'event': 'state_snapshot',
          'matchId': map['matchId'] ?? _matchId,
          'status': state['status'],
          'result': state['result'],
          'turn': state['turn'],
          'sequence': state['sequence'],
          'historyLen': historyLen,
        });
        final result = state['result'] as String?;
        if (result != null && result.trim().isNotEmpty) {
          logger.log(<String, Object?>{
            'event': 'session_complete',
            'matchId': map['matchId'] ?? _matchId,
            'result': result,
          });
          _finish();
        }
        return;
      case 'opponent_left':
        logger.log(<String, Object?>{
          'event': 'disconnect',
          'matchId': map['matchId'] ?? _matchId,
          'reason': map['message'] ?? 'opponent_left',
        });
        return;
      case 'error':
        final code = map['code']?.toString();
        logger.log(<String, Object?>{
          'event': _classifyServerErrorEvent(code),
          'matchId': map['matchId'] ?? _matchId,
          'failureCode': code ?? 'SERVER_ERROR',
          'message': map['message'] ?? 'Server error',
        });
        return;
      default:
        logger.log(<String, Object?>{'event': type, 'matchId': _matchId});
        return;
    }
  }

  void _finishWithError(String message) {
    logger.log(<String, Object?>{
      'event': 'crash',
      'matchId': _matchId,
      'message': message,
    });
    if (!_done.isCompleted) {
      _done.completeError(StateError(message));
    }
    _dispose();
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
    _dispose();
  }

  void _dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _watchdog?.cancel();
  }

  String _classifyServerErrorEvent(String? codeRaw) {
    final code = codeRaw?.trim().toLowerCase() ?? '';
    const recoverableCodes = <String>{
      'stale_state',
      'cooldown_active',
      'not_your_turn',
      'invalid_move',
      'illegal_move',
      'queue_rejected',
      'queue_conflict',
    };
    if (recoverableCodes.contains(code)) {
      return 'action_rejected';
    }
    return 'invariant_failure';
  }
}

class _JsonlLogger {
  _JsonlLogger({
    required this.path,
    required this.runId,
    required BughuntRole role,
    required this.seed,
  }) : _file = File(path),
       _sessionId = 'bg_${_timestamp()}_$pid',
       _role = role {
    final parent = _file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
  }

  final String path;
  final String runId;
  final BughuntRole _role;
  final int seed;
  final File _file;
  final String _sessionId;
  final BughuntStateHasher _stateHasher = const BughuntStateHasher();
  Future<void> _pending = Future<void>.value();
  int _logicalTick = 0;

  Future<void> log(Map<String, Object?> event) async {
    _logicalTick += 1;
    final eventTypeRaw = event['event']?.toString() ?? 'state_snapshot';
    final eventType = _eventType(eventTypeRaw);
    final historyLen = MultiplayerClientUtils.readInt(event['historyLen']) ?? 0;
    final severity = _severity(eventTypeRaw);
    final payload = <String, Object?>{...event};
    if (eventType == 'state_snapshot') {
      final hash = _stateHasher.hashSnapshot(payload);
      payload['stateHash'] = hash.value;
      payload['stateHashAlgorithm'] = hash.algorithm;
      payload['snapshotHashValid'] = true;
    }
    final sessionEvent = SessionEvent(
      schemaVersion: bughuntSchemaVersion,
      runId: runId,
      sessionId: _sessionId,
      game: 'backgammon',
      mode: BughuntMode.online,
      role: _role,
      appVersionOrCommitSha: Platform.environment['BULLETHOLE_COMMIT_SHA'],
      roomIdOrMatchId: event['matchId']?.toString(),
      seed: seed,
      maxTurns: null,
      deviceInfo: <String, Object?>{
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'pid': pid,
      },
      logicalTick: _logicalTick,
      wallClockTs: DateTime.now().toUtc().toIso8601String(),
      turnIndex: (historyLen ~/ 2) + 1,
      actionIndexOrPlyIndex: historyLen,
      eventType: eventType,
      payload: payload,
      severity: severity,
    );

    _pending = _pending.then((_) async {
      try {
        await _file.writeAsString(
          sessionEventToJsonLine(sessionEvent),
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Logging should never crash the runner.
      }
    });
    await _pending;
  }

  Future<void> close() async {
    await _pending;
  }

  String _eventType(String eventType) {
    final normalized = eventType.toLowerCase();
    if (normalized == 'app_start') {
      return 'app_start';
    }
    if (normalized == 'session_joined' || normalized == 'welcome') {
      return 'session_joined';
    }
    if (normalized == 'state_snapshot' || normalized == 'state') {
      return 'state_snapshot';
    }
    if (normalized == 'action_rejected' || normalized.contains('rejected')) {
      return 'action_rejected';
    }
    if (normalized == 'invariant_failure' || normalized == 'error') {
      return 'invariant_failure';
    }
    if (normalized == 'disconnect' || normalized.contains('left')) {
      return 'disconnect';
    }
    if (normalized == 'session_complete') {
      return 'session_complete';
    }
    if (normalized == 'crash') {
      return 'crash';
    }
    if (normalized.contains('action')) {
      return 'action_launched';
    }
    return eventType;
  }

  BughuntSeverity _severity(String eventType) {
    final normalized = eventType.toLowerCase();
    if (normalized.contains('crash') ||
        normalized.contains('error') ||
        normalized.contains('invariant')) {
      return BughuntSeverity.error;
    }
    if (normalized.contains('warn')) {
      return BughuntSeverity.warn;
    }
    return BughuntSeverity.info;
  }
}

class _Config {
  const _Config({
    required this.backendUrl,
    required this.displayName,
    required this.cooldownSeconds,
    required this.seed,
    required this.maxSeconds,
    required this.logFilePath,
    required this.runId,
    required this.role,
  });

  final String backendUrl;
  final String displayName;
  final int cooldownSeconds;
  final int seed;
  final int maxSeconds;
  final String logFilePath;
  final String runId;
  final BughuntRole role;

  static _Config parse(List<String> args) {
    var backendUrl = 'http://localhost:8080';
    var displayName = 'BackgammonAI-${pid.toString().padLeft(5, '0')}';
    var cooldownSeconds = 3;
    var seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    var maxSeconds = 120;
    String? logFilePath;
    String? runId;
    var role = BughuntRole.client;

    for (final arg in args) {
      if (arg.startsWith('--backend-url=')) {
        backendUrl = arg.substring('--backend-url='.length).trim();
        continue;
      }
      if (arg.startsWith('--name=')) {
        displayName = arg.substring('--name='.length).trim();
        continue;
      }
      if (arg.startsWith('--cooldown-seconds=')) {
        cooldownSeconds = int.parse(
          arg.substring('--cooldown-seconds='.length),
        );
        continue;
      }
      if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
        continue;
      }
      if (arg.startsWith('--max-seconds=')) {
        maxSeconds = int.parse(arg.substring('--max-seconds='.length));
        continue;
      }
      if (arg.startsWith('--log-file=')) {
        logFilePath = arg.substring('--log-file='.length).trim();
        continue;
      }
      if (arg.startsWith('--run-id=')) {
        runId = arg.substring('--run-id='.length).trim();
        continue;
      }
      if (arg.startsWith('--role=')) {
        final parsed = parseBughuntRole(arg.substring('--role='.length).trim());
        if (parsed != null) {
          role = parsed;
        }
        continue;
      }
      if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      }
      throw ArgumentError('Unknown argument: $arg');
    }

    logFilePath ??=
        'debug/network-ai-backgammon-${displayName.toLowerCase()}-${_timestamp()}.jsonl';
    runId ??= 'bgnet_${_timestamp()}';

    return _Config(
      backendUrl: backendUrl,
      displayName: displayName,
      cooldownSeconds: cooldownSeconds,
      seed: seed,
      maxSeconds: maxSeconds,
      logFilePath: logFilePath,
      runId: runId,
      role: role,
    );
  }
}

String _timestamp() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final ss = now.second.toString().padLeft(2, '0');
  return '$y$m$d-$hh$mm$ss';
}

Never _printUsageAndExit() {
  print(
    'Usage: dart run tool/network_ai_duel_client.dart '
    '[--backend-url=http://localhost:8080] [--name=BackgammonAI-A] '
    '[--cooldown-seconds=3] [--seed=123] [--max-seconds=120] '
    '[--log-file=debug/backgammon-network.jsonl] [--run-id=id] [--role=host|client]',
  );
  exit(0);
}
