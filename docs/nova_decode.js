// NOVA v2 decoder in JavaScript: port of the decoding paths of nova_codec.li, nova_model.li,
// nova_lossy.li, nova_wavelet.li and the container of nova.li. Must give the same pixels as
// `nova decode` bit for bit (test/js.sh). Lisaac Int is int64: every product that can pass 2^31
// is done on doubles (exact below 2^53) with Math.floor (for >>) or Math.trunc (for /).
// ponytail: RAW frames (level 6) are not decoded; the viewer shows their PREV thumbnail.
'use strict';

// ---------------------------------------------------------------------------------------------
// Shared tables (nova_model.li make_tables, nova_codec.li make_qtables)
// ---------------------------------------------------------------------------------------------

const SQUASH_T = [1, 2, 3, 6, 10, 16, 27, 45, 73, 120, 194, 310, 488, 747, 1101, 1546, 2047, 2549, 2994,
  3348, 3607, 3785, 3901, 3975, 4024, 4050, 4068, 4079, 4085, 4089, 4092, 4093, 4094];

function squash(d) {
  if (d > 2047) return 4095;
  if (d < -2047) return 0;
  const w = d & 127, i = (d >> 7) + 16;
  return (SQUASH_T[i] * (128 - w) + SQUASH_T[i + 1] * w + 64) >> 7;
}

