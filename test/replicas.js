// Runs one yaif command in N wasm replicas in this process (docs/yaif_enc.js, YAIF_REPLICA=r/N) and
// writes the output of replica 0: must equal the native output.
// Usage: node test/replicas.js N in out [yaif options...]
const fs = require('fs'), path = require('path');
const YaifWasm = require('../docs/yaif_enc.js');
const [n, src, dst, ...opts] = process.argv.slice(2), N = +n;
const cmd = /\.yaif$/i.test(dst) ? 'encode' : 'decode';

(async () => {
  const data = fs.readFileSync(src), t0 = Date.now();
  let waiting = [];
  // Barrier: when every replica has sent its changes, each gets the others'.
  const sync = r => d => new Promise(res => {
    waiting.push({ r, d, res });
    if (waiting.length < N) return;
    const all = waiting; waiting = [];
    for (const w of all) {
      const others = all.filter(x => x !== w), out = new Uint8Array(others.reduce((s, x) => s + x.d.length, 0));
      let o = 0;
      for (const x of others) { out.set(x.d, o); o += x.d.length; }
      w.res(out);
    }
  });
  const runs = [];
  for (let r = 0; r < N; r++) {
    runs.push(new Promise(async (done, fail) => {
      const M = await YaifWasm({ sync: sync(r), print: () => {}, printErr: s => /replicas|rror/.test(s) && console.error(`[${r}] ${s}`), onExit: c => c ? fail(new Error('exit ' + c)) : done(M), preRun: [m => { m.ENV.YAIF_REPLICA = `${r}/${N}`; }] });
      M.FS.writeFile('/in' + path.extname(src), data);
      try { M.callMain([cmd, '/in' + path.extname(src), '/out' + path.extname(dst), ...opts]); } catch (x) { if (x.status) fail(x); }
    }));
  }
  const ms = await Promise.all(runs);
  fs.writeFileSync(dst, ms[0].FS.readFile('/out' + path.extname(dst)));
  console.error(`${N} replicas: ${Date.now() - t0} ms`);
})().catch(e => { console.error(e); process.exit(1); });
