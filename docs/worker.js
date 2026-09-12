// One decoding job (a stripe) per message: see runJob in nova_decode.js.
importScripts('nova_decode.js');
self.onmessage = e => {
  const j = e.data;
  if (j.kind === 'l14') {
    let last = 0;
    j.onRow = y => { if (y - last >= 64) { self.postMessage({ rows: y - last }); last = y; } };
  }
  const r = NovaDecode.runJob(j);
  if (r.img) self.postMessage({ done: true, ok: r.ok, img: r.img }, [r.img.buffer]);
  else self.postMessage({ done: true, ok: r.ok, planes: r.planes }, r.planes.map(p => p.buffer));
};
