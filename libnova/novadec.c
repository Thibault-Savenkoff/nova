/* libnovadec: port of docs/nova_decode.js (itself a port of the decoding paths of nova_codec.li,
   nova_model.li, nova_lossy.li, nova_wavelet.li and the container of nova.li). Must give the same
   pixels as `nova decode` bit for bit (test/libnova.sh). Lisaac Int is int64, and the JS uses doubles
   (exact below 2^53) for the same values: here they are int64_t. JS Math.floor(a / 2^k) is a >> k on
   int64 (arithmetic shift), Math.trunc(a / b) is C's a / b. Stripes (independent streams) and the
   three wavelet planes are decoded on up to one thread per core (NOVADEC_THREADS=n overrides;
   build with -DNOVADEC_NO_THREADS for one thread).
   ponytail: RAW frames (level 6) are not decoded (use the PREV thumbnail). */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L   /* sysconf, pthreads under -std=c99 */
#endif
#include "novadec.h"
#include <stdlib.h>
#include <string.h>
#ifndef NOVADEC_NO_THREADS
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif
#endif

/* ------------------------------------------------------------------------------------------- */
/* Shared tables (nova_model.li make_tables, nova_codec.li make_qtables)                        */
/* ------------------------------------------------------------------------------------------- */

static const int SQUASH_T[33] = { 1, 2, 3, 6, 10, 16, 27, 45, 73, 120, 194, 310, 488, 747, 1101, 1546, 2047,
  2549, 2994, 3348, 3607, 3785, 3901, 3975, 4024, 4050, 4068, 4079, 4085, 4089, 4092, 4093, 4094 };

static int squash(int d) {
  int w, i;
  if (d > 2047) return 4095;
  if (d < -2047) return 0;
  w = d & 127;
  i = (d >> 7) + 16;
  return (SQUASH_T[i] * (128 - w) + SQUASH_T[i + 1] * w + 64) >> 7;
}

static int SQ[4096], STRETCH[4096], RATE[1024], QL[4096], QH[4096];
/* ponytail: filled once; two threads racing on the first call write the same values. */
static volatile int tables_ready;

static void make_tables(void) {
  int j, x, v, n, pi = 0, a, r;
  if (tables_ready) return;
  for (j = 0; j < 4096; j++) SQ[j] = squash(j - 2048);
  for (x = -2047; x <= 2047; x++) {
    v = squash(x);
    for (j = pi; j <= v; j++) STRETCH[j] = x;
    if (v + 1 > pi) pi = v + 1;
  }
  for (j = pi; j <= 4095; j++) STRETCH[j] = 2047;
  for (n = 0; n < 1024; n++) RATE[n] = 131072 / (2 * n + 3);
  for (v = 0; v < 4096; v++) {
    a = v; r = 0;
    while (a > 0 && r < 7) { r++; a >>= 1; }
    QL[v] = r;
    if (v < 4) r = v;
    else {
      a = v; r = 0;
      while (a >= 8) { r += 2; a >>= 1; }
      r += 4;
      if (a >= 6) r++;
      if (r > 15) r = 15;
    }
    QH[v] = r;
  }
  tables_ready = 1;
}

static int qlog(int v) { return v < 4096 ? QL[v] : 7; }
static int qhalf(int v) { return v < 4096 ? QH[v] : 15; }
static uint32_t hash(uint32_t h, int v) { return (h * 16777619u) ^ (uint32_t)v; }
static int sq(int v) { return v < 0 ? -qlog(-v) : qlog(v); }
static int iabs(int v) { return v < 0 ? -v : v; }
static int clip(int v, int mx) { return v > mx ? mx : v; }
static int sclip(int v, int mx) { return v > mx ? mx : v < -mx ? -mx : v; }
static int clamp2047(int64_t d) { return d < -2047 ? -2047 : d > 2047 ? 2047 : (int)d; }

/* ------------------------------------------------------------------------------------------- */
/* Model: range decoder + context mixing (nova_model.li, decoding side only)                    */
/* ------------------------------------------------------------------------------------------- */

#define NM 7
#define ND 92160
#define LR 6

typedef struct {
  uint32_t *t;
  size_t tcap;
  uint32_t ctx[8];
  int idx[8], st[10], gb[8];
  int64_t weights[1440], weights2[2880], weights3[2880];
  int apm[640 * 33];
  int mt[160];
  int mlb, lite, ultra, nact, hbits;
  int wbase, wbase2, wbase3, abase;
  const uint8_t *inp;
  size_t in_pos, in_end;
  int overrun, oom;
  uint32_t range, code;
} Model;

static int next_byte(Model *m) {
  int r = 0;
  if (m->in_pos < m->in_end) r = m->inp[m->in_pos];
  else if (m->in_pos >= m->in_end + 4) m->overrun = 1;
  m->in_pos++;
  return r;
}

static void model_reset(Model *m, int64_t n) {
  int hb = 12, i;
  size_t size;
  m->nact = m->lite ? 2 : NM;
  while (hb < 22 && ((int64_t)1 << hb) < n * 2) hb++;
  if (m->lite) hb = 0;
  m->hbits = hb;
  size = ND + ((size_t)(m->nact - 2) << hb);
  if (size > m->tcap) {
    uint32_t *t = realloc(m->t, size * sizeof *t);
    if (!t) { m->oom = 1; m->overrun = 1; return; }
    m->t = t;
    m->tcap = size;
  }
  for (i = 0; i < (int)size; i++) m->t[i] = 32768u << 10;
  for (i = 0; i < 1440; i++) m->weights[i] = 65536 * 3 / 10;
  for (i = 0; i < 2880; i++) m->weights2[i] = m->weights3[i] = 65536 * 3 / 10;
  for (i = 0; i < 160; i++) m->mt[i] = 32768 << 10;
  for (i = 0; i < 640 * 33; i++) m->apm[i] = squash(((i % 33) - 16) * 128) * 16;
}

static void model_start(Model *m, const uint8_t *data, size_t pos, size_t len, int64_t n, int lv) {
  int i;
  m->lite = lv < 2;
  m->ultra = lv >= 4;
  m->inp = data;
  m->in_pos = pos;
  m->in_end = pos + len;
  m->overrun = 0;
  m->range = 0xFFFFFFFFu;
  m->code = 0;
  for (i = 0; i < 4; i++) m->code = m->code * 256 + (uint32_t)next_byte(m);
  model_reset(m, n);
}

static int code_bit(Model *m, int p) {
  uint32_t bound = (m->range >> 12) * (uint32_t)(4096 - p);
  int r = 0;
  if (m->code < bound) m->range = bound;
  else { m->code -= bound; m->range -= bound; r = 1; }
  while (m->range < 0x1000000u) {
    m->range <<= 8;
    m->code = (m->code << 8) + (uint32_t)next_byte(m);
  }
  return r;
}

static void set_weights(Model *m, int ws, int ws2, int ws3, int as) { m->wbase = ws; m->wbase2 = ws2; m->wbase3 = ws3; m->abase = as; }

static void group(Model *m, int g) {
  int k, hb = m->hbits;
  for (k = 2; k < m->nact; k++) {
    uint32_t x = m->ctx[k] + (uint32_t)g * 40503u;
    x *= 2146121005u;
    m->gb[k] = ND + ((k - 2) << hb) + (int)((x >> (36 - hb)) << 4);
  }
}

