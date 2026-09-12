/* Reference for test/raw.sh: the sensor frame as LibRaw unpacks it, 16-bit big-endian, no header. */
#include <stdio.h>
#include <dlfcn.h>
#include "../third_party/libraw/libraw/libraw.h"
int main(int c, char **v) {
  void *l = dlopen("libraw_r.so.25", RTLD_NOW);
  libraw_data_t *(*init)(unsigned) = l ? dlsym(l, "libraw_init") : 0;
  int (*open)(libraw_data_t *, const char *) = l ? dlsym(l, "libraw_open_file") : 0;
  int (*unpack)(libraw_data_t *) = l ? dlsym(l, "libraw_unpack") : 0;
  libraw_data_t *r;
  FILE *f;
  int x, y;
  if (c != 3 || !init || !open || !unpack) return 2;
  r = init(0);
  if (open(r, v[1]) || unpack(r) || !r->rawdata.raw_image || !(f = fopen(v[2], "wb"))) return 1;
  for (y = 0; y < r->sizes.raw_height; y++)
    for (x = 0; x < r->sizes.raw_width; x++) {
      unsigned short s = r->rawdata.raw_image[y * (r->sizes.raw_pitch / 2) + x];
      fputc(s >> 8, f);
      fputc(s & 255, f);
    }
  fclose(f);
  /* Parameters a developer needs, to compare a DNG with its source. */
  printf("%s %s %dx%d visible %dx%d at %d,%d filters %x black(0,0) %u white %u flip %d\n", r->idata.make, r->idata.model,
         r->sizes.raw_width, r->sizes.raw_height, r->sizes.width, r->sizes.height, r->sizes.top_margin, r->sizes.left_margin,
         r->idata.filters, r->color.black + r->color.cblack[0] + (r->color.cblack[4] && r->color.cblack[5] ? r->color.cblack[6] : 0), r->color.linear_max[0] ? (unsigned)r->color.linear_max[0] : r->color.maximum, r->sizes.flip);
  printf("wb %.4f %.4f %.4f  xyz %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f\n",
         r->color.cam_mul[0] / r->color.cam_mul[1], r->color.cam_mul[2] / r->color.cam_mul[1], r->color.cam_mul[1] / r->color.cam_mul[1],
         r->color.cam_xyz[0][0], r->color.cam_xyz[0][1], r->color.cam_xyz[0][2], r->color.cam_xyz[1][0], r->color.cam_xyz[1][1],
         r->color.cam_xyz[1][2], r->color.cam_xyz[2][0], r->color.cam_xyz[2][1], r->color.cam_xyz[2][2]);
  printf("iso %.0f shutter %.5f aperture %.1f focal %.0f time %ld artist '%s' lens '%s'\n", r->other.iso_speed, r->other.shutter,
         r->other.aperture, r->other.focal_len, (long)r->other.timestamp, r->other.artist, r->lens.Lens);
  return 0;
}
