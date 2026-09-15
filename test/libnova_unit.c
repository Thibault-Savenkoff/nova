/* Unit tests of libnovadec (libnova/novadec.c, included to reach its static functions).
   Built and run by test/libnova_unit.sh. Arguments: pairs "file.nova expected.icc" ("-": no profile).
   - inflate_zlib against zlib: every block type (stored, fixed, dynamic), levels, strategies, sizes;
     corrupt and truncated streams must give NULL, never a crash;
   - nova_check, nova_read_info on bad input;
   - nova_icc on real files (JPEG profile in several APP2 segments, PNG iCCP). */
#include "../libnova/novadec.c"
#include <stdio.h>
#include <zlib.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); fails++; } } while (0)

static uint32_t rng = 12345;
static uint8_t rnd(void) { rng = rng * 1103515245u + 12345u; return (uint8_t)(rng >> 16); }

/* data kinds: 0 random, 1 text-like (dynamic codes), 2 long runs (long matches), 3 small alphabet */
static void fill(uint8_t *d, size_t n, int kind) {
  static const char *words[] = {"colour ", "profile ", "NOVA ", "sRGB ", "gamma ", "\n"};
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
                    "corrupt stream: zlib %s, libnova %s (size %zu kind %d level %d strategy %zu)",
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

static void test_api(const char *nova) {
  nova_info info;
  size_t n, len;
  uint8_t *d = load(nova, &n);
  static const uint8_t junk[16] = "not a nova file";
  CHECK(d && nova_check(d, n), "%s: signature", nova);
  CHECK(!nova_check(junk, sizeof junk), "junk passes nova_check");
  CHECK(!nova_check(d, 8), "8 bytes pass nova_check");
  memset(&info, 0, sizeof info);
  CHECK(nova_read_info(junk, sizeof junk, &info) == -1 && info.error, "junk read_info");
  memset(&info, 0, sizeof info);
  CHECK(nova_read_info(d, 20, &info) == -1 && info.error, "truncated read_info");
  memset(&info, 0, sizeof info);
  CHECK(!nova_decode(d, n / 2, &info), "half file decoded");
  CHECK(!nova_icc(junk, sizeof junk, &len), "icc of junk");
  memset(&info, 0, sizeof info);
  CHECK(nova_read_info(d, n, &info) == 0 && info.width > 0 && info.height > 0 && info.frames >= 1, "%s: read_info", nova);
  free(d);
}

static void test_icc(const char *nova, const char *expect) {
  size_t n, en = 0, len = 0;
  uint8_t *d = load(nova, &n), *e = strcmp(expect, "-") ? load(expect, &en) : NULL, *icc;
  CHECK(d != NULL, "cannot read %s", nova);
  if (!d) return;
  icc = nova_icc(d, n, &len);
  if (e) CHECK(icc && len == en && !memcmp(icc, e, en), "%s: icc %zu bytes, expected %zu", nova, icc ? len : 0, en);
  else CHECK(!icc, "%s: icc found, none expected", nova);
  printf("icc: %s %zu bytes\n", nova, icc ? len : 0);
  free(icc);
  free(d);
  free(e);
}

int main(int argc, char **argv) {
  int i;
  test_inflate();
  for (i = 1; i + 1 < argc; i += 2) {
    test_api(argv[i]);
    test_icc(argv[i], argv[i + 1]);
  }
  printf(fails ? "%d FAIL\n" : "all OK\n", fails);
  return fails != 0;
}