static int bit(Model *m, int nd, int off, int hv) {
  uint32_t *t = m->t;
  int *idx = m->idx, *st = m->st, nact = m->nact, k, cls, ws, ws2, ws3, mi, sm = 0, p, a, wt = 0, r;
  int64_t *W1 = m->weights, *W2 = m->weights2, *W3 = m->weights3, dot = 0, dot2 = 0, dot3 = 0, err;
  int d1, d2, d3 = 0, p1, p2, p3 = 0;
  idx[0] = (int)m->ctx[0] + nd;
  idx[1] = (int)m->ctx[1] + nd;
  for (k = 2; k < nact; k++) idx[k] = m->gb[k] + off;
  cls = nd < 16 ? nd : 9;
  ws = (m->wbase * 10 + cls) * (NM + 2);
  ws2 = (m->wbase2 * 10 + cls) * (NM + 2);
  ws3 = (m->wbase3 * 10 + cls) * (NM + 2);
  for (k = 0; k < nact; k++) {
    int s = STRETCH[t[idx[k]] >> 14];
    st[k] = s;
    dot += W1[ws + k] * s;
    dot2 += W2[ws2 + k] * s;
  }
  mi = m->mlb * 10 + cls;
  if (hv >= 0) {
    sm = STRETCH[(uint32_t)m->mt[mi] >> 14];
    if (hv == 0) sm = -sm;
  }
  st[NM] = sm;
  dot += W1[ws + NM] * sm;
  dot2 += W2[ws2 + NM] * sm;
  if (m->ultra) {
    for (k = 0; k < nact; k++) dot3 += W3[ws3 + k] * st[k];
    dot3 += W3[ws3 + NM] * sm;
    d3 = clamp2047((dot3 + W3[ws3 + NM + 1] * 256) >> 16);
    p3 = SQ[d3 + 2048];
  }
  d1 = clamp2047((dot + W1[ws + NM + 1] * 256) >> 16);
  d2 = clamp2047((dot2 + W2[ws2 + NM + 1] * 256) >> 16);
  p1 = SQ[d1 + 2048];
  p2 = SQ[d2 + 2048];
  if (m->lite) { p = p1; a = -1; }
  else {
    int pm = m->ultra ? SQ[(d1 + d2 + d3) / 3 + 2048] : SQ[((d1 + d2) >> 1) + 2048];
    wt = STRETCH[pm] + 2048;
    a = (m->abase + cls) * 33 + (wt >> 7);
    wt &= 127;
    p = (pm + 3 * (((m->apm[a] * (128 - wt) + m->apm[a + 1] * wt) >> 7) >> 4)) >> 2;
  }
  if (p < 1) p = 1;
  if (p > 4095) p = 4095;
  r = code_bit(m, p);
  if (a >= 0) {
    int j = a + (wt >> 6);
    m->apm[j] += ((r << 16) - r - m->apm[j]) >> 7;
  }
  if (hv >= 0) {
    int v = m->mt[mi], q = v >> 10, n = v & 1023;
    if (r == hv) q += (int)(((uint32_t)(65535 - q) * (uint32_t)RATE[n]) >> 16);
    else q -= (int)(((uint32_t)q * (uint32_t)RATE[n]) >> 16);
    if (n < 255) n++;
    m->mt[mi] = (q << 10) | n;
  }
  for (k = 0; k < nact; k++) {
    int i = idx[k], lim = k < 2 ? 1000 : 60;
    uint32_t v = t[i], q = v >> 10, n = v & 1023;
    if (r == 1) q += ((65535 - q) * (uint32_t)RATE[n]) >> 16;
    else q -= (q * (uint32_t)RATE[n]) >> 16;
    if ((int)n < lim) n++;
    t[i] = (q << 10) | n;
  }
  err = (int64_t)((r << 12) - p1) * LR;
  for (k = 0; k < nact; k++) W1[ws + k] += (st[k] * err) >> 14;
  W1[ws + NM] += (sm * err) >> 14;
  W1[ws + NM + 1] += (256 * err) >> 14;
  if (!m->lite) {
    err = (int64_t)((r << 12) - p2) * LR;
    for (k = 0; k < nact; k++) W2[ws2 + k] += (st[k] * err) >> 14;
    W2[ws2 + NM] += (sm * err) >> 14;
    W2[ws2 + NM + 1] += (256 * err) >> 14;
  }
  if (m->ultra) {
    err = (int64_t)((r << 12) - p3) * LR;
    for (k = 0; k < nact; k++) W3[ws3 + k] += (st[k] * err) >> 14;
    W3[ws3 + NM] += (sm * err) >> 14;
    W3[ws3 + NM + 1] += (256 * err) >> 14;
  }
  return r;
}

/* ------------------------------------------------------------------------------------------- */
/* Levels 0-4 (nova_codec.li)                                                                   */
/* ------------------------------------------------------------------------------------------- */

#define NONE 100000

static int TDX[35], TDY[35];
static void make_taps(void) {
  int i, k, r;
  TDX[0] = -2; TDY[0] = 0;
  for (i = 0; i <= 4; i++) { TDX[1 + i] = i - 2; TDY[1 + i] = -1; TDX[6 + i] = i - 2; TDY[6 + i] = -2; }
  TDX[11] = -3; TDY[11] = 0; TDX[12] = -2; TDY[12] = 0; TDX[13] = -1; TDY[13] = 0;
  k = 14;
  for (r = 1; r <= 3; r++) for (i = 0; i <= 6; i++) { TDX[k] = i - 3; TDY[k] = -r; k++; }
}

typedef struct {
  Model *m;
  int64_t sp[6], lw[192], ld[48], ccn[4], ccd[4];
  int nl_on[2], cur[4];
  uint8_t *px;
  int stride, ox, oy, w, h, level, eps, npred;
  int pmode;
  int *ibuf;
  int ra, rb, rc, rd, raa, rbb;
  int *ebuf, *rbuf;
  int64_t *pbuf;
  int *mtab;
  size_t mcap;
  int mbits, mpos, mlen, mok;
} Codec;

static int sample(Codec *c, int p, int x, int y) {
  const uint8_t *px;
  int i, g;
  if (c->pmode) return c->ibuf[y * c->w + x];
  i = ((c->oy + y) * c->stride + c->ox + x) * 4;
  px = c->px;
  g = px[i + 1];
  if (p == 0) return g;
  if (p == 1) return px[i] - g + 255;
  if (p == 2) return px[i + 2] - g + 255;
  return px[i + 3];
}

static void store(Codec *c, int v, int p, int x, int y) {
  uint8_t *px;
  int i;
  if (c->pmode) { c->ibuf[y * c->w + x] = v; return; }
  i = ((c->oy + y) * c->stride + c->ox + x) * 4;
  px = c->px;
  if (p == 0) px[i + 1] = (uint8_t)v;
  else if (p == 1) px[i] = (uint8_t)((v - 255 + px[i + 1]) & 255);
  else if (p == 2) px[i + 2] = (uint8_t)((v - 255 + px[i + 1]) & 255);
  else px[i + 3] = (uint8_t)v;
}

#define NB(c, p, x, y) ((c)->rbuf[((((y) & 3) * (c)->w) + (x)) * 4 + (p)])
#define ERR_AT(c, p, x, y) ((c)->ebuf[((((y) & 1) * (c)->w) + (x)) * 4 + (p)])
#define PERR(c, p, k, x, y) ((c)->pbuf[(((((y) & 1) * (c)->w) + (x)) * 4 + (p)) * 6 + (k)])

static void neighbours(Codec *c, int p, int x, int y) {
  int ra, rb, rc, rd;
  if (y == 0) {
    ra = x > 0 ? NB(c, p, x - 1, 0) : 0;
    rb = rc = rd = ra;
  } else {
    rb = NB(c, p, x, y - 1);
    if (x > 0) { ra = NB(c, p, x - 1, y); rc = NB(c, p, x - 1, y - 1); } else { ra = rc = rb; }
    rd = x < c->w - 1 ? NB(c, p, x + 1, y - 1) : rb;
  }
  c->ra = ra; c->rb = rb; c->rc = rc; c->rd = rd;
  c->raa = x > 1 ? NB(c, p, x - 2, y) : ra;
  c->rbb = y > 1 ? NB(c, p, x, y - 2) : rb;
}

static int predict(const Codec *c) {
  int ra = c->ra, rb = c->rb, rc = c->rc, mx = ra, mn = rb;
  if (rb > ra) { mx = rb; mn = ra; }
  if (rc >= mx) return mn;
  if (rc <= mn) return mx;
  return ra + rb - rc;
}

static int64_t nlms(Codec *c, int j, int p, int x, int y) {
  int m = 2 + j, n = 11 + j * 13, f = j * 11, k, wv;
  int64_t dot = 0;
  c->nl_on[j] = 0;
  if (y >= m && x >= m && x < c->w - m) {
    c->nl_on[j] = 1;
    wv = NB(c, p, x - 1, y);
    for (k = 0; k < n; k++) {
      int64_t d = NB(c, p, x + TDX[f + k], y + TDY[f + k]) - wv;
      c->ld[j * 24 + k] = d;
      dot += c->lw[(j * 4 + p) * 24 + k] * d;
    }
    return wv + (dot >> 16);
  }
  return c->sp[0];
}

