#include <stdio.h>
#include <libraw/libraw.h>
int main(int c, char **v) {
  libraw_data_t *r = libraw_init(0);
  r->params.use_camera_wb = 1; r->params.output_bps = 16; r->params.half_size = 1;
  r->params.no_auto_bright = 1; r->params.gamm[0] = 1; r->params.gamm[1] = 1;
  if (libraw_open_file(r, v[1]) || libraw_unpack(r) || libraw_dcraw_process(r)) return 1;
  return libraw_dcraw_ppm_tiff_writer(r, v[2]);
}
