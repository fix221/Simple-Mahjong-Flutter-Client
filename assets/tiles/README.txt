Tile face images (pseudo-3D client)

Naming:
  {suit}_{num}.png
  suit: 0=wan 1=tong 2=tiao 3=feng 4=jian
  num:  1-9 for suits; feng 1-4=ESWN; jian 1-3=zhong/fa/bai
  back.png = tile back

Examples:
  0_1.png  = 1 wan
  2_9.png  = 9 tiao
  3_1.png  = East
  4_1.png  = Zhong
  back.png

To use real photos:
  1) Export portrait PNGs (recommended ~128x180 or 256x360)
  2) Replace files here with same names
  OR put overrides in assets/tiles/photo/ with same names
     (code tries photo/ first, then this folder)

Current files are generated placeholders (text faces), not photos.