const SQ = new Int32Array(4096), STRETCH = new Int32Array(4096), RATE = new Int32Array(1024);
const QL = new Int32Array(4096), QH = new Int32Array(4096);
(function makeTables() {
  for (let j = 0; j < 4096; j++) SQ[j] = squash(j - 2048);
  let pi = 0;
  for (let x = -2047; x <= 2047; x++) {
    const v = squash(x);
    for (let j = pi; j <= v; j++) STRETCH[j] = x;
    if (v + 1 > pi) pi = v + 1;
  }
  for (let j = pi; j <= 4095; j++) STRETCH[j] = 2047;
  for (let n = 0; n < 1024; n++) RATE[n] = Math.trunc(131072 / (2 * n + 3));
  for (let v = 0; v < 4096; v++) {
    let a = v, r = 0;
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
})();

const qlog = v => (v < 4096 ? QL[v] : 7);
const qhalf = v => (v < 4096 ? QH[v] : 15);
const hash = (h, v) => (Math.imul(h, 16777619) ^ v) >>> 0;
const sq = v => (v < 0 ? -qlog(-v) : qlog(v));

// ---------------------------------------------------------------------------------------------
// Model: range decoder + context mixing (nova_model.li, decoding side only)
// ---------------------------------------------------------------------------------------------

const NM = 7, ND = 92160, LR = 6;

class Model {
  constructor() {
    this.t = new Uint32Array(ND);
    this.ctx = new Float64Array(8);     // direct bases or 32-bit hashes
    this.idx = new Int32Array(8);
    this.st = new Int32Array(10);
    this.gb = new Int32Array(8);
    this.weights = new Float64Array(1440);
    this.weights2 = new Float64Array(2880);
    this.weights3 = new Float64Array(2880);
    this.apm = new Int32Array(640 * 33);
    this.mt = new Int32Array(160);
    this.mlb = 0;
  }

  start(data, pos, len, n, lv) {
    this.lite = lv < 2;
    this.ultra = lv >= 4;
    this.inp = data;
    this.inPos = pos;
    this.inEnd = pos + len;
    this.overrun = false;
    this.range = 0xFFFFFFFF;
    this.code = 0;
    for (let i = 0; i < 4; i++) this.code = this.code * 256 + this.nextByte();
    this.reset(n);
  }

  reset(n) {
    this.nact = this.lite ? 2 : NM;
    let hb = 12;
    while (hb < 22 && (1 << hb) < n * 2) hb++;
    if (this.lite) hb = 0;
    this.hbits = hb;
    const size = ND + ((this.nact - 2) << hb);
    if (size > this.t.length) this.t = new Uint32Array(size);
    this.t.fill(32768 << 10, 0, size);
    this.weights.fill(Math.trunc(65536 * 3 / 10));
    this.weights2.fill(Math.trunc(65536 * 3 / 10));
    this.weights3.fill(Math.trunc(65536 * 3 / 10));
    this.mt.fill(32768 << 10);
    for (let i = 0; i < 640 * 33; i++) this.apm[i] = squash(((i % 33) - 16) * 128) * 16;
  }

  nextByte() {
    let r = 0;
    if (this.inPos < this.inEnd) r = this.inp[this.inPos];
    else if (this.inPos >= this.inEnd + 4) this.overrun = true;
    this.inPos++;
    return r;
  }

  codeBit(p) {
    const bound = (this.range >>> 12) * (4096 - p);
    let r = 0;
    if (this.code < bound) this.range = bound;
    else { this.code -= bound; this.range -= bound; r = 1; }
    while (this.range < 0x1000000) {
      this.range *= 256;
      this.code = (this.code * 256 + this.nextByte()) % 4294967296;
    }
    return r;
  }

  setWeights(ws, ws2, ws3, as) { this.wbase = ws; this.wbase2 = ws2; this.wbase3 = ws3; this.abase = as; }

  group(g) {
    const hb = this.hbits;
    for (let k = 2; k < this.nact; k++) {
      let x = (this.ctx[k] + g * 40503) >>> 0;
      x = Math.imul(x, 2146121005) >>> 0;
      this.gb[k] = ND + ((k - 2) << hb) + ((x >>> (36 - hb)) << 4);
    }
  }

  update(i, y, lim) {
    const v = this.t[i];
    let p = v >>> 10, n = v & 1023;
    if (y === 1) p += ((65535 - p) * RATE[n]) >>> 16;
    else p -= (p * RATE[n]) >>> 16;
    if (n < lim) n++;
    this.t[i] = (p << 10) | n;
  }

  bit(nd, off, hv) {
    const t = this.t, idx = this.idx, st = this.st, nact = this.nact;
    const W1 = this.weights, W2 = this.weights2, W3 = this.weights3;
    idx[0] = this.ctx[0] + nd;
    idx[1] = this.ctx[1] + nd;
    for (let k = 2; k < nact; k++) idx[k] = this.gb[k] + off;
    const cls = nd < 16 ? nd : 9;
    const ws = (this.wbase * 10 + cls) * (NM + 2);
    const ws2 = (this.wbase2 * 10 + cls) * (NM + 2);
    const ws3 = (this.wbase3 * 10 + cls) * (NM + 2);
    let dot = 0, dot2 = 0, dot3 = 0, p3 = 0;
    for (let k = 0; k < nact; k++) {
      const s = STRETCH[t[idx[k]] >>> 14];
      st[k] = s;
      dot += W1[ws + k] * s;
      dot2 += W2[ws2 + k] * s;
    }
    const mi = this.mlb * 10 + cls;
    let sm = 0;
    if (hv >= 0) {
      sm = STRETCH[this.mt[mi] >>> 14];
      if (hv === 0) sm = -sm;
    }
    st[NM] = sm;
    dot += W1[ws + NM] * sm;
    dot2 += W2[ws2 + NM] * sm;
    if (this.ultra) {
      for (let k = 0; k < nact; k++) dot3 += W3[ws3 + k] * st[k];
      dot3 += W3[ws3 + NM] * sm;
      dot3 = clamp2047(Math.floor((dot3 + W3[ws3 + NM + 1] * 256) / 65536));
      p3 = SQ[dot3 + 2048];
    }
    dot = clamp2047(Math.floor((dot + W1[ws + NM + 1] * 256) / 65536));
    dot2 = clamp2047(Math.floor((dot2 + W2[ws2 + NM + 1] * 256) / 65536));
    const p1 = SQ[dot + 2048], p2 = SQ[dot2 + 2048];
    let p, a, wt = 0;
    if (this.lite) { p = p1; a = -1; }
    else {
      const pm = this.ultra ? SQ[Math.trunc((dot + dot2 + dot3) / 3) + 2048] : SQ[((dot + dot2) >> 1) + 2048];
      wt = STRETCH[pm] + 2048;
      a = (this.abase + cls) * 33 + (wt >> 7);
      wt &= 127;
      p = (pm + 3 * (((this.apm[a] * (128 - wt) + this.apm[a + 1] * wt) >> 7) >> 4)) >> 2;
    }
    if (p < 1) p = 1;
    if (p > 4095) p = 4095;
    const r = this.codeBit(p);
    if (a >= 0) {
      const j = a + (wt >> 6);
      this.apm[j] += ((r << 16) - r - this.apm[j]) >> 7;
    }
    if (hv >= 0) {
      const v = this.mt[mi];
      let q = v >> 10, n = v & 1023;
      if (r === hv) q += ((65535 - q) * RATE[n]) >>> 16;
      else q -= (q * RATE[n]) >>> 16;
      if (n < 255) n++;
      this.mt[mi] = (q << 10) | n;
    }
    this.update(idx[0], r, 1000);
    this.update(idx[1], r, 1000);
    for (let k = 2; k < nact; k++) this.update(idx[k], r, 60);
    let err = ((r << 12) - p1) * LR;
    for (let k = 0; k < nact; k++) W1[ws + k] += (st[k] * err) >> 14;
    W1[ws + NM] += (sm * err) >> 14;
    W1[ws + NM + 1] += (256 * err) >> 14;
    if (!this.lite) {
      err = ((r << 12) - p2) * LR;
      for (let k = 0; k < nact; k++) W2[ws2 + k] += (st[k] * err) >> 14;
      W2[ws2 + NM] += (sm * err) >> 14;
      W2[ws2 + NM + 1] += (256 * err) >> 14;
    }
    if (this.ultra) {
      err = ((r << 12) - p3) * LR;
      for (let k = 0; k < nact; k++) W3[ws3 + k] += (st[k] * err) >> 14;
      W3[ws3 + NM] += (sm * err) >> 14;
      W3[ws3 + NM + 1] += (256 * err) >> 14;
    }
    return r;
  }
}

function clamp2047(d) { return d < -2047 ? -2047 : d > 2047 ? 2047 : d; }

// ---------------------------------------------------------------------------------------------
// Levels 0-4 (nova_codec.li)
// ---------------------------------------------------------------------------------------------

const NONE = 100000;
const TDX = new Int32Array(35), TDY = new Int32Array(35);
(function makeTaps() {
  const tap = (k, dx, dy) => { TDX[k] = dx; TDY[k] = dy; };
  tap(0, -2, 0);
  for (let i = 0; i <= 4; i++) { tap(1 + i, i - 2, -1); tap(6 + i, i - 2, -2); }
  tap(11, -3, 0); tap(12, -2, 0); tap(13, -1, 0);
  let k = 14;
  for (let r = 1; r <= 3; r++) for (let i = 0; i <= 6; i++) tap(k++, i - 3, -r);
})();

class Codec {
  constructor(model) {
    this.m = model;
    this.sp = new Float64Array(6);
    this.lw = new Float64Array(192);
    this.ld = new Float64Array(48);
    this.nlOn = new Int32Array(2);
    this.ccn = new Float64Array(4);
    this.ccd = new Float64Array(4);
    this.cur = new Int32Array(4);
    this.mtab = new Int32Array(4);
    this.pmode = false;
  }

  // Region (ox, oy, w, h) of px (RGBA, width stride).
  setRegion(px, stride, ox, oy, w, h) { this.px = px; this.stride = stride; this.ox = ox; this.oy = oy; this.w = w; this.h = h; }

  sample(p, x, y) {
    if (this.pmode) return this.ibuf[y * this.w + x];
    const i = ((this.oy + y) * this.stride + this.ox + x) * 4, px = this.px, g = px[i + 1];
    if (p === 0) return g;
    if (p === 1) return px[i] - g + 255;
    if (p === 2) return px[i + 2] - g + 255;
    return px[i + 3];
  }

  store(v, p, x, y) {
    if (this.pmode) { this.ibuf[y * this.w + x] = v; return; }
    const i = ((this.oy + y) * this.stride + this.ox + x) * 4, px = this.px;
    if (p === 0) px[i + 1] = v;
    else if (p === 1) px[i] = (v - 255 + px[i + 1]) & 255;
    else if (p === 2) px[i + 2] = (v - 255 + px[i + 1]) & 255;
    else px[i + 3] = v;
  }

  nb(p, x, y) { return this.rbuf[(((y & 3) * this.w) + x) * 4 + p]; }

  errAt(p, x, y) { return this.ebuf[(((y & 1) * this.w) + x) * 4 + p]; }

  perr(p, k, x, y) { return this.pbuf[((((y & 1) * this.w) + x) * 4 + p) * 6 + k]; }

  neighbours(p, x, y) {
    const w = this.w;
    let ra, rb, rc, rd;
    if (y === 0) {
      ra = x > 0 ? this.nb(p, x - 1, 0) : 0;
      rb = rc = rd = ra;
    } else {
      rb = this.nb(p, x, y - 1);
      if (x > 0) { ra = this.nb(p, x - 1, y); rc = this.nb(p, x - 1, y - 1); } else { ra = rc = rb; }
      rd = x < w - 1 ? this.nb(p, x + 1, y - 1) : rb;
    }
    this.ra = ra; this.rb = rb; this.rc = rc; this.rd = rd;
    this.raa = x > 1 ? this.nb(p, x - 2, y) : ra;
    this.rbb = y > 1 ? this.nb(p, x, y - 2) : rb;
  }

  predict() {
    const ra = this.ra, rb = this.rb, rc = this.rc;
    let mx = ra, mn = rb;
    if (rb > ra) { mx = rb; mn = ra; }
    if (rc >= mx) return mn;
    if (rc <= mn) return mx;
    return ra + rb - rc;
  }

  nlms(j, p, x, y) {
    const m = 2 + j, n = 11 + j * 13, f = j * 11;
    this.nlOn[j] = 0;
    if (y >= m && x >= m && x < this.w - m) {
      this.nlOn[j] = 1;
      const wv = this.nb(p, x - 1, y);
      let dot = 0;
      for (let k = 0; k < n; k++) {
        const d = this.nb(p, x + TDX[f + k], y + TDY[f + k]) - wv;
        this.ld[j * 24 + k] = d;
        dot += this.lw[(j * 4 + p) * 24 + k] * d;
      }
      return wv + Math.floor(dot / 65536);
    }
    return this.sp[0];
  }

  nlmsUpdate(j, p, v) {
    if (this.nlOn[j] !== 1) return;
    const n = 11 + j * 13;
    let en = 16;
    for (let k = 0; k < n; k++) en += this.ld[j * 24 + k] * this.ld[j * 24 + k];
    const f = Math.trunc(((v - this.sp[4 + j]) * 2097 * 1024) / en);
    for (let k = 0; k < n; k++) this.lw[(j * 4 + p) * 24 + k] += Math.floor((f * this.ld[j * 24 + k]) / 1024);
  }

  blend(p, x, y) {
    const sp = this.sp, w = this.w;
    sp[0] = this.predict();
    sp[1] = (this.ra + this.rb + 1) >> 1;
    sp[2] = this.ra + this.rb - this.rc;
    sp[3] = (this.ra + this.rd + 1) >> 1;
    sp[4] = this.nlms(0, p, x, y);
    if (this.npred === 6) sp[5] = this.nlms(1, p, x, y);
    let sw = 0, sum = 0;
    for (let k = 0; k < this.npred; k++) {
      let s = 0;
      if (x > 0) s += this.perr(p, k, x - 1, y);
      if (y > 0) {
        s += this.perr(p, k, x, y - 1);
        if (x > 0) s += this.perr(p, k, x - 1, y - 1);
        if (x < w - 1) s += this.perr(p, k, x + 1, y - 1);
      }
      const wk = Math.floor(1073741824 / (8 + s));
      sw += wk;
      sum += wk * sp[k];
    }
    return Math.trunc((sum + Math.floor(sw / 2)) / sw);
  }

  cross(p) {
    let c = Math.trunc((this.ccn[p] * 64) / (this.ccd[p] + 64));
    if (c < -128) c = -128;
    if (c > 128) c = 128;
    return c;
  }

  setContexts(p, x, y, pr) {
    const m = this.m, w = this.w;
    const g = Math.abs(this.rd - this.rb) + Math.abs(this.rb - this.rc) + Math.abs(this.rc - this.ra);
    let act = qlog(g);
    if (g >= 128) act = 8 + qlog(g >> 7);
    let sew = 0, sen = 0, ene = 0, enw = 0;
    if (x > 0) sew = this.errAt(p, x - 1, y);
    if (y > 0) {
      sen = this.errAt(p, x, y - 1);
      ene = enw = Math.abs(sen);
      if (x < w - 1) ene = Math.abs(this.errAt(p, x + 1, y - 1));
      if (x > 0) enw = Math.abs(this.errAt(p, x - 1, y - 1));
    }
    const ew = Math.abs(sew), en = Math.abs(sen);
    const q1 = qlog(ew + en);
    const q2 = p === 0 ? qlog(ene + enw) : qlog(Math.abs(this.errAt(0, x, y)));
    m.ctx[0] = (p * 16 + act) * 80;
    m.ctx[1] = 5120 + ((p * 16 + qhalf(2 * (ew + en) + ene + enw)) * 8 + q2) * 80;
    m.setWeights(p * 4 + (act >> 2), p * 8 + q1, p * 8 + q2, (p * 16 + act) * 10);
    if (this.level >= 2) {
      const ra = this.ra, rb = this.rb, rc = this.rc, rd = this.rd, cur = this.cur;
      let h3 = hash(p + 1, ra);
      h3 = hash(h3, rb); h3 = hash(h3, rc); h3 = hash(h3, rd); h3 = hash(h3, pr);
      let h4 = hash(p + 11, h3);
      h4 = hash(h4, this.raa); h4 = hash(h4, this.rbb);
      let h5 = hash(p + 21, ra);
      h5 = hash(h5, rb);
      for (let i = 0; i < p; i++) { h4 = hash(h4, cur[i]); h5 = hash(h5, cur[i]); }
      h5 = hash(h5, pr);
      if (p === 0) h5 = hash(h5, act * 8 + q1);
      let h6 = hash(p + 31, sq(ra - pr));
      h6 = hash(h6, sq(rb - pr)); h6 = hash(h6, sq(rc - pr)); h6 = hash(h6, sq(rd - pr));
      let h7 = hash(p + 41, sq(sew));
      h7 = hash(h7, sq(sen));
      h7 = p === 0 ? hash(h7, q2) : hash(h7, sq(this.errAt(0, x, y)));
      m.ctx[2] = h3; m.ctx[3] = h4; m.ctx[4] = h5; m.ctx[5] = h6; m.ctx[6] = h7;
    }
  }

  // Decodes one residual; er: residual the match predicts (NONE: no match).
  codeResidual(er) {
    const m = this.m;
    const ea = Math.abs(er);
    let en = 0;
    while ((ea >> (en + 1)) > 0) en++;
    let hv = er !== NONE ? (er !== 0 ? 1 : 0) : -1;
    m.group(0);
    let b = m.bit(0, 0, hv);
    if (b !== hv) hv = -1;
    if (b !== 1) return 0;
    if (hv >= 0) hv = er < 0 ? 1 : 0;
    const s = m.bit(1, 1, hv);
    if (s !== hv) hv = -1;
    let n = 0;
    for (;;) {
      if (n >= 7) break;
      if (hv >= 0) hv = n < en ? 1 : 0;
      b = m.bit(2 + n, 2 + n + 7 * s, hv);
      if (b !== hv) hv = -1;
      if (b !== 1) break;
      n++;
    }
    if (n > 0) m.group(1 + s * 8 + n);
    let prefix = 1, off = 1;
    for (let i = n - 1; i >= 0; i--) {
      if (off >= 16) { m.group(256 + (s * 8 + n) * 32 + prefix); off = 1; }
      if (hv >= 0) hv = (ea >> i) & 1;
      b = m.bit(16 + 8 * n + i, off, hv);
      if (b !== hv) hv = -1;
      prefix = (prefix << 1) | b;
      off = (off << 1) | b;
    }
    return s === 1 ? -prefix : prefix;
  }

  matchReset() {
    let mb = 12;
    while (mb < 22 && (1 << mb) < this.w * this.h * 2) mb++;
    this.mbits = mb;
    const n = 1 << mb;
    if (n > this.mtab.length) this.mtab = new Int32Array(n);
    this.mtab.fill(0, 0, n);
    this.mpos = -1;
    this.mlen = 0;
    this.mok = false;
  }

  matchStep(np, x, y) {
    if (this.mpos >= 0 && this.mok) {
      this.mpos++;
      if (this.mlen < 65535) this.mlen++;
    } else { this.mpos = -1; this.mlen = 0; }
    if (x >= 2 && y >= 2 && x < this.w - 1) {
      let hh = 0;
      for (let p = 0; p < np; p++) {
        hh = hash(hh, this.nb(p, x - 1, y));
        hh = hash(hh, this.nb(p, x - 2, y));
        hh = hash(hh, this.nb(p, x - 1, y - 1));
        hh = hash(hh, this.nb(p, x, y - 1));
        hh = hash(hh, this.nb(p, x + 1, y - 1));
        hh = hash(hh, this.nb(p, x, y - 2));
      }
      hh = (Math.imul(hh, 2146121005) >>> 0) >>> (32 - this.mbits);
      if (this.mpos < 0) {
        const c = this.mtab[hh] - 1;
        if (c >= 0) this.mpos = c;
      }
      this.mtab[hh] = y * this.w + x + 1;
    }
    this.mok = this.mpos >= 0;
    this.m.mlb = qhalf(this.mlen);
  }

  expected(p, pr, q) {
    if (this.mpos < 0) return NONE;
    const ev = this.sample(p, this.mpos % this.w, Math.trunc(this.mpos / this.w));
    let r;
    if (q === 1) {
      r = (ev - pr) & 255;
      if (r > 127) r -= 256;
    } else {
      r = Math.trunc((Math.abs(ev - pr) + this.eps) / q);
      if (ev < pr) r = -r;
    }
    return r;
  }

  codeRegion(np) {
    const w = this.w, h = this.h, m = this.m;
    if (!this.ebuf || w * 8 > this.ebuf.length) {
      this.ebuf = new Int32Array(w * 8);
      this.pbuf = new Float64Array(w * 48);
      this.rbuf = new Int32Array(w * 16);
    }
    this.ebuf.fill(0, 0, w * 8);
    this.pbuf.fill(0, 0, w * 48);
    this.lw.fill(0);
    this.npred = this.level >= 4 ? 6 : 5;
    this.ccn.fill(0);
    this.ccd.fill(0);
    this.matchReset();
    const cur = this.cur, sp = this.sp, level = this.level, eps = this.eps;
    for (let y = 0; y < h; y++) {
      if (this.onRow) this.onRow(y);
      for (let x = 0; x < w; x++) {
        this.matchStep(np, x, y);
        for (let p = 0; p < np; p++) {
          const lo = (p === 1 || p === 2) ? 255 - cur[0] : 0;
          this.neighbours(p, x, y);
          const base = level < 3 ? this.predict() : this.blend(p, x, y);
          let pr = base, eg = 0;
          if (level >= 3 && lo !== 0) {
            eg = this.errAt(0, x, y);
            pr += (this.cross(p) * eg) >> 6;
          }
          if (pr < lo) pr = lo;
          if (pr > lo + 255) pr = lo + 255;
          this.setContexts(p, x, y, pr);
          const q = p < 3 ? 2 * eps + 1 : 1;
          const er = this.expected(p, pr, q);
          const e = this.codeResidual(er);
          let v;
          if (q === 1) v = lo + ((pr - lo + e + 256) & 255);
          else {
            v = pr + e * q;
            if (v < lo) v = lo;
            if (v > lo + 255) v = lo + 255;
          }
          this.store(v, p, x, y);
          if (er === NONE || e !== er) this.mok = false;
          cur[p] = v;
          this.rbuf[(((y & 3) * w) + x) * 4 + p] = v;
          const i = (((y & 1) * w) + x) * 4 + p;
          this.ebuf[i] = e;
          if (level >= 3) {
            for (let k = 0; k < this.npred; k++) this.pbuf[i * 6 + k] = Math.abs(v - sp[k]);
            this.nlmsUpdate(0, p, v);
            if (this.npred === 6) this.nlmsUpdate(1, p, v);
          }
          if (level >= 3 && lo !== 0) {
            const raw = v - base;
            this.ccn[p] = this.ccn[p] - Math.floor(this.ccn[p] / 1024) + eg * raw;
            this.ccd[p] = this.ccd[p] - Math.floor(this.ccd[p] / 1024) + eg * eg;
          }
        }
      }
    }
  }

  decodePalette(data, pos, len, np) {
    const n = data[pos] + 1, k = pos + 1 + n * np;
    if (k > pos + len) return false;
    const pal = new Uint8Array(n * 4);
    for (let j = 0; j < n; j++) {
      const i = pos + 1 + j * np;
      pal[j * 4] = data[i]; pal[j * 4 + 1] = data[i + 1]; pal[j * 4 + 2] = data[i + 2];
      pal[j * 4 + 3] = np === 4 ? data[i + 3] : 255;
    }
    const w = this.w, h = this.h;
    this.ibuf = new Int32Array(w * h);
    this.pmode = true;
    this.level = 2;
    this.eps = 0;
    this.m.start(data, k, pos + len - k, w * h, 2);
    this.codeRegion(1);
    this.pmode = false;
    // ponytail: np 1 (alpha region) at level 0 writes the palette's first byte to G, as the C does.
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let c = this.ibuf[y * w + x];
        if (c >= n) c = n - 1;
        const i = ((this.oy + y) * this.stride + this.ox + x) * 4;
        this.px[i] = pal[c * 4]; this.px[i + 1] = pal[c * 4 + 1]; this.px[i + 2] = pal[c * 4 + 2]; this.px[i + 3] = pal[c * 4 + 3];
      }
    }
    return !this.m.overrun;
  }
}

