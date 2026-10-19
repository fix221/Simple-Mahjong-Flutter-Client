import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game_client.dart';
import '../models.dart';
import 'mahjong_tile.dart';

/// Square mahjong table: self bottom, opposite top, left/right sides.
class Table3D extends StatelessWidget {
  final GameClient client;
  final void Function(Tile tile, int index)? onHandTap;

  const Table3D({super.key, required this.client, this.onHandTap});

  int get _n {
    final n = client.playerNames.length;
    if (n >= 2) return n;
    return 4;
  }

  int seatOfRel(int rel) {
    if (client.mySeat < 0) return rel % _n;
    return (client.mySeat + rel) % _n;
  }

  int relOf(int seat) {
    if (client.mySeat < 0) return seat % _n;
    return (seat - client.mySeat + _n * 4) % _n;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(box.maxWidth, box.maxHeight);
      // leave room below square for own hand if needed; use full square for table
      return ColoredBox(
        color: const Color(0xFF102010),
        child: Column(
          children: [
            // HUD
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: _hud(),
            ),
            // SQUARE table
            Expanded(
              child: Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: _squareTable(side),
                ),
              ),
            ),
            // Own hand ALWAYS under the square — large & visible
            _selfHandBar(box.maxWidth),
          ],
        ),
      );
    });
  }

  Widget _hud() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '座位${client.mySeat}  墙${client.wall}  庄P${client.dealer}'
        '${client.sealedN > 0 ? "  封${client.sealedN}" : ""}'
        '  ${client.status}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _squareTable(double side) {
    final pad = side * 0.04;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(side * 0.06),
        border: Border.all(color: const Color(0xFF5D4037), width: side * 0.025),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(side * 0.04),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _FeltPainter()),
            // inner wood line
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: EdgeInsets.all(side * 0.01),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(side * 0.035),
                    border: Border.all(color: const Color(0xFF8D6E63), width: 2),
                  ),
                ),
              ),
            ),
            // center label
            Center(
              child: Container(
                width: side * 0.22,
                height: side * 0.22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.18),
                  border: Border.all(color: Colors.white24),
                ),
                alignment: Alignment.center,
                child: Text(
                  client.rule == 'sichuan' ? '川麻' : '推倒胡',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontWeight: FontWeight.bold,
                    fontSize: side * 0.035,
                  ),
                ),
              ),
            ),
            // TOP: opposite
            Positioned(
              top: pad,
              left: pad * 2,
              right: pad * 2,
              child: _remoteSeat(seatOfRel(2), Axis.horizontal, tile: side * 0.055),
            ),
            // BOTTOM: self name + discards (hand is outside)
            Positioned(
              bottom: pad,
              left: pad * 2,
              right: pad * 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _seatMelds(seatOfRel(0), side * 0.045, side * 0.06),
                  const SizedBox(height: 4),
                  _discardRow(seatOfRel(0), tile: side * 0.05),
                  const SizedBox(height: 4),
                  _nameChip(seatOfRel(0)),
                ],
              ),
            ),
            // LEFT
            Positioned(
              left: pad * 0.5,
              top: side * 0.18,
              bottom: side * 0.18,
              width: side * 0.16,
              child: _remoteSeat(seatOfRel(3), Axis.vertical, tile: side * 0.05),
            ),
            // RIGHT
            Positioned(
              right: pad * 0.5,
              top: side * 0.18,
              bottom: side * 0.18,
              width: side * 0.16,
              child: _remoteSeat(seatOfRel(1), Axis.vertical, tile: side * 0.05),
            ),
            // center discards of all (compact)
            Positioned(
              left: side * 0.22,
              right: side * 0.22,
              top: side * 0.28,
              bottom: side * 0.28,
              child: _centerDiscards(side),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameChip(int seat) {
    if (seat < 0 || seat >= client.playerNames.length) {
      return Text('P$seat', style: const TextStyle(color: Colors.white70, fontSize: 12));
    }
    final name = client.playerNames[seat];
    final turn = client.current == seat && client.phase == 'discard';
    final dealer = client.dealer == seat;
    final won = client.wonSeats.contains(seat);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: turn ? Colors.amber : Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'P$seat $name${dealer ? " 庄" : ""}${won ? " 胡" : ""}${turn ? " ←" : ""}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: turn ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  int _handCount(int seat) {
    if (seat == client.mySeat) return client.hand.length;
    final c = client.handCountOf(seat);
    // fallback so backs always visible before first sync
    if (c <= 0) return 13;
    return c;
  }

  Widget _remoteSeat(int seat, Axis axis, {required double tile}) {
    final count = _handCount(seat).clamp(0, 14);
    final backs = List.generate(
      count,
      (i) => Padding(
        padding: EdgeInsets.all(axis == Axis.horizontal ? 1.0 : 0.5),
        child: MahjongTile(
          faceDown: true,
          width: tile,
          height: tile * 1.35,
          small: true,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _nameChip(seat),
        const SizedBox(height: 4),
        _seatMelds(seat, tile * 0.9, tile * 1.15),
        const SizedBox(height: 4),
        if (axis == Axis.horizontal)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: backs),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: backs),
            ),
          ),
      ],
    );
  }

  Widget _discardRow(int seat, {required double tile}) {
    final tiles = client.discardsOf(seat);
    if (tiles.isEmpty) return const SizedBox(height: 4);
    final show = tiles.length > 10 ? tiles.sublist(tiles.length - 10) : tiles;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in show)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: MahjongTile(
                tile: t,
                width: tile,
                height: tile * 1.35,
                small: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _centerDiscards(double side) {
    final tile = side * 0.045;
    return Stack(
      children: [
        for (var s = 0; s < _n; s++)
          Builder(builder: (_) {
            final rel = relOf(s);
            final tiles = client.discardsOf(s);
            if (tiles.isEmpty) return const SizedBox.shrink();
            final show =
                tiles.length > 8 ? tiles.sublist(tiles.length - 8) : tiles;
            Alignment a;
            switch (rel) {
              case 0:
                a = Alignment.bottomCenter;
                break;
              case 1:
                a = Alignment.centerRight;
                break;
              case 2:
                a = Alignment.topCenter;
                break;
              default:
                a = Alignment.centerLeft;
            }
            return Align(
              alignment: a,
              child: Wrap(
                spacing: 1,
                runSpacing: 1,
                alignment: WrapAlignment.center,
                children: [
                  for (final t in show)
                    MahjongTile(
                      tile: t,
                      width: tile,
                      height: tile * 1.35,
                      small: true,
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _selfHandBar(double maxW) {
    final hand = client.hand;
    // scale tile to fit ~14 tiles on screen
    final tw = (maxW / 15).clamp(36.0, 56.0);
    final th = tw * 1.4;
    final melds = client.seatMelds;

    return Container(
      width: double.infinity,
      color: const Color(0xFF0A1A0A),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hand.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('等待手牌…', style: TextStyle(color: Colors.white54)),
            )
          else
            SizedBox(
              height: th + 16,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < hand.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: MahjongTile(
                            tile: hand[i],
                            width: tw,
                            height: th,
                            selected: client.isIndexSelected(i),
                            highlight: client.isHighlightedAt(i),
                            dimmed: client.myQue >= 0 &&
                                hand[i].suit == client.myQue,
                            onTap: onHandTap == null
                                ? null
                                : () => onHandTap!(hand[i], i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _meld(dynamic m, double w, double h) {
    if (m is! Map) return const SizedBox.shrink();
    final type = m['type'];
    final tiles = m['tiles'];
    final kind = switch (type) {
      0 => '碰',
      1 => '暗',
      2 => '杠',
      3 => '补',
      _ => '副',
    };
    final list = <Tile>[];
    if (tiles is List) {
      for (final t in tiles) {
        if (t is Map) {
          list.add(Tile.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          child: Text(kind, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ),
        for (var i = 0; i < list.length; i++)
          MahjongTile(
            tile: list[i],
            faceDown: type == 1 && i >= 2,
            width: w,
            height: h,
            small: true,
          ),
      ],
    );
  }

  Widget _seatMelds(int seat, double tileW, double tileH) {
    final melds = client.meldsOf(seat);
    if (melds.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in melds) ...[
            _meld(m, tileW, tileH),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFF0D3B12)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF66BB6A).withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
