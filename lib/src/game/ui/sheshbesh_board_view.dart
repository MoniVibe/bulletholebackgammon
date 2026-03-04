import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/sheshbesh_model.dart';
import 'skin_catalog.dart';

class SheshBeshBoardView extends StatelessWidget {
  const SheshBeshBoardView({
    required this.points,
    required this.playerColor,
    required this.turnColor,
    required this.boardSkin,
    required this.whitePieceSkin,
    required this.blackPieceSkin,
    required this.whiteBar,
    required this.blackBar,
    required this.whiteBorneOff,
    required this.blackBorneOff,
    required this.selectedPoint,
    required this.selectedFromBar,
    required this.playableSourcePoints,
    required this.barPlayable,
    required this.legalTargetPoints,
    required this.targetDiceSpentHints,
    this.invertBlackPieceColors = false,
    required this.canBearOffTarget,
    required this.onPointTap,
    required this.onPointLongPress,
    required this.onBarTap,
    required this.onBearOffTap,
    this.playerLastMove,
    this.opponentLastMove,
    super.key,
  }) : assert(points.length == 24);

  final List<SheshBeshPoint> points;
  final String playerColor;
  final String turnColor;
  final BoardSkinOption boardSkin;
  final PieceSkinOption whitePieceSkin;
  final PieceSkinOption blackPieceSkin;
  final int whiteBar;
  final int blackBar;
  final int whiteBorneOff;
  final int blackBorneOff;
  final int? selectedPoint;
  final bool selectedFromBar;
  final Set<int> playableSourcePoints;
  final bool barPlayable;
  final Set<int> legalTargetPoints;
  final Map<int, int> targetDiceSpentHints;
  final bool invertBlackPieceColors;
  final bool canBearOffTarget;
  final SheshBeshMove? playerLastMove;
  final SheshBeshMove? opponentLastMove;
  final ValueChanged<int> onPointTap;
  final ValueChanged<int> onPointLongPress;
  final VoidCallback onBarTap;
  final VoidCallback onBearOffTap;

  static const _maxVisibleStack = 5;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final geometry = _BoardGeometry.fromSize(boardSize);
            final pointRects = _buildPointRects(geometry);

