#include <stdint.h>
#include <stdlib.h>

/*
 * Optional C accelerator for nova.py hot loops.
 *
 * Compile:
 *   gcc -O2 -shared -fPIC -o nova_accel.so nova_accel.c
 *
 * nova.py loads nova_accel.so automatically if present in the same directory.
 * Falls back to pure Python if the .so is absent — no action required.
 */

/*
 * Find bounding box of changed pixels between two frames (flat RGBA/RGB byte arrays).
 * Writes (x0, y0, x1, y1) into out[4]. All zeros if no difference.
 */
void frame_diff_bbox(const uint8_t* a, const uint8_t* b,
                     int w, int h, int channels, int* out)
{
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int off = (y * w + x) * channels;
            int diff = 0;
            for (int c = 0; c < channels; c++)
                diff |= (a[off + c] != b[off + c]);
            if (diff) {
                if (x     < x0) x0 = x;
                if (y     < y0) y0 = y;
                if (x + 1 > x1) x1 = x + 1;
                if (y + 1 > y1) y1 = y + 1;
            }
        }
    }
    if (x1 == -1) { out[0] = out[1] = out[2] = out[3] = 0; }
    else           { out[0] = x0; out[1] = y0; out[2] = x1; out[3] = y1; }
}
