// One decoding job (a stripe) per message: see runJob in yaif_decode.js.
importScripts('yaif_decode.js' + self.location.search);
self.onmessage = e => {
  const j = e.data;
  if (j.kind === 'l14') {
    let last = 0;
    j.onRow = y => { if (y - last >= 64) { self.postMessage({ rows: y - last }); last = y; } };
  }
  const r = YaifDecode.runJob(j);
  if (r.img) self.postMessage({ done: true, ok: r.ok, img: r.img }, [r.img.buffer]);
  else if (r.plane) self.postMessage({ done: true, ok: r.ok, plane: r.plane }, [r.plane.buffer]);
  else self.postMessage({ done: true, ok: r.ok, planes: r.planes }, r.planes.map(p => p.buffer));
};