static void nlms_update(Codec *c, int j, int p, int v) {
  int n = 11 + j * 13, k;
  int64_t en = 16, f;
  if (c->nl_on[j] != 1) return;
  for (k = 0; k < n; k++) en += c->ld[j * 24 + k] * c->ld[j * 24 + k];
  f = ((v - c->sp[4 + j]) * 2097 * 1024) / en;
  for (k = 0; k < n; k++) c->lw[(j * 4 + p) * 24 + k] += (f * c->ld[j * 24 + k]) >> 10;
}

static int blend(Codec *c, int p, int x, int y) {
  int64_t *sp = c->sp, sw = 0, sum = 0;
  int w = c->w, k;
  sp[0] = predict(c);
  sp[1] = (c->ra + c->rb + 1) >> 1;
  sp[2] = c->ra + c->rb - c->rc;
  sp[3] = (c->ra + c->rd + 1) >> 1;
  sp[4] = nlms(c, 0, p, x, y);
  if (c->npred == 6) sp[5] = nlms(c, 1, p, x, y);
  for (k = 0; k < c->npred; k++) {
    int64_t s = 0, wk;
    if (x > 0) s += PERR(c, p, k, x - 1, y);
    if (y > 0) {
      s += PERR(c, p, k, x, y - 1);
      if (x > 0) s += PERR(c, p, k, x - 1, y - 1);
      if (x < w - 1) s += PERR(c, p, k, x + 1, y - 1);
    }
    wk = 1073741824 / (8 + s);
    sw += wk;
    sum += wk * sp[k];
  }
  return (int)((sum + (sw >> 1)) / sw);
}

static int cross(const Codec *c, int p) {
  int64_t v = (c->ccn[p] * 64) / (c->ccd[p] + 64);
  if (v < -128) v = -128;
  if (v > 128) v = 128;
  return (int)v;
}

static void codec_contexts(Codec *c, int p, int x, int y, int pr) {
  Model *m = c->m;
  int w = c->w, g, act, sew = 0, sen = 0, ene = 0, enw = 0, ew, en, q1, q2;
  g = iabs(c->rd - c->rb) + iabs(c->rb - c->rc) + iabs(c->rc - c->ra);
  act = qlog(g);
  if (g >= 128) act = 8 + qlog(g >> 7);
  if (x > 0) sew = ERR_AT(c, p, x - 1, y);
  if (y > 0) {
    sen = ERR_AT(c, p, x, y - 1);
    ene = enw = iabs(sen);
    if (x < w - 1) ene = iabs(ERR_AT(c, p, x + 1, y - 1));
    if (x > 0) enw = iabs(ERR_AT(c, p, x - 1, y - 1));
  }
  ew = iabs(sew); en = iabs(sen);
  q1 = qlog(ew + en);
  q2 = p == 0 ? qlog(ene + enw) : qlog(iabs(ERR_AT(c, 0, x, y)));
  m->ctx[0] = (uint32_t)((p * 16 + act) * 80);
  m->ctx[1] = (uint32_t)(5120 + ((p * 16 + qhalf(2 * (ew + en) + ene + enw)) * 8 + q2) * 80);
  set_weights(m, p * 4 + (act >> 2), p * 8 + q1, p * 8 + q2, (p * 16 + act) * 10);
  if (c->level >= 2) {
    int ra = c->ra, rb = c->rb, rc = c->rc, rd = c->rd, i;
    uint32_t h3, h4, h5, h6, h7;
    h3 = hash((uint32_t)p + 1, ra);
    h3 = hash(h3, rb); h3 = hash(h3, rc); h3 = hash(h3, rd); h3 = hash(h3, pr);
    h4 = hash((uint32_t)p + 11, (int)h3);
    h4 = hash(h4, c->raa); h4 = hash(h4, c->rbb);
    h5 = hash((uint32_t)p + 21, ra);
    h5 = hash(h5, rb);
    for (i = 0; i < p; i++) { h4 = hash(h4, c->cur[i]); h5 = hash(h5, c->cur[i]); }
    h5 = hash(h5, pr);
    if (p == 0) h5 = hash(h5, act * 8 + q1);
    h6 = hash((uint32_t)p + 31, sq(ra - pr));
    h6 = hash(h6, sq(rb - pr)); h6 = hash(h6, sq(rc - pr)); h6 = hash(h6, sq(rd - pr));
    h7 = hash((uint32_t)p + 41, sq(sew));
    h7 = hash(h7, sq(sen));
    h7 = p == 0 ? hash(h7, q2) : hash(h7, sq(ERR_AT(c, 0, x, y)));
    m->ctx[2] = h3; m->ctx[3] = h4; m->ctx[4] = h5; m->ctx[5] = h6; m->ctx[6] = h7;
  }
}

/* Decodes one residual; er: residual the match predicts (NONE: no match). */
static int code_residual(Codec *c, int er) {
  Model *m = c->m;
  int ea = iabs(er), en = 0, hv, b, s, n, prefix = 1, off = 1, i;
  while ((ea >> (en + 1)) > 0) en++;
  hv = er != NONE ? (er != 0 ? 1 : 0) : -1;
  group(m, 0);
  b = bit(m, 0, 0, hv);
  if (b != hv) hv = -1;
  if (b != 1) return 0;
  if (hv >= 0) hv = er < 0 ? 1 : 0;
  s = bit(m, 1, 1, hv);
  if (s != hv) hv = -1;
  n = 0;
  for (;;) {
    if (n >= 7) break;
    if (hv >= 0) hv = n < en ? 1 : 0;
    b = bit(m, 2 + n, 2 + n + 7 * s, hv);
    if (b != hv) hv = -1;
    if (b != 1) break;
    n++;
  }
  if (n > 0) group(m, 1 + s * 8 + n);
  for (i = n - 1; i >= 0; i--) {
    if (off >= 16) { group(m, 256 + (s * 8 + n) * 32 + prefix); off = 1; }
    if (hv >= 0) hv = (ea >> i) & 1;
    b = bit(m, 16 + 8 * n + i, off, hv);
    if (b != hv) hv = -1;
    prefix = (prefix << 1) | b;
    off = (off << 1) | b;
  }
  return s == 1 ? -prefix : prefix;
}

static int match_reset(Codec *c) {
  int mb = 12;
  size_t n;
  while (mb < 22 && ((int64_t)1 << mb) < (int64_t)c->w * c->h * 2) mb++;
  c->mbits = mb;
  n = (size_t)1 << mb;
  if (n > c->mcap) {
    int *t = realloc(c->mtab, n * sizeof *t);
    if (!t) return 0;
    c->mtab = t;
    c->mcap = n;
  }
  memset(c->mtab, 0, n * sizeof *c->mtab);
  c->mpos = -1;
  c->mlen = 0;
  c->mok = 0;
  return 1;
}

static void match_step(Codec *c, int np, int x, int y) {
  if (c->mpos >= 0 && c->mok) {
    c->mpos++;
    if (c->mlen < 65535) c->mlen++;
  } else { c->mpos = -1; c->mlen = 0; }
  if (x >= 2 && y >= 2 && x < c->w - 1) {
    uint32_t hh = 0;
    int p;
    for (p = 0; p < np; p++) {
      hh = hash(hh, NB(c, p, x - 1, y));
      hh = hash(hh, NB(c, p, x - 2, y));
      hh = hash(hh, NB(c, p, x - 1, y - 1));
      hh = hash(hh, NB(c, p, x, y - 1));
      hh = hash(hh, NB(c, p, x + 1, y - 1));
      hh = hash(hh, NB(c, p, x, y - 2));
    }
    hh = (hh * 2146121005u) >> (32 - c->mbits);
    if (c->mpos < 0) {
      int k = c->mtab[hh] - 1;
      if (k >= 0) c->mpos = k;
    }
    c->mtab[hh] = y * c->w + x + 1;
  }
  c->mok = c->mpos >= 0;
  c->m->mlb = qhalf(c->mlen);
}

static int expected(Codec *c, int p, int pr, int q) {
  int ev, r;
  if (c->mpos < 0) return NONE;
  ev = sample(c, p, c->mpos % c->w, c->mpos / c->w);
  if (q == 1) {
    r = (ev - pr) & 255;
    if (r > 127) r -= 256;
  } else {
    r = (iabs(ev - pr) + c->eps) / q;
    if (ev < pr) r = -r;
  }
  return r;
}

static void codec_free(Codec *c) {
  free(c->ebuf); free(c->rbuf); free(c->pbuf); free(c->mtab); free(c->ibuf);
  c->ebuf = c->rbuf = c->mtab = c->ibuf = NULL;
  c->pbuf = NULL;
  c->mcap = 0;
}

