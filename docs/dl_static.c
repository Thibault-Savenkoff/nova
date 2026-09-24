/* WebAssembly build: yaif loads LibRaw and zlib with dlopen/dlsym; here they are linked in, and
   build.sh renames yaif.c's dlopen/dlsym to these. Other libraries (libheif, libwebp) stay "not found". */
#include <string.h>
#include <zlib.h>
#include "../third_party/libraw/libraw/libraw.h"

/* yaif declares adler32_combine with a long length; this zlib.h maps it to the 64-bit variant, and a
   call through a pointer of another signature traps in wasm. */
static unsigned long combine(unsigned long a, unsigned long b, long n) { return adler32_combine(a, b, n); }

#define F(s) { #s, (void *)s }
static const struct { const char *name; void *fn; } syms[] = {
  F(libraw_init), F(libraw_open_file), F(libraw_unpack), F(libraw_close), F(libraw_versionNumber),
  F(libraw_strerror), F(libraw_open_buffer), F(libraw_dcraw_process), F(libraw_dcraw_make_mem_image),
  F(libraw_dcraw_clear_mem), F(adler32), { "adler32_combine", (void *)combine },F(compress2), F(compressBound), F(deflate),
  F(deflateInit_), F(deflateInit2_), F(deflateEnd), F(uncompress), F(crc32),
};

void *yaif_dlopen(const char *name, int flags) {
  (void)flags;
  return name && (!strncmp(name, "libraw_r.so", 11) || !strncmp(name, "libz.so", 7)) ? (void *)syms : 0;
}

void *yaif_dlsym(void *h, const char *s) {
  unsigned i;
  if (!h || !s) return 0;
  for (i = 0; i < sizeof syms / sizeof *syms; i++) if (!strcmp(syms[i].name, s)) return syms[i].fn;
  return 0;
}
