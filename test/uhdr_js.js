// node test/uhdr_js.js x.nova gain.raw [primary.jpg gain.jpg out.jpg]: the gain map decoded by
// docs/nova_decode.js (RGBA), and the Ultra HDR JPEG its builder makes from two plain JPEGs.
const fs = require('fs'), N = require('../docs/nova_decode.js');
(async () => {
  const a = process.argv, g = await N.decodeGainMap(new Uint8Array(fs.readFileSync(a[2])));
  if (!g) throw new Error('no gain map');
  fs.writeFileSync(a[3], g.rgba);
  if (a[4]) fs.writeFileSync(a[6], N.ultraHdr(new Uint8Array(fs.readFileSync(a[4])), new Uint8Array(fs.readFileSync(a[5])), g.meta));
  console.log(g.width + 'x' + g.height + ', ' + N.gainMapParams(g.meta).headroomAlt.toFixed(2) + ' stops');
})().catch(e => { console.log('ERROR ' + e.message); process.exit(1); });