/* Decodes the region set up in c (np planes). 0 on out of memory. */
static int code_region(Codec *c, int np) {
  int w = c->w, h = c->h, x, y, p, k;
  int *cur = c->cur, level = c->level, eps = c->eps;
  int64_t *sp = c->sp;
  free(c->ebuf); free(c->rbuf); free(c->pbuf);
  c->ebuf = calloc((size_t)w * 8, sizeof *c->ebuf);
  c->rbuf = calloc((size_t)w * 16, sizeof *c->rbuf);
  c->pbuf = calloc((size_t)w * 48, sizeof *c->pbuf);
  if (!c->ebuf || !c->rbuf || !c->pbuf || !match_reset(c)) return 0;
  memset(c->lw, 0, sizeof c->lw);
  c->npred = level >= 4 ? 6 : 5;
  memset(c->ccn, 0, sizeof c->ccn);
  memset(c->ccd, 0, sizeof c->ccd);
  for (y = 0; y < h; y++) {
    for (x = 0; x < w; x++) {
      match_step(c, np, x, y);
      for (p = 0; p < np; p++) {
        int lo = (p == 1 || p == 2) ? 255 - cur[0] : 0, base, pr, eg = 0, q, er, e, v, i;
        neighbours(c, p, x, y);
        base = level < 3 ? predict(c) : blend(c, p, x, y);
        pr = base;
        if (level >= 3 && lo != 0) {
          eg = ERR_AT(c, 0, x, y);
          pr += (cross(c, p) * eg) >> 6;
        }
        if (pr < lo) pr = lo;
        if (pr > lo + 255) pr = lo + 255;
        codec_contexts(c, p, x, y, pr);
        q = p < 3 ? 2 * eps + 1 : 1;
        er = expected(c, p, pr, q);
        e = code_residual(c, er);
        if (q == 1) v = lo + ((pr - lo + e + 256) & 255);
        else {
          v = pr + e * q;
          if (v < lo) v = lo;
          if (v > lo + 255) v = lo + 255;
        }
        store(c, v, p, x, y);
        if (er == NONE || e != er) c->mok = 0;
        cur[p] = v;
        NB(c, p, x, y) = v;
        i = (((y & 1) * w) + x) * 4 + p;
        c->ebuf[i] = e;
        if (level >= 3) {
          for (k = 0; k < c->npred; k++) {
            int64_t d = v - sp[k];
            c->pbuf[i * 6 + k] = d < 0 ? -d : d;
          }
          nlms_update(c, 0, p, v);
          if (c->npred == 6) nlms_update(c, 1, p, v);
        }
        if (level >= 3 && lo != 0) {
          int raw = v - base;
          c->ccn[p] = c->ccn[p] - (c->ccn[p] >> 10) + (int64_t)eg * raw;
          c->ccd[p] = c->ccd[p] - (c->ccd[p] >> 10) + (int64_t)eg * eg;
        }
      }
    }
  }
  return 1;
}

static int decode_palette(Codec *c, const uint8_t *data, size_t pos, size_t len, int np) {
  int n = data[pos] + 1, j, x, y, w = c->w, h = c->h;
  size_t k = pos + 1 + (size_t)n * np;
  uint8_t pal[256 * 4];
  if (k > pos + len) return 0;
  for (j = 0; j < n; j++) {
    size_t i = pos + 1 + (size_t)j * np;
    pal[j * 4] = data[i]; pal[j * 4 + 1] = data[i + 1]; pal[j * 4 + 2] = data[i + 2];
    pal[j * 4 + 3] = np == 4 ? data[i + 3] : 255;
  }
  free(c->ibuf);
  c->ibuf = malloc((size_t)w * h * sizeof *c->ibuf);
  if (!c->ibuf) return 0;
  c->pmode = 1;
  c->level = 2;
  c->eps = 0;
  model_start(c->m, data, k, pos + len - k, (int64_t)w * h, 2);
  if (c->m->oom || !code_region(c, 1)) { c->pmode = 0; return 0; }
  c->pmode = 0;
  /* ponytail: np 1 (alpha region) at level 0 writes the palette's first byte to G, as the C does. */
  for (y = 0; y < h; y++) {
    for (x = 0; x < w; x++) {
      int ci = c->ibuf[y * w + x];
      size_t i = ((size_t)(c->oy + y) * c->stride + c->ox + x) * 4;
      if (ci >= n) ci = n - 1;
      c->px[i] = pal[ci * 4]; c->px[i + 1] = pal[ci * 4 + 1]; c->px[i + 2] = pal[ci * 4 + 2]; c->px[i + 3] = pal[ci * 4 + 3];
    }
  }
  return !c->m->overrun;
}

static uint32_t u32(const uint8_t *d, size_t p) { return ((uint32_t)d[p] << 24) | ((uint32_t)d[p + 1] << 16) | ((uint32_t)d[p + 2] << 8) | d[p + 3]; }
static int u16(const uint8_t *d, size_t p) { return (d[p] << 8) | d[p + 1]; }

/* ------------------------------------------------------------------------------------------- */
/* Level 5 (nova_lossy.li + nova_wavelet.li)                                                    */
/* ------------------------------------------------------------------------------------------- */

static const int POW_T[14] = { 1000, 1051, 1104, 1160, 1219, 1281, 1346, 1414, 1486, 1561, 1641, 1724, 1811, 1903 };
#define RECON 26
#define CHROMA1 512
#define CHROMA2 420

static int wavelet_levels(int w, int h) {
  int l = 0;
  while (l < 6 && ((w + (1 << l) - 1) >> l) >= 16 && ((h + (1 << l) - 1) >> l) >= 16) l++;
  return l;
}

static void lift(int32_t *c, size_t base, int step, int n, int k, int par, int sg) {
  int j;
  for (j = par; j < n; j += 2) {
    int l = j - 1, r = j + 1;
    size_t i = base + (size_t)j * step;
    if (l < 0) l = 1;
    if (r >= n) r = n - 2;
    c[i] = c[i] + sg * (int32_t)(((int64_t)k * ((int64_t)c[base + (size_t)l * step] + c[base + (size_t)r * step]) + 2048) >> 12);
  }
}

static void lift_cols(int32_t *c, int w, int nw, int st, int n, int k, int par, int sg) {
  size_t rs = (size_t)st * w;
  int j, i;
  for (j = par; j < n; j += 2) {
    int l = j - 1, r = j + 1;
    size_t a, b, d;
    if (l < 0) l = 1;
    if (r >= n) r = n - 2;
    a = l * rs; b = r * rs; d = j * rs;
    for (i = 0; i < nw; i++) {
      size_t o = (size_t)i * st;
      c[d + o] = c[d + o] + sg * (int32_t)(((int64_t)k * ((int64_t)c[a + o] + c[b + o]) + 2048) >> 12);
    }
  }
}

static void wavelet_inverse(int32_t *c, int w, int h, int levels) {
  int k, i;
  for (k = levels - 1; k >= 0; k--) {
    int st = 1 << k, nw = (w + st - 1) >> k, nh = (h + st - 1) >> k;
    if (nh >= 2) {
      lift_cols(c, w, nw, st, nh, 1817, 0, -1);
      lift_cols(c, w, nw, st, nh, 3616, 1, -1);
      lift_cols(c, w, nw, st, nh, -217, 0, -1);
      lift_cols(c, w, nw, st, nh, -6497, 1, -1);
    }
    if (nw >= 2) {
      for (i = 0; i < nh; i++) {
        size_t base = (size_t)i * st * w;
        lift(c, base, st, nw, 1817, 0, -1);
        lift(c, base, st, nw, 3616, 1, -1);
        lift(c, base, st, nw, -217, 0, -1);
        lift(c, base, st, nw, -6497, 1, -1);
      }
    }
  }
}

/* Band (k, o): o = 0 low-low (k = levels), 1 HL, 2 LH, 3 HH. */
typedef struct { int k, o, bs, bx, by; } Band;
static Band band(int k, int o) {
  Band b;
  b.k = k; b.o = o;
  b.bs = o == 0 ? 1 << k : 2 << k;
  b.bx = (o == 1 || o == 3) ? 1 << k : 0;
  b.by = (o == 2 || o == 3) ? 1 << k : 0;
  return b;
}

