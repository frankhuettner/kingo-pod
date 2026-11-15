// CI: the other ways past the locks of clickthrough that Playwright's API gives a script (setup/claude/clickthrough-setup.js).
//   clickthrough clickthrough_ways.js <port of a listener on 127.0.0.1> <page.html>
// Each of these must stop with clickthrough's words: another way to a browser (launchServer, connect, connectOverCDP,
// browser.bind, browser.newBrowserCDPSession), firefox and webkit, clientCertificates (Playwright puts a proxy of its
// own in front of the context for them), and arguments for Chrome that say where it connects (--host-rules sent the
// discard port of lock 1 to a service on 15 Nov 2026).
// And nothing may connect to the listener (the shell reads its log): from a context with a proxy of its own, made on
// the browser of a persistent context; and with ignoreDefaultArgs, which must not take lock 1's arguments away (with
// the ones the script can work out: a WebSocket and a fetch from the file page).
// Prints WAYS <way> refused <words> | WAYS <way> OPEN | WAYS <way> FAILED <words>, and WAYS-DONE.
const { chromium, firefox, webkit } = require('playwright-core');
const { pathToFileURL } = require('url');
const [port, file] = process.argv.slice(2);
const first = (e) => String(e && e.message).split('\n')[0].slice(0, 160);
async function way(name, fn) {
  try {
    await fn();
    console.log('WAYS ' + name + ' OPEN');
  } catch (e) {
    console.log('WAYS ' + name + (/^clickthrough[: ]/.test(first(e)) ? ' refused ' : ' FAILED ') + first(e));
  }
}
const certificate = [{ origin: 'https://example.com', cert: Buffer.from('not a certificate'), key: Buffer.from('not a key') }];
(async () => {
  await way('launchServer', async () => { const server = await chromium.launchServer(); await server.close(); });
  await way('connect', () => chromium.connect('ws://127.0.0.1:9/', { timeout: 3000 }));
  await way('connectOverCDP', () => chromium.connectOverCDP('http://127.0.0.1:9/', { timeout: 3000 }));
  await way('firefox', async () => { const b = await firefox.launch({ timeout: 5000 }); await b.close(); });
  await way('webkit', async () => { const b = await webkit.launch({ timeout: 5000 }); await b.close(); });
  for (const arg of ['--host-rules=MAP * 127.0.0.1:' + port, '--host-resolver-rules=MAP * 127.0.0.1:' + port,
    '--proxy-server=direct://', '-proxy-bypass-list=*', '--no-proxy-server', '--remote-debugging-port=0']) {
    await way('args ' + arg.split('=')[0], async () => { const b = await chromium.launch({ args: [arg] }); await b.close(); });
  }
  await way('persistent clientCertificates', async () => {
    const c = await chromium.launchPersistentContext('', { clientCertificates: certificate }); await c.close();
  });
  const browser = await chromium.launch();
  await way('newBrowserCDPSession', () => browser.newBrowserCDPSession());
  await way('bind', async () => { await browser.bind('clickthrough'); await browser.unbind(); });
  await way('clientCertificates', async () => { const c = await browser.newContext({ clientCertificates: certificate }); await c.close(); });
  await browser.close();
  // the browser of a persistent context, and a context of it with a proxy of its own: nothing may arrive
  const persistent = await chromium.launchPersistentContext('');
  try {
    const other = await persistent.browser().newContext({ proxy: { server: 'direct://' } });
    const page = await other.newPage();
    await page.goto(`http://127.0.0.1:${port}/from-a-context-with-a-proxy-of-its-own`, { timeout: 5000 }).catch(() => {});
  } catch (e) { console.log('WAYS persistent browser: ' + first(e)); }
  await persistent.close();

  // ignoreDefaultArgs with lock 1's arguments, as the script can work them out (clickthrough-setup.js)
  let https = 'direct://';
  try { const u = new URL(process.env.HTTPS_PROXY || process.env.https_proxy || ''); https = u.protocol + '//' + u.host; } catch (e) { /* none */ }
  const rules = 'https=' + https + ';http=http://127.0.0.1:9;socks=socks5://127.0.0.1:9';
  const dev = process.env.KINGO_CLICKTHROUGH_DEV;
  const bypass = ['<-loopback>'].concat(dev ? ['localhost', '127.0.0.1', '[::1]'].map((h) => h + ':' + dev) : []).join(';');
  const b = await chromium.launch({ ignoreDefaultArgs: ['--proxy-server=' + rules, '--proxy-bypass-list=' + bypass] });
  const page = await b.newPage();
  await page.goto(pathToFileURL(file).href);
  await page.evaluate(async (port) => {
    const late = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    await Promise.race([new Promise((resolve) => {
      try { const ws = new WebSocket(`ws://127.0.0.1:${port}/ignore-default-args`); ws.onopen = ws.onerror = resolve; } catch (e) { resolve(); }
    }), late(5000)]);
    await Promise.race([fetch(`http://127.0.0.1:${port}/ignore-default-args`, { mode: 'no-cors' }).catch(() => {}), late(5000)]);
  }, port);
  await b.close();
  console.log('WAYS ignoreDefaultArgs done');
  console.log('WAYS-DONE');
})().catch(e => { console.log('WAYS-ERROR ' + first(e)); process.exit(1); });
