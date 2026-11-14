// A page with playwright-core, as Claude could write it: an order form is filled in, or the title of the page is read.
//   node playwright_trial_page.js <folder with node_modules> <browser> <address> <picture> [proxy]
// With "proxy", the browser goes through the proxy in HTTPS_PROXY (nono's, with its user and password).
const [, , home, browser, url, picture, how] = process.argv;
const { chromium } = require(home + '/node_modules/playwright-core');
(async () => {
  const options = { executablePath: browser, headless: true, chromiumSandbox: false, args: ['--no-sandbox', '--disable-gpu'] };
  if (process.env.KINGO_BROWSER_MODE === 'single') options.args.push('--single-process');   // as look's second try on a Mac
  if (how === 'proxy') {
    const p = new URL(process.env.HTTPS_PROXY || process.env.https_proxy || '');
    options.proxy = { server: p.protocol + '//' + p.host, username: decodeURIComponent(p.username), password: decodeURIComponent(p.password),
                      bypass: '<-loopback>' };
    console.log('   step  the proxy: ' + p.protocol + '//' + p.host + (p.password ? ', with a password' : ', without a password'));
  }
  const b = await chromium.launch(options);
  const page = await b.newPage();
  const answer = await page.goto(url, { timeout: 30000 });
  console.log('   step  ' + url + ': HTTP ' + (answer ? answer.status() : 'none'));
  let said;
  if (await page.$('#name')) {
    await page.fill('#name', 'Mina');
    await page.selectOption('#product', 'Coffee');
    await page.click('#go');
    said = await page.textContent('#out');
  } else {
    said = await page.title();
  }
  await page.screenshot({ path: picture });
  await b.close();
  const good = said === 'Thank you, Mina: 1 Coffee' || said === 'Example Domain';
  console.log((good ? 'PAGE-RESULT ok: the page said "' : 'PAGE-RESULT failed: the page said "') + said + '"');
})().catch(e => { console.log('PAGE-RESULT failed: ' + String(e.message).split('\n')[0].slice(0, 400)); process.exit(1); });