static int64_t lossy_step(int q, int p, Band b) {
  int e = 108 - q, n, i;
  int64_t d = ((((int64_t)512 * 256 * POW_T[e % 14]) / 1000) << (e / 14)) >> 2;
  if (p == 1) d = (d * CHROMA1) / 256;
  if (p == 2) d = (d * CHROMA2) / 256;
  n = b.o == 3 ? b.k - 1 : b.k;
  for (i = 1; i <= n; i++) d = (d * 4096) / 5413;
  return d < 16 ? 16 : d;
}

typedef struct {
  Model *m;
  int w, h, levels, ytop, ybot;
  size_t off;
  int32_t *pl[3];
  uint8_t *zb;
  int zcap;
  int bk, bo, bs, bx, by;
} Lossy;

static void set_band(Lossy *L, Band b) { L->bk = b.k; L->bo = b.o; L->bs = b.bs; L->bx = b.bx; L->by = b.by; }

static int aq(const Lossy *L, int p, int x, int y) {
  return (x >= 0 && y >= L->ytop && x < L->w && y < L->ybot) ? iabs(L->pl[p][(size_t)y * L->w + x - L->off]) : 0;
}

static int sv(const Lossy *L, int p, int x, int y) {
  return (x >= 0 && y >= L->ytop && x < L->w && y < L->ybot) ? L->pl[p][(size_t)y * L->w + x - L->off] : 0;
}

static void lossy_contexts(Lossy *L, int p, int x, int y) {
  Model *m = L->m;
  int bs = L->bs, bk = L->bk, bo = L->bo, bx = L->bx, by = L->by, w = L->w;
  const int32_t *pl = L->pl[p];
  size_t i = (size_t)y * w + x - L->off;
  int cw, cn, cnw, cne, cww, cnn, vw, vn, par = 0, cous = 0, lum = 0, a, bc, q1, q2;
  uint32_t hh;
  if (x >= 2 * bs && x + bs < w && y - 2 * bs >= L->ytop) {
    size_t r = (size_t)bs * w;
    vw = pl[i - bs]; vn = pl[i - r];
    cw = iabs(vw); cn = iabs(vn); cnw = iabs(pl[i - bs - r]);
    cne = iabs(pl[i + bs - r]); cww = iabs(pl[i - 2 * bs]); cnn = iabs(pl[i - 2 * r]);
  } else {
    cw = aq(L, p, x - bs, y); cn = aq(L, p, x, y - bs); cnw = aq(L, p, x - bs, y - bs);
    cne = aq(L, p, x + bs, y - bs); cww = aq(L, p, x - 2 * bs, y); cnn = aq(L, p, x, y - 2 * bs);
    vw = sv(L, p, x - bs, y); vn = sv(L, p, x, y - bs);
  }
  if (bo > 0 && bk + 1 < L->levels) par = aq(L, p, bx * 2 + ((x - bx) / bs / 2) * bs * 2, by * 2 + ((y - by) / bs / 2) * bs * 2);
  if (bo == 2) cous = aq(L, p, x + (1 << bk), y - (1 << bk));
  if (bo == 3) cous = aq(L, p, x, y - (1 << bk)) + aq(L, p, x - (1 << bk), y);
  if (p > 0) lum = iabs(L->pl[0][i]);
  if (p == 2) lum += iabs(L->pl[1][i]);
  a = qhalf(clip(2 * (cw + cn) + cnw + cne + par, 4095));
  bc = bo > 0 ? 1 + clip(bk, 4) * 3 + bo - 1 : 0;
  q1 = qlog(clip(cw + cn, 4095));
  q2 = p == 0 ? qlog(clip(2 * par + cous, 4095)) : qlog(clip(2 * lum + cous, 4095));
  m->ctx[0] = (uint32_t)((((p * 16 + bc) * 12) + clip(a, 11)) * 80);
  m->ctx[1] = (uint32_t)(46080 + ((p * 16 + bc) * 8 + q2) * 80);
  set_weights(m, p * 4 + (a >> 2), p * 8 + (bc >> 1), p * 8 + q2, (p * 16 + a) * 10);
  hh = hash((uint32_t)p + 1, bc);
  hh = hash(hh, sclip(vw, 15));
  hh = hash(hh, sclip(vn, 15));
  hh = hash(hh, clip(cnw, 7));
  hh = hash(hh, clip(cne, 7));
  m->ctx[2] = hh;
  hh = hash((uint32_t)p + 11, bc);
  hh = hash(hh, a);
  hh = hash(hh, clip(par, 15));
  hh = hash(hh, clip(cous, 15));
  m->ctx[3] = hh;
  hh = hash((uint32_t)p + 21, bc);
  hh = hash(hh, a >> 1);
  if (p > 0) hh = hash(hh, sclip(L->pl[0][i], 15));
  if (p == 2) hh = hash(hh, sclip(L->pl[1][i], 15));
  m->ctx[4] = hh;
  hh = hash((uint32_t)p + 31, bc);
  hh = hash(hh, qlog(clip(cw, 4095)));
  hh = hash(hh, qlog(clip(cn, 4095)));
  hh = hash(hh, qlog(clip(cnw, 4095)));
  hh = hash(hh, qlog(clip(cne, 4095)));
  hh = hash(hh, qlog(clip(cww, 4095)));
  hh = hash(hh, qlog(clip(cnn, 4095)));
  hh = hash(hh, qlog(clip(par, 4095)));
  m->ctx[5] = hh;
  hh = hash((uint32_t)p + 41, bc);
  hh = hash(hh, q2);
  hh = hash(hh, q1);
  hh = hash(hh, qlog(clip(lum, 4095)));
  m->ctx[6] = hh;
}

static int code_coef(Lossy *L) {
  Model *m = L->m;
  int s, n = 0, v = 1, off = 1, i;
  group(m, 0);
  if (bit(m, 0, 0, -1) != 1) return 0;
  s = bit(m, 1, 1, -1);
  for (;;) {
    int sl;
    if (n >= 20) break;
    if (n == 14) group(m, 1);
    sl = n >= 14 ? n - 14 : 2 + n;
    if (bit(m, 2 + n, sl, -1) != 1) break;
    n++;
  }
  if (n > 0) group(m, 2 + n);
  for (i = n - 1; i >= 0; i--) {
    int b;
    if (n - 1 - i < 3) {
      b = bit(m, 22 + (n > 18 ? 18 : n) * 3 + (n - 1 - i), off, -1);
      off = (off << 1) | b;
    } else b = code_bit(m, 2048);
    v = v * 2 + b;
  }
  return s == 1 ? -v : v;
}

static void code_flags(Lossy *L, int y) {
  Model *m = L->m;
  int bs = L->bs, bo = L->bo, bx = L->bx, by = L->by, w = L->w, lf = 1, i = 0, x;
  for (x = bx; x < w; x += 2 * bs) {
    int n = 0, par = 0, cous = 0, p, j, k, up, a, q, z;
    uint32_t hh;
    for (p = 0; p < 3; p++) {
      n += aq(L, p, x - bs, y - bs) + aq(L, p, x, y - bs) + aq(L, p, x + bs, y - bs) + aq(L, p, x + 2 * bs, y - bs);
      if (L->levels > 1) par += aq(L, p, bx * 2 + ((x - bx) / bs / 2) * bs * 2, by * 2 + ((y - by) / bs / 2) * bs * 2);
      for (j = 0; j <= 1; j++) {
        for (k = 0; k <= 1; k++) {
          if (bo == 2) cous += aq(L, p, x + k * bs + 1, y + j * bs - 1);
          if (bo == 3) cous += aq(L, p, x + k * bs, y + j * bs - 1) + aq(L, p, x + k * bs - 1, y + j * bs);
        }
      }
    }
    up = L->zb[i];
    a = clip(qhalf(clip(2 * n + 3 * par + cous, 4095)), 11);
    q = qlog(clip(par, 4095));
    m->ctx[0] = (uint32_t)((bo * 12 + a) * 80);
    m->ctx[1] = (uint32_t)(46080 + ((lf * 16 + bo) * 8 + q) * 80);
    set_weights(m, 12 + (a >> 2), 24 + lf * 2 + up, 24 + q, (48 + a) * 10);
    hh = hash(51, bo);
    hh = hash(hh, a);
    m->ctx[2] = hash(hh, lf);
    hh = hash(52, bo);
    hh = hash(hh, clip(par, 15));
    m->ctx[3] = hash(hh, clip(cous, 15));
    hh = hash(53, bo);
    hh = hash(hh, qlog(clip(n, 4095)));
    hh = hash(hh, q);
    m->ctx[4] = hash(hh, lf);
    hh = hash(54, bo);
    hh = hash(hh, clip(n, 15));
    m->ctx[5] = hash(hh, up);
    hh = hash(55, bo);
    hh = hash(hh, qlog(clip(cous, 4095)));
    hh = hash(hh, up);
    m->ctx[6] = hash(hh, lf);
    group(m, 40);
    z = bit(m, 79, 0, -1);
    L->zb[i] = (uint8_t)z;
    lf = z;
    i++;
  }
}

