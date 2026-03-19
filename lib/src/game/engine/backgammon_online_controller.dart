import 'dart:async';
import 'dart:io';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Transport-only online controller for backgammon.
///
/// Reasoning:
/// - Keeps matchmaking/network/session concerns isolated from rules/playability.
/// - Allows gameplay logic to be plugged in later without rewriting transport.
/// - Preserves compatibility with the current shared realtime endpoint contract.
class BackgammonOnlineController extends ChangeNotifier {
  static const String _defaultPieceSkinId = 'bg_royal';
  static const Duration _defaultHealthTimeout = Duration(seconds: 5);
  static const Duration _defaultWakeTimeout = Duration(seconds: 15);
  static const int _maxDebugLogEntries = 400;

  BackgammonOnlineController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    http.Client? httpClient,
    DateTime Function()? nowProvider,
  }) : _cooldownDuration = initialCooldownDuration,
       _now = nowProvider ?? DateTime.now {
    _httpClient = httpClient ?? http.Client();
    _ownsHttpClient = httpClient == null;
    _transportClient = MultiplayerTransportClient(
      httpClient: _httpClient,
      requestTimeout: _defaultHealthTimeout,
    );
    _backendHealthChecker = BackendHealthChecker(
      httpClient: _httpClient,
      defaultTimeout: _defaultHealthTimeout,
      wakeTimeout: _defaultWakeTimeout,
    );
    final now = _now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
    _sessionLogger.beginSession(
      sessionLabel: 'controller_boot',
      context: <String, Object?>{
        'cooldownSeconds': _cooldownDuration.inSeconds,
      },
    );
    _sessionLogger.logEvent('controller_initialized');
  }

  late final Timer _ticker;
  late final http.Client _httpClient;
  late final bool _ownsHttpClient;
  late final BackendHealthChecker _backendHealthChecker;
  late final MultiplayerTransportClient _transportClient;
  final DateTime Function() _now;

  OnlineConnectionState _connectionState = OnlineConnectionState.disconnected;
  BackendHealthState _backendHealthState = BackendHealthState.unknown;
  Duration _cooldownDuration;
  int _sequence = 0;
  int _clockOffsetMs = 0;
  int _whiteReadyAtMs = 0;
  int _blackReadyAtMs = 0;
  bool _disposed = false;

  String? _backendHealthMessage;
  DateTime? _backendHealthCheckedAt;
  String? _feedback;
  String? _matchId;
  String? _myColor;
  String _status = 'disconnected';
  String? _result;
  String? _turnColor;
  String? _whitePlayerName;
  String? _blackPlayerName;
  String _myPieceSkinId = _defaultPieceSkinId;
  final Map<String, String> _pieceSkinByColor = <String, String>{
    'w': _defaultPieceSkinId,
    'b': _defaultPieceSkinId,
  };
  final List<String> _history = <String>[];
  Map<String, dynamic>? _latestState;
  final List<String> _debugLogEntries = <String>[];
  final GameSessionLogger _sessionLogger = GameSessionLogger(
    applicationId: 'bulletholebackgammon',
    gameId: 'backgammon',
    mode: 'online',
  );

  OnlineConnectionState get connectionState => _connectionState;
  BackendHealthState get backendHealthState => _backendHealthState;
  String? get backendHealthMessage => _backendHealthMessage;
  DateTime? get backendHealthCheckedAt => _backendHealthCheckedAt;
  Duration get cooldownDuration => _cooldownDuration;
  String? get feedback => _feedback;
  String? get matchId => _matchId;
  String? get myColor => _myColor;
  bool get isConnected => _connectionState == OnlineConnectionState.connected;
  bool get isMatchActive => _status == 'active';
  bool get isWaitingForOpponent => _status == 'waiting';
  bool get hasActiveGame => _status == 'active';
  bool get isGameOver => _result != null;
  String? get resultCode => _result;
  String? get turnColor => _turnColor;
  String? get whitePlayerName => _whitePlayerName;
  String? get blackPlayerName => _blackPlayerName;
  String get myPieceSkinId => _myPieceSkinId;
  List<String> get history => List.unmodifiable(_history);
  Map<String, dynamic>? get latestState => _latestState == null
      ? null
      : Map<String, dynamic>.unmodifiable(_latestState!);
  List<String> get debugLogEntries =>
      List.unmodifiable(_debugLogEntries.reversed.toList(growable: false));

  String pieceSkinIdForColor(String color) {
    return _pieceSkinByColor[color] ?? _defaultPieceSkinId;
  }

  String get statusText {
    if (_connectionState == OnlineConnectionState.disconnected) {
      return 'Not connected.';
    }
    if (_connectionState == OnlineConnectionState.connecting) {
      return 'Connecting...';
    }
    if (_status == 'waiting') {
      return 'Connected. Waiting for another player...';
    }
    if (_status == 'active') {
      final color = _myColor;
      if (color == null) {
        return 'Match active. Waiting for color assignment...';
      }
      final myRemaining = cooldownRemaining(color);
      if (myRemaining.inMilliseconds > 0) {
        return 'Connected. Cooldown ${_formatDuration(myRemaining)}.';
      }
      return 'Connected. Ready for actions.';
    }
    if (_status == 'finished') {
      return 'Match finished. Start a rematch.';
    }
    return 'Connected.';
  }

  Duration cooldownRemaining(String color) {
    final now = _estimatedServerNowMs();
    final readyAt = color == 'w' ? _whiteReadyAtMs : _blackReadyAtMs;
    final remaining = readyAt - now;
    if (remaining <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remaining);
  }

  String buildDebugReport({int maxEntries = 250}) {
    final header = <String>[
      'Bullethole Backgammon Debug Report',
      'generatedAt=${_now().toIso8601String()}',
      'connectionState=${_connectionState.name}',
      'matchId=${_matchId ?? '-'}',
      'status=$_status',
      'myColor=${_myColor ?? '-'}',
      'turn=${_turnColor ?? '-'}',
      'result=${_result ?? '-'}',
      'cooldownSeconds=${_cooldownDuration.inSeconds}',
      'cooldownRemainingWMs=${cooldownRemaining('w').inMilliseconds}',
      'cooldownRemainingBMs=${cooldownRemaining('b').inMilliseconds}',
      'historyLen=${_history.length}',
      'latestStateKeys=${_latestState?.keys.length ?? 0}',
      '--- events ---',
    ];
    final start = _debugLogEntries.length > maxEntries
        ? _debugLogEntries.length - maxEntries
        : 0;
    final lines = _debugLogEntries.sublist(start);
    return <String>[...header, ...lines].join('\n');
  }

  void clearDebugLog() {
    _debugLogEntries.clear();
    notifyListeners();
  }

  void setMyPieceSkin(String skinId) {
    final normalizedSkinId = MultiplayerClientUtils.sanitizeIdentifier(skinId);
    if (normalizedSkinId == null || normalizedSkinId == _myPieceSkinId) {
      return;
    }

    _myPieceSkinId = normalizedSkinId;
    final myColor = _myColor;
    if (myColor != null) {
      _pieceSkinByColor[myColor] = normalizedSkinId;
    } else {
      _pieceSkinByColor['w'] = normalizedSkinId;
      _pieceSkinByColor['b'] = normalizedSkinId;
    }

    if (isConnected) {
      _send(<String, dynamic>{
        'type': 'set_piece_skin',
        'pieceSkinId': normalizedSkinId,
      });
      _logEvent(
        'piece_skin_update_sent',
        details: <String, Object?>{
          'pieceSkinId': normalizedSkinId,
          'myColor': _myColor,
        },
      );
    }
    notifyListeners();
  }

  Future<void> findMatch({
    required String apiBaseUrl,
    required String displayName,
    int? cooldownSeconds,
  }) async {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      _logEvent('matchmaking_missing_name');
      _feedback = 'Display name is required.';
      notifyListeners();
      return;
    }

    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    _logEvent(
      'matchmaking_start',
      details: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'name': normalizedName,
        'cooldownSeconds': cooldownSeconds,
        'pieceSkinId': _myPieceSkinId,
      },
    );
    _sessionLogger.beginSession(
      sessionLabel: 'find_match',
      context: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'displayName': normalizedName,
        'cooldownSeconds': cooldownSeconds,
      },
    );
    notifyListeners();

    try {
      final joined = await _transportClient.joinMatch(
        apiBaseUrl: apiBaseUrl,
        displayName: normalizedName,
        pieceSkinId: _myPieceSkinId,
        cooldownSeconds: cooldownSeconds,
      );
      if (joined.cooldownSeconds != null && joined.cooldownSeconds! > 0) {
        _cooldownDuration = Duration(seconds: joined.cooldownSeconds!);
      }

      await _connectWebSocket(
        baseUri: joined.baseUri,
        wsPath: joined.wsPath,
        matchId: joined.matchId,
        playerId: joined.playerId,
      );
      _sessionLogger.setRoomOrMatchId(joined.matchId);
      _logEvent(
        'matchmaking_success',
        details: <String, Object?>{
          'matchId': joined.matchId,
          'playerId': joined.playerId,
          'cooldownSeconds': _cooldownDuration.inSeconds,
        },
      );
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = _friendlyNetworkError(
        error,
        fallback: 'Matchmaking failed: $error',
      );
      _logEvent(
        'matchmaking_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      notifyListeners();
    }
  }

  void requestNewGame({int? cooldownSeconds}) {
    if (!isConnected) {
      return;
    }
    final payload = <String, dynamic>{'type': 'new_game'};
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      payload['cooldownSeconds'] = cooldownSeconds;
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    _send(payload);
    _logEvent(
      'new_game_requested',
      details: <String, Object?>{
        'cooldownSeconds': cooldownSeconds ?? _cooldownDuration.inSeconds,
      },
    );
  }

  void sendClientAction({
    required String action,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    if (!isConnected || action.trim().isEmpty) {
      return;
    }
    final sanitizedAction = MultiplayerClientUtils.sanitizeIdentifier(action);
    if (sanitizedAction == null) {
      _feedback = 'Invalid action identifier.';
      notifyListeners();
      return;
    }

    final message = <String, dynamic>{'type': sanitizedAction};
    if (payload.isNotEmpty) {
      message['payload'] = payload;
    }
    _send(message);
    _logEvent(
      'custom_action_sent',
      details: <String, Object?>{
        'type': sanitizedAction,
        'payloadKeys': payload.keys.join(','),
      },
    );
  }

  Future<bool> checkBackendHealth({
    required String apiBaseUrl,
    Duration timeout = _defaultHealthTimeout,
  }) async {
    _backendHealthState = BackendHealthState.checking;
    _backendHealthMessage = null;
    _logEvent(
      'backend_health_check_start',
      details: <String, Object?>{'apiBase': apiBaseUrl.trim()},
    );
    notifyListeners();

    final result = await _backendHealthChecker.check(
      apiBaseUrl: apiBaseUrl,
      timeout: timeout,
    );
    _backendHealthState = result.ok
        ? BackendHealthState.healthy
        : BackendHealthState.unhealthy;
    _backendHealthMessage = result.ok ? null : result.message;
    _backendHealthCheckedAt = result.checkedAt;
    _logEvent(
      'backend_health_check_result',
      details: <String, Object?>{
        'ok': result.ok,
        'statusCode': result.statusCode,
        'message': _backendHealthMessage,
      },
    );
    notifyListeners();
    return result.ok;
  }

  Future<bool> wakeBackend({required String apiBaseUrl}) async {
    _backendHealthState = BackendHealthState.checking;
    _backendHealthMessage = 'Requesting backend wake-up...';
    _logEvent(
      'backend_wake_start',
      details: <String, Object?>{'apiBase': apiBaseUrl.trim()},
    );
    notifyListeners();

    final result = await _backendHealthChecker.wake(apiBaseUrl: apiBaseUrl);
    _backendHealthState = result.ok
        ? BackendHealthState.healthy
        : BackendHealthState.unhealthy;
    _backendHealthMessage = result.ok ? null : result.message;
    _backendHealthCheckedAt = result.checkedAt;
    _logEvent(
      'backend_wake_result',
      details: <String, Object?>{
        'ok': result.ok,
        'statusCode': result.statusCode,
        'message': _backendHealthMessage,
      },
    );
    notifyListeners();
    return result.ok;
  }

  Future<int> pullServerDebugLogs({
    required String apiBaseUrl,
    int limit = 120,
  }) async {
    final normalizedLimit = limit.clamp(1, 500);
    _logEvent(
      'server_logs_pull_start',
      details: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'limit': normalizedLimit,
        'matchId': _matchId,
      },
    );

    try {
      final items = await _transportClient.fetchServerDebugLogs(
        apiBaseUrl: apiBaseUrl,
        matchId: _matchId,
        limit: normalizedLimit,
      );
      var appended = 0;
      for (final map in items) {
        _appendServerLogLine(map);
        appended += 1;
      }
      _logEvent(
        'server_logs_pull_success',
        details: <String, Object?>{'appended': appended},
      );
      notifyListeners();
      return appended;
    } catch (error) {
      _logEvent(
        'server_logs_pull_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      notifyListeners();
      return 0;
    }
  }

  Future<void> disconnect({bool notify = true}) async {
    _logEvent(
      'disconnect',
      details: <String, Object?>{
        'matchId': _matchId,
        'connectionState': _connectionState.name,
      },
    );
    await _transportClient.disconnect();

    _connectionState = OnlineConnectionState.disconnected;
    _status = 'disconnected';
    _matchId = null;
    _myColor = null;
    _turnColor = null;
    _result = null;
    _whitePlayerName = null;
    _blackPlayerName = null;
    _history.clear();
    _latestState = null;
    _feedback = null;
    _sequence = 0;
    _clockOffsetMs = 0;
    final now = _now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _sessionLogger.closeSession(
      reason: 'disconnect',
      summary: _sessionSnapshot(),
    );

    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sessionLogger.closeSession(
      reason: 'controller_dispose',
      summary: _sessionSnapshot(),
    );
    _disposed = true;
    _ticker.cancel();
    disconnect(notify: false);
    _transportClient.dispose();
    _backendHealthChecker.dispose();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }

  void _onTick() {
    if (_disposed) {
      return;
    }
    if (_status == 'active') {
      notifyListeners();
    }
  }

  Future<void> _connectWebSocket({
    required Uri baseUri,
    required String wsPath,
    required String matchId,
    required String playerId,
  }) async {
    await disconnect(notify: false);
    _logEvent(
      'ws_connect_start',
      details: <String, Object?>{
        'matchId': matchId,
        'playerId': playerId,
        'wsPath': wsPath,
      },
    );

    try {
      _matchId = matchId;
      final wsUri = await _transportClient.connectSocket(
        baseUri: baseUri,
        wsPath: wsPath,
        matchId: matchId,
        playerId: playerId,
        onMessage: _onMessage,
        onError: (Object error) {
          _feedback = _friendlyNetworkError(
            error,
            fallback: 'Connection error: $error',
          );
          _connectionState = OnlineConnectionState.disconnected;
          _logEvent(
            'ws_stream_error',
            details: <String, Object?>{'error': error.toString()},
          );
          notifyListeners();
        },
        onDone: () {
          _feedback = 'Disconnected from server.';
          _connectionState = OnlineConnectionState.disconnected;
          _logEvent('ws_stream_done');
          notifyListeners();
        },
      );

      _connectionState = OnlineConnectionState.connected;
      _logEvent(
        'ws_connected',
        details: <String, Object?>{'matchId': matchId, 'uri': wsUri.toString()},
      );
      notifyListeners();
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = _friendlyNetworkError(
        error,
        fallback: 'Unable to connect game socket: $error',
      );
      _logEvent(
        'ws_connect_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      notifyListeners();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      _logEvent('ws_message_ignored_non_string');
      return;
    }

    final map = MultiplayerClientUtils.decodeJsonMap(raw);
    final type = map['type'];
    if (type is! String) {
      _logEvent('ws_message_missing_type');
      return;
    }

    switch (type) {
      case 'welcome':
        _applyWelcome(map);
        return;
      case 'state':
        _applyState(map);
        return;
      case 'opponent_left':
        _feedback = map['message'] as String? ?? 'Opponent disconnected.';
        _logEvent(
          'ws_opponent_left',
          details: <String, Object?>{'message': _feedback},
        );
        notifyListeners();
        return;
      case 'error':
        _feedback = map['message'] as String? ?? 'Server error';
        _applyCooldownSnapshotFromPayload(
          payload: map,
          fallbackColor: _myColor,
          fallbackNow: MultiplayerClientUtils.readInt(map['serverNow']),
        );
        _logEvent(
          'ws_error',
          details: <String, Object?>{
            'code': map['code'],
            'message': _feedback,
            'matchId': _matchId,
          },
        );
        notifyListeners();
        return;
      case 'pong':
        _logEvent('ws_pong');
        return;
      default:
        _logEvent(
          'ws_message_unknown_type',
          details: <String, Object?>{'type': type},
        );
        return;
    }
  }

  void _applyWelcome(Map<String, dynamic> map) {
    _connectionState = OnlineConnectionState.connected;
    _matchId = map['matchId'] as String? ?? _matchId;
    _sessionLogger.setRoomOrMatchId(_matchId);
    _myColor = map['color'] as String?;
    _turnColor = map['turn'] as String?;

    final welcomePieceSkinId = MultiplayerClientUtils.sanitizeIdentifier(
      map['pieceSkinId'],
    );
    if (welcomePieceSkinId != null) {
      _myPieceSkinId = welcomePieceSkinId;
      if (_myColor != null) {
        _pieceSkinByColor[_myColor!] = welcomePieceSkinId;
      }
    }

    final welcomeCooldown = MultiplayerClientUtils.readInt(
      map['cooldownSeconds'],
    );
    if (welcomeCooldown != null && welcomeCooldown > 0) {
      _cooldownDuration = Duration(seconds: welcomeCooldown);
    }

    final serverNow = MultiplayerClientUtils.readInt(map['serverNow']);
    if (serverNow != null) {
      _clockOffsetMs = serverNow - _now().millisecondsSinceEpoch;
    }

    _feedback = null;
    _logEvent(
      'ws_welcome',
      details: <String, Object?>{
        'matchId': _matchId,
        'myColor': _myColor,
        'turn': _turnColor,
        'pieceSkinId': _myPieceSkinId,
        'cooldownSeconds': _cooldownDuration.inSeconds,
      },
    );
    notifyListeners();
  }

  void _applyState(Map<String, dynamic> state) {
    final nextSequence = MultiplayerClientUtils.readInt(state['sequence']);
    final normalizedSequence = nextSequence ?? (_sequence + 1);
    if (normalizedSequence < _sequence) {
      _logEvent(
        'state_ignored_outdated',
        details: <String, Object?>{
          'nextSequence': normalizedSequence,
          'currentSequence': _sequence,
        },
      );
      return;
    }
    _sequence = normalizedSequence;

    final serverNow = MultiplayerClientUtils.readInt(state['serverNow']);
    if (serverNow != null) {
      _clockOffsetMs = serverNow - _now().millisecondsSinceEpoch;
    }

    final cooldownSeconds = MultiplayerClientUtils.readInt(
      state['cooldownSeconds'],
    );
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    final cooldownMs = MultiplayerClientUtils.readInt(state['cooldownMs']);
    if ((cooldownSeconds == null || cooldownSeconds <= 0) &&
        cooldownMs != null &&
        cooldownMs > 0) {
      _cooldownDuration = Duration(milliseconds: cooldownMs);
    }

    _applyCooldownSnapshotFromPayload(
      payload: state,
      fallbackColor: null,
      fallbackNow: serverNow,
    );

    _status = state['status'] as String? ?? _status;
    _result = state['result'] as String?;
    _turnColor = state['turn'] as String? ?? _turnColor;

    final players = state['players'];
    if (players is Map) {
      final playersMap = Map<String, dynamic>.from(players);
      _whitePlayerName = playersMap['w'] as String?;
      _blackPlayerName = playersMap['b'] as String?;
    }

    final pieceSkins = state['pieceSkins'];
    if (pieceSkins is Map) {
      final skinMap = Map<String, dynamic>.from(pieceSkins);
      final whiteSkin = MultiplayerClientUtils.sanitizeIdentifier(skinMap['w']);
      final blackSkin = MultiplayerClientUtils.sanitizeIdentifier(skinMap['b']);
      if (whiteSkin != null) {
        _pieceSkinByColor['w'] = whiteSkin;
      }
      if (blackSkin != null) {
        _pieceSkinByColor['b'] = blackSkin;
      }
      final myColor = _myColor;
      if (myColor != null) {
        final mySkin = _pieceSkinByColor[myColor];
        if (mySkin != null) {
          _myPieceSkinId = mySkin;
        }
      }
    }

    _history
      ..clear()
      ..addAll(_extractHistory(state));

    _latestState = Map<String, dynamic>.from(state);
    _feedback = null;
    _logEvent(
      'state_applied',
      details: <String, Object?>{
        'sequence': _sequence,
        'status': _status,
        'turn': _turnColor,
        'result': _result,
        'historyLen': _history.length,
      },
    );
    _sessionLogger.logBughuntEvent(
      'turn_started',
      payload: <String, Object?>{
        'turnColor': _turnColor,
        ..._sessionSnapshot(),
      },
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
    _sessionLogger.recordStateSnapshot(
      _sessionSnapshot(),
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
    notifyListeners();
  }

  void _applyCooldownSnapshotFromPayload({
    required Map<String, dynamic> payload,
    required String? fallbackColor,
    required int? fallbackNow,
  }) {
    var receivedSnapshot = false;
    final cooldownEndsAt = payload['cooldownEndsAt'];
    if (cooldownEndsAt is Map) {
      final cooldownMap = Map<String, dynamic>.from(cooldownEndsAt);
      final w = MultiplayerClientUtils.readInt(cooldownMap['w']);
      final b = MultiplayerClientUtils.readInt(cooldownMap['b']);
      if (w != null) {
        _whiteReadyAtMs = w;
        receivedSnapshot = true;
      }
      if (b != null) {
        _blackReadyAtMs = b;
        receivedSnapshot = true;
      }
    }

    if (receivedSnapshot || fallbackColor == null) {
      return;
    }

    // Compatibility fallback for backends without `cooldownEndsAt`.
    final remainingMs = MultiplayerClientUtils.readInt(payload['remainingMs']);
    if (remainingMs == null || remainingMs <= 0) {
      return;
    }
    final baseNow = fallbackNow ?? _estimatedServerNowMs();
    _setReadyAtForColor(fallbackColor, baseNow + remainingMs);
  }

  List<String> _extractHistory(Map<String, dynamic> state) {
    final rawHistory = state['history'];
    if (rawHistory is! List) {
      return const <String>[];
    }
    return rawHistory
        .map((entry) => entry?.toString() ?? '')
        .where((entry) => entry.trim().isNotEmpty)
        .toList(growable: false);
  }

  void _setReadyAtForColor(String color, int readyAtMs) {
    if (color == 'w') {
      _whiteReadyAtMs = readyAtMs;
      return;
    }
    _blackReadyAtMs = readyAtMs;
  }

  int _estimatedServerNowMs() {
    return _now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  void _send(Map<String, dynamic> payload) {
    _transportClient.sendJson(payload);
  }

  void _logEvent(
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final ts = _now().toIso8601String();
    final detailText = details.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    final line = detailText.isEmpty
        ? '[$ts] $event'
        : '[$ts] $event | $detailText';
    _debugLogEntries.add(line);
    while (_debugLogEntries.length > _maxDebugLogEntries) {
      _debugLogEntries.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('[bg-online] $line');
    }
    _sessionLogger.logEvent(event, data: details);
  }

  void _appendServerLogLine(Map<String, dynamic> entry) {
    final at = entry['at']?.toString() ?? '-';
    final event = entry['event']?.toString() ?? 'unknown';
    final level = entry['level']?.toString() ?? 'info';
    final excluded = <String>{'id', 'at', 'event', 'level'};
    final details = entry.entries
        .where((e) => !excluded.contains(e.key) && e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    final line = details.isEmpty
        ? '[server $at] $event | level=$level'
        : '[server $at] $event | level=$level, $details';
    _debugLogEntries.add(line);
    while (_debugLogEntries.length > _maxDebugLogEntries) {
      _debugLogEntries.removeAt(0);
    }
  }

  static String _friendlyNetworkError(
    Object error, {
    required String fallback,
  }) {
    if (error is MultiplayerTransportException) {
      return error.message;
    }
    if (error is SocketException) {
      return 'Cannot reach backend (connection refused). Check Backend URL or start the server.';
    }
    final raw = error.toString().toLowerCase();
    if (raw.contains('connection refused')) {
      return 'Cannot reach backend (connection refused). Check Backend URL or start the server.';
    }
    if (raw.contains('failed host lookup')) {
      return 'Backend host lookup failed. Check the Backend URL.';
    }
    return fallback;
  }

  static String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    return '${(halfSteps / 2).toStringAsFixed(1)}s';
  }

  int _derivedActionIndex() => _history.length;

  int _derivedTurnIndex() => (_derivedActionIndex() ~/ 2) + 1;

  Map<String, Object?> _sessionSnapshot() {
    return <String, Object?>{
      'turnIndex': _derivedTurnIndex(),
      'actionIndexOrPlyIndex': _derivedActionIndex(),
      'connectionState': _connectionState.name,
      'status': _status,
      'matchId': _matchId,
      'myColor': _myColor,
      'turnColor': _turnColor,
      'result': _result,
      'historyLen': _history.length,
      'cooldownSeconds': _cooldownDuration.inSeconds,
      'whiteRemainingMs': cooldownRemaining('w').inMilliseconds,
      'blackRemainingMs': cooldownRemaining('b').inMilliseconds,
      'feedback': _feedback,
    };
  }
}
