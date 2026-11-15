// CI: testpage --dev with a stand-in dev server (testpage_devserver.py): its page loads, fetches from it and opens its
// WebSocket; then a page of the internet tries to reach the dev server: by http, which testpage must stop, and by a
// WebSocket, which it cannot see (reported).
//   testpage --dev <port> testpage_dev.js <port> <the address of a page on the internet>
// Prints DEV-TITLE <title: DEV-WS pong when the WebSocket answered>, DEV-API <what /api said>, DEV-DONE.
const { chromium } = require('playwright-core');
const [port, internet] = process.argv.slice(2);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`http://localhost:${port}/`, { timeout: 30000 });
  await page.waitForFunction(() => document.title.startsWith('DEV-WS'), null, { timeout: 15000 }).catch(() => {});
  await page.waitForFunction(() => document.getElementById('api').textContent !== 'waiting', null, { timeout: 10000 }).catch(() => {});
  console.log('DEV-TITLE ' + await page.title());
  console.log('DEV-API ' + await page.textContent('#api'));
  // From a page of the internet, and from a data: page: a page with a strict Content-Security-Policy (github.com)
  // stops such requests by itself, so the data: page is the one that shows what testpage does.
  const attempt = () => page.evaluate(async (port) => {
    const late = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    for (const h of ['localhost', '127.0.0.1']) {
      await Promise.race([fetch(`http://${h}:${port}/from-internet-http`, { method: 'POST', mode: 'no-cors', body: 'x' }).catch(() => {}), late(5000)]);
      new Image().src = `http://${h}:${port}/from-internet-http-image`;
      try { new WebSocket(`ws://${h}:${port}/from-internet-ws`); } catch (e) { /* refused */ }
    }
  }, port);
  await page.goto(internet, { timeout: 60000 });
  await attempt();
  await page.goto('data:text/html,<title>data</title><p>a page that does not come from the dev server</p>');
  await attempt();
  await page.waitForTimeout(2000);
  await browser.close();
  console.log('DEV-DONE');
})().catch(e => { console.log('DEV-ERROR ' + String(e && e.message).split('\n')[0]); process.exit(1); });