static void code_position(Lossy *L, int x, int y) {
  int bs = L->bs, w = L->w, p;
  for (p = 0; p < 3; p++) {
    size_t i = (size_t)y * w + x - L->off;
    lossy_contexts(L, p, x, y);
    if (L->bo == 0) {
      int a = sv(L, p, x - bs, y), b = sv(L, p, x, y - bs), c = sv(L, p, x - bs, y - bs), mx, mn, pr;
      if (x == 0) a = b;
      if (y == L->ytop) { b = a; c = a; }
      if (x == 0) c = b;
      mx = a; mn = b;
      if (b > a) { mx = b; mn = a; }
      pr = c >= mx ? mn : c <= mn ? mx : a + b - c;
      L->pl[p][i] = pr + code_coef(L);
    } else L->pl[p][i] = code_coef(L);
  }
}

static int code_band(Lossy *L) {
  int fine = L->bo > 0 && L->bk == 0, bs = L->bs, bx = L->bx, w = L->w, x, y;
  if (fine) {
    if (L->zcap < w) {
      uint8_t *z = realloc(L->zb, (size_t)w);
      if (!z) return 0;
      L->zb = z;
      L->zcap = w;
    }
    memset(L->zb, 1, (size_t)w);
  }
  for (y = L->ytop + L->by; y < L->ybot; y += bs) {
    if (fine && ((y - L->ytop - L->by) / bs) % 2 == 0) code_flags(L, y);
    for (x = bx; x < w; x += bs) {
      if (fine && L->zb[(x - bx) / (2 * bs)] == 1) {
        size_t i = (size_t)y * w + x - L->off;
        L->pl[0][i] = 0; L->pl[1][i] = 0; L->pl[2][i] = 0;
      } else code_position(L, x, y);
    }
  }
  return 1;
}

/* Rows [ytop, ybot) of stripe s of ns (multiples of 2^levels). */
static void lossy_rows(int w, int h, int s, int ns, int *a, int *b) {
  int u = 1 << wavelet_levels(w, h), n = (h + u - 1) / u, per = (n + ns - 1) / ns;
  *a = s * per * u < h ? s * per * u : h;
  *b = (s + 1) * per * u < h ? (s + 1) * per * u : h;
}

/* Decodes the coefficients of stripe s (of ns) into the rows of the full planes P (w x h). */
static int decode_stripe(Lossy *L, int32_t *P[3], const uint8_t *d, size_t off, size_t len, int s, int ns) {
  int a, b, k, o, c;
  lossy_rows(L->w, L->h, s, ns, &a, &b);
  L->ytop = a;
  L->ybot = b;
  L->off = 0;
  for (c = 0; c < 3; c++) L->pl[c] = P[c];   /* the full planes: indices y * w + x, rows of this stripe only */
  model_start(L->m, d, off, len, (int64_t)L->w * (b - a) * 3 / 16, 3);
  if (L->m->oom) return 0;
  L->m->mlb = 0;
  set_band(L, band(L->levels, 0));
  if (!code_band(L)) return 0;
  for (k = L->levels - 1; k >= 0; k--) {
    for (o = 1; o <= 3; o++) { set_band(L, band(k, o)); if (!code_band(L)) return 0; }
  }
  return !L->m->overrun;
}

/* Dequantizes plane p and inverts its wavelet, in place. */
static void lossy_plane(int32_t *a, int w, int h, int q, int p) {
  int levels = wavelet_levels(w, h), k, o, x, y;
  for (k = levels; k >= 0; k--) {
    for (o = (k == levels ? 0 : 1); o <= (k == levels ? 0 : 3); o++) {
      Band b = band(k, o);
      int64_t st = lossy_step(q, p, b), rc = (RECON * st) >> 8;
      for (y = b.by; y < h; y += b.bs) {
        for (x = b.bx; x < w; x += b.bs) {
          size_t i = (size_t)y * w + x;
          int32_t v = a[i];
          if (v != 0) {
            int32_t cv = (int32_t)(((int64_t)iabs(v) * st + rc + 128) >> 8);
            a[i] = v < 0 ? -cv : cv;
          }
        }
      }
    }
  }
  wavelet_inverse(a, w, h, levels);
}

static uint8_t px6(int v) { v = (v + 32) >> 6; return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v); }

/* Writes the YCoCg planes (after lossy_plane) as RGB into buf (region x0, y0, w, h of stride s). */
static void lossy_finish(int32_t *P[3], int w, int h, uint8_t *buf, int s, int x0, int y0) {
  int x, y;
  for (y = 0; y < h; y++) {
    for (x = 0; x < w; x++) {
      size_t i = ((size_t)(y0 + y) * s + x0 + x) * 4, j = (size_t)y * w + x;
      int yy = P[0][j] + 8192, co = P[1][j], cg = P[2][j];
      buf[i] = px6(yy + co - cg);
      buf[i + 1] = px6(yy + cg);
      buf[i + 2] = px6(yy - co - cg);
    }
  }
}

/* ------------------------------------------------------------------------------------------- */
/* Region decoder (nova_codec.li decode)                                                        */
/* ------------------------------------------------------------------------------------------- */

typedef struct {
  Model m;
  Codec c;
  Lossy l;
} State;

typedef void (*job_fn)(void *ctx, int i, State *S);
static int run_jobs(int n, job_fn fn, void *ctx, State *S);

/* Stripe jobs of one region: (off, len) of each stream. */
typedef struct {
  const uint8_t *data;
  size_t off[16], len[16];
  int ns, ok;
  int32_t *P[3];                    /* level 5 */
  int fw, fh, q;
  uint8_t *buf;                     /* levels 1-4 */
  int s, x0, y0, rows, np, lv;
} Stripes;

static void l5_job(void *ctx, int i, State *S) {
  Stripes *J = ctx;
  Lossy *L = &S->l;
  L->m = &S->m;
  L->w = J->fw; L->h = J->fh; L->levels = wavelet_levels(J->fw, J->fh);
  if (!decode_stripe(L, J->P, J->data, J->off[i], J->len[i], i, J->ns)) J->ok = 0;
}

static void plane_job(void *ctx, int i, State *S) {
  Stripes *J = ctx;
  (void)S;
  lossy_plane(J->P[i], J->fw, J->fh, J->q, i);
}

static void l14_job(void *ctx, int i, State *S) {
  Stripes *J = ctx;
  Codec *c = &S->c;
  int y = i * J->rows, r = J->rows < J->fh - y ? J->rows : J->fh - y;
  /* Decoded in place: a stripe reads only its own rows (region-relative coordinates). */
  c->m = &S->m;
  c->px = J->buf; c->stride = J->s; c->ox = J->x0; c->oy = J->y0 + y; c->w = J->fw; c->h = r;
  c->level = J->lv;
  c->eps = J->q;
  model_start(&S->m, J->data, J->off[i], J->len[i], (int64_t)J->fw * r * J->np, J->lv);
  if (S->m.oom || !code_region(c, J->np) || S->m.overrun) J->ok = 0;
}

/* Reads a stripe table [ns] ns x (u32 length, stream) in d[pos, end) into J. */
static int stripe_table(Stripes *J, const uint8_t *d, size_t pos, size_t end) {
  size_t tp = pos + 1;
  int i;
  if (pos >= end) return 0;
  J->ns = d[pos];
  if (J->ns < 1 || J->ns > 16) return 0;
  for (i = 0; i < J->ns; i++) {
    size_t sl;
    if (tp + 4 > end) return 0;
    sl = u32(d, tp);
    if (tp + 4 + sl > end) return 0;
    J->off[i] = tp + 4;
    J->len[i] = sl;
    tp += 4 + sl;
  }
  return 1;
}

