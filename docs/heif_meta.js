// HEIF/HEIC/AVIF metadata of the primary image (EXIF, XMP, ICC), read from the container only:
// no HEVC decoding here. Same blocks as nova's libheif path (nova_heic.li nh_metadata).
(function (root) {
  'use strict';
  const u16 = (d, p) => d[p] << 8 | d[p + 1];
  const u32 = (d, p) => (d[p] << 24 | d[p + 1] << 16 | d[p + 2] << 8 | d[p + 3]) >>> 0;
  const un = (d, p, n) => { let v = 0; for (let i = 0; i < n; i++) v = v * 256 + d[p + i]; return v; };
  const str = (d, p) => String.fromCharCode(d[p], d[p + 1], d[p + 2], d[p + 3]);

  // Child boxes of d[lo, hi): {type, lo (payload start), hi}.
  function boxes(d, lo, hi) {
    const r = [];
    while (lo + 8 <= hi) {
      let n = u32(d, lo), h = 8;
      if (n === 1) { n = un(d, lo + 8, 8); h = 16; }
      else if (n === 0) n = hi - lo;
      if (n < h || lo + n > hi) break;
      r.push({ type: str(d, lo + 4), lo: lo + h, hi: lo + n });
      lo += n;
    }
    return r;
  }
  const find = (bs, t) => bs.find(b => b.type === t);

  function isHeif(d) {
    return d.length >= 12 && str(d, 4) === 'ftyp' && /^(heic|heix|heim|heis|hevc|hevx|mif1|msf1|avif|avis)$/.test(str(d, 8));
  }

  // Orientation tag (0x0112) of IFD0 set to 1: the browser draws the pixels already turned.
  function orient1(t) {
    if (t.length < 8) return;
    const le = t[0] === 0x49;
    const g16 = p => le ? t[p] | t[p + 1] << 8 : t[p] << 8 | t[p + 1];
    const off = le ? (t[4] | t[5] << 8 | t[6] << 16 | t[7] << 24) >>> 0 : u32(t, 4);
    if (off + 2 > t.length) return;
    for (let i = 0, cnt = g16(off); i < cnt && off + 14 + i * 12 <= t.length; i++) {
      const e = off + 2 + i * 12;
      if (g16(e) === 0x0112 && g16(e + 2) === 3) { t[e + 8] = le ? 1 : 0; t[e + 9] = le ? 0 : 1; }
    }
  }

  function read(d) {
    const out = { exif: null, xmp: null, icc: null };
    const meta = find(boxes(d, 0, d.length), 'meta');
    if (!meta) return out;
    const mb = boxes(d, meta.lo + 4, meta.hi);   // meta is a FullBox
    const pitm = find(mb, 'pitm'), iinf = find(mb, 'iinf'), iloc = find(mb, 'iloc'), idat = find(mb, 'idat');
    const iref = find(mb, 'iref'), iprp = find(mb, 'iprp');
    const primary = pitm ? (d[pitm.lo] ? u32(d, pitm.lo + 4) : u16(d, pitm.lo + 4)) : 0;

    // Items: id -> {type, ctype}
    const items = new Map();
    if (iinf) {
      const v = d[iinf.lo], p = iinf.lo + 4 + (v ? 4 : 2);
      for (const b of boxes(d, p, iinf.hi)) {
        if (b.type !== 'infe' || d[b.lo] < 2) continue;
        const v3 = d[b.lo] === 3, q = b.lo + 4, id = v3 ? u32(d, q) : u16(d, q), t = q + (v3 ? 4 : 2) + 2;
        let ctype = '';
        if (str(d, t) === 'mime') {
          let e = t + 4;
          while (e < b.hi && d[e]) e++;   // item_name
          const s = ++e;
          while (e < b.hi && d[e]) e++;
          ctype = String.fromCharCode(...d.subarray(s, e));
        }
        items.set(id, { type: str(d, t), ctype });
      }
    }

    // Metadata items describing the primary image (cdsc references), else all of them.
    let described = null;
    if (iref) {
      const v = d[iref.lo];
      for (const b of boxes(d, iref.lo + 4, iref.hi)) {
        if (b.type !== 'cdsc') continue;
        described = described || new Set();
        const w = v ? 4 : 2, rd = p => v ? u32(d, p) : u16(d, p);
        const from = rd(b.lo), n = u16(d, b.lo + w);
        for (let i = 0; i < n; i++) if (rd(b.lo + w + 2 + i * w) === primary) described.add(from);
      }
    }

    // Item bytes from iloc extents (construction 0: file, 1: idat).
    function bytes(id) {
      if (!iloc) return null;
      const v = d[iloc.lo];
      let p = iloc.lo + 4;
      const os = d[p] >> 4, ls = d[p] & 15, bs = d[p + 1] >> 4, is = v ? d[p + 1] & 15 : 0;
      p += 2;
      const cnt = v < 2 ? u16(d, p) : u32(d, p);
      p += v < 2 ? 2 : 4;
      for (let i = 0; i < cnt; i++) {
        const iid = v < 2 ? u16(d, p) : u32(d, p);
        p += v < 2 ? 2 : 4;
        const cm = v ? u16(d, p) & 15 : 0;
        if (v) p += 2;
        p += 2;   // data_reference_index
        const base = un(d, p, bs);
        p += bs;
        const ne = u16(d, p);
        p += 2;
        const parts = [];
        for (let k = 0; k < ne; k++) {
          p += is;
          const off = un(d, p, os), len = un(d, p + os, ls);
          p += os + ls;
          parts.push([base + off, len]);
        }
        if (iid !== id) continue;
        const src = cm === 1 && idat ? d.subarray(idat.lo, idat.hi) : cm === 0 ? d : null;
        if (!src) return null;
        const r = new Uint8Array(parts.reduce((s, x) => s + x[1], 0));
        let o = 0;
        for (const [a, n] of parts) { if (a + n > src.length) return null; r.set(src.subarray(a, a + n), o); o += n; }
        return r;
      }
      return null;
    }

    for (const [id, it] of items) {
      if (described && !described.has(id)) continue;
      if (it.type === 'Exif' && !out.exif) {
        const b = bytes(id);
        if (b && b.length > 4) {
          const off = 4 + u32(b, 0);
          if (off < b.length) { out.exif = b.slice(off); orient1(out.exif); }
        }
      } else if (it.type === 'mime' && it.ctype === 'application/rdf+xml' && !out.xmp) out.xmp = bytes(id);
    }

    // ICC: colr 'prof'/'rICC' property associated with the primary image.
    const ipco = iprp && find(boxes(d, iprp.lo, iprp.hi), 'ipco'), ipma = iprp && find(boxes(d, iprp.lo, iprp.hi), 'ipma');
    if (ipco && ipma) {
      const props = boxes(d, ipco.lo, ipco.hi), v = d[ipma.lo], big = d[ipma.lo + 3] & 1;
      let p = ipma.lo + 4;
      const cnt = u32(d, p);
      p += 4;
      for (let i = 0; i < cnt; i++) {
        const id = v ? u32(d, p) : u16(d, p);
        p += v ? 4 : 2;
        const n = d[p++];
        for (let k = 0; k < n; k++) {
          const x = (big ? u16(d, p) & 0x7FFF : d[p] & 0x7F) - 1;
          p += big ? 2 : 1;
          const c = props[x];
          if (id === primary && c && c.type === 'colr' && /^(prof|rICC)$/.test(str(d, c.lo))) out.icc = d.slice(c.lo + 4, c.hi);
        }
      }
    }
    return out;
  }

  const api = { isHeif, read };
  if (typeof module !== 'undefined') module.exports = api;
  else root.HeifMeta = api;
})(this);