function u32(d, p) { return ((d[p] << 24) >>> 0) + (d[p + 1] << 16) + (d[p + 2] << 8) + d[p + 3]; }
function u16(d, p) { return (d[p] << 8) | d[p + 1]; }

// Stripe table of a levels 1-4 block d[pos, pos + len): [{off, len, y0, rows}] or null.
function stripeTable(d, pos, len, fh) {
  if (len < 1) return null;
  const ns = d[pos];
  if (ns < 1 || ns > 16 || ns > fh) return null;
  const rows = Math.trunc((fh + ns - 1) / ns), out = [];
  let p = pos + 1;
  for (let i = 0; i < ns; i++) {
    if (p + 4 > pos + len || i * rows >= fh) return null;
    const n = u32(d, p);
    if (p + 4 + n > pos + len) return null;
    out.push({ off: p + 4, len: n, y0: i * rows, rows: Math.min(rows, fh - i * rows) });
    p += 4 + n;
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Level 5 (nova_lossy.li + nova_wavelet.li)
// ---------------------------------------------------------------------------------------------

const POW_T = [1000, 1051, 1104, 1160, 1219, 1281, 1346, 1414, 1486, 1561, 1641, 1724, 1811, 1903];
const RECON = 26, CHROMA1 = 512, CHROMA2 = 420;

function waveletLevels(w, h) {
  let l = 0;
  while (l < 6 && ((w + (1 << l) - 1) >> l) >= 16 && ((h + (1 << l) - 1) >> l) >= 16) l++;
  return l;
}

function lift(c, base, step, n, k, par, sg) {
  for (let j = par; j < n; j += 2) {
    let l = j - 1; if (l < 0) l = 1;
    let r = j + 1; if (r >= n) r = n - 2;
    const i = base + j * step;
    c[i] = c[i] + sg * Math.floor((k * (c[base + l * step] + c[base + r * step]) + 2048) / 4096);
  }
}

function liftCols(c, w, nw, st, n, k, par, sg) {
  const rs = st * w;
  for (let j = par; j < n; j += 2) {
    let l = j - 1; if (l < 0) l = 1;
    let r = j + 1; if (r >= n) r = n - 2;
    const a = l * rs, b = r * rs, d = j * rs;
    for (let i = 0; i < nw; i++) {
      const o = i * st;
      c[d + o] = c[d + o] + sg * Math.floor((k * (c[a + o] + c[b + o]) + 2048) / 4096);
    }
  }
}

function waveletInverse(c, w, h, levels) {
  for (let k = levels - 1; k >= 0; k--) {
    const st = 1 << k, nw = (w + st - 1) >> k, nh = (h + st - 1) >> k;
    if (nh >= 2) {
      liftCols(c, w, nw, st, nh, 1817, 0, -1);
      liftCols(c, w, nw, st, nh, 3616, 1, -1);
      liftCols(c, w, nw, st, nh, -217, 0, -1);
      liftCols(c, w, nw, st, nh, -6497, 1, -1);
    }
    if (nw >= 2) {
      for (let i = 0; i < nh; i++) {
        const base = i * st * w;
        lift(c, base, st, nw, 1817, 0, -1);
        lift(c, base, st, nw, 3616, 1, -1);
        lift(c, base, st, nw, -217, 0, -1);
        lift(c, base, st, nw, -6497, 1, -1);
      }
    }
  }
}

// Band (k, o): o = 0 low-low (k = levels), 1 HL, 2 LH, 3 HH.
function band(k, o) {
  const bs = o === 0 ? 1 << k : 2 << k;
  return { k, o, bs, bx: (o === 1 || o === 3) ? 1 << k : 0, by: (o === 2 || o === 3) ? 1 << k : 0 };
}

function lossyStep(q, p, b) {
  const e = 108 - q;
  let d = (Math.trunc((512 * 256 * POW_T[e % 14]) / 1000) << Math.trunc(e / 14)) >> 2;
  if (p === 1) d = Math.trunc((d * CHROMA1) / 256);
  if (p === 2) d = Math.trunc((d * CHROMA2) / 256);
  const n = b.o === 3 ? b.k - 1 : b.k;
  for (let i = 1; i <= n; i++) d = Math.trunc((d * 4096) / 5413);
  return d < 16 ? 16 : d;
}

class Lossy {
  constructor(model) { this.m = model; this.zb = new Uint8Array(4); }

  // Planes: 3 Int32Array holding the rows [ytop, ybot) of the stripe (index y * w + x - off).
  setup(w, h) { this.w = w; this.h = h; this.levels = waveletLevels(w, h); }

  setBand(b) { this.bk = b.k; this.bo = b.o; this.bs = b.bs; this.bx = b.bx; this.by = b.by; }

  aq(p, x, y) { return (x >= 0 && y >= this.ytop && x < this.w && y < this.ybot) ? Math.abs(this.pl[p][y * this.w + x - this.off]) : 0; }

  sv(p, x, y) { return (x >= 0 && y >= this.ytop && x < this.w && y < this.ybot) ? this.pl[p][y * this.w + x - this.off] : 0; }

  setContexts(p, x, y) {
    const m = this.m, bs = this.bs, bk = this.bk, bo = this.bo, bx = this.bx, by = this.by;
    const cw = this.aq(p, x - bs, y), cn = this.aq(p, x, y - bs), cnw = this.aq(p, x - bs, y - bs);
    const cne = this.aq(p, x + bs, y - bs), cww = this.aq(p, x - 2 * bs, y), cnn = this.aq(p, x, y - 2 * bs);
    let par = 0;
    if (bo > 0 && bk + 1 < this.levels) {
      par = this.aq(p, bx * 2 + Math.trunc(Math.trunc((x - bx) / bs) / 2) * bs * 2, by * 2 + Math.trunc(Math.trunc((y - by) / bs) / 2) * bs * 2);
    }
    let cous = 0;
    if (bo === 2) cous = this.aq(p, x + (1 << bk), y - (1 << bk));
    if (bo === 3) cous = this.aq(p, x, y - (1 << bk)) + this.aq(p, x - (1 << bk), y);
    let lum = 0;
    if (p > 0) lum = this.aq(0, x, y);
    if (p === 2) lum += this.aq(1, x, y);
    const clip = (v, mx) => (v > mx ? mx : v);
    const sclip = (v, mx) => (v > mx ? mx : v < -mx ? -mx : v);
    const a = qhalf(clip(2 * (cw + cn) + cnw + cne + par, 4095));
    const bc = bo > 0 ? 1 + clip(bk, 4) * 3 + bo - 1 : 0;
    const q1 = qlog(clip(cw + cn, 4095));
    const q2 = p === 0 ? qlog(clip(2 * par + cous, 4095)) : qlog(clip(2 * lum + cous, 4095));
    m.ctx[0] = (((p * 16 + bc) * 12) + clip(a, 11)) * 80;
    m.ctx[1] = 46080 + ((p * 16 + bc) * 8 + q2) * 80;
    m.setWeights(p * 4 + (a >> 2), p * 8 + (bc >> 1), p * 8 + q2, (p * 16 + a) * 10);
    let hh = hash(p + 1, bc);
    hh = hash(hh, sclip(this.sv(p, x - bs, y), 15));
    hh = hash(hh, sclip(this.sv(p, x, y - bs), 15));
    hh = hash(hh, clip(cnw, 7));
    hh = hash(hh, clip(cne, 7));
    m.ctx[2] = hh;
    hh = hash(p + 11, bc);
    hh = hash(hh, a);
    hh = hash(hh, clip(par, 15));
    hh = hash(hh, clip(cous, 15));
    m.ctx[3] = hh;
    hh = hash(p + 21, bc);
    hh = hash(hh, a >> 1);
    if (p > 0) hh = hash(hh, sclip(this.sv(0, x, y), 15));
    if (p === 2) hh = hash(hh, sclip(this.sv(1, x, y), 15));
    m.ctx[4] = hh;
    hh = hash(p + 31, bc);
    hh = hash(hh, qlog(clip(cw, 4095)));
    hh = hash(hh, qlog(clip(cn, 4095)));
    hh = hash(hh, qlog(clip(cnw, 4095)));
    hh = hash(hh, qlog(clip(cne, 4095)));
    hh = hash(hh, qlog(clip(cww, 4095)));
    hh = hash(hh, qlog(clip(cnn, 4095)));
    hh = hash(hh, qlog(clip(par, 4095)));
    m.ctx[5] = hh;
    hh = hash(p + 41, bc);
    hh = hash(hh, q2);
    hh = hash(hh, q1);
    hh = hash(hh, qlog(clip(lum, 4095)));
    m.ctx[6] = hh;
  }

  codeCoef() {
    const m = this.m;
    m.group(0);
    if (m.bit(0, 0, -1) !== 1) return 0;
    const s = m.bit(1, 1, -1);
    let n = 0;
    for (;;) {
      if (n >= 20) break;
      if (n === 14) m.group(1);
      const sl = n >= 14 ? n - 14 : 2 + n;
      if (m.bit(2 + n, sl, -1) !== 1) break;
      n++;
    }
    if (n > 0) m.group(2 + n);
    let v = 1, off = 1;
    for (let i = n - 1; i >= 0; i--) {
      let b;
      if (n - 1 - i < 3) {
        b = m.bit(22 + (n > 18 ? 18 : n) * 3 + (n - 1 - i), off, -1);
        off = (off << 1) | b;
      } else b = m.codeBit(2048);
      v = v * 2 + b;
    }
    return s === 1 ? -v : v;
  }

  codeFlags(y) {
    const m = this.m, bs = this.bs, bo = this.bo, bx = this.bx, by = this.by, w = this.w;
    const clip = (v, mx) => (v > mx ? mx : v);
    let lf = 1, i = 0;
    for (let x = bx; x < w; x += 2 * bs) {
      let n = 0, par = 0, cous = 0;
      for (let p = 0; p < 3; p++) {
        n += this.aq(p, x - bs, y - bs) + this.aq(p, x, y - bs) + this.aq(p, x + bs, y - bs) + this.aq(p, x + 2 * bs, y - bs);
        if (this.levels > 1) {
          par += this.aq(p, bx * 2 + Math.trunc(Math.trunc((x - bx) / bs) / 2) * bs * 2, by * 2 + Math.trunc(Math.trunc((y - by) / bs) / 2) * bs * 2);
        }
        for (let j = 0; j <= 1; j++) {
          for (let k = 0; k <= 1; k++) {
            if (bo === 2) cous += this.aq(p, x + k * bs + 1, y + j * bs - 1);
            if (bo === 3) cous += this.aq(p, x + k * bs, y + j * bs - 1) + this.aq(p, x + k * bs - 1, y + j * bs);
          }
        }
      }
      const up = this.zb[i];
      const a = clip(qhalf(clip(2 * n + 3 * par + cous, 4095)), 11);
      const q = qlog(clip(par, 4095));
      m.ctx[0] = (bo * 12 + a) * 80;
      m.ctx[1] = 46080 + ((lf * 16 + bo) * 8 + q) * 80;
      m.setWeights(12 + (a >> 2), 24 + lf * 2 + up, 24 + q, (48 + a) * 10);
      let hh = hash(51, bo);
      hh = hash(hh, a);
      m.ctx[2] = hash(hh, lf);
      hh = hash(52, bo);
      hh = hash(hh, clip(par, 15));
      m.ctx[3] = hash(hh, clip(cous, 15));
      hh = hash(53, bo);
      hh = hash(hh, qlog(clip(n, 4095)));
      hh = hash(hh, q);
      m.ctx[4] = hash(hh, lf);
      hh = hash(54, bo);
      hh = hash(hh, clip(n, 15));
      m.ctx[5] = hash(hh, up);
      hh = hash(55, bo);
      hh = hash(hh, qlog(clip(cous, 4095)));
      hh = hash(hh, up);
      m.ctx[6] = hash(hh, lf);
      m.group(40);
      const z = m.bit(79, 0, -1);
      this.zb[i] = z;
      lf = z;
      i++;
    }
  }

  codeBand() {
    const fine = this.bo > 0 && this.bk === 0, bs = this.bs, bx = this.bx, w = this.w, pl = this.pl;
    if (fine) {
      if (this.zb.length < w) this.zb = new Uint8Array(w);
      this.zb.fill(1);
    }
    for (let y = this.ytop + this.by; y < this.ybot; y += bs) {
      if (fine && Math.trunc((y - this.ytop - this.by) / bs) % 2 === 0) this.codeFlags(y);
      for (let x = bx; x < w; x += bs) {
        if (fine && this.zb[Math.trunc((x - bx) / (2 * bs))] === 1) {
          const i = y * w + x - this.off;
          pl[0][i] = 0; pl[1][i] = 0; pl[2][i] = 0;
        } else this.codePosition(x, y);
      }
    }
  }

  codePosition(x, y) {
    const bs = this.bs, w = this.w;
    for (let p = 0; p < 3; p++) {
      this.setContexts(p, x, y);
      if (this.bo === 0) {
        let a = this.sv(p, x - bs, y), b = this.sv(p, x, y - bs), c = this.sv(p, x - bs, y - bs);
        if (x === 0) a = b;
        if (y === this.ytop) { b = a; c = a; }
        if (x === 0) c = b;
        let mx = a, mn = b;
        if (b > a) { mx = b; mn = a; }
        const pr = c >= mx ? mn : c <= mn ? mx : a + b - c;
        this.pl[p][y * w + x - this.off] = pr + this.codeCoef();
      } else this.pl[p][y * w + x - this.off] = this.codeCoef();
    }
  }

  // Decodes the coefficients of stripe s (of ns) from d[off, off + len) into new planes.
  decodeStripe(d, off, len, s, ns) {
    const [a, b] = lossyRows(this.w, this.h, s, ns), n3 = this.w * (b - a);
    this.ytop = a;
    this.ybot = b;
    this.off = a * this.w;
    this.pl = [new Int32Array(n3), new Int32Array(n3), new Int32Array(n3)];
    this.m.start(d, off, len, Math.trunc((this.w * (this.ybot - this.ytop) * 3) / 16), 3);
    this.m.mlb = 0;
    this.setBand(band(this.levels, 0));
    this.codeBand();
    for (let k = this.levels - 1; k >= 0; k--) {
      for (let o = 1; o <= 3; o++) { this.setBand(band(k, o)); this.codeBand(); }
    }
    return !this.m.overrun;
  }
}

// Rows [ytop, ybot) of stripe s of ns (multiples of 2^levels).
function lossyRows(w, h, s, ns) {
  const u = 1 << waveletLevels(w, h), n = Math.trunc((h + u - 1) / u), per = Math.trunc((n + ns - 1) / ns);
  return [Math.min(s * per * u, h), Math.min((s + 1) * per * u, h)];
}

// Dequantizes plane p and inverts its wavelet, in place (one job per plane: they run in parallel).
function lossyPlane(a, w, h, q, p) {
  const levels = waveletLevels(w, h);
  const bands = [band(levels, 0)];
  for (let k = levels - 1; k >= 0; k--) for (let o = 1; o <= 3; o++) bands.push(band(k, o));
  for (const b of bands) {
    const st = lossyStep(q, p, b), rc = (RECON * st) >> 8;
    for (let y = b.by; y < h; y += b.bs) {
      for (let x = b.bx; x < w; x += b.bs) {
        const i = y * w + x, v = a[i];
        if (v !== 0) {
          const c = Math.floor((Math.abs(v) * st + rc + 128) / 256);
          a[i] = v < 0 ? -c : c;
        }
      }
    }
  }
  waveletInverse(a, w, h, levels);
}

// Writes the YCoCg planes (after lossyPlane) as RGB into buf (region x0, y0, w, h of stride s).
function lossyFinish(planes, w, h, buf, s, x0, y0) {
  const px = v => { v = (v + 32) >> 6; return v < 0 ? 0 : v > 255 ? 255 : v; };
  const P0 = planes[0], P1 = planes[1], P2 = planes[2];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = ((y0 + y) * s + x0 + x) * 4, j = y * w + x;
      const yy = P0[j] + 8192, co = P1[j], cg = P2[j];
      buf[i] = px(yy + co - cg);
      buf[i + 1] = px(yy + cg);
      buf[i + 2] = px(yy - co - cg);
    }
  }
}

