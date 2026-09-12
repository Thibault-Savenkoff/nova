// node test/js_dump.js x.nova out.raw [preview]: RGBA of every frame (or of the PREV), concatenated.
const fs = require('fs'), N = require('../docs/nova_decode.js');
(async () => {
  const d = new Uint8Array(fs.readFileSync(process.argv[2])), t0 = Date.now();
  let r;
  if (process.argv[4] === 'preview') { const p = await N.decodePreview(d); r = { width: p.width, height: p.height, frames: [p.rgba] }; }
  else r = await N.decode(d);
  fs.writeFileSync(process.argv[3], Buffer.concat(r.frames.map(f => Buffer.from(f))));
  console.log(r.width + 'x' + r.height + ' ' + r.frames.length + ' frame(s) ' + ((Date.now() - t0) / 1000).toFixed(1) + ' s');
})().catch(e => { console.log('ERROR ' + e.message); process.exit(1); });
