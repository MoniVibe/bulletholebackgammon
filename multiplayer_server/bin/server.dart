import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> main(List<String> args) async {
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final roomManager = RoomManager();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        Cascade()
            .add(_healthHandler)
            .add(
              webSocketHandler(
                (channel, _) => roomManager.handleConnection(channel),
              ),
            )
            .handler,
      );

  final server = await shelf_io.serve(handler, host, port);
  stdout.writeln(
    'Bullethole multiplayer server listening on ws://${server.address.host}:${server.port}',
  );
}

Response _healthHandler(Request request) {
  if (request.url.path == 'healthz') {
    return Response.ok(
      jsonEncode(<String, dynamic>{'ok': true, 'at': DateTime.now().toUtc().toIso8601String()}),
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  return Response.notFound('not found');
}

class RoomManager {
  final Map<String, _Room> _rooms = <String, _Room>{};

  void handleConnection(WebSocketChannel channel) {
    String? roomId;
    String? playerId;

    void sendError(String message) {
      _send(channel, <String, dynamic>{'type': 'error', 'message': message});
    }

    late final StreamSubscription<dynamic> subscription;
    subscription = channel.stream.listen(
      (dynamic raw) {
        final payload = _parseJsonMap(raw);
        if (payload == null) {
          sendError('Invalid message payload.');
          return;
        }

        final type = payload['type'];
        if (type is! String || type.isEmpty) {
          sendError('Missing message type.');
          return;
        }

        if (type == 'join') {
          if (roomId != null) {
            sendError('Already joined a room.');
            return;
          }

          final requestedRoomId = payload['roomId'];
          final displayName = payload['name'];
          if (requestedRoomId is! String || !_isValidRoomId(requestedRoomId)) {
            sendError('Invalid room id. Use 3-32 letters, numbers, _ or -.');
            return;
          }
          if (displayName is! String || displayName.trim().isEmpty) {
            sendError('Name is required.');
            return;
          }

          final joinResult = _joinRoom(
            requestedRoomId.toLowerCase(),
            displayName.trim(),
            channel,
          );
          if (!joinResult.ok) {
            sendError(joinResult.errorMessage!);
            return;
          }

          roomId = joinResult.roomId;
          playerId = joinResult.playerId;
          return;
        }

        if (type == 'ping') {
          _send(channel, <String, dynamic>{'type': 'pong', 'at': DateTime.now().toUtc().toIso8601String()});
          return;
        }

        if (roomId == null || playerId == null) {
          sendError('Join a room first.');
          return;
        }

        final room = _rooms[roomId!];
        if (room == null) {
          sendError('Room no longer exists.');
          return;
        }

        switch (type) {
          case 'move':
            final from = payload['from'];
            final to = payload['to'];
            final promotionRaw = payload['promotion'];
            final promotion = promotionRaw is String && promotionRaw.isNotEmpty ? promotionRaw : 'q';

            if (from is! String || to is! String) {
              sendError('Move requires from and to.');
              return;
            }

            room.tryMove(
              playerId: playerId!,
              from: from,
              to: to,
              promotion: promotion,
            );
            return;
          case 'new_game':
            room.resetGame(requestedByPlayerId: playerId!);
            return;
          default:
            sendError('Unknown message type: $type');
        }
      },
      onDone: () {
        if (roomId != null && playerId != null) {
          final room = _rooms[roomId!];
          if (room != null) {
            room.removePlayer(playerId!);
            if (room.isEmpty) {
              _rooms.remove(roomId!);
            }
          }
        }
      },
      onError: (_) {
        subscription.cancel();
      },
      cancelOnError: false,
    );
  }

  _JoinResult _joinRoom(String roomId, String displayName, WebSocketChannel channel) {
    final room = _rooms.putIfAbsent(roomId, () => _Room(roomId: roomId));
    final added = room.addPlayer(displayName: displayName, channel: channel);

    if (!added.ok) {
      return _JoinResult.error(added.errorMessage!);
    }

    return _JoinResult.ok(roomId: roomId, playerId: added.playerId!);
  }
}

class _Room {
  _Room({required this.roomId});

  final String roomId;
  final Map<String, _Player> _playersById = <String, _Player>{};
  final Map<String, String> _colorByPlayerId = <String, String>{};
  chess.Chess _game = chess.Chess();
  int _sequence = 0;

  bool get isEmpty => _playersById.isEmpty;

  _JoinResult addPlayer({required String displayName, required WebSocketChannel channel}) {
    if (_playersById.length >= 2) {
      return _JoinResult.error('Room is full.');
    }

    final playerId = 'p_${DateTime.now().microsecondsSinceEpoch}_${_playersById.length}';
    final color = _playersById.isEmpty ? 'w' : 'b';

    _playersById[playerId] = _Player(
      id: playerId,
      name: displayName,
      channel: channel,
    );
    _colorByPlayerId[playerId] = color;

    _sendToPlayer(
      playerId,
      <String, dynamic>{
        'type': 'welcome',
        'roomId': roomId,
        'playerId': playerId,
        'color': color,
      },
    );

    _broadcastState();

    return _JoinResult.ok(roomId: roomId, playerId: playerId);
  }

  void removePlayer(String playerId) {
    _playersById.remove(playerId);
    _colorByPlayerId.remove(playerId);

    for (final player in _playersById.values) {
      _send(
        player.channel,
        <String, dynamic>{
          'type': 'opponent_left',
          'message': 'Your opponent disconnected.',
        },
      );
    }

    _broadcastState();
  }

  void tryMove({
    required String playerId,
    required String from,
    required String to,
    required String promotion,
  }) {
    final player = _playersById[playerId];
    if (player == null) {
      return;
    }

    if (_playersById.length < 2) {
      _sendError(player.channel, 'Waiting for opponent.');
      return;
    }

    if (_game.game_over) {
      _sendError(player.channel, 'Game is over. Start a new game.');
      return;
    }

    final expectedColor = _colorByPlayerId[playerId];
    if (expectedColor == null) {
      _sendError(player.channel, 'Unknown player color.');
      return;
    }

    if (_game.turn != _toChessColor(expectedColor)) {
      _sendError(player.channel, 'Not your turn.');
      return;
    }

    final moved = _game.move(<String, String>{
      'from': from,
      'to': to,
      'promotion': promotion,
    });

    if (!moved) {
      _sendError(player.channel, 'Illegal move.');
      return;
    }

    _broadcastState(
      lastMove: <String, dynamic>{
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
  }

  void resetGame({required String requestedByPlayerId}) {
    if (!_playersById.containsKey(requestedByPlayerId)) {
      return;
    }

    _game = chess.Chess();
    _broadcastState();
  }

  void _broadcastState({Map<String, dynamic>? lastMove}) {
    _sequence += 1;

    final state = <String, dynamic>{
      'type': 'state',
      'sequence': _sequence,
      'roomId': roomId,
      'status': _statusLabel(),
      'fen': _game.fen,
      'turn': _colorCode(_game.turn),
      'history': _game.getHistory(),
      'players': <String, dynamic>{
        'w': _nameForColor('w'),
        'b': _nameForColor('b'),
      },
      if (_game.game_over) 'result': _resultLabel(),
    };
    if (lastMove != null) {
      state['lastMove'] = lastMove;
    }

    for (final player in _playersById.values) {
      _send(player.channel, state);
    }
  }

  String _statusLabel() {
    if (_playersById.length < 2) {
      return 'waiting';
    }
    if (_game.game_over) {
      return 'game_over';
    }
    return 'active';
  }

  String _resultLabel() {
    if (_game.in_checkmate) {
      return _colorCode(_game.turn) == 'w'
          ? 'black_wins_checkmate'
          : 'white_wins_checkmate';
    }
    if (_game.in_draw) {
      return 'draw';
    }
    return 'game_over';
  }

  String? _nameForColor(String color) {
    final entry = _colorByPlayerId.entries.where((e) => e.value == color);
    if (entry.isEmpty) {
      return null;
    }
    return _playersById[entry.first.key]?.name;
  }

  void _sendToPlayer(String playerId, Map<String, dynamic> payload) {
    final player = _playersById[playerId];
    if (player == null) {
      return;
    }
    _send(player.channel, payload);
  }
}

class _Player {
  const _Player({required this.id, required this.name, required this.channel});

  final String id;
  final String name;
  final WebSocketChannel channel;
}

class _JoinResult {
  const _JoinResult._({this.roomId, this.playerId, this.errorMessage});

  factory _JoinResult.ok({required String roomId, required String playerId}) {
    return _JoinResult._(roomId: roomId, playerId: playerId);
  }

  factory _JoinResult.error(String message) {
    return _JoinResult._(errorMessage: message);
  }

  final String? roomId;
  final String? playerId;
  final String? errorMessage;

  bool get ok => errorMessage == null;
}

chess.Color _toChessColor(String colorCode) {
  return colorCode == 'w' ? chess.Color.WHITE : chess.Color.BLACK;
}

String _colorCode(chess.Color color) {
  return color == chess.Color.WHITE ? 'w' : 'b';
}

bool _isValidRoomId(String value) {
  final regex = RegExp(r'^[a-zA-Z0-9_-]{3,32}$');
  return regex.hasMatch(value);
}

Map<String, dynamic>? _parseJsonMap(dynamic raw) {
  if (raw is! String) {
    return null;
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    return null;
  }
  return Map<String, dynamic>.from(decoded);
}

void _send(WebSocketChannel channel, Map<String, dynamic> payload) {
  channel.sink.add(jsonEncode(payload));
}

void _sendError(WebSocketChannel channel, String message) {
  _send(channel, <String, dynamic>{'type': 'error', 'message': message});
}
