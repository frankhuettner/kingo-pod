// CI: clickthrough --dev with a stand-in dev server (clickthrough_devserver.py): its page loads, fetches from it and opens its
// WebSocket; then a page of the internet tries to reach the dev server: by http, which clickthrough must stop, and by a
// WebSocket, which it cannot see (reported). A page that does not come from the dev server also sends the tab there
// itself: a form (POST), location and window.open, which clickthrough must stop too; page.goto of the script still opens
// the dev page from there.
//   clickthrough --dev <port> clickthrough_dev.js <port> <the address of a page on the internet>
// Prints DEV-TITLE <title: DEV-WS pong when the WebSocket answered>, DEV-API <what /api said>, DEV-AGAIN <what /api
// said after page.goto from a data: page>, DEV-DONE.
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
  // stops such requests by itself, so the data: page is the one that shows what clickthrough does.
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
  const data = 'data:text/html,<title>data</title><p>a page that does not come from the dev server</p>';
  await page.goto(data);
  await attempt();
  // The page sends the tab to the dev server itself. Each from a fresh data: page, as each leaves it.
  const leave = async (how) => {
    await page.goto(data);
    await page.evaluate(({ port, how }) => {
      const to = `http://localhost:${port}/from-internet-http-${how}`;
      if (how === 'form') {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = to;
        form.innerHTML = '<input name="secret" value="from a page of the internet">';
        document.body.appendChild(form);
        form.submit();
      } else if (how === 'location') {
        location.href = to;
      } else {
        window.open(to);
      }
    }, { port, how });
    await page.waitForTimeout(1500);
  };
  for (const how of ['form', 'location', 'open']) await leave(how);
  // page.goto of the script goes to the dev server from a page that does not come from it
  await page.goto(data);
  await page.goto(`http://127.0.0.1:${port}/`, { timeout: 30000 });
  await page.waitForFunction(() => document.getElementById('api').textContent !== 'waiting', null, { timeout: 10000 }).catch(() => {});
  console.log('DEV-AGAIN ' + await page.textContent('#api'));
  await page.waitForTimeout(1000);
  await browser.close();
  console.log('DEV-DONE');
})().catch(e => { console.log('DEV-ERROR ' + String(e && e.message).split('\n')[0]); process.exit(1); });
