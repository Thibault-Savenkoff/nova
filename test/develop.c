/* Reference development of a RAW file with LibRaw, same settings as nova (Nova_rawin nr_develop):
   camera white balance, linear, no automatic brightness, then a tone curve of nova_look.h (look: 0 canon, default; 1 darktable), 16 bits;
   writes a binary PPM (big-endian samples).
   cc -Ithird_party/libraw test/develop.c -o test/develop -l:libraw_r.so.25 -lm */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <libraw/libraw.h>
#include "../nova_look.h"
int main(int argc, char **argv) {
  libraw_data_t *r = libraw_init(0);
  libraw_processed_image_t *im;
  int e;
  if (argc < 3) { fprintf(stderr, "usage: develop in.raw out.ppm [look]\n"); return 2; }
  r->params.use_camera_wb = 1;
  r->params.output_bps = 16;
  r->params.no_auto_bright = 1;
  r->params.gamm[0] = 1;
  r->params.gamm[1] = 1;
  if ((e = libraw_open_file(r, argv[1])) || (e = libraw_unpack(r)) || (e = libraw_dcraw_process(r))) { fprintf(stderr, "%s\n", libraw_strerror(e)); return 1; }
  if (!(im = libraw_dcraw_make_mem_image(r, &e))) { fprintf(stderr, "%s\n", libraw_strerror(e)); return 1; }
  {
    FILE *f = fopen(argv[2], "wb");
    long i, n = (long)im->width * im->height * 3;
    const unsigned short *p = (const unsigned short *)im->data;
    fprintf(f, "P6\n%d %d\n65535\n", im->width, im->height);
    int look = argc > 3 ? atoi(argv[3]) : 0;
    static unsigned short lut[65536];
    unsigned short o[3];
    for (i = 0; i < 65536; i++) lut[i] = nova_look_map(i, look);
    for (i = 0; i < n; i += 3) {
      int c;
      nova_look_rgb(lut, p + i, o, look);
      for (c = 0; c < 3; c++) { fputc(o[c] >> 8, f); fputc(o[c] & 255, f); }
    }
    fclose(f);
  }
  libraw_close(r);
  return 0;
}