            return Center(
              child: SizedBox(
                width: boardSize,
                height: boardSize,
                child: Stack(
                  children: [
                    _buildBoardBackground(boardSize, geometry),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BoardOverlayPainter(
                          geometry: geometry,
                          activeColor: turnColor,
                        ),
                      ),
                    ),
                    ..._buildPointHitboxes(pointRects),
                    ..._buildPointCheckers(
                      pointRects,
                      boardCenterY: geometry.innerRect.center.dy,
                    ),
                    ..._buildMoveHighlights(pointRects),
                    ..._buildDiceUsageBadges(
                      pointRects,
                      boardCenterY: geometry.innerRect.center.dy,
                    ),
                    _buildBarArea(geometry),
                    ..._buildBarCheckers(geometry),
                    _buildBorneOffBadge(
                      color: 'w',
                      count: whiteBorneOff,
                      alignment: playerColor == 'w'
                          ? Alignment.bottomRight
                          : Alignment.topLeft,
                    ),
                    _buildBorneOffBadge(
                      color: 'b',
                      count: blackBorneOff,
                      alignment: playerColor == 'w'
                          ? Alignment.topRight
                          : Alignment.bottomLeft,
                    ),
                    if (canBearOffTarget)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: FilledButton.tonal(
                          onPressed: onBearOffTap,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          child: const Text('Bear Off'),
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

  Widget _buildBoardBackground(double boardSize, _BoardGeometry geometry) {
    if (boardSkin.assetPath == null) {
      return CustomPaint(
        size: Size.square(boardSize),
        painter: _BoardPainter(geometry: geometry),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          boardSkin.assetPath!,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return CustomPaint(
              size: Size.square(boardSize),
              painter: _BoardPainter(geometry: geometry),
            );
          },
        ),
        if (boardSkin.tintOverlay != null)
          ColoredBox(color: boardSkin.tintOverlay!),
      ],
    );
  }

  Map<int, Rect> _buildPointRects(_BoardGeometry geometry) {
    final mapping = <int, Rect>{};
    for (var column = 0; column < 12; column++) {
      final topIndex = _boardIndexForCell(top: true, column: column);
      final bottomIndex = _boardIndexForCell(top: false, column: column);
      mapping[topIndex] = geometry.topPointRect(column);
      mapping[bottomIndex] = geometry.bottomPointRect(column);
    }
    return mapping;
  }

  int _boardIndexForCell({required bool top, required int column}) {
    final base = top ? (12 + column) : (11 - column);
    if (playerColor == 'w') {
      return base;
    }
    return 23 - base;
  }

  List<Widget> _buildPointHitboxes(Map<int, Rect> pointRects) {
    return pointRects.entries
        .map((entry) {
          final point = entry.key;
          final rect = entry.value;
          final selected = selectedPoint == point;
          final playableSource = playableSourcePoints.contains(point);
          final legalTarget = legalTargetPoints.contains(point);

          final borderColor = selected
              ? const Color(0xFF1DE9B6)
              : (legalTarget
                    ? const Color(0xAA26A69A)
                    : (playableSource
                          ? const Color(0x9932D1C8)
                          : Colors.transparent));
          final fillColor = playableSource && !selected && !legalTarget
              ? const Color(0x1532D1C8)
              : Colors.transparent;

          return Positioned.fromRect(
            rect: rect,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onPointTap(point),
                onLongPress: () => onPointLongPress(point),
                splashColor: const Color(0x2200BCD4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fillColor,
                    border: Border.all(
                      color: borderColor,
                      width: selected ? 2.4 : 1.6,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          );
        })
        .toList(growable: false);
  }

  List<Widget> _buildPointCheckers(
    Map<int, Rect> pointRects, {
    required double boardCenterY,
  }) {
    final widgets = <Widget>[];

    for (final entry in pointRects.entries) {
      final pointIndex = entry.key;
      final pointRect = entry.value;
      final stack = points[pointIndex];
      if (stack.isEmpty) {
        continue;
      }

      final tokenSize = pointRect.width * 0.88;
      final visibleCount = math.min(stack.count, _maxVisibleStack);
      final isTopRow = pointRect.center.dy < boardCenterY;
      final sourcePlayable = playableSourcePoints.contains(pointIndex);

      for (var i = 0; i < visibleCount; i++) {
        final y = isTopRow
            ? pointRect.top + 3 + (i * (tokenSize * 0.5))
            : pointRect.bottom - tokenSize - 3 - (i * (tokenSize * 0.5));
        final x = pointRect.center.dx - (tokenSize / 2);

        widgets.add(
          Positioned(
            left: x,
            top: y,
            width: tokenSize,
            height: tokenSize,
            child: i == 0 && sourcePlayable
                ? _PlayableCoinGlow(
                    child: _CoinSprite(
                      color: stack.color!,
                      pieceSkin: _pieceSkinForColor(stack.color!),
                      invertColors: _shouldInvertForColor(stack.color!),
                    ),
                  )
                : _CoinSprite(
                    color: stack.color!,
                    pieceSkin: _pieceSkinForColor(stack.color!),
                    invertColors: _shouldInvertForColor(stack.color!),
                  ),
          ),
        );
      }

      if (stack.count > _maxVisibleStack) {
        widgets.add(
          Positioned(
            left: pointRect.right - 19,
            top: isTopRow ? pointRect.top + 4 : pointRect.bottom - 22,
            child: _CountBadge(count: stack.count),
          ),
        );
      }
    }

    return widgets;
  }

  List<Widget> _buildMoveHighlights(Map<int, Rect> pointRects) {
    final overlays = <Widget>[];

    void addForMove(SheshBeshMove? move, Color color) {
      if (move == null) {
        return;
      }
      final from = move.fromPoint;
      final to = move.toPoint;
      if (from != null && pointRects[from] != null) {
        overlays.add(_highlightRect(pointRects[from]!, color));
      }
      if (to != null && pointRects[to] != null) {
        overlays.add(
          _highlightRect(pointRects[to]!, color.withValues(alpha: 0.7)),
        );
      }
    }

    addForMove(playerLastMove, const Color(0x66D7CA64));
    addForMove(opponentLastMove, const Color(0x66E57373));
    return overlays;
  }

  List<Widget> _buildDiceUsageBadges(
    Map<int, Rect> pointRects, {
    required double boardCenterY,
  }) {
    final widgets = <Widget>[];

    void addBadgeForPoint({
      required int point,
      required int diceSpent,
      required Color color,
      required bool emphasized,
    }) {
      final rect = pointRects[point];
      if (rect == null || diceSpent <= 0) {
        return;
      }
      final isTopRow = rect.center.dy < boardCenterY;
      widgets.add(
        Positioned(
          left: rect.left + 3,
          top: isTopRow ? rect.top + 3 : rect.bottom - 18,
          child: IgnorePointer(
            child: _DiceSpentBadge(
              diceSpent: diceSpent,
              color: color,
              emphasized: emphasized,
            ),
          ),
        ),
      );
    }

    for (final entry in targetDiceSpentHints.entries) {
      if (!legalTargetPoints.contains(entry.key)) {
        continue;
      }
      addBadgeForPoint(
        point: entry.key,
        diceSpent: entry.value,
        color: const Color(0xCCD17E2C),
        emphasized: true,
      );
    }

    return widgets;
  }

  Widget _highlightRect(Rect rect, Color color) {
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildBarArea(_BoardGeometry geometry) {
    return Positioned.fromRect(
      rect: geometry.barRect,
      child: Material(
        color: selectedFromBar
            ? const Color(0x5529B6F6)
            : (barPlayable
                  ? const Color(0x2232D1C8)
                  : Colors.black.withValues(alpha: 0.08)),
        child: InkWell(onTap: onBarTap, child: const SizedBox.expand()),
      ),
    );
  }

  List<Widget> _buildBarCheckers(_BoardGeometry geometry) {
    final whiteOnBottom = playerColor == 'w';
    final whiteRect = whiteOnBottom
        ? geometry.barBottomRect
        : geometry.barTopRect;
    final blackRect = whiteOnBottom
        ? geometry.barTopRect
        : geometry.barBottomRect;

    return <Widget>[
      _buildBarStack(rect: whiteRect, count: whiteBar, color: 'w'),
      _buildBarStack(rect: blackRect, count: blackBar, color: 'b'),
    ];
  }

  Widget _buildBarStack({
    required Rect rect,
    required int count,
    required String color,
  }) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }

    final tokenSize = rect.width * 0.85;
    final visible = math.min(count, 4);
    final widgets = <Widget>[];
    for (var i = 0; i < visible; i++) {
      final y = rect.bottom - tokenSize - (i * (tokenSize * 0.42));
      widgets.add(
        Positioned(
          left: rect.center.dx - (tokenSize / 2),
          top: y,
          width: tokenSize,
          height: tokenSize,
          child: _CoinSprite(
            color: color,
            pieceSkin: _pieceSkinForColor(color),
            invertColors: _shouldInvertForColor(color),
          ),
        ),
      );
    }

    widgets.add(
      Positioned(
        left: rect.center.dx - 12,
        top: rect.top + 2,
        child: _CountBadge(count: count),
      ),
    );

    return Stack(children: widgets);
  }

  Widget _buildBorneOffBadge({
    required String color,
    required int count,
    required Alignment alignment,
  }) {
    final label = color == 'w' ? 'W off' : 'B off';
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Text(
              '$label: $count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }

  PieceSkinOption _pieceSkinForColor(String color) {
    return color == 'w' ? whitePieceSkin : blackPieceSkin;
  }

  bool _shouldInvertForColor(String color) {
    return invertBlackPieceColors && color == 'b';
  }
}

class _BoardGeometry {
  _BoardGeometry({
    required this.size,
    required this.outerRect,
    required this.innerRect,
    required this.columnWidth,
    required this.pointHeight,
    required this.barRect,
    required this.barTopRect,
    required this.barBottomRect,
  });

  final double size;
  final Rect outerRect;
  final Rect innerRect;
  final double columnWidth;
  final double pointHeight;
  final Rect barRect;
  final Rect barTopRect;
  final Rect barBottomRect;

  static _BoardGeometry fromSize(double size) {
    final outerRect = Offset.zero & Size.square(size);
    final inset = size * 0.03;
    final inner = outerRect.deflate(inset);
    final barWidth = size * 0.08;
    final centerGap = size * 0.035;

    final trackHeight = (inner.height - centerGap) / 2;
    final pointHeight = trackHeight - (size * 0.015);
    final columnWidth = (inner.width - barWidth) / 12;

    final barLeft = inner.left + (6 * columnWidth);
    final barRect = Rect.fromLTWH(barLeft, inner.top, barWidth, inner.height);
    final barTopRect = Rect.fromLTWH(barLeft, inner.top, barWidth, trackHeight);
    final barBottomRect = Rect.fromLTWH(
      barLeft,
      inner.top + trackHeight + centerGap,
      barWidth,
      trackHeight,
    );

    return _BoardGeometry(
      size: size,
      outerRect: outerRect,
      innerRect: inner,
      columnWidth: columnWidth,
      pointHeight: pointHeight,
      barRect: barRect,
      barTopRect: barTopRect,
      barBottomRect: barBottomRect,
    );
  }

  Rect topPointRect(int column) {
    final left =
        innerRect.left +
        (column * columnWidth) +
        (column >= 6 ? barRect.width : 0);
    return Rect.fromLTWH(left, innerRect.top, columnWidth, pointHeight);
  }

  Rect bottomPointRect(int column) {
    final left =
        innerRect.left +
        (column * columnWidth) +
        (column >= 6 ? barRect.width : 0);
    return Rect.fromLTWH(
      left,
      innerRect.bottom - pointHeight,
      columnWidth,
      pointHeight,
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.geometry});

  final _BoardGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF523A28), Color(0xFF2F2219)],
      ).createShader(geometry.outerRect);
    canvas.drawRect(geometry.outerRect, outerPaint);

    final feltPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFF0D3B44), Color(0xFF0B262E)],
      ).createShader(geometry.innerRect);
    canvas.drawRect(geometry.innerRect, feltPaint);

    final barPaint = Paint()
      ..color = const Color(0xFF7A5B44).withValues(alpha: 0.85);
    canvas.drawRect(geometry.barRect, barPaint);

    for (var column = 0; column < 12; column++) {
      final topRect = geometry.topPointRect(column);
      final bottomRect = geometry.bottomPointRect(column);
      final topColor = column.isEven
          ? const Color(0xFFF4C987)
          : const Color(0xFFBD6E2E);
      final bottomColor = column.isEven
          ? const Color(0xFFB95F2F)
          : const Color(0xFFF1BE75);

      _drawPointTriangle(
        canvas: canvas,
        rect: topRect,
        pointsDown: true,
        color: topColor,
      );
      _drawPointTriangle(
        canvas: canvas,
        rect: bottomRect,
        pointsDown: false,
        color: bottomColor,
      );
    }
  }

  void _drawPointTriangle({
    required Canvas canvas,
    required Rect rect,
    required bool pointsDown,
    required Color color,
  }) {
    final path = Path();
    if (pointsDown) {
      path
        ..moveTo(rect.left, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.center.dx, rect.bottom)
        ..close();
    } else {
      path
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.center.dx, rect.top)
        ..close();
    }

    final fill = Paint()..color = color;
    canvas.drawPath(path, fill);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.black.withValues(alpha: 0.24);
    canvas.drawPath(path, edge);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) {
    return oldDelegate.geometry.size != geometry.size;
  }
}

