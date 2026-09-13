// node test/js_workers.js x.nova out.raw: decodes through the viewer's Web Worker runner (docs/index.html),
// emulated on worker_threads. Run from nova-lisaac/; compare out.raw with nova decode (see test/js.sh).
const fs = require('fs'), path = require('path'), { Worker: W } = require('worker_threads');
const web = path.resolve('docs');
global.NovaDecode = require(web + '/nova_decode.js');
// Node 21+ has a read-only global navigator: redefine it.
Object.defineProperty(global, "navigator", { value: { hardwareConcurrency: +(process.env.JS_WORKERS || 8) } });
// Browser Worker on worker_threads: importScripts + self.onmessage/postMessage.
global.Worker = class {
  constructor(f) {
    f = f.replace(/\?.*/, '');   // cache buster (?v=)
    const code = `const {parentPort}=require('worker_threads');global.self=global;self.location={search:''};global.importScripts=f=>{Object.assign(global,{NovaDecode:require(${JSON.stringify(web)}+'/'+f)})};
self.postMessage=(m,t)=>parentPort.postMessage(m,t);parentPort.on('message',d=>self.onmessage({data:d}));` + fs.readFileSync(web + '/' + f, 'utf8');
    this.w = new W(code, { eval: true });
    this.w.on('message', d => this.onmessage({ data: d }));
    this.w.on('error', e => this.onerror(e));
  }
  postMessage(m, t) { this.w.postMessage(m, t); }
};
const html = fs.readFileSync(web + '/index.html', 'utf8');
const src = html.slice(html.indexOf('let pool = null;'), html.indexOf('function show('));
const V = '', location = { search: '' };
eval(src + '; global.runner = runner; global.pool = () => pool;');
(async () => {
  const d = new Uint8Array(fs.readFileSync(process.argv[2])), t0 = Date.now();
  let last = 0;
  const r = await NovaDecode.decode(d, { run: runner(x => { if (x - last > 0.2 || x === 1) { process.stdout.write((x * 100).toFixed(0) + '% '); last = x; } }) });
  fs.writeFileSync(process.argv[3], Buffer.concat(r.frames.map(f => Buffer.from(f))));
  console.log('\n' + ((Date.now() - t0) / 1000).toFixed(1) + ' s');
  console.log("workers:", pool().length);
  pool().forEach(w => w.w.terminate());
})();
