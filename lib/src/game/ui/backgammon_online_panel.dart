import 'dart:convert';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/backgammon_online_controller.dart';
import '../engine/sheshbesh_model.dart';
import 'app_assets.dart';
import 'sheshbesh_board_view.dart';
import 'skin_catalog.dart';

/// Online infrastructure panel for backgammon.
///
/// Notes:
/// - Transport/session plumbing is functional.
/// - Move/playability semantics are intentionally deferred to game logic work.
class BackgammonOnlinePanel extends StatefulWidget {
  const BackgammonOnlinePanel({
    this.isOnlineMode = true,
    this.onModeChanged,
    this.showModeSwitch = true,
    super.key,
  });

  final bool isOnlineMode;
  final ValueChanged<bool>? onModeChanged;
  final bool showModeSwitch;

  @override
  State<BackgammonOnlinePanel> createState() => _BackgammonOnlinePanelState();
}

class _BackgammonOnlinePanelState extends State<BackgammonOnlinePanel> {
  static const List<int> _cooldownOptionsSeconds = <int>[2, 3, 5, 7, 10];
  static const String _defaultBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const Set<String> _ownedBackgammonPieceSkinIds = <String>{
    'bg_ruby',
    'bg_royal',
    'bg_minimal',
  };

  late final BackgammonOnlineController _controller;
  late final TextEditingController _apiBaseController;
  late final TextEditingController _nameController;
  late final ScrollController _matchSettingsScrollController;

  bool _menuOpen = true;
  bool _connecting = false;
  bool _backendActionInFlight = false;
  int _selectedCooldownSeconds = 3;
  String _selectedPlayerSkinId = SkinCatalog.defaultBackgammonPieceSkinId;

  @override
  void initState() {
    super.initState();
    _controller = BackgammonOnlineController();
    _apiBaseController = TextEditingController(text: _defaultBackendUrl);
    _nameController = TextEditingController(text: 'Player');
    _matchSettingsScrollController = ScrollController();
    _checkBackendHealth();
  }

