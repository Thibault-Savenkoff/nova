/* Unit tests of libyaifdec (libyaif/yaifdec.c, included to reach its static functions).
   Built and run by test/libyaif_unit.sh. Arguments: pairs "file.yaif expected.icc", where the
   profile is "-" for a file that has none and "?" when it is only exercised, not compared.
   - inflate_zlib against zlib: every block type (stored, fixed, dynamic), levels, strategies, sizes;
     corrupt and truncated streams must give NULL, never a crash;
   - yaif_check, yaif_read_info on bad input;
   - yaif_icc on real files (JPEG profile in several APP2 segments, PNG iCCP). */
#include "../libyaif/yaifdec.c"
#include <stdio.h>
#include <zlib.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); fails++; } } while (0)

static uint32_t rng = 12345;
static uint8_t rnd(void) { rng = rng * 1103515245u + 12345u; return (uint8_t)(rng >> 16); }

/* data kinds: 0 random, 1 text-like (dynamic codes), 2 long runs (long matches), 3 small alphabet */
static void fill(uint8_t *d, size_t n, int kind) {
  static const char *words[] = {"colour ", "profile ", "YAIF ", "sRGB ", "gamma ", "\n"};
  size_t i = 0;
  while (i < n) {
    if (kind == 0) d[i++] = rnd();
    else if (kind == 1) { const char *w = words[rnd() % 6]; while (*w && i < n) d[i++] = (uint8_t)*w++; }
    else if (kind == 2) { uint8_t c = rnd(); size_t r = 1 + rnd() * 4u; while (r-- && i < n) d[i++] = c; }
    else d[i++] = (uint8_t)('a' + rnd() % 4);
  }
}

static void test_inflate(void) {
  static const size_t sizes[] = {0, 1, 100, 5000, 70000, 300000};
  static const int levels[] = {0, 1, 6, 9};
  static const int strategies[] = {Z_DEFAULT_STRATEGY, Z_FIXED, Z_HUFFMAN_ONLY, Z_RLE, Z_FILTERED};
  size_t si, li, st, k, n, out_len;
  int kind, cases = 0;
  for (si = 0; si < sizeof sizes / sizeof *sizes; si++)
    for (kind = 0; kind < 4; kind++)
      for (li = 0; li < sizeof levels / sizeof *levels; li++)
        for (st = 0; st < sizeof strategies / sizeof *strategies; st++) {
          z_stream z;
          uint8_t *src, *zb, *out;
          n = sizes[si];
          src = malloc(n + 1);
          fill(src, n, kind);
          zb = malloc(compressBound(n) + 64);
          memset(&z, 0, sizeof z);
          deflateInit2(&z, levels[li], Z_DEFLATED, 15, 8, strategies[st]);
          z.next_in = src; z.avail_in = (uInt)n;
          z.next_out = zb; z.avail_out = (uInt)(compressBound(n) + 64);
          deflate(&z, Z_FINISH);
          k = z.total_out;
          deflateEnd(&z);
          out = inflate_zlib(zb, k, &out_len);
          CHECK(out && out_len == n && !memcmp(out, src, n), "inflate size %zu kind %d level %d strategy %zu", n, kind, levels[li], st);
          free(out);
          if (k > 8) {   /* truncated: NULL */
            out = inflate_zlib(zb, k - 5, &out_len);
            CHECK(!out, "truncated stream accepted (size %zu kind %d)", n, kind);
            free(out);
            /* corrupt: same verdict as zlib (a flipped bit can still leave a valid stream), no crash */
            zb[k / 2] ^= 0x55;
            out = inflate_zlib(zb, k, &out_len);
            {
              uLongf zn = (uLongf)n + 1;
              uint8_t *zo = malloc(n + 1);
              int zok = uncompress(zo, &zn, zb, (uLong)k) == Z_OK;
              CHECK(zok ? out && out_len == zn && !memcmp(out, zo, zn) : !out,
                    "corrupt stream: zlib %s, libyaif %s (size %zu kind %d level %d strategy %zu)",
                    zok ? "accepts" : "rejects", out ? "accepts" : "rejects", n, kind, levels[li], st);
              free(zo);
            }
            free(out);
          }
          free(src);
          free(zb);
          cases++;
        }
  /* bad headers */
  {
    static const uint8_t bad_method[] = {0x79, 0x9c, 3, 0, 0, 0, 0, 1};    /* CM 9 */
    static const uint8_t bad_check[] = {0x78, 0x9d, 3, 0, 0, 0, 0, 1};     /* FCHECK wrong */
    static const uint8_t dict[] = {0x78, 0xbb, 3, 0, 0, 0, 0, 1};          /* preset dictionary */
    CHECK(!inflate_zlib(bad_method, sizeof bad_method, &out_len), "bad method accepted");
    CHECK(!inflate_zlib(bad_check, sizeof bad_check, &out_len), "bad header check accepted");
    CHECK(!inflate_zlib(dict, sizeof dict, &out_len), "preset dictionary accepted");
    CHECK(!inflate_zlib(bad_method, 2, &out_len), "2-byte stream accepted");
  }
  printf("inflate: %d zlib streams\n", cases);
}

