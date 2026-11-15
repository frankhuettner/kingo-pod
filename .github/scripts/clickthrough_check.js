// CI: a script as Claude would write it to try a page, run with clickthrough (setup/claude/bin/clickthrough).
//   clickthrough clickthrough_check.js <page.html> <picture> [the address of a page on the internet]
// Fills in the form of clickthrough_shop.html, sends it, prints what the page says then (CLICKTHROUGH-SAID), makes a picture,
// and with an address also prints the title of that page (CLICKTHROUGH-TITLE).
const { chromium } = require('playwright-core');
const { pathToFileURL } = require('url');
const [form, picture, internet] = process.argv.slice(2);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(pathToFileURL(form).href);
  await page.fill('#name', 'Mina');
  await page.selectOption('#product', 'Coffee');
  await page.click('#go');
  console.log('CLICKTHROUGH-SAID ' + await page.textContent('#out'));
  await page.screenshot({ path: picture });
  if (internet) {
    await page.goto(internet, { timeout: 60000 });
    console.log('CLICKTHROUGH-TITLE ' + await page.title());
  }
  await browser.close();
})().catch(e => { console.log('CLICKTHROUGH-ERROR ' + String(e && e.message).split('\n')[0]); process.exit(1); });
