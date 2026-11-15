// CI: the script's own routes. Playwright asks the routes of a page before those of its context, and later routes
// before earlier ones, so a route of the script comes before lock 2 of clickthrough (setup/claude/clickthrough-setup.js); lock
// 2 must hold all the same. With clickthrough --dev, the stand-in dev server (clickthrough_devserver.py) and a listener that
// stands for n8n (clickthrough_listener.py):
//   clickthrough --dev <port> clickthrough_routes.js <port> <port of the listener>
//   - a route of the page and a later one of the context let every request go on (route.continue); from a data: page,
//     a fetch to the dev server, and a form that sends the tab there: nothing may arrive at the dev server
//   - the same after context.unrouteAll() and page.unrouteAll(): lock 2 stays
//   - a route that sends the request itself and gives the page its answer (route.fetch, route.fulfill: a script does
//     so to change an answer). The dev page asks for an address of the dev server that redirects to the listener:
//     Node.js must not follow that redirect, past both locks
// Prints ROUTES-DEV <what /api of the dev page said through that route>, ROUTES-DONE. The shell reads both logs.
const { chromium } = require('playwright-core');
const [port, listener] = process.argv.slice(2);
const data = 'data:text/html,<title>data</title><p>a page that does not come from the dev server</p>';
(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();
  const fromData = async (tag) => {
    await page.goto(data);
    await page.evaluate(async ({ port, tag }) => {
      const late = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      await Promise.race([fetch(`http://localhost:${port}/from-internet-http-${tag}-fetch`, { mode: 'no-cors' }).catch(() => {}), late(3000)]);
      const form = document.createElement('form');
      form.method = 'POST';
      form.action = `http://localhost:${port}/from-internet-http-${tag}-form`;
      document.body.appendChild(form);
      form.submit();
    }, { port, tag });
    await page.waitForTimeout(1500);
  };
  await page.route('**/*', (route) => route.continue());
  await context.route('**/*', (route) => route.continue());
  await fromData('routes');
  await context.unrouteAll();
  await page.unrouteAll();
  await fromData('unrouteall');

  await page.route('**/*', async (route) => route.fulfill({ response: await route.fetch() }));
  await page.goto(`http://localhost:${port}/`, { timeout: 30000 });
  await page.waitForFunction(() => document.getElementById('api').textContent !== 'waiting', null, { timeout: 10000 }).catch(() => {});
  console.log('ROUTES-DEV ' + await page.textContent('#api'));
  await page.evaluate(async (to) => {
    await Promise.race([fetch('/redirect?to=' + encodeURIComponent(to)).catch(() => {}), new Promise((resolve) => setTimeout(resolve, 5000))]);
  }, `http://127.0.0.1:${listener}/from-route-fetch`);
  await page.waitForTimeout(1500);
  await browser.close();
  console.log('ROUTES-DONE');
})().catch(e => { console.log('ROUTES-ERROR ' + String(e && e.message).split('\n')[0]); process.exit(1); });
