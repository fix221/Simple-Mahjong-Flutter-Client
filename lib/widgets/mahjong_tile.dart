import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'tile_assets.dart';

/// Extruded mahjong tile.
/// Face: Unicode glyph (optional photo override).
class MahjongTile extends StatelessWidget {
  static const String _mahjongFont = 'I.MahjongCAN';
  static const String _emojiFallback = 'Noto Color Emoji';
  final Tile? tile;
  final bool faceDown;
  final bool selected;
  final bool highlight;
  final bool dimmed;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final bool small;
  final bool useUnicode;

  const MahjongTile({
    super.key,
    this.tile,
    this.faceDown = false,
    this.selected = false,
    this.highlight = false,
    this.dimmed = false,
    this.width = 48,
    this.height = 68,
    this.onTap,
    this.small = false,
    this.useUnicode = true,
    double yaw = 0,
    double pitch = 0,
  });

  @override
  Widget build(BuildContext context) {
    final depth = (width * 0.12).clamp(3.0, 8.0);
    final lift = selected ? 10.0 : (highlight ? 5.0 : 0.0);
    final radius = BorderRadius.circular(width * 0.1);

    final face = faceDown || tile == null ? _back(radius) : _front(radius);

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: width + depth,
      height: height + depth + lift,
      transform: Matrix4.translationValues(0, -lift, 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: depth * 0.4,
            top: depth * 0.55,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: radius,
                color: faceDown
                    ? const Color(0xFF0A3A7A)
                    : const Color(0xFF5D4037),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: selected ? 10 : 5,
                    offset: Offset(depth * 0.15, depth * 0.45),
                  ),
                ],
              ),
              child: face,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }

  Color get _borderColor {
    if (highlight) return Colors.amberAccent;
    if (selected) return Colors.lightGreenAccent;
    return const Color(0xFF8D6E63);
  }

  Widget _faceBox(BorderRadius radius, Widget child) {
    // Do NOT wrap emoji in Opacity — on many Android devices color emoji
    // becomes fully/partially transparent under Opacity.
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Always-opaque ivory face (dimmed = greyer)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dimmed
                    ? const [Color(0xFFCFD8DC), Color(0xFF90A4AE)]
                    : const [
                        Color(0xFFFFFFF8),
                        Color(0xFFFFF8E7),
                        Color(0xFFE8D5A3),
                      ],
              ),
            ),
          ),
          child,
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _borderColor,
                  width: highlight || selected ? 2.4 : 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _back(BorderRadius radius) {
    final photo = TileAssets.backPhoto();
    return _faceBox(
      radius,
      photo != null
          ? Image.asset(
              photo,
              fit: BoxFit.cover,
              width: width,
              height: height,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  _glyphFill(Tile.unicodeBack, isBack: true),
            )
          : _glyphFill(Tile.unicodeBack, isBack: true),
    );
  }

  Widget _front(BorderRadius radius) {
    final t = tile!;
    final photo = TileAssets.face(t);
    final glyph = t.label;

    return _faceBox(
      radius,
      photo != null
          ? Image.asset(
              photo,
              fit: BoxFit.cover,
              width: width,
              height: height,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  _glyphFill(glyph, isBack: false),
            )
          : _glyphFill(glyph, isBack: false),
    );
  }

  /// Unicode face. Slight zoom; avoid Opacity / huge scale (Android transparency).
  Widget _glyphFill(String text, {required bool isBack}) {
    // Desktop emoji often has more padding; mobile less. Keep zoom modest.
    final zoom = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS
        ? 1.12
        : 1.18;

    // Base font size relative to tile — not 120pt (can fail on mobile rasterizers)
    final base = (width * 0.92).clamp(18.0, 96.0);

    return ClipRect(
      child: Center(
        child: Transform.scale(
          scale: zoom,
          child: Text(
            text,
            textAlign: TextAlign.center,
            // Important for color emoji on Android/iOS:
            // - no Opacity ancestor
            // - no ColorFilter
            // - do not set a translucent color
            style: TextStyle(
              fontSize: base,
              height: 1.0,
              leadingDistribution: TextLeadingDistribution.even,
              // Keep the glyph fallback only when the PNG asset fails to load.
              foreground: Paint()
                ..style = PaintingStyle.fill
                ..color = useUnicode
                    ? (isBack ? const Color(0xFF263238) : const Color(0xFFB71C1C))
                    : (isBack ? Colors.white : const Color(0xFF212121)),
              fontFamilyFallback: const [
                _emojiFallback,
                'Segoe UI Emoji',
                'Apple Color Emoji',
                'Segoe UI Symbol',
              ],
            ),
          ),
        ),
      ),
    );
  }
}
