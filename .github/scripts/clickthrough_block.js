// CI: a page tries to reach a service on this laptop, as a page of the internet could (setup/claude/clickthrough-setup.js).
//   clickthrough clickthrough_block.js <port of a listener on 127.0.0.1> <page.html> <the address of a page on the internet> [own]
// From the page of the internet, from the file and from a data: page: a POST (fetch), an image and a WebSocket, each to
// 127.0.0.1, localhost and 127.0.0.1.nip.io (a name that points to 127.0.0.1); then page.goto on such an http address.
// With "own", the script names the browser itself, as a script must with a copy of Playwright of its own (the shell
// puts this file next to one, clickthrough_copy).
// Nothing may arrive at the listener: the shell reads its log. Prints BLOCK-PLAYWRIGHT <the playwright-core that
// require found>, BLOCK-GOTO <what clickthrough said>, BLOCK-DONE.
const { chromium } = require('playwright-core');
const { pathToFileURL } = require('url');
const [port, file, internet, own] = process.argv.slice(2);
const hosts = ['127.0.0.1', 'localhost', '127.0.0.1.nip.io'];

async function tryAll(page) {
  return page.evaluate(async ({ hosts, port }) => {
    const late = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    for (const h of hosts) {
      await Promise.race([fetch(`http://${h}:${port}/post`, { method: 'POST', mode: 'no-cors', body: 'hello' }).catch(() => {}), late(5000)]);
      new Image().src = `http://${h}:${port}/image`;
      await Promise.race([new Promise((resolve) => {
        try { const ws = new WebSocket(`ws://${h}:${port}/socket`); ws.onopen = ws.onerror = resolve; } catch (e) { resolve(); }
      }), late(5000)]);
    }
  }, { hosts, port });
}

(async () => {
  console.log('BLOCK-PLAYWRIGHT ' + require.resolve('playwright-core'));
  const browser = await chromium.launch(own ? { executablePath: process.env.KINGO_BROWSER, chromiumSandbox: false,
    args: process.env.KINGO_BROWSER_MODE === 'single' ? ['--single-process'] : [] } : undefined);
  const page = await browser.newPage();
  await page.goto(internet, { timeout: 60000 });
  await tryAll(page);
  await page.goto(pathToFileURL(file).href);
  await tryAll(page);
  await page.goto('data:text/html,<title>data</title><p>a page without an origin</p>');
  await tryAll(page);
  try { await page.goto(`http://127.0.0.1.nip.io:${port}/page`); console.log('BLOCK-GOTO opened'); }
  catch (e) { console.log('BLOCK-GOTO ' + String(e.message).split('\n')[0]); }
  await page.waitForTimeout(2000);
  await browser.close();
  console.log('BLOCK-DONE');
})().catch(e => { console.log('BLOCK-ERROR ' + String(e && e.message).split('\n')[0]); process.exit(1); });
