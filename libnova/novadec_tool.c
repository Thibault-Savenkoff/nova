/* novadec x.nova out.raw [preview]: RGBA of every frame (or of the PREV), concatenated, as
   test/js_dump.js does for the JavaScript decoder (test/libnova.sh compares it with nova). */
#include "novadec.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char **argv) {
  FILE *f;
  long n;
  uint8_t *d, *px;
  nova_info info;
  int w, h, frames = 1;
  clock_t t0 = clock();
  if (argc < 3) { fprintf(stderr, "usage: novadec x.nova out.raw [preview]\n"); return 2; }
  f = fopen(argv[1], "rb");
  if (!f) { printf("ERROR cannot read %s\n", argv[1]); return 1; }
  fseek(f, 0, SEEK_END);
  n = ftell(f);
  fseek(f, 0, SEEK_SET);
  d = malloc(n);
  if (!d || fread(d, 1, n, f) != (size_t)n) { printf("ERROR read\n"); return 1; }
  fclose(f);
  if (argc > 3) {
    px = nova_decode_preview(d, n, &w, &h);
    if (!px) { printf("ERROR no preview\n"); return 1; }
  } else {
    px = nova_decode(d, n, &info);
    if (!px) { printf("ERROR %s\n", info.error); return 1; }
    w = info.width; h = info.height; frames = info.frames;
  }
  f = fopen(argv[2], "wb");
  fwrite(px, 4, (size_t)w * h * frames, f);
  fclose(f);
  printf("%dx%d %d frame(s) %.1f s\n", w, h, frames, (double)(clock() - t0) / CLOCKS_PER_SEC);
  free(px);
  free(d);
  return 0;
}