// Stripe table of a level-5 block: [{off, len}] or null.
function lossyTable(d, pos, len, w, h) {
  if (len < 1) return null;
  const ns = d[pos];
  if (ns < 1 || ns > 16) return null;
  const out = [];
  let p = pos + 1;
  for (let i = 0; i < ns; i++) {
    if (p + 4 > pos + len) return null;
    const n = u32(d, p);
    if (p + 4 + n > pos + len) return null;
    out.push({ off: p + 4, len: n });
    p += 4 + n;
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Region decoder (nova_codec.li decode). Runs the stripes through `run` (sequential by default;
// the viewer passes one that fans them out to Web Workers).
// ---------------------------------------------------------------------------------------------

// Jobs: {kind: 'l14', data, off, len, fw, rows, np, level, eps, img (RGBA of the stripe)} or
// {kind: 'l5', data, off, len, w, h, s, ns} -> 3 Int32Array planes of the stripe rows, or
// {kind: 'l5p', plane, w, h, q, p} -> the plane dequantized and back from the wavelet.
let worker = null;
function jobState() {
  if (!worker) { const m = new Model(); worker = { m, codec: new Codec(m), lossy: new Lossy(m) }; }
  return worker;
}

function runJob(j) {
  const st = jobState();
  if (j.kind === 'l14') {
    const c = st.codec;
    c.setRegion(j.img, j.fw, 0, 0, j.fw, j.rows);
    c.level = j.level;
    c.eps = j.eps;
    c.onRow = j.onRow || null;
    st.m.start(j.data, j.off, j.len, j.fw * j.rows * j.np, j.level);
    c.codeRegion(j.np);
    return { ok: !st.m.overrun, img: j.img };
  }
  if (j.kind === 'l5p') {
    lossyPlane(j.plane, j.w, j.h, j.q, j.p);
    return { ok: true, plane: j.plane };
  }
  const L = st.lossy;
  L.setup(j.w, j.h);
  const ok = L.decodeStripe(j.data, j.off, j.len, j.s, j.ns);
  return { ok, planes: L.pl };
}

async function runSequential(jobs) { return jobs.map(runJob); }

async function decodeRegion(data, pos, len, buf, s, x0, y0, fw, fh, np, run, info) {
  run = run || runSequential;
  const lv = len >= 1 ? data[pos] : -1, q = len >= 2 ? data[pos + 1] : -1;
  if (len >= 3 && lv === 0) {
    const st = jobState();
    st.codec.setRegion(buf, s, x0, y0, fw, fh);
    return st.codec.decodePalette(data, pos + 2, len - 2, np);
  }
  if (lv === 5 && q <= 100 && (np === 3 ? len >= 2 : len >= 6)) {
    if (info) info.lossy = true;
    let p = pos + 2, n = len - 2;
    if (np === 4) {
      n = u32(data, pos + 2);
      if (n > len - 8 || data[pos + 6 + n] < 1 || data[pos + 6 + n] > 4) return false;
      p = pos + 6;
    }
    const tab = lossyTable(data, p, n, fw, fh);
    if (!tab) return false;
    const planes = [new Int32Array(fw * fh), new Int32Array(fw * fh), new Int32Array(fw * fh)];
    const res = await run(tab.map((t, s) => ({ kind: 'l5', data, off: t.off, len: t.len, w: fw, h: fh, s, ns: tab.length })));
    let ok = true;
    res.forEach((r, i) => {
      ok = ok && r.ok;
      const a = lossyRows(fw, fh, i, tab.length)[0] * fw;
      for (let c = 0; c < 3; c++) planes[c].set(r.planes[c], a);
    });
    const fin = await run(planes.map((a, p) => ({ kind: 'l5p', plane: a, w: fw, h: fh, q, p })));
    lossyFinish(fin.map(r => r.plane), fw, fh, buf, s, x0, y0);
    if (np === 4 && ok) {
      const a = new Uint8Array(fw * fh * 4);
      for (let y = 0; y < fh; y++) for (let x = 0; x < fw; x++) a[(y * fw + x) * 4 + 1] = buf[((y0 + y) * s + x0 + x) * 4 + 3];
      ok = await decodeRegion(data, pos + 6 + n, len - 6 - n, a, fw, 0, 0, fw, fh, 1, run, info);
      for (let y = 0; y < fh; y++) for (let x = 0; x < fw; x++) buf[((y0 + y) * s + x0 + x) * 4 + 3] = a[(y * fw + x) * 4 + 1];
    }
    return ok;
  }
  if (len >= 2 && lv >= 1 && lv <= 4 && q <= 64) {
    if (q > 0 && info) info.lossy = true;
    const tab = stripeTable(data, pos + 2, len - 2, fh);
    if (!tab) return false;
    const jobs = tab.map(t => {
      const img = new Uint8Array(fw * t.rows * 4);
      for (let y = 0; y < t.rows; y++) img.set(buf.subarray(((y0 + t.y0 + y) * s + x0) * 4, ((y0 + t.y0 + y) * s + x0 + fw) * 4), y * fw * 4);
      return { kind: 'l14', data, off: t.off, len: t.len, fw, rows: t.rows, np, level: lv, eps: q, img };
    });
    const res = await run(jobs);
    let ok = true;
    res.forEach((r, i) => {
      ok = ok && r.ok;
      const t = tab[i];
      for (let y = 0; y < t.rows; y++) buf.set(r.img.subarray(y * fw * 4, (y + 1) * fw * 4), ((y0 + t.y0 + y) * s + x0) * 4);
    });
    return ok;
  }
  return false;
}

// ---------------------------------------------------------------------------------------------
// Container (nova.li read_nova)
// ---------------------------------------------------------------------------------------------

const CRC_T = new Int32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  CRC_T[n] = c;
}
function crc(c, d, lo, hi) {
  for (let i = lo; i < hi; i++) c = CRC_T[(c ^ d[i]) & 255] ^ (c >>> 8);
  return c;
}

const tag = s => (s.charCodeAt(0) << 24 >>> 0) + (s.charCodeAt(1) << 16) + (s.charCodeAt(2) << 8) + s.charCodeAt(3);
const T = { IHDR: tag('IHDR'), ANIM: tag('ANIM'), FDAT: tag('FDAT'), FDLT: tag('FDLT'), IEND: tag('IEND'),
  MDAT: tag('MDAT'), PREV: tag('PREV'), RAWH: tag('RAWH'), LIVE: tag('LIVE'), GMAP: tag('GMAP') };

// Parses the chunks: {width, height, np, raw, animated, delay, nframes, chunks: [{type, pos, len}]}.
function parse(data) {
  if (data.length < 9 || u32(data, 0) !== 0x894E4F56 || u32(data, 4) !== 0x410D0A1A || data[8] !== 0x0A) throw new Error('not a NOVA file');
  const f = { width: 0, height: 0, np: 0, raw: false, animated: false, delay: 100, nframes: 0, chunks: [] };
  let pos = 9;
  while (pos < data.length) {
    if (pos + 12 > data.length) throw new Error('truncated file');
    const t = u32(data, pos), len = u32(data, pos + 4);
    if (len > data.length - pos - 12) throw new Error('truncated file');
    let c = crc(-1, data, pos, pos + 4);
    c = crc(c, data, pos + 8, pos + 8 + len);
    if (((c ^ -1) >>> 0) !== u32(data, pos + 8 + len)) throw new Error('CRC mismatch');
    const p = pos + 8;
    if (t === T.IHDR) {
      if (len < 12) throw new Error('bad IHDR');
      f.width = u32(data, p); f.height = u32(data, p + 4); f.np = data[p + 9];
      const flags = data[p + 11];
      f.animated = (flags & 4) !== 0; f.raw = (flags & 8) !== 0;
      if (data[p + 10] !== 2) throw new Error('unsupported NOVA version (only v2)');
      if (!f.raw && (data[p + 8] !== 8 || (f.np !== 3 && f.np !== 4))) throw new Error('unsupported frame format');
      if (!f.width || !f.height || f.width > 65535 || f.height > 65535) throw new Error('bad size');
    } else if (t === T.ANIM && len >= 4) {
      f.nframes = u32(data, p);
      if (len >= 6) f.delay = u16(data, p + 4);
    }
    f.chunks.push({ type: t, pos: p, len });
    pos = p + len + 4;
    if (t === T.IEND) break;
  }
  if (!f.width) throw new Error('no IHDR');
  return f;
}

// Decodes the PREV thumbnail: {width, height, rgba} or null.
async function decodePreview(data, opts) {
  const f = parse(data), c = f.chunks.find(c => c.type === T.PREV && c.len >= 5);
  if (!c) return null;
  const w = u16(data, c.pos), h = u16(data, c.pos + 2), np = data[c.pos + 4];
  if (!w || !h || (np !== 3 && np !== 4)) throw new Error('bad PREV');
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 3; i < rgba.length; i += 4) rgba[i] = 255;
  if (!(await decodeRegion(data, c.pos + 5, c.len - 5, rgba, w, 0, 0, w, h, np, opts && opts.run))) throw new Error('corrupt PREV');
  return { width: w, height: h, rgba };
}

// Decodes the HDR gain map (GMAP): {width, height, rgba, meta: ISO 21496-1 bytes} or null.
async function decodeGainMap(data, opts) {
  const f = parse(data), c = f.chunks.find(c => c.type === T.GMAP && c.len >= 7);
  if (!c || f.animated) return null;
  const w = u16(data, c.pos), h = u16(data, c.pos + 2), n = u16(data, c.pos + 5);
  if (!w || !h || data[c.pos + 4] !== 3 || 7 + n > c.len) throw new Error('bad GMAP');
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 3; i < rgba.length; i += 4) rgba[i] = 255;
  if (!(await decodeRegion(data, c.pos + 7 + n, c.len - 7 - n, rgba, w, 0, 0, w, h, 3, opts && opts.run))) throw new Error('corrupt GMAP');
  return { width: w, height: h, rgba, meta: data.slice(c.pos + 7, c.pos + 7 + n) };
}