static int decode_region(State *S, const uint8_t *data, size_t pos, size_t len, uint8_t *buf, int s,
                         int x0, int y0, int fw, int fh, int np) {
  int lv = len >= 1 ? data[pos] : -1, q = len >= 2 ? data[pos + 1] : -1;
  if (len >= 3 && lv == 0) {
    Codec *c = &S->c;
    c->px = buf; c->stride = s; c->ox = x0; c->oy = y0; c->w = fw; c->h = fh;
    return decode_palette(c, data, pos + 2, len - 2, np);
  }
  if (lv == 5 && q <= 100 && (np == 3 ? len >= 2 : len >= 6)) {
    size_t p = pos + 2, n = len - 2;
    int ok, c;
    Stripes J;
    memset(&J, 0, sizeof J);
    if (np == 4) {
      n = u32(data, pos + 2);
      if (n > len - 8 || data[pos + 6 + n] < 1 || data[pos + 6 + n] > 4) return 0;
      p = pos + 6;
    }
    if (!stripe_table(&J, data, p, p + n)) return 0;
    for (c = 0; c < 3; c++) J.P[c] = calloc((size_t)fw * fh, sizeof(int32_t));
    J.data = data; J.fw = fw; J.fh = fh; J.q = q; J.ok = 1;
    ok = J.P[0] && J.P[1] && J.P[2] && run_jobs(J.ns, l5_job, &J, S) && J.ok;
    if (ok) {
      ok = run_jobs(3, plane_job, &J, S);
      if (ok) lossy_finish(J.P, fw, fh, buf, s, x0, y0);
    }
    for (c = 0; c < 3; c++) free(J.P[c]);
    if (np == 4 && ok) {
      int x, y;
      uint8_t *a = calloc((size_t)fw * fh * 4, 1);
      if (!a) return 0;
      for (y = 0; y < fh; y++) for (x = 0; x < fw; x++) a[((size_t)y * fw + x) * 4 + 1] = buf[((size_t)(y0 + y) * s + x0 + x) * 4 + 3];
      ok = decode_region(S, data, pos + 6 + n, len - 6 - n, a, fw, 0, 0, fw, fh, 1);
      for (y = 0; y < fh; y++) for (x = 0; x < fw; x++) buf[((size_t)(y0 + y) * s + x0 + x) * 4 + 3] = a[((size_t)y * fw + x) * 4 + 1];
      free(a);
    }
    return ok;
  }
  if (len >= 3 && lv >= 1 && lv <= 4 && q <= 64) {
    Stripes J;
    memset(&J, 0, sizeof J);
    if (!stripe_table(&J, data, pos + 2, pos + len) || J.ns > fh) return 0;
    J.data = data; J.buf = buf; J.s = s; J.x0 = x0; J.y0 = y0; J.fw = fw; J.fh = fh;
    J.rows = (fh + J.ns - 1) / J.ns; J.np = np; J.lv = lv; J.q = q; J.ok = 1;
    if ((J.ns - 1) * J.rows >= fh) return 0;
    return run_jobs(J.ns, l14_job, &J, S) && J.ok;
  }
  return 0;
}

static State *state_new(void) {
  State *S = calloc(1, sizeof *S);
  if (!S) return NULL;
  make_tables();
  make_taps();
  S->c.m = &S->m;
  S->l.m = &S->m;
  return S;
}

static void state_free(State *S) {
  if (!S) return;
  codec_free(&S->c);
  free(S->l.zb);
  free(S->m.t);
  free(S);
}

/* Runs fn(ctx, i, state) for i in [0, n) on up to one thread per core, each thread with its own State
   (a level 1-4 stripe model takes up to ~80 MB: threads are capped, not one per job). */
typedef void (*job_fn)(void *ctx, int i, State *S);
typedef struct { job_fn fn; void *ctx; int n; volatile long next; volatile int failed; } Jobs;

static void jobs_loop(Jobs *J, State *S0) {
  State *S = S0 ? S0 : state_new();
  if (!S) { J->failed = 1; return; }
  for (;;) {
#if defined(NOVADEC_NO_THREADS)
    long i = J->next++;
#elif defined(_WIN32)
    long i = InterlockedIncrement(&J->next) - 1;
#else
    long i = __atomic_fetch_add(&J->next, 1, __ATOMIC_SEQ_CST);
#endif
    if (i >= J->n) break;
    J->fn(J->ctx, (int)i, S);
  }
  if (!S0) state_free(S);
}

static int ncpu(void) {
  const char *e = getenv("NOVADEC_THREADS");
  int n = e ? atoi(e) : 0;
#if !defined(NOVADEC_NO_THREADS)
  if (n < 1) {
#ifdef _WIN32
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    n = (int)si.dwNumberOfProcessors;
#else
    n = (int)sysconf(_SC_NPROCESSORS_ONLN);
#endif
  }
#endif
  return n < 1 ? 1 : n > 64 ? 64 : n;
}

#if !defined(NOVADEC_NO_THREADS)
#ifdef _WIN32
static DWORD WINAPI job_thread(LPVOID a) { jobs_loop((Jobs *)a, NULL); return 0; }
#else
static void *job_thread(void *a) { jobs_loop((Jobs *)a, NULL); return NULL; }
#endif
#endif

/* S: the caller's State, used by the calling thread. Returns 0 if a job failed to get memory. */
static int run_jobs(int n, job_fn fn, void *ctx, State *S) {
  Jobs J;
  int nt = ncpu(), t = 0;
  J.fn = fn; J.ctx = ctx; J.n = n; J.next = 0; J.failed = 0;
  if (nt > n) nt = n;
#if !defined(NOVADEC_NO_THREADS)
  {
#ifdef _WIN32
    HANDLE th[64];
    for (t = 0; t < nt - 1; t++) if (!(th[t] = CreateThread(NULL, 0, job_thread, &J, 0, NULL))) break;
    jobs_loop(&J, S);
    WaitForMultipleObjects((DWORD)t, th, TRUE, INFINITE);
    while (t > 0) CloseHandle(th[--t]);
#else
    pthread_t th[64];
    for (t = 0; t < nt - 1; t++) if (pthread_create(&th[t], NULL, job_thread, &J)) break;
    jobs_loop(&J, S);
    while (t > 0) pthread_join(th[--t], NULL);
#endif
  }
#else
  (void)nt; (void)t;
  jobs_loop(&J, S);
#endif
  return !J.failed;
}

/* ------------------------------------------------------------------------------------------- */
/* Container (nova.li read_nova)                                                                */
/* ------------------------------------------------------------------------------------------- */

#define TAG(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))
#define T_IHDR TAG('I', 'H', 'D', 'R')
#define T_ANIM TAG('A', 'N', 'I', 'M')
#define T_FDAT TAG('F', 'D', 'A', 'T')
#define T_FDLT TAG('F', 'D', 'L', 'T')
#define T_IEND TAG('I', 'E', 'N', 'D')
#define T_MDAT TAG('M', 'D', 'A', 'T')
#define T_PREV TAG('P', 'R', 'E', 'V')

static uint32_t crc(uint32_t c, const uint8_t *d, size_t lo, size_t hi) {
  static uint32_t T[256];
  static volatile int ready;
  size_t i;
  if (!ready) {
    uint32_t n, k, v;
    for (n = 0; n < 256; n++) {
      v = n;
      for (k = 0; k < 8; k++) v = v & 1 ? 0xEDB88320u ^ (v >> 1) : v >> 1;
      T[n] = v;
    }
    ready = 1;
  }
  for (i = lo; i < hi; i++) c = T[(c ^ d[i]) & 255] ^ (c >> 8);
  return c;
}

int nova_check(const uint8_t *d, size_t n) {
  return n >= 9 && u32(d, 0) == 0x894E4F56u && u32(d, 4) == 0x410D0A1Au && d[8] == 0x0A;
}

