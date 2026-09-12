#include <stdio.h>
#include <libraw/libraw.h>
int main(int c, char **v) {
  libraw_data_t *r = libraw_init(0); int i;
  if (libraw_open_file(r, v[1])) return 1;
  for (i = 0; i < r->thumbs_list.thumbcount; i++) fprintf(stderr, "thumb %d: %dx%d fmt %d len %d\n", i, r->thumbs_list.thumblist[i].twidth, r->thumbs_list.thumblist[i].theight, r->thumbs_list.thumblist[i].tformat, r->thumbs_list.thumblist[i].tlength);
  if (libraw_unpack_thumb(r)) return 2;
  fprintf(stderr, "chosen %dx%d\n", r->thumbnail.twidth, r->thumbnail.theight);
  return libraw_dcraw_thumb_writer(r, v[2]);
}
