// Metadata options applied to an encoded .nova: MDAT chunks ([kind u32][raw block]) are dropped or
// have their location removed; the pixels are untouched. Needs NovaDecode (crc).
(function (root) {
  'use strict';
  const ND = root.NovaDecode || (typeof require !== 'undefined' && require('./nova_decode.js'));
  const u32 = (d, p) => (d[p] << 24 | d[p + 1] << 16 | d[p + 2] << 8 | d[p + 3]) >>> 0;
  const tag = s => u32(Uint8Array.from(s, c => c.charCodeAt(0)), 0);
  const MDAT = tag('MDAT'), APP1 = tag('APP1'), APP2 = tag('APP2'), EXIF = tag('eXIf'), ITXT = tag('iTXt'), CMT4 = tag('CMT4');
  // Colour blocks stay even without metadata: they change how the pixels look, not who took them.
  const COLOUR = [tag('iCCP'), tag('sRGB'), tag('gAMA'), tag('cHRM'), tag('cICP')];
  const starts = (d, s) => s.split('').every((c, i) => d[i] === c.charCodeAt(0));

  // GPS IFD of a TIFF (EXIF) block: its entries and values zeroed, its pointer removed from IFD0.
  const SIZE = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8];
  function dropGps(t) {
    if (t.length < 8) return;
    const le = t[0] === 0x49;
    const g16 = p => le ? t[p] | t[p + 1] << 8 : t[p] << 8 | t[p + 1];
    const g32 = p => le ? (t[p] | t[p + 1] << 8 | t[p + 2] << 16 | t[p + 3] << 24) >>> 0 : u32(t, p);
    const ok = (p, n) => p + n <= t.length;
    const ifd0 = g32(4);
    if (!ok(ifd0, 2)) return;
    const n = g16(ifd0);
    if (!ok(ifd0 + 2, n * 12 + 4)) return;
    for (let i = 0; i < n; i++) {
      const e = ifd0 + 2 + i * 12;
      if (g16(e) !== 0x8825) continue;
      const gps = g32(e + 8);
      if (ok(gps, 2)) {
        const m = g16(gps);
        for (let k = 0; k < m && ok(gps + 2 + k * 12, 12); k++) {
          const f = gps + 2 + k * 12, len = (SIZE[g16(f + 2)] || 0) * g32(f + 4);
          if (len > 4 && ok(g32(f + 8), len)) t.fill(0, g32(f + 8), g32(f + 8) + len);
          t.fill(0, f, f + 12);
        }
      }
      // Entry removed: the following entries and the next-IFD offset move up, the freed slot is zeroed.
      t.copyWithin(e, e + 12, ifd0 + 2 + n * 12 + 4);
      t.fill(0, ifd0 + 2 + n * 12 - 8, ifd0 + 2 + n * 12 + 4);
      const c = n - 1;
      t[ifd0] = le ? c & 255 : c >> 8;
      t[ifd0 + 1] = le ? c >> 8 : c & 255;
      return;
    }
  }

  // XMP without its exif:GPS… properties (attributes or elements), or null if it has none.
  // ponytail: uncompressed XMP only (what nova and cameras write).
  function xmpNoGps(b) {
    const s = new TextDecoder().decode(b);
    const r = s.replace(/\s+exif:GPS\w+="[^"]*"/g, '').replace(/<exif:(GPS\w+)[\s>][\s\S]*?<\/exif:\1>\s*/g, '').replace(/<exif:GPS\w+\/>\s*/g, '');
    return r === s ? null : new TextEncoder().encode(r);
  }

  // opts: {keep: false → only colour blocks stay, gps: true → location removed}.
  function apply(nova, opts) {
    if (opts.keep && !opts.gps) return nova;
    const parts = [nova.subarray(0, 9)];
    const f = ND.parse(nova);
    for (const c of f.chunks) {
      let body = nova.subarray(c.pos, c.pos + c.len);
      if (c.type === MDAT && c.len >= 4) {
        const kind = u32(body, 0), raw = body.subarray(4);
        const colour = COLOUR.includes(kind) || (kind === APP2 && starts(raw, 'ICC_PROFILE'));
        if (!opts.keep && !colour) continue;
        if (opts.gps && kind === CMT4) continue;   // CR3: CMT4 is the GPS IFD
        if (opts.gps) {
          body = body.slice();
          if (kind === EXIF) dropGps(body.subarray(4));
          else if (kind === APP1 && starts(raw, 'Exif\0\0')) dropGps(body.subarray(10));
          const xmp = kind === APP1 && starts(raw, 'http://ns.adobe.com/xap/1.0/\0') ? 29
            : kind === ITXT && starts(raw, 'XML:com.adobe.xmp\0') && raw[18] === 0 ? 22 : -1;
          const nb = xmp >= 0 && xmpNoGps(raw.subarray(xmp));
          if (nb) {
            const b = new Uint8Array(4 + xmp + nb.length);
            b.set(body.subarray(0, 4 + xmp));
            b.set(nb, 4 + xmp);
            body = b;
          }
        }
      }
      const h = new Uint8Array(12 + body.length), v = new DataView(h.buffer);
      v.setUint32(0, c.type);
      v.setUint32(4, body.length);
      h.set(body, 8);
      v.setUint32(8 + body.length, (ND.crc(ND.crc(0xFFFFFFFF, h, 0, 4), h, 8, 8 + body.length) ^ 0xFFFFFFFF) >>> 0);
      parts.push(h);
    }
    const out = new Uint8Array(parts.reduce((s, p) => s + p.length, 0));
    let o = 0;
    for (const p of parts) { out.set(p, o); o += p.length; }
    return out;
  }

  const api = { apply };
  if (typeof module !== 'undefined') module.exports = api;
  else root.MetaStrip = api;
})(this);