// ISO 21496-1 metadata (version 0, one channel read) -> {min, max, gamma, offsetSdr, offsetHdr,
// headroomBase, headroomAlt} in stops, or null. As nova_hdr.li.
function gainMapParams(m) {
  if (m.length < 62 || m[0] !== 0 || (m[5] & 0x3F)) return null;
  const fr = (p, sg) => { const d = u32(m, p + 4); let n = u32(m, p); if (sg && n > 0x7FFFFFFF) n -= 0x100000000; return d ? n / d : 0; };
  return { headroomBase: fr(6), headroomAlt: fr(14), min: fr(22, 1), max: fr(30, 1), gamma: fr(38) || 1, offsetSdr: fr(46, 1), offsetHdr: fr(54, 1) };
}

// Ultra HDR JPEG from an SDR JPEG and a gain map JPEG (both JFIF, e.g. from canvas.toBlob) and
// the gain map's ISO metadata: hdrgm XMP in each, MPF index after the primary's APP0. As nova_hdr.li.
function ultraHdr(primary, gain, meta) {
  const g = gainMapParams(meta), te = new TextEncoder();
  if (!g) return null;
  const x = v => v.toFixed(6), rdf = '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">';
  const app1 = s => {
    const id = te.encode('http://ns.adobe.com/xap/1.0/\0'), b = te.encode(s), o = new Uint8Array(4 + id.length + b.length);
    o.set([0xFF, 0xE1, (o.length - 2) >> 8, (o.length - 2) & 255]); o.set(id, 4); o.set(b, 4 + id.length);
    return o;
  };
  const afterApp0 = j => j[2] === 0xFF && j[3] === 0xE0 ? 4 + (j[4] << 8 | j[5]) : 2;
  const splice = (j, ...segs) => { const a = afterApp0(j), n = segs.reduce((s, x) => s + x.length, 0), o = new Uint8Array(j.length + n);
    o.set(j.subarray(0, a)); let p = a; for (const s of segs) { o.set(s, p); p += s.length; } o.set(j.subarray(a), p); return o; };
  const gm = splice(gain, app1(rdf + '<rdf:Description xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" hdrgm:Version="1.0"' +
    ` hdrgm:GainMapMin="${x(g.min)}" hdrgm:GainMapMax="${x(g.max)}" hdrgm:Gamma="${x(g.gamma)}" hdrgm:OffsetSDR="${x(g.offsetSdr)}"` +
    ` hdrgm:OffsetHDR="${x(g.offsetHdr)}" hdrgm:HDRCapacityMin="${x(g.headroomBase)}" hdrgm:HDRCapacityMax="${x(g.headroomAlt)}"` +
    ' hdrgm:BaseRenditionIsHDR="False"/></rdf:RDF></x:xmpmeta>'));
  const xmp = app1(rdf + '<rdf:Description xmlns:Container="http://ns.google.com/photos/1.0/container/"' +
    ' xmlns:Item="http://ns.google.com/photos/1.0/container/item/" xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" hdrgm:Version="1.0">' +
    '<Container:Directory><rdf:Seq><rdf:li rdf:parseType="Resource"><Container:Item Item:Semantic="Primary" Item:Mime="image/jpeg"/></rdf:li>' +
    `<rdf:li rdf:parseType="Resource"><Container:Item Item:Semantic="GainMap" Item:Mime="image/jpeg" Item:Length="${gm.length}"/></rdf:li>` +
    '</rdf:Seq></Container:Directory></rdf:Description></rdf:RDF></x:xmpmeta>');
  const mpf = new Uint8Array(90), v = new DataView(mpf.buffer);
  mpf.set([0xFF, 0xE2, 0, 88, 0x4D, 0x50, 0x46, 0, 0x4D, 0x4D, 0, 42, 0, 0, 0, 8, 0, 3,
    0xB0, 0, 0, 7, 0, 0, 0, 4, 0x30, 0x31, 0x30, 0x30, 0xB0, 1, 0, 4, 0, 0, 0, 1, 0, 0, 0, 2, 0xB0, 2, 0, 7, 0, 0, 0, 32, 0, 0, 0, 50]);
  const out = splice(primary, mpf, xmp), total = out.length, tiff = afterApp0(primary) + 8;
  v.setUint32(58, 0x030000); v.setUint32(62, total); v.setUint32(78, gm.length); v.setUint32(82, total - tiff);
  out.set(mpf, afterApp0(primary));
  const r = new Uint8Array(total + gm.length);
  r.set(out); r.set(gm, total);
  return r;
}