/* Walks the chunks: calls fn(type, pos, len, arg) for each; fills info from IHDR / ANIM. */
typedef int (*chunk_fn)(uint32_t t, size_t pos, size_t len, void *arg);
static int walk(const uint8_t *d, size_t n, nova_info *f, chunk_fn fn, void *arg) {
  size_t pos = 9;
  int nframes = 0;
  memset(f, 0, sizeof *f);
  f->delay = 100;
  f->frames = 1;
  f->orientation = 1;
  if (!nova_check(d, n)) { f->error = "not a NOVA file"; return -1; }
  while (pos < n) {
    uint32_t t, len, c;
    size_t p;
    if (pos + 12 > n) { f->error = "truncated file"; return -1; }
    t = u32(d, pos);
    len = u32(d, pos + 4);
    if (len > n - pos - 12) { f->error = "truncated file"; return -1; }
    c = crc(0xFFFFFFFFu, d, pos, pos + 4);
    c = crc(c, d, pos + 8, pos + 8 + len);
    if ((c ^ 0xFFFFFFFFu) != u32(d, pos + 8 + len)) { f->error = "CRC mismatch"; return -1; }
    p = pos + 8;
    if (t == T_IHDR) {
      int flags;
      if (len < 12) { f->error = "bad IHDR"; return -1; }
      f->width = (int)u32(d, p); f->height = (int)u32(d, p + 4); f->planes = d[p + 9];
      flags = d[p + 11];
      f->raw = (flags & 8) != 0;
      if (d[p + 10] != 2) { f->error = "unsupported NOVA version (only v2)"; return -1; }
      if (!f->raw && (d[p + 8] != 8 || (f->planes != 3 && f->planes != 4))) { f->error = "unsupported frame format"; return -1; }
      if (u32(d, p) == 0 || u32(d, p + 4) == 0 || u32(d, p) > 65535 || u32(d, p + 4) > 65535) { f->error = "bad size"; return -1; }
    } else if (t == T_ANIM && len >= 4) {
      nframes = (int)u32(d, p);
      if (len >= 6) f->delay = u16(d, p + 4);
    } else if (t == T_PREV && len >= 5) f->has_preview = 1;
    if (fn && fn(t, p, len, arg)) return -1;
    pos = p + len + 4;
    if (t == T_IEND) break;
  }
  if (!f->width) { f->error = "no IHDR"; return -1; }
  if (nframes > 0) f->frames = nframes;
  return 0;
}

/* EXIF orientation of a TIFF block t[0, n). */
static int tiff_orientation(const uint8_t *t, size_t n) {
  int le, i, cnt;
  size_t ifd;
  if (n < 8) return 1;
  le = t[0] == 0x49;
#define T16(i) (le ? (t[i] | t[(i) + 1] << 8) : (t[i] << 8 | t[(i) + 1]))
  ifd = le ? ((size_t)t[4] | (size_t)t[5] << 8 | (size_t)t[6] << 16 | (size_t)t[7] << 24) : u32(t, 4);
  if (ifd + 2 > n) return 1;
  cnt = T16(ifd);
  for (i = 0; i < cnt && ifd + 14 + (size_t)i * 12 <= n; i++) {
    size_t e = ifd + 2 + (size_t)i * 12;
    if (T16(e) == 0x0112) { int o = T16(e + 8); return o >= 1 && o <= 8 ? o : 1; }
  }
#undef T16
  return 1;
}

typedef struct { const uint8_t *d; nova_info *f; int seen; const uint8_t *icc; size_t icc_len; } MetaScan;
static int scan_meta(uint32_t t, size_t pos, size_t len, void *arg) {
  MetaScan *s = arg;
  const uint8_t *p;
  if (t != T_MDAT || len < 12) return 0;
  p = s->d + pos;
  if (!s->seen && !memcmp(p, "eXIf", 4)) { s->f->orientation = tiff_orientation(p + 4, len - 4); s->seen = 1; }
  else if (!s->seen && !memcmp(p, "APP1", 4) && len >= 10 && !memcmp(p + 4, "Exif\0\0", 6)) { s->f->orientation = tiff_orientation(p + 10, len - 10); s->seen = 1; }
  else if (!s->icc && !memcmp(p, "APP2", 4) && len >= 18 && !memcmp(p + 4, "ICC_PROFILE", 12)) { s->icc = p + 18; s->icc_len = len - 18; }
  return 0;
}

int nova_read_info(const uint8_t *d, size_t n, nova_info *info) {
  MetaScan s;
  memset(&s, 0, sizeof s);
  s.d = d; s.f = info;
  return walk(d, n, info, scan_meta, &s);
}

const uint8_t *nova_icc(const uint8_t *d, size_t n, size_t *len) {
  nova_info f;
  MetaScan s;
  memset(&s, 0, sizeof s);
  s.d = d; s.f = &f;
  if (walk(d, n, &f, scan_meta, &s)) return NULL;
  if (len) *len = s.icc_len;
  return s.icc;
}

typedef struct {
  const uint8_t *d;
  nova_info *f;
  State *S;
  uint8_t *out;
  int count, failed;
} FrameScan;

static int frame_chunk(uint32_t t, size_t pos, size_t len, void *arg) {
  FrameScan *s = arg;
  nova_info *f = s->f;
  size_t fs = (size_t)f->width * f->height * 4;
  uint8_t *next;
  if (t != T_FDAT && t != T_FDLT) return 0;
  if (s->count >= f->frames) return 0;   /* ANIM said fewer frames: ignore the rest */
  next = s->out + fs * s->count;
  if (t == T_FDAT) {
    size_t i;
    for (i = 3; i < fs; i += 4) next[i] = 255;
    if (!decode_region(s->S, s->d, pos, len, next, f->width, 0, 0, f->width, f->height, f->planes)) { f->error = "corrupt frame"; return 1; }
  } else {
    uint32_t x0, y0, dw, dh;
    if (!s->count) { f->error = "delta frame before full frame"; return 1; }
    if (len < 16) { f->error = "bad FDLT"; return 1; }
    memcpy(next, next - fs, fs);
    x0 = u32(s->d, pos); y0 = u32(s->d, pos + 4); dw = u32(s->d, pos + 8); dh = u32(s->d, pos + 12);
    if (dw > 0 && dh > 0) {
      if (x0 + (uint64_t)dw > (uint32_t)f->width || y0 + (uint64_t)dh > (uint32_t)f->height) { f->error = "bad FDLT region"; return 1; }
      if (!decode_region(s->S, s->d, pos + 16, len - 16, next, f->width, (int)x0, (int)y0, (int)dw, (int)dh, f->planes)) { f->error = "corrupt frame"; return 1; }
    }
  }
  s->count++;
  return 0;
}

uint8_t *nova_decode(const uint8_t *d, size_t n, nova_info *info) {
  FrameScan s;
  size_t fs;
  if (nova_read_info(d, n, info)) return NULL;
  if (info->raw) { info->error = "RAW sensor frame: only its preview can be decoded"; return NULL; }
  fs = (size_t)info->width * info->height * 4;
  memset(&s, 0, sizeof s);
  s.d = d; s.f = info;
  s.S = state_new();
  s.out = s.S ? calloc((size_t)info->frames, fs) : NULL;
  if (!s.out) { state_free(s.S); info->error = "out of memory"; return NULL; }
  {
    nova_info tmp = *info;
    if (walk(d, n, &tmp, frame_chunk, &s)) {
      info->error = tmp.error ? tmp.error : info->error;
      if (s.f->error) info->error = s.f->error;
      free(s.out); state_free(s.S); return NULL;
    }
  }
  state_free(s.S);
  if (s.count < info->frames) { info->error = "truncated file (missing frames)"; free(s.out); return NULL; }
  return s.out;
}

typedef struct { const uint8_t *d; size_t pos, len; } PrevScan;
static int prev_chunk(uint32_t t, size_t pos, size_t len, void *arg) {
  PrevScan *s = arg;
  if (t == T_PREV && len >= 5 && !s->len) { s->pos = pos; s->len = len; }
  return 0;
}

uint8_t *nova_decode_preview(const uint8_t *d, size_t n, int *w, int *h) {
  nova_info f;
  PrevScan s = { d, 0, 0 };
  State *S;
  uint8_t *rgba;
  int pw, ph, np;
  size_t i;
  if (walk(d, n, &f, prev_chunk, &s) || !s.len) return NULL;
  pw = u16(d, s.pos); ph = u16(d, s.pos + 2); np = d[s.pos + 4];
  if (!pw || !ph || (np != 3 && np != 4)) return NULL;
  rgba = calloc((size_t)pw * ph, 4);
  S = state_new();
  if (!rgba || !S) { free(rgba); state_free(S); return NULL; }
  for (i = 3; i < (size_t)pw * ph * 4; i += 4) rgba[i] = 255;
  if (!decode_region(S, d, s.pos + 5, s.len - 5, rgba, pw, 0, 0, pw, ph, np)) { free(rgba); rgba = NULL; }
  state_free(S);
  if (rgba) { *w = pw; *h = ph; }
  return rgba;
}
