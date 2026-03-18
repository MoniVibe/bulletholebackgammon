import 'dart:async';
import 'dart:math';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/foundation.dart';

import 'sheshbesh_ai_engine.dart';
import 'sheshbesh_model.dart';
import 'sheshbesh_rules.dart';

class LocalGameController extends ChangeNotifier {
  LocalGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    this.aiThinkDelayMin = const Duration(milliseconds: 1200),
    this.aiThinkDelayMax = const Duration(milliseconds: 2200),
    SheshBeshAiEngine? aiEngine,
    Random? random,
  }) : _random = random ?? Random(),
       _aiEngine = aiEngine ?? SheshBeshAiEngine(random: random ?? Random()),
       _cooldownDuration = initialCooldownDuration {
    _resetRuntimeState(activateGame: false);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
  }

  final Duration aiThinkDelayMin;
  final Duration aiThinkDelayMax;
  final Random _random;
  final SheshBeshAiEngine _aiEngine;
  final GameSessionLogger _sessionLogger = GameSessionLogger(
    applicationId: 'bulletholebackgammon',
    gameId: 'backgammon',
    mode: 'local_duel',
  );

  late Timer _ticker;
  Timer? _aiTurnTimer;

  Duration _cooldownDuration;
  bool _disposed = false;
  bool _hasActiveGame = false;
  bool _aiTurnPending = false;

  String _playerColor = 'w';
  String _turnColor = 'w';
  String? _overtimeColor;
  String? _pendingExtraRollColor;
  bool _turnTimeoutHandled = false;

  DateTime _turnDeadlineAt = DateTime.now();

  String? _winnerColor;
  String? _feedback;

  late SheshBeshPosition _position;
  TurnDecision _currentDecision = const TurnDecision(
    legalMoves: <SheshBeshMove>[],
    maxMovesUsable: 0,
    maxUsedPips: 0,
  );

  final Map<String, List<int>> _diceByColor = <String, List<int>>{
    'w': <int>[],
    'b': <int>[],
  };

  int? _selectedPoint;
  bool _selectedFromBar = false;
  Set<int> _legalTargetPoints = <int>{};
  bool _canBearOffTarget = false;
  Map<int, int> _targetDiceSpentHints = <int, int>{};
  Map<int, int> _sourceDiceUsageHints = <int, int>{};

  SheshBeshMove? _playerLastMove;
  SheshBeshMove? _opponentLastMove;

  final List<String> _history = <String>[];

  Duration get cooldownDuration => _cooldownDuration;
  String get playerColor => _playerColor;
  String get aiColor => SheshBeshRules.oppositeColor(_playerColor);
  String get turnColor => _turnColor;
  bool get hasActiveGame => _hasActiveGame;
  bool get isGameOver => _winnerColor != null;
  String? get winnerColor => _winnerColor;
  String? get winnerLabel =>
      _winnerColor == null ? null : (_winnerColor == 'w' ? 'White' : 'Black');

  String? get feedback => _feedback;

  List<SheshBeshPoint> get points => _position.points;
  int barCount(String color) => _position.barCount(color);
  int borneOffCount(String color) => _position.borneOffCount(color);
  List<int> get remainingDice => diceForColor(_turnColor);
  Duration get activeTurnRemaining => _turnRemaining();

  // Kept for UI compatibility; in this model it is the active timer for color.
  Duration cooldownRemaining(String color) => timerRemaining(color);

  Duration timerRemaining(String color) {
    if (!_hasActiveGame || isGameOver || !hasActiveDice(color)) {
      return Duration.zero;
    }
    if (color == _turnColor) {
      final remaining = _turnRemaining();
      if (remaining.inMilliseconds > 0) {
        return remaining;
      }
      // Overtime side still has dice but no timer.
      if (_overtimeColor == color) {
        return Duration.zero;
      }
      return Duration.zero;
    }
    if (_overtimeColor == color) {
      return Duration.zero;
    }
    return Duration.zero;
  }

  List<int> diceForColor(String color) {
    final dice = _diceByColor[color];
    if (dice == null) {
      return const <int>[];
    }
    return List<int>.unmodifiable(dice);
  }

  bool hasActiveDice(String color) {
    final dice = _diceByColor[color];
    return dice != null && dice.isNotEmpty;
  }

  int? get selectedPoint => _selectedPoint;
  bool get selectedFromBar => _selectedFromBar;
  Set<int> get legalTargetPoints => _legalTargetPoints;
  bool get canBearOffTarget => _canBearOffTarget;
  Map<int, int> get targetDiceSpentHints =>
      Map<int, int>.unmodifiable(_targetDiceSpentHints);
  Map<int, int> get sourceDiceUsageHints =>
      Map<int, int>.unmodifiable(_sourceDiceUsageHints);
  Set<int> get playableSourcePoints => _derivePlayableSourcePoints();
  bool get canEnterFromBar => _deriveCanEnterFromBar();

  SheshBeshMove? get playerLastMove => _playerLastMove;
  SheshBeshMove? get opponentLastMove => _opponentLastMove;

  List<String> get history => List<String>.unmodifiable(_history);

  bool get canPlayerInteract {
    return _hasActiveGame && !isGameOver && _isColorAllowedToMove(_playerColor);
  }

  String get statusText {
    if (!_hasActiveGame) {
      return 'Start a new sheshbesh game to begin.';
    }
    if (_winnerColor != null) {
      return '${winnerLabel!} wins. Start a new game.';
    }

    final playerAction = canPlayerInteract
        ? 'You can move now.'
        : 'You are waiting.';
    return '$playerAction  W: ${_colorLaneStatus('w')}  B: ${_colorLaneStatus('b')}';
  }

  void startNewGame({bool playerAsWhite = true, Duration? cooldownDuration}) {
    _cancelAiTimer();
    _playerColor = playerAsWhite ? 'w' : 'b';
    if (cooldownDuration != null) {
      _cooldownDuration = cooldownDuration;
    }
    _sessionLogger.beginSession(
      sessionLabel: 'new_game',
      context: <String, Object?>{
        'playerAsWhite': playerAsWhite,
        'cooldownSeconds': _cooldownDuration.inSeconds,
      },
    );

    _resetRuntimeState(activateGame: true);

    final opening = SheshBeshRules.determineOpeningStarter(_random);
    _history.add(
      'Opening roll W${opening.whiteRoll} / B${opening.blackRoll}. '
      '${opening.startingColor == 'w' ? 'White' : 'Black'} starts.',
    );

    _startTurnForColor(opening.startingColor);
    _refreshPlayerDecision();
    _maybeScheduleAiTurn();
    _sessionLogger.logEvent('new_game_started', data: _sessionSnapshot());
    notifyListeners();
  }

  void tapPoint(int pointIndex) {
    _syncForInput();
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (pointIndex < 0 || pointIndex >= 24) {
      return;
    }

    if (_position.barCount(_playerColor) > 0) {
      _selectedFromBar = true;
      _selectedPoint = null;
      _updateSelectionTargets();
      final moved = _attemptSelectedMove(toPoint: pointIndex);
      if (!moved) {
        _feedback = 'Enter from bar first.';
      }
      notifyListeners();
      return;
    }

    final isOwnPoint = _pointOwnedBy(pointIndex, _playerColor);

    if (_selectedPoint != null) {
      final moved = _attemptSelectedMove(toPoint: pointIndex);
      if (moved) {
        notifyListeners();
        return;
      }
    }

    if (!isOwnPoint) {
      _feedback = 'Select one of your checkers.';
      notifyListeners();
      return;
    }

    if (_selectedPoint == pointIndex) {
      _clearSelection();
      notifyListeners();
      return;
    }

    _selectedFromBar = false;
    _selectedPoint = pointIndex;
    _feedback = null;
    _updateSelectionTargets();
    notifyListeners();
  }

  void longPressPoint(int pointIndex) {
    _syncForInput();
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (pointIndex < 0 || pointIndex >= 24) {
      return;
    }

    if (_position.barCount(_playerColor) > 0) {
      _selectedFromBar = true;
      _selectedPoint = null;
      _feedback = 'Enter from bar first.';
      _updateSelectionTargets();
      notifyListeners();
      return;
    }

    if (!_pointOwnedBy(pointIndex, _playerColor)) {
      _feedback = 'Select one of your checkers.';
      notifyListeners();
      return;
    }
    if (!_isPlayableSourcePoint(pointIndex)) {
      _feedback = 'That checker cannot move with current dice.';
      notifyListeners();
      return;
    }

    _selectedFromBar = false;
    _selectedPoint = pointIndex;
    _feedback = null;
    _updateSelectionTargets();
    notifyListeners();
  }

  void tapBar() {
    _syncForInput();
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (_position.barCount(_playerColor) == 0) {
      return;
    }
    _selectedFromBar = true;
    _selectedPoint = null;
    _feedback = null;
    _updateSelectionTargets();
    notifyListeners();
  }

  void tapBearOff() {
    _syncForInput();
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (!_canBearOffTarget) {
      return;
    }
    if (_attemptSelectedMove(bearOff: true)) {
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
    _cancelAiTimer();
    super.dispose();
  }

  void _syncForInput() {
    if (_disposed || !_hasActiveGame || isGameOver) {
      return;
    }
    _processTurnTimeoutIfNeeded();
    _maybeAutoPassBlockedColor('w');
    _maybeAutoPassBlockedColor('b');
    _refreshPlayerDecision();
  }

  void _onTick() {
    if (_disposed || !_hasActiveGame || isGameOver) {
      return;
    }

    _processTurnTimeoutIfNeeded();
    _maybeAutoPassBlockedColor('w');
    _maybeAutoPassBlockedColor('b');
    _refreshPlayerDecision();
    _maybeScheduleAiTurn();
    notifyListeners();
  }

  bool _attemptSelectedMove({int? toPoint, bool bearOff = false}) {
    final source = _selectedSourceKind();
    if (source == _SelectedSource.none) {
      return false;
    }

    final matching = _currentDecision.legalMoves
        .where((move) {
          if (source == _SelectedSource.bar &&
              move.source != SheshBeshMoveSource.bar) {
            return false;
          }
          if (source == _SelectedSource.point) {
            if (move.source != SheshBeshMoveSource.point ||
                move.fromPoint != _selectedPoint) {
              return false;
            }
          }
          if (bearOff) {
            return move.bearsOff;
          }
          return !move.bearsOff && move.toPoint == toPoint;
        })
        .toList(growable: false);

    if (matching.isEmpty) {
      return false;
    }

    // If several dice map to the same destination, prefer the larger die.
    matching.sort((a, b) => b.die.compareTo(a.die));
    _applyMove(matching.first, moverColor: _playerColor, actorIsPlayer: true);
    return true;
  }

  void _applyMove(
    SheshBeshMove move, {
    required String moverColor,
    required bool actorIsPlayer,
  }) {
    _position = SheshBeshRules.applyMove(
      position: _position,
      color: moverColor,
      move: move,
    );

    _removeDieForColor(moverColor, move.die);

    if (actorIsPlayer) {
      _playerLastMove = move;
    } else {
      _opponentLastMove = move;
    }

    _history.add(move.describe(moverColor));
    _feedback = null;
    if (actorIsPlayer) {
      _clearSelection();
    } else {
      _reconcileSelectionAfterExternalBoardChange();
    }

    _winnerColor = SheshBeshRules.winnerColor(_position);
    if (_winnerColor != null) {
      _aiTurnPending = false;
      _cancelAiTimer();
      return;
    }

    final moverDecision = _decisionForColor(moverColor);
    if (!hasActiveDice(moverColor) || !moverDecision.hasMoves) {
      if (hasActiveDice(moverColor) && !moverDecision.hasMoves) {
        _history.add(
          '${_colorLabel(moverColor)} no legal moves with '
          'remaining dice ${diceForColor(moverColor).join(', ')}.',
        );
      }
      _completeDiceBatch(moverColor);
    }

    _refreshPlayerDecision();
    _maybeScheduleAiTurn();
    _sessionLogger.logEvent(
      'move_applied',
      data: <String, Object?>{
        ..._sessionSnapshot(),
        'moverColor': moverColor,
        'move': move.describe(moverColor),
        'actor': actorIsPlayer ? 'player' : 'ai',
      },
    );
  }

  void _completeDiceBatch(String color) {
    final wasTurnColor = color == _turnColor;
    final wasOvertime = color == _overtimeColor;

    _clearDiceForColor(color);

    if (wasOvertime) {
      _overtimeColor = null;

      // If the other side finished first, they were queued for a follow-up roll.
      if (_pendingExtraRollColor != null) {
        final queuedColor = _pendingExtraRollColor!;
        _pendingExtraRollColor = null;
        _startTurnForColor(queuedColor);
        return;
      }

      // Overtime can also be the visible turn lane while waiting.
      if (wasTurnColor) {
        _startTurnForColor(SheshBeshRules.oppositeColor(color));
      }
      return;
    }

    if (wasTurnColor) {
      // If overtime side still has old dice, wait for them to finish.
      if (_overtimeColor != null && hasActiveDice(_overtimeColor!)) {
        _pendingExtraRollColor = color;
        _turnColor = _overtimeColor!;
        _turnDeadlineAt = DateTime.now();
        _turnTimeoutHandled = true;
        return;
      }

      _startTurnForColor(SheshBeshRules.oppositeColor(color));
      return;
    }

    // Defensive fallback.
    if (!hasActiveDice(_turnColor)) {
      _startTurnForColor(SheshBeshRules.oppositeColor(color));
    }
  }

  void _processTurnTimeoutIfNeeded() {
    if (!_hasActiveGame || isGameOver || !hasActiveDice(_turnColor)) {
      return;
    }
    if (_turnTimeoutHandled) {
      return;
    }
    if (_turnRemaining().inMilliseconds > 0) {
      return;
    }
    if (_overtimeColor == _turnColor) {
      // Overtime lanes intentionally have no timer.
      _turnTimeoutHandled = true;
      return;
    }

    final timedOutColor = _turnColor;
    final opponent = SheshBeshRules.oppositeColor(timedOutColor);
    _turnTimeoutHandled = true;
    _overtimeColor = timedOutColor;
    _history.add(
      '${_colorLabel(timedOutColor)} time expired. '
      '${_colorLabel(opponent)} can play while ${_colorLabel(timedOutColor)} keeps old dice.',
    );

    if (!hasActiveDice(opponent)) {
      _startTurnForColor(opponent);
      return;
    }

    // Defensive fallback if opponent already had dice.
    _turnColor = opponent;
    _turnDeadlineAt = DateTime.now().add(_cooldownDuration);
    _turnTimeoutHandled = false;
  }

  bool _maybeAutoPassBlockedColor(String color) {
    if (!_isColorAllowedToMove(color)) {
      return false;
    }
    final decision = _decisionForColor(color);
    if (decision.hasMoves) {
      return false;
    }

    _history.add(
      '${_colorLabel(color)} passes (no legal moves for dice ${diceForColor(color).join(', ')}).',
    );
    _completeDiceBatch(color);
    return true;
  }

  void _maybeScheduleAiTurn() {
    if (!_hasActiveGame || isGameOver || _aiTurnPending) {
      return;
    }
    if (!_isColorAllowedToMove(aiColor)) {
      return;
    }

    final decision = _decisionForColor(aiColor);
    if (!decision.hasMoves) {
      return;
    }

    _aiTurnPending = true;
    _aiTurnTimer = Timer(_nextAiThinkDelay(), _runAiTurn);
  }

  void _runAiTurn() {
    if (_disposed) {
      return;
    }

    _syncForInput();
    if (!_hasActiveGame || isGameOver || !_isColorAllowedToMove(aiColor)) {
      _aiTurnPending = false;
      notifyListeners();
      return;
    }

    final decision = _decisionForColor(aiColor);
    if (!decision.hasMoves) {
      _history.add(
        '${_colorLabel(aiColor)} passes (no legal moves for dice ${diceForColor(aiColor).join(', ')}).',
      );
      _completeDiceBatch(aiColor);
      _aiTurnPending = false;
      _refreshPlayerDecision();
      _maybeScheduleAiTurn();
      notifyListeners();
      return;
    }

    final move = _aiEngine.chooseMove(
      position: _position,
      color: aiColor,
      dice: _diceByColor[aiColor]!,
    );
    if (move == null) {
      _history.add('${_colorLabel(aiColor)} pass fallback.');
      _completeDiceBatch(aiColor);
      _aiTurnPending = false;
      _refreshPlayerDecision();
      _maybeScheduleAiTurn();
      notifyListeners();
      return;
    }

    _applyMove(move, moverColor: aiColor, actorIsPlayer: false);
    _aiTurnPending = false;
    _refreshPlayerDecision();
    _maybeScheduleAiTurn();
    notifyListeners();
  }

  void _refreshPlayerDecision() {
    if (!_hasActiveGame || isGameOver || !_isColorAllowedToMove(_playerColor)) {
      _currentDecision = const TurnDecision(
        legalMoves: <SheshBeshMove>[],
        maxMovesUsable: 0,
        maxUsedPips: 0,
      );
      _clearSelection();
      _sourceDiceUsageHints = <int, int>{};
      return;
    }

    _currentDecision = _decisionForColor(_playerColor);
    if (!_currentDecision.hasMoves) {
      _clearSelection();
      _sourceDiceUsageHints = <int, int>{};
      return;
    }

    if (_position.barCount(_playerColor) > 0) {
      _selectedFromBar = true;
      _selectedPoint = null;
      _updateSelectionTargets();
      return;
    }

    if (_selectedPoint != null) {
      final selectedStillValid = _currentDecision.legalMoves.any(
        (move) =>
            move.source == SheshBeshMoveSource.point &&
            move.fromPoint == _selectedPoint,
      );
      if (!selectedStillValid) {
        _selectedPoint = null;
      }
    }

    _updateSelectionTargets();
  }

  TurnDecision _decisionForColor(String color) {
    final dice = _diceByColor[color];
    if (dice == null || dice.isEmpty) {
      return const TurnDecision(
        legalMoves: <SheshBeshMove>[],
        maxMovesUsable: 0,
        maxUsedPips: 0,
      );
    }
    return SheshBeshRules.computeTurnDecision(
      position: _position,
      color: color,
      dice: dice,
    );
  }

  void _updateSelectionTargets() {
    final targets = <int>{};
    var canBearOff = false;

    final source = _selectedSourceKind();
    if (source == _SelectedSource.none) {
      _legalTargetPoints = const <int>{};
      _canBearOffTarget = false;
      _rebuildDiceUsageHints(source: source);
      return;
    }

    for (final move in _currentDecision.legalMoves) {
      final matchesSource = switch (source) {
        _SelectedSource.bar => move.source == SheshBeshMoveSource.bar,
        _SelectedSource.point =>
          move.source == SheshBeshMoveSource.point &&
              move.fromPoint == _selectedPoint,
        _SelectedSource.none => false,
      };
      if (!matchesSource) {
        continue;
      }
      if (move.bearsOff) {
        canBearOff = true;
        continue;
      }
      if (move.toPoint != null) {
        targets.add(move.toPoint!);
      }
    }

    _legalTargetPoints = targets;
    _canBearOffTarget = canBearOff;
    _rebuildDiceUsageHints(source: source);
  }

  _SelectedSource _selectedSourceKind() {
    if (_selectedFromBar) {
      return _SelectedSource.bar;
    }
    if (_selectedPoint != null) {
      return _SelectedSource.point;
    }
    return _SelectedSource.none;
  }

  bool _pointOwnedBy(int point, String color) {
    final stack = _position.points[point];
    return stack.color == color && stack.count > 0;
  }

  bool _isPlayableSourcePoint(int pointIndex) {
    return _currentDecision.legalMoves.any(
      (move) =>
          move.source == SheshBeshMoveSource.point &&
          move.fromPoint == pointIndex,
    );
  }

  void _reconcileSelectionAfterExternalBoardChange() {
    // Preserve player selection across opponent moves when still meaningful.
    // This keeps overlap/overtime flow smooth without forcing re-selection.
    if (_selectedFromBar && _position.barCount(_playerColor) == 0) {
      _selectedFromBar = false;
    }
    if (_selectedPoint != null &&
        !_pointOwnedBy(_selectedPoint!, _playerColor)) {
      _selectedPoint = null;
    }
    if (_selectedFromBar) {
      _selectedPoint = null;
    }
  }

  Set<int> _derivePlayableSourcePoints() {
    if (!canPlayerInteract) {
      return const <int>{};
    }
    return _currentDecision.legalMoves
        .where((move) => move.source == SheshBeshMoveSource.point)
        .map((move) => move.fromPoint!)
        .toSet();
  }

  bool _deriveCanEnterFromBar() {
    if (!canPlayerInteract) {
      return false;
    }
    return _currentDecision.legalMoves.any(
      (move) => move.source == SheshBeshMoveSource.bar,
    );
  }

  void _startTurnForColor(String color) {
    _turnColor = color;
    _turnDeadlineAt = DateTime.now().add(_cooldownDuration);
    _turnTimeoutHandled = false;
    _diceByColor[color] = List<int>.from(SheshBeshRules.rollTurnDice(_random));
    _history.add(
      '${_colorLabel(color)} rolls ${_diceByColor[color]!.join(' + ')}',
    );
  }

  Duration _turnRemaining() {
    final remaining = _turnDeadlineAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  bool _isColorAllowedToMove(String color) {
    if (!hasActiveDice(color)) {
      return false;
    }
    if (color == _turnColor) {
      if (_turnRemaining().inMilliseconds > 0) {
        return true;
      }
      return _overtimeColor == color;
    }
    return _overtimeColor == color;
  }

  void _rebuildDiceUsageHints({required _SelectedSource source}) {
    _sourceDiceUsageHints = <int, int>{};
    _targetDiceSpentHints = <int, int>{};

    if (!canPlayerInteract || !_currentDecision.hasMoves) {
      return;
    }

    final pointMoves = _currentDecision.legalMoves
        .where(
          (move) =>
              move.source == SheshBeshMoveSource.point &&
              move.fromPoint != null,
        )
        .toList(growable: false);
    for (final move in pointMoves) {
      final sourcePoint = move.fromPoint!;
      final maxDiceSpent = _maxDiceSpentFollowingMove(move);
      final prior = _sourceDiceUsageHints[sourcePoint] ?? 0;
      if (maxDiceSpent > prior) {
        _sourceDiceUsageHints[sourcePoint] = maxDiceSpent;
      }

      if (source == _SelectedSource.point &&
          _selectedPoint == sourcePoint &&
          !move.bearsOff &&
          move.toPoint != null) {
        final targetPoint = move.toPoint!;
        final targetPrior = _targetDiceSpentHints[targetPoint] ?? 0;
        if (maxDiceSpent > targetPrior) {
          _targetDiceSpentHints[targetPoint] = maxDiceSpent;
        }
      }
    }

    if (source == _SelectedSource.bar) {
      final barMoves = _currentDecision.legalMoves
          .where(
            (move) =>
                move.source == SheshBeshMoveSource.bar &&
                !move.bearsOff &&
                move.toPoint != null,
          )
          .toList(growable: false);
      for (final move in barMoves) {
        final targetPoint = move.toPoint!;
        final maxDiceSpent = _maxDiceSpentFollowingMove(move);
        final prior = _targetDiceSpentHints[targetPoint] ?? 0;
        if (maxDiceSpent > prior) {
          _targetDiceSpentHints[targetPoint] = maxDiceSpent;
        }
      }
    }
  }

  int _maxDiceSpentFollowingMove(SheshBeshMove firstMove) {
    final nextPosition = SheshBeshRules.applyMove(
      position: _position,
      color: _playerColor,
      move: firstMove,
    );
    final nextDice = _consumeDie(_diceByColor[_playerColor]!, firstMove.die);
    final additional = firstMove.bearsOff || firstMove.toPoint == null
        ? 0
        : _maxAdditionalDiceForChecker(
            position: nextPosition,
            checkerPoint: firstMove.toPoint!,
            dice: nextDice,
          );
    return 1 + additional;
  }

  int _maxAdditionalDiceForChecker({
    required SheshBeshPosition position,
    required int checkerPoint,
    required List<int> dice,
  }) {
    if (dice.isEmpty) {
      return 0;
    }

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: _playerColor,
      dice: dice,
    );
    if (!decision.hasMoves) {
      return 0;
    }

    var best = 0;
    // Follow one checker through the tree so the badge means:
    // "max dice this piece can spend on this path".
    for (final move in decision.legalMoves) {
      if (move.source != SheshBeshMoveSource.point ||
          move.fromPoint != checkerPoint) {
        continue;
      }
      final nextPosition = SheshBeshRules.applyMove(
        position: position,
        color: _playerColor,
        move: move,
      );
      final nextDice = _consumeDie(dice, move.die);
      final tail = move.bearsOff || move.toPoint == null
          ? 0
          : _maxAdditionalDiceForChecker(
              position: nextPosition,
              checkerPoint: move.toPoint!,
              dice: nextDice,
            );
      final spent = 1 + tail;
      if (spent > best) {
        best = spent;
      }
    }
    return best;
  }

  List<int> _consumeDie(List<int> dice, int die) {
    final nextDice = List<int>.from(dice);
    final index = nextDice.indexOf(die);
    if (index >= 0) {
      nextDice.removeAt(index);
    }
    return nextDice;
  }

  void _clearDiceForColor(String color) {
    _diceByColor[color] = <int>[];
  }

  void _removeDieForColor(String color, int die) {
    final dice = _diceByColor[color];
    if (dice == null) {
      return;
    }
    final index = dice.indexOf(die);
    if (index >= 0) {
      dice.removeAt(index);
    }
  }

  void _clearSelection() {
    _selectedPoint = null;
    _selectedFromBar = false;
    _legalTargetPoints = <int>{};
    _canBearOffTarget = false;
    _targetDiceSpentHints = <int, int>{};
  }

  void _cancelAiTimer() {
    _aiTurnTimer?.cancel();
    _aiTurnTimer = null;
    _aiTurnPending = false;
  }

  Duration _nextAiThinkDelay() {
    final minMs = aiThinkDelayMin.inMilliseconds;
    final maxMs = aiThinkDelayMax.inMilliseconds;
    if (maxMs <= minMs) {
      return Duration(milliseconds: minMs);
    }
    final delta = _random.nextInt(maxMs - minMs + 1);
    return Duration(milliseconds: minMs + delta);
  }

  void _resetRuntimeState({required bool activateGame}) {
    _position = SheshBeshRules.initialPosition();
    _hasActiveGame = activateGame;
    _winnerColor = null;
    _feedback = null;
    _currentDecision = const TurnDecision(
      legalMoves: <SheshBeshMove>[],
      maxMovesUsable: 0,
      maxUsedPips: 0,
    );
    _clearSelection();
    _playerLastMove = null;
    _opponentLastMove = null;
    _history.clear();

    _diceByColor['w'] = <int>[];
    _diceByColor['b'] = <int>[];
    _turnColor = _playerColor;
    _overtimeColor = null;
    _pendingExtraRollColor = null;
    _turnDeadlineAt = DateTime.now();
    _turnTimeoutHandled = false;
    _sourceDiceUsageHints = <int, int>{};
    _targetDiceSpentHints = <int, int>{};
  }

  String _colorLabel(String color) => color == 'w' ? 'W' : 'B';

  String _colorLaneStatus(String color) {
    if (!hasActiveDice(color)) {
      return 'idle';
    }

    final diceText = diceForColor(color).join(' ');
    if (_isColorAllowedToMove(color)) {
      if (color == _turnColor && _turnRemaining().inMilliseconds > 0) {
        return '${_formatDuration(_turnRemaining())} | dice $diceText';
      }
      return 'overtime | dice $diceText';
    }
    return 'waiting | dice $diceText';
  }

  static String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    return '${(halfSteps / 2).toStringAsFixed(1)}s';
  }

  Map<String, Object?> _sessionSnapshot() {
    return <String, Object?>{
      'playerColor': _playerColor,
      'turnColor': _turnColor,
      'hasActiveGame': _hasActiveGame,
      'isGameOver': isGameOver,
      'winnerColor': _winnerColor,
      'historyLen': _history.length,
      'diceW': _diceByColor['w']?.join(','),
      'diceB': _diceByColor['b']?.join(','),
      'barW': _position.barCount('w'),
      'barB': _position.barCount('b'),
      'borneOffW': _position.borneOffCount('w'),
      'borneOffB': _position.borneOffCount('b'),
      'feedback': _feedback,
      'cooldownSeconds': _cooldownDuration.inSeconds,
    };
  }
}

enum _SelectedSource { none, point, bar }
