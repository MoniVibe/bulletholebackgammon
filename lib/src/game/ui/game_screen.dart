import 'dart:math' as math;

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/local_game_controller.dart';
import 'app_assets.dart';
import 'backgammon_online_panel.dart';
import 'sheshbesh_board_view.dart';
import 'skin_catalog.dart';

enum _GameMode { local, online }

enum _NewGameColor { white, black, random }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const List<int> _cooldownOptionsSeconds = [2, 3, 5, 7, 10];
  static const double _chatRailWidth = 330;
  static const double _compactChatHeight = 240;
  static const Set<String> _ownedBackgammonPieceSkinIds = <String>{
    'bg_ruby',
    'bg_royal',
    'bg_minimal',
  };

  late final LocalGameController _controller;
  late final TextEditingController _chatInputController;
  final math.Random _uiRandom = math.Random();
  final List<GameChatEntry> _chatEntries = <GameChatEntry>[];
  bool _isGameMenuOpen = false;
  _GameMode _mode = _GameMode.local;
  int _selectedCooldownSeconds = 3;
  String _selectedBoardSkinId = SkinCatalog.defaultBackgammonBoardSkinId;
  String _selectedPlayerPieceSkinId = SkinCatalog.defaultBackgammonPieceSkinId;
  TimeBarOrientation _timeBarOrientation = TimeBarOrientation.horizontal;
  bool _didPrecacheVisualAssets = false;

  @override
  void initState() {
    super.initState();
    _controller = LocalGameController(
      initialCooldownDuration: Duration(seconds: _selectedCooldownSeconds),
    );
    _chatInputController = TextEditingController();
    _chatEntries.add(
      GameChatEntry(
        author: 'System',
        message:
            'Chat is docked on the board side. Online message transport can plug into this panel.',
        sentAt: DateTime.now(),
        isMine: false,
      ),
    );
  }

  @override
  void dispose() {
    _chatInputController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheVisualAssets) {
      return;
    }
    _didPrecacheVisualAssets = true;
    _precacheVisualAssets();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  AppAssets.appBackground,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(color: Color(0xFFF2EFEA));
                  },
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.34),
                        Colors.white.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.03),
                      ],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _mode == _GameMode.local
                                  ? 'Sheshbesh Local'
                                  : 'Sheshbesh Online',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          CompactModeSwitch(
                            onlineSelected: _mode == _GameMode.online,
                            onChanged: (online) {
                              setState(() {
                                _mode = online
                                    ? _GameMode.online
                                    : _GameMode.local;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _mode == _GameMode.local
                          ? _buildLocalView()
                          : const BackgammonOnlinePanel(showModeSwitch: false),
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

  Widget _buildLocalView() {
    final history = _controller.history;
    final tailHistory = history.length > 10
        ? history.sublist(history.length - 10)
        : history;
    final boardSkin = SkinCatalog.backgammonBoardById(_selectedBoardSkinId);
    final playerPieceSkin = SkinCatalog.backgammonPieceById(
      _selectedPlayerPieceSkinId,
    );
    final opponentPieceSkin = SkinCatalog.backgammonPieceById(
      SkinCatalog.defaultBackgammonPieceSkinId,
    );
    final whitePieceSkin = _controller.playerColor == 'w'
        ? playerPieceSkin
        : opponentPieceSkin;
    final blackPieceSkin = _controller.playerColor == 'b'
        ? playerPieceSkin
        : opponentPieceSkin;
    final whiteSkinId = _controller.playerColor == 'w'
        ? _selectedPlayerPieceSkinId
        : SkinCatalog.defaultBackgammonPieceSkinId;
    final blackSkinId = _controller.playerColor == 'b'
        ? _selectedPlayerPieceSkinId
        : SkinCatalog.defaultBackgammonPieceSkinId;
    final invertBlackChipColors = _shouldInvertBlackBackgammonPieces(
      whiteSkin: whitePieceSkin,
      blackSkin: blackPieceSkin,
      whiteSkinId: whiteSkinId,
      blackSkinId: blackSkinId,
    );

    final whiteRemaining = _controller.timerRemaining('w');
    final blackRemaining = _controller.timerRemaining('b');
    final whiteDiceLabel = _controller.diceForColor('w').isEmpty
        ? '-'
        : _controller.diceForColor('w').join(' ');
    final blackDiceLabel = _controller.diceForColor('b').isEmpty
        ? '-'
        : _controller.diceForColor('b').join(' ');
    final showSideChatRail = MediaQuery.sizeOf(context).width >= 1220;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          CollapsibleSettingsCard(
            title: 'Game Menu',
            isOpen: _isGameMenuOpen,
            onToggle: () {
              setState(() {
                _isGameMenuOpen = !_isGameMenuOpen;
              });
            },
            leading: const AppAssetIcon(
              AppAssets.settingsIcon,
              fallbackIcon: Icons.settings,
              size: 22,
            ),
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _selectedCooldownSeconds,
                  decoration: const InputDecoration(
                    labelText: 'Turn Cooldown (seconds)',
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
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedCooldownSeconds = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                TimeBarOrientationSwitch(
                  orientation: _timeBarOrientation,
                  onChanged: (orientation) {
                    setState(() {
                      _timeBarOrientation = orientation;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('bg_board_skin_$_selectedBoardSkinId'),
                  initialValue: _selectedBoardSkinId,
                  decoration: const InputDecoration(
                    labelText: 'Select Board',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _backgammonBoardDropdownItems(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedBoardSkinId = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'bg_player_skin_$_selectedPlayerPieceSkinId',
                  ),
                  initialValue: _selectedPlayerPieceSkinId,
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
                      _selectedPlayerPieceSkinId = value;
                    });
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Applies to your own side only. Opponent keeps default skin.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6A635A),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _showNewGamePrompt,
                    icon: const AppAssetIcon(
                      AppAssets.newGameIcon,
                      fallbackIcon: Icons.refresh,
                      size: 20,
                    ),
                    label: const Text('New Game'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!showSideChatRail) {
                  return _buildBoardPane(
                    constraints: constraints,
                    boardSkin: boardSkin,
                    whitePieceSkin: whitePieceSkin,
                    blackPieceSkin: blackPieceSkin,
                    invertBlackChipColors: invertBlackChipColors,
                    whiteRemaining: whiteRemaining,
                    blackRemaining: blackRemaining,
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, boardConstraints) {
                          return _buildBoardPane(
                            constraints: boardConstraints,
                            boardSkin: boardSkin,
                            whitePieceSkin: whitePieceSkin,
                            blackPieceSkin: blackPieceSkin,
                            invertBlackChipColors: invertBlackChipColors,
                            whiteRemaining: whiteRemaining,
                            blackRemaining: blackRemaining,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: _chatRailWidth,
                      child: _buildLocalChatPanel(
                        title: 'Match Chat',
                        helper:
                            'Docked beside the board for always-on visibility.',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dice:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _controller.hasActiveGame
                          ? 'W: $whiteDiceLabel | B: $blackDiceLabel'
                          : '-',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_controller.statusText)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Log:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tailHistory.isEmpty ? '-' : tailHistory.join('  '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!showSideChatRail) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: _compactChatHeight,
              child: _buildLocalChatPanel(
                title: 'Match Chat',
                helper: 'Pinned below game stats on smaller screens.',
              ),
            ),
          ],
        ],
      ),
    );
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

  bool _shouldInvertBlackBackgammonPieces({
    required PieceSkinOption whiteSkin,
    required PieceSkinOption blackSkin,
    required String whiteSkinId,
    required String blackSkinId,
  }) {
    if (whiteSkinId != blackSkinId) {
      return false;
    }
    if (whiteSkin.mode != PieceSkinRenderMode.image ||
        blackSkin.mode != PieceSkinRenderMode.image) {
      return false;
    }
    final whiteAsset = whiteSkin.assetForColor('w');
    final blackAsset = blackSkin.assetForColor('b');
    return whiteAsset != null && whiteAsset == blackAsset;
  }

  Widget _buildBoardPane({
    required BoxConstraints constraints,
    required BoardSkinOption boardSkin,
    required PieceSkinOption whitePieceSkin,
    required PieceSkinOption blackPieceSkin,
    required bool invertBlackChipColors,
    required Duration whiteRemaining,
    required Duration blackRemaining,
  }) {
    if (_timeBarOrientation == TimeBarOrientation.vertical) {
      return _buildBoardPaneVertical(
        constraints: constraints,
        boardSkin: boardSkin,
        whitePieceSkin: whitePieceSkin,
        blackPieceSkin: blackPieceSkin,
        invertBlackChipColors: invertBlackChipColors,
        whiteRemaining: whiteRemaining,
        blackRemaining: blackRemaining,
      );
    }
    return _buildBoardPaneHorizontal(
      constraints: constraints,
      boardSkin: boardSkin,
      whitePieceSkin: whitePieceSkin,
      blackPieceSkin: blackPieceSkin,
      invertBlackChipColors: invertBlackChipColors,
      whiteRemaining: whiteRemaining,
      blackRemaining: blackRemaining,
    );
  }

  Widget _buildBoardPaneHorizontal({
    required BoxConstraints constraints,
    required BoardSkinOption boardSkin,
    required PieceSkinOption whitePieceSkin,
    required PieceSkinOption blackPieceSkin,
    required bool invertBlackChipColors,
    required Duration whiteRemaining,
    required Duration blackRemaining,
  }) {
    const barHeight = 58.0;
    const boardGap = 10.0;
    const sideHudGap = 12.0;
    const minSideHudWidth = 170.0;

    final boardSizeByHeight =
        constraints.maxHeight - (barHeight * 2) - (boardGap * 2);
    if (boardSizeByHeight <= 0) {
      return const SizedBox.shrink();
    }

    final canShowSideHud =
        constraints.maxWidth >=
        (boardSizeByHeight + (minSideHudWidth * 2) + (sideHudGap * 2));
    final boardSize = math.min(
      boardSizeByHeight,
      canShowSideHud ? boardSizeByHeight : constraints.maxWidth,
    );
    if (boardSize <= 0) {
      return const SizedBox.shrink();
    }

    final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
    final bottomColor = _controller.playerColor;
    final whiteIsPlayer = _controller.playerColor == 'w';
    final blackIsPlayer = _controller.playerColor == 'b';
    final topRemaining = topColor == 'w' ? whiteRemaining : blackRemaining;
    final bottomRemaining = bottomColor == 'w'
        ? whiteRemaining
        : blackRemaining;
    final topIsPlayer = topColor == 'w' ? whiteIsPlayer : blackIsPlayer;
    final bottomIsPlayer = bottomColor == 'w' ? whiteIsPlayer : blackIsPlayer;
    final topActiveColor = topColor == 'w'
        ? const Color(0xFF42A5F5)
        : const Color(0xFFFF7043);
    final bottomActiveColor = bottomColor == 'w'
        ? const Color(0xFF42A5F5)
        : const Color(0xFFFF7043);
    final topFlashTint = topColor == 'w'
        ? const Color(0xFFBBDEFB)
        : const Color(0xFFFFCCBC);
    final bottomFlashTint = bottomColor == 'w'
        ? const Color(0xFFBBDEFB)
        : const Color(0xFFFFCCBC);
    final sideHudWidth = canShowSideHud
        ? (constraints.maxWidth - boardSize - (sideHudGap * 2)) / 2
        : 0.0;
    final diceForWhite = _controller.diceForColor('w');
    final diceForBlack = _controller.diceForColor('b');
    final topDice = topColor == 'w' ? diceForWhite : diceForBlack;
    final bottomDice = bottomColor == 'w' ? diceForWhite : diceForBlack;

    return Center(
      child: SizedBox(
        width: canShowSideHud ? constraints.maxWidth : boardSize,
        height: boardSize + (barHeight * 2) + (boardGap * 2),
        child: Column(
          children: [
            SizedBox(
              height: barHeight,
              child: CooldownMeter(
                key: const ValueKey('top_bar'),
                label: topColor == 'w' ? 'W' : 'B',
                remaining: topRemaining,
                total: _controller.cooldownDuration,
                horizontalPrimaryAssetPath: AppAssets.horizontalTimeBarAccent,
                horizontalFallbackAssetPath: AppAssets.horizontalTimeBar,
                verticalPrimaryAssetPath: AppAssets.verticalTimeBarAccent,
                verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                diceFaceAssetBuilder: AppAssets.diceFaceAsset,
                diceFaces: topDice,
                orientation: TimeBarOrientation.horizontal,
                activeColor: topActiveColor,
                isPlayerSide: topIsPlayer,
                timeLabel: _controller.hasActiveGame
                    ? _formatDuration(topRemaining)
                    : '--',
                readyToFlash:
                    _controller.hasActiveGame &&
                    !_controller.isGameOver &&
                    _controller.hasActiveDice(topColor) &&
                    topRemaining.inMilliseconds == 0,
                flashTint: topFlashTint,
                flashDuration: const Duration(milliseconds: 700),
              ),
            ),
            const SizedBox(height: boardGap),
            SizedBox(
              height: boardSize,
              child: Row(
                children: [
                  if (canShowSideHud)
                    SizedBox(
                      width: sideHudWidth,
                      child: _buildTurnSidePanel(
                        sideColor: 'w',
                        isActive:
                            _controller.hasActiveGame &&
                            _controller.hasActiveDice('w'),
                        dice: diceForWhite,
                      ),
                    ),
                  if (canShowSideHud) const SizedBox(width: sideHudGap),
                  _buildBoardStack(
                    boardSize: boardSize,
                    boardSkin: boardSkin,
                    whitePieceSkin: whitePieceSkin,
                    blackPieceSkin: blackPieceSkin,
                    invertBlackChipColors: invertBlackChipColors,
                  ),
                  if (canShowSideHud) const SizedBox(width: sideHudGap),
                  if (canShowSideHud)
                    SizedBox(
                      width: sideHudWidth,
                      child: _buildTurnSidePanel(
                        sideColor: 'b',
                        isActive:
                            _controller.hasActiveGame &&
                            _controller.hasActiveDice('b'),
                        dice: diceForBlack,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: boardGap),
            SizedBox(
              height: barHeight,
              child: CooldownMeter(
                key: const ValueKey('bottom_bar'),
                label: bottomColor == 'w' ? 'W' : 'B',
                remaining: bottomRemaining,
                total: _controller.cooldownDuration,
                horizontalPrimaryAssetPath: AppAssets.horizontalTimeBarAccent,
                horizontalFallbackAssetPath: AppAssets.horizontalTimeBar,
                verticalPrimaryAssetPath: AppAssets.verticalTimeBarAccent,
                verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                diceFaceAssetBuilder: AppAssets.diceFaceAsset,
                diceFaces: bottomDice,
                orientation: TimeBarOrientation.horizontal,
                activeColor: bottomActiveColor,
                isPlayerSide: bottomIsPlayer,
                timeLabel: _controller.hasActiveGame
                    ? _formatDuration(bottomRemaining)
                    : '--',
                readyToFlash:
                    _controller.hasActiveGame &&
                    !_controller.isGameOver &&
                    _controller.hasActiveDice(bottomColor) &&
                    bottomRemaining.inMilliseconds == 0,
                flashTint: bottomFlashTint,
                flashDuration: const Duration(milliseconds: 700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardPaneVertical({
    required BoxConstraints constraints,
    required BoardSkinOption boardSkin,
    required PieceSkinOption whitePieceSkin,
    required PieceSkinOption blackPieceSkin,
    required bool invertBlackChipColors,
    required Duration whiteRemaining,
    required Duration blackRemaining,
  }) {
    const barWidth = 64.0;
    const boardGap = 10.0;

    final boardSizeByWidth =
        constraints.maxWidth - (barWidth * 2) - (boardGap * 2);
    if (boardSizeByWidth <= 0) {
      return const SizedBox.shrink();
    }
    final boardSize = math.min(boardSizeByWidth, constraints.maxHeight);
    if (boardSize <= 0) {
      return const SizedBox.shrink();
    }

    final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
    final bottomColor = _controller.playerColor;
    final whiteIsPlayer = _controller.playerColor == 'w';
    final blackIsPlayer = _controller.playerColor == 'b';
    final topRemaining = topColor == 'w' ? whiteRemaining : blackRemaining;
    final bottomRemaining = bottomColor == 'w'
        ? whiteRemaining
        : blackRemaining;
    final topIsPlayer = topColor == 'w' ? whiteIsPlayer : blackIsPlayer;
    final bottomIsPlayer = bottomColor == 'w' ? whiteIsPlayer : blackIsPlayer;
    final topActiveColor = topColor == 'w'
        ? const Color(0xFF42A5F5)
        : const Color(0xFFFF7043);
    final bottomActiveColor = bottomColor == 'w'
        ? const Color(0xFF42A5F5)
        : const Color(0xFFFF7043);
    final topFlashTint = topColor == 'w'
        ? const Color(0xFFBBDEFB)
        : const Color(0xFFFFCCBC);
    final bottomFlashTint = bottomColor == 'w'
        ? const Color(0xFFBBDEFB)
        : const Color(0xFFFFCCBC);
    final diceForWhite = _controller.diceForColor('w');
    final diceForBlack = _controller.diceForColor('b');
    final topDice = topColor == 'w' ? diceForWhite : diceForBlack;
    final bottomDice = bottomColor == 'w' ? diceForWhite : diceForBlack;

    return Center(
      child: SizedBox(
        width: boardSize + (barWidth * 2) + (boardGap * 2),
        height: boardSize,
        child: Row(
          children: [
            SizedBox(
              width: barWidth,
              child: CooldownMeter(
                key: const ValueKey('top_bar'),
                label: topColor == 'w' ? 'W' : 'B',
                remaining: topRemaining,
                total: _controller.cooldownDuration,
                horizontalPrimaryAssetPath: AppAssets.horizontalTimeBarAccent,
                horizontalFallbackAssetPath: AppAssets.horizontalTimeBar,
                verticalPrimaryAssetPath: AppAssets.verticalTimeBarAccent,
                verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                diceFaceAssetBuilder: AppAssets.diceFaceAsset,
                diceFaces: topDice,
                orientation: TimeBarOrientation.vertical,
                activeColor: topActiveColor,
                isPlayerSide: topIsPlayer,
                timeLabel: _controller.hasActiveGame
                    ? _formatDuration(topRemaining)
                    : '--',
                readyToFlash:
                    _controller.hasActiveGame &&
                    !_controller.isGameOver &&
                    _controller.hasActiveDice(topColor) &&
                    topRemaining.inMilliseconds == 0,
                flashTint: topFlashTint,
                flashDuration: const Duration(milliseconds: 700),
              ),
            ),
            const SizedBox(width: boardGap),
            _buildBoardStack(
              boardSize: boardSize,
              boardSkin: boardSkin,
              whitePieceSkin: whitePieceSkin,
              blackPieceSkin: blackPieceSkin,
              invertBlackChipColors: invertBlackChipColors,
            ),
            const SizedBox(width: boardGap),
            SizedBox(
              width: barWidth,
              child: CooldownMeter(
                key: const ValueKey('bottom_bar'),
                label: bottomColor == 'w' ? 'W' : 'B',
                remaining: bottomRemaining,
                total: _controller.cooldownDuration,
                horizontalPrimaryAssetPath: AppAssets.horizontalTimeBarAccent,
                horizontalFallbackAssetPath: AppAssets.horizontalTimeBar,
                verticalPrimaryAssetPath: AppAssets.verticalTimeBarAccent,
                verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                diceFaceAssetBuilder: AppAssets.diceFaceAsset,
                diceFaces: bottomDice,
                orientation: TimeBarOrientation.vertical,
                activeColor: bottomActiveColor,
                isPlayerSide: bottomIsPlayer,
                timeLabel: _controller.hasActiveGame
                    ? _formatDuration(bottomRemaining)
                    : '--',
                readyToFlash:
                    _controller.hasActiveGame &&
                    !_controller.isGameOver &&
                    _controller.hasActiveDice(bottomColor) &&
                    bottomRemaining.inMilliseconds == 0,
                flashTint: bottomFlashTint,
                flashDuration: const Duration(milliseconds: 700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardStack({
    required double boardSize,
    required BoardSkinOption boardSkin,
    required PieceSkinOption whitePieceSkin,
    required PieceSkinOption blackPieceSkin,
    required bool invertBlackChipColors,
  }) {
    return SizedBox(
      width: boardSize,
      height: boardSize,
      child: Stack(
        children: [
          SheshBeshBoardView(
            points: _controller.points,
            playerColor: _controller.playerColor,
            turnColor: _controller.turnColor,
            boardSkin: boardSkin,
            whitePieceSkin: whitePieceSkin,
            blackPieceSkin: blackPieceSkin,
            whiteBar: _controller.barCount('w'),
            blackBar: _controller.barCount('b'),
            whiteBorneOff: _controller.borneOffCount('w'),
            blackBorneOff: _controller.borneOffCount('b'),
            selectedPoint: _controller.selectedPoint,
            selectedFromBar: _controller.selectedFromBar,
            playableSourcePoints: _controller.playableSourcePoints,
            barPlayable: _controller.canEnterFromBar,
            legalTargetPoints: _controller.legalTargetPoints,
            targetDiceSpentHints: _controller.targetDiceSpentHints,
            invertBlackPieceColors: invertBlackChipColors,
            canBearOffTarget: _controller.canBearOffTarget,
            playerLastMove: _controller.playerLastMove,
            opponentLastMove: _controller.opponentLastMove,
            onPointTap: _controller.tapPoint,
            onPointLongPress: _controller.longPressPoint,
            onBarTap: _controller.tapBar,
            onBearOffTap: _controller.tapBearOff,
          ),
          if (!_controller.hasActiveGame)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _showNewGamePrompt,
                    icon: const AppAssetIcon(
                      AppAssets.newGameIcon,
                      fallbackIcon: Icons.play_arrow,
                      size: 20,
                    ),
                    label: const Text('Start New Game'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTurnSidePanel({
    required String sideColor,
    required bool isActive,
    required List<int> dice,
  }) {
    final accent = sideColor == 'w'
        ? const Color(0xFF9ADFFF)
        : const Color(0xFFFFC2A0);
    final label = sideColor == 'w' ? 'White' : 'Black';

    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = math.max(80.0, constraints.maxWidth - 20);
        final largeSize = ((usableWidth - 8) / 2).clamp(60.0, 82.0);
        final singleSize = (usableWidth - 8).clamp(68.0, 92.0);
        final dieSize = dice.length <= 1 ? singleSize : largeSize;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black.withValues(alpha: isActive ? 0.32 : 0.14),
            border: Border.all(
              color: accent.withValues(alpha: isActive ? 0.95 : 0.34),
              width: isActive ? 2.2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isActive ? 0.24 : 0.08),
                blurRadius: isActive ? 22 : 12,
                spreadRadius: isActive ? 1.5 : 0.3,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isActive ? '$label Turn' : '$label Waiting',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.35,
                    color: Colors.white.withValues(alpha: 0.97),
                    shadows: const <Shadow>[
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (dice.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: dice
                        .map(
                          (face) => _SideDiceFace(
                            face: face,
                            size: dieSize.toDouble(),
                          ),
                        )
                        .toList(growable: false),
                  )
                else
                  Text(
                    '...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
              ],
            ),
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

  List<DropdownMenuItem<String>> _backgammonBoardDropdownItems() {
    final board = SkinCatalog.backgammonBoardById(
      SkinCatalog.defaultBackgammonBoardSkinId,
    );
    return <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(value: board.id, child: Text(board.label)),
    ];
  }

  Widget _buildLocalChatPanel({required String title, required String helper}) {
    return GameChatPanel(
      title: title,
      helperText: helper,
      entries: _chatEntries,
      inputController: _chatInputController,
      onSend: _sendLocalChatMessage,
    );
  }

  Future<void> _showNewGamePrompt() async {
    final choice = await showModalBottomSheet<_NewGameColor>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.circle_outlined),
                title: const Text('Play White'),
                onTap: () => Navigator.of(context).pop(_NewGameColor.white),
              ),
              ListTile(
                leading: const Icon(Icons.circle),
                title: const Text('Play Black'),
                onTap: () => Navigator.of(context).pop(_NewGameColor.black),
              ),
              ListTile(
                leading: const Icon(Icons.shuffle),
                title: const Text('Random'),
                onTap: () => Navigator.of(context).pop(_NewGameColor.random),
              ),
            ],
          ),
        );
      },
    );

    if (choice == null) {
      return;
    }

    final playerAsWhite = switch (choice) {
      _NewGameColor.white => true,
      _NewGameColor.black => false,
      _NewGameColor.random => _uiRandom.nextBool(),
    };
    _startNewGame(playerAsWhite: playerAsWhite);
  }

  void _startNewGame({required bool playerAsWhite}) {
    _controller.startNewGame(
      playerAsWhite: playerAsWhite,
      cooldownDuration: Duration(seconds: _selectedCooldownSeconds),
    );
    setState(() {
      _isGameMenuOpen = false;
    });
  }

  void _sendLocalChatMessage() {
    final message = _chatInputController.text.trim();
    if (message.isEmpty) {
      return;
    }

    setState(() {
      _chatEntries.add(
        GameChatEntry(
          author: 'You',
          message: message,
          sentAt: DateTime.now(),
          isMine: true,
        ),
      );
      _chatInputController.clear();
    });
  }

  void _precacheVisualAssets() {
    final boardAssets = SkinCatalog.backgammonBoardSkins
        .map((skin) => skin.assetPath)
        .whereType<String>();
    final pieceAssets = SkinCatalog.backgammonPieceSkins.expand((skin) sync* {
      if (skin.whiteAssetPath != null) {
        yield skin.whiteAssetPath!;
      }
      if (skin.blackAssetPath != null) {
        yield skin.blackAssetPath!;
      }
    });
    final uniqueAssets = <String>{
      AppAssets.appBackground,
      AppAssets.backgammonBoardClassic,
      AppAssets.horizontalTimeBar,
      AppAssets.verticalTimeBar,
      AppAssets.horizontalTimeBarAccent,
      AppAssets.verticalTimeBarAccent,
      AppAssets.settingsIcon,
      AppAssets.newGameIcon,
      AppAssets.rematchIcon,
      AppAssets.feedbackIcon,
      AppAssets.whiteCoin,
      AppAssets.blackCoin,
      ...AppAssets.diceFaces.values,
      ...boardAssets,
      ...pieceAssets,
    };
    for (final assetPath in uniqueAssets) {
      // Optional/locked cosmetics can be absent in local dev packs.
      // Ignore preload failures so one missing asset does not break startup.
      precacheImage(
        AssetImage(assetPath),
        context,
        onError: (Object _, StackTrace? stackTrace) {},
      );
    }
  }
}

class _SideDiceFace extends StatelessWidget {
  const _SideDiceFace({required this.face, required this.size});

  final int face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = AppAssets.diceFaceAsset(face);
    if (asset == null) {
      return _fallbackFace();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => _fallbackFace(),
        ),
      ),
    );
  }

  Widget _fallbackFace() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$face',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF212121),
          fontSize: 22,
        ),
      ),
    );
  }
}
