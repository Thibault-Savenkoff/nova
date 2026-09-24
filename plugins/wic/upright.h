/* RGBA (as decoded) -> BGRA for WIC, turned upright by the EXIF orientation (1-8).
   out holds w x h pixels; *ow x *oh is the upright size (w, h swapped for orientations 5-8). */
#ifndef YAIF_UPRIGHT_H
#define YAIF_UPRIGHT_H
#include <stdint.h>

static void yaif_upright_bgra(const uint8_t *in, int w, int h, int o, uint8_t *out, int *ow, int *oh) {
  int swap = o >= 5 && o <= 8, W = swap ? h : w, H = swap ? w : h, x, y;
  for (y = 0; y < H; y++)
    for (x = 0; x < W; x++) {
      int sx, sy;
      switch (o) {
        case 2: sx = w - 1 - x; sy = y; break;
        case 3: sx = w - 1 - x; sy = h - 1 - y; break;
        case 4: sx = x; sy = h - 1 - y; break;
        case 5: sx = y; sy = x; break;
        case 6: sx = y; sy = h - 1 - x; break;
        case 7: sx = w - 1 - y; sy = h - 1 - x; break;
        case 8: sx = w - 1 - y; sy = x; break;
        default: sx = x; sy = y;
      }
      const uint8_t *s = in + ((size_t)sy * w + sx) * 4;
      uint8_t *d = out + ((size_t)y * W + x) * 4;
      d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = s[3];
    }
  *ow = W;
  *oh = H;
}
#endif
