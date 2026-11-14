// The plain way: a script with playwright-core, no MCP server and no CLI. Claude could write such a script itself.
//   node playwright_trial_lib.js <folder with node_modules> <browser> <address of the page> <picture> [single]
const [, , home, browser, url, picture, single] = process.argv;
const { chromium } = require(home + '/node_modules/playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: browser, headless: true, chromiumSandbox: false,
    args: ['--no-sandbox', '--disable-gpu'].concat(single ? ['--single-process'] : []) });
  const page = await b.newPage();
  await page.goto(url);
  await page.fill('#name', 'Mina');
  await page.selectOption('#product', 'Coffee');
  await page.click('#go');
  const said = await page.textContent('#out');
  await page.screenshot({ path: picture });
  await b.close();
  console.log(said === 'Thank you, Mina: 1 Coffee' ? 'LIB-RESULT ok: the page answered "' + said + '"' : 'LIB-RESULT failed: the page answered "' + said + '"');
})().catch(e => { console.log('LIB-RESULT failed: ' + String(e.message).slice(0, 900).replace(/\n/g, ' | ')); process.exit(1); });