// Decodes every frame: {width, height, np, delay, lossy, frames: [Uint8Array RGBA]}.
// opts.run: stripe runner (see decodeRegion); opts.onFrame(i, rgba): called as frames arrive.
async function decode(data, opts) {
  opts = opts || {};
  const f = parse(data);
  if (f.raw) throw new Error('RAW frame: not supported in JavaScript (use the preview)');
  const W = f.width, H = f.height, info = { lossy: false }, frames = [];
  let cur = null;
  for (const c of f.chunks) {
    if (c.type !== T.FDAT && c.type !== T.FDLT) continue;
    const next = new Uint8Array(W * H * 4);
    if (c.type === T.FDAT) {
      for (let i = 3; i < next.length; i += 4) next[i] = 255;
      if (!(await decodeRegion(data, c.pos, c.len, next, W, 0, 0, W, H, f.np, opts.run, info))) throw new Error('corrupt frame');
    } else {
      if (!cur) throw new Error('delta frame before full frame');
      if (c.len < 16) throw new Error('bad FDLT');
      next.set(cur);
      const x0 = u32(data, c.pos), y0 = u32(data, c.pos + 4), dw = u32(data, c.pos + 8), dh = u32(data, c.pos + 12);
      if (dw > 0 && dh > 0) {
        if (x0 + dw > W || y0 + dh > H) throw new Error('bad FDLT region');
        if (!(await decodeRegion(data, c.pos + 16, c.len - 16, next, W, x0, y0, dw, dh, f.np, opts.run, info))) throw new Error('corrupt frame');
      }
    }
    frames.push(next);
    if (opts.onFrame) opts.onFrame(frames.length - 1, next);
    cur = next;
  }
  if (!frames.length || (f.nframes > 0 && frames.length < f.nframes)) throw new Error('truncated file (missing frames)');
  return { width: W, height: H, np: f.np, delay: f.delay, lossy: info.lossy, frames };
}

const api = { parse, decode, decodePreview, decodeGainMap, gainMapParams, ultraHdr, decodeRegion, runJob, crc, T };
if (typeof module !== 'undefined') module.exports = api;
if (typeof self !== 'undefined') self.NovaDecode = api;
