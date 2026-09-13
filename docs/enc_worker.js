// Runs one nova command (nova compiled to wasm: nova_enc.js, built by docs/build.sh) on one file:
// {name, data, argv, out, replica, n, peers} with IN / OUT in argv standing for the input and output
// files. With n > 1 the page runs n such workers on the same command (replicas, see nova_par.li):
// each codes its share of the stripes and, at each barrier k, sends its changes to the others
// through the peers ports (one per other replica) and waits for theirs. Replica 0 returns the output.
// A fresh instance per command: the codec keeps global state.
importScripts('nova_enc.js' + self.location.search);
self.onmessage = async e => {
  const { name, data, argv, out, replica = 0, n = 1, peers = [] } = e.data, log = [];
  const inbox = {}, want = {};
  let round = 0;
  const take = k => {
    if (!want[k] || (inbox[k] || []).length < peers.length) return;
    want[k](inbox[k]);
    delete inbox[k];
    delete want[k];
  };
  peers.forEach(p => p.onmessage = e => { (inbox[e.data.k] = inbox[e.data.k] || []).push(e.data.d); take(e.data.k); });
  try {
    let exit;
    const done = new Promise(r => exit = r);
    const M = await NovaWasm({
      locateFile: f => f + self.location.search,
      print: s => log.push(s),
      // "\1<percent> <label>" and "\2<step>" lines are progress (nova_par.li): each replica reports the
      // share of the work it did (the page adds them up), replica 0 the steps.
      printErr: s => {
        if (s[0] === '\x01') self.postMessage({ pc: parseInt(s.slice(1)), label: s.slice(s.indexOf(' ') + 1), replica });
        else if (s[0] === '\x02') { if (!replica) self.postMessage({ step: s.slice(1) }); }
        else log.push(s);
      }, onExit: exit, onAbort: s => { log.push(String(s)); exit(1); },
      sync: d => new Promise(r => {
        const k = round++;
        want[k] = r;
        peers.forEach((p, i) => p.postMessage({ k, d }, i === peers.length - 1 ? [d.buffer] : []));
        take(k);
      }),
      preRun: [m => { if (n > 1) m.ENV.NOVA_REPLICA = replica + '/' + n; }],
    });
    const src = '/' + name.replace(/[^\w.-]/g, '_'), dst = '/' + out;
    M.FS.writeFile(src, data);
    try { M.callMain(argv.map(a => a === 'IN' ? src : a === 'OUT' ? dst : a)); } catch (x) { if (x.status === undefined) { log.push(String(x)); exit(1); } }
    const code = await done;
    if (code) throw new Error(log.join('\n') || 'nova exited with ' + code);
    const res = replica ? null : M.FS.readFile(dst);
    self.postMessage({ ok: true, out: res, log }, res ? [res.buffer] : []);
  } catch (x) { self.postMessage({ ok: false, error: x.message }); }
};