class _BoardOverlayPainter extends CustomPainter {
  _BoardOverlayPainter({required this.geometry, required this.activeColor});

  final _BoardGeometry geometry;
  final String activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xCCFFD79A)
      ..strokeWidth = math.max(2, geometry.size * 0.0045);
    canvas.drawRect(geometry.innerRect, borderPaint);

    final centerY = geometry.innerRect.center.dy;
    final turnIndicator = Paint()
      ..color = activeColor == 'w'
          ? const Color(0xFF8CE0FF).withValues(alpha: 0.34)
          : const Color(0xFFFFB38B).withValues(alpha: 0.34);
    canvas.drawRect(
      Rect.fromLTWH(
        geometry.innerRect.left,
        centerY - 2,
        geometry.innerRect.width,
        4,
      ),
      turnIndicator,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardOverlayPainter oldDelegate) {
    return oldDelegate.geometry.size != geometry.size ||
        oldDelegate.activeColor != activeColor;
  }
}

class _CoinSprite extends StatelessWidget {
  const _CoinSprite({
    required this.color,
    required this.pieceSkin,
    required this.invertColors,
  });

  final String color;
  final PieceSkinOption pieceSkin;
  final bool invertColors;

  @override
  Widget build(BuildContext context) {
    final asset = pieceSkin.assetForColor(color);
    if (pieceSkin.mode == PieceSkinRenderMode.image && asset != null) {
      Widget image = Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => _flatToken(),
      );
      if (pieceSkin.tintColor != null) {
        image = ColorFiltered(
          colorFilter: ColorFilter.mode(
            pieceSkin.tintColor!.withValues(alpha: color == 'w' ? 0.2 : 0.35),
            BlendMode.overlay,
          ),
          child: image,
        );
      }
      if (invertColors) {
        image = ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            -1,
            0,
            0,
            0,
            255,
            0,
            -1,
            0,
            0,
            255,
            0,
            0,
            -1,
            0,
            255,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: image,
        );
      }
      return image;
    }
    Widget fallback = _flatToken();
    if (invertColors) {
      fallback = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          -1,
          0,
          0,
          0,
          255,
          0,
          -1,
          0,
          0,
          255,
          0,
          0,
          -1,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: fallback,
      );
    }
    return fallback;
  }

  Widget _flatToken() {
    final isLight = color == 'w';
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? const <Color>[Color(0xFFF5F6F8), Color(0xFFBFC6CE)]
              : const <Color>[Color(0xFF535C68), Color(0xFF171B21)],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
      ),
    );
  }
}

class _PlayableCoinGlow extends StatelessWidget {
  const _PlayableCoinGlow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF32D1C8), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6632D1C8),
            blurRadius: 10,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(1.5), child: child),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0E1116),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DiceSpentBadge extends StatelessWidget {
  const _DiceSpentBadge({
    required this.diceSpent,
    required this.color,
    required this.emphasized,
  });

  final int diceSpent;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: emphasized ? 0.75 : 0.45),
          width: emphasized ? 1.3 : 1.0,
        ),
        boxShadow: emphasized
            ? const [
                BoxShadow(
                  color: Color(0x55252216),
                  blurRadius: 5,
                  offset: Offset(0, 1.5),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          'x$diceSpent',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