static uint8_t *load(const char *name, size_t *n) {
  FILE *f = fopen(name, "rb");
  uint8_t *d;
  long s;
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  s = ftell(f);
  fseek(f, 0, SEEK_SET);
  d = malloc(s > 0 ? (size_t)s : 1);
  *n = fread(d, 1, (size_t)s, f);
  fclose(f);
  return d;
}

static void test_api(const char *yaif) {
  yaif_info info;
  size_t n, len;
  uint8_t *d = load(yaif, &n);
  static const uint8_t junk[16] = "not a yaif file";
  CHECK(d && yaif_check(d, n), "%s: signature", yaif);
  CHECK(!yaif_check(junk, sizeof junk), "junk passes yaif_check");
  CHECK(!yaif_check(d, 8), "8 bytes pass yaif_check");
  memset(&info, 0, sizeof info);
  CHECK(yaif_read_info(junk, sizeof junk, &info) == -1 && info.error, "junk read_info");
  memset(&info, 0, sizeof info);
  CHECK(yaif_read_info(d, 20, &info) == -1 && info.error, "truncated read_info");
  memset(&info, 0, sizeof info);
  CHECK(!yaif_decode(d, n / 2, &info), "half file decoded");
  CHECK(!yaif_icc(junk, sizeof junk, &len), "icc of junk");
  memset(&info, 0, sizeof info);
  CHECK(yaif_read_info(d, n, &info) == 0 && info.width > 0 && info.height > 0 && info.frames >= 1, "%s: read_info", yaif);
  free(d);
}

static void test_icc(const char *yaif, const char *expect) {
  size_t n, en = 0, len = 0;
  int any = !strcmp(expect, "?");
  uint8_t *d = load(yaif, &n), *e = (strcmp(expect, "-") && !any) ? load(expect, &en) : NULL, *icc;
  CHECK(d != NULL, "cannot read %s", yaif);
  if (!d) return;
  icc = yaif_icc(d, n, &len);
  if (e) CHECK(icc && len == en && !memcmp(icc, e, en), "%s: icc %zu bytes, expected %zu", yaif, icc ? len : 0, en);
  else if (!any) CHECK(!icc, "%s: icc found, none expected", yaif);
  printf("icc: %s %zu bytes\n", yaif, icc ? len : 0);
  free(icc);
  free(d);
  free(e);
}

/* Corrupt files through the whole API: the plugins run inside a viewer, so a bad .yaif must never
   crash it. Built with sanitizers by test/libyaif_unit.sh, which also runs it under valgrind. */
static void fuzz(const char *yaif, int tries) {
  size_t n, len;
  uint8_t *d = load(yaif, &n), *b, *p;
  yaif_info info;
  int t, w, h;
  if (!d || n < 16) { free(d); return; }
  for (t = 0; t < tries; t++) {
    size_t m = n;
    b = malloc(n);
    memcpy(b, d, n);
    switch (t % 4) {
    case 0: { int k = 1 + rnd() % 4; while (k--) b[(rnd() << 8 | rnd()) % n] = rnd(); break; }
    case 1: m = (size_t)((rnd() << 8 | rnd()) % n); break;               /* cut short */
    case 2: b[((rnd() << 8 | rnd()) % (n < 200 ? n : 200))] ^= 1 << (rnd() % 8); break;   /* header */
    default: { size_t q = (rnd() << 8 | rnd()) % n; while (q < n) b[q++] = rnd(); }       /* random tail */
    }
    memset(&info, 0, sizeof info);
    yaif_check(b, m);
    yaif_read_info(b, m, &info);
    free(yaif_decode(b, m, &info));
    free(yaif_decode_preview(b, m, &w, &h));
    p = yaif_icc(b, m, &len);
    if (p && len == 0) CHECK(0, "%s: icc of %zu bytes returned", yaif, len);
    free(p);
    free(b);
  }
  free(d);
  printf("fuzz: %d corrupt copies of %s\n", tries, yaif);
}

int main(int argc, char **argv) {
  int i;
  test_inflate();
  for (i = 1; i + 1 < argc; i += 2) {
    test_api(argv[i]);
    test_icc(argv[i], argv[i + 1]);
    fuzz(argv[i], 400);
  }
  printf(fails ? "%d FAIL\n" : "all OK\n", fails);
  return fails != 0;
}