  @override
  void dispose() {
    _matchSettingsScrollController.dispose();
    _apiBaseController.dispose();
    _nameController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final connected = _controller.isConnected;
        final canStart = !connected && !_connecting;
        final history = _controller.history;
        final tailHistory = history.length > 8
            ? history.sublist(history.length - 8)
            : history;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              CollapsibleSettingsCard(
                title: 'Matchmaking',
                isOpen: _menuOpen,
                onToggle: () {
                  setState(() {
                    _menuOpen = !_menuOpen;
                  });
                },
                leading: const AppAssetIcon(
                  AppAssets.settingsIcon,
                  fallbackIcon: Icons.settings,
                  size: 22,
                ),
                trailing: widget.showModeSwitch
                    ? CompactModeSwitch(
                        onlineSelected: widget.isOnlineMode,
                        onChanged: (selected) {
                          widget.onModeChanged?.call(selected);
                        },
                      )
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Scrollbar(
                    controller: _matchSettingsScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _matchSettingsScrollController,
                      child: Column(
                        children: [
                          TextField(
                            controller: _apiBaseController,
                            decoration: const InputDecoration(
                              labelText: 'Backend URL',
                              hintText: 'https://your-backend.example.com',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Display Name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            initialValue: _selectedCooldownSeconds,
                            decoration: const InputDecoration(
                              labelText: 'Cooldown (seconds)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _cooldownOptionsSeconds
                                .map(
                                  (seconds) => DropdownMenuItem<int>(
                                    value: seconds,
                                    child: Text('$seconds s'),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: connected
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _selectedCooldownSeconds = value;
                                    });
                                  },
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              'bg_online_skin_$_selectedPlayerSkinId',
                            ),
                            initialValue: _selectedPlayerSkinId,
                            decoration: const InputDecoration(
                              labelText: 'Player Skin',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _backgammonPieceSkinDropdownItems(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedPlayerSkinId = value;
                              });
                              _controller.setMyPieceSkin(value);
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: canStart ? _findMatch : null,
                                  icon: const AppAssetIcon(
                                    AppAssets.newGameIcon,
                                    fallbackIcon: Icons.groups_2_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Find Match'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: connected ? _disconnect : null,
                                  child: const Text('Disconnect'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _BackendHealthCard(
                            state: _controller.backendHealthState,
                            message: _controller.backendHealthMessage,
                            checkedAt: _controller.backendHealthCheckedAt,
                            busy: _backendActionInFlight,
                            onCheckPressed: _checkBackendHealth,
                            onWakePressed: _wakeBackend,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: connected
                                      ? () => _controller.requestNewGame(
                                          cooldownSeconds:
                                              _selectedCooldownSeconds,
                                        )
                                      : null,
                                  icon: const AppAssetIcon(
                                    AppAssets.rematchIcon,
                                    fallbackIcon: Icons.replay,
                                    size: 18,
                                  ),
                                  label: const Text('Request New Game'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _pullServerLogs(),
                                  icon: const Icon(
                                    Icons.description_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Pull Server Logs'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _controller.clearDebugLog,
                                  icon: const Icon(Icons.clear_all, size: 18),
                                  label: const Text('Clear Log'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildOnlineBoardSurface(canStart: canStart),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      flex: 4,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildSessionStatusCard(tailHistory)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildTransportDebugCard()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<DropdownMenuItem<String>> _backgammonPieceSkinDropdownItems() {
    return SkinCatalog.backgammonPieceSkins
        .map(
          (skin) => DropdownMenuItem<String>(
            value: skin.id,
            enabled: _ownedBackgammonPieceSkinIds.contains(skin.id),
            child: Text(
              _ownedBackgammonPieceSkinIds.contains(skin.id)
                  ? skin.label
                  : '${skin.label} (Locked)',
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _findMatch() async {
    setState(() {
      _connecting = true;
    });
    try {
      await _controller.findMatch(
        apiBaseUrl: _apiBaseController.text,
        displayName: _nameController.text,
        cooldownSeconds: _selectedCooldownSeconds,
      );
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _menuOpen = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await _controller.disconnect();
  }

  Future<void> _checkBackendHealth() async {
    if (_backendActionInFlight) {
      return;
    }
    setState(() {
      _backendActionInFlight = true;
    });
    try {
      await _controller.checkBackendHealth(apiBaseUrl: _apiBaseController.text);
    } finally {
      if (mounted) {
        setState(() {
          _backendActionInFlight = false;
        });
      }
    }
  }

  Future<void> _wakeBackend() async {
    if (_backendActionInFlight) {
      return;
    }
    setState(() {
      _backendActionInFlight = true;
    });
    try {
      await _controller.wakeBackend(apiBaseUrl: _apiBaseController.text);
    } finally {
      if (mounted) {
        setState(() {
          _backendActionInFlight = false;
        });
      }
    }
  }

  Future<void> _pullServerLogs() async {
    final count = await _controller.pullServerDebugLogs(
      apiBaseUrl: _apiBaseController.text,
      limit: 150,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pulled $count server log entries.')),
    );
  }

  Widget _buildOnlineBoardSurface({required bool canStart}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = constraints.maxHeight < constraints.maxWidth
                ? constraints.maxHeight
                : constraints.maxWidth;
            final boardSkin = SkinCatalog.backgammonBoardById(
              SkinCatalog.defaultBackgammonBoardSkinId,
            );
            final whitePieceSkin = SkinCatalog.backgammonPieceById(
              _controller.pieceSkinIdForColor('w'),
            );
            final blackPieceSkin = SkinCatalog.backgammonPieceById(
              _controller.pieceSkinIdForColor('b'),
            );
            return Center(
              child: SizedBox(
                width: boardSize,
                height: boardSize,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SheshBeshBoardView(
                        points: List<SheshBeshPoint>.generate(
                          24,
                          (_) => const SheshBeshPoint(),
                          growable: false,
                        ),
                        playerColor: _controller.myColor ?? 'w',
                        turnColor: _controller.turnColor ?? 'w',
                        boardSkin: boardSkin,
                        whitePieceSkin: whitePieceSkin,
                        blackPieceSkin: blackPieceSkin,
                        whiteBar: 0,
                        blackBar: 0,
                        whiteBorneOff: 0,
                        blackBorneOff: 0,
                        selectedPoint: null,
                        selectedFromBar: false,
                        playableSourcePoints: const <int>{},
                        barPlayable: false,
                        legalTargetPoints: const <int>{},
                        targetDiceSpentHints: const <int, int>{},
                        canBearOffTarget: false,
                        onPointTap: (_) {},
                        onPointLongPress: (_) {},
                        onBarTap: () {},
                        onBearOffTap: () {},
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (!_controller.isConnected)
                      Positioned.fill(
                        child: _buildBoardOverlay(
                          title: 'Online Board Ready',
                          subtitle:
                              'Find a match to start syncing live game state.',
                          actionLabel: 'Find Match',
                          onAction: canStart ? _findMatch : null,
                        ),
                      )
                    else if (_controller.isWaitingForOpponent)
                      Positioned.fill(
                        child: _buildBoardOverlay(
                          title: 'Waiting For Opponent',
                          subtitle:
                              'Board remains visible while matchmaking completes.',
                          loading: true,
                        ),
                      )
                    else
                      Positioned(
                        left: 10,
                        top: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              'Match ${_controller.matchId ?? '-'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBoardOverlay({
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    bool loading = false,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE6E6E6), fontSize: 12),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionStatusCard(List<String> tailHistory) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Status',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _statusRow('Connection', _controller.connectionState.name),
            _statusRow('Match ID', _controller.matchId ?? '-'),
            _statusRow('Status', _controller.statusText),
            _statusRow('My Color', _controller.myColor ?? '-'),
            _statusRow('Turn', _controller.turnColor ?? '-'),
            _statusRow('Result', _controller.resultCode ?? '-'),
            _statusRow(
              'White Cooldown',
              _formatDuration(_controller.cooldownRemaining('w')),
            ),
            _statusRow(
              'Black Cooldown',
              _formatDuration(_controller.cooldownRemaining('b')),
            ),
            _statusRow(
              'Players',
              'W: ${_controller.whitePlayerName ?? '-'} | '
                  'B: ${_controller.blackPlayerName ?? '-'}',
            ),
            if (_controller.feedback != null) ...[
              const SizedBox(height: 8),
              Text(
                _controller.feedback!,
                style: const TextStyle(
                  color: Color(0xFFB71C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Server History',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x1A000000)),
                ),
                child: tailHistory.isEmpty
                    ? const Center(
                        child: Text(
                          'No state history yet.',
                          style: TextStyle(color: Color(0xFF707070)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: tailHistory.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final entry = tailHistory[index];
                          return Text(
                            '• $entry',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2A2A2A),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportDebugCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transport Debug',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Infrastructure is active. Gameplay move semantics can plug into this connection layer.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5A554F)),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1115),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _controller.debugLogEntries.isEmpty
                    ? const Center(
                        child: Text(
                          'No debug events yet.',
                          style: TextStyle(color: Color(0xFF9EA3AA)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _controller.debugLogEntries.length,
                        itemBuilder: (context, index) {
                          final line = _controller.debugLogEntries[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Color(0xFFC8CCD2),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Latest State Snapshot',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x1A000000)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _prettyJson(_controller.latestState),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF2B2B2B),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  static String _prettyJson(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return '{ }';
    }
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(map);
  }

  static String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    final halfSecondValue = halfSteps / 2;
    return '${halfSecondValue.toStringAsFixed(1)}s';
  }
}

class _BackendHealthCard extends StatelessWidget {
  const _BackendHealthCard({
    required this.state,
    required this.message,
    required this.checkedAt,
    required this.busy,
    required this.onCheckPressed,
    required this.onWakePressed,
  });

  final BackendHealthState state;
  final String? message;
  final DateTime? checkedAt;
  final bool busy;
  final VoidCallback onCheckPressed;
  final VoidCallback onWakePressed;

  @override
  Widget build(BuildContext context) {
    final statusText = switch (state) {
      BackendHealthState.unknown => 'Unknown',
      BackendHealthState.checking => 'Checking...',
      BackendHealthState.healthy => 'Healthy',
      BackendHealthState.unhealthy => 'Unhealthy',
    };

    final statusColor = switch (state) {
      BackendHealthState.unknown => const Color(0xFF616161),
      BackendHealthState.checking => const Color(0xFF1565C0),
      BackendHealthState.healthy => const Color(0xFF2E7D32),
      BackendHealthState.unhealthy => const Color(0xFFC62828),
    };

    final checkedLabel = checkedAt == null
        ? 'Not checked yet'
        : 'Checked: ${checkedAt!.toLocal().toIso8601String().substring(11, 19)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1A000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  checkedLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6A635A),
                  ),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A554F)),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onCheckPressed,
                  icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                  label: const Text('Check'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onWakePressed,
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  label: const Text('Wake'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
