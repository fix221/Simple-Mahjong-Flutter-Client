import '../models.dart';

/// Asset paths for tile face photos / drawings.
///
/// Put files under `assets/tiles/`:
///   - face: `{suit}_{num}.png`  e.g. `0_1.png` = 1万, `3_1.png` = 东, `4_1.png` = 中
///   - back: `back.png`
///
/// To use real photos: export 128x180 (or any portrait) PNGs with the same names and replace.
class TileAssets {
  static const String dir = 'assets/tiles';

  static String back() => '$dir/back.png';

  static String? face(Tile tile) => switch (tile.suit) {
        0 => '$dir/0_${tile.num}.png',
        1 => '$dir/1_${tile.num}.png',
        2 => '$dir/2_${tile.num}.png',
        3 => '$dir/3_${tile.num}.png',
        4 => '$dir/4_${tile.num}.png',
        _ => null,
      };

  /// Optional higher-res photo override folder (same filenames).
  static String? facePhoto(Tile tile) => null;

  static String? backPhoto() => '$dir/photo/back.png';
}
